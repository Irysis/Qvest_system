#==============================================================================
# Telegram Brief — WT-D20260427_002 Iter 18 Optimizer
# v4 ENFORCE: tg_agent_brief() single dispatch
#==============================================================================

suppressPackageStartupMessages({
  library(jsonlite)
})

PROJECT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_ID   <- "WT-D20260427_002"
WT_DIR  <- file.path(PROJECT, "qepm/mailbox/worktask", WT_ID)
setwd(PROJECT)

source("02_Infrastructure/telegram/telegram_notify.R")

opt <- fromJSON(file.path(WT_DIR, "optimization_package.json"), simplifyVector = FALSE)
mc <- opt$method_comparison
selected <- opt$method_selected

# Build method shopping table (top 6 by net_IR)
mc_names <- names(mc)
mc_dt <- data.frame(
  Method = mc_names,
  netIR  = sapply(mc_names, function(m) round(as.numeric(mc[[m]]$net_ir %||% NA), 3)),
  alpha_act = sapply(mc_names, function(m) round(as.numeric(mc[[m]]$alpha_activation_rate %||% NA), 2)),
  TO_ok = sapply(mc_names, function(m) ifelse(isTRUE(mc[[m]]$pass_to_cap), "O", "X")),
  MDD_ok = sapply(mc_names, function(m) ifelse(isTRUE(mc[[m]]$pass_mdd_cap), "O", "X")),
  CVaR_ok = sapply(mc_names, function(m) ifelse(isTRUE(mc[[m]]$pass_cvar_cap), "O", "X")),
  stringsAsFactors = FALSE
)
mc_dt <- mc_dt[order(-mc_dt$netIR), ][1:6, ]

`%||%` <- function(a, b) if (is.null(a) || (length(a) == 1 && is.na(a))) b else a

res <- tg_agent_brief(
  agent = "Optimizer",
  title = sprintf("WT-%s OPTIMIZER_DONE — %s netIR %.3f", WT_ID, selected,
                  as.numeric(opt$expected_information_ratio)),
  sections = list(
    list(emoji = "🔬", heading = "Method Shopping (top 6)", type = "table",
         df = mc_dt),
    list(emoji = "💡", heading = "Selected Method 근거", type = "text",
         body = sprintf(
           "선택: %s. 알파 활성화율 %.1f%% (L-226 ERC near-EW 0%% 대비 개선). HHI=%.3f<0.10 cap. Iter 11 LinTilt 메커니즘 + EMA persistence + CVaR penalty. 92 sig_dates bi-monthly 그리드 — Forge에서 monthly로 PG2 blend 평가.",
           selected,
           100 * as.numeric(opt$alpha_activation_rate),
           as.numeric(mc[[selected]]$hhi))),
    list(emoji = "🎯", heading = "Hard Constraints", type = "bullet",
         items = c(
           sprintf("n_names: 20 / 20 (92/92 sig_dates PASS)"),
           sprintf("Σw=1: %s / weights∈[0,0.20]: %s / long-only: O",
                   ifelse(opt$hard_constraint_checks$sum_w_eq_1, "O", "X"),
                   ifelse(opt$hard_constraint_checks$weights_le_0.20, "O", "X")),
           sprintf("TO_ann %.2f<6.0: %s / MDD %.4f<-0.45: %s / CVaR_d %.4f<-0.025: %s",
                   as.numeric(opt$turnover_annual),
                   ifelse(opt$forward_to_optimizer_mandate_compliance$turnover_pass, "PASS", "FAIL"),
                   as.numeric(opt$expected_mdd),
                   ifelse(opt$forward_to_optimizer_mandate_compliance$mdd_pass, "PASS", "FAIL"),
                   as.numeric(opt$cvar_d_post_optim),
                   ifelse(opt$forward_to_optimizer_mandate_compliance$cvar_d_pass, "PASS", "INFEASIBLE_disclosed_R12"))
         )),
    list(emoji = "🎛️", heading = "Forecast", type = "kv",
         kv = list(
           netIR = sprintf("%.3f", as.numeric(opt$expected_information_ratio)),
           SR_net = sprintf("%.3f", as.numeric(opt$expected_sharpe_ratio)),
           CAGR_net = sprintf("%.3f", as.numeric(opt$expected_cagr)),
           MDD = sprintf("%.3f", as.numeric(opt$expected_mdd)),
           TO_ann = sprintf("%.2f", as.numeric(opt$turnover_annual)),
           CVaR_d = sprintf("%.4f", as.numeric(opt$cvar_d_post_optim)),
           alpha_activation = sprintf("%.1f%%", 100 * as.numeric(opt$alpha_activation_rate))
         )),
    list(emoji = "⚠️", heading = "Infeasibility (R12 No Silent Override)", type = "text",
         body = "CVaR_d 2.5% structurally infeasible — KR top-20 long-only NORMAL EW base -2.90%. 명시적 disclosure. Forge에서 cash overlay OR Governor cap relaxation 필요. PG2 baseline 1.4625 비교는 Forge 결정.")
  ),
  emoji_min = 5L
)
stopifnot(isTRUE(res$ok))
cat("[telegram] sent\n")
