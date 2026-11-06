@echo off
rem Qvest_StressDaily - Task Scheduler entry point (same shape as 02_Infrastructure\ops\scheduler\*.bat).
rem ASCII only: cmd.exe mis-reads batch files that contain multi-byte text (offsets drift, lines get garbled).
rem Machine-independent: paths are relative to this file; QM_ROOT comes from the user environment (fallback = 4 levels up).
rem Registration = ops\README.md. The real work is run_daily_stress_task.sh (wait for refresh lock -> run_daily_stress.sh).
setlocal
set "HERE=%~dp0"
set "HERE_U=%HERE:\=/%"
if not defined QM_ROOT for %%I in ("%HERE%..\..\..\..") do set "QM_ROOT=%%~fI"
set "ROOT_U=%QM_ROOT:\=/%"
set "GITBASH=%ProgramFiles%\Git\bin\bash.exe"
if not exist "%GITBASH%" set "GITBASH=%ProgramW6432%\Git\bin\bash.exe"
if not exist "%GITBASH%" set "GITBASH=%LOCALAPPDATA%\Programs\Git\bin\bash.exe"
if not exist "%GITBASH%" (
  echo [Qvest_StressDaily] Git Bash not found: %ProgramFiles%\Git\bin\bash.exe
  exit /b 9
)
if not exist "%QM_ROOT%\.cache\scheduler_logs" mkdir "%QM_ROOT%\.cache\scheduler_logs"
"%GITBASH%" -c "export PATH='/c/Program Files/R/R-4.5.2/bin:'$PATH; export CLAUDE_PROJECT_DIR='%ROOT_U%'; export QM_ROOT='%ROOT_U%'; export QVEST_UNATTENDED=1; export PYTHONUTF8=1; bash '%HERE_U%run_daily_stress_task.sh' >> '%ROOT_U%/.cache/scheduler_logs/stress_daily.log' 2>&1"
exit /b %ERRORLEVEL%
