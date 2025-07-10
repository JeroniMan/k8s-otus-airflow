# Terraform конфигурация для Kubernetes кластера

Эта директория содержит Terraform конфигурацию для создания инфраструктуры Kubernetes кластера в Yandex Cloud.

## 📋 Что создается

- **Сеть и подсеть** для изоляции кластера
- **Security Group** с правилами для Kubernetes
- **Виртуальные машины**:
  - 1 Master нода (control plane)
  - 2 Worker ноды (для рабочей нагрузки)
- **Load Balancer** для доступа к сервисам
- **Ansible Inventory** генерируется автоматически

## 🚀 Быстрый старт

### 1. Подготовка

```bash
# Создайте SSH ключи
ssh-keygen -t rsa -b 4096 -f ~/.ssh/k8s-airflow -N ""

# Скопируйте пример конфигурации
cp terraform.tfvars terraform.tfvars

# Отредактируйте terraform.tfvars своими значениями
nano terraform.tfvars
```

### 2. Инициализация

```bash
# Инициализация Terraform
terraform init

# Проверка конфигурации
terraform validate

# Просмотр плана
terraform plan
```

### 3. Создание инфраструктуры

```bash
# Применение конфигурации
terraform apply

# Или без подтверждения
terraform apply -auto-approve
```

### 4. Получение информации

```bash
# Показать все outputs
terraform output

# Получить IP адрес Load Balancer
terraform output -raw load_balancer_ip

# Получить команду для SSH на master
terraform output -raw ssh_master_command
```

### 5. Удаление инфраструктуры

```bash
# ВАЖНО: Это удалит все ресурсы!
terraform destroy
```

## 💰 Оценка стоимости

### Минимальная конфигурация (по умолчанию):
- 3 прерываемые VM (50% CPU)
- HDD диски
- **~70-100 руб/день**

### Production конфигурация:
- 3+ непрерываемые VM (100% CPU)
- SSD диски
- **~300-500 руб/день**

## 🔧 Основные переменные

| Переменная | Описание | По умолчанию |
|------------|----------|--------------|
| `yc_cloud_id` | ID облака в Yandex Cloud | обязательно |
| `yc_folder_id` | ID каталога в Yandex Cloud | обязательно |
| `master_count` | Количество master нод | 1 |
| `worker_count` | Количество worker нод | 2 |
| `preemptible` | Использовать прерываемые VM | true |
| `core_fraction` | Процент производительности CPU | 50 |

## 📁 Структура файлов

```
terraform/
├── main.tf               # Основная конфигурация
├── variables.tf          # Определение переменных
├── outputs.tf            # Выходные данные
├── cloud-init.yaml       # Начальная настройка VM
├── terraform.tfvars.example  # Пример переменных
├── templates/
│   └── inventory.tpl     # Шаблон для Ansible
└── README.md            # Этот файл
```

## 🛠️ Полезные команды

```bash
# Форматирование кода
terraform fmt -recursive

# Обновление провайдеров
terraform init -upgrade

# Детальный план с сохранением
terraform plan -out=tfplan

# Применение сохраненного плана
terraform apply tfplan

# Показать текущее состояние
terraform show

# Обновить outputs
terraform refresh
```

## ⚠️ Важные замечания

1. **SSH ключи** должны быть созданы ДО запуска Terraform
2. **S3 bucket** для state должен существовать
3. **Прерываемые VM** могут быть остановлены Yandex Cloud в любой момент
4. **Security Group** по умолчанию открыта для всех IP (измените в продакшене!)

## 🆘 Решение проблем

### Ошибка с S3 backend
```bash
# Создайте bucket вручную
yc storage bucket create --name tfstate-k8s-airflow-unique-name
```

### Ошибка с SSH ключами
```bash
# Проверьте путь к ключам
ls -la ~/.ssh/k8s-airflow*

# Проверьте права
chmod 600 ~/.ssh/k8s-airflow
chmod 644 ~/.ssh/k8s-airflow.pub
```

### Превышение квот
- Попробуйте другую зону: `ru-central1-b` или `ru-central1-c`
- Уменьшите количество ресурсов
- Обратитесь в поддержку для увеличения квот