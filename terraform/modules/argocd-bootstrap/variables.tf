variable "gitops_repo_url" {
  description = "URL GitOps-репозитория, из которого ArgoCD берёт манифесты"
  type        = string
}

variable "gitops_revision" {
  description = "Ветка/тег GitOps-репозитория"
  type        = string
  default     = "main"
}

variable "argocd_chart_version" {
  type    = string
  default = "10.17.1"
}

variable "argocd_apps_chart_version" {
  type    = string
  default = "2.0.7"
}
