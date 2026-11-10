variable "cluster_name" {
  description = "Имя kind-кластера"
  type        = string
}

variable "node_image" {
  description = "Образ узла kind (версия Kubernetes), закреплён по digest"
  type        = string
}

variable "worker_count" {
  description = "Количество worker-узлов (минимум 3 для сценария падения узла)"
  type        = number
  default     = 3

  validation {
    condition     = var.worker_count >= 1
    error_message = "Нужен хотя бы один worker."
  }
}

variable "kubeconfig_path" {
  description = "Куда записать kubeconfig кластера"
  type        = string
}

variable "port_mappings" {
  description = "Проброс NodePort -> порт на 127.0.0.1 хоста"
  type = list(object({
    node_port = number
    host_port = number
  }))
  default = []
}
