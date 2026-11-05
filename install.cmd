@echo off
setlocal enableextensions
rem ============================================================
rem Fun for Windows -- double-click installer.
rem
rem Extracts nothing: run this from the extracted release folder, next to
rem fun\fun.exe. The default install is per-user:
rem
rem   %LOCALAPPDATA%\Programs\Fun      files
rem   user PATH                        <install>\fun
rem   HKCU\Software\Classes            .fun .foo .fxx associations
rem
rem Options are passed to install.ps1:
rem   install.cmd -AllUsers            elevated install under Program Files
rem   install.cmd -Dir D:\Fun          custom location
rem   install.cmd -NoAssoc             skip file associations
rem   install.cmd -NoPath              skip PATH
rem   install.cmd -Portable            no registry or PATH changes
rem ============================================================

set "HERE=%~dp0"

rem Leave the extraction tree: it may be the upgrade target or be deleted by
rem the uninstaller.
cd /d "%TEMP%" >nul 2>&1

rem A browser download marks the archive. Clear the marker on the extracted
rem scripts so SmartScreen/ExecutionPolicy does not block this run.
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "Get-ChildItem -LiteralPath '%HERE%' -Recurse -File -ErrorAction SilentlyContinue | Unblock-File -ErrorAction SilentlyContinue" >nul 2>&1

powershell -NoProfile -ExecutionPolicy Bypass -File "%HERE%install.ps1" %*
set "RC=%ERRORLEVEL%"

if not "%RC%"=="0" (
    echo.
    echo Fun installation failed. Review the messages above.
    pause
    exit /b %RC%
)

if "%~1"=="" (
    echo.
    pause
)
exit /b 0
