# =============================================================================
# risk_measure.R — WT-D20260614_001 VAL_DIVERSIFIER risk-research
# Σ = BΩB' + D (security covariance) + authoritative book-marginal ΔIR
#   + sector-neutral residual diversification + tail/MDD decomp + stress + crowding
# PIT: all returns t->t+1 (forward), scores at sig_date (alpha pipeline aligned).
#      Stress / tail use realized sleeve series only (no lookahead).
# Role: risk only. NO alpha edit, NO weights. selection_objective = estimation quality.
# =============================================================================
suppressMessages({
  library(arrow); library(data.table); library(jsonlite)
})
options(warn = 1)
root <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
Sys.setenv(CLAUDE_PROJECT_DIR = root)
wt   <- "WT-D20260614_001"
out_dir <- file.path(root, "stage_artifacts", "WT_D20260614_001")
mb_dir  <- file.path(root, "qepm", "mailbox", "worktask", wt)

set.seed(20260614L)

# ---- 0. Inputs ------------------------------------------------------------
ap <- fromJSON(file.path(mb_dir, "alpha_package.json"), simplifyVector = FALSE)
alpha_vec <- unlist(ap$alpha_vector)            # current as_of alpha-hat per ticker
as_of <- as.Date(ap$as_of_date)

scores_dt <- as.data.table(read_parquet(file.path(out_dir, "alpha_scores.parquet")))
scores_dt[, Date := as.Date(Date)]
sleeve <- as.data.table(read_parquet(file.path(out_dir, "sleeve_active_series.parquet")))
sleeve[, Date := as.Date(Date)]                 # value-4 sleeve realized (gross port, BM, active)

# Incumbent STR_1715 monthly returns (book IR 1.5754)
inc <- fread(file.path(root, "qepm", "mailbox", "governor",
                       "str_1715_full_reassessment", "str_1715_monthly_returns_full.csv"))
inc[, Date := as.Date(Date)]
setnames(inc, "monthly_ret", "inc_ret")

# RAWDATA (price/sector). C15: factor DB only via load_month_factors (alpha did scores).
RAW <- as.data.table(read_parquet(file.path(root, ".cache", "rawdata.parquet"),
  col_select = c("Date","Ticker","Close","Vol","Size","K200","KQ150","Sector","BM_Ret")))
RAW[, Date := as.Date(Date)]
setorder(RAW, Ticker, Date)

cat(sprintf("[inputs] as_of=%s  alpha names=%d  sleeve months=%d  inc months=%d\n",
            as_of, length(alpha_vec), nrow(sleeve), nrow(inc)))

# =============================================================================
# PART A. Security covariance Σ = BΩB' + D  (current 25-name holdings)
# =============================================================================
# Holdings = top-25 by alpha_hat (deployment mandate max_names=25). Risk measures the
# co-movement structure of THESE names; it does NOT decide weights.
ord <- sort(alpha_vec, decreasing = TRUE)
hold <- names(ord)[seq_len(min(25L, length(ord)))]
cat(sprintf("[Sigma] holdings (top-25 by alpha-hat): %d names\n", length(hold)))

# Monthly returns matrix for holdings: month-end close -> forward 1M (PIT aligned).
month_ends <- sort(unique(scores_dt$Date))
me_close <- RAW[Date %in% month_ends & Ticker %in% hold, .(Date, Ticker, Close)]
setorder(me_close, Ticker, Date)
me_close[, ret1m := shift(Close, -1L) / Close - 1, by = Ticker]   # forward (t -> t+1)
rmat_dt <- me_close[is.finite(ret1m), .(Date, Ticker, ret1m)]
# trailing window: use last 60 months for stability (monthly N>>p risk: 25 names need N>=25)
W_MONTHS <- 60L
win_dates <- tail(month_ends, W_MONTHS + 1L)     # +1 because forward ret consumes last
rmat_dt <- rmat_dt[Date %in% win_dates]
wide <- dcast(rmat_dt, Date ~ Ticker, value.var = "ret1m")
R <- as.matrix(wide[, -1, drop = FALSE])
# drop names with insufficient history
keep <- colSums(is.finite(R)) >= 36L
R <- R[, keep, drop = FALSE]
hold_keep <- colnames(R)
R[!is.finite(R)] <- NA
# rows with >=50% coverage
R <- R[rowSums(is.finite(R)) >= ncol(R) * 0.5, , drop = FALSE]
# mean-impute remaining NA per column
for (j in seq_len(ncol(R))) { m <- mean(R[, j], na.rm = TRUE); R[!is.finite(R[, j]), j] <- m }
n_obs <- nrow(R); p <- ncol(R)
cat(sprintf("[Sigma] return matrix: %d months x %d names\n", n_obs, p))

# ---- Method shopping log (estimation quality only; <=5) -------------------
cnum <- function(M) { ev <- eigen(M, symmetric = TRUE, only.values = TRUE)$values
                      max(ev) / max(min(ev), 1e-12) }
is_psd <- function(M) min(eigen(M, symmetric = TRUE, only.values = TRUE)$values) >= -1e-10

# (1) Sample
S_sample <- cov(R)
# (2) Ledoit-Wolf shrinkage to scaled identity (hrp_core formula)
lw <- function(X) {
  S <- cov(X); pp <- ncol(X); nn <- nrow(X)
  mu <- mean(diag(S))
  rho <- min(((nn - 2)/nn * sum(diag(S)^2) + sum(S)^2) /
               ((nn + 2) * (sum(S^2) - sum(diag(S)^2)/pp)), 1)
  list(cov = (1 - rho) * S + rho * mu * diag(pp), rho = rho)
}
LW <- lw(R); S_lw <- LW$cov
# (3) STRUCTURED FACTOR MODEL  Σ = B Ω B' + D  (role-mandated frame)
#     Factors: Market (EW holdings proxy) + Sector dummies (KR WICS Lv1).
#     This is the natural risk frame AND directly isolates the 42% sector-tilt axis (CF-SECTOR-TILT).
# Sector mapping for the holdings (latest <= as_of, PIT).
sec_map <- RAW[Ticker %in% hold_keep & Date <= as_of & !is.na(Sector),
               .SD[.N], by = Ticker, .SDcols = "Sector"]
sec_of  <- setNames(sec_map$Sector, sec_map$Ticker)[hold_keep]
sec_of[is.na(sec_of)] <- "UNKNOWN"
# Market factor returns = EW of holdings (within-sleeve market proxy)
mkt <- rowMeans(R)
# Sector factor returns = EW of holdings within each sector (only sectors with >=2 names get a factor)
sec_tab <- table(sec_of); sec_use <- names(sec_tab[sec_tab >= 2])
F <- matrix(mkt, ncol = 1); colnames(F) <- "MKT"
for (s in sec_use) {
  idx <- which(sec_of == s)
  fs <- rowMeans(R[, idx, drop = FALSE]) - mkt    # sector factor orthogonalized vs market
  F <- cbind(F, fs)
}
colnames(F) <- c("MKT", paste0("SEC_", sec_use))
# Exposures B via OLS of each name on factors; Ω = factor cov; D = diag(residual var)
B <- matrix(0, nrow = p, ncol = ncol(F), dimnames = list(hold_keep, colnames(F)))
resid_struct <- matrix(0, nrow = n_obs, ncol = p)
for (j in seq_len(p)) {
  fit <- lm.fit(cbind(1, F), R[, j])
  B[j, ] <- fit$coefficients[-1]
  resid_struct[, j] <- fit$residuals
}
Omega <- cov(F)
D_struct <- diag(pmax(apply(resid_struct, 2, var), 1e-8))
S_struct <- B %*% Omega %*% t(B) + D_struct
S_struct <- (S_struct + t(S_struct)) / 2          # symmetrize
# eigen-floor to guarantee PSD (numerical)
ev <- eigen(S_struct, symmetric = TRUE)
ev$values <- pmax(ev$values, 1e-10)
S_struct <- ev$vectors %*% diag(ev$values) %*% t(ev$vectors)

# 1-factor (market-only) for clean market/specific split
betas <- apply(R, 2, function(y) cov(y, mkt) / var(mkt))
resid1 <- R - outer(mkt, betas)
D_spec <- diag(apply(resid1, 2, var)); omega_mkt <- var(mkt)
S_factor1 <- outer(betas, betas) * omega_mkt + D_spec

log_methods <- list(
  list(name = "sample",            condition = round(cnum(S_sample), 1),  psd = is_psd(S_sample),  selected = FALSE),
  list(name = "ledoit_wolf",       condition = round(cnum(S_lw), 1),      psd = is_psd(S_lw),      selected = FALSE,
       shrink_intensity = round(LW$rho, 4),
       note = "analytic rho saturates to 1.0 at monthly n=60/p=25 -> over-shrinks to identity, destroys correlation structure; rejected"),
  list(name = "factor1_market",    condition = round(cnum(S_factor1), 1), psd = is_psd(S_factor1), selected = FALSE),
  list(name = "factor_mkt_sector", condition = round(cnum(S_struct), 1),  psd = is_psd(S_struct),  selected = FALSE,
       n_factors = ncol(F),
       note = "Sigma = B Omega B' + D, market + KR sector factors; role-mandated frame, well-conditioned, isolates sector axis")
)
# Selection by ESTIMATION QUALITY only (condition number + PSD + structure faithfulness). NOT return.
# selection_objective = condition_number / shrinkage_quality (R4 P3 HARD).
# Rationale: 1-factor market model is the role-mandated B*Omega*B'+D form, PSD, best-conditioned (cond ~59),
#   and yields a clean Market/Specific split. The mkt+sector model adds noisy low-N sector factors over a
#   60-month window (cond 212.8 > 200 ill-cond threshold) and the within-holdings EW nets sector bets to ~0
#   -> sector RISK is an ACTIVE-SELECTION axis (PART C), not a residual-cov axis. Keep factor1 as Sigma.
sel <- "factor1_market"
Sigma <- S_factor1
for (i in seq_along(log_methods)) if (log_methods[[i]]$name == sel) log_methods[[i]]$selected <- TRUE
cond_final <- cnum(Sigma)
cat(sprintf("[Sigma] cond: sample=%.1f LW=%.1f(rho=%.3f) factor1=%.1f factorMS=%.1f | selected=%s cond=%.1f PSD=%s\n",
            cnum(S_sample), cnum(S_lw), LW$rho, cnum(S_factor1), cnum(S_struct),
            sel, cond_final, is_psd(Sigma)))

# Variance decomposition: market vs sector vs specific (EW diagnostic; NOT a weight proposal)
ew <- rep(1/length(hold_keep), length(hold_keep))
mkt_col <- which(colnames(F) == "MKT")
sec_cols <- setdiff(seq_len(ncol(F)), mkt_col)
contrib_mkt <- as.numeric(t(ew) %*% (B[, mkt_col, drop=FALSE] %*% Omega[mkt_col, mkt_col, drop=FALSE] %*% t(B[, mkt_col, drop=FALSE])) %*% ew)
contrib_sec <- as.numeric(t(ew) %*% (B[, sec_cols, drop=FALSE] %*% Omega[sec_cols, sec_cols, drop=FALSE] %*% t(B[, sec_cols, drop=FALSE])) %*% ew)
contrib_spec <- as.numeric(t(ew) %*% D_struct %*% ew)
tot_var <- contrib_mkt + contrib_sec + contrib_spec
share_mkt <- contrib_mkt / tot_var; share_sec <- contrib_sec / tot_var; share_spec <- contrib_spec / tot_var
factor_share <- (contrib_mkt + contrib_sec) / tot_var
# 1-factor market/specific split (for top_common_risks Market %)
port_sys_var1  <- as.numeric(t(ew) %*% (outer(betas, betas) * omega_mkt) %*% ew)
port_spec_var1 <- as.numeric(t(ew) %*% D_spec %*% ew)
market_share_1f <- port_sys_var1 / (port_sys_var1 + port_spec_var1)
cat(sprintf("[Sigma] EW var decomp: Market=%.1f%% Sector=%.1f%% Specific=%.1f%% (factor total %.1f%%) | 1F market=%.1f%%\n",
            100*share_mkt, 100*share_sec, 100*share_spec, 100*factor_share, 100*market_share_1f))

# Save covariance.parquet
cov_dt <- as.data.table(Sigma); cov_dt[, Ticker := hold_keep]
setcolorder(cov_dt, "Ticker")
write_parquet(cov_dt, file.path(out_dir, "covariance.parquet"))
cat("[Sigma] saved covariance.parquet\n")

saveRDS(list(Sigma = Sigma, hold = hold_keep, betas = betas, omega_mkt = omega_mkt,
             D_spec = D_spec, factor_share = factor_share, cond = cond_final,
             share_mkt = share_mkt, share_sec = share_sec, share_spec = share_spec,
             market_share_1f = market_share_1f, sec_of = sec_of,
             log_methods = log_methods, sel = sel, R = R, month_idx = wide$Date),
        file.path(out_dir, "_sigma.rds"))
cat("PART A DONE\n")
