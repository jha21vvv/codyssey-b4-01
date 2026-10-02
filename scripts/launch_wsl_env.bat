@echo off
REM ==============================================================================
REM Codyssey B4-1 WSL2 Ubuntu 22.04 LTS 가상머신 접속 및 실습 런처
REM ==============================================================================
echo =====================================================================
echo  [Codyssey B4-1] Connecting to WSL2 Ubuntu 22.04 Virtual Lab...
echo =====================================================================

REM 1. WSL 설치 여부 점검
wsl --status >nul 2>&1
if %errorlevel% neq 0 (
    echo [INFO] WSL is not yet enabled. Installing Ubuntu 22.04...
    echo Please run PowerShell as Administrator and execute:
    echo     wsl --install -d Ubuntu-22.04
    pause
    exit /b 1
)

REM 2. 프로젝트 폴더로 이동하여 WSL Ubuntu 쉘 실행
echo [*] Entering Ubuntu 22.04 VM shell...
echo [*] Ready to execute:
echo       sudo ./scripts/setup_server.sh
echo       ./scripts/verify_all.sh
echo.
wsl -d Ubuntu-22.04 -e bash -c "cd /mnt/c/Users/안재현/Documents/24_code/2609_codyssey/codyssey-b4-01 && exec bash"
