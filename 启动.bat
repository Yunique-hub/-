@echo off
chcp 65001 >nul
title Ydisks闲鱼助手 · 启动
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0deploy\start.ps1"
if %ERRORLEVEL% neq 0 pause