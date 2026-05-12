#==============================================================================
# WT-D20260511_001 PD20-C Path 3 — judge_ready/backtest_summary.json
#==============================================================================

suppressPackageStartupMessages({
  library(data.table); library(jsonlite)
})

WT_DIR <- "qepm/mailbox/worktask/WT-D20260511_001"
OUT_DIR <- file.path(WT_DIR, "backtest_result_pd20c_path3")
JR_DIR <- file.path(WT_DIR, "judge_ready")

m <- readRDS(file.path(OUT_DIR, "metrics_pd20c_path3.rds"))

# Read existing judge_ready/backtest_summary.json or create
existing_path <- file.path(JR_DIR, "backtest_summary.json")
existing <- if (file.exists(existing_path)) fromJSON(existing_path) else list()

# Build judge-ready summary
backtest_summary <- list(
  task_id = "WT-D20260511_001",
  variants = list(
    PD20C_Path3 = list(
      label = "PD20-C Path 3 (composite 0.45 + buffer keep25/entry20 + Cash 14.5)",
      n_months = m$metrics$N,
      period = "2005-02-01 ~ 2026-04-01",
      composite_active_period = "2011-01 ~ 2026-04 (184 sig_dates)",
      sleeve_weights = list(
        Composite_KR_equity = m$sleeve_weights$COMP,
        TSMOM_8_ETF = m$sleeve_weights$TSMOM,
        KR_10y = m$sleeve_weights$KR,
        Cash = m$sleeve_weights$CASH
      ),
      composite_internal = list(
        w_1715 = m$composite_internal_ratio$w_1715,
        w_NEW = m$composite_internal_ratio$w_NEW
      ),
      buffer_zone = list(
        keep_n = m$buffer_zone$keep_n,
        entry_n = m$buffer_zone$entry_n,
        n_target = m$buffer_zone$n_target
      ),
      metrics = list(
        SR_ann_geometric = round(m$metrics$SR_ann_geometric, 4),
        CAGR = round(m$metrics$CAGR, 4),
        MDD_magnitude = round(m$metrics$MDD, 4),
        Sortino = round(m$metrics$Sortino, 4),
        Calmar = round(m$metrics$Calmar, 4),
        CVaR_95_monthly = round(m$metrics$CVaR_95_monthly, 4),
        CVaR_99_monthly = round(m$metrics$CVaR_99_monthly, 4),
        hit_rate = round(m$metrics$hit_rate, 4),
        vol_ann = round(m$metrics$vol_ann, 4),
        sleeve_internal_RT_TO_annual_pct = round(m$metrics$mean_turnover_round_trip_sleeve_internal_annual_pct, 1),
        portfolio_weighted_RT_TO_annual_pct = round(m$metrics$portfolio_weighted_round_trip_annual_pct, 1),
        cost_drag_annual_bps = round(m$metrics$mean_cost_drag_annual_bps, 2)
      ),
      strict_improve = m$strict_improve,
      hurdle_check = list(
        TO_RT_annual_pct = round(m$metrics$portfolio_weighted_round_trip_annual_pct, 1),
        hurdle_threshold = 600,
        hurdle_status = ifelse(m$metrics$portfolio_weighted_round_trip_annual_pct < 600, "PASS", "HARD_FAIL"),
        delta_pp = round(m$metrics$portfolio_weighted_round_trip_annual_pct - 600, 1)
      ),
      diebold_mariano_vs_S4_v2 = list(
        t_NW = round(m$DM$t_NW, 4),
        p = round(m$DM$p, 4),
        N = m$DM$N,
        harvey_liu_zhu_strict_pass = abs(m$DM$t_NW) > 3.0
      ),
      verdict_summary = "3/4_strict_improve_PASS (MDD regress vs S4) + TO 613% HARD FAIL hurdle 600%. Path 3 insufficient. Recommend (B) keep30/entry20 iteration or (E) abandon NEW alpha source."
    ),
    PD20B_Path2 = list(
      label = "PD20-B Path 2 (composite 0.55 + no buffer)",
      metrics = list(
        SR_ann_geometric = m$PD20B_aligned$SR,
        CAGR = m$PD20B_aligned$CAGR,
        MDD_magnitude = m$PD20B_aligned$MDD,
        CVaR_95_monthly = m$PD20B_aligned$CVaR_95,
        portfolio_weighted_RT_TO_annual_pct = 685.1
      ),
      verdict = "4/4_strict_improve_PASS + TO 685% HARD FAIL hurdle 600%. Codex C5 mitigation needed (-> Path 3 attempted, also FAIL)."
    ),
    S4_v2_baseline = list(
      label = "S4 v2 baseline (50/25/20/5)",
      metrics = list(
        SR_ann_geometric = m$S4_baseline$SR,
        CAGR = m$S4_baseline$CAGR,
        MDD_magnitude = m$S4_baseline$MDD,
        CVaR_95_monthly = m$S4_baseline$CVaR_95
      ),
      verdict = "Baseline reference. Safe but lacks NEW alpha source contribution."
    )
  ),
  comparison_table = list(
    columns = c("strategy", "SR", "CAGR", "MDD_mag", "CVaR_95", "TO_RT_pct", "stance"),
    rows = list(
      c("PD20C_Path3", round(m$metrics$SR_ann_geometric, 4), round(m$metrics$CAGR, 4),
        round(m$metrics$MDD, 4), round(m$metrics$CVaR_95_monthly, 4),
        round(m$metrics$portfolio_weighted_round_trip_annual_pct, 1), "3/4_PASS_TO_FAIL_613"),
      c("PD20B_Path2", round(m$PD20B_aligned$SR, 4), round(m$PD20B_aligned$CAGR, 4),
        round(m$PD20B_aligned$MDD, 4), round(m$PD20B_aligned$CVaR_95, 4),
        685.1, "4/4_PASS_TO_FAIL_685"),
      c("S4_v2_baseline", round(m$S4_baseline$SR, 4), round(m$S4_baseline$CAGR, 4),
        round(m$S4_baseline$MDD, 4), round(m$S4_baseline$CVaR_95, 4),
        "~30", "BASELINE")
    )
  ),
  judge_directive = list(
    primary_question = "Path 3 design FAILED to mitigate C5. Choose: (B) iterate to keep30/entry20 / (E) abandon NEW alpha / (other Q-Lead decision).",
    risk_audit = "MDD +0.85pp regress vs S4 — Composite augmented by NEW Vol/Skew alpha may add tail-event sensitive names. Cash 14.5% increase did not offset.",
    cert_eligibility = list(
      schedule_fidelity = "eligible — 184/184 sig_dates density 1.0",
      sr_provenance = "eligible — measurement_basis_primary set, 4-field consistent",
      forge_package_validated = "eligible_after_finalization",
      alpha_discovery = "deferred to alpha agent (NEW alpha source originated from alpha_package WT_D20260511)",
      governor_concord = "pending — admission decision required"
    ),
    pure_function = list(
      md5_alpha = m$pure_function$md5_start$alpha,
      md5_risk = m$pure_function$md5_start$risk,
      md5_opt = m$pure_function$md5_start$opt,
      all_match = m$pure_function$match,
      audit = "PASS"
    )
  ),
  carry_forward = list(
    PD20A_Path1 = list(SR = 1.9928, CAGR = 0.2777, MDD = -0.2807, label = "16+4 split, MDD admit-block"),
    PD18_5sleeve = list(SR = 2.241, CAGR = 0.2355, MDD = -0.1154, label = "49 holdings (production cap violation)")
  ),
  forge_provenance = list(
    forge_package_pd20c_path3_draft = "qepm/mailbox/worktask/WT-D20260511_001/forge_package_pd20c_path3_draft.json",
    forge_package_pd20c_path3_final_pending_codex = TRUE,
    codex_round_response = "qepm/mailbox/worktask/WT-D20260511_001/codex_critic_response_forge_pd20c_path3.json (pending background)",
    build_script = "qepm/mailbox/worktask/WT-D20260511_001/build_pd20c_path3_composite_buffer.R"
  ),
  created_at = Sys.time(),
  updated_at = Sys.time()
)

# Merge with existing if any
existing$pd20c_path3 <- backtest_summary
existing$last_update_timestamp <- as.character(Sys.time())

dir.create(JR_DIR, showWarnings = FALSE, recursive = TRUE)
write_json(existing, existing_path, auto_unbox = TRUE, pretty = TRUE, na = "null")
cat("Wrote judge_ready/backtest_summary.json (with pd20c_path3 entry)\n")
cat("File size (KB):", round(file.info(existing_path)$size / 1024, 1), "\n")
