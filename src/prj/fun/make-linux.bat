@echo off
call setenv.bat
set dcc=%FPC%\bin\i386-win32\ppc386
%dcc% funcmd.dpr -B -Sd -O2 -Ooregvar -Xs -Tlinux -dLinux -Fu%FPC%\units\i386-linux %*
