#!/usr/bin/env bash
#==============================================================================
# run_pg2_rebalance_full.sh - PG2 월간 리밸 단일 오케스트레이터 (얇은 래퍼)
#
# 기존 스크립트를 순서대로 호출하고 사이에 fail-loud 게이트를 넣는다. 로직 무수정.
#   [0] Gate I(하드 · 검사만): 이번 리밸이 읽을 원천이 sig 일까지 왔나 + sig 월 팩터DB 앵커
#        (book_rebalance_preflight.py --runner-gate · 사양 rebalance_spec.json::runner_gate)
#        ★러너는 적재하지 않는다 — 2026-11-06 도훈 지시 "daily_refresh 돌리는 프로세스는 빼버려.
#          이제 어차피 데이터 리프레시 때 퀀티 데이터들 다 업데이트하니까 필요없어".
#          구 [0] qw_refresh.ps1 + Gate A · [1] daily_refresh.sh + [1b] sig 월 팩터DB 재빌드 + Gate B 제거.
#        Gate M(하드): 통합 국면 신호 = as-of MSM 표식 ∧ sig 월까지 전진? (gate_msm_asof.sh — [2] 하위 [0b] 와 같은 판정)
#   [2] run_nolayer4_monthly.sh  알파->m4->β_R05->비중 (Layer4 없음) + monitor
#        (하위 [0c] 가 소비 직전에 Gate I 를 다시 건다 — 예약 경로와 한 지점)
#        Gate C(하드): 홀딩 CSV 생성? 아니면 ABORT
#        (구 FaithTrend/2-2 경로 → noLayer4/2-3 전환, 도훈 지시 2026-07-03 Layer4 제거)
#   [3] Gate D(하드): 하드 제약 + 재계산 정합(전월 지문)
#   [STOP] Governor(자본편입)은 호출 안 함 - event-driven, 도훈 수동 confirm.
#
# 원칙: 얇은 래퍼 / fail-loud / 멱등(재실행 시 완료분 스킵) / 단일 로그 / 페이퍼 비중까지.
#
# 사용:
#   bash run_pg2_rebalance_full.sh                     # 이번달 1일 AS_OF
#   PG2_AS_OF=2026-07-01 bash run_pg2_rebalance_full.sh
#   (구 --skip-refresh · --only-weights 는 리프레시 단계가 없어져 받아도 무시한다 — 동작 동일)
#==============================================================================
set -uo pipefail
export QM_ROOT="${QM_ROOT:-C:/Users/99922/OneDrive/Quant_Module_Moltbot}"
export CLAUDE_PROJECT_DIR="$QM_ROOT"
cd "$QM_ROOT"

AS_OF="${PG2_AS_OF:-$(date +%Y-%m)-01}"
DT="$(echo "$AS_OF" | tr -d '-')"
# 사양(02_Infrastructure/book/rebalance_spec.json) 키 — 이 러너가 배포하는 BOOK. Gate I 가 이 사양의 runner_gate 로 잰다.
BOOK_ID="${PG2_BOOK_ID:-BOOK_0001}"
PY="$QM_ROOT/.venv_qvest_ml/Scripts/python.exe"
RSCRIPT="$(command -v Rscript || echo '/c/Program Files/R/R-4.6.2/bin/Rscript.exe')"
LOGD="$QM_ROOT/.cache/pg2_rebalance_logs"; mkdir -p "$LOGD"
LOG="$LOGD/full_$(date +%Y%m%d_%H%M).log"
# ── 배포 슬롯 / 산출 파일명 — book_state.admitted_ids 에서 해석 ────────────
#   구판은 슬롯 2-3 을 하드코딩했다. 2026-07-19 D3 swap-in 으로 admitted 가
#   STR_1715_on_M4gAE_R05_noLayer4_PG2(슬롯 2-4)로 바뀐 뒤에도 계속 구 변형을 산출했다.
#   2026-08 은 m4 미발화로 두 슬롯 산출이 바이트 동일이라 무해했을 뿐 —
#   m4 발화월(실측 37개월 중 36개월, 97.3%)에는 자동화가 30% de-risk 를 누락한다.
#   해석은 정확 매칭 + fail-closed. 실패 시 여기서 멈춘다(구 슬롯으로 되돌아가지 않음).
#   ★슬롯 선택에 .lineage_anchor() 계열을 쓰지 말 것 — 그 함수는 설계상 2-3·2-4 를
#     같은 STR_1715 앵커로 병합해(measurement_basis_audit.R:89-99) 구분 불능이 된다.
. "$QM_ROOT/02_Infrastructure/ops/resolve_admitted_slot.sh"
resolve_admitted_slot || { echo "XX ABORT [slot] admitted 슬롯 해석 실패 — 배포 대상 불명확" >&2; exit 11; }
#   해석 결과: ADMITTED_ID / SLOT_DIR / HOLD_TAG / GEN_SCRIPT (인프라 미러, production 사본과 sha1 일치 검증됨)
HOLD_DIR="$SLOT_DIR/02_holdings_universe"
HOLD="$HOLD_DIR/${DT}_${HOLD_TAG}_weights_cap_0p20.csv"
MANIFEST="$HOLD_DIR/${DT}_${HOLD_TAG}_manifest.json"
PREV_DT="$(date -d "$AS_OF -1 month" +%Y%m01)"
PREV_HOLD="$HOLD_DIR/${PREV_DT}_${HOLD_TAG}_weights_cap_0p20.csv"

say(){ echo "$1" | tee -a "$LOG"; }
abort(){ say "XX ABORT [$1] (exit $3): $2"; exit "$3"; }

say "===== PG2 rebalance FULL | AS_OF=$AS_OF | $(date '+%Y-%m-%d %H:%M:%S') ====="
say "slot: $ADMITTED_ID → ${SLOT_DIR##*/} (tag=$HOLD_TAG)"
say "gen : ${GEN_SCRIPT#$QM_ROOT/}"
say "log: $LOG"
for a in "$@"; do case "$a" in
  --skip-refresh|--only-weights) say "[note] $a 무시 — 러너에 리프레시 단계가 없다(2026-11-06 도훈 지시 · 적재는 데이터 리프레시 소관)" ;;
esac; done

# ── [0] Gate I — 입력 도달 + 팩터DB 앵커 (검사만 · 갱신 없음 · 2026-11-06) ──────────────
#   ★도훈 지시 2026-11-06: "daily_refresh 돌리는 프로세스는 빼버려. 이제 어차피 데이터 리프레시 때
#     퀀티 데이터들 다 업데이트하니까 필요없어". 그래서 이 러너는 적재하지 않는다 — 구 [0] qw_refresh.ps1 +
#     Gate A(원천 상태파일) · [1] daily_refresh.sh + [1b] sig 월 팩터DB 강제 재빌드 + IC · Gate B(앵커 내용)를 걷어냈다.
#     적재 · 팩터DB 월말 확정(+IC)은 데이터 리프레시 소관이다 — 밤 Qvest_DailyRefresh(daily_refresh.sh: 퀀티 Update_File ·
#     [6a] update_factor_db_daily 의 직전 달 finalize) · 부팅 ensure_data_current.sh. 그쪽이 원천을 전진시키지
#     못했으면 여기서 멈춘다(우회하지 않는다 · 원천 재적재 뒤 sig 월 팩터DB 재빌드도 그쪽 일이다).
#   잰다(소비면 · 관용이 아니라 도달): ① sig 일 = KRX 등록부 기준 AS_OF 직전 거래일 ② 벤치 sig 월 마지막 날 == sig
#     ③ 사양 runner_gate.sig_reach 의 파일마다 max(Date) ≥ sig(RAWDATA · 수급 · 컨센서스 계열별 · 유니버스 보조)
#     ④ factor_db_<sig 월> 앵커 == sig. 판정 정본 = book_rebalance_preflight.py --runner-gate(하위 [0c] 와 한 벌).
#   ★Gate A 를 검사로 남기지 않은 이유: 상태파일은 수신 기록이지 적재 증거가 아니다 — 11-06 실측 Consensus
#     ymd=20261105 인데 소비면 eps_1y 10-19 · op_profit_fy1 10-16 이었고, Benchmark 키는 10-17 벤치 정본 이관 뒤
#     20260828 에 멈춰 Gate A 는 매번 '미달'을 냈다. 구 Gate B 는 sig 일을 벤치 최대값에서 구해 벤치가 낡으면
#     sig 일도 같이 낡았다 — ①이 그 순환을 끊는다.
#   exit 24 (구 Gate A 10 · Gate B 21/22 퇴역). 하위 러너 [0c] 도 같은 판정 · 같은 코드.
"$PY" -c "import pandas, pyarrow" >/dev/null 2>&1 \
  || abort "GateI-python" "관문 실행기 기능 확인 실패($PY — pandas · pyarrow import) — 판정 없이 지나가지 않는다" 24
say "[0] Gate I: 입력 sig 일 도달 + 팩터DB 앵커 (검사만 — 리프레시 없음)"
GI="$(PYTHONUTF8=1 "$PY" "$QM_ROOT/02_Infrastructure/book/book_rebalance_preflight.py" \
        --book-id "$BOOK_ID" --as-of "$AS_OF" --runner-gate 2>>"$LOG" | tee -a "$LOG" | tail -n 1)"
_GI_RC=$?
say "  Gate I: ${GI:-BAD (관문 출력 없음)} (rc=$_GI_RC)"
[ "$_GI_RC" -eq 0 ] && [ "${GI#OK }" != "$GI" ] \
  || abort "GateI-inputs" "이번 리밸이 읽을 원천이 sig 일까지 오지 않았거나 팩터DB 앵커가 sig 일이 아님 — 러너는 적재하지 않는다(도훈 11-06). 데이터 리프레시 소관으로 이관(로그의 [BAD] 줄 확인)" 24

# ── Gate M — 국면 입력의 MSM 추정기 표식 + 신선도 (2026-11-06 · MSM-ASOF-SWITCH-20261017 D4 B · S3 · 적대 검토 #4·#15·#16·#19) ─────
#   동결 BOOK 엔진(factor_engine.R · m4)은 손대지 않는다. 대신 엔진이 읽는 통합 국면 신호
#   (.cache/unified_regime_signal.parquet)를 본다. 판정 정본 = 02_Infrastructure/ops/gate_msm_asof.sh — 예약 경로
#   run_nolayer4_monthly.sh [0b] 와 같은 스크립트 · 같은 판정이다(구판은 여기에 R 판정을 인라인으로 두었다 — 한 벌만 남긴다).
#     표식: 행 열 msm_estimator 고유값 = asof_yearly:v1 ∧ 파일 속성 같은 값(구 C1 판 · 표식 없음 · 혼합 = 중단 · 폴백 없음)
#     신선도: SIG_DATE(벤치에서 AS_OF 전 마지막 거래일 · sig 월 안) · sig 월 행 avail_date == SIG_DATE ·
#             일간 신호 max(Date) ≥ SIG_DATE. 구판은 표식만 봐서 밤 MSM 실패로 동결된 국면을 통과시켰다(검토 #16 —
#             찍던 max= 는 월말 라벨이라 내용이 언제까지인지 못 보여 줬다).
#   왜: 구판 MSM 은 1990~2026-01 전 표본 MLE 모수(PIT C1 — 결정 PIT-C1-MSM-PARAMS)라 m4 의 Cash_Pct ·
#   MSM_Crisis_Prob 입력이 미래 자료로 정해진 값이었다. 원장 재발행이 실패해 라이브가 구판으로 남는 경우를 잡는다.
#   ★여기 것은 조기 경보다 — [2] 의 run_nolayer4_monthly.sh 가 소비 직전([0b])에 같은 관문을 다시 건다(예약 경로와 한 지점).
#     낡음으로 막히면 데이터 리프레시(밤 MSM as-of 갱신 · 국면 원장 append) 뒤 재실행한다 — 러너는 갱신하지 않는다.
GM="$(bash "$QM_ROOT/02_Infrastructure/ops/gate_msm_asof.sh" "$AS_OF" "$QM_ROOT" 2>>"$LOG")"
_GM_RC=$?
say "  Gate M: ${GM:-BAD (관문 출력 없음)} (rc=$_GM_RC)"
[ "$_GM_RC" -eq 0 ] && [ "${GM#OK }" != "$GM" ] \
  || abort "GateM-msm" "통합 국면 신호가 as-of MSM 판이 아니거나 sig 월까지 전진하지 않음(${GM:-판독 실패}) — C1 · 낡은 국면으로 비중을 만들지 않는다([marker] = regime_append_only.R --republish 확인 · [sig_row]/[avail]/[daily] = 밤 MSM as-of 갱신 · 국면 원장 append 확인)" 23

# ── [2] 리밸 (비중 + monitor, Layer4 없음) + Gate C ─────────────────────────
say "[2] rebalance (run_nolayer4_monthly.sh, AS_OF=$AS_OF)..."
#   (구 PG2_REFRESH_DONE 플래그 제거 2026-11-06 — 하위 러너도 리프레시하지 않으므로 알릴 것이 없다)
PG2_AS_OF="$AS_OF" PG2_BOOK_ID="$BOOK_ID" \
  bash "02_Infrastructure/monitoring/run_nolayer4_monthly.sh" >> "$LOG" 2>&1
_NL4_RC=$?
# ★Gate M · Gate I 전파 (2026-11-06): 하위 러너가 [0b] Gate M(rc 23) 또는 [0c] Gate I(rc 24)에서 멈추면 이번 실행은
#   비중을 만들지 않았다. 그 rc 를 아래처럼 경고로 삼키면, 같은 AS_OF 의 이전 홀딩 CSV 가 남아 있을 때 Gate C 가 그것을
#   이번 산출로 보고 '완료'를 낸다. 위 조기 관문과 하위 관문 사이에 국면 · 원천 파일이 바뀌는 경우(밤 리프레시와 겹침)가
#   그 길이다. 다른 rc 는 종전대로 Gate C/D 가 최종 검증한다.
[ "$_NL4_RC" -eq 23 ] \
  && abort "GateM-msm-sub" "하위 러너 run_nolayer4_monthly.sh [0b] Gate M 차단 — 이번 실행은 비중 미산출(로그의 [0b] 줄 확인)" 23
[ "$_NL4_RC" -eq 24 ] \
  && abort "GateI-inputs-sub" "하위 러너 run_nolayer4_monthly.sh [0c] Gate I 차단 — 이번 실행은 비중 미산출(로그의 [0c] 줄 확인)" 24
[ "$_NL4_RC" -eq 0 ] || say "[warn] run_nolayer4_monthly 일부 step warn (rc=$_NL4_RC · Gate C가 최종 검증)"
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
