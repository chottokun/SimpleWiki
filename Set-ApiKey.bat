@echo off
chcp 65001 > NUL
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Set-ApiKey.ps1" %*
