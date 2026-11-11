#!/bin/bash
#
# sysmaint.sh — TUI-меню обслуживания системы (Arch)
#

set -uo pipefail

# ── Цвета ──────────────────────────────────────────────
RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[0;33m'
CYAN=$'\033[0;36m'
DIM=$'\033[2m'
BOLD=$'\033[1m'
RESET=$'\033[0m'

# ── Пункты меню ────────────────────────────────────────
MENU_ITEMS=(
    "Обновление системы (pacman + flatpak)"
    "Кэш pacman и пакеты-сироты"
    "Временные файлы и кэш программ"
    "Кэш браузера Zen"
    "Журналы systemd (старше 7 дней)"
)
STATES=(0 0 0 0 0)   # 0 = не выбрано, 1 = выбрано
SELECTED=0           # текущая позиция курсора

# ── Логотип ────────────────────────────────────────────
show_logo() {
    echo "                            _          _ "
    echo "  ___ ___  ___  ___ ___ _  (_)__  ____(_)"
    echo " (_─<╱ _ ╲╱ _ ╲╱ _ '╱  ' ╲╱ ╱ _ ╲╱ __╱ ╱ "
    echo "╱___╱╲___╱_╱╱_╱╲_,_╱_╱_╱_╱_╱╲___╱_╱ ╱_╱  "
    echo "                                         "
}

# ── Хелперы вывода ─────────────────────────────────────
info() { echo -e "${CYAN}[info]${RESET} $*"; }
ok()   { echo -e "${GREEN}[ ok ]${RESET} $*"; }
skip() { echo -e "${DIM}[skip] $*${RESET}"; }
fail() { echo -e "${RED}[fail]${RESET} $*" >&2; }

log_section() {
    echo
    echo -e "${BOLD}${CYAN}▶ $*${RESET}"
    echo -e "${DIM}────────────────────────────────────────────${RESET}"
}

pause() {
    echo
    read -rsn1 -p "${DIM}Нажмите любую клавишу, чтобы вернуться в меню...${RESET}" || true
}

# ══════════════════════════════════════════════════════
#  ЗАДАЧИ
# ══════════════════════════════════════════════════════

# ── 1. Обновление системы ──────────────────────────────
task_update() {
    log_section "Обновление системы"

    local path="$HOME"
    local required_kb=$((6 * 1024 * 1024))   # 6 ГиБ в КиБ
    local disk_info available_kb available_gib

    if ! disk_info=$(df -Pk -- "$path"); then
        fail "Не удалось проверить свободное место ($path)"
        return 1
    fi

    available_kb=$(awk 'NR == 2 {print $4}' <<<"$disk_info")
    if [[ ! "$available_kb" =~ ^[0-9]+$ ]]; then
        fail "Не удалось определить объём свободного места"
        return 1
    fi

    available_gib=$(awk -v kb="$available_kb" 'BEGIN {printf "%.2f", kb / 1024 / 1024}')
    info "Свободно: $available_gib ГиБ (требуется ≥ 6 ГиБ)"

    if ((available_kb < required_kb)); then
        fail "Недостаточно места — обновление отменено"
        return 1
    fi

    echo
    info "sudo pacman -Syu"
    sudo pacman -Syu

    if command -v flatpak &>/dev/null; then
        echo
        info "flatpak update"
        flatpak update
    else
        skip "flatpak не установлен"
    fi
}

# ── 2. Кэш pacman и сироты ─────────────────────────────
task_pacman_cache() {
    log_section "Кэш pacman и пакеты-сироты"

    info "pacman -Scc (ответьте [y], затем Enter)"
    sudo pacman -Scc

    echo
    info "Удаление /var/cache/pacman/pkg/*"
    sudo rm -rf /var/cache/pacman/pkg/*

    echo
    local orphans
    if orphans=$(pacman -Qtdq 2>/dev/null) && [[ -n "$orphans" ]]; then
        info "Найдены пакеты-сироты:"
        echo "$orphans"
        echo "$orphans" | sudo pacman -Rns -
    else
        skip "Пакетов-сирот не найдено"
    fi
}

# ── Удаление одного пути с проверками ──────────────────
clean_path() {
    local target="$1"

    if [[ "$target" == *\** ]]; then
        shopt -s nullglob dotglob
        local matches=( $target )
        shopt -u nullglob dotglob

        if ((${#matches[@]} > 0)); then
            rm -rf -- "${matches[@]}" \
                && ok "$target (${#matches[@]} шт.)" \
                || fail "$target"
        else
            skip "$target — уже пусто"
        fi
    else
        if [[ -e "$target" ]]; then
            rm -rf -- "$target" && ok "$target" || fail "$target"
        else
            skip "$target — не существует"
        fi
    fi
}

# ── 3. Временные файлы и кэш программ ──────────────────
task_temp_cache() {
    log_section "Временные файлы и кэш программ"

    local w64="$HOME/.wine64/drive_c"
    local w32="$HOME/.wine/drive_c"
    local osu="$HOME/.local/share/wineprefixes/osu-wineprefix/drive_c"

    local -a targets=(
        "$HOME/.cache/*"
        "$w64/users/$USER/AppData/Local/Temp/*"
        "$w64/users/$USER/AppData/Roaming/.minecraft/assets/skins/*"
        "$w64/users/$USER/AppData/Roaming/.minecraft/screenshots/*"
        "$w64/windows/temp/*"
        "$w32/users/$USER/AppData/Local/Microsoft/Windows/INetCache/*"
        "$w32/users/$USER/AppData/Local/Overwolf/Temp/*"
        "$w32/windows/Microsoft.NET/Framework64/v4.0.30319/SetupCache/*"
        "$w32/windows/temp"
        "$osu/windows/Microsoft.NET/Framework64/v4.0.30319/SetupCache/*"
        "$HOME/.tlauncher/cache/*"
        "$HOME/.tlauncher/logs/*"
        "$HOME/.local/share/TelegramDesktop/tdata/emoji/*"
        "$HOME/.local/share/TelegramDesktop/log"
        "$HOME/.local/share/AyuGramDesktop/tdata/audio_cache/*"
        "$HOME/.local/share/AyuGramDesktop/tdata/user_data/*"
        "$HOME/.local/share/AyuGramDesktop/log"
        "$HOME/.local/share/Trash/files/*"
        "$HOME/.config/discord/Cache/*"
        "$HOME/.config/Prizrak-Box/Cache/*"
        "$HOME/.config/obsidian/Cache/*"
    )

    local t
    for t in "${targets[@]}"; do
        clean_path "$t"
    done

    # vicinae clipboard
    local vicinae="$HOME/.local/share/vicinae/clipboard-data"
    if [[ -d "$vicinae" ]]; then
        find "$vicinae" -mindepth 1 -delete 2>/dev/null \
            && ok "$vicinae/*" || fail "$vicinae"
    else
        skip "$vicinae — не существует"
    fi
}

# ── 4. Кэш браузера Zen ────────────────────────────────
task_zen_cache() {
    log_section "Кэш браузера Zen"

    local base_path="$HOME/.config/zen"
    if [[ ! -d "$base_path" ]]; then
        fail "Путь не найден: $base_path"
        return 1
    fi

    local found=false cache_dir item
    while IFS= read -r -d '' cache_dir; do
        found=true
        shopt -s dotglob nullglob
        for item in "$cache_dir"/*; do
            rm -rf -- "$item"
        done
        shopt -u dotglob nullglob
        ok "$cache_dir/*"
    done < <(find "$base_path" -type d -name "cache" -print0 2>/dev/null)

    $found || skip "Папки 'cache' не найдены"
}

# ── 5. Журналы systemd ─────────────────────────────────
task_journal() {
    log_section "Журналы systemd"
    sudo journalctl --vacuum-time=7d
    ok "Оставлены записи за последние 7 дней"
}

# ── Диспетчер ──────────────────────────────────────────
run_task() {
    case "$1" in
        0) task_update ;;
        1) task_pacman_cache ;;
        2) task_temp_cache ;;
        3) task_zen_cache ;;
        4) task_journal ;;
    esac
}

# ══════════════════════════════════════════════════════
#  TUI-МЕНЮ
# ══════════════════════════════════════════════════════

draw_menu() {
    clear
    show_logo

    local i count=0
    for i in "${!STATES[@]}"; do
        ((count += STATES[i]))
    done

    echo -e "${BOLD}Меню обслуживания${RESET} ${DIM}(выбрано: $count/${#MENU_ITEMS[@]})${RESET}"
    echo -e "${DIM}↑/↓ или j/k — навигация · Space — выбрать · A — всё · Enter — запуск · Q — выход${RESET}"
    echo

    for i in "${!MENU_ITEMS[@]}"; do
        local box="[ ]"
        ((STATES[i])) && box="[${GREEN}✔${RESET}]"

        if ((i == SELECTED)); then
            echo -e " ${CYAN}❯${RESET} ${box} ${BOLD}${MENU_ITEMS[i]}${RESET}"
        else
            echo -e "   ${box} ${MENU_ITEMS[i]}"
        fi
    done
    echo
}

read_key() {
    local key seq
    IFS= read -rsn1 key 2>/dev/null || true
    if [[ "$key" == $'\x1b' ]]; then
        IFS= read -rsn2 -t 0.05 seq 2>/dev/null || true
        key+="$seq"
    fi
    printf '%s' "$key"
}

toggle_all() {
    local i all_on=1
    for i in "${!STATES[@]}"; do
        ((STATES[i] == 0)) && { all_on=0; break; }
    done
    local new=$(( all_on ? 0 : 1 ))
    for i in "${!STATES[@]}"; do
        STATES[i]=$new
    done
}

run_selected() {
    local i any=0
    for i in "${!STATES[@]}"; do
        ((STATES[i])) && { any=1; break; }
    done

    tput cnorm 2>/dev/null || true   # вернуть курсор на время выполнения
    clear
    show_logo

    if ((any == 0)); then
        echo -e "${YELLOW}Ничего не выбрано.${RESET} Отметьте задачи пробелом."
    else
        local before after freed
        before=$(df -Pk -- "$HOME" | awk 'NR==2 {print $4}')

        for i in "${!MENU_ITEMS[@]}"; do
            if ((STATES[i])); then
                run_task "$i"
                echo
            fi
        done

        after=$(df -Pk -- "$HOME" | awk 'NR==2 {print $4}')
        if [[ "$before" =~ ^[0-9]+$ && "$after" =~ ^[0-9]+$ ]]; then
            freed=$(awk -v a="$after" -v b="$before" 'BEGIN {printf "%.1f", (a - b) / 1024}')
        fi

        echo -e "${GREEN}${BOLD}══════════════════════════════════════${RESET}"
        echo -e "${GREEN}${BOLD} Готово!${RESET} Освобождено: ${BOLD}${freed:-?} МиБ${RESET}"
        echo -e "${DIM} Рекомендуется перезагрузка.${RESET}"
        echo -e "${GREEN}${BOLD}══════════════════════════════════════${RESET}"
    fi

    pause
    tput civis 2>/dev/null || true
}

menu() {
    tput civis 2>/dev/null || true   # спрятать курсор

    while true; do
        draw_menu

        local key
        key=$(read_key)

        case "$key" in
            $'\x1b[A'|k) ((SELECTED = (SELECTED - 1 + ${#MENU_ITEMS[@]}) % ${#MENU_ITEMS[@]})) ;;
            $'\x1b[B'|j) ((SELECTED = (SELECTED + 1) % ${#MENU_ITEMS[@]})) ;;
            ' ')
                ((STATES[SELECTED])) && STATES[SELECTED]=0 || STATES[SELECTED]=1
                ;;
            a|A|ф|Ф) toggle_all ;;
            q|Q|й|Й|$'\x1b') return 1 ;;
            "") run_selected ;;   # Enter
        esac
    done
}

main() {
    trap 'tput cnorm 2>/dev/null' EXIT
    menu || true
    clear
    echo "До встречи 👻"
}

main
