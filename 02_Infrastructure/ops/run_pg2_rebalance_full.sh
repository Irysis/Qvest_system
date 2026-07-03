#!/usr/bin/env bash
#==============================================================================
# run_pg2_rebalance_full.sh - PG2 월간 리밸 단일 오케스트레이터 (얇은 래퍼)
#
# 기존 3스크립트를 순서대로 호출하고 사이에 fail-loud 게이트를 넣는다. 로직 무수정.
#   [0] qw_refresh.ps1            QuantiWise -> Update_File 증분 refresh
#        Gate A(하드): 5파일 전부 target 도달? 아니면 ABORT (stale 인제스트 차단)
#   [1] daily_refresh.sh          incremental_update_all + build_factor_db
#        Gate B(경고): 최신 factor_db mtime==오늘? (알파 hard-stop이 2차 방어)
#   [2] run_nolayer4_monthly.sh  알파->m4->β_R05->비중 (Layer4 없음) + monitor
#        Gate C(하드): 홀딩 CSV 생성? 아니면 ABORT
#        (구 FaithTrend/2-2 경로 → noLayer4/2-3 전환, 도훈 지시 2026-07-03 Layer4 제거)
#   [STOP] Governor(자본편입)은 호출 안 함 - event-driven, 도훈 수동 confirm.
#
# 원칙: 얇은 래퍼 / fail-loud / 멱등(재실행 시 완료분 스킵) / 단일 로그 / 페이퍼 비중까지.
#
# 사용:
#   bash run_pg2_rebalance_full.sh                     # 이번달 1일 AS_OF, 전과정
#   PG2_AS_OF=2026-07-01 bash run_pg2_rebalance_full.sh
#   bash run_pg2_rebalance_full.sh --skip-refresh      # 데이터 이미 신선 -> [1][2]만
#   bash run_pg2_rebalance_full.sh --only-weights      # [2]만 (팩터DB 신선 가정)
#==============================================================================
set -uo pipefail
export QM_ROOT="${QM_ROOT:-C:/Users/99922/OneDrive/Quant_Module_Moltbot}"
export CLAUDE_PROJECT_DIR="$QM_ROOT"
cd "$QM_ROOT"

AS_OF="${PG2_AS_OF:-$(date +%Y-%m)-01}"
DT="$(echo "$AS_OF" | tr -d '-')"
PY="$QM_ROOT/.venv_qvest_ml/Scripts/python.exe"
RSCRIPT="$(command -v Rscript || echo '/c/Program Files/R/R-4.5.2/bin/Rscript.exe')"
LOGD="$QM_ROOT/.cache/pg2_rebalance_logs"; mkdir -p "$LOGD"
LOG="$LOGD/full_$(date +%Y%m%d_%H%M).log"
HOLD="$QM_ROOT/05_Production/2.Factor_Model/2-3.STR_1715_on_M4_R05_noLayer4_PG2/02_holdings_universe/${DT}_noLayer4_weights_cap_0p20.csv"

SKIP_REFRESH=0; ONLY_WEIGHTS=0
for a in "$@"; do case "$a" in
  --skip-refresh) SKIP_REFRESH=1 ;;
  --only-weights) ONLY_WEIGHTS=1; SKIP_REFRESH=1 ;;
esac; done

say(){ echo "$1" | tee -a "$LOG"; }
abort(){ say "XX ABORT [$1] (exit $3): $2"; exit "$3"; }

say "===== PG2 rebalance FULL | AS_OF=$AS_OF | $(date '+%Y-%m-%d %H:%M:%S') ====="
say "log: $LOG"

# ── [0] QuantiWise refresh + Gate A ─────────────────────────────────────────
if [ "$SKIP_REFRESH" != "1" ]; then
  say "[0] QuantiWise refresh (qw_refresh.ps1)..."
  powershell -ExecutionPolicy Bypass -File "02_Infrastructure/ops/qw_refresh.ps1" >> "$LOG" 2>&1 \
    || say "[warn] qw_refresh 종료코드!=0 (Gate A가 실 도달여부 검증)"
  GA="$("$PY" - <<'PYEOF' 2>/dev/null
import json,os,pyarrow.parquet as pq,pandas as pd
root=os.environ["QM_ROOT"]
target=pd.to_datetime(pq.read_table(root+"/.cache/RAWDATA.parquet",columns=["Date"]).to_pandas()["Date"]).max().strftime("%Y%m%d")
try: st=json.load(open(root+"/.cache/qw_refresh_state.json"))
except Exception: st={}
need=["Benchmark","OHLCVS","Universe_Support","Investor_Act","Consensus"]
miss=[n for n in need if str((st.get(n) or {}).get("ymd"))!=target]
print("ALLDONE target="+target if not miss else "INCOMPLETE("+",".join(miss)+") target="+target)
PYEOF
)"
  say "  Gate A: $GA"
  echo "$GA" | grep -q "^ALLDONE" || abort "GateA-refresh" "일부 Update_File target 미달 -> stale 인제스트 방지 (공유자 kick 등, qw_refresh 재실행으로 이어감)" 10
else
  say "[0] refresh 스킵 (--skip-refresh)"
fi

# ── [1] 인제스트 + 팩터DB + Gate B ──────────────────────────────────────────
if [ "$ONLY_WEIGHTS" != "1" ]; then
  say "[1] ingest + factor DB (daily_refresh.sh)..."
  QVEST_REFRESH_TG=0 bash "02_Infrastructure/data/daily_refresh.sh" >> "$LOG" 2>&1 \
    || say "[warn] daily_refresh 종료코드!=0 (Gate B/알파 hard-stop이 검증)"
  FDB="$(ls -1t .cache/factor_db/factor_db_2*.parquet 2>/dev/null | head -1)"
  [ -n "$FDB" ] || abort "GateB-factordb" "factor_db 파일 없음" 20
  FDB_DAY="$(date -r "$FDB" +%Y%m%d 2>/dev/null || echo 0)"; TODAY="$(date +%Y%m%d)"
  say "  Gate B: latest=$(basename "$FDB") mtime=$FDB_DAY (today=$TODAY)"
  [ "$FDB_DAY" = "$TODAY" ] || say "[warn] factor_db가 오늘 재빌드 안 됨 -> 알파가 stale 팩터DB 사용 가능. 알파 hard-stop(결측만) 통과해도 fundamental이 옛값일 수 있으니 daily_refresh 로그 확인 권장."
else
  say "[1] 인제스트/팩터DB 스킵 (--only-weights)"
fi

# ── [2] 리밸 (비중 + monitor, Layer4 없음) + Gate C ─────────────────────────
say "[2] rebalance (run_nolayer4_monthly.sh, AS_OF=$AS_OF)..."
PG2_AS_OF="$AS_OF" bash "02_Infrastructure/monitoring/run_nolayer4_monthly.sh" >> "$LOG" 2>&1 \
  || say "[warn] run_nolayer4_monthly 일부 step warn (Gate C가 최종 검증)"
[ -f "$HOLD" ] && [ "$(wc -l < "$HOLD")" -ge 5 ] \
  || abort "GateC-weights" "홀딩 CSV 미생성/부실: $HOLD (run_pg2_forward alpha/m4/beta 실패 가능 - 로그 확인)" 30

# ── 결과 리포트 ─────────────────────────────────────────────────────────────
say ""
say "===== OK 완료 - ${AS_OF} 보유비중 산출 ====="
say "홀딩: $HOLD"
{ head -1 "$HOLD"; tail -n +2 "$HOLD" | head -8; } | sed 's/^/  /' | tee -a "$LOG"
say "  ... 총 $(($(wc -l < "$HOLD")-1))종목"
say ""
say "Governor(자본편입/book_state)는 호출 안 함 - event-driven, 도훈 수동 confirm (설계상 유지)."
say "다음(선택): 편입/교체/퇴출 결정이 있을 때만 governor 별도 호출."
say "===== DONE $(date '+%H:%M:%S') | log: $LOG ====="
