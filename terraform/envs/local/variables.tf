variable "cluster_name" {
  type    = string
  default = "gitops-slo"
}

variable "node_image" {
  description = "Kubernetes 1.36.4 (kind v0.33.0), закреплён по digest"
  type        = string
  default     = "kindest/node:v1.36.4@sha256:099e049362a1526b2db71494e1947aae99bd16290d7c895f2b7ea312e3cbfaed"
}

variable "worker_count" {
  type    = number
  default = 3
}

variable "kubeconfig_path" {
  type    = string
  default = "~/.kube/kind-gitops-slo"
}

variable "gitops_repo_url" {
  type    = string
  default = "https://github.com/Sinerror/gitops-slo-platform.git"
}

variable "gitops_revision" {
  type    = string
  default = "main"
}
