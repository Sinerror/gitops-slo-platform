# Окружение "local": kind-кластер в Docker + ArgoCD.
# Подъём с нуля:  terraform init && terraform apply
# Остальное (gateway, мониторинг, kafka, vault, velero, приложение) ставит ArgoCD.

terraform {
  required_version = ">= 1.9"

  required_providers {
    kind = {
      source  = "tehcyx/kind"
      version = "~> 0.13.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.1"
    }
  }

  # Для локального кластера state хранится локально: удалённый backend внутри
  # того же кластера был бы курицей и яйцом. Окружение yandex использует
  # remote state в Object Storage (см. ../yandex/backend.hcl.example).
  backend "local" {
    path = "terraform.tfstate"
  }
}

locals {
  kubeconfig_path = pathexpand(var.kubeconfig_path)

  # NodePort'ы Envoy Gateway (см. platform/gateway) -> 127.0.0.1 хоста
  port_mappings = [
    { node_port = 30080, host_port = 18080 }, # prod HTTP
    { node_port = 30443, host_port = 18443 }, # prod HTTPS
    { node_port = 30081, host_port = 18081 }, # staging HTTP
    { node_port = 30090, host_port = 18090 }, # platform UI: grafana, argocd, ...
  ]
}

module "cluster" {
  source = "../../modules/kind-cluster"

  cluster_name    = var.cluster_name
  node_image      = var.node_image
  worker_count    = var.worker_count
  kubeconfig_path = local.kubeconfig_path
  port_mappings   = local.port_mappings
}

provider "helm" {
  kubernetes = {
    host                   = module.cluster.endpoint
    client_certificate     = module.cluster.client_certificate
    client_key             = module.cluster.client_key
    cluster_ca_certificate = module.cluster.cluster_ca_certificate
  }
}

module "argocd" {
  source = "../../modules/argocd-bootstrap"

  gitops_repo_url = var.gitops_repo_url
  gitops_revision = var.gitops_revision

  depends_on = [module.cluster]
}
