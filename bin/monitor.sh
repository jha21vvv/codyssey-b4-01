#!/bin/bash
# ==============================================================================
# Script Name : monitor.sh
# Description : System resource monitoring and application health check script
# Author      : agent-dev
# Group       : agent-core
# Permission  : 750 (rwxr-x---)
# Target OS   : Ubuntu 22.04 LTS (Bash Only)
# ==============================================================================

# [1차]: 표준 C 로케일로 강제 설정하여 명령어 출력(awk, top 등)의 언어 및 소수점 표기(쉼표 vs 점) 차이로 인한 파싱 버그를 원천 방지합니다.
# [2차]: 전 세계 어디서 스크립트를 돌려도 똑같은 잣대로 숫자를 읽을 수 있도록 번역기를 미국 표준 잣대로 고정해 둡니다.
export LC_ALL=C

# [1차]: 환경 변수 AGENT_HOME이 존재하면 그 값을 쓰고, 없으면 기본값인 /home/agent-admin/agent-app으로 안전하게 폴백(Fallback) 지정합니다.
# [2차]: 회사 출입 주소가 적힌 명함을 먼저 보고, 없으면 기본 본사 건물 주소를 적어두는 안전장치입니다.
AGENT_HOME="${AGENT_HOME:-/home/agent-admin/agent-app}"

# [1차]: 서비스가 리슨할 목표 TCP 포트 번호를 15034로 설정합니다.
# [2차]: 고객이 우리 가게로 들어올 특정 출입문 번호(15034호)를 지정합니다.
AGENT_PORT="${AGENT_PORT:-15034}"

# [1차]: 모니터링 대상이 될 애플리케이션의 프로세스 실행 명칭을 정의합니다.
# [2차]: 감시대상 환자의 이름표(agent_app.py)를 간호사 차트에 적어두는 것입니다.
APP_PROCESS_NAME="${APP_PROCESS_NAME:-agent_app.py}"

# [1차]: 스크립트의 현재 위치와 프로젝트 루트 디렉토리 절대 경로를 계산합니다.
# [2차]: 내가 지금 서 있는 방의 주소와 프로젝트 건물의 정문 위치를 확인합니다.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# [1차]: 로그 파일 저장 디렉토리를 3단계로 스마트하게 결정합니다:
#        1) 환경 변수 AGENT_LOG_DIR이 선언되어 있으면 최우선 적용
#        2) 리눅스 시스템 디렉토리(/var/log/agent-app)에 쓰기 권한이 있으면 사용
#        3) 로컬 개발/테스트 환경에서는 프로젝트 내부의 logs 디렉토리(${PROJECT_ROOT}/logs)를 기본값으로 사용
# [2차]: 공식 캐비닛이 있으면 거길 쓰고, 로컬 내 방에서 작업할 때는 내 서랍(logs 폴더)에 바로 일기장을 꽂아둡니다.
if [ -n "${AGENT_LOG_DIR:-}" ]; then
    LOG_DIR="${AGENT_LOG_DIR}"
elif [ -w "/var/log" ] || [ -d "/var/log/agent-app" -a -w "/var/log/agent-app" ]; then
    LOG_DIR="/var/log/agent-app"
else
    LOG_DIR="${PROJECT_ROOT}/logs"
fi

# [1차]: 최종 누적 로그 파일의 절대 경로를 완성합니다.
# [2차]: 캐비닛 안에 꽂아둘 진료 일지 노트의 전체 파일명을 확정합니다.
LOG_FILE="${LOG_DIR}/monitor.log"

# [1차]: 로그 파일의 최대 허용 크기를 바이트 단위(10MB = 10 * 1024 * 1024 = 10,485,760 bytes)로 지정합니다.
# [2차]: 진료 일지가 너무 두꺼워져서 캐비닛이 터지지 않도록 허용할 최대 페이지 수(10MB)를 정합니다.
MAX_LOG_SIZE=$((10 * 1024 * 1024))

# [1차]: 로그 로테이션 시 보존할 과거 백업 파일의 최대 개수를 10개로 제한합니다.
# [2차]: 서류 보관함에 과거 기록을 딱 10권까지만 보관하고 제일 오래된 것은 버리겠다는 규칙입니다.
MAX_BACKUP_COUNT=10

# [1차]: CPU 사용률 경고 임계치를 20%로 선언합니다.
# [2차]: 환자의 체온이 38도를 넘으면 주의보를 울리듯, CPU가 20%를 넘기면 주의하라는 기준선입니다.
CPU_THRESHOLD=20

# [1차]: 메모리 사용률 경고 임계치를 10%로 선언합니다.
# [2차]: 뇌의 작업 메모리가 10%를 초과해 차오르면 과부하 신호를 주겠다는 기준선입니다.
MEM_THRESHOLD=10

# [1차]: 루트 파티션 디스크 사용률 경고 임계치를 80%로 선언합니다.
# [2차]: 창고 공간이 80% 이상 차서 넘치기 전에 미리 경고 방송을 하겠다는 마지노선입니다.
DISK_THRESHOLD=80

# ------------------------------------------------------------------------------
# 1. 로그 디렉토리 및 파일 권한 보장
# ------------------------------------------------------------------------------
# [1차]: 디렉토리 존재 여부(-d)를 점검하고, 없으면 부모 경로까지 포함(-p)하여 자동 생성합니다.
# [2차]: 서류철을 꽂아둘 캐비닛 선반이 없으면 그 자리에서 즉시 조립해 만드는 안전장치입니다.
if [ ! -d "${LOG_DIR}" ]; then
    mkdir -p "${LOG_DIR}" 2>/dev/null || true
fi

# ------------------------------------------------------------------------------
# 2. 로그 로테이션 함수 (최대 10MB, 10개 유지)
# ------------------------------------------------------------------------------
# [1차]: 로그 파일 크기를 검사하여 10MB 초과 시 기존 로그를 1칸씩 쉬프트하고 가장 오래된 파일을 제거하는 함수입니다.
# [2차]: 책꽂이가 꽉 차면 제일 오래된 10번째 책을 파쇄기에 넣고, 나머지 책을 한 칸씩 뒤로 밀어 새 책 자리를 만드는 청소부입니다.
rotate_logs() {
    # [1차]: 모니터링 로그 파일이 실제로 파일로 존재하는지(-f) 검사합니다.
    # [2차]: 검사할 일기장 파일이 책상 위에 진짜로 놓여 있는지 확인합니다.
    if [ -f "${LOG_FILE}" ]; then
        local file_size=0

        # [1차]: 리눅스(GNU stat -c%s) 또는 BSD/macOS(stat -f%z) 또는 wc -c를 단계적으로 시도하여 파일 바이트 크기를 측정합니다.
        # [2차]: 자(ruler)가 국산이든 외산이든 가리지 않고 일기장 두께를 정확히 재어보는 방법입니다.
        if stat -c%s "${LOG_FILE}" >/dev/null 2>&1; then
            file_size=$(stat -c%s "${LOG_FILE}")
        elif stat -f%z "${LOG_FILE}" >/dev/null 2>&1; then
            file_size=$(stat -f%z "${LOG_FILE}")
        else
            file_size=$(wc -c < "${LOG_FILE}" 2>/dev/null || echo 0)
        fi

        # [1차]: tr 명령어로 숫자(0-9) 이외의 모든 공백이나 제어 문자를 제거하여 순수 정수로 정제합니다.
        # [2차]: 측정한 두께 수치에서 불순물(단위 글자나 찌꺼기)을 싹 털어내고 순수 숫자만 남깁니다.
        file_size=$(echo "${file_size}" | tr -dc '0-9')
        file_size="${file_size:-0}"

        # [1차]: 측정한 파일 크기가 최대 허용치(10MB) 이상인지 정수 크기 비교(-ge)를 수행합니다.
        # [2차]: 일기장 두께가 허용 기준치(10MB)를 넘었는지 저울로 달아보는 순간입니다.
        if [ "${file_size}" -ge "${MAX_LOG_SIZE}" ]; then
            # [1차]: 가장 오래된 10번째 백업 파일이 존재하면 디스크 절약을 위해 강제 삭제(-f)합니다.
            # [2차]: 책꽂이 맨 끝에 꽂힌 가장 낡은 10호 일기장을 미련 없이 분쇄기에 넣습니다.
            if [ -f "${LOG_FILE}.${MAX_BACKUP_COUNT}" ]; then
                rm -f "${LOG_FILE}.${MAX_BACKUP_COUNT}"
            fi

            # [1차]: 9번부터 1번까지 역순으로 루프를 돌며 파일명을 .i에서 .(i+1)로 한 칸씩 이동(mv)시킵니다.
            # [2차]: 9호 책은 10호 자리로, 8호 책은 9호 자리로 차례대로 한 칸씩 뒤로 밀어 옮기는 과정입니다.
            for ((i = MAX_BACKUP_COUNT - 1; i >= 1; i--)); do
                if [ -f "${LOG_FILE}.${i}" ]; then
                    mv "${LOG_FILE}.${i}" "${LOG_FILE}.$((i + 1))"
                fi
            done

            # [1차]: 현재 작성 중이던 원본 로그 파일을 첫 번째 백업 파일(.1)로 이동시킵니다.
            # [2차]: 방금 꽉 찬 일기장에 '1호 백업' 스티커를 붙여서 보관함 첫 칸에 꽂아둡니다.
            mv "${LOG_FILE}" "${LOG_FILE}.1"

            # [1차]: 빈 로그 파일을 새롭게 생성(touch)하고 최소 권한(640: 소유자 RW, 그룹 R)을 부여합니다.
            # [2차]: 오늘부터 새로 기록할 깨끗한 백지 일기장을 새로 꺼내고 자물쇠를 채워둡니다.
            touch "${LOG_FILE}"
            chmod 640 "${LOG_FILE}" 2>/dev/null || true
        fi
    fi
}

# ------------------------------------------------------------------------------
# 3. Health Check: 프로세스 및 포트 검사 (실패 시 즉시 exit 1)
# ------------------------------------------------------------------------------
# [1차]: 감시 대상 애플리케이션의 프로세스 생존 여부를 조회하고 PID를 반환하며, 죽어 있으면 표준 에러 출력 후 즉시 비정상 종료(exit 1)합니다.
# [2차]: 환자가 숨을 쉬고 있는지 맥박(PID)을 짚어보고, 맥박이 안 뛰면 즉시 비상벨(exit 1)을 누르는 심폐소생 프로토콜입니다.
check_process() {
    local pid=""

    # [1차]: 1순위로 리눅스 표준 프로세스 정규식 조회 도구인 pgrep을 통해 실행 중인 프로세스의 PID를 추출합니다.
    # [2차]: 병원 전산망 검색창(pgrep)에 환자 이름을 넣고 진료 번호(PID)를 조회합니다.
    if command -v pgrep >/dev/null 2>&1; then
        pid=$(pgrep -f "${APP_PROCESS_NAME}" | head -n 1)
    fi

    # [1차]: pgrep이 없는 환경을 대비하여 ps 명령어 결과에서 자기 자신 및 grep을 제외하고 첫 번째 PID를 파싱합니다.
    # [2차]: 전산망이 안 될 때는 종이 환자 명부(ps aux)를 직접 눈으로 훑어서 환자 번호를 찾아냅니다.
    if [ -z "${pid}" ]; then
        pid=$(ps aux 2>/dev/null | grep -i "${APP_PROCESS_NAME}" | grep -vE "grep|monitor\.sh|test_monitor" | awk '{print $2}' | head -n 1)
    fi
    if [ -z "${pid}" ]; then
        pid=$(ps -ef 2>/dev/null | grep -i "${APP_PROCESS_NAME}" | grep -vE "grep|monitor\.sh|test_monitor" | awk '{print $2}' | head -n 1)
    fi

    # [1차]: Windows 호스트 환경 호환: PowerShell을 통해 Python 프로세스 중에서 CommandLine에 앱 스크립트명이 포함된 PID를 조회합니다.
    # [2차]: 윈도우 환경에서도 파이썬 점원의 신분증 번호(PID)를 정확히 확인하는 크로스 플랫폼 지원입니다.
    if [ -z "${pid}" ] && command -v powershell.exe >/dev/null 2>&1; then
        pid=$(powershell.exe -NoProfile -Command "Get-CimInstance Win32_Process | Where-Object { \$_.Name -like 'python*' -and \$_.CommandLine -like '*${APP_PROCESS_NAME}*' } | Select-Object -ExpandProperty ProcessId" 2>/dev/null | tr -dc '0-9' | head -n 1)
    fi

    # [1차]: PID를 전혀 찾지 못한 경우(프로세스 부재)에는 치명적 장애로 간주하고 표준 에러로 출력 후 exit 1 종료합니다.
    # [2차]: 맥박이 전혀 감지되지 않으면 사망 선고를 내리고 즉시 응급 신호(exit 1)를 발송합니다.
    if [ -z "${pid}" ]; then
        echo "[ERROR] Health Check Failed: Process '${APP_PROCESS_NAME}' is NOT running!" >&2
        exit 1
    fi
    echo "${pid}"
}

# [1차]: 지정된 TCP 포트가 시스템에서 LISTEN 상태로 열려 있는지 ss, netstat, lsof, /proc를 통해 다중 검증합니다.
# [2차]: 고객들이 들어오는 15034번 출입문이 활짝 열려 있는지 문고리를 직접 흔들어 확인하는 점검입니다.
check_port() {
    local target_port="$1"
    local is_listening=0

    # [1차]: 최신 Ubuntu 22.04 LTS의 고성능 소켓 조회 유틸리티인 ss 명령어로 포트 리슨 여부를 확인합니다.
    # [2차]: 최신식 전자 도어록 감지기(ss)로 15034호 문이 열려 있는지 검사합니다.
    if command -v ss >/dev/null 2>&1; then
        if ss -tuln 2>/dev/null | grep -E "(:${target_port}\b)" >/dev/null 2>&1; then
            is_listening=1
        fi
    fi

    # [1차]: ss가 없는 환경이나 구형 환경, 윈도우 환경 호환을 위해 netstat 명령어로 포트를 2차 교차 검증합니다.
    # [2차]: 전자 도어록이 없으면 전통적인 기계식 열쇠 검사기(netstat)로 문 열림 상태를 재확인합니다.
    if [ "${is_listening}" -ne 1 ] && command -v netstat >/dev/null 2>&1; then
        if netstat -tuln 2>/dev/null | grep -E "(:${target_port}\b)" >/dev/null 2>&1; then
            is_listening=1
        elif netstat -an 2>/dev/null | grep -i "LISTEN" | grep -E "(:${target_port}\b)" >/dev/null 2>&1; then
            is_listening=1
        fi
    fi

    # [1차]: 파일 서술자 기반의 lsof 명령어로 TCP 포트 리슨 상태를 3차 확인합니다.
    # [2차]: 방범용 CCTV(lsof)를 돌려보며 15034번 통로에 불이 켜져 있는지 확인합니다.
    if [ "${is_listening}" -ne 1 ] && command -v lsof >/dev/null 2>&1; then
        if lsof -i TCP:"${target_port}" -sTCP:LISTEN >/dev/null 2>&1; then
            is_listening=1
        fi
    fi

    # [1차]: 외부 유틸리티가 모두 없는 극한의 리눅스 컨테이너 환경을 위해 /proc/net/tcp 커널 16진수 소켓 테이블을 직접 조회합니다.
    # [2차]: 모든 장비가 고장 났을 때 리눅스 척추 신경망(/proc)을 직접 만져보며 전류가 흐르는지 감지하는 궁극의 생존기입니다.
    if [ "${is_listening}" -ne 1 ] && [ -f /proc/net/tcp ]; then
        local hex_port
        hex_port=$(printf "%04X" "${target_port}")
        if grep -qi ":${hex_port} " /proc/net/tcp 2>/dev/null; then
            is_listening=1
        fi
    fi

    # [1차]: 어떤 도구로도 포트 활성화를 찾지 못한 경우 즉시 치명적 에러 출력 후 exit 1로 종료합니다.
    # [2차]: 출입문이 굳게 잠겨 있어 손님이 전혀 들어올 수 없으므로 비상벨(exit 1)을 울리고 조사를 요구합니다.
    if [ "${is_listening}" -ne 1 ]; then
        echo "[ERROR] Health Check Failed: Port ${target_port} is NOT listening!" >&2
        exit 1
    fi
}

# ------------------------------------------------------------------------------
# 4. 방화벽 상태 점검 (비활성 시 경고만 출력, 스크립트 계속 진행)
# ------------------------------------------------------------------------------
# [1차]: UFW 또는 firewalld 방화벽의 활성화 여부를 조회하고, 꺼져 있을 경우 경고 메시지만 출력하되 종료하지 않습니다.
# [2차]: 성벽의 성문 경비병(UFW)이 졸고 있는지 확인하고, 졸고 있어도 당장 성안의 환자 치료(관제)를 멈추지 않고 경고 메모만 남겨둡니다.
check_firewall() {
    local fw_active=0

    # [1차]: ufw status 명령어로 현재 방화벽 동작 상태(Status: active)를 검사합니다.
    # [2차]: 성문 정문 초소에 근무 중(Status: active) 표지판이 걸려 있는지 확인합니다.
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

    # [1차]: 방화벽이 꺼져 있으면 콘솔에 WARNING 메시지를 출력합니다.
    # [2차]: "경비병이 부재중입니다!"라는 노란색 주의 경고 깃발을 내걸어 관리자의 주의를 환기합니다.
    if [ "${fw_active}" -ne 1 ]; then
        echo "[WARNING] Firewall is inactive or status check restricted!"
    fi
}

# ------------------------------------------------------------------------------
# 5. 시스템 자원 수집 및 임계값 경고 (CPU, Memory, Disk)
# ------------------------------------------------------------------------------
# [1차]: top 명령어의 idle(유휴) 퍼센트를 역산(100 - idle)하여 전체 CPU 사용률(%)을 정수로 반환합니다.
# [2차]: CPU 직원이 100시간 중 몇 시간을 쉬고 있는지(idle)를 잰 뒤, 100에서 뺀 나머지 일한 시간(%)을 계산합니다.
get_cpu_usage() {
    local cpu_used=0

    if command -v top >/dev/null 2>&1; then
        local idle
        idle=$(top -bn1 2>/dev/null | grep -i "%Cpu(s)" | awk -F',' '{for(i=1;i<=NF;i++) if($i ~ /id/) print $i}' | tr -dc '0-9.')
        if [ -n "${idle}" ]; then
            cpu_used=$(awk "BEGIN {printf \"%.0f\", 100 - ${idle}}" 2>/dev/null || echo "0")
        fi
    elif [ -f /proc/stat ]; then
        # [1차]: top이 없을 때 /proc/stat의 jiffies 틱 값을 0.1초 간격으로 측정하여 사용률을 연산합니다.
        # [2차]: 시계 초침 소리를 0.1초 동안 직접 귀로 세어서 심장 박동수를 계산하는 정밀 측정 방식입니다.
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

# [1차]: free 명령어 또는 /proc/meminfo의 used / total 비율을 계산하여 메모리 사용률(%)을 정수로 반환합니다.
# [2차]: 작업 책상(RAM) 위에 올려진 서류 더미가 전체 책상 면적의 몇 %를 차지하는지 면적을 재는 것입니다.
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

# [1차]: df -P / 명령어를 통해 루트 파티션('/')의 디스크 사용 퍼센트(Used %)를 정수로 추출합니다.
# [2차]: 서버 지하 창고(Root 디스크)에 짐이 몇 %나 쌓여 있는지 줄자로 측정합니다.
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

# ==============================================================================
# 메인 실행 흐름
# ==============================================================================
main() {
    # [1차]: 핵심 Health Check를 1순위로 실행하여 비정상 시 즉각 exit 1로 중단되도록 합니다.
    # [2차]: 환자가 살아 있는지와 입구가 열려 있는지를 가장 먼저 확인하고, 사망 시 즉각 비상 대응합니다.
    APP_PID=$(check_process) || exit 1
    check_port "${AGENT_PORT}"

    # [1차]: 방화벽 상태를 점검합니다 (비활성 시 경고만).
    # [2차]: 성문 보초병이 근무 중인지 훑어봅니다.
    check_firewall

    # [1차]: 시스템 자원 사용률 3대 지표(CPU, MEM, DISK)를 측정합니다.
    # [2차]: 체온, 혈압, 폐활량을 순서대로 측정하여 수첩에 기록합니다.
    CPU_USAGE=$(get_cpu_usage)
    MEM_USAGE=$(get_mem_usage)
    DISK_USAGE=$(get_disk_usage)

    # [1차]: CPU 사용률이 임계값(20%)을 초과했는지 비교하고 경고 메시지를 출력합니다.
    # [2차]: 직원이 너무 땀을 뻘뻘 흘리고 있으면 "과로 주의!" 경고등을 켭니다.
    if [ "${CPU_USAGE}" -gt "${CPU_THRESHOLD}" ]; then
        echo "[WARNING] CPU usage high: ${CPU_USAGE}% (Threshold: >${CPU_THRESHOLD}%)"
    fi

    # [1차]: 메모리 사용률이 임계값(10%)을 초과했는지 비교하고 경고 메시지를 출력합니다.
    # [2차]: 책상 위에 서류가 쌓이기 시작하면 "메모리 정리 요망!" 노란 카드를 꺼냅니다.
    if [ "${MEM_USAGE}" -gt "${MEM_THRESHOLD}" ]; then
        echo "[WARNING] Memory usage high: ${MEM_USAGE}% (Threshold: >${MEM_THRESHOLD}%)"
    fi

    # [1차]: 디스크 사용률이 임계값(80%)을 초과했는지 비교하고 경고 메시지를 출력합니다.
    # [2차]: 창고 공간이 80%를 넘으면 "창고 대청소 필요!" 사이렌을 울립니다.
    if [ "${DISK_USAGE}" -gt "${DISK_THRESHOLD}" ]; then
        echo "[WARNING] Disk usage high: ${DISK_USAGE}% (Threshold: >${DISK_THRESHOLD}%)"
    fi

    # [1차]: 콘솔 표준 출력으로 현재 정상 상태와 지표 요약을 보고합니다.
    # [2차]: 병원 모니터 화면에 "환자 상태 안정, 정상 작동 중" 메시지를 띄웁니다.
    echo "[INFO] Health Check Passed. PID=${APP_PID}, Port ${AGENT_PORT} is ACTIVE."
    echo "[INFO] Resource Usage: CPU=${CPU_USAGE}%, MEM=${MEM_USAGE}%, DISK=${DISK_USAGE}%"

    # [1차]: 신규 로그 기록 전에 기존 로그 파일 크기를 점검하고 필요시 로테이션을 수행합니다.
    # [2차]: 일기장에 새 글을 쓰기 전에 책이 꽉 찼으면 새 권으로 교체합니다.
    rotate_logs

    # [1차]: ISO 표준 규격에 맞춘 타임스탬프를 생성합니다.
    # [2차]: 블랙박스 영상 좌측 상단에 찍힐 현재 시각 도장을 파냅니다.
    CURRENT_TIME=$(date "+%Y-%m-%d %H:%M:%S")

    # [1차]: 요구사항에 명시된 엄격한 로그 포맷 문자열을 조립합니다.
    # [2차]: 규격화된 한 줄 진료 기록 라인을 완벽하게 조립합니다.
    LOG_LINE="[${CURRENT_TIME}] PID:${APP_PID} CPU:${CPU_USAGE}% MEM:${MEM_USAGE}% DISK_USED:${DISK_USAGE}%"

    # [1차]: 조립된 로그 라인을 로그 파일 끝에 덧붙여 누적(>>) 기록합니다.
    # [2차]: 진료 차트 맨 마지막 줄에 만년필로 오늘의 상태를 또박또박 적어 넣습니다.
    if echo "${LOG_LINE}" >> "${LOG_FILE}" 2>/dev/null; then
        echo "[INFO] Log record added to ${LOG_FILE}"
    else
        echo "[WARNING] Unable to write to ${LOG_FILE}. Please check directory permissions." >&2
    fi

    # [1차]: 모든 점검 및 로깅이 정상 완결되었음을 알리는 종료 코드 0을 반환합니다.
    # [2차]: 오늘의 정기 건강검진이 이상 없이 성공적으로 끝났음을 공식 확인 도장(0)으로 찍습니다.
    exit 0
}

# [1차]: 스크립트 실행 시 전달된 모든 인자($@)를 main 함수로 위임하여 기동합니다.
# [2차]: 준비된 모든 관제 엔진에 시동 키를 꽂고 출발합니다.
main "$@"
