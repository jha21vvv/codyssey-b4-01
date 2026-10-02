#!/bin/bash

set -euo pipefail

echo "======================================================================"
echo "    [Codyssey B4-1] 가상환경(VM/WSL2) 통합 실습 및 검증 러너"
echo "======================================================================"

if [ "$(id -u)" -ne 0 ]; then
    echo "[ERROR] This demo runner must be run with sudo! (e.g. sudo ./scripts/run_vm_demo.sh)" >&2
    exit 1
fi

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "${PROJECT_ROOT}"

echo ""
echo "[Step 1/5] Running Infrastructure Setup (setup_server.sh)..."
bash ./scripts/setup_server.sh

echo ""
echo "[Step 2/5] Starting Agent App under 'agent-admin' user..."
pkill -f "agent_app.py" 2>/dev/null || true
sleep 1

su - agent-admin -c "python3 ~/agent-app/agent_app.py" > /tmp/agent_app_boot.log 2>&1 &
APP_PID=$!
sleep 2

echo "  -> Agent App launched in background (PID: ${APP_PID})"
cat /tmp/agent_app_boot.log || true

echo ""
echo "[Step 3/5] Running monitor.sh manually..."
su - agent-admin -c "bash ~/agent-app/bin/monitor.sh"

echo ""
echo "[Step 4/5] Inspecting latest log line (/var/log/agent-app/monitor.log)..."
if [ -f "/var/log/agent-app/monitor.log" ]; then
    tail -n 3 /var/log/agent-app/monitor.log
else
    echo "  (Log file not yet created)"
fi

echo ""
echo "[Step 5/5] Executing 8-Proof Verification (verify_all.sh)..."
bash ./scripts/verify_all.sh

echo ""
echo "======================================================================"
echo "    [SUCCESS] 가상환경(VM/WSL2) 실습 및 8대 증거 검증 완료!"
echo "======================================================================"
echo "[*] 에이전트 앱은 현재 백그라운드에서 계속 실행 중입니다."
echo "[*] 앱을 끄려면: sudo pkill -f agent_app.py"

