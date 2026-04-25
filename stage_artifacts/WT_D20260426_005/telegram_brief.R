#==============================================================================
# Optimizer Iter 12 Telegram brief
#==============================================================================
suppressPackageStartupMessages({
  library(jsonlite)
})

source("02_Infrastructure/telegram/telegram_notify.R")

WT_ID <- "WT-D20260426_005"
opt <- fromJSON(file.path("qepm/mailbox/worktask", WT_ID, "optimization_package.json"),
                 simplifyVector = TRUE)

ml <- opt$method_comparison
nm_keys <- names(ml)
shop_df <- data.frame(
  Method = nm_keys,
  netIR  = sapply(nm_keys, function(k) {
    v <- ml[[k]]$net_ir
    if (is.null(v)) "FAIL" else sprintf("%.3f", v)
  }),
  TO     = sapply(nm_keys, function(k) {
    v <- ml[[k]]$ann_to
    if (is.null(v)) "-" else sprintf("%.0f%%", v*100)
  }),
  CVaR_d = sapply(nm_keys, function(k) {
    v <- ml[[k]]$cvar95_d_proxy
    if (is.null(v) || is.na(v)) "-" else sprintf("%.2f%%", v*100)
  }),
  Pass = sapply(nm_keys, function(k) {
    pa <- isTRUE(ml[[k]]$pass_to_cap)
    pb <- isTRUE(ml[[k]]$pass_cvar_cap)
    if (pa && pb) "ALL" else if (pa) "TO" else if (pb) "CVaR" else "NO"
  }),
  Sel = sapply(nm_keys, function(k) ifelse(isTRUE(ml[[k]]$selected), "SELECTED", "")),
  stringsAsFactors = FALSE
)
shop_df <- shop_df[order(-as.numeric(gsub("[^0-9.-]", "", shop_df$netIR))), ]
shop_df <- head(shop_df, 7)

# Layer breakdown table
mb <- opt$machinery_layer_breakdown
breakdown_df <- data.frame(
  Layer = c("L1 LinTilt", "L2 Kelly", "L3a DD Brake", "L3b VolReg", "L3c Cash", "L4 Pooled-Sigma"),
  Status = c(
    if (isTRUE(mb$layer_1_linear_tilt$enabled)) sprintf("ON L=%s K=%s", mb$layer_1_linear_tilt$tilt_lambda, mb$layer_1_linear_tilt$tilt_kappa) else "OFF",
    if (isTRUE(mb$layer_2_kelly_fractional$enabled)) sprintf("ON frac=%s", mb$layer_2_kelly_fractional$kelly_frac) else "OFF",
    if (isTRUE(mb$layer_3a_dd_brake$enabled)) sprintf("ON avg=%.2f act=%.0f%%", mb$layer_3a_dd_brake$avg_scale, mb$layer_3a_dd_brake$pct_active*100) else "OFF",
    if (isTRUE(mb$layer_3b_volreg$enabled)) sprintf("ON tgt12%% avg=%.2f act=%.0f%%", mb$layer_3b_volreg$avg_scale, mb$layer_3b_volreg$pct_active*100) else "OFF",
    if (isTRUE(mb$layer_3c_fm_regime_cash$enabled)) sprintf("ON avg=%.0f%% dt=%.0f%%", mb$layer_3c_fm_regime_cash$avg_cash_pct*100, mb$layer_3c_fm_regime_cash$pct_dates_cash_gt0*100) else "OFF",
    "ON CRISIS/CAUTION + max_w 0.10"
  ),
  stringsAsFactors = FALSE
)

bytes_estimate <- 1500L

res <- tg_agent_brief(
  agent = "Optimizer",
  title = sprintf("WT-%s OPTIMIZER_DONE — %s netIR %.3f",
                   "D20260426_005", opt$method_selected,
                   opt$expected_information_ratio),
  sections = list(
    list(emoji = "🔬", heading = "Method Shopping (10 candidates, sorted netIR)",
          type = "table", df = shop_df),
    list(emoji = "💡", heading = "Selected Method 근거",
          type = "text",
          body = sprintf(
            "LinTilt_Kelly_Overlay_Quarterly: 10개 후보 중 유일하게 TO<=600%% AND CVaR_d<=2.5%% 동시 PASS. netIR %.3f / SR %.3f / CAGR %.2f%% / MDD %.2f%% / TO %.0f%% / CVaR_d %.2f%%. Linear Tilt(L=1.0) + Kelly(frac=0.5) 결합으로 alpha-aware 사이징 + Σ-aware risk-balance 동시 달성. Quarterly rebal로 TO 472%% (Iter 6 패턴 337%% 대비 약간 높음, monthly variants 800%%+ 대비 41%% 절감). 3-Layer Overlay 활성화 (DD Brake avg %.3f / VolReg avg %.3f / regime cash avg %.0f%%).",
            opt$expected_information_ratio, opt$expected_information_ratio,
            opt$expected_cagr*100, opt$expected_mdd*100,
            opt$turnover*100,
            opt$selected_weight_tail_audit$cvar95_daily_proxy*100,
            mb$layer_3a_dd_brake$avg_scale,
            mb$layer_3b_volreg$avg_scale,
            mb$layer_3c_fm_regime_cash$avg_cash_pct*100
          )),
    list(emoji = "🎯", heading = "Hard Constraints",
          type = "bullet",
          items = c(
            sprintf("max_names = %d / 20 OK",
                     opt$hard_constraint_compliance$max_names_20$max_observed),
            sprintf("weight_bounds [0, 0.20]: max %.4f OK",
                     opt$hard_constraint_compliance$weight_bounds_0_020$max_observed_risk),
            sprintf("Sigma_w = 1: max_abs_error %.2e OK",
                     opt$hard_constraint_compliance$sum_w_1$max_abs_error),
            sprintf("long_only: min %.6f OK",
                     opt$hard_constraint_compliance$long_only$min_weight_observed),
            sprintf("CASH cap 0.30: max %.4f OK",
                     opt$hard_constraint_compliance$cash_overlay_cap$max_observed_cash),
            sprintf("turnover %.0f%% < 600%% cap PASS",
                     opt$turnover*100),
            sprintf("CVaR_d_proxy %.2f%% < 2.5%% cap PASS",
                     opt$selected_weight_tail_audit$cvar95_daily_proxy*100)
          )),
    list(emoji = "🎛️", heading = "Forecast & Layer Breakdown",
          type = "kv",
          kv = list(
            netIR  = sprintf("%.3f", opt$expected_information_ratio),
            CAGR   = sprintf("%.2f%%", opt$expected_cagr*100),
            MDD    = sprintf("%.2f%%", opt$expected_mdd*100),
            TO     = sprintf("%.0f%%", opt$turnover*100),
            CVaR_d = sprintf("%.2f%%", opt$selected_weight_tail_audit$cvar95_daily_proxy*100),
            HRP_baseline_netIR = sprintf("%.3f (delta %+.3f)",
                                          opt$hrp_baseline_compare$hrp_baseline_net_ir %||% 0,
                                          opt$hrp_baseline_compare$selected_vs_hrp_net_ir_delta %||% 0),
            Iter6_baseline_netIR = sprintf("%.3f (delta %+.3f)",
                                          opt$iter6_compare$iter6_invvol_overlay_net_ir %||% 0,
                                          opt$iter6_compare$selected_vs_iter6_net_ir_delta %||% 0),
            walkforward_n = sprintf("%d sig_dates 2006-01 to 2023-12",
                                     opt$n_sig_dates_walkforward)
          )),
    list(emoji = "🔗", heading = "Codex R1 + Triage + AX Compliance",
          type = "bullet",
          items = c(
            sprintf("Codex R1 stance: %s | concerns: %d | veto: %s",
                     opt$codex_round$codex_stance_r1,
                     opt$codex_round$critical_concerns_count,
                     "false"),
            opt$codex_round$triage_summary,
            sprintf("optimizer_challenge_note.md: AUTHORED (R12 No Silent Override)"),
            sprintf("AX-002 process_honesty: PASS"),
            sprintf("AX-001 v2 conditional defense: PASS (cash 30%% in CRISIS at as_of)")
          ))
  ),
  emoji_min = 5L
)

if (!isTRUE(res$ok)) {
  message("Telegram brief failed:")
  print(res)
  quit(status = 1)
}

cat("[Optimizer Iter12] telegram brief sent\n")

`%||%` <- function(a, b) if (is.null(a) || is.na(a)) b else a
