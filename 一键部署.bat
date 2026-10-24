@echo off
chcp 65001 >nul
title Ydisks闲鱼助手 · 一键部署
cd /d "%~dp0"

echo ============================================================
echo  Ydisks闲鱼助手 · Windows 本地一键部署
echo  ------------------------------------------------------------
echo   1. 检查前置条件（Git / Node.js 24+）
echo   2. 下载便携 Go 工具链（约 72 MB）
echo   3. 克隆上游源码
echo   4. 构建前端与 Go 可执行文件
echo   5. 下载 Chromium 运行时（约 700 MB，首次较慢）
echo   6. 初始化管理员并启动服务
echo ============================================================
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0deploy\bootstrap.ps1"
set RC=%ERRORLEVEL%

echo.
if %RC% neq 0 (
  echo [x] 部署失败，详见 logs\ 目录下的 bootstrap 日志
) else (
  echo [√] 部署完成
)
pause
exit /b %RC%