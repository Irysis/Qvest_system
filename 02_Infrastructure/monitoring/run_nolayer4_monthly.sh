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
## ★ARROW_IO_THREADS 를 1 로 두지 말 것 (2026-08-13 실측 확정). `=1` ∧ `read_parquet(mmap=FALSE)`
##   조합에서 arrow 가 자기 교착해 **무한 대기**한다 — 2×3 격자: 미설정×{TRUE,FALSE} OK · 1×TRUE OK ·
##   **1×FALSE HANG** · 2×FALSE OK · 4×FALSE OK. 여기는 export 라 하위 전 스텝이 상속하므로,
##   되쓸 파일을 mmap=FALSE 로 읽는 스텝([1a] m4 게이트)이 통째로 멈췄다. 저장소 관행도 이미 2다
##   (02_Infrastructure/reports/*.R 15개가 Sys.setenv(ARROW_IO_THREADS="2")). 다른 스레드 핀은 1 유지.
export R_DATATABLE_NUM_THREADS=1 OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 ARROW_IO_THREADS=2
cd "$QM_ROOT"
B23="05_Production/2.Factor_Model/2-3.STR_1715_on_M4_R05_noLayer4_PG2/01_reproducible_code"
# B21(2-1 슬롯) 참조 제거 (2026-08-02) — base 패널 빌더는 02_Infrastructure/portfolio/ 로 이전
RSCRIPT="$(command -v Rscript || echo '/c/Program Files/R/R-4.5.2/bin/Rscript.exe')"
LOGD="$QM_ROOT/.cache/nolayer4_track_logs"; mkdir -p "$LOGD"
AS_OF="${PG2_AS_OF:-$(date +%Y-%m)-01}"
TS="$(date +%Y%m%d)"; LOG="$LOGD/track_$TS.log"
kill_stray(){ taskkill //F //IM Rscript.exe >/dev/null 2>&1 || true; }
echo "=== noLayer4 월간 트래킹 $AS_OF ($(date)) ===" | tee "$LOG"

# 0) ★데이터 리프레시 (2026-08-30 신설 — 도훈 지시 "리밸런싱할 때 데이터 리프레시도 진행")
#    왜: 이 스크립트는 예약 작업(noLayer4_Monthly_PaperTracking)이 .bat 로 **직접** 부르는
#    경로인데, 리프레시가 **한 스텝도 없었다** — 있는 캐시가 무엇이든 그 위에서 알파·m4·
#    β·AE 를 계산했다. 그러면 신선도 게이트들이 **구조적으로 눈이 먼다**:
#      · 아래 [1a2] AE 핀 신선도는 '핀 vs 라이브' 비교라, **라이브 자체가 낡으면 통과**한다.
#      · Gate B(팩터DB 앵커)·Gate D 는 full 러너에만 있어 예약 경로에선 안 돈다.
#    ⇒ 소비 직전에 원천을 전진시키고, 전진 실패는 삼키지 않는다.
#    ★멱등: full 러너(run_pg2_rebalance_full.sh)는 [0]/[1] 에서 이미 refresh 를 돌리고
#      PG2_REFRESH_DONE=1 을 내려보낸다 → 그 경로에선 중복 실행하지 않는다.
#    ★QuantiWise(qw_refresh.ps1)는 **여기서 부르지 않는다** — 자동 로그인이 풀린 상태에서
#      무인 실행하면 빈 PW 로 40회 클릭해 계정 잠금 위험이 있다(2026-08-29 실측).
#      그건 사람이 붙는 full 러너의 [0]+Gate A 소관으로 남긴다.
if [ "${PG2_REFRESH_DONE:-0}" = "1" ]; then
  echo "── [0] 데이터 리프레시 스킵 — 상위 러너가 이미 수행(PG2_REFRESH_DONE=1)" | tee -a "$LOG"
else
  echo "[0] 데이터 리프레시 (daily_refresh.sh — ingest + factor DB)..." | tee -a "$LOG"
  kill_stray
  QVEST_REFRESH_TG=0 bash "$QM_ROOT/02_Infrastructure/data/daily_refresh.sh" >> "$LOG" 2>&1
  _drrc=$?
  # rc 만으로 판정하지 않는다 — 이 체인은 스텝 실패를 fail-soft 로 넘기는 구간이 있어
  # rc=0 이 "전진했다"를 뜻하지 않는다(2026-08-14~20: 6일 연속 '실패 0' 인데 거래일 3일 결손).
  # 그래서 rc 는 경고로만 남기고, **전진 여부는 아래 [1a2] AE 원천 신선도 게이트가 실측으로 잡는다**.
  if [ "$_drrc" -ne 0 ]; then
    echo "!! [0] daily_refresh rc=$_drrc — 원천 전진 실패 가능. [1a2] 원천 신선도 게이트가 실측 판정" | tee -a "$LOG"
  else
    echo "── [0] 데이터 리프레시 완료 (rc=0)" | tee -a "$LOG"
  fi
fi

# 1) base 최신화 + noLayer4 배포 비중 (alpha->m4->β_R05->비중, Layer4 없음) — 슬롯2-3 하드닝 파이프라인
#    ★faith 대비: 별도 β_faith 오버레이 스텝 없음. run_pg2_forward_noLayer4.sh가 alpha/m4/generator 자체 포함.
#    (내부: _recompute_alpha_asof.R + STR_1715 run_all.R + m4 factor_engine → m4_extended.csv/alpha 신선)
kill_stray; PG2_AS_OF="$AS_OF" bash "$B23/run_pg2_forward_noLayer4.sh" >> "$LOG" 2>&1 || echo "[warn] run_pg2_forward_noLayer4 비정상(로그 확인)" | tee -a "$LOG"

# 1a) ★m4 append-only 게이트 (도훈 지시 2026-08-13 "과거값 소급변경 시키지말고 최신 데이터만 행 추가시켜")
#     [1]의 factor_engine 은 패널을 **전량 재생성**한다. m4 자체 기계는 안정이나(ret_net·bocpd_norm·
#     decay_* 변경 0) **매크로 국면 입력이 과거를 재서술**해서 최종 weight_str1715 가 소급 변경된다
#     — 2026-07-02 백업 대비 8행 변경(2008-02-01 1.0→0.844 등) + **2026-07 행 통째 유실** 실측.
#     이 게이트가 발행 원장(06_Registry/m4_published/)을 정본으로 삼아 과거를 되돌리고 새 달만 잇는다.
#     ★[1b] 배포 생성기가 이 패널을 읽으므로 **반드시 [1] 과 [1b] 사이**에 있어야 한다.
#     exit 1 = 과거 재서술 시도 검출(발행본은 보존됨) → 경고만 하고 계속. 배포 비중은 안정된 이력 위에서 산출된다.
#     ★2026-08-13 리허설이 잡은 결함: 이 호출이 **무한 대기**했다(단독 실행은 1초, 러너 안에서만 재현).
#     원인 = 11행의 `ARROW_IO_THREADS=1` 상속 ∧ 게이트의 `read_parquet(mmap=FALSE)` → arrow 자기 교착.
#     (오진 2회: "파일 잠김"으로 보고 크기-안정화 대기·임시사본 경유를 넣었으나 둘 다 무효였다.
#      판별한 것은 무관한 271행 파일을 먼저 읽는 카나리아 — 그것도 멈춰 대상 특정성이 없음이 드러났다.)
#     수리는 11행에서 했고, 여기 timeout 은 **원인과 무관하게 남긴다** — 무한 대기는 리밸을 조용히
#     멈추지만 timeout 은 로그를 남기고 중단시킨다. 다음 교착이 무엇이든 유한 실패로 받는 그물이다.
kill_stray
QM_ROOT="$QM_ROOT" CLAUDE_PROJECT_DIR="$QM_ROOT" \
  timeout 300 "$RSCRIPT" --no-save "$QM_ROOT/02_Infrastructure/regime/m4_append_only.R" --as-of "$AS_OF" >> "$LOG" 2>&1
_m4rc=$?
if [ "$_m4rc" -eq 124 ]; then
  echo "XX [1a] m4 게이트 300초 타임아웃 — 교착 의심. arrow io_threads 와 mmap 조합부터 확인할 것. 중단" | tee -a "$LOG"
  exit 15
fi
case "$_m4rc" in
  0) echo "── [1a] m4 append-only OK (과거 불변 + 신규행 PIT 통과)" | tee -a "$LOG" ;;
  1) echo "!! [1a] m4 과거 재서술 시도 검출 — 발행본 보존됨(로그 확인). 상류 매크로 국면 재생성 점검 필요" | tee -a "$LOG" ;;
  3) echo "XX [1a] m4 AS_OF 행 미생성 — 이대로 가면 배포 생성기가 직전 달 m4 를 조용히 쓴다. 중단" | tee -a "$LOG"; exit 13 ;;
  4) echo "XX [1a] ★m4 PIT 위반 — 신규 행이 결정일 이후 매크로 관측 사용. 중단" | tee -a "$LOG"; exit 14 ;;
  *) echo "XX [1a] m4 append-only 게이트 실패(rc=$_m4rc) — 패널 신뢰 불가, 중단" | tee -a "$LOG"; exit 13 ;;
esac

# 1a2) ★AE 월간 배관 (2026-08-30 신설 — 도훈 지시). [1b] 의 D3 게이트가 이 신호를 먹는다.
#     ★결함: `02_Infrastructure/regime/ae_regime_monthly.py` 는 D3 게이트용 AE 신호의 운영
#       정본인데 **어떤 실행기도 부르지 않았다**(.sh/.ps1/예약작업 참조 0건). 자기 docstring 이
#       이미 "AE 신호에 생산자가 아예 없었다"고 적어둔 상태로 방치돼 있었다(2026-08-01 감사).
#       그래서 ae_regime_signal_ext.parquet 이 2026-08-01 에 멈췄고, 소비자는 AS_OF 행이
#       없으면 `which.max(decision_date)` 로 **직전 달 행을 조용히 재사용**했다. 소비자의
#       PIT 가드 `last_feat < AS_OF` 는 낡음을 구조적으로 못 잡는다 — 오래될수록 더 잘 통과한다.
#       2026-09 는 m4 미발화라 gate=1.00 으로 고정돼 무해했으나, m4 발화월(실측 37개월 중 36,
#       97.3%)에는 **30% de-risk 오판**으로 직결된다.
#     ★배선 위치가 여기인 이유: 예약 작업(noLayer4_Monthly_PaperTracking)은
#       run_nolayer4_monthly.bat → **이 스크립트를 직접** 부른다(아래 [1b] 주석 참조).
#       run_pg2_rebalance_full.sh 에만 붙이면 무인 경로가 그대로 비어 있게 된다 —
#       Gate C/D 가 예약 경로에서 한 번도 안 도는 것과 정확히 같은 계통이다.
#       여기 두면 두 경로가 모두 덮인다(full 러너는 [2]에서 이 스크립트를 부른다).
#     ★fail-closed. 경고로 삼키지 않는다 — 실패를 삼키면 [1b] 가 낡은 AE 로 비중을 낸다.
kill_stray
_AE_PY=""
for _c in "$QM_ROOT/.venv_qvest_ml/Scripts/python.exe" "${QVEST_PY:-}"; do
  _c="${_c//\\//}"
  # ★존재가 아니라 **실행**으로 확인한다 — bare python 스텁 함정(resolve_admitted_slot.sh 선례).
  [ -n "$_c" ] && "$_c" -c 'import sys' >/dev/null 2>&1 && { _AE_PY="$_c"; break; }
done
if [ -z "$_AE_PY" ]; then
  echo "XX [1a2] AE 갱신용 python 미발견(venv/QVEST_PY) — 낡은 AE 로 배포하지 않는다. 중단" | tee -a "$LOG"
  exit 16
fi
QM_ROOT="$QM_ROOT" CLAUDE_PROJECT_DIR="$QM_ROOT" \
  timeout 900 "$_AE_PY" "$QM_ROOT/02_Infrastructure/regime/ae_regime_monthly.py" \
    --as-of "$AS_OF" --advance-pin >> "$LOG" 2>&1
_aerc=$?
case "$_aerc" in
  0)   echo "── [1a2] AE 월간 갱신 OK ($AS_OF 결정행 확보)" | tee -a "$LOG" ;;
  124) echo "XX [1a2] AE 갱신 900초 타임아웃 — 중단" | tee -a "$LOG"; exit 20 ;;
  1)   echo "XX [1a2] ★AE parity 차단 — 과거 발행 행이 변경됨(재계산본 .parity_reject 보존)." | tee -a "$LOG"
       echo "        오염인지 **교정**인지 먼저 특정할 것(게이트 메시지의 'FRED 개정 의심'은 가설이지 증거가 아니다)." | tee -a "$LOG"
       echo "        판정 컬럼과 점수 컬럼을 나눠 diff → 교정이면 --accept-parity '<사유>' 로 사유를 남겨 통과. 중단" | tee -a "$LOG"
       exit 17 ;;
  2)   echo "XX [1a2] AE 입력/환경 오류 (핀 원본 부재 또는 ★낡은 핀 재사용 거부) — 로그의 [ae-monthly] 사유 확인. 중단" | tee -a "$LOG"; exit 18 ;;
  3)   echo "XX [1a2] ★AE PIT 위반 — 결정일 이후 관측 사용. 중단" | tee -a "$LOG"; exit 19 ;;
  *)   echo "XX [1a2] AE 갱신 실패(rc=$_aerc) — 낡은 AE 로 배포하지 않는다. 중단" | tee -a "$LOG"; exit 20 ;;
esac

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
    R_DATATABLE_NUM_THREADS=1 OMP_NUM_THREADS=1 \
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
