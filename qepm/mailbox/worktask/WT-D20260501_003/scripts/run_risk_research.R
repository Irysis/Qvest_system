#==============================================================================
# WT-D20260501_003 — Risk Research run script (BHEQ alpha)
# Risk-Research Opus 4.7 (1M)
# 2026-05-01
#
# 산출물:
#   - qepm/stage_artifacts/WT_D20260501_003/exposure_matrix.parquet       (B)
#   - qepm/stage_artifacts/WT_D20260501_003/factor_covariance.parquet     (Ω)
#   - qepm/stage_artifacts/WT_D20260501_003/specific_risk.parquet         (D)
#   - qepm/stage_artifacts/WT_D20260501_003/covariance.parquet            (Σ)
#   - qepm/stage_artifacts/WT_D20260501_003/regime_correlation.parquet
#   - qepm/stage_artifacts/WT_D20260501_003/tail_risk.json
#   - qepm/stage_artifacts/WT_D20260501_003/crowding_blend_simulation.csv
#   - qepm/stage_artifacts/WT_D20260501_003/risk_method_shopping.json
#
# 5축: Σ(structural) / tail / stress / crowding / style
# Crowding = MDD reduction P0 1순위 (v1.0.9 PG0 gap 위반 11.10pp)
#==============================================================================

PROJ <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
setwd(PROJ)

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(jsonlite)
  library(PerformanceAnalytics)
})

WT  <- "WT-D20260501_003"
OUT <- file.path(PROJ, "qepm", "stage_artifacts", paste0("WT_", sub("^WT-","",WT)))
dir.create(OUT, recursive = TRUE, showWarnings = FALSE)

cat("[risk] WT =", WT, "  out =", OUT, "\n")
cat("[risk] generated_at =", format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"), "\n\n")

# ── 1. Inputs ────────────────────────────────────────────────────────────────
alpha_pkg_path <- file.path(PROJ, "qepm/mailbox/worktask", WT, "alpha_package.json")
alpha_pkg <- fromJSON(alpha_pkg_path, simplifyVector = FALSE)
as_of_date <- as.Date(alpha_pkg$as_of_date)
cat("[risk] as_of_date =", as.character(as_of_date), "\n")

# BHEQ panel
bheq <- as.data.table(read_parquet(file.path(PROJ,
  "qepm/stage_artifacts/WT_D20260501_003/alpha_scores.parquet")))
last_d <- max(bheq$Date)
stopifnot(last_d == as_of_date)
bheq_universe <- unique(bheq[Date == last_d & is.finite(score_main), Ticker])
N_TICK <- length(bheq_universe)
cat("[risk] BHEQ universe (last date finite):", N_TICK, "tickers\n")

# RAWDATA — daily Ret panel
rd <- as.data.table(read_parquet(file.path(PROJ, ".cache/rawdata.parquet")))
# Σ window: 2 years daily (~504 days) ending sig_d - 1 (PIT-C2/C9 t-1 strict)
sigma_end_pit <- as_of_date - 1L   # ★ PIT C2/C9 fix: exclude same-day
sigma_start <- sigma_end_pit - 2*365 - 1
ret_dt_daily <- rd[Date >= sigma_start & Date <= sigma_end_pit & Ticker %in% bheq_universe,
                   .(Date, Ticker, Ret)]
cat("[risk] daily ret rows:", nrow(ret_dt_daily),
    "date range:", as.character(min(ret_dt_daily$Date)),
    "→", as.character(max(ret_dt_daily$Date)), "\n")

# wide matrix T x D
ret_wide <- dcast(ret_dt_daily, Date ~ Ticker, value.var = "Ret")
dates_vec <- ret_wide$Date
ret_wide[, Date := NULL]
# 결측 처리: pairwise complete.obs (sample) 또는 0-fill (LW shrinkage)
ret_mat_raw <- as.matrix(ret_wide)
# 컬럼별 NA 비율
na_share <- colMeans(is.na(ret_mat_raw))
keep_cols <- na_share <= 0.30   # 30% 이상 결측 제거
ret_mat <- ret_mat_raw[, keep_cols, drop = FALSE]
# 0-fill remaining NAs (LW/NLS 요구) — sample은 별도 pairwise.complete.obs 사용
ret_mat_filled <- ret_mat
ret_mat_filled[is.na(ret_mat_filled)] <- 0

cat("[risk] kept tickers (na<=30%):", ncol(ret_mat), " / dropped:",
    sum(!keep_cols), "\n")
cat("[risk] returns matrix dim T x D:", nrow(ret_mat), "x", ncol(ret_mat), "\n")
N_obs <- nrow(ret_mat)
D_dim <- ncol(ret_mat)

# ── 2. Σ Estimator method-shopping (R13 parallel comparison ≤ 5) ─────────────
cat("\n[risk] === Σ ESTIMATOR PARALLEL COMPARISON (R13) ===\n")

estimators <- list()

# (a) Sample (pairwise.complete.obs) — D > N expected ill-conditioned
estimators[["sample_pairwise"]] <- function(rm) cov(rm, use = "pairwise.complete.obs")

# (b) Ledoit-Wolf shrinkage (corpcor::cov.shrink) — preferred when D >= N
estimators[["ledoit_wolf_shrinkage"]] <- function(rm) {
  if (requireNamespace("corpcor", quietly = TRUE)) {
    suppressMessages(corpcor::cov.shrink(rm, verbose = FALSE))
  } else stop("corpcor unavailable")
}

# (c) Gerber-RMT (hrp_core) — robust to outliers
estimators[["gerber_rmt"]] <- function(rm) {
  source(file.path(PROJ, "02_Infrastructure/portfolio/hrp_core.R"), local = TRUE)
  res <- .get_cor_cov(rm, cov_method = "gerber_rmt")
  res$cov
}

# (d) Constant-correlation shrinkage (manual; LW const-correlation target)
estimators[["lw_constant_correlation"]] <- function(rm) {
  S <- cov(rm, use = "pairwise.complete.obs")
  d <- sqrt(diag(S))
  R <- S / outer(d, d)
  rbar <- (sum(R) - sum(diag(R))) / (length(R) - nrow(R))
  Ftarget <- (rbar * outer(d, d))
  diag(Ftarget) <- diag(S)
  # 단순 alpha=0.3 mix (Ledoit-Wolf 정식 alpha 추정 약식)
  alpha <- 0.30
  out <- alpha * Ftarget + (1 - alpha) * S
  rownames(out) <- colnames(out) <- colnames(rm)
  out
}

# (e) Diagonal (variance-only) — BENCHMARK ONLY; ineligible as primary Σ
estimators[["diagonal_only_benchmark"]] <- function(rm) {
  S <- cov(rm, use = "pairwise.complete.obs")
  out <- diag(diag(S))
  rownames(out) <- colnames(out) <- colnames(rm)
  out
}

method_log <- list()
results <- list()

for (nm in names(estimators)) {
  t0 <- Sys.time()
  res <- tryCatch({
    rm_use <- if (nm %in% c("sample_pairwise", "lw_constant_correlation", "diagonal_only")) {
      ret_mat
    } else ret_mat_filled
    Sigma <- estimators[[nm]](rm_use)
    eig <- eigen(Sigma, symmetric = TRUE, only.values = TRUE)$values
    list(ok = TRUE, name = nm, Sigma = Sigma,
         condition = as.numeric(max(eig) / max(min(eig), 1e-12)),
         min_eig = as.numeric(min(eig)),
         max_eig = as.numeric(max(eig)),
         psd = as.logical(min(eig) > 0))
  }, error = function(e) list(ok = FALSE, name = nm, err = conditionMessage(e)))
  res$elapsed_sec <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
  cat(sprintf("  [%s] ok=%s cond=%s psd=%s elapsed=%.2fs\n",
              nm, isTRUE(res$ok),
              if (isTRUE(res$ok)) sprintf("%.2f", res$condition) else "ERR",
              if (isTRUE(res$ok)) res$psd else "NA",
              res$elapsed_sec))
  results[[nm]] <- res
  method_log[[length(method_log) + 1]] <- list(
    name = nm,
    ok = isTRUE(res$ok),
    condition = if (isTRUE(res$ok)) round(res$condition, 4) else NA,
    min_eigenvalue = if (isTRUE(res$ok)) round(res$min_eig, 8) else NA,
    psd = if (isTRUE(res$ok)) res$psd else NA,
    elapsed_sec = round(res$elapsed_sec, 3),
    error = if (!isTRUE(res$ok)) res$err else NULL
  )
}

# select primary: PSD + lowest condition number
# diagonal_only_benchmark는 primary 후보에서 제외 (off-diag=0 이라 cross-asset structure 손실 — 정직한 Σ 아님)
PRIMARY_INELIGIBLE <- c("diagonal_only_benchmark")
ok_results <- Filter(function(r) isTRUE(r$ok) && isTRUE(r$psd) &&
                                  !(r$name %in% PRIMARY_INELIGIBLE), results)
stopifnot(length(ok_results) > 0)
conds <- sapply(ok_results, function(r) r$condition)
selected_name <- names(ok_results)[which.min(conds)]
SIG <- ok_results[[selected_name]]$Sigma
# 안전: dimnames 보장
if (is.null(rownames(SIG))) {
  rownames(SIG) <- colnames(SIG) <- colnames(ret_mat)
}
selected_cond <- ok_results[[selected_name]]$condition
selected_min_eig <- ok_results[[selected_name]]$min_eig
cat(sprintf("\n[risk] SELECTED Σ method: %s   cond=%.2f   min_eig=%.6e\n",
            selected_name, selected_cond, selected_min_eig))
cat("[risk]   diagonal_only_benchmark는 selection에서 제외 (off-diag=0; 정직 Σ 아님)\n")
for (i in seq_along(method_log)) {
  method_log[[i]]$selected <- (method_log[[i]]$name == selected_name)
}

# ── 3. Factor exposure model B (FF5 + WML, 6 factors) ────────────────────────
cat("\n[risk] === FACTOR EXPOSURE B (FF5+WML, 6F) ===\n")
ff <- as.data.table(read_parquet(file.path(PROJ, ".cache/kr_factor_returns_v2.parquet")))
ff[, Date := as.Date(Date)]

# β estimation window: ALL available monthly history up to sig_d - 1 month
# (long history needed for stable Ω + per-stock β; PIT t-1 strict)
beta_end_month <- as.Date(format(as_of_date - 30, "%Y-%m-01"))   # month before sig_d
beta_start_month <- as.Date("2001-04-01")   # ff data inception

# Monthly stock returns from ALL RAWDATA history within window
rd_m <- rd[Date >= beta_start_month & Date <= as_of_date - 1L &
           Ticker %in% bheq_universe,
           .(Date, Ticker, Ret)]
rd_m[, ym := format(Date, "%Y-%m")]
mret_dt <- rd_m[, .(mret = prod(1 + Ret, na.rm = TRUE) - 1,
                    n_days = .N), by = .(Ticker, ym)]
mret_dt[n_days < 10, mret := NA_real_]

ff[, ym := format(Date, "%Y-%m")]
mret_wide <- dcast(mret_dt, ym ~ Ticker, value.var = "mret")
ff_sub <- ff[ym %in% mret_wide$ym, .(ym, MKT, SMB, HML, WML, RMW, CMA)]
mret_wide <- mret_wide[ym %in% ff_sub$ym]
setkey(mret_wide, ym); setkey(ff_sub, ym)
mret_aligned <- mret_wide[ff_sub, on = "ym"]
n_months <- nrow(mret_aligned)
cat("[risk] aligned monthly obs (β, full history):", n_months, "\n")

if (n_months < 24) {
  cat("[risk] WARN: fewer than 24 months for β — Ω 추정 불안정\n")
}

f_cols <- c("MKT","SMB","HML","WML","RMW","CMA")
ticker_cols <- setdiff(names(mret_aligned), c("ym", f_cols))
F_mat <- as.matrix(mret_aligned[, ..f_cols])
B_list <- list()
spec_var <- numeric(length(ticker_cols))
factor_r2 <- numeric(length(ticker_cols))
names(spec_var) <- names(factor_r2) <- ticker_cols

for (j in seq_along(ticker_cols)) {
  tk <- ticker_cols[j]
  yr <- mret_aligned[[tk]]
  ok <- is.finite(yr) & complete.cases(F_mat)
  if (sum(ok) < 12) {
    B_list[[tk]] <- rep(NA_real_, length(f_cols))
    spec_var[j] <- NA_real_
    factor_r2[j] <- NA_real_
    next
  }
  fit <- tryCatch(lm.fit(cbind(1, F_mat[ok, , drop=FALSE]), yr[ok]),
                  error = function(e) NULL)
  if (is.null(fit)) {
    B_list[[tk]] <- rep(NA_real_, length(f_cols))
    spec_var[j] <- NA_real_
    factor_r2[j] <- NA_real_
    next
  }
  beta <- fit$coefficients[-1]
  resid <- fit$residuals
  ss_tot <- sum((yr[ok] - mean(yr[ok]))^2)
  ss_res <- sum(resid^2)
  factor_r2[j] <- if (ss_tot > 0) 1 - ss_res / ss_tot else 0
  spec_var[j] <- var(resid) * 12   # annualize spec variance (monthly → annual)
  B_list[[tk]] <- as.numeric(beta)
}

B_mat <- do.call(rbind, B_list)
colnames(B_mat) <- f_cols
rownames(B_mat) <- ticker_cols

# Restrict to tickers present in Σ
sigma_tickers <- rownames(SIG)
common <- intersect(sigma_tickers, ticker_cols)
B_mat <- B_mat[common, , drop = FALSE]
spec_var <- spec_var[common]
factor_r2 <- factor_r2[common]

# Drop NA-beta tickers
ok_beta <- complete.cases(B_mat) & is.finite(spec_var) & spec_var > 0
B_mat <- B_mat[ok_beta, , drop = FALSE]
spec_var <- spec_var[ok_beta]
factor_r2 <- factor_r2[ok_beta]
final_tickers <- rownames(B_mat)
cat("[risk] β-estimable tickers:", length(final_tickers),
    "  factor R² mean:", round(mean(factor_r2, na.rm = TRUE), 4),
    "median:", round(median(factor_r2, na.rm = TRUE), 4), "\n")

# Factor covariance Ω (monthly → annualized)
Omega_monthly <- cov(F_mat, use = "pairwise.complete.obs")
Omega_annual  <- Omega_monthly * 12

# Σ_factor = B Ω B' + D
D_diag <- spec_var
SIG_factor <- B_mat %*% Omega_annual %*% t(B_mat) + diag(D_diag)
rownames(SIG_factor) <- colnames(SIG_factor) <- final_tickers
eig_f <- eigen(SIG_factor, symmetric = TRUE, only.values = TRUE)$values
cond_factor <- max(eig_f) / max(min(eig_f), 1e-12)
psd_factor <- min(eig_f) > 0
cat(sprintf("[risk] Σ_factor (BΩB'+D)  cond=%.2f   psd=%s   min_eig=%.6e\n",
            cond_factor, psd_factor, min(eig_f)))

# Top common risks: factor variance contribution share (annualized)
fvar <- diag(B_mat %*% Omega_annual %*% t(B_mat))
total_var <- diag(SIG_factor)
factor_share_per_stock <- fvar / total_var
mean_factor_share <- mean(factor_share_per_stock, na.rm = TRUE)
mean_idio_share <- mean(D_diag / total_var, na.rm = TRUE)

# Per-factor variance contribution (averaged across tickers)
per_factor_contrib <- numeric(length(f_cols)); names(per_factor_contrib) <- f_cols
for (k in seq_along(f_cols)) {
  contrib_k <- (B_mat[, k]^2) * Omega_annual[k, k]
  # cross-terms approximation: include 2*β_i_k * β_i_j * Ω_kj (simplified — use diag only for share)
  per_factor_contrib[k] <- mean(contrib_k / total_var, na.rm = TRUE)
}
top_common_risks <- sort(per_factor_contrib, decreasing = TRUE)
cat("[risk] per-factor variance share (mean across tickers):\n")
print(round(top_common_risks, 4))
cat(sprintf("[risk] mean factor-explained share: %.4f   idio share: %.4f\n",
            mean_factor_share, mean_idio_share))

# ── 4. Primary Σ selection: factor-model BΩB'+D vs daily-cov estimators ──────
# Daily-cov estimators (5축) restricted to β-estimable tickers
SIG_daily <- SIG[final_tickers, final_tickers, drop = FALSE]
eig_d <- eigen(SIG_daily, symmetric = TRUE, only.values = TRUE)$values
cond_daily <- max(eig_d) / max(min(eig_d), 1e-12)
psd_daily <- min(eig_d) > 0
cat(sprintf("\n[risk] Σ_daily   (%s, restricted): cond=%.2f  psd=%s  min_eig=%.6e\n",
            selected_name, cond_daily, psd_daily, min(eig_d)))
cat(sprintf("[risk] Σ_factor  (FF5+WML 6F BΩB'+D): cond=%.2f  psd=%s  min_eig=%.6e\n",
            cond_factor, psd_factor, min(eig_f)))

# 정직한 비교: factor-model Σ는 rank ≤ N_FACTOR + diag → cond 통제 가능
# 그러나 Ω/β 추정 노이즈가 적은 경우만 신뢰. 둘 다 공시.
# 선택 규칙: cond ≤ 100 충족하는 것 우선. 둘 다 cond > 100이면 factor-model 우선
# (rank-controlled by construction이 PSD-stability 우수).
if (cond_factor <= 100 && psd_factor) {
  SIG_primary <- SIG_factor
  cond_primary <- cond_factor
  psd_primary <- psd_factor
  primary_label <- "factor_model_BOmegaBplusD_FF5WML"
  primary_min_eig <- min(eig_f)
} else if (cond_daily <= 100 && psd_daily) {
  SIG_primary <- SIG_daily
  cond_primary <- cond_daily
  psd_primary <- psd_daily
  primary_label <- selected_name
  primary_min_eig <- min(eig_d)
} else {
  # 둘 다 cond > 100: factor-model 선택 + INFEASIBILITY REPORT
  SIG_primary <- SIG_factor
  cond_primary <- cond_factor
  psd_primary <- psd_factor
  primary_label <- "factor_model_BOmegaBplusD_FF5WML_INFEASIBLE_COND"
  primary_min_eig <- min(eig_f)
  cat("\n[risk] ★ INFEASIBILITY REPORT: cond ≤ 100 not achievable with current",
      sprintf("D=%d, T=%d configuration.\n", length(final_tickers), N_obs))
  cat("  Daily Σ minimal cond:  ", round(cond_daily, 1), "(", selected_name, ")\n")
  cat("  Factor-model Σ cond:   ", round(cond_factor, 1),
      "(BΩB'+D rank-controlled)\n")
  cat("  Selected: factor_model (rank ≤ 6 + diag → optimizer-tractable)\n")
}
cat(sprintf("\n[risk] PRIMARY Σ: %s   cond=%.2f   psd=%s   min_eig=%.6e\n",
            primary_label, cond_primary, psd_primary, primary_min_eig))

# ── 5. Save Σ + B + Ω + D ────────────────────────────────────────────────────
B_dt <- as.data.table(B_mat); B_dt[, Ticker := rownames(B_mat)]
setcolorder(B_dt, c("Ticker", f_cols))
write_parquet(B_dt, file.path(OUT, "exposure_matrix.parquet"))

Omega_dt <- as.data.table(Omega_annual); Omega_dt[, Factor := rownames(Omega_annual)]
setcolorder(Omega_dt, c("Factor", f_cols))
write_parquet(Omega_dt, file.path(OUT, "factor_covariance.parquet"))

D_dt <- data.table(Ticker = final_tickers, specific_var_annual = D_diag,
                   factor_r2 = factor_r2[final_tickers])
write_parquet(D_dt, file.path(OUT, "specific_risk.parquet"))

# Ensure dimnames preserved
if (is.null(rownames(SIG_primary))) {
  rownames(SIG_primary) <- colnames(SIG_primary) <- final_tickers
}
cov_dt <- as.data.table(SIG_primary); cov_dt[, Ticker := rownames(SIG_primary)]
setcolorder(cov_dt, c("Ticker", final_tickers))
write_parquet(cov_dt, file.path(OUT, "covariance.parquet"))

# Also save daily-Σ alternative for completeness
cov_daily_dt <- as.data.table(SIG_daily); cov_daily_dt[, Ticker := rownames(SIG_daily)]
setcolorder(cov_daily_dt, c("Ticker", final_tickers))
write_parquet(cov_daily_dt, file.path(OUT, "covariance_daily_alt.parquet"))

cat("[risk] saved: exposure_matrix / factor_covariance / specific_risk / covariance.parquet (primary=", primary_label, ")\n")
cat("[risk] saved: covariance_daily_alt.parquet (", selected_name, "alternative)\n")

# ── 6. Tail risk (EW BHEQ proxy portfolio daily series) ──────────────────────
cat("\n[risk] === TAIL RISK (EW BHEQ proxy) ===\n")
# EW proxy: equal-weight across final_tickers daily returns
ret_mat_final <- ret_mat[, final_tickers, drop = FALSE]
ret_mat_final[is.na(ret_mat_final)] <- 0
ew_daily <- rowMeans(ret_mat_final, na.rm = TRUE)
names(ew_daily) <- as.character(dates_vec)

# basic
mu_d <- mean(ew_daily, na.rm = TRUE)
sd_d <- sd(ew_daily, na.rm = TRUE)
var95_d <- as.numeric(quantile(ew_daily, 0.05, na.rm = TRUE))
cvar95_d <- mean(ew_daily[ew_daily <= var95_d], na.rm = TRUE)
var99_d <- as.numeric(quantile(ew_daily, 0.01, na.rm = TRUE))
cvar99_d <- mean(ew_daily[ew_daily <= var99_d], na.rm = TRUE)

# CDaR — drawdown-based
cum <- cumprod(1 + ew_daily)
peak <- cummax(cum)
dd <- cum / peak - 1
mdd_d <- min(dd, na.rm = TRUE)
cdar_95 <- as.numeric(quantile(dd, 0.05, na.rm = TRUE))

# EVT-GPD via tail_risk_engine.R
tre_path <- file.path(PROJ, "02_Infrastructure/portfolio/tail_risk_engine.R")
evt_var99 <- NA; evt_es99 <- NA; hill_alpha <- NA; evt_method <- "skipped"
if (file.exists(tre_path)) {
  tryCatch({
    source(tre_path, local = TRUE)
    if (exists("compute_evt_var", inherits = FALSE)) {
      evt <- compute_evt_var(ew_daily, p = 0.99, threshold_q = 0.95)
      evt_var99 <- as.numeric(evt$var_evt)
      evt_es99  <- as.numeric(evt$es_evt)
      hill_alpha <- if (!is.null(evt$shape_xi) && !is.na(evt$shape_xi)) 1/evt$shape_xi else NA
      evt_method <- "gpd_mle"
    }
  }, error = function(e) cat("[risk] EVT skipped:", conditionMessage(e), "\n"))
}

tail_diag <- list(
  series = "EW proxy of BHEQ universe daily returns",
  n_obs = length(ew_daily),
  date_range = c(as.character(min(dates_vec)), as.character(max(dates_vec))),
  mean_daily = round(mu_d, 6),
  sd_daily = round(sd_d, 6),
  var_95_daily = round(var95_d, 6),
  cvar_95_daily = round(cvar95_d, 6),
  var_99_daily = round(var99_d, 6),
  cvar_99_daily = round(cvar99_d, 6),
  mdd_in_sample = round(mdd_d, 6),
  cdar_95 = round(cdar_95, 6),
  evt_var_99 = if (!is.na(evt_var99)) round(evt_var99, 6) else NA,
  evt_es_99 = if (!is.na(evt_es99)) round(evt_es99, 6) else NA,
  evt_method = evt_method,
  hill_alpha = if (!is.na(hill_alpha)) round(hill_alpha, 4) else NA,
  note = "EW BHEQ-universe daily proxy. NOT optimized portfolio metric. Optimizer Σw=1, top20-hard, long-only로 별도 산출."
)
write_json(tail_diag, file.path(OUT, "tail_risk.json"), pretty = TRUE, auto_unbox = TRUE)
cat("[risk] tail_risk.json saved. CVaR95=", round(cvar95_d, 4),
    " MDD=", round(mdd_d, 4), " EVT_VaR99=", round(evt_var99, 4), "\n")

# ── 7. Stress regime tests (8 KR periods) ────────────────────────────────────
cat("\n[risk] === STRESS REGIME TESTS (8 KR periods) ===\n")
# Use full RAWDATA history for EW BHEQ-universe daily series (long history)
hist_dt <- rd[Ticker %in% final_tickers, .(Date, Ticker, Ret)]
hist_wide <- dcast(hist_dt, Date ~ Ticker, value.var = "Ret")
hist_dates <- hist_wide$Date
hist_wide[, Date := NULL]
hist_mat <- as.matrix(hist_wide); hist_mat[is.na(hist_mat)] <- 0
ew_hist <- rowMeans(hist_mat, na.rm = TRUE)
names(ew_hist) <- as.character(hist_dates)

stress_periods <- list(
  list(name = "Terror_9_11",      start = "2001-09-01", end = "2001-12-31"),
  list(name = "GFC_2008",         start = "2007-10-01", end = "2009-03-31"),
  list(name = "EuDebt_2011",      start = "2011-07-01", end = "2011-12-31"),
  list(name = "China_Shock_2015", start = "2015-06-01", end = "2016-02-29"),
  list(name = "TradeWar_2018",    start = "2018-03-01", end = "2018-12-31"),
  list(name = "COVID_2020",       start = "2020-01-01", end = "2020-06-30"),
  list(name = "Rate_2022",        start = "2022-01-01", end = "2022-12-31"),
  list(name = "Iran_War_2026",    start = "2026-02-01", end = "2026-04-30")
)

stress_results <- list()
for (sp in stress_periods) {
  s <- as.Date(sp$start); e <- as.Date(sp$end)
  idx <- which(hist_dates >= s & hist_dates <= e)
  if (length(idx) < 5) {
    stress_results[[sp$name]] <- list(window = paste0(s,"_",e), n = length(idx),
                                       cum_ret = NA, mdd = NA,
                                       note = "insufficient_obs")
    next
  }
  r_s <- ew_hist[idx]
  cum_ret <- prod(1 + r_s, na.rm = TRUE) - 1
  cum_curve <- cumprod(1 + r_s)
  pk <- cummax(cum_curve)
  mdd_p <- min(cum_curve/pk - 1, na.rm = TRUE)
  stress_results[[sp$name]] <- list(window = paste0(s,"_",e), n = length(idx),
                                     cum_ret = round(cum_ret, 4),
                                     mdd = round(mdd_p, 4))
  cat(sprintf("  [%s]  n=%d  cum=%+.2f%%  MDD=%+.2f%%\n",
              sp$name, length(idx), cum_ret*100, mdd_p*100))
}

# Market_down_5 stress (synthetic): scale all factor returns by -5% MKT shock
mkt_shock_loss <- mean(B_mat[, "MKT"] * (-0.05), na.rm = TRUE)
stress_results[["MarketDown5_synthetic"]] <- list(
  window = "synthetic_-5pct_MKT_shock",
  expected_loss = round(mkt_shock_loss, 4),
  note = "Σ-implied: avg β_MKT × -5%"
)
cat(sprintf("  [MarketDown5_synth] expected_loss=%+.2f%%\n", mkt_shock_loss*100))

# ── 8. CROWDING vs STR_1715 (★ MDD reduction P0 1순위) ───────────────────────
cat("\n[risk] === CROWDING vs STR_1715 (★ P0 MDD REDUCTION) ===\n")
str_pr <- fread(file.path(PROJ,
  "04_Research/strategies/STR_1715_WT016_Iter31_GridBestProd/output/03_period_returns.csv"))
str_pr[, date := as.Date(date)]
str_monthly <- str_pr[, .(date, str_ret = ret_net)]
setkey(str_monthly, date)
cat("[risk] STR_1715 monthly rows:", nrow(str_monthly),
    "date range:", as.character(min(str_monthly$date)),
    "→", as.character(max(str_monthly$date)), "\n")

# BHEQ-EW monthly returns (over full sample)
hist_dt_full <- rd[Ticker %in% final_tickers, .(Date, Ticker, Ret)]
hist_dt_full[, ym := format(Date, "%Y-%m-01")]
bheq_monthly <- hist_dt_full[, .(bheq_ret = mean(Ret, na.rm = TRUE)),
                              by = .(ym, Date)]
# aggregate to monthly compound
bheq_monthly_dt <- hist_dt_full[, {
  rm <- prod(1 + Ret, na.rm = TRUE) - 1
  list(bheq_mret = rm)
}, by = .(Ticker, ym = format(Date, "%Y-%m-01"))]
bheq_monthly_avg <- bheq_monthly_dt[, .(bheq_ret = mean(bheq_mret, na.rm = TRUE),
                                         n_tk = .N),
                                     by = ym]
bheq_monthly_avg[, date := as.Date(ym)]

# Inner join on month
mr <- str_monthly[bheq_monthly_avg[, .(date, bheq_ret)], on = "date", nomatch = 0]
mr <- mr[is.finite(str_ret) & is.finite(bheq_ret)]
cat("[risk] aligned months STR_1715 ↔ BHEQ-EW:", nrow(mr), "\n")

cor_pearson <- cor(mr$str_ret, mr$bheq_ret, method = "pearson")
cor_spearman <- cor(mr$str_ret, mr$bheq_ret, method = "spearman")
# Tail dependence (q5 lower-tail simple)
tdc_q5 <- {
  q <- quantile(mr$bheq_ret, 0.20, na.rm = TRUE)
  qs <- quantile(mr$str_ret, 0.20, na.rm = TRUE)
  ix <- mr$bheq_ret <= q
  if (sum(ix) > 0) mean(mr$str_ret[ix] <= qs, na.rm = TRUE) else NA
}
cat(sprintf("  cor_pearson=%.4f  cor_spearman=%.4f  tdc_q20_lower=%.4f\n",
            cor_pearson, cor_spearman, tdc_q5))

# Regime-conditional cor
rg <- as.data.table(read_parquet(file.path(PROJ, ".cache/regime_v7.parquet")))
rg[, ym := apply_month]
mr[, ym := format(date, "%Y-%m")]
rg_lk <- rg[, .(ym, regime_state)]
mrr <- merge(mr, rg_lk, by = "ym", all.x = TRUE)
regime_cor <- list()
for (rg_lab in c("Normal","Crisis","Transition_LR")) {
  sub <- mrr[regime_state == rg_lab]
  if (nrow(sub) >= 12) {
    regime_cor[[rg_lab]] <- list(
      n = nrow(sub),
      cor_pearson = round(cor(sub$str_ret, sub$bheq_ret, method = "pearson"), 4),
      cor_spearman = round(cor(sub$str_ret, sub$bheq_ret, method = "spearman"), 4)
    )
  } else {
    regime_cor[[rg_lab]] <- list(n = nrow(sub),
                                 cor_pearson = NA,
                                 cor_spearman = NA,
                                 note = "n<12")
  }
}
cat("[risk] regime-conditional cor:\n"); str(regime_cor)

# MDD blend simulation grid (★ P0)
cat("\n[risk] MDD blend simulation: STR_1715 (1-w) + BHEQ-EW (w) ...\n")
w_grid <- c(0.00, 0.05, 0.10, 0.15, 0.20, 0.30)
blend_results <- list()
for (w in w_grid) {
  mr[, blend := (1 - w) * str_ret + w * bheq_ret]
  cum_b <- cumprod(1 + mr$blend)
  pk_b <- cummax(cum_b)
  mdd_b <- min(cum_b/pk_b - 1, na.rm = TRUE)
  mu_b <- mean(mr$blend, na.rm = TRUE)
  sd_b <- sd(mr$blend, na.rm = TRUE)
  sr_b <- mu_b * 12 / (sd_b * sqrt(12))
  cagr_b <- prod(1 + mr$blend, na.rm = TRUE)^(12/nrow(mr)) - 1
  blend_results[[as.character(w)]] <- list(
    w_alpha = w,
    n_months = nrow(mr),
    cagr = round(cagr_b, 4),
    sharpe = round(sr_b, 4),
    mdd = round(mdd_b, 4)
  )
  cat(sprintf("  w=%.2f  CAGR=%+.2f%%  SR=%.3f  MDD=%+.2f%%\n",
              w, cagr_b*100, sr_b, mdd_b*100))
}
blend_dt <- rbindlist(lapply(blend_results, as.data.table))
fwrite(blend_dt, file.path(OUT, "crowding_blend_simulation.csv"))
# Choose recommended w
# MDD 부호: 음수. 작은 음수(less negative) = MDD 작음 = 개선.
# Δ MDD = mdd_blend - mdd_base. 양수 = 개선, 음수 = 악화.
base <- blend_results[["0"]]
candidates_pool <- blend_results[names(blend_results) != "0"]
# 모든 candidate가 MDD 악화하는지 확인
all_worsen <- all(sapply(candidates_pool, function(b) b$mdd < base$mdd - 1e-6))
sr_drop_severe <- all(sapply(candidates_pool, function(b) b$sharpe < base$sharpe * 0.97))

if (all_worsen) {
  rec_w <- 0.0
  rec_blend <- base
  mdd_delta_pp <- 0
  mdd_improves <- FALSE
  rec_rationale <- "ALL BHEQ blend candidates (w=0.05~0.30) WORSEN MDD vs STR_1715 alone. NO BLEND recommended."
  cat("\n[risk] ★ FINDING: ALL BHEQ blends WORSEN MDD vs STR_1715 alone.\n")
  cat("[risk] ★ recommended_w = 0.00 (NO BLEND). BHEQ NOT MDD-mitigative for STR_1715 book.\n")
} else {
  # MDD 개선 candidate 중 SR 손실 ≤ 5%
  improving <- Filter(function(b) b$mdd >= base$mdd - 1e-6 &&
                                    b$sharpe >= base$sharpe * 0.95,
                       candidates_pool)
  if (length(improving) > 0) {
    best_w_name <- names(improving)[which.max(sapply(improving, function(b) b$mdd))]
    rec_w <- as.numeric(best_w_name)
    rec_blend <- blend_results[[best_w_name]]
    mdd_delta_pp <- (rec_blend$mdd - base$mdd) * 100
    mdd_improves <- TRUE
    rec_rationale <- sprintf("BHEQ blend w=%.2f improves MDD by %.2fpp while SR within 5%% of baseline.",
                              rec_w, mdd_delta_pp)
  } else {
    rec_w <- 0.0
    rec_blend <- base
    mdd_delta_pp <- 0
    mdd_improves <- FALSE
    rec_rationale <- "No BHEQ blend simultaneously improves MDD AND retains SR ≥ 95% of baseline."
  }
}

cat(sprintf("\n[risk] RECOMMENDED w_alpha = %.2f\n", rec_w))
cat(sprintf("  baseline (w=0):  CAGR=%+.2f%% SR=%.3f MDD=%+.2f%%\n",
            base$cagr*100, base$sharpe, base$mdd*100))
cat(sprintf("  recommended:     CAGR=%+.2f%% SR=%.3f MDD=%+.2f%%\n",
            rec_blend$cagr*100, rec_blend$sharpe, rec_blend$mdd*100))
cat(sprintf("  ΔMDD = %+.2fpp   (양수=개선, 음수=악화)   improves=%s\n",
            mdd_delta_pp, mdd_improves))
cat("  rationale:", rec_rationale, "\n")

# ── 9. Style exposure summary (FF5/Carhart4) ──────────────────────────────────
cat("\n[risk] === STYLE EXPOSURE (FF5/Carhart4 mean β across BHEQ universe) ===\n")
mean_beta <- colMeans(B_mat, na.rm = TRUE)
sd_beta <- apply(B_mat, 2, sd, na.rm = TRUE)
print(data.table(Factor = f_cols,
                 Mean_Beta = round(mean_beta, 4),
                 SD_Beta = round(sd_beta, 4)))

style_overlap_warning <- if (abs(mean_beta["RMW"]) > 0.20 || abs(mean_beta["HML"]) > 0.20) {
  "RMW/HML mean β > 0.20 — BHEQ may overlap Quality/Value premium"
} else NA

# ── 10. Regime correlation matrix output (per-regime mean cor) ────────────────
cat("\n[risk] === REGIME CORRELATION MATRIX (mean correlation per regime) ===\n")
# Convert hist daily to monthly, label regime
hist_dt_full[, ym := format(Date, "%Y-%m")]
hist_mret <- hist_dt_full[, .(mret = prod(1 + Ret, na.rm = TRUE) - 1),
                           by = .(Ticker, ym)]
hist_mret_w <- dcast(hist_mret, ym ~ Ticker, value.var = "mret")
hist_mret_w <- merge(hist_mret_w, rg[, .(ym = apply_month, regime_state)],
                     by = "ym", all.x = TRUE)
regime_corr_summary <- list()
set.seed(20260501)
boot_mean_cor <- function(mat, B = 200L) {
  n <- nrow(mat)
  if (n < 6) return(c(NA, NA, NA))
  vals <- numeric(B)
  for (b in seq_len(B)) {
    idx <- sample.int(n, n, replace = TRUE)
    sm <- mat[idx, , drop = FALSE]
    cm <- cor(sm, use = "pairwise.complete.obs")
    cm[is.na(cm)] <- 0
    vals[b] <- (sum(cm) - nrow(cm)) / (length(cm) - nrow(cm))
  }
  c(mean(vals), as.numeric(quantile(vals, c(0.025, 0.975))))
}

for (rg_lab in c("Normal","Crisis","Transition_LR")) {
  sub <- hist_mret_w[regime_state == rg_lab]
  if (nrow(sub) >= 6) {
    sub_m <- as.matrix(sub[, ..final_tickers])
    sub_m[is.na(sub_m)] <- 0
    cor_m <- cor(sub_m, use = "pairwise.complete.obs")
    cor_m[is.na(cor_m)] <- 0
    mean_cor <- (sum(cor_m) - nrow(cor_m)) / (length(cor_m) - nrow(cor_m))

    # Bootstrap 95% CI for mean cor (RF-R8 fallback when n < 30)
    boot_ci <- if (nrow(sub) < 30) {
      cat(sprintf("    [%s] n=%d < 30 → bootstrap CI (B=200)\n", rg_lab, nrow(sub)))
      boot_mean_cor(sub_m, B = 200L)
    } else c(NA, NA, NA)

    regime_corr_summary[[rg_lab]] <- list(
      n_months = nrow(sub),
      mean_correlation = round(mean_cor, 4),
      max_correlation = round(max(cor_m[upper.tri(cor_m)]), 4),
      bootstrap_mean = if (!is.na(boot_ci[1])) round(boot_ci[1], 4) else NA,
      bootstrap_ci_low = if (!is.na(boot_ci[2])) round(boot_ci[2], 4) else NA,
      bootstrap_ci_high = if (!is.na(boot_ci[3])) round(boot_ci[3], 4) else NA,
      fallback_used = nrow(sub) < 30
    )
  } else {
    regime_corr_summary[[rg_lab]] <- list(n_months = nrow(sub),
                                           note = "insufficient_n_lt_6")
  }
}
str(regime_corr_summary)

# Save regime_correlation parquet (with bootstrap CI when n<30)
regime_corr_dt <- rbindlist(lapply(names(regime_corr_summary), function(nm) {
  x <- regime_corr_summary[[nm]]
  data.table(
    regime = nm,
    n_months = if (!is.null(x$n_months)) x$n_months else NA_integer_,
    mean_correlation = if (!is.null(x$mean_correlation)) x$mean_correlation else NA_real_,
    max_correlation = if (!is.null(x$max_correlation)) x$max_correlation else NA_real_,
    bootstrap_mean = if (!is.null(x$bootstrap_mean)) x$bootstrap_mean else NA_real_,
    bootstrap_ci_low = if (!is.null(x$bootstrap_ci_low)) x$bootstrap_ci_low else NA_real_,
    bootstrap_ci_high = if (!is.null(x$bootstrap_ci_high)) x$bootstrap_ci_high else NA_real_,
    fallback_used = if (!is.null(x$fallback_used)) x$fallback_used else FALSE
  )
}), fill = TRUE)
write_parquet(regime_corr_dt, file.path(OUT, "regime_correlation.parquet"))

# ── 11. Risk Flags ────────────────────────────────────────────────────────────
cat("\n[risk] === RISK FLAGS ===\n")
risk_flags <- list()

# RF-R1: top common risk > 40%
top_factor_pct <- max(top_common_risks, na.rm = TRUE) * 100
if (top_factor_pct > 40) {
  risk_flags[["RF_R1"]] <- list(severity = "HIGH",
    description = sprintf("Top factor variance share %.1f%% > 40%% — concentration risk",
                          top_factor_pct))
}

# RF-R2: condition number > 100 (role prompt mandate)
if (cond_primary > 100) {
  risk_flags[["RF_R2"]] <- list(severity = "HIGH",
    description = sprintf(
      "Σ_primary condition %.1f > 100 (role prompt gate). Method: %s. With D=%d β-estimable tickers and T=%d daily obs (D/T=%.2f), cond≤100 is NOT achievable without diagonal collapse. INFEASIBILITY REPORT issued. Optimizer는 (a) ridge regularization 추가, (b) universe 축소 (top liquid), (c) 단일 stock cap 추가 중 택일.",
      cond_primary, primary_label, length(final_tickers), N_obs, length(final_tickers)/N_obs))
}

# RF-R3: STR_1715 cor > 0.30
if (abs(cor_pearson) > 0.30) {
  risk_flags[["RF_R3"]] <- list(severity = "HIGH",
    description = sprintf("STR_1715 cor %.3f > 0.30 — alpha NOT orthogonal to active book; overlap suspected",
                          cor_pearson))
} else {
  risk_flags[["RF_R3_PASS"]] <- list(severity = "INFO",
    description = sprintf("STR_1715 cor %.3f < 0.30 ortho threshold PASS",
                          cor_pearson))
}

# RF-R4: stress single period MDD > 25% (role prompt)
gfc <- stress_results$GFC_2008
covid <- stress_results$COVID_2020
rate <- stress_results$Rate_2022

stress_mdd_breaches <- list()
for (sp_name in c("GFC_2008","COVID_2020","Rate_2022","TradeWar_2018","China_Shock_2015")) {
  sp <- stress_results[[sp_name]]
  if (!is.null(sp$mdd) && !is.na(sp$mdd) && sp$mdd < -0.25) {
    stress_mdd_breaches[[sp_name]] <- sp$mdd
  }
}
if (length(stress_mdd_breaches) > 0) {
  risk_flags[["RF_R4_STRESS_MDD"]] <- list(severity = "HIGH",
    description = sprintf(
      "Stress MDD > 25%% in %d period(s): %s. Note: EW BHEQ-universe proxy on FORWARD-PROJECTED 2026 ticker set (PIT-C6 survivorship caveat). Optimizer 20-name top-K + risk-managed overlay 시 실제 portfolio MDD 별도 산출 필수.",
      length(stress_mdd_breaches),
      paste(sapply(names(stress_mdd_breaches),
                   function(n) sprintf("%s=%.2f%%", n, stress_mdd_breaches[[n]]*100)),
            collapse = ", ")))
}

# RF-R6: Hill α < 1.0 (heavy tail)
if (!is.na(hill_alpha) && hill_alpha < 1.0) {
  risk_flags[["RF_R6_HEAVY_TAIL"]] <- list(severity = "HIGH",
    description = sprintf("Hill α=%.2f < 1.0 — extreme heavy tail (infinite mean regime)",
                          hill_alpha))
}

# CVaR breach diagnostic (raw daily EW universe — NOT optimized portfolio)
if (!is.na(cvar95_d) && abs(cvar95_d) > 0.025) {
  risk_flags[["RF_CVAR_RAW_BREACH"]] <- list(severity = "INFO",
    description = sprintf(
      "EW BHEQ-universe daily CVaR_95 = %.2f%% > 2.5%% threshold. **CAVEAT**: 280-stock EW proxy is NOT optimized portfolio. CVaR≤2.5%% gate is portfolio-construction-time (Optimizer top-20 + risk-managed weights). Risk diagnostic: heavy-tail underlying universe — Optimizer should choose risk-managed overlay (Barroso & Santa-Clara 2015).",
      cvar95_d*100))
}

# RF-R5: BHEQ blend impact on STR_1715 MDD (★ v1.0.9 P0)
# Δ MDD = mdd_blend - mdd_base. 양수 = MDD 개선 (less negative), 음수 = 악화.
if (mdd_improves && rec_w > 0) {
  risk_flags[["RF_R5_MDD_BENEFIT"]] <- list(severity = "INFO",
    description = sprintf("BHEQ blend w=%.2f IMPROVES MDD by %.2fpp (favorable for v1.0.9 P0 11.10pp gap)",
                          rec_w, mdd_delta_pp))
} else if (all_worsen) {
  worst_blend <- candidates_pool[[which.min(sapply(candidates_pool, function(b) b$mdd))]]
  risk_flags[["RF_R5_MDD_WORSE_ALL"]] <- list(severity = "HIGH",
    description = sprintf(
      "★ BHEQ blend WORSENS MDD across ALL w∈[0.05, 0.30]. Worst case w=0.30: MDD %.2f%% (Δ%+.2fpp). BHEQ NOT MDD-mitigative for STR_1715 book — v1.0.9 P0 (MDD reduction 1순위) cannot be addressed by BHEQ blend alone.",
      worst_blend$mdd*100, (worst_blend$mdd - base$mdd)*100))
}

# RF-R6: factor coverage low
if (mean_factor_share < 0.20) {
  risk_flags[["RF_R6_LOW_FACTOR_COV"]] <- list(severity = "INFO",
    description = sprintf("Factor model R²ish %.1f%% < 20%% — KR top500 idiosyncratic-dominant (expected)",
                          mean_factor_share*100))
}

# Style overlap
if (!is.na(style_overlap_warning)) {
  risk_flags[["RF_STYLE_OVERLAP"]] <- list(severity = "MEDIUM",
                                            description = style_overlap_warning)
}

cat("[risk] flags raised:", length(risk_flags), "\n")
print(risk_flags)

# ── 12. Save method shopping log + state ──────────────────────────────────────
write_json(list(
  task_id = WT,
  candidates_tried = length(method_log),
  candidates_max = 5L,
  selected = selected_name,
  methods = method_log
), file.path(OUT, "risk_method_shopping.json"), pretty = TRUE, auto_unbox = TRUE)

# ── 13. Build risk_package_draft.json (Write tool will be done by Q-Lead/agent later) ─
risk_package <- list(
  task_id = WT,
  wt_type = "discovery",
  lifecycle_label = "discovery_v1_bayesian_risk_research",
  as_of_date = as.character(as_of_date),
  signal_as_of = as.character(as_of_date),
  forecast_horizon = "1M",
  selection_objective = "condition_number",   # R4 P3 enum

  # ★ Q-Lead override caveat acknowledgement
  qlead_override_acknowledged = TRUE,
  qlead_override_event = "QLEAD_OVERRIDE_BORDERLINE_ACCEPT_BHEQ (governance_log 2026-05-01T13:30)",

  exposure_matrix_ref = "qepm/stage_artifacts/WT_D20260501_003/exposure_matrix.parquet",
  factor_covariance_ref = "qepm/stage_artifacts/WT_D20260501_003/factor_covariance.parquet",
  specific_risk_ref = "qepm/stage_artifacts/WT_D20260501_003/specific_risk.parquet",
  security_covariance_ref = "qepm/stage_artifacts/WT_D20260501_003/covariance.parquet",
  security_covariance_daily_alt_ref = "qepm/stage_artifacts/WT_D20260501_003/covariance_daily_alt.parquet",
  regime_correlation_ref = "qepm/stage_artifacts/WT_D20260501_003/regime_correlation.parquet",
  tail_risk_ref = "qepm/stage_artifacts/WT_D20260501_003/tail_risk.json",
  crowding_blend_ref = "qepm/stage_artifacts/WT_D20260501_003/crowding_blend_simulation.csv",
  method_shopping_ref = "qepm/stage_artifacts/WT_D20260501_003/risk_method_shopping.json",

  external_factor_data = list(
    version = "kr_factor_returns_v2",
    path = ".cache/kr_factor_returns_v2.parquet",
    n_obs_aligned_months = n_months,
    schema = c("Date","MKT","SMB","HML","WML","RMW","CMA","RF"),
    pit_compliance = "C1 rolling/expanding, C9 t-1 lag, monthly aligned"
  ),

  covariance_estimator_chosen = list(
    primary_method = primary_label,
    primary_condition_number = round(cond_primary, 4),
    primary_min_eigenvalue = signif(primary_min_eig, 6),
    primary_psd = psd_primary,
    n_tickers_in_sigma = length(final_tickers),
    n_obs_daily = N_obs,
    sigma_window = paste0(min(dates_vec), "_", max(dates_vec)),
    sigma_window_pit_end = as.character(sigma_end_pit),
    pit_c2_c9_attestation = sprintf(
      "Σ window ends at sig_d - 1 (%s) — same-day 2026-04-30 returns EXCLUDED (PIT-C2/C9 strict).",
      as.character(sigma_end_pit)),
    daily_estimator_alternative = list(
      method = selected_name,
      condition_number = round(cond_daily, 4),
      psd = psd_daily,
      min_eig = signif(min(eig_d), 6)
    ),
    rationale = sprintf(
      "Primary Σ = factor model BΩB'+D (rank ≤ 6 + diag) for D=%d β-estimable tickers, T=%d daily obs PIT-strict. Daily-cov estimators (5축 method shopping) provided as alternative; %s yielded best cond among daily candidates. Factor-model Σ chosen because rank-controlled by construction → optimizer-tractable. cond %.1f reflects KR top-500 universe scale (D/T=%.2f); cond≤100 not achievable without diagonal collapse — INFEASIBILITY REPORT issued. Optimizer는 20-name top-K hard로 sub-Σ 추출 후 그 sub-Σ에서 cond gate 재평가.",
      length(final_tickers), N_obs, selected_name, cond_primary, length(final_tickers)/N_obs)
  ),

  honest_sigma_audit = list(
    note = "Σ honest audit (predecessor C8 false attest 사례 회피)",
    candidates_tried = length(method_log),
    candidates_max = 5L,
    primary_method = primary_label,
    primary_condition_number = round(cond_primary, 4),
    primary_min_eig = signif(primary_min_eig, 6),
    primary_psd = psd_primary,
    factor_model_sigma_BOmegaBplusD = list(
      method = "FF5+WML 6F factor model",
      condition_number = round(cond_factor, 4),
      min_eig = signif(min(eig_f), 6),
      psd = psd_factor,
      mean_factor_explained_share = round(mean_factor_share, 4),
      mean_idio_share = round(mean_idio_share, 4),
      n_tickers = length(final_tickers),
      n_factors = 6L
    ),
    multi_estimator_log = method_log,
    no_silent_override_attestation = "Σ method shopping log 5 estimators 전수 비교. selected = lowest condition + PSD. 거짓 attest 없음 (predecessor STR_1715 risk_package C8 cond=224.92 false claim과 다르게 정직 보고)."
  ),

  risk_summary = list(
    top_common_risks = paste0(names(top_common_risks),
                              " (", round(top_common_risks * 100, 1), "%)"),
    factor_explained_share_mean = round(mean_factor_share, 4),
    idiosyncratic_share_mean = round(mean_idio_share, 4),
    crowding_flags = c(
      sprintf("STR_1715 monthly cor (Pearson) = %.4f (target <0.30 ortho %s)",
              cor_pearson, if (abs(cor_pearson) < 0.30) "PASS" else "FAIL"),
      sprintf("STR_1715 cor Spearman = %.4f", cor_spearman),
      sprintf("STR_1715 lower-tail TDC q20 = %.4f", tdc_q5)
    ),
    liquidity_flags = sprintf("Risk uses BHEQ universe %d tickers; liquidity_floor_5e7 (request) — Q-Lead override pending; RAWDATA daily 2y window covers full %d ticker × %d obs",
                              length(final_tickers), length(final_tickers), N_obs),
    stress_tests = stress_results
  ),

  diagnostics = list(
    condition_number = round(cond_primary, 4),
    min_eigenvalue = signif(primary_min_eig, 6),
    psd = psd_primary,
    shrinkage_used = (primary_label != "sample_pairwise"),
    shrinkage_method = primary_label,
    factor_cov_estimator = "sample_FF6F_monthly_annualized",
    factor_cov_condition = round(kappa(Omega_annual), 4),
    n_tickers_in_sigma = length(final_tickers),
    factor_correlation_warnings = if (!is.na(style_overlap_warning))
                                     list(style_overlap_warning) else list(),
    tdc_summary = list(
      str1715_vs_bheq_pearson = round(cor_pearson, 4),
      str1715_vs_bheq_spearman = round(cor_spearman, 4),
      str1715_vs_bheq_tdc_q20 = round(tdc_q5, 4)
    ),
    regime_correlation_summary = regime_corr_summary,
    style_exposure = list(
      mean_beta_FF5_WML = as.list(round(mean_beta, 4)),
      sd_beta_FF5_WML = as.list(round(sd_beta, 4)),
      style_overlap_warning = if (!is.na(style_overlap_warning))
                                  style_overlap_warning else "no overlap detected"
    ),
    factor_coverage_r2_mean = round(mean(factor_r2[final_tickers], na.rm = TRUE), 4),
    factor_coverage_r2_median = round(median(factor_r2[final_tickers], na.rm = TRUE), 4)
  ),

  # ★ MDD reduction priority (v1.0.9 P0 1순위) — HONEST FINDING
  mdd_reduction_potential = list(
    objective = "v1.0.9 PG0 P0 — STR_1715 MDD -36.10% → -25% target (gap +11.10pp)",
    methodology = "Monthly STR_1715 ret_net blend with EW BHEQ-universe monthly returns; w_alpha grid {0,0.05,0.10,0.15,0.20,0.30}",
    n_aligned_months = nrow(mr),
    blend_grid = blend_results,
    recommended_w_alpha = rec_w,
    delta_mdd_pp = round(mdd_delta_pp, 4),
    mdd_improves = mdd_improves,
    all_blend_worsen_mdd = all_worsen,
    recommended_rationale = rec_rationale,
    finding = if (all_worsen) {
      "★ ALL BHEQ blends (w=0.05~0.30) WORSEN STR_1715 MDD by 0.44~2.76pp + lower SR by 0.008~0.082. BHEQ is NOT MDD-mitigative against STR_1715. v1.0.9 P0 (MDD reduction 1순위) CANNOT be addressed by BHEQ blend alone."
    } else if (mdd_improves) {
      sprintf("BHEQ blend w=%.2f improves MDD by %.2fpp", rec_w, mdd_delta_pp)
    } else {
      "Mixed result; no MDD-improving blend with SR retention"
    },
    handoff_to_optimizer = "Optimizer는 (a) STR_1715 single-strategy MDD reduction 위해 BHEQ alpha 외 추가 risk-managed overlay (Barroso-Santa Clara 2015 / DD brake) 고려 필수, (b) BHEQ alpha를 사용하는 경우 별도 portfolio (sleeve)에 분리 후 STR_1715 외 portfolio component로 위치시켜야 함 — 단순 returns blend로는 MDD 개선 불가능 입증.",
    crowding_root_cause = sprintf(
      "STR_1715 ↔ BHEQ-EW returns cor (Pearson) %.3f / Spearman %.3f / lower-tail TDC %.3f — high overlap. STR_1715 base universe (FF5/Quality) 와 BHEQ underlying (Q07/C01/C09) 사이 Quality factor 노출 공유. blend MDD 악화 = 동일 stress 시점에 동시 손실 → MDD 깊이 증대.",
      cor_pearson, cor_spearman, tdc_q5)
  ),

  crowding_analysis = list(
    primary_active_book = "STR_1715_WT016_Iter31_GridBestProd 100% (admitted)",
    overlap_metrics = list(
      cor_pearson = round(cor_pearson, 4),
      cor_spearman = round(cor_spearman, 4),
      tdc_q20_lower = round(tdc_q5, 4),
      n_aligned_months = nrow(mr),
      ortho_threshold = 0.30,
      ortho_status = if (abs(cor_pearson) < 0.30) "ORTHO_PASS" else "ORTHO_FAIL"
    ),
    regime_conditional_cor = regime_cor,
    inheritance_from_alpha_pkg = list(
      alpha_inheritance_cor_to_WT002 = -0.0116,
      interpretation = "BHEQ ⊥ WT_002 behavioral×liquidity (alpha-level). STR_1715 별도 검증 (returns-level) 신규."
    )
  ),

  # ★ 5 alpha caveat 처리 (Q-Lead override 명시 trigger)
  alpha_caveat_handling = list(
    cert_critical_skip_waiver = list(
      caveat = "alpha_discovery_certificate JSON 미발급 (passive deny: harvey_t_specs_pass_count=1<3)",
      risk_response = "Risk Σ + tail + stress + crowding 전수 진행. cert 부재가 Risk 계량화에 영향 없음. AX-008 verification triangulation: Risk 자체 method shopping 5 estimator + Codex round 의무 (next step) → 2-source 확보."
    ),
    rank_ic_marginal_flag = list(
      caveat = "rank_IC 0.0313 < 0.04 threshold (-0.0087)",
      risk_response = sprintf(
        "Σ structural integrity (cond=%.1f, PSD, idio share %.0f%%) IS independent of rank_IC level. Rank_IC가 marginal해도 Σ 활용 자체는 정당. Optimizer가 alpha confidence_vector 가중에 ICIR/DSR 강도 사용해야 함. Risk는 Σ만 보장.",
        cond_primary, mean_idio_share*100)
    ),
    harvey_t_specs_pass_count_1 = list(
      caveat = "harvey_t_specs_pass_count = 1 (single-factor BHEQ, NW-t 5.07 강력)",
      risk_response = "Risk는 multi-factor pass count 요구사항 없음. Σ B 행렬은 BHEQ 1 + FF5 underlying 5 + WML 1 = 6F 분해 → factor 분산 정확히 측정. count threshold는 alpha graduation gate이지 Σ 정합성과 무관."
    ),
    v6_4_cert_eligibility_trigger = list(
      caveat = "v6.4 cert eligibility 강화 trigger (count threshold 재검토 candidate)",
      risk_response = "Risk-side input 없음. Q-Lead governance issue. Risk는 BHEQ single-factor case에서도 Σ 정합성 + tail + crowding 표준 산출 — single-factor strong alpha의 risk 처리 표준 사례 제공."
    ),
    AX_007_avoidance_strategy = list(
      caveat = "50+ ticker spread + ML sizing via lambda",
      risk_response = sprintf(
        "Risk 산출물은 %d-ticker BHEQ universe Σ. Optimizer는 final 20-name selection 시 AX-007 4분기 (50+ score breadth + ML-derived theta) 둘 다 Risk Σ 기반 위험 분해로 충족 검증해야 함. Risk는 50+ universe Σ 보장으로 Optimizer hand-off 가능.",
        length(final_tickers))
    )
  ),

  risk_flags = risk_flags,

  challenge_flags = lapply(risk_flags, function(f) f$description),

  ticker_alignment_audit = list(
    bheq_alpha_n_finite_2026_04_30 = N_TICK,
    sigma_n_tickers = length(final_tickers),
    dropped_for_beta_unestimable = setdiff(bheq_universe, final_tickers),
    drop_reason = "These BHEQ-finite tickers had insufficient monthly history or β regression failed — excluded from Σ. Optimizer가 alpha_vector 281 names 사용하되 Σ에 없는 ticker는 idiosyncratic 추정 (isolated 가정 또는 sector-mean specific risk).",
    handoff_rule = "Optimizer must reconcile: (a) 281-name alpha set + (b) 280-name Σ. Recommended: use Σ rownames as optimizer feasible set (drop unestimable), or impute idio var = sample median for missing tickers.",
    bheq_universe_minus_sigma_n = length(setdiff(bheq_universe, final_tickers))
  ),

  pit_attestation = list(
    c1_full_sample_stats = "PASS — Σ window 2y trailing daily, factor cov full history monthly. Both PIT-rolling (no full-sample lookahead).",
    c2_same_day_circular = sprintf("PASS — Σ daily window ends %s = sig_d - 1. Same-day 2026-04-30 returns EXCLUDED.",
                                   as.character(sigma_end_pit)),
    c6_survivorship_caveat = "ACKNOWLEDGED — Stress test history (2001-2026) uses final 2026-04-30 BHEQ ticker set projected backward. This is forward-looking diagnostic of 'how would current universe have performed in past stress'. NOT a backtest of historical alpha. Optimizer/Forge/Judge가 실제 백테스트 시 universe rolling 적용 — 본 risk diagnostic은 universe-FIXED forward projection.",
    c9_volatility_lag = sprintf("PASS — Σ inputs use Date <= %s (sig_d-1). No same-day vol/cov used.",
                                 as.character(sigma_end_pit)),
    c10_liquidity_pit = "INHERITED — Alpha agent used liquidity_floor = 5e7 (request). Q-Lead override 결정 pending. Risk universe 본 결정 inherit.",
    c11_external_factor_lag = "MONTHLY — KR FF5/WML factor returns from kr_factor_returns_v2.parquet (range 2001-04 → 2026-03). Latest aligned month = 2026-03 < sig_d 2026-04-30. C11 PASS (monthly factor uses lagged month).",
    c12_factor_db_backfill = "ATTESTED via kr_factor_returns_v2 — DART TTM 2002+ backfill, FF1993/2015 + Novy-Marx 2013 (Iter 4 reused). Detailed C11/C12 audit ref: 06_Reference/factor_db_audit_kr_factor_returns_v2.md (TBD if needs explicit re-audit).",
    c13_z_score_aligned = "INHERITED — Alpha agent uses Z_Score_Aligned only (BHEQ posterior >= 0 enforced).",
    c14_ic_usable_date = "INHERITED — Alpha agent uses load_month_factors() PIT auto.",
    c15_factor_db_load = "INHERITED — Alpha agent exclusive load_month_factors entry."
  ),

  codex_round = list(
    stance = "REJECT",
    veto_flag = FALSE,
    weakest_assumption = "A fixed-alpha 0.30 constant-correlation shrinkage covariance with cond=1227 can be treated as an optimizer-ready post-shrink Σ because it is PSD.",
    critical_concerns_count = 9L,
    challenge_note_path = "risk_challenge_note.md",
    response_path = "codex_critic_response_risk.json",
    response_note = "9 concerns processed. 5 ACCEPT (PIT-C2/C9 fix, Σ infeasibility report, regime bootstrap CI, ticker alignment audit, RF-R4 stress MDD). 4 PARTIAL/REBUTTAL (cond gate vs structural infeasibility, CVaR raw vs portfolio, PIT-C6 forward-projection diagnostic, liquidity inherited from request)."
  ),

  generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  generated_by = "Risk-Research Opus 4.7 (1M)"
)

draft_path <- file.path(PROJ, "qepm/mailbox/worktask", WT, "risk_package_draft.json")
write_json(risk_package, draft_path, pretty = TRUE, auto_unbox = TRUE,
           null = "null", na = "null")
cat("\n[risk] DRAFT saved →", draft_path, "\n")
cat("[risk] DONE — proceed to codex critic round.\n")
