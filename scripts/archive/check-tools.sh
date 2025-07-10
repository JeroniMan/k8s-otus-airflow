#!/bin/bash
# scripts/check-tools.sh
# Проверка установленных инструментов

# Цвета
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "================================================"
echo "     Проверка установленных инструментов"
echo "================================================"
echo ""

# Функция проверки
check_tool() {
    local tool=$1
    local required_version=$2

    if command -v "$tool" &> /dev/null; then
        local version=$($tool --version 2>&1 | head -1)
        echo -e "${GREEN}[✓]${NC} $tool: $version"
        return 0
    else
        echo -e "${RED}[✗]${NC} $tool: НЕ УСТАНОВЛЕН (требуется $required_version)"
        return 1
    fi
}

# Проверка версии
check_version() {
    local tool=$1
    local command=$2

    if command -v "$tool" &> /dev/null; then
        local version=$(eval "$command" 2>&1)
        echo -e "${GREEN}[✓]${NC} $tool: $version"
        return 0
    else
        echo -e "${RED}[✗]${NC} $tool: НЕ УСТАНОВЛЕН"
        return 1
    fi
}

# Счетчик ошибок
errors=0

# Основные инструменты
echo "Основные инструменты:"
echo "--------------------"
check_tool "git" "любая" || ((errors++))
check_tool "make" "любая" || ((errors++))
check_tool "jq" "любая" || ((errors++))
check_tool "curl" "любая" || ((errors++))
check_tool "wget" "любая" || ((errors++))

echo ""
echo "Инструменты развертывания:"
echo "--------------------------"
check_version "terraform" "terraform version | head -1" || ((errors++))
check_version "ansible" "ansible --version | head -1" || ((errors++))
check_version "kubectl" "kubectl version --client --short 2>/dev/null || kubectl version --client | grep 'Client Version'" || ((errors++))
check_version "helm" "helm version --short" || ((errors++))

echo ""
echo "Cloud CLI:"
echo "----------"
check_version "yc" "yc version" || ((errors++))

# Проверка Yandex Cloud конфигурации
echo ""
echo "Конфигурация Yandex Cloud:"
echo "--------------------------"
if command -v yc &> /dev/null; then
    if yc config list &> /dev/null; then
        echo -e "${GREEN}[✓]${NC} Yandex Cloud настроен"
        yc config list | grep -E "cloud-id|folder-id" | sed 's/^/  /'
    else
        echo -e "${YELLOW}[!]${NC} Yandex Cloud не настроен. Выполните: yc init"
        ((errors++))
    fi
else
    echo -e "${RED}[✗]${NC} Yandex Cloud CLI не установлен"
fi

# Проверка SSH ключей
echo ""
echo "SSH ключи:"
echo "----------"
if [ -f ~/.ssh/k8s-airflow ] && [ -f ~/.ssh/k8s-airflow.pub ]; then
    echo -e "${GREEN}[✓]${NC} SSH ключи найдены: ~/.ssh/k8s-airflow"
else
    echo -e "${YELLOW}[!]${NC} SSH ключи не найдены"
    echo "  Выполните: ssh-keygen -t rsa -b 4096 -f ~/.ssh/k8s-airflow -N ''"
    ((errors++))
fi

# Проверка Python
echo ""
echo "Python:"
echo "-------"
if command -v python3 &> /dev/null; then
    version=$(python3 --version)
    echo -e "${GREEN}[✓]${NC} Python3: $version"

    # Проверка модулей
    if python3 -c "import cryptography" 2>/dev/null; then
        echo -e "${GREEN}[✓]${NC} cryptography модуль установлен"
    else
        echo -e "${YELLOW}[!]${NC} cryptography модуль не установлен"
        echo "  Выполните: pip3 install cryptography"
    fi
else
    echo -e "${RED}[✗]${NC} Python3 не установлен"
    ((errors++))
fi

# Итог
echo ""
echo "================================================"
if [ $errors -eq 0 ]; then
    echo -e "${GREEN}Все инструменты установлены и настроены!${NC}"
    echo ""
    echo "Можете приступать к развертыванию:"
    echo "  make deploy-all"
else
    echo -e "${RED}Обнаружено проблем: $errors${NC}"
    echo ""
    echo "Установите недостающие инструменты:"
    echo "  ./scripts/setup-tools.sh"
fi
echo "================================================"

exit $errors