#!/usr/bin/env bash
#==============================================================================
# noLayer4 PG2 월간 페이퍼 트래킹 — base 최신화 + m4×β_R05 비중(Layer4 없음) → 모니터
# 도훈 지시 2026-07-03. run_faithtrend_monthly.sh 미러 — ★faith_overlay 스텝 제거(Layer4 없음).
# Task Scheduler 월간 호출. 모니터링 전용(book_state/자본 변경 없음, 실주문은 도훈 수동).
# 사용: bash run_nolayer4_monthly.sh   (PG2_AS_OF 미지정 시 이번달 1일)
#==============================================================================
set -uo pipefail
export QM_ROOT="${QM_ROOT:-C:/Users/99922/OneDrive/Quant_Module_Moltbot}"
export CLAUDE_PROJECT_DIR="$QM_ROOT"
export R_DATATABLE_NUM_THREADS=1 OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 ARROW_IO_THREADS=1
cd "$QM_ROOT"
B23="05_Production/2.Factor_Model/2-3.STR_1715_on_M4_R05_noLayer4_PG2/01_reproducible_code"
B21="05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/01_reproducible_code"
RSCRIPT="$(command -v Rscript || echo '/c/Program Files/R/R-4.5.2/bin/Rscript.exe')"
LOGD="$QM_ROOT/.cache/nolayer4_track_logs"; mkdir -p "$LOGD"
AS_OF="${PG2_AS_OF:-$(date +%Y-%m)-01}"
TS="$(date +%Y%m%d)"; LOG="$LOGD/track_$TS.log"
kill_stray(){ taskkill //F //IM Rscript.exe >/dev/null 2>&1 || true; }
echo "=== noLayer4 월간 트래킹 $AS_OF ($(date)) ===" | tee "$LOG"

# 1) base 최신화 + noLayer4 배포 비중 (alpha->m4->β_R05->비중, Layer4 없음) — 슬롯2-3 하드닝 파이프라인
#    ★faith 대비: 별도 β_faith 오버레이 스텝 없음. run_pg2_forward_noLayer4.sh가 alpha/m4/generator 자체 포함.
#    (내부: _recompute_alpha_asof.R + STR_1715 run_all.R + m4 factor_engine → m4_extended.csv/alpha 신선)
kill_stray; PG2_AS_OF="$AS_OF" bash "$B23/run_pg2_forward_noLayer4.sh" >> "$LOG" 2>&1 || echo "[warn] run_pg2_forward_noLayer4 비정상(로그 확인)" | tee -a "$LOG"

# 2) base 오버레이 패널 최신화 (β_R05/m4/ret_orig per realized_ym) — run_layer5_rerun_extended.R.
#    ★extend_nolayer4_series의 연료. 이 스텝이 없으면 base 패널이 정적→새 실현월이 시리즈에 안 쌓임.
#    (step 1의 m4_extended.csv + STR_1715 PR 확장이 선행돼야 여기서 새 realized_ym 생성됨.)
kill_stray; "$RSCRIPT" --no-save "$QM_ROOT/$B21/run_layer5_rerun_extended.R" >> "$LOG" 2>&1 || echo "[warn] base 패널(run_layer5_rerun_extended) 비정상" | tee -a "$LOG"

# 3) ★noLayer4 오버레이-시리즈 확장 (제거된 faith_overlay 자리 = Layer4 없이 β_R05×m4 재계산).
#    단일 vintage 통째 재계산 → live_track/live_book_series.csv (05_Production 정적코드 미수정).
#    ret_noLayer4 = beta_R05×m4×ret_orig − |Δbeta_R05|×15bps (β_faith 제거).
kill_stray; "$RSCRIPT" --no-save "$QM_ROOT/02_Infrastructure/monitoring/extend_nolayer4_series.R" >> "$LOG" 2>&1 || echo "[warn] extend_nolayer4_series 비정상" | tee -a "$LOG"

# 4) 모니터 (live_track 확장 시리즈에서 신규 실현월 감지 → paper_nav append + holdout 대조 + Telegram)
kill_stray; "$RSCRIPT" --no-save "$QM_ROOT/02_Infrastructure/monitoring/monitor_nolayer4_paper.R" >> "$LOG" 2>&1 || echo "[warn] monitor 비정상" | tee -a "$LOG"
echo "=== done $(date) — 로그 $LOG ===" | tee -a "$LOG"
