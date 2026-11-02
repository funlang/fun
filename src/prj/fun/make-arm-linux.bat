@echo off
call setenv.bat
set dcc=%FPC%\bin\i386-win32\ppcrossarm.exe
%dcc% funcmd.dpr -B -Sd -O2 -Ooregvar -Xs -Tlinux -dLinux -dARM -Fu%FPC%\units\arm-linux %*
