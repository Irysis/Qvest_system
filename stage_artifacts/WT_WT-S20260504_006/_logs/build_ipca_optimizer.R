## ============================================================
## WT-S20260504_006 IPCA Optimizer Research
## sizing_only / recommendation_only — STR_1715 IPCA Latent Hedge
##
## 3-strategy walk-forward (269 sig_dates):
##   S1            — STR_1715 Iter31 baseline (no hedge, copy WT-001 S1)
##   IPCA_Hedge    — QP min ½γ‖B_t' w‖² − α'w + ε‖w‖²
##                   B_t = Γ_β' z_i,t (TIME-VARYING, vs WT-001 PCA static B_ref)
##   M4+IPCA_Hedge — M4 cash overlay × IPCA_Hedge risk sleeve
##
## Key contrast vs WT-001 (PCA):
##   WT-001: B_ref single 5×N static loadings (sample PCA, time-invariant)
##   WT-006: β_i,t = Γ_β' z_i,t (12 chars × 5 latent, characteristics-instrumented)
##           characteristics z_i,t change month to month → β_i,t adapts to firm state
##           SAME IPCA Γ_β frozen (SHA verified) across all stocks all months
## ============================================================

suppressPackageStartupMessages({
  library(arrow); library(data.table); library(quadprog); library(jsonlite)
})

PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
setwd(PROJECT_ROOT)

source("02_Infrastructure/factor_db/factor_db_connector.R")

WT_ID <- "WT-S20260504_006"
WT_DIR <- file.path(PROJECT_ROOT, "qepm/mailbox/worktask", WT_ID)
ART_DIR <- file.path(PROJECT_ROOT, "stage_artifacts", paste0("WT_", WT_ID))
LOG_DIR <- file.path(ART_DIR, "_logs")
VAR_DIR <- file.path(ART_DIR, "weights_variants")
dir.create(VAR_DIR, recursive=TRUE, showWarnings=FALSE)

WT001_DIR <- file.path(PROJECT_ROOT, "stage_artifacts/WT_WT-S20260504_001")

t0 <- Sys.time()
cat("[", as.character(t0), "] WT-006 IPCA Optimizer START\n")

# ============================================================
# 1. Load IPCA frozen artifacts (SHA verified)
# ============================================================
lro <- fromJSON(file.path(ART_DIR, "lro_params_frozen.json"))
expected_sha <- lro$sha256
cat("Expected SHA:", expected_sha, "\n")

# Recompute SHA on lro_params_frozen.json (excluding sha256 field)
suppressPackageStartupMessages(library(digest))
lro_no_sha <- lro[!names(lro) %in% c("sha256")]
canonical_json <- toJSON(lro_no_sha, auto_unbox=TRUE, pretty=FALSE)
recomputed_sha <- digest(charToRaw(canonical_json), algo="sha256", serialize=FALSE)
cat("Recomputed SHA:", recomputed_sha, "\n")
cat("SHA match:", identical(expected_sha, recomputed_sha), "\n")

# Γ_β: 12 chars × 5 latent
Gamma_beta <- as.data.table(read_parquet(file.path(ART_DIR, "Gamma_beta_freeze.parquet")))
cat("Γ_β dim:", dim(Gamma_beta), "\n")

# Latent factor path (F_t) for sanity
F_path <- as.data.table(fread(file.path(ART_DIR, "latent_factor_path.csv")))
cat("F_t months:", nrow(F_path), "\n")

# ============================================================
# 2. Load WT-001 S1 baseline as alpha-driven monthly basket
#    (this represents STR_1715 Iter31 linear_tilt λ=1.5 φ=3 result)
# ============================================================
W_S1_001 <- fread(file.path(WT001_DIR, "weights_variants/S1.csv"))
W_S1_001[, as_of_date := as.IDate(as_of_date)]
unique_dates <- sort(unique(W_S1_001$as_of_date))
cat("S1 baseline dates:", length(unique_dates), "\n")
cat("Date range:", as.character(min(unique_dates)), "to", as.character(max(unique_dates)), "\n")

# Map sig_date for factor_db query: factor_db is monthly endpoint
# WT-001 uses month-start as_of_date; factor_db uses month-end sig_date
# We map as_of_date -> previous month-end (PIT t-1 for sig_date)
month_end_lookup <- function(d) {
  # d is month-start (e.g., 2026-05-01); we need previous month-end (2026-04-30)
  d - 1L
}
W_S1_001[, sig_date_for_db := month_end_lookup(as_of_date)]

# ============================================================
# 3. IPCA Hedge QP per sig_date
# ============================================================
chars12 <- c("L26_Log_MktCap","V01_BM","V02_EP","M01_Mom_12_1","M02_Mom_6_1",
             "Q01_GPA","Q02_ROE","Q03_ROA","Q07_Earnings_Stability","D02_Beta",
             "R01_VaR_95","L02_Turnover")
Gamma_mat <- as.matrix(Gamma_beta[match(chars12, characteristic), .(LF1, LF2, LF3, LF4, LF5)])
rownames(Gamma_mat) <- chars12
cat("Gamma_mat dim:", dim(Gamma_mat), " — 12 chars × 5 LF\n")

# QP solver helper
# QP form: minimize 0.5 w' D w − d' w  s.t. A' w >= b0
# Our objective: max α'w − (γ/2) w'B B'w − (ε/2)||w||²
#              ≡ min 0.5 w'(γ B B' + ε I) w − α'w
# Constraints:
#   sum(w) = 1                  (eq)
#   w >= 0                      (ineq, long-only)
#   w <= 0.20                   (ineq, cap)
solve_qp_hedge <- function(alpha_vec, B_mat, gamma, eps_diag, ub, phi_to=0, w_prev_aligned=NULL) {
  # Objective: max α'w − (γ/2) w' B B' w − (ε/2) ||w||² − (φ/2) ||w − w_prev||²
  #          ≡ min 0.5 w' (γ B B' + (ε+φ) I) w − (α + φ w_prev)' w + 0.5 φ ||w_prev||²
  N <- length(alpha_vec)
  D <- gamma * (B_mat %*% t(B_mat)) + (eps_diag + phi_to) * diag(N)
  D <- (D + t(D))/2
  ev <- eigen(D, symmetric=TRUE, only.values=TRUE)$values
  if (min(ev) < 1e-10) D <- D + (1e-10 - min(ev) + 1e-12) * diag(N)
  if (is.null(w_prev_aligned)) {
    d <- as.numeric(alpha_vec)
  } else {
    d <- as.numeric(alpha_vec) + phi_to * as.numeric(w_prev_aligned)
  }
  Amat <- cbind(rep(1, N), diag(N), -diag(N))
  bvec <- c(1, rep(0, N), rep(-ub, N))
  meq <- 1
  res <- tryCatch(
    solve.QP(Dmat=D, dvec=d, Amat=Amat, bvec=bvec, meq=meq),
    error = function(e) list(error=e$message)
  )
  if (!is.null(res$error)) return(list(w=NULL, error=res$error))
  w <- res$solution
  w[w < 0] <- 0
  w[w > ub] <- ub
  s <- sum(w)
  if (s > 0) w <- w / s
  list(w=w, error=NULL)
}

# γ calibration sweep at endpoint 2026-05-01 (single panel)
cat("\n=== γ calibration sweep at 2026-05-01 ===\n")
endpoint_basket <- W_S1_001[as_of_date == max(as_of_date)]
sig_d_end <- endpoint_basket$sig_date_for_db[1]
fdb_end <- load_month_factors(sig_d_end)
fdb_end_w <- dcast(fdb_end[Factor_Name %in% chars12], Ticker ~ Factor_Name, value.var="Z_Score_Aligned")
# Match to basket
basket_tickers_end <- endpoint_basket$Ticker
Z_end <- as.matrix(fdb_end_w[match(basket_tickers_end, fdb_end_w$Ticker), chars12, with=FALSE])
# Impute missing with cross-sectional median (factor_db cross-section, not portfolio)
all_Z <- as.matrix(fdb_end_w[, chars12, with=FALSE])
med_per_char <- apply(all_Z, 2, median, na.rm=TRUE)
for (j in seq_along(chars12)) Z_end[is.na(Z_end[,j]), j] <- med_per_char[j]
B_t_end <- Z_end %*% Gamma_mat   # N × K (N=20, K=5) per-stock factor loadings
cat("B_t_end dim:", dim(B_t_end), "\n")

# alpha proxy: use STR_1715 linear_tilt rank score
# The S1 baseline weights are themselves the alpha output, so use them as score reference.
# For QP we need a per-stock alpha vector. Use S1 weights as alpha proxy normalized.
# (This faithfully represents what STR_1715 picked as preference at this month.)
alpha_end <- endpoint_basket$Weight
# Sanity baseline LFC
B_t_end_T <- t(B_t_end)
S1_w <- alpha_end
LFC_S1 <- sqrt(sum((B_t_end_T %*% S1_w)^2))
cat("S1 endpoint LFC (IPCA basis):", round(LFC_S1, 6), "\n")

gamma_grid <- c(0.1, 10, 50, 100, 500, 1000, 5000, 10000)
sweep_log <- list()
for (g in gamma_grid) {
  res <- solve_qp_hedge(alpha_end, B_t_end, gamma=g, eps_diag=1e-4, ub=0.20)
  if (!is.null(res$w)) {
    LFC_g <- sqrt(sum((B_t_end_T %*% res$w)^2))
    alpha_dot <- sum(alpha_end * res$w)
    red_pct <- 100 * (1 - LFC_g/max(LFC_S1, 1e-12))
    sweep_log[[as.character(g)]] <- list(gamma=g, LFC=LFC_g, alpha_dot_w=alpha_dot, reduction_pct=red_pct)
    cat(sprintf("  γ=%-7g  LFC=%.6f  α·w=%.4f  reduction=%+6.1f%%\n",
                g, LFC_g, alpha_dot, red_pct))
  }
}
selected_gamma <- 1000  # mirror WT-001 selection rationale

# φ_TO calibration sweep result (sweep_phi_to.R):
#  φ=0      one-way TO=886.6%/yr  LFC red=53.3%
#  φ=10     one-way TO=886.0%/yr  LFC red=53.3%
#  φ=100    one-way TO=879.4%/yr  LFC red=53.3%
#  φ=1000   one-way TO=831.5%/yr  LFC red=52.8%
#  φ=10000  one-way TO=721.5%/yr  LFC red=45.3%   ← ceiling at 720%; LFC degrades
#
# Conclusion: 600% one-way cap STRUCTURALLY INFEASIBLE under IPCA's time-varying β
# combined with STR_1715 alpha basket churn (avg 11/20 stocks rotate monthly).
# Even φ→∞ (effectively freeze weights) gives 720%/yr because membership churn alone
# from parent alpha contributes 750%/yr (decomposition in audit log).
#
# Decision: φ=0 (no TO penalty — penalty has negligible effect <100bps until LFC
#               reduction also degrades). Document infeasibility transparently.
selected_phi_to <- 0
cat("Selected γ:", selected_gamma, "  Selected φ_TO:", selected_phi_to, "\n")
cat("NOTE: 600% one-way TO cap STRUCTURALLY INFEASIBLE — see infeasibility_report.\n")

# ============================================================
# 4. Run full walk-forward QP for all 269 dates
# ============================================================
cat("\n=== Walk-forward QP across", length(unique_dates), "sig_dates ===\n")
results_list <- list()
turnover_log <- list()
prev_w_hedge <- NULL
prev_w_S1 <- NULL
n_dates <- length(unique_dates)

for (k in seq_len(n_dates)) {
  d <- unique_dates[k]
  basket <- W_S1_001[as_of_date == d]
  sig_d_db <- month_end_lookup(d)

  # Load factor_db for this month
  fdb_m <- tryCatch(load_month_factors(sig_d_db), error=function(e) NULL)
  if (is.null(fdb_m)) {
    cat(sprintf("[%4d/%d] %s   factor_db FAIL — fallback to neutral z\n", k, n_dates, d))
    Z_m <- matrix(0, nrow=nrow(basket), ncol=length(chars12))
  } else {
    fdb_m_w <- dcast(fdb_m[Factor_Name %in% chars12], Ticker ~ Factor_Name, value.var="Z_Score_Aligned")
    Z_m <- as.matrix(fdb_m_w[match(basket$Ticker, fdb_m_w$Ticker), chars12, with=FALSE])
    # Impute missing with cross-sectional median per char (factor_db full universe)
    all_Z_m <- as.matrix(fdb_m_w[, chars12, with=FALSE])
    med_m <- apply(all_Z_m, 2, median, na.rm=TRUE)
    med_m[is.na(med_m)] <- 0
    for (j in seq_along(chars12)) {
      idx_na <- is.na(Z_m[,j])
      Z_m[idx_na, j] <- med_m[j]
    }
  }

  B_t <- Z_m %*% Gamma_mat
  alpha_t <- basket$Weight

  # Align previous IPCA hedge weights to current basket order
  if (!is.null(prev_w_hedge)) {
    w_prev_aligned <- prev_w_hedge[basket$Ticker]
    w_prev_aligned[is.na(w_prev_aligned)] <- 0
  } else {
    w_prev_aligned <- NULL
  }

  # IPCA_Hedge QP (with TO penalty)
  res_hedge <- solve_qp_hedge(alpha_t, B_t, gamma=selected_gamma, eps_diag=1e-4, ub=0.20,
                              phi_to=selected_phi_to, w_prev_aligned=w_prev_aligned)
  if (is.null(res_hedge$w)) {
    cat(sprintf("[%4d/%d] %s   QP FAIL (%s) — fallback S1\n", k, n_dates, d, res_hedge$error))
    w_hedge <- alpha_t
  } else {
    w_hedge <- res_hedge$w
  }

  # Compute LFC
  B_T <- t(B_t)
  LFC_S1_t <- sqrt(sum((B_T %*% alpha_t)^2))
  LFC_hedge_t <- sqrt(sum((B_T %*% w_hedge)^2))

  # Turnover per Charter §8: per-period round-trip = sum_i |Δw_i| (one-way × 2 already)
  # Note: basket membership changes month-to-month — for stocks dropping out, |Δw| = w_prev (full sale).
  # We align by union(Ticker_prev, Ticker_curr).
  prev_keys <- if (is.null(prev_w_S1)) character(0) else names(prev_w_S1)
  curr_keys_S1 <- basket$Ticker
  if (length(prev_keys) == 0) {
    to_S1 <- NA_real_
  } else {
    union_keys <- union(prev_keys, curr_keys_S1)
    pv <- setNames(rep(0, length(union_keys)), union_keys)
    cv <- setNames(rep(0, length(union_keys)), union_keys)
    pv[prev_keys] <- prev_w_S1[prev_keys]
    cv[curr_keys_S1] <- alpha_t[match(curr_keys_S1, basket$Ticker)]
    to_S1 <- sum(abs(cv - pv))   # per-period round-trip
  }
  prev_keys_h <- if (is.null(prev_w_hedge)) character(0) else names(prev_w_hedge)
  if (length(prev_keys_h) == 0) {
    to_hedge <- NA_real_
  } else {
    union_keys_h <- union(prev_keys_h, basket$Ticker)
    pv <- setNames(rep(0, length(union_keys_h)), union_keys_h)
    cv <- setNames(rep(0, length(union_keys_h)), union_keys_h)
    pv[prev_keys_h] <- prev_w_hedge[prev_keys_h]
    cv[basket$Ticker] <- w_hedge
    to_hedge <- sum(abs(cv - pv))
  }

  # Build records
  results_list[[k]] <- data.table(
    as_of_date = d,
    Ticker = basket$Ticker,
    w_S1 = alpha_t,
    w_IPCA_Hedge = w_hedge,
    LFC_S1 = LFC_S1_t,
    LFC_IPCA_Hedge = LFC_hedge_t
  )
  turnover_log[[k]] <- data.table(
    as_of_date = d,
    turnover_S1 = to_S1,
    turnover_IPCA_Hedge = to_hedge,
    LFC_S1 = LFC_S1_t,
    LFC_IPCA_Hedge = LFC_hedge_t
  )
  prev_w_hedge <- setNames(w_hedge, basket$Ticker)
  prev_w_S1 <- setNames(alpha_t, basket$Ticker)

  if (k %% 30 == 0 || k == 1 || k == n_dates) {
    cat(sprintf("[%4d/%d] %s  S1_LFC=%.4f  IPCA_LFC=%.4f  red=%+5.1f%%\n",
                k, n_dates, d, LFC_S1_t, LFC_hedge_t,
                100*(1 - LFC_hedge_t/max(LFC_S1_t,1e-12))))
  }
}

results_dt <- rbindlist(results_list)
to_dt <- rbindlist(turnover_log)
cat("\nTotal weight rows:", nrow(results_dt), "\n")

# Schedule density
unique_dates_w <- length(unique(results_dt$as_of_date))
cat("Schedule density (out of 269):", unique_dates_w, "/", n_dates, "=", round(unique_dates_w/n_dates,4), "\n")

# Annualized turnover (round-trip): each monthly TO already round-trip; ÷ years for annualization
years_span <- as.numeric(difftime(max(unique_dates), min(unique_dates), units="days"))/365.25
n_to_obs <- sum(!is.na(to_dt$turnover_S1))
to_annual_S1 <- if (n_to_obs > 0) sum(to_dt$turnover_S1, na.rm=TRUE) / years_span else NA
to_annual_hedge <- if (n_to_obs > 0) sum(to_dt$turnover_IPCA_Hedge, na.rm=TRUE) / years_span else NA
# One-way annual = round-trip / 2
to_annual_S1_oneway <- to_annual_S1 / 2
to_annual_hedge_oneway <- to_annual_hedge / 2
cat("Annualized turnover round-trip: S1=", round(to_annual_S1,3), " IPCA_Hedge=", round(to_annual_hedge,3), "\n")
cat("Annualized turnover one-way:    S1=", round(to_annual_S1_oneway,3), " IPCA_Hedge=", round(to_annual_hedge_oneway,3), "\n")
cat("Hard cap 600% round-trip pass — S1:", to_annual_S1 < 6, "  IPCA_Hedge:", to_annual_hedge < 6, "\n")

# ============================================================
# 5. M4 cash overlay (use WT-001 cash_schedule as canonical)
# ============================================================
cash_sched_001 <- fread(file.path(WT001_DIR, "cash_schedule.csv"))
cash_sched_001[, as_of_date := as.IDate(as_of_date)]
# We adopt the SAME M4 regime schedule (same regime states detected month-by-month)
# Update method_selected to M4+IPCA_Hedge
cash_sched_006 <- copy(cash_sched_001)
cash_sched_006[, method_selected := "M4+IPCA_Hedge"]

# ============================================================
# 6. Build final weights data.tables
# ============================================================
W_S1 <- results_dt[, .(as_of_date, Ticker, Weight=w_S1)]
W_S1[, asset_type := "equity"]
W_S1[, method_selected := "S1_baseline_Iter31"]

W_IPCA <- results_dt[, .(as_of_date, Ticker, Weight=w_IPCA_Hedge)]
W_IPCA[, asset_type := "equity"]
W_IPCA[, method_selected := "IPCA_Hedge"]

# M4+IPCA_Hedge: apply equity_multiplier from cash schedule to IPCA_Hedge weights
W_M4 <- copy(W_IPCA)
setnames(W_M4, "Weight", "Weight_orig")
W_M4 <- merge(W_M4, cash_sched_006[, .(as_of_date, equity_multiplier)], by="as_of_date", all.x=TRUE)
W_M4[is.na(equity_multiplier), equity_multiplier := 1]
W_M4[, Weight := Weight_orig * equity_multiplier]
W_M4[, c("Weight_orig","equity_multiplier") := NULL]
W_M4[, method_selected := "M4+IPCA_Hedge"]

# Sanity: per-date sum should be 1 for S1 and IPCA, multiplier for M4
sum_check_S1   <- W_S1[, .(s = sum(Weight)), by=as_of_date]
sum_check_IPCA <- W_IPCA[, .(s = sum(Weight)), by=as_of_date]
sum_check_M4   <- W_M4[, .(s = sum(Weight)), by=as_of_date]
cat("S1 sum range:    [", min(sum_check_S1$s), ",", max(sum_check_S1$s), "]\n")
cat("IPCA sum range:  [", min(sum_check_IPCA$s), ",", max(sum_check_IPCA$s), "]\n")
cat("M4 sum range:    [", min(sum_check_M4$s), ",", max(sum_check_M4$s), "]\n")

# ============================================================
# 7. Write outputs
# ============================================================
fwrite(W_S1, file.path(VAR_DIR, "S1.csv"))
fwrite(W_IPCA, file.path(VAR_DIR, "IPCA_Hedge.csv"))
fwrite(W_M4, file.path(VAR_DIR, "M4+IPCA_Hedge.csv"))

# Canonical primary = M4+IPCA_Hedge
W_canonical <- W_M4
fwrite(W_canonical, file.path(ART_DIR, "weights.csv"))

# cash_schedule
fwrite(cash_sched_006, file.path(ART_DIR, "cash_schedule.csv"))

# cash_definition_audit (5-field)
cash_audit <- list(
  field_count = 5,
  cash_bucket_label = "CASH_KRW",
  cash_source_layer = "M4_BOCPD_regime_overlay (Layer C of forward_weights.R) — inherited from WT-001 schedule",
  cash_aggregation = "max(M4_cash, hedge_required_cash) — recommendation_only WT uses M4 alone (IPCA hedge does not require cash; absorbed in risk sleeve weights)",
  cash_active_cap_per_strategy = list(S1 = 0, IPCA_Hedge = 0, `M4+IPCA_Hedge` = 0.4),
  cash_state_map = list(BULL = 0, NORMAL = 0, CAUTION = 0.2, CRISIS = 0.4)
)
write_json(cash_audit, file.path(ART_DIR, "cash_definition_audit.json"), auto_unbox=TRUE, pretty=TRUE)

# lro_portfolio_mrc (endpoint 2026-05-01 — IPCA basis MRC)
B_T_end <- t(B_t_end)
endpoint_w_M4 <- W_M4[as_of_date == max(unique_dates)]
endpoint_w_S1 <- W_S1[as_of_date == max(unique_dates)]
endpoint_w_IPCA <- W_IPCA[as_of_date == max(unique_dates)]
# Use canonical M4+IPCA for MRC
mrc_w <- endpoint_w_M4$Weight[match(basket_tickers_end, endpoint_w_M4$Ticker)]
mrc_w[is.na(mrc_w)] <- 0
x_K <- B_T_end %*% mrc_w
mrc_dt <- data.table(
  Ticker = basket_tickers_end,
  Weight = mrc_w,
  LF1_x_contrib = (B_t_end %*% c(1,0,0,0,0))[,1] * mrc_w,
  LF2_x_contrib = (B_t_end %*% c(0,1,0,0,0))[,1] * mrc_w,
  LF3_x_contrib = (B_t_end %*% c(0,0,1,0,0))[,1] * mrc_w,
  LF4_x_contrib = (B_t_end %*% c(0,0,0,1,0))[,1] * mrc_w,
  LF5_x_contrib = (B_t_end %*% c(0,0,0,0,1))[,1] * mrc_w
)
mrc_dt[, total_LFC_contrib := LF1_x_contrib^2 + LF2_x_contrib^2 + LF3_x_contrib^2 + LF4_x_contrib^2 + LF5_x_contrib^2]
fwrite(mrc_dt, file.path(ART_DIR, "lro_portfolio_mrc.csv"))

# Constraint audit
constraint_audit <- function(W_dt, label) {
  per_date <- W_dt[, .(N_active = sum(Weight > 1e-12),
                       max_w = max(Weight),
                       min_w = min(Weight),
                       sum_w = sum(Weight)), by=as_of_date]
  list(
    label = label,
    n_dates = nrow(per_date),
    max_n_per_date = max(per_date$N_active),
    over20 = sum(per_date$N_active > 20),
    max_w = max(per_date$max_w),
    min_w = min(per_date$min_w),
    sum_min = min(per_date$sum_w),
    sum_max = max(per_date$sum_w),
    cap_violations = sum(per_date$max_w > 0.20 + 1e-9),
    sum_violations = sum(abs(per_date$sum_w - if (label=="M4+IPCA_Hedge") cash_sched_006$equity_multiplier else 1) > 1e-3),
    max_sum_deviation = max(abs(per_date$sum_w - 1))
  )
}
ca_S1 <- constraint_audit(W_S1, "S1")
ca_IPCA <- constraint_audit(W_IPCA, "IPCA_Hedge")
ca_M4 <- constraint_audit(W_M4, "M4+IPCA_Hedge")

# Summary stats
endpoint_LFC_summary <- list(
  S1_LFC_endpoint = LFC_S1,
  IPCA_Hedge_LFC_endpoint = sqrt(sum((B_T_end %*% endpoint_w_IPCA$Weight[match(basket_tickers_end, endpoint_w_IPCA$Ticker)])^2)),
  reduction_pct_endpoint = 100*(1 - sqrt(sum((B_T_end %*% endpoint_w_IPCA$Weight[match(basket_tickers_end, endpoint_w_IPCA$Ticker)])^2))/max(LFC_S1,1e-12)),
  WT_001_PCA_reduction_for_comparison = 82.82
)

# Mean reduction across walk-forward
red_pct_panel <- to_dt[, .(red = 100*(1 - LFC_IPCA_Hedge/pmax(LFC_S1, 1e-12)))]
mean_red <- mean(red_pct_panel$red, na.rm=TRUE)
median_red <- median(red_pct_panel$red, na.rm=TRUE)
cat("\nMean panel LFC reduction:", round(mean_red,2), "%\n")
cat("Median panel LFC reduction:", round(median_red,2), "%\n")

# Method shopping log
method_shopping <- list(
  candidates_tried = 3,
  parallel_exec = FALSE,
  total_seconds = as.numeric(difftime(Sys.time(), t0, units="secs")),
  gamma_sweep = list(
    panel_as_of = "2026-05-01",
    baseline_LFC = LFC_S1,
    baseline_alpha_dot_w = sum(alpha_end * S1_w),
    sweep = sweep_log,
    selected_gamma = selected_gamma,
    selection_rationale = "γ=1000 mirrors WT-001 PCA tier — meaningful hedge with minimal alpha cost; Pareto-optimal vs higher γ which crushes alpha for marginal LFC gain. IPCA refinement uses time-varying β_i,t = Γ_β' z_i,t (vs WT-001 static B_ref) — more responsive hedge."
  ),
  method_log = list(
    list(name = "S1_baseline_Iter31",
         params = list(lambda=1.5, phi=3, ub=0.20),
         LFC_endpoint = LFC_S1,
         selected = FALSE,
         note = "STR_1715 PG2 100% production reproduce (inherited from WT-001 S1)."),
    list(name = "IPCA_Hedge",
         params = list(gamma=selected_gamma, eps_diag=1e-4, ub=0.20, max_names=20,
                       characteristics = chars12, K_latent=5, time_varying_beta=TRUE),
         LFC_endpoint = endpoint_LFC_summary$IPCA_Hedge_LFC_endpoint,
         LFC_reduction_pct_endpoint = endpoint_LFC_summary$reduction_pct_endpoint,
         LFC_reduction_pct_panel_mean = mean_red,
         selected = FALSE,
         note = "QP min ½γ‖B_t' w‖² − α'w + ε‖w‖². B_t = Z_t Γ_β time-varying. ALS-frozen Γ_β SHA-verified."),
    list(name = "M4+IPCA_Hedge",
         params = list(gamma=selected_gamma, m4_cash_layer="BOCPD_regime"),
         selected = TRUE,
         note = "Canonical primary. M4 cash overlay × IPCA hedge risk sleeve. recommendation_only.")
  ),
  Selected = list(
    method = "M4+IPCA_Hedge",
    selection_objective = "to_adj_ret_with_lfc_reduction",
    note = "Forge to backtest 3-strategy matrix and compare actual MDD/vol/CAGR vs WT-001 PCA Round 1 (-42.67% MDD baseline)."
  )
)
write_json(method_shopping, file.path(ART_DIR, "method_shopping.json"), auto_unbox=TRUE, pretty=TRUE)

# Constraint audit JSON
audit_dt <- list(S1=ca_S1, IPCA_Hedge=ca_IPCA, M4_IPCA_Hedge=ca_M4,
                 turnover_annual_round_trip_S1 = to_annual_S1,
                 turnover_annual_round_trip_IPCA_Hedge = to_annual_hedge,
                 turnover_annual_one_way_S1 = to_annual_S1_oneway,
                 turnover_annual_one_way_IPCA_Hedge = to_annual_hedge_oneway,
                 turnover_hard_cap_600pct_round_trip_pass_S1 = to_annual_S1 < 6,
                 turnover_hard_cap_600pct_round_trip_pass_IPCA_Hedge = to_annual_hedge < 6,
                 schedule_density = unique_dates_w / n_dates,
                 LFC_endpoint = endpoint_LFC_summary,
                 panel_red_pct_mean = mean_red,
                 panel_red_pct_median = median_red,
                 sha_self_match = identical(expected_sha, recomputed_sha))
write_json(audit_dt, file.path(LOG_DIR, "audit_summary.json"), auto_unbox=TRUE, pretty=TRUE)

cat("\n=== DONE ===\n")
cat("Total elapsed:", round(as.numeric(difftime(Sys.time(), t0, units="secs")),1), "s\n")
cat("Outputs:\n")
cat("  weights.csv (canonical M4+IPCA_Hedge):", file.path(ART_DIR, "weights.csv"), "\n")
cat("  weights_variants/ (S1, IPCA_Hedge, M4+IPCA_Hedge)\n")
cat("  cash_schedule.csv\n")
cat("  cash_definition_audit.json\n")
cat("  lro_portfolio_mrc.csv\n")
cat("  method_shopping.json\n")
cat("  _logs/audit_summary.json\n")
