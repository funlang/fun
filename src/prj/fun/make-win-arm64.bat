@echo off
rem ============================================================
rem make-win-arm64.bat -- build funcmd.exe for Windows on arm64 (win64/aarch64)
rem
rem FPC 3.2.2 has no win64/aarch64 target. This script therefore needs an
rem FPC 3.3.1 (trunk) aarch64-win64 snapshot. Download
rem fpc-3.3.1.aarch64-win64.built.on.x86_64-linux.tar.gz from
rem   https://downloads.freepascal.org/fpc/snapshot/trunk/aarch64-win64/
rem extract it somewhere, and point FPC_ARM64 at the extracted root (the
rem directory that contains bin\aarch64-win64\fpc.exe). The default below
rem matches the layout .github/workflows/winarm64.yml uses.
rem
rem Optional DLLs are picked up exactly as in make-win64.bat: pcre3.dll
rem enables regex (-dRegex -dPCRE_WinDLL), ffi.dll enables getapi (-dWinFFI).
rem Neither is required; the DLLs must be arm64 builds.
rem
rem Usage:
rem   set FPC_ARM64=C:\FPC\aarch64-win64
rem   make-win-arm64.bat
rem   set SAFE=strict && make-win-arm64.bat      (funcmd-safe.exe)
rem
rem Output: funcmd.exe (or funcmd-safe.exe) in this directory.
rem ============================================================
setlocal enableextensions
cd /d "%~dp0"

if not defined FPC_ARM64 set "FPC_ARM64=%~dp0..\..\..\.fpc\aarch64-win64"
set "dcc=%FPC_ARM64%\bin\aarch64-win64\fpc.exe"
if not exist "%dcc%" (
  echo FPC arm64 compiler not found: "%dcc%" 1>&2
  echo Set FPC_ARM64 to an extracted aarch64-win64 FPC 3.3.1 snapshot. 1>&2
  exit /b 2
)
set "UNITS=%FPC_ARM64%\units\aarch64-win64"
if not exist "%UNITS%\rtl\system.ppu" (
  echo aarch64-win64 RTL units not found under "%UNITS%" 1>&2
  exit /b 2
)

rem -n writes no fpc.cfg lookup; -Fu addresses the snapshot's units directly.
rem -dFunPack matches the release build (the CI win64 job adds it too).
set "FPCOPTS=-n -B -Sd -O2 -Twin64 -Paarch64 -dWin64 -d_B_ -d_C_ -dFunPack -Fu..\..\lib"
set "FPCOPTS=%FPCOPTS% -Fu"%UNITS%\*" -Fu"%UNITS%\rtl""

rem -dMD5 enables str.md5()/str.sha1(): the Windows build takes these from
rem advapi32.dll, and lib-hmac needs sha1, so keep them on like make-win64.bat.
set "HASH=-dMD5"

rem -dFunTraceback records the runtime call ring (default). FUN_TRACEBACK=0
rem builds without the bookkeeping.
set "TRACEBACK=-dFunTraceback"
if /i "%FUN_TRACEBACK%"=="0" set "TRACEBACK="

rem Regex only when pcre3.dll (arm64) sits here; without it -dRegex would fail
rem to link. -dPCRE_WinDLL imports the plain C names from the DLL.
set "REGEX="
if exist pcre3.dll if not defined FUN_NO_REGEX set "REGEX=-dRegex -dPCRE_WinDLL"

rem getapi through FPC's bundled libffi needs ffi.dll (arm64) next to the exe.
set "FFI="
if exist ffi.dll if not defined FUN_NO_FFI set "FFI=-dWinFFI"

rem SAFE=strict|readonly|readwrite|custom builds funcmd-safe.exe with the same
rem capability macros as the POSIX scripts. Unit caches stay separate.
set "SAFE_FLAGS="
set "SAFE_OUT="
set "SAFE_UNITS=-FUunits-arm64"
if not defined SAFE goto :build
if /i "%SAFE%"=="0" goto :build
if /i "%SAFE%"=="no" goto :build
if /i "%SAFE%"=="off" goto :build
if /i "%SAFE%"=="1" goto :safe_strict
if /i "%SAFE%"=="strict" goto :safe_strict
if /i "%SAFE%"=="read" goto :safe_read
if /i "%SAFE%"=="readonly" goto :safe_read
if /i "%SAFE%"=="fs" goto :safe_readwrite
if /i "%SAFE%"=="rw" goto :safe_readwrite
if /i "%SAFE%"=="readwrite" goto :safe_readwrite
if /i "%SAFE%"=="read-write" goto :safe_readwrite
if /i "%SAFE%"=="custom" goto :safe_custom
echo Unknown SAFE='%SAFE%' (use strict, readonly, readwrite or custom). 1>&2
exit /b 2

:safe_strict
set "SAFE_LEVEL=strict"
set "SAFE_ALLOW="
goto :safe_common

:safe_read
set "SAFE_LEVEL=readonly"
set "SAFE_ALLOW=read"
goto :safe_common

:safe_readwrite
set "SAFE_LEVEL=readwrite"
set "SAFE_ALLOW=read,write"
goto :safe_common

:safe_custom
set "SAFE_LEVEL=custom"
set "SAFE_ALLOW=%SAFE_ALLOW%"
goto :safe_common

:safe_common
set "SAFE_FLAGS=-dFunSafe"
set "SAFE_OUT=-ofuncmd-safe.exe"
set "SAFE_UNITS=-FUunits-arm64-safe"
if not exist units-arm64-safe mkdir units-arm64-safe
del /q units-arm64-safe\*.ppu units-arm64-safe\*.o units-arm64-safe\*.or 2>nul
set "ALLOW=%SAFE_ALLOW:,= %"
for %%c in (%ALLOW%) do call :safe_add %%c
if errorlevel 1 exit /b 2
echo SAFE=%SAFE_LEVEL% - building funcmd-safe.exe.
goto :build

:safe_add
if /i "%1"=="read"    set "SAFE_FLAGS=%SAFE_FLAGS% -dFunSafeAllowRead"
if /i "%1"=="write"   set "SAFE_FLAGS=%SAFE_FLAGS% -dFunSafeAllowWrite"
if /i "%1"=="compile" set "SAFE_FLAGS=%SAFE_FLAGS% -dFunSafeAllowCompile"
if /i not "%1"=="read" if /i not "%1"=="write" if /i not "%1"=="compile" (
  echo Unknown SAFE_ALLOW capability '%1' (use read, write, compile). 1>&2
  exit /b 2
)
exit /b 0

:build
if not exist units-arm64 mkdir units-arm64
echo Building with "%dcc%"
"%dcc%" funcmd.dpr %FPCOPTS% %HASH% %TRACEBACK% %REGEX% %FFI% %SAFE_FLAGS% %SAFE_OUT% %SAFE_UNITS%
if errorlevel 1 exit /b %errorlevel%
echo Done.
