# 📘 나의 학습 노트 (My Study Notes)
> 본 문서는 코드베이스 전반에 작성된 `# 마이:` 개인 학습 메모와 그 맥락(질문과 깨달음, 1차 기술 원리 및 2차 직관적 비유)을 한눈에 복습할 수 있도록 영구 보존 및 집대성한 학습 자료입니다.

---

## 1. 네트워크 소켓(Socket)의 본질과 부팅 시퀀스

### [코드 위치]: `app/agent_app.py` (L124~L151)
```python
# 마이: 소켓이란 뭔가? 랜선으로는 지금 이 순간에도 유튜브 영상, 카카오톡 메시지, 웹서핑 데이터 등 
# **수억 개의 0과 1 (전기 신호)**이 물밀듯이 쏟아져 들어옵니다. 그중 해당 프로그램이 필요한 정보를 주고 받기위해 만든 전용 연결 통로
server_sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
server_sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
server_sock.bind(("0.0.0.0", agent_port))
server_sock.listen(5)
```

### 💡 나의 이해와 핵심 정리
1. **소켓(Socket)이란?**
   * 랜선을 타고 들어오는 수억 개의 전기 신호(0과 1) 중, **"우리 프로그램 전용으로 데이터를 주고받기 위해 뚫어놓은 전용 파이프/출입구"**.
2. **`AF_INET`과 `SOCK_STREAM`**
   * `AF_INET`: IPv4(192.168.0.1 같은 4자리 숫자 IP) 전 세계 표준 인터넷 주소 체계.
   * `SOCK_STREAM`: 데이터 유실 없이 순서대로 전달하는 신뢰성 있는 TCP 스트림 방식 (중간에 끊기면 재전송 보장).
3. **`SOL_SOCKET` (Socket Option Level : Socket)**
   * TCP나 IP 같은 통신 규칙 레벨이 아니라, **"소켓 파이프(기계 자체)를 어떻게 다룰 것인가?"**에 대한 기본 카테고리 지정.
4. **`SO_REUSEADDR, 1` (포트 즉시 재사용)**
   * 프로그램을 껐다가 1초 만에 바로 켤 때, OS가 지연 패킷 방지를 위해 포트를 1~2분간 잠그는 **TIME_WAIT 대기 상태를 무시하고 즉시 포트를 다시 쓰게 해주는 필수 보험 스위치**.
5. **`bind(("0.0.0.0", 15034))`**
   * "0.0.0.0"(모든 랜선/와이파이 IP)으로 들어오는 15034번 포트 데이터를 내 소켓으로 연결해 달라고 OS에 등록.

---

## 2. 프로세스 종료 시그널(Signal)과 우아한 종료(Graceful Shutdown)

### [코드 위치]: `app/agent_app.py` (L200~L210)
```python
def handle_signal(sig, frame):
    print("\n[*] Shutting down Agent application gracefully...")
    try:
        sock.close()
    except Exception:
        pass
    sys.exit(0)

# 종료 시그널이 나오면 가로채서 handle_signal을 실행하고 
signal.signal(signal.SIGINT, handle_signal)   # 콘트롤 c 
signal.signal(signal.SIGTERM, handle_signal)  # 관리자가 터미널에서 kill 명령어
```

### 💡 나의 이해와 핵심 정리
1. **시그널 감지와 가로채기**
   * 외부(사용자의 `Ctrl + C` = `SIGINT`, 또는 OS/관리자의 `kill` = `SIGTERM`)에서 종료 신호가 날아올 때 프로그램을 강제로 튕기지 않고 가로챔.
2. **왜 2줄을 등록하는가?**
   * 두 번 실행되는 게 아니라, **"키보드로 끄든(`SIGINT`), 터미널 명령어로 끄든(`SIGTERM`), 둘 중 하나라도 들어오면 딱 1번 `handle_signal`을 발동시켜라"**는 비상 매뉴얼 등록.
3. **`handle_signal`의 역할**
   * 열려 있던 15034번 포트 문(`sock.close()`)을 깨끗이 닫고, 에러 로그 없이 깔끔하게 종료(`sys.exit(0)`).

---

## 3. 소켓 대기 루프와 동면 방지 (`sock.settimeout`)

### [코드 위치]: `app/agent_app.py` (L213~L220)
```python
# 마이 1초 단위로 해당 프로그램을 개우는 역할임. 없으면 바로 sock.accept()로 가서 오는 자료가 없다고 판단하고
# 동면상태가 되어 명령을 안받게됨. 그럼 꺼지지도 않는 문제 생김.
sock.settimeout(1.0)
while True:
    try:
        conn, addr = sock.accept() # 오면 conn이란 연결통로와 주소를 받아서 아래 내용을 주고 바로 크로즈해버림. 
        conn.sendall(b"HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\n\r\nAgent Status: OK\n")
        conn.close()
    except socket.timeout:
        continue
```

### 💡 나의 이해와 핵심 정리
1. **`sock.settimeout(1.0)`이 없으면 생기는 치명적 문제**
   * `sock.accept()`에서 손님이 올 때까지 CPU를 커널에 반납하고 **동면(블로킹)**에 빠짐.
   * 이때 사용자가 `Ctrl + C`를 눌러도 감지를 못 해서 **프로그램이 먹통이 되고 꺼지지도 않음!**
2. **1초 타임아웃의 역할**
   * 손님이 안 와도 1초마다 눈을 깜빡이며 잠에서 깨어남 ➡️ 사용자가 `Ctrl + C`를 눌렀는지 주기적으로 확인하여 즉각 반응 가능.
3. **`accept` ➡️ `sendall` ➡️ `close`의 흐름**
   * 손님이 오면 전용 대화 통로(`conn`)를 열고, "나 정상 작동 중이야(HTTP 200 OK)" 쪽지를 쥐여준 뒤, 즉시 연결을 닫고(`close`) 다음 손님 맞을 준비를 함.

---

## 4. 리눅스 명령어 삼총사 (`grep`, `sed`, `fi`)

### [코드 위치]: `scripts/setup_server.sh` (L80~L85)
```bash
# 마이: 그랩은 찾기, 찾는게 있으면(then), sed는 찾아 바꾸기, fi는 조건문끝.
if grep -q "^#*Port " /etc/ssh/sshd_config; then
    sed -i 's/^#*Port .*/Port 20022/' /etc/ssh/sshd_config
fi
```

### 💡 나의 이해와 핵심 정리
1. **`grep` (돋보기 / 찾기)**
   * 파일 안에서 특정 글자가 적혀 있는지 검색 (`-q`: 조용히 결과 코드만 반환).
2. **`sed` (지우개 / 찾아 바꾸기)**
   * 메모장을 열지 않고 터미널에서 글자를 즉시 치환 (`-i`: 원본 파일에 바로 덮어쓰기).
3. **`fi` (조건문 끝)**
   * `if`를 거꾸로 뒤집은 글자로, 조건문의 종료를 나타내는 닫는 괄호.

---

## 5. 협업 폴더 권한의 정석: SetGID (`2770`)와 Default ACL (`setfacl -d`)

### [코드 위치]: `scripts/setup_server.sh` (L239~L260)
```bash
# 마이: 2: SetGID 비트의 뜻은 폴더안에 새로운 폴더를 만들면 해당속성을 부모속성을 상속시킨다는 뜻
# 마이:  "앞으로 여기에 들어오는 파일은 전부 '우리 팀 공용 소속'으로 명찰을 바꿔라!"
chmod 2770 "${AGENT_HOME}/upload_files"

# 마이: "그리고 그 파일들은 '우리 팀원 누구나 수정(rwx)'할 수 있게 자물쇠를 항상 열어둬라!"
# setfacl (Set File Access Control Lists) 뜻: 파일의 세부 접근 권한(ACL)을 설정(Set)하는 리눅스 명령어
# -d (Default - 기본값 / 상속) 뜻: "지금 있는 파일이 아니라, 앞으로 이 폴더 안에 새로 만들어질 모든 자식 파일/폴더"에 적용하겠다는 옵션
# -m (Modify - 수정 / 규칙 추가) 뜻: 새로운 권한 규칙을 추가하거나 기존 규칙을 수정(Modify)하겠다는 옵션입니다.
# g (Group): 사용자 개인(u)이 아니라 특정 그룹(g)을 대상으로 하겠다!
# agent-common: 권한을 부여받을 그룹 이름입니다.
# rwx (Read, Write, eXecute): 부여할 권한
# 2>: 리눅스에서 1번은 정상 출력(STDOUT), 2번은 에러 출력(STDERR)을 뜻합니다.
# /dev/null: 리눅스의 '블랙홀(휴지통)'입니다. 여기에 들어간 글자는 화면에 안 보이고 영원히 증발합니다.
setfacl -d -m g:agent-common:rwx "${AGENT_HOME}/upload_files" 2>/dev/null || true
```

### 💡 나의 이해와 핵심 정리
1. **SetGID (`chmod 2770`)는 "소속 그룹 명찰"만 물려준다!**
   * 누가 파일을 올리든 파일의 소속 그룹을 `agent-common`으로 자동 고정.
   * 하지만 유저의 `umask` 때문에 권한은 `644(rw-r--r--)`가 되어 **다른 팀원의 쓰기(w)가 막히는 한계**가 발생!
2. **Default ACL (`setfacl -d`)이 "진짜 쓰기 권한(rwx)"을 물려준다!**
   * 앞으로 생길 모든 파일에 `agent-common` 그룹의 `rwx` 권한을 강제로 박아넣음.
3. **결론**: SetGID와 Default ACL을 세트로 써야만 **"소속도 우리 팀이고 + 팀원 누구나 수정(R/W)도 가능한 진짜 공용 폴더"**가 완성됨.

---

## 6. 주기적 자동 실행 스케줄러 (`cron`과 `crontab`)

### [코드 위치]: `scripts/setup_server.sh` (L360~L387)
```bash
# * * * * * : 모든 날짜 데이터를 받아오고 그게 변할떄 알림을 받는다이기에 일종의 서식임. 0  9  *  *  1   을 하면 월요일 오전9시에 알림받는다.는 뜻이됨
# ${AGENT_HOME}/bin/monitor.sh을 실행
# 화살표 1개(>)는 기존 내용을 싹 지우고 새로 쓰는 **'덮어쓰기'**입니다.화살표 2개(>>)는 기존 내용을 보존하고 **그 밑에 계속 이어 붙이는 '누적 쓰기(Append)'**입니다.
# ${LOG_DIR}/cron.log뜻: 스크립트 실행 결과를 누적해서 저장할 로그 파일의 이름과 경로
# 2>&1 뜻: 에러(Error)가 나면 화면(터미널)에 보이지 말고, 로그 파일(cron.log) 뒤에 붙여서 같이 기록해라. 2번에 나오는 에러 메시지도 1에 보내고
# 1에 보내면 그게 합쳐져서 출력되니 로그에 기록됨. 
CRON_JOB="* * * * * ${AGENT_HOME}/bin/monitor.sh >> ${LOG_DIR}/cron.log 2>&1"

# (): 뜻: 괄호 안에 있는 여러 명령어들의 출력을 하나의 큰 결과물로 한 번에 묶어서 취합하겠다는 뜻
# crontab: 뜻: 리눅스에서 주기적으로 작업을 실행하는 '시간 예약 스케줄러(자명종 시계)'를 관리하는 명령어
# -u (User): 뜻: 특정 사용자(여기서는 agent-admin)의 작업 목록을 보거나 수정하겠다는 뜻
# -l (List): 뜻: 현재 등록된 작업 목록(List)을 보여달라는 뜻
# 2>/dev/null : 뜻: 에러 메시지가 나오면 버려라 (보통 작업이 없을 때 "no crontab for user" 같은 에러가 나오는데 그걸 숨기기 위함)
# grep -v "monitor.sh" : 뜻: 텍스트에서 'monitor.sh'라는 단어가 포함되지 않은 줄만 골라내라 (제외(Invert)의 뜻)
# 7시1분에 깨운다는 식으로 등록되는게 아니야 매분 깨운다로 등록되기에 중복되면 매분 2명이 깨우는 사태가 일어남.
# || true : 뜻: 앞의 명령이 실패해도(예: 작업이 하나도 없어서 grep이 에러를 뱉어도) 프로그램을 죽이지 말고 그냥 계속 진행해라 (True)
# echo "${CRON_JOB}"의 텍스트가 출력되면 텍스트를 받아서 crontab -u agent-admin -에서 일을 함.
# - 맨 뒤의 대시 기호: 뜻: 키보드 입력이나 파일이 아니라, 앞에서 파이프(|)를 타고 넘어온 그 내용물 전체를 받아서 통째로 새 알람 목록으로 저장(덮어쓰기)해라!
# 크론 설정에 크론 잡을 읽고 설정으로 들어가서 알아서 1분마다 깨우는 매커니즘이 됨.
(crontab -u agent-admin -l 2>/dev/null | grep -v "monitor.sh" || true; echo "${CRON_JOB}") | crontab -u agent-admin -

# 위에서 크론 설정한걸 시스템 서비스로 가동함.
systemctl enable cron
systemctl restart cron || true
```

### 💡 나의 이해와 핵심 정리
1. **`* * * * *` (별 5개의 의미)**
   * `[분] [시] [일] [월] [요일]`의 고정 서식.
   * `*`는 "상관없이 항상 통과"이므로 매월, 매일, 매시간, **매 1분마다 무한 반복 실행**.
2. **왜 기존 `monitor.sh`를 굳이 빼고(`grep -v`) 다시 넣을까?**
   * `setup_server.sh`를 3번 실행했을 때 알람이 3개로 중복 복사되어 1분마다 3번씩 도는 대참사를 막기 위해!
   * 기존 잡동사니 업무는 살려두고, 옛날 `monitor.sh`는 지우고 새 `monitor.sh` 1개만 깔끔하게 등록(멱등성 보장).
3. **`CRON_JOB` 변수와 `crontab -`의 관계**
   * 변수에 적힌 긴 글자를 꺼내어(`echo`) 파이프로 넘겨주면, 맨 뒤의 `crontab -u ... -`가 진짜 리눅스 알람 장부 파일(`/var/spool/cron/...`)에 저장함.

---

## 7. 문자열 필터링과 로그 로테이션 (`tr -dc`, `-ge`)

### [코드 위치]: `bin/monitor.sh` (L99~L130)
```bash
# tr(변경한다는 명령어) 명령어로 숫자(0-9) 이외의 모든 공백이나 제어 문자를 제거하여 순수 정수로 정제합니다.
# 마이: d는 삭제, c는 제외. 0~9제외하고 지우란 내용이 됨.
file_size=$(echo "${file_size}" | tr -dc '0-9')
file_size="${file_size:-0}"

# ge가 그레이터 or이퀄로 파일사이즈가 맥스보다 크면 발동되는 셈
if [ "${file_size}" -ge "${MAX_LOG_SIZE}" ]; then
    ...
    # 일단 기존 로그 파일의 번호를 1씩 더하고 기존 로그 파일을 로그 1번파일로 바꾸고 새 로그 파일을 만드는 순서
    touch "${LOG_FILE}"
    chmod 640 "${LOG_FILE}" 2>/dev/null || true
fi
```

### 💡 나의 이해와 핵심 정리
1. **`tr -dc '0-9'`**
   * `-d` (Delete: 지워라) + `-c` (Complement: 0~9 빼고 나머지 전부를)
   * 파일 크기 수치에 묻어있는 공백, 엔터(`\r\n`) 등의 찌꺼기를 날려버리고 **순수 정수만 남기는 거름망**.
2. **`-ge` (Greater than or Equal)**
   * `file_size >= 10MB` 조건. 파일이 10MB 이상으로 뚱뚱해지면 로그 로테이션 발동!
3. **로그 로테이션의 3단계 순서**
   * ① 9번부터 1번까지 뒤에서부터 번호를 1씩 증가 (`.1` ➡️ `.2`, ..., `.9` ➡️ `.10`)
   * ② 꽉 찬 원본 `monitor.log`를 `monitor.log.1`로 변경
   * ③ 새 `monitor.log`를 생성하고 권한 640 부여

---

## 8. 프로세스 검색 (`pgrep`)

### [코드 위치]: `bin/monitor.sh` (L143~L149)
```bash
# pgrep(프로세스그랩)은 프로세스를 찾을때 쓰는 명령어임. 있는지 확인후 있으면 해당 프로세스를 위에서 1줄 내놓으란 이야기
if command -v pgrep >/dev/null 2>&1; then
    pid=$(pgrep -f "${APP_PROCESS_NAME}" | head -n 1)
fi
```

### 💡 나의 이해와 핵심 정리
1. **`command -v pgrep`**
   * 시스템에 `pgrep` 도구가 깔려 있는지 사전 검사.
2. **`pgrep -f` (Full Command-line Search)**
   * 프로세스 이름뿐만 아니라 전체 명령어 줄(`python app/agent_app.py`)까지 통째로 검색해서 PID를 찾아냄.
3. **`head -n 1`**
   * 혹시 여러 개가 검색되더라도 헷갈리지 않게 맨 윗줄 1개만 추출.
