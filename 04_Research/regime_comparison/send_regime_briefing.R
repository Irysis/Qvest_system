library(data.table)
source("02_Infrastructure/config.R")
source("02_Infrastructure/telegram_notify.R")

cat("=== Regime Engine Briefing → Telegram ===\n")

output_dir <- file.path(RESEARCH_OUTPUT, "regime_comparison/output")
str373_dir <- file.path(RESEARCH_OUTPUT, "strategies/STR_373_cascade_bcs/output")

# ================================================================
# 1. 통합 브리핑 메시지
# ================================================================

msg1 <- '
<b>📊 국면 엔진 v1.1 성능 브리핑</b>
<b>3-Layer Cascade + BCS Behavioral Overlay</b>

━━━━━━━━━━━━━━━━━━━━━━━━
<b>▸ 아키텍처</b>
━━━━━━━━━━━━━━━━━━━━━━━━

Layer 1 (MSM): 조기탐지 | Recall 86.5% | max 40pt
Layer 2 (FRED MRS): 거시확인 | Precision 40% | max 35pt
Layer 3 (KTRI+VEA): 미시구조 | Precision 60.8% | max 15pt
Layer 4 (BCS): 행태 오버레이 | r=-0.143 | Q5→+15% cash

Score 분류:
  ≥70 → RISK_OFF (Cash 50-100%)
  45-69 → CAUTION (Cash 15-35%)
  25-44 → NEUTRAL (Cash 0%)
  &lt;25 → RISK_ON (Cash 0%)

━━━━━━━━━━━━━━━━━━━━━━━━
<b>▸ BCS (Behavioral Composite Score)</b>
━━━━━━━━━━━━━━━━━━━━━━━━

구성: VIX 3d변화(40%) + Complacency(25%)
      + Multi-Danger(15%) + Put OI변화(20%)

r(BCS, Fwd_1M) = -0.143 (최강 행태 신호)
Q1-Q5 spread = +2.52%/mo
Cascade 직교 (r=0.07) → 독립적 추가 정보

<b>위기 선행 탐지:</b>
  COVID: +80일 (2019-12-02 탐지 → 2020-02-20 crash)
  Rate Shock: +181일 (2021-07-08 → 2022-01-05)
  2015 China: +83일 | 2011 EU: +84일 | 2018 VIX: +20일
'
tg_send(msg1)
Sys.sleep(1)

# ================================================================
# 2. 위기 탐지 성과
# ================================================================

msg2 <- '
<b>📉 위기 탐지 성과</b>

━━━━━━━━━━━━━━━━━━━━━━━━
<b>▸ Regime Score Peak</b>
━━━━━━━━━━━━━━━━━━━━━━━━

GFC 2008-09: Score 81.2 → RISK_OFF | Cash 69%
COVID 2020-03: Score 74.2 → RISK_OFF | Cash 57%
Rate 2022-09: Score 64.4 → CAUTION | Cash 30%

━━━━━━━━━━━━━━━━━━━━━━━━
<b>▸ 전략 적용 결과 (STR_316 vs STR_373)</b>
━━━━━━━━━━━━━━━━━━━━━━━━

STR_316 [레짐: MRS≥30 binary]
  CAGR 16.1% | Sharpe 0.921 | MDD ~42% | Score 77.0 (A)

STR_373 [레짐: Cascade+BCS v1.1] ← 신규
  CAGR 14.7% | Sharpe 0.994 | MDD 36.2% | Score 71.4 (B)

변화: CAGR -1.4%p | Sharpe +0.073 | MDD -5.8%p

<b>위기 방어 Alpha:</b>
  GFC 2008: -16.2% vs BM -35.6% → Alpha +19.4%
  Rate 2022: -12.8% vs BM -26.1% → Alpha +13.4%
  COVID: -6.9% vs BM -4.6% → Alpha -2.3%

FF5 Alpha: 5.92%/yr (t=1.65)
최근 3Y Sharpe: 1.318 (개선 추세 ↑)

<b>결론:</b> CAGR 1.4%p 희생 → Sharpe +8%, MDD -5.8%p
위기 방어 목적에 최적화된 국면 모델
'
tg_send(msg2)
Sys.sleep(1)

# ================================================================
# 3. 전략 레짐엔진 적용 현황
# ================================================================

msg3 <- '
<b>🏷 전략 레짐엔진 적용 현황</b>

━━━━━━━━━━━━━━━━━━━━━━━━
<b>Grade A 전략 (8개) — 레짐: MRS≥30 binary</b>
━━━━━━━━━━━━━━━━━━━━━━━━

STR_316 [MRS binary] Score 77.0 | CAGR 16.1% | Sharpe 0.921
STR_298 [MRS binary] Score 76.4 | CAGR 16.1% | Sharpe 0.931
STR_304 [MRS binary] Score 76.5 | CAGR 16.0% | Sharpe 0.928
STR_324 [MRS binary] Score 74.3 | CAGR 16.1% | Sharpe 0.924
STR_303 [MRS binary] Score 73.9 | CAGR 16.3% | Sharpe 0.938
STR_290 [MRS binary] Score 66.6 | CAGR 16.0% | Sharpe 0.983
STR_269 [MRS binary] Score 65.4 | CAGR 16.2% | Sharpe 0.986
STR_271 [MRS binary] Score 65.4 | CAGR 16.2% | Sharpe 0.986

━━━━━━━━━━━━━━━━━━━━━━━━
<b>신규: Cascade+BCS v1.1 적용</b>
━━━━━━━━━━━━━━━━━━━━━━━━

STR_373 [Cascade+BCS] Score 71.4 | CAGR 14.7% | Sharpe 0.994
  → Sharpe 전체 최고 | MDD 36.2% 전체 최저
  → CAGR &lt; 16% → Grade B (위기방어 특화)

<b>레짐엔진 차이:</b>
  MRS binary: MRS≥30 → 100% cash-out (all or nothing)
  Cascade+BCS: graduated cash (0-100%) + BCS 행태 overlay
'
tg_send(msg3)
Sys.sleep(1)

# ================================================================
# 4. 차트 전송
# ================================================================

# 레짐 엔진 차트
regime_charts <- c(
  "regime_score_timeseries.png",
  "regime_vs_cumret.png",
  "layer_contributions.png",
  "bcs_daily_signal.png",
  "cash_allocation.png",
  "crisis_zoom_gfc.png",
  "crisis_zoom_covid.png",
  "crisis_zoom_rate shock.png"
)

cat("[tg] Sending regime charts...\n")
for (f in regime_charts) {
  path <- file.path(output_dir, f)
  if (file.exists(path)) {
    cap <- gsub("_", " ", tools::file_path_sans_ext(f))
    cap <- paste0("[레짐엔진] ", cap)
    tg_send_photo(path, caption = cap)
    Sys.sleep(0.5)
    cat(sprintf("  Sent: %s\n", f))
  }
}

# STR_373 차트
str_charts <- c("equity_curve.png", "annual_returns.png")
for (f in str_charts) {
  path <- file.path(str373_dir, f)
  if (file.exists(path)) {
    cap <- paste0("[STR_373 Cascade+BCS] ", gsub("_", " ", tools::file_path_sans_ext(f)))
    tg_send_photo(path, caption = cap)
    Sys.sleep(0.5)
    cat(sprintf("  Sent: %s\n", f))
  }
}

cat("\n=== Briefing Complete ===\n")
