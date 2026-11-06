@echo off
setlocal enableextensions enabledelayedexpansion
rem ============================================================
rem Fun - safe-build capability regression (Windows)
rem
rem Runs the focused capability test against funcmd-safe.exe, the counterpart
rem of run-safe-regression.sh. The default and safe modes are separate binaries;
rem this script never builds anything.
rem
rem Usage, from the repository root:
rem   fun\test\run-safe-regression.bat strict
rem   fun\test\run-safe-regression.bat readonly
rem   set FUNCMD=...\funcmd-safe.exe && fun\test\run-safe-regression.bat strict
rem ============================================================

set "MODE=%~1"
if not defined MODE set "MODE=strict"
if /i "%MODE%"=="strict" goto :strict
if /i "%MODE%"=="readonly" goto :readonly
echo usage: %~nx0 [strict^|readonly] 1>&2
exit /b 2

:strict
set "TESTNAME=safe-mode-test.fun"
goto :mode_ready
:readonly
set "TESTNAME=safe-readonly-test.fun"
goto :mode_ready

:mode_ready
set "HERE=%~dp0"
pushd "%HERE%..\.." 2>nul
if errorlevel 1 ( echo cannot enter the repository root 1>&2 & exit /b 2 )

if defined FUNCMD if exist "%FUNCMD%" goto :have_cmd
set "FUNCMD=src\prj\fun\funcmd-safe.exe"
if exist "%FUNCMD%" goto :have_cmd
set "FUNCMD=fun\funcmd-safe.exe"
if exist "%FUNCMD%" goto :have_cmd
set "FUNCMD=fun\fun-safe.exe"
if exist "%FUNCMD%" goto :have_cmd
echo funcmd-safe.exe not found. Build it first: 1>&2
echo   cd src\prj\fun ^&^& set SAFE=strict ^&^& make-win64.bat 1>&2
popd & exit /b 2

:have_cmd
echo safe mode: %MODE%
echo safe binary: %FUNCMD%
set "OUTFILE=%TEMP%\fun-safe-%RANDOM%.out"
"%FUNCMD%" "fun\test\%TESTNAME%" > "%OUTFILE%" 2>&1
set "RC=%ERRORLEVEL%"
type "%OUTFILE%"

if not "%RC%"=="0" (
    echo safe regression: interpreter exited %RC% 1>&2
    del "%OUTFILE%" >nul 2>&1
    popd & exit /b 1
)

rem The runner prints "# tests: N passed: P failed: F [skipped: S] [todo: T]".
set "SUMMARY="
for /f "usebackq delims=" %%l in ("%OUTFILE%") do set "SUMMARY=%%l"
del "%OUTFILE%" >nul 2>&1

echo %SUMMARY% | findstr /c:"failed: 0" >nul
if errorlevel 1 (
    echo safe regression: no clean summary ^(got: %SUMMARY%^) 1>&2
    popd & exit /b 1
)

rem Parse "# tests: N passed: P failed: F skipped: S todo: T" so an
rem accidentally empty run cannot pass.
set "TOTAL="
set "FAILED="
set "SKIPPED="
set "TODO="
for /f "tokens=1-11 delims=: " %%a in ("%SUMMARY%") do (
    set "TOTAL=%%c"
    set "FAILED=%%g"
    set "SKIPPED=%%i"
    set "TODO=%%k"
)
if not defined TOTAL (
    echo safe regression: could not read the test count ^(got: %SUMMARY%^) 1>&2
    popd & exit /b 1
)
if not defined FAILED set "FAILED=0"
if not defined SKIPPED set "SKIPPED=0"
if not defined TODO set "TODO=0"
if %TOTAL% LSS 5 (
    echo safe regression: expected at least 5 tests, got %TOTAL% 1>&2
    popd & exit /b 1
)

set /a PASSED=TOTAL-SKIPPED-TODO
set "MSG=safe regression: %PASSED%/%TOTAL% passed"
if %SKIPPED% GTR 0 set "MSG=%MSG%, %SKIPPED% skipped"
if %TODO% GTR 0 set "MSG=%MSG%, %TODO% todo"
if %SKIPPED% GTR 0 goto :safe_counts
if %TODO% GTR 0 goto :safe_counts
echo safe regression: %TOTAL% tests passed
goto :safe_done
:safe_counts
echo %MSG%
:safe_done
popd
exit /b 0
