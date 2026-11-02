@echo off
call setenv.bat
set dcc=%FPC%\bin\i386-win32\ppcrossarm.exe
%dcc% funcmd.dpr -B -Sd -O2 -Ooregvar -Xs -Twince -dWinCE -dARM -d_B_ -d_C_ -dFunUIx -dWinAPIx -dWinCOMx -Fu..\..\3rd;%FPC%\units\arm-wince %*
