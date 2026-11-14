#!/usr/bin/env bash
#==============================================================================
# Morning Regime Briefing — 매일 아침 7시
# 1) 데이터 최신화 (Arrow + KTRI + FRED + Regime Signal — RAWDATA 주가는 밤 퀀티 Update_File 단일 · 10-17 아침 KRX · Naver 보충 퇴역)
# 2) 텔레그램 레짐 브리핑 발송
#
# crontab: 10 7 * * 1-5 bash "/c/Users/99922/OneDrive/Quant_Module_Moltbot/02_Infrastructure/morning_briefing.sh"
#==============================================================================
set -uo pipefail  # -e 제거: 개별 스텝 실패해도 나머지 계속 실행
LOGFILE="/tmp/qm_morning_briefing_$(date +%Y%m%d).log"
exec > >(tee -a "$LOGFILE") 2>&1

echo "=== Morning Briefing @ $(date) ==="
source "$(dirname "${BASH_SOURCE[0]:-$0}")/resolve_project.sh"
INFRA="$BASE/02_Infrastructure"

# ── RAWDATA writer 잠금 (도훈 결정 OPS-RUNNER-REFRESH-BARRIER · 2026-09-24) ─────────────────────────────
#   [4.5/5] self_heal 창에 writer 잠금을 쥔다(강화 러너의 리프레시 배리어 refresh_barrier.sh 가 held 로 본다).
#   (10-17 · 결정 RAWDATA-QW-ONLY-20261017) 구 [1/5] krx_update · [1.5/5] naver_supplement 는 퇴역했고 self_heal 의 네이버 재수집도 뺐다 —
#   지금 아침 체인에 RAWDATA 를 쓰는 단계는 없다. self_heal 잠금은 MSM 재적합 창을 배리어에 보이게 남겨 둔 것이다(무해 · 짧다).
#   ★daily_refresh 잠금(/tmp/qm_daily_refresh.lock)과는 **다른** 잠금이다 — 같은 잠금을 쥐면 그 사이 뜬 daily_refresh 가
#     "이미 실행 중" 으로 종료해 버린다(daily_refresh.sh 무변경이 결정 조건).
#   판정기 부재면 no-op(브리핑은 그대로 돈다 — 막는 쪽인 배리어가 fail-closed 다). 보유자 = 이 셸($$) · EXIT 에서 해제.
if [ -f "$INFRA/ops/refresh_barrier.sh" ] && . "$INFRA/ops/refresh_barrier.sh"; then
  trap 'rb_writer_release' EXIT
else
  rb_writer_acquire() { return 0; }; rb_writer_release() { return 0; }
fi

# ── [0/5] 데이터 최신성 확보 — 브리핑보다 **먼저**, 그리고 필요하면 기다린다 ───
# 도훈 지시 2026-08-03. 실측 경합(같은 날 로그):
#   07:03 DailyRefresh 보충 실행 시작 → 07:10 이 브리핑 발화 → 07:50 리프레시 완료.
#   PC 가 00:03 에 꺼져 있던 날이면 브리핑이 **갱신 중 디스크**를 읽고 렌더한다.
#   아래 4.5 의 self-heal 층은 "리프레시가 이미 끝났다"는 전제로 설계돼 이 경우를 못 막는다.
# ensure_data_current.sh 는 (1) 진행 중 리프레시가 있으면 완료까지 대기하고
#   (2) 신선도를 실제로 **재고**, 이미 최신이면 아무것도 하지 않으며(중복 실행 방지)
#   (3) stale 일 때만 daily_refresh 를 돌린 뒤 **재감사**한다.
# ★rc=3(리프레시 후에도 stale)이어도 브리핑은 계속한다 — 침묵하는 것보다 "무엇이
#   오래됐는지 표기된 브리핑"이 낫다. 대신 그 사실을 로그와 스탬프에 남긴다.
echo "[0/5] 데이터 최신성 확보 (ensure_data_current)..."
if [ -f "$INFRA/ops/ensure_data_current.sh" ]; then
  bash "$INFRA/ops/ensure_data_current.sh"; EDC_RC=$?
  case "$EDC_RC" in
    0) echo "[0/5] 최신 확보됨" ;;
    3) echo "[0/5] ⚠ stale 잔존 — 브리핑은 계속하되 신선도 경보가 함께 나감" ;;
    *) echo "[0/5] ⚠ ensure_data_current 실행 실패(rc=$EDC_RC) — 브리핑 계속" ;;
  esac
else
  echo "[0/5] ⚠ ensure_data_current.sh 부재 — 최신성 미보장 상태로 진행"
fi

# 1 · 1.5 — 퇴역 (2026-10-17 도훈 '주가관련 복잡한 규칙들 모두 없애고 … 퀀티로 최신화' · 결정 RAWDATA-QW-ONLY-20261017)
#   구 [1/5] KRX Data Update(krx_run_pipeline) · [1.5/5] Naver T+0 Supplement(naver_run_pipeline). RAWDATA 주가 원천 = 퀀티 Update_File 단일
#   (밤 daily_refresh.sh [1pre-qw] → [0b']). 아침 보충 원천은 없다 — 밤 수급이 미완료면 위 [0/5] ensure_data_current 가 stale 을 보고한다.
echo "[1/5] (퇴역 10-17) RAWDATA 주가 = 퀀티 Update_File 단일 — 아침 KRX · Naver 보충 없음"

# 2. Arrow + KTRI 연장 (외부화 2026-06-19 — 동일 no-op 트랩 수리)
echo "[2/5] Arrow + KTRI..."
cd "$BASE"
Rscript --no-save -e 'source("02_Infrastructure/ops/morning_steps/arrow_extend.R")'
cd "$BASE"
# KTRI v3 signal rebuild + ktri_indices update (외부화 2026-06-13)
Rscript --no-save -e 'source("02_Infrastructure/ops/morning_steps/ktri_rebuild.R")'

# 3. FRED + Regime Signal 업데이트 (monthly + daily 모두 build)
echo "[3/5] FRED + Regime Signal..."
cd "$BASE"
Rscript --no-save -e 'source("02_Infrastructure/ops/morning_steps/fred_regime.R")'

# 4. 레짐 브리핑 발송 — 제거됨 (2026-05-13 도훈 mandate, 2-fire 해소)
# mrs_daily_briefing.sh (07:30) 가 tg_regime_briefing() 단일 송신 담당.
# 본 morning_briefing.sh (07:10) 는 데이터 갱신만 (Arrow/KTRI/FRED/Regime — RAWDATA 주가는 밤 퀀티 단일 · 10-17).
# 07:10 갱신 → 07:30 송신 20분 buffer 로 차트 최신화 보장.
echo "[4/5] Regime briefing — skipped (mrs_daily_briefing.sh 07:30 SOT)"

# 4.5. Self-healing refit — daily_refresh fail 대비 (도훈 mandate 2026-05-15)
# 캐시 stale 감지 시 자동 refit으로 사용자 개입 없이 정상화
# 구조: daily_refresh.sh 03:00 primary → morning_briefing.sh 07:10 self-heal layer
echo "[4.5/5] Self-healing refit (stale detection + auto-refit)..."
cd "$BASE"
rb_writer_acquire "self_heal" || echo "[4.5/5] ⚠ RAWDATA writer 잠금 획득 실패 — self-heal 은 계속(배리어 미표시)"
Rscript --no-save -e 'source("02_Infrastructure/ops/morning_steps/self_heal.R")'
rb_writer_release

# 5. Freshness audit — 모든 source 최신 거래일 검증 + stale 시 Telegram alert
# 2026-05-13 도훈 mandate: 구조적 자동 검증 (silent fail 방지)
echo "[5/5] Freshness audit..."
cd "$BASE"
# 외부 .R 파일로 분리 (2026-06-13): 인라인 -e 의 한글/이모지(⚠️🚨✅→) 리터럴이 bash→Windows-R
# 코드페이지 변환에서 깨져 "Execution halted"로 JSON 미작성되던 문제 해소. 파일은 UTF-8 정상 read.
# v10.4 (2026-09-24) 판정·JSON 은 그대로, 텔레그램은 억제 — 이 감사는 [6a] P3 생산 **전**이라 p3_forecast STALE 을
#   1~2분 뒤 스스로 해소될 상태로 보냈다(09-10·15·23·24, 조치 0). 발송은 [6a] 뒤 mrs_daily_briefing.sh:57 재감사 한 곳이 맡는다.
QVEST_FRESHNESS_QUIET=1 Rscript --no-save -e 'source("02_Infrastructure/ops/morning_steps/freshness_audit.R")'

echo "=== Morning Briefing Done @ $(date) ==="

# Step 5a2: 부활 신호원 신선화 — value_quality_spread deriver (구현 C, 2026-07-05)
#   실패지식 재부상 모니터(step 5b가 소비)가 참조하는 value_quality_spread(V02_EP dispersion)
#   parquet 을 리밸 이전에 최신화(지속가능). 외부 .R source(인라인 한글 -e 금지). fail-soft(|| true).
echo "[5a2/5] 부활 신호원 신선화 (value_quality_spread deriver)..."
cd "$BASE"
Rscript --no-save -e 'source("02_Infrastructure/ops/derive_value_quality_spread.R")' || true

# Step 5b: Axiom(DIST) 승인 대기 노출 (INV-6 재정의 2026-07-04 — 무인 활성화 금지)
#   자동초안+적대검증 완료된 status=proposed DIST 초안을 사람이 읽는 요약으로 노출(읽기 전용).
#   활성화(distilled 전환)는 도훈 배치 승인 게이트. fail-soft(|| true).
echo "[5b/5] Axiom 승인 대기 노출..."
cd "$BASE"
Rscript --no-save -e 'source("02_Infrastructure/ops/morning_steps/axiom_approval_queue.R")' || true

# Step 3: (v10 2026-09-03 제거) STR_905 daily NAV report — 대상 전략이 04_Research/strategies/ 에 없어
#   매일 "[NAV] Skip" 만 남기던 no-op 였다. BOOK 트래킹은 /book(book-tracker) 온디맨드가 정본이고,
#   BOOK_0001 일별 MTM 은 아래 Step 3b 가 담당한다. 되살릴 일이 있으면 git 2026-09-03 이전 판.

# Step 3b: noLayer4 PG2 book 데일리 mark-to-market (현 운용북 데일리 성과, 도훈 지시 2026-07-03 Layer4 제거 전환)
#   구 FaithTrend(Layer4) 호출은 mark_nolayer4_daily.R로 대체 (Layer4 제거 → noLayer4 book). 구 스크립트는 rollback 보존(deprecated).
echo "[3b] noLayer4 book 데일리 mark-to-market..."
QM_ROOT="$BASE" Rscript --no-save "$BASE/02_Infrastructure/monitoring/mark_nolayer4_daily.R" >> /tmp/qm_morning.log 2>&1 || echo "[nolayer4-daily] skip (홀딩 미산출 or 데이터 대기)"

# ──────────────────────────────────────────────────────────────────────────────
# Step 6: P3 (v3-fast Hansen, hparam-tuned) bearish forecast — daily inference + brief + 텔레그램 발송
# 도훈 mandate 2026-05-26: KOSPI 200 1일 분포 forecast (mu, sigma, nu, lam) + VaR/ES/P(폭락)
# P3 spec: α=6.68e-4, taus=11, train_min=3024 (~12y lookback) — Optuna trial 19
# ──────────────────────────────────────────────────────────────────────────────
# Step 5c (2026-11-10 감사 레인 B): 1계층(v10.2) 상태 한 통 · 무음 — 데이터 신선도 · 판 표식 · 상설 판 · 기저 풀 · 강화 사슬 · 결과 원장 · 열린 결정.
#   성과 수치 없음 · 칸 판독 실패 = '판독 불가'(체인 계속) · 정본 = morning_steps/l1_status_send.R
echo "[5c] 1계층 상태 (무음)..."
cd "$BASE"
Rscript --no-save -e 'source("02_Infrastructure/ops/morning_steps/l1_status_send.R")' >> /tmp/qm_morning.log 2>&1 || echo "[5c] l1_status 실패 (fail-soft)"

echo "[6/6] K200 일간 위험 브리핑 — 본 모형 H1 · P3 비교 기록 (2026-11-14 도훈 결정 K200-RISK-H1-REPLACE-P3-20261114)"
# 단계 정본 = morning_steps/k200_risk_brief.sh — 6a P3 601(비교 기록) · 6a' 실현값 · 6h H1 602 + 입력 점검 · 6b 603 발송 원천 결정
#   (H1 | P3 대체 | 수치 보류) · 6b' 613(P3 대체 때만) · 6c 발송(p3_brief_send.R · brief_meta.json).
#   구 [6/6] 블록(P3 단일 · 601 → 600 → 613 → p3_brief_send)은 git 태그 pre-k200-h1-20261114 판.
if [ -f "$INFRA/ops/morning_steps/k200_risk_brief.sh" ]; then
  bash "$INFRA/ops/morning_steps/k200_risk_brief.sh"
  echo "[6/6] k200_risk_brief exit=$?"
else
  echo "[6/6] ⚠ morning_steps/k200_risk_brief.sh 부재 — 발송기만 돌려 정체 경보를 낸다"
  cd "$BASE"
  Rscript --no-save -e 'source("02_Infrastructure/ops/morning_steps/p3_brief_send.R")' >> /tmp/qm_morning.log 2>&1
fi

echo "=== Morning Briefing Full Done @ $(date) ==="

