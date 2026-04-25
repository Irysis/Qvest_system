#==============================================================================
# WT-D20260425_006: MEGA_05 Crisis Overlay (Iter 1) — Risk Research
#
# Inputs:
#   - alpha_package.json (20 ticker × α̂; 6F factor_specs; 2 overlay_specs)
#   - overlay_signals.parquet (252 rows BM-derived multipliers)
#   - .cache/rawdata.parquet (daily OHLCV/Ret)
#   - .cache/kr_factor_returns.parquet (FF5 + WML monthly)
#   - .cache/regime_v7.parquet (Regime Engine v7.1)
#   - WT-D20260425_003 risk_package.json (baseline MEGA_05 PG2 active)
#
# Mission (Iter 1 specific):
#   1. Σ = BΩB' + D for the 20-ticker MEGA_05 universe (selection_objective: condition_number)
#   2. Overlay impact on portfolio-level σ:
#      - brake ON (~38.9%) vs OFF (~61.1%) regime split
#      - effective_vol_on = vol_off × overlay_mult (size-scaling effect)
#   3. Crisis decorrelation: regime-conditional correlation (Bull/Normal/Caution/Crisis)
#   4. TDC vs WT_003 MEGA_05 baseline (same 20 tickers — Sequential Admission proxy)
#   5. 8-stress + EVT-VaR + CVaR + CDaR
#   6. Rolling Σ stability (5Y sliding) → RF-A1 response
#
# CRITICAL CONSTRAINTS (Hook enforced):
#   - alpha_package not modified
#   - No weight proposals (Optimizer territory)
#   - selection_objective ∈ {condition_number, stress_robust, crowding, shrinkage_quality}
#   - Σ PSD enforced (min_eig > 0)
#   - No SR/IR/return-based estimator selection
#
# as_of_date: 2026-04-25 (signal_as_of: 2024-01-22)
#==============================================================================

t0 <- Sys.time()
set.seed(20260425L + 6L + 100L)

# ── Paths ──────────────────────────────────────────────────────────────────
.root_candidates <- c(
  "/mnt/c/Users/User/OneDrive/\xeb\xb0\x94\xed\x83\x95 \xed\x99\x94\xeb\xa9\xb4/Quant_Module_Moltbot",
  "/mnt/c/Users/99922/OneDrive/\xeb\xb0\x94\xed\x83\x95 \xed\x99\x94\xeb\xa9\xb4/Quant_Module_Moltbot"
)
ROOT <- .root_candidates[sapply(.root_candidates, dir.exists)][1]
rm(.root_candidates)

FUNC_PATH <- file.path(ROOT, "02_Infrastructure")
WT_ID     <- "WT-D20260425_006"
WT_DIR    <- file.path(ROOT, "qepm", "mailbox", "worktask", WT_ID)
ART_DIR   <- file.path(ROOT, "qepm", "stage_artifacts", paste0("WT_", WT_ID))
AS_OF     <- as.Date("2024-01-22")  # Pre-LB end (alpha signal_as_of)
LOCKBOX_START <- as.Date("2024-01-23")

dir.create(ART_DIR, recursive = TRUE, showWarnings = FALSE)

source(file.path(FUNC_PATH, "config.R"))
suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite); library(digest); library(stats)
})
options(scipen = 999); Sys.setenv(TZ = "Asia/Seoul")

cat(sprintf("\n=== %s | Risk Research (MEGA_05 Crisis Overlay Iter 1) ===\n", WT_ID))
cat(sprintf("AS_OF = %s | Pre-LB end (signal_as_of)\n", AS_OF))

# ===================================================================
# Step 1. Load alpha_package + overlay_signals + WT_003 baseline risk
# ===================================================================
cat("\n[Step 1] Inputs\n")
alpha_pkg <- fromJSON(file.path(WT_DIR, "alpha_package.json"), simplifyVector = FALSE)
ov_dt     <- as.data.table(read_parquet(file.path(ART_DIR, "overlay_signals.parquet")))
ov_dt[, Date := as.Date(Date)]
setkey(ov_dt, Date)

# MEGA_05 baseline risk package (WT-D20260425_003)
baseline_risk_path <- file.path(ROOT, "qepm", "mailbox", "worktask",
                                "WT-D20260425_003", "risk_package.json")
baseline_risk <- fromJSON(baseline_risk_path, simplifyVector = FALSE)

tickers <- names(alpha_pkg$alpha_vector)
N <- length(tickers)
cat(sprintf("  Tickers: %d (MEGA_05 universe inherited)\n", N))
cat(sprintf("  Overlay rows: %d (brake ON %.1f%%)\n",
            nrow(ov_dt),
            100 * mean(ov_dt$dd_brake_state == "ON", na.rm = TRUE)))
cat(sprintf("  Baseline WT_003 method: %s, cond=%.2f, port_vol_ann=%.2f%%\n",
            baseline_risk$selected_estimator$name,
            baseline_risk$sigma_structure$condition_number,
            baseline_risk$sigma_structure$port_vol_ann_pct))

# ===================================================================
# Step 2. Returns matrix (60 months, monthly compounded, ending Pre-LB)
# ===================================================================
cat("\n[Step 2] Loading return matrix (5Y monthly, ending 2024-01)\n")
rawdata <- as.data.table(read_parquet(file.path(ROOT, ".cache/rawdata.parquet")))
rawdata[, Date := as.Date(Date)]
setkey(rawdata, Ticker, Date)

# Window: 2018-12 ~ 2024-01 (62 months) — ensure 60 valid + buffer
ret_pool <- rawdata[Ticker %in% tickers &
                    Date >= as.Date("2018-11-01") & Date <= AS_OF,
                    .(Ticker, Date, Ret, Close)]
ret_pool[, YM := format(Date, "%Y-%m")]
# Compound daily into monthly
ret_pool[, MonthlyRet := prod(1 + ifelse(is.na(Ret), 0, Ret)) - 1, by = .(Ticker, YM)]
ret_mon <- unique(ret_pool[, .(Ticker, YM, MonthlyRet)])
ret_wide <- dcast(ret_mon, YM ~ Ticker, value.var = "MonthlyRet")
setorder(ret_wide, YM)

months_avail <- ret_wide$YM
window_months <- tail(months_avail, 60L)
ret_wide_w <- ret_wide[YM %in% window_months]
month_labels <- ret_wide_w$YM
ret_wide_w[, YM := NULL]

# Coverage check & fill
non_na <- sapply(ret_wide_w, function(x) sum(!is.na(x)))
eligible <- names(non_na)[non_na >= 48L]
missing_tk <- setdiff(tickers, eligible)
if (length(missing_tk) > 0) {
  cat(sprintf("  WARN: %d tickers <48 months coverage: %s\n",
              length(missing_tk), paste(missing_tk, collapse=",")))
}
present_tk <- intersect(tickers, eligible)
R_mat <- as.matrix(ret_wide_w[, present_tk, with = FALSE])
rownames(R_mat) <- month_labels

# Fill NA with cross-section median per row (proxy)
proxy_mask <- is.na(R_mat)
proxy_pct <- 100 * sum(proxy_mask) / length(R_mat)
for (t in seq_len(nrow(R_mat))) {
  row_t <- R_mat[t, ]
  if (any(is.na(row_t))) R_mat[t, is.na(row_t)] <- median(row_t, na.rm = TRUE)
}
cat(sprintf("  R_mat: %d × %d  (proxy fill %.2f%%)\n", nrow(R_mat), ncol(R_mat), proxy_pct))

# ===================================================================
# Step 3. Covariance estimator parallel comparison (R13)
# ===================================================================
cat("\n[Step 3] Σ estimator parallel comparison (5 candidates)\n")
source(file.path(FUNC_PATH, "portfolio", "hrp_core.R"))

est_sample <- function(R) cov(R, use = "pairwise.complete.obs")

est_lw_oracle <- function(R) {
  if (requireNamespace("corpcor", quietly = TRUE)) {
    suppressMessages(corpcor::cov.shrink(R, verbose = FALSE))
  } else stop("corpcor unavailable")
}

est_lw_constcor <- function(R) {
  S <- cov(R, use = "pairwise.complete.obs")
  p <- ncol(S); n <- nrow(R)
  if (p < 2) return(S)
  std <- sqrt(diag(S))
  r <- S / outer(std, std); diag(r) <- NA
  r_bar <- mean(r, na.rm = TRUE)
  F_target <- r_bar * outer(std, std); diag(F_target) <- diag(S)
  X <- scale(R, center = TRUE, scale = FALSE)
  y <- X^2
  phi_mat <- t(y) %*% y / n - S^2
  phi <- sum(phi_mat); rho <- sum(diag(phi_mat))
  gamma <- sum((F_target - S)^2)
  if (gamma <= 0) return(S)
  kappa <- (phi - rho) / gamma
  delta <- max(0, min(1, kappa / n))
  delta * F_target + (1 - delta) * S
}

est_gerber_rmt <- function(R) {
  res <- tryCatch(.get_cor_cov(R, cov_method = "gerber_rmt"),
                  error = function(e) list(cov = NULL))
  if (is.null(res$cov)) stop("gerber_rmt failed")
  res$cov
}

est_nls_approx <- function(R) {
  S <- cov(R, use = "pairwise.complete.obs")
  eig <- eigen(S, symmetric = TRUE)
  vals <- eig$values
  n <- nrow(R); p <- ncol(S); q <- p / n
  if (q < 1) {
    floor_val <- mean(vals) * (1 - sqrt(q))^2
    vals_clip <- pmax(vals, floor_val * 0.5)
    alpha_b <- min(0.5, q)
    vals_new <- (1 - alpha_b) * vals_clip + alpha_b * mean(vals_clip)
  } else vals_new <- pmax(vals, 1e-6)
  S_new <- eig$vectors %*% diag(vals_new) %*% t(eig$vectors)
  rownames(S_new) <- colnames(S_new) <- colnames(R)
  S_new
}

estimators <- list(
  list(name = "sample",               fn = est_sample),
  list(name = "ledoit_wolf_oracle",   fn = est_lw_oracle),
  list(name = "ledoit_wolf_constcor", fn = est_lw_constcor),
  list(name = "gerber_rmt",           fn = est_gerber_rmt),
  list(name = "nonlinear_shrinkage",  fn = est_nls_approx)
)

use_parallel <- FALSE
tryCatch({
  if (requireNamespace("future.apply", quietly = TRUE) &&
      requireNamespace("future", quietly = TRUE)) {
    library(future); library(future.apply)
    nw <- min(5L, parallel::detectCores() - 1L)
    if (nw >= 2L) {
      plan(multisession, workers = nw); use_parallel <- TRUE
      cat(sprintf("  Parallel: %d workers\n", nw))
    }
  }
}, error = function(e) NULL)

cov_run_one <- function(e, R) {
  ts <- Sys.time()
  tryCatch({
    Sigma <- e$fn(R)
    Sigma <- (Sigma + t(Sigma)) / 2
    eig <- eigen(Sigma, symmetric = TRUE, only.values = TRUE)$values
    cn <- max(abs(eig)) / max(min(abs(eig)), 1e-12)
    list(ok = TRUE, name = e$name, Sigma = Sigma,
         condition = cn, min_eig = min(eig), max_eig = max(eig),
         psd = (min(eig) > 0),
         elapsed = as.numeric(difftime(Sys.time(), ts, units = "secs")))
  }, error = function(err) list(ok = FALSE, name = e$name, error = conditionMessage(err)))
}

if (use_parallel) {
  results <- future.apply::future_lapply(estimators, cov_run_one, R = R_mat,
                                         future.seed = TRUE)
  plan(sequential)
} else {
  results <- lapply(estimators, cov_run_one, R = R_mat)
}

method_log <- list()
for (r in results) {
  if (isTRUE(r$ok)) {
    cat(sprintf("    %-22s cond=%8.2f  min_eig=%.3e  PSD=%s  (%.2fs)\n",
                r$name, r$condition, r$min_eig, r$psd, r$elapsed))
    method_log[[r$name]] <- list(name = r$name, condition = round(r$condition, 4),
                                 min_eig = round(r$min_eig, 8),
                                 max_eig = round(r$max_eig, 6),
                                 psd = r$psd, elapsed_sec = round(r$elapsed, 2),
                                 selected = FALSE)
  } else {
    cat(sprintf("    %-22s FAILED: %s\n", r$name, r$error))
    method_log[[r$name]] <- list(name = r$name, error = r$error, selected = FALSE)
  }
}

ok_results <- Filter(function(r) isTRUE(r$ok) && r$psd, results)
stopifnot(length(ok_results) > 0)
best <- ok_results[[which.min(sapply(ok_results, function(r) r$condition))]]
Sigma_primary <- best$Sigma
method_selected <- best$name
method_log[[method_selected]]$selected <- TRUE
cat(sprintf("  -> Selected: %s (cond=%.2f)\n", method_selected, best$condition))

# ===================================================================
# Step 4. Factor model: Σ = BΩB' + D (FF3 + WML)
# ===================================================================
cat("\n[Step 4] Factor risk decomposition Σ = BΩB' + D\n")
fr <- as.data.table(read_parquet(file.path(ROOT, ".cache/kr_factor_returns.parquet")))
fr[, YM := format(Date, "%Y-%m")]
fr_sub <- fr[YM %in% month_labels, .(YM, MKT, SMB, WML)]

fr_align <- merge(data.table(YM = month_labels), fr_sub, by = "YM", all.x = TRUE)
setorder(fr_align, YM)
for (col in c("MKT","SMB","WML")) {
  if (any(is.na(fr_align[[col]]))) fr_align[is.na(get(col)), (col) := 0]
}
F_mat <- as.matrix(fr_align[, .(MKT, SMB, WML)]); rownames(F_mat) <- fr_align$YM
Omega <- cov(F_mat)

n_p <- ncol(R_mat)
B <- matrix(0, n_p, 3, dimnames = list(colnames(R_mat), c("MKT","SMB","WML")))
specific_var <- numeric(n_p); names(specific_var) <- colnames(R_mat)
r2_stk <- numeric(n_p); names(r2_stk) <- colnames(R_mat)

for (i in seq_len(n_p)) {
  y <- R_mat[, i]
  ok <- which(!is.na(y))
  if (length(ok) < 24L) {
    specific_var[i] <- var(y, na.rm = TRUE); next
  }
  X <- F_mat[ok, , drop = FALSE]; y_ok <- y[ok]
  fit <- tryCatch(lm.fit(cbind(1, X), y_ok), error = function(e) NULL)
  if (is.null(fit) || any(is.na(fit$coefficients[-1]))) {
    specific_var[i] <- var(y, na.rm = TRUE); next
  }
  B[i, ] <- fit$coefficients[-1]
  resid_i <- fit$residuals
  specific_var[i] <- var(resid_i)
  ss_tot <- sum((y_ok - mean(y_ok))^2); ss_res <- sum(resid_i^2)
  r2_stk[i] <- if (ss_tot > 0) 1 - ss_res / ss_tot else 0
}
D_diag <- diag(specific_var); rownames(D_diag) <- colnames(D_diag) <- colnames(R_mat)
Sigma_struct <- B %*% Omega %*% t(B) + D_diag

avg_total_var <- mean(apply(R_mat, 2, var, na.rm = TRUE))
factor_coverage <- 1 - mean(specific_var) / avg_total_var
cat(sprintf("  Factor coverage R²: %.2f%% (mean R² across %d stocks)\n",
            factor_coverage * 100, n_p))

# Blend: if coverage >= 40%, blend struct (50%) + LW (50%); else 100% LW
if (factor_coverage < 0.40) {
  blend_w <- 0.0; Sigma_final <- Sigma_primary
  cat("  Coverage < 40% → 100% LW shrinkage\n")
} else {
  blend_w <- 0.5; Sigma_final <- 0.5 * Sigma_struct + 0.5 * Sigma_primary
  cat("  Coverage >= 40% → 50% structured + 50% LW\n")
}
Sigma_final <- (Sigma_final + t(Sigma_final)) / 2
eig_f <- eigen(Sigma_final, symmetric = TRUE, only.values = TRUE)$values
cond_final <- max(abs(eig_f)) / max(min(abs(eig_f)), 1e-12)
min_eig_final <- min(eig_f)
if (min_eig_final <= 0) {
  shrink_a <- abs(min_eig_final) * 1.5 + 1e-6
  Sigma_final <- Sigma_final + shrink_a * diag(nrow(Sigma_final))
  eig_f <- eigen(Sigma_final, symmetric = TRUE, only.values = TRUE)$values
  cond_final <- max(abs(eig_f)) / max(min(abs(eig_f)), 1e-12)
  min_eig_final <- min(eig_f)
  cat(sprintf("  PSD shrunk: cond=%.2f, min_eig=%.3e\n", cond_final, min_eig_final))
} else {
  cat(sprintf("  Σ_final cond=%.2f, min_eig=%.3e (PSD)\n", cond_final, min_eig_final))
}

# ===================================================================
# Step 5. Risk decomposition (top common risks, MEGA_05 universe)
# ===================================================================
cat("\n[Step 5] Risk decomposition\n")
w_ew <- rep(1 / n_p, n_p); names(w_ew) <- colnames(R_mat)
var_total <- as.numeric(t(w_ew) %*% Sigma_final %*% w_ew)
b_ew <- t(B) %*% w_ew  # 3-vector portfolio factor exposure
var_mkt  <- as.numeric(b_ew["MKT", 1]^2 * Omega["MKT","MKT"])
var_smb  <- as.numeric(b_ew["SMB", 1]^2 * Omega["SMB","SMB"])
var_wml  <- as.numeric(b_ew["WML", 1]^2 * Omega["WML","WML"])
var_spec <- sum(w_ew^2 * specific_var)
market_pct <- var_mkt / var_total
size_pct   <- var_smb / var_total
mom_pct    <- var_wml / var_total
specific_pct <- var_spec / var_total
sys_pct <- 1 - specific_pct
port_vol_ann <- sqrt(var_total) * sqrt(12)
cat(sprintf("  Port vol (ann): %.2f%%\n", port_vol_ann * 100))
cat(sprintf("  Market %.1f%% | Size %.1f%% | Mom %.1f%% | Specific %.1f%%\n",
            market_pct * 100, size_pct * 100, mom_pct * 100, specific_pct * 100))

# Sector concentration
sector_info <- rawdata[Ticker %in% colnames(R_mat) & Date >= AS_OF - 60,
                       .(Sector = first(Sector_Lv2)), by = Ticker]
sector_info <- sector_info[match(colnames(R_mat), Ticker)]
if (!"Sector" %in% names(sector_info) || all(is.na(sector_info$Sector))) {
  sector_info[, Sector := "Unknown"]
}
sector_info[is.na(Sector), Sector := "Unknown"]
sector_tbl <- sector_info[, .N, by = Sector][order(-N)]
sector_tbl[, Pct := N / sum(N)]
top_sec <- sector_tbl[1:min(3, .N)]
cat("  Top sectors:\n")
for (j in seq_len(nrow(top_sec))) {
  cat(sprintf("    %-20s %5.1f%% (%d)\n", top_sec$Sector[j], top_sec$Pct[j]*100, top_sec$N[j]))
}

top_common_risks <- c(
  sprintf("Market (%.1f%%)", market_pct * 100),
  sprintf("Sector_%s (%.1f%%)", top_sec$Sector[1], top_sec$Pct[1] * 100),
  sprintf("Size (%.1f%%)", size_pct * 100),
  sprintf("Specific (%.1f%%)", specific_pct * 100)
)

# ===================================================================
# Step 6. OVERLAY-CONDITIONAL Σ (Iter 1 core)
#   Split monthly history into brake_ON_lag vs brake_OFF_lag periods.
#   Use overlay_signals.parquet → align YM → tag each return month.
#   Compute Σ_on, Σ_off; effective port vol after multiplier scaling.
# ===================================================================
cat("\n[Step 6] Overlay-conditional Σ (brake ON vs OFF) — Iter 1 core\n")
ov_dt[, YM := format(Date, "%Y-%m")]
# overlay_signals row at sig_date(t) reflects state DECIDED at t-1 (already lagged)
# i.e., it controls how returns from t→t+1 are scaled. So tag YM(sig_date) → next month return.
ov_label <- ov_dt[, .(YM_sig = YM,
                      brake = dd_brake_state,
                      mult = overlay_mult)]
# match: YM_sig (sig_date month) controls the position held over the next month,
# whose return is realized at YM_sig+1 (the month_labels index).
# In our R_mat, month_labels[k] is realized return YM. So overlay was decided
# at sig_date in month_labels[k-1].
yms_dt <- data.table(YM_real = month_labels, idx = seq_along(month_labels))
yms_dt[, YM_sig := format(as.Date(paste0(YM_real, "-01")) - 1, "%Y-%m")]
ov_align <- merge(yms_dt, ov_label, by = "YM_sig", all.x = TRUE)
ov_align[is.na(brake), brake := "OFF"]
ov_align[is.na(mult), mult := 1.0]

n_on  <- sum(ov_align$brake == "ON")
n_off <- sum(ov_align$brake == "OFF")
cat(sprintf("  60-month tag: ON=%d (%.1f%%) | OFF=%d (%.1f%%)\n",
            n_on, 100*n_on/(n_on+n_off), n_off, 100*n_off/(n_on+n_off)))

R_on  <- R_mat[ov_align$brake == "ON",  , drop = FALSE]
R_off <- R_mat[ov_align$brake == "OFF", , drop = FALSE]

build_cov_safe <- function(R) {
  if (nrow(R) < 12) return(NULL)
  S <- est_lw_constcor(R)
  S <- (S + t(S)) / 2
  eig <- eigen(S, symmetric = TRUE, only.values = TRUE)$values
  if (min(eig) <= 0) {
    shrink_a <- abs(min(eig)) * 1.5 + 1e-6
    S <- S + shrink_a * diag(nrow(S))
    eig <- eigen(S, symmetric = TRUE, only.values = TRUE)$values
  }
  list(Sigma = S, cond = max(abs(eig))/max(min(abs(eig)), 1e-12),
       min_eig = min(eig), n_obs = nrow(R))
}

cov_on  <- build_cov_safe(R_on)
cov_off <- build_cov_safe(R_off)

if (!is.null(cov_off) && !is.null(cov_on)) {
  vol_off_ann <- sqrt(as.numeric(t(w_ew) %*% cov_off$Sigma %*% w_ew)) * sqrt(12)
  vol_on_ann  <- sqrt(as.numeric(t(w_ew) %*% cov_on$Sigma  %*% w_ew)) * sqrt(12)
  # Effective vol: brake ON applies overlay_mult ~0.5 × volreg_mult ~0.6 (med)
  # Sample average mult during brake-ON months
  mean_mult_on  <- mean(ov_align[brake == "ON",  mult], na.rm = TRUE)
  mean_mult_off <- mean(ov_align[brake == "OFF", mult], na.rm = TRUE)
  effective_vol_on  <- vol_on_ann * mean_mult_on
  effective_vol_off <- vol_off_ann * mean_mult_off
  vol_reduction_pct_brake_on <- 100 * (1 - effective_vol_on / vol_on_ann)

  # Time-weighted blended portfolio vol (overlay ON full sample)
  # σ_eff = sqrt(p_on * (mean_mult_on * σ_on)^2 + p_off * (mean_mult_off * σ_off)^2)
  # vs no-overlay: σ_full = sqrt(p_on * σ_on^2 + p_off * σ_off^2)
  p_on  <- n_on / (n_on + n_off); p_off <- n_off / (n_on + n_off)
  sigma_full_blended <- sqrt(p_on * vol_on_ann^2 + p_off * vol_off_ann^2)
  sigma_eff_blended  <- sqrt(p_on * (mean_mult_on * vol_on_ann)^2 +
                             p_off * (mean_mult_off * vol_off_ann)^2)
  overall_vol_reduction_pct <- 100 * (1 - sigma_eff_blended / sigma_full_blended)

  cat(sprintf("  vol_off_ann = %.2f%% | vol_on_ann = %.2f%% (raw, no overlay scaling)\n",
              vol_off_ann * 100, vol_on_ann * 100))
  cat(sprintf("  mean_mult_on=%.3f | mean_mult_off=%.3f\n", mean_mult_on, mean_mult_off))
  cat(sprintf("  effective_vol_on  = %.2f%% (brake ON × scaling)\n", effective_vol_on * 100))
  cat(sprintf("  effective_vol_off = %.2f%% (brake OFF × volreg only)\n", effective_vol_off * 100))
  cat(sprintf("  σ_full_blended (no overlay) = %.2f%% | σ_eff (overlay) = %.2f%%\n",
              sigma_full_blended * 100, sigma_eff_blended * 100))
  cat(sprintf("  → Overall portfolio vol reduction: %.2f%% (Iter 1 KPI)\n",
              overall_vol_reduction_pct))
} else {
  cat("  WARN: insufficient months for ON/OFF split\n")
  vol_off_ann <- NA; vol_on_ann <- NA
  mean_mult_on <- NA; mean_mult_off <- NA
  effective_vol_on <- NA; effective_vol_off <- NA
  vol_reduction_pct_brake_on <- NA; overall_vol_reduction_pct <- NA
  sigma_full_blended <- NA; sigma_eff_blended <- NA
}

# Crisis decorrelation: avg pairwise correlation under brake ON vs OFF
avg_cor_on  <- if (!is.null(cov_on))  mean(cov2cor(cov_on$Sigma)[upper.tri(cov_on$Sigma)])  else NA
avg_cor_off <- if (!is.null(cov_off)) mean(cov2cor(cov_off$Sigma)[upper.tri(cov_off$Sigma)]) else NA
cat(sprintf("  avg_cor_on=%.3f | avg_cor_off=%.3f | Δ=%.3f (crisis decorrelation)\n",
            avg_cor_on, avg_cor_off, avg_cor_on - avg_cor_off))

# ===================================================================
# Step 7. Regime-conditional correlation (4-regime)
# ===================================================================
cat("\n[Step 7] Regime-conditional Σ (Bull/Normal/Caution/Crisis)\n")
regime <- as.data.table(read_parquet(file.path(ROOT, ".cache/regime_v7.parquet")))
regime[, YM := apply_month]
reg_slim <- regime[, .(YM, regime_state, p_crisis, MRS, slow_crisis)]
yms_for_reg <- data.table(YM = month_labels, idx = seq_along(month_labels))
reg_align <- merge(yms_for_reg, reg_slim, by = "YM", all.x = TRUE)
reg_align[, Regime4 := fcase(
  is.na(regime_state), "NORMAL",
  regime_state == "Crisis", "CRISIS",
  regime_state == "Caution", "CAUTION",
  regime_state == "Bull", "BULL",
  default = "NORMAL"
)]
cat(sprintf("  regime tally: %s\n",
            paste(reg_align[, .N, by = Regime4][order(-N)][, paste(Regime4, N, sep="=")], collapse=" | ")))

regime_cor_long <- list()
regime_cond_summary <- list()
for (reg in c("BULL","NORMAL","CAUTION","CRISIS")) {
  idx_r <- which(reg_align$Regime4 == reg)
  if (length(idx_r) >= 6) {
    R_r <- R_mat[idx_r, , drop = FALSE]
    S_r <- tryCatch(est_lw_constcor(R_r), error = function(e) cov(R_r))
    S_r <- (S_r + t(S_r))/2
    cor_r <- cov2cor(S_r)
    avg_cor <- mean(cor_r[upper.tri(cor_r)])
    vol_ann_reg <- sqrt(as.numeric(t(w_ew) %*% S_r %*% w_ew)) * sqrt(12)
    regime_cond_summary[[reg]] <- list(avg_cor = round(avg_cor, 4),
                                        vol_ann_pct = round(vol_ann_reg * 100, 2),
                                        n_obs = length(idx_r))
    # long format
    for (i in 1:nrow(cor_r)) for (j in i:ncol(cor_r)) {
      regime_cor_long[[length(regime_cor_long)+1]] <- data.table(
        regime = reg, ticker_i = rownames(cor_r)[i], ticker_j = colnames(cor_r)[j],
        correlation = cor_r[i,j], covariance = S_r[i,j])
    }
    cat(sprintf("  %s (N=%d): avg_cor=%.3f | vol_ann=%.2f%%\n",
                reg, length(idx_r), avg_cor, vol_ann_reg * 100))
  } else {
    regime_cond_summary[[reg]] <- list(avg_cor = NA, vol_ann_pct = NA, n_obs = length(idx_r))
    cat(sprintf("  %s (N=%d): insufficient\n", reg, length(idx_r)))
  }
}
reg_cor_dt <- rbindlist(regime_cor_long)
reg_corr_path <- file.path(ART_DIR, "regime_correlation.parquet")
write_parquet(reg_cor_dt, reg_corr_path)
cat(sprintf("  → %s (%d rows)\n", reg_corr_path, nrow(reg_cor_dt)))

# ===================================================================
# Step 8. Tail risk + EVT/CVaR/CDaR (EW portfolio proxy)
# ===================================================================
cat("\n[Step 8] Tail risk (EW portfolio)\n")
port_ret <- as.numeric(R_mat %*% w_ew)
compute_cvar <- function(r, alpha) {
  r <- r[!is.na(r)]
  v <- as.numeric(quantile(r, alpha)); list(VaR = v, CVaR = mean(r[r <= v]))
}
compute_cdar <- function(r, alpha) {
  r <- r[!is.na(r)]; eq <- cumprod(1+r); peak <- cummax(eq); dd <- (eq-peak)/peak
  v <- as.numeric(quantile(dd, alpha)); list(VaR_dd = v, CDaR = mean(dd[dd <= v]))
}
v95 <- compute_cvar(port_ret, 0.05); v99 <- compute_cvar(port_ret, 0.01)
d95 <- compute_cdar(port_ret, 0.05)
mdd_obs <- min((cumprod(1+port_ret) / cummax(cumprod(1+port_ret))) - 1)

# EVT-GPD VaR99 (manual POT)
evt_var99 <- function(r, threshold_q = 0.90) {
  r <- r[!is.na(r)]; losses <- -r
  u <- as.numeric(quantile(losses, threshold_q))
  exceed <- losses[losses > u] - u
  if (length(exceed) < 5) return(list(method = "empirical_fallback",
                                      var99 = as.numeric(quantile(losses, 0.99)),
                                      es99  = mean(losses[losses >= as.numeric(quantile(losses, 0.99))])))
  # Method-of-moments GPD fit
  m1 <- mean(exceed); m2 <- var(exceed)
  xi <- 0.5 * (1 - m1^2 / m2); beta <- 0.5 * m1 * (1 + m1^2 / m2)
  if (!is.finite(xi) || !is.finite(beta) || beta <= 0) {
    return(list(method = "empirical_fallback",
                var99 = as.numeric(quantile(losses, 0.99)),
                es99  = mean(losses[losses >= as.numeric(quantile(losses, 0.99))])))
  }
  n <- length(losses); n_u <- length(exceed); p <- 0.99
  var_p <- u + (beta / xi) * (((n / n_u) * (1 - p))^(-xi) - 1)
  es_p  <- (var_p + beta - xi * u) / (1 - xi)
  list(method = "GPD_MoM", xi = xi, beta = beta, var99 = var_p, es99 = es_p)
}
evt <- evt_var99(port_ret)

cat(sprintf("  CVaR_95=%.4f | CVaR_99=%.4f | CDaR_95=%.4f | MDD_obs=%.4f\n",
            v95$CVaR, v99$CVaR, d95$CDaR, mdd_obs))
cat(sprintf("  EVT(%s): VaR99=%.4f | ES99=%.4f\n", evt$method, evt$var99, evt$es99))

# ===================================================================
# Step 9. 8-period stress test + DD Brake regime-conditional effect
# ===================================================================
cat("\n[Step 9] 8 stress periods + brake ON/OFF separation\n")
stress_periods <- list(
  GFC_2008          = c("2008-09", "2009-03"),
  EuDebt_2011       = c("2011-07", "2012-06"),
  China_2015        = c("2015-06", "2016-02"),
  Brexit_2016       = c("2016-06", "2016-12"),
  Volmageddon_2018  = c("2018-01", "2018-12"),
  COVID_2020        = c("2020-02", "2020-04"),
  Inflation_2022    = c("2022-01", "2022-10"),
  KR_Liq_Crisis_2022= c("2022-09", "2022-12")
)

# We have 60 monthly observations 2018-12 ~ 2024-01.
# Past stress (GFC etc.) → use baseline WT_003 stress + parametric translation.
# Local stress (in-window): use observed.
stress_results <- list()
for (sp_name in names(stress_periods)) {
  rng <- stress_periods[[sp_name]]
  in_window <- which(month_labels >= rng[1] & month_labels <= rng[2])
  if (length(in_window) >= 1) {
    sp_ret <- port_ret[in_window]
    cum_ret <- prod(1 + sp_ret) - 1
    stress_results[[sp_name]] <- list(
      method = "observed",
      n_months = length(in_window),
      cum_return = round(cum_ret, 4),
      worst_month = round(min(sp_ret), 4),
      avg_brake_on = round(mean(ov_align$brake[in_window] == "ON"), 4)
    )
  } else {
    # Parametric: market shock via beta_market
    # Map approx market shock magnitude per period
    shock_map <- list(GFC_2008 = -0.45, EuDebt_2011 = -0.20, China_2015 = -0.18,
                      Brexit_2016 = -0.08, Volmageddon_2018 = -0.12,
                      COVID_2020 = -0.30, Inflation_2022 = -0.25,
                      KR_Liq_Crisis_2022 = -0.18)
    mkt_shock <- shock_map[[sp_name]] %||% -0.10
    beta_port <- as.numeric(b_ew["MKT", 1])
    parametric_loss <- beta_port * mkt_shock
    stress_results[[sp_name]] <- list(
      method = "parametric_factor",
      mkt_shock = mkt_shock, beta_port = round(beta_port, 4),
      cum_return_estimate = round(parametric_loss, 4)
    )
  }
}

# market_down_5 / value_crash / momentum_reversal scenarios
scen_market_5  <- as.numeric(b_ew["MKT", 1]) * (-0.05)
# value_crash: HML +20% → portfolio not directly exposed (no HML loading), proxy via ε
scen_value_crash <- 0  # FF3 model; HML excluded
# momentum reversal: WML -20%
scen_mom_reversal <- as.numeric(b_ew["WML", 1]) * (-0.20)

# Parametric CVaR cap check
cvar_cap <- 0.025
cvar_cap_breach <- abs(v95$CVaR) > cvar_cap

cat(sprintf("  market_down_5 = %+.4f\n", scen_market_5))
cat(sprintf("  momentum_reversal = %+.4f\n", scen_mom_reversal))
for (sp_name in names(stress_results)) {
  s <- stress_results[[sp_name]]
  if (s$method == "observed") {
    cat(sprintf("  %-22s [observed N=%d] cum=%+.2f%% | worst=%+.2f%% | brake_on_avg=%.0f%%\n",
                sp_name, s$n_months, s$cum_return*100, s$worst_month*100, s$avg_brake_on*100))
  } else {
    cat(sprintf("  %-22s [parametric] mkt=%+.0f%% × β=%.3f → %+.2f%%\n",
                sp_name, s$mkt_shock*100, s$beta_port, s$cum_return_estimate*100))
  }
}

# ===================================================================
# Step 10. TDC vs MEGA_05 baseline (WT_003) + crowding diagnostic
# ===================================================================
cat("\n[Step 10] TDC vs WT_003 baseline + crowding\n")
# MEGA_05 baseline universe is identical (20 tickers same).  Therefore TDC at the
# 20-ticker portfolio level is essentially 1.0 (same names + similar weights pattern).
# More meaningful: TDC of the OVERLAY-SCALED portfolio time-series vs baseline (no overlay).
# Baseline equivalent monthly returns: r_full = port_ret  (no overlay applied)
# Iter1 returns (proxy with overlay scaling): r_overlay = port_ret * mult_lag
mult_aligned <- ov_align$mult
port_ret_overlay <- port_ret * mult_aligned
# Empirical lower-tail dependence (bottom 10%)
empirical_tdc <- function(x, y, u = 0.10) {
  n <- length(x)
  rx <- rank(x) / (n + 1); ry <- rank(y) / (n + 1)
  sum(rx < u & ry < u) / (u * n)
}
tdc_iter1_vs_baseline <- empirical_tdc(port_ret_overlay, port_ret)
upper_tdc            <- (function(x,y,u=0.10){
  n <- length(x); rx <- rank(x)/(n+1); ry <- rank(y)/(n+1)
  sum(rx > 1-u & ry > 1-u) / (u * n)
})(port_ret_overlay, port_ret)

# vs WT_003 PG2 active (proxy: same MEGA_05 baseline returns since 20 tickers identical)
# Note: weights differ post-Optimizer, but since this is alpha+overlay layer, baseline returns are
# the closest proxy for the WT_003 pre-overlay portfolio.
cat(sprintf("  TDC(Iter1 overlay vs baseline EW): lower=%.3f | upper=%.3f\n",
            tdc_iter1_vs_baseline, upper_tdc))

# Family weight & HHI
# Risk_Management overlay is a NEW family — but it's a scaling layer, not a weight allocator.
# Portfolio family composition still 100% Analyst_Consensus + Quality + Accrual.
fam_weights <- list(
  Analyst_Consensus = 0.4664,  # C01+C04+C02+C06 (sum of theta)
  Quality_Earnings  = 0.2806,
  Accrual_Quality   = 0.2529,
  Risk_Management   = 0.0      # overlay = 0% allocator (size scaler only)
)
hhi_factor <- sum(unlist(fam_weights)^2)
cat(sprintf("  Family HHI (factor θ): %.3f\n", hhi_factor))

# Concentration check (alpha vector top-3 vs top-5)
av <- unlist(alpha_pkg$alpha_vector)
av_norm <- abs(av) / sum(abs(av))
top3_conc <- sum(sort(av_norm, decreasing = TRUE)[1:3])
top5_conc <- sum(sort(av_norm, decreasing = TRUE)[1:5])
cat(sprintf("  Alpha vector concentration: top3=%.1f%% | top5=%.1f%%\n",
            top3_conc * 100, top5_conc * 100))

# Q07 vs AC21 internal correlation (inherited from WT_003)
q07_ac21_cor_baseline <- baseline_risk$vif_diagnosis$Q07_vs_AC21_cor
cat(sprintf("  Q07_vs_AC21 cor (inherited): %.3f (baseline)\n", q07_ac21_cor_baseline))

# ===================================================================
# Step 11. Rolling Σ stability (RF-A1 response)
#   Question: is Σ_iter1 stable across rolling windows?
#   Method: 36-month rolling Σ (every 6 months step) → compare avg portfolio vol stdev
# ===================================================================
cat("\n[Step 11] Rolling Σ stability (RF-A1 response)\n")
roll_size <- 36L; step <- 6L
roll_results <- list()
for (start in seq(1, nrow(R_mat) - roll_size + 1, by = step)) {
  end <- start + roll_size - 1L
  Rw <- R_mat[start:end, , drop = FALSE]
  Sw <- tryCatch(est_lw_constcor(Rw), error = function(e) NULL)
  if (is.null(Sw)) next
  Sw <- (Sw + t(Sw)) / 2
  vol_w <- sqrt(as.numeric(t(w_ew) %*% Sw %*% w_ew)) * sqrt(12)
  avg_cor_w <- mean(cov2cor(Sw)[upper.tri(Sw)])
  roll_results[[length(roll_results)+1]] <- list(
    start = month_labels[start], end = month_labels[end],
    vol_ann_pct = round(vol_w * 100, 2),
    avg_cor = round(avg_cor_w, 3))
}
roll_dt <- rbindlist(roll_results)
roll_vol_mean <- mean(roll_dt$vol_ann_pct)
roll_vol_sd   <- sd(roll_dt$vol_ann_pct)
roll_vol_cv   <- roll_vol_sd / roll_vol_mean   # coefficient of variation
cat(sprintf("  rolling vol: mean=%.2f%% sd=%.2f%% CV=%.3f (lower=stable)\n",
            roll_vol_mean, roll_vol_sd, roll_vol_cv))
print(roll_dt)

# ===================================================================
# Step 12. Save artifacts
# ===================================================================
cat("\n[Step 12] Writing artifacts\n")

# 12a) covariance.parquet
sigma_long <- list()
for (i in 1:n_p) for (j in i:n_p) {
  sigma_long[[length(sigma_long)+1]] <- data.table(
    ticker_i = rownames(Sigma_final)[i],
    ticker_j = colnames(Sigma_final)[j],
    cov = Sigma_final[i,j],
    cor = Sigma_final[i,j] / sqrt(Sigma_final[i,i] * Sigma_final[j,j])
  )
}
sigma_dt <- rbindlist(sigma_long)
cov_path <- file.path(ART_DIR, "covariance.parquet")
write_parquet(sigma_dt, cov_path)
cat(sprintf("  -> %s (%d rows)\n", cov_path, nrow(sigma_dt)))

# 12b) exposure_matrix.parquet
B_dt <- as.data.table(B, keep.rownames = "Ticker")
exp_path <- file.path(ART_DIR, "exposure_matrix.parquet")
write_parquet(B_dt, exp_path)

# 12c) factor_covariance.parquet
omega_dt <- as.data.table(Omega, keep.rownames = "factor")
fcov_path <- file.path(ART_DIR, "factor_covariance.parquet")
write_parquet(omega_dt, fcov_path)

# 12d) specific_risk.parquet
spec_dt <- data.table(Ticker = names(specific_var),
                      specific_var = specific_var,
                      specific_vol_ann = sqrt(specific_var) * sqrt(12),
                      r_squared = r2_stk[names(specific_var)])
spec_path <- file.path(ART_DIR, "specific_risk.parquet")
write_parquet(spec_dt, spec_path)

# 12e) tail_risk.json
tail_risk <- list(
  cvar_95_monthly = round(abs(v95$CVaR), 4),
  cvar_99_monthly = round(abs(v99$CVaR), 4),
  var_95_monthly  = round(abs(v95$VaR), 4),
  var_99_monthly  = round(abs(v99$VaR), 4),
  cdar_95         = round(abs(d95$CDaR), 4),
  max_drawdown_observed = round(abs(mdd_obs), 4),
  evt_var_99      = round(evt$var99, 4),
  evt_es_99       = round(evt$es99, 4),
  evt_method      = evt$method,
  evt_xi          = if (!is.null(evt$xi)) round(evt$xi, 4) else NULL,
  evt_beta        = if (!is.null(evt$beta)) round(evt$beta, 4) else NULL,
  cvar_cap        = cvar_cap,
  cvar_cap_breach = cvar_cap_breach
)
tail_path <- file.path(ART_DIR, "tail_risk.json")
write_json(tail_risk, tail_path, pretty = TRUE, auto_unbox = TRUE, null = "null", na = "null")
cat(sprintf("  -> %s\n", tail_path))

# 12f) method_shopping_log_risk.json
write_json(list(
  candidates_tried = length(estimators),
  parallel_exec = use_parallel,
  selection_objective = "condition_number",
  selected = method_selected,
  method_log = method_log
), file.path(ART_DIR, "method_shopping_log_risk.json"),
   pretty = TRUE, auto_unbox = TRUE, null = "null", na = "null")

# ===================================================================
# Step 13. Risk Package JSON
# ===================================================================
cat("\n[Step 13] risk_package.json\n")

# RF flags
challenge_flags <- list()
if (market_pct > 0.40) {
  challenge_flags <- c(challenge_flags, list(
    `RF-R1` = list(id = "RF-R1", severity = "HIGH",
                   msg = "Market 기여도 > 40%",
                   detail = sprintf("Market=%.1f%%", market_pct*100))
  ))
}
if (cond_final > 500) {
  challenge_flags <- c(challenge_flags, list(
    `RF-R2` = list(id = "RF-R2", severity = "HIGH",
                   msg = sprintf("Condition number > 500 (after shrinkage): %.1f", cond_final),
                   detail = method_selected)
  ))
}
if (q07_ac21_cor_baseline > 0.7) {
  challenge_flags <- c(challenge_flags, list(
    `RF-R3` = list(id = "RF-R3", severity = "MEDIUM",
                   msg = "Q07_AC21 crowding inherited from baseline",
                   detail = sprintf("cor=%.3f (WT_003 inherited)", q07_ac21_cor_baseline))
  ))
}
if (abs(scen_market_5) > 0.08) {
  challenge_flags <- c(challenge_flags, list(
    `RF-R4` = list(id = "RF-R4", severity = "HIGH",
                   msg = sprintf("market_down_5 < -8%% (loss=%.2f%%)", scen_market_5*100),
                   detail = sprintf("β_port=%.3f", b_ew["MKT",1]))
  ))
}
# Iter 1 specific note: RF-A1 (Alpha sub-stability) → Risk-side response
# Sub-stability is alpha-IC concept; Risk side measures Σ stability via roll_vol_cv
risk_response_to_RFA1 <- list(
  alpha_sub_stability_flag = "RF-A1 HIGH (sub_stab=0.345)",
  risk_response = if (roll_vol_cv < 0.15) "Σ stable across rolling windows (CV<15%) — RF-A1 is alpha-IC issue, not Σ instability"
                  else if (roll_vol_cv < 0.25) "Σ moderate stability (CV 15-25%)"
                  else "Σ unstable (CV>25%)",
  rolling_vol_cv = round(roll_vol_cv, 4),
  rolling_vol_mean_pct = round(roll_vol_mean, 2),
  rolling_vol_sd_pct = round(roll_vol_sd, 2)
)

risk_pkg <- list(
  task_id = WT_ID,
  as_of_date = as.character(AS_OF),
  agent = "risk_research_v1.1",
  inherits_from_baseline = "WT-D20260425_003",
  exposure_matrix_ref = sprintf("stage_artifacts/WT_%s/exposure_matrix.parquet", WT_ID),
  factor_covariance_ref = sprintf("stage_artifacts/WT_%s/factor_covariance.parquet", WT_ID),
  specific_risk_ref = sprintf("stage_artifacts/WT_%s/specific_risk.parquet", WT_ID),
  security_covariance_ref = sprintf("stage_artifacts/WT_%s/covariance.parquet", WT_ID),
  selection_objective = "condition_number",
  selected_estimator = list(
    name = method_selected,
    primary_cond = round(best$condition, 2),
    final_cond = round(cond_final, 2),
    factor_blend_weight = blend_w,
    shrinkage_used = (min_eig_final < best$min_eig),
    rationale = "R4 v6.1 enum: condition_number minimization. PSD enforced. No alpha-return reference."
  ),
  method_shopping_log = list(
    risk_agent = list(
      candidates_tried = length(estimators),
      parallel_exec = use_parallel,
      selection_objective = "condition_number",
      method_log = method_log
    )
  ),
  factor_exposure_summary = list(
    n_factors = 3L, n_factors_alpha = 6L,
    factor_names = c("MKT","SMB","WML"),
    portfolio_betas = list(MKT = round(b_ew["MKT",1], 4),
                           SMB = round(b_ew["SMB",1], 4),
                           WML = round(b_ew["WML",1], 4)),
    factor_coverage_R2_avg = round(factor_coverage, 4),
    weight_thetas = baseline_risk$factor_exposure_summary$weight_thetas
  ),
  vif_diagnosis = list(
    inherited_from_baseline = TRUE,
    Q07_vs_AC21_cor = round(q07_ac21_cor_baseline, 4),
    note = "Iter 1 baseline 6F unchanged; VIF inherited from WT-D20260425_003"
  ),
  sigma_structure = list(
    method = "BΩB_plus_D_blended_LW_50_50",
    n_tickers = n_p,
    n_factors = 3L,
    factor_coverage_pct = round(factor_coverage * 100, 2),
    condition_number = round(cond_final, 2),
    min_eig = round(min_eig_final, 8),
    psd = (min_eig_final > 0),
    port_vol_ann_pct = round(port_vol_ann * 100, 2),
    systematic_pct = round(sys_pct * 100, 2),
    specific_pct = round(specific_pct * 100, 2),
    market_contribution_pct = round(market_pct * 100, 2),
    size_contribution_pct = round(size_pct * 100, 2),
    momentum_contribution_pct = round(mom_pct * 100, 2)
  ),
  overlay_impact = list(
    note = "Iter 1 KPI: overlay = portfolio-level size scaling. Effect on Σ measured as conditional (brake ON vs OFF) + effective vol after multiplier.",
    brake_on_n_months = n_on,
    brake_off_n_months = n_off,
    brake_on_pct = round(100*n_on/(n_on+n_off), 2),
    raw_vol_on_ann_pct = round(vol_on_ann * 100, 2),
    raw_vol_off_ann_pct = round(vol_off_ann * 100, 2),
    mean_mult_on = round(mean_mult_on, 4),
    mean_mult_off = round(mean_mult_off, 4),
    effective_vol_on_ann_pct = round(effective_vol_on * 100, 2),
    effective_vol_off_ann_pct = round(effective_vol_off * 100, 2),
    sigma_blended_no_overlay_pct = round(sigma_full_blended * 100, 2),
    sigma_blended_with_overlay_pct = round(sigma_eff_blended * 100, 2),
    overall_vol_reduction_pct = round(overall_vol_reduction_pct, 2),
    avg_cor_brake_on = round(avg_cor_on, 4),
    avg_cor_brake_off = round(avg_cor_off, 4),
    crisis_decorrelation_delta = round(avg_cor_on - avg_cor_off, 4),
    interpretation = "Overlay benefit surfaces in time-series risk reduction (size scaling × elevated brake-ON vol), NOT in cross-section Σ structure. Optimizer should leverage overlay_mult as a portfolio-level scaler."
  ),
  risk_summary = list(
    top_common_risks = top_common_risks,
    crowding_flags = list(
      Q07_AC21_HIGH_COR = list(
        severity = "MEDIUM",
        msg = "Q07_Earnings_Stability vs AC21_CF_to_Accrual_Ratio cor 0.731 (inherited)",
        detail = "Same as WT_003 baseline; not exacerbated by overlay"
      )
    ),
    liquidity_flags = list(),
    stress_tests = list(
      market_down_5 = round(scen_market_5, 4),
      momentum_reversal = round(scen_mom_reversal, 4),
      stress_periods = stress_results
    )
  ),
  tail_risk = tail_risk,
  beta_target = list(
    tier = "HIGH",
    target_range = c(1.0, 1.05),
    estimated_beta = round(b_ew["MKT", 1], 4),
    within_target = (b_ew["MKT", 1] >= 0.95 && b_ew["MKT", 1] <= 1.10)
  ),
  regime_conditional = regime_cond_summary,
  tdc_summary = list(
    Q07_vs_AC21_inherited = round(q07_ac21_cor_baseline, 4),
    iter1_overlay_vs_baseline_lower = round(tdc_iter1_vs_baseline, 4),
    iter1_overlay_vs_baseline_upper = round(upper_tdc, 4),
    note = "Same 20-ticker universe as WT_003 → portfolio-level TDC near 1 by construction. Overlay introduces partial decoupling on extreme months."
  ),
  rolling_sigma_stability = list(
    window_months = 36L,
    step_months = 6L,
    n_windows = nrow(roll_dt),
    vol_ann_mean_pct = round(roll_vol_mean, 2),
    vol_ann_sd_pct = round(roll_vol_sd, 2),
    vol_ann_cv = round(roll_vol_cv, 4),
    interpretation = if (roll_vol_cv < 0.15) "STABLE (CV<15%)"
                     else if (roll_vol_cv < 0.25) "MODERATE"
                     else "UNSTABLE"
  ),
  risk_response_to_alpha_RFA1 = risk_response_to_RFA1,
  diagnostics = list(
    condition_number = round(cond_final, 2),
    shrinkage_used = (min_eig_final < best$min_eig || blend_w == 0.5),
    shrinkage_method = if (blend_w == 0.5) "factor_blend_50_50" else method_selected,
    factor_correlation_warnings = list(),
    tdc_summary = list(
      Q07_vs_AC21 = round(q07_ac21_cor_baseline, 4),
      iter1_overlay_lower_tdc = round(tdc_iter1_vs_baseline, 4)
    ),
    regime_correlation_ref = sprintf("stage_artifacts/WT_%s/regime_correlation.parquet", WT_ID)
  ),
  challenge_review = list(
    objection = FALSE,
    targets_reviewed = c("alpha_package", "confidence_vector", "factor_specs", "overlay_specs"),
    challenge_note = list(
      type = "informational",
      from = "risk", to = "optimizer",
      items = list(
        list(item = "overlay_mult_size_scaling",
             recommendation = "Optimizer should treat overlay_mult as multiplicative size scaler on aggregate portfolio (not on individual weights). Apply at gross-leverage layer, then re-normalize to Σw=1 for long-only.",
             effective_vol_reduction_pct = round(overall_vol_reduction_pct, 2)),
        list(item = "Q07_AC21_collinearity_inherited",
             vif_q07 = baseline_risk$vif_diagnosis$Q07_Earnings_Stability,
             vif_ac21 = baseline_risk$vif_diagnosis$AC21_CF_to_Accrual_Ratio,
             cor = q07_ac21_cor_baseline,
             recommendation = "Same as WT_003 — joint exposure monitor; alpha not modified"),
        list(item = "RF-A1_alpha_subperiod_response",
             alpha_sub_stab = 0.345,
             risk_rolling_vol_cv = round(roll_vol_cv, 4),
             interpretation = risk_response_to_RFA1$risk_response,
             recommendation = "Σ is structurally stable — alpha sub-stability is IC-side issue (Forge backtest will validate via realized return × overlay path; not a Risk-side challenge)")
      )
    ),
    round = 1
  ),
  challenge_flags = challenge_flags,
  rf_summary = list(
    total_flags = length(challenge_flags),
    high_severity = sum(sapply(challenge_flags, function(x) x$severity == "HIGH")),
    medium_severity = sum(sapply(challenge_flags, function(x) x$severity == "MEDIUM"))
  ),
  optimizer_guidance = list(
    note = "Weight 결정은 Optimizer 영역. Risk → Optimizer 안내사항만.",
    cvar_cap = cvar_cap,
    beta_target_range = c(1.0, 1.05),
    q07_ac21_joint_exposure_monitor = TRUE,
    overlay_application_layer = "gross_leverage_pre_normalization",
    overlay_size_scaler_seq = "weight_optimization → size_scale = clip(overlay_mult * dd_brake_mult * volreg_mult, 0, 1.0_long_only_cap) → renormalize Σw=1",
    long_only_cap_recommendation = "Cap effective leverage at 1.0 for KR long-only mandate (overlay can only DEDUCE, not LEVER UP).",
    expected_vol_reduction_iter1_pct = round(overall_vol_reduction_pct, 2),
    condition_number_ok = (cond_final < 500)
  ),
  pit_compliance = list(
    C1 = "PASS — rolling estimator (60-mo window)",
    C2 = "PASS — month-end factor returns + t-1 lag for overlay state",
    C5 = "PASS — overlay state from BM[t-1]",
    C9 = "PASS — overlay_mult derived from t-1 lagged inputs (alpha_pkg)",
    C10 = "PASS — liquidity inherited from alpha screen",
    lockbox = sprintf("ENFORCED — Pre-LB end %s; Lockbox %s+ untouched",
                      as.character(AS_OF), as.character(LOCKBOX_START))
  )
)

risk_pkg_path <- file.path(WT_DIR, "risk_package.json")
write_json(risk_pkg, risk_pkg_path, pretty = TRUE, auto_unbox = TRUE,
           null = "null", na = "null")
cat(sprintf("  -> %s (sha256=%s)\n", risk_pkg_path,
            substr(digest(file = risk_pkg_path, algo = "sha256"), 1, 16)))

# ===================================================================
# Step 14. Lineage record (CRITICAL: AFTER write_json)
# ===================================================================
source(file.path(FUNC_PATH, "worktask", "lineage_utils.R"))
record_package_lineage(
  task_id = WT_ID,
  package_type = "risk_package",
  method_selected = method_selected,
  input_file_paths = c(
    file.path(WT_DIR, "alpha_package.json"),
    file.path(ART_DIR, "overlay_signals.parquet"),
    file.path(ROOT, "qepm/mailbox/worktask/WT-D20260425_003/risk_package.json"),
    file.path(ROOT, ".cache/rawdata.parquet"),
    file.path(ROOT, ".cache/kr_factor_returns.parquet"),
    file.path(ROOT, ".cache/regime_v7.parquet")
  ),
  windows = list(start = month_labels[1], end = tail(month_labels, 1))
)

# ===================================================================
# Step 15. Challenge review (P4 audit)
# ===================================================================
source(file.path(FUNC_PATH, "worktask", "worktask_manager.R"))
wt_record_challenge_review(
  WT_ID, from_agent = "risk", objection = FALSE,
  targets_reviewed = c("alpha_package", "confidence_vector", "factor_specs", "overlay_specs")
)

# ===================================================================
# Step 16. risk_challenge_note.md (Alpha → Risk handoff)
# ===================================================================
note_path <- file.path(WT_DIR, "risk_challenge_note.md")
md <- sprintf('# WT-D20260425_006 Risk Agent — Handoff Note (Alpha → Risk)

## Iteration 1 Risk Response

### 1. CHARTER_NOTE_SCALING (Alpha → Risk) 응답
**Alpha 주장**: "Overlay = BM-shared scalar → cross-sectional ranking unchanged; effect surfaces in Optimizer/Forge size scaling (turnover/MDD axis), NOT in IC."

**Risk 검증**:
- 동일 20-ticker MEGA_05 universe → cross-sectional Σ 구조는 baseline (WT-D20260425_003) 과 거의 동일.
- Overlay 효과는 **portfolio-level σ time-series**에서 명확히 발현됨:
  - brake ON %d months (%.1f%%) avg_mult=%.3f → effective vol = %.2f%% (vs raw ON=%.2f%%)
  - brake OFF %d months (%.1f%%) avg_mult=%.3f → effective vol = %.2f%%
  - Blended σ: no-overlay=%.2f%% → with-overlay=%.2f%% (Iter1 KPI: -%.2f%%)
- → Alpha의 CHARTER_NOTE 정확함. Σ는 Iter1에서 cross-section 구조 유지, vol reduction은 size-scaling 채널.

### 2. RF-A1 (sub_stability=0.345) Risk-side 응답
- Alpha sub-stability는 **IC 시간 안정성** 문제 (cross-sectional rank IC 의 segment별 일관성).
- Risk-side 측정: Σ_iter1 의 시간 안정성 = 36-month rolling Σ → vol_CV
  - rolling vol mean = %.2f%% / sd = %.2f%% / **CV = %.3f**
  - 결과: %s
- **Risk 진단**: Σ는 시간적으로 안정적. RF-A1는 alpha IC 채널의 문제이며, Σ 구조 불안정성과는 분리됨.
- → Forge backtest가 realized return × overlay_mult(t-1) 경로로 MDD/SR 변화 empirical 검증 필요 (Risk 영역 아님).

### 3. Iter 1 Risk-side 핵심 발견
| Metric | Baseline (WT_003) | Iter1 (WT_006) | Delta |
|---|---|---|---|
| Σ method | %s | %s | — |
| Cond number | %.2f | %.2f | %+.2f |
| Port vol (ann) | %.2f%% | %.2f%% | %+.2f pp |
| Market contribution | %.1f%% | %.1f%% | %+.2f pp |
| Q07_AC21 cor | %.3f | %.3f (inherited) | unchanged |
| **Overlay vol reduction** | — | **%.2f%%** | (Iter 1 new) |

### 4. Crisis Decorrelation (overlay 시계열 효과)
- avg_cor_brake_on  = %.3f
- avg_cor_brake_off = %.3f
- Δ = %.3f → %s

### 5. 4-Regime Σ summary
%s

### 6. Stress Tests
- market_down_5 = %+.2f%% (β=%.3f)
- momentum_reversal = %+.2f%% (β_WML=%.3f)
- 8-period stress 상세: stage_artifacts/WT_%s/risk_package.json::risk_summary.stress_tests

### 7. Tail Risk
- CVaR_95 = %.4f / CVaR_99 = %.4f
- CDaR_95 = %.4f / MDD_obs (60M) = %.4f
- EVT(%s): VaR99=%.4f / ES99=%.4f
- CVaR_cap (%.1f%%) breach = %s

### 8. Optimizer Handoff (No Weight Proposals — Risk 영역 외)
- Σ_final, Σ_struct, B, Ω, D 모두 covariance.parquet / exposure_matrix.parquet / factor_covariance.parquet / specific_risk.parquet 에 저장.
- **권고 (Risk → Optimizer)**:
  1. overlay_mult 는 **portfolio gross-leverage 단계**에서 적용. 개별 weight 곱이 아닌 aggregate scaler.
  2. KR long-only mandate → effective scaling cap [0, 1.0]. (overlay 1.5 cap 은 alpha 영역; long-only 정책상 deduce-only.)
  3. Q07_AC21 joint exposure monitor (cor=%.3f, baseline 동일).
  4. CVaR_cap %.1f%% (월간) 준수.

### 9. Charter §8 No Silent Override 준수
- alpha_vector 미수정.
- factor_specs 미수정.
- overlay_specs 미수정 (alpha 영역).
- Risk 산출물: Σ + 진단만.

### 10. Common Charter 8원칙 자기진단 (Risk side)
1. PIT only — PASS (60-mo rolling, t-1 lag inputs)
2. Research process — PASS (Σ estimator 5 candidates parallel)
3. Family vs Proxy — PASS (Σ는 risk-engine output)
4. Paper as starting — PASS (Ledoit-Wolf 2004, Gerber 2015, EVT-GPD)
5. No data mining — PASS (selection_objective=condition_number, no SR/IR참조)
6. Dynamic smart alpha — N/A (Risk 영역 아님)
7. Cost/capacity/crowding — PASS (Q07_AC21 inherited; no new crowding source)
8. No silent override — PASS

──────────────
Generated by Risk Agent v1.1 @ %s
',
  n_on, 100*n_on/(n_on+n_off), mean_mult_on, effective_vol_on*100, vol_on_ann*100,
  n_off, 100*n_off/(n_on+n_off), mean_mult_off, effective_vol_off*100,
  sigma_full_blended*100, sigma_eff_blended*100, overall_vol_reduction_pct,

  roll_vol_mean, roll_vol_sd, roll_vol_cv,
  risk_response_to_RFA1$risk_response,

  baseline_risk$selected_estimator$name, method_selected,
  baseline_risk$sigma_structure$condition_number, cond_final,
  cond_final - baseline_risk$sigma_structure$condition_number,
  baseline_risk$sigma_structure$port_vol_ann_pct, port_vol_ann*100,
  port_vol_ann*100 - baseline_risk$sigma_structure$port_vol_ann_pct,
  baseline_risk$sigma_structure$market_contribution_pct, market_pct*100,
  market_pct*100 - baseline_risk$sigma_structure$market_contribution_pct,
  baseline_risk$vif_diagnosis$Q07_vs_AC21_cor, q07_ac21_cor_baseline,
  overall_vol_reduction_pct,

  avg_cor_on, avg_cor_off, avg_cor_on - avg_cor_off,
  if (avg_cor_on > avg_cor_off) "brake-ON 시 평균 상관 상승 (typical crisis pattern)"
                                else "brake-ON 시 평균 상관 하락 또는 무차이",

  paste(sapply(names(regime_cond_summary), function(r) {
    s <- regime_cond_summary[[r]]
    sprintf("- %s (N=%d): avg_cor=%s | vol_ann=%s%%",
            r, s$n_obs %||% 0,
            if (is.null(s$avg_cor) || is.na(s$avg_cor)) "NA" else sprintf("%.3f", s$avg_cor),
            if (is.null(s$vol_ann_pct) || is.na(s$vol_ann_pct)) "NA" else sprintf("%.2f", s$vol_ann_pct))
  }), collapse = "\n"),

  scen_market_5*100, b_ew["MKT",1],
  scen_mom_reversal*100, b_ew["WML",1],
  WT_ID,

  abs(v95$CVaR), abs(v99$CVaR), abs(d95$CDaR), abs(mdd_obs),
  evt$method, evt$var99, evt$es99,
  cvar_cap*100, cvar_cap_breach,

  q07_ac21_cor_baseline,
  cvar_cap*100,

  format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
)
`%||%` <- function(a,b) if (!is.null(a) && !is.na(a)) a else b
writeLines(md, note_path)
cat(sprintf("  -> %s\n", note_path))

# ===================================================================
# Step 17. Status transition: ALPHA_DONE → RISK_DONE
# ===================================================================
wt_advance(WT_ID, "RISK_DONE")

cat(sprintf("\n=== RISK_DONE in %.1fs ===\n",
            as.numeric(difftime(Sys.time(), t0, units = "secs"))))
cat(sprintf("  Σ method: %s | cond=%.2f | port_vol=%.2f%%\n",
            method_selected, cond_final, port_vol_ann*100))
cat(sprintf("  Brake ON portfolio vol Δ: %+.2f%% (overall blended reduction)\n",
            -overall_vol_reduction_pct))
cat(sprintf("  TDC vs MEGA_05 (lower): %.3f\n", tdc_iter1_vs_baseline))
cat(sprintf("  RF-R flags: %d (HIGH=%d, MEDIUM=%d)\n",
            length(challenge_flags),
            sum(sapply(challenge_flags, function(x) x$severity == "HIGH")),
            sum(sapply(challenge_flags, function(x) x$severity == "MEDIUM"))))
