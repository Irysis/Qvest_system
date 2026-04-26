#==============================================================================
# Telegram brief for Risk WT-D20260426_007 (Iter 14)
# v4 ENFORCE: tg_agent_brief() only. ≥4 sections, emoji ≥5, bytes ≥1200.
#==============================================================================

suppressPackageStartupMessages({
  library(jsonlite)
})

PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
setwd(PROJECT_ROOT)
source("02_Infrastructure/telegram/telegram_notify.R")

# Estimator comparison table (≥2 rows × ≥2 cols)
estimator_df <- data.frame(
  Estimator = c("sample", "lw_oracle*", "lw_constcor", "gerber_rmt", "diag_shrink"),
  Cond = c(120.43, 38.28, 52.52, 47.64, 37.96),
  PSD = c("TRUE", "TRUE", "TRUE", "TRUE", "TRUE"),
  Selected = c("", "Y", "", "", ""),
  stringsAsFactors = FALSE
)

# Tail risk + stress narrative ≥50 chars
tail_text <- paste0(
  "EW universe-350-name long-only proxy (8790 daily obs, 2002-2023):\n",
  "- CVaR_95: -3.67% / VaR_95: -2.29% / CDaR_95: -46.14%\n",
  "- MDD in-sample: -60.46% (2008 GFC peak-trough)\n",
  "- EVT GPD: VaR_99=-5.52% / ES_99=-6.88% (gpd_mle, k=197)\n",
  "- Hill α (top-5%): 3.158 — finite variance + finite mean\n",
  "- Cornish-Fisher VaR_99: -5.29% (non-Normal adjusted)\n",
  "Worst stress: GFC_2008 cum_ret=-25.93% mdd=-56.99% (RF-R4 HIGH).\n",
  "Note: EW-350 PROXY — NOT Forge realized portfolio NAV."
)

# Risk flags ≥3 bullets
risk_flags <- c(
  "RF-CROWD-1656 HIGH — V2↔STR_1656 TDC q5 lower=0.4796 > 0.30 mandate (FAIL). Tail-coupled with diversifier.",
  "RF-CROWD-V2-BASE INFO — V2 score_str1701 vs Iter11 STR_1701 score_eff cor=0.057 (NOT ~1.0). V2 reconstructed slots — NOT same family. PG2 framework needs Governor reconsideration.",
  "RF-R4 HIGH — GFC_2008 cum_ret=-25.93% on EW universe-350 proxy. Escalated to Optimizer/Forge (not Risk-side gate).",
  "RF-R2 regime cond breach — CRISIS T=6 cond=4467, CAUTION T=28 cond=269, BULL T=87 cond=700. Pooled Σ fallback artifact written + binding rule bound.",
  "RF-R3 sector — top-decile concentration 14.3% (상사,자본재 / 화장품) — well-distributed."
)

# AX-002 compliance kv ≥3 named
compliance_kv <- list(
  PSD = "TRUE (min_eig=0.0131)",
  cond_post_ridge = "100.0 (boundary, λ=0.0104)",
  factor_R2_mean = "0.234 (FF5 v2, KR universe-350)",
  resolution_count = "9/9 mandatory (4A + 3P + 2R)",
  challenge_note = "authored (9 sections + sym findings)"
)

res <- tg_agent_brief(
  agent = "Risk",
  title = "WT-D20260426_007 RISK_DONE — Σ lw_oracle cond 100 (350-name)",
  sections = list(
    list(emoji = "🔬", heading = "Σ Estimator 비교", type = "table",
         df = estimator_df),
    list(emoji = "🌪️", heading = "Tail Risk + Stress (EW-350 proxy)",
         type = "text", body = tail_text),
    list(emoji = "🚩", heading = "Risk Flags (8건)",
         type = "bullet", items = risk_flags),
    list(emoji = "🎛️", heading = "AX-002 Compliance + Σ 진단",
         type = "kv", kv = compliance_kv),
    list(emoji = "🤝", heading = "Optimizer Handoff",
         type = "bullet", items = c(
           "Primary Σ: stage_artifacts/WT_D20260426_007/covariance.parquet (350×350, PSD, cond=100)",
           "Pooled fallback: covariance_pooled_fallback.parquet (T=80×N=244, cond=100) — BIND in CRISIS/CAUTION",
           "PG2 reconsider: V2 may be ADDITIVE alpha (not incremental). Forge realized NAV vs STR_1701 cor required.",
           "TDC q5=0.4796 fail — diversification benefit assumption needs realized verification"
         ))
  ),
  emoji_min = 5L
)

stopifnot(isTRUE(res$ok))
cat("Telegram brief sent. ok=", res$ok, "\n")
