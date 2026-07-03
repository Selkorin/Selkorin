#!/usr/bin/env python3
"""Анализ журнала прогона пиролизной установки с помощью ИИ (Claude API).

Контроллер пишет CSV-телеметрию в Serial (см. ../controller/WIRING.md).
Скрипт считает статистику прогона, ищет аномалии простыми эвристиками,
а затем (если задан ANTHROPIC_API_KEY) отправляет сводку в Claude для
инженерного разбора: оценка качества регулирования, подозрительные
участки, рекомендации по следующему прогону.

ВАЖНО: ИИ здесь — только аналитик ПОСЛЕ прогона. Аварийные защиты
работают детерминированно в контроллере и механике (клапан, гидрозатвор)
и не зависят от этого скрипта.

Использование:
    pip install anthropic
    export ANTHROPIC_API_KEY=sk-ant-...
    python analyze_run.py run_20260703_1400.csv
"""

import csv
import os
import sys
from statistics import mean


def load_run(path: str) -> list[dict]:
    with open(path, newline="") as f:
        return [row for row in csv.DictReader(f) if row.get("t_reactor")]


def summarize(rows: list[dict]) -> str:
    t = [float(r["t_reactor"]) for r in rows]
    tv = [float(r["t_vapor"]) for r in rows]
    p = [float(r["p_bar"]) for r in rows]
    duty = [float(r["heater_duty"]) for r in rows]
    states = [r["state"] for r in rows]
    duration_min = (int(rows[-1]["ms"]) - int(rows[0]["ms"])) / 60000

    # простые эвристики до всякого ИИ
    warnings = []
    if max(p) > 1.0:
        warnings.append(f"давление доходило до {max(p):.2f} бар — проверить тракт на закоксовывание")
    soak = [x for x, s in zip(t, states) if s == "SOAK"]
    if soak and (max(soak) - min(soak)) > 15:
        warnings.append(f"колебания температуры на выдержке ±{(max(soak)-min(soak))/2:.0f} °C — перенастроить PID")
    if any(s == "FAULT" for s in states):
        first_fault = next(r for r in rows if r["state"] == "FAULT")
        warnings.append(f"прогон завершился АВАРИЕЙ на {int(first_fault['ms'])//60000} мин: {first_fault.get('', '')}")

    lines = [
        f"Длительность: {duration_min:.0f} мин",
        f"T реактора: макс {max(t):.0f} °C, на выдержке в среднем {mean(soak):.0f} °C" if soak else f"T реактора: макс {max(t):.0f} °C (до выдержки не дошло)",
        f"T паров: макс {max(tv):.0f} °C",
        f"Давление: макс {max(p):.2f} бар",
        f"Средняя мощность нагрева на выдержке: {mean([d for d, s in zip(duty, states) if s == 'SOAK']):.0f} %" if soak else "",
        f"Состояния: {' -> '.join(dict.fromkeys(states))}",
    ]
    if warnings:
        lines.append("Эвристики: " + "; ".join(warnings))
    return "\n".join(x for x in lines if x)


def ai_review(summary: str, sample_rows: list[dict]) -> str:
    try:
        import anthropic
    except ImportError:
        return "(пакет anthropic не установлен — только локальная сводка)"
    if not os.environ.get("ANTHROPIC_API_KEY"):
        return "(ANTHROPIC_API_KEY не задан — только локальная сводка)"

    sample = "\n".join(",".join(r.values()) for r in sample_rows[:: max(1, len(sample_rows) // 120)])
    client = anthropic.Anthropic()
    msg = client.messages.create(
        model="claude-sonnet-5",
        max_tokens=1500,
        system=(
            "Ты инженер-технолог по пиролизу полиолефинов. Тебе дают телеметрию "
            "прогона мини-реактора (уставка 430 °C, рампа 5 °C/мин, PID+SSR). "
            "Разбери прогон: качество регулирования, признаки проблем (закоксовывание "
            "тракта — рост давления; захлёб конденсатора — рост T паров; недогрев), "
            "и дай 3-5 конкретных рекомендаций к следующему прогону. Отвечай по-русски, кратко."
        ),
        messages=[{
            "role": "user",
            "content": f"Сводка прогона:\n{summary}\n\nПрореженная телеметрия (CSV):\n{sample}",
        }],
    )
    return msg.content[0].text


def main() -> None:
    if len(sys.argv) != 2:
        sys.exit(f"использование: {sys.argv[0]} run_XXXX.csv")
    rows = load_run(sys.argv[1])
    if not rows:
        sys.exit("журнал пуст или без заголовка CSV")
    summary = summarize(rows)
    print("=== Сводка прогона ===")
    print(summary)
    print("\n=== Разбор ИИ ===")
    print(ai_review(summary, rows))


if __name__ == "__main__":
    main()
