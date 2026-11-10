# РћРєСЂСѓР¶РµРЅРёРµ "yandex": Managed Kubernetes РІ Yandex Cloud + С‚РѕС‚ Р¶Рµ ArgoCD-bootstrap.
# РџСЂРёРјРµРЅСЏРµС‚СЃСЏ РѕРїС†РёРѕРЅР°Р»СЊРЅРѕ (СЃС‚РѕРёС‚ РґРµРЅРµРі). РџРµСЂРµРґ apply:
#   1. yc init; export YC_TOKEN=$(yc iam create-token) YC_CLOUD_ID=... YC_FOLDER_ID=...
#   2. cp backend.hcl.example backend.hcl && terraform init -backend-config=backend.hcl
#   3. cp terraform.tfvars.example terraform.tfvars && terraform apply
# РџРѕРіР°СЃРёС‚СЊ: terraform destroy

terraform {
  required_version = ">= 1.9"

  required_providers {
    yandex = {
      source  = "yandex-cloud/yandex"
      version = "~> 0.244"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.1"
    }
  }

  # Remote state РІ Yandex Object Storage (S3-СЃРѕРІРјРµСЃС‚РёРјС‹Р№). РџР°СЂР°РјРµС‚СЂС‹ вЂ” РІ backend.hcl.
  backend "s3" {}
}

provider "yandex" {
  folder_id = var.folder_id
  zone      = var.zone
}

# ---------- РЎРµС‚СЊ ----------
resource "yandex_vpc_network" "this" {
  name = "${var.name}-net"
}

resource "yandex_vpc_subnet" "nodes" {
  name           = "${var.name}-nodes"
  zone           = var.zone
  network_id     = yandex_vpc_network.this.id
  v4_cidr_blocks = [var.nodes_cidr]
}

# ---------- РЎРµСЂРІРёСЃРЅС‹Рµ Р°РєРєР°СѓРЅС‚С‹ ----------
resource "yandex_iam_service_account" "cluster" {
  name = "${var.name}-cluster"
}

resource "yandex_iam_service_account" "nodes" {
  name = "${var.name}-nodes"
}

resource "yandex_resourcemanager_folder_iam_member" "cluster" {
  for_each  = toset(["k8s.clusters.agent", "vpc.publicAdmin", "load-balancer.admin"])
  folder_id = var.folder_id
  role      = each.value
  member    = "serviceAccount:${yandex_iam_service_account.cluster.id}"
}

resource "yandex_resourcemanager_folder_iam_member" "nodes" {
  folder_id = var.folder_id
  role      = "container-registry.images.puller"
  member    = "serviceAccount:${yandex_iam_service_account.nodes.id}"
}

# ---------- РљР»Р°СЃС‚РµСЂ ----------
resource "yandex_kubernetes_cluster" "this" {
  name       = var.name
  network_id = yandex_vpc_network.this.id

  master {
    version   = var.k8s_version
    public_ip = true

    zonal {
      zone      = var.zone
      subnet_id = yandex_vpc_subnet.nodes.id
    }

    maintenance_policy {
      auto_upgrade = false
    }
  }

  service_account_id      = yandex_iam_service_account.cluster.id
  node_service_account_id = yandex_iam_service_account.nodes.id
  release_channel         = "STABLE"
  network_policy_provider = "CALICO"

  depends_on = [
    yandex_resourcemanager_folder_iam_member.cluster,
    yandex_resourcemanager_folder_iam_member.nodes,
  ]
}

resource "yandex_kubernetes_node_group" "workers" {
  cluster_id = yandex_kubernetes_cluster.this.id
  name       = "${var.name}-workers"
  version    = var.k8s_version

  instance_template {
    platform_id = "standard-v3"

    resources {
      cores         = var.node_cores
      memory        = var.node_memory_gb
      core_fraction = 100
    }

    boot_disk {
      type = "network-ssd"
      size = 64
    }

    # РџСЂРµСЂС‹РІР°РµРјС‹Рµ Р’Рњ РІ СЂР°Р·С‹ РґРµС€РµРІР»Рµ вЂ” РґР»СЏ СѓС‡РµР±РЅРѕРіРѕ СЃС‚РµРЅРґР° РґРѕСЃС‚Р°С‚РѕС‡РЅРѕ.
    scheduling_policy {
      preemptible = var.preemptible
    }

    network_interface {
      subnet_ids = [yandex_vpc_subnet.nodes.id]
      nat        = true
    }

    container_runtime {
      type = "containerd"
    }
  }

  scale_policy {
    fixed_scale {
      size = var.node_count
    }
  }

  allocation_policy {
    location {
      zone = var.zone
    }
  }
}

# ---------- ArgoCD (С‚РѕС‚ Р¶Рµ РјРѕРґСѓР»СЊ, С‡С‚Рѕ Рё РґР»СЏ kind) ----------
provider "helm" {
  kubernetes = {
    host                   = yandex_kubernetes_cluster.this.master[0].external_v4_endpoint
    cluster_ca_certificate = yandex_kubernetes_cluster.this.master[0].cluster_ca_certificate
    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "yc"
      args        = ["managed-kubernetes", "create-token"]
    }
  }
}

module "argocd" {
  source = "../../modules/argocd-bootstrap"

  gitops_repo_url = var.gitops_repo_url
  gitops_revision = var.gitops_revision

  depends_on = [yandex_kubernetes_node_group.workers]
}
