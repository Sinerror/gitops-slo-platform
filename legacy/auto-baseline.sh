#!/usr/bin/env bash
# Нижняя граница для «до»: те же 7 шагов из legacy/README.md, но выполненные скриптом
# без единой паузы. Человек по инструкции из вики не может быть быстрее: он ещё читает,
# набирает команды, правит YAML в редакторе и кликает в браузере. Поэтому результат —
# «не быстрее, чем», а не замер ручной работы. Замер с человеком — legacy/stopwatch.sh.
#
# Результат: measurements/legacy-deploy.csv (строки с пометкой scripted).
set -euo pipefail
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_SRC="${APP_SRC:-$REPO_DIR/../gitops-slo-app/src/checkoutservice}"
OUT="$REPO_DIR/measurements/legacy-deploy.csv"
WORK="$(mktemp -d)"
IMG=ghcr.io/sinerror/checkoutservice:manual
MANIFESTS_URL=https://raw.githubusercontent.com/GoogleCloudPlatform/microservices-demo/v0.10.7/release/kubernetes-manifests.yaml
if command -v cygpath >/dev/null 2>&1; then
  KUBECONFIG="$(cygpath -m "${KUBECONFIG:-$HOME/.kube/kind-gitops-slo}")"; export KUBECONFIG
fi
[ -f "$OUT" ] || echo "date,step,seconds" > "$OUT"
date_iso() { date -u +%Y-%m-%dT%H:%M:%SZ; }
PF=""
trap '[ -n "$PF" ] && kill "$PF" 2>/dev/null; rm -rf "$WORK"' EXIT

step() { # step "<название>" <функция>
  local name="$1" t d; shift
  t=$(date +%s)
  "$@"
  d=$(( $(date +%s) - t ))
  echo "$(date_iso),\"$name (scripted)\",$d" >> "$OUT"
  echo ">> $name: ${d}s"
}

s1() { docker build --no-cache -q -t "$IMG" "$APP_SRC" >/dev/null; }
s2() { kind load docker-image --name gitops-slo "$IMG" >/dev/null 2>&1; }
s3() {
  curl -sfL -o "$WORK/kubernetes-manifests.yaml" "$MANIFESTS_URL"
  sed -i -E "s#^( *image: ).*/checkoutservice:.*#\1$IMG#" "$WORK/kubernetes-manifests.yaml"
  grep -q "image: $IMG" "$WORK/kubernetes-manifests.yaml"
}
s4() {
  kubectl create namespace legacy --dry-run=client -o yaml | kubectl apply -f - >/dev/null
  kubectl -n legacy apply -f "$(cygpath -m "$WORK/kubernetes-manifests.yaml" 2>/dev/null || echo "$WORK/kubernetes-manifests.yaml")" >/dev/null
}
s5() {
  # loadgenerator не ждём: в ручной инструкции смотрят только на сервисы магазина
  for d in $(kubectl -n legacy get deploy -o name | grep -v loadgenerator); do
    kubectl -n legacy rollout status "$d" --timeout=900s >/dev/null
  done
}
s6() {
  kubectl -n legacy port-forward --address 127.0.0.1 svc/frontend 9999:80 >/dev/null 2>&1 &
  PF=$!
  local jar="$WORK/jar" code
  for _ in $(seq 1 30); do curl -s -m 3 -o /dev/null http://127.0.0.1:9999/_healthz && break; sleep 1; done
  chk() { code=$(curl -s -m 90 -o /dev/null -w '%{http_code}' -b "$jar" -c "$jar" "$@"); echo "   $code ${*: -1}"; [ "$code" -lt 400 ]; }
  chk http://127.0.0.1:9999/
  chk -X POST -d product_id=OLJCESPC7Z -d quantity=1 http://127.0.0.1:9999/cart
  chk -X POST -d email=manual@example.com -d street_address=Main -d zip_code=94043 -d city=City -d state=CA \
      -d country=US -d credit_card_number=4432801561520454 -d credit_card_expiration_month=1 \
      -d credit_card_expiration_year=2039 -d credit_card_cvv=672 http://127.0.0.1:9999/cart/checkout
  kill "$PF" 2>/dev/null || true; PF=""
}
s7() { echo "$(date_iso) checkoutservice:manual выкачен в legacy" >> "$WORK/release-journal.txt"; }

start=$(date +%s)
step "1. docker build" s1
step "2. kind load docker-image" s2
step "3. скачать и поправить манифесты" s3
step "4. kubectl apply" s4
step "5. дождаться подов" s5
step "6. ручная проверка магазина" s6
step "7. запись в журнал релизов" s7
total=$(( $(date +%s) - start ))
echo "$(date_iso),\"TOTAL manual deploy (scripted lower bound)\",$total" >> "$OUT"
echo "Итого: ${total}s (нижняя граница, без человека) -> $OUT"
echo "После замера: kubectl delete namespace legacy"
