@echo off
chcp 65001 >nul
set VERSION=%1
if "%VERSION%"=="" (
    powershell -ExecutionPolicy Bypass -File "%~dp0release.ps1"
) else (
    powershell -ExecutionPolicy Bypass -File "%~dp0release.ps1" -Version "%VERSION%"
)
pause
