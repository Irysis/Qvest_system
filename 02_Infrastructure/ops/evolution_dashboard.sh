#!/bin/bash
# Self-Evolution Dashboard — 변화 추적
source "$(dirname "${BASH_SOURCE[0]:-$0}")/resolve_project.sh"
cd "$PROJECT"
STATE="/tmp/evo_dashboard_state.json"

while true; do
  ts=$(date '+%H:%M:%S')

  # Collect current stats
  s0_count=$(find 04_Research/strategies/STR_15* -name "s0_record_*.json" 2>/dev/null | wc -l)
  bt_count=$(find 04_Research/strategies/STR_15* -name "performance.csv" -path "*/output/*" 2>/dev/null | wc -l)
  s5_count=$(find 04_Research/strategies/STR_15* -type d -name "output_s5_*" -o -name "output_tight_*" -o -name "output_dd*" 2>/dev/null | wc -l)
  judge_count=$(find 04_Research/strategies/STR_15* -name "judge_result.json" 2>/dev/null | wc -l)
  lc_count=$(grep -c "^### L-" /home/quant/.claude/projects/-mnt-c-Users-User-OneDrive-------Quant-Module-Moltbot/memory/methodology_memory.md 2>/dev/null)
  ce_count=$(find 04_Research/strategies -name "counter_example_*.json" 2>/dev/null | wc -l)

  # Best SR from mutations
  best_sr=$(Rscript --no-save -e '
  library(data.table)
  best <- 0
  for (d in list.dirs("04_Research/strategies", recursive=FALSE)) {
    for (out in list.dirs(d, recursive=FALSE)) {
      if (!grepl("output_s5|output_tight|output_dd", basename(out))) next
      pf <- file.path(out, "performance.csv")
      if (!file.exists(pf)) next
      p <- fread(pf, nrows=1)
      sr <- as.numeric(p$Sharpe[1])
      if (!is.na(sr) && sr > best) best <- sr
    }
  }
  cat(best)
  ' 2>/dev/null)

  # Load previous state
  prev_s0=0; prev_bt=0; prev_s5=0; prev_judge=0; prev_lc=0; prev_ce=0; prev_sr=0
  if [ -f "$STATE" ]; then
    eval $(python3 -c "
import json
d=json.load(open('$STATE'))
for k,v in d.items(): print(f'prev_{k}={v}')
" 2>/dev/null)
  fi

  # Save current state
  python3 -c "
import json
json.dump({'s0':$s0_count,'bt':$bt_count,'s5':$s5_count,'judge':$judge_count,'lc':$lc_count,'ce':$ce_count,'sr':$best_sr}, open('$STATE','w'))
" 2>/dev/null

  # Compute deltas
  d_s0=$((s0_count - prev_s0))
  d_bt=$((bt_count - prev_bt))
  d_s5=$((s5_count - prev_s5))
  d_judge=$((judge_count - prev_judge))
  d_lc=$((lc_count - prev_lc))
  d_ce=$((ce_count - prev_ce))

  # Agent status
  agent_status=""
  for pane in 0 1 2; do
    last=$(tmux capture-pane -t research:0.$pane -p 2>/dev/null | sed 's/\x1b\[[0-9;]*[a-zA-Z]//g' | grep -v "^$" | tail -1)
    if echo "$last" | grep -qE '(bypass|❯|How is)'; then
      status="IDLE"
    elif echo "$last" | grep -qE '(\$|quant@)'; then
      status="DEAD"
    else
      status="WORK"
    fi
    name=$(echo "S F J" | cut -d' ' -f$((pane+1)))
    agent_status="$agent_status $name:$status"
  done

  # Print dashboard
  echo "[$ts]$agent_status | S0:$s0_count(+$d_s0) BT:$bt_count(+$d_bt) S5:$s5_count(+$d_s5) Judge:$judge_count(+$d_judge) LC:$lc_count(+$d_lc) CE:$ce_count(+$d_ce) | BestSR:$best_sr"

  sleep 120
done
