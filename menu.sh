#!/bin/bash

# ============================================================================
# REMOTE SYSTEM CONTROL INTERFACE
# ============================================================================
# Script para controlar sistemas remotos Linux/Windows mediante SSH
# ============================================================================

CONFIG_FILE="hosts.conf"
LOCAL_SCRIPTS_DIR="local_scripts"
SSH_USER="root"

mkdir -p "$LOCAL_SCRIPTS_DIR/linux" "$LOCAL_SCRIPTS_DIR/windows"

# ============================================================================
# Verificar que dialog y ssh estén instalados
# ============================================================================
check_dependencies() {
    if ! command -v dialog &> /dev/null; then
        echo "Error: 'dialog' is not installed."
        echo "Install: sudo pacman -S dialog"
        exit 1
    fi
    
    if ! command -v ssh &> /dev/null; then
        echo "Error: 'ssh' is not installed."
        echo "Install: sudo pacman -S openssh"
        exit 1
    fi
}

# ============================================================================
# Ejecutar un script local en un host remoto
# $1: IP del host
# $2: Ruta del script local
# $3: Argumentos opcionales
# ============================================================================
execute_local_script_remote() {
    local host=$1
    local script_path=$2
    local args="${3:-}"
    
    [ ! -f "$script_path" ] && echo "ERROR: Script not found: $script_path" && return 1
    
    ssh -o ConnectTimeout=5 "${SSH_USER}@${host}" "bash -s $args" < "$script_path" 2>&1
}

# ============================================================================
# Ejecutar un comando directo en un host remoto
# $1: IP del host
# $2: Comando a ejecutar
# ============================================================================
ssh_exec() {
    ssh -o ConnectTimeout=5 "${SSH_USER}@$1" "$2" 2>&1
}

# ============================================================================
# Verificar si un host está online (ping)
# $1: IP del host
# Retorna: 0 si está online, 1 si está offline
# ============================================================================
check_host_online() {
    ping -c 1 -W 1 "$1" &> /dev/null
}

# ============================================================================
# Convertir la selección del usuario en un array de IPs ONLINE
# $1: IPs seleccionadas ("ALL" o "192.168.56.10 192.168.56.20")
# $2: Filtro de OS opcional ("linux" o "windows")
# Retorna: Array de IPs que están ONLINE
# ============================================================================
get_selected_ips() {
    local selected_ips=$1
    local filter_os=${2:-""}
    local ips=()
    
    if [[ "$selected_ips" == "ALL" ]]; then
        # Usuario seleccionó "ALL" - obtener todos los hosts
        while IFS='|' read -r hostname ip os_type; do
            # Filtrar por OS si se especificó
            [ -n "$filter_os" ] && [ "$os_type" != "$filter_os" ] && continue
            
            # Solo añadir si está online
            check_host_online "$ip" && ips+=("$ip")
        done < "$CONFIG_FILE"
    else
        # Usuario seleccionó IPs específicas
        for selected_ip in $selected_ips; do
            while IFS='|' read -r hostname ip os_type; do
                if [[ "$ip" == "$selected_ip" ]]; then
                    # Filtrar por OS si se especificó
                    [ -n "$filter_os" ] && [ "$os_type" != "$filter_os" ] && continue
                    
                    # Solo añadir si está online
                    check_host_online "$ip" && ips+=("$ip")
                    break
                fi
            done < "$CONFIG_FILE"
        done
    fi
    
    echo "${ips[@]}"
}

# ============================================================================
# Mostrar menú para seleccionar hosts
# Variable global modificada: SELECTED_IPS
# ============================================================================
select_hosts() {
    [ ! -f "$CONFIG_FILE" ] && dialog --msgbox "Error: '$CONFIG_FILE' not found!" 10 50 && return 1
    
    local options=("ALL" "Execute on all hosts" OFF)
    
    # Leer todos los hosts y verificar estado
    while IFS='|' read -r hostname ip os_type; do
        local status="●OFFLINE"
        check_host_online "$ip" && status="✓ONLINE"
        
        options+=("$ip" "$hostname ($os_type) [$status]" OFF)
    done < "$CONFIG_FILE"
    
    [ ${#options[@]} -le 3 ] && dialog --msgbox "No hosts found!" 8 50 && return 1
    
    local selected=$(dialog --stdout --checklist "Select target hosts:" 20 80 10 "${options[@]}")
    [ -z "$selected" ] && return 1
    
    SELECTED_IPS=$(echo $selected | tr -d '"')
    return 0
}

# ============================================================================
# Mostrar menú para seleccionar hosts filtrados por OS
# $1: OS a filtrar ("linux" o "windows")
# Variable global modificada: SELECTED_IPS
# ============================================================================
select_hosts_by_os() {
    local filter_os=$1
    [ ! -f "$CONFIG_FILE" ] && dialog --msgbox "Error: '$CONFIG_FILE' not found!" 10 50 && return 1
    
    local options=("ALL" "Execute on all $filter_os hosts" OFF)
    local host_found=0
    
    while IFS='|' read -r hostname ip os_type; do
        # Solo procesar hosts del OS especificado
        [ "$os_type" != "$filter_os" ] && continue
        
        host_found=1
        local status="●OFFLINE"
        check_host_online "$ip" && status="✓ONLINE"
        
        options+=("$ip" "$hostname [$status]" OFF)
    done < "$CONFIG_FILE"
    
    [ $host_found -eq 0 ] && dialog --msgbox "No $filter_os hosts found!" 8 50 && return 1
    
    local selected=$(dialog --stdout --checklist "Select $filter_os hosts:" 20 80 10 "${options[@]}")
    [ -z "$selected" ] && return 1
    
    SELECTED_IPS=$(echo $selected | tr -d '"')
    return 0
}

# ============================================================================
# MENÚ PRINCIPAL
# ============================================================================
main_menu() {
    while true; do
        CHOICE=$(dialog --stdout --title "Remote System Control" \
            --menu "Choose an action:" 15 60 5 \
            1 "System Operations" \
            2 "Monitoring" \
            3 "Custom Command" \
            4 "Manage Hosts" \
            5 "Exit")
        
        case $CHOICE in
            1) system_operations_menu ;;
            2) monitoring_menu ;;
            3) execute_custom_command ;;
            4) manage_hosts_menu ;;
            *) clear; exit 0 ;;
        esac
    done
}

# ============================================================================
# MENÚ: Operaciones del Sistema
# ============================================================================
system_operations_menu() {
    while true; do
        CHOICE=$(dialog --stdout --title "System Operations" \
            --menu "Select operation:" 15 60 5 \
            1 "Reboot System(s)" \
            2 "Shutdown System(s)" \
            3 "Update System(s)" \
            4 "Restart Service" \
            5 "Back")
        
        case $CHOICE in
            1) execute_operation "reboot" ;;
            2) execute_operation "shutdown" ;;
            3) execute_operation "update" ;;
            4) execute_operation "restart_service" ;;
            *) return ;;
        esac
    done
}

# ============================================================================
# MENÚ: Monitoreo
# ============================================================================
monitoring_menu() {
    while true; do
        CHOICE=$(dialog --stdout --title "Monitoring" \
            --menu "Select option:" 15 60 6 \
            1 "Host Status" \
            2 "CPU Usage" \
            3 "Memory Usage" \
            4 "Disk Space" \
            5 "System Info" \
            6 "Back")
        
        case $CHOICE in
            1) check_all_hosts_status ;;
            2) execute_monitoring "cpu" ;;
            3) execute_monitoring "memory" ;;
            4) execute_monitoring "disk" ;;
            5) execute_monitoring "sysinfo" ;;
            *) return ;;
        esac
    done
}

# ============================================================================
# Ver estado (online/offline) de todos los hosts
# ============================================================================
check_all_hosts_status() {
    [ ! -f "$CONFIG_FILE" ] && dialog --msgbox "Error: Config not found!" 8 50 && return 1
    
    local temp=$(mktemp)
    echo "HOST STATUS REPORT" > "$temp"
    echo "Generated: $(date)" >> "$temp"
    echo "==============================" >> "$temp"
    echo "" >> "$temp"
    
    local online=0 offline=0
    
    while IFS='|' read -r hostname ip os_type; do
        if check_host_online "$ip"; then
            echo "✓ ONLINE  - $hostname ($ip) [$os_type]" >> "$temp"
            ((online++))
        else
            echo "● OFFLINE - $hostname ($ip) [$os_type]" >> "$temp"
            ((offline++))
        fi
    done < "$CONFIG_FILE"
    
    echo "" >> "$temp"
    echo "==============================" >> "$temp"
    echo "Total: $online online, $offline offline" >> "$temp"
    
    dialog --title "Host Status" --textbox "$temp" 20 60
    rm -f "$temp"
}

# ============================================================================
# Ejecutar operación del sistema (reboot, shutdown, update, restart_service)
# $1: Tipo de operación
# ============================================================================
execute_operation() {
    local operation=$1
    
    select_hosts || return
    
    local ips=($(get_selected_ips "$SELECTED_IPS"))
    [ ${#ips[@]} -eq 0 ] && dialog --msgbox "No hosts ONLINE!" 8 50 && return
    
    local script_path script_args confirm_msg
    
    case $operation in
        reboot)
            script_path="$LOCAL_SCRIPTS_DIR/linux/reboot.sh"
            confirm_msg="REBOOT ${#ips[@]} system(s)?\n\nIPs: ${ips[*]}\n\nAre you sure?"
            ;;
        shutdown)
            script_path="$LOCAL_SCRIPTS_DIR/linux/shutdown.sh"
            confirm_msg="SHUTDOWN ${#ips[@]} system(s)?\n\nIPs: ${ips[*]}\n\nAre you sure?"
            ;;
        update)
            script_path="$LOCAL_SCRIPTS_DIR/linux/update.sh"
            confirm_msg="Update ${#ips[@]} system(s)?\n\nIPs: ${ips[*]}\n\nContinue?"
            ;;
        restart_service)
            SERVICE=$(dialog --stdout --inputbox "Service name:" 10 50)
            [ -z "$SERVICE" ] && return
            script_path="$LOCAL_SCRIPTS_DIR/linux/restart_service.sh"
            script_args="$SERVICE"
            confirm_msg="Restart '$SERVICE' on ${#ips[@]} system(s)?\n\nIPs: ${ips[*]}"
            ;;
    esac
    
    [ ! -f "$script_path" ] && dialog --msgbox "ERROR: Script not found!\n\n$script_path" 10 60 && return
    
    dialog --yesno "$confirm_msg" 12 60 || return
    
    local temp=$(mktemp)
    echo "=== Operation: $operation ===" > "$temp"
    echo "Date: $(date)" >> "$temp"
    echo "Target IPs: ${ips[*]}" >> "$temp"
    echo "" >> "$temp"
    
    for ip in "${ips[@]}"; do
        echo ">>> $ip <<<" >> "$temp"
        execute_local_script_remote "$ip" "$script_path" "$script_args" >> "$temp"
        echo "" >> "$temp"
    done
    
    dialog --title "Results" --textbox "$temp" 22 70
    rm -f "$temp"
}

# ============================================================================
# Ejecutar comando de monitoreo (cpu, memory, disk, sysinfo)
# $1: Tipo de monitoreo
# ============================================================================
execute_monitoring() {
    local monitor_type=$1
    
    select_hosts || return
    
    local ips=($(get_selected_ips "$SELECTED_IPS"))
    [ ${#ips[@]} -eq 0 ] && dialog --msgbox "No hosts ONLINE!" 8 40 && return
    
    local command
    
    case $monitor_type in
        cpu)
            command="top -bn1 | grep 'Cpu(s)' | awk '{print \"CPU: \" 100-\$8 \"%\"}'"
            ;;
        memory)
            command="free -h | grep Mem | awk '{print \"Total: \"\$2\" | Used: \"\$3\" | Free: \"\$4}'"
            ;;
        disk)
            command="df -h / | tail -1 | awk '{print \"Size: \"\$2\" | Used: \"\$3\" | Free: \"\$4\" | Usage: \"\$5}'"
            ;;
        sysinfo)
            command="echo \"Host: \$(hostname)\"; echo \"IP: \$(hostname -I | awk '{print \$1}')\"; echo \"Kernel: \$(uname -r)\"; echo \"Uptime: \$(uptime -p 2>/dev/null || uptime)\""
            ;;
    esac
    
    local temp=$(mktemp)
    echo "=== Monitoring: $monitor_type ===" > "$temp"
    echo "Date: $(date)" >> "$temp"
    echo "IPs: ${ips[*]}" >> "$temp"
    echo "" >> "$temp"
    
    for ip in "${ips[@]}"; do
        echo ">>> $ip <<<" >> "$temp"
        ssh_exec "$ip" "$command" >> "$temp"
        echo "" >> "$temp"
    done
    
    dialog --title "Monitoring: $monitor_type" --textbox "$temp" 22 70
    rm -f "$temp"
}

# ============================================================================
# Ejecutar comando personalizado escrito por el usuario
# ============================================================================
execute_custom_command() {
    local os_type=$(dialog --stdout --title "OS Type" --menu "Select OS:" 12 40 2 1 "Linux" 2 "Windows")
    
    local os
    case $os_type in
        1) os="linux" ;;
        2) os="windows" ;;
        *) return ;;
    esac
    
    local cmd=$(dialog --stdout --inputbox "Enter command (runs as root):" 10 60)
    [ -z "$cmd" ] && return
    
    select_hosts_by_os "$os" || return
    
    local ips=($(get_selected_ips "$SELECTED_IPS" "$os"))
    [ ${#ips[@]} -eq 0 ] && dialog --msgbox "No $os hosts ONLINE!" 8 40 && return
    
    local temp=$(mktemp)
    echo "=== Custom Command ===" > "$temp"
    echo "Command: $cmd" >> "$temp"
    echo "OS: $os" >> "$temp"
    echo "Date: $(date)" >> "$temp"
    echo "IPs: ${ips[*]}" >> "$temp"
    echo "" >> "$temp"
    
    for ip in "${ips[@]}"; do
        echo ">>> $ip <<<" >> "$temp"
        ssh_exec "$ip" "$cmd" >> "$temp"
        echo "" >> "$temp"
    done
    
    dialog --title "Results" --textbox "$temp" 22 70
    rm -f "$temp"
}

# ============================================================================
# MENÚ: Gestionar Hosts
# ============================================================================
manage_hosts_menu() {
    while true; do
        CHOICE=$(dialog --stdout --title "Manage Hosts" \
            --menu "Select option:" 12 50 3 \
            1 "View Hosts" \
            2 "Edit Config" \
            3 "Back")
        
        case $CHOICE in
            1) view_hosts ;;
            2) edit_config ;;
            *) return ;;
        esac
    done
}

# ============================================================================
# Mostrar contenido del archivo de configuración
# ============================================================================
view_hosts() {
    [ -f "$CONFIG_FILE" ] && dialog --textbox "$CONFIG_FILE" 20 70 || dialog --msgbox "Config not found!" 8 40
}

# ============================================================================
# Abrir el archivo de configuración en un editor
# ============================================================================
edit_config() {
    [ -f "$CONFIG_FILE" ] && ${EDITOR:-nano} "$CONFIG_FILE" || dialog --msgbox "Config not found!" 8 40
}

# ============================================================================
# INICIO DEL SCRIPT
# ============================================================================
check_dependencies
main_menu