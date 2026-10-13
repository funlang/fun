@echo off
setlocal enableextensions enabledelayedexpansion
rem ============================================================
rem Fun - Windows regression runner (counterpart of run-linux-regression.sh)
rem
rem Usage, from the repository root:
rem   fun\test\run-windows-regression.bat               compare vs snapshots
rem   fun\test\run-windows-regression.bat --update      (re)write snapshots
rem   fun\test\run-windows-regression.bat --list        show the test list
rem   fun\test\run-windows-regression.bat --portable    host-independent subset only
rem   fun\test\run-windows-regression.bat --loadcheck   which stdlib modules load here
rem
rem Environment overrides:
rem   FUNCMD=...           path to funcmd.exe (default: src\prj\fun\funcmd.exe)
rem   FUNREG_EXPECTED=... snapshot dir      (default: fun\test\expected)
rem
rem The test list lives in fun\test\regression-list.txt, which the shell runner
rem reads too, so the two stay in sync.
rem   snap  - output must match the .txt byte for byte (fc /b)
rem   smoke - only exit code 0 and no crash markers
rem   shell - SKIPPED (lib-loadcheck.sh / run-benchmarks.sh need POSIX sh;
rem           --loadcheck below covers the module-load part natively)
rem --portable skips the entries whose output is host-dependent (paths, dll/.so,
rem   'host'.arg(), the -lnx backends): exactly the set worth diffing against a
rem   Linux snapshot. To build a Windows baseline to diff:
rem       set FUNREG_EXPECTED=fun\test\expected-win
rem       fun\test\run-windows-regression.bat --update
rem   then compare fun\test\expected-win\*.txt with fun\test\expected\*.txt.
rem ============================================================

set "HERE=%~dp0"
pushd "%HERE%..\.." 2>nul
if errorlevel 1 ( echo cannot enter the repository root 1>&2 & exit /b 2 )

if not defined FUNREG_EXPECTED set "FUNREG_EXPECTED=fun\test\expected"
set "EXPECTED=%FUNREG_EXPECTED%"
set "LISTFILE=fun\test\regression-list.txt"
if not exist "%LISTFILE%" ( echo missing %LISTFILE% 1>&2 & popd & exit /b 2 )

rem Tests whose output is host-dependent (see the shell runner header).
set "HOSTDEP= builtin-dispatch.fun lib-host-test.fun lib-param-linux.fun lib-cmdline-linux.fun lib-loadcheck.sh libc-outbuf.fun ptr-primitives.fun raw-address-getapi.fun lib-tcc-test.fun lib-jit-test.fun lib-asm-lnx.fun fractal-asm-x64.fun lib-hash-test.fun lib-proc-test.fun lib-unicode-test.fun run-benchmarks.sh "

set "MODE=compare"
set "PORTABLE=0"
:parse
if "%~1"=="" goto parsed
if /i "%~1"=="--update"    set "MODE=update"
if /i "%~1"=="--list"      set "MODE=list"
if /i "%~1"=="--portable" set "PORTABLE=1"
if /i "%~1"=="--loadcheck" set "MODE=loadcheck"
shift
goto parse
:parsed

if defined FUNCMD if exist "%FUNCMD%" goto findcmd
set "FUNCMD=src\prj\fun\funcmd.exe"
if exist "%FUNCMD%" goto findcmd
set "FUNCMD=src\prj\fun\fun.exe"
if exist "%FUNCMD%" goto findcmd
set "FUNCMD=bin\funcmd.exe"
if exist "%FUNCMD%" goto findcmd
set "FUNCMD=funcmd.exe"
if exist "%FUNCMD%" goto findcmd
echo funcmd.exe not found. Set FUNCMD=... to its path. 1>&2
popd & exit /b 2
:findcmd

if /i "%MODE%"=="list"      goto listmode
if /i "%MODE%"=="loadcheck" goto loadcheck

if not exist "%EXPECTED%" mkdir "%EXPECTED%" >nul 2>&1
set "FAIL=0"
set "TOTAL=0"
set "SKIP=0"
set "FAILED="
echo TEST                     RESULT
echo ------------------------ ------
for /f "usebackq tokens=1,2,3" %%a in ("%LISTFILE%") do call :one "%%a" "%%b" "%%c"
goto summary

rem --------------------------------------------------------------- one test
:one
set "name=%~1"
set "script=%~2"
set "tmode=%~3"
if /i "%tmode%"=="shell" goto skip_shell
if "%PORTABLE%"=="1" (
  echo !HOSTDEP! | findstr /i /c:" %name% " >nul
  if not errorlevel 1 goto skip_host
)
set "OUT=%TEMP%\funreg-%name%.out"
"%FUNCMD%" "fun\%script%" > "%OUT%" 2>&1
set "rc=!errorlevel!"
set /a TOTAL+=1

if /i "%tmode%"=="smoke" goto smoke
if /i "%MODE%"=="update" goto snap_update
if not "!rc!"=="0" ( set "result=FAIL(rc=!rc!)" & goto report )
if not exist "%EXPECTED%\%name%.txt" ( set "result=FAIL(no snapshot; run --update)" & goto report )
fc /b "%OUT%" "%EXPECTED%\%name%.txt" >nul 2>&1
if errorlevel 1 ( set "result=FAIL(output differs)" ) else ( set "result=PASS" )
goto report

:smoke
if not "!rc!"=="0" ( set "result=FAIL(rc=!rc!)" & goto report )
findstr /i /c:"access violation" /c:"syntax error" /c:"stack overflow" /c:"runtime error" "%OUT%" >nul 2>&1
if not errorlevel 1 ( set "result=FAIL(crash marker)" ) else ( set "result=PASS" )
goto report

:snap_update
copy /y "%OUT%" "%EXPECTED%\%name%.txt" >nul
set "result=SNAPSHOT"
goto report

:report
if "!result:~0,4!"=="FAIL" (
  set /a FAIL+=1
  set "FAILED=!FAILED! %name%"
  echo %name%   !result!
  echo     got: %OUT%
  echo     exp: %EXPECTED%\%name%.txt
  call :showdiff "%OUT%" "%EXPECTED%\%name%.txt"
) else (
  echo %name%   !result!
)
exit /b 0

:skip_shell
echo %name%   SKIP (needs sh)
set /a SKIP+=1
exit /b 0

:skip_host
echo %name%   SKIP (host-dependent)
set /a SKIP+=1
exit /b 0

:showdiff
set /a dn=0
for /f "usebackq delims=" %%D in (`fc "%~1" "%~2" 2^>^&1`) do (
  set /a dn+=1
  if !dn! leq 20 echo     ^| %%D
)
exit /b 0

rem --------------------------------------------------------------- summary
:summary
echo.
set /a PASSED=TOTAL-FAIL
echo !PASSED!/%TOTAL% checks passed ^(skipped !SKIP!^)
if not "%FAIL%"=="0" (
  echo failed:!FAILED!
  popd
  exit /b 1
)
popd
exit /b 0

rem --------------------------------------------------------------- modes
:listmode
for /f "usebackq tokens=1,2,3" %%a in ("%LISTFILE%") do echo   fun\%%b   %%c
popd
exit /b 0

:loadcheck
set "OK=0"
set "BAD=0"
for %%F in (fun\lib\*.fun) do (
  set "n=%%~nF"
  if "!n!"=="!n:-lnx=!" if /i not "!n!"=="lib-unicode-base" (
    >"fun\test\.loadcheck-one.fun" echo use 'fun/lib/!n!.fun';
    >>"fun\test\.loadcheck-one.fun" echo ?. 'loaded';
    "%FUNCMD%" "fun\test\.loadcheck-one.fun" > "%TEMP%\funreg-load.out" 2>&1
    findstr /x /c:"loaded" "%TEMP%\funreg-load.out" >nul 2>&1
    if errorlevel 1 (
      set /a BAD+=1
      echo FAIL !n!
    ) else (
      set /a OK+=1
      echo LOAD !n!
    )
  )
)
del "fun\test\.loadcheck-one.fun" >nul 2>&1
echo.
echo loaded=!OK! failed=!BAD!
popd
exit /b 0
