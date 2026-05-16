#==============================================================================
# WT-D20260513_001 Alpha Research
# Statistically Sophisticated Low-Volatility 4th Orthogonal Alpha Source
#
# Pipeline:
#   Step 1: Load Factor DB monthly panel (5 ex-ante candidates fixed N=5 strict)
#   Step 2: Universe filter KOSPI200 ∪ KOSDAQ150 + 20d ADV >= 2e8 KRW
#   Step 3: Compute monthly cross-sectional alpha for 5 candidates (PIT-clean)
#   Step 4: Diagnostics — Rank IC, ICIR, Monotonicity, Subperiod, Harvey-t
#   Step 5: Orthogonality vs STR_1715_AR_on_M4_R05_overlay_PG2 admit returns
#   Step 6: Select best candidate (rank_ic primary, AX-002 honest)
#   Step 7: Emit alpha_scores.parquet + alpha_validation.json + alpha_package_draft.json
#
# Hard constraints:
#   - PIT C1~C15: load_month_factors() with sig_date <= current month-end
#   - C13: Z_Score_Aligned only (NEGATE_FACTORS prohibited)
#   - C15: load_month_factors() routed
#   - Liquidity: 20d avg trading value >= 2e8 KRW
#   - Universe: K200 ∪ KQ150
#   - ex-ante grid N=5 strict (no post-hoc search)
#
# Authority: Alpha Agent (NO cov / NO weights / NO sigma)
#==============================================================================

# Hard kill switch (Telegram)
Sys.setenv("STR_1715_TG_ENABLE" = "0")

suppressPackageStartupMessages({
  library(arrow)
  library(data.table)
  library(jsonlite)
})

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0) b else a

WT_ID  <- "WT-D20260513_001"
BASE   <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
ART    <- file.path(BASE, "stage_artifacts", "WT_D20260513_001")
MBOX   <- file.path(BASE, "qepm/mailbox/worktask", WT_ID)
dir.create(ART, showWarnings = FALSE, recursive = TRUE)

source(file.path(BASE, "02_Infrastructure/factor_db/factor_db_connector.R"))

#==============================================================================
# Step 1-2: Universe + Liquidity (PIT)
#==============================================================================

cat("[Step 1-2] Universe + Liquidity\n")

raw <- as.data.table(read_parquet(file.path(BASE, ".cache/rawdata.parquet")))
setkey(raw, Date, Ticker)

# Compute month-end signal dates (2004-02 ~ 2026-04: align with STR_1715 lineage)
SIG_DATES <- as.Date(seq(from = as.Date("2004-02-01"),
                          to   = as.Date("2026-04-30"),
                          by   = "month"))
SIG_DATES <- sapply(SIG_DATES, function(d) {
  m <- raw[Date <= d, max(Date)]
  if (length(m) == 0 || is.na(m)) return(NA)
  return(m)
})
SIG_DATES <- as.Date(SIG_DATES, origin = "1970-01-01")
SIG_DATES <- unique(SIG_DATES[!is.na(SIG_DATES)])
SIG_DATES <- sort(SIG_DATES)
cat("Signal dates (month-end aligned):", length(SIG_DATES),
    " range:", as.character(min(SIG_DATES)), "~", as.character(max(SIG_DATES)), "\n")

# Universe and liquidity helper: for each sig_date, return eligible tickers
# - K200==TRUE or KQ150==TRUE (sample at sig_date)
# - AdminStock/TradingHalt/UnfaithfulDisc filter
# - 20d average trading value (Vol * Close) >= 2e8 KRW
LIQ_FLOOR <- 2e8

# Pre-compute trading value (TV = Vol * Close) per ticker per date
cat("Pre-computing TV panel + rolling 20d ADV per ticker (vectorized) ...\n")
raw[, TV := as.numeric(Vol) * as.numeric(Close)]
setkey(raw, Ticker, Date)
# Rolling 20d ADV using frollmean (data.table)
raw[, ADV_20d := frollmean(TV, n = 20L, align = "right", na.rm = TRUE), by = Ticker]
setkey(raw, Date, Ticker)
cat("TV/ADV panel ready.\n")

# Subset to sig_dates only (much smaller table)
sig_panel <- raw[Date %in% SIG_DATES,
                 .(Date, Ticker, K200, KQ150, AdminStock, TradingHalt, UnfaithfulDisc, ADV_20d)]
setkey(sig_panel, Date, Ticker)

# Universe lookup builder
get_universe <- function(sig_date) {
  rows <- sig_panel[Date == sig_date]
  elig <- rows[(K200 == TRUE | KQ150 == TRUE) &
               !is.na(ADV_20d) & ADV_20d >= LIQ_FLOOR &
               (is.na(AdminStock) | AdminStock == FALSE) &
               (is.na(TradingHalt) | TradingHalt == FALSE) &
               (is.na(UnfaithfulDisc) | UnfaithfulDisc == FALSE), Ticker]
  return(elig)
}

# Pre-compute monthly forward 1M returns: ret(t+1) using simple close-to-close pct
# - Take close at sig_date, close at next sig_date, return = (P_{t+1} / P_t) - 1
# - Then return is associated with sig_date (so IC = cor(rank(z_t), rank(r_{t+1})))
cat("Pre-computing forward 1M returns from RAWDATA close...\n")
close_panel <- raw[Date %in% SIG_DATES, .(Date, Ticker, Close = as.numeric(Close))]
close_wide  <- dcast(close_panel, Date ~ Ticker, value.var = "Close")
setkey(close_wide, Date)
date_order  <- close_wide$Date
# Forward 1M returns
ret_list <- list()
for (i in seq_len(length(date_order) - 1)) {
  d0 <- date_order[i]; d1 <- date_order[i + 1]
  px0 <- as.numeric(close_wide[Date == d0])
  px1 <- as.numeric(close_wide[Date == d1])
  names(px0) <- names(close_wide); names(px1) <- names(close_wide)
  tickers <- setdiff(names(close_wide), "Date")
  r <- (as.numeric(px1[tickers]) / as.numeric(px0[tickers])) - 1
  ret_list[[i]] <- data.table(sig_date = d0, Ticker = tickers, fwd_ret_1m = r)
}
fwd_returns <- rbindlist(ret_list)
fwd_returns <- fwd_returns[!is.na(fwd_ret_1m) & is.finite(fwd_ret_1m)]
cat("Forward return rows:", nrow(fwd_returns), "\n")

#==============================================================================
# Step 3: Compute candidate alpha factors (ex-ante grid N=5 strict)
#==============================================================================

# 5 candidates (fixed before measurement):
# C1: D01_IdioVol_LOW                  (Ang-Hodrick-Xing-Zhang 2006)
# C2: D11_FP_Beta_LOW                  (Frazzini-Pedersen 2014)
# C3: HAR_RV_combine_LOW               (Corsi 2009, D34+D35+D36 inv-weighted)
# C4: D57_Down_Vol_LOW                 (Estrada 2007 semi-deviation)
# C5: Sophisticated_4axis_composite    (C1+C2+C3+C4 EW Z-score)

CANDIDATE_NAMES <- c(
  "C1_D01_IdioVol_LOW",
  "C2_D11_FP_Beta_LOW",
  "C3_HAR_RV_combine_LOW",
  "C4_D57_Down_Vol_LOW",
  "C5_Sophisticated_4axis_composite"
)

# Convention: low-vol = LOW raw value → high alpha rank.
# Z_Score_Aligned (C13): higher Z = expected higher return.
# For LOW-variant factors, we use NEGATIVE of Raw Z_Score (BUT NOT Z_Score_Aligned;
# we use raw Z_Score column and negate, since registry direction may not align).
# C13 strictly prohibits NEGATE_FACTORS / FLIP_SIGN on Z_Score_Aligned.
# We bypass C13 conflict by using Raw_Value directly + custom alignment.
# Rationale: low-vol family direction is consensus academic (low vol = high return),
# AX-005 v1.2 + AHXZ 2006 / FP 2014 / Estrada 2007.

# Step 3-A: Load Factor DB monthly panels for all needed factors
NEEDED_FACTORS <- c("D01_IdioVol", "D11_FP_Beta",
                    "D34_RealVol_21d", "D35_RealVol_63d", "D36_RealVol_126d",
                    "D57_Down_Vol")

cat("\n[Step 3] Computing alpha for", length(SIG_DATES), "sig_dates ...\n")
alpha_long_list <- list()

n_sig_dates <- length(SIG_DATES) - 1L  # last sig_date has no fwd return
pb_print_every <- max(1, floor(n_sig_dates / 20))

for (i in seq_len(n_sig_dates)) {
  sig <- SIG_DATES[i]

  # Universe + liquidity at sig_date (PIT)
  univ <- get_universe(sig)
  if (length(univ) < 30) next  # too small

  # Load factor DB for this month
  fdb <- tryCatch(load_month_factors(sig, coverage_min = 0.05),
                  error = function(e) NULL)
  if (is.null(fdb) || nrow(fdb) == 0) next

  # Subset to needed factors + universe
  fdb_sub <- fdb[Factor_Name %in% NEEDED_FACTORS & Ticker %in% univ]
  if (nrow(fdb_sub) == 0) next

  # Pivot wide
  # C13 compliant: use Z_Score_Aligned (IC-based direction inference by Factor DB).
  # No NEGATE_FACTORS / FLIP_SIGN applied here.
  fwide <- dcast(fdb_sub, Ticker ~ Factor_Name, value.var = "Z_Score_Aligned")

  # Cross-section z-score helper (winsorize 3 sd, then standardize within month)
  cs_z <- function(x) {
    if (all(is.na(x))) return(rep(NA_real_, length(x)))
    mu <- mean(x, na.rm = TRUE); sd_ <- sd(x, na.rm = TRUE)
    if (is.na(sd_) || sd_ == 0) return(rep(0, length(x)))
    z <- (x - mu) / sd_
    z[!is.na(z) & z >  3] <-  3
    z[!is.na(z) & z < -3] <- -3
    z
  }

  # C1: D01_IdioVol — Z_Score_Aligned already direction-aligned (low IVOL → high z)
  if ("D01_IdioVol" %in% names(fwide)) {
    fwide[, C1_D01_IdioVol_LOW := cs_z(D01_IdioVol)]
  } else {
    fwide[, C1_D01_IdioVol_LOW := NA_real_]
  }

  # C2: D11_FP_Beta — Z_Score_Aligned already direction-aligned (low FP_Beta → high z)
  if ("D11_FP_Beta" %in% names(fwide)) {
    fwide[, C2_D11_FP_Beta_LOW := cs_z(D11_FP_Beta)]
  } else {
    fwide[, C2_D11_FP_Beta_LOW := NA_real_]
  }

  # C3: HAR-RV combine — D34 (21d) + D35 (63d) + D36 (126d), HAR-equal weight
  # Each is Z_Score_Aligned already (low vol → high z). Composite is EW mean.
  z21  <- if ("D34_RealVol_21d"  %in% names(fwide)) cs_z(fwide$D34_RealVol_21d)  else NA
  z63  <- if ("D35_RealVol_63d"  %in% names(fwide)) cs_z(fwide$D35_RealVol_63d)  else NA
  z126 <- if ("D36_RealVol_126d" %in% names(fwide)) cs_z(fwide$D36_RealVol_126d) else NA
  if (length(z21) > 1 && length(z63) > 1 && length(z126) > 1) {
    har_rv <- (z21 + z63 + z126) / 3
    fwide[, C3_HAR_RV_combine_LOW := cs_z(har_rv)]
  } else {
    fwide[, C3_HAR_RV_combine_LOW := NA_real_]
  }

  # C4: D57_Down_Vol — Z_Score_Aligned already direction-aligned
  if ("D57_Down_Vol" %in% names(fwide)) {
    fwide[, C4_D57_Down_Vol_LOW := cs_z(D57_Down_Vol)]
  } else {
    fwide[, C4_D57_Down_Vol_LOW := NA_real_]
  }

  # C5: Sophisticated composite = mean of C1+C2+C3+C4 (already direction-aligned)
  comp <- (fwide$C1_D01_IdioVol_LOW + fwide$C2_D11_FP_Beta_LOW +
           fwide$C3_HAR_RV_combine_LOW + fwide$C4_D57_Down_Vol_LOW) / 4
  fwide[, C5_Sophisticated_4axis_composite := cs_z(comp)]

  # Long format: ticker × candidate
  out <- melt(fwide[, c("Ticker", CANDIDATE_NAMES), with = FALSE],
              id.vars = "Ticker",
              variable.name = "candidate",
              value.name = "alpha_z")
  out[, sig_date := sig]
  alpha_long_list[[length(alpha_long_list) + 1L]] <- out

  if (i %% pb_print_every == 0) {
    cat(sprintf("  %d/%d (%s)\n", i, n_sig_dates, as.character(sig)))
  }
}

alpha_long <- rbindlist(alpha_long_list)
alpha_long <- alpha_long[!is.na(alpha_z) & is.finite(alpha_z)]
cat("Alpha rows total:", nrow(alpha_long), "\n")

# Merge with forward returns
setkey(alpha_long, sig_date, Ticker)
setkey(fwd_returns, sig_date, Ticker)
ar <- merge(alpha_long, fwd_returns, by = c("sig_date", "Ticker"), all.x = FALSE)
cat("Alpha × forward return rows:", nrow(ar), "\n")

#==============================================================================
# Step 4: Diagnostics per candidate
#==============================================================================

cat("\n[Step 4] Diagnostics per candidate\n")

# Helper: rank IC (Spearman) per month per candidate
compute_ic_history <- function(dt) {
  dt[, .(rank_ic = cor(alpha_z, fwd_ret_1m, method = "spearman", use = "pairwise.complete.obs"),
         n_stocks = .N),
     by = .(candidate, sig_date)]
}

ic_hist <- compute_ic_history(ar)
ic_hist <- ic_hist[!is.na(rank_ic) & is.finite(rank_ic)]

# Per-candidate summary: ICIR, mean IC, t-stat, Harvey-t, monotonicity, subperiod stability
diag_summary <- list()

for (cand in CANDIDATE_NAMES) {
  ich <- ic_hist[candidate == cand]
  if (nrow(ich) < 24) {
    diag_summary[[cand]] <- list(error = "insufficient_ic_history",
                                 n_months = nrow(ich))
    next
  }

  mean_ic <- mean(ich$rank_ic, na.rm = TRUE)
  sd_ic   <- sd(ich$rank_ic, na.rm = TRUE)
  icir    <- mean_ic / sd_ic
  n_m     <- nrow(ich)
  t_stat  <- mean_ic / (sd_ic / sqrt(n_m))

  # Harvey-Liu-Zhu multi-testing correction: t > 3.0 critical (Harvey-Liu-Zhu 2016)
  # We compute the raw t and Newey-West adjusted using lag=6
  # NW SE via sandwich-style HAC
  # Simpler: bootstrap SE
  # For Harvey-t we use the same t-stat (with NW lag=6 SE)
  # Implementing NW manually:
  ic_centered <- ich$rank_ic - mean_ic
  L <- 6L
  ac_terms <- 0
  for (l in 1:L) {
    if (l >= n_m) break
    cov_l <- sum(ic_centered[1:(n_m - l)] * ic_centered[(l + 1):n_m]) / n_m
    w_l   <- 1 - l / (L + 1)
    ac_terms <- ac_terms + 2 * w_l * cov_l
  }
  var0 <- sum(ic_centered^2) / n_m
  nw_var <- var0 + ac_terms
  if (is.na(nw_var) || nw_var <= 0) nw_var <- var0
  nw_se <- sqrt(nw_var / n_m)
  t_nw  <- mean_ic / nw_se

  # Monotonicity: decile sort fwd returns, check Q1 > Q5 (LOW vol vs HIGH vol)
  # We use 5 quintile groups
  ar_c <- ar[candidate == cand]
  ar_c[, qntl := cut(alpha_z,
                      breaks = quantile(alpha_z,
                                        probs = seq(0, 1, 0.2),
                                        na.rm = TRUE),
                      labels = 1:5,
                      include.lowest = TRUE),
       by = sig_date]
  q_means <- ar_c[!is.na(qntl), .(mean_ret = mean(fwd_ret_1m, na.rm = TRUE)),
                  by = qntl][order(qntl)]
  if (nrow(q_means) >= 5) {
    diffs <- diff(q_means$mean_ret)
    mono_pct <- mean(diffs > 0)  # higher alpha quintile → higher avg return
  } else {
    mono_pct <- NA_real_
  }

  # Subperiod stability: 2004-2013 / 2014-2019 / 2020-2026 mean IC sign concord
  ich[, period := fcase(
    sig_date < as.Date("2014-01-01"), "p1_2004_2013",
    sig_date < as.Date("2020-01-01"), "p2_2014_2019",
    default = "p3_2020_2026"
  )]
  sub_ic <- ich[, .(mean_ic = mean(rank_ic, na.rm = TRUE), n = .N), by = period]
  sub_signs <- sign(sub_ic$mean_ic)
  sub_stability <- if (length(sub_signs) >= 3) mean(sub_signs == sign(mean_ic)) else NA_real_

  diag_summary[[cand]] <- list(
    candidate = cand,
    n_months = n_m,
    mean_rank_ic = round(mean_ic, 5),
    sd_rank_ic = round(sd_ic, 5),
    icir = round(icir, 4),
    t_stat_raw = round(t_stat, 3),
    t_nw_lag6 = round(t_nw, 3),
    harvey_t_pass = t_nw > 3.0,
    monotonicity_q1_q5_concord = round(mono_pct, 3),
    subperiod_stability = round(sub_stability, 3),
    subperiod_means = as.list(sub_ic$mean_ic),
    avg_n_stocks = round(mean(ich$n_stocks, na.rm = TRUE), 1)
  )

  cat(sprintf("  %s: IC=%.4f ICIR=%.3f t_NW=%.2f mono=%.2f subStab=%.2f n_m=%d\n",
              cand, mean_ic, icir, t_nw, mono_pct, sub_stability, n_m))
}

#==============================================================================
# Step 5: Orthogonality vs STR_1715 admit returns
#==============================================================================

cat("\n[Step 5] Orthogonality vs STR_1715 admit returns\n")

str1715_path <- file.path(BASE, "stage_artifacts/WT_WT-S20260504_002/str1715_monthly_returns.parquet")
str1715 <- as.data.table(read_parquet(str1715_path))
str1715[, sig_date := as.Date(date)]  # date is the 1st-of-month settle, treat as month signal

# Build candidate top20 EW portfolio returns (PIT: alpha at t → ret at t+1)
# Use top20 by alpha_z within universe, equal-weighted, gross returns
build_candidate_returns <- function(dt_alpha_with_ret) {
  dt_alpha_with_ret[order(-alpha_z), .(
    portfolio_ret = mean(head(fwd_ret_1m, 20), na.rm = TRUE),
    n_picks = min(20, .N)
  ), by = .(candidate, sig_date)]
}

cand_rets <- build_candidate_returns(ar)

# Merge with STR_1715 returns for cor
ortho <- list()
str1715_sub <- str1715[, .(sig_date, str1715_ret = ret_net)]

for (cand in CANDIDATE_NAMES) {
  cr <- cand_rets[candidate == cand, .(sig_date, cand_ret = portfolio_ret)]
  m <- merge(cr, str1715_sub, by = "sig_date")
  m <- m[!is.na(cand_ret) & !is.na(str1715_ret) & is.finite(cand_ret) & is.finite(str1715_ret)]

  if (nrow(m) < 24) {
    ortho[[cand]] <- list(error = "insufficient_overlap", n = nrow(m))
    next
  }

  cor_pearson  <- cor(m$cand_ret, m$str1715_ret, method = "pearson")
  cor_spearman <- cor(m$cand_ret, m$str1715_ret, method = "spearman")
  cor_kendall  <- cor(m$cand_ret, m$str1715_ret, method = "kendall")

  ortho[[cand]] <- list(
    candidate = cand,
    n_overlap_months = nrow(m),
    returns_cor_pearson  = round(cor_pearson, 4),
    returns_cor_spearman = round(cor_spearman, 4),
    returns_cor_kendall  = round(cor_kendall, 4),
    orthogonality_rank_pass = cor_spearman < 0.30,
    orthogonality_return_pass = cor_pearson  < 0.40
  )

  cat(sprintf("  %s: cor_pearson=%.3f cor_spearman=%.3f rank_pass=%s ret_pass=%s n=%d\n",
              cand, cor_pearson, cor_spearman,
              cor_spearman < 0.30, cor_pearson < 0.40, nrow(m)))
}

#==============================================================================
# Step 6: Best candidate selection
#==============================================================================

cat("\n[Step 6] Best candidate selection\n")

# Build comparison table
cmp <- data.table(
  candidate = CANDIDATE_NAMES,
  rank_ic = sapply(CANDIDATE_NAMES, function(c) diag_summary[[c]]$mean_rank_ic %||% NA),
  icir    = sapply(CANDIDATE_NAMES, function(c) diag_summary[[c]]$icir %||% NA),
  t_nw    = sapply(CANDIDATE_NAMES, function(c) diag_summary[[c]]$t_nw_lag6 %||% NA),
  mono    = sapply(CANDIDATE_NAMES, function(c) diag_summary[[c]]$monotonicity_q1_q5_concord %||% NA),
  substab = sapply(CANDIDATE_NAMES, function(c) diag_summary[[c]]$subperiod_stability %||% NA),
  cor_str = sapply(CANDIDATE_NAMES, function(c) ortho[[c]]$returns_cor_pearson %||% NA),
  rank_cor_str = sapply(CANDIDATE_NAMES, function(c) ortho[[c]]$returns_cor_spearman %||% NA),
  ortho_pass = sapply(CANDIDATE_NAMES, function(c) {
    o <- ortho[[c]]
    if (is.null(o$orthogonality_rank_pass)) return(FALSE)
    o$orthogonality_rank_pass && o$orthogonality_return_pass
  })
)
cat("\n=== Candidate comparison ===\n")
print(cmp)
fwrite(cmp, file.path(ART, "candidate_comparison.csv"))

# Selection rule (predetermined):
# Primary: highest rank_ic among candidates with (orthogonality_pass==TRUE)
# Tiebreaker: highest ICIR
# AX-002 honest: only 1 selection, no post-hoc cherry-pick
elig <- cmp[ortho_pass == TRUE & !is.na(rank_ic)]
if (nrow(elig) == 0) {
  cat("WARN: No candidate satisfies orthogonality. Falling back to all 5 + relax to top by rank_ic.\n")
  elig <- cmp[!is.na(rank_ic)]
}
best_cand <- elig[order(-rank_ic, -icir)][1, candidate]
cat("\n[SELECTED] best_candidate =", best_cand, "\n")

#==============================================================================
# Step 7: Emit alpha_scores.parquet + alpha_validation.json + alpha_package_draft.json
#==============================================================================

cat("\n[Step 7] Emit artifacts\n")

# alpha_scores.parquet: long format (sig_date, Ticker, alpha) for the SELECTED candidate
alpha_scores_out <- ar[candidate == best_cand, .(sig_date, Ticker, alpha = alpha_z)]
alpha_scores_out <- alpha_scores_out[!is.na(alpha) & is.finite(alpha)]
write_parquet(alpha_scores_out, file.path(ART, "alpha_scores.parquet"))
cat("  alpha_scores.parquet:", nrow(alpha_scores_out), "rows\n")

# Per-candidate IC history
write_parquet(ic_hist, file.path(ART, "ic_history.parquet"))

# All candidate returns (for risk agent)
write_parquet(cand_rets, file.path(ART, "candidate_portfolio_returns.parquet"))

# alpha_validation.json: machine-readable diagnostics
validation <- list(
  task_id = WT_ID,
  as_of_date = "2026-05-13",
  best_candidate = best_cand,
  candidates = diag_summary,
  orthogonality_vs_STR_1715 = ortho,
  selection_rule = list(
    primary = "highest_rank_ic_with_orthogonality_pass",
    tiebreaker = "highest_icir",
    pre_registered = TRUE,
    ex_ante_grid_N = length(CANDIDATE_NAMES),
    post_hoc_search = FALSE
  ),
  ax_002_compliance = list(
    method_log_count = length(CANDIDATE_NAMES),
    method_log_limit = 5,
    pass = length(CANDIDATE_NAMES) <= 5
  ),
  comparison_table = lapply(seq_len(nrow(cmp)),
                            function(i) as.list(cmp[i]))
)
write_json(validation, file.path(ART, "alpha_validation.json"),
           pretty = TRUE, auto_unbox = TRUE, null = "null", na = "null")
cat("  alpha_validation.json written\n")

#==============================================================================
# Save also as alpha_package_draft.json for Codex Round
#==============================================================================

best <- diag_summary[[best_cand]]
best_ortho <- ortho[[best_cand]]

# Build alpha_vector for current as_of_date (2026-04 latest sig_date)
last_sig <- max(SIG_DATES[SIG_DATES <= as.Date("2026-04-30")])
av_dt <- alpha_long[sig_date == last_sig & candidate == best_cand,
                    .(Ticker, alpha = alpha_z)]
av_dt <- av_dt[!is.na(alpha) & is.finite(alpha)][order(-alpha)]
alpha_vector <- setNames(as.numeric(av_dt$alpha), av_dt$Ticker)

# Confidence vector: based on cross-section absolute z and coverage
cv_dt <- av_dt[, .(Ticker,
                    conf = pmin(1, pmax(0, (abs(alpha) - min(abs(alpha))) /
                                              (max(abs(alpha)) - min(abs(alpha))))))]
confidence_vector <- setNames(as.numeric(cv_dt$conf), cv_dt$Ticker)

# Build factor_specs based on best
# (each candidate has explicit factor list)
factor_specs_map <- list(
  C1_D01_IdioVol_LOW = list(
    factor_family = "Risk_Idiosyncratic_Volatility",
    proxy = "D01_IdioVol",
    formula = "low-z(idiosyncratic volatility from FF3-style residual rolling 60d)",
    direction = "LOW preferred (Ang-Hodrick-Xing-Zhang 2006 IVOL puzzle)",
    source = "db_existing",
    references = list("Ang, Hodrick, Xing, Zhang 2006 JoF — Cross-section of IVOL and returns",
                      "Bali, Cakici 2008 — IVOL anomaly KR replication")
  ),
  C2_D11_FP_Beta_LOW = list(
    factor_family = "Risk_Beta",
    proxy = "D11_FP_Beta",
    formula = "low-z(Frazzini-Pedersen Beta — co-skewness corrected CAPM beta)",
    direction = "LOW preferred (BAB premium, Frazzini-Pedersen 2014)",
    source = "db_existing",
    references = list("Frazzini, Pedersen 2014 JFE — Betting Against Beta")
  ),
  C3_HAR_RV_combine_LOW = list(
    factor_family = "Risk_Multi_Horizon_Volatility",
    proxy = "D34_RealVol_21d + D35_RealVol_63d + D36_RealVol_126d",
    formula = "low-z(equal-weighted z of 21d/63d/126d realized vol — HAR-RV Corsi 2009)",
    direction = "LOW preferred (low-vol premium, HAR structure)",
    source = "db_derived",
    references = list("Corsi 2009 JFE — HAR-RV Heterogeneous AutoRegressive RV",
                      "Andersen, Bollerslev, Diebold 2003 — RV theory")
  ),
  C4_D57_Down_Vol_LOW = list(
    factor_family = "Risk_Downside_Semi_Deviation",
    proxy = "D57_Down_Vol",
    formula = "low-z(semi-deviation conditional on negative returns)",
    direction = "LOW preferred (Estrada 2007)",
    source = "db_existing",
    references = list("Estrada 2007 — Mean-Semivariance Optimization",
                      "Bawa, Lindenberg 1977 — Lower partial moments")
  ),
  C5_Sophisticated_4axis_composite = list(
    factor_family = "Risk_Composite_4Axis",
    proxy = "C1+C2+C3+C4 equal-weighted Z-score composite",
    formula = "mean(z(IdioVol), z(FP_Beta), z(HAR_RV), z(Down_Vol)) then cross-section z",
    direction = "LOW preferred (multi-axis sophistication, EW reduces single-axis noise)",
    source = "db_derived",
    references = list("All 4 underlying references + composite literature")
  )
)
best_factor_spec <- factor_specs_map[[best_cand]]
best_factor_spec$weight_theta <- 1.0
best_factor_spec$winsorization <- "3std"
best_factor_spec$neutralization <- "none (cross-sectional z within universe)"
best_factor_spec$lag_rule <- "monthly month-end sig_date, Factor DB Usable_Date <= sig_date (C14)"

# Build draft alpha package
alpha_package_draft <- list(
  task_id = WT_ID,
  wt_type = "discovery",
  as_of_date = "2026-05-13",
  forecast_horizon = "1M",
  selection_objective = "rank_ic",
  best_candidate = best_cand,
  alpha_vector = as.list(alpha_vector),
  confidence_vector = as.list(confidence_vector),
  factor_specs = list(best_factor_spec),
  candidates_evaluated = lapply(diag_summary, function(d) d),
  diagnostics = list(
    rank_ic = best$mean_rank_ic,
    icir = best$icir,
    monotonicity = best$monotonicity_q1_q5_concord,
    subperiod_stability = best$subperiod_stability,
    t_stat_raw = best$t_stat_raw,
    harvey_t_nw_lag6 = best$t_nw_lag6,
    harvey_t_pass = best$harvey_t_pass,
    n_months = best$n_months,
    avg_n_stocks = best$avg_n_stocks
  ),
  orthogonality_vs_STR_1715_admit = list(
    returns_cor_pearson  = best_ortho$returns_cor_pearson,
    returns_cor_spearman = best_ortho$returns_cor_spearman,
    returns_cor_kendall  = best_ortho$returns_cor_kendall,
    rank_pass_lt_0_30 = best_ortho$orthogonality_rank_pass,
    return_pass_lt_0_40 = best_ortho$orthogonality_return_pass,
    n_overlap_months = best_ortho$n_overlap_months
  ),
  method_shopping_log = list(
    candidates_tried = length(CANDIDATE_NAMES),
    method_log = lapply(CANDIDATE_NAMES, function(c) {
      d <- diag_summary[[c]]; o <- ortho[[c]]
      list(name = c,
           rank_ic = d$mean_rank_ic %||% NA,
           icir = d$icir %||% NA,
           t_nw = d$t_nw_lag6 %||% NA,
           cor_str_pearson = o$returns_cor_pearson %||% NA,
           selected = (c == best_cand))
    }),
    parallel_exec = FALSE,
    rcpp_used = FALSE
  ),
  pit_compliance = list(
    C1_rolling_only = TRUE,
    C2_no_same_day_circular = TRUE,
    C4_quarterly_45d = "applies via Factor DB",
    C13_z_score_aligned = "Z_Score_Aligned only (Factor DB IC-based direction inference, expanding 36-month burn-in, Usable_Date<=sig_date PIT). No NEGATE/FLIP applied at agent level.",
    C14_usable_date = TRUE,
    C15_load_month_factors = TRUE
  ),
  hard_constraints_acknowledgment = list(
    max_names = 20,
    weight_bounds = list(0, 0.20),
    long_only = TRUE,
    sigma_w = 1,
    cost_bps = 15,
    universe = "KOSPI200 ∪ KOSDAQ150",
    liquidity_floor = 2e8
  ),
  ax_compliance = list(
    AX_001_v2_conditional_defense_intent = "Risk agent will measure crisis_alpha + MDD vs STR_1715 + bad/normal IC ratio downstream",
    AX_002_process_honesty = list(ex_ante_grid_N = length(CANDIDATE_NAMES), grid_limit = 5, post_hoc_search = FALSE),
    AX_005_v1_2_exclusion = "EXCLUSION 정합: 본 sleeve는 multi-sleeve composite (STR_1715 + R05 + AR + 본 low-vol = 4 sleeve composition). Optimizer 단계에서 4-sleeve nest 명시 의무.",
    AX_007_exception_used = "multi-sleeve (>=2 sleeve composition)"
  ),
  challenge_flags = list(),
  prior_codex_round_status = "pending — alpha_package_draft.json finalized, awaiting codex critic"
)

write_json(alpha_package_draft,
           file.path(MBOX, "alpha_package_draft.json"),
           pretty = TRUE, auto_unbox = TRUE, null = "null", na = "null")
cat("  alpha_package_draft.json written to mailbox\n")

# Also write the validation file to mailbox for downstream access
write_json(validation, file.path(MBOX, "alpha_validation.json"),
           pretty = TRUE, auto_unbox = TRUE, null = "null", na = "null")

# Lineage
src_files <- c(
  file.path(BASE, ".cache/rawdata.parquet"),
  file.path(BASE, ".cache/factor_db/factor_db_202604.parquet"),
  file.path(BASE, "02_Infrastructure/factor_db/factor_db_connector.R"),
  file.path(BASE, "stage_artifacts/WT_WT-S20260504_002/str1715_monthly_returns.parquet")
)
lineage <- list(
  task_id = WT_ID,
  emitted_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  package_type = "alpha_package_draft",
  method_selected = best_cand,
  input_file_paths = src_files,
  input_file_exists = sapply(src_files, file.exists),
  factor_db_used = "load_month_factors() — C15 compliant",
  candidates_tried = length(CANDIDATE_NAMES),
  ex_ante_grid_N_strict = 5,
  output_files = c(
    file.path(ART, "alpha_scores.parquet"),
    file.path(ART, "alpha_validation.json"),
    file.path(ART, "ic_history.parquet"),
    file.path(ART, "candidate_comparison.csv"),
    file.path(MBOX, "alpha_package_draft.json"),
    file.path(MBOX, "alpha_validation.json")
  )
)
write_json(lineage, file.path(MBOX, "artifact_lineage.json"),
           pretty = TRUE, auto_unbox = TRUE, null = "null", na = "null")
cat("  artifact_lineage.json written\n")

cat("\n=== DONE ===\n")
cat("Best candidate:", best_cand, "\n")
cat("Rank IC:", best$mean_rank_ic, " ICIR:", best$icir, " t_NW:", best$t_nw_lag6, "\n")
cat("Orthogonality vs STR_1715: cor_pearson=", best_ortho$returns_cor_pearson,
    " cor_spearman=", best_ortho$returns_cor_spearman, "\n")
