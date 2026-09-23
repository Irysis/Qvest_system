#!/usr/bin/env bash
#==============================================================================
# Morning Regime Briefing — 매일 아침 7시
# 1) 데이터 최신화 (KRX + Naver T+0 + Arrow + KTRI + FRED + Regime Signal)
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

# 1. KRX 데이터 최신화
echo "[1/5] KRX Data Update..."
cd "$BASE"
Rscript --no-save -e 'source("02_Infrastructure/ops/morning_steps/krx_update.R")'

# 1.5 Naver T+0 보완 (KRX T+1 발행지연 gap을 Naver로 채움)
# ★외부화 2026-06-19(도훈): 기존 인라인 멀티라인 -e가 첫 줄 invisible(NULL)만 실행되는 no-op 트랩이라
#   naver_run_pipeline()이 한 번도 안 돌았음 → 단일줄 source로 수리.
echo "[1.5/5] Naver T+0 Supplement..."
cd "$BASE"
Rscript --no-save -e 'source("02_Infrastructure/ops/morning_steps/naver_supplement.R")'

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
# 본 morning_briefing.sh (07:10) 는 데이터 갱신만 (KRX/Naver/Arrow/KTRI/FRED/Regime).
# 07:10 갱신 → 07:30 송신 20분 buffer 로 차트 최신화 보장.
echo "[4/5] Regime briefing — skipped (mrs_daily_briefing.sh 07:30 SOT)"

# 4.5. Self-healing refit — daily_refresh fail 대비 (도훈 mandate 2026-05-15)
# 캐시 stale 감지 시 자동 refit으로 사용자 개입 없이 정상화
# 구조: daily_refresh.sh 03:00 primary → morning_briefing.sh 07:10 self-heal layer
echo "[4.5/5] Self-healing refit (stale detection + auto-refit)..."
cd "$BASE"
Rscript --no-save -e 'source("02_Infrastructure/ops/morning_steps/self_heal.R")'

# 5. Freshness audit — 모든 source 최신 거래일 검증 + stale 시 Telegram alert
# 2026-05-13 도훈 mandate: 구조적 자동 검증 (silent fail 방지)
echo "[5/5] Freshness audit..."
cd "$BASE"
# 외부 .R 파일로 분리 (2026-06-13): 인라인 -e 의 한글/이모지(⚠️🚨✅→) 리터럴이 bash→Windows-R
# 코드페이지 변환에서 깨져 "Execution halted"로 JSON 미작성되던 문제 해소. 파일은 UTF-8 정상 read.
Rscript --no-save -e 'source("02_Infrastructure/ops/morning_steps/freshness_audit.R")'

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
echo "[6/6] P2 bearish forecast brief..."
P2_BF_DIR="$BASE/04_Research/decision_framework/bearish_forecast_v3"
P2_PY=""
for _c in "$BASE/.venv_qvest_ml/Scripts/python.exe" "$BASE/.venv_qvest_ml/bin/python"; do
  [ -x "$_c" ] && P2_PY="$_c" && break
done
if [[ -x "$P2_PY" && -d "$P2_BF_DIR" ]]; then
  # 6_pre. 벤치 **교차검증**(KOSPI200) — 도훈 mandate 2026-05-28, 2026-09-18 역할 변경.
  #   ★구판은 여기서도 benchmark.parquet 을 썼다(두 번째 writer). 축 정규화 후 갱신기의
  #     기본 모드는 **검증만**이고, 쓰기는 daily_refresh 의 [1pre] 한 곳으로 모았다 —
  #     브리핑이 데이터를 바꾸면 "브리핑을 봤더니 값이 달라져 있다" 가 된다.
  cd "$BASE"
  # ★2026-09-23 실사고: 구판은 `| tail -5 || true` 로 교차검증 rc 를 버렸다 — 트립와이어가 '1120.74(장중) vs 1123.59'
  #   를 잡았는데도 [6a] 가 그 장중 벤치로 P3 추론을 진행했다. rc 를 보존하고 rc=1(트립와이어)이면 추론을 건너뛴다.
  _BMV_LOG="/tmp/qm_bm_verify_$(date +%Y%m%d_%H%M%S).log"
  "$P2_PY" 02_Infrastructure/data/naver_benchmark_update.py --start_date $(date -d "7 days ago" +%Y-%m-%d) > "$_BMV_LOG" 2>&1
  _BMV_RC=$?
  tail -5 "$_BMV_LOG"
  cd "$P2_BF_DIR"
  # 6a. daily inference (오늘 forecast 추가) — P3.
  # [2026-06-01 fix] 601 default(no --asof)는 ret_fwd-dropna로 마지막 행이 잘려 benchmark_max-1(1일 stale)을
  #   forecast → brief가 매일 1일 정체. benchmark 최신 종가일을 --asof로 명시(검증된 forecast-only 경로)해 재발 방지.
  ASOF_BM=$("$P2_PY" -c "import pandas as pd; print(pd.to_datetime(pd.read_parquet('$BASE/.cache/benchmark.parquet', columns=['Date'])['Date']).max().date())" 2>/dev/null)
  if [[ "$_BMV_RC" == "1" ]]; then
    echo "[6a] SKIP — 벤치 교차검증 트립와이어 발화(rc=1 · $_BMV_LOG) — 불일치 벤치로 P3 추론하지 않는다(전일 예측 유지)"
  elif [[ -n "$ASOF_BM" ]]; then
    echo "[6a] 601 inference --asof $ASOF_BM (benchmark 최신 종가일)"
    "$P2_PY" scripts/601_daily_inference.py --model P3 --asof "$ASOF_BM" 2>&1 | tail -5
  else
    echo "[6a] ASOF_BM 추출 실패 — default 경로 fallback"
    "$P2_PY" scripts/601_daily_inference.py --model P3 2>&1 | tail -5
  fi
  # 6a'. y_actual backfill (이전 forecast row의 realized 1d return 채움, 도훈 mandate 2026-05-28)
  "$P2_PY" -c "
import pandas as pd, numpy as np, sys, os
sys.path.insert(0, '$P2_BF_DIR/03_models')
import p1_hansen_skewt as HSK
p3_path = '$P2_BF_DIR/03_models/daily_predictions/P3_daily.parquet'
p3 = pd.read_parquet(p3_path); p3['Date'] = pd.to_datetime(p3['Date']); p3 = p3.sort_values('Date').reset_index(drop=True)
bm = pd.read_parquet('$BASE/.cache/benchmark.parquet'); bm['Date'] = pd.to_datetime(bm['Date']); bm = bm.sort_values('Date').reset_index(drop=True)
bm['log_ret'] = np.log(bm['BM_Close']).diff() * 100
fwd_map = bm.assign(ret_fwd=bm.log_ret.shift(-1)).set_index('Date')['ret_fwd'].to_dict()
n_filled = 0
for i, row in p3.iterrows():
    if pd.isna(row['y_actual']) and row['Date'] in fwd_map:
        fwd = fwd_map[row['Date']]
        if pd.notna(fwd):
            p3.loc[i, 'y_actual'] = fwd
            try:
                pit = HSK.pit_per_obs(np.array([fwd]), np.array([row['mu']]), np.array([row['sigma']]), np.array([row['nu']]), np.array([row['lam']]))[0]
                p3.loc[i, 'pit'] = pit
            except Exception: pass
            n_filled += 1
p3.to_parquet(p3_path)
print(f'[y_actual backfill] {n_filled} rows filled')
" 2>&1 | tail -2
  # 6b. brief 생성 (markdown + dist.png + trend.png)
  "$P2_PY" scripts/600_morning_brief.py 2>&1 | grep -v "Glyph\|UserWarning" | tail -3
  # 6b'. Risk Pro 9-Quadrant 강화 대시보드 (도훈 mandate 2026-05-27)
  cd "$BASE"
  Rscript "$BASE/04_Research/decision_framework/bearish_forecast_v3/scripts/613_p3_9quad_riskpro.R" 2>&1 | tail -2 || true
  # 6c. 텔레그램 발송 (latest brief) — 외부화 2026-06-13 (한글/이모지 인라인 -e 깨짐 해소)
  cd "$BASE"
  Rscript --no-save -e 'source("02_Infrastructure/ops/morning_steps/p3_brief_send.R")' >> /tmp/qm_morning.log 2>&1
else
  echo "[6/6] SKIP — venv or v3 dir missing"
fi

echo "=== Morning Briefing Full Done @ $(date) ==="

