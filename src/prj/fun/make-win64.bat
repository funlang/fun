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
%dcc% funcmd.dpr -B -Sd -O2 -Ooregvar -Xs -Twin64 -dWin64 -d_B_ -d_C_ -dWinCOMx %REGEX% -Fu..\..\lib
