# DPL best-cell single-config rerun (WT_DPL_ALPHASEARCH2)
# Purpose: lite 6-cell sweep died on cell 5/6 -> never reached export -> dpl_best_net_returns.parquet missing.
# Re-run the WINNING config as a single cell so the export block writes the best net-return series parquet.
# Best cell (sweep_progress.jsonl cell 1 = log cell 2/6): gamma2.0 / dropout0.3 / l2 1e-3 / temp0.7 /
#   lookback72 / lam0 / depth3 / width64 / epochs25  -> net active SR 0.512, subMin +0.189, TO 15.35.
# n_trials for DSR handled separately (honest sweep size = 6) via dpl_best_dsr_carhart.py.
# python -u (UNBUFFERED) -> live progress; checkpoint -> sweep_progress_best.jsonl (no overwrite of 6-cell ckpt).
$env:CLAUDE_PROJECT_DIR = "G:/Quant_Module_Moltbot"
$env:PYTHONUTF8 = "1"
$env:PYTHONWARNINGS = "ignore"
$env:DPL_OUT_DIR = "G:/Quant_Module_Moltbot/stage_artifacts/WT_DPL_ALPHASEARCH2"
# Single best config: all axes single-valued -> 1 cell -> best == this cell -> export fires.
$env:DPL_GRID = '{"gamma":[2.0],"dropout":[0.3],"l2":[0.001],"temp":[0.7],"lookback":[72],"lam":[0.0],"depth":[3],"width":[64],"epochs":[25]}'
$log = "G:/Quant_Module_Moltbot/stage_artifacts/WT_DPL_ALPHASEARCH2/best_cell_run.log"
"=== DPL ALPHASEARCH2 BEST-CELL rerun start $(Get-Date -Format o) ===" | Out-File -FilePath $log -Encoding utf8
"GRID: $env:DPL_GRID" | Out-File -FilePath $log -Append -Encoding utf8
# cmd.exe /c so stdout+stderr merge at OS level (avoid PS 5.1 NativeCommandError stderr-wrapping). -u unbuffered.
$py = "G:/Quant_Module_Moltbot/.venv_qvest_ml/Scripts/python.exe"
$script = "G:/Quant_Module_Moltbot/02_Infrastructure/ml_pipeline/dpl_gpu_sweep.py"
& cmd.exe /c "`"$py`" -u `"$script`" >> `"$log`" 2>&1"
$ec = $LASTEXITCODE
"=== DPL ALPHASEARCH2 BEST-CELL rerun DONE $(Get-Date -Format o) exit=$ec ===" | Out-File -FilePath $log -Append -Encoding utf8
