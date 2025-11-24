#!/bin/bash

# ============================================================================
# REMOTE SYSTEM CONTROL INTERFACE
# ============================================================================
# Script to control remote Linux/Windows systems via SSH
# ============================================================================

CONFIG_FILE="hosts.conf"
LOCAL_SCRIPTS_DIR="local_scripts"
SSH_USER="root"
WINDOWS_USER="Administrator"
WINDOWS_PASS="1QAZxsw2"
LOG_DIR="logs"

# --- BACKUP VARIABLES ---
LINUX_BACKUP_DIR="backups/linux"
WINDOWS_BACKUP_DIR="backups/windows"
LINUX_BACKUP_SOURCES="/etc /var/log /home"
WINDOWS_BACKUP_SOURCES='C:\Users\Administrator\Documents C:\inetpub'

mkdir -p "$LINUX_BACKUP_DIR" "$WINDOWS_BACKUP_DIR"


 


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
# Check if a host is online (ping)
# $1: Host IP
# Returns: 0 if online, 1 if offline
# ============================================================================
check_host_online() {
    ping -c 1 -W 1 "$1" &> /dev/null
}

# ============================================================================
# Convert user selection into an array of ONLINE IPs
# $1: Selected IPs ("ALL" or "192.168.56.10 192.168.56.20")
# $2: Optional OS filter ("linux" or "windows")
# Returns: Array of IPs that are ONLINE
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
# View status (online/offline) of all hosts
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
# Show configuration file contents
# ============================================================================
view_hosts() {
    [ -f "$CONFIG_FILE" ] && dialog --textbox "$CONFIG_FILE" 20 70 || dialog --msgbox "Config not found!" 8 40
}

# ============================================================================
# Open configuration file in an editor
# ============================================================================
edit_config() {
    [ -f "$CONFIG_FILE" ] && ${EDITOR:-nano} "$CONFIG_FILE" || dialog --msgbox "Config not found!" 8 40
}

# ============================================================================
# Show menu to select hosts
# Modified global variable: SELECTED_IPS
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
# Show menu to select hosts filtered by OS
# $1: OS to filter ("linux" or "windows")
# Modified global variable: SELECTED_IPS
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
# MAIN MENU
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
# MENU: System Operations
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
# MENU: Monitoring
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
# MENU: Manage Hosts
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
# Execute a local script on a remote host
# $1: Host IP
# $2: Local script path
# $3: Optional arguments
# ============================================================================
execute_local_script_remote() {
    local host=$1
    local script_path=$2
    local args="${3:-}"
    
    [ ! -f "$script_path" ] && echo "ERROR: Script not found: $script_path" && return 1
    
    # Detect if Windows or Linux
    local os_type=$(grep "$host" "$CONFIG_FILE" | cut -d'|' -f3)
    
    if [ "$os_type" = "windows" ]; then
        # For Windows: send PowerShell script via stdin
        # Use flags to run PowerShell non-interactively and bypass execution policy.
        # Use quieter SSH/sshpass flags and avoid persisting host keys to suppress warnings.
        if [[ "$script_path" == *.ps1 ]]; then
            # PowerShell script: send it via stdin to powershell non-interactively
            sshpass -p "$WINDOWS_PASS" ssh -q -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR "${WINDOWS_USER}@${host}" "powershell -NoProfile  -ExecutionPolicy Bypass -Command -" < "$script_path" 2>&1
        else
            # Direct command
            sshpass -p "$WINDOWS_PASS" ssh -q -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR "${WINDOWS_USER}@${host}" "powershell -NoProfile  -ExecutionPolicy Bypass -Command \"$args\"" 2>&1
        fi
    else
        # For Linux: normal SSH
        ssh -o ConnectTimeout=5 "${SSH_USER}@${host}" "bash -s $args" < "$script_path" 2>&1
    fi
}

# ============================================================================
# Execute a direct command on a remote host
# $1: Host IP
# $2: Command to execute
# ============================================================================
ssh_exec() {
    local host=$1
    local command=$2
    
    # Detect if Windows or Linux
    local os_type=$(grep "$host" "$CONFIG_FILE" | cut -d'|' -f3)
    
    if [ "$os_type" = "windows" ]; then
    # For Windows: use sshpass with PowerShell (silence SSH warnings)
    sshpass -p "$WINDOWS_PASS" ssh -q -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR "${WINDOWS_USER}@${host}" "powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command \"$command\"" 2>&1
    else
        # For Linux: normal SSH
        ssh -o ConnectTimeout=5 "${SSH_USER}@${host}" "$command" 2>&1
    fi
}

# ============================================================================
# BACKUP FUNCTION
# ============================================================================
execute_backup_operation() {
    
    # Declare variables
    local os_type backup_sources backup_dir os
    local script_path_linux script_path_windows remote_temp_file

    os_type=$(dialog --stdout --title "OS Type" --menu "Select OS:" 12 40 2 1 "Linux (LVM Snapshot)" 2 "Windows")
    
    case $os_type in
        1) os="linux" ;;
        2) os="windows" ;;
        *) return ;;
    esac

    # 2. Show menu ONLY for hosts of selected OS
    select_hosts_by_os "$os" || return

    local ips=($(get_selected_ips "$SELECTED_IPS"))
    [ ${#ips[@]} -eq 0 ] && dialog --msgbox "No $os hosts ONLINE!" 8 50 && return

    # 3. Configuration according to OS
    if [ "$os" == "linux" ]; then
        script_path_linux="$LOCAL_SCRIPTS_DIR/linux/backup.sh"
        
        # Load sources AS-IS from config (e.g., "/etc /home")
        backup_sources="$LINUX_BACKUP_SOURCES"
        backup_dir="$LINUX_BACKUP_DIR"
        
        [ ! -f "$script_path_linux" ] && dialog --msgbox "ERROR: Script not found!\n\n$script_path_linux" 10 60 && return
    else
        script_path_windows="$LOCAL_SCRIPTS_DIR/windows/backup.ps1"
        backup_sources="$WINDOWS_BACKUP_SOURCES"
        backup_dir="$WINDOWS_BACKUP_DIR"
        [ ! -f "$script_path_windows" ] && dialog --msgbox "ERROR: Script not found!\n\n$script_path_windows" 10 60 && return
    fi

    # 3. Confirm
    local backup_method=""
    if [ "$os" == "linux" ]; then
        backup_method="Linux will use LVM Snapshots for consistency."
    else
        backup_method="Windows will use native tar with live files."
    fi
    
    local confirm_msg="BACKUP ${#ips[@]} ($os) system(s)?\n
    IPs: ${ips[*]}\n
    Sources: $backup_sources\n
    Destination: $backup_dir\n
    Note: $backup_method"
    
    dialog --yesno "$confirm_msg" 15 70 || return

    # 4. Execute backups with progress
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
        echo "Processing backup ($os) from $ip ($((counter+1))/$total_hosts)..."
        echo "XXX"
        echo $percent

        echo ">>> Host: $ip <<<" >> "$temp"

        if [ "$os" == "linux" ]; then
            # ---- Linux Backup (LVM SNAPSHOT) ----
            
            # Path cleanup: converts "/etc /home" to "etc home" to work within snapshot
            local clean_sources=$(echo "$backup_sources" | sed -e 's|^/||' -e 's| /| |g')

            # Execute passing the cleaned variable
            bash "$script_path_linux" "$ip" "$clean_sources" "$backup_dir" >> "$temp" 2>&1

        elif [ "$os" == "windows" ]; then
            # ---- Windows Backup (Simplified) ----
            echo "Running simplified backup on $ip..." >> "$temp"
            
            # Step 1: Verify that tar.exe exists
            echo "Verifying tar.exe..." >> "$temp"
            TAR_CHECK=$(sshpass -p "$WINDOWS_PASS" ssh -q -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR "${WINDOWS_USER}@${ip}" \
                "where tar.exe" 2>&1)
            echo "Tar check result: $TAR_CHECK" >> "$temp"
            
            if [[ "$TAR_CHECK" != *"tar.exe"* ]]; then
                echo "ERROR: tar.exe is not available on Windows. Requires Windows 10 1803+ or Windows 11" >> "$temp"
                continue
            fi
            
            # Step 2: Create filename
            WIN_HOSTNAME=$(sshpass -p "$WINDOWS_PASS" ssh -q -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR "${WINDOWS_USER}@${ip}" "hostname" 2>&1 | tr -d '\r\n')
            TIMESTAMP=$(date +%Y-%m-%d_%H%M%S)
            REMOTE_FILE_PATH="C:\\Windows\\Temp\\backup-${WIN_HOSTNAME:-$ip}-${TIMESTAMP}.tar.gz"
            
            echo "Destination file: $REMOTE_FILE_PATH" >> "$temp"
            
            # Step 3: Verify source paths
            echo "Verifying source paths..." >> "$temp"
            for path in $backup_sources; do
                PATH_CHECK=$(sshpass -p "$WINDOWS_PASS" ssh -q -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR "${WINDOWS_USER}@${ip}" \
                    "powershell -Command \"Test-Path '$path'\"" 2>&1 | tr -d '\r\n')
                echo "Path $path exists: $PATH_CHECK" >> "$temp"
            done
            
            # Step 4: Create backup with tar (all important user folders)
            echo "Running tar with multiple folders..." >> "$temp"
            TAR_OUTPUT=$(sshpass -p "$WINDOWS_PASS" ssh -o ConnectTimeout=60 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "${WINDOWS_USER}@${ip}" \
                "cd C:\\ && tar.exe -czf \"$REMOTE_FILE_PATH\" \"Users\\Administrator\\Documents\" \"Users\\Administrator\\Desktop\" \"Users\\Administrator\\Downloads\" \"Users\\Administrator\\Pictures\" \"Users\\Administrator\\Videos\" \"Users\\Administrator\\Music\" \"PerfLogs\" \"Program Files\" \"Windows\\System32\\drivers\\etc\" 2>&1" 2>&1)
            
            echo "=== TAR Output ===" >> "$temp"
            echo "$TAR_OUTPUT" >> "$temp"
            echo "=== End TAR Output ===" >> "$temp"
            
            # Step 5: Verify that the file was created
            FILE_CHECK=$(sshpass -p "$WINDOWS_PASS" ssh -q -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR "${WINDOWS_USER}@${ip}" \
                "powershell -Command \"Test-Path '$REMOTE_FILE_PATH'\"" 2>&1 | tr -d '\r\n')
                
            echo "File created: $FILE_CHECK" >> "$temp"

            if [[ "$FILE_CHECK" != "True" ]]; then
                echo "ERROR: Backup file was not generated" >> "$temp"
            else
                # 6. Download the backup (convert Windows path to SCP format)
                local_file_name="backup-WIN-${WIN_HOSTNAME:-$ip}-${TIMESTAMP}.tar.gz"
                SCP_REMOTE_PATH=$(echo "$REMOTE_FILE_PATH" | sed 's|C:\\Windows\\Temp\\|/cygdrive/c/Windows/Temp/|' | sed 's|\\\\|/|g')
                
                echo "Original path: $REMOTE_FILE_PATH" >> "$temp"
                echo "SCP path: $SCP_REMOTE_PATH" >> "$temp"
                echo "Downloading to: $backup_dir/$local_file_name" >> "$temp"
                
                # Try download with different path formats
                echo "Attempting download..." >> "$temp"
                if sshpass -p "$WINDOWS_PASS" scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "${WINDOWS_USER}@${ip}:\"$REMOTE_FILE_PATH\"" "$backup_dir/$local_file_name" >> "$temp" 2>&1; then
                    echo "✓ Successful download with Windows path" >> "$temp"
                elif sshpass -p "$WINDOWS_PASS" scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "${WINDOWS_USER}@${ip}:$SCP_REMOTE_PATH" "$backup_dir/$local_file_name" >> "$temp" 2>&1; then
                    echo "✓ Successful download with Cygwin path" >> "$temp"
                else
                    echo "✗ Download failed, trying with PSCP..." >> "$temp"
                    # As last resort, use PowerShell to copy the file
                    sshpass -p "$WINDOWS_PASS" ssh -o ConnectTimeout=30 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "${WINDOWS_USER}@${ip}" \
                        "powershell -Command \"[System.Convert]::ToBase64String([System.IO.File]::ReadAllBytes('$REMOTE_FILE_PATH'))\"" > "$backup_dir/${local_file_name}.b64" 2>>"$temp"
                    
                    if [ -f "$backup_dir/${local_file_name}.b64" ]; then
                        base64 -d "$backup_dir/${local_file_name}.b64" > "$backup_dir/$local_file_name" 2>>"$temp"
                        rm -f "$backup_dir/${local_file_name}.b64"
                        echo "✓ Successful download with Base64" >> "$temp"
                    else
                        echo "✗ Complete download failure" >> "$temp"
                    fi
                fi
                
                # 7. Verify that the file was downloaded
                if [ -f "$backup_dir/$local_file_name" ]; then
                    FILE_SIZE=$(ls -lh "$backup_dir/$local_file_name" | awk '{print $5}')
                    echo "✓ File downloaded: $local_file_name (${FILE_SIZE})" >> "$temp"
                    
                    # 8. Clean up temporary file on Windows
                    sshpass -p "$WINDOWS_PASS" ssh -q -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR "${WINDOWS_USER}@${ip}" \
                        "del \"$REMOTE_FILE_PATH\"" >> "$temp" 2>&1
                    
                    echo "Backup of $ip completed: $local_file_name" >> "$temp"
                else
                    echo "ERROR: The file could not be downloaded to the local folder" >> "$temp"
                fi
            fi
        fi

        echo "" >> "$temp"
        ((counter++))
    done
    ) | dialog --title "Pulling Backups..." --gauge "Starting..." 10 70 0

    dialog --title "Backup Results" --textbox "$temp" 22 70
    rm -f "$temp"
}

# ============================================================================
# Execute system operation (reboot, shutdown, update)
# $1: Operation type
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
    
    # Build confirmation message and then execute per-host with correct script
    confirm_msg="${operation^^} ${#ips[@]} system(s)?\n\nIPs: ${ips[*]}\n\nAre you sure?"

    # (restart_service removed) No per-operation additional inputs required

    dialog --yesno "$confirm_msg" 12 60 || return

    local temp=$(mktemp)
    echo "=== Operation: $operation ===" > "$temp"
    echo "Date: $(date)" >> "$temp"
    echo "Target IPs: ${ips[*]}" >> "$temp"
    echo "" >> "$temp"

    for ip in "${ips[@]}"; do
        # Lookup hostname and OS info for clearer logs
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
    # Save results to logs and display
    save_log "$temp" "custom_command"
    dialog --title "Results" --textbox "$temp" 22 70
    rm -f "$temp"
}

# ============================================================================
# Execute monitoring command (cpu, memory, disk, sysinfo)
# $1: Monitoring type
# ============================================================================
execute_monitoring() {
    local monitor_type=$1
    
    select_hosts || return
    
    local ips=($(get_selected_ips "$SELECTED_IPS"))
    [ ${#ips[@]} -eq 0 ] && dialog --msgbox "No hosts ONLINE!" 8 40 && return
    
    local command
    
    # Detect if there are Windows or Linux hosts
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
# Execute custom command written by the user
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
# SCRIPT START
# ============================================================================
main_menu