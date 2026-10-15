@echo off
call setenv.bat
set dcc=%FPC%\bin\i386-win32\ppcrossx64.exe
rem -dWinAPI is intentionally absent: winapi.pas getapi() is 32-bit x86 stack
rem asm (esp-relative args) and does not compile for x86_64. Add it back only
rem together with an x64 getapi. -dWinCE/-dARM were spurious here too: -dWinCE
rem made 'host'.arg() report the OS as 'wince' on a Win64 build.
rem -Fu..\..\lib: funcmd.dpr lists host with an explicit `in` path, but units
rem that host pulls in itself (lffi, under -dWinFFI) need the lib dir here.
%dcc% funcmd.dpr -B -Sd -O2 -Ooregvar -Xs -Twin64 -dWin64 -d_B_ -d_C_ -dWinCOMx -dRegexx -Fu..\..\lib
