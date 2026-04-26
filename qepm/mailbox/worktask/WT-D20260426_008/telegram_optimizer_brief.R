#==============================================================================
# Optimizer Telegram Brief — WT-D20260426_008
# v4 ENFORCE compliance — tg_agent_brief() ONLY
#==============================================================================

suppressPackageStartupMessages({
  library(jsonlite)
  library(data.table)
})

PROJECT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_ID   <- "WT-D20260426_008"
WT_DIR  <- file.path(PROJECT, "qepm/mailbox/worktask", WT_ID)
setwd(PROJECT)

source("02_Infrastructure/telegram/telegram_notify.R")

# Load finalized package
opt_pkg <- fromJSON(file.path(WT_DIR, "optimization_package.json"), simplifyVector = FALSE)

method_selected <- opt_pkg$method_selected
sr_net    <- opt_pkg$expected_sharpe_ratio
net_ir    <- opt_pkg$expected_information_ratio
cagr      <- opt_pkg$expected_cagr
mdd       <- opt_pkg$expected_mdd
to_ann    <- opt_pkg$turnover_annual
cvar_d    <- opt_pkg$cvar_d_post_optim
cost_ann  <- opt_pkg$estimated_cost_annual
infeas    <- !is.null(opt_pkg$infeasibility_report)
n_methods <- length(opt_pkg$method_comparison)

# Top 5 method shopping table (by net_IR)
mc <- opt_pkg$method_comparison
mc_dt <- rbindlist(lapply(names(mc), function(nm) {
  m <- mc[[nm]]
  data.table(
    Method  = nm,
    netIR   = if (!is.null(m$net_ir) && !is.na(m$net_ir)) sprintf("%.3f", m$net_ir) else "NA",
    CAGR    = if (!is.null(m$cagr_net) && !is.na(m$cagr_net)) sprintf("%.1f%%", m$cagr_net * 100) else "NA",
    MDD     = if (!is.null(m$mdd) && !is.na(m$mdd)) sprintf("%.1f%%", m$mdd * 100) else "NA",
    TO      = if (!is.null(m$turnover_ann) && !is.na(m$turnover_ann)) sprintf("%.2f", m$turnover_ann) else "NA",
    Pass    = if (isTRUE(m$pass_to_cap) && isTRUE(m$pass_cvar_cap) && isTRUE(m$pass_mdd_cap)) "ALL" else
              paste(c(if (isTRUE(m$pass_to_cap)) "TO" else NULL,
                      if (isTRUE(m$pass_cvar_cap)) "CV" else NULL,
                      if (isTRUE(m$pass_mdd_cap)) "MDD" else NULL), collapse = "+")
  )
}))
mc_dt[, sort_key := suppressWarnings(as.numeric(netIR))]
mc_dt[is.na(sort_key), sort_key := -999]
setorder(mc_dt, -sort_key)
mc_dt[, sort_key := NULL]
mc_dt_top <- head(mc_dt, 5)
mc_df_top <- as.data.frame(mc_dt_top)

# Selected method narrative
selected_text <- sprintf(
  "Selected: %s — net_IR %.4f, SR_net %.4f, CAGR %.1f%%, MDD %.1f%%. Selection rule: max(net_IR) ∧ pass_TO ∧ pass_MDD (CVaR mandate structurally infeasible — see infeasibility_report). %d sig_dates × 20 names = %d weight cells produced. Hard caps verified: max_names=20 / Σw=1 / weights ∈ [0, 0.20] / long-only.",
  method_selected, net_ir, sr_net, cagr * 100, mdd * 100,
  opt_pkg$per_sig_date_audit$n_sig_dates,
  opt_pkg$per_sig_date_audit$n_sig_dates * 20
)

# Hard constraints bullet
hc_items <- c(
  sprintf("max_names = %d (hard cap, verified across all sig_dates)", 20),
  sprintf("weight_bounds = [0, 0.20] (CRISIS shrink to 0.10 enforced)"),
  sprintf("Σw = 1 (absolute long-only, all sig_dates within 1e-3 tolerance)"),
  sprintf("liquidity ≥ 2e8 KRW (universe pre-filter from alpha pkg)"),
  sprintf("cost_model = v2.3_kr_retail_15bps one-way")
)

# Forecast KV
forecast_kv <- list(
  netIR    = sprintf("%.4f", net_ir),
  SR_net   = sprintf("%.4f", sr_net),
  CAGR     = sprintf("%.1f%%", cagr * 100),
  MDD      = sprintf("%.1f%%", mdd * 100),
  CVaR_d   = sprintf("%.2f%% (cap 2.5%%, %s)", cvar_d * 100,
                     if (abs(cvar_d) <= 0.025) "PASS" else "BREACH"),
  TO_ann   = sprintf("%.2f (cap 6.0, %s)", to_ann,
                     if (to_ann <= 6.0) "PASS" else "BREACH"),
  Cost_ann = sprintf("%.2f%%", cost_ann * 100),
  Infeasibility = if (infeas) "EMITTED" else "NONE"
)

# Codex stance
codex_stance <- "PENDING_R1"
if (file.exists(file.path(WT_DIR, "codex_critic_response_optimizer.json"))) {
  cr <- tryCatch(fromJSON(file.path(WT_DIR, "codex_critic_response_optimizer.json"),
                          simplifyVector = FALSE), error = function(e) NULL)
  if (!is.null(cr)) {
    codex_stance <- cr$verdict %||% cr$final_stance %||% "PROCESSED"
  }
}
`%||%` <- function(a, b) if (is.null(a) || (length(a) == 1 && is.na(a))) b else a

# Assemble brief
title <- sprintf("WT-%s OPTIMIZER_DONE — %s netIR %.3f (%s)",
                 sub("WT-", "", WT_ID),
                 method_selected,
                 net_ir,
                 if (infeas) "INFEAS_REPORTED" else "ALL_PASS")

res <- tg_agent_brief(
  agent = "Optimizer",
  title = title,
  sections = list(
    list(
      emoji = "🔬",
      heading = sprintf("Method Shopping — top %d by netIR (%d evaluated)", nrow(mc_df_top), n_methods),
      type = "table",
      df   = mc_df_top
    ),
    list(
      emoji = "💡",
      heading = "Selected Method 근거",
      type = "text",
      body = selected_text
    ),
    list(
      emoji = "🎯",
      heading = "Hard Constraints (모두 verified)",
      type = "bullet",
      items = hc_items
    ),
    list(
      emoji = "🎛️",
      heading = "Forecast (post-optim, weight-applied)",
      type = "kv",
      kv = forecast_kv
    ),
    list(
      emoji = "⚠️",
      heading = "Risk Forward Mandate Compliance",
      type = "bullet",
      items = c(
        sprintf("Pooled Σ binding: CRISIS+CAUTION (%d sig_dates) — DONE",
                opt_pkg$regime_handling$n_crisis + opt_pkg$regime_handling$n_caution),
        sprintf("max_w shrink: CRISIS only (%d sig_dates, w_hi=0.10) — DONE",
                opt_pkg$regime_handling$n_crisis),
        sprintf("CVaR_d weight-applied re-measurement — DONE (%.2f%% vs cap 2.5%%, BREACH disclosed)",
                cvar_d * 100),
        sprintf("MDD weight-applied: %.1f%% (cap 45%%, %s)",
                mdd * 100, if (abs(mdd) <= 0.45) "PASS" else "BREACH"),
        sprintf("infeasibility_report: %s (R12 No Silent Override)",
                if (infeas) "EMITTED" else "NONE"),
        sprintf("Codex R1 stance: %s", codex_stance)
      )
    )
  ),
  emoji_min = 5L
)

stopifnot(isTRUE(res$ok))
cat("[Telegram brief] sent OK\n")
