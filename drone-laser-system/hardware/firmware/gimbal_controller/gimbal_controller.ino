/*
 * Selkorin Sky Sentinel — прошивка контроллера осей и лазера.
 *
 * Задачи (реальное время, детерминированно):
 *   - приём команд от вычислителя по UART (см. docs/electronics.md);
 *   - управление двумя шаговыми приводами (азимут/возвышение) к целевым углам;
 *   - управление лазером ТОЛЬКО при выполнении всех аппаратных блокировок;
 *   - независимая от ПО безопасность: E-STOP, ключ, watchdog, перегрев, концевики;
 *   - индикатор излучения и реле блокировки питания лазера.
 *
 * ВАЖНО: контроллер вправе отклонить/погасить любую команду огня.
 * E-STOP дополнительно разрывает питание лазера аппаратно (не через этот код).
 */

#include <Arduino.h>

// ---- Назначение выводов (см. docs/electronics.md) ----
const uint8_t PIN_PAN_STEP   = 2;
const uint8_t PIN_PAN_DIR    = 3;
const uint8_t PIN_TILT_STEP  = 4;
const uint8_t PIN_TILT_DIR   = 5;
const uint8_t PIN_DRV_ENABLE = 6;   // активный низкий
const uint8_t PIN_EMIT_LED   = 7;   // индикатор излучения
const uint8_t PIN_LASER_RELAY= 8;   // реле блокировки питания лазера
const uint8_t PIN_LASER_PWM  = 9;   // управление мощностью
const uint8_t PIN_ESTOP      = 10;  // вход, NC, pullup: LOW = нажат
const uint8_t PIN_ARM_KEY    = 11;  // вход, pullup: LOW = ключ вставлен/включён
const uint8_t PIN_LIMIT_PAN  = 12;
const uint8_t PIN_LIMIT_TILT = 13;
const uint8_t PIN_LASER_TEMP = A0;

// ---- Параметры механики ----
const float STEPS_PER_DEG   = (200.0 * 16.0 * 5.0) / 360.0; // 200 шагов, 1/16, редукция 5:1
const float PAN_MIN_DEG     = -170.0, PAN_MAX_DEG = 170.0;
const float TILT_MIN_DEG    = 0.0,    TILT_MAX_DEG = 85.0;
const unsigned STEP_PULSE_US = 3;
const unsigned MIN_STEP_INTERVAL_US = 200; // ограничение скорости

// ---- Параметры безопасности ----
const unsigned long WATCHDOG_TIMEOUT_MS = 500; // нет PING дольше => гасим лазер
const int   LASER_TEMP_ADC_MAX = 720;          // порог перегрева (ADC), настроить
const unsigned long MAX_FIRE_MS = 30000;       // предел непрерывного излучения

// ---- Состояние ----
enum State { SAFE, ARMED, FIRING };
State state = SAFE;

float pan_target = 0, tilt_target = 0;
long  pan_steps = 0, tilt_steps = 0;   // текущее положение в шагах
long  pan_goal_steps = 0, tilt_goal_steps = 0;

unsigned long last_ping_ms = 0;
unsigned long fire_start_ms = 0;
uint8_t fire_power = 0;                 // 0..255
unsigned long fire_duration_ms = 0;
bool laser_on = false;

char buf[48];
uint8_t buf_len = 0;

// ---- Прототипы (для сборки вне Arduino IDE, где нет автогенерации) ----
bool laser_inhibited_precheck();
void home_axes();
void enter_safe();
void laser_off();

// ---------------------------------------------------------------------------
bool estop_pressed()  { return digitalRead(PIN_ESTOP) == LOW; }
bool key_present()     { return digitalRead(PIN_ARM_KEY) == LOW; }
bool laser_overheat() { return analogRead(PIN_LASER_TEMP) > LASER_TEMP_ADC_MAX; }
bool watchdog_stale() { return (millis() - last_ping_ms) > WATCHDOG_TIMEOUT_MS; }

// Единая точка запрета излучения. Любое TRUE => лазер запрещён.
bool laser_inhibited() {
    return estop_pressed() || !key_present() || laser_overheat() ||
           watchdog_stale() || state != FIRING;
}

void laser_off() {
    analogWrite(PIN_LASER_PWM, 0);
    digitalWrite(PIN_LASER_RELAY, LOW);   // разрыв питания лазера
    digitalWrite(PIN_EMIT_LED, LOW);
    laser_on = false;
}

void enter_safe() {
    laser_off();
    state = SAFE;
    digitalWrite(PIN_DRV_ENABLE, HIGH);   // отключить драйверы (активный низкий)
}

// ---------------------------------------------------------------------------
float clampf(float v, float lo, float hi) { return v < lo ? lo : (v > hi ? hi : v); }

void set_target(float pan, float tilt) {
    pan_target  = clampf(pan,  PAN_MIN_DEG,  PAN_MAX_DEG);
    tilt_target = clampf(tilt, TILT_MIN_DEG, TILT_MAX_DEG);
    pan_goal_steps  = (long)(pan_target  * STEPS_PER_DEG);
    tilt_goal_steps = (long)(tilt_target * STEPS_PER_DEG);
}

void step_axis(uint8_t step_pin, uint8_t dir_pin, long &pos, long goal) {
    if (pos == goal) return;
    bool dir = goal > pos;
    digitalWrite(dir_pin, dir ? HIGH : LOW);
    digitalWrite(step_pin, HIGH);
    delayMicroseconds(STEP_PULSE_US);
    digitalWrite(step_pin, LOW);
    pos += dir ? 1 : -1;
}

// ---------------------------------------------------------------------------
void handle_command(char *line) {
    if (strncmp(line, "PING", 4) == 0) {
        last_ping_ms = millis();
    } else if (strncmp(line, "ARM", 3) == 0) {
        if (key_present() && !estop_pressed()) {
            state = ARMED;
            digitalWrite(PIN_DRV_ENABLE, LOW); // включить драйверы
        }
    } else if (strncmp(line, "DISARM", 6) == 0) {
        enter_safe();
    } else if (strncmp(line, "AIM", 3) == 0) {
        float p, t;
        if (sscanf(line + 3, "%f %f", &p, &t) == 2) set_target(p, t);
    } else if (strncmp(line, "FIRE", 4) == 0) {
        int power, ms; char mode[8];
        if (sscanf(line + 4, "%7s %d %d", mode, &power, &ms) == 3) {
            if (state == ARMED && !laser_inhibited_precheck()) {
                fire_power = constrain(power, 0, 100) * 255 / 100;
                fire_duration_ms = (unsigned long)ms;
                fire_start_ms = millis();
                state = FIRING;
            }
        }
    } else if (strncmp(line, "HOLD", 4) == 0) {
        if (state == FIRING) { laser_off(); state = ARMED; }
    } else if (strncmp(line, "HOME", 4) == 0) {
        home_axes();
    }
}

// предпроверка блокировок без учёта state (state ещё ARMED в момент FIRE)
bool laser_inhibited_precheck() {
    return estop_pressed() || !key_present() || laser_overheat() || watchdog_stale();
}

void home_axes() {
    digitalWrite(PIN_DRV_ENABLE, LOW);
    // движение к концевикам (упрощённо)
    while (digitalRead(PIN_LIMIT_PAN) == HIGH) {
        digitalWrite(PIN_PAN_DIR, LOW);
        digitalWrite(PIN_PAN_STEP, HIGH); delayMicroseconds(STEP_PULSE_US);
        digitalWrite(PIN_PAN_STEP, LOW);  delayMicroseconds(MIN_STEP_INTERVAL_US);
        if (estop_pressed()) { enter_safe(); return; }
    }
    while (digitalRead(PIN_LIMIT_TILT) == HIGH) {
        digitalWrite(PIN_TILT_DIR, LOW);
        digitalWrite(PIN_TILT_STEP, HIGH); delayMicroseconds(STEP_PULSE_US);
        digitalWrite(PIN_TILT_STEP, LOW);  delayMicroseconds(MIN_STEP_INTERVAL_US);
        if (estop_pressed()) { enter_safe(); return; }
    }
    pan_steps = tilt_steps = 0;
    pan_goal_steps = tilt_goal_steps = 0;
    enter_safe();
}

// ---------------------------------------------------------------------------
void send_telemetry() {
    static unsigned long last = 0;
    if (millis() - last < 100) return;   // 10 Гц
    last = millis();
    Serial.print("STATE ");
    Serial.print(state == SAFE ? "SAFE" : state == ARMED ? "ARMED" : "FIRING");
    Serial.print(" PAN ");   Serial.print(pan_steps / STEPS_PER_DEG, 2);
    Serial.print(" TILT ");  Serial.print(tilt_steps / STEPS_PER_DEG, 2);
    Serial.print(" LASER "); Serial.print(laser_on ? "on" : "off");
    Serial.print(" ESTOP "); Serial.print(estop_pressed() ? 1 : 0);
    Serial.print(" KEY ");   Serial.print(key_present() ? 1 : 0);
    Serial.print(" TEMP ");  Serial.println(analogRead(PIN_LASER_TEMP));
}

// ---------------------------------------------------------------------------
void setup() {
    Serial.begin(115200);
    pinMode(PIN_PAN_STEP, OUTPUT);  pinMode(PIN_PAN_DIR, OUTPUT);
    pinMode(PIN_TILT_STEP, OUTPUT); pinMode(PIN_TILT_DIR, OUTPUT);
    pinMode(PIN_DRV_ENABLE, OUTPUT);
    pinMode(PIN_EMIT_LED, OUTPUT);
    pinMode(PIN_LASER_RELAY, OUTPUT);
    pinMode(PIN_LASER_PWM, OUTPUT);
    pinMode(PIN_ESTOP, INPUT_PULLUP);
    pinMode(PIN_ARM_KEY, INPUT_PULLUP);
    pinMode(PIN_LIMIT_PAN, INPUT_PULLUP);
    pinMode(PIN_LIMIT_TILT, INPUT_PULLUP);
    enter_safe();
    last_ping_ms = millis();
}

void loop() {
    // 1) чтение команд
    while (Serial.available()) {
        char c = Serial.read();
        if (c == '\n' || c == '\r') {
            if (buf_len > 0) { buf[buf_len] = 0; handle_command(buf); buf_len = 0; }
        } else if (buf_len < sizeof(buf) - 1) {
            buf[buf_len++] = c;
        }
    }

    // 2) безусловные аппаратные проверки безопасности
    if (estop_pressed() || !key_present()) { enter_safe(); }

    // 3) управление лазером
    if (state == FIRING) {
        bool timed_out = (millis() - fire_start_ms) > fire_duration_ms ||
                         (millis() - fire_start_ms) > MAX_FIRE_MS;
        if (laser_inhibited() || timed_out) {
            laser_off();
            state = (estop_pressed() || !key_present()) ? SAFE : ARMED;
        } else {
            digitalWrite(PIN_LASER_RELAY, HIGH);
            analogWrite(PIN_LASER_PWM, fire_power);
            digitalWrite(PIN_EMIT_LED, HIGH);
            laser_on = true;
        }
    } else {
        laser_off();
    }

    // 4) движение приводов (только если не SAFE)
    if (state != SAFE) {
        static unsigned long last_step = 0;
        if (micros() - last_step >= MIN_STEP_INTERVAL_US) {
            step_axis(PIN_PAN_STEP, PIN_PAN_DIR, pan_steps, pan_goal_steps);
            step_axis(PIN_TILT_STEP, PIN_TILT_DIR, tilt_steps, tilt_goal_steps);
            last_step = micros();
        }
    }

    // 5) телеметрия
    send_telemetry();
}
