#!/usr/bin/env bash
# DORA-метрики по фактическим данным:
#   lead time  = deployedAt (история ArgoCD) - Source-Commit-Time (трейлер, который пишет CI)
#   частота    = число синков приложения за период
#   CFR        = доля релизов prod, после которых был revert
# Использование: scripts/dora.sh [app] (по умолчанию boutique-staging и boutique-prod)
set -euo pipefail
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APPS="${*:-boutique-staging boutique-prod}"
to_epoch() { date -d "$1" +%s; }

for app in $APPS; do
  echo "== $app"
  hist="$(kubectl -n argocd get application "$app" \
    -o jsonpath='{range .status.history[*]}{.revision} {.deployedAt}{"\n"}{end}')"
  [ -n "$hist" ] || { echo "   истории синков нет"; continue; }
  n=0; sum=0
  while read -r rev deployed; do
    [ -n "$rev" ] || continue
    # ревизии, которых нет в репозитории (снимки временного git-сервера до публикации), пропускаем
    if ! git -C "$REPO_DIR" cat-file -e "$rev^{commit}" 2>/dev/null; then
      printf '   %s  %-40s (ревизии нет в репозитории)
' "$deployed" "${rev:0:7}"; continue
    fi
    src="$(git -C "$REPO_DIR" log -1 --format=%B "$rev" | sed -n 's/^Source-Commit-Time: //p' | head -1)"
    subj="$(git -C "$REPO_DIR" log -1 --format=%s "$rev")"
    if [ -n "$src" ]; then
      lt=$(( $(to_epoch "$deployed") - $(to_epoch "$src") ))
      n=$((n+1)); sum=$((sum+lt))
      printf '   %s  %-40s lead time %4ds\n' "$deployed" "$subj" "$lt"
    else
      printf '   %s  %-40s (не из CI)\n' "$deployed" "$subj"
    fi
  done <<< "$hist"
  [ "$n" -eq 0 ] || echo "   средний lead time по $n релизам из CI: $((sum/n))s"
  echo "   синков в истории: $(echo "$hist" | grep -c .)"
done

prod_releases=$(git -C "$REPO_DIR" log --oneline -- envs/prod | grep -vc '^.\{8\} Revert' || true)
reverts=$(git -C "$REPO_DIR" log --oneline -- envs/prod | grep -c 'Revert' || true)
echo "== change failure rate (prod): $reverts revert(ов) на $prod_releases изменений envs/prod"
