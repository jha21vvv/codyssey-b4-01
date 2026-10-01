#!/bin/bash
# ==============================================================================
# Script Name : test_agent_app.sh
# Description : Test script for agent_app.py boot sequence and port binding
# ==============================================================================

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_SCRIPT="${PROJECT_ROOT}/app/agent_app.py"
TEST_ENV_DIR="${PROJECT_ROOT}/tests/tmp_app_env"

rm -rf "${TEST_ENV_DIR}"
mkdir -p "${TEST_ENV_DIR}/upload_files"
mkdir -p "${TEST_ENV_DIR}/api_keys"
mkdir -p "${TEST_ENV_DIR}/logs"

echo "agent_api_key_test" > "${TEST_ENV_DIR}/api_keys/t_secret.key"

export AGENT_HOME="${TEST_ENV_DIR}"
export AGENT_PORT=15034
export AGENT_UPLOAD_DIR="${TEST_ENV_DIR}/upload_files"
export AGENT_KEY_PATH="${TEST_ENV_DIR}/api_keys/t_secret.key"
export AGENT_LOG_DIR="${TEST_ENV_DIR}/logs"

echo "=== Launching agent_app.py for Boot Sequence Verification ==="
python "${APP_SCRIPT}" &
APP_PID=$!
sleep 2

echo "=== Verifying Port 15034 with curl / python ==="
python -c "
import socket
s = socket.socket()
s.connect(('127.0.0.1', 15034))
s.sendall(b'GET / HTTP/1.1\r\nHost: localhost\r\n\r\n')
res = s.recv(1024)
print('Response:', res.decode('utf-8', errors='ignore'))
s.close()
"

kill -9 "${APP_PID}" 2>/dev/null || taskkill //F //PID "${APP_PID}" 2>/dev/null || true
rm -rf "${TEST_ENV_DIR}"
echo "=== agent_app.py Test PASSED ==="
