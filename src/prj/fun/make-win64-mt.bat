@echo off
rem Build funcmd-mt.exe, the worker-capable Fun interpreter for win64.
rem
rem This is the default funcmd plus -dFunThreads. It is a separate binary on
rem purpose: the thread-safe runtime costs ordinary scripts throughput. Use
rem funcmd.exe for normal scripts and funcmd-mt.exe for scripts that use
rem lib-worker.
rem
rem Extra arguments are passed through, e.g.:
rem   make-win64-mt.bat -dFunTraceback
setlocal
set FUN_THREADS=1
call "%~dp0make-win64.bat" %*
exit /b %ERRORLEVEL%
