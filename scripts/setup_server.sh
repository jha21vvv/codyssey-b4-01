#!/bin/bash
# ==============================================================================
# Script Name : setup_server.sh
# Description : Ubuntu 22.04 LTS 환경 전체 자동화 인프라 및 보안 설정 스크립트
# Target OS   : Ubuntu 22.04 LTS
# Usage       : sudo ./scripts/setup_server.sh
# ==============================================================================

set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
    echo "[ERROR] This setup script must be run as root (or with sudo)!" >&2
    exit 1
fi

echo "=========================================================="
echo "    Starting Codyssey B4-1 Infrastructure Automated Setup"
echo "=========================================================="

# ------------------------------------------------------------------------------
# 1. 필수 패키지 설치
# ------------------------------------------------------------------------------
echo "[1/6] Installing required packages..."
apt-get update -y
apt-get install -y openssh-server ufw acl cron procps iproute2 python3 python3-pip curl

# ------------------------------------------------------------------------------
# 2. SSH 보안 설정 (Port 20022, PermitRootLogin no)
# ------------------------------------------------------------------------------
echo "[2/6] Configuring SSH Security (Port 20022, Root Login Disabled)..."
mkdir -p /etc/ssh/sshd_config.d
cat << 'EOF' > /etc/ssh/sshd_config.d/codyssey.conf
# Codyssey B4-1 SSH Security Rules
Port 20022
PermitRootLogin no
EOF

# 구형 환경 호환을 위해 메인 sshd_config도 검사/보완
if grep -q "^#*Port " /etc/ssh/sshd_config; then
    sed -i 's/^#*Port .*/Port 20022/' /etc/ssh/sshd_config
fi
if grep -q "^#*PermitRootLogin " /etc/ssh/sshd_config; then
    sed -i 's/^#*PermitRootLogin .*/PermitRootLogin no/' /etc/ssh/sshd_config
fi

# ssh 문법 테스트 및 서비스 재시작
if sshd -t; then
    systemctl restart ssh || systemctl restart sshd || true
    echo "  -> SSH daemon restarted on Port 20022."
else
    echo "[WARN] sshd configuration test failed. Please check manually."
fi

# ------------------------------------------------------------------------------
# 3. 방화벽(UFW) 정책 수립 (20022, 15034만 허용)
# ------------------------------------------------------------------------------
echo "[3/6] Configuring UFW Firewall Rules..."
ufw default deny incoming
ufw default allow outgoing
ufw allow 20022/tcp comment 'SSH Custom Port'
ufw allow 15034/tcp comment 'Agent App Service Port'
ufw --force enable
echo "  -> UFW firewall enabled with strict inbound rules."

# ------------------------------------------------------------------------------
# 4. 계정 및 그룹 체계 구성
# ------------------------------------------------------------------------------
echo "[4/6] Creating Groups and User Accounts..."
# 그룹 생성
groupadd -f agent-common
groupadd -f agent-core

# 계정 생성 함수 (비밀번호: codyssey123! 로 기본 세팅)
create_user_if_not_exists() {
    local username="$1"
    local primary_group="$2"
    local secondary_groups="$3"

    if ! id -u "${username}" >/dev/null 2>&1; then
        useradd -m -s /bin/bash -g "${primary_group}" -G "${secondary_groups}" "${username}"
        echo "${username}:codyssey123!" | chpasswd
        echo "  -> Created user '${username}'"
    else
        usermod -g "${primary_group}" -a -G "${secondary_groups}" "${username}"
        echo "  -> User '${username}' updated."
    fi
}

# 계정 생성 및 그룹 할당
create_user_if_not_exists "agent-admin" "agent-core" "agent-common,sudo"
create_user_if_not_exists "agent-dev"   "agent-core" "agent-common"
create_user_if_not_exists "agent-test"  "agent-common" "agent-common"

# ------------------------------------------------------------------------------
# 5. 디렉토리 구조 및 접근 권한(ACL) 설정
# ------------------------------------------------------------------------------
echo "[5/6] Establishing Directory Hierarchy and Permissions..."
AGENT_HOME="/home/agent-admin/agent-app"
LOG_DIR="/var/log/agent-app"

mkdir -p "${AGENT_HOME}/bin"
mkdir -p "${AGENT_HOME}/upload_files"
mkdir -p "${AGENT_HOME}/api_keys"
mkdir -p "${LOG_DIR}"

# 1) upload_files: agent-common 그룹 R/W 가능, 권한 2770 (setgid)
chown agent-admin:agent-common "${AGENT_HOME}/upload_files"
chmod 2770 "${AGENT_HOME}/upload_files"
# POSIX Default ACL 설정 (하위 파일/디렉토리도 그룹 R/W 유지)
setfacl -d -m g:agent-common:rwx "${AGENT_HOME}/upload_files" 2>/dev/null || true

# 2) api_keys: agent-core ONLY R/W 가능 (다른 사용자 완전 차단)
chown agent-admin:agent-core "${AGENT_HOME}/api_keys"
chmod 750 "${AGENT_HOME}/api_keys"

# 3) /var/log/agent-app: agent-core 그룹 R/W 가능
chown agent-admin:agent-core "${LOG_DIR}"
chmod 775 "${LOG_DIR}"
setfacl -d -m g:agent-core:rwx "${LOG_DIR}" 2>/dev/null || true

# 4) API Secret Key 파일 생성
SECRET_KEY_PATH="${AGENT_HOME}/api_keys/t_secret.key"
echo "agent_api_key_test" > "${SECRET_KEY_PATH}"
chown agent-admin:agent-core "${SECRET_KEY_PATH}"
chmod 640 "${SECRET_KEY_PATH}"

# 5) 모니터링 스크립트 배치 및 권한 부여 (소유: agent-dev:agent-core, 권한: 750)
SCRIPT_SRC="$(dirname "$0")/../bin/monitor.sh"
if [ -f "${SCRIPT_SRC}" ]; then
    cp "${SCRIPT_SRC}" "${AGENT_HOME}/bin/monitor.sh"
    chown agent-dev:agent-core "${AGENT_HOME}/bin/monitor.sh"
    chmod 750 "${AGENT_HOME}/bin/monitor.sh"
fi

# 6) 앱 소스코드 배치
APP_SRC="$(dirname "$0")/../app/agent_app.py"
if [ -f "${APP_SRC}" ]; then
    cp "${APP_SRC}" "${AGENT_HOME}/agent_app.py"
    chown agent-admin:agent-core "${AGENT_HOME}/agent_app.py"
    chmod 755 "${AGENT_HOME}/agent_app.py"
fi

# 7) 환경 변수 프로파일 작성 (/etc/profile.d/agent_env.sh)
cat << EOF > /etc/profile.d/agent_env.sh
export AGENT_HOME="${AGENT_HOME}"
export AGENT_PORT=15034
export AGENT_UPLOAD_DIR="${AGENT_HOME}/upload_files"
export AGENT_KEY_PATH="${SECRET_KEY_PATH}"
export AGENT_LOG_DIR="${LOG_DIR}"
EOF

# ------------------------------------------------------------------------------
# 6. cron 자동 실행 등록 (agent-admin 계정)
# ------------------------------------------------------------------------------
echo "[6/6] Registering monitor.sh in agent-admin crontab..."
CRON_JOB="* * * * * ${AGENT_HOME}/bin/monitor.sh >> ${LOG_DIR}/cron.log 2>&1"
# 기존 crontab에 중복 등록 방지
(crontab -u agent-admin -l 2>/dev/null | grep -v "monitor.sh" || true; echo "${CRON_JOB}") | crontab -u agent-admin -
systemctl enable cron
systemctl restart cron || true

echo "=========================================================="
echo "    Codyssey B4-1 Setup Completed Successfully!          "
echo "=========================================================="
echo "Verify configuration with: ./scripts/verify_all.sh"
