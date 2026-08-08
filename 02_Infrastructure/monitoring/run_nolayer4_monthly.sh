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
# B21(2-1 슬롯) 참조 제거 (2026-08-02) — base 패널 빌더는 02_Infrastructure/portfolio/ 로 이전
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

# 1b) ★deployed 슬롯 생성기 — book_state.admitted_ids 가 슬롯 2-3 이 아닐 때만 추가 실행.
#     2026-07-19 D3 swap-in 이후 admitted = STR_1715_on_M4gAE_R05_noLayer4_PG2(슬롯 2-4)인데
#     이 실행기는 슬롯 2-3 만 돌리고 있었다 — m4 발화월(실측 37개월 중 36개월)에는
#     30% de-risk 가 누락된 **틀린 비중**이 배포된다. 2026-08 은 m4 미발화라 두 산출이
#     바이트 동일이었을 뿐이다.
#     ★[1]과 [1b]는 체인이 아니라 **형제**다 — 2-4 생성기는 2-3 의 weights 를 읽지 않고
#       [1]이 만든 같은 alpha/m4 패널을 읽는다. 그래서 [1] 은 계속 필요하다(연료 + base 시리즈).
#     ★05_Production 무수정: 인프라 미러(GEN_SCRIPT)를 호출한다. 해석기가 production 사본과
#       sha1 대조까지 마친 경로만 반환한다.
. "$QM_ROOT/02_Infrastructure/ops/resolve_admitted_slot.sh"
if resolve_admitted_slot; then
  echo "── [1b] deployed 슬롯: $ADMITTED_ID → ${SLOT_DIR##*/} (tag=$HOLD_TAG)" | tee -a "$LOG"
  if [ "${SLOT_DIR##*/}" = "2-3.STR_1715_on_M4_R05_noLayer4_PG2" ]; then
    echo "   admitted == 슬롯2-3 → [1] 산출이 곧 배포본 (추가 실행 없음)" | tee -a "$LOG"
  else
    kill_stray
    QM_ROOT="$QM_ROOT" CLAUDE_PROJECT_DIR="$QM_ROOT" PG2_AS_OF="$AS_OF" \
    PG2_OUT_DIR="$SLOT_DIR/02_holdings_universe" \
    R_DATATABLE_NUM_THREADS=1 OMP_NUM_THREADS=1 ARROW_IO_THREADS=1 \
      "$RSCRIPT" --no-save "$GEN_SCRIPT" >> "$LOG" 2>&1 \
      || echo "[warn] deployed 생성기($( basename "$GEN_SCRIPT")) 비정상 — ★이 경로엔 후속 검증 없음(아래 주석)" | tee -a "$LOG"
    # ★2026-08-08 주석 정정: 구 문구는 "Gate C/D 가 최종 검증"이라 주장했으나 **거짓**이다.
    #   Gate C(홀딩 CSV 존재·5행) 와 Gate D(deployed_holdings_check.py — 하드제약·재계산 정합)는
    #   `02_Infrastructure/ops/run_pg2_rebalance_full.sh` 안에만 있는데, 실제 예약 작업
    #   `noLayer4_Monthly_PaperTracking` 은 run_nolayer4_monthly.bat → **이 스크립트를 직접** 호출한다
    #   (Get-ScheduledTask 전수 확인: run_pg2_rebalance_full.sh 를 부르는 등록 없음).
    #   ⇒ 예약 경로에서 Gate C/D 는 **한 번도 돌지 않는다**. 생성기가 실패하거나 전월 값을 그대로
    #   재출력해도 아무도 안 잡는다. 배선 결정은 미실행(행동 변경) — 메모리 참조:
    #   project-gate-cd-not-on-scheduled-path-20260808
  fi
else
  # fail-closed: 해석 실패 시 구 슬롯으로 조용히 되돌아가지 않는다.
  echo "XX [1b] admitted 슬롯 해석 실패 — 배포본 미산출. book_state/슬롯 구성 확인 필요" | tee -a "$LOG"
  exit 12
fi

# 2) base 오버레이 패널 최신화 (β_R05/m4/ret_orig per realized_ym) — run_layer5_rerun_extended.R.
#    ★extend_nolayer4_series의 연료. 이 스텝이 없으면 base 패널이 정적→새 실현월이 시리즈에 안 쌓임.
#    (step 1의 m4_extended.csv + STR_1715 PR 확장이 선행돼야 여기서 새 realized_ym 생성됨.)
#    2026-08-02 정본 이전: 구 2-1 슬롯 원본(종료월 하드코딩) → 02_Infrastructure/portfolio/
#    (종료월 동적화 반영본). 2-1 슬롯은 철거 대상 — 여기서 더는 참조하지 않는다.
#    ★종점 앵커 정규화 선행: STR_1715 확장 종점(월말 raw 끝) 행을 장부 규약으로 정규화
#    (완결월→다음달 1일 재라벨 / 진행월→제거). 없으면 ym 중복 → 조인 2배 증식 (08-01 실사고).
"$RSCRIPT" --no-save "$QM_ROOT/02_Infrastructure/portfolio/normalize_terminal_anchor.R" \
  "$QM_ROOT/04_Research/strategies/STR_1715_WT016_Iter31_GridBestProd/output/03_period_returns.csv" \
  >> "$LOG" 2>&1 || { echo "XX [2] 종점 앵커 정규화 실패 — 패널 빌드 중단(중복 라벨 방지)" | tee -a "$LOG"; exit 21; }
#    ★2026-08-08 fail-closed 전파 (칩 task_972fe292): 구판은 `|| echo "[warn]"` 로 실패를 삼켜
#      [3](시리즈 확장)·[4](모니터/paper_nav append)가 **stale 패널 위에서 계속 진행**했다.
#      R 쪽에 fail-closed 를 넣어도 러너가 삼키면 무력하다 — 바로 위 앵커 정규화(exit 21)와 동일하게 중단.
#      ★[1b] 배포 비중은 이 지점 **이전**에 산출되므로 주문은 정상적으로 나간다(기록만 멈춘다).
kill_stray; "$RSCRIPT" --no-save "$QM_ROOT/02_Infrastructure/portfolio/run_layer5_rerun_extended.R" >> "$LOG" 2>&1 \
  || { echo "XX [2] base 패널(run_layer5_rerun_extended) 실패 — 시리즈/모니터 중단(stale 전파 방지). 배포 비중[1b]는 산출 완료." | tee -a "$LOG"; exit 22; }

# 3) ★noLayer4 오버레이-시리즈 확장 (제거된 faith_overlay 자리 = Layer4 없이 β_R05×m4 재계산).
#    단일 vintage 통째 재계산 → live_track/live_book_series.csv (05_Production 정적코드 미수정).
#    ret_noLayer4 = beta_R05×m4×ret_orig − |Δbeta_R05|×15bps (β_faith 제거).
kill_stray; "$RSCRIPT" --no-save "$QM_ROOT/02_Infrastructure/monitoring/extend_nolayer4_series.R" >> "$LOG" 2>&1 || echo "[warn] extend_nolayer4_series 비정상" | tee -a "$LOG"

# 4) 모니터 (live_track 확장 시리즈에서 신규 실현월 감지 → paper_nav append + holdout 대조 + Telegram)
kill_stray; "$RSCRIPT" --no-save "$QM_ROOT/02_Infrastructure/monitoring/monitor_nolayer4_paper.R" >> "$LOG" 2>&1 || echo "[warn] monitor 비정상" | tee -a "$LOG"
echo "=== done $(date) — 로그 $LOG ===" | tee -a "$LOG"
