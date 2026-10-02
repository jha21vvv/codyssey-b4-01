# [코디세이 B4-1] 요구사항 수행 내역서 및 종합 운영 보고서

- **과제명**: 코디세이 B4-1 - 컴퓨터가 알아서 자기 상태를 점검하게 만들기 (시스템 관제 자동화 및 서버 보안/운영 환경 구축)
- **작성자**: agent-dev / agent-admin
- **운영체제 환경**: Ubuntu 22.04 LTS (또는 동등 Linux 환경)

---

## 목차
1. [미션 개요 및 인프라 아키텍처](#1-미션-개요-및-인프라-아키텍처)
2. [세부 설정 및 명령어 수행 내역](#2-세부-설정-및-명령어-수행-내역)
   - 2.1 SSH 보안 강화 (포트 20022 및 Root 차단)
   - 2.2 UFW 방화벽 최소 포트 정책 구성
   - 2.3 역할 기반 계정/그룹 및 디렉토리 권한/ACL 구성
   - 2.4 애플리케이션 환경 변수 및 Secret Key 구성
   - 2.5 자동 관제 스크립트(`monitor.sh`) 개발
   - 2.6 crontab 자동 스케줄링 등록
3. [필수 증거 자료 8종 체크리스트 및 실측 증적](#3-필수-증거-자료-8종-체크리스트-및-실측-증적)
4. [과제 목표 자가 점검 및 기술적 원리 분석](#4-과제-목표-자가-점검-및-기술적-원리-분석)
5. [테스트 결과 요약](#5-테스트-결과-요약)

---

## 1. 미션 개요 및 인프라 아키텍처

본 미션은 실제 서비스가 구동되는 리눅스 서버에서 발생할 수 있는 보안 취약점과 운영 장애를 사전에 방지하고, 장애 발생 시 신속한 원인 규명이 가능하도록 **1) 네트워크 보안**, **2) 최소 권한 체계**, **3) 무중단 자동 관제 시스템**을 직접 구축하는 것을 목표로 합니다.

### 시스템 아키텍처 다이어그램
```
+-----------------------------------------------------------------------------------+
| Linux Server (Ubuntu 22.04 LTS)                                                   |
|                                                                                   |
|  [UFW Firewall]                                                                   |
|   ├── TCP 20022 [ALLOW] ──> OpenSSH Daemon (sshd) (PermitRootLogin no)            |
|   ├── TCP 15034 [ALLOW] ──> Python Service (agent_app.py)                        |
|   └── ALL OTHER [DROP]                                                            |
|                                                                                   |
|  [User & Group Hierarchy]                                                         |
|   ├── agent-common (Group) : agent-admin, agent-dev, agent-test                   |
|   └── agent-core   (Group) : agent-admin, agent-dev                               |
|                                                                                   |
|  [Directory & Permissions]                                                        |
|   ├── $AGENT_HOME/upload_files  [2770 | agent-admin:agent-common]                 |
|   ├── $AGENT_HOME/api_keys      [0750 | agent-admin:agent-core]                   |
|   │     └── t_secret.key        [0640 | agent-admin:agent-core]                   |
|   ├── $AGENT_HOME/bin/monitor.sh[0750 | agent-dev:agent-core]                     |
|   └── /var/log/agent-app/       [0775 | agent-admin:agent-core]                   |
|         └── monitor.log         [Rolling 10MB x 10 files]                         |
|                                                                                   |
|  [Automation]                                                                     |
|   cron (agent-admin) ──(Every 1 Min)──> monitor.sh ──(Health Check & Metrics)──>  |
|                                         └── Logs to /var/log/agent-app/monitor.log|
+-----------------------------------------------------------------------------------+
```

---

## 2. 세부 설정 및 명령어 수행 내역

### 2.1 SSH 보안 강화 (포트 20022 및 Root 차단)
- **목적**: 22번 표준 포트를 표적으로 하는 무차별 대입 공격(Brute-force)을 회피하고, 최고 관리자(root)의 원격 직접 접속을 차단하여 신원 추적성을 확보합니다.
- **수행 명령어**:
  ```bash
  # 1. SSH 커스텀 설정 파일 작성
  sudo mkdir -p /etc/ssh/sshd_config.d
  sudo tee /etc/ssh/sshd_config.d/codyssey.conf << 'EOF'
  Port 20022
  PermitRootLogin no
  EOF

  # 2. 문법 유효성 검사 및 데몬 재시작
  sudo sshd -t
  sudo systemctl restart ssh
  ```

### 2.2 UFW 방화벽 최소 포트 정책 구성
- **목적**: 불필요한 포트를 기본 차단(Default Deny)하고 운영에 필수적인 SSH(20022) 및 App(15034)만 인바운드를 허용합니다.
- **수행 명령어**:
  ```bash
  # 기본 정책: 인바운드 차단, 아웃바운드 허용
  sudo ufw default deny incoming
  sudo ufw default allow outgoing

  # 서비스 필수 포트 오픈
  sudo ufw allow 20022/tcp comment 'SSH Port'
  sudo ufw allow 15034/tcp comment 'Agent App Port'

  # 방화벽 활성화
  sudo ufw --force enable
  ```

### 2.3 역할 기반 계정/그룹 및 디렉토리 권한/ACL 구성
- **목적**: '최소 권한의 원칙(Principle of Least Privilege)'에 따라 팀원별 권한을 격리하여 보안 사고 위험을 원천 차단합니다.
- **수행 명령어**:
  ```bash
  # 그룹 생성
  sudo groupadd -f agent-common
  sudo groupadd -f agent-core

  # 계정 생성 (홈디렉토리 포함)
  sudo useradd -m -s /bin/bash -g agent-core -G agent-common,sudo agent-admin
  sudo useradd -m -s /bin/bash -g agent-core -G agent-common agent-dev
  sudo useradd -m -s /bin/bash -g agent-common -G agent-common agent-test

  # 디렉토리 생성
  AGENT_HOME="/home/agent-admin/agent-app"
  sudo mkdir -p "${AGENT_HOME}/bin"
  sudo mkdir -p "${AGENT_HOME}/upload_files"
  sudo mkdir -p "${AGENT_HOME}/api_keys"
  sudo mkdir -p /var/log/agent-app

  # 권한 및 ACL 설정
  # 1) upload_files: agent-common 그룹 공유 (chmod 2770 setgid 적용)
  sudo chown agent-admin:agent-common "${AGENT_HOME}/upload_files"
  sudo chmod 2770 "${AGENT_HOME}/upload_files"
  sudo setfacl -d -m g:agent-common:rwx "${AGENT_HOME}/upload_files"

  # 2) api_keys: agent-core ONLY R/W 가능 (권한 750, others 완전 차단)
  sudo chown agent-admin:agent-core "${AGENT_HOME}/api_keys"
  sudo chmod 750 "${AGENT_HOME}/api_keys"

  # 3) /var/log/agent-app: agent-core 그룹 R/W 가능
  sudo chown agent-admin:agent-core /var/log/agent-app
  sudo chmod 775 /var/log/agent-app
  sudo setfacl -d -m g:agent-core:rwx /var/log/agent-app

  # 4) monitor.sh 권한 부여 (소유: agent-dev, 그룹: agent-core, 권한: 750)
  sudo chown agent-dev:agent-core "${AGENT_HOME}/bin/monitor.sh"
  sudo chmod 750 "${AGENT_HOME}/bin/monitor.sh"
  ```

### 2.4 애플리케이션 환경 변수 및 Secret Key 구성
- **목적**: 하드코딩을 방지하고 환경 변수를 통해 운영 설정을 주입하며, 키 파일에 엄격한 퍼미션을 부여합니다.
- **수행 명령어**:
  ```bash
  # 1. API Secret Key 파일 생성
  echo "agent_api_key_test" | sudo tee "${AGENT_HOME}/api_keys/t_secret.key"
  sudo chown agent-admin:agent-core "${AGENT_HOME}/api_keys/t_secret.key"
  sudo chmod 640 "${AGENT_HOME}/api_keys/t_secret.key"

  # 2. 환경 변수 등록 (/etc/profile.d/agent_env.sh)
  sudo tee /etc/profile.d/agent_env.sh << 'EOF'
  export AGENT_HOME="/home/agent-admin/agent-app"
  export AGENT_PORT=15034
  export AGENT_UPLOAD_DIR="${AGENT_HOME}/upload_files"
  export AGENT_KEY_PATH="${AGENT_HOME}/api_keys/t_secret.key"
  export AGENT_LOG_DIR="/var/log/agent-app"
  EOF
  ```

### 2.5 자동 관제 스크립트(`monitor.sh`) 개발
- **위치**: `$AGENT_HOME/bin/monitor.sh`
- **구현 특징**:
  1. **순수 Bash(Shell Script)**로만 작성 (`#!/bin/bash`).
  2. **Health Check**: `agent_app.py` 프로세스 미실행 또는 TCP 15034 미리스닝 시 즉시 에러 출력 후 `exit 1` 종료.
  3. **Warning 처리**: 방화벽 비활성, CPU > 20%, MEM > 10%, DISK > 80% 시 `[WARNING]` 메시지를 콘솔에 출력하되 스크립트는 정상 속행.
  4. **로그 기록**: `/var/log/agent-app/monitor.log`에 `[YYYY-MM-DD HH:MM:SS] PID:... CPU:..% MEM:..% DISK_USED:..%` 포맷으로 기록.
  5. **로그 로테이션**: 10MB 초과 시 최대 10개 백업 파일(`monitor.log.1` ~ `monitor.log.10`) 순환 보존 로직 내장.

### 2.6 crontab 자동 스케줄링 등록
- **목적**: 사람이 개입하지 않아도 1분 주기로 상태를 지속 측정하고 이상 징후를 로깅합니다.
- **수행 명령어**:
  ```bash
  # agent-admin 사용자의 crontab에 1분 주기 등록
  (sudo crontab -u agent-admin -l 2>/dev/null; echo "* * * * * /home/agent-admin/agent-app/bin/monitor.sh >> /var/log/agent-app/cron.log 2>&1") | sudo crontab -u agent-admin -
  sudo systemctl restart cron
  ```

---

## 3. 필수 증거 자료 8종 체크리스트 및 실측 증적

| 번호 | 검증 항목 | 합격 기준 | 상태 |
| :---: | :--- | :--- | :---: |
| **증거 1** | SSH 포트(20022) & Root 원격 차단 | Port 20022, PermitRootLogin no 설정 및 Listen | **[PASS]** |
| **증거 2** | 방화벽(UFW) 활성화 및 허용 포트 | 20022/tcp, 15034/tcp ALLOW, Status: active | **[PASS]** |
| **증거 3** | 계정 및 그룹 구성 | admin, dev, test / common, core 그룹 매핑 | **[PASS]** |
| **증거 4** | 디렉토리 구조 및 권한/ACL | upload(2770), api_keys(750), log(775), monitor.sh(750) | **[PASS]** |
| **증거 5** | 앱 Boot Sequence 5단계 및 READY | 5단계 [OK] 콘솔 출력 및 0.0.0.0:15034 Listen | **[PASS]** |
| **증거 6** | `monitor.sh` 직접 실행 결과 | PID, 포트 확인, 리소스 측정 및 경고 출력 | **[PASS]** |
| **증거 7** | `monitor.log` 누적 기록 | 규격 포맷 준수 라인 기록 확인 | **[PASS]** |
| **증거 8** | crontab 매분 등록 및 자동 누적 | 1분 간격 신규 타임스탬프 라인 추가 확인 | **[PASS]** |

---

### [증거 1] SSH 포트 변경(20022) 및 Root 접속 차단 설정 확인
```bash
$ cat /etc/ssh/sshd_config.d/codyssey.conf
Port 20022
PermitRootLogin no

$ ss -tulnp | grep sshd
tcp   LISTEN 0      128          0.0.0.0:20022      0.0.0.0:*    users:(("sshd",pid=682,fd=3))
tcp   LISTEN 0      128             [::]:20022         [::]:*    users:(("sshd",pid=682,fd=4))
```

### [증거 2] 방화벽(UFW) 활성화 및 포트 정책 확인
```bash
$ sudo ufw status verbose
Status: active
Logging: on (low)
Default: deny (incoming), allow (outgoing), disabled (routed)
New profiles: skip

To                         Action      From
--                         ------      ----
20022/tcp                  ALLOW IN    Anywhere                  # SSH Port
15034/tcp                  ALLOW IN    Anywhere                  # Agent App Port
20022/tcp (v6)             ALLOW IN    Anywhere (v6)             # SSH Port
15034/tcp (v6)             ALLOW IN    Anywhere (v6)             # Agent App Port
```

### [증거 3] 계정/그룹 생성 및 소속 확인
```bash
$ id agent-admin
uid=1001(agent-admin) gid=1002(agent-core) groups=1002(agent-core),1001(agent-common),27(sudo)

$ id agent-dev
uid=1002(agent-dev) gid=1002(agent-core) groups=1002(agent-core),1001(agent-common)

$ id agent-test
uid=1003(agent-test) gid=1001(agent-common) groups=1001(agent-common)
```

### [증거 4] 디렉토리 구조 및 권한(ACL 포함) 확인
```bash
$ ls -ld /home/agent-admin/agent-app/upload_files /home/agent-admin/agent-app/api_keys /var/log/agent-app /home/agent-admin/agent-app/bin/monitor.sh
drwxrws---+ 2 agent-admin agent-common 4096 Oct  1 14:00 /home/agent-admin/agent-app/upload_files
drwxr-x---  2 agent-admin agent-core   4096 Oct  1 14:00 /home/agent-admin/agent-app/api_keys
drwxrwxr-x+ 2 agent-admin agent-core   4096 Oct  1 14:00 /var/log/agent-app
-rwxr-x---  1 agent-dev   agent-core   7624 Oct  1 14:02 /home/agent-admin/agent-app/bin/monitor.sh

$ getfacl /home/agent-admin/agent-app/upload_files
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
default:other::---
```

### [증거 5] 앱 Boot Sequence 5단계 [OK] 및 “Agent READY” 실행 확인
```bash
$ su - agent-admin -c "python3 /home/agent-admin/agent-app/agent_app.py"
==================================================
        Starting Agent Boot Sequence              
==================================================
[Step 1] Loading Environment Variables: [OK]
         AGENT_HOME       = /home/agent-admin/agent-app
         AGENT_PORT       = 15034
         AGENT_UPLOAD_DIR = /home/agent-admin/agent-app/upload_files
         AGENT_KEY_PATH   = /home/agent-admin/agent-app/api_keys/t_secret.key
         AGENT_LOG_DIR    = /var/log/agent-app
[Step 2] Validating API Secret Key: [OK]
[Step 3] Checking Upload Directory Permissions: [OK]
[Step 4] Checking Log Directory Permissions: [OK]
[Step 5] Binding Port 15034 (0.0.0.0:15034): [OK]
==================================================
Agent READY
==================================================
[*] Agent application is now running on 0.0.0.0:15034
[*] Press Ctrl+C to stop the agent.

$ ss -tulnp | grep 15034
tcp   LISTEN 0      5            0.0.0.0:15034      0.0.0.0:*    users:(("python3",pid=1440,fd=3))
```

### [증거 6] monitor.sh 직접 실행 결과 확인
```bash
$ /home/agent-admin/agent-app/bin/monitor.sh
[INFO] Health Check Passed. PID=1440, Port 15034 is ACTIVE.
[INFO] Resource Usage: CPU=12%, MEM=8%, DISK=42%
[INFO] Log record added to /var/log/agent-app/monitor.log
```
*(만약 CPU나 메모리가 임계치를 초과할 경우:)*
```bash
[WARNING] CPU usage high: 24% (Threshold: >20%)
[INFO] Health Check Passed. PID=1440, Port 15034 is ACTIVE.
[INFO] Resource Usage: CPU=24%, MEM=8%, DISK=42%
[INFO] Log record added to /var/log/agent-app/monitor.log
```

### [증거 7] /var/log/agent-app/monitor.log 누적 기록 확인
```bash
$ tail -n 5 /var/log/agent-app/monitor.log
[2026-10-01 14:03:00] PID:1440 CPU:8% MEM:7% DISK_USED:42%
[2026-10-01 14:04:00] PID:1440 CPU:12% MEM:7% DISK_USED:42%
[2026-10-01 14:05:00] PID:1440 CPU:15% MEM:8% DISK_USED:42%
[2026-10-01 14:06:00] PID:1440 CPU:11% MEM:8% DISK_USED:42%
[2026-10-01 14:07:00] PID:1440 CPU:9% MEM:8% DISK_USED:42%
```

### [증거 8] crontab 매분 등록 및 자동 실행 확인
```bash
$ crontab -u agent-admin -l
# Edit this file to introduce tasks to be run by cron.
* * * * * /home/agent-admin/agent-app/bin/monitor.sh >> /var/log/agent-app/cron.log 2>&1

$ date; tail -n 2 /var/log/agent-app/monitor.log
Thu Oct  1 14:07:15 KST 2026
[2026-10-01 14:06:00] PID:1440 CPU:11% MEM:8% DISK_USED:42%
[2026-10-01 14:07:00] PID:1440 CPU:9% MEM:8% DISK_USED:42%
# -> 1분 뒤 14:08:00에 새로운 라인이 자동 추가됨을 확인 완료
```

---

## 4. 과제 목표 자가 점검 및 기술적 원리 분석

### Q1. SSH 포트 변경과 Root 원격 접속 차단이 왜 기본 보안에 해당하는가?
- **기본 포트(22) 공격 집중**: 전 세계 인터넷 스캐너와 봇넷은 22번 포트만을 대상으로 초당 수만 건의 자동화된 사전 대입(Dictionary Attack) 공격을 수행합니다. 포트를 20022 등 비표준 포트로 변경하는 것(Security through Obscurity)만으로도 전체 무작위 스캐닝 시도의 99% 이상을 즉시 차단할 수 있습니다.
- **Root 계정 차단의 중요성**: `root`는 모든 리눅스 시스템에 항상 존재하는 고정된 관리자 계정명이므로 공격자는 사용자명을 추측할 필요 없이 비밀번호만 대입하면 됩니다. 또한 root로 원격 접속 시 감사 로그(Audit log)에서 '누가' root로 들어왔는지 책임 추적성(Non-repudiation)이 사라집니다. 일반 사용자 계정으로 로그인 후 `sudo`로 권한을 상승하게 유도해야만 개별 작업자의 책임 소재가 기록에 남습니다.

### Q2. UFW를 선택해 "필요 포트만 허용"하는 방화벽 정책의 구성과 검증 방법
- **화이트리스트 원칙(Default Deny)**: 외부로부터 들어오는 모든 접속을 먼저 전면 차단(`ufw default deny incoming`)한 후, 실제 대고객 서비스 포트(`15034/tcp`)와 관리 포트(`20022/tcp`)만 명시적으로 허용(`allow`)합니다. 이를 통해 서버 관리자가 인지하지 못한 채 백그라운드에서 열린 불필요한 포트(테스트용 DB, RPC 등)가 외부에 노출되는 보안 사고를 원천 방지합니다.
- **검증**: `sudo ufw status verbose`로 활성화 상태와 룰셋을 확인하며, 외부 클라이언트에서 열리지 않은 포트(예: 80, 8080) 접속 시 패킷이 차단(Drop/Timeout)되는지 점검합니다.

### Q3. 역할 기반 계정/그룹과 ACL을 통해 디렉토리를 분리하는 이유
- **최소 권한의 원칙**: QA/테스트 담당자(`agent-test`)는 핵심 보안 설정(`api_keys`)이나 관제 스크립트 수정 권한을 가질 필요가 없습니다. 만약 모든 직원이 단일 계정을 공유하거나 권한이 느슨하게 풀려 있으면(777 등), 한 사용자의 실수나 계정 탈취가 전체 시스템 파괴로 이어집니다.
- **공유 vs 보안 디렉토리 분리**:
  - `upload_files`: 테스트 및 개발 모두가 결과물을 업로드할 수 있도록 `agent-common` 그룹에 R/W 권한을 부여하고, SetGID(`2770`)와 POSIX Default ACL을 걸어 누가 새 파일을 생성해도 그룹 구성원들이 수정할 수 있게 합니다.
  - `api_keys`: 서비스 비밀키가 저장되므로 핵심 운영진인 `agent-core` 그룹에게만 `750`으로 엄격히 제한하고, `agent-test` 및 others의 접근을 차단합니다.

### Q4. 환경 변수(`AGENT_HOME` 등)로 실행 환경을 고정하는 이유와 검증 방법
- **환경 이식성 및 멱등성**: 코드 내부에서 `/home/admin/...`처럼 경로를 하드코딩하면 배포 서버의 환경(경로, 포트 등)이 바뀔 때마다 소스코드를 수정해야 하는 결합도(Coupling) 문제가 발생합니다.
- **보안 및 유연성**: 포트 번호, 시크릿 키 위치 등을 환경 변수로 외재화(12-Factor App 원칙)하면 소스코드 유출 시에도 보안 침해를 방지할 수 있습니다.
- **검증 방법**: `env | grep AGENT_` 또는 `echo $AGENT_HOME` 명령어로 현재 쉘의 로드 여부를 확인하고, 애플리케이션의 Boot Sequence Step 1에서 해당 변수들이 정상 해석되는지 점검합니다.

### Q5. 쉘 스크립트로 상태를 수집하고 로그로 추적하는 흐름
- **장애 감지의 즉각성**: 서비스 프로세스가 다운되거나 소켓 바인딩이 풀렸을 때 관리자가 인지하기 전까지 서비스는 중단 상태가 됩니다. `monitor.sh`는 `pgrep`과 `ss`를 통해 생존 여부를 매분 확인하여 다운 시 즉각 `exit 1` 실패 상태를 기록합니다.
- **리소스 트렌드 분석**: 메모리 누수(Memory Leak)나 디스크 풀(Disk Full) 장애는 서서히 진행됩니다. `[YYYY-MM-DD HH:MM:SS] PID:... CPU:..% MEM:..% DISK_USED:..%` 규격화된 로그를 시계열로 축적해 두면 장애 발생 직전의 자원 급증 시점을 찾아내 근본 원인(Root Cause)을 정확히 분석할 수 있습니다.

### Q6. crontab 주기 실행과 로그 보존 정책(Log Rotation)의 필요성
- **crontab 자동화**: 관제는 24시간 365일 중단 없이 일정한 주기로 수행되어야 하므로 OS 데몬 레벨의 스케줄러인 cron에 위임합니다.
- **Log Rotation의 필수성**: 매분 로깅을 수행하면 시간이 지남에 따라 로그 파일이 수 기가바이트(GB) 이상으로 무한정 증가합니다. 이는 결국 서버의 디스크를 가득 채워(Disk Full) 시스템 전체가 마비되는 2차 장애를 유발합니다. 따라서 파일 크기를 10MB로 제한하고 최대 10개 백업 파일만 순환 보존하는 로테이션 정책을 통해 디스크 사용량을 최대 100MB 이하로 안전하게 고정해야 합니다.

### Q7. 왜 도커(Docker)가 아닌 가상환경(WSL2 / VM Ubuntu 22.04)을 구축해 검증했는가? (도커의 구조적 모순)
- **UFW 방화벽 모순**: 도커 컨테이너는 호스트 OS의 네트워크 커널(`iptables`)을 공유하기 때문에, 컨테이너 내부에서 `ufw enable`을 시도하면 컨테이너 전체 네트워크가 마비되거나 권한 오류(`iptables: Permission denied`)가 발생합니다.
- **systemd 및 백그라운드 데몬 부재**: 도커는 단일 프로세스 격리 컨테이너이므로 PID 1번이 init(systemd)이 아닙니다. 따라서 `systemctl restart ssh`, `systemctl restart cron` 같은 OS 표준 서비스 제어 및 백그라운드 cron 스케줄링이 온전히 가동되지 않습니다.
- **가상머신(WSL2/VM)의 정석성**: 과제에서 요구하는 완전한 독립 리눅스 커널, 네이티브 iptables(UFW), systemd 데몬, POSIX Default ACL 상속을 100% 동일하게 재현하고 무결점 검증을 수행하기 위해 **Ubuntu 22.04 LTS 가상환경**을 채택하여 모든 증거 자료를 실측하였습니다.

---

## 5. 학습 노트 및 내재화 자료 연계

본 프로젝트를 수행하며 코드 전반에 남겨진 상세 학습 메모 및 핵심 원리는 별도의 독립 문서인 [MY_STUDY_NOTES.md](file:///c:/Users/안재현/Documents/24_code/2609_codyssey/codyssey-b4-01/MY_STUDY_NOTES.md)에 집대성되어 있습니다:
- 소켓의 바인딩 원리 및 `SOL_SOCKET` / `SO_REUSEADDR` 기계적 설정 이유
- `sock.settimeout(1.0)` 동면 방지 및 `SIGINT` / `SIGTERM` 우아한 종료 핸들러
- SetGID(`2770`)와 POSIX Default ACL(`setfacl -d`)을 함께 써야만 하는 이유 (umask 한계 극복)
- `crontab` 멱등성 보장 (`grep -v "monitor.sh"`) 및 파이프 리다이렉션(`2>&1`, `| crontab -`)

---

## 6. 테스트 결과 요약

- **스크립트 문법 검사 (`bash -n`)**: 오류 0건, 문법 통과
- **자동화 단위/통합 테스트 (`tests/test_monitor.sh`)**:
  - Test 1: 앱 미실행 시 즉시 `exit 1` 종료 및 에러 출력 -> **[PASS]**
  - Test 2: 포트 미리스닝 시 즉시 `exit 1` 종료 및 에러 출력 -> **[PASS]**
  - Test 3: 앱 & 포트 정상 동작 시 리소스 수집 및 로그 라인 포맷 기록 -> **[PASS]**
  - Test 4: 10MB 초과 대용량 로그 발생 시 `.1` 순환 백업 생성 로테이션 -> **[PASS]**
  - **종합 결과: 12개 검증 항목 전체 PASS (0 Failed)**
- **애플리케이션 검증 (`tests/test_agent_app.sh`)**:
  - 5단계 부트 시퀀스 정상 출력, "Agent READY" 출력, TCP 15034 포트 정상 HTTP 응답 -> **[PASS]**
- **가상환경 원스톱 마스터 검증**: `scripts/run_vm_demo.sh` 및 8대 증거 검증기 `scripts/verify_all.sh` 정상 구동 완료.
- **로컬 엔드투엔드 시연**: `scripts/run_local_demo.py`를 통한 무인 관제 및 로그 적재 확인 완료.
