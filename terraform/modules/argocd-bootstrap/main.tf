# Единственное, что Terraform ставит в кластер руками: ArgoCD и корневое
# Application (app of apps). Всё остальное ArgoCD синхронизирует из Git.

terraform {
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.1"
    }
  }
}

resource "helm_release" "argocd" {
  name             = "argocd"
  namespace        = "argocd"
  create_namespace = true
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = var.argocd_chart_version
  timeout          = 900
  wait             = true

  values = [file("${path.module}/argocd-values.yaml")]
}

resource "helm_release" "root_app" {
  name       = "root"
  namespace  = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argocd-apps"
  version    = var.argocd_apps_chart_version

  values = [yamlencode({
    projects = {
      platform = {
        namespace                = "argocd"
        description              = "Платформенные компоненты (gateway, мониторинг, kafka, секреты (OpenBao), бэкапы)"
        sourceRepos              = ["*"]
        destinations             = [{ namespace = "*", server = "https://kubernetes.default.svc" }]
        clusterResourceWhitelist = [{ group = "*", kind = "*" }]
      }
      boutique = {
        namespace   = "argocd"
        description = "Приложение Online Boutique (staging, prod)"
        sourceRepos = [var.gitops_repo_url]
        destinations = [
          { namespace = "boutique-staging", server = "https://kubernetes.default.svc" },
          { namespace = "boutique-prod", server = "https://kubernetes.default.svc" },
        ]
        # Приложению нельзя создавать кластерные ресурсы (RBAC/CRD и т.п.)
        clusterResourceWhitelist   = [{ group = "", kind = "Namespace" }]
        namespaceResourceBlacklist = [{ group = "", kind = "ResourceQuota" }]
      }
    }
    applications = {
      root = {
        namespace = "argocd"
        project   = "platform"
        source = {
          repoURL        = var.gitops_repo_url
          targetRevision = var.gitops_revision
          path           = "argocd/apps"
          directory      = { recurse = true }
        }
        destination = {
          server    = "https://kubernetes.default.svc"
          namespace = "argocd"
        }
        syncPolicy = {
          automated = { prune = true, selfHeal = true }
        }
      }
    }
  })]

  depends_on = [helm_release.argocd]
}
