#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Agent Application (agent_app.py)
Codyssey B4-1 실습 및 관제 대상 애플리케이션
- 5단계 Boot Sequence 출력 및 'Agent READY'
- 0.0.0.0:15034 TCP 포트 Listen
- 일반 계정 실행 검증 (루트 실행 금지)
"""

import os
import sys
import time
import socket
import signal

EXPECTED_KEY_CONTENT = "agent_api_key_test"

def check_non_root():
    # Windows 환경이 아닌 리눅스 환경에서 geteuid 체크
    if hasattr(os, "geteuid"):
        if os.geteuid() == 0:
            print("[FATAL] Security Error: Running as root is strictly prohibited!", file=sys.stderr)
            sys.exit(1)

def run_boot_sequence():
    print("==================================================")
    print("        Starting Agent Boot Sequence              ")
    print("==================================================")

    # Step 1: 환경 변수 로드
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

    # Step 2: 키 파일 검증
    if not os.path.isfile(key_path):
        print(f"[Step 2] Validating API Secret Key: [FAILED] (Key file not found at {key_path})", file=sys.stderr)
        sys.exit(1)
    try:
        with open(key_path, "r", encoding="utf-8") as f:
            content = f.read().strip()
            if content != EXPECTED_KEY_CONTENT:
                print(f"[Step 2] Validating API Secret Key: [FAILED] (Invalid key content)", file=sys.stderr)
                sys.exit(1)
        print(f"[Step 2] Validating API Secret Key: [OK]")
    except Exception as e:
        print(f"[Step 2] Validating API Secret Key: [FAILED] ({e})", file=sys.stderr)
        sys.exit(1)
    time.sleep(0.3)

    # Step 3: 업로드 디렉토리 확인
    if not os.path.isdir(upload_dir):
        print(f"[Step 3] Checking Upload Directory: [FAILED] (Directory not found: {upload_dir})", file=sys.stderr)
        sys.exit(1)
    if not (os.access(upload_dir, os.R_OK) and os.access(upload_dir, os.W_OK)):
        print(f"[Step 3] Checking Upload Directory: [FAILED] (Permission denied: R/W required)", file=sys.stderr)
        sys.exit(1)
    print(f"[Step 3] Checking Upload Directory Permissions: [OK]")
    time.sleep(0.3)

    # Step 4: 로그 디렉토리 확인
    if not os.path.isdir(log_dir):
        # 없으면 시도
        try:
            os.makedirs(log_dir, exist_ok=True)
        except Exception:
            pass
    if not os.path.isdir(log_dir) or not os.access(log_dir, os.W_OK):
        print(f"[Step 4] Checking Log Directory: [FAILED] (Permission denied: {log_dir} write required)", file=sys.stderr)
        sys.exit(1)
    print(f"[Step 4] Checking Log Directory Permissions: [OK]")
    time.sleep(0.3)

    # Step 5: 포트 바인딩 준비
    try:
        server_sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        server_sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        server_sock.bind(("0.0.0.0", agent_port))
        server_sock.listen(5)
        print(f"[Step 5] Binding Port {agent_port} (0.0.0.0:{agent_port}): [OK]")
    except Exception as e:
        print(f"[Step 5] Binding Port {agent_port}: [FAILED] ({e})", file=sys.stderr)
        sys.exit(1)
    time.sleep(0.3)

    print("==================================================")
    print("Agent READY")
    print("==================================================")
    print(f"[*] Agent application is now running on 0.0.0.0:{agent_port}")
    print("[*] Press Ctrl+C to stop the agent.")

    return server_sock

def main():
    check_non_root()
    sock = run_boot_sequence()

    def handle_signal(sig, frame):
        print("\n[*] Shutting down Agent application gracefully...")
        try:
            sock.close()
        except Exception:
            pass
        sys.exit(0)

    signal.signal(signal.SIGINT, handle_signal)
    signal.signal(signal.SIGTERM, handle_signal)

    # 서버 루프 (Non-blocking accept or simple timeout loop)
    sock.settimeout(1.0)
    while True:
        try:
            conn, addr = sock.accept()
            conn.sendall(b"HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\n\r\nAgent Status: OK\n")
            conn.close()
        except socket.timeout:
            continue
        except Exception:
            break

if __name__ == "__main__":
    main()
