#!/usr/bin/env bash
#==============================================================================
# PG2 (STR_1715_AR_on_M4_R05) FORWARD 비중 — 하드닝 파이프라인 (fail-loud + 재시도 + AS_OF 검증)
# 도훈 mandate 2026-06-17: "오버레이까지가 PG2 / 항상 연장 / 그 코드만 실행하면 전체 비중"
# 2026-06-17 하드닝: 간헐 R 세그폴트(잔류 프로세스+멀티스레드) + 비멱등 sub-script 대응.
#
# 설계 원칙:
#   1. 모든 step taskkill(잔류 R) + 단일스레드 + 최대 N회 재시도(세그폴트 흡수).
#   2. AS_OF 산출물 *검증* 후에만 다음 step (산출물 부재 = fail-loud 중단, EXIT≠0).
#   3. 비멱등/하드코딩 sub-script(M4 factor_engine AS_OF_DATE, β_AR build_optimizer_overlay)는
#      *검증 우선* — 스케줄에 AS_OF 행이 이미 있으면 재실행 안 함(퇴행 방지). 없으면 연장 시도.
#   4. alpha(파라미터화)·generator는 매 실행 신선 재계산.
#   PG2_FORCE=1 → m4/beta도 강제 재실행. PG2_RETRY_MAX=N → 재시도 횟수(기본 3).
#
# 사용:  PG2_AS_OF=2026-06-01 bash run_pg2_forward.sh
#==============================================================================
set -uo pipefail
export QM_ROOT="${QM_ROOT:-C:/Users/99922/OneDrive/Quant_Module_Moltbot}"
export CLAUDE_PROJECT_DIR="$QM_ROOT"
export PG2_AS_OF="${PG2_AS_OF:-2026-06-01}"
export R_DATATABLE_NUM_THREADS=1 OMP_NUM_THREADS=1   # 멀티스레드 OpenMP 세그폴트 회피
ROOT="$QM_ROOT"
STRAT="$ROOT/04_Research/strategies/STR_1715_WT016_Iter31_GridBestProd"
RSCRIPT="$(command -v Rscript || echo '/c/Program Files/R/R-4.5.2/bin/Rscript.exe')"
RETRY_MAX="${PG2_RETRY_MAX:-3}"
FORCE="${PG2_FORCE:-0}"
DT="$(echo "$PG2_AS_OF" | tr -d '-')"            # 20260601
LOGD="$ROOT/.cache/pg2_fwd_logs"; mkdir -p "$LOGD"
M4_CSV="$ROOT/stage_artifacts/WT-D20260430_001_m4_extended.csv"
BETA_CSV="$ROOT/stage_artifacts/WT_WT-S20260504_007/beta_t_mapping.csv"
PR_CSV="$STRAT/output/03_period_returns.csv"
WEIGHTS="$STRAT/production_weights/${DT}_R05_AR_weights_cap_0p20.csv"
FAILS=0

kill_stray(){ taskkill //F //IM Rscript.exe >/dev/null 2>&1 || true; }
log_tail(){ tail -2 "$1" 2>/dev/null | sed 's/^/        /'; }
crashed(){ grep -qE "Execution halted|Error in|cannot open|FATAL|Segmentation" "$1" 2>/dev/null; }

# ── 신선 재계산 step: 매번 실행(retry), 검증 grep 패턴이 로그/파일에 나와야 통과 ──
#   $1 label  $2 "run cmd"  $3 "validate cmd(0=ok)"
fresh_step(){
  local label="$1" runcmd="$2" validate="$3"
  local log="$LOGD/$label.log" i ec
  echo "── [$label] (신선 재계산)"
  for ((i=1;i<=RETRY_MAX;i++)); do
    kill_stray; sleep 0.5
    eval "$runcmd" > "$log" 2>&1; ec=$?
    if [ $ec -eq 0 ] && ! crashed "$log" && eval "$validate"; then
      echo "   ✓ try $i ok"; return 0
    fi
    echo "   ✗ try $i (exit=$ec) — 재시도"; log_tail "$log"; sleep 1
  done
  echo "   ✗✗ [$label] $RETRY_MAX회 실패 — 중단"; FAILS=$((FAILS+1)); return 1
}

# ── 검증 우선 step: AS_OF 이미 있으면 사용(비멱등 보호), 없으면 연장 시도 ──
#   $1 label  $2 file  $3 "extend cmd"
ensure_schedule(){
  local label="$1" file="$2" extend="$3"
  local log="$LOGD/$label.log" i
  echo "── [$label] (AS_OF 검증 우선)"
  if [ "$FORCE" != "1" ] && [ -f "$file" ] && grep -q "$PG2_AS_OF" "$file"; then
    echo "   ✓ 기존 스케줄에 AS_OF=$PG2_AS_OF 행 존재 → 사용 (재실행 생략; PG2_FORCE=1로 강제)"
    return 0
  fi
  echo "   · AS_OF 부재 또는 FORCE — 연장 시도"
  for ((i=1;i<=RETRY_MAX;i++)); do
    kill_stray; sleep 0.5
    eval "$extend" > "$log" 2>&1
    if [ -f "$file" ] && grep -q "$PG2_AS_OF" "$file"; then
      echo "   ✓ try $i — AS_OF 행 생성"; return 0
    fi
    echo "   ✗ try $i — AS_OF 미생성 (sub-script 하드코딩 가능)"; log_tail "$log"; sleep 1
  done
  echo "   ✗✗ [$label] AS_OF=$PG2_AS_OF 연장 실패 — sub-script가 AS_OF 미지원(하드코딩). 중단."
  FAILS=$((FAILS+1)); return 1
}

echo "=== PG2 forward 하드닝 파이프라인 | AS_OF=$PG2_AS_OF | retry=$RETRY_MAX force=$FORCE | $(date '+%H:%M:%S') ==="

# [1/4] alpha — 파라미터화, 매번 신선 (factor_db_{T-1} → score_eff @ AS_OF)
fresh_step "alpha" \
  "\"$RSCRIPT\" --no-save \"$ROOT/stage_artifacts/WT_D20260425_010/_recompute_alpha_asof.R\"" \
  "grep -q '\\[write\\] alpha $PG2_AS_OF' \"$LOGD/alpha.log\"" \
  || { echo "=== ABORT (alpha) ==="; exit 1; }

# [2/4] m4 — 검증 우선 (factor_engine AS_OF_DATE 하드코딩 → 06월 외 미연장 시 fail-loud)
ensure_schedule "m4" "$M4_CSV" \
  "( cd \"$STRAT\" && \"$RSCRIPT\" --no-save -e 'source(\"run_all.R\")' ); \"$RSCRIPT\" --no-save \"$ROOT/qepm/mailbox/worktask/WT-D20260430_001/stage_artifacts/factor_engine.R\"" \
  || { echo "=== ABORT (m4) ==="; exit 2; }

# [3/4] β_AR — 검증 우선 (build_optimizer_overlay 2026-05-01 하드코딩)
ensure_schedule "beta" "$BETA_CSV" \
  "\"$RSCRIPT\" --no-save \"$ROOT/stage_artifacts/WT_WT-S20260504_007/_logs/build_absorption_ratio.R\"; \"$RSCRIPT\" --no-save \"$ROOT/stage_artifacts/WT_WT-S20260504_007/_logs/build_optimizer_overlay.R\"" \
  || { echo "=== ABORT (beta) ==="; exit 3; }

# [4/4] generator — 매번 신선 (m4×β_AR×β_R05_V5 결합 → 전체 비중)
fresh_step "combine" \
  "\"$RSCRIPT\" --no-save \"$STRAT/forward_weights_R05_AR.R\"" \
  "[ -f \"$WEIGHTS\" ] && grep -q CASH \"$WEIGHTS\" && [ \$(wc -l < \"$WEIGHTS\") -ge 10 ]" \
  || { echo "=== ABORT (combine) ==="; exit 4; }

echo
echo "=== 결과 (AS_OF=$PG2_AS_OF) ==="
echo "weights: $WEIGHTS"
head -1 "$WEIGHTS"; grep -E ",CASH,|^[0-9]" "$WEIGHTS" | head -6
echo "  ... 총 $(($(wc -l < "$WEIGHTS")-1))행"
echo "=== DONE @ $(date '+%H:%M:%S') | FAILS=$FAILS — 자본 편입은 promote_to_production()+도훈 수동 ==="
[ "$FAILS" -eq 0 ] || exit 9
