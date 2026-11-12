@echo off
call setenv.bat
set dcc=%FPC%\bin\i386-win32\ppcrossx64.exe
rem -dWinAPI is intentionally absent: winapi.pas getapi() is 32-bit x86 stack
rem asm (esp-relative args) and does not compile for x86_64. getapi is instead
rem reached through the libffi-backed lffi unit: add -dWinFFI and put ffi.dll
rem (MSYS2 mingw-w64-x86_64-libffi) next to funcmd.exe - that is what the CI
rem does; without the DLL the flag only breaks the link. -dWinCE/-dARM were
rem spurious here too: -dWinCE
rem made 'host'.arg() report the OS as 'wince' on a Win64 build.
rem -Fu..\..\lib: funcmd.dpr lists host with an explicit `in` path, but units
rem that host pulls in itself (lffi, under -dWinFFI) need the lib dir here.
rem Regex: -dRegexx here was a typo that enabled nothing. win64 does support
rem regex when pcre3.dll sits next to funcmd.exe (CI builds it; see the PCRE
rem step in .github/workflows/regression.yml). -dPCRE_WinDLL imports the DLL,
rem so no bcc32 objects or MinGW CRT are needed. Without the DLL, skip it.
set "REGEX="
if exist pcre3.dll set "REGEX=-dRegex -dPCRE_WinDLL"

rem -dMD5 enables the str.md5()/str.sha1() builtins. On Windows src/libmd5.inc
rem wraps advapi32.dll (the 32-bit IDE build has always defined MD5 in
rem funcmd.cfg/funcmd.dof); the ABI is unchanged on win64. lib-hmac.fun and the
rem RFC 2202 vectors in lib-hmac-test.fun need sha1, so keep this on.
set "HASH=-dMD5"

rem -dFunTraceback records the runtime call ring (default). Set
rem FUN_TRACEBACK=0 to build without the bookkeeping.
set "TRACEBACK=-dFunTraceback"
if /i "%FUN_TRACEBACK%"=="0" set "TRACEBACK="

rem getapi uses FPC's bundled libffi on win64 (lffi.pas), which needs ffi.dll
rem next to funcmd.exe. Enable it only when the DLL is actually there; a bare
rem -dWinFFI without the library fails to link. CI builds ffi.dll from MSYS2.
set "FFI="
if exist ffi.dll set "FFI=-dWinFFI"

rem The 64-bit runtime DLLs are not the 32-bit copies from an old release:
rem   CC=x86_64-w64-mingw32-gcc sh build-win64-deps.sh
rem puts x86_64 libtcc.dll and zlib.dll here (see that script).

rem SAFE=strict|readonly|readwrite|custom builds funcmd-safe.exe with the same
rem compile-time macros as the POSIX scripts (SAFE_ALLOW=read,write,compile for
rem custom). The unit cache is separate (units-safe) so the two modes cannot
rem reuse each other's .ppu files. Use 'set SAFE=...' before calling this file;
rem 'set SAFE=' or 'set SAFE=0' builds the normal interpreter.
set "SAFE_FLAGS="
set "SAFE_OUT="
set "SAFE_UNITS="
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
set "SAFE_UNITS=-FUunits-safe"
if not exist units-safe mkdir units-safe
del /q units-safe\*.ppu units-safe\*.o units-safe\*.or 2>nul
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
%dcc% funcmd.dpr -B -Sd -O2 -Ooregvar -Xs -Twin64 -dWin64 -d_B_ -d_C_ -dWinCOMx %HASH% %TRACEBACK% %REGEX% %FFI% %SAFE_FLAGS% %SAFE_OUT% %SAFE_UNITS% -Fu..\..\lib
