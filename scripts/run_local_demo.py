
import subprocess

import time

import os

project_root = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))

os.chdir(project_root)

os.makedirs("upload_files", exist_ok=True)

os.makedirs("api_keys", exist_ok=True)

os.makedirs("logs", exist_ok=True)

with open("api_keys/t_secret.key", "w", encoding="utf-8") as f:
    f.write("agent_api_key_test\n")

env = os.environ.copy()

env["AGENT_HOME"] = project_root

env["AGENT_PORT"] = "15034"

env["AGENT_UPLOAD_DIR"] = os.path.join(project_root, "upload_files")

env["AGENT_KEY_PATH"] = os.path.join(project_root, "api_keys", "t_secret.key")

env["AGENT_LOG_DIR"] = os.path.join(project_root, "logs")

print("[*] Launching agent_app.py in background...")

app_proc = subprocess.Popen(["python", "app/agent_app.py"], env=env)

time.sleep(2)

bash_path = r"C:\Program Files\Git\bin\bash.exe"

print("[*] Running monitor.sh via Git Bash...")

result = subprocess.run([bash_path, "bin/monitor.sh"], capture_output=True, env=env)

print("\n=== STDOUT (닥터의 정상 보고) ===")
print(result.stdout.decode("utf-8", errors="replace"))

print("=== STDERR (닥터의 에러/경고 보고) ===")
print(result.stderr.decode("utf-8", errors="replace"))

print(f"Exit Code (0이면 성공, 1이면 장애): {result.returncode}")

print("\n[*] Shutting down agent_app.py...")

app_proc.terminate()

try:
    app_proc.wait(timeout=2)
except Exception:
    app_proc.kill()

print("[*] Demo finished! Check logs in './logs/monitor.log'")

