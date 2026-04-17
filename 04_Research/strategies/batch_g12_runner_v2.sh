#!/bin/bash
#==============================================================================
# G12 Batch Runner v2: Shell-based sequential execution
# Each strategy runs as independent Rscript process (avoids setwd issues)
#==============================================================================
echo "[G12 Batch v2] Starting..."

BASE_DIR="/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot/research_output/strategies"
SUMMARY_FILE="/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot/research_output/regime_comparison/output/g12_batch_summary.csv"

echo "STR,Name,Grade,Score,CAGR,Sharpe,MDD" > "$SUMMARY_FILE"

for sid in $(seq 354 372); do
  STR_ID=$(printf "STR_%03d" $sid)
  DIR_NAME=$(ls "$BASE_DIR" | grep "^${STR_ID}_" | head -1)

  if [ -z "$DIR_NAME" ]; then
    echo "  Skip: $STR_ID not found"
    continue
  fi

  STRAT_DIR="$BASE_DIR/$DIR_NAME"
  echo ""
  echo "========== $STR_ID ($DIR_NAME) =========="

  cd "$STRAT_DIR"
  Rscript -e 'source("run_all.R")' 2>&1 | grep -E "(HURDLE|Grade|Score|CAGR|Sharpe|MDD|Complete|ERROR|error|Error)" | head -10

  # Extract from hurdle_result.json if exists
  HURDLE_FILE="$STRAT_DIR/output/hurdle_result.json"
  if [ -f "$HURDLE_FILE" ]; then
    GRADE=$(python3 -c "import json; d=json.load(open('$HURDLE_FILE')); print(d['grade'])" 2>/dev/null)
    SCORE=$(python3 -c "import json; d=json.load(open('$HURDLE_FILE')); print(round(d['total_score'],1))" 2>/dev/null)
    CAGR=$(python3 -c "import json; d=json.load(open('$HURDLE_FILE')); print(round(d['metrics']['ann_ret']*100,1))" 2>/dev/null)
    SHARPE=$(python3 -c "import json; d=json.load(open('$HURDLE_FILE')); print(round(d['metrics']['sharpe'],3))" 2>/dev/null)
    MDD=$(python3 -c "import json; d=json.load(open('$HURDLE_FILE')); print(round(d['metrics']['mdd']*100,1))" 2>/dev/null)
    echo "$STR_ID,$DIR_NAME,$GRADE,$SCORE,$CAGR,$SHARPE,$MDD" >> "$SUMMARY_FILE"
    echo "  Result: Grade=$GRADE Score=$SCORE CAGR=$CAGR% Sharpe=$SHARPE MDD=$MDD%"
  else
    echo "$STR_ID,$DIR_NAME,ERR,NA,NA,NA,NA" >> "$SUMMARY_FILE"
    echo "  No hurdle result found"
  fi
done

echo ""
echo "========== G12 BATCH SUMMARY =========="
cat "$SUMMARY_FILE"
echo ""
echo "[G12 Batch v2] Complete."
