# Judge Pilot 8 Telegram — tg_agent_brief SOT (title 형식 강제)
suppressPackageStartupMessages({
  library(data.table); library(jsonlite)
})

PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
source(file.path(PROJECT_ROOT, "02_Infrastructure/telegram/telegram_notify.R"))

# ─── Section 1: Gate 판정 표 ─────────────────────────────
gate_df <- data.frame(
  Gate = c("A PIT", "B ISO", "C NET_ALPHA", "D CROWDING", "E CONCENTRATION", "F DRIFT"),
  Verdict = c("PASS", "PASS_W_NOTES", "COND_FAIL", "FAIL", "PASS", "FAIL"),
  Note = c(
    "C1~C15 OK, lockbox sealed",
    "opt hash first PASS, alpha null",
    "Forge SR 0.51 breakthrough",
    "MarketRisk 77.6% (P7 39)",
    "n=20 HHI 0.062 PASS",
    "Lockbox -93% collapse"
  ),
  stringsAsFactors = FALSE
)

# ─── Section 2: Pilot 6/7/8 성과 비교 표 ─────────────────
compare_df <- data.frame(
  Metric = c("Forge SR", "Forge CAGR", "Forge MDD", "Forge ActIR",
             "LB SR", "LB CAGR", "LB ActIR", "Market_Risk", "β_port"),
  P6 = c("0.066", "1.18%", "-63.9%", "N/A",
         "1.086", "20.37%", "-1.079", "50.3%", "0.75"),
  P7 = c("0.258", "4.69%", "-55.2%", "-1.033",
         "1.020", "21.31%", "-1.033", "39.0%", "0.75"),
  P8 = c("0.510", "9.19%", "-47.0%", "+0.582",
         "0.073", "1.20%", "-1.942", "77.6%", "1.022"),
  stringsAsFactors = FALSE
)

# ─── Section 3: Lockbox regime decomposition ─────────────
regime_df <- data.frame(
  Regime = c("RISK_ON", "NEUTRAL", "CAUTION"),
  Days_pct = c("68.7%", "27.0%", "4.3%"),
  Strat_SR = c("0.340", "0.083", "-1.017"),
  BM_SR = c("1.746", "1.732", "4.295"),
  Active_IR = c("-1.78", "-1.64", "-4.78"),
  stringsAsFactors = FALSE
)

# ─── Section 4: β 철학 breakthrough 해석 ──────────────────
beta_interp <- paste(
  "<b>β 철학 3-source convergence 실증 양면</b>",
  "✅ <b>Forge window 2012-2024 BREAKTHROUGH</b>",
  "  • SR 0.258→0.510 (+97% threshold 0.5 최초 PASS)",
  "  • Active IR -1.033→+0.5815 (+1.61 역전)",
  "  • P4~P7 4 pilot 연속 negative 최초 positive 전환",
  "  • Grinold-Kahn Active IR 정통 기여 Forge-level 실증",
  "",
  "❌ <b>Lockbox OOS 2024-2026 INVALIDATION</b>",
  "  • SR 1.020→0.073 (-93% 붕괴)",
  "  • Active IR -1.033→-1.942 (-0.909 악화)",
  "  • 5 pilot 연속 negative + 4 pilot 최악 갱신",
  "  • 모든 regime Active IR 악화 (P7 대비)",
  "",
  "🔥 <b>Forge↔Lockbox 10.2x divergence 구조</b>",
  "  • β philosophy = regime-dependent (not universal law)",
  "  • Forge train window 금융위기 포함 regime mix에 fit",
  "  • Lockbox KOSPI 강세 regime에 misfit 증폭",
  sep = "\n"
)

# ─── Section 5: L-code 권고 ───────────────────────────────
l_items <- c(
  "L-198 신설 (candidate) — β Philosophy Lockbox Invalidation",
  "L-196 upgraded (candidate → VALIDATED) — MinVar 3rd consecutive",
  "L-195a upgraded (candidate → VALIDATED_ORTHOGONAL) — sub-universe fix necessary not sufficient",
  "L-197 partial_refutation_update — β-constrained bottleneck 재정의"
)

# ─── Section 6: Pilot 9 방향 ──────────────────────────────
p9_items <- c(
  "Path B Multi-sleeve 즉시 진입 (AX-007 예외 'multi-sleeve' 공식 트리거)",
  "Alpha sleeve: alpha top-20 직접 선발 + MinVar penalty-free",
  "Beta-neutral sleeve: KOSPI200 etf 또는 low-variance factor hedge",
  "β corridor 0.85~1.0 + market_risk hard 40% 재복귀 (β soft 확대 실패 학습)",
  "OR regime-conditional β (RISK_ON 0.85 / NEUTRAL 0.95 / CRISIS 0.70)",
  "rolling 5Y SR + Active IR stability tracking 의무화"
)

# ─── Title (judge_init.md 강제 포맷) ──────────────────────
title <- "WT-D20260424_006 Pilot 8 GRADE_D / DISCARD_WITH_STRUCTURAL_REVELATION"

# ─── 발송 ─────────────────────────────────────────────────
result <- tg_agent_brief(
  agent = "Judge",
  title = title,
  as_of = "2026-04-24",
  sections = list(
    list(
      type = "table", heading = "Gate A~F 판정 (6 gates)",
      emoji = "⚖️", df = gate_df, max_col_width = 30
    ),
    list(
      type = "table", heading = "Pilot 6/7/8 누적 비교 (9 metrics)",
      emoji = "🔍", df = compare_df, max_col_width = 10
    ),
    list(
      type = "table", heading = "Lockbox 4-Regime Decomposition (487 days)",
      emoji = "🔒", df = regime_df, max_col_width = 10,
      notes = c("strategy_essence 기각 (BM 3 regime 압도)",
                "regime_lucky 기각 (RISK_ON 68.7% < 80% threshold)",
                "L-196 minvar_superior 3rd consecutive 확정")
    ),
    list(
      type = "text", heading = "β 철학 breakthrough vs invalidation",
      emoji = "💡", body = beta_interp
    ),
    list(
      type = "bullet", heading = "L-code 권고 (4 entries)",
      emoji = "📚", items = l_items
    ),
    list(
      type = "bullet", heading = "Pilot 9 방향 (Path B Multi-sleeve)",
      emoji = "➡️", items = p9_items
    )
  ),
  footer = paste(
    "🎯 <b>Judge Opus 4.7 단독 판정</b>",
    "📊 Forge Full Active IR +0.58 ↔ Lockbox Active IR -1.94 = 10.2x 분기",
    "🔒 Lockbox access log 8-entry (AX-002 준수)",
    "⚠️ β philosophy regime-dependent 실증 — Path B Multi-sleeve 필수",
    sep = "\n"
  ),
  force = TRUE  # force=TRUE 명시 (Risk/Optimizer skip 사례 방지)
)

cat("\n=== Telegram 발송 결과 ===\n")
cat("ok:", result$ok, "\n")
cat("bytes:", result$bytes %||% "NA", "\n")
if (!isTRUE(result$ok)) {
  cat("error:", result$error, "\n")
  stopifnot("Telegram 발송 실패" = FALSE)
}

stopifnot("tg_agent_brief 발송 실패 — force=TRUE retry 필요" = isTRUE(result$ok))
cat("✅ Telegram 발송 성공\n")
