# infrastructure/terraform/outputs.tf

# IP адреса master нод
output "master_ips" {
  description = "IP addresses of master nodes"
  value = {
    for k, v in yandex_compute_instance.k8s_node : k => {
      public_ip  = v.network_interface[0].nat_ip_address
      private_ip = v.network_interface[0].ip_address
    } if can(regex("^master-", k))
  }
}

# IP адреса worker нод
output "worker_ips" {
  description = "IP addresses of worker nodes"
  value = {
    for k, v in yandex_compute_instance.k8s_node : k => {
      public_ip  = v.network_interface[0].nat_ip_address
      private_ip = v.network_interface[0].ip_address
    } if can(regex("^worker-", k))
  }
}

# IP адрес Load Balancer
output "load_balancer_ip" {
  description = "IP address of the load balancer"
  value = try(
    flatten([
      for listener in yandex_lb_network_load_balancer.k8s_lb.listener :
      listener.external_address_spec[*].address if listener.name == "http"
    ])[0],
    flatten([
      for listener in yandex_lb_network_load_balancer.k8s_lb.listener :
      listener.external_address_spec[*].address
    ])[0]
  )
}

# Внутренний IP master для NFS
output "master_internal_ip" {
  description = "Internal IP of master node for NFS"
  value = try(values({
    for k, v in yandex_compute_instance.k8s_node :
    k => v.network_interface[0].ip_address
    if can(regex("^master-", k))
  })[0], "")
}

# Информация о сети
output "network_info" {
  description = "Network information"
  value = {
    network_id = yandex_vpc_network.k8s_network.id
    subnet_id  = yandex_vpc_subnet.k8s_subnet.id
    subnet_cidr = var.subnet_cidr
  }
}

# SSH команда для подключения к master
output "ssh_master_command" {
  description = "SSH command to connect to master node"
  value = format(
    "ssh -i %s ubuntu@%s",
    var.ssh_private_key_path,
    try(values({ for k, v in yandex_compute_instance.k8s_node : k => v.network_interface[0].nat_ip_address if can(regex("^master-", k)) })[0], "")
  )
}

# Путь к kubeconfig на master ноде
output "kubeconfig_path" {
  description = "Path to kubeconfig on master node"
  value       = "/etc/rancher/k3s/k3s.yaml"
}

# Команда для получения kubeconfig
output "get_kubeconfig_command" {
  description = "Command to get kubeconfig from master"
  value = format(
    "ssh -i %s ubuntu@%s 'sudo cat /etc/rancher/k3s/k3s.yaml' > kubeconfig && sed -i 's/127.0.0.1/%s/g' kubeconfig",
    var.ssh_private_key_path,
    try(values({ for k, v in yandex_compute_instance.k8s_node : k => v.network_interface[0].nat_ip_address if can(regex("^master-", k)) })[0], ""),
    try(values({ for k, v in yandex_compute_instance.k8s_node : k => v.network_interface[0].nat_ip_address if can(regex("^master-", k)) })[0], "")
  )
}

# URL для доступа к сервисам
output "service_urls" {
  description = "URLs to access services"
  value = {
    airflow = format("http://%s:8080",
      try(
        flatten([
          for listener in yandex_lb_network_load_balancer.k8s_lb.listener :
          listener.external_address_spec[*].address if listener.name == "airflow"
        ])[0],
        flatten([
          for listener in yandex_lb_network_load_balancer.k8s_lb.listener :
          listener.external_address_spec[*].address
        ])[0]
      )
    )
    grafana = format("http://%s:3000",
      try(
        flatten([
          for listener in yandex_lb_network_load_balancer.k8s_lb.listener :
          listener.external_address_spec[*].address if listener.name == "grafana"
        ])[0],
        flatten([
          for listener in yandex_lb_network_load_balancer.k8s_lb.listener :
          listener.external_address_spec[*].address
        ])[0]
      )
    )
    prometheus = format("http://%s:9090",
      try(
        flatten([
          for listener in yandex_lb_network_load_balancer.k8s_lb.listener :
          listener.external_address_spec[*].address if listener.name == "prometheus"
        ])[0],
        flatten([
          for listener in yandex_lb_network_load_balancer.k8s_lb.listener :
          listener.external_address_spec[*].address
        ])[0]
      )
    )
    argocd = format("https://%s:8443",
      try(
        flatten([
          for listener in yandex_lb_network_load_balancer.k8s_lb.listener :
          listener.external_address_spec[*].address if listener.name == "argocd"
        ])[0],
        flatten([
          for listener in yandex_lb_network_load_balancer.k8s_lb.listener :
          listener.external_address_spec[*].address
        ])[0]
      )
    )
  }
}

# Информация о созданных ресурсах
output "created_resources" {
  description = "Summary of created resources"
  value = {
    cluster_name  = local.k8s_cluster_name
    master_count  = var.master_count
    worker_count  = var.worker_count
    total_cpu     = (var.master_count * var.master_cpu) + (var.worker_count * var.worker_cpu)
    total_memory  = (var.master_count * var.master_memory) + (var.worker_count * var.worker_memory)
    preemptible   = var.preemptible
    k3s_version   = var.k3s_version
  }
}