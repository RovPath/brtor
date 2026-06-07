#!/bin/bash

# ================================================================
#  brtor v1.9.6 — мультиаккаунтный комбайн: профили + VPN + Tor
#  (Универсальная версия: Linux + macOS Compatible)
# ================================================================

CONFIG_FILE="$HOME/.config/brtor/config.conf"
PROFILE_BASE_DIR="$HOME/.local/share/brtor_profiles"
PROFILES_LIST_FILE="$HOME/.config/brtor/profiles.list"
BACKUP_DIR="$HOME/brtor_backups"

# --- Определение ОС ---------------------------------------------
IS_MAC=false
[[ "$OSTYPE" == "darwin"* ]] && IS_MAC=true

# --- Цвета (ANSI Escape Sequences) -------------------------------
G='\033[1;32m'     # Зелёный
B='\033[1;34m'     # Синий
C='\033[1;36m'     # Циан
R='\033[1;31m'     # Красный
Y='\033[1;33m'     # Жёлтый
M='\033[1;35m'     # Фиолетовый
P='\033[38;5;141m' # Tor-фиолетовый
D='\033[2m'        # Тусклый (Dim)
W='\033[1m'        # Жирный (Bold)
N='\033[0m'        # Сброс (Reset)

# --- Дефолтные параметры конфигурации ----------------------------
DEFAULT_BROWSER="qutebrowser"
VPN_PORT="10808"
TOR_PORT="9050"
TOR_ENABLED="false"

# ================================================================
#  ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ И ПРОВЕРКИ
# ================================================================
load_config() {
    [ -f "$CONFIG_FILE" ] && source "$CONFIG_FILE"
}

save_config() {
    mkdir -p "$(dirname "$CONFIG_FILE")"
    cat > "$CONFIG_FILE" <<EOF
DEFAULT_BROWSER="$DEFAULT_BROWSER"
VPN_PORT="$VPN_PORT"
TOR_PORT="$TOR_PORT"
TOR_ENABLED="$TOR_ENABLED"
EOF
}

check_dependencies() {
    local missing=()
    local cmd
    local deps=(tar awk cut head xargs mkdir mktemp grep sudo nohup date)

    if [ "$IS_MAC" = "true" ]; then
        deps+=(lsof)
    else
        deps+=(ss systemctl)
    fi

    for cmd in "${deps[@]}"; do
        command -v "$cmd" &>/dev/null || missing+=("$cmd")
    done
    if [ ${#missing[@]} -gt 0 ]; then
        echo -e "${R}[Ошибка] В системе отсутствуют критически важные утилиты: ${missing[*]}${N}"
        echo -e "${Y}Пожалуйста, установите их перед запуском brtor.${N}"
        exit 1
    fi
}

find_browser_binary() {
    local b="$1"
    if [ "$IS_MAC" = "true" ]; then
        case "$b" in
            qutebrowser) [ -f "/Applications/qutebrowser.app/Contents/MacOS/qutebrowser" ] && { echo "/Applications/qutebrowser.app/Contents/MacOS/qutebrowser"; return; } ;;
            chrome|google-chrome|google-chrome-stable) [ -f "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" ] && { echo "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"; return; } ;;
            brave|brave-browser) [ -f "/Applications/Brave Browser.app/Contents/MacOS/Brave Browser" ] && { echo "/Applications/Brave Browser.app/Contents/MacOS/Brave Browser"; return; } ;;
            chromium) [ -f "/Applications/Chromium.app/Contents/MacOS/Chromium" ] && { echo "/Applications/Chromium.app/Contents/MacOS/Chromium"; return; } ;;
            firefox) [ -f "/Applications/Firefox.app/Contents/MacOS/Firefox" ] && { echo "/Applications/Firefox.app/Contents/MacOS/Firefox"; return; } ;;
        esac
    fi
    command -v "$b" &>/dev/null && { echo "$b"; return; }
    echo ""
}

profile_name_exists() {
    local search_name="$1"
    local name
    for name in "${profiles_names[@]}"; do
        if [ "$name" = "$search_name" ]; then
            return 0
        fi
    done
    return 1
}

# ================================================================
#  АВТОНАСТРОЙКА (ПЕРВЫЙ ЗАПУСК)
# ================================================================
check_and_autoconfig() {
    if [ ! -f "$CONFIG_FILE" ]; then
        clear
        sep
        hdr "ПЕРВЫЙ ЗАПУСК: ИНИЦИАЛИЗАЦИЯ И АВТОНАСТРОЙКА v1.9.5"
        sep
        echo ""
        echo -e "  ${Y}[Инфо] Конфигурационный файл не найден. Система готова к работе.${N}"
        echo -e "  Мастер настройки может выполнить сканирование среды для оптимизации."
        echo ""
        mi "1" "Запустить автоматическую настройку (Рекомендуется)" "$G"
        mi "2" "Продолжить с ручной настройкой параметров (Вручную)" "$D"
        echo ""
        sep_dim
        echo -ne "  Ваш выбор [1]: "
        read -r first_choice
        first_choice="${first_choice:-1}"

        if [ "$first_choice" = "1" ]; then
            echo -e "\n  ${C}[*] Сканирование доступных в системе браузеров...${N}"
            local found_browser=""
            local b bin
            for b in qutebrowser brave-browser brave chromium google-chrome-stable google-chrome firefox chrome; do
                bin=$(find_browser_binary "$b")
                if [ -n "$bin" ]; then
                    DEFAULT_BROWSER="$bin"
                    found_browser="$b"
                    break
                fi
            done

            if [ -n "$found_browser" ]; then
                echo -e "      - Обнаружен и успешно выбран: ${G}$found_browser${N}"
            else
                echo -e "      - ${Y}[Внимание] Поддерживаемые браузеры не найдены. Установлен по умолчанию: qutebrowser${N}"
            fi

            echo -e "  ${C}[*] Резервирование стандартных сетевых портов...${N}"
            echo -e "      - Сетевой порт VPN зафиксирован: ${G}$VPN_PORT${N}"
            echo -e "      - Сетевой порт Tor зафиксирован: ${G}$TOR_PORT${N}"
            save_config
            echo -e "\n  ${G}[Успешно] Автоматическая настройка завершена! Конфигурация сохранена.${N}"
            echo -ne "  Нажмите Enter, чтобы войти в главное меню... "
            read -r
        elif [ "$first_choice" = "2" ]; then
            echo -e "\n  ${C}[*] Сканирование установленных браузеров...${N}"
            local avail_browsers=()
            local b bin
            for b in qutebrowser brave-browser brave chromium google-chrome-stable google-chrome firefox chrome; do
                bin=$(find_browser_binary "$b")
                [ -n "$bin" ] && avail_browsers+=("$b")
            done

            if [ ${#avail_browsers[@]} -gt 0 ]; then
                echo -e "  Найденные браузеры в вашей системе:\n"
                local idx=1
                for b in "${avail_browsers[@]}"; do
                    mi "$idx" "$b" "$G"
                    idx=$((idx + 1))
                done
                mi "d" "Использовать по умолчанию ($DEFAULT_BROWSER)" "$D"
                echo ""
                echo -ne "  Выберите браузер из списка [d]: "
                read -r b_choice
                if [[ "$b_choice" =~ ^[0-9]+$ ]] && [ "$b_choice" -le "${#avail_browsers[@]}" ] && [ "$b_choice" -gt 0 ]; then
                    local selected_name="${avail_browsers[$((b_choice-1))]}"
                    DEFAULT_BROWSER=$(find_browser_binary "$selected_name")
                    echo -e "      - Выбран браузер: ${G}$selected_name${N}"
                else
                    echo -e "      - Оставлен вариант по умолчанию: ${G}$DEFAULT_BROWSER${N}"
                fi
            else
                echo -e "  ${Y}[Внимание] Доступные браузеры не обнаружены. Установлен: $DEFAULT_BROWSER${N}"
            fi

            echo -e "\n  ${C}[*] Резервирование портов...${N}"
            echo -e "      - Настроен порт VPN: ${G}$VPN_PORT${N}"
            echo -e "      - Настроен порт Tor: ${G}$TOR_PORT${N}"
            save_config
            echo -e "\n  ${G}[Успешно] Конфигурация сохранена.${N}"
            sleep 1.5
        else
            save_config
            echo -e "\n  ${D}[Инфо] Применены стандартные фабричные параметры.${N}"
            sleep 1
        fi
    fi
}

# ================================================================
#  ПРОФИЛИ   Формат структуры базы: id|Название|vpn(true/false)|url
# ================================================================
init_profiles() {
    mkdir -p "$PROFILE_BASE_DIR"
    mkdir -p "$BACKUP_DIR"
    mkdir -p "$(dirname "$PROFILES_LIST_FILE")"
    if [ ! -f "$PROFILES_LIST_FILE" ]; then
        echo "acc_main|Основной аккаунт|false|https://claude.ai" > "$PROFILES_LIST_FILE"
    fi
}

load_profiles() {
    profiles_ids=()
    profiles_names=()
    profiles_proxy=()
    profiles_urls=()

    [ -f "$PROFILES_LIST_FILE" ] || return 0

    local pid pname pproxy purl
    while IFS='|' read -r pid pname pproxy purl || [ -n "$pid" ]; do
        pid=$(echo "$pid" | tr -d '\r' | xargs 2>/dev/null)

        if [[ -z "$pid" || "$pid" == \#* ]]; then
            continue
        fi

        profiles_ids+=("$pid")
        profiles_names+=("$pname")
        profiles_proxy+=("$pproxy")
        profiles_urls+=("$purl")
    done < "$PROFILES_LIST_FILE"
}

save_profiles() {
    local tmp k
    tmp="$(mktemp)"
    for k in "${!profiles_ids[@]}"; do
        printf '%s|%s|%s|%s\n' \
            "${profiles_ids[$k]}" "${profiles_names[$k]}" \
            "${profiles_proxy[$k]}" "${profiles_urls[$k]}"
    done > "$tmp"
    mv "$tmp" "$PROFILES_LIST_FILE"
}

generate_id() {
    printf 'acc_%s%04d' "$(date +%s)" "$(( ${SRANDOM:-$RANDOM} % 10000 ))"
}

# ================================================================
#  TOR MODULE
# ================================================================
tor_port_open() {
    if [ "$IS_MAC" = "true" ]; then
        lsof -i :"${TOR_PORT}" -sTCP:LISTEN &>/dev/null
    else
        ss -tuln 2>/dev/null | grep -q ":${TOR_PORT} "
    fi
}

tor_service_active() {
    if [ "$IS_MAC" = "true" ]; then
        pgrep -x tor &>/dev/null
    else
        systemctl is-active --quiet tor 2>/dev/null
    fi
}

get_tor_status() {
    if [ "$TOR_ENABLED" = "true" ]; then
        if tor_port_open; then
            TOR_STATUS_TEXT="Включен  (порт ${TOR_PORT})"
            TOR_STATUS_COL="$P"
        else
            TOR_STATUS_TEXT="Включен  (порт $TOR_PORT недоступен!)"
            TOR_STATUS_COL="$R"
        fi
    else
        TOR_STATUS_TEXT="Выключен"
        TOR_STATUS_COL="$D"
    fi
}

toggle_tor() {
    if [ "$TOR_ENABLED" = "true" ]; then
        TOR_ENABLED="false"
        save_config
        echo -e "\n${D}  Режим Tor отключен.${N}"
        echo -ne "  Остановить системную службу tor? (yes/NO): "
        read -r ans
        if [ "$ans" = "yes" ]; then
            echo -e "${Y}  Останавливаю службу tor...${N}"
            if [ "$IS_MAC" = "true" ]; then
                if command -v brew &>/dev/null && brew services list | grep -q tor; then
                    brew services stop tor 2>/dev/null
                else
                    killall tor 2>/dev/null
                fi
            else
                sudo systemctl stop tor 2>/dev/null
            fi
            echo -e "${G}  [Успешно] Служба Tor остановлена.${N}"
        fi
    else
        if ! tor_port_open; then
            if tor_service_active; then
                echo -e "${Y}  [Внимание] Служба tor active, но порт $TOR_PORT не отвечает.${N}"
                sleep 2
                return
            fi

            echo -e "${Y}  Запускаю службу tor...${N}"

            if [ "$IS_MAC" = "true" ]; then
                if command -v brew &>/dev/null; then
                    brew services start tor 2>/dev/null
                else
                    tor --runasdaemon 1 2>/dev/null
                fi
            else
                sudo systemctl start tor 2>/dev/null
            fi

            if [ $? -ne 0 ] && ! tor_port_open; then
                echo -e "${R}  [Ошибка] Не удалось запустить службу tor${N}"
                sleep 2
                return
            fi
            local i
            for i in {1..8}; do
                sleep 1
                tor_port_open && break
            done
        fi

        if tor_port_open; then
            TOR_ENABLED="true"
            save_config
            echo -e "\n${P}  [Успешно] Режим Tor активирован. Трафик направлен на 127.0.0.1:${TOR_PORT}${N}"
            echo -e "${D}  Сайты в зоне .onion теперь доступны для просмотра${N}"
        else
            # ИСПРАВЛЕНИЕ 2: убран китайский иероглиф 端口, заменён на русское слово "порта"
            echo -e "${R}  [Ошибка] Процесс Tor не начал прослушивание порта $TOR_PORT после запуска.${N}"
        fi
    fi
    sleep 1.5
}

# ================================================================
#  VPN MODULE
# ================================================================
get_vpn_ip() {
    if [ "$IS_MAC" = "true" ]; then
        if ! lsof -i :"${VPN_PORT}" -sTCP:LISTEN &>/dev/null; then
            echo -e "${R}  [Ошибка] Сетевой порт VPN ($VPN_PORT) не обнаружен.${N}" >&2
            return 1
        fi
        echo "127.0.0.1"
    else
        if ! ss -tuln 2>/dev/null | grep -q ":${VPN_PORT} "; then
            echo -e "${R}  [Ошибка] Сетевой порт VPN ($VPN_PORT) не обнаружен.${N}" >&2
            return 1
        fi
        local full_addr ip
        full_addr="$(ss -tuln 2>/dev/null | awk -v p=":${VPN_PORT}" '$5 ~ p {print $5; exit}')"
        ip="${full_addr%:*}"
        ip="${ip//[\[\]]/}"

        case "$ip" in
            ""|"*"|"0.0.0.0"|"[::]"|"::") echo "127.0.0.1" ;;
            "[::1]"|"::1")                 echo "127.0.0.1" ;;
            *)                             echo "$ip" ;;
        # ИСПРАВЛЕНИЕ 1: </ac заменён на корректный esac
        esac
    fi
}

# ================================================================
#  LAUNCH BROWSER
# ================================================================
launch_browser() {
    local pid="$1" use_proxy="$2" url="$3"
    local prof_dir="$PROFILE_BASE_DIR/$pid"
    mkdir -p "$prof_dir"

    local proxy_host="" proxy_port="" proxy_cmd=""
    local browser_pid=""

    if [ "$TOR_ENABLED" = "true" ]; then
        if [ "$use_proxy" = "true" ]; then
            if tor_port_open; then
                proxy_host="127.0.0.1"
                proxy_port="${TOR_PORT}"
                proxy_cmd="socks5://${proxy_host}:${proxy_port}"
                echo -e "${P}  [Tor] ${proxy_host}:${proxy_port}${N}"
            else
                echo -e "${R}  [Ошибка] Режим Tor включен, но порт $TOR_PORT недоступен. Запуск напрямую (Direct).${N}"
            fi
        else
            echo -e "${D}  [Инфо] Прямое подключение (Режим DIRECT игнорирует глобальный Tor)${N}"
        fi
    elif [ "$use_proxy" = "true" ]; then
        local vip
        if vip="$(get_vpn_ip 2>/dev/null)" && [ -n "$vip" ]; then
            proxy_host="$vip"
            proxy_port="${VPN_PORT}"
            proxy_cmd="socks5://${proxy_host}:${proxy_port}"
            echo -e "${G}  [VPN] ${proxy_host}:${proxy_port}${N}"
        else
            echo -e "${Y}  [Инфо] Прокси-сервер VPN недоступен — запуск напрямую (Direct)${N}"
        fi
    else
        echo -e "${D}  [Инфо] Прямое подключение (Direct)${N}"
    fi

    if [ -n "$proxy_host" ]; then
        echo -e "${D}  [Инфо] Стабилизация сетевого окружения прокси...${N}"
        sleep 0.4
    fi

    echo -e "${C}  [>] Открытие браузера (профиль: $pid)${N}"
    local qute_proxy="${proxy_cmd/socks5:\/\//socks://}"
    local log_file="$prof_dir/session.log"

    echo "=== Запуск сессии: $(date) ===" > "$log_file"

    case "$DEFAULT_BROWSER" in
        *qutebrowser*)
            if [ -n "$proxy_cmd" ]; then
                nohup "$DEFAULT_BROWSER" -s content.proxy "$qute_proxy" --basedir "$prof_dir" --target window "$url" < /dev/null >> "$log_file" 2>&1 &
                browser_pid=$!
                disown $browser_pid
            else
                nohup "$DEFAULT_BROWSER" --basedir "$prof_dir" --target window "$url" < /dev/null >> "$log_file" 2>&1 &
                browser_pid=$!
                disown $browser_pid
            fi ;;
        *chromium*|*brave*|*chrome*|*Google\ Chrome*)
            local chrome_flags=(
                "--user-data-dir=$prof_dir"
                "--disable-blink-features=AutomationControlled"
                "--force-webrtc-ip-handling-policy=disable_non_proxied_udp"
                "--no-first-run"
                "--password-store=basic"
                "--disable-component-update"
                "--enable-logging=stderr"
                "--v=1"
            )
            if [ -n "$proxy_cmd" ]; then
                chrome_flags+=("--proxy-server=$proxy_cmd")
            fi
            nohup "$DEFAULT_BROWSER" "${chrome_flags[@]}" "$url" < /dev/null >> "$log_file" 2>&1 &
            browser_pid=$!
            disown $browser_pid
            ;;
        *firefox*|*Firefox*)
            local user_js="$prof_dir/user.js"
            if [ -n "$proxy_host" ]; then
                cat > "$user_js" <<EOF
user_pref("network.proxy.type", 1);
user_pref("network.proxy.socks", "$proxy_host");
user_pref("network.proxy.socks_port", $proxy_port);
user_pref("network.proxy.socks_version", 5);
user_pref("network.proxy.socks_remote_dns", true);
user_pref("privacy.resistFingerprinting", true);
user_pref("layout.css.font-visibility.level", 1);
user_pref("privacy.trackingprotection.fingerprinting.annotate.enabled", true);
user_pref("media.peerconnection.enabled", false);
EOF
            else
                cat > "$user_js" <<EOF
user_pref("network.proxy.type", 0);
user_pref("privacy.resistFingerprinting", true);
user_pref("layout.css.font-visibility.level", 1);
user_pref("media.peerconnection.enabled", false);
EOF
            fi
            nohup "$DEFAULT_BROWSER" --profile "$prof_dir" --no-remote "$url" < /dev/null >> "$log_file" 2>&1 &
            browser_pid=$!
            disown $browser_pid
            ;;
        *)
            echo -e "${Y}  [Инфо] Браузер '$DEFAULT_BROWSER': полная изоляция и автоматический прокси не гарантируются${N}"
            nohup "$DEFAULT_BROWSER" "$url" < /dev/null >> "$log_file" 2>&1 &
            browser_pid=$!
            disown $browser_pid
            ;;
    esac
    echo -e "${D}  Идентификатор процесса (PID): $browser_pid${N}"
    echo -e "${D}  Журнал событий записывается в: $log_file${N}"
}

# ================================================================
#  ПРОСМОТР ЛОГОВ СЕССИЙ
# ================================================================
menu_view_logs() {
    load_profiles
    if [ ${#profiles_ids[@]} -eq 0 ]; then
        echo -e "${R}  [Ошибка] Нет созданных профилей для анализа журналов.${N}"
        sleep 1
        return
    fi

    clear
    sep
    hdr "ПРОСМОТР ЛОГОВ БРАУЗЕРА"
    sep
    echo ""
    local i
    for i in "${!profiles_ids[@]}"; do
        printf "  ${Y}%2s)${N}  %s  ${D}(%s)${N}\n" "$((i+1))" "${profiles_names[$i]}" "${profiles_ids[$i]}"
    done
    echo ""
    echo -ne "  Выберите профиль для чтения логов (Enter для отмены): "
    read -r sel
    [ -z "$sel" ] && return

    if [[ "$sel" =~ ^[0-9]+$ ]]; then
        local idx=$(( sel - 1 ))
        if [ "$idx" -ge 0 ] && [ "$idx" -lt "${#profiles_ids[@]}" ]; then
            local log_path="$PROFILE_BASE_DIR/${profiles_ids[$idx]}/session.log"
            clear
            sep
            hdr "Последние события: ${profiles_names[$idx]}"
            sep
            echo ""
            if [ -f "$log_path" ]; then
                tail -n 40 "$log_path"
            else
                echo -e "${Y}  [Инфо] Файл журнала пуст или еще не создан. Запустите браузер данного профиля.${N}"
            fi
            echo ""
            sep
            echo -ne "\n  ${D}Нажмите Enter, чтобы вернуться в меню...${N}"
            read -r
        else
            echo -e "${R}  [Ошибка] Указан неверный номер профиля.${N}"
            sleep 1
        fi
    fi
}

# ================================================================
#  ИМПОРТ / ЭКСПОРТ (МЕНЕДЖЕР БЭКАПОВ)
# ================================================================
menu_backup_manager() {
    while true; do
        clear
        sep
        hdr "МЕНЕДЖЕР РЕЗЕРВНЫХ КОПИЙ И ИМПОРТА v1.9.5"
        sep
        echo -e "  ${D}Каталог хранения копий:${N}"
        echo -e "  ${C}$BACKUP_DIR${N}\n"

        mi "1" "Экспортировать один выбранный профиль"
        mi "2" "Экспортировать группу (полный бэкап всей системы)" "$G"
        sep_dim
        mi "3" "Импортировать один профиль из файла резервной копии"
        mi "4" "Импортировать группу (полное восстановление базы данных)" "$Y"
        sep_dim
        mi "b" "Вернуться в главное меню" "$R"
        echo ""
        echo -ne "  Ваш выбор: "
        read -r bc

        case "$bc" in
            1)
                load_profiles
                if [ ${#profiles_ids[@]} -eq 0 ]; then
                    echo -e "${R}  [Ошибка] Нет профилей для выполнения экспорта.${N}"
                    sleep 1
                    continue
                fi
                echo -e "\n  Выберите профиль для архивации:"
                local i
                for i in "${!profiles_ids[@]}"; do
                    printf "  ${Y}%2s)${N}  %s\n" "$((i+1))" "${profiles_names[$i]}"
                done
                echo -ne "\n  Номер профиля (Enter для отмены): "
                read -r b_sel
                [ -z "$b_sel" ] && continue

                if [[ "$b_sel" =~ ^[0-9]+$ ]]; then
                    local b_idx=$((b_sel - 1))
                    if [ "$b_idx" -ge 0 ] && [ "$b_idx" -lt "${#profiles_ids[@]}" ]; then
                        local p_id="${profiles_ids[$b_idx]}"
                        echo -ne "  Введите имя файла архива (без .tar.gz) [Enter для авто-имени]: "
                        read -r custom_name

                        local target_archive
                        if [ -n "$custom_name" ]; then
                            target_archive="$BACKUP_DIR/${custom_name}.tar.gz"
                        else
                            target_archive="$BACKUP_DIR/${p_id}_backup_$(date +%s).tar.gz"
                        fi

                        echo -e "${Y}  Выполняется упаковка сессии и файлов профиля...${N}"
                        tar -czf "$target_archive" -C "$PROFILE_BASE_DIR" "$p_id"
                        echo -e "${G}  [Успешно] Резервная копия сохранена в: $target_archive${N}"
                    else
                        echo -e "${R}  [Ошибка] Указан неверный номер.${N}"
                    fi
                fi
                sleep 2.5 ;;
            2)
                local full_archive="$BACKUP_DIR/brtor_FULL_GROUP_BACKUP_$(date +%Y%m%d_%H%M%S).tar.gz"
                echo -e "${Y}  Запущена пакетная групповая архивация всей среды данных...${N}"
                tar -czf "$full_archive" -C "$HOME" ".local/share/brtor_profiles" ".config/brtor" 2>/dev/null
                echo -e "${G}  [Успешно] Группа профилей и конфигурационные файлы сохранены!${N}"
                echo -e "            Файл бэкапа: $full_archive"
                sleep 3.5 ;;
            3)
                echo -e "\n  Укажите полный путь к файлу .tar.gz одиночного профиля:"
                echo -ne "  Путь к файлу (Enter для отмены): "
                read -r import_path
                [ -z "$import_path" ] && continue

                if [ -f "$import_path" ]; then
                    echo -ne "  Введите имя для импортируемого профиля: "
                    read -r imp_name
                    [ -z "$imp_name" ] && imp_name="Импортированная сессия"

                    load_profiles
                    if profile_name_exists "$imp_name"; then
                        echo -e "${Y}  [Предупреждение] Профиль с именем «$imp_name» уже существует!${N}"
                        echo -ne "  Вы хотите продолжить и создать дубликат имени? (yes/NO): "
                        read -r name_conf
                        if [ "$name_conf" != "yes" ]; then
                            echo -e "${D}  Операция отменена.${N}"
                            sleep 1.5
                            continue
                        fi
                    fi

                    local imp_id
                    imp_id="$(generate_id)"
                    local tmp_extract
                    tmp_extract="$(mktemp -d)"
                    tar -xzf "$import_path" -C "$tmp_extract"

                    local extracted_dir
                    extracted_dir="$(find "$tmp_extract" -mindepth 1 -maxdepth 1 -type d | head -n1)"

                    if [ -n "$extracted_dir" ]; then
                        mv "$extracted_dir" "$PROFILE_BASE_DIR/$imp_id"
                        profiles_ids+=("$imp_id")
                        profiles_names+=("$imp_name")
                        profiles_proxy+=("true")
                        profiles_urls+=("https://claude.ai")
                        save_profiles
                        echo -e "${G}  [Успешно] Профиль успешно интегрирован под именем «$imp_name»!${N}"
                    else
                        echo -e "${R}  [Ошибка] Структура архива повреждена или пуста.${N}"
                    fi
                    rm -rf "$tmp_extract"
                else
                    echo -e "${R}  [Ошибка] Указанный файл резервной копии не найден.${N}"
                fi
                sleep 2.5 ;;
            4)
                echo -e "\n  ${Y}[Внимание] Восстановление группы полностью перезапишет текущую базу данных комбайна!${N}"
                echo -ne "  Укажите полный путь к групповому файлу бэкапа (.tar.gz) (Enter для отмены):\n  Путь: "
                read -r group_path
                [ -z "$group_path" ] && continue

                if [ -f "$group_path" ]; then
                    echo -ne "  Вы уверены, что хотите восстановить всю группу? (yes/NO): "
                    read -r conf_group
                    if [ "$conf_group" = "yes" ]; then
                        echo -e "${Y}  Выполняется распаковка и замена пакетного бэкапа...${N}"
                        tar -xzf "$group_path" -C "$HOME"
                        echo -e "${G}  [Успешно] Вся группа профилей, база данных и настройки восстановлены.${N}"
                    else
                        echo -e "${D}  Операция отменена пользователем.${N}"
                    fi
                else
                    echo -e "${R}  [Ошибка] Указанный файл группового бэкапа не обнаружен.${N}"
                fi
                sleep 3.0 ;;
            b|B|"") return ;;
        esac
    done
}

# ================================================================
#  UI РЕНДЕРИНГ
# ================================================================
DIV=$(printf '=%.0s' {1..56})

sep()     { echo -e "${B}$DIV${N}"; }
sep_dim() { echo -e "${D}$DIV${N}"; }
hdr()     { echo -e "${W}  $1${N}"; }
kv()      { printf "  %-12s : ${3}%s${N}\n" "$1" "$2"; }
mi()      { printf "  ${3:-$M}%s)${N}  %s\n" "$1" "$2"; }

prof_line() {
    local num="$1" name="$2" proxy="$3" badge col
    if [ "$TOR_ENABLED" = "true" ]; then
        if [ "$proxy" = "true" ]; then
            badge="TOR" col="$P"
        else
            badge="DIRECT" col="$D"
        fi
    elif [ "$proxy" = "true" ]; then
        badge="VPN" col="$G"
    else
        badge="DIRECT" col="$R"
    fi
    printf "  ${Y}%2s)${N}  %-32s ${col}[%s]${N}\n" "$num" "$name" "$badge"
}

# ================================================================
#  УПРАВЛЕНИЕ ПРОФИЛЯМИ (ADD / EDIT / CLEAR / DELETE)
# ================================================================
menu_add_profile() {
    clear
    sep
    hdr "ДОБАВИТЬ НОВЫЙ ПРОФИЛЬ"
    sep
    echo ""

    echo -ne "  Название профиля (например: Работа / Личный) (Enter для отмены): "
    read -r new_name
    [ -z "$new_name" ] && return

    load_profiles
    if profile_name_exists "$new_name"; then
        echo -e "${Y}  [Предупреждение] Профиль с именем «$new_name» уже существует!${N}"
        echo -ne "  Вы хотите продолжить и использовать такое же имя? (yes/NO): "
        read -r name_conf
        if [ "$name_conf" != "yes" ]; then
            echo -e "${D}  Операция отменена.${N}"
            sleep 1
            return
        fi
    fi

    echo -ne "  Стартовый URL-адрес [https://claude.ai]: "
    read -r new_url
    new_url="${new_url:-https://claude.ai}"

    echo ""
    mi "1" "Маршрутизация через VPN (Socks5-порт $VPN_PORT)" "$G"
    mi "2" "Прямое подключение к сети (Direct, без прокси)"  "$R"
    echo -ne "\n  Выберите режим работы сети [1]: "
    read -r proxy_choice
    local new_proxy="true"
    [ "$proxy_choice" = "2" ] && new_proxy="false"

    local new_id
    new_id="$(generate_id)"

    profiles_ids+=("$new_id")
    profiles_names+=("$new_name")
    profiles_proxy+=("$new_proxy")
    profiles_urls+=("$new_url")
    save_profiles

    mkdir -p "$PROFILE_BASE_DIR/$new_id"
    echo -e "\n${G}  [Успешно] Профиль «$new_name» успешно создан!${N}"
    echo -e "${D}          Системный ID: $new_id${N}"
    sleep 1.5
}

menu_edit_profile() {
    load_profiles
    if [ ${#profiles_ids[@]} -eq 0 ]; then
        echo -e "${R}  [Ошибка] Созданные профили отсутствуют.${N}"
        sleep 1
        return
    fi

    clear
    sep
    hdr "РЕДАКТИРОВАТЬ ПАРАМЕТРЫ ПРОФИЛЯ"
    sep
    echo ""
    local i
    for i in "${!profiles_ids[@]}"; do
        printf "  ${Y}%2s)${N}  %s  ${D}(%s)${N}\n" "$((i+1))" "${profiles_names[$i]}" "${profiles_ids[$i]}"
    done
    echo ""
    echo -ne "  Выберите номер профиля для изменения (Enter для отмены): "
    read -r sel
    [ -z "$sel" ] && return

    if [[ "$sel" =~ ^[0-9]+$ ]]; then
        local idx=$(( sel - 1 ))
        if [ "$idx" -lt 0 ] || [ "$idx" -ge "${#profiles_ids[@]}" ]; then
            echo -e "${R}  [Ошибка] Некорректный номер профиля.${N}"
            sleep 1
            return
        fi

        clear
        sep
        hdr "Редактирование профиля: ${profiles_names[$idx]}"
        sep
        echo ""

        echo -ne "  Новое название [${profiles_names[$idx]}]: "
        read -r val
        if [ -n "$val" ] && [ "$val" != "${profiles_names[$idx]}" ]; then
            if profile_name_exists "$val"; then
                echo -e "${Y}  [Предупреждение] Профиль с именем «$val» уже существует!${N}"
                echo -ne "  Всё равно присвоить это имя? (yes/NO): "
                read -r name_conf
                if [ "$name_conf" = "yes" ]; then
                    profiles_names[$idx]="$val"
                else
                    echo -e "${D}  Изменение названия пропущено.${N}"
                fi
            else
                profiles_names[$idx]="$val"
            fi
        fi

        echo -ne "  Новый URL [${profiles_urls[$idx]}]: "
        read -r val
        [ -n "$val" ] && profiles_urls[$idx]="$val"

        echo -ne "  Использовать VPN-прокси? (Текущий статус: ${profiles_proxy[$idx]}) [yes/no]: "
        read -r val

        case "$val" in
            yes|y|1|true)  profiles_proxy[$idx]="true" ;;
            no|n|0|false)  profiles_proxy[$idx]="false" ;;
        esac

        save_profiles
        echo -e "\n${G}  [Успешно] Все изменения сохранены в базу данных.${N}"
    else
        echo -e "${R}  [Ошибка] Некорректный формат ввода данных.${N}"
    fi
    sleep 1.2
}

menu_clear_cache() {
    load_profiles
    if [ ${#profiles_ids[@]} -eq 0 ]; then
        echo -e "${R}  [Ошибка] Нет созданных профилей.${N}"
        sleep 1
        return
    fi

    clear
    sep
    hdr "ОЧИСТКА КЭША И ИСТОРИИ ПРОФИЛЕЙ"
    sep
    echo ""
    local i
    for i in "${!profiles_ids[@]}"; do
        local sz
        sz="$(du -sh "$PROFILE_BASE_DIR/${profiles_ids[$i]}" 2>/dev/null | cut -f1)"
        sz="${sz:-0B}"
        printf "  ${Y}%2s)${N}  %-32s ${D}[Размер: %s]${N}\n" "$((i+1))" "${profiles_names[$i]}" "$sz"
    done
    echo ""
    mi "0" "Полный сброс (Очистить кэш всех имеющихся профилей)" "$R"
    echo ""
    echo -ne "  Выберите номер профиля для очистки (Enter для отмены): "
    read -r sel
    [ -z "$sel" ] && return

    if [ "$sel" = "0" ]; then
        echo -ne "  ${R}Вы действительно хотите безвозвратно удалить данные ВСЕХ профилей? (yes/NO): ${N}"
        read -r confirm
        if [ "$confirm" = "yes" ]; then
            rm -rf "$PROFILE_BASE_DIR" && mkdir -p "$PROFILE_BASE_DIR"
            init_profiles
            echo -e "${G}  [Успешно] Все кэш-директории полностью очищены.${N}"
        else
            echo -e "${D}  Операция сброса отменена.${N}"
        fi
    elif [[ "$sel" =~ ^[0-9]+$ ]]; then
        local idx=$(( sel - 1 ))
        if [ "$idx" -ge 0 ] && [ "$idx" -lt "${#profiles_ids[@]}" ]; then
            local pd="$PROFILE_BASE_DIR/${profiles_ids[$idx]}"
            rm -rf "$pd" && mkdir -p "$pd"
            echo -e "${G}  [Успешно] Данные кэша профиля «${profiles_names[$idx]}» полностью удалены.${N}"
        else
            echo -e "${R}  [Ошибка] Выбран неверный номер.${N}"
        fi
    fi
    sleep 1.5
}

menu_delete_profile() {
    load_profiles
    if [ ${#profiles_ids[@]} -eq 0 ]; then
        echo -e "${R}  [Ошибка] Список профилей пуст.${N}"
        sleep 1
        return
    fi

    clear
    sep
    hdr "УДАЛИТЬ ВЫБРАННЫЙ ПРОФИЛЬ"
    sep
    echo ""
    local i
    for i in "${!profiles_ids[@]}"; do
        printf "  ${Y}%2s)${N}  %s  ${D}(%s)${N}\n" "$((i+1))" "${profiles_names[$i]}" "${profiles_ids[$i]}"
    done
    echo ""
    echo -ne "  Выберите номер профиля для удаления (Enter для отмены): "
    read -r sel
    [ -z "$sel" ] && return

    if [[ "$sel" =~ ^[0-9]+$ ]]; then
        local idx=$(( sel - 1 ))
        if [ "$idx" -ge 0 ] && [ "$idx" -lt "${#profiles_ids[@]}" ]; then
            local del_name="${profiles_names[$idx]}"
            local del_id="${profiles_ids[$idx]}"
            echo ""
            echo -ne "  ${R}Удалить профиль «$del_name» и всю его историю сессий? (yes/NO): ${N}"
            read -r confirm
            if [ "$confirm" = "yes" ]; then
                rm -rf "$PROFILE_BASE_DIR/$del_id"
                local ni=() nn=() np=() nu=() j
                for j in "${!profiles_ids[@]}"; do
                    [ "$j" -eq "$idx" ] && continue
                    ni+=("${profiles_ids[$j]}")
                    nn+=("${profiles_names[$j]}")
                    np+=("${profiles_proxy[$j]}")
                    nu+=("${profiles_urls[$j]}")
                done
                profiles_ids=("${ni[@]}")
                profiles_names=("${nn[@]}")
                profiles_proxy=("${np[@]}")
                profiles_urls=("${nu[@]}")
                save_profiles
                echo -e "${G}  [Успешно] Профиль и связанные с ним данные стерты.${N}"
            else
                echo -e "${D}  Операция удаления отменена.${N}"
            fi
        else
            echo -e "${R}  [Ошибка] Профиль под указанным номером отсутствует.${N}"
        fi
        sleep 1.5
    fi
}

# ================================================================
#  КОНФИГУРАЦИЯ И НАСТРОЙКИ СИСТЕМЫ
# ================================================================
menu_settings() {
    while true; do
        clear
        sep
        hdr "КОНФИГУРАЦИЯ И НАСТРОЙКИ СИСТЕМЫ"
        sep
        echo -e "  ${D}Путь к файлу конфигурации:${N}"
        echo -e "  ${C}$CONFIG_FILE${N}\n"

        kv "Браузер"   "$DEFAULT_BROWSER"  "$C"
        kv "VPN-порт"  "$VPN_PORT"         "$G"
        kv "Tor-порт"  "$TOR_PORT"         "$P"
        echo ""
        mi "1" "Изменить основной исполняемый браузер"
        mi "2" "Изменить порт SOCKS5 VPN"
        mi "3" "Изменить рабочий порт сети Tor" "$P"
        mi "4" "Выполнить диагностику VPN соединения"
        mi "5" "Выполнить диагностику статуса Tor"
        mi "6" "Вывести сырую базу профилей (Просмотр raw файла)"
        mi "b" "Вернуться в главное меню" "$R"
        echo ""
        sep
        echo ""
        echo -ne "  Ваш выбор: "
        read -r c

        case "$c" in
            1)
                echo -ne "  Введите команду или путь запуска браузера: "
                read -r nb
                if [ -n "$nb" ]; then
                    DEFAULT_BROWSER="$nb"
                    save_config
                    echo -e "${G}  [Успешно] Браузер изменен -> $DEFAULT_BROWSER${N}"
                fi
                sleep 1.5 ;;
            2)
                echo -ne "  Введите новый сетевой порт VPN-клиента [${VPN_PORT}]: "
                read -r np
                if [[ "$np" =~ ^[0-9]+$ ]] && [ "$np" -gt 0 ] && [ "$np" -lt 65536 ]; then
                    VPN_PORT="$np"
                    save_config
                    echo -e "${G}  [Успешно] Порт VPN успешно переназначен -> $VPN_PORT${N}"
                else
                    echo -e "${R}  [Ошибка] Введен некорректный диапазон сетевого порта.${N}"
                fi
                sleep 1.5 ;;
            3)
                echo -ne "  Введите новый порт прокси-службы Tor [${TOR_PORT}]: "
                read -r np
                if [[ "$np" =~ ^[0-9]+$ ]] && [ "$np" -gt 0 ] && [ "$np" -lt 65536 ]; then
                    TOR_PORT="$np"
                    save_config
                    echo -e "${P}  [Успешно] Сетевой порт Tor изменен -> $TOR_PORT${N}"
                else
                    echo -e "${R}  [Ошибка] Введен некорректный диапазон сетевого порта.${N}"
                fi
                sleep 1.5 ;;
            4)
                echo ""
                local vip
                if vip="$(get_vpn_ip 2>/dev/null)" && [ -n "$vip" ]; then
                    echo -e "${G}  [Успешно] Туннель VPN активен локально на адресе: $vip:$VPN_PORT${N}"
                else
                    echo -e "${R}  [Ошибка] Прокси-клиент VPN на порту $VPN_PORT в системе не запущен.${N}"
                fi
                echo -ne "\n  ${D}Нажмите Enter для продолжения...${N}"
                read -r ;;
            5)
                echo ""
                if tor_service_active; then
                    echo -e "${P}  [Успешно] Служба Tor активна в процессах.${N}"
                else
                    echo -e "${R}  [Ошибка] Процесс Tor не запущен в системе.${N}"
                fi

                if tor_port_open; then
                    echo -e "${P}  [Успешно] Процесс Tor принимает входящие сокеты на порту $TOR_PORT${N}"
                else
                    echo -e "${R}  [Ошибка] Порт Tor ($TOR_PORT) не прослушивается.${N}"
                fi
                echo -ne "\n  ${D}Нажмите Enter для продолжения...${N}"
                read -r ;;
            6)
                echo -e "\n--- Начало конфигурационного файла ---"
                cat "$PROFILES_LIST_FILE" 2>/dev/null || echo "  (Файл базы данных пуст либо отсутствует)"
                echo -e "--- Конец конфигурационного файла ---"
                echo -ne "\n  ${D}Нажмите Enter для продолжения...${N}"
                read -r ;;
            b|B|"") return ;;
            *) echo -e "${R}  [Ошибка] Неверный вариант ввода.${N}"; sleep 0.8 ;;
        esac
    done
}

# ================================================================
#  ГЛАВНОЕ МЕНЮ
# ================================================================
menu_main() {
    while true; do
        load_profiles
        get_tor_status

        local vpn_text vpn_col
        if [ "$IS_MAC" = "true" ]; then
            if lsof -i :"${VPN_PORT}" -sTCP:LISTEN &>/dev/null; then
                vpn_text="Активен (порт ${VPN_PORT})"
                vpn_col="$G"
            else
                vpn_text="Не активен (порт ${VPN_PORT})"
                vpn_col="$R"
            fi
        else
            if ss -tuln 2>/dev/null | grep -q ":${VPN_PORT} "; then
                vpn_text="Активен (порт ${VPN_PORT})"
                vpn_col="$G"
            else
                vpn_text="Не активен (порт ${VPN_PORT})"
                vpn_col="$R"
            fi
        fi

        clear
        sep
        printf "  ${W}brtor v1.9.6${N}  |  ${D}Менеджер изолированных браузерных сессий (Universal)${N}\n"
        sep
        echo ""
        kv "Браузер"    "$(basename "$DEFAULT_BROWSER")"  "$C"
        kv "VPN прокси" "$vpn_text"                       "$vpn_col"
        kv "Tor прокси" "$TOR_STATUS_TEXT"                "$TOR_STATUS_COL"
        echo ""
        sep_dim

        if [ ${#profiles_ids[@]} -eq 0 ]; then
            echo -e "  ${D}(Доступные профили не найдены. Для создания нажмите клавишу 'a')${N}"
        else
            local i
            for i in "${!profiles_ids[@]}"; do
                prof_line "$((i+1))" "${profiles_names[$i]}" "${profiles_proxy[$i]}"
            done
        fi

        sep_dim
        echo ""
        mi "t" "Переключить режим Tor" "$P"
        mi "a" "Создать новый профиль"
        mi "e" "Редактировать параметры профиля"
        mi "c" "Очистить кэш и сбросить настройки"
        mi "d" "Удалить выбранный профиль"
        mi "l" "Просмотреть логи браузера" "$C"
        mi "i" "Резервные копии (импорт и экспорт)" "$B"
        mi "s" "Конфигурация и настройки"
        mi "q" "Выход из программы" "$R"
        echo ""
        sep
        echo ""
        echo -ne "  Выбор (номер профиля или код команды): "
        read -r CHOICE
        echo ""

        if [[ "$CHOICE" =~ ^[0-9]+$ ]]; then
            local idx=$(( CHOICE - 1 ))
            if [ "$idx" -ge 0 ] && [ "$idx" -lt "${#profiles_ids[@]}" ]; then
                launch_browser \
                    "${profiles_ids[$idx]}" \
                    "${profiles_proxy[$idx]}" \
                    "${profiles_urls[$idx]}"
                echo ""
                echo -ne "${D}  Процесс запущен. Нажмите Enter для возврата в главное меню...${N}"
                read -r
            else
                echo -e "${R}  [Ошибка] Профиль с таким порядковым номером отсутствует.${N}"
                sleep 1
            fi
        else
            case "$CHOICE" in
                t|T) toggle_tor ;;
                a|A) menu_add_profile ;;
                e|E) menu_edit_profile ;;
                c|C) menu_clear_cache ;;
                d|D) menu_delete_profile ;;
                l|L) menu_view_logs ;;
                i|I) menu_backup_manager ;;
                s|S) menu_settings ;;
                q|Q|"")
                    clear
                    echo -e "\n${B}  [brtor] Сессия завершена. Безопасного и стабильного сёрфинга!${N}\n"
                    exit 0 ;;
                *) echo -e "${R}  [Ошибка] Некорректная команда. Повторите попытку.${N}"; sleep 0.8 ;;
            esac
        fi
    done
}

# ================================================================
#  СТАРТ ПРОГРАММЫ
# ================================================================
check_dependencies
load_config
check_and_autoconfig
init_profiles
menu_main
