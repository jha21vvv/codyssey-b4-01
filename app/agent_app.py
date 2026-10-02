#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
==============================================================================
Agent Application (agent_app.py)
Codyssey B4-1 과제의 메인 서비스 애플리케이션 (가게 점원 역할)
- 5단계 Boot Sequence 사전 검증 및 통과 후 'Agent READY' 출력
- 0.0.0.0:15034 TCP 포트를 열고 손님의 접속을 대기 (LISTEN)
- 루트(root) 계정 실행을 엄격히 금지 (최소 권한의 원칙 준수)
==============================================================================
"""

import os      # [1차]: 운영체제 환경변수 및 파일/디렉토리 시스템 제어 표준 라이브러리
               # [2차]: 파이썬이 리눅스/윈도우 OS와 대화하기 위한 전화기
import sys     # [1차]: 파이썬 인터프리터 제어 및 exit() 종료 코드, 표준에러(stderr) 제어
               # [2차]: 프로그램의 생명줄(강제종료, 에러 외치기)을 쥐고 있는 스위치
import time    # [1차]: 단계별 지연(sleep) 및 타임아웃 처리를 위한 시간 모듈
               # [2차]: 부팅 단계를 사람이 눈으로 차분히 볼 수 있게 0.3초 쉬어가는 스톱워치
import socket  # [1차]: TCP/IP 네트워크 소켓 통신을 생성하고 포트를 바인딩하는 라이브러리
               # [2차]: 15034번 방에 전화선(통신 통로)을 연결하는 도구
import signal  # [1차]: Ctrl+C(SIGINT) 등 OS 인터럽트 시그널을 가로채서 안전하게 종료하는 모듈
               # [2차]: 손님이 가게 불을 끌 때(Ctrl+C) 전기 충격 없이 차분히 문 닫고 퇴근하는 안전장치

# [1차]: t_secret.key 파일 안에 정확히 들어있어야 하는 비밀키 기대값 상수
# [2차]: 금고를 열기 위해 맞춰야 하는 공식 비밀번호 텍스트
EXPECTED_KEY_CONTENT = "agent_api_key_test"

def check_non_root():
    """
    [1차]: 현재 실행 중인 프로세스의 실효 사용자 ID(EUID)가 0(root)인지 검사합니다.
    [2차]: 앱을 실행한 사람이 최고 권력자 '사장님(root)'인지 확인하고, 사장님이면 일을 시키지 않고 쫓아냅니다.
    """
    # [1차]: 윈도우에는 geteuid가 없으므로 hasattr로 리눅스 환경 여부를 먼저 확인합니다.
    # [2차]: 리눅스 환경인 경우에만 신분증 번호(UID) 검사기를 꺼냅니다.
    if hasattr(os, "geteuid"):
        if os.geteuid() == 0:
            # [1차]: UID가 0(root)이면 보안 규정 위반이므로 표준 에러로 출력하고 비정상 종료(exit 1)합니다.
            # [2차]: "보안상 사장님 직접 실행 금지! 일반 직원 계정으로 로그인해서 실행하세요!" 경고 후 종료합니다.
            print("[FATAL] Security Error: Running as root is strictly prohibited!", file=sys.stderr)
            sys.exit(1)

def run_boot_sequence():
    """
    [1차]: 서비스를 오픈하기 전에 5단계 필수 환경(환경변수, 비밀키, 디렉토리 권한, 포트)을 점검하는 함수입니다.
    [2차]: 비행기가 이륙하기 전 5가지 체크리스트를 하나씩 확인하고, 다 통과해야 'Agent READY' 사인을 켭니다.
    """
    print("==================================================")
    print("        Starting Agent Boot Sequence              ")
    print("==================================================")

    # --------------------------------------------------------------------------
    # [Step 1]: 환경 변수 로드 검증
    # --------------------------------------------------------------------------
    # [1차]: os.environ.get으로 OS에 등록된 환경변수를 읽고, 없으면 기본값으로 대체합니다.
    # [2차]: 근무 지침서(환경변수 메모)를 읽어서 홈 디렉토리, 포트 번호, 금고 위치를 파악합니다.
    agent_home = os.environ.get("AGENT_HOME", os.path.expanduser("~/agent-app"))
    agent_port = int(os.environ.get("AGENT_PORT", "15034"))
    upload_dir = os.environ.get("AGENT_UPLOAD_DIR", os.path.join(agent_home, "upload_files"))
    key_path = os.environ.get("AGENT_KEY_PATH", os.path.join(agent_home, "api_keys", "t_secret.key"))
    log_dir = os.environ.get("AGENT_LOG_DIR", "/var/log/agent-app")

    print(f"[Step 1] Loading Environment Variables: [OK]")
    print(f"         AGENT_HOME       = {agent_home}")
    print(f"         AGENT_PORT       = {agent_port}")
    print(f"         AGENT_UPLOAD_DIR = {upload_dir}")
    print(f"         AGENT_KEY_PATH   = {key_path}")
    print(f"         AGENT_LOG_DIR    = {log_dir}")
    time.sleep(0.3)

    # --------------------------------------------------------------------------
    # [Step 2]: API Secret Key 파일 실존 및 내용 검증
    # --------------------------------------------------------------------------
    # [1차]: 키 파일이 실제 파일로 존재하는지(-f) 검사합니다. 없으면 즉시 exit 1로 Fail-Fast 종료합니다.
    # [2차]: 금고 안에 비밀열쇠(t_secret.key)가 진짜로 놓여 있는지 확인합니다.
    if not os.path.isfile(key_path):
        print(f"[Step 2] Validating API Secret Key: [FAILED] (Key file not found at {key_path})", file=sys.stderr)
        sys.exit(1)

    try:
        # [1차]: 키 파일을 UTF-8로 열어 내용을 읽고 공백을 제거(.strip())한 뒤 기대값과 비교합니다.
        # [2차]: 비밀열쇠에 적힌 암호가 진짜 정품 암호('agent_api_key_test')와 일치하는지 확인합니다.
        with open(key_path, "r", encoding="utf-8") as f:
            content = f.read().strip()
            if content != EXPECTED_KEY_CONTENT:
                print(f"[Step 2] Validating API Secret Key: [FAILED] (Invalid key content)", file=sys.stderr)
                sys.exit(1)
        print(f"[Step 2] Validating API Secret Key: [OK]")
    except Exception as e:
        print(f"[Step 2] Validating API Secret Key: [FAILED] ({e})", file=sys.stderr)
        sys.exit(1)
    time.sleep(0.05)

    # --------------------------------------------------------------------------
    # [Step 3]: 파일 업로드 디렉토리 존재 및 읽기/쓰기(R/W) 권한 검증
    # --------------------------------------------------------------------------
    # [1차]: upload_files 경로가 디렉토리인지 확인하고, 현재 프로세스가 읽기(R_OK)와 쓰기(W_OK) 권한이 있는지 검사합니다.
    # [2차]: 손님이 물건을 올려둘 창고가 진짜 있는지, 거기에 물건을 넣고 뺄 수 있는지 문을 열어봅니다.
    if not os.path.isdir(upload_dir):
        print(f"[Step 3] Checking Upload Directory: [FAILED] (Directory not found: {upload_dir})", file=sys.stderr)
        sys.exit(1)
    if not (os.access(upload_dir, os.R_OK) and os.access(upload_dir, os.W_OK)):
        print(f"[Step 3] Checking Upload Directory: [FAILED] (Permission denied: R/W required)", file=sys.stderr)
        sys.exit(1)
    print(f"[Step 3] Checking Upload Directory Permissions: [OK]")
    time.sleep(0.05)

    # --------------------------------------------------------------------------
    # [Step 4]: 로그 기록 디렉토리 쓰기(W) 권한 검증
    # --------------------------------------------------------------------------
    # [1차]: 로그 디렉토리가 없으면 생성을 시도하고, 최종적으로 쓰기(W_OK)가 가능한지 점검합니다.
    # [2차]: 나중에 닥터가 일기장을 꽂아둘 서류함에 펜으로 글씨를 쓸 수 있는지 확인합니다.
    if not os.path.isdir(log_dir):
        try:
            os.makedirs(log_dir, exist_ok=True)
        except Exception:
            pass
    if not os.path.isdir(log_dir) or not os.access(log_dir, os.W_OK):
        print(f"[Step 4] Checking Log Directory: [FAILED] (Permission denied: {log_dir} write required)", file=sys.stderr)
        sys.exit(1)
    print(f"[Step 4] Checking Log Directory Permissions: [OK]")
    time.sleep(0.05)


    # 마이: 소켓이란 뭔가? 랜선으로는 지금 이 순간에도 유튜브 영상, 카카오톡 메시지, 웹서핑 데이터 등 
    # **수억 개의 0과 1 (전기 신호)**이 물밀듯이 쏟아져 들어옵니다. 그중 해당 프로그램이 필요한 정보를 주고 받기위해 만든 전용 연결 통로
    # --------------------------------------------------------------------------
    # [Step 5]: 0.0.0.0:15034 TCP 소켓 바인딩 및 LISTEN 개방
    # --------------------------------------------------------------------------
    # [1차]: IPv4 TCP 스트림 소켓을 생성하고, 포트 재사용(SO_REUSEADDR) 옵션을 켠 뒤 15034번 포트로 바인딩합니다.
    # [2차]: 15034번 손님 출입구 문을 활짝 열고 안내 데스크를 설치합니다.
    # --------------------------------------------------------------------------
    # [Step 5]: 0.0.0.0:15034 TCP 소켓 바인딩 및 LISTEN 개방
    # --------------------------------------------------------------------------
    try:
        # [단어 분해]:
        # - socket.socket(...) : 파이썬의 네트워크 소켓 객체를 새로 생성하는 생성자 함수
        # - AF_INET (Address Family : INET) : IPv4 인터넷 주소 체계(192.168.0.1 같은 4자리 숫자 IP)를 사용하겠다는 뜻.
        # - 전세계표준으로 어디서든 접속 가능하게 한다는 내용
        # - SOCK_STREAM (Socket Stream) : 데이터 유실 없이 순서대로 전달하는 신뢰성 있는 TCP 연결 방식 프로토콜을 사용하겠다는 뜻
        #   데이터가 중간에 끊기거나 뒤섞이지 않고 편지처럼 차례대로 도착하는 보장하여 끊기거나 유실되면 새로 보내주는 방식
        # - server_sock : 이렇게 만들어진 전화기 본체 객체를 담아둘 변수 이름
        server_sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)

        # [단어 분해]:
        # - setsockopt (Set Socket Options) : 생성된 소켓의 세부 동작 옵션(설정 스위치)을 변경하는 함수
        # - SOL_SOCKET (Socket Option Level : Socket) : 설정하려는 옵션이 네트워크 프로토콜(TCP/IP) 레벨이 아니라 가장 기본인
        #  '소켓 자체' 레벨에 속한다는 표준 규격. 그러니까 소켓의 운영규칙 문제가 아니라 소켓의 자체를 어떻게 할거냐의 문제라는 의미. 기계적 설정
        # - SO_REUSEADDR (Socket Option : Reuse Address) : 방금 전 닫힌 포트 번호라도 TIME_WAIT(대기 시간) 없이 즉시 
        # 재사용(Reuse)하겠다는 옵션 이름
        # - 1 (True / 활성화) : 이 옵션 스위치를 ON(켜기: 1) 하겠다는 값
        server_sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)

        # [단어 분해]:
        # - bind (묶다 / 꽂다) : 소켓(전화기)에 특정 IP 주소와 포트 번호(내선번호)를 연결하여 OS에 등록하는 함수
        # - ("0.0.0.0", agent_port) : 튜플(Tuple) 형태의 (IP주소, 포트번호) 세트
        #   * "0.0.0.0" : 서버 컴퓨터에 연결된 모든 IP(내부 랜선, 외부 와이파이, 로컬 127.0.0.1 등)로 걸려오는 접속을 가리지 않고 전부 다 받겠다는 와일드카드 IP
        #   * agent_port (15034) : 우리 앱이 손님과 대화하기 위해 점유할 고유 출입문(포트) 번호
        # 15034번 포트로 들어오는 모든 데이터는 전부 내 전화기(server_sock)로 연결해 주세요!
        server_sock.bind(("0.0.0.0", agent_port))

        # [단어 분해]:
        # - listen (귀 기울여 듣다) : 소켓을 '손님 연결을 기다리는 상태(LISTEN 상태)'로 전환하는 함수
        # - 5 (Backlog / 대기 큐 크기) : 손님이 동시에 몰려왔을 때 미처 수화기를 들기 전 대기실(Queue)에 세워둘 수 있는 최대 대기 손님 수 (최대 5명 대기)
        server_sock.listen(5)

        # - print(...) : 5단계 성공을 콘솔에 찍음
        print(f"[Step 5] Binding Port {agent_port} (0.0.0.0:{agent_port}): [OK]")

    except Exception as e:
        # [단어 분해]:
        # - except Exception as e : 포트 충돌, 권한 부족 등 어떤 에러라도 발생하면 가로채서 e라는 변수에 에러 내용을 담음
        # - file=sys.stderr : 에러 문장을 일반 출력(stdout)이 아닌 '표준 에러(stderr)' 전용 통로로 내보내어 모니터링 도구가 감지하게 만듦
        # - sys.exit(1) : 1번 비상 에러 코드를 OS에 던지며 프로그램을 즉시 중단 (Fail-Fast)
        print(f"[Step 5] Binding Port {agent_port}: [FAILED] ({e})", file=sys.stderr)
        sys.exit(1)

    # - time.sleep(0.3) : 사람이 콘솔 글자를 편안하게 읽을 수 있도록 0.3초간 잠깐 숨을 고름
    time.sleep(0.05)


    # 5단계 통과 후 공식 준비 완료 신호 출력
    print("==================================================")
    print("Agent READY")
    print("==================================================")
    print(f"[*] Agent application is now running on 0.0.0.0:{agent_port}")
    print("[*] Press Ctrl+C to stop the agent.")

    return server_sock

def main():
    """
    [1차]: 보안 검증 -> 부팅 시퀀스 -> 시그널 핸들러 등록 -> 메인 서비스 루프 실행 흐름
    [2차]: 점원이 출근해서 문 열고, 손님 응대 루프를 돌며 하루를 시작하는 메인 함수
    """
    check_non_root()
    sock = run_boot_sequence()

    # [1차]: Ctrl+C(SIGINT)나 종료 시그널(SIGTERM) 수신 시 소켓을 닫고 안전하게 종료하는 핸들러
    # [2차]: 손님이 나가라고 불을 끄면(Ctrl+C) 문단속(sock.close)을 똑바로 하고 퇴근하는 정리 로직
    def handle_signal(sig, frame):
        print("\n[*] Shutting down Agent application gracefully...")
        try:
            sock.close()
        except Exception:
            pass
        sys.exit(0)
    # 종료 시그널이 나오면 가로채서 handle_signal을 실행하고 
    signal.signal(signal.SIGINT, handle_signal)# 콘트롤 c 
    signal.signal(signal.SIGTERM, handle_signal)#관리자가 터미널에서 kill 명령어

    # [1차]: 타임아웃 1초 단위로 accept 대기 루프를 돌며 간단한 헬스체크 HTTP 200 응답을 반환합니다.
    # [2차]: 카운터에서 1초마다 문밖을 내다보다가 손님이 오면 "정상 영업 중입니다" 인사하고 영수증을 줍니다.
    # 마이 1초 단위로 해당 프로그램을 개우는 역할임. 없으면 바로 sock.accept()로 가서 오는 자료가 없다고 판단하고
    # 동면상태가 되어 명령을 안받게됨. 그럼 꺼지지도 않는 문제 생김.
    sock.settimeout(1.0)
    while True:
        try:
            conn, addr = sock.accept()# 오면 conn이란 연결통로와 주소를 받아서 아래 내용을 주고 바로 크로즈해버림. 
            response_body = b"Agent Status: OK\n"
            response_header = (
                f"HTTP/1.1 200 OK\r\n"
                f"Content-Type: text/plain\r\n"
                f"Content-Length: {len(response_body)}\r\n"
                f"Connection: close\r\n\r\n"
            ).encode("utf-8")
            conn.sendall(response_header + response_body)
            conn.close()
        except socket.timeout:
            continue
        except Exception:
            break

if __name__ == "__main__":
    main()
