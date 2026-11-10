#!/usr/bin/env bash
# Авария 2: «падение узла» — останавливаем Docker-контейнер worker-узла kind.
# Выбирается worker с наибольшим числом подов boutique-prod, но НЕ тот, где работают
# Prometheus / Alertmanager / kube-state-metrics: иначе алерт не может сработать
# физически, и «нет алерта» было бы артефактом замера, а не результатом.
# Исправляющее действие после алерта: вернуть узел (docker start) — аналог перезагрузки ВМ.
# По умолчанию Kubernetes выселяет поды с NotReady-узла только через 300 с
# (tolerations not-ready/unreachable), это видно в таймлайне.
export SCENARIO=02-node-down
source "$(dirname "$0")/lib.sh"
require_cluster
assert_quiet "NodeNotReady BoutiqueHighErrorRate BoutiqueDeploymentUnavailable SLOAvailabilityFastBurn"

MON_NODES="$(kubectl -n monitoring get pod -o jsonpath='{range .items[*]}{.metadata.name} {.spec.nodeName}{"\n"}{end}' \
  | grep -E '^(prometheus-kube|alertmanager-kube|kube-prometheus-stack-kube-state)' | awk '{print $2}' | sort -u | paste -sd'|')"
NODE="$(kubectl -n boutique-prod get pod -o jsonpath='{range .items[*]}{.spec.nodeName}{"\n"}{end}' \
  | grep worker | grep -vE "^(${MON_NODES:-none})$" | sort | uniq -c | sort -rn | awk 'NR==1{print $2}')"
[ -n "$NODE" ] || { echo "нет worker-узла без компонентов мониторинга" >&2; exit 1; }
log "monitoring on: ${MON_NODES//|/, }; target node: $NODE ($(kubectl -n boutique-prod get pod -o jsonpath='{range .items[*]}{.spec.nodeName}{"
"}{end}' | grep -cx "$NODE") boutique-prod pods)"
log "platform pods on target: $(kubectl get pod -A -o jsonpath='{range .items[*]}{.spec.nodeName} {.metadata.namespace}/{.metadata.name}{"
"}{end}' | awk -v n="$NODE" '$1==n && $2!~/^(boutique|kube-system)/ {print $2}' | paste -sd' ')"

e0="$(gateway_5xx_total)"
t0="$(now)"
log "inject: docker stop $NODE"
docker stop "$NODE" >>"$LOG"

wait_alert "NodeNotReady BoutiqueHighErrorRate BoutiqueDeploymentUnavailable SLOAvailabilityFastBurn" 600 || true

log "mitigate: docker start $NODE"
docker start "$NODE" >>"$LOG"
node_ready() { kubectl get node "$NODE" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' | grep -q True; }
wait_until 600 "узел $NODE Ready" node_ready
# Если на узле был OpenBao, после рестарта он запечатан — распечатать (шаг runbook'а)
# (bao status возвращает 2 для sealed — с pipefail «| grep» напрямую давал ложь, поэтому через переменную)
bao_status="$(kexec -n openbao openbao-0 -- bao status -address=http://127.0.0.1:8200 2>/dev/null || true)"
if echo "$bao_status" | grep -qE 'Sealed +true'; then
  log "mitigate: OpenBao sealed after node restart -> scripts/openbao-init.sh"
  bash "$REPO_DIR/scripts/openbao-init.sh" >>"$LOG" 2>&1
fi
wait_until 600 "все Deployment в boutique-prod доступны" deployments_ready boutique-prod
wait_until 120 "главная отвечает" shop_ok /
t_rec="$(now)"

record "$t0" "$t_rec" "$e0" "docker stop $NODE; mitigation docker start after alert"
