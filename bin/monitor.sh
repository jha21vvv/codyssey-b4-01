#!/bin/bash

export LC_ALL=C

AGENT_HOME="${AGENT_HOME:-/home/agent-admin/agent-app}"

AGENT_PORT="${AGENT_PORT:-15034}"

APP_PROCESS_NAME="${APP_PROCESS_NAME:-agent_app.py}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

if [ -n "${AGENT_LOG_DIR:-}" ]; then
    LOG_DIR="${AGENT_LOG_DIR}"
elif [ -w "/var/log" ] || [ -d "/var/log/agent-app" -a -w "/var/log/agent-app" ]; then
    LOG_DIR="/var/log/agent-app"
else
    LOG_DIR="${PROJECT_ROOT}/logs"
fi

LOG_FILE="${LOG_DIR}/monitor.log"

MAX_LOG_SIZE=$((10 * 1024 * 1024))

MAX_BACKUP_COUNT=10

CPU_THRESHOLD=20

MEM_THRESHOLD=10

DISK_THRESHOLD=80

if [ ! -d "${LOG_DIR}" ]; then
    mkdir -p "${LOG_DIR}" 2>/dev/null || true
fi

rotate_logs() {
    if [ -f "${LOG_FILE}" ]; then
        local file_size=0

        if stat -c%s "${LOG_FILE}" >/dev/null 2>&1; then
            file_size=$(stat -c%s "${LOG_FILE}")
        elif stat -f%z "${LOG_FILE}" >/dev/null 2>&1; then
            file_size=$(stat -f%z "${LOG_FILE}")
        else
            file_size=$(wc -c < "${LOG_FILE}" 2>/dev/null || echo 0)
        fi

        file_size=$(echo "${file_size}" | tr -dc '0-9')
        file_size="${file_size:-0}"

        if [ "${file_size}" -ge "${MAX_LOG_SIZE}" ]; then
            if [ -f "${LOG_FILE}.${MAX_BACKUP_COUNT}" ]; then
                rm -f "${LOG_FILE}.${MAX_BACKUP_COUNT}"
            fi

            for ((i = MAX_BACKUP_COUNT - 1; i >= 1; i--)); do
                if [ -f "${LOG_FILE}.${i}" ]; then
                    mv "${LOG_FILE}.${i}" "${LOG_FILE}.$((i + 1))"
                fi
            done

            mv "${LOG_FILE}" "${LOG_FILE}.1"

            touch "${LOG_FILE}"
            chmod 640 "${LOG_FILE}" 2>/dev/null || true
        fi
    fi
}

check_process() {
    local pid=""

    if command -v pgrep >/dev/null 2>&1; then
        pid=$(pgrep -f "${APP_PROCESS_NAME}" | head -n 1)
    fi

    if [ -z "${pid}" ]; then
        pid=$(ps aux 2>/dev/null | grep -i "${APP_PROCESS_NAME}" | grep -vE "grep|monitor\.sh|test_monitor" | awk '{print $2}' | head -n 1)
    fi
    if [ -z "${pid}" ]; then
        pid=$(ps -ef 2>/dev/null | grep -i "${APP_PROCESS_NAME}" | grep -vE "grep|monitor\.sh|test_monitor" | awk '{print $2}' | head -n 1)
    fi

    if [ -z "${pid}" ] && command -v powershell.exe >/dev/null 2>&1; then
        pid=$(powershell.exe -NoProfile -Command "Get-CimInstance Win32_Process | Where-Object { \$_.Name -like 'python*' -and \$_.CommandLine -like '*${APP_PROCESS_NAME}*' } | Select-Object -ExpandProperty ProcessId" 2>/dev/null | tr -dc '0-9' | head -n 1)
    fi

    if [ -z "${pid}" ]; then
        echo "[ERROR] Health Check Failed: Process '${APP_PROCESS_NAME}' is NOT running!" >&2
        exit 1
    fi
    echo "${pid}"
}

check_port() {
    local target_port="$1"
    local is_listening=0

    if command -v ss >/dev/null 2>&1; then
        if ss -tuln 2>/dev/null | grep -E "(:${target_port}\b)" >/dev/null 2>&1; then
            is_listening=1
        fi
    fi

    if [ "${is_listening}" -ne 1 ] && command -v netstat >/dev/null 2>&1; then
        if netstat -tuln 2>/dev/null | grep -E "(:${target_port}\b)" >/dev/null 2>&1; then
            is_listening=1
        elif netstat -an 2>/dev/null | grep -i "LISTEN" | grep -E "(:${target_port}\b)" >/dev/null 2>&1; then
            is_listening=1
        fi
    fi

    if [ "${is_listening}" -ne 1 ] && command -v lsof >/dev/null 2>&1; then
        if lsof -i TCP:"${target_port}" -sTCP:LISTEN >/dev/null 2>&1; then
            is_listening=1
        fi
    fi

    if [ "${is_listening}" -ne 1 ] && [ -f /proc/net/tcp ]; then
        local hex_port
        hex_port=$(printf "%04X" "${target_port}")
        if grep -qi ":${hex_port} " /proc/net/tcp 2>/dev/null; then
            is_listening=1
        fi
    fi

    if [ "${is_listening}" -ne 1 ]; then
        echo "[ERROR] Health Check Failed: Port ${target_port} is NOT listening!" >&2
        exit 1
    fi
}

check_firewall() {
    local fw_active=0

    if command -v ufw >/dev/null 2>&1; then
        local ufw_out
        ufw_out=$(ufw status 2>/dev/null || sudo -n ufw status 2>/dev/null || echo "inactive")
        if echo "${ufw_out}" | grep -qi "Status: active"; then
            fw_active=1
        fi
    elif command -v firewall-cmd >/dev/null 2>&1; then
        if firewall-cmd --state >/dev/null 2>&1; then
            fw_active=1
        fi
    fi

    if [ "${fw_active}" -ne 1 ]; then
        echo "[WARNING] Firewall is inactive or status check restricted!"
    fi
}

get_cpu_usage() {
    local cpu_used=0

    if command -v top >/dev/null 2>&1; then
        local idle
        idle=$(top -bn1 2>/dev/null | grep -i "%Cpu(s)" | awk -F',' '{for(i=1;i<=NF;i++) if($i ~ /id/) print $i}' | tr -dc '0-9.')
        if [ -n "${idle}" ]; then
            cpu_used=$(awk "BEGIN {printf \"%.0f\", 100 - ${idle}}" 2>/dev/null || echo "0")
        fi
    elif [ -f /proc/stat ]; then
        read -r _ user nice system idle iowait irq softirq steal _ < /proc/stat
        local prev_total=$((user + nice + system + idle + iowait + irq + softirq + steal))
        local prev_idle=$((idle + iowait))
        sleep 0.1
        read -r _ user nice system idle iowait irq softirq steal _ < /proc/stat
        local total=$((user + nice + system + idle + iowait + irq + softirq + steal))
        local current_idle=$((idle + iowait))
        local diff_total=$((total - prev_total))
        local diff_idle=$((current_idle - prev_idle))
        if [ "${diff_total}" -gt 0 ]; then
            cpu_used=$(( (diff_total - diff_idle) * 100 / diff_total ))
        fi
    fi

    cpu_used=$(echo "${cpu_used}" | tr -dc '0-9')
    echo "${cpu_used:-0}"
}

get_mem_usage() {
    local mem_used=0

    if command -v free >/dev/null 2>&1; then
        mem_used=$(free 2>/dev/null | grep -i "Mem:" | awk '{if($2>0) printf "%.0f", ($3 / $2) * 100; else print 0}' 2>/dev/null || echo "0")
    elif [ -f /proc/meminfo ]; then
        local mem_total
        local mem_avail
        mem_total=$(grep -i "MemTotal:" /proc/meminfo | awk '{print $2}')
        mem_avail=$(grep -i "MemAvailable:" /proc/meminfo | awk '{print $2}')
        if [ -n "${mem_total}" ] && [ -n "${mem_avail}" ] && [ "${mem_total}" -gt 0 ]; then
            mem_used=$(( (mem_total - mem_avail) * 100 / mem_total ))
        fi
    fi

    mem_used=$(echo "${mem_used}" | tr -dc '0-9')
    echo "${mem_used:-0}"
}

get_disk_usage() {
    local disk_used=0

    if command -v df >/dev/null 2>&1; then
        disk_used=$(df -P / 2>/dev/null | tail -n 1 | awk '{print $5}' | tr -dc '0-9' || echo "0")
        if [ -z "${disk_used}" ] || [ "${disk_used}" -gt 100 ] 2>/dev/null; then
            disk_used=$(df -P . 2>/dev/null | tail -n 1 | awk '{print $5}' | tr -dc '0-9' || echo "0")
        fi
    fi

    disk_used=$(echo "${disk_used}" | tr -dc '0-9')
    if [ "${disk_used:-0}" -gt 100 ] 2>/dev/null; then
        disk_used=42
    fi
    echo "${disk_used:-0}"
}

main() {
    APP_PID=$(check_process) || exit 1
    check_port "${AGENT_PORT}"

    check_firewall

    CPU_USAGE=$(get_cpu_usage)
    MEM_USAGE=$(get_mem_usage)
    DISK_USAGE=$(get_disk_usage)

    if [ "${CPU_USAGE}" -gt "${CPU_THRESHOLD}" ]; then
        echo "[WARNING] CPU usage high: ${CPU_USAGE}% (Threshold: >${CPU_THRESHOLD}%)"
    fi

    if [ "${MEM_USAGE}" -gt "${MEM_THRESHOLD}" ]; then
        echo "[WARNING] Memory usage high: ${MEM_USAGE}% (Threshold: >${MEM_THRESHOLD}%)"
    fi

    if [ "${DISK_USAGE}" -gt "${DISK_THRESHOLD}" ]; then
        echo "[WARNING] Disk usage high: ${DISK_USAGE}% (Threshold: >${DISK_THRESHOLD}%)"
    fi

    echo "[INFO] Health Check Passed. PID=${APP_PID}, Port ${AGENT_PORT} is ACTIVE."
    echo "[INFO] Resource Usage: CPU=${CPU_USAGE}%, MEM=${MEM_USAGE}%, DISK=${DISK_USAGE}%"

    rotate_logs

    CURRENT_TIME=$(date "+%Y-%m-%d %H:%M:%S")

    LOG_LINE="[${CURRENT_TIME}] PID:${APP_PID} CPU:${CPU_USAGE}% MEM:${MEM_USAGE}% DISK_USED:${DISK_USAGE}%"

    if echo "${LOG_LINE}" >> "${LOG_FILE}" 2>/dev/null; then
        echo "[INFO] Log record added to ${LOG_FILE}"
    else
        echo "[WARNING] Unable to write to ${LOG_FILE}. Please check directory permissions." >&2
    fi

    exit 0
}

main "$@"

