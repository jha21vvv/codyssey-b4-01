@echo off
echo =====================================================================
echo  [Codyssey B4-1] Connecting to WSL2 Ubuntu 22.04 Virtual Lab...
echo =====================================================================

wsl --status >nul 2>&1
if %errorlevel% neq 0 (
    echo [INFO] WSL is not yet enabled. Installing Ubuntu 22.04...
    echo Please run PowerShell as Administrator and execute:
    echo     wsl --install -d Ubuntu-22.04
    pause
    exit /b 1
)

echo [*] Entering Ubuntu 22.04 VM shell...
echo [*] Ready to execute:
echo       sudo ./scripts/setup_server.sh
echo       ./scripts/verify_all.sh
echo.
wsl -d Ubuntu-22.04 -e bash -c "cd /mnt/c/Users/안재현/Documents/24_code/2609_codyssey/codyssey-b4-01 && exec bash"

