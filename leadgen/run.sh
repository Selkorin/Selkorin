#!/usr/bin/env bash
# Запуск Selkorin Lead Engine.
# Создаёт venv, ставит зависимости и поднимает сервер.
set -e
cd "$(dirname "$0")"

if [ ! -d ".venv" ]; then
  echo "→ Создаю виртуальное окружение..."
  python3 -m venv .venv
fi

# shellcheck disable=SC1091
source .venv/bin/activate
echo "→ Устанавливаю зависимости..."
pip install --quiet --upgrade pip
pip install --quiet -r requirements.txt

if [ ! -f ".env" ]; then
  cp .env.example .env
  echo "→ Создан .env (демо-режим). Ключи можно добавить позже в интерфейсе."
fi

PORT="${PORT:-8000}"
echo "→ Запуск на http://localhost:${PORT}"
exec uvicorn app.main:app --host 0.0.0.0 --port "${PORT}"
