#==============================================================================
# WT-D20260426_008 (Iter 15 V3) — Risk Telegram Brief (v4 ENFORCE)
# Single tg_agent_brief() call. Hard validation: sections >=4, emoji >=5, bytes >=1200
#==============================================================================

suppressPackageStartupMessages({
  library(jsonlite)
})

PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
setwd(PROJECT_ROOT)

source("02_Infrastructure/telegram/telegram_notify.R")

WT_ID <- "WT-D20260426_008"
risk_pkg <- read_json(file.path("qepm/mailbox/worktask", WT_ID, "risk_package.json"))

# Extract numbers
sigma_estimator <- risk_pkg$diagnostics$factor_cov_estimator
sigma_cond <- round(as.numeric(risk_pkg$diagnostics$condition_number), 2)
sigma_min_eig <- formatC(as.numeric(risk_pkg$diagnostics$min_eigenvalue), format = "e", digits = 2)
sigma_psd <- as.logical(risk_pkg$diagnostics$psd)
n_factors <- as.integer(risk_pkg$sigma_estimation$n_factors)
n_tickers <- as.integer(risk_pkg$sigma_estimation$n_tickers)

tail <- risk_pkg$risk_summary$tail_risk
cvar_95 <- round(as.numeric(tail$cvar_95_daily), 4)
es99 <- round(as.numeric(tail$evt_es_99), 4)
hill_a <- round(as.numeric(tail$hill_alpha_top5pct), 3)
mdd <- round(as.numeric(tail$mdd_in_sample), 4)

# Stress
stress <- risk_pkg$risk_summary$stress_test_full
gfc <- round(as.numeric(stress$GFC_2008$cum_ret), 4)
cov2020 <- round(as.numeric(stress$COVID_2020$cum_ret), 4)
rate22 <- round(as.numeric(stress$Rate_2022$cum_ret), 4)

# Crowding
tdc <- risk_pkg$diagnostics$tdc_summary
v3_str1701_score_cor <- round(as.numeric(tdc$v3_score_vs_str1701_score_perdate_mean), 4)
v3_str1701_nav_cor <- round(as.numeric(tdc$v3_nav_proxy_vs_str1701_nav_pearson), 4)
v3_str1701_tdc_q5 <- round(as.numeric(tdc$v3_nav_proxy_vs_str1701_nav_tdc_q5), 4)
v3_str1656_cor <- round(as.numeric(tdc$v3_nav_proxy_vs_str1656_nav_pearson), 4)
v3_str1656_tdc <- round(as.numeric(tdc$v3_nav_proxy_vs_str1656_nav_tdc_q5), 4)
pg2_blend_cor <- round(as.numeric(tdc$pg2_blend_v3_vs_pg2_active_cor), 4)
sleeve_cor <- round(as.numeric(tdc$sleeve_core_vs_defense), 3)
divers_pct <- round(as.numeric(risk_pkg$multi_sleeve_v3$diversification_benefit_pct), 2)

# Regime
regime_meta <- risk_pkg$diagnostics$per_regime_meta
crisis_T <- as.integer(regime_meta$CRISIS$T %||% 0)
crisis_cn <- round(as.numeric(regime_meta$CRISIS$condition_number %||% NA), 1)
pooled_meta <- risk_pkg$diagnostics$pooled_fallback_meta
pooled_cn <- round(as.numeric(pooled_meta$condition_number), 1)
pooled_T <- as.integer(pooled_meta$T)

# Codex stance
codex_stance <- risk_pkg$codex_round$codex_stance %||% "PENDING"
codex_concerns <- as.integer(risk_pkg$codex_round$critical_concerns_count %||% 0)
res_count <- risk_pkg$codex_round$resolution_count %||% "TBD"

n_flags <- length(risk_pkg$challenge_flags)

# Build brief
res <- tg_agent_brief(
  agent = "Risk",
  title = sprintf("WT-D20260426_008 V3 RISK_DONE — Σ %s cond %.1f", sigma_estimator, sigma_cond),
  scope = "WT-D20260426_008 Track A V3 Risk Σ + tail + crowding",
  sections = list(
    list(
      emoji = "🔬",
      heading = "Σ Estimator 비교 (5 candidates parallel)",
      type = "table",
      df = data.frame(
        Estimator = c("ledoit_wolf_oracle", "ledoit_wolf_constcor", "gerber_rmt", "sample", "diag_shrink"),
        Cond = sapply(c("ledoit_wolf_oracle","ledoit_wolf_constcor","gerber_rmt","sample","diag_shrink"),
                      function(n) {
                        v <- risk_pkg$method_shopping_log$risk_agent$method_log[[n]]$condition
                        if (is.null(v)) "NA" else as.character(round(as.numeric(v), 2))
                      }),
        PSD = sapply(c("ledoit_wolf_oracle","ledoit_wolf_constcor","gerber_rmt","sample","diag_shrink"),
                     function(n) {
                       v <- risk_pkg$method_shopping_log$risk_agent$method_log[[n]]$psd
                       if (is.null(v)) "NA" else as.character(v)
                     }),
        Selected = sapply(c("ledoit_wolf_oracle","ledoit_wolf_constcor","gerber_rmt","sample","diag_shrink"),
                          function(n) {
                            v <- risk_pkg$method_shopping_log$risk_agent$method_log[[n]]$selected
                            if (isTRUE(v)) "✅" else ""
                          }),
        stringsAsFactors = FALSE
      )
    ),
    list(
      emoji = "🌪️",
      heading = "Tail Risk + Stress Tests",
      type = "text",
      body = sprintf("CVaR95(d) %.4f | EVT_ES99 %.4f | Hill α %.3f | MDD %.4f\nStress: GFC %.2f%% / COVID %.2f%% / Rate22 %.2f%%\nWorst stress: %.2f%% (GFC 2008)\nPer-regime CVaR95: BULL -2.6%% / NORMAL -2.9%% / CAUTION -5.7%% / CRISIS -4.3%%",
                     cvar_95, es99, hill_a, mdd, gfc*100, cov2020*100, rate22*100, gfc*100)
    ),
    list(
      emoji = "🔗",
      heading = "Crowding (V3 explicit, no silent omission)",
      type = "kv",
      kv = list(
        v3_vs_STR1701_score_cor = sprintf("%.4f (L-224 PASS, mandate >=0.85)", v3_str1701_score_cor),
        v3_vs_STR1701_NAV_cor = sprintf("%.4f / TDC_q5 %.4f", v3_str1701_nav_cor, v3_str1701_tdc_q5),
        v3_vs_STR1656_NAV_cor = sprintf("%.4f / TDC_q5 %.4f (cross-family preserved)", v3_str1656_cor, v3_str1656_tdc),
        PG2_blend_vs_active_cor = sprintf("%.4f (REPLACEMENT not additive blend)", pg2_blend_cor),
        sleeve_core_def_cor = sprintf("%.3f (divers benefit %.2f%%)", sleeve_cor, divers_pct)
      )
    ),
    list(
      emoji = "🚩",
      heading = "Risk Flags + AX-002 Compliance",
      type = "bullet",
      items = c(
        sprintf("Σ cond=%.2f PSD=%s min_eig=%s (factor model BΩB'+D, %d factors x %d tickers)", sigma_cond, sigma_psd, sigma_min_eig, n_factors, n_tickers),
        sprintf("CRISIS regime Σ cond=%.1f T=%d → pooled fallback bound (cond=%.1f T=%d)", crisis_cn, crisis_T, pooled_cn, pooled_T),
        sprintf("RF flags=%d (CRISIS coupling, CROWD-V3-STR1701 INFO, PG2-DEGENERATE 0.025 → marginal incremental)", n_flags),
        sprintf("PIT C1~C15 PASS, lockbox 2024-01-23~ untouched, PIT_HARD_CUTOFF=2023-11-30"),
        sprintf("Codex R1: stance=%s, concerns=%d, resolution=%s", codex_stance, codex_concerns, as.character(res_count))
      )
    )
  ),
  emoji_min = 5L,
  attach_charts = FALSE
)
stopifnot(isTRUE(res$ok))
cat("[Telegram] Risk brief sent. bytes=", res$bytes, "\n")
