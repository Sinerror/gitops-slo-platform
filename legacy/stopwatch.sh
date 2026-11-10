#!/usr/bin/env bash
# Секундомер для ручного деплоя по legacy/README.md: человек выполняет шаг в другом
# терминале и жмёт Enter. Записывает длительность каждого шага и общий lead time.
set -euo pipefail
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$REPO_DIR/measurements/legacy-deploy.csv"
[ -f "$OUT" ] || echo "date,step,seconds" > "$OUT"

steps=(
  "1. docker build"
  "2. kind load docker-image"
  "3. скачать и поправить манифесты"
  "4. kubectl apply"
  "5. дождаться подов"
  "6. ручная проверка магазина"
  "7. запись в журнал релизов"
)

date_iso() { date -u +%Y-%m-%dT%H:%M:%SZ; }
start_all=$(date +%s)
for s in "${steps[@]}"; do
  read -r -p "Начинаю: $s — Enter, когда приступили... " _
  t=$(date +%s)
  read -r -p "   ...Enter, когда шаг выполнен " _
  d=$(( $(date +%s) - t ))
  echo "$(date_iso),\"$s\",$d" >> "$OUT"
  echo "   $s: ${d}s"
done
total=$(( $(date +%s) - start_all ))
echo "$(date_iso),\"TOTAL manual deploy\",$total" >> "$OUT"
echo "Итого ручной деплой: ${total}s  ->  $OUT"
