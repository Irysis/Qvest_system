# DPL diversified-panel GPU sweep — LITE relaunch (WT_DPL_ALPHASEARCH2)
# Panel: WT_DPL_C2 98-feature (90f base + RESIDMOM/PIOTROSKI/MOHANRAM/NETISSUE), PIT-passed. REUSED (no rebuild).
# Death history: 256-cell killed, then 96-cell (98f, gamma high) died ~1.5h with sweep_run.log holding
#   only start+GRID (block-buffered python stdout never flushed; no per-cell checkpoint -> total loss).
# LITE fix (도훈 "완주 최우선"):
#   - 6 cells: gamma[2,4,7] x dropout[0.1,0.3]; l2=1e-3 temp=0.7 lookback=72 lam=0 depth=3 width=64.
#   - epochs 40 -> 25.
#   - python -u (UNBUFFERED) -> [sweep] progress flushes live to log; see exactly which cell/stage if it dies.
#   - per-cell checkpoint sweep_progress.jsonl (appended on each cell DONE) -> crash never loses completed cells.
#   - torch.cuda.empty_cache() between cells -> OOM guard.
# NOTE: do NOT set ErrorActionPreference=Stop — native python stderr (numpy FutureWarning)
#       would be wrapped as NativeCommandError and abort the script before the sweep runs (PS 5.1).
$env:CLAUDE_PROJECT_DIR = "G:/Quant_Module_Moltbot"
$env:PYTHONUTF8 = "1"
$env:PYTHONWARNINGS = "ignore"
$env:DPL_OUT_DIR = "G:/Quant_Module_Moltbot/stage_artifacts/WT_DPL_ALPHASEARCH2"
# Lite grid: gamma extended high (primary TO lever, prior best gamma0.1/TO22 -> push TO down) x dropout.
# 3 * 2 = 6 cells (honest n_trials). Other axes single-valued (fixed) per 도훈 spec.
$env:DPL_GRID = '{"gamma":[2.0,4.0,7.0],"dropout":[0.1,0.3],"l2":[0.001],"temp":[0.7],"lookback":[72],"lam":[0.0],"depth":[3],"width":[64],"epochs":[25]}'
$log = "G:/Quant_Module_Moltbot/stage_artifacts/WT_DPL_ALPHASEARCH2/sweep_lite_run.log"
"=== DPL ALPHASEARCH2 LITE sweep start $(Get-Date -Format o) ===" | Out-File -FilePath $log -Encoding utf8
"GRID: $env:DPL_GRID" | Out-File -FilePath $log -Append -Encoding utf8
# Run python -u via cmd.exe so stdout+stderr both append to the log as plain text (avoids PS
# NativeCommandError stderr-wrapping). cmd 2>&1 merges streams at the OS level. -u = unbuffered.
$py = "G:/Quant_Module_Moltbot/.venv_qvest_ml/Scripts/python.exe"
$script = "G:/Quant_Module_Moltbot/02_Infrastructure/ml_pipeline/dpl_gpu_sweep.py"
& cmd.exe /c "`"$py`" -u `"$script`" >> `"$log`" 2>&1"
$ec = $LASTEXITCODE
"=== DPL ALPHASEARCH2 LITE sweep DONE $(Get-Date -Format o) exit=$ec ===" | Out-File -FilePath $log -Append -Encoding utf8
