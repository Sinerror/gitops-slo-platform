#!/usr/bin/env bash
# Подъём стенда с нуля с замером времени:
#   terraform apply (kind + ArgoCD) -> ArgoCD синхронизирует платформу -> OpenBao init
#   -> все приложения Synced/Healthy -> магазин отвечает.
set -euo pipefail
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$REPO_DIR/measurements/bootstrap.csv"
[ -f "$OUT" ] || echo "date,terraform_s,platform_ready_s,total_s" > "$OUT"
export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/kind-gitops-slo}"
# registry.terraform.io недоступен из РФ/РК — зеркало Yandex Cloud (TF_MIRROR=0 чтобы выключить)
if [ "${TF_MIRROR:-1}" = 1 ]; then export TF_CLI_CONFIG_FILE="$REPO_DIR/terraform/terraformrc.mirror"; fi

t0=$(date +%s)
terraform -chdir="$REPO_DIR/terraform/envs/local" init -input=false >/dev/null
terraform -chdir="$REPO_DIR/terraform/envs/local" apply -auto-approve -input=false
t_tf=$(( $(date +%s) - t0 ))
echo ">> terraform: ${t_tf}s"

echo ">> ждём OpenBao"
# Все ожидания — с дедлайном: первый замер с нуля провисел полтора часа на бесконечном until
wait_for() { # wait_for <секунд> <описание> <команда...>
  local t="$1" what="$2" end; shift 2; end=$(( $(date +%s) + t ))
  until "$@" >/dev/null 2>&1; do
    if [ "$(date +%s)" -ge "$end" ]; then
      echo "ТАЙМАУТ (${t}s): $what" >&2
      kubectl -n argocd get applications 2>&1 | head -30 >&2
      kubectl get pods -A --no-headers 2>/dev/null | awk '$4!="Running"&&$4!="Completed"' >&2
      exit 1
    fi
    sleep 5
  done
}
wait_for 900 "под openbao-0 создан" kubectl -n openbao get pod openbao-0
bash "$REPO_DIR/scripts/openbao-init.sh"

# ESO к этому моменту уже несколько раз не смог прочитать секреты и ушёл в backoff —
# пинаем все ExternalSecret, иначе ожидание Grafana/SeaweedFS/Velero растянется на минуты
echo ">> force-sync ExternalSecrets"
store_ready() { kubectl get clustersecretstore openbao -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' | grep -q True; }
wait_for 600 "ClusterSecretStore openbao Ready" store_ready
kubectl get externalsecret -A --no-headers -o custom-columns=NS:.metadata.namespace,N:.metadata.name \
  | while read -r ns name; do kubectl -n "$ns" annotate externalsecret "$name" force-sync="$(date +%s)" --overwrite >/dev/null; done

echo ">> ждём, пока все приложения ArgoCD станут Synced/Healthy"
deadline=$(( $(date +%s) + 1800 ))
while :; do
  bad="$(kubectl -n argocd get applications -o jsonpath='{range .items[*]}{.metadata.name} {.status.sync.status} {.status.health.status}{"\n"}{end}' \
    | awk '$2!="Synced" || $3!="Healthy"')"
  [ -z "$bad" ] && break
  [ "$(date +%s)" -lt "$deadline" ] || { echo "не дождались:"; echo "$bad"; exit 1; }
  sleep 10
done
wait_for 300 "магазин отвечает на :18080" curl -sf -o /dev/null http://localhost:18080/
total=$(( $(date +%s) - t0 ))
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ),$t_tf,$(( total - t_tf )),$total" >> "$OUT"
echo ">> стенд готов за ${total}s (terraform ${t_tf}s) -> $OUT"
terraform -chdir="$REPO_DIR/terraform/envs/local" output urls
