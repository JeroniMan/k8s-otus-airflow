#!/bin/bash
# scripts/cleanup.sh
# Очистка временных файлов и ресурсов

# Цвета
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "================================================"
echo "     Очистка временных файлов"
echo "================================================"
echo ""

# Подтверждение
echo -e "${YELLOW}Внимание!${NC} Это удалит:"
echo "- Временные файлы (.tmp, .bak, .log)"
echo "- Python кэш (__pycache__)"
echo "- Terraform планы"
echo ""
read -p "Продолжить? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Отменено"
    exit 0
fi

echo ""
echo "Очистка..."

# Временные файлы
echo -n "Удаление временных файлов... "
find . -type f \( -name "*.tmp" -o -name "*.bak" -o -name "*.swp" -o -name "*.swo" \) -delete
echo -e "${GREEN}[✓]${NC}"

# Логи (кроме директории logs)
echo -n "Удаление старых логов... "
find . -type f -name "*.log" -not -path "./logs/*" -delete
echo -e "${GREEN}[✓]${NC}"

# Python cache
echo -n "Удаление Python кэша... "
find . -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
find . -type d -name ".pytest_cache" -exec rm -rf {} + 2>/dev/null || true
find . -type f -name "*.pyc" -delete
echo -e "${GREEN}[✓]${NC}"

# Terraform
echo -n "Удаление Terraform временных файлов... "
find . -type f -name "*.tfplan" -delete
find . -type f -name "tfplan" -delete
find . -type d -name ".terraform" -exec rm -rf {} + 2>/dev/null || true
echo -e "${GREEN}[✓]${NC}"

# Ansible
echo -n "Удаление Ansible временных файлов... "
find . -type f -name "*.retry" -delete
rm -rf /tmp/ansible_* 2>/dev/null || true
echo -e "${GREEN}[✓]${NC}"

# Старые бэкапы (старше 30 дней)
if [ -d "backups" ]; then
    echo -n "Удаление старых бэкапов (>30 дней)... "
    find backups -type f -name "*.tar.gz" -mtime +30 -delete 2>/dev/null || true
    find backups -type d -empty -delete 2>/dev/null || true
    echo -e "${GREEN}[✓]${NC}"
fi

# Подсчет освобожденного места
echo ""
echo "================================================"
echo -e "${GREEN}Очистка завершена!${NC}"
echo "================================================"