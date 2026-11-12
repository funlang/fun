@echo off
call setenv.bat
set dcc=%DELPHI2006%\bin\dcc32
rem -DFunTraceback records the runtime call ring (default). Set
rem FUN_TRACEBACK=0 to build without the bookkeeping.
set "TRACEBACK=-DFunTraceback"
if /i "%FUN_TRACEBACK%"=="0" set "TRACEBACK="
%dcc% funcmd -B -Q -GD -$D+ %TRACEBACK% %*
