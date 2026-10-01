#!/bin/bash
# ==============================================================================
# Script Name : verify_all.sh
# Description : 8대 필수 증거자료 수집 및 검증 자동화 스크립트
# Target OS   : Ubuntu 22.04 LTS
# Usage       : ./scripts/verify_all.sh
# ==============================================================================

AGENT_HOME="${AGENT_HOME:-/home/agent-admin/agent-app}"
LOG_DIR="${AGENT_LOG_DIR:-/var/log/agent-app}"

echo "======================================================================"
echo "    Codyssey B4-1 8대 필수 증거자료 자동 검증 및 출력 도구"
echo "======================================================================"

echo ""
echo "----------------------------------------------------------------------"
echo "[증거 1] SSH 포트(20022) 및 Root 접속 차단(PermitRootLogin no) 검증"
echo "----------------------------------------------------------------------"
if [ -f /etc/ssh/sshd_config.d/codyssey.conf ]; then
    cat /etc/ssh/sshd_config.d/codyssey.conf
else
    grep -E "^(Port|PermitRootLogin)" /etc/ssh/sshd_config || echo "Check /etc/ssh configuration"
fi
echo ""
echo ">> SSH Listening Port 상태:"
ss -tulnp 2>/dev/null | grep -E "(:20022\b|sshd)" || echo "(sshd listen 확인 필요)"

echo ""
echo "----------------------------------------------------------------------"
echo "[증거 2] 방화벽(UFW) 활성화 및 허용 포트(20022/tcp, 15034/tcp) 검증"
echo "----------------------------------------------------------------------"
if command -v ufw >/dev/null 2>&1; then
    ufw status verbose 2>/dev/null || sudo ufw status verbose
else
    echo "UFW not found or firewall-cmd state:"
    firewall-cmd --list-all 2>/dev/null || true
fi

echo ""
echo "----------------------------------------------------------------------"
echo "[증거 3] 계정 및 그룹 구성(agent-admin/dev/test, agent-common/core) 검증"
echo "----------------------------------------------------------------------"
echo ">> Groups:"
getent group agent-common || true
getent group agent-core || true
echo ""
echo ">> Users ID Info:"
id agent-admin 2>/dev/null || echo "agent-admin user not found"
id agent-dev 2>/dev/null || echo "agent-dev user not found"
id agent-test 2>/dev/null || echo "agent-test user not found"

echo ""
echo "----------------------------------------------------------------------"
echo "[증거 4] 디렉토리 구조 및 권한(ACL 포함) 검증"
echo "----------------------------------------------------------------------"
echo ">> Directory Permissions (ls -ld):"
ls -ld "${AGENT_HOME}/upload_files" 2>/dev/null || true
ls -ld "${AGENT_HOME}/api_keys" 2>/dev/null || true
ls -ld "${LOG_DIR}" 2>/dev/null || true
ls -l "${AGENT_HOME}/bin/monitor.sh" 2>/dev/null || true
echo ""
echo ">> ACL Inspection (getfacl):"
if command -v getfacl >/dev/null 2>&1; then
    getfacl "${AGENT_HOME}/upload_files" 2>/dev/null || true
    echo "---"
    getfacl "${AGENT_HOME}/api_keys" 2>/dev/null || true
fi

echo ""
echo "----------------------------------------------------------------------"
echo "[증거 5] 앱 프로세스 및 포트 15034 LISTEN 상태 검증"
echo "----------------------------------------------------------------------"
echo ">> Process Status:"
pgrep -fl "agent_app.py" || echo "agent_app.py is not running."
echo ""
echo ">> Port 15034 Status:"
ss -tulnp 2>/dev/null | grep -E "(:15034\b)" || echo "Port 15034 is not listening."

echo ""
echo "----------------------------------------------------------------------"
echo "[증거 6] monitor.sh 직접 실행 결과 확인"
echo "----------------------------------------------------------------------"
if [ -f "${AGENT_HOME}/bin/monitor.sh" ]; then
    bash "${AGENT_HOME}/bin/monitor.sh"
elif [ -f "./bin/monitor.sh" ]; then
    bash "./bin/monitor.sh"
fi

echo ""
echo "----------------------------------------------------------------------"
echo "[증거 7] /var/log/agent-app/monitor.log 누적 로그 확인"
echo "----------------------------------------------------------------------"
if [ -f "${LOG_DIR}/monitor.log" ]; then
    tail -n 10 "${LOG_DIR}/monitor.log"
else
    echo "No log file found at ${LOG_DIR}/monitor.log"
fi

echo ""
echo "----------------------------------------------------------------------"
echo "[증거 8] crontab 매분 등록 및 스케줄링 확인"
echo "----------------------------------------------------------------------"
echo ">> agent-admin crontab:"
crontab -u agent-admin -l 2>/dev/null || crontab -l 2>/dev/null || echo "No crontab installed."

echo ""
echo "======================================================================"
echo "    Verification Complete."
echo "======================================================================"
