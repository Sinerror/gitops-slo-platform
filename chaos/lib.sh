#!/usr/bin/env bash
# Общие функции учебных аварий: отметки времени, ожидание алерта в Alertmanager,
# ожидание восстановления, запись результата в measurements/chaos-results.csv.
#
# Метрики:
#   MTTD = время от внесения аварии до появления первого алерта в Alertmanager
#   MTTR = время от внесения аварии до восстановления (SLI/реплики в норме)
#   time-to-mitigate = от алерта до начала исправляющего действия (в скриптах — сразу)
set -euo pipefail
# Git Bash (Windows) переписывает аргументы вида /path в C:/Program Files/Git/path:
# `kubectl exec ... rm /data/x` молча промахивался мимо пода. Глобально конвертацию не
# выключаем (сломается `curl -o /dev/null`), а используем kexec для команд внутри подов.
if command -v cygpath >/dev/null 2>&1; then
  KUBECONFIG="$(cygpath -m "${KUBECONFIG:-$HOME/.kube/config}")"
  export KUBECONFIG
fi
kexec() { MSYS_NO_PATHCONV=1 kubectl exec "$@"; }

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Наблюдаем через kubectl port-forward (API-сервер на control-plane), а не через platform
# Gateway: иначе авария на узле с Envoy ослепила бы сам замер.
# port-forward живёт недолго: в сценарии 05 он тихо умер за 20 минут ожидания, и скрипт
# не увидел алерт, который в Prometheus горел. Поэтому ensure_pf вызывается перед каждым
# запросом и поднимает проброс заново, если он не отвечает.
_PF_MANAGED=0; _PF_AM=""; _PF_PROM=""
if [ -z "${AM_URL:-}" ] || [ -z "${PROM_URL:-}" ]; then
  _PF_MANAGED=1
  AM_URL=http://127.0.0.1:19093
  PROM_URL=http://127.0.0.1:19090
  trap 'kill $_PF_AM $_PF_PROM 2>/dev/null || true' EXIT
fi
ensure_pf() {
  [ "$_PF_MANAGED" = 1 ] || return 0
  if ! curl -s -m 3 -o /dev/null "$AM_URL/-/ready"; then
    [ -n "$_PF_AM" ] && kill "$_PF_AM" 2>/dev/null || true
    kubectl -n monitoring port-forward --address 127.0.0.1 svc/kube-prometheus-stack-alertmanager 19093:9093 >/dev/null 2>&1 &
    _PF_AM=$!
    for _ in $(seq 1 20); do curl -s -m 3 -o /dev/null "$AM_URL/-/ready" && break; sleep 0.5; done
  fi
  if ! curl -s -m 3 -o /dev/null "$PROM_URL/-/ready"; then
    [ -n "$_PF_PROM" ] && kill "$_PF_PROM" 2>/dev/null || true
    kubectl -n monitoring port-forward --address 127.0.0.1 svc/kube-prometheus-stack-prometheus 19090:9090 >/dev/null 2>&1 &
    _PF_PROM=$!
    for _ in $(seq 1 20); do curl -s -m 3 -o /dev/null "$PROM_URL/-/ready" && break; sleep 0.5; done
  fi
}
ensure_pf
RESULTS="$REPO_DIR/measurements/chaos-results.csv"
RAW_DIR="$REPO_DIR/measurements/raw"
mkdir -p "$RAW_DIR"
[ -f "$RESULTS" ] || echo "date,scenario,first_alert,mttd_s,mttr_s,user_errors_5xx,notes" > "$RESULTS"

SCENARIO="${SCENARIO:-unknown}"
LOG="$RAW_DIR/chaos-$(date +%Y%m%d-%H%M%S)-$SCENARIO.log"

now() { date +%s; }
iso() { date -u +%Y-%m-%dT%H:%M:%SZ; }
log() { echo "$(iso) [$SCENARIO] $*" | tee -a "$LOG"; }

# Активные (не silenced/inhibited) алерты с одним из имён; печатает первое найденное
firing_alert() {
  local names="$1" body
  ensure_pf
  body="$(curl -s -m 10 -G "$AM_URL/api/v2/alerts" --data-urlencode active=true \
    --data-urlencode silenced=false --data-urlencode inhibited=false || true)"
  for n in $names; do
    if echo "$body" | grep -q "\"alertname\":\"$n\""; then echo "$n"; return 0; fi
  done
  return 1
}

# Перед внесением аварии ни один из целевых алертов не должен уже гореть —
# иначе wait_alert поймает старый алерт и MTTD будет фальшивым
assert_quiet() {
  local a
  if a="$(firing_alert "$1")"; then
    echo "алерт $a уже активен — дождитесь его разрешения и повторите" >&2
    exit 1
  fi
}

# wait_alert "<alert names>" <timeout_s>  -> выставляет ALERT_NAME и ALERT_AT (epoch)
wait_alert() {
  local names="$1" timeout="$2" deadline=$(( $(now) + $2 ))
  ALERT_NAME=""; ALERT_AT=""
  while [ "$(now)" -lt "$deadline" ]; do
    if ALERT_NAME="$(firing_alert "$names")"; then
      ALERT_AT="$(now)"; log "ALERT firing: $ALERT_NAME"; return 0
    fi
    sleep 5
  done
  log "no alert from [$names] within ${timeout}s"
  return 1
}

# Значение PromQL-скаляра (первая серия), пусто — если нет данных
prom() {
  ensure_pf
  curl -s -m 10 -G "$PROM_URL/api/v1/query" --data-urlencode "query=$1" \
    | grep -o '"value":\[[^]]*\]' | head -1 | sed -E 's/.*,"([^"]*)"\]/\1/'
}

# Сколько 5xx отдал prod Gateway с момента <t0>. Через increase(): он учитывает сброс
# счётчиков при рестарте Envoy (простая разница сумм в сценарии 02 дала «-59»).
gateway_5xx_since() {
  local t0="$1" w v
  w=$(( $(now) - t0 + 30 ))
  v="$(prom "sum(increase(envoy_http_downstream_rq_xx{gateway=\"prod\",envoy_response_code_class=\"5\"}[${w}s]))")"
  printf '%.0f' "${v:-0}"
}
# Оставлено для совместимости вызовов: отметка «до» больше не нужна
gateway_5xx_total() { echo 0; }

# Все Deployment в namespace доступны в желаемом количестве
deployments_ready() {
  local ns="$1"
  kubectl -n "$ns" get deploy -o jsonpath='{range .items[*]}{.spec.replicas}={.status.availableReplicas}{"\n"}{end}' \
    | awk -F= '$1!=$2 {bad=1} END {exit bad}'
}

# Пробный HTTP-запрос через prod Gateway
shop_ok() {
  local path="${1:-/}" code
  code="$(curl -s -o /dev/null -m 5 -w '%{http_code}' "http://localhost:18080$path" || true)"
  [ "$code" -lt 500 ] 2>/dev/null && [ "$code" -gt 0 ] 2>/dev/null
}

# wait_until <timeout_s> <описание> <команда...>
wait_until() {
  local timeout="$1" what="$2"; shift 2
  local deadline=$(( $(now) + timeout ))
  while [ "$(now)" -lt "$deadline" ]; do
    if "$@" >/dev/null 2>&1; then log "OK: $what"; return 0; fi
    sleep 3
  done
  log "TIMEOUT: $what (${timeout}s)"; return 1
}

# record <t0> <recovered_at> <5xx_before> <notes>
record() {
  local t0="$1" t_rec="$2" notes="$4"
  local mttd="" mttr="" errors
  [ -n "${ALERT_AT:-}" ] && mttd=$(( ALERT_AT - t0 ))
  [ -n "$t_rec" ] && mttr=$(( t_rec - t0 ))
  sleep 30  # дать Prometheus снять последние значения счётчиков
  errors="$(gateway_5xx_since "$t0")"
  echo "$(iso),$SCENARIO,${ALERT_NAME:-none},${mttd},${mttr},${errors},\"$notes\"" >> "$RESULTS"
  log "RESULT first_alert=${ALERT_NAME:-none} mttd=${mttd:-n/a}s mttr=${mttr:-n/a}s 5xx=$errors"
  log "log: $LOG ; summary: $RESULTS"
}

require_cluster() {
  kubectl get ns boutique-prod >/dev/null || { echo "кластер недоступен (KUBECONFIG?)" >&2; exit 1; }
  curl -s -o /dev/null "$AM_URL/-/ready" || { echo "Alertmanager недоступен: $AM_URL" >&2; exit 1; }
}
