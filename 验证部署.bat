@echo off
chcp 65001 >nul
title Ydisks闲鱼助手 · 部署验证
cd /d "%~dp0"
echo 运行完整验证（30 项）。若已改过管理员密码，请改用命令行加 -Password 参数。
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0deploy\verify.ps1"
pause