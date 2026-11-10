#!/usr/bin/env bash
# Авария 1: одновременное падение всех подов frontend в prod (kill -9, без graceful shutdown).
# Ожидание: Deployment пересоздаёт поды; вопрос — сколько запросов успевает упасть
# и замечает ли это мониторинг.
export SCENARIO=01-pod-kill
source "$(dirname "$0")/lib.sh"
require_cluster
assert_quiet "BoutiqueHighErrorRate SLOAvailabilityFastBurn BoutiqueDeploymentUnavailable BoutiquePodRestarting"

e0="$(gateway_5xx_total)"
t0="$(now)"
log "inject: kubectl delete pod -l app=frontend --grace-period=0 --force"
kubectl -n boutique-prod delete pod -l app=frontend --grace-period=0 --force >>"$LOG" 2>&1

# Восстановление: все реплики frontend доступны и главная отвечает
frontend_ready() {
  [ "$(kubectl -n boutique-prod get deploy frontend -o jsonpath='{.status.availableReplicas}')" = \
    "$(kubectl -n boutique-prod get deploy frontend -o jsonpath='{.spec.replicas}')" ] && shop_ok /
}
wait_until 300 "frontend восстановлен" frontend_ready
t_rec="$(now)"

# Алерт мог сработать и после восстановления (for: 1-2m) — ждём ещё 4 минуты
wait_alert "BoutiqueHighErrorRate SLOAvailabilityFastBurn BoutiqueDeploymentUnavailable BoutiquePodRestarting" 240 || true

record "$t0" "$t_rec" "$e0" "kill all frontend pods; self-healed by Deployment"
