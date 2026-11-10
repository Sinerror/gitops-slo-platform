#!/usr/bin/env bash
# Инициализация и настройка OpenBao (идемпотентно, можно запускать повторно):
#   - init (1 ключ — учебный стенд) и unseal; ключи -> .secrets/openbao-init.json (в .gitignore)
#   - kv-v2 по пути kv/, Kubernetes auth, политика и роль для External Secrets
#   - генерация случайных паролей платформы, если их ещё нет
# После рестарта пода OpenBao запечатан — запустите скрипт снова (он только распечатает).
# В облаке вместо этого: auto-unseal через KMS и отзыв root-токена.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SECRETS_DIR="$REPO_DIR/.secrets"
INIT_FILE="$SECRETS_DIR/openbao-init.json"
NS=openbao
POD=openbao-0
mkdir -p "$SECRETS_DIR"

bao() {
  kubectl -n "$NS" exec -i "$POD" -- env BAO_ADDR=http://127.0.0.1:8200 BAO_TOKEN="${BAO_TOKEN:-}" bao "$@"
}

json_field() { # json_field <key> < file  — без jq
  tr -d '\n ' | grep -o "\"$1\":\[\?\"[^\"]*\"" | head -1 | sed 's/.*"\([^"]*\)"$/\1/'
}

rand() { head -c 24 /dev/urandom | base64 | tr -d '/+=' | head -c 24; }

echo ">> waiting for $POD"
kubectl -n "$NS" wait --for=jsonpath='{.status.phase}'=Running "pod/$POD" --timeout=300s

status="$(bao status -format=json 2>/dev/null || true)"
if echo "$status" | tr -d ' ' | grep -q '"initialized":false'; then
  echo ">> operator init"
  bao operator init -key-shares=1 -key-threshold=1 -format=json > "$INIT_FILE"
  chmod 600 "$INIT_FILE"
  status="$(bao status -format=json 2>/dev/null || true)"
fi

[ -s "$INIT_FILE" ] || { echo "OpenBao уже инициализирован, но $INIT_FILE нет — восстановите файл с ключами" >&2; exit 1; }
UNSEAL_KEY="$(json_field unseal_keys_b64 < "$INIT_FILE")"
BAO_TOKEN="$(json_field root_token < "$INIT_FILE")"
export BAO_TOKEN

if echo "$status" | tr -d ' ' | grep -q '"sealed":true'; then
  echo ">> unseal"
  bao operator unseal "$UNSEAL_KEY" >/dev/null
fi

echo ">> kv-v2 и kubernetes auth"
bao secrets list -format=json | grep -q '"kv/"' || bao secrets enable -path=kv kv-v2
bao auth list -format=json | grep -q '"kubernetes/"' || bao auth enable kubernetes
bao write auth/kubernetes/config kubernetes_host=https://kubernetes.default.svc >/dev/null

bao policy write eso - >/dev/null <<'EOF'
# External Secrets: только чтение секретов платформы и приложения
path "kv/data/platform/*" { capabilities = ["read"] }
path "kv/data/boutique/*" { capabilities = ["read"] }
EOF

bao write auth/kubernetes/role/eso \
  bound_service_account_names=external-secrets \
  bound_service_account_namespaces=external-secrets \
  policies=eso ttl=1h >/dev/null

seed() { # seed <path> key=value...  — только если секрета ещё нет
  local path="$1"; shift
  if bao kv get -mount=kv "$path" >/dev/null 2>&1; then
    echo "   kv/$path уже есть"
  else
    bao kv put -mount=kv "$path" "$@" >/dev/null
    echo "   kv/$path создан"
  fi
}

echo ">> секреты"
seed platform/grafana admin-user=admin admin-password="$(rand)"
seed platform/backup-s3 access-key="velero$(rand | head -c 8)" secret-key="$(rand)"

echo ">> готово"
