#!/usr/bin/env bash
#==============================================================================
# DEPRECATED 2026-07-03 — Layer4 제거로 noLayer4 버전(run_nolayer4_monthly.sh)으로 대체. rollback 보존용 (Task 호출 끊김·로직 미변경).
# FaithTrend PG2 월간 페이퍼 트래킹 — base 최신화 → faith 오버레이 → 모니터
# 도훈 confirm 2026-07-01. Task Scheduler 월간 호출. 모니터링 전용(book_state/자본 변경 없음).
# 사용: bash run_faithtrend_monthly.sh   (PG2_AS_OF 미지정 시 이번달 1일)
#==============================================================================
set -uo pipefail
export QM_ROOT="${QM_ROOT:-C:/Users/99922/OneDrive/Quant_Module_Moltbot}"
export CLAUDE_PROJECT_DIR="$QM_ROOT"
export R_DATATABLE_NUM_THREADS=1 OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 ARROW_IO_THREADS=1
cd "$QM_ROOT"
B22="05_Production/2.Factor_Model/2-2.STR_1715_FaithTrend_on_M4_R05_overlay_PG2/01_reproducible_code"
B21="05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/01_reproducible_code"
RSCRIPT="$(command -v Rscript || echo '/c/Program Files/R/R-4.5.2/bin/Rscript.exe')"
LOGD="$QM_ROOT/.cache/faithtrend_track_logs"; mkdir -p "$LOGD"
AS_OF="${PG2_AS_OF:-$(date +%Y-%m)-01}"
TS="$(date +%Y%m%d)"; LOG="$LOGD/track_$TS.log"
kill_stray(){ taskkill //F //IM Rscript.exe >/dev/null 2>&1 || true; }
echo "=== FaithTrend 월간 트래킹 $AS_OF ($(date)) ===" | tee "$LOG"

# 1) base 최신화 (STR_1715/M4/R05/β_AR alpha 연장) — 하드닝 파이프라인
kill_stray; PG2_AS_OF="$AS_OF" bash "$B21/run_pg2_forward.sh" >> "$LOG" 2>&1 || echo "[warn] run_pg2_forward 비정상(로그 확인)" | tee -a "$LOG"
# 1b) ★FaithTrend 실제 리밸런싱 — β_faith 배포 홀딩 산출 (이번달 운용 비중)
kill_stray; PG2_AS_OF="$AS_OF" "$RSCRIPT" --no-save "$B22/forward_weights_R05_FAITH.R" >> "$LOG" 2>&1 || echo "[warn] FaithTrend 리밸 비정상" | tee -a "$LOG"
# 2) base 오버레이 패널 (β_AR/β_R05/m4/ret_orig) — WT-H 산출
kill_stray; "$RSCRIPT" --no-save "$B21/run_layer5_rerun_extended.R" >> "$LOG" 2>&1 || echo "[warn] layer5_rerun 비정상" | tee -a "$LOG"
# 3) FaithTrend 오버레이 — 신선 base panel 사용 (WT-H 산출 우선, 없으면 2-1 사본)
FRESH="$QM_ROOT/qepm/mailbox/worktask/WT-H20260513_001/output/period_returns_layer5.csv"
[ -f "$FRESH" ] && export FAITH_BASE_PANEL="$FRESH"
kill_stray; "$RSCRIPT" --no-save "$B22/run_layer5_faith_overlay.R" >> "$LOG" 2>&1 || echo "[warn] faith_overlay 비정상" | tee -a "$LOG"
# 4) 모니터 (append + holdout 대조 + Telegram)
kill_stray; "$RSCRIPT" --no-save "$QM_ROOT/02_Infrastructure/monitoring/monitor_faithtrend_paper.R" >> "$LOG" 2>&1 || echo "[warn] monitor 비정상" | tee -a "$LOG"
echo "=== done $(date) — 로그 $LOG ===" | tee -a "$LOG"
