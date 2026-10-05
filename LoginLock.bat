@echo off
chcp 65001 >nul
rem Login Lock - opens the setup terminal. Asks for administrator (UAC).
>nul 2>&1 net session && goto :run
powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
exit /b
:run
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup.ps1"
echo.
pause
exit /b
