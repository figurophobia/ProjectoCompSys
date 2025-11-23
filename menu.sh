#!/bin/bash

# ============================================================================
# REMOTE SYSTEM CONTROL INTERFACE
# ============================================================================
# Script para controlar sistemas remotos Linux/Windows mediante SSH
# ============================================================================

CONFIG_FILE="hosts.conf"
LOCAL_SCRIPTS_DIR="local_scripts"
SSH_USER="root"
WINDOWS_USER="Administrator"
WINDOWS_PASS="1QAZxsw2"
LOG_DIR="logs"

# --- VARIABLES PARA BACKUP ---
LINUX_BACKUP_DIR="backups/linux"
WINDOWS_BACKUP_DIR="backups/windows"
LINUX_BACKUP_SOURCES="/etc /var/log /home"
WINDOWS_BACKUP_SOURCES='C:\Users\Administrator\Documents C:\inetpub'

mkdir -p "$LINUX_BACKUP_DIR" "$WINDOWS_BACKUP_DIR"


# ============================================================================
# Verificar que dialog, ssh y sshpass estén instalados
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
    
    if ! command -v sshpass &> /dev/null; then
        echo "Error: 'sshpass' is not installed."
        echo "Install: sudo pacman -S sshpass"
        exit 1
    fi
}


# ============================================================================
# Logging helper
# $1: path to temp file containing the output
# $2: short action name (e.g. host_status, monitoring_cpu, reboot_results)
# ============================================================================
save_log() {
    local src_file="$1"
    local action="$2"
    [ -z "$src_file" ] && return 1
    [ ! -f "$src_file" ] && return 1

    mkdir -p "$LOG_DIR"
    local logfile="$LOG_DIR/todo.log"

    # Append a clear header and the contents so all outputs are consolidated
    {
        echo "============================================================"
        echo "Timestamp: $(date +"%Y-%m-%d %H:%M:%S %z")"
        echo "Action: $action"
        echo "------------------------------------------------------------"
        cat "$src_file"
        echo ""
    } >> "$logfile"
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
    
    # Detectar si es Windows o Linux
    local os_type=$(grep "$host" "$CONFIG_FILE" | cut -d'|' -f3)
    
    if [ "$os_type" = "windows" ]; then
        # Para Windows: enviar script PowerShell por stdin
        # Use flags to run PowerShell non-interactively and bypass execution policy.
        # Use quieter SSH/sshpass flags and avoid persisting host keys to suppress warnings.
        if [[ "$script_path" == *.ps1 ]]; then
            # Script PowerShell: enviarlo por stdin a powershell de forma no interactiva
            sshpass -p "$WINDOWS_PASS" ssh -q -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR "${WINDOWS_USER}@${host}" "powershell -NoProfile  -ExecutionPolicy Bypass -Command -" < "$script_path" 2>&1
        else
            # Comando directo
            sshpass -p "$WINDOWS_PASS" ssh -q -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR "${WINDOWS_USER}@${host}" "powershell -NoProfile  -ExecutionPolicy Bypass -Command \"$args\"" 2>&1
        fi
    else
        # Para Linux: SSH normal
        ssh -o ConnectTimeout=5 "${SSH_USER}@${host}" "bash -s $args" < "$script_path" 2>&1
    fi
}

# ============================================================================
# Ejecutar un comando directo en un host remoto
# $1: IP del host
# $2: Comando a ejecutar
# ============================================================================
ssh_exec() {
    local host=$1
    local command=$2
    
    # Detectar si es Windows o Linux
    local os_type=$(grep "$host" "$CONFIG_FILE" | cut -d'|' -f3)
    
    if [ "$os_type" = "windows" ]; then
    # Para Windows: usar sshpass con PowerShell (silenciar advertencias de SSH)
    sshpass -p "$WINDOWS_PASS" ssh -q -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR "${WINDOWS_USER}@${host}" "powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command \"$command\"" 2>&1
    else
        # Para Linux: SSH normal
        ssh -o ConnectTimeout=5 "${SSH_USER}@${host}" "$command" 2>&1
    fi
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
        while IFS='|' read -r hostname ip os_type; do
            [ -n "$filter_os" ] && [ "$os_type" != "$filter_os" ] && continue
            check_host_online "$ip" && ips+=("$ip")
        done < "$CONFIG_FILE"
    else
        for selected_ip in $selected_ips; do
            while IFS='|' read -r hostname ip os_type; do
                if [[ "$ip" == "$selected_ip" ]]; then
                    [ -n "$filter_os" ] && [ "$os_type" != "$filter_os" ] && continue
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
            4 "Backup(s)" \
            5 "Back")
        
        case $CHOICE in
            1) execute_operation "reboot" ;;
            2) execute_operation "shutdown" ;;
            3) execute_operation "update" ;;
            4) execute_operation "backup" ;;
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
            --menu "Select option:" 17 60 7 \
            1 "Host Status" \
            2 "CPU Usage" \
            3 "Memory Usage" \
            4 "Disk Space" \
            5 "System Info" \
            6 "Event Logs" \
            7 "Back")
        
        case $CHOICE in
            1) check_all_hosts_status ;;
            2) execute_monitoring "cpu" ;;
            3) execute_monitoring "memory" ;;
            4) execute_monitoring "disk" ;;
            5) execute_monitoring "sysinfo" ;;
            6) execute_monitoring "events" ;;
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
    
    # Save a copy to logs and show
    save_log "$temp" "host_status"
    dialog --title "Host Status" --textbox "$temp" 20 60
    rm -f "$temp"
}

# ============================================================================
# FUNCIÓN PARA BACKUPS
# ============================================================================
execute_backup_operation() {
    
    # Declaramos las variables
    local os_type backup_sources backup_dir os
    local script_path_linux script_path_windows remote_temp_file

    os_type=$(dialog --stdout --title "OS Type" --menu "Select OS:" 12 40 2 1 "Linux (LVM Snapshot)" 2 "Windows")
    
    case $os_type in
        1) os="linux" ;;
        2) os="windows" ;;
        *) return ;;
    esac

    # 2. Mostrar menú SOLO de hosts del OS seleccionado
    select_hosts_by_os "$os" || return

    local ips=($(get_selected_ips "$SELECTED_IPS"))
    [ ${#ips[@]} -eq 0 ] && dialog --msgbox "No $os hosts ONLINE!" 8 50 && return

    # 3. Configuración según OS
    if [ "$os" == "linux" ]; then
        script_path_linux="$LOCAL_SCRIPTS_DIR/linux/backup.sh"
        
        # Cargamos las fuentes TAL CUAL vienen de la config (ej: "/etc /home")
        backup_sources="$LINUX_BACKUP_SOURCES"
        backup_dir="$LINUX_BACKUP_DIR"
        
        [ ! -f "$script_path_linux" ] && dialog --msgbox "ERROR: Script not found!\n\n$script_path_linux" 10 60 && return
    else
        script_path_windows="$LOCAL_SCRIPTS_DIR/windows/backup.ps1"
        backup_sources="$WINDOWS_BACKUP_SOURCES"
        backup_dir="$WINDOWS_BACKUP_DIR"
        [ ! -f "$script_path_windows" ] && dialog --msgbox "ERROR: Script not found!\n\n$script_path_windows" 10 60 && return
    fi

    # 3. Confirmar
    local confirm_msg="BACKUP de ${#ips[@]} ($os) system(s)?\n
    IPs: ${ips[*]}\n
    Fuentes: $backup_sources\n
    Destino: $backup_dir\n
    Nota: Linux usará LVM Snapshots."
    
    dialog --yesno "$confirm_msg" 15 70 || return

    # 4. Ejecutar backups con progreso
    local temp=$(mktemp)
    echo "=== Operation: BACKUP ($os) ===" > "$temp"
    echo "Date: $(date)" >> "$temp"
    echo "Target IPs: ${ips[*]}" >> "$temp"
    echo "" >> "$temp"

    local total_hosts=${#ips[@]}
    local counter=0

    (
    for ip in "${ips[@]}"; do
        percent=$(( (counter * 100) / total_hosts ))

        echo "XXX"
        echo "Procesando backup ($os) de $ip ($((counter+1))/$total_hosts)..."
        echo "XXX"
        echo $percent

        echo ">>> Host: $ip <<<" >> "$temp"

        if [ "$os" == "linux" ]; then
            # ---- Backup Linux (LVM SNAPSHOT) ----
            
            # Limpieza de rutas: convierte "/etc /home" en "etc home" para que funcione dentro del snapshot
            local clean_sources=$(echo "$backup_sources" | sed -e 's|^/||' -e 's| /| |g')

            # Ejecutamos pasando la variable limpia
            bash "$script_path_linux" "$ip" "$clean_sources" "$backup_dir" >> "$temp" 2>&1

        elif [ "$os" == "windows" ]; then
            # ---- Backup Windows ----
            # 1. Copiar el script al servidor Windows
            REMOTE_SCRIPT_PATH="C:\\Windows\\Temp\\backup_temp.ps1"
            echo "Copiando script de backup a $ip..." >> "$temp"
            sshpass -p "$WINDOWS_PASS" scp -q -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR "$script_path_windows" "${WINDOWS_USER}@${ip}:${REMOTE_SCRIPT_PATH}" >> "$temp" 2>&1
            
            if [ $? -ne 0 ]; then
                echo "ERROR: No se pudo copiar el script al servidor Windows" >> "$temp"
                continue
            fi
            
            # 2. Ejecutar el script remotamente
            echo "Ejecutando backup en $ip..." >> "$temp"
            REMOTE_FILE_PATH=$(sshpass -p "$WINDOWS_PASS" ssh -q -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR "${WINDOWS_USER}@${ip}" \
                "powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File '${REMOTE_SCRIPT_PATH}' -Paths '${backup_sources}' -DestFolder 'C:\\Windows\\Temp'" 2>&1 | tail -n 1)

            REMOTE_FILE_PATH=$(echo "$REMOTE_FILE_PATH" | tr -d '\r')

            if [[ -z "$REMOTE_FILE_PATH" || "$REMOTE_FILE_PATH" != *".tar.gz"* ]]; then
                echo "ERROR: No se generó el archivo remoto. Salida: $REMOTE_FILE_PATH" >> "$temp"
            else
                # 3. Obtener hostname de Windows
                WIN_HOSTNAME=$(sshpass -p "$WINDOWS_PASS" ssh -q -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR "${WINDOWS_USER}@${ip}" "hostname" 2>&1 | tr -d '\r\n')
                local_file_name="backup-WIN-${WIN_HOSTNAME:-$ip}-$(date +%Y-%m-%d_%H%M).tar.gz"
                
                # 4. Descargar el backup usando scp con sshpass
                echo "Descargando backup de $ip..." >> "$temp"
                sshpass -p "$WINDOWS_PASS" scp -q -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR "${WINDOWS_USER}@${ip}:${REMOTE_FILE_PATH}" "$backup_dir/$local_file_name" >> "$temp" 2>&1
                
                # 5. Limpiar archivos temporales en Windows (script y backup)
                sshpass -p "$WINDOWS_PASS" ssh -q -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR "${WINDOWS_USER}@${ip}" "del '${REMOTE_FILE_PATH}' '${REMOTE_SCRIPT_PATH}'" >> "$temp" 2>&1
                
                echo "Backup de $ip completado: $local_file_name" >> "$temp"
            fi
        fi

        echo "" >> "$temp"
        ((counter++))
    done
    ) | dialog --title "Pulling Backups..." --gauge "Iniciando..." 10 70 0

    dialog --title "Backup Results" --textbox "$temp" 22 70
    rm -f "$temp"
}

# ============================================================================
# Ejecutar operación del sistema (reboot, shutdown, update)
# $1: Tipo de operación
# ============================================================================
execute_operation() {
    local operation=$1
    
    if [ "$operation" == "backup" ]; then
        execute_backup_operation
        return
    fi
    
    select_hosts || return
    
    local ips=($(get_selected_ips "$SELECTED_IPS"))
    [ ${#ips[@]} -eq 0 ] && dialog --msgbox "No hosts ONLINE!" 8 50 && return
    
    local script_path script_args confirm_msg
    
    # Build a confirmation message and then execute per-host with correct script
    confirm_msg="${operation^^} ${#ips[@]} system(s)?\n\nIPs: ${ips[*]}\n\nAre you sure?"

    # (restart_service removed) No per-operation additional inputs required

    dialog --yesno "$confirm_msg" 12 60 || return

    local temp=$(mktemp)
    echo "=== Operation: $operation ===" > "$temp"
    echo "Date: $(date)" >> "$temp"
    echo "Target IPs: ${ips[*]}" >> "$temp"
    echo "" >> "$temp"

    for ip in "${ips[@]}"; do
        # lookup hostname and os info for clearer logs
        host_line=$(grep "|$ip|" "$CONFIG_FILE" 2>/dev/null || grep "$ip" "$CONFIG_FILE" 2>/dev/null || true)
        hostname_entry=$(echo "$host_line" | cut -d'|' -f1)
        os_type=$(echo "$host_line" | cut -d'|' -f3)
        echo ">>> ${hostname_entry:-unknown} ($ip) [${os_type:-unknown}] <<<" >> "$temp"

        # Determine OS for this host
        local os_type=$(grep "$ip" "$CONFIG_FILE" | cut -d'|' -f3)
        local script_path=""
        local script_args=""

        case $operation in
            reboot)
                if [ "$os_type" = "windows" ]; then
                    script_path="$LOCAL_SCRIPTS_DIR/windows/reboot.ps1"
                else
                    script_path="$LOCAL_SCRIPTS_DIR/linux/reboot.sh"
                fi
                ;;
            shutdown)
                if [ "$os_type" = "windows" ]; then
                    script_path="$LOCAL_SCRIPTS_DIR/windows/shutdown.ps1"
                else
                    script_path="$LOCAL_SCRIPTS_DIR/linux/shutdown.sh"
                fi
                ;;
            update)
                if [ "$os_type" = "windows" ]; then
                    script_path="$LOCAL_SCRIPTS_DIR/windows/update.ps1"
                else
                    script_path="$LOCAL_SCRIPTS_DIR/linux/update.sh"
                fi
                ;;
            # restart_service removed
        esac

        if [ -z "$script_path" ] || [ ! -f "$script_path" ]; then
            echo "ERROR: Script not found for $ip: $script_path" >> "$temp"
            echo "" >> "$temp"
            continue
        fi

        execute_local_script_remote "$ip" "$script_path" "$script_args" >> "$temp"
        echo "" >> "$temp"
    done
    
    # Save results to logs and show to user
    save_log "$temp" "${operation}_results"
    # Save custom command results to logs and display
    save_log "$temp" "custom_command"
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
    
    # Detectar si hay hosts Windows o Linux
    local first_ip=${ips[0]}
    local os_type=$(grep "$first_ip" "$CONFIG_FILE" | cut -d'|' -f3)
    
    # Prepare Linux and Windows script paths; execution will be per-host
    local win_cpu="$LOCAL_SCRIPTS_DIR/windows/monitor_cpu.ps1"
    local win_mem="$LOCAL_SCRIPTS_DIR/windows/monitor_memory.ps1"
    local win_disk="$LOCAL_SCRIPTS_DIR/windows/monitor_disk.ps1"
    local win_sys="$LOCAL_SCRIPTS_DIR/windows/monitor_sysinfo.ps1"
    local win_events="$LOCAL_SCRIPTS_DIR/windows/get_eventlogs.ps1"

    local linux_cpu="$LOCAL_SCRIPTS_DIR/linux/monitor_cpu.sh"
    local linux_mem="$LOCAL_SCRIPTS_DIR/linux/monitor_memory.sh"
    local linux_disk="$LOCAL_SCRIPTS_DIR/linux/monitor_disk.sh"
    local linux_sys="$LOCAL_SCRIPTS_DIR/linux/monitor_sysinfo.sh"
    local linux_events="$LOCAL_SCRIPTS_DIR/linux/get_syslogs.sh"

    local temp=$(mktemp)
    echo "=== Monitoring: $monitor_type ===" > "$temp"
    echo "Date: $(date)" >> "$temp"
    echo "IPs: ${ips[*]}" >> "$temp"
    echo "" >> "$temp"

    for ip in "${ips[@]}"; do
        # lookup hostname and os info for clearer logs
        host_line=$(grep "|$ip|" "$CONFIG_FILE" 2>/dev/null || grep "$ip" "$CONFIG_FILE" 2>/dev/null || true)
        hostname_entry=$(echo "$host_line" | cut -d'|' -f1)
        os_type=$(echo "$host_line" | cut -d'|' -f3)
        echo ">>> ${hostname_entry:-unknown} ($ip) [${os_type:-unknown}] <<<" >> "$temp"

        if [ "$os_type" = "windows" ]; then
            case $monitor_type in
                cpu) execute_local_script_remote "$ip" "$win_cpu" >> "$temp" ;;
                memory) execute_local_script_remote "$ip" "$win_mem" >> "$temp" ;;
                disk) execute_local_script_remote "$ip" "$win_disk" >> "$temp" ;;
                sysinfo) execute_local_script_remote "$ip" "$win_sys" >> "$temp" ;;
                events) execute_local_script_remote "$ip" "$win_events" >> "$temp" ;;
            esac
        else
            case $monitor_type in
                cpu) execute_local_script_remote "$ip" "$linux_cpu" >> "$temp" ;;
                memory) execute_local_script_remote "$ip" "$linux_mem" >> "$temp" ;;
                disk) execute_local_script_remote "$ip" "$linux_disk" >> "$temp" ;;
                sysinfo) execute_local_script_remote "$ip" "$linux_sys" >> "$temp" ;;
                events) execute_local_script_remote "$ip" "$linux_events" >> "$temp" ;;
            esac
        fi

        echo "" >> "$temp"
    done
    
    # Save monitoring output to logs and display
    save_log "$temp" "monitor_${monitor_type}"
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
    
    local cmd=$(dialog --stdout --inputbox "Enter command (runs as root/admin):" 10 60)
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
        host_line=$(grep "|$ip|" "$CONFIG_FILE" 2>/dev/null || grep "$ip" "$CONFIG_FILE" 2>/dev/null || true)
        hostname_entry=$(echo "$host_line" | cut -d'|' -f1)
        os_type_entry=$(echo "$host_line" | cut -d'|' -f3)
        echo ">>> ${hostname_entry:-unknown} ($ip) [${os_type_entry:-unknown}] <<<" >> "$temp"
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