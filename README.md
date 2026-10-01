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
│   └── generate_architecture_diagrams.py # 고해상도 아키텍처 다이어그램 렌더링 파이썬 스크립트
├── docs/
│   └── images/                 # 고해상도 아키텍처 다이어그램 (PNG)
│       ├── architecture_system_overview.png
│       ├── architecture_security_acl.png
│       └── architecture_monitor_flow.png
├── tests/
│   ├── test_monitor.sh         # monitor.sh 단위/통합 테스트 스위트 (12개 항목 자동 검증)
│   └── test_agent_app.sh       # agent_app.py 부트 시퀀스 및 포트 바인딩 테스트
├── 스터디.md                   # 요구사항 1:1 매핑, 주니어 일상 비유 해설 및 면접 10초 Q&A
├── NOTEBOOKLM_GUIDE.md         # Google NotebookLM 팟캐스트(Audio Overview) 학습용 원천 텍스트
├── MISSION_PLAN.md             # 6단계 실행 마스터 계획서
├── REPORT.md                   # [산출물 1] 요구사항 수행 내역서 (8대 필수 증거 자료 및 기술 원리 해설)
└── README.md                   # 프로젝트 사용 설명서
```

---

## 🚀 빠른 시작 가이드

### 1. Ubuntu 22.04 LTS 환경에서 자동 세팅 (권장)
리눅스 서버에 본 저장소를 클론한 후 아래 명령어를 실행하면 모든 보안/계정/권한/cron 설정이 완료됩니다:
```bash
sudo chmod +x scripts/*.sh bin/*.sh tests/*.sh
sudo ./scripts/setup_server.sh
```

### 2. 애플리케이션 실행
루트가 아닌 일반 계정(`agent-admin` 또는 `agent-dev`)으로 실행합니다:
```bash
su - agent-admin
python3 ~/agent-app/agent_app.py
```
- 정상 실행 시 5단계 Boot Sequence가 `[OK]`로 출력되고 `Agent READY`가 표시됩니다.

### 3. 관제 스크립트 수동 실행
```bash
/home/agent-admin/agent-app/bin/monitor.sh
```

### 4. 8대 필수 증거자료 자동 검증
```bash
./scripts/verify_all.sh
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

## 🧪 지금 내 컴퓨터에서 바로 해보는 "3분 핸즈온 체험"

현재 계신 터미널(PowerShell 또는 Git Bash)에서 **아래 순서대로 명령어를 복사해서 실행**해 보세요. 직접 상황을 눈으로 보면 전체 그림이 바로 와닿습니다!

```powershell
# 프로젝트 폴더로 이동 (이미 여기 계시다면 바로 진행)
cd "c:\Users\안재현\Documents\24_code\2609_codyssey\codyssey-b4-01"
```

### [상황 1] 점원 출근시키기 (정상 부팅 시퀀스 눈으로 보기)

가게를 오픈하기 위해 필요한 테스트 환경을 잠깐 만들고 앱을 실행해 봅니다.

```powershell
# 1. 테스트용 임시 폴더와 비밀키 1초 만에 준비
mkdir -p tests/demo/upload_files, tests/demo/api_keys, tests/demo/logs
Set-Content -Path tests/demo/api_keys/t_secret.key -Value "agent_api_key_test"

# 2. 환경 변수를 걸어주고 앱 실행!
$env:AGENT_HOME = "$PWD\tests\demo"
$env:AGENT_PORT = "15034"
$env:AGENT_UPLOAD_DIR = "$PWD\tests\demo\upload_files"
$env:AGENT_KEY_PATH = "$PWD\tests\demo\api_keys\t_secret.key"
$env:AGENT_LOG_DIR = "$PWD\tests\demo\logs"

# 앱 실행 (새 창으로 띄우기)
Start-Process python -ArgumentList "app/agent_app.py"
```

👉 **눈으로 볼 수 있는 결과**:
- 5단계 부트 시퀀스(`[OK]`)가 차례대로 뜨고 마지막에 **`Agent READY`**가 출력되면서 15034번 포트로 손님을 기다리는 상태가 됩니다!

---

### [상황 2] 순찰 닥터 출동시키기 (monitor.sh 정상 작동 눈으로 보기)

가게가 잘 열려있는 상태에서 닥터(`monitor.sh`)를 수동으로 출동시켜 봅니다.

```powershell
# Git Bash를 통해 monitor.sh 1회 실행
& "C:\Program Files\Git\bin\bash.exe" -c "
export AGENT_PORT=15034
export APP_PROCESS_NAME=agent_app.py
export AGENT_LOG_DIR=tests/demo/logs
bash bin/monitor.sh
"
```

👉 **눈으로 볼 수 있는 결과**:
```text
[INFO] Health Check Passed. PID=1234, Port 15034 is ACTIVE.
[INFO] Resource Usage: CPU=12%, MEM=8%, DISK=42%
[INFO] Log record added to tests/demo/logs/monitor.log
```
- 점원이 살아있고 포트가 열려 있으니 `Health Check Passed`가 뜨며 정상 종료(exit code 0)됩니다!

---

### [상황 3] 블랙박스 일기장 확인하기 (로그 적재 눈으로 보기)

방금 닥터가 남긴 진료 기록을 확인해 봅니다.

```powershell
Get-Content tests/demo/logs/monitor.log
```

👉 **눈으로 볼 수 있는 결과**:
```text
[2026-10-01 16:10:00] PID:1234 CPU:12% MEM:8% DISK_USED:42%
```
- 요구사항에 적혀있던 그 포맷 그대로 타임스탬프와 PID, 리소스 사용량이 딱 찍혀있습니다.

---

### [상황 4] 장애 상황 발생시키기! (점원이 쓰러졌을 때 닥터의 반응)

이제 점원(파이썬 앱)을 강제로 강제 종료시켜 버립니다.

```powershell
# 1. 실행 중인 파이썬 앱 강제 종료
Stop-Process -Name python -Force

# 2. 순찰 닥터(monitor.sh) 다시 출동!
& "C:\Program Files\Git\bin\bash.exe" -c "
export AGENT_PORT=15034
export APP_PROCESS_NAME=agent_app.py
export AGENT_LOG_DIR=tests/demo/logs
bash bin/monitor.sh
"
```

👉 **눈으로 볼 수 있는 결과**:
```text
[ERROR] Health Check Failed: Process 'agent_app.py' is NOT running!
```
```powershell
# 방금 실행의 종료 코드 확인 (1이 나오면 장애를 성공적으로 감지한 것!)
$LASTEXITCODE
```
- 점원이 사라진 것을 닥터가 **즉시 알아채고 빨간 불(`[ERROR]`, exit 1)을 뿜으며 비상 경보**를 울립니다!

---

### [상황 5] 12가지 자동화 테스트 스위트 한 번에 돌려보기

우리가 만들어 둔 테스트 러너가 이 모든 상황(포트 다운, 프로세스 다운, 로그 로테이션 등)을 컴퓨터가 1초 만에 알아서 테스트하게 해 줍니다.

```powershell
& "C:\Program Files\Git\bin\bash.exe" tests/test_monitor.sh
```

👉 **눈으로 볼 수 있는 결과**:
- `[PASS]` 표시가 12개 연달아 뜨면서 **`12 PASSED, 0 FAILED`**가 찍힙니다!

---

## 💡 요약: "아, 결국 이거구나!"

1. **`agent_app.py`**: 카운터 지키는 점원
2. **`monitor.sh`**: 1분마다 점원 맥박 재고 일기장 쓰는 의사
3. **`crontab`**: 의사를 1분마다 등 떠미는 자명종 시계
4. **`UFW / SSH 20022`**: 가게 털러 오는 도둑 막는 자물쇠와 경비실

