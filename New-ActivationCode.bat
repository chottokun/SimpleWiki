@echo off
chcp 65001 > NUL
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0New-ActivationCode.ps1" %*
if %ERRORLEVEL% NEQ 0 (
    echo.
    pause
)
