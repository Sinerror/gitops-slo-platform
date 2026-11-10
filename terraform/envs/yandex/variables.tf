variable "folder_id" {
  description = "ID каталога Yandex Cloud"
  type        = string
}

variable "name" {
  type    = string
  default = "gitops-slo"
}

variable "zone" {
  type    = string
  default = "ru-central1-a"
}

variable "nodes_cidr" {
  type    = string
  default = "10.10.0.0/24"
}

variable "k8s_version" {
  description = "Версия Kubernetes; доступные: yc managed-kubernetes list-versions"
  type        = string
}

variable "node_count" {
  type    = number
  default = 3
}

variable "node_cores" {
  type    = number
  default = 4
}

variable "node_memory_gb" {
  type    = number
  default = 8
}

variable "preemptible" {
  type    = bool
  default = true
}

variable "gitops_repo_url" {
  type    = string
  default = "https://github.com/Sinerror/gitops-slo-platform.git"
}

variable "gitops_revision" {
  type    = string
  default = "main"
}
