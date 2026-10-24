@echo off
chcp 65001 >nul
title Ydisks闲鱼助手 · 停止
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0deploy\stop.ps1"
pause