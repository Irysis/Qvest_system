#!/bin/sh
ROOT="C:/Users/99922/OneDrive/Quant_Module_Moltbot"
BM="$ROOT/.cache/benchmark.parquet"
RD="$ROOT/.cache/RAWDATA.parquet"
i=0
while [ $i -lt 180 ]; do
  if [ -f "$BM" ]; then
    m1=$(stat -c %Y "$RD" 2>/dev/null); b1=$(stat -c %Y "$BM" 2>/dev/null)
    sleep 10
    m2=$(stat -c %Y "$RD" 2>/dev/null); b2=$(stat -c %Y "$BM" 2>/dev/null)
    if [ "$m1" = "$m2" ] && [ "$b1" = "$b2" ]; then
      echo "[wait] cache stable after $((i*10))s — launching"
      break
    fi
  fi
  sleep 10
  i=$((i+1))
done
cd "$ROOT" || exit 1
Rscript -e 'source("04_Research/strategies/RF_B3_15_SectorNeutral/run_b3_15.R")' \
  > "$ROOT/04_Research/strategies/RF_B3_15_SectorNeutral/run_b3_15.log" 2>&1
echo "EXIT=$?"
tail -40 "$ROOT/04_Research/strategies/RF_B3_15_SectorNeutral/run_b3_15.log"
