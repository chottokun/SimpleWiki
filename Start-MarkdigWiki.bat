@echo off
cd /d "%~dp0"
if "%~1"=="" (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Start-MarkdigWiki.ps1"
) else (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Start-MarkdigWiki.ps1" -RootFolder "%~1"
)
