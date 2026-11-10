#!/usr/bin/env bash
# Авария 5: отставание consumer Kafka. Релиз конфигурации order-consumer с
# processingDelayMs=30000 (имитация медленной зависимости) — обработка становится
# медленнее потока заказов, lag растёт. Исправление — git revert.
#   MODE=git (по умолчанию) | MODE=local — как в 03-bad-release.sh
export SCENARIO=05-kafka-consumer-lag
source "$(dirname "$0")/lib.sh"
require_cluster
assert_quiet "KafkaConsumerLagHigh"
MODE="${MODE:-git}"
VALUES="$REPO_DIR/envs/prod/values.yaml"

publish() { publish_git boutique-prod; }
lag() { prom 'sum(kafka_consumergroup_lag{consumergroup="order-consumer",topic="orders"})'; }

git -C "$REPO_DIR" diff --quiet -- "$VALUES" || { echo "в $VALUES есть незакоммиченные изменения" >&2; exit 1; }

e0="$(gateway_5xx_total)"
t0="$(now)"
log "inject: orderConsumer.processingDelayMs=30000 (MODE=$MODE), lag before: $(lag)"
printf '\norderConsumer:\n  processingDelayMs: 30000\n' >> "$VALUES"
git -C "$REPO_DIR" commit -qm "prod: order-consumer config change (chaos 05: slow consumer)" -- "$VALUES"
BAD_COMMIT="$(git -C "$REPO_DIR" rev-parse HEAD)"
publish

wait_alert "KafkaConsumerLagHigh" 1200 || true
log "lag at alert: $(lag)"

log "mitigate: git revert $BAD_COMMIT"
git -C "$REPO_DIR" revert --no-edit "$BAD_COMMIT" >>"$LOG"
publish

lag_drained() { v="$(lag)"; [ -n "$v" ] && [ "${v%.*}" -le 2 ]; }
wait_until 900 "lag снова около нуля" lag_drained
t_rec="$(now)"

record "$t0" "$t_rec" "$e0" "slow consumer config release; rollback = git revert ($MODE)"
