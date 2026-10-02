# Codyssey B4-1: 시스템 관제 자동화 및 서버 운영 환경 구축

> **"컴퓨터가 알아서 자기 상태를 점검하게 만들기"**  
> 리눅스 서버 보안 강화(SSH 커스텀 포트, UFW 방화벽), 다중 계정 권한 격리(POSIX ACL), 애플리케이션 5단계 부팅 검증, 그리고 순수 Bash 시스템 관제 스크립트(`monitor.sh`)와 crontab 무중단 로깅 자동화 프로젝트입니다.

---

## 🏛️ 시스템 아키텍처 인포그래픽 (Visual Architecture)

### 1. 전체 시스템 및 네트워크 보안 인프라 아키텍처
인터넷 외부 위협을 방화벽과 SSH 보안으로 원천 봉쇄하고 내부 서비스를 안전하게 운영 및 관제하는 전체 시스템 조감도입니다.

![시스템 전체 아키텍처](./docs/images/architecture_system_overview.png)

#### 🔍 핵심 설명 포인트:
- **방화벽 경계선 (UFW Default Deny)**: 비인가 포트는 전면 DROP 차단하며, 오직 관리용 `TCP 20022`와 서비스용 `TCP 15034`만 인바운드를 허용합니다.
- **SSH 침입 방어**: 22번 포트 자동 공격을 무력화하고 `PermitRootLogin no`로 최고 관리자의 원격 로그인을 차단하여 감사 추적성을 확보했습니다.
- **관제 자동화**: `crontab`이 매분 순수 Bash 기반의 `monitor.sh`를 구동하여 애플리케이션 상태와 리소스를 1분 단위로 지속 감시합니다.

---

### 2. 역할 기반 접근 제어(RBAC) 및 디렉토리 권한/ACL 아키텍처
'최소 권한의 원칙(Principle of Least Privilege)'에 따라 계정, 그룹, 디렉토리를 격리한 보안 구조도입니다.

![보안 및 ACL 아키텍처](./docs/images/architecture_security_acl.png)

#### 🔍 핵심 설명 포인트:
- **그룹 격리**: 전사 공통 작업용 `agent-common`과 핵심 보안 관리용 `agent-core`로 명확히 분리했습니다.
- **접근 권한 차단**: QA 테스터(`agent-test`)는 공용 업로드 폴더(`upload_files`, 2770)에만 접근할 수 있으며, 서비스 비밀키(`api_keys/t_secret.key`, 0640)와 시스템 로그 디렉토리는 접근이 엄격히 차단됩니다.

---

### 3. monitor.sh 관제 라이프사이클 및 로그 로테이션 큐 메커니즘
장애 상황에서의 엄격한 분기 처리(Health Check vs Warning)와 디스크 풀을 방지하는 100MB 상한 보존 큐 메커니즘입니다.

![관제 라이프사이클 흐름도](./docs/images/architecture_monitor_flow.png)

#### 🔍 핵심 설명 포인트:
- **이원화된 대응 (Fatal vs Warning)**: 프로세스 다운이나 포트 닫힘은 즉각적인 서비스 중단이므로 `exit 1`로 즉시 실패 종료하며, 자원 임계치(CPU>20%, MEM>10%, DISK>80%) 초과는 `[WARNING]` 경고만 출력하고 정상 관제를 지속합니다.
- **로그 로테이션 (최대 10MB x 10개)**: 파일 크기가 10MB에 도달하면 `.10`은 영구 삭제되고 `.1`부터 `.9`까지 한 칸씩 밀려나는 큐 구조를 적용하여, 디스크 사용량이 영원히 100MB를 넘지 않도록 수학적으로 고정했습니다.

---

## 📂 프로젝트 구조

```
codyssey-b4-01/
├── bin/
│   └── monitor.sh              # [산출물 2] 시스템 관제 및 로깅 스크립트 (순수 Bash, 2단 주석, 권한: 750)
├── app/
│   └── agent_app.py            # 5단계 Boot Sequence 및 15034 포트 리슨 애플리케이션
├── scripts/
│   ├── setup_server.sh         # Ubuntu 22.04 LTS 원클릭 인프라/보안/계정/ACL/cron 자동 설정 스크립트
│   ├── verify_all.sh           # 8대 필수 증거자료 자동 검증 및 출력 도구
│   ├── run_vm_demo.sh          # 가상환경(WSL2/VM) 전용 5단계 원스톱 마스터 실습 러너
│   ├── launch_wsl_env.bat      # 윈도우에서 WSL2 우분투 가상머신 원클릭 진입 런처
│   ├── run_local_demo.py       # 윈도우 로컬 Git Bash 연동 간편 데모 러너
│   └── generate_architecture_diagrams.py # 고해상도 아키텍처 다이어그램 렌더링 파이썬 스크립트
├── docs/
│   └── images/                 # 고해상도 아키텍처 다이어그램 (PNG)
│       ├── architecture_system_overview.png
│       ├── architecture_security_acl.png
│       └── architecture_monitor_flow.png
├── tests/
│   ├── test_monitor.sh         # monitor.sh 단위/통합 테스트 스위트 (12개 항목 자동 검증)
│   └── test_agent_app.sh       # agent_app.py 부트 시퀀스 및 포트 바인딩 테스트
├── MY_STUDY_NOTES.md           # 📘 [학습 노트] 소켓, 시그널, ACL, crontab 등 내재화 메모 집대성
├── 스터디.md                   # 요구사항 1:1 매핑, 주니어 일상 비유 해설 및 면접 10초 Q&A
├── NOTEBOOKLM_GUIDE.md         # Google NotebookLM 팟캐스트(Audio Overview) 학습용 원천 텍스트
├── MISSION_PLAN.md             # 가상환경(VM/WSL2) 기반 마스터 실습 플랜
├── REPORT.md                   # [산출물 1] 요구사항 수행 내역서 (8대 필수 증거 자료 및 기술 원리 해설)
└── README.md                   # 프로젝트 사용 설명서
```

---

## 🎬 실전 평가 시연 플레이북 (3단계 라이브 데모)

> **💡 평가자 맞이용 실전 시나리오**: 평가자가 도착했을 때부터 테스트 시연, 종료까지 이 순서대로만 진행하면 완벽합니다.

### 📍 1단계: 평가자 오면 가상머신 켜고 "정상 가동 & 실시간 관제" 보여주기

터미널 창을 **2개** 나란히 띄워두고 보여줍니다:

#### [창 1] 가상머신 접속 및 백엔드 앱 가동 확인

```powershell
# 1. 윈도우 PowerShell에서 가상머신 접속
wsl -d Ubuntu-22.04 -u agent-admin
```
* **정상 화면**: `agent-admin@DESKTOP-...:~$` (최고 관리자 프롬프트 진입)
* **의미**: Ubuntu 22.04 LTS 가상환경에 보안 관리자 `agent-admin` 계정으로 정상 로그인되었습니다.

```bash
# 2. 앱 서비스 상태 점검 (가상머신 부팅 시 systemd 서비스로 자동 상시 가동)
sudo systemctl status agent-app
```
* **정상 출력 화면**:
  ```text
  ● agent-app.service - Codyssey B4-1 Python Agent Application
       Loaded: loaded (/etc/systemd/system/agent-app.service; enabled; vendor preset: enabled)
       Active: active (running) since Fri 2026-10-02 17:47:32 KST; 1min ago
     Main PID: 977 (python3)
        Tasks: 1 (limit: 4297)
       Memory: 4.2M
  ```
* **각 항목의 의미**:
  * `enabled`: 가상머신이 켜질 때마다 앱이 알아서 켜지도록 systemd 부팅 서비스에 등록되어 있음을 의미합니다.
  * `active (running)`: 현재 백엔드 앱이 죽지 않고 메모리에 정상적으로 살아 숨 쉬며 서비스 중임을 의미합니다.
  * `Main PID: 977 (python3)`: 운영체제로부터 고유 프로세스 ID(PID 977)를 부여받아 백엔드 파이썬이 실행 중임을 의미합니다.

```bash
# 3. 앱 핑 테스트 (포트 15034 정상 응답 확인)
curl -i http://localhost:15034/
```
* **정상 출력 화면**:
  ```text
  HTTP/1.1 200 OK
  Content-Type: text/plain
  Content-Length: 17
  Connection: close

  Agent Status: OK
  ```
* **각 항목의 의미**:
  * `HTTP/1.1 200 OK`: 서버가 클라이언트 요청을 에러 없이 완벽히 수신 및 처리했음을 나타내는 표준 성공 상태 코드입니다.
  * `Agent Status: OK`: 앱 내부의 5단계 부팅 자가 검증(키 파일, 업로드 폴더, 로그 폴더, 포트 15034 바인딩)을 모두 통과한 정상 상태임을 서버가 직접 증명한 메시지입니다.

---

#### [창 2] 1분마다 자동 기록되는 실시간 건강검진 로그 띄워두기

```bash
tail -f /var/log/agent-app/monitor.log
```
* **정상 출력 화면 (1분마다 1줄씩 추가됨)**:
  ```text
  [2026-10-02 17:47:15] PID:977 CPU:0% MEM:11% DISK_USED:1%
  [2026-10-02 17:48:01] PID:977 CPU:0% MEM:11% DISK_USED:1%
  [2026-10-02 17:49:01] PID:977 CPU:0% MEM:11% DISK_USED:1%
  ```
* **각 항목의 의미**:
  * `[2026-10-02 17:48:01]`: 사람의 개입 없이 `crontab`이 1분 정각마다 `monitor.sh`를 깨워 순찰을 돌았음을 입증하는 타임스탬프입니다.
  * `PID:977`: 관제 스크립트가 대상 앱(PID 977)의 생존 여부와 포트 15034 LISTEN 상태를 실시간 확인했음을 의미합니다.
  * `CPU:0% MEM:11% DISK_USED:1%`: 시스템의 핵심 3대 자원 사용량을 정상 계측하여 누적 기록한 데이터입니다.
* 🗣️ **평가자 설명 멘트**: *"crontab이 1분마다 무중단으로 `monitor.sh`를 구동하여 CPU, MEM, DISK 상태를 실시간 로깅하고 있습니다."*

---

### 📍 2단계: 상황별 요구조건 충족 시연 (4대 핵심 포인트)

#### 상황 ① [정상 관제] 관제 스크립트 수동 1회 실행
```bash
~/agent-app/bin/monitor.sh
```
* **정상 출력 화면**:
  ```text
  [WARNING] Memory usage high: 11% (Threshold: >10%)
  [INFO] Health Check Passed. PID=977, Port 15034 is ACTIVE.
  [INFO] Resource Usage: CPU=0%, MEM=11%, DISK=1%
  [INFO] Log record added to /var/log/agent-app/monitor.log
  ```
* **각 항목의 의미**:
  * `[WARNING] Memory usage high: 11% (Threshold: >10%)`: 과제 요구조건인 메모리 임계치(>10%) 초과를 스크립트가 정확히 감지했습니다. 치명적 장애가 아니므로 프로세스를 중단하지 않고 경고만 출력합니다.
  * `[INFO] Health Check Passed`: 프로세스 생존과 포트 활성화 2대 필수 조건을 모두 통과했다는 합격 판정입니다.
  * `[INFO] Log record added...`: 방금 측정한 진단 결과가 `/var/log/agent-app/monitor.log`에 정상 추가되었음을 나타냅니다.

---

#### 상황 ② [장애 대응] 앱이 다운되었을 때 관제 스크립트의 Fail-Fast 감지 (★하이라이트)
> 🗣️ **평가자 설명**: *"만약 예기치 못한 장애로 백엔드 앱이 죽었을 때 관제 스크립트가 즉시 비상 종료(Exit 1)하는지 보여드리겠습니다."*

**1. 앱 서비스 중지 (장애 주입)**:
```bash
sudo systemctl stop agent-app
```
* **의미**: 갑작스러운 서버 오류나 프로세스 충돌로 앱이 꺼진 장애 상황을 재현합니다.

**2. 관제 스크립트 실행 및 에러 감지 확인**:
```bash
~/agent-app/bin/monitor.sh
echo "종료코드: $?"
```
* **정상 출력 화면**:
  ```text
  [ERROR] Health Check Failed: Process 'agent_app.py' is NOT running!
  종료코드: 1
  ```
* **각 항목의 의미**:
  * `[ERROR] Health Check Failed...`: 닥터 스크립트가 앱의 비정상 종료를 즉각 감지하고 에러 메시지를 표준 에러(stderr)로 출력했습니다.
  * `종료코드: 1`: 일반적인 정상 종료(0)가 아니라, 외부 관제 시스템에 장애를 즉각 전파할 수 있도록 실패 코드 `1`을 반환하며 즉시 멈췄음(Fail-Fast)을 증명합니다.

**3. 앱 서비스 다시 살리기 (정상 복구)**:
```bash
sudo systemctl start agent-app
curl -i http://localhost:15034/
```
* **정상 출력 화면**: `HTTP/1.1 200 OK`, `Agent Status: OK`
* **의미**: 서비스를 다시 시작하여 앱이 정상적으로 복구되었음을 확인합니다.

---

#### 상황 ③ [보안/권한 격리] 테스터 계정의 보안 비밀키 접근 차단 (최소 권한의 원칙)
> 🗣️ **평가자 설명**: *"POSIX ACL 및 파일 권한을 통해 테스터 계정은 업로드 폴더만 쓰고, 핵심 비밀키는 열람할 수 없도록 격리했습니다."*

**1. 테스터 계정으로 전환 (비밀번호 불필요)**:
```bash
sudo su - agent-test
```
* **정상 화면**: `agent-test@DESKTOP-...:~$` (테스터 프롬프트로 변경됨)
* **의미**: 비밀번호 입력 없이 테스터 계정 환경으로 즉시 전환되었습니다.

**2. 공용 업로드 폴더 파일 생성 (성공 확인)**:
```bash
touch /home/agent-admin/agent-app/upload_files/test_file.txt
ls -l /home/agent-admin/agent-app/upload_files/test_file.txt
```
* **정상 출력 화면**:
  ```text
  -rw-rw----+ 1 agent-test agent-common 0 Oct  2 17:53 test_file.txt
  ```
* **각 항목의 의미**:
  * `agent-test`: 테스터 계정 권한으로 파일이 성공적으로 생성되었습니다.
  * `agent-common`: `upload_files` 디렉토리에 걸린 SetGID(2770) 속성 덕분에, 새 파일의 그룹 소속이 자동으로 공용 그룹(`agent-common`)으로 상속 지정되었습니다.
  * `+` 기호: POSIX Default ACL이 상속되어 팀원 누구나 해당 파일을 함께 읽고 수정할 수 있음을 나타냅니다.

**3. 보안 비밀키 접근 시도 (차단 확인!)**:
```bash
cat /home/agent-admin/agent-app/api_keys/t_secret.key
```
* **정상 출력 화면**:
  ```text
  cat: /home/agent-admin/agent-app/api_keys/t_secret.key: Permission denied
  ```
* **각 항목의 의미**:
  * `Permission denied`: `api_keys` 폴더는 소유 그룹이 `agent-core`(보안팀 전용)이고 타인(others) 권한이 `0`이므로, `agent-common` 소속인 테스터의 접근이 커널 레벨에서 원천 차단되었음을 증명합니다.

**4. 원래 관리자 계정으로 복귀**:
```bash
exit
```
* **정상 화면**: `agent-admin@DESKTOP-...:~$` (관리자 계정으로 복귀 완료)

> 💡 **Tip (계정 전환 없이 1줄로 보여주는 초간편 방법)**:
> ```bash
> # 업로드 폴더 쓰기 성공 시연
> sudo -u agent-test touch /home/agent-admin/agent-app/upload_files/tester_demo.txt
> 
> # 비밀키 열람 차단(Permission denied) 시연
> sudo -u agent-test cat /home/agent-admin/agent-app/api_keys/t_secret.key
> ```

#### 상황 ④ [8대 증거 피날레] 요구사항 종합 검증 도구 원스톱 실행
```bash
sudo /mnt/c/Users/안재현/Documents/24_code/2609_codyssey/codyssey-b4-01/scripts/verify_all.sh
```

##### 📊 [필수 참고] 8대 증거 화면 출력 내용 및 상세 의미 해설

| 번호 | 검증 증거 항목 | 터미널 핵심 출력 내용 | 실무적 의미 및 평가자 답변 멘트 |
| :---: | :--- | :--- | :--- |
| **증거 1** | **SSH 포트 및 Root 차단** | `Port 20022`<br/>`PermitRootLogin no`<br/>`0.0.0.0:20022` / `[::]:20022` | 기본 22번 포트 자동 공격 봇을 무력화하고, root의 외부 직접 접속을 차단하여 접속자의 감사 추적성을 확보했습니다. (IPv4/IPv6 듀얼 스택) |
| **증거 2** | **UFW 방화벽 규칙** | `Status: active`<br/>`Default: deny (incoming)`<br/>`20022, 15034 ALLOW IN` | 인바운드 기본 정책을 deny로 잠그고(Zero Trust), 관리용 20022번과 서비스용 15034번만 최소 개방했습니다. |
| **증거 3** | **계정 및 그룹 RBAC** | `admin (agent-core, sudo)`<br/>`dev (agent-core)`<br/>`test (agent-common ONLY)` | 최소 권한의 원칙에 따라 운영팀장, 개발자, 테스터의 그룹과 sudo 권한을 엄격히 분리 격리했습니다. |
| **증거 4** | **디렉토리 권한 및 ACL** | `upload_files (2770, SetGID, ACL+)`<br/>`api_keys (0750, others 차단)`<br/>`monitor.sh (0750, agent-dev)` | 공용 폴더는 SetGID와 POSIX ACL로 팀 협업을 보장하고, 비밀키 방은 테스터가 들어오지 못하게 잠갔습니다. |
| **증거 5** | **앱 프로세스 및 포트** | `1366 python3`<br/>`tcp LISTEN ... pid=1366` | 백엔드 파이썬 에이전트 앱의 프로세스 ID(1366)와 15034 포트를 LISTEN 중인 PID(1366)가 정확히 일치하여 정상 서비스 중입니다. |
| **증거 6** | **관제 스크립트 실행** | `Health Check Passed`<br/>`PID=..., Port 15034 is ACTIVE`<br/>`Resource Usage: CPU, MEM, DISK` | 순수 Bash로 작성된 monitor.sh가 프로세스, 포트, 3대 자원 사용량을 정상 진단하고 건강 판정을 내렸습니다. |
| **증거 7** | **누적 로깅 (디스크 보호)** | `/var/log/agent-app/monitor.log`<br/>`[날짜] PID:... CPU:...% MEM:...%` | 표준 시스템 로그 경로에 실시간 적재되며, 10MB x 10개 FIFO 큐 로테이션으로 디스크 풀을 방지합니다. |
| **증거 8** | **crontab 스케줄링** | `* * * * * monitor.sh >> ... 2>&1` | 관리자가 자리를 비워도 리눅스 cron 데몬이 1년 365일 매 1분마다 무중단으로 자동 순찰을 돕니다. |

---

#### 💡 [평가자 질문 대비] 증거 화면 세부 원리 Q&A

##### Q1. [증거 1] 왜 20022 포트가 2줄(`0.0.0.0:20022`, `[::]:20022`)이나 나오나요?
* **이유**: `0.0.0.0`은 기존 **IPv4**, `[::]`은 차세대 **IPv6** 인터넷 주소 체계입니다.
* 리눅스 `sshd` 데몬은 어떤 인터넷 환경에서 접속하더라도 연결을 놓치지 않도록 **듀얼 스택(Dual-Stack)으로 2개의 소켓을 열어두는 것이 완벽한 표준 동작**입니다.

##### Q2. [증거 2] `Default: deny (incoming), allow (outgoing), disabled (routed)`는 무슨 뜻인가요?
* **아파트 경비실 비유**:
  * `deny (incoming)`: 밖에서 들어오는 외부인은 **일단 전원 출입 금지!** (오직 방문증이 있는 20022번과 15034번만 통과)
  * `allow (outgoing)`: 아파트 주민이 밖으로 나가는 것은 **자유롭게 외출 허용!** (`apt update` 패키지 다운로드 등 가능)
  * `disabled (routed)`: 아파트 단지를 지름길 삼아 지나가려는 **경유 차량 통행 금지!** (해커의 경유지 악용 방지)

##### Q3. [증거 4] 권한 표기 `drwxrws---+`, `drwxr-x---`는 어떻게 읽나요?
* **공식**: **[1글자 종류] + [3글자 소유자] + [3글자 그룹] + [3글자 남들]**
  * 맨 앞 `d`는 **Directory (폴더)**, `-`는 **일반 파일**입니다.
  * `r` = 읽기(Read), `w` = 쓰기(Write), `x` = 실행 및 폴더 들어가기(eXecute), `-` = 권한 없음.
  * `s` (SetGID): 새 파일을 만들면 무조건 부모 폴더의 그룹(`agent-common`) 명찰이 붙는 특수 협업 비트입니다.
  * `+`: `setfacl`로 추가 설정된 정밀 자물쇠(POSIX ACL)가 걸려 있다는 표시입니다.
* **왜 테스터가 비밀키에 접근 못 하나요?**:
  * `api_keys`는 `drwxr-x---` (그룹: `agent-core`)로 잠겨 있습니다.
  * 테스터(`agent-test`)는 `agent-common` 소속이므로 **남들(`---`)** 취급을 받아 커널에서 즉시 `Permission denied`로 차단됩니다.

##### Q4. [증거 5] `1366 python3`의 숫자 `1366`은 무엇인가요?
* 운영체제가 파이썬 앱에게 발급해 준 **프로세스 고유 식별 번호(PID)**입니다.
* 윗줄의 `Process Status: 1366`과 아랫줄의 `pid=1366`이 똑같다는 것은, **"우리 파이썬 앱이 15034번 포트를 완벽하게 점유하고 있다"**는 결정적 증거입니다.

##### Q5. [증거 8] `* * * * * monitor.sh >> cron.log 2>&1`의 각 기호는 무엇인가요?
* `* * * * *`: 5개의 별은 `[분] [시] [일] [월] [요일]`이며, **"매 1분마다 쉬지 않고"**라는 뜻입니다.
* `>>`: 기존 내용을 덮어쓰지 않고 맨 밑에 계속 이어 붙여 쓰는 **누적 기록(Append)**입니다.
* `2>&1`: 1번(정상 출력)과 2번(에러 출력)을 하나로 합쳐서, **"사고나 에러가 나더라도 빠짐없이 로그 장부에 다 적어라"**라는 뜻입니다.

---

### 📍 3단계: 평가자 가면 가상머신 완전히 끄기

평가가 끝나면 깔끔하게 시스템을 종료합니다.

> ⚠️ **주의**: `wsl`은 윈도우 프로그램이므로, **우분투 가상머신 안에서 `wsl --shutdown`을 치면 `Command not found`**가 뜹니다! 아래 2가지 방법 중 하나를 사용하세요:

#### 방법 A: 빠져나와서 윈도우 PowerShell에서 끄기 (정석)
가상머신 안에서 `exit`를 입력해 PowerShell로 빠져나온 뒤:
```powershell
wsl --shutdown
```
*(가상머신의 메모리와 모든 백그라운드 프로세스가 즉시 안전하게 종료됩니다)*

#### 방법 B: 가상머신 안에서 바로 전원 끄기 (가장 편리함!)
가상머신 안에서 빠져나가지 않고 바로 종료 명령을 내립니다:
```bash
sudo poweroff
```
*(또는 우분투 안에서 윈도우 실행 파일명인 `wsl.exe --shutdown` 입력)*

---

## 🚀 가상환경(WSL2 / VM) 실습 및 직접 조작 가이드

> 💡 **안내**: 본 프로젝트는 UFW 방화벽 및 systemd, cron 데몬이 완벽히 구동되는 **WSL2 / VM Ubuntu 22.04 LTS** 환경에서 100% 검증 완료되었습니다.  
> 현재 가상환경에 **인프라 보안(SSH 20022, UFW) + 에이전트 앱(Port 15034) + crontab 자동 관제**가 모두 가동 중입니다.

---

### 🌟 코스 1: 지금 바로 가상환경에 들어가서 직접 만져보기 (추천!)

윈도우 PowerShell 터미널을 열고 아래 명령어로 가상환경에 접속하여 직접 조작해보실 수 있습니다:

#### 1. 가상머신 접속 (`agent-admin` 계정)
```powershell
# 윈도우 PowerShell에서 실행
wsl -d Ubuntu-22.04 -u agent-admin
```
*(접속 시 `/home/agent-admin` 디렉토리로 로그인됩니다)*

#### 2. 매 1분마다 찍히는 실시간 관제 로그 관찰 (`tail -f`)
백그라운드 cron이 매분 `monitor.sh`를 돌려 남기는 건강 검진 로그를 실시간으로 봅니다:
```bash
tail -f /var/log/agent-app/monitor.log
```
* 로그 예시: `[2026-10-02 17:37:15] PID:2708 CPU:0% MEM:11% DISK_USED:1%`
* 멈추려면: `Ctrl + C`

#### 3. 백엔드 에이전트 앱에 직접 HTTP 요청 보내보기 (`curl`)
포트 15034에서 살아 숨 쉬는 파이썬 에이전트 서버에 직접 핑을 보냅니다:
```bash
curl http://localhost:15034/
```
* 정상 응답: `{"status": "running", "service": "Codyssey Agent Server", "port": 15034}`

#### 4. 관제 스크립트(`monitor.sh`) 수동으로 1회 실행해보기
```bash
~/agent-app/bin/monitor.sh
```
* 출력 화면:
  ```text
  [WARNING] Memory usage high: 11% (Threshold: >10%)
  [INFO] Health Check Passed. PID=2708, Port 15034 is ACTIVE.
  [INFO] Resource Usage: CPU=0%, MEM=11%, DISK=1%
  [INFO] Log record added to /var/log/agent-app/monitor.log
  ```

#### 5. 8대 필수 제출 증거자료 원스톱 검증 도구 실행
과제 평가관에게 제출할 8대 증거(SSH 20022, UFW, 계정/ACL, 프로세스/포트, 로그 등)를 한 화면에 자동 검증합니다:
```bash
sudo /mnt/c/Users/안재현/Documents/24_code/2609_codyssey/codyssey-b4-01/scripts/verify_all.sh
```

#### 6. crontab 스케줄 등록 내역 확인
```bash
crontab -l
```
* 확인 내용: `* * * * * /home/agent-admin/agent-app/bin/monitor.sh >> /var/log/agent-app/cron.log 2>&1`

---

### 🔄 코스 2: 원클릭 마스터 통합 러너 (처음부터 끝까지 자동 재시연)

인프라 구축부터 앱 기동, 관제 실행, 8대 증거 수집까지 단 한 번의 명령어로 완전히 자동 재실행하고 싶을 때 사용합니다.

#### 방법 A: 윈도우 PowerShell에서 원클릭 실행
```powershell
wsl -d Ubuntu-22.04 -u root -e bash -c "cd /mnt/c/Users/안재현/Documents/24_code/2609_codyssey/codyssey-b4-01 && ./scripts/run_vm_demo.sh"
```

#### 방법 B: 가상머신 접속 후 실행
```bash
cd /mnt/c/Users/안재현/Documents/24_code/2609_codyssey/codyssey-b4-01
sudo ./scripts/run_vm_demo.sh
```

---

### 🛠️ 코스 3: 단계별 수동 구축 및 실습 (A to Z)

모든 과정을 단계별로 직접 실행하며 학습하고자 할 때 사용합니다:

1. **실행 권한 부여 및 인프라 프로비저닝**:
   ```bash
   sudo chmod +x scripts/*.sh bin/*.sh tests/*.sh
   sudo ./scripts/setup_server.sh
   ```
2. **에이전트 앱 백그라운드 기동 (`agent-admin` 계정)**:
   ```bash
   su - agent-admin -c "python3 ~/agent-app/agent_app.py" > /tmp/agent_app_boot.log 2>&1 &
   ```
3. **앱 상태 및 포트 리슨 확인**:
   ```bash
   ss -tulpn | grep 15034
   ```
4. **수동 관제 실행**:
   ```bash
   su - agent-admin -c "bash ~/agent-app/bin/monitor.sh"
   ```
5. **8대 필수 증거자료 수집**:
   ```bash
   sudo ./scripts/verify_all.sh
   ```
6. **앱 프로세스 종료 방법 (필요 시)**:
   ```bash
   sudo pkill -f "agent_app.py"
   ```

---

### 💻 코스 4: 윈도우 로컬 환경에서 맛보기 데모
리눅스 가상머신 없이 윈도우 로컬 터미널(Git Bash 연동)에서 5초 만에 관제 로직을 시연해보려면:
```powershell
python scripts/run_local_demo.py
```

---

## 🧪 자동화 테스트 실행

본 저장소에 포함된 테스트 스위트를 통해 스크립트의 무결성을 즉시 검증할 수 있습니다:

```bash
# monitor.sh 단위/통합 테스트 (프로세스 부재, 포트 미리스닝, 정상 수집, 로그 로테이션)
bash tests/test_monitor.sh

# agent_app.py 부트 시퀀스 및 15034 포트 바인딩 테스트
bash tests/test_agent_app.sh

# 아키텍처 다이어그램 재생성 (필요 시)
python scripts/generate_architecture_diagrams.py
```

---

## 📋 핵심 문서 바로가기
- 📘 **[스터디 및 면접 가이드 (스터디.md)](./스터디.md)**: 요구사항 1:1 매핑표, 쉬운 비유 해설 및 평가자 대비 10초 Q&A
- 🎙️ **[NotebookLM 팟캐스트 소스 (NOTEBOOKLM_GUIDE.md)](./NOTEBOOKLM_GUIDE.md)**: 귀로 듣는 오디오 개요용 딥다이브 텍스트
- 📄 **[요구사항 수행 내역서 (REPORT.md)](./REPORT.md)**: 8대 필수 증거자료 실측 로그 및 6가지 과제 목표 상세 해설
- 📜 **[관제 스크립트 (bin/monitor.sh)](./bin/monitor.sh)**: 순수 Bash 2단 주석화 헬스체크 및 로그 로테이션 스크립트

---

## 🎬 한눈에 보는 3막 스토리 (전체 그림 1분 요약)

우리가 만든 시스템은 쉽게 말해 **"무인 24시 편의점과 자동 순찰 경비 시스템"**입니다.

```
[1막. 성벽 치기] ──> [2막. 가게 열기] ──> [3막. 자동 순찰 & 블랙박스 기록]
   (SSH & 방화벽)        (Python 앱)               (monitor.sh & cron)
```

1. **1막: 도둑 차단 (SSH 20022 & UFW 방화벽)**
   - 편의점 정문(22번 포트)으로 도둑들이 자꾸 열쇠를 쑤셔대서, **출입구를 비밀문(20022번)으로 바꾸고 사장님 마스터키(root)는 외부에서 못 쓰게** 막았습니다.
   - 그리고 편의점 손님 통로(15034번)와 관리자 문(20022번) 외에는 모든 창문과 문을 시멘트로 막아버렸습니다(Default Deny).
2. **2막: 가게 오픈 (agent_app.py)**
   - 편의점 점원 역할을 하는 파이썬 프로그램입니다.
   - 문을 열기 전에 **5가지 준비운동(환경변수, 비밀키, 창고 확인 등)**을 하고 이상이 없으면 15034번 카운터에 앉아서 손님을 맞이합니다(`Agent READY`).
3. **3막: 1분 순찰 닥터 (monitor.sh & crontab)**
   - 점원이 졸고 있거나 쓰러지면 큰일 나니까, **cron이라는 로봇이 1분마다 순찰 닥터(`monitor.sh`)를 출동**시킵니다.
   - 점원이 살아있는지(PID), 카운터가 열려있는지(15034 포트), 매장의 전기세/온도(CPU/메모리)는 정상인지 체크해서 **블랙박스 일기장(`monitor.log`)**에 한 줄씩 기록합니다.

---

## 🖥️ 평가자 앞 시연 가이드: Ubuntu 가상 머신(VM) 실전 조작

> ⚠️ **중요 안내**:  
> 본 프로젝트의 모든 스크립트와 아키텍처는 **Linux (Ubuntu 22.04 LTS) 가상 머신 전용**으로 완성되었습니다.  
> 평가자 앞에서는 Windows 파워쉘이 아니라 **Ubuntu 가상 머신(VM 또는 WSL2) 터미널(`ubuntu@server:~$`)**에 입장하여 아래 순서대로 시연하시면 됩니다.

---

### 🚀 [초간단] 원클릭 통합 시연 러너 (권장)

가상 머신 터미널에서 아래 단 **1줄**을 실행하면, **서버 세팅부터 앱 실행, 관제 검진, 8대 증거 수집까지 한 번에 완료**됩니다.

```bash
sudo ./scripts/run_vm_demo.sh
```

---

### 🖐️ [정석 시연] 평가자 앞에서 한 단계씩 보여주는 4단계 라이브 시연

평가자가 각 단계별 확인을 요구할 경우, 아래 4개 블록을 순서대로 복사해서 가상 머신 터미널에 붙여넣으시면 됩니다.

#### [1단계] 서버 인프라 원클릭 자동 구축
*SSH 포트(20022), Root 차단, UFW 방화벽, 3개 계정 및 2개 그룹, ACL 권한, crontab을 한 번에 구축합니다.*
```bash
sudo ./scripts/setup_server.sh
```
👉 **평가자 확인 포인트**:
- SSH 설정 완료 (`/etc/ssh/sshd_config.d/codyssey.conf`)
- UFW 방화벽 활성화 (20022, 15034만 ALLOW)
- `agent-admin`, `agent-dev`, `agent-test` 계정 생성 및 권한 분리

---

#### [2단계] 일반 계정(`agent-admin`)으로 파이썬 에이전트 앱 기동
*루트가 아닌 일반 계정 권한으로 앱을 띄우고 5단계 부트 시퀀스 [OK]와 `Agent READY`를 확인합니다.*
```bash
# 백그라운드로 에이전트 앱 실행
su - agent-admin -c "nohup python3 ~/agent-app/agent_app.py > ~/agent-app/boot.log 2>&1 &"
sleep 2

# 부팅 5단계 [OK] 및 LISTEN 상태 확인
cat /home/agent-admin/agent-app/boot.log
ss -tulnp | grep 15034
```
👉 **평가자 확인 포인트**:
- Boot Sequence 5단계 전부 `[OK]`
- 마지막 라인 `[BOOT] Agent READY - Listening on 0.0.0.0:15034`
- 15034 포트 정상 LISTEN 확인

---

#### [3단계] 관제 스크립트(`monitor.sh`) 수동 점검 및 로그 적재 확인
*개발자(`agent-dev`)가 작성하고 관리자(`agent-admin`)가 실행하는 관제 스크립트의 동작과 로그를 확인합니다.*
```bash
# monitor.sh 직접 1회 실행
su - agent-admin -c "bash ~/agent-app/bin/monitor.sh"

# /var/log/agent-app/monitor.log 누적 기록 확인
tail -n 5 /var/log/agent-app/monitor.log
```
👉 **평가자 확인 포인트**:
- 프로세스(PID) 정상 감지 및 15034 포트 정상 확인
- CPU/MEM/DISK 사용률 측정 및 1줄 규격 포맷 로그 적재

---

#### [4단계] 8대 필수 증거자료 원스톱 검증 (평가표 채점)
*과제 요구사항에 명시된 8대 필수 증거자료를 터미널 화면에 일목요연하게 출력합니다.*
```bash
./scripts/verify_all.sh
```
👉 **평가자 확인 포인트**:
1. SSH 포트 20022 및 PermitRootLogin no
2. UFW 상태 (20022, 15034 허용)
3. 계정 및 그룹 구성
4. 디렉토리 구조 및 getfacl 권한
5. 부트 시퀀스 5단계 [OK]
6. monitor.sh 실행 결과
7. monitor.log 누적 기록
8. crontab 매분 실행 등록 상태

---

### 🚨 [보너스] 장애 감지 시연 (평가자가 장애 복구/감지 테스트를 요구할 때)

```bash
# 1. 점원(앱) 강제 종료
sudo pkill -f agent_app.py

# 2. monitor.sh 재실행 -> 즉시 비상 경보 발생 확인 (exit 1)
su - agent-admin -c "bash ~/agent-app/bin/monitor.sh" || echo "==> [장애 감지 완료: exit 1 정상 반환] <=="
```
👉 **평가자 확인 포인트**:
- `[ERROR] Health Check Failed: Process 'agent_app.py' is NOT running!`
- 프로세스 다운 시 즉시 `exit 1`로 비상 상태를 반환하는 엔지니어링 설계 입증

---

## 💡 최종 정리

| 구분 | 파일 위치 | 주요 역할 |
| :--- | :--- | :--- |
| **인프라 구축** | [`scripts/setup_server.sh`](file:///scripts/setup_server.sh) | SSH 20022, UFW, 계정/그룹/ACL, crontab 자동 설정 |
| **관제 스크립트** | [`bin/monitor.sh`](file:///bin/monitor.sh) | 헬스체크(PID/Port), 임계치 경고, 10MB×10 로그 로테이션 |
| **증거 검증기** | [`scripts/verify_all.sh`](file:///scripts/verify_all.sh) | 평가자 제출용 8대 필수 증거 일괄 수집 및 검증 |
| **원클릭 러너** | [`scripts/run_vm_demo.sh`](file:///scripts/run_vm_demo.sh) | 위 전 과정을 가상머신에서 원클릭으로 구동 |
| **제출 보고서** | [`REPORT.md`](file:///REPORT.md) | 요구사항 수행 내역서 및 8대 증거자료 체크리스트 문서 |



