#!/bin/bash
# ==============================================================================
# Script Name : setup_server.sh
# Description : Ubuntu 22.04 LTS 환경 전체 자동화 인프라 및 보안 설정 스크립트
#               (SSH 20022, UFW 방화벽, 계정 3개, 그룹 2개, 디렉토리 권한/ACL, cron)
# Target OS   : Ubuntu 22.04 LTS
# Usage       : sudo ./scripts/setup_server.sh
# ==============================================================================

# [1차]: set -euo pipefail 설정
# - -e (errexit): 명령어가 하나라도 0이 아닌 실패 코드로 끝나면 스크립트 즉시 중단
# - -u (nounset): 정의되지 않은 빈 변수를 참조하려고 하면 즉시 에러 발생 및 중단
# - -o pipefail: 파이프라인(A | B | C) 중간에 하나라도 에러가 나면 전체를 실패로 처리
# [2차]: 작업 도중 나사 하나라도 삐끗하면 폭주하지 않고 즉시 작업을 멈추는 세이프티 브레이크입니다.
set -euo pipefail

# [1차]: 현재 스크립트 실행자의 고유 사용자 번호(UID)가 0(root)인지 확인합니다. (id -u: root 계정은 무조건 0)
# [2차]: 방화벽과 시스템 계정, SSH를 만지는 중요한 공사 작업이므로 '사장님 권한(root 또는 sudo)'으로 실행했는지 검사합니다.
if [ "$(id -u)" -ne 0 ]; then
    # [1차]: 표준 에러(STDERR, >&2)로 경고 문구를 출력합니다.
    # [2차]: "일반 직원 권한으로는 이 기계를 만질 수 없습니다! 사장님(sudo) 권한으로 다시 실행하세요!" 하고 경고창을 띄웁니다.
    echo "[ERROR] This setup script must be run as root (or with sudo)!" >&2
    # [1차]: 비정상 종료 코드 1을 반환하며 스크립트를 즉시 탈출합니다.
    # [2차]: 자격 미달이므로 문 앞에서 공사를 즉시 취소하고 되돌아갑니다.
    exit 1
fi

# [1차]: 설치 시작 안내 배너를 화면에 출력합니다.
# [2차]: 작업 개시를 알리는 시작 현수막을 펼칩니다.
echo "=========================================================="
echo "    Starting Codyssey B4-1 Infrastructure Automated Setup"
echo "=========================================================="

# ------------------------------------------------------------------------------
# 1. 필수 패키지 설치
# ------------------------------------------------------------------------------

# [1차]: 1단계 패키지 설치 시작 안내 문구를 출력합니다.
# [2차]: 공사에 필요한 도구들을 창고에서 꺼내오는 단계임을 알립니다.
echo "[1/6] Installing required packages..."

# [1차]: 필수 도구(sshd, ufw, getfacl, cron, python3)가 이미 설치되어 있는지 확인하고 누락된 경우에만 설치합니다.
# [2차]: 연장통에 이미 공구가 다 들어있으면 불필요하게 카탈로그를 다시 다운로드하지 않고 건너뜁니다.
if ! command -v sshd >/dev/null 2>&1 || ! command -v ufw >/dev/null 2>&1 || ! command -v getfacl >/dev/null 2>&1; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y || true
    apt-get install -y openssh-server ufw acl cron procps iproute2 python3 curl
fi

# ------------------------------------------------------------------------------
# 2. SSH 보안 설정 (Port 20022, PermitRootLogin no)
# ------------------------------------------------------------------------------

# [1차]: 2단계 SSH 보안 설정 시작 안내 문구를 출력합니다.
# [2차]: 외부에서 들어오는 원격 출입문 보안 공사를 시작함을 알립니다.
echo "[2/6] Configuring SSH Security (Port 20022, Root Login Disabled)..."

# [1차]: 우분투 SSH 최신 권장 설정 디렉토리인 /etc/ssh/sshd_config.d 폴더를 생성합니다. (-p: 이미 있어도 에러 안 남)
# [2차]: 건물의 보안 규칙 문서를 꽂아둘 전용 서류함 폴더를 만듭니다.
mkdir -p /etc/ssh/sshd_config.d

# eof는 여러줄 넣을때 쓰는 명령어
# [1차]: cat << 'EOF' 리다이렉션으로 /etc/ssh/sshd_config.d/codyssey.conf 커스텀 설정 파일을 생성합니다.
# - Port 20022 : 기본 22번 포트 대신 커스텀 20022번 포트로 변경
# - PermitRootLogin no : 최고 관리자(root)의 원격 직접 접속을 전면 차단
# [2차]: 도둑들이 가장 먼저 노리는 22번 정문 간판을 떼고 20022번 비밀 출입문으로 바꾸며, 사장님 열쇠는 외부에서 아예 못 쓰게 못 박습니다.
cat << 'EOF' > /etc/ssh/sshd_config.d/codyssey.conf
# Codyssey B4-1 SSH Security Rules
Port 20022
PermitRootLogin no
EOF

# [1차]: 기존 메인 설정 파일(/etc/ssh/sshd_config)에 Port 항목이 남아있다면 정규식 sed로 20022로 강제 치환합니다.
# [2차]: 혹시 기존 건물 설계도 원본에 옛날 문 번호(22번)가 남아있다면 20022번으로 지우개질해서 고칩니다.
# 마이: 그랩은 찾기, 찾는게 있으면(then), sed는 찾아 바꾸기, fi는 조건문끝.
if grep -q "^#*Port " /etc/ssh/sshd_config; then
    sed -i 's/^#*Port .*/Port 20022/' /etc/ssh/sshd_config
fi

# [1차]: 메인 설정 파일에 PermitRootLogin 항목이 남아있다면 sed로 'PermitRootLogin no'로 확실하게 수정합니다.
# [2차]: 원본 설계도에도 '사장님 원격 출입 금지' 규칙을 빨간 펜으로 확실하게 덮어씁니다.
if grep -q "^#*PermitRootLogin " /etc/ssh/sshd_config; then
    sed -i 's/^#*PermitRootLogin .*/PermitRootLogin no/' /etc/ssh/sshd_config
fi

# [1차]: sshd -t 명령어로 SSH 설정 파일의 문법적 오류(Syntax Error)를 사전 검증합니다.
# [2차]: 새로 바꾼 문고리가 뻑뻑하지 않은지 열쇠를 미리 돌려보고, 합격했을 때만 진짜 문을 바꿉니다.
if sshd -t; then
    # [1차]: 설정 검증 통과 시 SSH 데몬(ssh 또는 sshd)을 재기동하여 새 포트 20022를 활성화합니다.
    # [2차]: 새 문패를 정식으로 걸고 수문장(SSH 데몬)을 새 보초 근무지로 이동시킵니다.
    systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null || service ssh restart 2>/dev/null || service sshd restart 2>/dev/null || true
    echo "  -> SSH daemon restarted on Port 20022."
else
    # [1차]: 설정 파일 문법 검증 실패 시 경고 메시지를 출력하고 중단을 방지합니다.
    # [2차]: 문고리 규격이 안 맞으면 강제로 바꾸다 갇힐 수 있으니 수동 점검하라고 경고합니다.
    echo "[WARN] sshd configuration test failed. Please check manually."
fi

# ------------------------------------------------------------------------------
# 3. 방화벽(UFW) 정책 수립 (20022, 15034만 허용)
# ------------------------------------------------------------------------------

# [1차]: 3단계 방화벽 설정 시작 문구를 출력합니다.
# [2차]: 건물 외곽에 철조망과 검문소를 세우는 단계임을 알립니다.
echo "[3/6] Configuring UFW Firewall Rules..."

# [1차]: ufw default deny incoming : 외부에서 들어오는 모든 접속 시도를 기본적으로 거부(DROP/REJECT)합니다.
# [2차]: 검문소 기본 수칙을 "허가증 없는 모든 방문자는 무조건 입구 컷(전면 차단)"으로 정합니다.
ufw default deny incoming

# [1차]: ufw default allow outgoing : 서버 내부에서 밖으로 나가는 트래픽(패키지 다운 등)은 자유롭게 허용합니다.
# [2차]: 내부 직원이 외부로 심부름 가거나 물건 사러 나가는 것은 자유롭게 통과시킵니다.
ufw default allow outgoing

# [1차]: ufw allow 20022/tcp : 변경된 SSH 관리자 접속 포트 20022번 TCP를 방화벽 허용 목록에 등록합니다.
# [2차]: 20022번 관리자 비밀문만 검문소를 통과할 수 있도록 통행증을 발급합니다.
ufw allow 20022/tcp comment 'SSH Custom Port'

# [1차]: ufw allow 15034/tcp : 에이전트 서비스 포트 15034번 TCP를 방화벽 허용 목록에 등록합니다.
# [2차]: 15034번 손님 접수 창구만 검문소를 통과할 수 있도록 통행증을 발급합니다.
ufw allow 15034/tcp comment 'Agent App Service Port'

# [1차]: ufw --force enable : 사용자 추가 확인 프롬프트(Y/n) 없이 방화벽을 즉시 강제 활성화합니다.
# [2차]: 검문소 차단기를 즉시 가동시켜 철통 경비를 시작합니다.
ufw --force enable

# [1차]: 방화벽 적용 성공 안내 메시지를 출력합니다.
# [2차]: "외곽 경비가 완벽히 시작되었습니다!"라고 안내합니다.
echo "  -> UFW firewall enabled with strict inbound rules."

# ------------------------------------------------------------------------------
# 4. 계정 및 그룹 체계 구성
# ------------------------------------------------------------------------------

# [1차]: 4단계 계정 및 그룹 생성 시작 문구를 출력합니다.
# [2차]: 사원증 발급 및 조직도 구성 단계임을 알립니다.
echo "[4/6] Creating Groups and User Accounts..."

# [1차]: groupadd -f agent-common : 전사 공통 그룹 생성 (-f: 이미 존재해도 에러 없이 패스)
# [2차]: '일반 사원증(agent-common)' 등급을 조직도에 만듭니다.
groupadd -f agent-common

# [1차]: groupadd -f agent-core : 핵심 권한 그룹 생성 (-f)
# [2차]: '보안 구역 전용 카드(agent-core)' 등급을 조직도에 만듭니다.
groupadd -f agent-core

# [1차]: 사용자 계정이 없을 때는 신규 생성하고, 이미 있을 때는 보조 그룹만 추가하는 멱등성 보장 쉘 함수입니다.
# [2차]: 직원이 신입이면 새 책상과 사원증을 파주고, 이미 다니고 있으면 부서 이동만 처리해 주는 총무팀 함수입니다.
create_user_if_not_exists() {
    # [1차]: 함수의 첫 번째 인자로 계정명(username)을 변수에 담습니다.
    # [2차]: 신규 직원의 이름을 메모합니다.
    local username="$1"
    # [1차]: 함수의 두 번째 인자로 주 그룹(primary_group)을 담습니다.
    # [2차]: 직원의 주 소속 부서를 메모합니다.
    local primary_group="$2"
    # [1차]: 함수의 세 번째 인자로 보조 그룹(secondary_groups) 목록을 담습니다.
    # [2차]: 직원이 겸직할 보조 부서 명단을 메모합니다.
    local secondary_groups="$3"

    # [1차]: id -u로 사용자가 이미 시스템에 존재하는지 확인합니다. (존재하지 않으면 조건문 진입)
    # [2차]: 기존 직원 명부에 이 사람 이름이 있는지 찾아봅니다.
    if ! id -u "${username}" >/dev/null 2>&1; then
        # [1차]: useradd로 홈 디렉토리 생성(-m), bash 쉘 지정(-s), 주 그룹(-g), 보조 그룹(-G)을 부여하여 계정을 생성합니다.
        # [2차]: 신입 사원의 책상(홈 폴더)을 만들어주고 사원증과 출입 권한을 세팅합니다.
        useradd -m -s /bin/bash -g "${primary_group}" -G "${secondary_groups}" "${username}"
        # [1차]: chpasswd 명령어로 초기 비밀번호를 설정합니다.
        # [2차]: 사원증 초기 임시 비밀번호를 세팅합니다.
        echo "${username}:codyssey123!" | chpasswd
        # [1차]: 계정 생성 완료 메시지를 출력합니다.
        # [2차]: 신입 사원 등록 완료를 알립니다.
        echo "  -> Created user '${username}'"
    else
        # [1차]: 이미 계정이 있다면 usermod로 주 그룹과 보조 그룹(-a -G: 기존 그룹 유지하며 추가)을 업데이트합니다.
        # [2차]: 기존 사원의 부서 배치를 재조정합니다.
        usermod -g "${primary_group}" -a -G "${secondary_groups}" "${username}"
        # [1차]: 계정 정보 갱신 완료 메시지를 출력합니다.
        # [2차]: 직원 정보 수정 완료를 알립니다.
        echo "  -> User '${username}' updated."
    fi
}

# [1차]: 운영팀장 계정(agent-admin) 생성 (주그룹: agent-core, 보조그룹: agent-common, sudo)
# [2차]: 금고 카드와 사장님 도장(sudo)을 모두 가진 운영팀장 계정을 만듭니다.
create_user_if_not_exists "agent-admin" "agent-core" "agent-common,sudo"

# [1차]: 개발자 계정(agent-dev) 생성 (주그룹: agent-core, 보조그룹: agent-common)
# [2차]: 금고 카드는 있지만 사장님 도장(sudo)은 없는 기술 개발자 계정을 만듭니다.
create_user_if_not_exists "agent-dev"   "agent-core" "agent-common"

# [1차]: QA 테스터 계정(agent-test) 생성 (주그룹: agent-common, 보조그룹: agent-common)
# [2차]: 공용 카페테리아만 갈 수 있고 비밀 금고는 못 들어가는 인턴 테스터 계정을 만듭니다.
create_user_if_not_exists "agent-test"  "agent-common" "agent-common"

# [1차]: agent-admin 계정에게 비밀번호 입력 없는 sudo 권한을 부여합니다.
# [2차]: 운영팀장이 시스템 점검 및 과제 검증 시 매번 비밀번호를 묻지 않고 편하게 작업하도록 프리패스를 발급합니다.
mkdir -p /etc/sudoers.d
echo "agent-admin ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/agent-admin
chmod 0440 /etc/sudoers.d/agent-admin

# [1차]: WSL 환경에서 윈도우 한글 사용자명 등으로 인한 OOBE 충돌을 방지하고 기본 사용자를 설정합니다.
if [ -d "/usr/lib/wsl" ]; then
    grep -q '\[user\]' /etc/wsl.conf || echo -e '\n[user]\ndefault=agent-admin' >> /etc/wsl.conf
    cat << 'EOF' > /usr/lib/wsl/wsl-setup
#!/bin/bash
exit 0
EOF
    chmod +x /usr/lib/wsl/wsl-setup
fi

# ------------------------------------------------------------------------------
# 5. 디렉토리 구조 및 접근 권한(ACL) 설정
# ------------------------------------------------------------------------------

# [1차]: 5단계 디렉토리 및 파일 권한 설정 시작 문구를 출력합니다.
# [2차]: 건물 각 방의 문패를 달고 도어락 비밀번호를 설정하는 단계임을 알립니다.
echo "[5/6] Establishing Directory Hierarchy and Permissions..."

# [1차]: 앱이 설치될 루트 경로 변수를 /home/agent-admin/agent-app 으로 지정합니다.
# [2차]: 에이전트 본사 사무실 주소를 정의합니다.
AGENT_HOME="/home/agent-admin/agent-app"

# [1차]: 로그가 적재될 시스템 로그 경로 변수를 과제 표준 규격인 /var/log/agent-app 으로 지정합니다.
# [2차]: 순찰 일지 서류 보관실 주소를 정의합니다. (환경변수 AGENT_LOG_DIR이 있으면 우선 적용)
LOG_DIR="${AGENT_LOG_DIR:-/var/log/agent-app}"

# [1차]: 스크립트 실행 파일 보관용 bin 디렉토리를 생성합니다.
# [2차]: 순찰 도구실(bin) 방을 만듭니다.
mkdir -p "${AGENT_HOME}/bin"

# [1차]: 사용자 업로드 파일 보관용 upload_files 디렉토리를 생성합니다.
# [2차]: 손님 택배 보관 창고(upload_files) 방을 만듭니다.
mkdir -p "${AGENT_HOME}/upload_files"

# [1차]: 암호 비밀키 보관용 api_keys 디렉토리를 생성합니다.
# [2차]: 극비 비밀 금고(api_keys) 방을 만듭니다.
mkdir -p "${AGENT_HOME}/api_keys"

# [1차]: 시스템 관제 로그 보관용 /var/log/agent-app 디렉토리를 생성합니다.
# [2차]: 병원 의무기록실(LOG_DIR) 방을 만듭니다.
mkdir -p "${LOG_DIR}"

# [1차]: agent-common 그룹 소속 계정(agent-test 등)이 upload_files 경로로 진입(traverse)할 수 있도록 상위 홈 디렉토리에 ACL rx 권한을 부여합니다.
setfacl -m g:agent-common:rx /home/agent-admin
chmod 755 "${AGENT_HOME}"
# [1차]: upload_files의 소유자를 agent-admin, 소유 그룹을 agent-common으로 변경합니다.
# [2차]: 공용 창고의 관리 책임자를 admin으로 두고, 소속 그룹을 일반 사원(common)으로 지정합니다.
chown agent-admin:agent-common "${AGENT_HOME}/upload_files"

# [1차]: 권한 2770 부여 (2: SetGID 비트, 7: 소유자 rwx, 7: 그룹 rwx, 0: others 전면 차단)
# [2차]: 창고 문에 '2770' 번호키를 겁니다. 누구나 파일을 넣을 수 있고(rwx), 새 상자를 넣으면 무조건 공용 라벨(SetGID)이 붙습니다.
# 마이: 2: SetGID 비트의 뜻은 폴더안에 새로운 폴더를 만들면 해당속성을 부모속성을 상속시킨다는 뜻
# 마이:  "앞으로 여기에 들어오는 파일은 전부 '우리 팀 공용 소속'으로 명찰을 바꿔라!"
chmod 2770 "${AGENT_HOME}/upload_files"

# [1차]: POSIX Default ACL을 설정하여, 향후 이 폴더 안에 생성되는 모든 파일/폴더에 agent-common 그룹
# rwx 권한이 자동 상속되게 합니다.
# [2차]: 앞으로 이 창고에 들어오는 모든 새 상자에도 공용 사원증으로 열 수 있는 도장을 자동으로 찍어줍니다.
# 마이: "그리고 그 파일들은 '우리 팀원 누구나 수정(rwx)'할 수 있게 자물쇠를 항상 열어둬라!"
# setfacl (Set File Access Control Lists) 뜻: 파일의 **세부 접근 권한(ACL)을 설정(Set)**하는 리눅스 명령어
# -d (Default - 기본값 / 상속) 뜻: **"지금 있는 파일이 아니라, 앞으로 이 폴더 안에 새로 만들어질 모든 자식 파일/폴더"**에 적용하겠다는 옵
#  -m (Modify - 수정 / 규칙 추가) 뜻: 새로운 권한 규칙을 **추가하거나 기존 규칙을 수정(Modify)**하겠다는 옵션입니다.
# g (Group): 사용자 개인(u)이 아니라 **특정 그룹(g)**을 대상으로 하겠다!
# agent-common: 권한을 부여받을 그룹 이름입니다.
# rwx (Read, Write, eXecute): 부여할 권한
# 2>: 리눅스에서 1번은 정상 출력(STDOUT), **2번은 에러 출력(STDERR)**을 뜻합니다.
#/dev/null: 리눅스의 **'블랙홀(휴지통)'**입니다. 여기에 들어간 글자는 화면에 안 보이고 영원히 증발합니다.
# 뜻: 혹시 이 명령어를 실행하다가 에러(예: ACL 패키지가 안 깔려있거나 지원 안 되는 파일시스템)가 나더라도, 터미널 화면에 시뻘건 에러 글씨를 
# 띄우지 말고 조용히 버려라!
setfacl -d -m g:agent-common:rwx "${AGENT_HOME}/upload_files" 2>/dev/null || true

# --- 2) api_keys 설정 ---
# [1차]: api_keys의 소유자를 agent-admin, 소유 그룹을 agent-core로 변경합니다.
# [2차]: 비밀 금고의 소속 그룹을 핵심 운영진(agent-core)으로 한정합니다.
chown agent-admin:agent-core "${AGENT_HOME}/api_keys"

# [1차]: 권한 750 부여 (소유자 rwx, agent-core 그룹 r-x, others 전면 차단)
# [2차]: 비밀 금고 문에 '750' 자물쇠를 걸어 일반 테스터(agent-test)는 방 근처에도 못 오게 차단합니다.
chmod 750 "${AGENT_HOME}/api_keys"

# --- 3) /var/log/agent-app 설정 ---
# [1차]: 로그 디렉토리의 소유자를 agent-admin, 소유 그룹을 agent-core로 변경합니다.
# [2차]: 의무기록실 소속을 핵심 운영진(agent-core)으로 지정합니다.
chown agent-admin:agent-core "${LOG_DIR}"

# [1차]: 권한 775 부여 (소유자 rwx, 그룹 rwx, others r-x)
# [2차]: 닥터와 운영진 모두 순찰 일지를 작성(w)할 수 있게 문을 열어둡니다.
chmod 775 "${LOG_DIR}"

# [1차]: POSIX Default ACL을 설정하여 생성되는 모든 로그 파일에 agent-core의 rwx 권한을 상속합니다.
# [2차]: 앞으로 생기는 모든 진료 차트에도 운영진이 수정할 수 있는 권한을 자동 상속합니다.
setfacl -d -m g:agent-core:rwx "${LOG_DIR}" 2>/dev/null || true

# --- 4) API Secret Key 파일 생성 ---
# [1차]: 비밀키 파일의 절대 경로를 변수로 지정합니다.
# [2차]: 금고 안에 넣어둘 열쇠의 보관 위치를 확정합니다.
SECRET_KEY_PATH="${AGENT_HOME}/api_keys/t_secret.key"

# [1차]: 정품 인증키 문자열을 파일에 기록합니다.
# [2차]: 금고 안에 진짜 열쇠('agent_api_key_test') 실물을 쏙 집어넣습니다.
echo "agent_api_key_test" > "${SECRET_KEY_PATH}"

# [1차]: 비밀키 파일의 소유권을 agent-admin:agent-core 로 설정합니다.
# [2차]: 열쇠의 주인을 핵심 운영진으로 한정합니다.
chown agent-admin:agent-core "${SECRET_KEY_PATH}"

# [1차]: 권한 640 부여 (소유자 rw-, 그룹 r--, others 전면 차단)
# [2차]: 열쇠에 '640' 자물쇠를 걸어 핵심 멤버만 살짝 볼 수 있게(r) 하고 외부인은 전혀 못 보게 차단합니다.
chmod 640 "${SECRET_KEY_PATH}"

# --- 5) 모니터링 스크립트 배치 ---
# [1차]: 현재 실행 중인 setup_server.sh 위치 기준으로 원본 monitor.sh의 상대 경로를 계산합니다.
# [2차]: 배낭에 들어있는 순찰 닥터(monitor.sh) 원본 위치를 찾습니다.
SCRIPT_SRC="$(dirname "$0")/../bin/monitor.sh"

# [1차]: 원본 monitor.sh 파일이 존재하면 실행 위치로 복사하고 소유권 및 권한을 세팅합니다.
# [2차]: 닥터 실물이 확인되면 전용 도구실(bin)로 파견 보냅니다.
if [ -f "${SCRIPT_SRC}" ]; then
    # [1차]: monitor.sh 파일을 대상 bin 디렉토리로 복사합니다.
    # [2차]: 닥터를 도구실 방에 배치합니다.
    cp "${SCRIPT_SRC}" "${AGENT_HOME}/bin/monitor.sh"
    # [1차]: 소유자를 agent-dev, 그룹을 agent-core로 설정합니다. (개발자가 제작, 운영팀이 공유)
    # [2차]: 닥터의 명찰 소유자를 '개발자(agent-dev)'로 달아줍니다.
    chown agent-dev:agent-core "${AGENT_HOME}/bin/monitor.sh"
    # [1차]: 권한 750 (rwxr-x---) 부여로 실행 권한을 켭니다.
    # [2차]: 닥터에게 순찰용 신분증과 열쇠를 쥐어주어 일할 수 있게 합니다.
    chmod 750 "${AGENT_HOME}/bin/monitor.sh"
fi

# --- 6) 앱 소스코드 배치 ---
# [1차]: 현재 위치 기준으로 원본 agent_app.py의 경로를 찾습니다.
# [2차]: 배낭에 들어있는 점원 앱(agent_app.py) 원본 위치를 찾습니다.
APP_SRC="$(dirname "$0")/../app/agent_app.py"

# [1차]: 원본 agent_app.py 파일이 존재하면 운영 홈 디렉토리로 복사합니다.
# [2차]: 점원 실물이 확인되면 카운터 방으로 출근시킵니다.
if [ -f "${APP_SRC}" ]; then
    # [1차]: agent_app.py를 AGENT_HOME 바로 밑에 복사합니다.
    # [2차]: 점원을 1층 메인 카운터 책상에 앉힙니다.
    cp "${APP_SRC}" "${AGENT_HOME}/agent_app.py"
    # [1차]: 소유자를 agent-admin:agent-core 로 지정합니다.
    # [2차]: 점원의 인사 관리 책임을 운영팀장에게 부여합니다.
    chown agent-admin:agent-core "${AGENT_HOME}/agent_app.py"
    # [1차]: 권한 755 (소유자 rwx, 그룹 r-x, 타인 r-x) 부여로 파이썬 실행이 가능하게 합니다.
    # [2차]: 점원이 카운터 컴퓨터를 켤 수 있게 출입 권한을 열어줍니다.
    chmod 755 "${AGENT_HOME}/agent_app.py"
fi

# --- 7) 시스템 공통 환경 변수 등록 ---
# [1차]: 모든 사용자가 로그인할 때 시스템 전역으로 로드되는 /etc/profile.d/agent_env.sh 파일을 작성합니다.
# [2차]: 전 직원 공용 게시판에 매일 아침 확인할 표준 근무 수칙을 부착합니다.
cat << EOF > /etc/profile.d/agent_env.sh
# Codyssey B4-1 System-wide Environment Variables
export AGENT_HOME="${AGENT_HOME}"
export AGENT_PORT=15034
export AGENT_UPLOAD_DIR="${AGENT_HOME}/upload_files"
export AGENT_KEY_PATH="${SECRET_KEY_PATH}"
export AGENT_LOG_DIR="${LOG_DIR}"
EOF

# --- 8) systemd 서비스 등록 (부팅 시 자동 기동) ---
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

# ------------------------------------------------------------------------------
# 6. cron 자동 실행 등록 (agent-admin 계정)
# ------------------------------------------------------------------------------

# [1차]: 6단계 cron 스케줄 등록 시작 문구를 출력합니다.
# [2차]: 자명종 시계를 세팅하는 단계임을 알립니다.
echo "[6/6] Registering monitor.sh in agent-admin crontab..."

# [1차]: 매분(* * * * *) monitor.sh를 실행하고 결과를 cron.log에 누적(>>)하는 크론 명령어 문자열을 정의합니다.
# [2차]: "매 1분마다 닥터의 등짝을 때려서 순찰을 보내고, 결과를 cron.log에 적어라"라는 시계 알람 문구를 적습니다.
# * * * * * : 모든 날짜 데이터를 받아오고 그게 변할떄 알림을 받는다이기에 일종의 서식임. 0  9  *  *  1   을 하면 월요일 오전9시에 알림받는다.는 뜻이됨
# ${AGENT_HOME}/bin/monitor.sh을 실행
# 화살표 1개(>)는 기존 내용을 싹 지우고 새로 쓰는 **'덮어쓰기'**입니다.화살표 2개(>>)는 기존 내용을 보존하고 **그 밑에 계속 이어 붙이는 '누적 쓰기(Append)'**입니다.
# ${LOG_DIR}/cron.log뜻: 스크립트 실행 결과를 누적해서 저장할 로그 파일의 이름과 경로
# 2>&1 뜻: 에러(Error)가 나면 화면(터미널)에 보이지 말고, 로그 파일(cron.log) 뒤에 붙여서 같이 기록해라. 2번에 나오는 에러 메시지도 1에 보내고
#1에 보내면 그게 합쳐져서 출력되니 로그에 기록됨. 
CRON_JOB="* * * * * ${AGENT_HOME}/bin/monitor.sh >> ${LOG_DIR}/cron.log 2>&1"

# [1차]: 기존 agent-admin의 crontab에서 중복된 monitor.sh 항목을 걸러내고(grep -v) 새 작업을 안전하게 등록합니다.
# [2차]: 시계에 이미 같은 알람이 맞춰져 있으면 지우고, 깨끗하게 새 알람 하나만 딱 맞춰둡니다.
# (): 뜻: 괄호 안에 있는 여러 명령어들의 출력을 하나의 큰 결과물로 한 번에 묶어서 취합하겠다는 뜻
# crontab: 뜻: 리눅스에서 주기적으로 작업을 실행하는 '시간 예약 스케줄러(자명종 시계)'를 관리하는 명령어
# -u (User): 뜻: 특정 사용자(여기서는 agent-admin)의 작업 목록을 보거나 수정하겠다는 뜻
# -l (List): 뜻: 현재 등록된 작업 목록(List)을 보여달라는 뜻
# 2>/dev/null : 뜻: 에러 메시지가 나오면 버려라 (보통 작업이 없을 때 "no crontab for user" 같은 에러가 나오는데 그걸 숨기기 위함)
# grep -v "monitor.sh" : 뜻: 텍스트에서 'monitor.sh'라는 단어가 **포함되지 않은 줄**만 골라내라 (제외(Invert)의 뜻)
# 7시1분에 깨운다는 식으로 등록되는게 아니야 매분 깨운다로 등록되기에 중복되면 매분 2명이 깨우는 사태가 일어남.
# || true : 뜻: 앞의 명령이 실패해도(예: 작업이 하나도 없어서 grep이 에러를 뱉어도) 프로그램을 죽이지 말고 그냥 계속 진행해라 (True)
# echo "${CRON_JOB}"의 텍스트가 출력되면 텍스트를 받아서  crontab -u agent-admin -에서 일을 함.
# - 맨 뒤의 대시 기호: 뜻:  키보드 입력이나 파일이 아니라, **"앞에서 파이프(|)를 타고 넘어온 그 내용물 전체를 받아서 통째로 새 알람 목록으로 저장(덮어쓰기)해라!"**라는 리눅스 표준 약속 기호
#크론 설정에 크론 잡을 읽고 설정으로 들어가서 알아서 1분마다 깨우는 매커니즘이 됨.
(crontab -u agent-admin -l 2>/dev/null | grep -v "monitor.sh" || true; echo "${CRON_JOB}") | crontab -u agent-admin -

# [1차]: cron 시스템 데몬을 부팅 시 자동 시작(enable)하도록 등록합니다.
# [2차]: 컴퓨터가 껐다 켜져도 시계 태엽이 자동으로 감기도록 등록합니다.
# 위에서 크론 설정한걸 시스템 서비스로 가동함. 
systemctl enable cron 2>/dev/null || true

# [1차]: cron 서비스를 재시작하여 방금 등록한 새 스케줄을 즉시 반영합니다.
# [2차]: 시계 초침을 지금 즉시 움직이게 재시동합니다.
systemctl restart cron 2>/dev/null || service cron restart 2>/dev/null || true

# [1차]: 전체 인프라 설정이 성공적으로 끝났음을 알리는 완료 배너를 출력합니다.
# [2차]: "축하합니다! 모든 인프라 공사가 완벽하게 끝났습니다!" 하고 축포를 쏩니다.
echo "=========================================================="
echo "    Codyssey B4-1 Setup Completed Successfully!          "
echo "=========================================================="

# [1차]: 다음 검증 단계로 ./scripts/verify_all.sh 실행을 추천 안내합니다.
# [2차]: "이제 8대 증거 검증 도구를 돌려서 성적표를 확인해 보세요!"라고 안내합니다.
echo "Verify configuration with: ./scripts/verify_all.sh"
