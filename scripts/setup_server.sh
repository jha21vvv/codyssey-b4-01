#!/bin/bash

set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
    echo "[ERROR] This setup script must be run as root (or with sudo)!" >&2
    exit 1
fi

echo "=========================================================="
echo "    Starting Codyssey B4-1 Infrastructure Automated Setup"
echo "=========================================================="

echo "[1/6] Installing required packages..."

if ! command -v sshd >/dev/null 2>&1 || ! command -v ufw >/dev/null 2>&1 || ! command -v getfacl >/dev/null 2>&1; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y || true
    apt-get install -y openssh-server ufw acl cron procps iproute2 python3 curl
fi

echo "[2/6] Configuring SSH Security (Port 20022, Root Login Disabled)..."

mkdir -p /etc/ssh/sshd_config.d

cat << 'EOF' > /etc/ssh/sshd_config.d/codyssey.conf
Port 20022
PermitRootLogin no
EOF

if grep -q "^#*Port " /etc/ssh/sshd_config; then
    sed -i 's/^#*Port .*/Port 20022/' /etc/ssh/sshd_config
fi

if grep -q "^#*PermitRootLogin " /etc/ssh/sshd_config; then
    sed -i 's/^#*PermitRootLogin .*/PermitRootLogin no/' /etc/ssh/sshd_config
fi

if sshd -t; then
    systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null || service ssh restart 2>/dev/null || service sshd restart 2>/dev/null || true
    echo "  -> SSH daemon restarted on Port 20022."
else
    echo "[WARN] sshd configuration test failed. Please check manually."
fi

echo "[3/6] Configuring UFW Firewall Rules..."

ufw default deny incoming

ufw default allow outgoing

ufw allow 20022/tcp comment 'SSH Custom Port'

ufw allow 15034/tcp comment 'Agent App Service Port'

ufw --force enable

echo "  -> UFW firewall enabled with strict inbound rules."

echo "[4/6] Creating Groups and User Accounts..."

groupadd -f agent-common

groupadd -f agent-core

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

create_user_if_not_exists "agent-admin" "agent-core" "agent-common,sudo"

create_user_if_not_exists "agent-dev"   "agent-core" "agent-common"

create_user_if_not_exists "agent-test"  "agent-common" "agent-common"

mkdir -p /etc/sudoers.d
echo "agent-admin ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/agent-admin
chmod 0440 /etc/sudoers.d/agent-admin

if [ -d "/usr/lib/wsl" ]; then
    grep -q '\[user\]' /etc/wsl.conf || echo -e '\n[user]\ndefault=agent-admin' >> /etc/wsl.conf
    cat << 'EOF' > /usr/lib/wsl/wsl-setup
#!/bin/bash
exit 0
EOF
    chmod +x /usr/lib/wsl/wsl-setup
fi

echo "[5/6] Establishing Directory Hierarchy and Permissions..."

AGENT_HOME="/home/agent-admin/agent-app"

LOG_DIR="${AGENT_LOG_DIR:-/var/log/agent-app}"

mkdir -p "${AGENT_HOME}/bin"

mkdir -p "${AGENT_HOME}/upload_files"

mkdir -p "${AGENT_HOME}/api_keys"

mkdir -p "${LOG_DIR}"

setfacl -m g:agent-common:rx /home/agent-admin
chmod 755 "${AGENT_HOME}"
chown agent-admin:agent-common "${AGENT_HOME}/upload_files"

chmod 2770 "${AGENT_HOME}/upload_files"

setfacl -d -m g:agent-common:rwx "${AGENT_HOME}/upload_files" 2>/dev/null || true

chown agent-admin:agent-core "${AGENT_HOME}/api_keys"

chmod 750 "${AGENT_HOME}/api_keys"

chown agent-admin:agent-core "${LOG_DIR}"

chmod 775 "${LOG_DIR}"

setfacl -d -m g:agent-core:rwx "${LOG_DIR}" 2>/dev/null || true

SECRET_KEY_PATH="${AGENT_HOME}/api_keys/t_secret.key"

echo "agent_api_key_test" > "${SECRET_KEY_PATH}"

chown agent-admin:agent-core "${SECRET_KEY_PATH}"

chmod 640 "${SECRET_KEY_PATH}"

SCRIPT_SRC="$(dirname "$0")/../bin/monitor.sh"

if [ -f "${SCRIPT_SRC}" ]; then
    cp "${SCRIPT_SRC}" "${AGENT_HOME}/bin/monitor.sh"
    chown agent-dev:agent-core "${AGENT_HOME}/bin/monitor.sh"
    chmod 750 "${AGENT_HOME}/bin/monitor.sh"
fi

APP_SRC="$(dirname "$0")/../app/agent_app.py"

if [ -f "${APP_SRC}" ]; then
    cp "${APP_SRC}" "${AGENT_HOME}/agent_app.py"
    chown agent-admin:agent-core "${AGENT_HOME}/agent_app.py"
    chmod 755 "${AGENT_HOME}/agent_app.py"
fi

cat << EOF > /etc/profile.d/agent_env.sh
export AGENT_HOME="${AGENT_HOME}"
export AGENT_PORT=15034
export AGENT_UPLOAD_DIR="${AGENT_HOME}/upload_files"
export AGENT_KEY_PATH="${SECRET_KEY_PATH}"
export AGENT_LOG_DIR="${LOG_DIR}"
EOF

cat << 'EOF' > /etc/systemd/system/agent-app.service
[Unit]
Description=Codyssey B4-1 Python Agent Application
After=network.target

[Service]
Type=simple
User=agent-admin
Group=agent-core
WorkingDirectory=/home/agent-admin/agent-app
ExecStart=/usr/bin/python3 -u /home/agent-admin/agent-app/agent_app.py
Restart=no
StandardOutput=append:/var/log/agent-app/app.log
StandardError=append:/var/log/agent-app/app.log

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable agent-app
systemctl restart agent-app || true

echo "[6/6] Registering monitor.sh in agent-admin crontab..."

CRON_JOB="* * * * * ${AGENT_HOME}/bin/monitor.sh >> ${LOG_DIR}/cron.log 2>&1"

(crontab -u agent-admin -l 2>/dev/null | grep -v "monitor.sh" || true; echo "${CRON_JOB}") | crontab -u agent-admin -

systemctl enable cron 2>/dev/null || true

systemctl restart cron 2>/dev/null || service cron restart 2>/dev/null || true

echo "=========================================================="
echo "    Codyssey B4-1 Setup Completed Successfully!          "
echo "=========================================================="

echo "Verify configuration with: ./scripts/verify_all.sh"

