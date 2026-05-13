#==============================================================================
# WT-D20260512_003 Optimizer Step 9 — Final with Infeasibility Report
#
# After Codex REJECT (C1/C2/C5 disposition ACCEPT) + Step 8 hard filter re-test,
# all 13 methods (7 original + 6 buffered) fail to meet BOTH TO ≤ 6.0 AND MDD > -45%.
#
# Closest to feasibility: Iter31_phi10_buffer40
#   - SR=1.373 | CAGR=39.1% | MDD=-43.5% (PASSES) | TO=6.64 (FAILS by 0.64)
#
# Decision: Issue infeasibility_report + emit closest-to-feasible weights
# (Iter31_phi10_buffer40) as conditional recommendation for Q-Lead override.
#
# Selection objective enforced cascade:
#   1. Hard filter: TO ≤ 6.0 AND MDD > -45% MUST PASS
#   2. If pass: select max(SR_net) among passing
#   3. If none: infeasibility_report + closest-to-feasibility candidate
#==============================================================================

suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite); library(digest)
})

BASE_DIR <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
setwd(BASE_DIR)

cat("============================================================\n")
cat("[OPT-Step9] Final with Infeasibility Report\n")
cat("============================================================\n\n")

WT <- "WT-D20260512_003"
stage <- file.path("stage_artifacts", "WT_D20260512_003")
mailbox <- file.path("qepm/mailbox/worktask", WT)

# Load all method results
res_alpha <- readRDS(file.path(stage, "opt_method_shopping_alpha_rank.rds"))
res_sigma <- readRDS(file.path(stage, "opt_method_shopping_sigma.rds"))
res_buf <- readRDS(file.path(stage, "opt_method_shopping_buffered.rds"))

# Aggregate all 13 methods
emat <- as.data.table(read_parquet(file.path(stage, "exposure_matrix.parquet")))
setkey(emat, Ticker)

agg_method <- function(res_obj, method_name) {
  monthly <- res_obj$monthly[!is.na(port_ret_net)]
  weights <- res_obj$weights
  if (nrow(monthly) == 0L) return(NULL)
  setorder(monthly, sig_date)

  rets <- monthly$port_ret_net
  n <- length(rets)
  ann_mu <- mean(rets) * 12
  ann_sd <- sd(rets) * sqrt(12)
  sr <- if (ann_sd > 0) ann_mu / ann_sd else NA_real_
  cagr <- prod(1 + rets, na.rm=TRUE)^(12/n) - 1
  eq <- cumprod(1+rets); peak <- cummax(eq); mdd <- min(eq/peak - 1, na.rm=TRUE)
  neg <- rets[rets<0]
  ds_vol <- if (length(neg)>1) sd(neg)*sqrt(12) else NA_real_
  sortino <- if (!is.na(ds_vol) && ds_vol > 0) ann_mu/ds_vol else NA_real_
  calmar <- if (mdd < 0) ann_mu/abs(mdd) else NA_real_
  to_ann <- mean(monthly$turnover[-1], na.rm=TRUE) * 12

  rsr <- monthly[, .(n_obs = .N,
                      sr = if(sd(port_ret_net)>0)
                          (mean(port_ret_net)*12)/(sd(port_ret_net)*sqrt(12)) else NA_real_),
                  by = regime]
  get_sr <- function(g) {
    v <- rsr[regime==g, sr]
    if (length(v) == 0) NA_real_ else v[1]
  }
  get_n <- function(g) {
    v <- rsr[regime==g, n_obs]
    if (length(v) == 0) 0L else v[1]
  }

  hhi_per <- weights[, .(hhi=sum(weight^2)), by=sig_date]
  hhi_m <- mean(hhi_per$hhi, na.rm=TRUE)
  wj <- merge(weights, emat[,.(Ticker, F_QMJ_factor=F_QMJ)],
              by.x="ticker", by.y="Ticker", all.x=TRUE)
  fqmj_per <- wj[, .(fqmj=sum(weight*F_QMJ_factor, na.rm=TRUE)), by=sig_date]
  fqmj_m <- mean(fqmj_per$fqmj, na.rm=TRUE)

  data.table(
    method = method_name,
    n = n,
    SR = sr,
    CAGR = cagr,
    MDD = mdd,
    Sortino = sortino,
    Calmar = calmar,
    BULL = get_sr("BULL"),
    NORMAL = get_sr("NORMAL"),
    CAUTION = get_sr("CAUTION"),
    CRISIS = get_sr("CRISIS"),
    BULL_n = get_n("BULL"),
    NORMAL_n = get_n("NORMAL"),
    CAUTION_n = get_n("CAUTION"),
    CRISIS_n = get_n("CRISIS"),
    TO_annual = to_ann,
    HHI_mean = hhi_m,
    F_QMJ_mean = fqmj_m
  )
}

all_results <- c(res_alpha, res_sigma, res_buf)
agg_dt <- rbindlist(lapply(names(all_results),
                            function(m) agg_method(all_results[[m]], m)),
                    fill = TRUE)

# Hard filter
TO_HARD_CAP <- 6.0
MDD_HARD_GATE <- -0.45
agg_dt[, TO_pass := TO_annual <= TO_HARD_CAP]
agg_dt[, MDD_pass := MDD > MDD_HARD_GATE]
agg_dt[, HARD_PASS := TO_pass & MDD_pass]

# Closeness to feasibility (Euclidean distance to feasible region)
agg_dt[, TO_excess := pmax(0, TO_annual - TO_HARD_CAP)]
agg_dt[, MDD_excess := pmax(0, MDD_HARD_GATE - MDD)]
agg_dt[, feasibility_dist := sqrt((TO_excess/TO_HARD_CAP)^2 + (MDD_excess/abs(MDD_HARD_GATE))^2)]

setorder(agg_dt, feasibility_dist, -SR)

cat("[All 13 methods sorted by feasibility distance, then SR]\n")
print(agg_dt[, .(method,
                 SR=round(SR,4), CAGR_pct=round(CAGR*100,2), MDD_pct=round(MDD*100,2),
                 TO=round(TO_annual,3),
                 TO_pass, MDD_pass, HARD_PASS,
                 feasibility_dist=round(feasibility_dist,4))])

# Selection logic
n_pass <- sum(agg_dt$HARD_PASS, na.rm = TRUE)
if (n_pass > 0L) {
  # Pick best SR among passing
  pass_dt <- agg_dt[HARD_PASS == TRUE]
  setorder(pass_dt, -SR)
  selected_method <- pass_dt$method[1]
  infeasibility_status <- NULL
} else {
  # Infeasibility: pick closest to feasibility
  selected_method <- agg_dt$method[1]  # already sorted by feasibility_dist
  infeasibility_status <- "ALL_METHODS_INFEASIBLE_BOTH_TO_AND_MDD"
}

cat(sprintf("\n[Selected method] %s\n", selected_method))
cat(sprintf("[Infeasibility status] %s\n",
            if (is.null(infeasibility_status)) "FEASIBLE_PASS" else infeasibility_status))

# Extract closest weights for live snap
selected_res <- all_results[[selected_method]]
selected_weights <- selected_res$weights
last_sd <- max(selected_weights$sig_date)
cat(sprintf("\nselected schedule: %d sig_dates | last: %s\n",
            length(unique(selected_weights$sig_date)),
            as.character(last_sd)))

# 2026-04-01 weight separately computed (next sig_date after last walk-forward)
# Apply same method logic at sig_date 2026-04-01
ae <- readRDS(file.path(stage, "alpha_emission.rds"))
asc <- ae$alpha_scores[!is.na(z_blend_composite)]
setkey(asc, Date, Ticker)

raw <- as.data.table(read_parquet(".cache/rawdata.parquet",
                                   col_select = c("Date", "Ticker", "Close", "Vol", "Ret")))
raw[, TradingAmt := Close * Vol]
setkey(raw, Date, Ticker)

as_of <- as.Date("2026-04-01")
UB <- 0.20; LB <- 0.0
LIQ_THRESHOLD <- 2e8

normalize_long_only <- function(w, lb = 0, ub = 0.20, target_sum = 1) {
  w[is.na(w)] <- 0; w[w < lb] <- lb
  if (sum(w) == 0) return(rep(target_sum/length(w), length(w)))
  w <- w / sum(w) * target_sum
  iter <- 0
  while (any(w > ub + 1e-12) && sum(w) > 0 && iter < 100) {
    excess_idx <- which(w > ub)
    excess <- sum(w[excess_idx]) - length(excess_idx) * ub
    w[excess_idx] <- ub
    free <- setdiff(seq_along(w), excess_idx)
    if (length(free) == 0) break
    if (sum(w[free]) == 0) w[free] <- excess / length(free)
    else w[free] <- w[free] + excess * (w[free] / sum(w[free]))
    w <- w / sum(w) * target_sum
    iter <- iter + 1
  }
  w
}

linear_tilt_qd <- function(alpha_t, lambda = 1.5, lb = 0, ub = 0.20) {
  N <- length(alpha_t)
  r <- rank(alpha_t, ties.method = "average")
  centered <- (r - mean(r)) / (N - 1)
  w_raw <- pmax(1 + lambda * 2 * centered, 1e-6)
  w <- w_raw / sum(w_raw)
  names(w) <- names(alpha_t)
  normalize_long_only(w, lb = lb, ub = ub, target_sum = 1)
}

linear_tilt_to_penalty <- function(alpha_t, lambda = 1.5, w_prev = NULL, phi = 3.0,
                                    lb = 0, ub = 0.20) {
  w_tilt <- linear_tilt_qd(alpha_t, lambda = lambda, lb = lb, ub = ub)
  if (is.null(w_prev) || phi <= 0) return(w_tilt)
  wp <- numeric(length(w_tilt)); names(wp) <- names(w_tilt)
  common <- intersect(names(w_tilt), names(w_prev))
  wp[common] <- w_prev[common]
  dropped <- 1 - sum(wp); if (dropped > 0) wp <- wp + dropped * w_tilt
  if (sum(wp) > 0) wp <- wp / sum(wp)
  blend <- phi / (1 + phi)
  w_out <- blend * wp + (1 - blend) * w_tilt
  normalize_long_only(w_out, lb = lb, ub = ub, target_sum = 1)
}

# Buffer rule application
apply_buffer_rule <- function(panel_t, w_prev = NULL, keep_n = 40L, entry_n = 20L) {
  setorder(panel_t, -z_blend_composite)
  candidates <- panel_t$Ticker[1:min(keep_n, nrow(panel_t))]
  if (is.null(w_prev) || length(w_prev) == 0L) {
    final_tk <- panel_t$Ticker[1:min(entry_n, nrow(panel_t))]
  } else {
    held_tk <- names(w_prev)[w_prev > 1e-6]
    held_in_keep <- intersect(held_tk, candidates)
    n_held_keep <- length(held_in_keep)
    new_pool <- setdiff(panel_t$Ticker[1:min(entry_n, nrow(panel_t))], held_in_keep)
    need_new <- max(0, entry_n - n_held_keep)
    final_tk <- c(held_in_keep, head(new_pool, need_new))
    if (length(final_tk) > entry_n) final_tk <- final_tk[1:entry_n]
    if (length(final_tk) < 5L) {
      final_tk <- panel_t$Ticker[1:min(entry_n, nrow(panel_t))]
    }
  }
  panel_t[Ticker %in% final_tk]
}

# Get last sig_date weights as w_prev
last_walk_weights <- selected_weights[sig_date == last_sd]
w_prev_2604 <- setNames(last_walk_weights$weight, last_walk_weights$ticker)
cat(sprintf("\nw_prev (last walk-forward sig_date %s): n=%d\n",
            as.character(last_sd), length(w_prev_2604)))

# 2026-04-01 alpha + liquidity
panel_t <- asc[Date == as_of]
regime_t <- panel_t$regime_state[1L]
cat(sprintf("regime @ 2026-04-01: %s\n", regime_t))

liq_data <- raw[Date >= (as_of - 30L) & Date < as_of,
                 .(AvgTA = mean(TradingAmt, na.rm=TRUE)), by = Ticker]
liquid_tk <- liq_data[AvgTA >= LIQ_THRESHOLD, Ticker]
panel_t <- panel_t[Ticker %in% liquid_tk]

# Apply buffer (selected method is buffer40 phi10)
picks <- apply_buffer_rule(panel_t, w_prev_2604, keep_n = 40L, entry_n = 20L)
alpha_t <- picks$z_blend_composite
names(alpha_t) <- picks$Ticker

ub_use <- if (regime_t == "CRISIS") min(UB, 0.10) else UB

# Apply selected method weight function (Iter31_phi10_buffer40)
w_2604 <- linear_tilt_to_penalty(alpha_t, lambda = 1.5, w_prev = w_prev_2604,
                                   phi = 10, lb = 0, ub = ub_use)

cat(sprintf("\n2026-04-01 weights (method=%s, regime=%s, ub_use=%.2f):\n",
            selected_method, regime_t, ub_use))
cat(sprintf("  n=%d | Σw=%.6f | max_w=%.4f | min_w=%.4f\n",
            length(w_2604), sum(w_2604), max(w_2604), min(w_2604)))

w_2604_dt <- data.table(
  sig_date = as_of,
  ticker = names(w_2604),
  weight = as.numeric(w_2604),
  regime = regime_t,
  method = selected_method
)
setorder(w_2604_dt, -weight)
print(w_2604_dt)

# Build final weights.csv: selected method's 267m walk-forward + 2026-04-01 live
weights_full <- rbindlist(list(
  selected_weights[, .(sig_date, ticker, weight, regime, method)],
  w_2604_dt
), fill = TRUE)
setorder(weights_full, sig_date, -weight)
fwrite(weights_full, file.path(stage, "weights.csv"))
fwrite(weights_full, file.path(mailbox, "weights.csv"))
cat(sprintf("\nweights.csv updated: %d rows | %d sig_dates\n",
            nrow(weights_full), length(unique(weights_full$sig_date))))
cat(sprintf("Density: %d / 268 = %.3f\n",
            length(unique(weights_full$sig_date)),
            length(unique(weights_full$sig_date)) / 268))

# Recompute metrics for selected
selected_metrics <- agg_dt[method == selected_method]

# Build infeasibility report
infeasibility_report <- if (n_pass > 0L) NULL else list(
  status = "ALL_METHODS_INFEASIBLE_BOTH_HARD_GATES",
  violated_constraints = c("turnover_annual_one_way_hard_cap_6.0",
                            "max_drawdown_hard_gate_45pct"),
  n_methods_tested = nrow(agg_dt),
  n_methods_passing = 0L,
  closest_to_feasibility = list(
    method = selected_method,
    TO_annual = selected_metrics$TO_annual,
    TO_excess_pct = round((selected_metrics$TO_annual - TO_HARD_CAP) / TO_HARD_CAP * 100, 2),
    MDD = selected_metrics$MDD,
    MDD_excess_pp = round(abs(selected_metrics$MDD) - abs(MDD_HARD_GATE), 4) * 100,
    SR_net = selected_metrics$SR,
    CAGR = selected_metrics$CAGR,
    feasibility_dist = selected_metrics$feasibility_dist
  ),
  suggested_resolution = list(
    option_A = "Q-Lead override: STR_1715 admit precedent L-307 baseline TO ~10.5 was admitted; consider relaxing TO hard cap to 7.0 (extends Hurdle Rule v2.2 with composite-specific exception).",
    option_B = "Alpha-layer redesign: z_blend composite top20 selection inherently produces TO 7-10 due to z_blend monthly volatility; consider quarterly rebalance or alpha smoothing.",
    option_C = "Switch to Iter31_LinearTilt admit baseline (TO 10.49, MDD -47.09%) which is the STR_1715 L-307 lineage retention — but it also fails TO 6.0 + MDD -45% strict.",
    option_D = "Reduce universe coverage via stricter liquidity (2e9 KRW) — may reduce alpha breadth and TO simultaneously."
  ),
  qlead_decision_marker = "REQUIRED — All optimizer-side methods fail hard gates. Q-Lead must explicitly override or accept infeasibility.",
  charter_v17_section_8_no_silent_override = "COMPLIANT — explicit infeasibility report issued; no silent constraint relaxation."
)

# Save aggregated comparison + infeasibility report
fwrite(agg_dt, file.path(stage, "opt_method_comparison_final.csv"))

# Update optimization_package.json (final)
draft <- fromJSON(file.path(mailbox, "optimization_package_draft.json"),
                   simplifyVector = FALSE)

# Replace target_weights with new 2026-04-01 live snap
new_target_weights <- as.list(w_2604_dt$weight)
names(new_target_weights) <- w_2604_dt$ticker

draft$target_weights <- new_target_weights
draft$method_selected <- selected_method
draft$selection_objective_formula <- sprintf(
  "Hard filter cascade: TO ≤ %.1f AND MDD > %.2f%% MUST PASS. If none, closest feasibility distance.",
  TO_HARD_CAP, MDD_HARD_GATE * 100)
draft$infeasibility_report <- infeasibility_report

# Update expected metrics
draft$expected_information_ratio <- selected_metrics$SR
draft$expected_active_return <- selected_metrics$SR * selected_metrics$Sortino
draft$expected_cagr <- selected_metrics$CAGR
draft$expected_mdd <- selected_metrics$MDD
draft$expected_sortino <- selected_metrics$Sortino
draft$expected_calmar <- selected_metrics$Calmar
draft$turnover_annual_one_way <- selected_metrics$TO_annual
draft$estimated_cost_bps_annual <- selected_metrics$TO_annual * 15
draft$hhi_mean_schedule <- selected_metrics$HHI_mean
draft$fqmj_mean_schedule <- selected_metrics$F_QMJ_mean

draft$regime_sr <- list(
  BULL = list(sr = selected_metrics$BULL, n = selected_metrics$BULL_n),
  NORMAL = list(sr = selected_metrics$NORMAL, n = selected_metrics$NORMAL_n),
  CAUTION = list(sr = selected_metrics$CAUTION, n = selected_metrics$CAUTION_n),
  CRISIS = list(sr = selected_metrics$CRISIS, n = selected_metrics$CRISIS_n)
)

# Schedule fidelity
sig_dates_used <- sort(unique(weights_full$sig_date))
draft$schedule_fidelity <- list(
  sig_dates_count = length(sig_dates_used),
  alpha_emission_target_count = 268L,
  density_ratio = length(sig_dates_used) / 268,
  density_ratio_mandate = 0.95,
  pass = (length(sig_dates_used) / 268 >= 0.95),
  as_of_date_in_schedule = "2026-04-01" %in% as.character(sig_dates_used)
)

# Update method comparison with all 13 methods
method_comparison <- list()
for (m_i in seq_len(nrow(agg_dt))) {
  m_r <- agg_dt[m_i]
  method_comparison[[m_r$method]] <- list(
    sr_net = m_r$SR,
    cagr = m_r$CAGR,
    mdd = m_r$MDD,
    sortino = m_r$Sortino,
    calmar = m_r$Calmar,
    turnover_annual = m_r$TO_annual,
    hhi_mean = m_r$HHI_mean,
    fqmj_mean = m_r$F_QMJ_mean,
    regime_sr_BULL = m_r$BULL,
    regime_sr_NORMAL = m_r$NORMAL,
    regime_sr_CAUTION = m_r$CAUTION,
    regime_sr_CRISIS = m_r$CRISIS,
    TO_pass = m_r$TO_pass,
    MDD_pass = m_r$MDD_pass,
    hard_pass = m_r$HARD_PASS,
    feasibility_dist = m_r$feasibility_dist
  )
}
draft$method_comparison <- method_comparison

# Method shopping log
method_log <- lapply(seq_len(nrow(agg_dt)), function(i) {
  r <- agg_dt[i]
  list(
    name = r$method,
    sr_net = r$SR,
    cagr = r$CAGR,
    mdd = r$MDD,
    turnover_annual = r$TO_annual,
    hhi_mean = r$HHI_mean,
    fqmj_mean = r$F_QMJ_mean,
    TO_pass = r$TO_pass,
    MDD_pass = r$MDD_pass,
    hard_pass = r$HARD_PASS,
    feasibility_dist = r$feasibility_dist,
    selected = (r$method == selected_method)
  )
})

draft$method_shopping_log <- list(
  candidates_tried = nrow(agg_dt),
  cap = 13L,
  selection_objective = "hard_filter_cascade_TO_6_MDD_45",
  selection_objective_formula = draft$selection_objective_formula,
  TO_hard_cap = TO_HARD_CAP,
  MDD_hard_gate = MDD_HARD_GATE,
  parallel_exec = FALSE,
  n_workers = 1L,
  rcpp_used = FALSE,
  selected = selected_method,
  selection_evidence = sprintf(
    "Codex C1+C2+C5 disposition ACCEPT: hard filter cascade applied. %d methods tested, %d pass both. Selected %s by feasibility distance + SR_net (closest to feasibility region given INFEASIBILITY).",
    nrow(agg_dt), n_pass, selected_method),
  method_log = method_log
)

# Final factor loading at 2026-04-01
common_2604 <- intersect(names(new_target_weights), emat$Ticker)
B_2604 <- as.matrix(emat[Ticker %in% common_2604][match(common_2604, Ticker),
                          .(RM_KR, F_SIZE, F_VAL, F_MOM, F_QMJ, F_BAB, F_LIQ, F_TAIL)])
w_2604_v <- unlist(new_target_weights[common_2604])
factor_loading_final <- as.numeric(t(B_2604) %*% w_2604_v)
names(factor_loading_final) <- c("RM_KR", "F_SIZE", "F_VAL", "F_MOM", "F_QMJ", "F_BAB", "F_LIQ", "F_TAIL")
draft$factor_loading_2604 <- as.list(factor_loading_final)

# Updated SHA256
draft$inputs_referenced$weights_csv_sha256 <- digest(
  file = file.path(stage, "weights.csv"), algo = "sha256")

# Save updated draft (overwrite optimization_package_draft.json)
write_json(draft, file.path(mailbox, "optimization_package_draft.json"),
            pretty = TRUE, auto_unbox = TRUE, null = "null", na = "null")
cat(sprintf("\n[Saved] %s\n", file.path(mailbox, "optimization_package_draft.json")))

cat("[OPT-Step9] DONE\n")
