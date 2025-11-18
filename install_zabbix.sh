#!/bin/bash

set -e

# Функция для вывода сообщений
log() {
    echo "[INFO] $1"
}

# Функция для вывода ошибок
error() {
    echo "[ERROR] $1" >&2
    exit 1
}

# Функция для установки админ-панели
install_admin_panel() {
    log "Запуск установки админ-панели Zabbix..."

    # Обновление списка пакетов
    log "Обновление списка пакетов..."
    apt-get update

    # Установка репозитория Zabbix
    log "Установка репозитория Zabbix..."
    wget https://repo.zabbix.com/zabbix/7.0/ubuntu/pool/main/z/zabbix-release/zabbix-release_7.0-2+ubuntu24.04_all.deb
    dpkg -i zabbix-release_7.0-2+ubuntu24.04_all.deb
    apt-get update

    # Установка компонентов Zabbix
    log "Установка Zabbix сервера, фронтенда и агента..."
    apt-get install -y zabbix-server-mysql zabbix-frontend-php zabbix-apache-conf zabbix-sql-scripts zabbix-agent

    # Установка и настройка MySQL
    log "Установка и настройка MySQL..."
    apt-get install -y mysql-server

    # Запрос пароля для базы данных
    read -sp "Пожалуйста, введите пароль для пользователя базы данных zabbix: " DB_PASSWORD
    echo

    # Создание базы данных и пользователя
    log "Создание базы данных и пользователя..."
    mysql -uroot -e "DROP DATABASE IF EXISTS zabbix;"
    mysql -uroot -e "DROP USER IF EXISTS 'zabbix'@'localhost';"
    mysql -uroot -e "create database zabbix character set utf8mb4 collate utf8mb4_bin;"
    mysql -uroot -e "create user 'zabbix'@'localhost' identified by '$DB_PASSWORD';"
    mysql -uroot -e "grant all privileges on zabbix.* to 'zabbix'@'localhost';"
    mysql -uroot -e "set global log_bin_trust_function_creators = 1;"
    mysql -uroot -e "flush privileges;"

    # Импорт начальной схемы
    log "Импорт начальной схемы базы данных..."
    zcat /usr/share/zabbix-sql-scripts/mysql/server.sql.gz | mysql --default-character-set=utf8mb4 -uzabbix -p"$DB_PASSWORD" zabbix

    # Настройка zabbix_server.conf
    log "Настройка zabbix_server.conf..."
    sed -i "s/^# DBPassword=/DBPassword=$DB_PASSWORD/" /etc/zabbix/zabbix_server.conf

    # Перезапуск и включение служб
    log "Перезапуск и включение служб..."
    systemctl restart zabbix-server zabbix-agent apache2
    systemctl enable zabbix-server zabbix-agent apache2

    # Проверка состояния служб
    log "Проверка состояния служб..."
    systemctl is-active --quiet zabbix-server && log "Zabbix сервер запущен." || error "Не удалось запустить Zabbix сервер."
    systemctl is-active --quiet apache2 && log "Apache2 запущен." || error "Не удалось запустить Apache2."

    # Проверка портов
    log "Проверка портов..."
    ss -tlnp | grep -q ':10051' && log "Порт 10051 (Zabbix сервер) прослушивается." || error "Порт 10051 не прослушивается."
    ss -tlnp | grep -q ':80' && log "Порт 80 (Apache) прослушивается." || error "Порт 80 не прослушивается."

    log "Установка админ-панели Zabbix завершена!"
    log "Пожалуйста, откройте http://<ip_вашего_сервера>/zabbix в вашем браузере, чтобы завершить настройку."
}

install_agent() {
    log "Запуск установки агента Zabbix..."

    # Проверка, установлен ли уже репозиторий
    if [ ! -f /etc/apt/sources.list.d/zabbix.list ]; then
        log "Установка репозитория Zabbix..."
        wget https://repo.zabbix.com/zabbix/7.0/ubuntu/pool/main/z/zabbix-release/zabbix-release_7.0-2+ubuntu24.04_all.deb
        dpkg -i zabbix-release_7.0-2+ubuntu24.04_all.deb
        apt-get update
    fi

    # Установка агента Zabbix
    log "Установка агента Zabbix..."
    apt-get install -y zabbix-agent

    # Запрос IP-адреса Zabbix-сервера
    read -p "Пожалуйста, введите IP-адрес или DNS-имя Zabbix-сервера: " ZABBIX_SERVER_IP

    # Настройка zabbix_agentd.conf
    log "Настройка zabbix_agentd.conf..."
    sed -i "s/^Server=127.0.0.1/Server=$ZABBIX_SERVER_IP/" /etc/zabbix/zabbix_agentd.conf
    sed -i "s/^ServerActive=127.0.0.1/ServerActive=$ZABBIX_SERVER_IP/" /etc/zabbix/zabbix_agentd.conf

    # Перезапуск и включение службы агента
    log "Перезапуск и включение службы агента Zabbix..."
    systemctl restart zabbix-agent
    systemctl enable zabbix-agent

    # Проверка состояния службы
    log "Проверка состояния службы агента..."
    systemctl is-active --quiet zabbix-agent && log "Zabbix агент запущен." || error "Не удалось запустить Zabbix агент."

    # Проверка порта
    log "Проверка порта агента..."
    ss -tlnp | grep -q ':10050' && log "Порт 10050 (Zabbix агент) прослушивается." || error "Порт 10050 не прослушивается."

    log "Установка агента Zabbix завершена!"
}

# Основная функция
main() {
    # Проверка прав суперпользователя
    if [ "$EUID" -ne 0 ]; then
        error "Пожалуйста, запустите скрипт с правами суперпользователя (root)."
    fi

    log "Добро пожаловать в установщик Zabbix!"
    log "Этот скрипт поможет вам установить и настроить Zabbix."

    PS3="Пожалуйста, выберите режим установки: "
    options=("Админ-панель + Агент" "Только админ-панель" "Только агент" "Выход")
    select opt in "${options[@]}"; do
        case $opt in
        "Админ-панель + Агент")
            log "Выбран режим: Админ-панель + Агент"
            install_admin_panel
            install_agent
            break
            ;;
        "Только админ-панель")
            log "Выбран режим: Только админ-панель"
            install_admin_panel
            break
            ;;
        "Только агент")
            log "Выбран режим: Только агент"
            install_agent
            break
            ;;
        "Выход")
            break
            ;;
        *)
            echo "Неверный выбор. Пожалуйста, попробуйте снова."
            ;;
        esac
    done

    log "Установка Zabbix завершена!"
}

# Запуск основной функции
main
