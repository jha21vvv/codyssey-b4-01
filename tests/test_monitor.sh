#!/bin/bash
# ==============================================================================
# Script Name : test_monitor.sh
# Description : Unit and Integration Test Suite for monitor.sh
# ==============================================================================

set -uo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MONITOR_SCRIPT="${PROJECT_ROOT}/bin/monitor.sh"
TEST_TMP_DIR="${PROJECT_ROOT}/tests/tmp_test"
TEST_LOG_DIR="${TEST_TMP_DIR}/logs"

echo "=========================================================="
echo "    Running Automated Test Suite for monitor.sh           "
echo "=========================================================="

rm -rf "${TEST_TMP_DIR}"
mkdir -p "${TEST_LOG_DIR}"

PASS_COUNT=0
FAIL_COUNT=0

assert_equals() {
    local test_name="$1"
    local expected="$2"
    local actual="$3"

    if [ "${expected}" = "${actual}" ]; then
        echo "  [PASS] ${test_name}"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo "  [FAIL] ${test_name} (Expected: ${expected}, Got: ${actual})"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
}

assert_contains() {
    local test_name="$1"
    local needle="$2"
    local haystack="$3"

    if echo "${haystack}" | grep -q "${needle}"; then
        echo "  [PASS] ${test_name}"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo "  [FAIL] ${test_name} (Expected to contain '${needle}')"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
}

# ------------------------------------------------------------------------------
# Test 1: Health Check 실패 테스트 (앱 프로세스 미실행 시 exit code 1)
# ------------------------------------------------------------------------------
echo ""
echo "[Test Case 1] App process not running -> Must exit with code 1"
export APP_PROCESS_NAME="non_existent_fake_app_12345"
export AGENT_PORT=15034
export AGENT_LOG_DIR="${TEST_LOG_DIR}"

OUTPUT=$(bash "${MONITOR_SCRIPT}" 2>&1 || true)
bash "${MONITOR_SCRIPT}" >/dev/null 2>&1
ACTUAL_EXIT=$?

assert_equals "Exit code should be 1 when process is absent" "1" "${ACTUAL_EXIT}"
assert_contains "Error message should mention process not running" "Process 'non_existent_fake_app_12345' is NOT running" "${OUTPUT}"

# ------------------------------------------------------------------------------
# Test 2: 포트 미리스닝 실패 테스트 (프로세스는 있지만 포트가 안 열렸을 때 exit code 1)
# ------------------------------------------------------------------------------
echo ""
echo "[Test Case 2] App running but port not listening -> Must exit with code 1"
( sleep 10 ) &
DUMMY_PID=$!
export APP_PROCESS_NAME="sleep"
export AGENT_PORT=59999

OUTPUT=$(bash "${MONITOR_SCRIPT}" 2>&1 || true)
bash "${MONITOR_SCRIPT}" >/dev/null 2>&1
ACTUAL_EXIT=$?

assert_equals "Exit code should be 1 when port is not listening" "1" "${ACTUAL_EXIT}"
assert_contains "Error message should mention port not listening" "Port 59999 is NOT listening" "${OUTPUT}"

kill "${DUMMY_PID}" 2>/dev/null || true

# ------------------------------------------------------------------------------
# Test 3: 정상 상황 테스트 (앱 & 포트 정상 동작)
# ------------------------------------------------------------------------------
echo ""
echo "[Test Case 3] App and port running -> Health check pass and log created"
cat << 'EOF' > "${TEST_TMP_DIR}/dummy_app.py"
import socket, time
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(('0.0.0.0', 15034))
s.listen(5)
while True:
    time.sleep(1)
EOF

python "${TEST_TMP_DIR}/dummy_app.py" &
APP_SRV_PID=$!
sleep 2

export APP_PROCESS_NAME="dummy_app.py"
export AGENT_PORT=15034
export AGENT_LOG_DIR="${TEST_LOG_DIR}"
rm -f "${TEST_LOG_DIR}/monitor.log"

OUTPUT=$(bash "${MONITOR_SCRIPT}" 2>&1)
ACTUAL_EXIT=$?

assert_equals "Exit code should be 0 on healthy status" "0" "${ACTUAL_EXIT}"
assert_contains "Output contains Health Check Passed" "Health Check Passed" "${OUTPUT}"

# 로그 파일 생성 및 형식 검증
LOG_LINE=$(cat "${TEST_LOG_DIR}/monitor.log" 2>/dev/null || echo "")
echo "  -> Logged Line: ${LOG_LINE}"
assert_contains "Log contains timestamp prefix" "\[20" "${LOG_LINE}"
assert_contains "Log contains PID" "PID:" "${LOG_LINE}"
assert_contains "Log contains CPU" "CPU:" "${LOG_LINE}"
assert_contains "Log contains MEM" "MEM:" "${LOG_LINE}"
assert_contains "Log contains DISK_USED" "DISK_USED:" "${LOG_LINE}"

# 서버 정리
kill -9 "${APP_SRV_PID}" 2>/dev/null || taskkill //F //PID "${APP_SRV_PID}" 2>/dev/null || true

# ------------------------------------------------------------------------------
# Test 4: 로그 로테이션 검증 (10MB 초과 시 .1 백업 파일 생성 및 최대 10개 유지)
# ------------------------------------------------------------------------------
echo ""
echo "[Test Case 4] Log Rotation logic test"
# 순수 bash dd 명령어로 11MB 파일 생성
dd if=/dev/zero of="${TEST_LOG_DIR}/monitor.log" bs=1048576 count=11 2>/dev/null

python "${TEST_TMP_DIR}/dummy_app.py" &
APP_SRV_PID=$!
sleep 2

bash "${MONITOR_SCRIPT}" >/dev/null 2>&1
kill -9 "${APP_SRV_PID}" 2>/dev/null || taskkill //F //PID "${APP_SRV_PID}" 2>/dev/null || true

if [ -f "${TEST_LOG_DIR}/monitor.log.1" ]; then
    echo "  [PASS] Log rotation created monitor.log.1 successfully."
    PASS_COUNT=$((PASS_COUNT + 1))
else
    echo "  [FAIL] Log rotation did not create monitor.log.1"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# 정리
rm -rf "${TEST_TMP_DIR}"

echo ""
echo "=========================================================="
echo " Test Results: ${PASS_COUNT} PASSED, ${FAIL_COUNT} FAILED"
echo "=========================================================="

if [ "${FAIL_COUNT}" -eq 0 ]; then
    exit 0
else
    exit 1
fi
