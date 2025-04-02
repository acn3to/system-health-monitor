#!/bin/bash
# health_check_with_summary.sh
# This script checks CPU/GPU temperatures, NVMe disk health, error logs, and then prints a summary.
# Some commands require root privileges, so run the script with sudo if needed.
#
# Usage:
#   ./health_check_sudo.sh        - Run health check only
#   ./health_check_sudo.sh --fix  - Run health check and fix issues if needed

LOG_FILE="/var/log/health_check.log"

# Parse command line arguments
FIX_ISSUES=false
if [[ "$1" == "--fix" ]]; then
    FIX_ISSUES=true
fi

# Add help message
if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    echo -e "System Health Monitor - Usage Guide"
    echo -e "----------------------------------"
    echo -e "This script checks various aspects of system health and can automatically fix common issues."
    echo -e ""
    echo -e "Usage:"
    echo -e "  ./system-health.sh             Run health check only"
    echo -e "  ./system-health.sh --fix       Run health check and fix issues"
    echo -e "  ./system-health.sh --help      Display this help message"
    echo -e ""
    echo -e "Features:"
    echo -e "  - CPU/GPU temperature monitoring"
    echo -e "  - Memory and disk usage analysis"
    echo -e "  - NVMe drive health check (if available)"
    echo -e "  - Package manager status and updates"
    echo -e "  - Docker/Podman container status"
    echo -e "  - Network information"
    echo -e "  - System error log analysis"
    echo -e ""
    echo -e "Automatic Fixes (with --fix option):"
    echo -e "  - Clear package manager locks"
    echo -e "  - Update system packages"
    echo -e "  - Handle kept-back packages"
    echo -e "  - Install missing monitoring tools"
    echo -e ""
    echo -e "Note: Some operations require root privileges. Run with sudo if needed."
    exit 0
fi

# Define color codes
GREEN="\033[0;32m"
YELLOW="\033[0;33m"
RED="\033[0;31m"
BLUE="\033[0;34m"
PURPLE="\033[0;35m"
CYAN="\033[0;36m"
BOLD="\033[1m"
UNDERLINE="\033[4m"
NC="\033[0m" # No Color

# Status indicators
OK="${GREEN}✓${NC}"
WARNING="${YELLOW}⚠${NC}"
CRITICAL="${RED}✗${NC}"
INFO="${BLUE}ℹ${NC}"

# Print header
echo -e "${BOLD}${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${BLUE}║             SYSTEM HEALTH CHECK REPORT                     ║${NC}"
echo -e "${BOLD}${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo -e "${CYAN}Report generated at:${NC} $(date)"
echo -e "${CYAN}Hostname:${NC} $(hostname) ${CYAN}| Kernel:${NC} $(uname -r) ${CYAN}| Uptime:${NC} $(uptime -p)"
if $FIX_ISSUES; then
    echo -e "${CYAN}Mode:${NC} ${GREEN}Check and Fix${NC}"
else
    echo -e "${CYAN}Mode:${NC} ${BLUE}Check Only${NC} (use --fix to automatically fix issues)"
fi
echo ""

# Fix for decimal format issues - force using period as decimal separator
export LC_NUMERIC=C

############################
# 1. System Summary Dashboard
############################
echo -e "${BOLD}${UNDERLINE}SYSTEM DASHBOARD${NC}"

# CPU Usage
cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2 + $4}')
if (( $(echo "$cpu_usage > 90" | bc -l) )); then
    cpu_status="$CRITICAL"
elif (( $(echo "$cpu_usage > 70" | bc -l) )); then
    cpu_status="$WARNING"
else
    cpu_status="$OK"
fi

# Memory Usage
mem_used_percent=$(free | grep Mem | awk '{print int($3/$2 * 100)}')
if [ "$mem_used_percent" -gt 90 ]; then
    mem_status="$CRITICAL"
elif [ "$mem_used_percent" -gt 70 ]; then
    mem_status="$WARNING"
else
    mem_status="$OK"
fi

# Get highest disk usage percentage (exclude temporary mounts and docker mounts)
highest_disk_usage=$(df -h -x tmpfs -x devtmpfs -x fuse.cursor -x squashfs | grep -v '/snap/' | awk 'NR>1 {gsub("%",""); if ($5 > max) max=$5} END {print max}')
if [ "$highest_disk_usage" -gt 90 ]; then
    disk_status="$CRITICAL"
elif [ "$highest_disk_usage" -gt 80 ]; then
    disk_status="$WARNING"
else
    disk_status="$OK"
fi

# Get CPU temperature
if command -v sensors >/dev/null 2>&1; then
    sensors_output=$(sensors)
    max_cpu_temp=$(echo "$sensors_output" | awk '/Core/ {
        gsub("[^0-9.]", "", $3);
        if ($3+0 > max) max=$3
    } END {print max}')
    
    if (( $(echo "$max_cpu_temp > 85" | bc -l) )); then
        cpu_temp_status="$CRITICAL"
    elif (( $(echo "$max_cpu_temp > 75" | bc -l) )); then
        cpu_temp_status="$WARNING"
    else
        cpu_temp_status="$OK"
    fi
else
    max_cpu_temp="N/A"
    cpu_temp_status="$INFO"
fi

# Get GPU temperature if available
if command -v nvidia-smi >/dev/null 2>&1; then
    nvidia_output=$(nvidia-smi)
    # Try different methods to extract the temperature
    gpu_temp=$(echo "$nvidia_output" | grep -o "[0-9]\+C" | head -1 | sed 's/C//')
    if [ -z "$gpu_temp" ]; then
        gpu_temp=$(nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader 2>/dev/null | head -1 | tr -d ' ')
    fi
    
    if [ -n "$gpu_temp" ]; then
        if [ "$gpu_temp" -gt 85 ]; then
            gpu_status="$CRITICAL"
        elif [ "$gpu_temp" -gt 75 ]; then
            gpu_status="$WARNING"
        else
            gpu_status="$OK"
        fi
    else
        gpu_temp="N/A"
        gpu_status="$INFO"
    fi
else
    gpu_temp="N/A"
    gpu_status="$INFO"
fi

# Check for errors in logs
error_count=$(sudo journalctl -p err -n 10 2>/dev/null | grep -v "apparmor=STATUS" | \
               grep -v "snapd" | grep -v "smartd" | grep -v "sudo:" | grep -c . || echo "0")
recent_errors=$(sudo journalctl -p err -n 5 2>/dev/null | grep -v "apparmor=STATUS" | \
                grep -v "snapd" | grep -v "smartd" | grep -v "sudo:" || echo "")

if [ "$error_count" -gt 10 ]; then
    error_status="$CRITICAL"
elif [ "$error_count" -gt 0 ]; then
    error_status="$WARNING"
else
    error_status="$OK"
fi

# Count running docker containers - more robust method
if command -v docker >/dev/null 2>&1; then
    docker_count=$(docker ps --format '{{.ID}}' 2>/dev/null | wc -l || echo "0")
else
    docker_count="N/A"
fi

# Check for pending updates
needs_updates=false
systemd_updates=false
if command -v apt >/dev/null 2>&1; then
    updates=$(apt list --upgradable 2>/dev/null | grep -v "Listing" | wc -l)
    
    # Check if updates are systemd related
    if apt list --upgradable 2>/dev/null | grep -q "systemd"; then
        systemd_updates=true
    fi
    
    if [ "$updates" -gt 50 ]; then
        update_status="$CRITICAL"
        needs_updates=true
    elif [ "$updates" -gt 10 ]; then
        update_status="$WARNING"
        needs_updates=true
    else
        update_status="$OK"
    fi
elif command -v dnf >/dev/null 2>&1; then
    updates=$(dnf check-update --quiet | wc -l)
    if [ "$updates" -gt 50 ]; then
        update_status="$CRITICAL"
        needs_updates=true
    elif [ "$updates" -gt 10 ]; then
        update_status="$WARNING"
        needs_updates=true
    else
        update_status="$OK"
    fi
elif command -v pacman >/dev/null 2>&1; then
    updates=$(pacman -Qu | wc -l)
    if [ "$updates" -gt 50 ]; then
        update_status="$CRITICAL"
        needs_updates=true
    elif [ "$updates" -gt 10 ]; then
        update_status="$WARNING"
        needs_updates=true
    else
        update_status="$OK"
    fi
else
    updates="N/A"
    update_status="$INFO"
fi

# Check for package lock files
dpkg_locked=false
our_pid=$$

# For improved user experience, in fix mode we'll completely ignore locks 
# as we'll be clearing them anyway
if ! $FIX_ISSUES; then
    # Only check for actual running processes, not stale lock files
    # This avoids false positives from lock files left behind
    apt_processes=$(pgrep -a "apt|dpkg|aptitude" | grep -v "$our_pid" 2>/dev/null)
    
    if [ -n "$apt_processes" ]; then
        dpkg_locked=true
    fi
fi

# Dashboard display
echo -e "┌─────────────────────────┬─────────────────────────┐"
echo -e "│ ${BOLD}CPU Usage:${NC} ${cpu_usage}% ${cpu_status} │ ${BOLD}Memory:${NC} ${mem_used_percent}% ${mem_status} │"
echo -e "├─────────────────────────┼─────────────────────────┤"
echo -e "│ ${BOLD}CPU Temp:${NC} ${max_cpu_temp}°C ${cpu_temp_status} │ ${BOLD}GPU Temp:${NC} ${gpu_temp}°C ${gpu_status} │"
echo -e "├─────────────────────────┼─────────────────────────┤"
echo -e "│ ${BOLD}Disk Usage:${NC} ${highest_disk_usage}% ${disk_status} │ ${BOLD}Updates:${NC} ${updates} ${update_status} │"
echo -e "├─────────────────────────┼─────────────────────────┤"
echo -e "│ ${BOLD}Containers:${NC} ${docker_count} ${INFO} │ ${BOLD}Errors:${NC} ${error_count} ${error_status} │"
echo -e "└─────────────────────────┴─────────────────────────┘"

# Show systemd update notification if needed
if $systemd_updates; then
    echo -e "${YELLOW}Note: System has pending systemd updates which require a reboot${NC}"
    echo -e "${YELLOW}After updates: sudo reboot${NC}"
fi

echo ""

############################
# 2. CPU Information
############################
echo -e "${BOLD}${UNDERLINE}CPU INFORMATION${NC}"
echo -e "${CYAN}Load Averages:${NC} $(uptime | awk -F'load average:' '{print $2}')"

# CPU Temperatures
if command -v sensors >/dev/null 2>&1; then
    echo -e "${CYAN}CPU Temperatures:${NC}"
    sensors | grep -E 'Core|Package' | sed 's/+//g' | while IFS= read -r line; do
        temp=$(echo "$line" | awk '{gsub(/[^0-9.]/, "", $3); print $3}')
        if (( $(echo "$temp > 85" | bc -l) )); then
            echo -e "  $line ${RED}(HOT)${NC}"
        elif (( $(echo "$temp > 75" | bc -l) )); then
            echo -e "  $line ${YELLOW}(WARM)${NC}"
        else
            echo -e "  $line ${GREEN}(OK)${NC}"
        fi
    done
else
    echo -e "${YELLOW}lm-sensors is not installed. Please install it (sudo apt install lm-sensors).${NC}"
fi
echo ""

############################
# 3. Memory Information
############################
echo -e "${BOLD}${UNDERLINE}MEMORY INFORMATION${NC}"
echo -e "${CYAN}Memory Usage:${NC}"
free -h | awk 'NR==1 {printf "  %-12s %10s %10s %10s %10s %10s\n", $1, $2, $3, $4, $6, $7}
               NR==2 {printf "  %-12s %10s %10s %10s %10s %10s",$1, $2, $3, $4, $6, $7}'
if [ "$mem_used_percent" -gt 90 ]; then
    echo -e " ${RED}(CRITICAL: ${mem_used_percent}%)${NC}"
elif [ "$mem_used_percent" -gt 70 ]; then
    echo -e " ${YELLOW}(WARNING: ${mem_used_percent}%)${NC}"
else
    echo -e " ${GREEN}(OK: ${mem_used_percent}%)${NC}"
fi

# Swap Information
echo -e "${CYAN}Swap Usage:${NC}"
swap_used_percent=$(free | grep Swap | awk '{if ($2 > 0) print int($3/$2 * 100); else print "0"}')
free -h | grep Swap
if [ "$swap_used_percent" -gt 50 ]; then
    echo -e "  Swap Usage: ${swap_used_percent}% ${RED}(HIGH)${NC}"
elif [ "$swap_used_percent" -gt 20 ]; then
    echo -e "  Swap Usage: ${swap_used_percent}% ${YELLOW}(MODERATE)${NC}"
else
    echo -e "  Swap Usage: ${swap_used_percent}% ${GREEN}(OK)${NC}"
fi
echo ""

############################
# 4. Disk Information
############################
echo -e "${BOLD}${UNDERLINE}DISK INFORMATION${NC}"
echo -e "${CYAN}Disk Usage:${NC}"
echo -e "  Filesystem                Size    Used   Avail   Use%   Mounted on"
df -h -x tmpfs -x devtmpfs | grep -v "Filesystem" | while read line; do
    usage=$(echo $line | awk '{print $5}' | sed 's/%//')
    if [ "$usage" -gt 90 ]; then
        # Check if it's a temporary mount
        mount_point=$(echo $line | awk '{print $6}')
        if [[ "$mount_point" == "/tmp/"* || "$mount_point" == *"/snap/"* || "$mount_point" == *".mount_"* ]]; then
            echo -e "  $line ${BLUE}(TEMP)${NC}"
        else
            echo -e "  $line ${RED}(CRITICAL)${NC}"
        fi
    elif [ "$usage" -gt 80 ]; then
        echo -e "  $line ${YELLOW}(WARNING)${NC}"
    else
        echo -e "  $line ${GREEN}(OK)${NC}"
    fi
done

# NVMe Health if available
NVME_DEVICE="/dev/nvme0n1"
if [ -e "$NVME_DEVICE" ]; then
    if command -v smartctl >/dev/null 2>&1; then
        echo -e "${CYAN}NVMe Disk Health:${NC}"
        disk_health=$(smartctl -H "$NVME_DEVICE" 2>/dev/null)
        health_status=$(echo "$disk_health" | grep -i "SMART overall-health")
        
        if [[ "$health_status" == *"PASSED"* ]]; then
            echo -e "  $health_status ${GREEN}(HEALTHY)${NC}"
        elif [ -z "$health_status" ]; then
            echo -e "  ${YELLOW}Unable to read SMART health data. Try running with sudo.${NC}"
        else
            echo -e "  $health_status ${RED}(FAILING)${NC}"
            # Show some additional SMART data if it's failing
            echo -e "  ${YELLOW}SMART Error Details:${NC}"
            smartctl -a "$NVME_DEVICE" | grep -E "Error|Wear|Life|Media|Unsafe" | head -5 | sed 's/^/    /'
        fi
        
        # Extract NVMe temperature
        nvme_temp=$(smartctl -a "$NVME_DEVICE" 2>/dev/null | grep -i "Temperature:" | head -1 | awk '{print $2}')
        if [ -z "$nvme_temp" ]; then
            nvme_temp=$(smartctl -a "$NVME_DEVICE" 2>/dev/null | grep -i "Sensor 1:" | head -1 | awk '{print $3}' | sed 's/+//;s/°C//')
        fi
        
        if [ -n "$nvme_temp" ]; then
            if (( $(echo "$nvme_temp > 70" | bc -l) )); then
                echo -e "  Temperature: ${nvme_temp}°C ${RED}(HOT)${NC}"
            elif (( $(echo "$nvme_temp > 60" | bc -l) )); then
                echo -e "  Temperature: ${nvme_temp}°C ${YELLOW}(WARM)${NC}"
            else
                echo -e "  Temperature: ${nvme_temp}°C ${GREEN}(OK)${NC}"
            fi
        fi
    else
        echo -e "${YELLOW}smartctl is not installed. Please install smartmontools (sudo apt install smartmontools).${NC}"
    fi
fi

# I/O Statistics if available
if command -v iostat >/dev/null 2>&1; then
    echo -e "${CYAN}Disk I/O Statistics:${NC}"
    iostat -dxh 1 1 | grep -v "loop" | grep -v "^$" | tail -n +4
else
    echo -e "${YELLOW}iostat not found. Install sysstat package to get I/O statistics.${NC}"
fi
echo ""

############################
# 5. GPU Information
############################
if command -v nvidia-smi >/dev/null 2>&1; then
    echo -e "${BOLD}${UNDERLINE}GPU INFORMATION${NC}"
    echo -e "${CYAN}NVIDIA GPU Status:${NC}"
    # Extract the relevant parts of nvidia-smi output using a more reliable method
    gpu_info=$(nvidia-smi --query-gpu=name,temperature.gpu,utilization.gpu,utilization.memory,memory.used,memory.total,power.draw --format=csv,noheader 2>/dev/null)
    if [ -n "$gpu_info" ]; then
        echo "$gpu_info" | while IFS="," read -r name temp util mem_util mem_used mem_total power; do
            echo -e "  ${BOLD}Model:${NC}$(echo $name | xargs)"
            
            # Format temperature with color
            temp_value=$(echo $temp | xargs | tr -cd '0-9')
            if [ -n "$temp_value" ]; then
                if [ "$temp_value" -gt 85 ]; then
                    echo -e "  ${BOLD}Temperature:${NC} ${temp_value}°C ${RED}(HOT)${NC}"
                elif [ "$temp_value" -gt 75 ]; then
                    echo -e "  ${BOLD}Temperature:${NC} ${temp_value}°C ${YELLOW}(WARM)${NC}"
                else
                    echo -e "  ${BOLD}Temperature:${NC} ${temp_value}°C ${GREEN}(OK)${NC}"
                fi
            fi
            
            # Usage and memory
            echo -e "  ${BOLD}GPU Utilization:${NC}$(echo $util | xargs)"
            echo -e "  ${BOLD}Memory Used:${NC}$(echo $mem_used | xargs) /$(echo $mem_total | xargs)"
            echo -e "  ${BOLD}Power Draw:${NC}$(echo $power | xargs)"
        done
    else
        # Fallback to simpler output if the query format doesn't work
        echo "$nvidia_output" | grep -E "Model|Temp|Memory-Usage|Power" | sed 's/^/  /'
    fi
    
    # Display running GPU processes
    echo -e "${CYAN}GPU Processes:${NC}"
    gpu_processes=$(nvidia-smi --query-compute-apps=pid,process_name,used_memory --format=csv,noheader 2>/dev/null)
    if [ -n "$gpu_processes" ] && [ "$(echo "$gpu_processes" | wc -l)" -gt 0 ]; then
        echo "$gpu_processes" | while read line; do
            echo "  $line"
        done
    else
        echo "  No GPU processes running"
    fi
    echo ""
# Added support for AMD GPUs
elif command -v rocm-smi >/dev/null 2>&1; then
    echo -e "${BOLD}${UNDERLINE}GPU INFORMATION${NC}"
    echo -e "${CYAN}AMD GPU Status:${NC}"
    
    # Get AMD GPU model and temperature
    amd_gpu_model=$(rocm-smi --showproductname | grep -v "====" | tail -n +3 | head -1 | awk '{$1=""; print $0}' | xargs)
    amd_gpu_temp=$(rocm-smi --showtemp | grep -v "====" | tail -n +3 | head -1 | awk '{print $2}' | tr -cd '0-9.')
    amd_gpu_usage=$(rocm-smi --showuse | grep -v "====" | tail -n +3 | head -1 | awk '{print $2}')
    amd_gpu_mem=$(rocm-smi --showmemuse | grep -v "====" | tail -n +3 | head -1 | awk '{print $2}')
    amd_gpu_power=$(rocm-smi --showpower | grep -v "====" | tail -n +3 | head -1 | awk '{print $2 " " $3}')
    
    echo -e "  ${BOLD}Model:${NC} $amd_gpu_model"
    
    # Format temperature with color
    if [ -n "$amd_gpu_temp" ]; then
        if (( $(echo "$amd_gpu_temp > 85" | bc -l) )); then
            echo -e "  ${BOLD}Temperature:${NC} ${amd_gpu_temp}°C ${RED}(HOT)${NC}"
        elif (( $(echo "$amd_gpu_temp > 75" | bc -l) )); then
            echo -e "  ${BOLD}Temperature:${NC} ${amd_gpu_temp}°C ${YELLOW}(WARM)${NC}"
        else
            echo -e "  ${BOLD}Temperature:${NC} ${amd_gpu_temp}°C ${GREEN}(OK)${NC}"
        fi
        # Update global gpu_temp variable for status checks
        gpu_temp=${amd_gpu_temp%.*}
    fi
    
    # Show usage info
    [ -n "$amd_gpu_usage" ] && echo -e "  ${BOLD}GPU Utilization:${NC} $amd_gpu_usage"
    [ -n "$amd_gpu_mem" ] && echo -e "  ${BOLD}Memory Used:${NC} $amd_gpu_mem"
    [ -n "$amd_gpu_power" ] && echo -e "  ${BOLD}Power Draw:${NC} $amd_gpu_power"
    
    echo ""
# Check for Intel integrated graphics
elif [ -d "/sys/class/drm/card0/device" ]; then
    # Look for intel_gpu_top command
    if command -v intel_gpu_top >/dev/null 2>&1; then
        echo -e "${BOLD}${UNDERLINE}GPU INFORMATION${NC}"
        echo -e "${CYAN}Intel GPU Status:${NC}"
        
        # Try to get Intel GPU info
        intel_gpu_model=$(lspci | grep -i 'VGA.*Intel' | sed 's/.*: //')
        
        # Try to get temperature (only works on some systems)
        if [ -f "/sys/class/drm/card0/device/hwmon/hwmon*/temp1_input" ]; then
            intel_temp_file=$(find /sys/class/drm/card0/device/hwmon/hwmon* -name temp1_input 2>/dev/null | head -1)
            if [ -n "$intel_temp_file" ]; then
                intel_gpu_temp=$(cat "$intel_temp_file" 2>/dev/null)
                intel_gpu_temp=$((intel_gpu_temp / 1000))
                
                echo -e "  ${BOLD}Model:${NC} $intel_gpu_model"
                
                # Format temperature with color
                if [ -n "$intel_gpu_temp" ]; then
                    if [ "$intel_gpu_temp" -gt 85 ]; then
                        echo -e "  ${BOLD}Temperature:${NC} ${intel_gpu_temp}°C ${RED}(HOT)${NC}"
                    elif [ "$intel_gpu_temp" -gt 75 ]; then
                        echo -e "  ${BOLD}Temperature:${NC} ${intel_gpu_temp}°C ${YELLOW}(WARM)${NC}"
                    else
                        echo -e "  ${BOLD}Temperature:${NC} ${intel_gpu_temp}°C ${GREEN}(OK)${NC}"
                    fi
                    # Update global gpu_temp variable for status checks
                    gpu_temp=$intel_gpu_temp
                fi
            fi
        fi
        
        # Run quick intel_gpu_top for brief stats
        echo -e "  ${BOLD}GPU Activity:${NC}"
        timeout 0.5s intel_gpu_top -J 2>/dev/null | grep -E "busy|engines" | head -3 | sed 's/^/    /'
        
        echo ""
    fi
fi

############################
# 6. Container Information
############################
echo -e "${BOLD}${UNDERLINE}CONTAINER INFORMATION${NC}"

# Check Docker - more robust method with error handling
if command -v docker >/dev/null 2>&1; then
    echo -e "${CYAN}Docker Containers:${NC}"
    docker_running=$(docker ps --format '{{.ID}}' 2>/dev/null | wc -l || echo "0")
    docker_total=$(docker ps -a --format '{{.ID}}' 2>/dev/null | wc -l || echo "0")
    echo -e "  Running: ${docker_running} | Total: ${docker_total}"
    
    if [ "$docker_running" -gt 0 ]; then
        echo -e "${CYAN}Running Containers:${NC}"
        docker ps --format "  {{.Names}}: {{.Status}} (Image: {{.Image}})" 2>/dev/null || echo "  Error retrieving container details"
    fi
else
    echo -e "  Docker not installed or not in PATH"
fi

# Check Podman
if command -v podman >/dev/null 2>&1; then
    echo -e "${CYAN}Podman Containers:${NC}"
    podman_count=$(podman ps -q 2>/dev/null | wc -l || echo "0")
    podman_total=$(podman ps -aq 2>/dev/null | wc -l || echo "0")
    echo -e "  Running: ${podman_count} | Total: ${podman_total}"
    
    if [ "$podman_count" -gt 0 ]; then
        echo -e "${CYAN}Running Containers:${NC}"
        podman ps --format "  {{.Names}}: {{.Status}}" 2>/dev/null || echo "  Error retrieving container details"
    fi
else
    echo -e "  Podman not installed or not in PATH"
fi
echo ""

############################
# 7. Network Information
############################
echo -e "${BOLD}${UNDERLINE}NETWORK INFORMATION${NC}"

# Check network interface statistics
echo -e "${CYAN}Network Interfaces:${NC}"
ip -br addr show | grep -v "^lo"

# Show network traffic if available
if command -v ifstat >/dev/null 2>&1; then
    echo -e "${CYAN}Network Traffic (KB/s):${NC}"
    ifstat -i $(ip -br addr show | grep -v "^lo" | awk '{print $1}' | tr '\n' ' ') -q 1 1
elif command -v bwm-ng >/dev/null 2>&1; then
    echo -e "${CYAN}Network Traffic:${NC}"
    bwm-ng -o csv -c 1 -T rate -u bits | grep total
elif command -v nethogs >/dev/null 2>&1; then
    echo -e "${CYAN}Top Network Processes:${NC}"
    sudo nethogs -t -c 2 | head -10
fi

# Show active connections
if command -v ss >/dev/null 2>&1; then
    echo -e "${CYAN}Active Network Connections:${NC}"
    conn_count=$(ss -tuln | wc -l)
    echo -e "  Total Connections: ${conn_count}"
    echo -e "${CYAN}Listening Ports:${NC}"
    ss -tuln | grep LISTEN | grep -v "127.0.0.1" | awk '{print "  " $5}' | sort | head -5
fi
echo ""

############################
# 8. Error Logs
############################
echo -e "${BOLD}${UNDERLINE}SYSTEM LOGS${NC}"
echo -e "${CYAN}Recent Error Logs (last 5):${NC}"
if [ -n "$recent_errors" ]; then
    echo "$recent_errors" | while read line; do
        echo -e "  $line" | grep --color=auto -E "error|warning|fail|critical"
    done
else
    echo -e "  ${GREEN}No significant errors found${NC}"
fi

echo -e "${CYAN}Recent Kernel Messages:${NC}"
sudo dmesg | tail -n 5 | while read line; do
    echo -e "  $line"
done
echo ""

echo "========== Health Check Complete =========="
echo ""

############################
# 9. Summary Evaluation
############################
echo -e "${BOLD}${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${BLUE}║             SYSTEM HEALTH SUMMARY                          ║${NC}"
echo -e "${BOLD}${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"

# Define threshold values (adjust as needed)
cpu_threshold=80.0      # degrees Celsius for CPU cores
gpu_threshold=80        # degrees Celsius for GPU
nvme_threshold=70       # degrees Celsius for NVMe drive
error_threshold=1       # more than 1 error log line triggers warning
mem_threshold=90        # memory usage percentage
disk_threshold=90       # disk usage percentage

# Overall status evaluation
status="${GREEN}HEALTHY${NC}"
issues_found=0

# Print issues
echo -e "${BOLD}System Status Checks:${NC}"

# CPU Check
if (( $(echo "$max_cpu_temp > $cpu_threshold" | bc -l) )); then
    echo -e "  ${WARNING} CPU temperature is high at ${max_cpu_temp}°C"
    status="${YELLOW}WARNING${NC}"
    ((issues_found++))
else
    echo -e "  ${OK} CPU temperature normal at ${max_cpu_temp}°C"
fi

# Memory Check
if [ "$mem_used_percent" -gt "$mem_threshold" ]; then
    echo -e "  ${WARNING} Memory usage is high at ${mem_used_percent}%"
    status="${YELLOW}WARNING${NC}"
    ((issues_found++))
else
    echo -e "  ${OK} Memory usage normal at ${mem_used_percent}%"
fi

# Disk Check
if [ "$highest_disk_usage" -gt "$disk_threshold" ]; then
    echo -e "  ${WARNING} Disk usage is high at ${highest_disk_usage}%"
    status="${YELLOW}WARNING${NC}"
    ((issues_found++))
else
    echo -e "  ${OK} Disk usage normal at ${highest_disk_usage}%"
fi

# GPU Check
if [ "$gpu_temp" != "N/A" ] && [ "$gpu_temp" -gt "$gpu_threshold" ]; then
    echo -e "  ${WARNING} GPU temperature is high at ${gpu_temp}°C"
    status="${YELLOW}WARNING${NC}"
    ((issues_found++))
elif [ "$gpu_temp" != "N/A" ]; then
    echo -e "  ${OK} GPU temperature normal at ${gpu_temp}°C"
fi

# NVMe Check
if [ -n "$nvme_temp" ] && (( $(echo "$nvme_temp > $nvme_threshold" | bc -l) )); then
    echo -e "  ${WARNING} NVMe drive temperature is high at ${nvme_temp}°C"
    status="${YELLOW}WARNING${NC}"
    ((issues_found++))
elif [ -n "$nvme_temp" ]; then
    echo -e "  ${OK} NVMe drive temperature normal at ${nvme_temp}°C"
else
    echo -e "  ${INFO} NVMe drive temperature data not available"
fi

# Error Log Check
if [ "$error_count" -gt "$error_threshold" ]; then
    echo -e "  ${WARNING} There are ${error_count} recent error log entries"
    status="${YELLOW}WARNING${NC}"
    ((issues_found++))
else
    echo -e "  ${OK} Error log count normal"
fi

# Package Manager Checks
if $dpkg_locked; then
    echo -e "  ${WARNING} Package manager is locked (dpkg lock files found)"
    status="${YELLOW}WARNING${NC}"
    ((issues_found++))
else
    echo -e "  ${OK} Package manager is not locked"
fi

if $needs_updates; then
    echo -e "  ${WARNING} System has ${updates} pending updates"
    status="${YELLOW}WARNING${NC}"
    ((issues_found++))
else
    echo -e "  ${OK} System is up to date"
fi

echo -e "\n${BOLD}Overall System Health: ${status}${NC}"

# Determine available fixes
if $FIX_ISSUES && [ $issues_found -gt 0 ]; then
    echo -e "\n${BOLD}${GREEN}Attempting to fix issues:${NC}"
    
    # Fix dpkg locks if needed
    if $dpkg_locked; then
        echo -e "  ${INFO} Clearing package manager locks..."
        sudo rm -f /var/lib/dpkg/lock-frontend 
        sudo rm -f /var/lib/dpkg/lock
        
        # Check for additional lock files
        sudo rm -f /var/lib/apt/lists/lock
        sudo rm -f /var/cache/apt/archives/lock
        
        # Check for and kill running apt/dpkg processes
        if pgrep -a apt | grep -q .; then
            echo -e "  ${WARNING} Found running apt processes. Attempting to terminate..."
            sudo pkill -f apt
            sleep 2
        fi
        
        if pgrep -a dpkg | grep -q .; then
            echo -e "  ${WARNING} Found running dpkg processes. Attempting to terminate..."
            sudo pkill -f dpkg
            sleep 2
        fi
        
        # Fix potentially interrupted dpkg
        echo -e "  ${INFO} Attempting to reconfigure dpkg if needed..."
        sudo dpkg --configure -a
        
        echo -e "  ${OK} Package manager locks cleared."
    fi
    
    # Update packages if needed
    if $needs_updates; then
        echo -e "  ${INFO} Updating system packages (this may take several minutes)..."
        
        # Detect package manager and update accordingly
        if command -v apt >/dev/null 2>&1; then
            echo -e "  ${CYAN}Running apt update and upgrade${NC}"
            
            # Check for systemd updates first
            if $systemd_updates; then
                echo -e "  ${YELLOW}=====================================================${NC}"
                echo -e "  ${YELLOW}NOTICE: Detected systemd package updates${NC}"
                echo -e "  ${YELLOW}These packages are essential system components${NC}"
                echo -e "  ${YELLOW}A system reboot will be required after updates${NC}"
                echo -e "  ${YELLOW}=====================================================${NC}"
            fi
            
            # Update package lists
            echo -e "  ${INFO} Updating package lists..."
            sudo apt update -y
            
            # Upgrade packages
            echo -e "  ${INFO} Upgrading packages..."
            sudo apt upgrade -y
            
            # Check for kept-back packages
            kept_back_count=$(apt list --upgradable 2>/dev/null | grep -c "kept" || echo "0")
            kept_back_count=$(echo "$kept_back_count" | tr -cd '0-9')

            # Try to handle kept-back packages
            if [ -n "$kept_back_count" ] && [ "$kept_back_count" -gt 0 ]; then
                echo -e "  ${INFO} Found ${kept_back_count} kept-back packages"
                
                # Check if they are systemd packages
                if apt list --upgradable 2>/dev/null | grep -q systemd; then
                    echo -e "  ${WARNING} Systemd packages detected - these may require a reboot"
                    echo -e "  ${YELLOW}Note: Systemd updates are being kept back because they control core system functions${NC}"
                    echo -e "  ${YELLOW}      They can be safely updated with 'sudo apt full-upgrade' followed by a reboot${NC}"
                fi
                
                echo -e "  ${INFO} Handling kept-back packages..."
                # Try apt-get with new pkgs
                sudo apt-get --with-new-pkgs upgrade -y
                
                # Try full-upgrade for more complex dependency changes
                echo -e "  ${INFO} Running full upgrade for kept-back packages..."
                sudo apt full-upgrade -y
                
                # Check if we still have kept-back packages
                remaining_kept_back=$(apt list --upgradable 2>/dev/null | grep -c "kept" || echo "0")
                remaining_kept_back=$(echo "$remaining_kept_back" | tr -cd '0-9')

                if [ -n "$remaining_kept_back" ] && [ "$remaining_kept_back" -gt 0 ]; then
                    echo -e "  ${WARNING} ${remaining_kept_back} packages still kept back"
                    if apt list --upgradable 2>/dev/null | grep -q systemd; then
                        echo -e "  ${YELLOW}Note: Systemd packages may require a manual reboot${NC}"
                        echo -e "  ${YELLOW}After current maintenance completes, run: sudo reboot${NC}"
                    fi
                fi
            fi
            
            # Distribution upgrade
            echo -e "  ${INFO} Running distribution upgrade..."
            sudo apt dist-upgrade -y
            
            # Try apt-get dist-upgrade as a final attempt
            echo -e "  ${INFO} Final attempt for stubborn packages..."
            sudo apt-get dist-upgrade -y
            
            # Check if a reboot is needed
            if [ -f /var/run/reboot-required ]; then
                echo -e "  ${WARNING} System indicates a reboot is required"
                echo -e "  ${YELLOW}Please reboot your system after maintenance completes${NC}"
            fi
            
            # Autoremove unused packages
            echo -e "  ${INFO} Removing unused packages..."
            sudo apt autoremove -y
            
            # Clean package cache
            echo -e "  ${INFO} Cleaning package cache..."
            sudo apt autoclean -y
            
        # DNF (Fedora, RHEL, CentOS)
        elif command -v dnf >/dev/null 2>&1; then
            echo -e "  ${CYAN}Running dnf update${NC}"
            
            # Check for kernel updates
            needs_reboot=false
            if dnf check-update kernel 2>/dev/null | grep -q kernel; then
                echo -e "  ${YELLOW}=====================================================${NC}"
                echo -e "  ${YELLOW}NOTICE: Kernel updates detected${NC}"
                echo -e "  ${YELLOW}A system reboot will be required after updates${NC}"
                echo -e "  ${YELLOW}=====================================================${NC}"
                needs_reboot=true
            fi
            
            # Update packages
            echo -e "  ${INFO} Updating packages..."
            sudo dnf update -y
            
            # Clean orphaned packages
            echo -e "  ${INFO} Removing orphaned packages..."
            sudo dnf autoremove -y
            
            # Clean cache
            echo -e "  ${INFO} Cleaning package cache..."
            sudo dnf clean all
            
            if $needs_reboot; then
                echo -e "  ${YELLOW}Remember to reboot your system after updates${NC}"
            fi
            
        # YUM (older RHEL, CentOS)
        elif command -v yum >/dev/null 2>&1; then
            echo -e "  ${CYAN}Running yum update${NC}"
            
            # Check for kernel updates
            needs_reboot=false
            if yum check-update kernel 2>/dev/null | grep -q kernel; then
                echo -e "  ${YELLOW}=====================================================${NC}"
                echo -e "  ${YELLOW}NOTICE: Kernel updates detected${NC}"
                echo -e "  ${YELLOW}A system reboot will be required after updates${NC}"
                echo -e "  ${YELLOW}=====================================================${NC}"
                needs_reboot=true
            fi
            
            # Update packages
            echo -e "  ${INFO} Updating packages..."
            sudo yum update -y
            
            # Clean orphaned packages
            echo -e "  ${INFO} Removing orphaned packages..."
            sudo yum autoremove -y
            
            # Clean cache
            echo -e "  ${INFO} Cleaning package cache..."
            sudo yum clean all
            
            if $needs_reboot; then
                echo -e "  ${YELLOW}Remember to reboot your system after updates${NC}"
            fi
            
        # Pacman (Arch Linux)
        elif command -v pacman >/dev/null 2>&1; then
            echo -e "  ${CYAN}Running pacman update${NC}"
            
            # Sync database
            echo -e "  ${INFO} Syncing package database..."
            sudo pacman -Sy
            
            # Update packages
            echo -e "  ${INFO} Upgrading packages..."
            sudo pacman -Su --noconfirm
            
            # Check if kernel was updated
            if pacman -Q linux | grep -q "linux"; then
                echo -e "  ${YELLOW}Kernel packages may have been updated${NC}"
                echo -e "  ${YELLOW}A system reboot is recommended after updates${NC}"
            fi
            
            # Clean package cache (keep one version)
            echo -e "  ${INFO} Cleaning package cache..."
            sudo pacman -Sc --noconfirm
            
            # Check for orphaned packages
            if command -v paru >/dev/null 2>&1; then
                echo -e "  ${INFO} Checking for orphaned packages..."
                paru -c
            elif command -v yay >/dev/null 2>&1; then
                echo -e "  ${INFO} Checking for orphaned packages..."
                yay -c
            fi
        else
            echo -e "  ${WARNING} No supported package manager found. Manual updates required."
        fi
        
        # Final systemd update check
        if $systemd_updates; then
            echo -e "\n  ${YELLOW}System has pending systemd updates which require a reboot${NC}"
            echo -e "  ${YELLOW}Would you like to reboot now? (y/n)${NC}"
            read -r REBOOT_NOW
            
            if [[ "$REBOOT_NOW" =~ ^[Yy]$ ]]; then
                echo -e "  ${CYAN}Rebooting system now...${NC}"
                sudo reboot
            else
                echo -e "  ${CYAN}Please remember to reboot later with: sudo reboot${NC}"
            fi
        fi
        
        echo -e "  ${OK} System update complete."
    fi
    
    # Install missing tools if needed
    if ! command -v smartctl >/dev/null 2>&1 || ! command -v sensors >/dev/null 2>&1 || ! command -v iostat >/dev/null 2>&1; then
        echo -e "  ${INFO} Installing missing system monitoring tools..."
        
        if ! command -v smartctl >/dev/null 2>&1; then
            echo -e "  ${INFO} Installing smartmontools..."
            sudo apt install -y smartmontools
        fi
        
        if ! command -v sensors >/dev/null 2>&1; then
            echo -e "  ${INFO} Installing lm-sensors..."
            sudo apt install -y lm-sensors
        fi
        
        if ! command -v iostat >/dev/null 2>&1; then
            echo -e "  ${INFO} Installing sysstat..."
            sudo apt install -y sysstat
        fi
        
        echo -e "  ${OK} Missing tools installed."
    fi
    
    echo -e "\n${BOLD}${GREEN}Fix operations completed.${NC}"
    echo -e "${CYAN}Run the script again to verify system health.${NC}"
elif [ $issues_found -gt 0 ]; then
    echo -e "\n${CYAN}Recommendations:${NC}"
    
    if $dpkg_locked; then
        echo -e "  - Clear package manager locks: sudo rm -f /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock /var/lib/apt/lists/lock /var/cache/apt/archives/lock"
        echo -e "  - Fix interrupted installations: sudo dpkg --configure -a"
    fi
    
    if $needs_updates; then
        echo -e "  - Update system: sudo apt update && sudo apt upgrade -y"
        
        # Check if there are kept-back packages
        if apt list --upgradable 2>/dev/null | grep -q kept; then
            echo -e "  - For kept-back packages: sudo apt-get --with-new-pkgs upgrade -y"
            echo -e "  - For stubborn packages: sudo apt full-upgrade -y"
            
            # Special handling for systemd packages
            if $systemd_updates; then
                echo -e "  - ${YELLOW}IMPORTANT: systemd packages require a system reboot${NC}"
                echo -e "  - ${YELLOW}Run these commands in sequence:${NC}"
                echo -e "    1. sudo apt full-upgrade -y"
                echo -e "    2. sudo reboot"
            fi
        fi
    fi
    
    if ! command -v smartctl >/dev/null 2>&1; then
        echo -e "  - Install smartmontools for better disk health monitoring: sudo apt install smartmontools"
    fi
    
    if ! command -v iostat >/dev/null 2>&1; then
        echo -e "  - Install sysstat for I/O statistics: sudo apt install sysstat"
    fi

    echo -e "  - Run with --fix parameter to automatically fix issues: ${CYAN}sudo $0 --fix${NC}"
fi

echo -e "\n${CYAN}Report Complete at $(date +"%H:%M:%S")${NC}"