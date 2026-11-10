#!/usr/bin/env bash
# Авария 3: плохой релиз в prod — конфигурация с FAULT_ERROR_RATE=0.5 для checkoutservice
# выкатывается обычным GitOps-путём (коммит в envs/prod/values.yaml -> ArgoCD sync).
# Половина оформлений заказа отвечает 500. Исправление — git revert того же коммита.
#
#   MODE=git   (по умолчанию) — коммит и push в origin (GitHub), как в жизни
#   MODE=local — без пуша на GitHub, через hack/local-git-serve.sh (отладка до публикации)
export SCENARIO=03-bad-release
source "$(dirname "$0")/lib.sh"
require_cluster
assert_quiet "CheckoutErrorRateHigh BoutiqueHighErrorRate SLOAvailabilityFastBurn"
MODE="${MODE:-git}"
VALUES="$REPO_DIR/envs/prod/values.yaml"

publish() { publish_git boutique-prod; }

git -C "$REPO_DIR" diff --quiet -- "$VALUES" || { echo "в $VALUES есть незакоммиченные изменения" >&2; exit 1; }

e0="$(gateway_5xx_total)"
t0="$(now)"
log "inject: commit FAULT_ERROR_RATE=0.5 into envs/prod/values.yaml (MODE=$MODE)"
sed -i -E '/^  checkoutservice:$/{n;s/^(    replicas: 2)$/\1\n    env:\n      FAULT_ERROR_RATE: "0.5"/}' "$VALUES"
grep -q FAULT_ERROR_RATE "$VALUES" || { echo "не удалось внести изменение" >&2; exit 1; }
git -C "$REPO_DIR" commit -qm "prod: checkoutservice config change (chaos 03: bad release)" -- "$VALUES"
BAD_COMMIT="$(git -C "$REPO_DIR" rev-parse HEAD)"
publish

wait_alert "CheckoutErrorRateHigh BoutiqueHighErrorRate SLOAvailabilityFastBurn" 900 || true

log "mitigate: git revert $BAD_COMMIT"
git -C "$REPO_DIR" revert --no-edit "$BAD_COMMIT" >>"$LOG"
publish

checkout_clean() {
  ! kubectl -n boutique-prod get deploy checkoutservice -o yaml | grep -q FAULT_ERROR_RATE \
    && kubectl -n boutique-prod rollout status deploy/checkoutservice --timeout=5s
}
wait_until 600 "откат выкачен (FAULT_ERROR_RATE убран)" checkout_clean
t_rec="$(now)"

record "$t0" "$t_rec" "$e0" "bad config release via GitOps; rollback = git revert ($MODE)"
