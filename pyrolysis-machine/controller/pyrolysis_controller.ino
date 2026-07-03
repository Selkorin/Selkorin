/*
 * Контроллер мини-установки пиролиза пластика
 * Плата: ESP32 DevKit v1
 *
 * Функции:
 *  - PID-регулирование температуры реактора через SSR (окно 2 с)
 *  - Программа нагрева: рампа 5 °C/мин до уставки, выдержка
 *  - Жёсткие блокировки (детерминированные, без ИИ):
 *      T реактора > 480 °C            -> АВАРИЯ
 *      T паров    > 400 °C            -> АВАРИЯ
 *      Давление   > 1.5 бар           -> АВАРИЯ
 *      Обрыв/КЗ термопары             -> АВАРИЯ
 *      Утечка горючего газа (MQ-2)    -> АВАРИЯ
 *    АВАРИЯ = снять сигнал с контактора нагрева (fail-safe: катушка
 *    держится выходом HEATER_ENABLE; пропало питание/контроллер завис
 *    -> контактор отпал -> нагрев выключен), сирена, лог.
 *  - Телеметрия: CSV в Serial раз в 2 с (для журнала прогона и
 *    последующего ИИ-анализа, см. ../ai/analyze_run.py)
 *
 * ВАЖНО: электроника не заменяет механический предохранительный клапан
 * и гидрозатвор. Кнопка аварийного останова разрывает цепь катушки
 * контактора аппаратно, мимо этого кода.
 *
 * Библиотеки (Library Manager):
 *   Adafruit MAX31855 library
 */

#include <SPI.h>
#include "Adafruit_MAX31855.h"

// ---------- Пины ----------
#define PIN_SCK        18   // SPI, общий для обеих термопар
#define PIN_MISO       19
#define PIN_CS_TC1      5   // термопара реактора
#define PIN_CS_TC2     17   // термопара паров
#define PIN_PRESSURE   34   // датчик давления 0.5-4.5В через делитель -> 0.27-2.45В
#define PIN_GAS        35   // MQ-2, аналоговый выход через делитель
#define PIN_SSR        25   // твердотельное реле нагревателей
#define PIN_CONTACTOR  26   // катушка контактора (через реле-модуль), HIGH = разрешён нагрев
#define PIN_BUZZER     27
#define PIN_START_BTN  32   // кнопка "старт программы" (на GND, INPUT_PULLUP)

// ---------- Параметры процесса ----------
const float T_SETPOINT      = 430.0;  // уставка реактора, °C
const float RAMP_C_PER_MIN  = 5.0;    // скорость нагрева
const float T_REACTOR_TRIP  = 480.0;  // аварийный порог реактора
const float T_VAPOR_TRIP    = 400.0;  // аварийный порог паров
const float P_TRIP_BAR      = 1.5;    // аварийное давление
const int   GAS_TRIP_RAW    = 2200;   // порог MQ-2 (подобрать калибровкой!)
const unsigned long SOAK_MS = 3UL * 60UL * 60UL * 1000UL; // выдержка 3 ч максимум

// ---------- PID ----------
const float KP = 8.0, KI = 0.02, KD = 60.0;
const unsigned long PID_WINDOW_MS = 2000; // окно ШИМ для SSR

enum State { IDLE, PURGE_WAIT, RAMP, SOAK, COOLDOWN, FAULT };
State state = IDLE;
const char* stateNames[] = {"IDLE","PURGE_WAIT","RAMP","SOAK","COOLDOWN","FAULT"};

Adafruit_MAX31855 tc1(PIN_SCK, PIN_CS_TC1, PIN_MISO);
Adafruit_MAX31855 tc2(PIN_SCK, PIN_CS_TC2, PIN_MISO);

float rampTarget = 25.0;
float integral = 0, prevErr = 0;
unsigned long windowStart = 0, rampStartMs = 0, soakStartMs = 0, lastLogMs = 0;
String faultReason = "";

float readPressureBar() {
  // датчик 0-5 бар, 0.5-4.5В; делитель 10к/18.7к -> коэффициент 0.652
  float v = analogReadMilliVolts(PIN_PRESSURE) / 1000.0 / 0.652;
  return (v - 0.5) * 5.0 / 4.0;
}

void trip(const String& reason) {
  digitalWrite(PIN_SSR, LOW);
  digitalWrite(PIN_CONTACTOR, LOW);   // контактор отпадает — нагрев обесточен
  state = FAULT;
  faultReason = reason;
}

bool checkInterlocks(float t1, float t2, float pBar, int gasRaw) {
  if (isnan(t1))              { trip("TC1_FAULT");   return false; }
  if (isnan(t2))              { trip("TC2_FAULT");   return false; }
  if (t1 > T_REACTOR_TRIP)    { trip("OVERTEMP_REACTOR"); return false; }
  if (t2 > T_VAPOR_TRIP)      { trip("OVERTEMP_VAPOR");   return false; }
  if (pBar > P_TRIP_BAR)      { trip("OVERPRESSURE");     return false; }
  if (gasRaw > GAS_TRIP_RAW)  { trip("GAS_LEAK");         return false; }
  return true;
}

void setup() {
  Serial.begin(115200);
  pinMode(PIN_SSR, OUTPUT);       digitalWrite(PIN_SSR, LOW);
  pinMode(PIN_CONTACTOR, OUTPUT); digitalWrite(PIN_CONTACTOR, LOW);
  pinMode(PIN_BUZZER, OUTPUT);
  pinMode(PIN_START_BTN, INPUT_PULLUP);
  delay(500); // старт MAX31855
  Serial.println("ms,state,t_reactor,t_vapor,p_bar,gas_raw,ramp_target,heater_duty");
}

void loop() {
  float t1 = tc1.readCelsius();
  float t2 = tc2.readCelsius();
  float pBar = readPressureBar();
  int gasRaw = analogRead(PIN_GAS);
  float duty = 0;

  if (state != IDLE && state != FAULT) {
    if (!checkInterlocks(t1, t2, pBar, gasRaw)) { /* trip() уже вызван */ }
  }

  switch (state) {
    case IDLE:
      if (digitalRead(PIN_START_BTN) == LOW) {
        // Оператор подтверждает кнопкой, что продувка инертом выполнена
        state = PURGE_WAIT;
      }
      break;

    case PURGE_WAIT:
      // 60 секунд на отход от установки, потом старт нагрева
      static unsigned long purgeT = 0;
      if (purgeT == 0) purgeT = millis();
      if (millis() - purgeT > 60000) {
        purgeT = 0;
        rampTarget = isnan(t1) ? 25.0 : t1;
        rampStartMs = millis();
        digitalWrite(PIN_CONTACTOR, HIGH); // разрешить силовую цепь
        integral = 0; prevErr = 0; windowStart = millis();
        state = RAMP;
      }
      break;

    case RAMP:
    case SOAK: {
      if (state == RAMP) {
        rampTarget += RAMP_C_PER_MIN * (millis() - rampStartMs) / 60000.0f;
        rampStartMs = millis();
        if (rampTarget >= T_SETPOINT) { rampTarget = T_SETPOINT; soakStartMs = millis(); state = SOAK; }
      } else if (millis() - soakStartMs > SOAK_MS) {
        digitalWrite(PIN_SSR, LOW);
        digitalWrite(PIN_CONTACTOR, LOW);
        state = COOLDOWN;
        break;
      }
      // PID
      float err = rampTarget - t1;
      integral += KI * err;
      integral = constrain(integral, 0, 100);
      float deriv = KD * (err - prevErr);
      prevErr = err;
      duty = constrain(KP * err + integral + deriv, 0, 100);
      // ШИМ медленным окном для SSR
      if (millis() - windowStart > PID_WINDOW_MS) windowStart = millis();
      digitalWrite(PIN_SSR, (millis() - windowStart) < duty * PID_WINDOW_MS / 100.0 ? HIGH : LOW);
      break;
    }

    case COOLDOWN:
      if (!isnan(t1) && t1 < 80) state = IDLE;
      break;

    case FAULT:
      // сирена, выход только перезапуском питания после осмотра установки
      digitalWrite(PIN_BUZZER, (millis() / 400) % 2);
      break;
  }

  // телеметрия CSV
  if (millis() - lastLogMs > 2000) {
    lastLogMs = millis();
    Serial.printf("%lu,%s,%.1f,%.1f,%.3f,%d,%.1f,%.0f", millis(), stateNames[state],
                  t1, t2, pBar, gasRaw, rampTarget, duty);
    if (state == FAULT) Serial.printf(",FAULT:%s", faultReason.c_str());
    Serial.println();
  }
  delay(100);
}
