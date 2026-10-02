#!/bin/bash
# ==============================================================================
# Script Name : run_vm_demo.sh
# Description : 가상환경(WSL2 / VM Ubuntu 22.04 LTS)에서 전체 과제 라이프사이클을
#               (인프라 구축 -> 앱 기동 -> 관제 실행 -> 8대 증거 수집)
#               원클릭으로 실시간 시연 및 검증하는 가상환경 마스터 러너
# Target OS   : Ubuntu 22.04 LTS (WSL2 / VM / Cloud Instance)
# Usage       : sudo ./scripts/run_vm_demo.sh
# ==============================================================================

set -euo pipefail

echo "======================================================================"
echo "    [Codyssey B4-1] 가상환경(VM/WSL2) 통합 실습 및 검증 러너"
echo "======================================================================"

# [Phase 0]: root(sudo) 권한 검사
if [ "$(id -u)" -ne 0 ]; then
    echo "[ERROR] This demo runner must be run with sudo! (e.g. sudo ./scripts/run_vm_demo.sh)" >&2
    exit 1
fi

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "${PROJECT_ROOT}"

# [Phase 1]: 인프라 자동 구축 (setup_server.sh)
echo ""
echo "[Step 1/5] Running Infrastructure Setup (setup_server.sh)..."
bash ./scripts/setup_server.sh

# [Phase 2]: 백그라운드로 Python 에이전트 앱 기동 (agent-admin 계정 권한)
echo ""
echo "[Step 2/5] Starting Agent App under 'agent-admin' user..."
# 기존에 혹시 실행 중인 앱이 있다면 종료
pkill -f "agent_app.py" 2>/dev/null || true
sleep 1

# agent-admin 계정으로 환경 변수를 로드하며 백그라운드 기동
su - agent-admin -c "python3 ~/agent-app/agent_app.py" > /tmp/agent_app_boot.log 2>&1 &
APP_PID=$!
sleep 2

echo "  -> Agent App launched in background (PID: ${APP_PID})"
cat /tmp/agent_app_boot.log || true

# [Phase 3]: 관제 스크립트 (monitor.sh) 직접 1회 실행
echo ""
echo "[Step 3/5] Running monitor.sh manually..."
su - agent-admin -c "bash ~/agent-app/bin/monitor.sh"

# [Phase 4]: /var/log/agent-app/monitor.log 적재 확인
echo ""
echo "[Step 4/5] Inspecting latest log line (/var/log/agent-app/monitor.log)..."
if [ -f "/var/log/agent-app/monitor.log" ]; then
    tail -n 3 /var/log/agent-app/monitor.log
else
    echo "  (Log file not yet created)"
fi

# [Phase 5]: 8대 필수 증거자료 원스톱 검증 (verify_all.sh)
echo ""
echo "[Step 5/5] Executing 8-Proof Verification (verify_all.sh)..."
bash ./scripts/verify_all.sh

echo ""
echo "======================================================================"
echo "    [SUCCESS] 가상환경(VM/WSL2) 실습 및 8대 증거 검증 완료!"
echo "======================================================================"
echo "[*] 에이전트 앱은 현재 백그라운드에서 계속 실행 중입니다."
echo "[*] 앱을 끄려면: sudo pkill -f agent_app.py"
