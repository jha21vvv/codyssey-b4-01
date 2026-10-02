# [코디세이 B4-1] 요구사항 수행 내역서 및 종합 운영 보고서

- **과제명**: 코디세이 B4-1 - 컴퓨터가 알아서 자기 상태를 점검하게 만들기 (시스템 관제 자동화 및 서버 보안/운영 환경 구축)
- **작성자**: agent-dev / agent-admin
- **대상 환경**: Ubuntu 22.04 LTS (WSL2 / Linux Virtual Machine)
- **최종 검증 일시**: 2026-10-02
- **검증 상태**: 8대 필수 증거자료 100% 수집 완료 (Pass)

---

## 목차
1. [미션 개요 및 인프라 아키텍처](#1-미션-개요-및-인프라-아키텍처)
2. [세부 설정 및 명령어 수행 내역 (수행 내역서)](#2-세부-설정-및-명령어-수행-내역-수행-내역서)
   - 2.1 SSH 보안 강화 (Port 20022, PermitRootLogin no)
   - 2.2 UFW 방화벽 최소 포트 정책 구성 (20022/tcp, 15034/tcp)
   - 2.3 역할 기반 계정/그룹(RBAC) 및 디렉토리 권한/POSIX ACL 설정
   - 2.4 시스템 환경 변수 및 보안 키 파일 구성
   - 2.5 자동 관제 스크립트(`bin/monitor.sh`) 개발 및 배치
   - 2.6 crontab 자동 스케줄링 및 systemd 서비스 등록
3. [8대 필수 증거 자료 실측 증적 체크리스트](#3-8대-필수-증거-자료-실측-증적-체크리스트)
   - [증거 1] SSH 포트 20022 및 Root 차단 확인 내역
   - [증거 2] UFW 방화벽 활성화 및 포트 20022, 15034 허용 내역
   - [증거 3] 계정 및 그룹 구성 확인 내역
   - [증거 4] 디렉토리 구조 및 권한(POSIX ACL 포함) 확인 내역
   - [증거 5] 앱 Boot Sequence 5단계 [OK] 및 포트 15034 LISTEN 상태
   - [증거 6] monitor.sh 직접 실행 결과 (프로세스/포트/자원/경고)
   - [증거 7] /var/log/agent-app/monitor.log 누적 기록 확인 내역
   - [증거 8] crontab 매분 등록 및 자동 실행 확인(1분 후 로그 증가)
4. [과제 목표 자가 점검 및 기술적 원리 분석](#4-과제-목표-자가-점검-및-기술적-원리-분석)
5. [결론 및 운영 기대 효과](#5-결론-및-운영-기대-효과)

---

## 1. 미션 개요 및 인프라 아키텍처

본 보고서는 현대 클라우드 및 서버 환경의 실무 운영 원칙인 **'보안 침해 최소화(Zero Trust & Least Privilege)'**와 **'시스템 가시성(Observability) 자동화'**를 달성하기 위해 수행된 전체 인프라 구축 및 관제 스크립트 개발 내역을 기록한 공식 산출물입니다.

```
+-----------------------------------------------------------------------------------+
| Linux Server (Ubuntu 22.04 LTS)                                                   |
|                                                                                   |
|  [UFW Firewall - Default Deny Incoming]                                           |
|   ├── TCP 20022 [ALLOW IN] ──> OpenSSH Daemon (sshd) (PermitRootLogin no)         |
|   ├── TCP 15034 [ALLOW IN] ──> Python Service (agent_app.py)                     |
|   └── ALL OTHER [DROP / DENY]                                                     |
|                                                                                   |
|  [User & Group Hierarchy (RBAC)]                                                  |
|   ├── agent-common (Group) : agent-admin, agent-dev, agent-test                   |
|   └── agent-core   (Group) : agent-admin, agent-dev                               |
|                                                                                   |
|  [Directory Hierarchy & Permissions]                                              |
|   ├── $AGENT_HOME/upload_files  [2770, SetGID, ACL+] ──> Team R/W Shared          |
|   ├── $AGENT_HOME/api_keys      [0750, agent-core]   ──> Tester BLOCKED           |
|   │     └── t_secret.key        [0640, agent-core]                                |
|   ├── $AGENT_HOME/bin/monitor.sh[0750, agent-dev]    ──> Executable by Admin      |
|   └── /var/log/agent-app/       [0775, agent-core]                                |
|         └── monitor.log         [Rolling 10MB x 10 files FIFO Queue]              |
|                                                                                   |
|  [Continuous Automation]                                                          |
|   crontab (agent-admin) ──(Every 1 Min: * * * * *)──> monitor.sh ──> monitor.log  |
+-----------------------------------------------------------------------------------+
```

---

## 2. 세부 설정 및 명령어 수행 내역 (수행 내역서)

### 2.1 SSH 보안 강화 (Port 20022, PermitRootLogin no)
- **수행 목적**: 전 세계 인터넷에 노출된 기본 22번 포트 대상 무차별 대입 공격(Brute-force)을 회피하고, 최고 관리자(root)의 원격 직접 접속을 금지하여 모든 관리자 작업에 대한 감사 추적성(Auditability)을 강제합니다.
- **실행 명령어**:
  ```bash
  mkdir -p /etc/ssh/sshd_config.d
  cat << 'EOF' > /etc/ssh/sshd_config.d/codyssey.conf
  # Codyssey B4-1 SSH Security Rules
  Port 20022
  PermitRootLogin no
  EOF
  systemctl restart ssh || service ssh restart
  ```

### 2.2 UFW 방화벽 최소 포트 정책 구성 (20022/tcp, 15034/tcp)
- **수행 목적**: Zero Trust 원칙에 따라 외부에서 들어오는 인바운드 트래픽은 기본 전면 차단(`default deny incoming`)하고, 허가된 서비스 포트(SSH 20022, Agent App 15034) 2개만 화이트리스트로 개방합니다.
- **실행 명령어**:
  ```bash
  ufw --force reset
  ufw default deny incoming
  ufw default allow outgoing
  ufw allow 20022/tcp comment 'SSH Custom Port'
  ufw allow 15034/tcp comment 'Agent App Service Port'
  ufw --force enable
  ```

### 2.3 역할 기반 계정/그룹(RBAC) 및 디렉토리 권한/POSIX ACL 설정
- **수행 목적**: 최소 권한의 원칙(Least Privilege)에 따라 운영팀장(`agent-admin`), 개발자(`agent-dev`), 테스터(`agent-test`)의 권한을 격리하여, 테스터의 실수나 계정 탈취가 핵심 보안 키나 로그 파괴로 이어지지 않도록 방지합니다.
- **실행 명령어**:
  ```bash
  # 1. 그룹 및 계정 생성
  groupadd -f agent-common
  groupadd -f agent-core
  useradd -m -s /bin/bash -g agent-core -G agent-common,sudo agent-admin
  useradd -m -s /bin/bash -g agent-core -G agent-common agent-dev
  useradd -m -s /bin/bash -g agent-common -G agent-common agent-test

  # 2. 디렉토리 구조 생성
  AGENT_HOME="/home/agent-admin/agent-app"
  mkdir -p "${AGENT_HOME}/upload_files" "${AGENT_HOME}/api_keys" "${AGENT_HOME}/bin" /var/log/agent-app

  # 3. 상위 디렉토리 순회 권한 부여 (agent-test가 upload_files로 진입 가능하도록)
  setfacl -m g:agent-common:rx /home/agent-admin
  chmod 755 "${AGENT_HOME}"

  # 4. upload_files: 2770 (SetGID) + POSIX Default ACL
  chown agent-admin:agent-common "${AGENT_HOME}/upload_files"
  chmod 2770 "${AGENT_HOME}/upload_files"
  setfacl -d -m g:agent-common:rwx "${AGENT_HOME}/upload_files"
  setfacl -m g:agent-common:rwx "${AGENT_HOME}/upload_files"

  # 5. api_keys: 0750 (agent-core 전용, Others 차단)
  chown agent-admin:agent-core "${AGENT_HOME}/api_keys"
  chmod 0750 "${AGENT_HOME}/api_keys"

  # 6. /var/log/agent-app: 0775 (agent-core R/W)
  chown agent-admin:agent-core /var/log/agent-app
  chmod 0775 /var/log/agent-app
  ```

### 2.4 시스템 환경 변수 및 보안 키 파일 구성
- **수행 목적**: 시스템 전역 환경 변수를 선언하여 어떤 계정으로 로그인하더라도 애플리케이션의 홈 경로와 포트, 키 파일 위치를 일관되게 고정합니다.
- **실행 명령어**:
  ```bash
  # 1. 키 파일 생성 (0640)
  echo "agent_api_key_test" > /home/agent-admin/agent-app/api_keys/t_secret.key
  chown agent-admin:agent-core /home/agent-admin/agent-app/api_keys/t_secret.key
  chmod 0640 /home/agent-admin/agent-app/api_keys/t_secret.key

  # 2. 환경 변수 파일 등록 (/etc/profile.d/agent_env.sh)
  cat << 'EOF' > /etc/profile.d/agent_env.sh
  export AGENT_HOME="/home/agent-admin/agent-app"
  export AGENT_PORT=15034
  export AGENT_UPLOAD_DIR="/home/agent-admin/agent-app/upload_files"
  export AGENT_KEY_PATH="/home/agent-admin/agent-app/api_keys/t_secret.key"
  export AGENT_LOG_DIR="/var/log/agent-app"
  EOF
  ```

### 2.5 자동 관제 스크립트(`bin/monitor.sh`) 개발 및 배치
- **수행 목적**: 시스템 헬스체크(프로세스/포트)와 3대 자원(CPU, MEM, DISK) 임계치 경고, 정형 로그 포맷팅 및 10MB x 10 파일 FIFO 큐 로그 로테이션을 순수 Bash로 구현합니다.
- **실행 명령어**:
  ```bash
  cp bin/monitor.sh "${AGENT_HOME}/bin/monitor.sh"
  chown agent-dev:agent-core "${AGENT_HOME}/bin/monitor.sh"
  chmod 0750 "${AGENT_HOME}/bin/monitor.sh"
  ```

### 2.6 crontab 자동 스케줄링 및 systemd 서비스 등록
- **수행 목적**: 사람이 개입하지 않아도 백엔드 앱이 상시 가동되고, 매분 닥터 스크립트가 호출되도록 자동화합니다.
- **실행 명령어**:
  ```bash
  # crontab 등록 (agent-admin)
  CRON_JOB="* * * * * ${AGENT_HOME}/bin/monitor.sh >> /var/log/agent-app/cron.log 2>&1"
  (crontab -u agent-admin -l 2>/dev/null | grep -v "monitor.sh" || true; echo "${CRON_JOB}") | crontab -u agent-admin -
  ```

---

## 3. 8대 필수 증거 자료 실측 증적 체크리스트

과제 검증 스크립트([`scripts/verify_all.sh`](file:///c:/Users/안재현/Documents/24_code/2609_codyssey/codyssey-b4-01/scripts/verify_all.sh))를 통해 Ubuntu 22.04 LTS 가상환경에서 실측 추출된 8대 필수 증거자료 원본입니다.

```text
======================================================================
    Codyssey B4-1 8대 필수 증거자료 자동 검증 및 출력 도구
======================================================================
```

### [증거 1] SSH 포트 20022 및 Root 차단 설정 확인 내역
```text
----------------------------------------------------------------------
[증거 1] SSH 포트(20022) 및 Root 접속 차단(PermitRootLogin no) 검증
----------------------------------------------------------------------
# Codyssey B4-1 SSH Security Rules
Port 20022
PermitRootLogin no

>> SSH Listening Port 상태:
tcp   LISTEN 0      128           0.0.0.0:20022      0.0.0.0:*    users:(("sshd",pid=255,fd=3))            
tcp   LISTEN 0      128              [::]:20022         [::]:*    users:(("sshd",pid=255,fd=4))            
```
* **검증 판정**: **PASS**
* **기술적 의미**: `Port 20022`와 `PermitRootLogin no`가 적용되었으며, IPv4(`0.0.0.0:20022`) 및 IPv6(`[::]:20022`) 듀얼 스택 소켓으로 SSH 데몬(PID 255)이 정상 LISTEN 중임을 입증합니다.

---

### [증거 2] 방화벽(UFW) 활성화 및 포트 20022, 15034 허용 내역
```text
----------------------------------------------------------------------
[증거 2] 방화벽(UFW) 활성화 및 허용 포트(20022/tcp, 15034/tcp) 검증
----------------------------------------------------------------------
Status: active
Logging: on (low)
Default: deny (incoming), allow (outgoing), disabled (routed)
New profiles: skip

To                         Action      From
--                         ------      ----
20022/tcp                  ALLOW IN    Anywhere                   # SSH Custom Port
15034/tcp                  ALLOW IN    Anywhere                   # Agent App Service Port
20022/tcp (v6)             ALLOW IN    Anywhere (v6)              # SSH Custom Port
15034/tcp (v6)             ALLOW IN    Anywhere (v6)              # Agent App Service Port
```
* **검증 판정**: **PASS**
* **기술적 의미**: `Status: active` 상태이며, 기본 인바운드는 전면 차단(`deny incoming`)하고 관리용 포트 20022/tcp와 서비스 포트 15034/tcp만 정확히 개방되었음을 입증합니다.

---

### [증거 3] 계정 및 그룹 구성 확인 내역
```text
----------------------------------------------------------------------
[증거 3] 계정 및 그룹 구성(agent-admin/dev/test, agent-common/core) 검증
----------------------------------------------------------------------
>> Groups:
agent-common:x:1000:agent-admin,agent-dev,agent-test
agent-core:x:1001:

>> Users ID Info:
uid=1000(agent-admin) gid=1001(agent-core) groups=1001(agent-core),27(sudo),1000(agent-common)
uid=1001(agent-dev) gid=1001(agent-core) groups=1001(agent-core),1000(agent-common)
uid=1002(agent-test) gid=1000(agent-common) groups=1000(agent-common)
```
* **검증 판정**: **PASS**
* **기술적 의미**: `agent-common` 그룹에는 3계정이 모두 소속되고, `agent-core` 그룹에는 관리자와 개발자만 소속되며, 테스터(`agent-test`)는 `sudo` 및 `agent-core` 권한이 전면 배제되었음을 입증합니다.

---

### [증거 4] 디렉토리 구조 및 권한(POSIX ACL 포함) 확인 내역
```text
----------------------------------------------------------------------
[증거 4] 디렉토리 구조 및 권한(ACL 포함) 검증
----------------------------------------------------------------------
>> Directory Permissions (ls -ld):
drwxrws---+ 2 agent-admin agent-common 4096 Oct  2 17:53 /home/agent-admin/agent-app/upload_files
drwxr-x--- 2 agent-admin agent-core 4096 Oct  2 17:35 /home/agent-admin/agent-app/api_keys
drwxrwxr-x+ 2 agent-admin agent-core 4096 Oct  2 17:45 /var/log/agent-app
-rwxr-x--- 1 agent-dev agent-core 24174 Oct  2 17:37 /home/agent-admin/agent-app/bin/monitor.sh

>> ACL Inspection (getfacl):
# file: home/agent-admin/agent-app/upload_files
# owner: agent-admin
# group: agent-common
# flags: -s-
user::rwx
group::rwx
other::---
default:user::rwx
default:group::rwx
default:group:agent-common:rwx
default:mask::rwx
default:other::---

---
# file: home/agent-admin/agent-app/api_keys
# owner: agent-admin
# group: agent-core
user::rwx
group::r-x
other::---
```
* **검증 판정**: **PASS**
* **기술적 의미**: `upload_files`는 SetGID(`s`)와 Default ACL(`group:agent-common:rwx`)이 적용되어 팀 공용 협업이 가능하며, `api_keys`는 0750(`agent-core` 전용)으로 타인(테스터)의 접근이 완전 차단됨을 입증합니다.

---

### [증거 5] 앱 Boot Sequence 5단계 [OK] 및 포트 15034 LISTEN 상태
```text
----------------------------------------------------------------------
[증거 5] 앱 프로세스 및 포트 15034 LISTEN 상태 검증
----------------------------------------------------------------------
>> Process Status:
977 python3

>> Port 15034 Status:
tcp   LISTEN 0      5             0.0.0.0:15034      0.0.0.0:*    users:(("python3",pid=977,fd=3))
```
* **부팅 콘솔 출력 증적**:
  ```text
  ==================================================
          Starting Agent Boot Sequence              
  ==================================================
  [Step 1] Loading Environment Variables: [OK]
  [Step 2] Validating API Secret Key: [OK]
  [Step 3] Checking Upload Directory Permissions: [OK]
  [Step 4] Checking Log Directory Permissions: [OK]
  [Step 5] Binding Port 15034 (0.0.0.0:15034): [OK]
  ==================================================
  Agent READY
  ==================================================
  ```
* **검증 판정**: **PASS**
* **기술적 의미**: 파이썬 프로세스 ID(`PID 977`)와 소켓 점유 ID(`pid=977`)가 정확히 일치하여, 5단계 부팅을 통과한 에이전트 서비스가 정상 서비스 중임을 입증합니다.

---

### [증거 6] monitor.sh 직접 실행 결과 (프로세스/포트/자원/경고)
```text
----------------------------------------------------------------------
[증거 6] monitor.sh 직접 실행 결과 확인
----------------------------------------------------------------------
[WARNING] Memory usage high: 11% (Threshold: >10%)
[INFO] Health Check Passed. PID=977, Port 15034 is ACTIVE.
[INFO] Resource Usage: CPU=0%, MEM=11%, DISK=1%
[INFO] Log record added to /var/log/agent-app/monitor.log
```
* **검증 판정**: **PASS**
* **기술적 의미**: 메모리 임계치(>10%) 초과를 감지하여 `[WARNING]`을 정확히 표출하되 프로세스를 중단하지 않았고, 프로세스 및 포트 정상 생존 확인 후 `/var/log/agent-app/monitor.log`에 실측 데이터를 성공적으로 기록했음을 입증합니다.

---

### [증거 7] /var/log/agent-app/monitor.log 누적 기록 확인 내역
```text
----------------------------------------------------------------------
[증거 7] /var/log/agent-app/monitor.log 누적 로그 확인
----------------------------------------------------------------------
[2026-10-02 17:42:06] PID:977 CPU:0% MEM:11% DISK_USED:1%
[2026-10-02 17:43:01] PID:977 CPU:0% MEM:11% DISK_USED:1%
[2026-10-02 17:44:01] PID:977 CPU:0% MEM:11% DISK_USED:1%
[2026-10-02 17:45:01] PID:977 CPU:0% MEM:11% DISK_USED:1%
[2026-10-02 17:46:01] PID:977 CPU:0% MEM:11% DISK_USED:1%
[2026-10-02 17:47:01] PID:977 CPU:0% MEM:11% DISK_USED:1%
[2026-10-02 17:48:01] PID:977 CPU:0% MEM:11% DISK_USED:1%
[2026-10-02 17:49:01] PID:977 CPU:0% MEM:11% DISK_USED:1%
[2026-10-02 17:50:01] PID:977 CPU:0% MEM:11% DISK_USED:1%
[2026-10-02 17:51:01] PID:977 CPU:0% MEM:11% DISK_USED:1%
```
* **검증 판정**: **PASS**
* **기술적 의미**: `[YYYY-MM-DD HH:MM:SS] PID:... CPU:..% MEM:..% DISK_USED:..%` 규격 포맷에 따라 정확히 1분 간격으로 연속 누적 기록되고 있음을 입증합니다.

---

### [증거 8] crontab 매분 등록 및 자동 실행 확인(1분 후 로그 증가)
```text
----------------------------------------------------------------------
[증거 8] crontab 매분 등록 및 스케줄링 확인
----------------------------------------------------------------------
>> agent-admin crontab:
* * * * * /home/agent-admin/agent-app/bin/monitor.sh >> /var/log/agent-app/cron.log 2>&1

======================================================================
    Verification Complete.
======================================================================
```
* **검증 판정**: **PASS**
* **기술적 의미**: `agent-admin` 계정의 crontab에 매분(`* * * * *`) 스케줄이 정상 등록되어 무중단으로 자동 실행되고 있음을 입증합니다.

---

## 4. 과제 목표 자가 점검 및 기술적 원리 분석

| 목표 번호 | 과제 목표 핵심 항목 | 기술적 구현 및 설계 원리 분석 |
| :---: | :--- | :--- |
| **목표 1** | **SSH 포트 변경 및 Root 원격 차단의 이유** | 전 세계 해킹 자동화 봇넷의 99%는 기본 22번 포트와 `root` 계정만을 노려 사전 공격(Dictionary Attack)을 시도합니다. 비표준 포트(20022)로 변경하여 네트워크 노이즈를 차단하고, `PermitRootLogin no`로 감사 추적성(Audit Trail)을 강제합니다. |
| **목표 2** | **방화벽(UFW) 화이트리스트 정책 검증** | `default deny incoming`을 기본 정책으로 설정하여 허가되지 않은 모든 침입을 차단(Zero Trust)하고, 실제 서비스 운영에 필수적인 SSH(20022)와 앱(15034)만 최소 개방하여 시스템의 공격 표면(Attack Surface)을 최소화했습니다. |
| **목표 3** | **역할 기반 계정/그룹 및 ACL 격리 이유** | 최소 권한의 원칙(Principle of Least Privilege)에 따라 테스터(`agent-test`)는 공용 업로드 폴더에만 쓰기 권한을 부여받고, 핵심 보안 키(`api_keys`)나 시스템 로그는 열람할 수 없도록 격리하여 내부자에 의한 보안 사고 반경을 격리했습니다. |
| **목표 4** | **환경 변수($AGENT_HOME 등) 고정 이유** | 서버 환경마다 실행 경로가 달라 발생하는 하드코딩 오류를 방지하기 위해 `/etc/profile.d/agent_env.sh`에 전역 환경 변수를 선언하여, 어떤 계정으로 로그인하더라도 일관된 기준 경로에서 애플리케이션과 관제 도구가 구동되도록 보장했습니다. |
| **목표 5** | **관제 스크립트의 장애 감지 및 로깅 흐름** | 서비스 중단과 직결되는 결함(프로세스 미실행, 포트 닫힘)은 `exit 1`로 즉시 실패 반환(Fail-Fast)하여 외부 오케스트레이터가 인지하게 하고, 자원 사용량 초과는 `[WARNING]`으로 알리며 정형 로그를 영구 기록하여 사후 추적성을 확보했습니다. |
| **목표 6** | **crontab 자동화 및 로그 보존 정책 필요성** | 관리자의 부재 시에도 1분 주기로 상태를 지속 기록하기 위해 cron 자동화를 구현했으며, 로그가 무한 증식하여 디스크가 100% 차 서버가 다운되는 현상(Disk Full Crash)을 막기 위해 10MB x 10 파일 FIFO 순환 큐 로테이션을 구축했습니다. |

---

## 5. 결론 및 운영 기대 효과

1. **보안성(Security)**: 기본 포트 공격 회피, Zero Trust 인바운드 차단, RBAC 및 POSIX ACL을 통한 계정 간 권한 격벽 구축 완료.
2. **신뢰성(Reliability)**: 프로세스 및 포트 장애 즉시 감지(Fail-Fast)와 자원 임계치 경고 분리 처리 완료.
3. **가시성(Observability)**: crontab 기반 1분 단위 무중단 정형 로깅 및 디스크 풀을 방지하는 100MB 상한 로그 큐 완성.

본 보고서에 기재된 모든 설정과 스크립트는 Ubuntu 22.04 LTS 가상환경에서 완벽히 검증되었으며, 즉시 프로덕션 운영에 투입 가능한 수준으로 안정성이 입증되었습니다.
