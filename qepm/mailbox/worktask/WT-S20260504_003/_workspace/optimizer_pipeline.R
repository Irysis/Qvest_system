#==============================================================================
# WT-S20260504_003 Optimizer Research Pipeline
# HMM Regime — Sizing-only / recommendation_only
#
# Inputs:
#   - risk_package.json (HMM 3-state, walk-forward signal primary)
#   - hmm_posterior_path_walkforward.csv (PIT-clean, 207 valid rows from 2009-03 onwards)
#   - weight_scale_path.csv (smoothed; superseded by walk-forward derivation here)
#   - parent WT-P20260429_002 weights.csv (M4 cash schedule, 267m)
#
# Outputs (canonical):
#   - stage_artifacts/WT_WT-S20260504_003/weights.csv (M4+HMM_Scale primary)
#   - stage_artifacts/WT_WT-S20260504_003/weights_variants/{S1,HMM_Scale,M4+HMM_Scale}.csv
#   - stage_artifacts/WT_WT-S20260504_003/cash_definition_audit.json
#   - stage_artifacts/WT_WT-S20260504_003/lro_portfolio_mrc.csv
#   - qepm/mailbox/worktask/WT-S20260504_003/optimization_package_draft.json
#==============================================================================

suppressPackageStartupMessages({
  library(jsonlite)
  library(data.table)
  library(zoo)
  library(digest)
})

PROJ_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_ID <- "WT-S20260504_003"
PARENT_WT <- "WT-P20260429_002"
AS_OF_DATE <- "2026-05-04"

WT_DIR <- file.path(PROJ_ROOT, "qepm/mailbox/worktask", WT_ID)
STAGE_DIR <- file.path(PROJ_ROOT, "stage_artifacts", paste0("WT_", WT_ID))
PARENT_WT_DIR <- file.path(PROJ_ROOT, "qepm/mailbox/worktask", PARENT_WT)

dir.create(file.path(STAGE_DIR, "weights_variants"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(WT_DIR, "_workspace"), recursive = TRUE, showWarnings = FALSE)

cat(sprintf("[%s] Optimizer pipeline start — WT_ID=%s\n", format(Sys.time(), "%H:%M:%S"), WT_ID))

`%||%` <- function(a, b) if (is.null(a) || (length(a) == 1 && is.na(a))) b else a

# ─────────────────────────────────────────────────────────────────
# 1. Load inputs
# ─────────────────────────────────────────────────────────────────

risk_pkg <- fromJSON(file.path(WT_DIR, "risk_package.json"), simplifyVector = FALSE)
sf_deriv <- fromJSON(file.path(STAGE_DIR, "scale_factor_derivation.json"), simplifyVector = FALSE)
lro_frozen <- fromJSON(file.path(STAGE_DIR, "lro_params_frozen.json"), simplifyVector = FALSE)
crisis_ci <- fromJSON(file.path(STAGE_DIR, "crisis_bootstrap_ci.json"), simplifyVector = FALSE)
state_labels <- fromJSON(file.path(STAGE_DIR, "state_labels.json"), simplifyVector = FALSE)
tail_risk <- fromJSON(file.path(STAGE_DIR, "tail_risk.json"), simplifyVector = FALSE)

# Walk-forward (PIT-clean) — primary signal
wf_path <- fread(file.path(STAGE_DIR, "hmm_posterior_path_walkforward.csv"),
                 colClasses = list(character = "date"))
wf_path[, date := as.Date(date)]

# Parent M4 schedule (deployment lineage)
parent_wts <- fread(file.path(PARENT_WT_DIR, "weights.csv"),
                    colClasses = list(character = "Date"))
parent_wts[, Date := as.Date(Date)]
setnames(parent_wts, c("Date", "weight_str1715", "weight_cash"))

cat(sprintf("[1] risk_pkg loaded. wf rows=%d (filtered_nonblank=%d). parent rows=%d\n",
            nrow(wf_path), sum(!is.na(wf_path$gamma_Normal_filtered)), nrow(parent_wts)))

# ─────────────────────────────────────────────────────────────────
# 2. Build canonical date index — yearmon alignment
# ─────────────────────────────────────────────────────────────────
# Strategy: anchor on parent M4 dates (267m, first-of-month). HMM dates are
# end-of-month BDay. We map by yearmon and use HMM signal AT that yearmon.

wf_path[, ym := as.yearmon(date)]
parent_wts[, ym := as.yearmon(Date)]

# Joined frame on yearmon
canonical <- merge(parent_wts, wf_path,
                   by = "ym", all.x = TRUE, all.y = FALSE)

# scale_predicted is the PIT-clean predicted scale for next-period sizing.
# When NA (pre-MIN_TRAIN+1 = pre-2009-03), use baseline = 1.0 (no de-risk signal).
canonical[is.na(scale_predicted), scale_predicted := 1.0]

cat(sprintf("[2] canonical merged: %d rows, %d with HMM walk-forward signal\n",
            nrow(canonical),
            sum(!is.na(canonical$most_likely_predicted))))

# ─ C2 remediation (Codex critic): Apply Crisis pooled blend per crisis_bootstrap_ci.json
# Risk's scale_predicted does NOT honor the pooled blend; we apply it here at optimizer layer.
# Rule: scale_blended = γ_Normal * scale_Normal + γ_Caution * scale_Caution + γ_Crisis * scale_Crisis_pooled
# where scale_Crisis_pooled = 0.5*scale_Crisis + 0.5*scale_Caution (n_crisis=47<50 trigger)

# ─────────────────────────────────────────────────────────────────
# 3. Scale derivation per state (re-derive from risk package for audit)
# ─────────────────────────────────────────────────────────────────
# scale_adopted from risk package
scale_state <- list(
  Normal  = sf_deriv$scale_adopted$Normal,
  Caution = sf_deriv$scale_adopted$Caution,
  Crisis  = sf_deriv$scale_adopted$Crisis
)
# Pooled fallback (Crisis n=47 < 50)
crisis_pooled_blend <- 0.5 * scale_state$Crisis + 0.5 * scale_state$Caution
cat(sprintf("[3] scale_adopted Normal=%.3f Caution=%.3f Crisis=%.3f (pooled_blend=%.3f)\n",
            scale_state$Normal, scale_state$Caution, scale_state$Crisis,
            crisis_pooled_blend))

# Apply pooled blend on Crisis component (Codex C2 remediation)
canonical[, scale_state_marginal := ifelse(
  !is.na(gamma_Normal_predicted),
  gamma_Normal_predicted * scale_state$Normal +
    gamma_Caution_predicted * scale_state$Caution +
    gamma_Crisis_predicted * scale_state$Crisis,
  1.0
)]

# C2 remediation: pooled-blend scale (Crisis component blended with Caution at 50/50)
canonical[, scale_pooled_blend := ifelse(
  !is.na(gamma_Normal_predicted),
  gamma_Normal_predicted * scale_state$Normal +
    gamma_Caution_predicted * scale_state$Caution +
    gamma_Crisis_predicted * crisis_pooled_blend,
  1.0
)]

audit_scale_diff <- max(abs(canonical$scale_predicted - canonical$scale_state_marginal),
                        na.rm = TRUE)
audit_blend_diff <- max(abs(canonical$scale_pooled_blend - canonical$scale_state_marginal),
                        na.rm = TRUE)
cat(sprintf("[3] scale_predicted vs marginal diff=%.6f; pooled_blend vs marginal diff=%.6f (expected positive — blend lifts Crisis)\n",
            audit_scale_diff, audit_blend_diff))

# OPTIMIZER decision: adopt pooled_blend as the canonical scaling signal (C2 fix)
# This honors the Crisis n=47<50 conservative-against-false-positive rule from risk_package
canonical[, scale_canonical := scale_pooled_blend]

# ─────────────────────────────────────────────────────────────────
# 4. 3 strategy variants
# ─────────────────────────────────────────────────────────────────
# S1 baseline: w_str = 1.0, cash = 0
# HMM_Scale: w_str = scale_predicted (walk-forward), cash = 1 - scale
# M4+HMM_Scale: cash = max(M4_cash, 1 - scale_HMM); w_str = 1 - cash

variants <- list()

# S1 baseline (constant 100%)
S1 <- canonical[, .(Date = Date, weight_str1715 = 1.0, weight_cash = 0.0)]
variants$S1 <- S1

# M4_alone (Codex C3 fix: deployed baseline, parent WT-P20260429_002 schedule)
M4 <- canonical[, .(Date = Date,
                    weight_str1715 = weight_str1715,
                    weight_cash = weight_cash)]
variants$M4_alone <- M4

# HMM_Scale (pure HMM walk-forward + pooled-blend; C2 fix)
HMM <- canonical[, .(
  Date = Date,
  weight_str1715 = pmin(pmax(scale_canonical, 0), 1),
  weight_cash = pmin(pmax(1 - scale_canonical, 0), 1)
)]
variants$HMM_Scale <- HMM

# M4+HMM_Scale: cash = max(M4_cash_parent, 1 - scale_canonical); w_str = 1 - cash
M4_HMM <- canonical[, .(
  Date = Date,
  m4_cash = weight_cash,           # parent M4 cash
  hmm_cash = pmin(pmax(1 - scale_canonical, 0), 1)
)]
M4_HMM[, weight_cash := pmax(m4_cash, hmm_cash)]
M4_HMM[, weight_str1715 := 1 - weight_cash]
M4_HMM_out <- M4_HMM[, .(Date, weight_str1715, weight_cash)]
variants$`M4+HMM_Scale` <- M4_HMM_out

cat("[4] Variants built:\n")
for (vn in names(variants)) {
  v <- variants[[vn]]
  cat(sprintf("    %s: rows=%d mean(w_str)=%.3f mean(w_cash)=%.3f range=[%.3f, %.3f]\n",
              vn, nrow(v), mean(v$weight_str1715), mean(v$weight_cash),
              min(v$weight_str1715), max(v$weight_str1715)))
}

# ─────────────────────────────────────────────────────────────────
# 5. Σw audit + bounds check
# ─────────────────────────────────────────────────────────────────
# Hard constraints: long_only (≥0), Σw=1, weight_bounds[0, 0.20] applies to
# UNDERLYING STR_1715 internal stocks (inherited from parent admit). Sleeve-level
# w_str ∈ [0,1] is allowed (sleeve scaling).
# Active cap = 0.20 per Q-Lead spawn instruction interpreted as: STR_1715 internal
# stocks ≤ 0.20 (inherited, unchanged). Sleeve-level scale ∈ [0,1].

for (vn in names(variants)) {
  v <- variants[[vn]]
  s <- v$weight_str1715 + v$weight_cash
  stopifnot(all(abs(s - 1.0) < 1e-9))
  stopifnot(all(v$weight_str1715 >= 0 & v$weight_str1715 <= 1))
  stopifnot(all(v$weight_cash >= 0 & v$weight_cash <= 1))
}
cat("[5] Σw=1 + long_only + bounds [0,1] PASS for all 3 variants\n")

# ─────────────────────────────────────────────────────────────────
# 6. Write canonical + variant CSVs
# ─────────────────────────────────────────────────────────────────
# Canonical = M4+HMM_Scale (primary per WT spec / Q-Lead instruction)
fwrite(M4_HMM_out, file.path(STAGE_DIR, "weights.csv"))

fwrite(S1, file.path(STAGE_DIR, "weights_variants", "S1.csv"))
fwrite(M4, file.path(STAGE_DIR, "weights_variants", "M4_alone.csv"))
fwrite(HMM, file.path(STAGE_DIR, "weights_variants", "HMM_Scale.csv"))
fwrite(M4_HMM_out, file.path(STAGE_DIR, "weights_variants", "M4+HMM_Scale.csv"))

cat("[6] CSVs written. Canonical = M4+HMM_Scale.csv\n")

# ─────────────────────────────────────────────────────────────────
# 6b. Security-level forecast snapshot (Codex C1 partial remediation)
# ─────────────────────────────────────────────────────────────────
# Historical 20-stock weights are NOT available in parent (STR_1715 holdings is
# meta-sleeve only). For the AS_OF_DATE forecast, join canonical sleeve weight
# with the live STR_1715 production_weights snapshot.

str_pw_path <- file.path(PROJ_ROOT,
  "04_Research/strategies/STR_1715_WT016_Iter31_GridBestProd/production_weights/20260501_weights_cap_0p20.csv")
str_pw <- fread(str_pw_path)
# Schema: rank,Ticker,Name,Sector,Weight (sums to 1 within sleeve)

# Latest canonical sleeve weight
last_row <- M4_HMM_out[Date == max(Date)]
sleeve_w <- last_row$weight_str1715
cash_w <- last_row$weight_cash

# Effective security-level weight = sleeve_w * stock_w_within_sleeve
sec_level <- str_pw[, .(
  as_of_date = AS_OF_DATE,
  ticker = Ticker,
  name = Name,
  sector = Sector,
  sleeve_weight = Weight,
  effective_weight = Weight * sleeve_w,
  method_selected = "M4+HMM_Scale"
)]
# Append cash row
cash_row <- data.table(
  as_of_date = AS_OF_DATE, ticker = "CASH_KRW", name = "KRW Cash",
  sector = "Cash", sleeve_weight = 0, effective_weight = cash_w,
  method_selected = "M4+HMM_Scale"
)
sec_level <- rbind(sec_level, cash_row)

# Hard constraint check at security level
n_active_stocks <- sec_level[ticker != "CASH_KRW" & effective_weight > 1e-6, .N]
max_eff_w <- max(sec_level[ticker != "CASH_KRW"]$effective_weight)
sum_eff_w <- sum(sec_level$effective_weight)

cat(sprintf("[6b] Security-level snapshot: n_active=%d / max_eff=%.4f / Σ=%.4f / cash=%.4f\n",
            n_active_stocks, max_eff_w, sum_eff_w, cash_w))
# n_active should be ≤ 20, max_eff should be ≤ 0.20, Σ should be 1.0
stopifnot(n_active_stocks <= 20)
stopifnot(max_eff_w <= 0.20 + 1e-9)
stopifnot(abs(sum_eff_w - 1.0) < 1e-6)

fwrite(sec_level, file.path(STAGE_DIR, "weights_security_level_snapshot.csv"))
cat("[6b] weights_security_level_snapshot.csv written (as_of forecast, hard-constraint-verified)\n")

# ─────────────────────────────────────────────────────────────────
# 7. cash_definition_audit.json
# ─────────────────────────────────────────────────────────────────
cash_audit <- list(
  task_id = WT_ID,
  cash_definition = list(
    canonical_strategy = "M4+HMM_Scale",
    cash_rule = "weight_cash_t = max(M4_parent_cash_t, 1 - scale_HMM_walkforward_t); weight_str_t = 1 - weight_cash_t",
    cash_overlap_principle = "single cash source — combined max() ensures no double-counting; M4 + HMM signals OR'd at cash-bucket level, not stacked",
    parent_M4_source = sprintf("qepm/mailbox/worktask/%s/weights.csv", PARENT_WT),
    hmm_source = "stage_artifacts/WT_WT-S20260504_003/hmm_posterior_path_walkforward.csv (walk-forward filtered, PIT-clean)",
    pre_walkforward_period_handling = "scale_HMM = 1.0 (no PIT-clean signal pre-2009-03 → no de-risk overlay; M4 alone applies)",
    cash_neutral_periods = sum(M4_HMM_out$weight_cash == 0),
    cash_active_periods = sum(M4_HMM_out$weight_cash > 0),
    mean_cash_canonical = mean(M4_HMM_out$weight_cash),
    max_cash_canonical = max(M4_HMM_out$weight_cash)
  ),
  variant_summary = list(
    S1 = list(mean_w_str = mean(S1$weight_str1715), mean_w_cash = mean(S1$weight_cash)),
    HMM_Scale = list(mean_w_str = mean(HMM$weight_str1715), mean_w_cash = mean(HMM$weight_cash)),
    `M4+HMM_Scale` = list(mean_w_str = mean(M4_HMM_out$weight_str1715),
                           mean_w_cash = mean(M4_HMM_out$weight_cash))
  ),
  active_cap_interpretation = "Sleeve-level w_str ∈ [0,1]; underlying STR_1715 stock weight cap [0,0.20] inherited from parent admit (unchanged here)",
  long_only = TRUE,
  sigma_w_eq_1 = TRUE,
  generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
)
write_json(cash_audit, file.path(STAGE_DIR, "cash_definition_audit.json"),
           pretty = TRUE, auto_unbox = TRUE, na = "null")
cat("[7] cash_definition_audit.json written\n")

# ─────────────────────────────────────────────────────────────────
# 8. LRO portfolio MRC (Marginal Risk Contribution) — sleeve-level
# ─────────────────────────────────────────────────────────────────
# At sleeve-level, MRC reduces to: portfolio_vol_t = w_str_t * σ_str_t
# With cash σ_cash = 0, MRC_str = w_str_t * σ_str_t and MRC_cash = 0.
# Use STR_1715 NAV vol from risk package state-conditional vols.

# State-conditional STR vols
ann_vol_state <- list(
  Normal  = sf_deriv$state_str_metrics$Normal$ann_vol,
  Caution = sf_deriv$state_str_metrics$Caution$ann_vol,
  Crisis  = sf_deriv$state_str_metrics$Crisis$ann_vol
)
canonical[, sigma_str_state_marginal := ifelse(
  !is.na(gamma_Normal_predicted),
  sqrt(gamma_Normal_predicted * ann_vol_state$Normal^2 +
         gamma_Caution_predicted * ann_vol_state$Caution^2 +
         gamma_Crisis_predicted * ann_vol_state$Crisis^2),
  ann_vol_state$Normal  # baseline pre-walkforward
)]

mrc <- merge(M4_HMM_out, canonical[, .(Date, sigma_str_state_marginal)],
             by = "Date", all.x = TRUE)
mrc[, mrc_str := weight_str1715 * sigma_str_state_marginal]
mrc[, mrc_cash := 0]
mrc[, port_vol := mrc_str]
mrc_out <- mrc[, .(Date, weight_str1715, weight_cash,
                   sigma_str_state_marginal, mrc_str, mrc_cash, port_vol)]
fwrite(mrc_out, file.path(STAGE_DIR, "lro_portfolio_mrc.csv"))
cat(sprintf("[8] lro_portfolio_mrc.csv written. mean port_vol = %.4f (ann)\n",
            mean(mrc_out$port_vol)))

# ─────────────────────────────────────────────────────────────────
# 9. Schedule density audit
# ─────────────────────────────────────────────────────────────────
n_unique_dates <- length(unique(M4_HMM_out$Date))
n_parent_dates <- length(unique(parent_wts$Date))
schedule_density <- n_unique_dates / n_parent_dates
cat(sprintf("[9] Schedule density: %d / %d = %.3f\n",
            n_unique_dates, n_parent_dates, schedule_density))

# ─────────────────────────────────────────────────────────────────
# 10. Method comparison metrics (post-hoc realized over historical scale path)
# ─────────────────────────────────────────────────────────────────
# Use STR_1715 03_period_returns.csv for the 268m monthly returns
# Re-build NAV under each variant (sleeve-scaled returns)

str_pr_path <- file.path(PROJ_ROOT,
  "04_Research/strategies/STR_1715_WT016_Iter31_GridBestProd/output/03_period_returns.csv")
str_pr <- fread(str_pr_path)
# Normalize date col
date_col <- intersect(c("Date", "date"), names(str_pr))[1]
setnames(str_pr, date_col, "Date")
str_pr[, Date := as.Date(Date)]
cat(sprintf("[10] str_pr cols: %s, rows=%d\n",
            paste(names(str_pr), collapse=","), nrow(str_pr)))

# Use ret_net (after-cost) per backtest_contract — net of 15bps embedded
ret_col <- intersect(c("ret_net", "Return", "return", "ret", "monthly_return"),
                     names(str_pr))[1]
if (is.na(ret_col)) stop("Cannot find return column in 03_period_returns.csv")
cat(sprintf("[10] Using return col: %s\n", ret_col))

setnames(str_pr, ret_col, "ret_str")
str_pr[, ym := as.yearmon(Date)]

# Merge variants on yearmon basis
canon_ym <- canonical[, .(Date_canonical = Date, ym = ym)]
canon_ym <- merge(canon_ym, str_pr[, .(ym, ret_str)], by = "ym", all.x = TRUE)

method_metrics <- list()
for (vn in names(variants)) {
  v <- variants[[vn]]
  v_ym <- copy(v)
  v_ym[, ym := as.yearmon(Date)]
  v_ret <- merge(v_ym[, .(ym, weight_str1715, weight_cash)],
                 canon_ym[, .(ym, ret_str)], by = "ym", all.x = TRUE)
  # Cash return = 0 (research, no IRX overlay)
  v_ret[, ret_port := weight_str1715 * ret_str]
  v_ret <- v_ret[!is.na(ret_port)]

  if (nrow(v_ret) < 24) {
    method_metrics[[vn]] <- list(insufficient_obs = TRUE)
    next
  }

  # Annualized stats
  mu_m <- mean(v_ret$ret_port)
  sd_m <- sd(v_ret$ret_port)
  ann_ret <- (1 + mu_m)^12 - 1
  ann_vol <- sd_m * sqrt(12)
  ann_sr <- ann_ret / ann_vol

  # MDD
  cum_nav <- cumprod(1 + v_ret$ret_port)
  peak <- cummax(cum_nav)
  dd <- (cum_nav - peak) / peak
  mdd <- min(dd)

  # Turnover (sleeve-level: |Δw_str|)
  dw <- diff(v_ret$weight_str1715)
  to_m_avg <- mean(abs(dw))
  to_annual <- to_m_avg * 12 * 2  # roundtrip × 12 (annualized round-trip)

  # C4 fix: Overlay turnover cost (additive on top of ret_str's embedded cost)
  # When sleeve scales by Δw, the underlying 20 stocks rebalance proportionally.
  # Overlay cost ≈ |Δw_str| * 15bps (one-way). ret_str ALREADY embeds STR_1715's
  # internal stock turnover. Overlay only adds sleeve-scaling turnover.
  v_ret_cost_adj <- copy(v_ret)
  dw_path <- c(0, diff(v_ret_cost_adj$weight_str1715))
  v_ret_cost_adj[, overlay_cost := abs(dw_path) * 0.0015]  # one-way 15bps
  v_ret_cost_adj[, ret_port_net := ret_port - overlay_cost]
  mu_m_net <- mean(v_ret_cost_adj$ret_port_net)
  sd_m_net <- sd(v_ret_cost_adj$ret_port_net)
  ann_ret_net <- (1 + mu_m_net)^12 - 1
  ann_vol_net <- sd_m_net * sqrt(12)
  ann_sr_net <- ann_ret_net / ann_vol_net

  cum_nav_net <- cumprod(1 + v_ret_cost_adj$ret_port_net)
  peak_net <- cummax(cum_nav_net)
  dd_net <- (cum_nav_net - peak_net) / peak_net
  mdd_net <- min(dd_net)

  # Compute IR vs both S1 and M4_alone baselines
  compute_active <- function(v_ret_in, baseline_v) {
    bv <- copy(baseline_v)
    bv[, ym := as.yearmon(Date)]
    bv_ret <- merge(bv[, .(ym, weight_str1715)],
                    canon_ym[, .(ym, ret_str)], by = "ym", all.x = TRUE)
    bv_ret[, ret_port := weight_str1715 * ret_str]
    bv_ret <- bv_ret[!is.na(ret_port)]
    common_ym <- intersect(v_ret_in$ym, bv_ret$ym)
    v_aln <- v_ret_in[ym %in% common_ym, .(ym, ret_port)]
    b_aln <- bv_ret[ym %in% common_ym, .(ym, ret_port_b = ret_port)]
    aln <- merge(v_aln, b_aln, by = "ym")
    aln[, active := ret_port - ret_port_b]
    list(te = sd(aln$active) * sqrt(12),
         ir = mean(aln$active) * 12 / (sd(aln$active) * sqrt(12)),
         active_ret_ann = mean(aln$active) * 12)
  }

  if (vn == "S1") {
    ir <- NA; te <- NA
    ir_vs_M4 <- NA; te_vs_M4 <- NA; active_vs_M4 <- NA
  } else {
    s1_active <- compute_active(v_ret, variants$S1)
    te <- s1_active$te; ir <- s1_active$ir
    if (vn == "M4_alone") {
      ir_vs_M4 <- 0; te_vs_M4 <- 0; active_vs_M4 <- 0
    } else {
      m4_active <- compute_active(v_ret, variants$M4_alone)
      te_vs_M4 <- m4_active$te
      ir_vs_M4 <- m4_active$ir
      active_vs_M4 <- m4_active$active_ret_ann
    }
  }

  method_metrics[[vn]] <- list(
    n_obs = nrow(v_ret),
    ann_ret = round(ann_ret, 4),
    ann_vol = round(ann_vol, 4),
    sr = round(ann_sr, 4),
    mdd = round(mdd, 4),
    ann_ret_net_overlay = round(ann_ret_net, 4),
    sr_net_overlay = round(ann_sr_net, 4),
    mdd_net_overlay = round(mdd_net, 4),
    turnover_annual_roundtrip = round(to_annual, 4),
    overlay_cost_drag_ann_bps = round((ann_ret - ann_ret_net) * 1e4, 2),
    ir_vs_S1 = if (is.na(ir)) NA else round(ir, 4),
    te_vs_S1 = if (is.na(te)) NA else round(te, 4),
    ir_vs_M4 = if (is.na(ir_vs_M4)) NA else round(ir_vs_M4, 4),
    te_vs_M4 = if (is.na(te_vs_M4)) NA else round(te_vs_M4, 4),
    active_ret_vs_M4_ann = if (is.na(active_vs_M4)) NA else round(active_vs_M4, 4),
    net_ir = if (is.na(ir_vs_M4)) NA else round(ir_vs_M4, 4)  # WT objective is M4-relative
  )
}

cat("[10] Method comparison:\n")
for (vn in names(method_metrics)) {
  m <- method_metrics[[vn]]
  ir_m4 <- m$ir_vs_M4 %||% NA
  cat(sprintf("    %s: SR=%.3f SR_net=%.3f MDD=%.3f MDD_net=%.3f TO=%.3f IR_S1=%s IR_M4=%s OvCost=%.1fbp\n",
              vn, m$sr %||% NA_real_, m$sr_net_overlay %||% NA_real_,
              m$mdd %||% NA_real_, m$mdd_net_overlay %||% NA_real_,
              m$turnover_annual_roundtrip %||% NA_real_,
              if (is.null(m$ir_vs_S1) || is.na(m$ir_vs_S1)) "NA" else sprintf("%.3f", m$ir_vs_S1),
              if (is.na(ir_m4)) "NA" else sprintf("%.3f", ir_m4),
              m$overlay_cost_drag_ann_bps %||% 0))
}

# ─────────────────────────────────────────────────────────────────
# 11. optimization_package_draft.json
# ─────────────────────────────────────────────────────────────────

# SHA of risk inputs
hmm_sha <- lro_frozen$hmm_params_sha256
canonical_csv_sha <- digest::digest(file = file.path(STAGE_DIR, "weights.csv"),
                                     algo = "sha256")

opt_pkg_draft <- list(
  task_id = WT_ID,
  package_kind = "optimization_package_hmm_regime",
  wt_type = "sizing_only",
  wt_kind = "recommendation_only",
  agent = "optimizer-research",
  produced_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  as_of_date = AS_OF_DATE,
  parent_wt = PARENT_WT,
  parent_alpha_package_sha = "34cc99fb8aa423f7ce97ebea877a4fa68207896bffd8043443f87dcb2ba60984",
  hmm_params_sha256 = hmm_sha,
  weights_csv_sha256 = canonical_csv_sha,

  method_summary = list(
    framework = "HMM 3-state regime-conditional sleeve scaling (sizing-only overlay on STR_1715 PG2)",
    primary_signal = "scale_predicted (walk-forward forward-filter, PIT-clean from hmm_posterior_path_walkforward.csv)",
    canonical_strategy = "M4+HMM_Scale",
    canonical_rule = "w_cash_t = max(M4_parent_cash_t, 1 - scale_HMM_walkforward_t); w_str_t = 1 - w_cash_t",
    pre_walkforward_handling = "scale_HMM=1.0 pre-2009-03 (no PIT signal); M4 cash alone applies",
    selection_objective = "crowding_adj_ret",
    selection_objective_rationale = "Sizing overlay's value = MDD/vol reduction without alpha distortion. Net-IR vs S1 baseline ≥ 0 + MDD reduction = primary criterion."
  ),

  method_shopping_log = list(
    candidates_tried = 4L,
    method_log = list(
      list(name = "S1_baseline", ann_ret = method_metrics$S1$ann_ret,
           sr = method_metrics$S1$sr, mdd = method_metrics$S1$mdd,
           turnover_annual_roundtrip = method_metrics$S1$turnover_annual_roundtrip,
           selected = FALSE,
           rationale = "Constant w_str=1.0 (no overlay); IR baseline reference"),
      list(name = "M4_alone", ann_ret = method_metrics$M4_alone$ann_ret,
           sr = method_metrics$M4_alone$sr, mdd = method_metrics$M4_alone$mdd,
           turnover_annual_roundtrip = method_metrics$M4_alone$turnover_annual_roundtrip,
           ir_vs_S1 = method_metrics$M4_alone$ir_vs_S1,
           selected = FALSE,
           rationale = "Codex C3 fix: deployed baseline (parent WT-P20260429_002 M4 schedule alone). WT objective is M4-relative."),
      list(name = "HMM_Scale", ann_ret = method_metrics$HMM_Scale$ann_ret,
           sr = method_metrics$HMM_Scale$sr, mdd = method_metrics$HMM_Scale$mdd,
           turnover_annual_roundtrip = method_metrics$HMM_Scale$turnover_annual_roundtrip,
           ir_vs_S1 = method_metrics$HMM_Scale$ir_vs_S1,
           ir_vs_M4 = method_metrics$HMM_Scale$ir_vs_M4,
           selected = FALSE,
           rationale = "Pure HMM walk-forward + Crisis pooled-blend (n=47<50). No M4 cash. Reference for additivity audit."),
      list(name = "M4+HMM_Scale", ann_ret = method_metrics$`M4+HMM_Scale`$ann_ret,
           sr = method_metrics$`M4+HMM_Scale`$sr, mdd = method_metrics$`M4+HMM_Scale`$mdd,
           turnover_annual_roundtrip = method_metrics$`M4+HMM_Scale`$turnover_annual_roundtrip,
           ir_vs_S1 = method_metrics$`M4+HMM_Scale`$ir_vs_S1,
           ir_vs_M4 = method_metrics$`M4+HMM_Scale`$ir_vs_M4,
           overlay_cost_drag_ann_bps = method_metrics$`M4+HMM_Scale`$overlay_cost_drag_ann_bps,
           selected = TRUE,
           rationale = "Canonical: max(M4_cash, HMM_pooled_blend_cash) — additive de-risk, MDD vs M4 < -3pp target test pending Forge re-backtest")
    ),
    parallel_exec = FALSE,
    n_workers = 1L,
    selection_logic = "M4-relative MDD reduction is the WT primary objective. Selected candidate must: (1) honor M4 deployed schedule; (2) add HMM walk-forward signal at no double-cost; (3) respect Crisis n=47<50 pooled-blend rule (Codex C2 fix). M4+HMM_Scale uniquely meets all three."
  ),

  method_selected = "M4+HMM_Scale",
  method_selected_rationale = "WT spec mandates HMM_Regime + M4 already deployed (parent WT-P20260429_002). Combined max-cash rule retains both signals without stacking, and provides the primary canonical target_weights handoff to Forge.",

  selection_objective = "crowding_adj_ret",

  target_weights_summary = list(
    n_unique_dates = n_unique_dates,
    n_parent_dates = n_parent_dates,
    schedule_density_ratio = round(schedule_density, 4),
    schedule_density_pass = schedule_density >= 0.95,
    columns = c("Date", "weight_str1715", "weight_cash"),
    date_range = c(format(min(M4_HMM_out$Date), "%Y-%m-%d"),
                   format(max(M4_HMM_out$Date), "%Y-%m-%d")),
    mean_weight_str = round(mean(M4_HMM_out$weight_str1715), 4),
    mean_weight_cash = round(mean(M4_HMM_out$weight_cash), 4),
    max_weight_cash = round(max(M4_HMM_out$weight_cash), 4),
    n_cash_active_periods = sum(M4_HMM_out$weight_cash > 0)
  ),

  active_weights_basis = "active = w_canonical - w_S1_baseline (sleeve-level deviation from constant 100% allocation)",

  expected_active_return = round((method_metrics$`M4+HMM_Scale`$ann_ret %||% 0) -
                                  (method_metrics$M4_alone$ann_ret %||% 0), 4),
  expected_active_return_basis = "M4_alone (deployed baseline per WT objective)",
  expected_tracking_error = method_metrics$`M4+HMM_Scale`$te_vs_M4,
  expected_information_ratio = method_metrics$`M4+HMM_Scale`$ir_vs_M4,

  expected_active_return_vs_S1 = round((method_metrics$`M4+HMM_Scale`$ann_ret %||% 0) -
                                  (method_metrics$S1$ann_ret %||% 0), 4),
  expected_tracking_error_vs_S1 = method_metrics$`M4+HMM_Scale`$te_vs_S1,
  expected_information_ratio_vs_S1 = method_metrics$`M4+HMM_Scale`$ir_vs_S1,

  m4_relative_mdd_improvement_pp = round(
    (method_metrics$M4_alone$mdd - method_metrics$`M4+HMM_Scale`$mdd) * 100, 2
  ),  # positive means canonical has SHALLOWER MDD than M4 alone

  turnover = method_metrics$`M4+HMM_Scale`$turnover_annual_roundtrip,
  overlay_cost_drag_ann_bps = method_metrics$`M4+HMM_Scale`$overlay_cost_drag_ann_bps,
  estimated_cost_one_way = round(method_metrics$`M4+HMM_Scale`$turnover_annual_roundtrip * 0.0015, 5),
  estimated_cost_round_trip = round(method_metrics$`M4+HMM_Scale`$turnover_annual_roundtrip * 0.0015, 5),
  cost_basis_note = "ret_str (= STR_1715 ret_net) ALREADY embeds STR_1715's internal 15bps. Overlay cost = sleeve-scale Δw × 15bps one-way (additive). turnover_annual_roundtrip = mean(|Δw|) × 12 × 2 (matches Charter §10 round-trip).",

  binding_constraints = list(),  # sleeve-level no per-name bound binding
  infeasibility_report = NULL,

  hard_constraints_audit = list(
    sleeve_level = list(
      long_only = TRUE,
      sigma_w_eq_1 = TRUE,
      weight_str_in_unit = TRUE,
      weight_cash_in_unit = TRUE
    ),
    security_level_snapshot = list(
      as_of_date = AS_OF_DATE,
      n_active_stocks = n_active_stocks,
      max_effective_weight = round(max_eff_w, 6),
      sigma_effective_weight = round(sum_eff_w, 6),
      cash_weight = round(cash_w, 6),
      max_names_constraint_pass = n_active_stocks <= 20,
      weight_bound_constraint_pass = max_eff_w <= 0.20 + 1e-9,
      sigma_constraint_pass = abs(sum_eff_w - 1.0) < 1e-6,
      reference = "stage_artifacts/WT_WT-S20260504_003/weights_security_level_snapshot.csv"
    ),
    underlying_str1715_max_w_inherited = "0.20 per-stock (STR_1715 PG2 forward_weights.R v2 enforced; production_weights/20260501_weights_cap_0p20.csv)",
    max_names_inherited = "20 stocks (STR_1715 internal optimizer, unchanged)",
    historical_security_level_provenance = "STR_1715 historical 04_holdings.csv contains placeholder STR_1715_RISK_SLEEVE meta-ticker only (operational sleeve abstraction). Per-stock historical weights not materialized; 20-stock cap enforcement is at STR_1715 internal optimizer layer, not at this overlay WT. Forge re-backtest will validate via STR_1715 historical NAV reconstruction."
  ),

  hmm_walkforward_provenance = list(
    csv_path = "stage_artifacts/WT_WT-S20260504_003/hmm_posterior_path_walkforward.csv",
    n_valid_predictions = sum(!is.na(wf_path$gamma_Normal_filtered)),
    min_train_obs = 60L,
    first_pit_clean_date = "2009-03-02",
    last_pit_clean_date = format(max(wf_path$date[!is.na(wf_path$gamma_Normal_filtered)]), "%Y-%m-%d"),
    pre_walkforward_baseline_scale = 1.0
  ),

  cash_definition_audit_ref = "stage_artifacts/WT_WT-S20260504_003/cash_definition_audit.json",
  lro_portfolio_mrc_ref = "stage_artifacts/WT_WT-S20260504_003/lro_portfolio_mrc.csv",
  weights_csv_ref = "stage_artifacts/WT_WT-S20260504_003/weights.csv",
  weights_variants_ref = list(
    S1 = "stage_artifacts/WT_WT-S20260504_003/weights_variants/S1.csv",
    M4_alone = "stage_artifacts/WT_WT-S20260504_003/weights_variants/M4_alone.csv",
    HMM_Scale = "stage_artifacts/WT_WT-S20260504_003/weights_variants/HMM_Scale.csv",
    `M4+HMM_Scale` = "stage_artifacts/WT_WT-S20260504_003/weights_variants/M4+HMM_Scale.csv"
  ),
  weights_security_level_snapshot_ref = "stage_artifacts/WT_WT-S20260504_003/weights_security_level_snapshot.csv",

  axiom_assertions = list(
    `AX-000` = "한계 없음 — 통계적 sizing 결정 (no fixed cash %)",
    `AX-001_v2` = sprintf("Sleeve-level vol/MDD reduction recommendation. Mean cash %.3f, max cash %.3f, n_cash_active=%d. Crisis pooled-blend honored (n=47<50).",
                          mean(M4_HMM_out$weight_cash), max(M4_HMM_out$weight_cash),
                          sum(M4_HMM_out$weight_cash > 0)),
    `AX-002` = sprintf("HMM params SHA-frozen (sha256=%s). Walk-forward forward-filter only — verified via hmm_posterior_path_walkforward.csv. Smoothed posterior NOT used for sizing.", substr(hmm_sha, 1, 16)),
    `AX-007` = "exception_clause_3_ml_sizing — HMM is statistical sizing overlay on existing top20 sleeve (STR_1715 PG2). No new factor signals. Sleeve-level w∈[0,1].",
    `AX-008` = "Verification triangulation pending: this Optimizer package = source 1. Forge will re-fit + re-backtest (source 2). Codex critic round = source 3. Need 2/3 PASS."
  ),

  challenge_flags = list(
    "codex_REJECT_round1_remediated_pooled_blend_C2",
    "codex_REJECT_round1_remediated_M4_baseline_C3",
    "codex_REJECT_round1_remediated_security_level_snapshot_C1",
    "codex_REJECT_round1_remediated_overlay_cost_C4",
    "negative_M4_relative_IR_disclosed_under_mdd_target_priority"
  ),

  explanation = list(
    top_overweights = "Sleeve-level only — STR_1715 internal stock weights inherited from parent (S-Oil 20%, 쏠리드 20%, 한올바이오 13.1%, 리노공업 7.6%, 삼성전자 7.3%)",
    top_underweights = "N/A at sleeve level",
    main_tradeoffs = c(
      "M4 deployed cash schedule preserved (max-cash rule does not weaken existing deployment)",
      "HMM walk-forward scale_predicted adds Crisis-state de-risk signal beyond M4",
      "Pre-2009-03 period inherits M4 schedule alone (no PIT-clean HMM signal)"
    )
  ),

  forge_handoff = list(
    primary_input = "weights.csv (M4+HMM_Scale canonical)",
    variants_for_audit = c("S1", "HMM_Scale"),
    inheritance = list(
      str_1715_internal_weights = "INHERITED_FROM_STR_1715 PG2 (parent admit 2026-05-02)",
      cost_model = "v2.3_kr_retail_15bps",
      universe = "KOSPI200_KOSDAQ150_intersection (parent universe unchanged)"
    ),
    expected_metrics_target = list(
      cagr_floor = 0.20,
      mdd_target = "≤ -25% OR M4 대비 -3pp 개선",
      vol_target = "M4 대비 -20% 개선"
    )
  ),

  draft_revision = "v1",
  draft_status = "_draft suffix retained until Codex critic round complete"
)

write_json(opt_pkg_draft,
           file.path(WT_DIR, "optimization_package_draft.json"),
           pretty = TRUE, auto_unbox = TRUE, na = "null")

cat(sprintf("[11] optimization_package_draft.json written. SHA(weights.csv)=%s\n",
            substr(canonical_csv_sha, 1, 16)))

cat(sprintf("\n[%s] Optimizer pipeline COMPLETE.\n", format(Sys.time(), "%H:%M:%S")))
cat("Next: bash run_codex_qepm_critic.sh --role=optimizer ...\n")
