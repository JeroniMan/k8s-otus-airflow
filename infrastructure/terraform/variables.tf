# infrastructure/terraform/variables.tf

# Yandex Cloud настройки
variable "yc_cloud_id" {
 description = "Yandex Cloud ID"
 type        = string
}

variable "yc_folder_id" {
 description = "Yandex Cloud Folder ID"
 type        = string
}

variable "yc_zone" {
 description = "Yandex Cloud Zone"
 type        = string
 default     = "ru-central1-a"
}

# Проект
variable "project_name" {
 description = "Project name"
 type        = string
 default     = "k8s-airflow"
}

variable "environment" {
 description = "Environment name"
 type        = string
 default     = "prod"
}

# Сеть
variable "subnet_cidr" {
 description = "CIDR block for subnet"
 type        = string
 default     = "10.0.1.0/24"
}

variable "ssh_allowed_ips" {
 description = "List of IPs allowed to SSH"
 type        = list(string)
 default     = ["0.0.0.0/0"] # В продакшене обязательно ограничьте!
}

# SSH ключи
variable "ssh_public_key_path" {
 description = "Path to SSH public key"
 type        = string
 default     = "~/.ssh/k8s-airflow.pub"
}

variable "ssh_private_key_path" {
 description = "Path to SSH private key for Ansible"
 type        = string
 default     = "~/.ssh/k8s-airflow"
}

# k3s версия
variable "k3s_version" {
 description = "Version of k3s to install"
 type        = string
 default     = "v1.28.5+k3s1"
}

# Master ноды
variable "master_count" {
 description = "Number of master nodes"
 type        = number
 default     = 1

 validation {
   condition     = var.master_count >= 1 && var.master_count <= 3
   error_message = "Master count must be between 1 and 3"
 }
}

variable "master_cpu" {
 description = "Number of CPU cores for master nodes"
 type        = number
 default     = 2

 validation {
   condition     = var.master_cpu >= 2
   error_message = "Master nodes require at least 2 CPU cores"
 }
}

variable "master_memory" {
 description = "Memory in GB for master nodes"
 type        = number
 default     = 4

 validation {
   condition     = var.master_memory >= 2
   error_message = "Master nodes require at least 2GB of memory"
 }
}

variable "master_disk_size" {
 description = "Disk size in GB for master nodes"
 type        = number
 default     = 50
}

# Worker ноды
variable "worker_count" {
 description = "Number of worker nodes"
 type        = number
 default     = 2

 validation {
   condition     = var.worker_count >= 1
   error_message = "At least 1 worker node is required"
 }
}

variable "worker_cpu" {
 description = "Number of CPU cores for worker nodes"
 type        = number
 default     = 2

 validation {
   condition     = var.worker_cpu >= 2
   error_message = "Worker nodes require at least 2 CPU cores"
 }
}

variable "worker_memory" {
 description = "Memory in GB for worker nodes"
 type        = number
 default     = 4

 validation {
   condition     = var.worker_memory >= 4
   error_message = "Worker nodes require at least 4GB of memory for Airflow"
 }
}

variable "worker_disk_size" {
 description = "Disk size in GB for worker nodes"
 type        = number
 default     = 100
}

# Общие настройки VM
variable "platform_id" {
 description = "Platform ID for instances"
 type        = string
 default     = "standard-v3" # Intel Ice Lake

 validation {
   condition = contains([
     "standard-v1", # Intel Broadwell
     "standard-v2", # Intel Cascade Lake
     "standard-v3"  # Intel Ice Lake
   ], var.platform_id)
   error_message = "Platform ID must be one of: standard-v1, standard-v2, standard-v3"
 }
}

variable "disk_type" {
 description = "Disk type"
 type        = string
 default     = "network-ssd"

 validation {
   condition = contains([
     "network-ssd",
     "network-hdd"
   ], var.disk_type)
   error_message = "Disk type must be either network-ssd or network-hdd"
 }
}

variable "core_fraction" {
 description = "Core fraction for burstable instances (5, 20, 50 or 100)"
 type        = number
 default     = 50 # 50% производительности для экономии

 validation {
   condition     = contains([5, 20, 50, 100], var.core_fraction)
   error_message = "Core fraction must be 5, 20, 50 or 100"
 }
}

variable "preemptible" {
 description = "Use preemptible instances (cheaper but can be terminated)"
 type        = bool
 default     = true
}