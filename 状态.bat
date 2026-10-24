@echo off
chcp 65001 >nul
title Ydisks闲鱼助手 · 状态
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0deploy\status.ps1"
pause