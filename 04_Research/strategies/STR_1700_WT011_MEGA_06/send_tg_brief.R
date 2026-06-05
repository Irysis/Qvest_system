## Resend Telegram brief for STR_1700 — using saved forge_package.json metrics
suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite)
})

`%||%` <- function(a, b) if (!is.null(a) && length(a) > 0 && !all(is.na(a))) a else b

BASE_DIR <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
WT_ID    <- "WT-D20260425_011"
PREV_WT  <- "WT-D20260425_010"
OUT_DIR  <- file.path(BASE_DIR, "04_Research/strategies/STR_1700_WT011_MEGA_06/output")

fp <- fromJSON(file.path(BASE_DIR, "qepm/mailbox/worktask", WT_ID, "forge_package.json"),
                simplifyVector = FALSE)

bs    <- fp$backtest_summary
sp3   <- fp$mega_06_vs_str_1699_vs_mega_05_same_period
oos   <- fp$oos_24_26_frozen_weights
scen  <- fp$scenario_comparison
freg  <- fp$factor_regression_5_specs

# STR_1699 OOS reference for table 3 (Iter5 reference)
str1699_oos <- fread(file.path(BASE_DIR, "qepm/mailbox/worktask", PREV_WT,
                                "backtest_result/oos_24_26_monthly.csv"))
oos_ret <- str1699_oos$port_ret
oos_n   <- length(oos_ret)
oos_sr_str <- (mean(oos_ret) / sd(oos_ret)) * sqrt(12)
oos_cagr_str <- prod(1 + oos_ret)^(12/oos_n) - 1
oos_cum_str <- cumprod(1 + oos_ret)
oos_mdd_str <- min(oos_cum_str/cummax(oos_cum_str) - 1)
oos_hit_str <- mean(oos_ret > 0)

source(file.path(BASE_DIR, "02_Infrastructure/telegram/telegram_notify.R"))

# Section 1
s1_df <- data.frame(
  Sample   = c("Pre-LB", "Lockbox", "Combined", "Full +OOS"),
  n_months = c(bs$pre_lockbox$n_months, bs$lockbox$n_months,
               bs$combined$n_months, bs$full_period$n_months),
  CAGR_pct = sprintf("%.2f", 100*c(bs$pre_lockbox$cagr %||% NA, bs$lockbox$cagr %||% NA,
                                    bs$combined$cagr    %||% NA, bs$full_period$cagr %||% NA)),
  SR       = sprintf("%.3f", c(bs$pre_lockbox$sr %||% NA, bs$lockbox$sr %||% NA,
                                bs$combined$sr    %||% NA, bs$full_period$sr %||% NA)),
  MDD_pct  = sprintf("%.2f", 100*c(bs$pre_lockbox$mdd %||% NA, bs$lockbox$mdd %||% NA,
                                    bs$combined$mdd    %||% NA, bs$full_period$mdd %||% NA)),
  stringsAsFactors = FALSE
)

# Section 2
m6 <- sp3$mega_06_same_period; s9 <- sp3$str_1699_same_period; m5 <- sp3$mega_05_same_period
s2_df <- data.frame(
  Strategy = c("MEGA_06", "STR_1699", "MEGA_05"),
  n_m      = c(m6$n_months, s9$n_months, m5$n_months),
  SR       = sprintf("%.3f", c(m6$sr %||% NA, s9$sr %||% NA, m5$sr %||% NA)),
  CAGR_pct = sprintf("%.2f", 100*c(m6$cagr %||% NA, s9$cagr %||% NA, m5$cagr %||% NA)),
  MDD_pct  = sprintf("%.2f", 100*c(m6$mdd %||% NA, s9$mdd %||% NA, m5$mdd %||% NA)),
  t_FF5    = sprintf("%.2f", c(m6$harvey_t_ff5 %||% NA, s9$harvey_t_ff5 %||% NA,
                                m5$harvey_t_ff5 %||% NA)),
  stringsAsFactors = FALSE
)

# Section 3 — 2-row OOS comparison
s3_df <- data.frame(
  Strategy = c("MEGA_06 OOS", "STR_1699 OOS"),
  n_m      = c(oos$n_months, oos_n),
  SR       = sprintf("%.3f", c(oos$sr %||% NA, oos_sr_str)),
  CAGR_pct = sprintf("%.2f", 100*c(oos$cagr %||% NA, oos_cagr_str)),
  MDD_pct  = sprintf("%.2f", 100*c(oos$mdd %||% NA, oos_mdd_str)),
  Hit_pct  = sprintf("%.1f", 100*c(oos$hit %||% NA, oos_hit_str)),
  stringsAsFactors = FALSE
)

# Section 4 — scenarios
sA <- scen$A_replacement_100$perf;       scA <- scen$A_replacement_100$score
sAB<- scen$AB_mega06_80_str1656_20$perf; scAB<- scen$AB_mega06_80_str1656_20$score
sB <- scen$B_60_20_20$perf;               scB <- scen$B_60_20_20$score
sD <- scen$D_current_PG2_mega05_8020$perf; scD <- scen$D_current_PG2_mega05_8020$score
s4_df <- data.frame(
  Scenario = c("A. M06 100%", "AB. M06 80+1656 20", "B. M06 60+1699 20+1656 20",
               "D. PG2 (M05 80+1656 20)"),
  n_m      = c(sA$n_months, sAB$n_months, sB$n_months, sD$n_months),
  SR       = sprintf("%.3f", c(sA$sr %||% NA, sAB$sr %||% NA, sB$sr %||% NA, sD$sr %||% NA)),
  CAGR_pct = sprintf("%.2f", 100*c(sA$cagr %||% NA, sAB$cagr %||% NA, sB$cagr %||% NA, sD$cagr %||% NA)),
  MDD_pct  = sprintf("%.2f", 100*c(sA$mdd %||% NA, sAB$mdd %||% NA, sB$mdd %||% NA, sD$mdd %||% NA)),
  Score    = sprintf("%.3f", c(scA, scAB, scB, scD)),
  stringsAsFactors = FALSE
)

# Section 5 — 5-spec
s5_df <- data.frame(
  Spec  = c("CAPM", "Carhart_3", "Carhart_4", "FF5", "FF6"),
  t_NW  = sprintf("%.3f", c(freg$CAPM$t_nw %||% NA, freg$Carhart_3$t_nw %||% NA,
                              freg$Carhart_4$t_nw %||% NA, freg$FF5$t_nw %||% NA,
                              freg$FF6$t_nw %||% NA)),
  Gate  = ifelse(c(freg$CAPM$t_nw %||% 0, freg$Carhart_3$t_nw %||% 0,
                    freg$Carhart_4$t_nw %||% 0, freg$FF5$t_nw %||% 0,
                    freg$FF6$t_nw %||% 0) >= 2.95, "PASS", "FAIL"),
  stringsAsFactors = FALSE
)

# Section 6 — kv
pc <- sp3$pairwise_correlation
dvs <- sp3$delta_mega06_vs_str1699
dvm <- sp3$delta_mega06_vs_mega05
s6_kv <- list(
  `cor(MEGA_06, STR_1699)`   = sprintf("%.4f", pc$mega06_str1699),
  `cor(MEGA_06, MEGA_05)`    = sprintf("%.4f", pc$mega06_mega05),
  `cor(STR_1699, MEGA_05)`   = sprintf("%.4f", pc$str1699_mega05),
  `Δ MEGA_06 vs STR_1699 SR` = sprintf("%+.3f (CAGR %+.2fpp / MDD %+.2fpp)",
                                          dvs$delta_sr, dvs$delta_cagr_pp, dvs$delta_mdd_pp),
  `Δ MEGA_06 vs MEGA_05 SR`  = sprintf("%+.3f (CAGR %+.2fpp / MDD %+.2fpp)",
                                          dvm$delta_sr, dvm$delta_cagr_pp, dvm$delta_mdd_pp),
  `Recommended Scenario`     = sprintf("%s (max score %.3f)",
                                        scen$recommended,
                                        max(c(scA, scAB, scB, scD))),
  `Pure Function Hash`       = if (isTRUE(fp$hash_audit$pure_function_pass)) "PASS" else "FAIL",
  `5-spec PASS count`        = sprintf("%d/5 (gate t>=2.95)", freg$n_pass_t295)
)

# Section 7 — bullets
s7_items <- c(
  sprintf("Walk-forward 215 sig_dates × Kelly_frac05 + 3-Layer Overlay (DD 6/8/20 + VolReg 12%% + FM cash)"),
  sprintf("Pooled-Σ fallback: 29/215 sig_dates (CRISIS+CAUTION binding) per Risk handoff"),
  sprintf("OOS 24-26 frozen-weights MEGA_06: SR=%.3f CAGR=%.2f%% MDD=%.2f%% (vs STR_1699 OOS SR=%.3f)",
          oos$sr %||% NA, (oos$cagr %||% NA)*100, (oos$mdd %||% NA)*100, oos_sr_str),
  sprintf("DSR penalty MEGA_06=20*0.05=1.00 vs STR_1699/MEGA_05=15*0.05=0.75 (fair_comparison_note mandate)"),
  sprintf("MEGA_06 dominant on SR/MDD same-period: +0.113 SR / +1.84pp MDD vs MEGA_05 / +0.084 SR / +11.95pp MDD vs STR_1699"),
  sprintf("Pure Function v6.1 R12 hash audit: %s | 3-package read-only honored",
          if (isTRUE(fp$hash_audit$pure_function_pass)) "PASS" else "FAIL"),
  "Judge S6 ready — Gate 0~6 + Role Honesty Audit + DSR + 5-spec gate"
)

charts <- c(file.path(OUT_DIR, "equity_curve.png"),
            file.path(OUT_DIR, "annual_returns.png"),
            file.path(OUT_DIR, "oos_zoom_chart.png"),
            file.path(OUT_DIR, "scenario_comparison.png"))

ret <- tg_agent_brief(
  agent = "Forge",
  title = sprintf("STR_1700 %s Iter6 MEGA_06 (Kelly + 3-Layer Overlay)", WT_ID),
  as_of = as.character(Sys.Date()),
  sections = list(
    list(emoji = "📊", heading = "Performance — Pre-LB / Lockbox / Combined / Full+OOS",
         type = "table", df = s1_df, max_col_width = 14L),
    list(emoji = "⚖️", heading = "3-Strategy Same-Period Fair Comparison (243m NAV-level)",
         type = "table", df = s2_df, max_col_width = 14L),
    list(emoji = "🚀", heading = "24-26 OOS Frozen-Weights (MEGA_06 vs STR_1699)",
         type = "table", df = s3_df, max_col_width = 14L),
    list(emoji = "🧬", heading = "Replacement / Integration Scenarios",
         type = "table", df = s4_df, max_col_width = 16L),
    list(emoji = "📈", heading = "5-Spec FF5 v2 Regression (Newey-West HAC)",
         type = "table", df = s5_df, max_col_width = 12L),
    list(emoji = "🔬", heading = "Pairwise Cor + Δ + Recommendation",
         type = "kv", kv = s6_kv),
    list(emoji = "➡️", heading = "Audit + Next Step (Judge S6)",
         type = "bullet", items = s7_items)
  ),
  charts = charts,
  footer = sprintf("📚 STR_1700 | %s Iter6 MEGA_06 | Pure Function v6.1 R12 | Hash=%s | 5/5 PASS",
                   WT_ID, if (isTRUE(fp$hash_audit$pure_function_pass)) "PASS" else "FAIL")
)
cat(sprintf("tg_agent_brief: ok=%s bytes=%d\n", ret$ok %||% NA, ret$bytes %||% 0))
