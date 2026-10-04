@echo off
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0Manage-Installer.ps1" -Action Install
set "installer_exit=%errorlevel%"
pause
exit /b %installer_exit%
