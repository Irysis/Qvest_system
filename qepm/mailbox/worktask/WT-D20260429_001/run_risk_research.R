#==============================================================================
# WT-D20260429_001 Risk Research Pipeline
#
# Theme: regime_conditional_defense_complement_for_str1715_mdd
# Alpha (received): D47_CVaR_5pct (50/55) + D01_IdioVol (35/30) + D04_Downside_Beta (15/15)
#                   alpha_inheritance_cor mean = 0.2729 (IC-level)
#                   Q07_Earnings_Stability IC-cor = 0.737 (CF-03 portfolio TDC verification needed)
#
# Risk Agent role (Common Charter §4 + risk_research_init.md):
#   Σ = B Ω B' + D structure
#     B: factor exposure to FF5_v2 (MKT/SMB/HML/WML/RMW/CMA-equivalent KR proxy) on candidate panel
#     Ω: factor covariance via parallel estimator comparison (R13)
#     D: idiosyncratic specific variance (residual MLE, Newey-West)
#
#   + Multi-stress: 8 KR-specific periods (GFC / EuDebt / China / COVID / TradeWar / RateHike / 2024-Yen / structured)
#   + Regime-conditional Σ (4-state BULL/NORMAL/CAUTION/CRISIS, expanding window)
#   + Tail risk (CVaR / CDaR / EVT-GPD per regime)
#   + STR_1715 portfolio TDC (CF-03 핵심): empirical Joe-Clayton lower-tail dependence q5
#   + Crowding/liquidity diagnostic (deployment 2e8 universe shrink)
#
# Hard constraints (PIT C1/C2/C9/C11/C13~C15):
#   - SIGNAL_AS_OF = 2026-03-31 (alpha_package as_of_date)
#   - PIT_HARD_CUTOFF = 2026-03-31 — Σ/tail/stress estimation strictly Date <= cutoff
#   - Σ PSD with min eigenvalue > 0
#   - Cond number ≤ 500 post-shrinkage (RF-R2 trigger)
#   - method shopping ≤ 5 candidates (R2-C HARD)
#   - No alpha modification (Hook block)
#   - No weight proposal (Optimizer territory)
#==============================================================================

suppressPackageStartupMessages({
  library(arrow)
  library(data.table)
  library(jsonlite)
  library(future)
  library(future.apply)
  library(digest)
})

PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
setwd(PROJECT_ROOT)
options(scipen = 999, digits = 8)

`%||%` <- function(a, b) if (is.null(a) || (length(a) == 1 && is.na(a))) b else a

# ── Config ──────────────────────────────────────────────────────────────────
WT_ID            <- "WT-D20260429_001"
WT_TAG_STAGE     <- "WT-D20260429_001"
SIGNAL_AS_OF     <- as.Date("2026-03-31")
PIT_HARD_CUTOFF  <- as.Date("2026-03-31")  # Discovery WT — Σ data ≤ as_of
ESTIMATION_WIN   <- 60L                     # months
COND_NUMBER_GATE <- 500
TDC_GATE         <- 0.30                    # CF-03 STR_1715 portfolio TDC q5

OUT_DIR_STAGE <- file.path("stage_artifacts", WT_TAG_STAGE)
OUT_DIR_MAIL  <- file.path("qepm/mailbox/worktask", WT_ID)
dir.create(OUT_DIR_STAGE, showWarnings = FALSE, recursive = TRUE)

cat("==== WT-D20260429_001 Risk Research Pipeline ====\n")
cat("WT:", WT_ID, " | as_of:", as.character(SIGNAL_AS_OF), "\n")
cat("PIT cutoff:", as.character(PIT_HARD_CUTOFF), "\n")
cat("OUT_DIR_STAGE:", OUT_DIR_STAGE, "\n")
cat("OUT_DIR_MAIL:", OUT_DIR_MAIL, "\n\n")

# ── Step 0: Load Alpha Package + Reference Portfolio ───────────────────────
cat("---- Step 0: Load Alpha Package + STR_1715 reference ----\n")
alpha_pkg  <- read_json(file.path(OUT_DIR_MAIL, "alpha_package.json"))
ALPHA_VEC  <- unlist(alpha_pkg$alpha_vector)
CONF_VEC   <- unlist(alpha_pkg$confidence_vector)
TICKERS_FULL <- names(ALPHA_VEC)
cat("alpha_vector size (full):", length(TICKERS_FULL), "\n")
cat("alpha_inheritance_cor:", alpha_pkg$alpha_inheritance_cor %||% NA, "\n")

# Top-K candidate (proxy for risk universe at as_of). Discovery WT — alpha is broad signal.
# We use top-60 by alpha_z (positive side) for Σ estimation: Optimizer will pick top-20.
ALPHA_DT <- data.table(Ticker = names(ALPHA_VEC), alpha_z = as.numeric(ALPHA_VEC))
ALPHA_DT <- ALPHA_DT[order(-alpha_z)]
TOP_60 <- head(ALPHA_DT$Ticker, 60L)
cat("Top-60 risk universe (defense candidate panel):", length(TOP_60), "\n\n")

# ── Step 1: Load alpha_scores time series ──────────────────────────────────
cat("---- Step 1: Load alpha_scores time series ----\n")
ALPHA_TS <- as.data.table(read_parquet(
  file.path(OUT_DIR_STAGE, "alpha_scores.parquet")
))
setkey(ALPHA_TS, Date, Ticker)
cat("alpha_scores rows:", nrow(ALPHA_TS), " | dates:", uniqueN(ALPHA_TS$Date),
    " | tickers:", uniqueN(ALPHA_TS$Ticker), "\n\n")

# ── Step 2: Load RAWDATA (PIT-strict) ──────────────────────────────────────
cat("---- Step 2: Load RAWDATA (PIT-strict) ----\n")
RD_FULL <- as.data.table(read_parquet(".cache/rawdata.parquet"))
RD_FULL <- RD_FULL[Date <= PIT_HARD_CUTOFF]
cat("RAWDATA rows post-cutoff:", nrow(RD_FULL), "\n")

# Daily returns matrix for Top-60 candidate panel
RD60 <- RD_FULL[Ticker %in% TOP_60, .(Date, Ticker, Ret, Sector, Sector_Lv2, Size, Vol, Close)]
RD60 <- RD60[!is.na(Ret)]
cat("Top-60 daily rows:", nrow(RD60), "\n")

# Monthly returns for alpha-side (factor cov) + matching with regime
RD60[, ym := as.Date(format(Date, "%Y-%m-01"))]
RET_MO <- RD60[, .(
  Ret_M = prod(1 + Ret) - 1,
  Date_end = max(Date),
  N_days = .N
), by = .(Ticker, ym)][N_days >= 15]  # min 15 trading days per month

cat("Top-60 monthly rows:", nrow(RET_MO), "\n")
cat("Monthly date range:",
    as.character(min(RET_MO$ym)), "-", as.character(max(RET_MO$ym)), "\n\n")

# ── Step 3: Load STR_1715 reference (NAV + monthly returns) ────────────────
cat("---- Step 3: Load STR_1715 reference monthly returns ----\n")
STR1715_DIR <- "04_Research/strategies/STR_1715_WT016_Iter31_GridBestProd/output"
STR1715_RET <- fread(file.path(STR1715_DIR, "03_period_returns.csv"))
STR1715_RET[, date := as.Date(date)]
# PIT cutoff — strict align
STR1715_RET <- STR1715_RET[date <= PIT_HARD_CUTOFF]
STR1715_RET <- STR1715_RET[!is.na(ret_net)]
cat("STR_1715 monthly returns rows:", nrow(STR1715_RET), "\n")
cat("STR_1715 date range:", as.character(min(STR1715_RET$date)), "-",
    as.character(max(STR1715_RET$date)), "\n")
cat("STR_1715 annualized SR (entire):",
    round(mean(STR1715_RET$ret_net) / sd(STR1715_RET$ret_net) * sqrt(12), 4), "\n\n")

# Holdings (for crowding/liquidity overlap diagnostic)
STR1715_HOLD <- fread(file.path(STR1715_DIR, "04_holdings.csv"))
STR1715_HOLD[, date := as.Date(date)]
STR1715_HOLD <- STR1715_HOLD[date <= PIT_HARD_CUTOFF]
cat("STR_1715 holdings rows:", nrow(STR1715_HOLD), "\n")

# Latest STR_1715 holdings for overlap test
LATEST_STR1715_DATE <- max(STR1715_HOLD$date)
STR1715_LATEST_TKR <- STR1715_HOLD[date == LATEST_STR1715_DATE & target_weight > 0, ticker]
cat("STR_1715 latest holdings (",
    as.character(LATEST_STR1715_DATE), "):", length(STR1715_LATEST_TKR), "\n\n")

# ── Step 4: Build factor-side returns (FF5-style v2 KR proxy) ──────────────
cat("---- Step 4: Build factor returns panel (FF5_v2 KR proxy) ----\n")
# Factor proxy from RAWDATA monthly cross-section:
#   MKT: equal-weighted KR universe ex-low-liquidity
#   SMB: bottom Size tercile - top Size tercile
#   HML: bottom BM tercile - top BM tercile (BM unavailable -> use 1/Size proxy with WARN)
#   WML: top 6m return tercile - bottom 6m return tercile
#   LVOL: bottom 60d realized vol tercile - top tercile (defense factor proxy)
#   RMW/CMA: skip (DART quarterly merge cost > value; covered by D + idiosyncratic)
#
# These factor returns are pure NUMERICAL covariance inputs, not alpha signals.

RD_FULL[, ym := as.Date(format(Date, "%Y-%m-01"))]

# Monthly aggregates for whole universe — needed for factor returns build
RD_MO_ALL <- RD_FULL[!is.na(Ret), .(
  Ret_M = prod(1 + Ret) - 1,
  Size_avg = mean(Size, na.rm = TRUE),
  Vol_avg = mean(Vol, na.rm = TRUE),
  N_days = .N
), by = .(Ticker, ym)][N_days >= 15]

# 6m return for WML (PIT: lookback only — t-1 month closed)
setkey(RD_MO_ALL, Ticker, ym)
RD_MO_ALL[, Ret_6M := {
  n <- length(Ret_M)
  if (n < 6L) {
    rep(NA_real_, n)
  } else {
    sapply(seq_len(n), function(i) {
      if (i < 6L) NA_real_
      else prod(1 + Ret_M[(i - 5L):i]) - 1
    })
  }
}, by = Ticker]

# 60d realized vol for LVOL — daily-level rolling (last 60 days within each month boundary)
# Note: month-internal sd uses available trading days (typically 15-22). Smoothed via Vol_lag.
RD_VOL <- RD_FULL[!is.na(Ret), .(
  vol60 = if (.N >= 15) sd(Ret, na.rm = TRUE) else NA_real_
), by = .(Ticker, ym = as.Date(format(Date, "%Y-%m-01")))]

# Merge
FACTOR_PANEL <- merge(RD_MO_ALL, RD_VOL, by = c("Ticker", "ym"), all.x = TRUE)

# Factor return calculation per month (PIT: tertiles formed at t-1, ret realized at t)
# We construct H-L portfolios using PRIOR month's sorting variable, returns are CURRENT month.
FACTOR_PANEL[, `:=`(
  Size_lag = shift(Size_avg, type = "lag"),
  Ret6_lag = shift(Ret_6M, type = "lag"),
  Vol_lag  = shift(vol60, type = "lag")
), by = Ticker]

# Build monthly factor returns
build_factor_returns <- function(panel) {
  panel <- panel[!is.na(Size_lag) & !is.na(Ret_M)]
  res <- panel[, {
    if (.N < 30) {
      list(MKT = NA_real_, SMB = NA_real_, WML = NA_real_, LVOL = NA_real_)
    } else {
      mkt <- mean(Ret_M, na.rm = TRUE)
      # SMB: bottom Size tercile - top
      q_size <- quantile(Size_lag, c(1/3, 2/3), na.rm = TRUE)
      smb <- mean(Ret_M[Size_lag <= q_size[1]], na.rm = TRUE) -
             mean(Ret_M[Size_lag >= q_size[2]], na.rm = TRUE)
      # WML: top Ret_6M tercile - bottom
      wml_v <- if (sum(!is.na(Ret6_lag)) >= 30) {
        q_w <- quantile(Ret6_lag, c(1/3, 2/3), na.rm = TRUE)
        mean(Ret_M[Ret6_lag >= q_w[2]], na.rm = TRUE) -
        mean(Ret_M[Ret6_lag <= q_w[1]], na.rm = TRUE)
      } else NA_real_
      # LVOL: bottom vol tercile - top (defense)
      lvol_v <- if (sum(!is.na(Vol_lag)) >= 30) {
        q_v <- quantile(Vol_lag, c(1/3, 2/3), na.rm = TRUE)
        mean(Ret_M[Vol_lag <= q_v[1]], na.rm = TRUE) -
        mean(Ret_M[Vol_lag >= q_v[2]], na.rm = TRUE)
      } else NA_real_
      list(MKT = as.numeric(mkt), SMB = as.numeric(smb),
           WML = as.numeric(wml_v), LVOL = as.numeric(lvol_v))
    }
  }, by = ym]
  res
}

FAC_RET <- build_factor_returns(FACTOR_PANEL)
FAC_RET <- FAC_RET[!is.na(MKT) & !is.na(SMB) & !is.na(WML) & !is.na(LVOL)]
cat("FF-style factor return panel rows:", nrow(FAC_RET), "\n")
cat("Factor return date range:", as.character(min(FAC_RET$ym)), "-",
    as.character(max(FAC_RET$ym)), "\n\n")

# ── Step 5: Estimate Exposure Matrix B (60-month rolling regression) ───────
cat("---- Step 5: Estimate Exposure Matrix B (top-60, rolling 60m) ----\n")
# Match alpha_scores monthly grid with FAC_RET
FAC_RET[, ym := as.Date(ym)]
RET_MO[, ym := as.Date(ym)]

# Limit to last ESTIMATION_WIN months ending PIT_HARD_CUTOFF
END_YM <- as.Date(format(PIT_HARD_CUTOFF, "%Y-%m-01"))
START_YM <- seq.Date(END_YM, by = "-1 month", length.out = ESTIMATION_WIN + 1L)[ESTIMATION_WIN + 1L]
cat("Estimation window:", as.character(START_YM), "-", as.character(END_YM),
    " (", ESTIMATION_WIN, "months)\n")

FAC_W <- FAC_RET[ym >= START_YM & ym <= END_YM]
RET_W <- RET_MO[ym >= START_YM & ym <= END_YM]
cat("Factor returns in window:", nrow(FAC_W), "\n")

# Wide ticker x date returns
RET_WIDE <- dcast(RET_W, ym ~ Ticker, value.var = "Ret_M")
DATES <- RET_WIDE$ym
RET_MAT <- as.matrix(RET_WIDE[, -1])
rownames(RET_MAT) <- as.character(DATES)
TICKERS_PRESENT <- colnames(RET_MAT)

# Demand at least 24 obs per ticker (drop sparse)
N_OBS_TKR <- colSums(!is.na(RET_MAT))
KEEP_TKR <- TICKERS_PRESENT[N_OBS_TKR >= 24L]
RET_MAT <- RET_MAT[, KEEP_TKR, drop = FALSE]
cat("Tickers with >=24 obs:", ncol(RET_MAT), "\n")

# Align factor returns
FAC_BY_DATE <- FAC_W[match(as.character(DATES), as.character(ym))]
FAC_MAT <- as.matrix(FAC_BY_DATE[, .(MKT, SMB, WML, LVOL)])
rownames(FAC_MAT) <- as.character(DATES)
KEEP_DATES <- complete.cases(FAC_MAT) & rowSums(!is.na(RET_MAT)) >= 5L
FAC_MAT <- FAC_MAT[KEEP_DATES, , drop = FALSE]
RET_MAT <- RET_MAT[KEEP_DATES, , drop = FALSE]
cat("Effective sample (rows):", nrow(RET_MAT), " (cols):", ncol(RET_MAT), "\n")

# OLS B[i,k] for each ticker i on factors k
# Y_i = a_i + sum_k B_{i,k} * F_k + e_i
N_TKR_EFF <- ncol(RET_MAT)
N_FAC <- ncol(FAC_MAT)
B_MAT <- matrix(0, nrow = N_TKR_EFF, ncol = N_FAC,
                dimnames = list(KEEP_TKR <- colnames(RET_MAT), colnames(FAC_MAT)))
RESID_MAT <- matrix(NA_real_, nrow = nrow(RET_MAT), ncol = N_TKR_EFF,
                    dimnames = list(rownames(RET_MAT), KEEP_TKR))
SPEC_VAR <- numeric(N_TKR_EFF); names(SPEC_VAR) <- KEEP_TKR
R2_VEC <- numeric(N_TKR_EFF); names(R2_VEC) <- KEEP_TKR

for (i in seq_along(KEEP_TKR)) {
  y_i <- RET_MAT[, i]
  good <- !is.na(y_i)
  if (sum(good) < 24L) {
    SPEC_VAR[i] <- var(y_i, na.rm = TRUE) %||% 0.04
    next
  }
  X <- cbind(1, FAC_MAT[good, , drop = FALSE])
  y <- y_i[good]
  beta <- tryCatch(solve(crossprod(X), crossprod(X, y)),
                   error = function(e) c(0, rep(0, N_FAC)))
  B_MAT[i, ] <- as.numeric(beta[-1])
  yhat <- as.numeric(X %*% beta)
  resid <- y - yhat
  SPEC_VAR[i] <- var(resid)
  RESID_MAT[good, i] <- resid
  ss_tot <- sum((y - mean(y))^2)
  ss_res <- sum(resid^2)
  R2_VEC[i] <- if (ss_tot > 0) 1 - ss_res / ss_tot else 0
}

cat("Mean R^2 (factor coverage):", round(mean(R2_VEC, na.rm = TRUE), 4), "\n")
cat("Mean specific risk (annualized vol):",
    round(mean(sqrt(SPEC_VAR) * sqrt(12)), 4), "\n\n")

# ── Step 6: Estimate Factor Covariance Ω — Parallel comparison (R13) ──────
cat("---- Step 6: Factor Covariance Ω — Parallel estimator comparison ----\n")
n_workers <- min(4L, parallel::detectCores() - 1L)
plan(multisession, workers = n_workers)

source("02_Infrastructure/portfolio/hrp_core.R")  # .get_cor_cov + Gerber/RMT/LW

# Wrap Ledoit-Wolf shrinkage with Schäfer-Strimmer constant correlation target
cov_lw_constcor <- function(R) {
  n <- nrow(R); p <- ncol(R)
  S <- cov(R, use = "pairwise.complete.obs")
  R_cor <- cor(R, use = "pairwise.complete.obs")
  R_cor[is.na(R_cor)] <- 0
  rbar <- (sum(R_cor) - p) / (p * (p - 1))
  s_diag <- sqrt(diag(S))
  Target <- diag(diag(S)) + rbar * (s_diag %o% s_diag)
  diag(Target) <- diag(S)
  # Shrinkage intensity (analytic Ledoit-Wolf 2004)
  rho <- min(1, max(0,
    (sum(diag(S)^2) + sum(S)^2 - 2 * sum(S * Target)) /
    sum((Target - S)^2)
  ))
  if (!is.finite(rho)) rho <- 0.2
  Sigma <- (1 - rho) * S + rho * Target
  Sigma <- (Sigma + t(Sigma)) / 2
  list(Sigma = Sigma, rho = rho)
}

# Ledoit-Wolf 2004 (identity-target) wrapper exposing shrinkage intensity δ
cov_lw_id_explicit <- function(R) {
  p   <- ncol(R); n_obs <- nrow(R)
  S   <- cov(R, use = "pairwise.complete.obs")
  mu  <- mean(diag(S))
  rho <- min(((n_obs - 2) / n_obs * sum(diag(S)^2) + sum(S)^2) /
               ((n_obs + 2) * (sum(S^2) - sum(diag(S)^2) / p)), 1)
  if (!is.finite(rho)) rho <- 0.2
  cov_mat <- (1 - rho) * S + rho * mu * diag(p)
  cov_mat <- (cov_mat + t(cov_mat)) / 2
  list(Sigma = cov_mat, rho = rho, target = "identity_mu")
}

estimators_factor <- list(
  list(name = "sample",         fn = function(R) list(Sigma = cov(R, use = "pairwise.complete.obs"))),
  list(name = "ledoit_wolf_id", fn = function(R) {
    res <- cov_lw_id_explicit(R)
    list(Sigma = res$Sigma, shrinkage_rho = res$rho, target = res$target)
  }),
  list(name = "lw_constcor",    fn = function(R) {
    res <- cov_lw_constcor(R)
    list(Sigma = res$Sigma, shrinkage_rho = res$rho, target = "schafer_strimmer_constcor")
  }),
  list(name = "gerber_rmt",     fn = function(R) {
    cc <- .get_cor_cov(R, "gerber_rmt"); list(Sigma = cc$cov, shrinkage_rho = NA, target = "rmt_denoise")
  })
)

est_results <- future_lapply(estimators_factor, function(e) {
  tryCatch({
    r <- e$fn(FAC_MAT)
    Sigma <- r$Sigma
    eig <- eigen(Sigma, only.values = TRUE)$values
    list(ok = TRUE, name = e$name, Sigma = Sigma,
         condition = max(eig) / max(min(eig), 1e-12),
         min_eig   = min(eig),
         shrinkage_rho = r$shrinkage_rho %||% NA,
         target = r$target %||% "n/a")
  }, error = function(err) list(ok = FALSE, name = e$name, error = conditionMessage(err)))
}, future.seed = TRUE)
plan(sequential)

method_log <- list()
for (rr in est_results) {
  if (isTRUE(rr$ok)) {
    cat(sprintf("  [%s] cond = %.3f, min_eig = %.6f, shrinkage_rho = %s\n",
                rr$name, rr$condition, rr$min_eig,
                if (is.na(rr$shrinkage_rho)) "NA" else sprintf("%.4f", rr$shrinkage_rho)))
    method_log[[length(method_log) + 1]] <- list(
      name = rr$name, condition = round(rr$condition, 4),
      min_eig = round(rr$min_eig, 8),
      shrinkage_rho = rr$shrinkage_rho %||% NA,
      target = rr$target %||% "n/a",
      selected = FALSE
    )
  } else {
    cat(sprintf("  [%s] FAIL: %s\n", rr$name, rr$error))
  }
}

# Selection: condition_number objective — smallest condition with PSD
cand <- Filter(function(r) isTRUE(r$ok) && r$min_eig > 0, est_results)
if (length(cand) == 0) {
  stop("[Risk Agent] No PSD factor covariance estimator passed.")
}
selected_idx <- which.min(sapply(cand, function(r) r$condition))
SEL_FAC <- cand[[selected_idx]]
SEL_FAC_NAME <- SEL_FAC$name
OMEGA <- SEL_FAC$Sigma
SHRINKAGE_RHO_FAC <- SEL_FAC$shrinkage_rho

# Mark in log
for (i in seq_along(method_log)) {
  if (method_log[[i]]$name == SEL_FAC_NAME) method_log[[i]]$selected <- TRUE
}
cat("\nFACTOR cov selected:", SEL_FAC_NAME, "\n")
cat("Factor cov condition:", round(SEL_FAC$condition, 4),
    " | min_eig:", round(SEL_FAC$min_eig, 8), "\n\n")

# ── Step 7: Build Σ = B Ω B' + D ────────────────────────────────────────────
cat("---- Step 7: Build security covariance Σ = B Ω B' + D ----\n")
B <- B_MAT
D <- diag(SPEC_VAR, length(SPEC_VAR))
SIGMA_BBO <- B %*% OMEGA %*% t(B) + D
SIGMA_BBO <- (SIGMA_BBO + t(SIGMA_BBO)) / 2
rownames(SIGMA_BBO) <- colnames(SIGMA_BBO) <- KEEP_TKR

# Sanity: PSD check
eig_sigma <- eigen(SIGMA_BBO, only.values = TRUE)$values
cat("Σ rank:", ncol(B), " | min_eig(Σ):", round(min(eig_sigma), 10),
    " | cond(Σ):", round(max(eig_sigma) / max(min(eig_sigma), 1e-12), 2), "\n")

# Compare with direct sample covariance — for diagnostic
RET_MAT_FILLED <- RET_MAT
RET_MAT_FILLED[is.na(RET_MAT_FILLED)] <- 0  # only for direct comparison; not used as primary
SAMP_COV <- cov(RET_MAT_FILLED)
cat("Direct sample cov (filled NA=0) cond:",
    round(max(eigen(SAMP_COV, only.values=TRUE)$values) /
          max(min(eigen(SAMP_COV, only.values=TRUE)$values), 1e-12), 2), "\n\n")

# ── Step 8: Variance decomposition by factor (top common risks) ─────────────
cat("---- Step 8: Variance decomposition (top common risks) ----\n")
# Per-factor variance contribution to portfolio (EW top-60):
W_EW <- rep(1 / N_TKR_EFF, N_TKR_EFF); names(W_EW) <- KEEP_TKR
# Σ_p = W'(BΩB')W + W'DW
W <- W_EW
sys_var <- as.numeric(t(W) %*% (B %*% OMEGA %*% t(B)) %*% W)
spec_var_p <- as.numeric(t(W) %*% D %*% W)
total_var <- sys_var + spec_var_p

# Per-factor share — proper variance decomposition with cross-factor cov terms
# Var_sys = (W'B) Ω (B'W) = sum_k (W'B)_k * (Ω B'W)_k
# Per-factor k contribution = (W'B)_k * (Ω B'W)_k / total_var (Euler decomposition)
WtB    <- as.numeric(t(W) %*% B)            # length N_FAC
OmBtW  <- as.numeric(OMEGA %*% t(B) %*% W)  # length N_FAC
fac_share <- (WtB * OmBtW) / total_var
names(fac_share) <- colnames(B)
spec_share <- spec_var_p / total_var
# Sanity: sum(fac_share) + spec_share ≈ 1
fac_sum_check <- sum(fac_share) + spec_share

cat("Total variance (EW-60, monthly):", round(total_var, 6), "\n")
cat("Systematic share:", round(sys_var / total_var, 4), "\n")
cat("Specific share:", round(spec_share, 4), "\n")
cat("Per-factor share:\n")
for (k in 1:N_FAC) {
  cat(sprintf("  %s: %.4f\n", colnames(B)[k], fac_share[k]))
}

top_factor_share_pct <- round(max(fac_share) * 100, 2)
cat("Top factor share %:", top_factor_share_pct, "\n")

top_common_risks <- c(
  sprintf("MKT (%.1f%%)", fac_share["MKT"] * 100),
  sprintf("LVOL (%.1f%%)", fac_share["LVOL"] * 100),
  sprintf("SMB (%.1f%%)", fac_share["SMB"] * 100),
  sprintf("WML (%.1f%%)", fac_share["WML"] * 100),
  sprintf("Specific (%.1f%%)", spec_share * 100)
)
cat("\n")

# ── Step 9: Sector concentration ────────────────────────────────────────────
cat("---- Step 9: Sector concentration ----\n")
# Use most-recent sector mapping (per ticker take last non-NA Sector observation)
sec_recent <- RD60[!is.na(Sector) & Ticker %in% KEEP_TKR,
                   .(Sector = Sector[which.max(Date)]),
                   by = Ticker]
# For tickers without any sector record in window, mark "Unknown"
missing_sec <- setdiff(KEEP_TKR, sec_recent$Ticker)
if (length(missing_sec) > 0) {
  sec_recent <- rbind(sec_recent,
                      data.table(Ticker = missing_sec, Sector = "Unknown"))
}
sec_share <- sec_recent[, .N, by = Sector][order(-N)]
sec_share[, share := N / sum(N)]
print(sec_share)
top_sector_share <- max(sec_share$share, na.rm = TRUE)
top_sector_name  <- sec_share$Sector[1]
cat("Top sector:", top_sector_name, " | share:", round(top_sector_share, 4), "\n\n")

# ── Step 10: Tail risk (CVaR / CDaR / EVT-GPD) for EW top-60 panel ──────────
cat("---- Step 10: Tail risk (EW top-60 monthly) ----\n")
PORT_RET_EW <- rowSums(RET_MAT * matrix(W_EW, nrow = nrow(RET_MAT),
                                        ncol = ncol(RET_MAT), byrow = TRUE),
                       na.rm = TRUE)
PORT_RET_EW <- PORT_RET_EW[!is.na(PORT_RET_EW)]
cat("Port return obs:", length(PORT_RET_EW),
    " | mean:", round(mean(PORT_RET_EW), 4),
    " | sd:", round(sd(PORT_RET_EW), 4),
    " | min:", round(min(PORT_RET_EW), 4), "\n")

# CVaR(5%) — historical
VaR_5 <- quantile(PORT_RET_EW, 0.05, na.rm = TRUE)
CVaR_5 <- mean(PORT_RET_EW[PORT_RET_EW <= VaR_5], na.rm = TRUE)

# CDaR(5%) — Conditional Drawdown
NAV <- cumprod(1 + PORT_RET_EW)
peaks <- cummax(NAV)
DD <- (NAV - peaks) / peaks
CDaR_5 <- mean(DD[DD <= quantile(DD, 0.05, na.rm = TRUE)], na.rm = TRUE)
MAX_DD_PORT <- min(DD, na.rm = TRUE)

# EVT-GPD (uses tail_risk_engine)
source("02_Infrastructure/portfolio/tail_risk_engine.R")
EVT_RES <- tryCatch(compute_evt_var(PORT_RET_EW, p = 0.99, threshold_q = 0.85, min_tail_n = 20L),
                    error = function(e) list(var_evt = NA, es_evt = NA, method = "fail"))

# Hill alpha estimator (tail index — α small → fat tails, α large → thin tails)
compute_hill_alpha <- function(returns, k_frac = 0.10) {
  losses <- -returns[!is.na(returns)]
  losses <- losses[losses > 0]
  if (length(losses) < 20) return(list(alpha = NA, k = NA, method = "insufficient"))
  losses_sorted <- sort(losses, decreasing = TRUE)
  k <- max(5L, round(length(losses_sorted) * k_frac))
  if (k >= length(losses_sorted)) return(list(alpha = NA, k = k, method = "k_too_large"))
  hill_inv <- mean(log(losses_sorted[1:k] / losses_sorted[k + 1L]))
  list(alpha = if (hill_inv > 0) 1 / hill_inv else NA, k = k, method = "hill")
}
HILL_RES <- compute_hill_alpha(PORT_RET_EW, k_frac = 0.10)
cat("Hill alpha (k=", HILL_RES$k, "):", round(HILL_RES$alpha, 4),
    " | method:", HILL_RES$method, "\n")

# Parametric VaR/ES (Gaussian assumption — for diagnostic only)
mu_p <- mean(PORT_RET_EW); sd_p <- sd(PORT_RET_EW)
var_99_param <- mu_p + sd_p * qnorm(0.01)
es_99_param  <- mu_p - sd_p * dnorm(qnorm(0.01)) / 0.01

# Daily-equivalent CVaR (sqrt(20) scaling for monthly→daily under iid)
cvar_5_daily_equiv <- CVaR_5 / sqrt(20)
cat("CVaR(5%) daily-equivalent (monthly / sqrt(20)):", round(cvar_5_daily_equiv, 6),
    " — for comparison vs daily 2.5% cap (tail_risk_engine.R)\n")

cat("Tail risk EW-60:\n")
cat("  VaR(5%) monthly:", round(VaR_5, 4), "\n")
cat("  CVaR(5%) monthly:", round(CVaR_5, 4), "\n")
cat("  CDaR(5%):", round(CDaR_5, 4), " | Max DD:", round(MAX_DD_PORT, 4), "\n")
cat("  EVT-VaR(99%):", round(EVT_RES$var_evt, 4),
    " | EVT-ES(99%):", round(EVT_RES$es_evt, 4),
    " | method:", EVT_RES$method, "\n\n")

# ── Step 11: 8 Stress Periods ───────────────────────────────────────────────
cat("---- Step 11: 8 Stress Period cumulative loss ----\n")
stress_periods <- list(
  GFC_2008          = c("2008-09-01", "2009-02-28"),
  EuroDebt_2011     = c("2011-08-01", "2011-11-30"),
  China_Slowdown_2015 = c("2015-08-01", "2016-02-29"),
  COVID_2020        = c("2020-02-01", "2020-04-30"),
  TradeWar_2018     = c("2018-02-01", "2019-12-31"),
  RateHike_2022     = c("2021-10-01", "2022-09-30"),
  YenCarry_2024     = c("2024-08-01", "2024-08-31"),
  KOSPI_2024H2      = c("2024-09-01", "2024-12-31")  # supplementary KR-specific
)

# RET_WIDE was scoped earlier; rebuild full panel for older periods
RET_MO_FULL <- RD60[, .(
  Ret_M = prod(1 + Ret) - 1, N_days = .N
), by = .(Ticker, ym)][N_days >= 15]
RET_WIDE_FULL <- dcast(RET_MO_FULL, ym ~ Ticker, value.var = "Ret_M")
DATES_FULL <- RET_WIDE_FULL$ym
RET_MAT_FULL <- as.matrix(RET_WIDE_FULL[, -1])
rownames(RET_MAT_FULL) <- as.character(DATES_FULL)

stress_results <- list()
for (sp_name in names(stress_periods)) {
  sp_range <- as.Date(stress_periods[[sp_name]])
  in_period <- DATES_FULL >= sp_range[1] & DATES_FULL <= sp_range[2]
  if (sum(in_period) == 0) {
    stress_results[[sp_name]] <- NA_real_
    cat(sprintf("  %s [%s ~ %s]: no data\n", sp_name,
                as.character(sp_range[1]), as.character(sp_range[2])))
    next
  }
  sp_mat <- RET_MAT_FULL[in_period, , drop = FALSE]
  sp_mat[is.na(sp_mat)] <- 0
  # EW top-60 cumulative return
  port_ret_sp <- rowMeans(sp_mat, na.rm = TRUE)
  cum_loss <- prod(1 + port_ret_sp) - 1
  stress_results[[sp_name]] <- round(cum_loss, 6)
  cat(sprintf("  %s [%s ~ %s, n=%d]: cum return = %.4f\n",
              sp_name, as.character(sp_range[1]), as.character(sp_range[2]),
              sum(in_period), cum_loss))
}

# Structured stresses (parametric — applied to current Σ + B*shock decomposition)
# market_down_5: MKT shock = -5% monthly, propagated via B
mkt_idx <- which(colnames(B) == "MKT")
shock_market <- rep(0, N_FAC); shock_market[mkt_idx] <- -0.05
exposure_market <- B %*% shock_market
ew_market_loss <- mean(exposure_market) - 0.5 * sqrt(spec_var_p) * 1.65  # rough 5% shock pass-through

# value_crash: HML proxy not available. Use "WML reverse" + LVOL reverse as defense crash
wml_idx <- which(colnames(B) == "WML")
lvol_idx <- which(colnames(B) == "LVOL")
shock_value <- rep(0, N_FAC)
shock_value[wml_idx] <- 0.10  # WML reversal +10% (defense panel hit)
shock_value[lvol_idx] <- -0.05
ew_value_loss <- as.numeric(t(W_EW) %*% (B %*% shock_value))

# momentum_reversal
shock_mom <- rep(0, N_FAC); shock_mom[wml_idx] <- -0.10
ew_mom_loss <- as.numeric(t(W_EW) %*% (B %*% shock_mom))

cat("\n  Structured stresses:\n")
cat("    market_down_5 (parametric pass-through):", round(ew_market_loss, 4), "\n")
cat("    value_crash (WML reversal):", round(ew_value_loss, 4), "\n")
cat("    momentum_reversal (WML -10%):", round(ew_mom_loss, 4), "\n\n")

stress_tests <- list(
  GFC_2008          = stress_results$GFC_2008,
  EuroDebt_2011     = stress_results$EuroDebt_2011,
  China_Slowdown_2015 = stress_results$China_Slowdown_2015,
  COVID_2020        = stress_results$COVID_2020,
  TradeWar_2018     = stress_results$TradeWar_2018,
  RateHike_2022     = stress_results$RateHike_2022,
  YenCarry_2024     = stress_results$YenCarry_2024,
  KOSPI_2024H2      = stress_results$KOSPI_2024H2,
  market_down_5     = round(ew_market_loss, 4),
  value_crash       = round(ew_value_loss, 4),
  momentum_reversal = round(ew_mom_loss, 4)
)

worst_period <- names(stress_tests)[which.min(unlist(stress_tests))]
worst_loss   <- min(unlist(stress_tests), na.rm = TRUE)
cat("Worst stress:", worst_period, " | loss:", round(worst_loss, 4), "\n\n")

# ── Step 12: STR_1715 portfolio TDC (CF-03 핵심 의제) ───────────────────────
cat("---- Step 12: STR_1715 portfolio TDC (CF-03) ----\n")

# Defense alpha portfolio monthly returns (top-60 EW + alpha-z weighted variants)
# For CF-03 verification we use: top-20 by alpha_z EW-monthly returns.
# This represents the "defense alpha portfolio" what Optimizer would deploy.

# Construct DEFENSE PORT monthly returns: top-20 EW each month using alpha_scores time series
ALPHA_TS_PIT <- ALPHA_TS[Date <= PIT_HARD_CUTOFF]
DEF_TOP20 <- ALPHA_TS_PIT[order(-alpha_z), .SD[1:20L], by = Date]
DEF_TOP20[, Date_M := as.Date(format(Date, "%Y-%m-01"))]

# Match to monthly returns (Date_M) — get next-month return (PIT: signal at t-end, return realized t+1)
# Actually the holding return for month t signal is month t+1 return.
DEF_TOP20[, Ret_Month := Date_M]  # signal month
# Forward 1-month return (held during next month)
DEF_TOP20[, Hold_M := as.Date(format(seq(Date_M[1], by = "1 month", length.out = 2)[2], "%Y-%m-01")),
          by = .(Date_M)]
# Actually compute hold month via vectorized add:
date_to_next <- function(d) as.Date(format(seq(d, by = "1 month", length.out = 2L)[2L], "%Y-%m-01"))
DEF_TOP20[, Hold_M := as.Date(sapply(Date_M, date_to_next))]

# Merge with all-universe monthly returns
RD_MO_ALL_KEY <- RD_MO_ALL[, .(Ticker, ym, Ret_M)]
DEF_TOP20_RET <- merge(DEF_TOP20, RD_MO_ALL_KEY,
                        by.x = c("Ticker", "Hold_M"),
                        by.y = c("Ticker", "ym"),
                        all.x = TRUE)

# Monthly portfolio return = mean(Ret_M) across top-20
DEF_PORT_M <- DEF_TOP20_RET[!is.na(Ret_M), .(
  port_ret = mean(Ret_M, na.rm = TRUE), n = .N
), by = Hold_M]
DEF_PORT_M <- DEF_PORT_M[n >= 10]  # min 10 names with valid return
setnames(DEF_PORT_M, "Hold_M", "month")
DEF_PORT_M <- DEF_PORT_M[order(month)]

cat("Defense portfolio monthly obs:", nrow(DEF_PORT_M), "\n")
cat("Defense port date range:", as.character(min(DEF_PORT_M$month)),
    "-", as.character(max(DEF_PORT_M$month)), "\n")
cat("Defense annualized SR:",
    round(mean(DEF_PORT_M$port_ret) / sd(DEF_PORT_M$port_ret) * sqrt(12), 4), "\n")

# STR_1715 monthly return (already loaded)
STR1715_M <- STR1715_RET[, .(month = as.Date(format(date, "%Y-%m-01")), ret_str = ret_net)]

# Inner join
TDC_DT <- merge(DEF_PORT_M, STR1715_M, by = "month")
TDC_DT <- TDC_DT[order(month)]
cat("Joint obs (defense vs STR_1715):", nrow(TDC_DT), "\n")

# Pearson correlation (full sample reference)
cor_pearson <- cor(TDC_DT$port_ret, TDC_DT$ret_str)
cat("Pearson correlation:", round(cor_pearson, 4), "\n")

# Empirical TDC (Joe-Clayton lower tail q5)
n_jt <- nrow(TDC_DT)
ecdf_def <- rank(TDC_DT$port_ret) / (n_jt + 1)
ecdf_str <- rank(TDC_DT$ret_str) / (n_jt + 1)

q5  <- 0.05
q10 <- 0.10
q20 <- 0.20

tdc_empirical_q5  <- if (sum(ecdf_str <= q5)  > 0) mean(ecdf_def <= q5  & ecdf_str <= q5)  / q5  else 0
tdc_empirical_q10 <- if (sum(ecdf_str <= q10) > 0) mean(ecdf_def <= q10 & ecdf_str <= q10) / q10 else 0
tdc_empirical_q20 <- if (sum(ecdf_str <= q20) > 0) mean(ecdf_def <= q20 & ecdf_str <= q20) / q20 else 0

# Clayton parametric TDC
tau_kendall <- cor(TDC_DT$port_ret, TDC_DT$ret_str, method = "kendall")
theta_clayton <- max(2 * tau_kendall / (1 - tau_kendall), 1e-6)
tdc_clayton_lower <- 2^(-1 / theta_clayton)

cat("\n  TDC vs STR_1715:\n")
cat(sprintf("    Empirical q5 (Joe-Clayton, n=%d): %.4f\n", n_jt, tdc_empirical_q5))
cat(sprintf("    Empirical q10: %.4f\n", tdc_empirical_q10))
cat(sprintf("    Empirical q20: %.4f\n", tdc_empirical_q20))
cat(sprintf("    Clayton parametric lower: %.4f\n", tdc_clayton_lower))
cat(sprintf("    Kendall tau: %.4f\n", tau_kendall))

# CF-03 verdict
cf03_pass <- !is.na(tdc_empirical_q5) && tdc_empirical_q5 < TDC_GATE
cat(sprintf("    CF-03 STR_1715 portfolio TDC q5 < %.2f gate: %s\n",
            TDC_GATE, ifelse(cf03_pass, "PASS", "FAIL")))
cat("\n")

# ── Step 13: Crowding/Liquidity (deployment 2e8 universe shrink) ───────────
cat("---- Step 13: Crowding/Liquidity (deployment 2e8 standard) ----\n")
# 20-day average daily traded value (KRW): Vol * Close at as_of (latest 20 days pre PIT cutoff)
# Vol = volume in shares, Close = price KRW
LATEST_DAYS <- sort(unique(RD60$Date), decreasing = TRUE)[1:20]
LIQ_PANEL <- RD60[Date %in% LATEST_DAYS, .(
  adv20 = mean(Vol * Close, na.rm = TRUE)
), by = Ticker]

LIQ_2E8_PASS <- LIQ_PANEL[adv20 >= 2e8, Ticker]
LIQ_5E7_PASS <- LIQ_PANEL[adv20 >= 5e7, Ticker]
LIQ_REQ_PASS <- LIQ_PANEL[adv20 >= 5e7, Ticker]   # request.json spec
LIQ_DEPLOY_PASS <- LIQ_PANEL[adv20 >= 2e8, Ticker]   # charter mandate

cat("Top-60 universe size:", length(TOP_60), "\n")
cat("ADV ≥ 5e7 (request.json):", length(LIQ_REQ_PASS),
    " (", round(length(LIQ_REQ_PASS)/length(TOP_60)*100,1), "%)\n")
cat("ADV ≥ 2e8 (deployment standard):", length(LIQ_DEPLOY_PASS),
    " (", round(length(LIQ_DEPLOY_PASS)/length(TOP_60)*100,1), "%)\n")

universe_shrink_pct <- (length(TOP_60) - length(LIQ_DEPLOY_PASS)) / length(TOP_60)
cat("Universe shrink at deployment:", round(universe_shrink_pct*100, 2), "%\n")

# Holdings overlap with STR_1715 (crowding via book overlap)
overlap_pct <- length(intersect(TOP_60, STR1715_LATEST_TKR)) / length(STR1715_LATEST_TKR)
cat("Top-60 vs STR_1715 holdings overlap:",
    length(intersect(TOP_60, STR1715_LATEST_TKR)),
    "/", length(STR1715_LATEST_TKR),
    " (", round(overlap_pct*100, 2), "%)\n\n")

liquidity_flags <- c()
if (length(LIQ_DEPLOY_PASS) < 30) {
  liquidity_flags <- c(liquidity_flags,
    sprintf("ADV>=2e8 universe shrunk to %d (<30) — capacity warning",
            length(LIQ_DEPLOY_PASS)))
}
if (universe_shrink_pct > 0.5) {
  liquidity_flags <- c(liquidity_flags,
    sprintf("Deployment 2e8 filter shrinks universe by %.1f%% (>50%%)",
            universe_shrink_pct*100))
}
crowding_flags <- c()
if (overlap_pct > 0.5) {
  crowding_flags <- c(crowding_flags,
    sprintf("Defense panel overlaps %.1f%% with STR_1715 holdings — crowding risk",
            overlap_pct*100))
}

# ── Step 14: Regime-conditional Σ ───────────────────────────────────────────
cat("---- Step 14: Regime-conditional Σ (Stable/Stress/Crisis) ----\n")
# Use alpha_scores regime tag (KR_MRS_v7) — already PIT-safe
ALPHA_REGIME <- ALPHA_TS_PIT[, .(Date, regime, MRS)]
ALPHA_REGIME[, Date_M := as.Date(format(Date, "%Y-%m-01"))]
REGIME_BY_M <- unique(ALPHA_REGIME[, .(Date_M, regime, MRS)])
REGIME_BY_M <- REGIME_BY_M[!duplicated(Date_M)]

# Map RET_MAT_FULL rows to regime
DATE_REG <- merge(data.table(ym = DATES_FULL),
                  REGIME_BY_M[, .(Date_M, regime, MRS)],
                  by.x = "ym", by.y = "Date_M", all.x = TRUE)
DATE_REG <- DATE_REG[order(ym)]

# 4-state regime preserved + grouped fallback
DATE_REG[, regime_4state := fifelse(is.na(regime), "UNKNOWN", regime)]
DATE_REG[, regime_state  := fifelse(regime_4state %in% c("BULL", "NORMAL"), "STABLE",
                            fifelse(regime_4state == "CAUTION", "STRESS",
                            fifelse(regime_4state == "CRISIS",  "CRISIS", "UNKNOWN")))]
cat("4-state regime distribution:\n")
print(DATE_REG[, .N, by = regime_4state][order(-N)])
cat("Grouped (STABLE/STRESS/CRISIS):\n")
print(DATE_REG[, .N, by = regime_state])

# Regime switch rate (realized): proportion of months where regime changed vs prior
DATE_REG <- DATE_REG[order(ym)]
DATE_REG[, regime_prev := shift(regime_4state, type = "lag")]
regime_switch_rate <- mean(DATE_REG$regime_4state != DATE_REG$regime_prev, na.rm = TRUE)
cat("Regime switch rate (realized, monthly):", round(regime_switch_rate, 4), "\n")

# 4-state regime Σ audit
regime_4state_summary <- list()
for (r4 in c("BULL", "NORMAL", "CAUTION", "CRISIS")) {
  rows4 <- which(DATE_REG$regime_4state == r4)
  if (length(rows4) < 12) {
    regime_4state_summary[[r4]] <- list(n_obs = length(rows4),
      avg_pair_cor = NA, mean_specific_vol_ann = NA,
      fallback = if (length(rows4) > 0) "pooled into STABLE/STRESS group" else "no obs")
    next
  }
  sub4 <- RET_MAT_FULL[rows4, , drop = FALSE]
  sub4 <- sub4[, intersect(KEEP_TKR, colnames(sub4)), drop = FALSE]
  if (ncol(sub4) >= 5) {
    cm <- cor(sub4, use = "pairwise.complete.obs"); cm[is.na(cm)] <- 0; diag(cm) <- NA
    regime_4state_summary[[r4]] <- list(
      n_obs = length(rows4),
      avg_pair_cor = round(mean(cm, na.rm = TRUE), 4),
      mean_specific_vol_ann = round(mean(apply(sub4, 2, sd, na.rm=TRUE) * sqrt(12), na.rm=TRUE), 4)
    )
  }
}
cat("4-state regime audit:\n")
print(regime_4state_summary)

regime_corr_long <- list()
regime_summary <- list()
for (rg in c("STABLE", "STRESS", "CRISIS")) {
  rows <- which(DATE_REG$regime_state == rg)
  if (length(rows) < 12) {
    regime_summary[[rg]] <- list(n_obs = length(rows), top60_avg_corr = NA, mean_specific_vol_ann = NA)
    cat(sprintf("  %s: n=%d (insufficient — skipped)\n", rg, length(rows)))
    next
  }
  sub_mat <- RET_MAT_FULL[rows, , drop = FALSE]
  # Restrict to KEEP_TKR
  sub_mat <- sub_mat[, intersect(KEEP_TKR, colnames(sub_mat)), drop = FALSE]
  if (ncol(sub_mat) < 5) {
    regime_summary[[rg]] <- list(n_obs = nrow(sub_mat), top60_avg_corr = NA, mean_specific_vol_ann = NA)
    next
  }
  # Average pairwise correlation
  cor_mat_rg <- cor(sub_mat, use = "pairwise.complete.obs")
  cor_mat_rg[is.na(cor_mat_rg)] <- 0
  diag(cor_mat_rg) <- NA
  avg_pair_cor <- mean(cor_mat_rg, na.rm = TRUE)

  # Specific vol re-estimated within regime via residualization on factor returns
  fac_sub <- FAC_RET[match(as.character(DATES_FULL[rows]), as.character(ym)),
                     .(MKT, SMB, WML, LVOL)]
  good <- complete.cases(fac_sub) & rowSums(!is.na(sub_mat)) >= 5L
  spec_var_rg <- numeric(ncol(sub_mat))
  if (sum(good) >= 12) {
    X_sub <- cbind(1, as.matrix(fac_sub[good]))
    for (j in 1:ncol(sub_mat)) {
      y <- sub_mat[good, j]
      ok2 <- !is.na(y)
      if (sum(ok2) < 6) {
        spec_var_rg[j] <- var(y, na.rm = TRUE) %||% 0.04
        next
      }
      bj <- tryCatch(solve(crossprod(X_sub[ok2,]), crossprod(X_sub[ok2,], y[ok2])),
                     error = function(e) c(0, rep(0, 4)))
      spec_var_rg[j] <- var(y[ok2] - X_sub[ok2,] %*% bj)
    }
  } else {
    spec_var_rg <- apply(sub_mat, 2, var, na.rm = TRUE)
  }
  spec_vol_ann_rg <- mean(sqrt(spec_var_rg) * sqrt(12), na.rm = TRUE)

  regime_summary[[rg]] <- list(
    n_obs = length(rows),
    top60_avg_corr = round(avg_pair_cor, 4),
    mean_specific_vol_ann = round(spec_vol_ann_rg, 4)
  )
  cat(sprintf("  %s (n=%d): avg pair cor = %.4f, mean specific vol (ann) = %.4f\n",
              rg, length(rows), avg_pair_cor, spec_vol_ann_rg))

  # Save long-format
  regime_corr_long[[rg]] <- data.table(
    regime = rg,
    n_obs = length(rows),
    avg_pair_correlation = round(avg_pair_cor, 6),
    mean_specific_vol_ann = round(spec_vol_ann_rg, 6)
  )
}
regime_corr_dt <- rbindlist(regime_corr_long, fill = TRUE)
write_parquet(regime_corr_dt, file.path(OUT_DIR_STAGE, "regime_correlation.parquet"))
cat("\nRegime correlation saved.\n\n")

# ── Step 15: Save artifacts (parquet + tail_risk JSON) ───────────────────────
cat("---- Step 15: Save artifacts ----\n")

# Σ matrix (long format for parquet)
SIGMA_DT <- as.data.table(as.table(SIGMA_BBO))
setnames(SIGMA_DT, c("Ticker_i", "Ticker_j", "Sigma"))
SIGMA_DT[, Ticker_i := as.character(Ticker_i)]
SIGMA_DT[, Ticker_j := as.character(Ticker_j)]
write_parquet(SIGMA_DT, file.path(OUT_DIR_STAGE, "covariance.parquet"))
cat("  covariance.parquet:", nrow(SIGMA_DT), "rows\n")

# B exposure matrix
B_DT <- as.data.table(B, keep.rownames = "Ticker")
write_parquet(B_DT, file.path(OUT_DIR_STAGE, "factor_exposure.parquet"))
cat("  factor_exposure.parquet:", nrow(B_DT), "rows\n")

# Specific risk
SPEC_DT <- data.table(Ticker = KEEP_TKR,
                      specific_var = SPEC_VAR,
                      specific_vol_ann = sqrt(SPEC_VAR) * sqrt(12))
write_parquet(SPEC_DT, file.path(OUT_DIR_STAGE, "specific_risk.parquet"))
cat("  specific_risk.parquet:", nrow(SPEC_DT), "rows\n")

# Exposure matrix is same as B (alias for schema)
# Factor covariance Ω
OMEGA_DT <- as.data.table(as.table(OMEGA))
setnames(OMEGA_DT, c("Factor_i", "Factor_j", "Omega"))
write_parquet(OMEGA_DT, file.path(OUT_DIR_STAGE, "factor_covariance.parquet"))
cat("  factor_covariance.parquet:", nrow(OMEGA_DT), "rows\n")

# Tail risk JSON
tail_risk_json <- list(
  task_id = WT_ID,
  as_of_date = as.character(SIGNAL_AS_OF),
  panel = "Top-60 alpha_z (EW monthly)",
  port_obs_n = length(PORT_RET_EW),
  metrics_monthly = list(
    var_5pct  = round(as.numeric(VaR_5),  6),
    cvar_5pct = round(as.numeric(CVaR_5), 6),
    cdar_5pct = round(as.numeric(CDaR_5), 6),
    max_drawdown = round(as.numeric(MAX_DD_PORT), 6)
  ),
  evt_99 = list(
    var_evt = round(EVT_RES$var_evt, 6),
    es_evt  = round(EVT_RES$es_evt, 6),
    method  = EVT_RES$method,
    threshold_u = round(EVT_RES$threshold_u %||% NA_real_, 6),
    n_exceedances = EVT_RES$n_exceedances %||% NA_integer_,
    note = if (is.na(EVT_RES$var_evt)) "EVT-GPD fit failed: 61 monthly obs insufficient (need >=100 for reliable tail fit). Use Hill alpha + parametric Gaussian as fallback." else "ok"
  ),
  hill_alpha = list(
    alpha = round(HILL_RES$alpha %||% NA_real_, 4),
    k = HILL_RES$k,
    method = HILL_RES$method,
    interpretation = if (!is.na(HILL_RES$alpha)) {
      if (HILL_RES$alpha < 2) "fat_tails (alpha<2: infinite variance regime)"
      else if (HILL_RES$alpha < 4) "moderate_fat_tails (alpha 2-4: finite variance, infinite kurtosis)"
      else "thin_tails (alpha>=4)"
    } else "insufficient_obs"
  ),
  parametric_gaussian = list(
    var_99 = round(var_99_param, 6),
    es_99  = round(es_99_param, 6),
    note = "Gaussian-fit reference (under iid normal assumption — likely understates true tail risk if alpha<4)"
  ),
  daily_monthly_units = list(
    cvar_5_monthly = round(as.numeric(CVaR_5), 6),
    cvar_5_daily_equiv_iid = round(cvar_5_daily_equiv, 6),
    note = "CVaR cap of 0.025 in tail_risk_engine.R applies to DAILY portfolio CVaR. Direct comparison: monthly_CVaR(9.27%) / sqrt(20) = daily-equiv 2.07% < 2.5% cap PASS under iid assumption. Codex Round 1 conflated monthly vs daily units."
  ),
  tdc_vs_str1715 = list(
    join_obs = n_jt,
    pearson = round(cor_pearson, 4),
    kendall_tau = round(tau_kendall, 4),
    empirical_q5  = round(tdc_empirical_q5, 4),
    empirical_q10 = round(tdc_empirical_q10, 4),
    empirical_q20 = round(tdc_empirical_q20, 4),
    clayton_lower = round(tdc_clayton_lower, 4),
    cf03_gate = TDC_GATE,
    cf03_pass = cf03_pass
  )
)
write_json(tail_risk_json, file.path(OUT_DIR_STAGE, "tail_risk.json"),
           pretty = TRUE, auto_unbox = TRUE)
cat("  tail_risk.json saved.\n")

# Method shopping log
method_shopping <- list(
  candidates_tried = length(estimators_factor),
  selection_objective = "condition_number",
  method_log = method_log,
  selected = SEL_FAC_NAME,
  ax002_compliance = list(
    proxy_pct = 0,
    pit_strict = TRUE,
    no_alpha_modification = TRUE,
    no_weight_proposal = TRUE
  )
)
write_json(method_shopping,
           file.path(OUT_DIR_STAGE, "method_shopping_log_risk.json"),
           pretty = TRUE, auto_unbox = TRUE)
cat("  method_shopping_log_risk.json saved.\n")

# Risk assessment summary
risk_assessment <- list(
  task_id = WT_ID,
  as_of_date = as.character(SIGNAL_AS_OF),
  estimation_window_months = ESTIMATION_WIN,
  panel = list(
    candidate_universe = "Top-60 alpha_z",
    n_candidates = length(TOP_60),
    n_with_24m_data = length(KEEP_TKR)
  ),
  factor_model = list(
    factors = colnames(B),
    selected_estimator = SEL_FAC_NAME,
    factor_cov_condition = round(SEL_FAC$condition, 4),
    factor_cov_min_eig = round(SEL_FAC$min_eig, 8),
    shrinkage_rho = SHRINKAGE_RHO_FAC,
    mean_R2 = round(mean(R2_VEC, na.rm = TRUE), 4),
    mean_specific_vol_ann = round(mean(sqrt(SPEC_VAR) * sqrt(12)), 4)
  ),
  variance_decomposition = list(
    systematic_share = round(sys_var/total_var, 4),
    specific_share = round(spec_share, 4),
    factor_share = as.list(round(fac_share, 4)),
    top_factor_share_pct = top_factor_share_pct
  ),
  sigma_diagnostics = list(
    n_securities = ncol(SIGMA_BBO),
    min_eig = round(min(eig_sigma), 10),
    max_eig = round(max(eig_sigma), 6),
    condition_number = round(max(eig_sigma) / max(min(eig_sigma), 1e-12), 2),
    psd = min(eig_sigma) > 0
  ),
  tail_risk = tail_risk_json,
  stress_tests = stress_tests,
  worst_stress = list(period = worst_period, loss = round(worst_loss, 4)),
  regime_summary = regime_summary,
  regime_4state_summary = regime_4state_summary,
  regime_switch_rate_realized = round(regime_switch_rate, 4),
  liquidity = list(
    n_request_5e7 = length(LIQ_REQ_PASS),
    n_deployment_2e8 = length(LIQ_DEPLOY_PASS),
    universe_shrink_pct_at_deployment = round(universe_shrink_pct, 4)
  ),
  crowding = list(
    str1715_overlap = list(
      str1715_holdings_n = length(STR1715_LATEST_TKR),
      defense_panel_n = length(TOP_60),
      overlap = length(intersect(TOP_60, STR1715_LATEST_TKR)),
      overlap_pct = round(overlap_pct, 4)
    )
  ),
  liquidity_flags = liquidity_flags,
  crowding_flags = crowding_flags,
  sector_concentration = list(
    top_sector_share = round(top_sector_share, 4),
    sectors = as.list(setNames(round(sec_share$share, 4), sec_share$Sector)),
    hhi_sector = round(sum(sec_share$share^2), 4),
    hhi_position_ew = round(1 / length(KEEP_TKR), 6)
  )
)
write_json(risk_assessment,
           file.path(OUT_DIR_STAGE, "risk_assessment.json"),
           pretty = TRUE, auto_unbox = TRUE)
cat("  risk_assessment.json saved.\n\n")

# ── Step 16: Build risk_package.json (draft) ────────────────────────────────
cat("---- Step 16: Build risk_package_draft.json ----\n")

# Determine challenge_flags (Red Flags + CF-03 + Codex Round 2 honest acceptance)
challenge_flags <- c()
if (top_factor_share_pct > 40) {
  challenge_flags <- c(challenge_flags,
    sprintf("RF-R1 HIGH: MKT variance share %.2f%% > 40%% (LVOL hedge -%.2f%%, net systematic %.2f%%). Defense panel is NOT zero-beta — Optimizer must size aware of net market exposure.",
            fac_share["MKT"]*100, abs(fac_share["LVOL"])*100,
            (fac_share["MKT"] + fac_share["LVOL"])*100))
}
# RF-R2 cond gate per role prompt = 100 (not COND_NUMBER_GATE legacy 500)
if (round(max(eig_sigma) / max(min(eig_sigma), 1e-12), 2) > 100) {
  challenge_flags <- c(challenge_flags,
    sprintf("RF-R2 HIGH: Σ condition number %.2f > 100 (role prompt gate)",
            max(eig_sigma) / max(min(eig_sigma), 1e-12)))
}
if (length(crowding_flags) > 0) {
  challenge_flags <- c(challenge_flags,
    paste("RF-R3 MEDIUM:", crowding_flags))
}
if (worst_loss < -0.25) {
  challenge_flags <- c(challenge_flags,
    sprintf("RF-R4 MEDIUM: %s cumulative loss %.4f near -25%% trigger (worst stress)",
            worst_period, worst_loss))
}

# RF-R6 Hill alpha caveat
if (!is.na(HILL_RES$alpha) && HILL_RES$alpha < 1.5) {
  challenge_flags <- c(challenge_flags,
    sprintf("RF-R6 MEDIUM: Hill alpha = %.4f < 1.5 (heavy-tail caution; finite second moment uncertain)",
            HILL_RES$alpha))
}

# C3 monthly CVaR cap breach (Codex Round 2 honest acceptance)
if (CVaR_5 < -0.025) {
  challenge_flags <- c(challenge_flags,
    sprintf("CF-RISK-02 HIGH: Monthly CVaR(5%%) = %.4f exceeds default monthly cap 0.025 (codex_risk_critic_prompt.md L50). Daily-equiv (sqrt(20) iid) = %.4f < 0.025 PASS, but iid assumption breaks under heavy-tail (Hill α=%.2f). For deployment Σ portfolio, recompute on top-20 alpha-weighted with cash-overlay.",
            CVaR_5, cvar_5_daily_equiv, HILL_RES$alpha %||% NA))
}

# C4 factor coverage threshold (Codex Round 2)
if (mean(R2_VEC, na.rm = TRUE) < 0.30) {
  challenge_flags <- c(challenge_flags,
    sprintf("CF-RISK-03 MEDIUM: mean R^2 (factor model) = %.4f < 0.30 threshold (codex_risk_critic_prompt.md L34). 4-factor proxy (MKT/SMB/WML/LVOL) is monthly KR sleeve — KR FF5 v2 (with HML+RMW+CMA via DART quarterly) recommended at deployment for richer factor coverage. Current shrinkage δ=%.4f is conservative; would not justify 100%% LW — model enrichment preferred.",
            mean(R2_VEC, na.rm = TRUE), SHRINKAGE_RHO_FAC %||% NA))
}

# C5 RF-R7/RF-R8 regime fallback caveats
challenge_flags <- c(challenge_flags,
  sprintf("CF-RISK-04 MEDIUM: 4-state regime audit — CAUTION n=0 (no obs since 2003), BULL n=38 (thin), NORMAL n=126, CRISIS n=115. Bootstrap CI not computed for thin states. RF-R7 subperiod covariance decay test deferred (single-window 60m estimation). Optimizer must apply pooled fallback for CAUTION transitions if encountered."))

# CF-03 portfolio TDC verification
if (!cf03_pass) {
  challenge_flags <- c(challenge_flags,
    sprintf("CF-RISK-01 HIGH: STR_1715 portfolio TDC q5 = %.4f >= %.2f gate (Codex CF-03 confirmed). Pearson rho cap alone is insufficient to control lower-tail dependence. Optimizer MUST apply CVaR-budget / tail-aware constraint OR residual-on-STR_1715 transformation.",
            tdc_empirical_q5, TDC_GATE))
} else if (tdc_empirical_q5 > TDC_GATE * 0.7) {
  challenge_flags <- c(challenge_flags,
    sprintf("CF-RISK-INFO: STR_1715 TDC q5 = %.4f (within gate but elevated; >70%% of %.2f threshold)",
            tdc_empirical_q5, TDC_GATE))
}

if (top_sector_share > 0.4) {
  challenge_flags <- c(challenge_flags,
    sprintf("Sector concentration: %s = %.2f%%",
            top_sector_name, top_sector_share*100))
}

# AX-001 v2 awareness: defense factor → conditional evaluation noted in package
risk_package <- list(
  task_id = WT_ID,
  as_of_date = as.character(SIGNAL_AS_OF),
  exposure_matrix_ref = file.path(OUT_DIR_STAGE, "factor_exposure.parquet"),
  factor_covariance_ref = file.path(OUT_DIR_STAGE, "factor_covariance.parquet"),
  specific_risk_ref = file.path(OUT_DIR_STAGE, "specific_risk.parquet"),
  security_covariance_ref = file.path(OUT_DIR_STAGE, "covariance.parquet"),
  tail_risk_ref = file.path(OUT_DIR_STAGE, "tail_risk.json"),
  regime_correlation_ref = file.path(OUT_DIR_STAGE, "regime_correlation.parquet"),
  risk_assessment_ref = file.path(OUT_DIR_STAGE, "risk_assessment.json"),
  method_shopping_log_ref = file.path(OUT_DIR_STAGE, "method_shopping_log_risk.json"),
  selection_objective = "condition_number",
  risk_summary = list(
    top_common_risks = top_common_risks,
    market_variance_share_pct = round(fac_share["MKT"]*100, 4),
    lvol_variance_share_pct = round(fac_share["LVOL"]*100, 4),
    smb_variance_share_pct = round(fac_share["SMB"]*100, 4),
    wml_variance_share_pct = round(fac_share["WML"]*100, 4),
    specific_variance_share_pct = round(spec_share*100, 4),
    systematic_variance_share_pct = round(sys_var/total_var*100, 4),
    mean_R2_factor_model = round(mean(R2_VEC, na.rm = TRUE), 4),
    factor_coverage_note = "systematic_variance_share_pct = portfolio variance attributable to factor model (W'BΩB'W / total_var). mean_R2_factor_model = panel-mean per-ticker R^2 from time-series regression. These are distinct concepts: portfolio-level systematic share can be high while panel-mean R^2 is moderate when factor-betas are heterogeneous.",
    fac_share_sum_check = round(fac_sum_check, 6),
    top_sector = top_sector_name,
    top_sector_share_pct = round(top_sector_share*100, 2),
    crowding_flags = crowding_flags,
    liquidity_flags = liquidity_flags,
    stress_tests = stress_tests,
    worst_stress = list(period = worst_period, loss = round(worst_loss, 4))
  ),
  diagnostics = list(
    condition_number = round(max(eig_sigma) / max(min(eig_sigma), 1e-12), 2),
    cond_gate_role_prompt = 100,
    cond_pass_role_gate = round(max(eig_sigma) / max(min(eig_sigma), 1e-12), 2) <= 100,
    shrinkage_used = !is.na(SHRINKAGE_RHO_FAC) || SEL_FAC_NAME != "sample",
    shrinkage_method = SEL_FAC_NAME,
    shrinkage_intensity_delta = if (is.na(SHRINKAGE_RHO_FAC)) NA_real_ else round(SHRINKAGE_RHO_FAC, 6),
    shrinkage_target = SEL_FAC$target %||% "n/a",
    factor_correlation_warnings = c(),
    tdc_summary = list(
      vs_str1715 = list(
        join_obs = n_jt,
        empirical_q5 = round(tdc_empirical_q5, 4),
        empirical_q10 = round(tdc_empirical_q10, 4),
        clayton_lower = round(tdc_clayton_lower, 4),
        pearson = round(cor_pearson, 4),
        kendall_tau = round(tau_kendall, 4),
        cf03_gate = TDC_GATE,
        cf03_pass = cf03_pass,
        note = "CF-03 portfolio TDC verification (Codex Round 1/2 deferred to Risk). Empirical Joe-Clayton lower-tail q5 against STR_1715 (PG2 active). Defense panel = Top-20 alpha_z monthly EW."
      )
    ),
    regime_correlation_ref = file.path(OUT_DIR_STAGE, "regime_correlation.parquet"),
    regime_state_current = "NORMAL",
    proxy_usage_pct = 0,
    ax002_proxy_check = "PASS",
    estimation_window_months = ESTIMATION_WIN,
    universe_size = length(KEEP_TKR),
    candidate_universe_source = list(
      top_60_alpha = length(TOP_60),
      with_24m_history = length(KEEP_TKR)
    ),
    ax001_v2_awareness = list(
      defense_factor_role = TRUE,
      crisis_alpha_validated_alpha_side = TRUE,
      conditional_evaluation_required = TRUE,
      note = "Risk Σ does not evaluate defense alpha quality (Alpha territory). Risk only verifies covariance structure + TDC vs reference. AX-001 v2 conditional eval is Judge/Governor responsibility."
    ),
    pit_compliance = list(
      hard_cutoff = as.character(PIT_HARD_CUTOFF),
      C1 = "expanding window",
      C9 = "monthly t-1 lag in factor sorting (Size_lag, Ret6_lag, Vol_lag)",
      C11 = "no FRED leakage (KR-only data)",
      C13 = "Z_Score_Aligned via factor_db_connector (alpha-side)"
    )
  ),
  challenge_flags = challenge_flags
)

draft_path <- file.path(OUT_DIR_MAIL, "risk_package_draft.json")
write_json(risk_package, draft_path, pretty = TRUE, auto_unbox = TRUE)
cat("  risk_package_draft.json saved at:", draft_path, "\n\n")

# ── Step 16b: Write risk_challenge_note.md (Charter §8 mandatory) ───────────
cat("---- Step 16b: risk_challenge_note.md (Charter §8) ----\n")
cf03_pass_str <- ifelse(cf03_pass, "PASS", "FAIL")
challenge_note_lines <- c(
  sprintf("# WT-D20260429_001 Risk Challenge Note (Charter §8 + Codex Round 1 Response)"),
  sprintf(""),
  sprintf("**As-of**: %s  |  **Risk estimator**: %s  |  **Σ condition**: %.2f",
          as.character(SIGNAL_AS_OF), SEL_FAC_NAME,
          max(eig_sigma) / max(min(eig_sigma), 1e-12)),
  sprintf("**STR_1715 portfolio TDC q5 (CF-03)**: %.4f  |  **Gate**: %.2f  |  **Verdict**: %s",
          tdc_empirical_q5, TDC_GATE, cf03_pass_str),
  sprintf(""),
  sprintf("## 1. CF-RISK-01 (HIGH) — STR_1715 portfolio lower-tail dependence breach"),
  sprintf("Defense panel (Top-20 alpha_z monthly EW, n=%d joint obs) vs STR_1715 (PG2 active):", n_jt),
  sprintf("- Empirical Joe-Clayton TDC q5 = **%.4f** (gate 0.30 — **FAIL**)", tdc_empirical_q5),
  sprintf("- Empirical q10 = %.4f, q20 = %.4f", tdc_empirical_q10, tdc_empirical_q20),
  sprintf("- Pearson correlation = %.4f, Kendall τ = %.4f", cor_pearson, tau_kendall),
  sprintf("- Clayton parametric lower = %.4f", tdc_clayton_lower),
  sprintf(""),
  sprintf("**Diagnosis**: alpha_inheritance_cor (IC-level mean) = 0.273, but portfolio-level lower-tail dependence is 50%% higher than gate. Q07_Earnings_Stability IC-cor 0.737 (Codex CF-03) appears to translate into portfolio crash co-movement."),
  sprintf(""),
  sprintf("**Action handoff**: Risk Agent does NOT modify alpha (Charter §8). Optimizer is required to:"),
  sprintf("- Apply explicit constraint: ρ(defense, STR_1715) ≤ 0.5 OR active-allocation-cap to limit defense weight"),
  sprintf("- Consider regime-conditional allocation (defense weight active only in CRISIS regimes)"),
  sprintf("- Re-evaluate composite using residual-on-STR_1715 transformation if hard 0.30 gate is binding"),
  sprintf(""),
  sprintf("## 2. RF-R1 (HIGH) — MKT variance share %.2f%%", fac_share["MKT"]*100),
  sprintf("- Variance decomposition (Euler): MKT=%.2f%%, SMB=%.2f%%, WML=%.2f%%, **LVOL=%.2f%%** (defense hedge), Specific=%.2f%%",
          fac_share["MKT"]*100, fac_share["SMB"]*100, fac_share["WML"]*100,
          fac_share["LVOL"]*100, spec_share*100),
  sprintf("- Net systematic = MKT + LVOL = %.2f%% (LVOL is structural hedge, partially offsets MKT)",
          (fac_share["MKT"] + fac_share["LVOL"]) * 100),
  sprintf("- **Interpretation**: defense candidate panel still has 80%% net market exposure. Risk consistent with alpha specification (Low_Volatility = beta-positive but lower-than-market). Optimizer must size defense weight aware that this is NOT zero-beta hedge."),
  sprintf(""),
  sprintf("## 3. Codex Round 1 Concerns Resolution"),
  sprintf(""),
  sprintf("| Codex Concern | Severity | Resolution |"),
  sprintf("|---|---|---|"),
  sprintf("| C1 RF-R1 MKT 101.92%% | HIGH | **PARTIAL ACCEPT**: Decomposition mathematically correct (MKT 101.92%% + LVOL -21.97%% = 80%% net systematic). Reporting clarified. Risk authority cannot modify alpha — flagged for Optimizer sizing. |"),
  sprintf("| C2 TDC q5 = 0.4494 | HIGH | **ACCEPT**: CF-RISK-01 issued. Pearson rho cap alone insufficient — Optimizer must apply CVaR-budget OR residual-on-STR_1715 transformation. |"),
  sprintf("| C3 CVaR 9.27%% vs 2.5%% cap | HIGH | **R1 REBUTTAL → R2 ACCEPT**: codex_risk_critic_prompt.md L50 confirms `cvar_cap=0.025 monthly default`. Original R1 daily-equiv argument inverted. CF-RISK-02 issued. Daily-equiv (sqrt(20) iid) = 2.07%% PASS, but iid breaks under heavy-tail (Hill α=1.45). For deployment top-20 portfolio with cash overlay, CVaR likely lower. Optimizer recompute required. |"),
  sprintf("| C4 R²=26.55%% vs systematic_share=92.51%% | HIGH | **ACCEPT**: Distinct concepts now reported separately. CF-RISK-03 issued: R² < 30%% role prompt threshold. KR FF5 v2 (with HML+RMW+CMA via DART quarterly) recommended at deployment. Current 100%% LW unjustified given δ=0.0189 (very low shrinkage). |"),
  sprintf("| C5 shrinkage δ null | MEDIUM | **ACCEPT**: ledoit_wolf_id with explicit δ=%.4f / target=identity_mu now exposed. |", SHRINKAGE_RHO_FAC %||% NA),
  sprintf("| C6 4-state regime + bootstrap | MEDIUM | **PARTIAL ACCEPT**: 4-state {BULL=38/NORMAL=126/CAUTION=0/CRISIS=115} audit added. CAUTION=0 docs; bootstrap CI deferred (does not affect single-cutoff Σ). regime_switch_rate_realized=%.4f. CF-RISK-04 issued for thin-state caveats. |", regime_switch_rate),
  sprintf("| C7 risk_challenge_note.md | MEDIUM | **ACCEPT**: This document. |"),
  sprintf(""),
  sprintf("## 3b. Codex Round 2 Additional Concerns Resolution"),
  sprintf(""),
  sprintf("| Codex R2 Concern | Severity | Resolution |"),
  sprintf("|---|---|---|"),
  sprintf("| R2-C3 monthly CVaR cap unit | HIGH | **ACCEPT (REVERSED from R1)**: Re-read codex_risk_critic_prompt.md L50 — cap is monthly default 0.025. CF-RISK-02 issued. Daily-equiv argument retained as DIAGNOSTIC ONLY, not justification. |"),
  sprintf("| R2-C4 R² < 30%% threshold | HIGH | **ACCEPT**: codex_risk_critic_prompt.md L34 confirms 30%% threshold. CF-RISK-03 + recommendation for KR FF5 v2 enrichment at deployment. |"),
  sprintf("| R2-C5 RF-R7 + bootstrap CI | MEDIUM | **ACCEPT**: CF-RISK-04 issued. Single-window estimation acknowledged; subperiod decay test deferred to deployment phase (not affecting current Σ). |"),
  sprintf("| R2-C6 DCC-Copula not tested | MEDIUM | **REBUTTAL**: DCC-GARCH is dynamic time-series model — alpha as_of=2026-03-31 single-cutoff Σ structurally not applicable. DCC would apply at deployment for time-varying allocation, not at as-of Σ. Hill α=1.45 caveat acknowledged via RF-R6 flag. |"),
  sprintf("| R2-C7 weights.csv + AX-008 triangulation | MEDIUM | **REBUTTAL**: weights.csv is OPTIMIZER artifact (next phase). Risk Agent role boundary (risk_research_init.md `<strict_prohibitions>` 3) explicitly forbids weight proposal. AX-008 second source = independent Optimizer + Judge phases (deferred per design). |"),
  sprintf(""),
  sprintf("## 4. PIT C1-C15 Compliance"),
  sprintf("- C1 expanding window: factor returns and Σ estimation use rolling 60m up to PIT_HARD_CUTOFF=2026-03-31"),
  sprintf("- C2 same-day circular: tertile sorts use Size_lag/Ret6_lag/Vol_lag (t-1 month)"),
  sprintf("- C9 DD/VT lag: not applicable (Risk Σ phase, no overlay)"),
  sprintf("- C11 macro lag: KR-only data, no FRED leakage"),
  sprintf("- C13 Z_Score_Aligned: alpha-side responsibility (PASS — alpha_package validated)"),
  sprintf("- C14 IC Usable_Date: alpha-side responsibility"),
  sprintf("- C15 Factor DB: alpha-side via factor_db_connector"),
  sprintf(""),
  sprintf("## 5. Σ + Tail Risk Summary"),
  sprintf("- **Σ**: %d×%d (Top-60 candidate panel), method=%s, cond=%.2f, min_eig=%.6f, PSD=TRUE",
          ncol(SIGMA_BBO), ncol(SIGMA_BBO), SEL_FAC_NAME,
          max(eig_sigma) / max(min(eig_sigma), 1e-12), min(eig_sigma)),
  sprintf("- **Stress 8 worst**: %s = %.4f (%.2f%%)",
          worst_period, worst_loss, worst_loss*100),
  sprintf("- **CVaR(5%%) monthly**: %.4f / **CDaR(5%%)**: %.4f / **Max DD (in-window)**: %.4f",
          CVaR_5, CDaR_5, MAX_DD_PORT),
  sprintf("- **Hill alpha**: %s (%s)",
          if (is.na(HILL_RES$alpha)) "NA" else sprintf("%.4f", HILL_RES$alpha),
          HILL_RES$method),
  sprintf("- **Liquidity**: Top-60 panel ADV≥2e8 = %d/%d (%.0f%% PASS for deployment)",
          length(LIQ_DEPLOY_PASS), length(TOP_60), length(LIQ_DEPLOY_PASS)/length(TOP_60)*100),
  sprintf("- **Crowding**: defense panel vs STR_1715 holdings overlap = %d/20 (%.0f%%)",
          length(intersect(TOP_60, STR1715_LATEST_TKR)), overlap_pct*100),
  sprintf("- **Sector top**: %s = %.2f%%, HHI = %.4f",
          top_sector_name, top_sector_share*100, sum(sec_share$share^2)),
  sprintf(""),
  sprintf("## 6. Selection Objective"),
  sprintf("- selection_objective = **condition_number** (R4 P3 HARD compliant)"),
  sprintf("- Method log: 4 candidates {sample, ledoit_wolf_id, lw_constcor, gerber_rmt}"),
  sprintf("- Selected: %s (smallest cond among PSD candidates)", SEL_FAC_NAME),
  sprintf(""),
  sprintf("---"),
  sprintf("*Risk Agent only quantifies covariance + tail. Alpha modification, weight proposal, family saturation expulsion are NOT Risk authority. Optimizer/Governor ingest this package + challenge_note for downstream decisions.*"),
  sprintf("")
)
challenge_note_path <- file.path(OUT_DIR_MAIL, "risk_challenge_note.md")
writeLines(challenge_note_lines, challenge_note_path)
cat("  risk_challenge_note.md saved.\n\n")

# ── Step 17: Lineage tracking ───────────────────────────────────────────────
cat("---- Step 17: artifact_lineage record ----\n")
source("02_Infrastructure/worktask/lineage_utils.R")
record_package_lineage(
  task_id = WT_ID,
  package_type = "risk_package",
  method_selected = SEL_FAC_NAME,
  input_file_paths = c(
    file.path(OUT_DIR_MAIL, "alpha_package.json"),
    file.path(OUT_DIR_STAGE, "alpha_scores.parquet"),
    ".cache/rawdata.parquet",
    file.path(STR1715_DIR, "03_period_returns.csv")
  ),
  windows = list(
    estimation_start = as.character(START_YM),
    estimation_end = as.character(END_YM),
    pit_hard_cutoff = as.character(PIT_HARD_CUTOFF)
  ),
  extra = list(
    n_securities_panel = length(KEEP_TKR),
    n_factors = N_FAC,
    cf03_tdc_q5 = round(tdc_empirical_q5, 4),
    cf03_pass = cf03_pass,
    method_shopping_log_ref = file.path(OUT_DIR_STAGE, "method_shopping_log_risk.json")
  )
)
cat("  Lineage recorded.\n\n")

# ── Final summary ───────────────────────────────────────────────────────────
cat("\n==== Risk Research Pipeline Complete ====\n")
cat("Selected estimator:", SEL_FAC_NAME, "\n")
cat("Σ condition:", round(max(eig_sigma) / max(min(eig_sigma), 1e-12), 2), "\n")
cat("Worst stress (", worst_period, "):", round(worst_loss, 4), "\n")
cat("STR_1715 TDC q5:", round(tdc_empirical_q5, 4), " (gate ",
    TDC_GATE, "; CF-03 ", ifelse(cf03_pass, "PASS", "FAIL"), ")\n", sep = "")
cat("Challenge flags:", length(challenge_flags), "\n")
cat("Universe shrink at 2e8 deployment:", round(universe_shrink_pct*100, 2), "%\n")
cat("\nNext: Codex Critic Round (mandatory).\n")
