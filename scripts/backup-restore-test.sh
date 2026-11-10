#!/usr/bin/env bash
# Проверка восстановления из бэкапа (а не только факта бэкапа):
#   1. кладём в корзину маркерный товар (сессия restore-check-<время>)
#   2. Velero backup namespace boutique-prod (манифесты + файловый бэкап томов Kopia)
#   3. отключаем автосинк ArgoCD для boutique-prod и удаляем namespace — «потеря»
#   4. Velero restore; меряем время до работающего магазина
#   5. проверяем, что маркерный товар в корзине на месте (данные Redis восстановлены)
#   6. возвращаем автосинк ArgoCD
# Результат -> measurements/backup-restore.csv
set -euo pipefail
# Git Bash: KUBECONFIG в Windows-форму, чтобы MSYS_NO_PATHCONV у kubectl exec не ломал путь
if command -v cygpath >/dev/null 2>&1; then
  KUBECONFIG="$(cygpath -m "${KUBECONFIG:-$HOME/.kube/config}")"
  export KUBECONFIG
fi

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$REPO_DIR/measurements/backup-restore.csv"
[ -f "$OUT" ] || echo "date,backup_s,restore_s,restore_to_shop_ok_s,data_restored,notes" > "$OUT"
SHOP=http://localhost:18080
STAMP="$(date +%Y%m%d-%H%M%S)"
SESSION="restore-check-$STAMP"
PRODUCT=66VCHSJNUP   # Tank Top
now() { date +%s; }
log() { echo "$(date -u +%H:%M:%S) $*"; }

# Корзина хранится в Redis хэшем <session> -> data (protobuf). Проверяем сам ключ, а не HTML
# страницы корзины: там есть блок рекомендаций с ID товаров (ложные совпадения), а сразу после
# restore cartservice может быть ещё не готов (ложный «нет данных» в первом прогоне).
redis_cli() {
  local pod
  pod="$(kubectl -n boutique-prod get pod -l app=redis-cart -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)" || return 1
  MSYS_NO_PATHCONV=1 kubectl -n boutique-prod exec "$pod" -c redis -- redis-cli "$@" 2>/dev/null
}
cart_has_marker() {
  redis_cli HGET "$SESSION" data | grep -q "$PRODUCT"
}

wait_phase() { # wait_phase <kind> <name> <timeout>
  local deadline=$(( $(now) + $3 )) phase=""
  while [ "$(now)" -lt "$deadline" ]; do
    phase="$(kubectl -n velero get "$1" "$2" -o jsonpath='{.status.phase}' 2>/dev/null || true)"
    case "$phase" in
      Completed) return 0 ;;
      Failed|PartiallyFailed|FailedValidation) log "$1/$2: $phase"; kubectl -n velero get "$1" "$2" -o yaml | tail -20; return 1 ;;
    esac
    sleep 3
  done
  log "$1/$2: timeout (phase=$phase)"; return 1
}

log "1. marker: add $PRODUCT to cart of session $SESSION"
curl -s -o /dev/null -X POST -b "shop_session-id=$SESSION" -d product_id=$PRODUCT -d quantity=3 "$SHOP/cart"
cart_has_marker || { echo "маркер не появился в корзине" >&2; exit 1; }
sleep 2  # AOF everysec

log "2. velero backup"
t0="$(now)"
cat <<EOF | kubectl apply -f - >/dev/null
apiVersion: velero.io/v1
kind: Backup
metadata:
  name: restore-test-$STAMP
  namespace: velero
spec:
  includedNamespaces: [boutique-prod]
  defaultVolumesToFsBackup: true
  storageLocation: default
  ttl: 72h0m0s
EOF
wait_phase backup "restore-test-$STAMP" 600
t_backup=$(( $(now) - t0 ))
log "   backup completed in ${t_backup}s"

log "3. disable ArgoCD auto-sync (root + boutique-prod) and delete namespace boutique-prod"
# root тоже: иначе его selfHeal вернёт boutique-prod автосинк из Git и namespace пересоздастся пустым
# shellcheck disable=SC2089,SC2090  # JSON-строка для kubectl patch, не массив аргументов
AUTO='{"spec":{"syncPolicy":{"automated":{"prune":true,"selfHeal":true}}}}'
kubectl -n argocd patch application root --type merge -p '{"spec":{"syncPolicy":{"automated":null}}}' >/dev/null
kubectl -n argocd patch application boutique-prod --type merge -p '{"spec":{"syncPolicy":{"automated":null}}}' >/dev/null
# shellcheck disable=SC2090
trap 'kubectl -n argocd patch application boutique-prod --type merge -p "$AUTO" >/dev/null; kubectl -n argocd patch application root --type merge -p "$AUTO" >/dev/null' EXIT
kubectl delete namespace boutique-prod --wait=true --timeout=300s >/dev/null
log "   namespace deleted; shop: $(curl -s -o /dev/null -m 5 -w '%{http_code}' $SHOP/ || true)"

log "4. velero restore"
t1="$(now)"
cat <<EOF | kubectl apply -f - >/dev/null
apiVersion: velero.io/v1
kind: Restore
metadata:
  name: restore-test-$STAMP
  namespace: velero
spec:
  backupName: restore-test-$STAMP
  includedNamespaces: [boutique-prod]
  existingResourcePolicy: none
EOF
wait_phase restore "restore-test-$STAMP" 900
t_restore=$(( $(now) - t1 ))
log "   restore completed in ${t_restore}s"

deadline=$(( $(now) + 600 ))
until curl -s -o /dev/null -m 5 -w '%{http_code}' "$SHOP/" | grep -q 200; do
  [ "$(now)" -lt "$deadline" ] || { log "shop not OK after restore"; break; }
  sleep 3
done
t_shop=$(( $(now) - t1 ))
log "   shop OK ${t_shop}s after restore start"

log "5. data check (Redis, до 60 с)"
restored=no
for _ in $(seq 1 20); do cart_has_marker && { restored=yes; break; }; sleep 3; done
log "   marker in cart after restore: $restored"

echo "$(date -u +%Y-%m-%dT%H:%M:%SZ),$t_backup,$t_restore,$t_shop,$restored,\"namespace boutique-prod deleted and restored (Kopia FS backup of redis tmpfs)\"" >> "$OUT"
log "6. re-enable ArgoCD auto-sync (trap); result -> $OUT"
