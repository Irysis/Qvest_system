# DPL diversified-panel GPU sweep launcher (WT_DPL_ALPHASEARCH2)
# Panel: WT_DPL_C2 98-feature (90f base + RESIDMOM/PIOTROSKI/MOHANRAM/NETISSUE), PIT-passed.
# Grid focus: extend gamma upward (TO<=11) + L2/dropout regularization (over-fit control).
# NOTE: do NOT set ErrorActionPreference=Stop — native python stderr (numpy FutureWarning)
#       would be wrapped as NativeCommandError and abort the script before the sweep runs (PS 5.1).
$env:CLAUDE_PROJECT_DIR = "G:/Quant_Module_Moltbot"
$env:PYTHONUTF8 = "1"
$env:PYTHONWARNINGS = "ignore"
$env:DPL_OUT_DIR = "G:/Quant_Module_Moltbot/stage_artifacts/WT_DPL_ALPHASEARCH2"
# Focused grid: gamma extended high (primary TO lever) + temp (EW-ization) + regularization.
# depth=3/width=64 fixed (prior 8f best architecture). 3*2*2*2*2*2 = 96 cells (honest n_trials).
$env:DPL_GRID = '{"gamma":[2.0,4.0,7.0],"temp":[0.7,1.5],"dropout":[0.1,0.3],"l2":[0.001,0.005],"lookback":[72,120],"lam":[0.0,0.3],"depth":[3],"width":[64]}'
$log = "G:/Quant_Module_Moltbot/stage_artifacts/WT_DPL_ALPHASEARCH2/sweep_run.log"
"=== DPL ALPHASEARCH2 sweep start $(Get-Date -Format o) ===" | Out-File -FilePath $log -Encoding utf8
"GRID: $env:DPL_GRID" | Out-File -FilePath $log -Append -Encoding utf8
# Run python via cmd.exe so stdout+stderr both append to the log as plain text (avoids PS
# NativeCommandError stderr-wrapping). cmd 2>&1 merges streams at the OS level.
$py = "G:/Quant_Module_Moltbot/.venv_qvest_ml/Scripts/python.exe"
$script = "G:/Quant_Module_Moltbot/02_Infrastructure/ml_pipeline/dpl_gpu_sweep.py"
& cmd.exe /c "`"$py`" `"$script`" >> `"$log`" 2>&1"
$ec = $LASTEXITCODE
"=== DPL ALPHASEARCH2 sweep DONE $(Get-Date -Format o) exit=$ec ===" | Out-File -FilePath $log -Append -Encoding utf8
