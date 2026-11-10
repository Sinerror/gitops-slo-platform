# Thin wrappers over scripts (GNU make 3.81+, bash). On Windows run from Git Bash, not PowerShell.
SHELL := bash
export KUBECONFIG ?= $(HOME)/.kube/kind-gitops-slo

.PHONY: help up destroy openbao-init grafana-password status chaos-01 chaos-02 chaos-03 chaos-04 chaos-05 backup-test dora legacy-stopwatch lint

help:
	@echo "make up               - bring everything up from scratch (terraform + ArgoCD + OpenBao), timed"
	@echo "make destroy          - delete the stand"
	@echo "make status           - ArgoCD application status"
	@echo "make openbao-init     - init/unseal OpenBao (after a pod restart)"
	@echo "make grafana-password - Grafana admin password"
	@echo "make chaos-01..05     - failure drills (see chaos/)"
	@echo "make backup-test      - backup -> delete namespace -> restore -> verify data"
	@echo "make dora             - lead time / frequency / CFR from ArgoCD history and Git"
	@echo "make lint             - helm lint, terraform validate, kustomize build"

up:
	bash scripts/up.sh

destroy:
	TF_CLI_CONFIG_FILE=terraform/terraformrc.mirror terraform -chdir=terraform/envs/local destroy -auto-approve

status:
	kubectl -n argocd get applications

openbao-init:
	bash scripts/openbao-init.sh

grafana-password:
	@kubectl -n monitoring get secret grafana-admin -o jsonpath='{.data.admin-password}' | base64 -d; echo

chaos-01:
	bash chaos/01-pod-kill.sh
chaos-02:
	bash chaos/02-node-down.sh
chaos-03:
	bash chaos/03-bad-release.sh
chaos-04:
	bash chaos/04-redis-disk-full.sh
chaos-05:
	bash chaos/05-kafka-consumer-lag.sh

backup-test:
	bash scripts/backup-restore-test.sh

dora:
	bash scripts/dora.sh

legacy-stopwatch:
	bash legacy/stopwatch.sh

lint:
	helm lint charts/boutique -f envs/staging/values.yaml
	helm lint charts/boutique -f envs/prod/values.yaml
	kubectl kustomize platform/monitoring/manifests > /dev/null
	TF_CLI_CONFIG_FILE=terraform/terraformrc.mirror terraform -chdir=terraform/envs/local validate
