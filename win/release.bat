@echo off
chcp 65001 >nul
set VERSION=%1
if "%VERSION%"=="" set VERSION=2026.10.1
powershell -ExecutionPolicy Bypass -File "%~dp0release.ps1" -Version "%VERSION%"
pause
