@echo off
chcp 65001 >nul
setlocal
title PCL 2.99.0.0 恢复原版
echo PCL 2.99.0.0 恢复原版
echo.
if "%~1"=="" (
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Patch-PCL.ps1" -Restore <nul
) else (
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Patch-PCL.ps1" -TargetExe "%~1" -Restore <nul
)
set "patchExit=%errorlevel%"
echo.
echo 按任意键关闭窗口...
pause >nul
exit /b %patchExit%
