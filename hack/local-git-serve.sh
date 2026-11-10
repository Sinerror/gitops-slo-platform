#!/usr/bin/env bash
# Отладка GitOps без пуша на GitHub. Временный git-сервер живёт внутри kind
# (hack/local-git-server.yaml), снимок рабочей копии заливается через
# kubectl exec (наружу ничего не публикуется). Ваш репозиторий не коммитится.
#
#   hack/local-git-serve.sh up       # поднять git-сервер в кластере
#   hack/local-git-serve.sh push     # залить снимок текущих файлов
#   hack/local-git-serve.sh point    # переключить ArgoCD на локальный снимок
#   hack/local-git-serve.sh unpoint  # вернуть GitHub и удалить git-сервер
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WORK="${TMPDIR:-/tmp}/gitops-slo-snapshot"
GITHUB_URL="https://github.com/Sinerror/gitops-slo-platform.git"
LOCAL_URL="git://local-git.argocd.svc.cluster.local/gitops-slo-platform.git"

up() {
  kubectl apply -f "$REPO_DIR/hack/local-git-server.yaml"
  kubectl -n argocd rollout status deploy/local-git --timeout=120s
}

push() {
  rm -rf "$WORK" && mkdir -p "$WORK"
  (cd "$REPO_DIR" && git ls-files -co --exclude-standard -z | tar --null -T - -cf -) | (cd "$WORK" && tar -xf -)
  grep -rl "$GITHUB_URL" "$WORK" | xargs -r sed -i "s#$GITHUB_URL#$LOCAL_URL#g"
  # git push через port-forward на Windows зависает, поэтому файлы передаются
  # tar-потоком через kubectl exec, а коммит делается внутри пода.
  (cd "$WORK" && tar -cf - .) | kubectl -n argocd exec -i deploy/local-git -- sh -c '
    set -e
    rm -rf /srv/work && mkdir -p /srv/work && tar -xf - -C /srv/work
    cd /srv/work && git init -q -b main && git add -A
    git -c user.name=local -c user.email=local@localhost commit -qm "snapshot $(date -Iseconds)"
    git push -qf /srv/gitops-slo-platform.git main
    git rev-parse --short HEAD'
  kubectl -n argocd annotate application root argocd.argoproj.io/refresh=hard --overwrite >/dev/null
}

point() {
  local url="$1"
  kubectl -n argocd patch application root --type merge -p "{\"spec\":{\"source\":{\"repoURL\":\"$url\"}}}"
  kubectl -n argocd patch appproject boutique --type merge -p "{\"spec\":{\"sourceRepos\":[\"$url\"]}}"
  kubectl -n argocd annotate application root argocd.argoproj.io/refresh=hard --overwrite
}

case "${1:-}" in
  up) up ;;
  push) push ;;
  point) point "$LOCAL_URL" ;;
  unpoint)
    point "$GITHUB_URL"
    kubectl delete -f "$REPO_DIR/hack/local-git-server.yaml" --ignore-not-found
    ;;
  *) echo "usage: $0 up|push|point|unpoint" >&2; exit 2 ;;
esac
