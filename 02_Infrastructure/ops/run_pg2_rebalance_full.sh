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
# ── 배포 슬롯 / 산출 파일명 ────────────────────────────────────────────────
#   슬롯별 파일명 규칙: ${DT}_<TAG>_weights_cap_0p20.csv · ${DT}_<TAG>_manifest.json
#   (2-3 → TAG=noLayer4 / 2-4 → TAG=M4gAE)
SLOT_DIR="$QM_ROOT/05_Production/2.Factor_Model/2-3.STR_1715_on_M4_R05_noLayer4_PG2"
HOLD_TAG="noLayer4"
HOLD_DIR="$SLOT_DIR/02_holdings_universe"
HOLD="$HOLD_DIR/${DT}_${HOLD_TAG}_weights_cap_0p20.csv"
MANIFEST="$HOLD_DIR/${DT}_${HOLD_TAG}_manifest.json"
PREV_DT="$(date -d "$AS_OF -1 month" +%Y%m01)"
PREV_HOLD="$HOLD_DIR/${PREV_DT}_${HOLD_TAG}_weights_cap_0p20.csv"

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
  # ── [1b] sig-month factor DB 강제 재빌드 + IC 재계산 (2026-08-01 추가) ─────
  #   왜: daily_refresh [6a] 의 update_factor_db_daily() 는 today <- Sys.Date() 기준이라
  #   **당월만** 빌드한다(factor_db_builder.R:1361-1364). 그런데 월초 리밸의 sig_date 는
  #   *전월* 말일 → 소비 파일은 전월 DB다. gap-scan(.fdb_gap_months)은 '없는 달'만 잡고
  #   '있지만 월중 앵커'는 못 잡는다. 실측(2026-08-01): factor_db_202607 의 Date 단일값이
  #   2026-07-24 로, 월말이 아니었다(07-26 빌드 당시 RAWDATA 가 07-24 까지였던 탓).
  #   그대로 두면 종목 선정과 β_R05 가 **둘 다 5거래일 낡은 Z-score** 로 계산된다.
  #   ★순서 의존: 앵커를 고친 *뒤* IC 를 돌려야 한다. 앵커가 월중이면
  #   ic_pair_completeness 가 file_partial 로 pair 를 건너뛰어 IC 가 전진하지 않는다.
  SIG_YM="$(date -d "$AS_OF -1 day" +%Y%m)"
  SIG_DATE="$("$PY" - "$SIG_YM" <<'PYEOF'
import sys, pyarrow.parquet as pq, pandas as pd
ym = sys.argv[1]
b = pd.to_datetime(pq.read_table(".cache/benchmark.parquet", columns=["Date"]).to_pandas()["Date"])
m = b[b.dt.strftime("%Y%m") == ym]
print(m.max().strftime("%Y-%m-%d") if len(m) else "")
PYEOF
)"
  [ -n "$SIG_DATE" ] || abort "GateB-sigdate" "sig month $SIG_YM 의 거래일을 benchmark 에서 찾지 못함" 21
  say "[1b] sig-month factor DB 강제 재빌드 (sig_ym=$SIG_YM sig_date=$SIG_DATE)"
  _T="$(mktemp /tmp/qm_fdb_XXXX.R)"
  printf '%s\n' \
    "setwd('$QM_ROOT')" \
    "source('02_Infrastructure/factor_db/factor_db_builder.R')" \
    "build_factor_db('$SIG_DATE', force = TRUE)" \
    "compute_all_factor_ic_monthly()" > "$_T"
  "$RSCRIPT" --no-save "$_T" >> "$LOG" 2>&1 || say "[warn] sig-month 재빌드/IC rc!=0 (Gate B 가 내용으로 검증)"
  rm -f "$_T"

  # ── Gate B = 앵커 **내용** 검사 (mtime 아님) ────────────────────────────────
  #   구판은 `ls -1t | head -1` 로 가장 최근 factor_db 를 골라 mtime 만 봤다. 월초에 실행하면
  #   그건 오늘 만들어진 *당월* DB(예: 202608)라 **소비하지 않는 파일**을 검사하고 초록을 냈다.
  #   게다가 warn-only 라 abort 도 없었다. 파일이 있다/최근이다 는 "맞는 신호일로 만들어졌나"를
  #   재지 못한다 — 잴 것을 재도록 앵커 Date 를 직접 검사하고 미달 시 중단한다.
  GB="$("$PY" - "$SIG_YM" "$SIG_DATE" <<'PYEOF'
import sys, os, pyarrow.parquet as pq, pandas as pd
ym, sig = sys.argv[1], sys.argv[2]
p = f".cache/factor_db/factor_db_{ym}.parquet"
if not os.path.exists(p):
    print(f"BAD 파일 부재 {p}"); raise SystemExit
try:
    d = pd.to_datetime(pq.read_table(p, columns=["Date"]).to_pandas()["Date"])
    u = sorted(d.dt.strftime("%Y-%m-%d").unique())
    print(("OK " if u[-1] == sig else "BAD ") + f"anchor={u[-1]} (기대 {sig}) rows={len(d)} uniq={len(u)}")
except Exception as e:
    print(f"BAD read_error={e}")
PYEOF
)"
  say "  Gate B: $GB"
  echo "$GB" | grep -q "^OK" \
    || abort "GateB-anchor" "factor_db_$SIG_YM 앵커가 $SIG_DATE 아님 ($GB) — 알파·β_R05 가 낡은 신호일로 계산되는 것을 차단" 22
else
  say "[1] 인제스트/팩터DB 스킵 (--only-weights)"
fi

# ── [2] 리밸 (비중 + monitor, Layer4 없음) + Gate C ─────────────────────────
say "[2] rebalance (run_nolayer4_monthly.sh, AS_OF=$AS_OF)..."
PG2_AS_OF="$AS_OF" bash "02_Infrastructure/monitoring/run_nolayer4_monthly.sh" >> "$LOG" 2>&1 \
  || say "[warn] run_nolayer4_monthly 일부 step warn (Gate C가 최종 검증)"
[ -f "$HOLD" ] && [ "$(wc -l < "$HOLD")" -ge 5 ] \
  || abort "GateC-weights" "홀딩 CSV 미생성/부실: $HOLD (run_pg2_forward alpha/m4/beta 실패 가능 - 로그 확인)" 30

# ── [3] Gate D — 하드 제약 + 재계산 정합 (2026-08-01 추가) ──────────────────
#   왜: Gate C 는 "파일이 생겼고 5행 이상"만 본다 → **전월 값이 그대로 재출력돼도 통과**하고,
#   하드 제약(25종·long-only·bounds·Σw=1·유동성)은 배포 체인 어디서도 산출물에 대해
#   검사되지 않았다(2026-08-01 감사: "구성상 만족일 뿐 검증 0건"). 구성이 맞다는 것과
#   산출물이 맞다는 것은 다르다 — 산출물을 직접 잰다.
#   전월 지문 대조로 '조용한 재출력'까지 검거한다. hard FAIL 이면 중단.
say "[3] Gate D: 배포 홀딩 제약·정합 검증 (deployed_holdings_check.py)"
_DHC_ARGS=(--as-of "$AS_OF" --holdings "$HOLD" --manifest "$MANIFEST")
if [ -f "$PREV_HOLD" ]; then
  _DHC_ARGS+=(--prev-holdings "$PREV_HOLD")
else
  say "  [warn] 전월 홀딩 부재($PREV_HOLD) — 재계산 지문 대조 SKIP(조용한 재출력 미검)"
fi
"$PY" "$QM_ROOT/02_Infrastructure/validation/deployed_holdings_check.py" "${_DHC_ARGS[@]}" 2>&1 | tee -a "$LOG"
_DHC_RC="${PIPESTATUS[0]}"
case "$_DHC_RC" in
  0) say "  Gate D: PASS" ;;
  2) abort "GateD-missing" "검증 대상 산출물 판독 불가 (홀딩/매니페스트)" 41 ;;
  *) abort "GateD-constraints" "하드 제약/정합 위반 — 위 FAIL 항목 확인 (비중 배포 금지)" 40 ;;
esac

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
