# infrastructure/terraform/main.tf

terraform {
  required_version = ">= 1.3"

  required_providers {
    yandex = {
      source  = "yandex-cloud/yandex"
      version = "~> 0.100"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.4"
    }
  }

  backend "s3" {
    endpoints = {
      s3 = "https://storage.yandexcloud.net"
    }
    bucket   = "tfstate-k8s-airflow-2025-07-09"
    region   = "ru-central1"
    key      = "terraform.tfstate"

    skip_region_validation      = true
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_requesting_account_id  = true
  }
}

# Провайдер Yandex Cloud
provider "yandex" {
  cloud_id  = var.yc_cloud_id
  folder_id = var.yc_folder_id
  zone      = var.yc_zone
}

# Локальные переменные для удобства
locals {
  k8s_cluster_name = "${var.project_name}-${var.environment}"
  common_labels = {
    project     = var.project_name
    environment = var.environment
    managed_by  = "terraform"
  }
}

# Сеть для кластера
resource "yandex_vpc_network" "k8s_network" {
  name        = "${local.k8s_cluster_name}-network"
  description = "Network for Kubernetes cluster ${local.k8s_cluster_name}"
  labels      = local.common_labels
}

# Подсеть для кластера
resource "yandex_vpc_subnet" "k8s_subnet" {
  name           = "${local.k8s_cluster_name}-subnet"
  description    = "Subnet for Kubernetes cluster ${local.k8s_cluster_name}"
  v4_cidr_blocks = [var.subnet_cidr]
  zone           = var.yc_zone
  network_id     = yandex_vpc_network.k8s_network.id
  labels         = local.common_labels
}

# Security group для кластера
resource "yandex_vpc_security_group" "k8s_security_group" {
  name        = "${local.k8s_cluster_name}-sg"
  description = "Security group for Kubernetes cluster ${local.k8s_cluster_name}"
  network_id  = yandex_vpc_network.k8s_network.id
  labels      = local.common_labels

  # Разрешаем весь трафик внутри подсети
  ingress {
    protocol       = "ANY"
    description    = "Allow all traffic within subnet"
    v4_cidr_blocks = [var.subnet_cidr]
  }

  # SSH доступ
  ingress {
    protocol       = "TCP"
    description    = "SSH access"
    v4_cidr_blocks = var.ssh_allowed_ips
    port           = 22
  }

  # Kubernetes API
  ingress {
    protocol       = "TCP"
    description    = "Kubernetes API"
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = 6443
  }

  # NodePort диапазон для сервисов
  ingress {
    protocol       = "TCP"
    description    = "NodePort services"
    v4_cidr_blocks = ["0.0.0.0/0"]
    from_port      = 30000
    to_port        = 32767
  }

  # HTTP для Ingress
  ingress {
    protocol       = "TCP"
    description    = "HTTP traffic"
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = 80
  }

  # HTTPS для Ingress
  ingress {
    protocol       = "TCP"
    description    = "HTTPS traffic"
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = 443
  }

  # Исходящий трафик - разрешаем все
  egress {
    protocol       = "ANY"
    description    = "Allow all outgoing traffic"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}

# Создаем диски для нод
resource "yandex_compute_disk" "k8s_node_disk" {
  for_each = merge(
    { for i in range(var.master_count) : "master-${i}" => {
      role  = "master"
      index = i
    } },
    { for i in range(var.worker_count) : "worker-${i}" => {
      role  = "worker"
      index = i
    } }
  )

  name   = "${local.k8s_cluster_name}-${each.key}-disk"
  type   = var.disk_type
  zone   = var.yc_zone
  size   = each.value.role == "master" ? var.master_disk_size : var.worker_disk_size
  labels = merge(local.common_labels, { role = each.value.role })

  # Используем стандартный образ Ubuntu 22.04 LTS
  image_id = "fd80bm0rh4rkepi5ksdi" # Ubuntu 22.04 LTS
}

# Создаем виртуальные машины для кластера
resource "yandex_compute_instance" "k8s_node" {
  for_each = merge(
    { for i in range(var.master_count) : "master-${i}" => {
      role  = "master"
      index = i
    } },
    { for i in range(var.worker_count) : "worker-${i}" => {
      role  = "worker"
      index = i
    } }
  )

  name        = "${local.k8s_cluster_name}-${each.key}"
  hostname    = "${local.k8s_cluster_name}-${each.key}"
  platform_id = var.platform_id
  zone        = var.yc_zone
  labels      = merge(local.common_labels, { role = each.value.role })

  resources {
    cores         = each.value.role == "master" ? var.master_cpu : var.worker_cpu
    memory        = each.value.role == "master" ? var.master_memory : var.worker_memory
    core_fraction = var.core_fraction
  }

  boot_disk {
    disk_id = yandex_compute_disk.k8s_node_disk[each.key].id
  }

  network_interface {
    subnet_id          = yandex_vpc_subnet.k8s_subnet.id
    nat                = true
    security_group_ids = [yandex_vpc_security_group.k8s_security_group.id]
  }

  metadata = {
    ssh-keys = "ubuntu:${file(var.ssh_public_key_path)}"
    user-data = templatefile("${path.module}/cloud-init.yaml", {
      hostname = "${local.k8s_cluster_name}-${each.key}"
      role     = each.value.role
    })
  }

  scheduling_policy {
    preemptible = var.preemptible
  }
}

# Target group для Load Balancer
resource "yandex_lb_target_group" "k8s_workers" {
  name      = "${local.k8s_cluster_name}-workers"
  region_id = "ru-central1"
  labels    = local.common_labels

  dynamic "target" {
    for_each = { for k, v in yandex_compute_instance.k8s_node : k => v if can(regex("^worker-", k)) }
    content {
      subnet_id = yandex_vpc_subnet.k8s_subnet.id
      address   = target.value.network_interface[0].ip_address
    }
  }
}

# Network Load Balancer для доступа к Ingress
resource "yandex_lb_network_load_balancer" "k8s_lb" {
  name   = "${local.k8s_cluster_name}-lb"
  labels = local.common_labels

  listener {
    name = "http-listener"
    port = 32080
    external_address_spec {
      ip_version = "ipv4"
    }
  }

  listener {
    name = "https-listener"
    port = 32443
    external_address_spec {
      ip_version = "ipv4"
    }
  }

  attached_target_group {
    target_group_id = yandex_lb_target_group.k8s_workers.id

    healthcheck {
      name = "http"
      http_options {
        port = 32080
        path = "/healthz"
      }
      healthy_threshold   = 2
      unhealthy_threshold = 2
      timeout             = 1
      interval            = 5
    }
  }
}

# Генерация Ansible inventory
resource "local_file" "ansible_inventory" {
  content = templatefile("${path.module}/templates/inventory.tpl", {
    masters = { for k, v in yandex_compute_instance.k8s_node : k => {
      name       = v.name
      public_ip  = v.network_interface[0].nat_ip_address
      private_ip = v.network_interface[0].ip_address
    } if can(regex("^master-", k)) }

    workers = { for k, v in yandex_compute_instance.k8s_node : k => {
      name       = v.name
      public_ip  = v.network_interface[0].nat_ip_address
      private_ip = v.network_interface[0].ip_address
    } if can(regex("^worker-", k)) }

    ssh_user = "ubuntu"
    ssh_key  = var.ssh_private_key_path
    k3s_version = var.k3s_version
    master_internal_ip = try(values({
      for k, v in yandex_compute_instance.k8s_node :
      k => v.network_interface[0].ip_address
      if can(regex("^master-", k))
    })[0], "")
  })

  filename = "${path.module}/../ansible/inventory/hosts.yml"

  depends_on = [yandex_compute_instance.k8s_node]
}