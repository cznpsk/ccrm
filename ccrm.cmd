@echo off
chcp 65001 >nul
if "%~1"=="update" (
  powershell -NoProfile -ExecutionPolicy Bypass -Command "irm ('https://github.com/cznpsk/ccrm/releases/latest/download/install.ps1?ts=' + [DateTimeOffset]::Now.ToUnixTimeSeconds()) | iex"
  exit /b
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0ccrm-core.ps1" %*
