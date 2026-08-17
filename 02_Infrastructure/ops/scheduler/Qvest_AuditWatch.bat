@echo off
REM Qvest_AuditWatch - venv deletion audit watcher. Created 2026-08-16.
REM
REM WHY THIS EXISTS:
REM   On 2026-08-16 16:02:11 the .venv_qvest_ml tree was emptied. File System
REM   auditing was OFF at the time, so events 4660/4663 were never written and
REM   the culprit is permanently unknowable. Auditing plus a folder SACL were
REM   then enabled and proven to record (positive control at 17:09:56).
REM   The remaining gap: reading the Security log requires administrator rights,
REM   but boot_currency_check.sh runs as a normal user. This task runs elevated
REM   and distills the answer into .cache/audit_watch_status.json, which the
REM   boot check reads without privilege (axis C11).
REM
REM MUST BE REGISTERED WITH "Run with highest privileges" (elevated).
REM   Without elevation the script still runs but records elevated=false and
REM   verdict=DEGRADED - C11 then reports that the watch is blind rather than
REM   pretending everything is fine. Silence must never read as safety.
REM
REM REGISTER (run once, in an elevated PowerShell - paste the 4 lines directly,
REM   do NOT wrap them in powershell -Command "..." : an outer PowerShell expands
REM   $a/$t/$p to empty strings before the inner one ever sees them. That exact
REM   trap cost a debugging round on 2026-08-16 - the SACL command silently did
REM   nothing and "no events" was misread as "auditing does not work"):
REM
REM   $a = New-ScheduledTaskAction -Execute "C:\Users\99922\OneDrive\Quant_Module_Moltbot\02_Infrastructure\ops\scheduler\Qvest_AuditWatch.bat"
REM   $t = New-ScheduledTaskTrigger -Daily -At 08:00
REM   $p = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -RunLevel Highest -LogonType Interactive
REM   Register-ScheduledTask -TaskName "Qvest_AuditWatch" -Action $a -Trigger $t -Principal $p
REM
REM WHY LogonType Interactive (not S4U): every other Qvest_* task registered on
REM   this machine uses Interactive, and Qvest_BootDataCurrency.bat documents the
REM   reason - this pipeline lives under the user's OneDrive path, which does not
REM   exist in a non-interactive/SYSTEM context. RunLevel Highest is the only
REM   deviation, and it is the whole point: the Security log needs elevation.
REM
REM WINDOW: the script looks back 26h by default, which overlaps the 24h cadence
REM   so a single missed run does not create a blind gap. C11 also fails when the
REM   digest itself goes stale, so a dead task is visible instead of silent.
REM
REM NOTE: keep this .bat ASCII-only - cmd.exe reads it in CP949 and mangles UTF-8.
set QM_ROOT=C:\Users\99922\OneDrive\Quant_Module_Moltbot
if not exist "%QM_ROOT%\.cache\scheduler_logs" mkdir "%QM_ROOT%\.cache\scheduler_logs"
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%QM_ROOT%\02_Infrastructure\ops\audit_watch.ps1" >> "%QM_ROOT%\.cache\scheduler_logs\audit_watch.log" 2>&1
