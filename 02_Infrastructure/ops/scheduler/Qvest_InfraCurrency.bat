@echo off
REM Qvest_InfraCurrency - daily infrastructure version check (R, Rtools, Python, venv, system Python, R packages) - every machine
REM 2026-11-08 new (dohoon: "check R / Python versions and packages at boot so the infrastructure can be kept up to date")
REM
REM What it does (infra_currency.py - its header has the full contract): read-only. Compares installed R / Rtools / Python
REM   with the official latest (CRAN VERSION-INFO.dcf, CRAN Rtools page, python.org API), counts upgradable packages
REM   (pip dry-run resolution - packages held by dependency caps are reported as held; R old.packages type=binary) and
REM   lists versions pinned by open (registered) research rounds. Writes .cache\machine\infra_currency_<HOST>.json,
REM   which boot_lean.sh turns into the "Infra:" boot line. Updating is NOT done here (infra_update.py / env_upgrade PLAN.md).
REM period local (machines.conf): each machine checks its own installs - no main-priority gate.
REM rc: 0 = recorded (being behind is still 0) - 2 = could not write the record.
REM Log: .cache\scheduler_logs\infra_currency_<HOST>.log (one SUMMARY line per run).  Test: python 08_Tests/ops/test_infra_currency.py
REM
REM REGISTER (once per machine, normal PowerShell in the project folder):
REM   powershell -NoProfile -ExecutionPolicy Bypass -File 02_Infrastructure\ops\machine\qvest_tasks.ps1 -Mode Apply -From 02_Infrastructure\ops\scheduler\_task_xml_backup -Name Qvest_InfraCurrency
REM
REM NOTE: keep this .bat ASCII-only - cmd.exe reads it in CP949 and mangles UTF-8.
"C:\Program Files\Git\bin\bash.exe" "C:/Users/99922/OneDrive/Quant_Module_Moltbot/02_Infrastructure/ops/infra_currency_run.sh"
