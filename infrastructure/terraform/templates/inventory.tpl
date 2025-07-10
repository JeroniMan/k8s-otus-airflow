# infrastructure/terraform/templates/inventory.tpl

# Глобальные переменные для всех хостов
all:
  vars:
    ansible_user: ${ssh_user}
    ansible_ssh_private_key_file: ${ssh_key}
    ansible_ssh_common_args: '-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'
    ansible_python_interpreter: /usr/bin/python3

    # Kubernetes настройки
    k3s_version: "${k3s_version}"
    k3s_config_file: /etc/rancher/k3s/config.yaml

    # NFS настройки
    nfs_server_ip: ${master_internal_ip}
    nfs_path: /srv/nfs/k8s

    # Системные настройки
    system_timezone: "Europe/Moscow"

  children:
    # Группа master нод
    masters:
      hosts:
%{ for name, instance in masters ~}
        ${instance.name}:
          ansible_host: ${instance.public_ip}
          internal_ip: ${instance.private_ip}
          node_name: ${instance.name}
%{ endfor ~}
      vars:
        node_type: master

    # Группа worker нод
    workers:
      hosts:
%{ for name, instance in workers ~}
        ${instance.name}:
          ansible_host: ${instance.public_ip}
          internal_ip: ${instance.private_ip}
          node_name: ${instance.name}
%{ endfor ~}
      vars:
        node_type: worker

    # Группа для k3s сервера (master)
    k3s_server:
      hosts:
%{ for name, instance in masters ~}
        ${instance.name}:
%{ endfor ~}

    # Группа для k3s агентов (workers)
    k3s_agent:
      hosts:
%{ for name, instance in workers ~}
        ${instance.name}:
%{ endfor ~}