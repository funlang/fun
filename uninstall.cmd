@echo off
setlocal enableextensions
rem ============================================================
rem Fun for Windows -- uninstaller.
rem
rem Double-click from the install directory, or pass -AllUsers for an
rem all-users install. Options are passed to uninstall.ps1:
rem   uninstall.cmd -AllUsers
rem   uninstall.cmd -KeepFiles      keep the files, remove registry/PATH
rem   uninstall.cmd -Force          delete even if the folder does not look
rem                                 like a Fun install
rem ============================================================

rem Do not keep the current directory inside the tree being deleted.
cd /d "%TEMP%" >nul 2>&1

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0uninstall.ps1" -Dir "%~dp0." %*
set "RC=%ERRORLEVEL%"

if not "%RC%"=="0" (
    echo.
    echo Fun uninstall failed. Review the messages above.
    pause
    exit /b %RC%
)

if "%~1"=="" (
    echo.
    pause
)
exit /b 0
