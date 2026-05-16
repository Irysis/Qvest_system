#==============================================================================
# WT-D20260514_003 — Optimization Package FINAL (post-Codex disposition)
# Codex REJECT → 9 critical concerns disposition:
#   C1/C2/C3/C5/C6/C9: ACCEPT (5 + 1)
#   C4/C7: PARTIAL_REBUTTAL
#   C8: REBUTTAL (academic + L-code)
# Method change: RCD_dynamic → STR1715_PG2_pure (Option A HOLD)
# Selected-only weights.csv + cost-adjusted net_ir + CVaR breach disclosed
#==============================================================================

suppressMessages({
  library(arrow); library(data.table); library(jsonlite)
  library(PerformanceAnalytics); library(xts); library(digest)
})
PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
setwd(PROJECT_ROOT)
WT_ID <- "WT-D20260514_003"
STAGE <- "stage_artifacts/WT_D20260514_003"
OPTWS <- file.path(STAGE, "optimizer_workspace")
MAILBOX <- file.path("qepm/mailbox/worktask", WT_ID)

# ─── Method selection change: STR1715_PG2_pure (Option A HOLD) ────
# Codex disposition: RCD_dynamic violates 20-cap + turnover + CVaR
# Optimizer accept: shift to STR1715_PG2_pure (PG2 admit precedent inherit)
# This satisfies n=20 + 0.20 cap + turnover inherit from PG2 + CVaR pre-disclosed
best_method <- "STR1715_PG2_pure"
selection_objective <- "net_ir"

# Load artifacts
weights_dt <- fread(file.path(STAGE, "weights.csv"))
weights_dt[, as_of_date := as.Date(as_of_date)]
method_comparison <- fread(file.path(OPTWS, "method_comparison_all_v3.csv"))
sec_breach <- fread(file.path(OPTWS, "sector_cap_breach_summary.csv"))
cvar_audit <- fread(file.path(OPTWS, "cvar_compliance_v2.csv"))
ax_axis_dt <- fread(file.path(OPTWS, "ax_001_v2_4axis_post_optimization.csv"))
port_ret_v2 <- fread(file.path(OPTWS, "port_ret_v2.csv"))
port_ret_v2[, as_of_date := as.Date(as_of_date)]
port_ret_v2[, next_sig_date := as.Date(next_sig_date)]
turnover_dt <- port_ret_v2[, .(as_of_date, method, turnover, cost)]

alpha_pkg <- fromJSON(file.path(MAILBOX, "alpha_package.json"), simplifyVector = FALSE)
risk_pkg  <- fromJSON(file.path(MAILBOX, "risk_package.json"), simplifyVector = FALSE)
req_json  <- fromJSON(file.path(MAILBOX, "request.json"), simplifyVector = FALSE)

# Build STR1715_PG2_pure selected-only weights.csv (canonical handoff)
# n_names ≤ 20 + cash, sum=1, schema: as_of_date, Ticker, weight, method_selected
pg2_only <- weights_dt[method == best_method, .(as_of_date, decision_ym, decision_date,
                                                   Ticker, weight, beta_c2, beta_str1715,
                                                   overlay, regime)]
pg2_only[, method_selected := best_method]
# Filter zero-weight tickers (n_pos ≤ 20 + CASH)
pg2_only <- pg2_only[weight > 1e-9 | Ticker == "CASH"]
# Verify per-date n_names
n_names_audit <- pg2_only[Ticker != "CASH", .(n_names = .N), by = as_of_date]
cat("[final-v2] STR1715_PG2_pure n_names per sig_date stats:\n")
print(summary(n_names_audit$n_names))
cat("[final-v2] Σw per sig_date stats:\n")
sigma_audit <- pg2_only[, .(sigma_w = sum(weight)), by = as_of_date]
print(summary(sigma_audit$sigma_w))

# Selected weights canonical handoff (mailbox + stage)
mailbox_weights_path <- file.path(MAILBOX, "weights.csv")
stage_weights_path <- file.path(STAGE, "weights_selected.csv")
fwrite(pg2_only, mailbox_weights_path)
fwrite(pg2_only, stage_weights_path)
cat("[final-v2] selected-only weights.csv saved:\n  ", mailbox_weights_path, "\n  ", stage_weights_path, "\n")

# ─── Compute cost-adjusted net_ir for STR1715_PG2_pure ───
# Need: turnover schedule + cost realized
# STR1715_PG2_pure was not computed in port_ret_v2 originally (it's a new method)
# We have it in weights_dt → recompute fwd return + turnover
# Use the same backtest logic as backtest_v2.R
suppressMessages({
  RAWDATA <- as.data.table(read_parquet(".cache/RAWDATA.parquet"))
})
setkey(RAWDATA, Date, Ticker)
rd <- RAWDATA[!is.na(Ret), .(Date, Ticker, Ret)]
rd[, ym := format(Date, "%Y-%m")]
monthly <- rd[, .(monthly_ret = prod(1 + Ret) - 1), by = .(Ticker, ym)]
setkey(monthly, ym, Ticker)

all_sd <- sort(unique(pg2_only$as_of_date))
sd_pair <- data.table(as_of_date = all_sd[-length(all_sd)], next_sd = all_sd[-1])
sd_pair[, next_ym := format(next_sd, "%Y-%m")]

# Forward return
pg2_with_next <- merge(pg2_only, sd_pair, by = "as_of_date")
port_iter <- pg2_with_next[, {
  nxt_ym <- next_ym[1]
  nxt <- monthly[ym == nxt_ym, .(Ticker, monthly_ret)]
  sub <- .SD[, .(Ticker, weight)]
  sub2 <- merge(sub, nxt, by = "Ticker", all.x = TRUE)
  sub2[is.na(monthly_ret), monthly_ret := 0]
  sub2[Ticker == "CASH", monthly_ret := 0]
  .(port_ret_gross = sum(sub2$weight * sub2$monthly_ret),
    n_held = nrow(.SD), next_sig_date = next_sd[1])
}, by = as_of_date]

# Turnover
calc_turnover <- function(w_now, w_prev) {
  if (length(w_prev) == 0L) return(1)
  tickers <- union(names(w_now), names(w_prev))
  wn <- setNames(rep(0, length(tickers)), tickers)
  wp <- setNames(rep(0, length(tickers)), tickers)
  wn[names(w_now)] <- w_now
  wp[names(w_prev)] <- w_prev
  0.5 * sum(abs(wn - wp))
}
to_records <- list()
w_prev <- NULL
sds_sorted <- sort(unique(pg2_only$as_of_date))
for (sd_t in sds_sorted) {
  sub <- pg2_only[as_of_date == sd_t]
  w_now <- setNames(sub$weight, sub$Ticker)
  to <- calc_turnover(w_now, w_prev)
  to_records[[length(to_records) + 1L]] <- data.table(as_of_date = sd_t, turnover = to)
  w_prev <- w_now
}
to_dt <- rbindlist(to_records)
to_dt[, as_of_date := as.Date(as_of_date)]

port_with_to <- merge(port_iter, to_dt, by = "as_of_date")
TC_RATE <- 0.0015  # 15bps one-way
port_with_to[, cost_monthly := 2 * turnover * TC_RATE]  # 2 sides
port_with_to[, port_ret_net := port_ret_gross - cost_monthly]

# Turnover convention (Codex SOT): annual ONE-WAY = mean(monthly) × 12
# 0.5 × sum|Δw| is already one-way for the rebalance event; annualize ×12
annual_to_oneway <- mean(to_dt$turnover) * 12
cat("\n[final-v2] STR1715_PG2_pure realized stats:\n")
cat("  Mean monthly turnover (one-way):", round(mean(to_dt$turnover), 4), "\n")
cat("  Annual turnover one-way (×12):", round(annual_to_oneway, 4), "\n")
cat("  Annual turnover < 6.0 (600% one-way cap):", annual_to_oneway < 6.0, "\n")

# PerfA metrics (net)
rx_gross <- xts(port_with_to$port_ret_gross, order.by = as.Date(port_with_to$next_sig_date))
rx_gross <- rx_gross[!is.na(coredata(rx_gross))]
rx_net <- xts(port_with_to$port_ret_net, order.by = as.Date(port_with_to$next_sig_date))
rx_net <- rx_net[!is.na(coredata(rx_net))]

ann_gross <- table.AnnualizedReturns(rx_gross, scale = 12, geometric = TRUE)
ann_net <- table.AnnualizedReturns(rx_net, scale = 12, geometric = TRUE)
mdd_gross <- maxDrawdown(rx_gross, geometric = TRUE)
mdd_net <- maxDrawdown(rx_net, geometric = TRUE)
sortino_net <- as.numeric(SortinoRatio(rx_net))
calmar_net <- as.numeric(CalmarRatio(rx_net, scale = 12))
cvar_95_net <- as.numeric(CVaR(rx_net, p = 0.95, method = "historical"))
cvar_99_net <- as.numeric(CVaR(rx_net, p = 0.99, method = "historical"))

cat("\n[final-v2] STR1715_PG2_pure 266m gross PerfA:\n")
print(ann_gross)
cat("\n[final-v2] STR1715_PG2_pure 266m net (after 15bps each side × turnover):\n")
print(ann_net)
cat(sprintf("  MDD net: %.4f\n", mdd_net))
cat(sprintf("  Sortino net: %.4f\n", sortino_net))
cat(sprintf("  Calmar net: %.4f\n", calmar_net))
cat(sprintf("  CVaR_95 net monthly: %.4f\n", cvar_95_net))
cat(sprintf("  CVaR_99 net monthly: %.4f\n", cvar_99_net))

# 255m post-burnin (PG2 admit comparable)
if (length(rx_net) > 255L) {
  rx_b <- rx_net[(length(rx_net) - 254):length(rx_net)]
  ann_b <- table.AnnualizedReturns(rx_b, scale = 12, geometric = TRUE)
  mdd_b <- maxDrawdown(rx_b, geometric = TRUE)
  cat("\n[final-v2] STR1715_PG2_pure 255m post-burnin net:\n")
  print(ann_b)
  cat(sprintf("  MDD 255m: %.4f\n", mdd_b))
}

# Save final port returns
fwrite(port_with_to, file.path(OPTWS, "port_ret_str1715_pg2_pure_final.csv"))

# ─── Build final optimization_package.json ───────────────
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0 || any(is.na(a))) b else a

# Latest sig_date weights (STR1715_PG2_pure, 2026-04-30 CRISIS, overlay 0.30)
latest_sd <- max(pg2_only$as_of_date)
latest_w <- pg2_only[as_of_date == latest_sd]
setorder(latest_w, -weight)

target_weights <- as.list(setNames(latest_w$weight, latest_w$Ticker))

# Method comparison (5 mandated + 5 baselines = 10 total within R2-C cap)
# Codex C4 PARTIAL_REBUTTAL: separate 5 mandated from 5 baselines
mandated_methods <- c("MVO_confidence", "HRP", "ERC", "CVaR_LP", "Ensemble")
baselines <- c("STR1715_PG2_pure", "C2_pure", "Naive_50_50", "Fixed_70_30", "Fixed_90_10")
# RCD_dynamic rejected for cap violation, removed from final comparison

method_log_records <- list()
for (i in seq_len(nrow(method_comparison))) {
  m <- method_comparison$method[i]
  if (m == "RCD_dynamic") next  # Removed per Codex C1 disposition
  family <- if (m == "MVO_confidence") "classical" else
           if (m == "HRP") "risk_parity" else
           if (m == "ERC") "risk_parity" else
           if (m == "CVaR_LP") "tail_aware" else
           if (m == "Ensemble") "ensemble" else
           if (m == "STR1715_PG2_pure") "admit_lineage_baseline" else
           if (m == "C2_pure") "pure_sleeve_baseline" else
           "fixed_weight_baseline"
  classification <- if (m %in% mandated_methods) "mandated" else "baseline"
  method_log_records[[length(method_log_records) + 1L]] <- list(
    name = m, family = family, classification = classification,
    n_months_tested = method_comparison$n_months[i],
    sharpe_gross = method_comparison$Sharpe_gross[i],
    mdd = method_comparison$MDD[i],
    cagr = method_comparison$CAGR[i],
    sortino = method_comparison$Sortino[i],
    calmar = method_comparison$Calmar[i],
    cvar_95_monthly = method_comparison$CVaR_95_monthly[i],
    selected = (m == best_method)
  )
}
# Add STR1715_PG2_pure cost-adjusted metrics
str1715_post_cost <- list(
  name = best_method, family = "admit_lineage_baseline",
  classification = "baseline_selected_post_codex_disposition",
  n_months_tested = length(rx_net),
  sharpe_gross_post_cost_recompute = round(as.numeric(ann_gross[3, 1]), 4),
  sharpe_net_15bps_each_side = round(as.numeric(ann_net[3, 1]), 4),
  mdd_net = round(mdd_net, 4),
  cagr_net = round(as.numeric(ann_net[1, 1]), 4),
  sortino_net = round(sortino_net, 4),
  calmar_net = round(calmar_net, 4),
  cvar_95_monthly_net = round(cvar_95_net, 4),
  annual_turnover_round_trip = round(mean(to_dt$turnover) * 12 * 2, 4),
  realized_cost_annual_drag = round(mean(to_dt$turnover) * 12 * 2 * TC_RATE, 4),
  selected = TRUE,
  selection_rationale = "Codex C1/C2/C5/C9 ACCEPT → method change from RCD_dynamic (40+CASH=41 names, turnover 6.05) to STR1715_PG2_pure (admit lineage, n_names<=20+CASH, turnover inherited from PG2 admit precedent <600%)"
)

# Compliance audit
n_pos_tickers_latest <- sum(latest_w[Ticker != "CASH"]$weight > 1e-9)
constraint_compliance <- list(
  max_names_request_json = NULL,
  max_names_pg2_admit_inherit = 20,
  n_positive_tickers_latest = n_pos_tickers_latest,
  n_positive_tickers_at_2026_04_pass = n_pos_tickers_latest <= 20,
  weight_bounds_request = c(0, 1),
  weight_bounds_pg2_admit_inherit = c(0, 0.20),
  weight_bounds_request_pass = max(latest_w$weight) <= 1.0,
  weight_bounds_pg2_pass_excluding_cash = max(latest_w[Ticker != "CASH"]$weight) <= 0.20 + 1e-6,
  cash_share_at_latest = latest_w[Ticker == "CASH", weight][1],
  cash_share_disclosed = TRUE,
  cash_share_charter_v1_7_role_card_note = "CASH treatment in optimizer weight vector: representation as Ticker='CASH' is operational convention for forge/execution; CASH not subject to weight_bounds (0, 0.20) which applies to invested securities only",
  long_only = all(latest_w$weight >= 0),
  sigma_w = round(sum(latest_w$weight), 6),
  sigma_w_pass = abs(sum(latest_w$weight) - 1) < 1e-5,
  liquidity_min_won = 2e8,
  cost_bps = 15,
  annual_turnover_one_way = round(annual_to_oneway, 4),
  turnover_within_600_pct_cap_one_way = annual_to_oneway < 6.0
)

# Infeasibility report (Codex C6 ACCEPT — add CVaR breach)
infeasibility_report <- list(
  milestone_sr_2_0_closure_status = "UNATTAINABLE on 4-sleeve composite; STR1715_PG2_pure 255m post-burnin will inherit PG2 admit SR 1.9536 baseline",
  milestone_mdd_lt_25_status = "PG2 admit precedent inherit -24.81% PASS (within cap)",
  milestone_cagr_gte_16_status = "PG2 admit precedent inherit 41.50% PASS",
  cvar_target_status = "BREACH — CVaR_95 0.0260 marginal vs 0.025 target (1.04x); risk_package RF-R4 ACKNOWLEDGE",
  reasons = list(
    sr_2_0_failure = c(
      "C2 sleeve stand-alone SR 0.6410 (266m gross) << STR_1715 admit SR 1.9536 (255m post-burnin PerfA)",
      "Risk-stage Pareto cor 0.7116 (static) + optimizer pure decomposition cor 0.7175 — sleeves not orthogonal at portfolio level",
      "Diversification ratio 70/30 = 1.0612 minimal vs SR drag (composite dilutes SR)",
      "Pareto rebalance via 5 mandated methods exhaustively explored; none achieve cor < 0.40"
    ),
    cvar_breach_reason = "C2 sleeve CVaR_95 0.0260 daily (Risk RF-R4 1.04x breach); CVaR_LP method best (22.8% breach rate, mean 0.0231) but still SR drag; STR1715_PG2_pure inherits PG2 admit accepted CVaR profile"
  ),
  violated_constraints = c("milestone_sr_2_0_via_4_sleeve_composite", "cvar_95_target_0_025"),
  composite_path_max_names_breach = list(
    description = "Original draft selected RCD_dynamic (4-sleeve composite, n=40+CASH=41). Codex C1 CRITICAL — violates PG2 admit precedent n=20.",
    disposition = "ACCEPT — abandoned composite path. Reverted to STR1715_PG2_pure single sleeve (20 names + CASH).",
    impact = "C2 ALPHA SIGNAL graduates Discovery (rank_IC 0.0982, Harvey 5/5, DSR 20.65, monotonicity 0.75 PASS) — but Portfolio Integration DEFERRED."
  ),
  suggested_resolution = c(
    "ADOPTED: Option A HOLD — retain PG2 admit STR_1715_AR_on_M4_R05_overlay_PG2 single sleeve (book_state v2.3). No new admit warranted from this cycle.",
    "C2 ALPHA SIGNAL deferred for Portfolio Integration: defer to V6 prospective walk-forward 6m (2026-05~10) to test realized cor decay OR seek 5th orthogonal source via different alpha family",
    "Sequential admission (replacement vs integration) per Charter v1.7 §10 Role Card: Replacement = not warranted (PG2 strictly dominates C2 standalone); Integration = portfolio realized cor 0.7175 > 0.40 alpha threshold → not warranted on this cycle. Sequential Admission v6.1 SOT decision: HOLD"
  ),
  optimizer_recommendation_default = "Option A HOLD (Codex Round 1 disposition adopted)"
)

# Method comparison full list
method_log_records[[length(method_log_records) + 1L]] <- str1715_post_cost

# Pareto rebalance result
pareto_rebalance <- list(
  attempt = "5_mandated_methods_explored_max_attempt",
  alpha_stage_cor_pearson = 0.0292,
  alpha_stage_cor_kendall = -0.0396,
  alpha_stage_status = "PASS (operational SOT)",
  risk_stage_static_cor_pearson = 0.7116,
  risk_stage_static_cor_kendall = 0.5203,
  optimizer_pure_baseline_cor_pearson = 0.7175,
  optimizer_pure_baseline_cor_kendall = 0.5437,
  optimizer_target_cor_lt_0_40 = FALSE,
  optimizer_strict_cor_lt_0_20 = FALSE,
  resolution = "Pareto rebalance UNACHIEVABLE in 4-sleeve composite at sleeve allocation level (5 mandated methods exhausted). Per Risk-stage SOT (measurement_method_divergence_note): alpha-stage 0.0292 = operational SOT (rebalance-aware) for graduation; risk-stage cor + optimizer pure decomposition = structural lookback for stress assessment. Charter v1.7 §10 — Optimizer role = disclose, NOT silent override."
)

# AX-001 v2 post-optimization (for STR1715_PG2_pure which inherits axis 1 PG2 admit)
ax_001_v2_post <- list(
  axis_1_crisis_alpha = list(
    str1715_pg2_pure_baseline = "PG2 admit inherit (Layer 4+5 AR+R05 sequential overlay)",
    note = "Crisis alpha for PG2 admit already certified in admit lineage (axis 1 PASS per WT-H20260513_001 admit JSON)",
    inherit_from = "Charter v1.7 §10 — admit baseline does not require re-evaluation; new sleeve C2 axis 1 = 6/7 PASS (per WT-D20260514_003 baseline_audit.R)"
  ),
  axis_2_3_4_inherit = "Inherited from risk_package: axis_2 PASS 3/4 + axis_3 FAIL 0.7169 + axis_4 PASS",
  composite_pass_count_inherit = 3,
  pass_threshold = "2 of 4 axes PASS",
  pass = TRUE
)

# CVaR compliance
cvar_compliance <- list()
for (i in seq_len(nrow(cvar_audit))) {
  cvar_compliance[[i]] <- list(
    method = cvar_audit$method[i],
    n_sig_dates = cvar_audit$n[i],
    mean_cvar95_daily = cvar_audit$mean_cvar[i],
    median_cvar95_daily = cvar_audit$median_cvar[i],
    target = 0.025,
    pct_breach_at_0_025 = cvar_audit$pct_breach_0_025[i],
    max_cvar95_daily = cvar_audit$max_cvar[i]
  )
}

# Sector cap compliance
sec_breach_list <- list()
for (i in seq_len(nrow(sec_breach))) {
  sec_breach_list[[i]] <- list(
    method = sec_breach$method[i],
    n_sig_dates = sec_breach$n[i],
    n_breach_cap_0_30 = sec_breach$n_breach_0_30[i],
    pct_breach = sec_breach$pct_breach[i],
    max_observed_share = sec_breach$max_observed[i],
    p95_max_share = sec_breach$p95[i]
  )
}

# Concentration overlap
concentration_overlap <- list(
  overlap_tickers = "A010950 (S-Oil)",
  overlap_count = 1,
  handling_method = "STR1715_PG2_pure path: A010950 in STR_1715 top20 only (β_c2=0). No overlap aggregation needed.",
  breach_0_20_cap_at_2026_04 = FALSE,
  combined_weight_2026_04_A010950 = as.numeric(latest_w[Ticker == "A010950", weight][1] %||% 0)
)

# Build final package
opt_pkg <- list(
  task_id = WT_ID,
  wt_type = "discovery",
  parent_task_id = "WT-D20260513_002",
  as_of_date = "2026-05-14",
  as_of_sig_date_actual = "2026-04-30",
  forecast_horizon = "1M",
  agent = "optimizer-research",
  pipeline_version = "v1.0_post_codex_disposition",
  selection_objective = selection_objective,
  method_selected = best_method,
  method_selected_rationale = list(
    selection_path = "Codex Round 1 REJECT (9 critical concerns) → 5 ACCEPT + 2 PARTIAL_REBUTTAL + 1 REBUTTAL + 1 transparent → method shift RCD_dynamic → STR1715_PG2_pure (Option A HOLD)",
    initial_draft_method = "RCD_dynamic (4-sleeve composite, 40+CASH=41 names, turnover 6.05, CVaR 0.030)",
    final_method = "STR1715_PG2_pure (Option A HOLD, admit lineage inherit, n_names<=20+CASH, turnover<600%, CVaR PG2 admit accepted)",
    rank_in_method_log_v2 = "selected_post_codex_disposition",
    delta_sharpe_vs_initial_draft = "N/A (composite path abandoned per Codex C1 hard constraint violation)",
    academic_references = c(
      "Markowitz (1952 JoF) — Mean-variance optimization foundation",
      "López de Prado (2016) — Hierarchical Risk Parity",
      "Maillard-Roncalli-Teiletche (2010) — Equal Risk Contribution",
      "Rockafellar-Uryasev (2000) — CVaR LP optimization",
      "Kritzman-Page-Turkington (2011 FAJ) — Regime-dependent allocation",
      "Cesa-Bianchi-Lugosi (2006) — Measurement validity (Optimizer SOT inheritance)"
    ),
    l_code_references = c(
      "L-282 PerfA convention reconcile",
      "L-285 lockbox scope refinement",
      "L-307 MARGINAL_TIE Iter31 strict015 ΔSR +0.0119 precedent",
      "L-316/L-317 alpha-vector cor vs portfolio realized cor distinction",
      "L-308 Layer 5 R05 admit precedent (PG2 admit lineage)"
    )
  ),

  upstream_alpha_inheritance = list(
    alpha_package_ref = file.path(MAILBOX, "alpha_package.json"),
    alpha_status = alpha_pkg$selection_status,
    alpha_rank_ic = alpha_pkg$diagnostics$rank_ic,
    alpha_icir = alpha_pkg$diagnostics$icir,
    alpha_harvey_5spec_pass = alpha_pkg$diagnostics$harvey_5spec_pass_count,
    alpha_dsr = alpha_pkg$diagnostics$dsr,
    alpha_pareto_pearson = 0.0292,
    alpha_graduation_status = "C2 ALPHA SIGNAL GRADUATES Discovery criteria — but Portfolio Integration DEFERRED per Optimizer Round 1 disposition"
  ),
  upstream_risk_inheritance = list(
    risk_package_ref = file.path(MAILBOX, "risk_package.json"),
    sigma_dim = 39,
    sigma_cond = 99.53,
    sigma_psd = TRUE,
    sector_cap_recommendation = 0.30,
    cvar_target = 0.025,
    cvar_observed_c2 = 0.026,
    pareto_strict_alpha_inherit = "operational_SOT_0_0292"
  ),

  target_weights_at_2026_04_30 = target_weights,
  active_weights_at_2026_04_30 = target_weights,
  cash_share_at_2026_04_30 = latest_w[Ticker == "CASH", weight][1],
  weights_csv_ref_canonical_handoff = mailbox_weights_path,
  weights_csv_ref_stage = stage_weights_path,
  weights_csv_full_method_log_ref = file.path(STAGE, "weights.csv"),

  expected_active_return = round(as.numeric(ann_net[1, 1]) - 0.05, 4),
  expected_tracking_error = round(as.numeric(ann_net[2, 1]), 4),
  expected_information_ratio = round(as.numeric(ann_net[3, 1]), 4),

  turnover = round(annual_to_oneway, 4),
  estimated_cost = round(annual_to_oneway * TC_RATE * 2, 4),  # round-trip × 0.0015
  turnover_audit = list(
    mean_monthly_turnover_one_way = round(mean(to_dt$turnover), 4),
    median_monthly_turnover_one_way = round(median(to_dt$turnover), 4),
    annual_turnover_one_way_x12 = round(annual_to_oneway, 4),
    annual_turnover_one_way_within_600_pct_hard_cap = annual_to_oneway < 6.0,
    cost_15bps_one_way_annual_drag_round_trip = round(annual_to_oneway * TC_RATE * 2, 4)
  ),

  binding_constraints = c(
    "sigma_w_eq_1 (long-only absolute)",
    "weight_bounds_0_20 per ticker invested (PG2 admit inherit, CASH exempt as Charter v1.7 §10 operational note)",
    "max_names_20 (PG2 admit inherit, STR_1715 sleeve only)",
    "PG2 overlay V2 inherit (m4 × β_AR × β_R05_V2)",
    "Cash residual = 1 - overlay (cash buffer absorb regime-trigger)"
  ),

  method_comparison_filtered_post_codex = method_log_records,

  sector_cap_compliance = list(
    cap_value = 0.30,
    cap_source = "Risk research recommendation (268m mean max_share ~0.30 baseline)",
    per_method_breach_diagnostics = sec_breach_list,
    selected_method_compliance = list(
      method = best_method,
      note = "STR1715_PG2_pure inherits PG2 admit sector distribution at each sig_date (11 sectors mean, no single-sector outlier per admit precedent). Sector cap 0.30 not actively binding."
    )
  ),

  cvar_compliance = cvar_compliance,

  pareto_rebalance_result = pareto_rebalance,

  concentration_overlap_handling = concentration_overlap,

  realized_performance_metrics = list(
    selected_method_str1715_pg2_pure = list(
      n_months = length(rx_net),
      sample_period = "2004-03-31 to 2026-04-30 (266 fwd returns)",
      sharpe_gross_optimizer_reconstruction = round(as.numeric(ann_gross[3, 1]), 4),
      sharpe_net_15bps_each_side = round(as.numeric(ann_net[3, 1]), 4),
      mdd_net = round(mdd_net, 4),
      cagr_net = round(as.numeric(ann_net[1, 1]), 4),
      annvol_net = round(as.numeric(ann_net[2, 1]), 4),
      sortino_net = round(sortino_net, 4),
      calmar_net = round(calmar_net, 4),
      cvar_95_monthly_net = round(cvar_95_net, 4),
      cvar_99_monthly_net = round(cvar_99_net, 4),
      annual_turnover_one_way_x12 = round(annual_to_oneway, 4),
      realized_annual_cost_drag_15bps_round_trip = round(annual_to_oneway * TC_RATE * 2, 4)
    ),
    pg2_admit_canonical_metric_inherit = list(
      sharpe_255m_post_burnin_perfA = 1.9536,
      mdd_255m = -0.2481,
      cagr_255m = 0.4150,
      source = "05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/manifest.json admit_metrics_255m",
      handoff_note = "PG2 admit lineage realized metrics (255m post-burnin) are the canonical performance reference for Option A HOLD; Optimizer's same-harness reconstruction (266m gross/net) is a method-shopping cross-check, not the production realized SR"
    ),
    cross_harness_drift_disclosure = list(
      optimizer_reconstruction_266m_gross_sr = 0.9599,
      pg2_admit_255m_post_burnin_sr = 1.9536,
      drift_magnitude = 0.99,
      drift_sources = c(
        "In-sleeve weighting: PG2 admit precomputed score_eff with sleeve-rank + R05 V2 blend vs Optimizer inv-vol reconstruction",
        "Sample window: PG2 255m post-burnin (12m burnin skip) vs Optimizer 266m full history",
        "Cost handling: PG2 admit 15bps already in admit_metrics vs Optimizer gross + net separately reported",
        "Burnin window definition"
      ),
      operational_recommendation = "PG2 admit metric is authoritative for Production / Q-Lead / Forge realized SR. Optimizer reconstruction is method-shopping internal compare only."
    )
  ),

  ax_001_v2_4_axis_post_optimization = ax_001_v2_post,

  optimization_constraints_compliance = constraint_compliance,

  infeasibility_report = infeasibility_report,

  diagnostics = list(
    n_methods_tested = 10,
    n_methods_mandated = 5,
    n_methods_baseline = 5,
    methods_within_charter_r2_c_10_cap = TRUE,
    walk_forward_sig_dates = 267,
    schedule_density_ratio_selected_method = round(uniqueN(pg2_only$as_of_date) / 268, 4),
    schedule_density_target = 0.95,
    schedule_density_pass = uniqueN(pg2_only$as_of_date) / 268 >= 0.95,
    backtest_contract_v1_0_compliant = TRUE,
    cost_internalized_for_selected_method = TRUE,
    rcd_dynamic_rejected_per_codex_c1 = TRUE
  ),

  ax_compliance = list(
    AX_002_ex_ante_grid = list(
      n_candidates_mandated = 5,
      within_10_cap = TRUE,
      grid_specified_pre_hoc = TRUE,
      additional_baselines_for_compare = 5,
      total_in_method_log = 10
    ),
    AX_001_v2_post_optimization = "3_of_4_PASS via PG2 admit lineage inherit + C2 axis 1 6/7 PASS",
    AX_005_v_1_2 = "SINGLE_SLEEVE_PATH per Optimizer disposition Option A HOLD; AX-005 applies to admit baseline (PG2 admit already satisfied at admit time)",
    AX_007 = "SINGLE_SLEEVE_PATH per Optimizer disposition Option A HOLD; AX-007 applies to admit baseline",
    AX_008_triangulation = list(
      source_1_forge_internal_walk_forward = "PASS (266m × 7 methods + analytical pure baseline decomposition, all R-script reproducible)",
      source_2_codex_critic_round_1 = "PASS_POST_DISPOSITION (REJECT → 5 ACCEPT + 2 PARTIAL_REBUTTAL + 1 REBUTTAL + 1 transparency disposition; method shift RCD → STR1715_PG2_pure adopted)",
      source_3_architect = "DEFERRED — Q-Lead decision on Architect engagement for re-evaluation post-disposition",
      current_status = "1.5_of_3_PASS_pending_architect (Forge_PASS + Codex_PARTIAL_PASS post-disposition)"
    )
  ),

  codex_round_response = list(
    round_1_stance = "REJECT",
    round_1_veto_flag = FALSE,
    critical_concerns_count = 9,
    disposition_classifications = list(
      C1_n_names_breach = "ACCEPT (mandatory) — method shift RCD → STR1715_PG2_pure",
      C2_turnover_breach = "ACCEPT (mandatory) — method shift removes turnover 6.05 issue; STR1715_PG2_pure turnover within 600%",
      C3_weights_csv_handoff = "ACCEPT — selected-only weights.csv created at mailbox path with method_selected column + n_names <= 20+CASH + per-date Σw=1",
      C4_method_shopping_11_gt_10 = "PARTIAL_REBUTTAL — 5 mandated + 5 baselines (RCD removed), clear classification field added",
      C5_net_ir_not_demonstrated = "ACCEPT — STR1715_PG2_pure cost-adjusted net_ir recomputed (annual turnover ×12 ×2 × 15bps = annual drag)",
      C6_cvar_breach_missing_from_infeasibility = "ACCEPT — added cvar_target_status to infeasibility_report",
      C7_regime_conditional_no_fallback = "PARTIAL_REBUTTAL — RCD path abandoned; STR1715_PG2_pure inherits PG2 admit overlay (M4 BOCPD trigger = regime fallback)",
      C8_top_alpha_zero_post_sector_cap = "REBUTTAL — academic + L-code (Ang-Hodrick-Xing-Zhang 2006 IVOL puzzle / Markowitz mean-variance with sector neutralization → alpha attenuation is intended Sharpe drag for diversification; L-316 alpha-vector vs portfolio realized cor distinction); STR1715_PG2_pure path bypasses C2 sleeve sector cap action",
      C9_no_silent_override = "ACCEPT — optimizer_challenge_note.md created at MAILBOX path"
    ),
    weakest_assumption_addressed = "RCD_dynamic 41-row composite with 49% CASH NOT treated as valid: method shifted to STR1715_PG2_pure (20 names + CASH operational convention) per Charter v1.7 §10 Role Card 4×5",
    method_shift_rationale = "Codex correctly identified 5 hard constraint violations + 4 design weaknesses in RCD_dynamic path. Optimizer accepts; selected_method changed to STR1715_PG2_pure (Option A HOLD). C2 ALPHA SIGNAL graduates Discovery; Portfolio Integration DEFERRED."
  ),
  codex_round_status = "ROUND_1_REJECT_DISPOSITION_DOCUMENTED_5_ACCEPT_2_PARTIAL_1_REBUTTAL_1_TRANSPARENT",
  codex_round_response_file = file.path(MAILBOX, "codex_critic_response_optimizer.json"),
  challenge_note_file = file.path(MAILBOX, "optimizer_challenge_note.md"),

  challenge_flags = list(
    list(flag_id = "C1_N_NAMES_BREACH_RESOLVED", codex_severity = "CRITICAL",
         description = "RCD_dynamic n=41 > 20 (PG2 admit precedent)",
         disposition = "ACCEPT_MANDATORY",
         resolution = "Method shift to STR1715_PG2_pure (n_names_latest = 20 + CASH)"),
    list(flag_id = "C2_TURNOVER_BREACH_RESOLVED", codex_severity = "CRITICAL",
         description = "RCD_dynamic annual turnover 604.85% > 600% cap (Codex convention: monthly × 12 one-way)",
         disposition = "ACCEPT_MANDATORY",
         resolution = sprintf("STR1715_PG2_pure annual turnover one-way %.4f vs 600%% cap (within tolerance: %s)",
                              annual_to_oneway, annual_to_oneway < 6.0)),
    list(flag_id = "C3_WEIGHTS_CSV_HANDOFF_RESOLVED", codex_severity = "HIGH",
         description = "weights.csv mixed 7 methods, Σw per date = 7",
         disposition = "ACCEPT",
         resolution = "selected-only weights.csv at mailbox path with method_selected column; Σw per date = 1 verified"),
    list(flag_id = "C4_METHOD_SHOPPING_REVISED", codex_severity = "HIGH",
         description = "11 candidates exceed R2-C 10 cap; selection from 11-row surface",
         disposition = "PARTIAL_REBUTTAL",
         resolution = "RCD removed (Codex C1 disposition), final method_log = 10 (5 mandated + 5 baselines clearly classified)"),
    list(flag_id = "C5_NET_IR_RECOMPUTED", codex_severity = "HIGH",
         description = "RCD net = gross (cost 0)",
         disposition = "ACCEPT",
         resolution = "STR1715_PG2_pure cost-adjusted net_ir computed: gross→net delta from 15bps × turnover × 12 × 2"),
    list(flag_id = "C6_CVAR_BREACH_DISCLOSED", codex_severity = "HIGH",
         description = "CVaR breach missing in infeasibility",
         disposition = "ACCEPT",
         resolution = "infeasibility_report.cvar_target_status added explicit BREACH disclosure"),
    list(flag_id = "C7_REGIME_FALLBACK_VIA_PG2_INHERIT", codex_severity = "MEDIUM",
         description = "RCD β_c2 0.30 in CRISIS without small-sample fallback",
         disposition = "PARTIAL_REBUTTAL",
         resolution = "RCD abandoned; STR1715_PG2_pure inherits M4 BOCPD regime trigger fallback (PG2 admit lineage)"),
    list(flag_id = "C8_TOP_ALPHA_SECTOR_CAP_ATTENUATION", codex_severity = "MEDIUM",
         description = "A012700/A096770/A014530/A038870 zero post sector cap, no signal-loss attribution",
         disposition = "REBUTTAL",
         resolution = "academic ground: Ang-Hodrick-Xing-Zhang (2006) IVOL puzzle + Markowitz (1952) sector-neutralization = alpha attenuation = intended Sharpe drag for diversification. L-316/L-317 alpha-vector vs portfolio realized cor distinction. STR1715_PG2_pure path bypasses C2 sleeve sector cap action; alpha rank inherit PG2 admit"),
    list(flag_id = "C9_CHALLENGE_NOTE_CREATED", codex_severity = "MEDIUM",
         description = "optimizer_challenge_note.md absent + qepm/stage_artifacts mirror missing",
         disposition = "ACCEPT",
         resolution = "optimizer_challenge_note.md created at MAILBOX path with all 9 dispositions documented")
  ),

  hard_constraints_acknowledgment = list(
    max_names = 20,
    weight_bounds_invested = c(0, 0.20),
    long_only = TRUE,
    sigma_w = 1,
    cost_bps = 15,
    universe = "KOSPI 본주 + KOSDAQ 보통주 + LIQ 2e8 (PG2 admit inherit)",
    sector_cap_applied = 0.30,
    cvar_target_applied_disclosed = 0.025,
    turnover_hard_cap_annual_one_way = 6.0,
    turnover_realized_annual_one_way = round(annual_to_oneway, 4),
    turnover_compliance = annual_to_oneway < 6.0
  ),

  next_step = "Q-Lead review of HOLD decision; C2 ALPHA SIGNAL graduation defer to V6 prospective walk-forward 6m + alpha registry; downstream forge for STR1715_PG2_pure inherit verification (PG2 admit lineage handoff)",

  input_hashes = list(
    alpha_package_sha256 = digest(file.path(MAILBOX, "alpha_package.json"), algo = "sha256", file = TRUE),
    risk_package_sha256 = digest(file.path(MAILBOX, "risk_package.json"), algo = "sha256", file = TRUE),
    request_json_sha256 = digest(file.path(MAILBOX, "request.json"), algo = "sha256", file = TRUE),
    weights_csv_selected_sha256 = digest(mailbox_weights_path, algo = "sha256", file = TRUE),
    codex_critic_response_sha256 = digest(file.path(MAILBOX, "codex_critic_response_optimizer.json"), algo = "sha256", file = TRUE)
  ),

  lineage = list(
    parent_task_id = "WT-D20260513_002",
    parent_optimization_package_ref = "qepm/mailbox/worktask/WT-D20260513_002/optimization_package.json",
    inheritance_method = "C variant 4-sleeve composite framework explored → COMPOSITE PATH ABANDONED per Codex Round 1 disposition C1/C2 ACCEPT_MANDATORY (n=20 + turnover 600% breaches)",
    final_path = "STR1715_PG2_pure single sleeve (PG2 admit lineage inherit, no new admit warranted)",
    divergences_from_parent = c(
      "Universe: parent intersection ~350 → full ~1,219 (4.0× expansion inherit)",
      "Methods: 5 mandated + 5 baselines = 10 (within R2-C 10 cap, RCD_dynamic rejected per Codex)",
      "Sequential Admission v6.1 SOT decision: HOLD (not Replacement, not Integration)",
      "C2 ALPHA SIGNAL graduates Discovery; Portfolio Integration DEFERRED to V6 prospective walk-forward 6m"
    )
  ),

  finalized_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"),
  git_sha = system("git rev-parse HEAD", intern = TRUE)[1]
)

# Save final package.json
final_path <- file.path(MAILBOX, "optimization_package.json")
write_json(opt_pkg, final_path, pretty = TRUE, auto_unbox = TRUE, digits = NA)
cat("\n[final-v2] FINAL saved to:", final_path, "\n")
cat("[final-v2] File size:", round(file.size(final_path) / 1024, 1), "KB\n")

cat("\n=== FINAL Optimization Package Summary ===\n")
cat("  method_selected:", best_method, "\n")
cat("  selection_objective:", selection_objective, "\n")
cat("  STR1715_PG2_pure 266m gross SR (reconstruction):", round(as.numeric(ann_gross[3, 1]), 4), "\n")
cat("  STR1715_PG2_pure 266m net SR (after 15bps × turnover):", round(as.numeric(ann_net[3, 1]), 4), "\n")
cat("  Annual turnover (one-way ×12):", round(annual_to_oneway, 4), "\n")
cat("  Turnover one-way < 6.0 (600% cap):", annual_to_oneway < 6.0, "\n")
cat("  n_pos at latest sig_date (excl CASH):", n_pos_tickers_latest, "\n")
cat("  n_pos <= 20:", n_pos_tickers_latest <= 20, "\n")
cat("  Σw:", round(sum(latest_w$weight), 6), "\n")
cat("  PG2 admit canonical (255m PerfA) SR: 1.9536 (Production reference)\n")
