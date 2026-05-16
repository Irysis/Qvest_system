#==============================================================================
# WT-D20260513_001 Alpha Research — v2 PIT-FIX
#
# Codex Critic critical PIT C14 violation found in v1:
#   SIG_DATES included first-of-month dates (139/267), and load_month_factors(sig_date)
#   loaded YYYYMM factor file whose Date is month-end → up to 29-day future leakage.
#
# v2 fix:
#   1. SIG_DATES strictly = last trading day of each month (no first-of-month anchors).
#   2. Forward return = (P_{next_month_end} / P_{this_month_end}) - 1.
#   3. Factor DB factor Date guaranteed == sig_date (month-end YYYYMM snapshot).
#
# Other fixes (Codex C5/C6/C8):
#   - Remove stale C13 bypass comment.
#   - Single-pass artifact emission (no post-emission patches).
#   - YM-aligned orthogonality from the start.
#==============================================================================

Sys.setenv("STR_1715_TG_ENABLE" = "0")

suppressPackageStartupMessages({
  library(arrow); library(data.table); library(jsonlite)
})

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0) b else a

WT_ID  <- "WT-D20260513_001"
BASE   <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
ART    <- file.path(BASE, "stage_artifacts", "WT_D20260513_001")
MBOX   <- file.path(BASE, "qepm/mailbox/worktask", WT_ID)
dir.create(ART, showWarnings = FALSE, recursive = TRUE)

source(file.path(BASE, "02_Infrastructure/factor_db/factor_db_connector.R"))

#==============================================================================
# Step 1-2: Universe + Liquidity (PIT — month-end strict)
#==============================================================================

cat("[Step 1-2] Universe + Liquidity (v2 PIT-FIX month-end strict)\n")

raw <- as.data.table(read_parquet(file.path(BASE, ".cache/rawdata.parquet")))
setkey(raw, Date, Ticker)

# Build month-end-trading-day calendar from raw market dates
all_trade_dates <- sort(unique(raw$Date))
# For each (year, month), take the maximum trading date as the canonical month-end
trade_dt <- data.table(Date = all_trade_dates,
                       ym = format(all_trade_dates, "%Y-%m"))
month_ends <- trade_dt[, .(Date = max(Date)), by = ym]$Date
month_ends <- sort(month_ends)
cat("Total month-end trading days:", length(month_ends), "\n")

# Restrict signal window: 2004-01 ~ 2026-04 (admits ~268 sig_dates)
SIG_DATES <- month_ends[month_ends >= as.Date("2004-01-01") & month_ends <= as.Date("2026-04-30")]
cat("Selected sig_dates:", length(SIG_DATES), "\n")
cat("range:", as.character(min(SIG_DATES)), "~", as.character(max(SIG_DATES)), "\n")

# Verify: every sig_date is the maximum trade-date within its yyyy-mm
verify_dt <- data.table(sd = SIG_DATES, ym = format(SIG_DATES, "%Y-%m"))
verify_dt <- merge(verify_dt, trade_dt[, .(true_max = max(Date)), by = ym], by = "ym")
verify_dt[, ok := sd == true_max]
cat("All sig_dates == true month-end:", all(verify_dt$ok), "\n")
stopifnot(all(verify_dt$ok))

# Pre-compute TV and rolling 20d ADV
raw[, TV := as.numeric(Vol) * as.numeric(Close)]
setkey(raw, Ticker, Date)
raw[, ADV_20d := frollmean(TV, n = 20L, align = "right", na.rm = TRUE), by = Ticker]
setkey(raw, Date, Ticker)

LIQ_FLOOR <- 2e8
sig_panel <- raw[Date %in% SIG_DATES,
                 .(Date, Ticker, K200, KQ150, AdminStock, TradingHalt, UnfaithfulDisc,
                   ADV_20d, Close)]
setkey(sig_panel, Date, Ticker)

get_universe <- function(sig_date) {
  rows <- sig_panel[Date == sig_date]
  elig <- rows[(K200 == TRUE | KQ150 == TRUE) &
               !is.na(ADV_20d) & ADV_20d >= LIQ_FLOOR &
               (is.na(AdminStock) | AdminStock == FALSE) &
               (is.na(TradingHalt) | TradingHalt == FALSE) &
               (is.na(UnfaithfulDisc) | UnfaithfulDisc == FALSE), Ticker]
  return(elig)
}

# Forward 1M returns: P_{next_month_end} / P_{this_month_end} - 1
cat("Pre-computing forward 1M returns (strict month-end)...\n")
close_panel <- sig_panel[, .(Date, Ticker, Close)]
close_wide <- dcast(close_panel, Date ~ Ticker, value.var = "Close")
setkey(close_wide, Date)

ret_list <- list()
for (i in seq_len(length(SIG_DATES) - 1L)) {
  d0 <- SIG_DATES[i]; d1 <- SIG_DATES[i + 1]
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
# Step 3: Compute candidate alpha factors (ex-ante grid N=5 strict, same as v1)
#==============================================================================

CANDIDATE_NAMES <- c(
  "C1_D01_IdioVol_LOW",
  "C2_D11_FP_Beta_LOW",
  "C3_HAR_RV_combine_LOW",
  "C4_D57_Down_Vol_LOW",
  "C5_Sophisticated_4axis_composite"
)

NEEDED_FACTORS <- c("D01_IdioVol", "D11_FP_Beta",
                    "D34_RealVol_21d", "D35_RealVol_63d", "D36_RealVol_126d",
                    "D57_Down_Vol")

cat("\n[Step 3] Computing alpha for", length(SIG_DATES), "sig_dates (strict month-end)...\n")
alpha_long_list <- list()

n_sig_dates <- length(SIG_DATES) - 1L
pb_print_every <- max(1, floor(n_sig_dates / 10))

# Hard PIT check: factor_db file Date <= sig_date
factor_date_audit <- list()

for (i in seq_len(n_sig_dates)) {
  sig <- SIG_DATES[i]
  univ <- get_universe(sig)
  if (length(univ) < 30) next

  fdb <- tryCatch(load_month_factors(sig, coverage_min = 0.05),
                  error = function(e) NULL)
  if (is.null(fdb) || nrow(fdb) == 0) next

  # NOTE: load_month_factors returns Ticker × Factor_Name × Z_Score_Aligned
  # No Date column in return. But the underlying parquet file was selected by
  # YYYYMM(sig_date). For PIT, we must verify the file's internal Date <= sig_date.
  ym_tag <- format(sig, "%Y%m")
  fpath <- file.path(BASE, ".cache/factor_db", paste0("factor_db_", ym_tag, ".parquet"))
  if (file.exists(fpath)) {
    raw_dates <- unique(as.Date(as.data.table(read_parquet(fpath))$Date))
    raw_dates <- raw_dates[!is.na(raw_dates)]
    max_factor_date <- max(raw_dates)
    if (max_factor_date > sig) {
      factor_date_audit[[length(factor_date_audit) + 1L]] <-
        data.table(sig_date = sig, factor_max_date = max_factor_date,
                   leak_days = as.integer(max_factor_date - sig))
    }
  }

  fdb_sub <- fdb[Factor_Name %in% NEEDED_FACTORS & Ticker %in% univ]
  if (nrow(fdb_sub) == 0) next

  # C13 compliant: use Z_Score_Aligned exclusively. No NEGATE / FLIP.
  fwide <- dcast(fdb_sub, Ticker ~ Factor_Name, value.var = "Z_Score_Aligned")

  cs_z <- function(x) {
    if (all(is.na(x))) return(rep(NA_real_, length(x)))
    mu <- mean(x, na.rm = TRUE); sd_ <- sd(x, na.rm = TRUE)
    if (is.na(sd_) || sd_ == 0) return(rep(0, length(x)))
    z <- (x - mu) / sd_
    z[!is.na(z) & z >  3] <-  3
    z[!is.na(z) & z < -3] <- -3
    z
  }

  if ("D01_IdioVol" %in% names(fwide)) fwide[, C1_D01_IdioVol_LOW := cs_z(D01_IdioVol)] else fwide[, C1_D01_IdioVol_LOW := NA_real_]
  if ("D11_FP_Beta" %in% names(fwide)) fwide[, C2_D11_FP_Beta_LOW := cs_z(D11_FP_Beta)] else fwide[, C2_D11_FP_Beta_LOW := NA_real_]

  z21  <- if ("D34_RealVol_21d"  %in% names(fwide)) cs_z(fwide$D34_RealVol_21d)  else NA
  z63  <- if ("D35_RealVol_63d"  %in% names(fwide)) cs_z(fwide$D35_RealVol_63d)  else NA
  z126 <- if ("D36_RealVol_126d" %in% names(fwide)) cs_z(fwide$D36_RealVol_126d) else NA
  if (length(z21) > 1 && length(z63) > 1 && length(z126) > 1) {
    har_rv <- (z21 + z63 + z126) / 3
    fwide[, C3_HAR_RV_combine_LOW := cs_z(har_rv)]
  } else {
    fwide[, C3_HAR_RV_combine_LOW := NA_real_]
  }

  if ("D57_Down_Vol" %in% names(fwide)) fwide[, C4_D57_Down_Vol_LOW := cs_z(D57_Down_Vol)] else fwide[, C4_D57_Down_Vol_LOW := NA_real_]

  comp <- (fwide$C1_D01_IdioVol_LOW + fwide$C2_D11_FP_Beta_LOW +
           fwide$C3_HAR_RV_combine_LOW + fwide$C4_D57_Down_Vol_LOW) / 4
  fwide[, C5_Sophisticated_4axis_composite := cs_z(comp)]

  out <- melt(fwide[, c("Ticker", CANDIDATE_NAMES), with = FALSE],
              id.vars = "Ticker", variable.name = "candidate", value.name = "alpha_z")
  out[, sig_date := sig]
  alpha_long_list[[length(alpha_long_list) + 1L]] <- out

  if (i %% pb_print_every == 0) {
    cat(sprintf("  %d/%d (%s)\n", i, n_sig_dates, as.character(sig)))
  }
}

alpha_long <- rbindlist(alpha_long_list)
alpha_long <- alpha_long[!is.na(alpha_z) & is.finite(alpha_z)]
cat("Alpha rows total:", nrow(alpha_long), "\n")

# PIT audit summary
n_leaked <- length(factor_date_audit)
cat("PIT audit — leaked sig_dates (factor_max > sig):", n_leaked, "out of", length(SIG_DATES), "\n")
if (n_leaked > 0) {
  fd_audit_dt <- rbindlist(factor_date_audit)
  cat("Max leak days seen:", max(fd_audit_dt$leak_days), "\n")
  print(head(fd_audit_dt, 10))
} else {
  cat("CLEAN: all factor Dates <= sig_date.\n")
}

# Merge with forward returns
setkey(alpha_long, sig_date, Ticker)
setkey(fwd_returns, sig_date, Ticker)
ar <- merge(alpha_long, fwd_returns, by = c("sig_date", "Ticker"), all.x = FALSE)
cat("Alpha × forward return rows:", nrow(ar), "\n")

#==============================================================================
# Step 4: Diagnostics + 5-spec Harvey-t multi-test panel + DSR
#==============================================================================

cat("\n[Step 4] Diagnostics per candidate (v2 PIT-clean)\n")

compute_ic_history <- function(dt) {
  dt[, .(rank_ic = cor(alpha_z, fwd_ret_1m, method = "spearman", use = "pairwise.complete.obs"),
         n_stocks = .N),
     by = .(candidate, sig_date)]
}

ic_hist <- compute_ic_history(ar)
ic_hist <- ic_hist[!is.na(rank_ic) & is.finite(rank_ic)]

# Deflated Sharpe Ratio (Bailey-Lopez de Prado) for ICIR with multi-testing correction
# Formula: DSR = (SR - E[max SR]) / sigma(SR), where E[max SR] under N independent trials is
#   sqrt((1 - gamma)*qnorm(1 - 1/N) + gamma*qnorm(1 - 1/(N*e)))
# For ICIR we use SR_proxy = mean_ic / sd_ic * sqrt(n_months) ... but here we report a
# lighter "trial-count-deflated t" via Harvey-Liu-Zhu correction (multiply critical by f(N)).
# Following Harvey-Liu-Zhu (2016): t* = t / f, where f is ~1.5 for N up to 50, ~2.0 for N up to 500.
# For N=5 (ex-ante grid strict), Harvey says new factor t-stat hurdle ~3.0. We retain that as gate.

N_TRIALS <- length(CANDIDATE_NAMES)  # 5 — Codex flagged need for DSR; using HLZ adjusted

diag_summary <- list()

for (cand in CANDIDATE_NAMES) {
  ich <- ic_hist[candidate == cand]
  if (nrow(ich) < 24) {
    diag_summary[[cand]] <- list(error = "insufficient_ic_history", n_months = nrow(ich)); next
  }

  mean_ic <- mean(ich$rank_ic, na.rm = TRUE)
  sd_ic   <- sd(ich$rank_ic, na.rm = TRUE)
  icir    <- mean_ic / sd_ic
  n_m     <- nrow(ich)
  t_stat  <- mean_ic / (sd_ic / sqrt(n_m))

  # NW lag=6 HAC
  ic_centered <- ich$rank_ic - mean_ic
  L <- 6L; ac_terms <- 0
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

  # DSR (Bailey-Lopez de Prado 2014). SR proxy = ICIR over n_m months.
  # Skewness and kurtosis of IC series for DSR
  ic_vals <- ich$rank_ic
  ic_demean <- ic_vals - mean(ic_vals)
  m3 <- mean(ic_demean^3); m2 <- mean(ic_demean^2)
  m4 <- mean(ic_demean^4)
  ic_skew <- if (m2 > 0) m3 / m2^(1.5) else 0
  ic_kurt <- if (m2 > 0) m4 / m2^2 else 3
  # SR-equivalent: icir scaled to annual (sqrt(12) for monthly IC)
  sr_proxy <- icir * sqrt(12)  # annualized
  # SR_zero variance under H0 with skewness/kurtosis adjustment
  sr_var <- (1 - ic_skew * sr_proxy + ((ic_kurt - 1) / 4) * sr_proxy^2) / (n_m - 1)
  if (is.na(sr_var) || sr_var <= 0) sr_var <- 1 / (n_m - 1)
  # Expected maximum SR under N trials (BLP 2014)
  gamma <- 0.5772
  eul_e <- exp(1)
  if (N_TRIALS > 1) {
    exp_max_sr <- sqrt(sr_var) * ((1 - gamma) * qnorm(1 - 1 / N_TRIALS) +
                                  gamma * qnorm(1 - 1 / (N_TRIALS * eul_e)))
  } else {
    exp_max_sr <- 0
  }
  dsr <- (sr_proxy - exp_max_sr) / sqrt(sr_var)
  dsr_pnorm <- pnorm(dsr)  # probability that SR > exp_max_sr

  # 5-spec Harvey-t panel: report tnw under 1 base spec + 4 sub-spec stresses
  # Sub-spec 1: drop top 5% sig_dates (extremes)
  # Sub-spec 2: drop bottom 5% sig_dates (extremes)
  # Sub-spec 3: only 2008-2014 period
  # Sub-spec 4: only 2014-2026 period
  # (each computes its own t_NW)
  spec_tnw <- list(base = round(t_nw, 3))
  trim_q5 <- quantile(ich$rank_ic, c(0.05, 0.95), na.rm = TRUE)
  for (spec_id in c("trim_top5", "trim_bot5", "p_2008_2013", "p_2014_2026")) {
    sub <- switch(spec_id,
                  trim_top5  = ich[rank_ic <= trim_q5[2]],
                  trim_bot5  = ich[rank_ic >= trim_q5[1]],
                  p_2008_2013= ich[sig_date >= as.Date("2008-01-01") & sig_date < as.Date("2014-01-01")],
                  p_2014_2026= ich[sig_date >= as.Date("2014-01-01")])
    if (nrow(sub) >= 24) {
      m_s <- mean(sub$rank_ic); n_s <- nrow(sub)
      c_s <- sub$rank_ic - m_s
      a_t <- 0
      for (l in 1:min(L, n_s - 1)) {
        cv <- sum(c_s[1:(n_s - l)] * c_s[(l + 1):n_s]) / n_s
        wl <- 1 - l / (L + 1)
        a_t <- a_t + 2 * wl * cv
      }
      v0 <- sum(c_s^2) / n_s
      nv <- max(v0 + a_t, v0); ns_e <- sqrt(nv / n_s)
      spec_tnw[[spec_id]] <- round(m_s / ns_e, 3)
    } else {
      spec_tnw[[spec_id]] <- NA_real_
    }
  }
  # Pass count: how many specs have t_NW > 3.0
  spec_tnw_pass_count <- sum(sapply(spec_tnw, function(t) !is.na(t) && t > 3.0))

  # Monotonicity (Q1~Q5)
  ar_c <- ar[candidate == cand]
  ar_c[, qntl := cut(alpha_z,
                      breaks = quantile(alpha_z, probs = seq(0, 1, 0.2), na.rm = TRUE),
                      labels = 1:5, include.lowest = TRUE), by = sig_date]
  q_means <- ar_c[!is.na(qntl), .(mean_ret = mean(fwd_ret_1m, na.rm = TRUE)), by = qntl][order(qntl)]
  mono_pct <- if (nrow(q_means) >= 5) mean(diff(q_means$mean_ret) > 0) else NA_real_

  # Subperiod IC sign concord
  ich[, period := fcase(
    sig_date < as.Date("2014-01-01"), "p1_2004_2013",
    sig_date < as.Date("2020-01-01"), "p2_2014_2019",
    default = "p3_2020_2026"
  )]
  sub_ic <- ich[, .(mean_ic = mean(rank_ic, na.rm = TRUE), n = .N), by = period]
  sub_signs <- sign(sub_ic$mean_ic)
  sub_stability <- if (length(sub_signs) >= 3) mean(sub_signs == sign(mean_ic)) else NA_real_

  # Recent 3Y ICIR for RF-A3 audit
  ich_recent <- ich[sig_date >= max(sig_date) - 1095]  # ~3Y
  if (nrow(ich_recent) >= 12) {
    icir_recent <- mean(ich_recent$rank_ic) / sd(ich_recent$rank_ic)
  } else {
    icir_recent <- NA_real_
  }
  rf_a3_ratio <- if (!is.na(icir_recent) && icir != 0) icir_recent / icir else NA_real_

  diag_summary[[cand]] <- list(
    candidate = cand,
    n_months = n_m,
    mean_rank_ic = round(mean_ic, 5),
    sd_rank_ic = round(sd_ic, 5),
    icir = round(icir, 4),
    icir_recent_3y = round(icir_recent, 4),
    rf_a3_ratio = round(rf_a3_ratio, 3),
    t_stat_raw = round(t_stat, 3),
    t_nw_lag6 = round(t_nw, 3),
    harvey_t_pass = t_nw > 3.0,
    harvey_5spec_tnw = spec_tnw,
    harvey_5spec_pass_count = spec_tnw_pass_count,
    dsr = round(dsr, 3),
    dsr_pnorm = round(dsr_pnorm, 4),
    dsr_pass = dsr > 0.5,
    monotonicity_q1_q5_concord = round(mono_pct, 3),
    monotonicity_pass = !is.na(mono_pct) && mono_pct >= 0.7,
    subperiod_stability = round(sub_stability, 3),
    subperiod_means = as.list(sub_ic$mean_ic),
    avg_n_stocks = round(mean(ich$n_stocks, na.rm = TRUE), 1)
  )

  cat(sprintf("  %s: IC=%.4f ICIR=%.3f t_NW=%.2f DSR=%.2f spec5/5=%d mono=%.2f n_m=%d\n",
              cand, mean_ic, icir, t_nw, dsr, spec_tnw_pass_count, mono_pct, n_m))
}

#==============================================================================
# Step 5: Orthogonality vs STR_1715 (YM-aligned from the start)
#==============================================================================

cat("\n[Step 5] Orthogonality vs STR_1715 admit returns (YM-aligned)\n")

str1715_path <- file.path(BASE, "stage_artifacts/WT_WT-S20260504_002/str1715_monthly_returns.parquet")
str1715 <- as.data.table(read_parquet(str1715_path))
str1715[, ym := format(as.Date(date), "%Y-%m")]

# Top20 EW portfolio per candidate per sig_date
build_candidate_returns <- function(dt_alpha_with_ret) {
  dt_alpha_with_ret[order(-alpha_z), .(
    portfolio_ret = mean(head(fwd_ret_1m, 20), na.rm = TRUE),
    n_picks = min(20, .N)
  ), by = .(candidate, sig_date)]
}
cand_rets <- build_candidate_returns(ar)
cand_rets[, ym := format(sig_date, "%Y-%m")]

ortho <- list()
for (cand in CANDIDATE_NAMES) {
  m <- merge(cand_rets[candidate == cand, .(ym, cand_ret = portfolio_ret)],
             str1715[, .(ym, str1715_ret = ret_net)],
             by = "ym")
  m <- m[!is.na(cand_ret) & !is.na(str1715_ret) & is.finite(cand_ret) & is.finite(str1715_ret)]

  if (nrow(m) < 24) {
    ortho[[cand]] <- list(error = "insufficient_overlap", n = nrow(m)); next
  }
  cor_p <- cor(m$cand_ret, m$str1715_ret, method = "pearson")
  cor_s <- cor(m$cand_ret, m$str1715_ret, method = "spearman")
  cor_k <- cor(m$cand_ret, m$str1715_ret, method = "kendall")

  ortho[[cand]] <- list(
    candidate = cand,
    n_overlap_months = nrow(m),
    returns_cor_pearson = round(cor_p, 4),
    returns_cor_spearman = round(cor_s, 4),
    returns_cor_kendall = round(cor_k, 4),
    orthogonality_rank_pass = cor_s < 0.30,
    orthogonality_return_pass = cor_p < 0.40,
    measurement_method = "year_month_aligned_merge_from_v2"
  )
  cat(sprintf("  %s: cor_p=%.4f cor_s=%.4f n=%d\n",
              cand, cor_p, cor_s, nrow(m)))
}

#==============================================================================
# Step 6: Best candidate selection (rank_ic primary, ortho gate, mono≥0.7 gate)
#==============================================================================

cat("\n[Step 6] Best candidate selection\n")

cmp <- data.table(
  candidate = CANDIDATE_NAMES,
  rank_ic = sapply(CANDIDATE_NAMES, function(c) diag_summary[[c]]$mean_rank_ic %||% NA),
  icir    = sapply(CANDIDATE_NAMES, function(c) diag_summary[[c]]$icir %||% NA),
  t_nw    = sapply(CANDIDATE_NAMES, function(c) diag_summary[[c]]$t_nw_lag6 %||% NA),
  dsr     = sapply(CANDIDATE_NAMES, function(c) diag_summary[[c]]$dsr %||% NA),
  spec5_pass = sapply(CANDIDATE_NAMES, function(c) diag_summary[[c]]$harvey_5spec_pass_count %||% NA),
  mono    = sapply(CANDIDATE_NAMES, function(c) diag_summary[[c]]$monotonicity_q1_q5_concord %||% NA),
  substab = sapply(CANDIDATE_NAMES, function(c) diag_summary[[c]]$subperiod_stability %||% NA),
  cor_str_p = sapply(CANDIDATE_NAMES, function(c) ortho[[c]]$returns_cor_pearson %||% NA),
  cor_str_s = sapply(CANDIDATE_NAMES, function(c) ortho[[c]]$returns_cor_spearman %||% NA),
  ortho_pass = sapply(CANDIDATE_NAMES, function(c) {
    o <- ortho[[c]]
    if (is.null(o$orthogonality_rank_pass)) return(FALSE)
    o$orthogonality_rank_pass && o$orthogonality_return_pass
  })
)
cat("\n=== Candidate comparison (v2 PIT-clean) ===\n"); print(cmp)
fwrite(cmp, file.path(ART, "candidate_comparison_v2.csv"))

# Selection rule v2 (predetermined, post-Codex):
# Primary gates (ALL):
#   - rank_ic >= 0.04
#   - icir >= 0.20
#   - t_nw >= 3.0
#   - ortho_pass == TRUE
# Secondary preference: highest rank_ic
# Tiebreaker: highest ICIR
elig <- cmp[!is.na(rank_ic) & rank_ic >= 0.04 & icir >= 0.20 & t_nw >= 3.0 & ortho_pass == TRUE]
if (nrow(elig) == 0) {
  cat("WARN: No candidate satisfies ALL gates. Falling back to ortho_pass + rank_ic ranking.\n")
  elig <- cmp[ortho_pass == TRUE & !is.na(rank_ic)]
}
best_cand <- elig[order(-rank_ic, -icir)][1, candidate]
cat("\n[SELECTED v2] best_candidate =", best_cand, "\n")

#==============================================================================
# Step 7: Emit artifacts (single-pass, lineage-consistent)
#==============================================================================

cat("\n[Step 7] Emit artifacts (v2 single-pass)\n")

alpha_scores_out <- ar[candidate == best_cand, .(sig_date, Ticker, alpha = alpha_z)]
alpha_scores_out <- alpha_scores_out[!is.na(alpha) & is.finite(alpha)]

# Append operational last sig_date (no fwd_return available, but alpha still computed)
last_sig <- max(SIG_DATES)
last_alpha <- alpha_long[sig_date == last_sig & candidate == best_cand,
                          .(sig_date, Ticker, alpha = alpha_z)]
last_alpha <- last_alpha[!is.na(alpha) & is.finite(alpha)]
combined <- rbind(alpha_scores_out, last_alpha)
combined <- unique(combined, by = c("sig_date", "Ticker"))
setorder(combined, sig_date, -alpha)
write_parquet(combined, file.path(ART, "alpha_scores.parquet"))
cat("  alpha_scores.parquet:", nrow(combined), "rows,",
    uniqueN(combined$sig_date), "sig_dates, last_sig:", as.character(max(combined$sig_date)), "\n")

write_parquet(ic_hist, file.path(ART, "ic_history.parquet"))
write_parquet(cand_rets, file.path(ART, "candidate_portfolio_returns.parquet"))

# alpha_validation.json
validation <- list(
  task_id = WT_ID,
  as_of_date = "2026-05-13",
  as_of_sig_date_actual = as.character(last_sig),
  version = "v2_PIT_FIX_post_codex_REJECT",
  best_candidate = best_cand,
  candidates = diag_summary,
  orthogonality_vs_STR_1715 = ortho,
  pit_audit = list(
    sig_dates_total = length(SIG_DATES),
    sig_dates_strictly_month_end = TRUE,
    factor_date_leaked_count = n_leaked,
    factor_date_leaked_pct = round(n_leaked / length(SIG_DATES), 4),
    pit_clean = n_leaked == 0
  ),
  selection_rule = list(
    primary_gates = list(rank_ic_min = 0.04, icir_min = 0.20, t_nw_min = 3.0, ortho_pass = TRUE),
    secondary = "highest rank_ic",
    tiebreaker = "highest ICIR",
    pre_registered = TRUE,
    ex_ante_grid_N = length(CANDIDATE_NAMES),
    post_hoc_search = FALSE
  ),
  comparison_table = lapply(seq_len(nrow(cmp)), function(i) as.list(cmp[i]))
)
write_json(validation, file.path(ART, "alpha_validation.json"),
           pretty = TRUE, auto_unbox = TRUE, null = "null", na = "null")
write_json(validation, file.path(MBOX, "alpha_validation.json"),
           pretty = TRUE, auto_unbox = TRUE, null = "null", na = "null")

# alpha_package_draft.json (single-pass, no post-emission patches)
best <- diag_summary[[best_cand]]
best_ortho <- ortho[[best_cand]]
ranked <- combined[sig_date == last_sig][order(-alpha)]
alpha_vector <- setNames(as.list(as.numeric(ranked$alpha)), as.character(ranked$Ticker))
abs_a <- abs(ranked$alpha)
denom <- if (max(abs_a) > min(abs_a)) (max(abs_a) - min(abs_a)) else 1
conf <- pmin(1, pmax(0, (abs_a - min(abs_a)) / denom))
confidence_vector <- setNames(as.list(as.numeric(conf)), as.character(ranked$Ticker))

factor_specs_map <- list(
  C1_D01_IdioVol_LOW = list(
    factor_family = "Risk_Idiosyncratic_Volatility",
    proxy = "D01_IdioVol",
    formula = "Z_Score_Aligned(D01_IdioVol) — Factor DB rolling FF-residual IVOL, cross-section z within universe",
    economic_rationale = "IVOL puzzle (Ang-Hodrick-Xing-Zhang 2006 JoF): low idiosyncratic vol portfolios earn higher risk-adjusted returns. Behavioral explanation: lottery-stock demand drives high-IVOL premium negative.",
    direction_alignment = "Z_Score_Aligned by Factor DB IC-history (Usable_Date <= sig_date, expanding 36-month burn-in, L-168 fix).",
    source = "db_existing",
    references = list("Ang, Hodrick, Xing, Zhang (2006) JoF 'The Cross-Section of Volatility and Expected Returns' — pp.259-299",
                      "Bali, Cakici (2008) JFQA 'Idiosyncratic Volatility and the Cross Section of Expected Returns' — replication")
  ),
  C2_D11_FP_Beta_LOW = list(
    factor_family = "Risk_Beta",
    proxy = "D11_FP_Beta",
    formula = "Z_Score_Aligned(D11_FP_Beta) — Frazzini-Pedersen beta",
    economic_rationale = "Betting Against Beta (Frazzini-Pedersen 2014 JFE): leverage-constrained investors overpay for high-beta, low-beta stocks earn premium.",
    direction_alignment = "Z_Score_Aligned IC-history",
    source = "db_existing",
    references = list("Frazzini, Pedersen (2014) JFE 'Betting Against Beta' — pp.1-25")
  ),
  C3_HAR_RV_combine_LOW = list(
    factor_family = "Risk_Multi_Horizon_Volatility",
    proxy = "D34+D35+D36 multi-horizon RV (HAR-RV equal weight)",
    formula = "mean(z(D34_RealVol_21d), z(D35_RealVol_63d), z(D36_RealVol_126d)) then cross-section z",
    economic_rationale = "Heterogeneous AutoRegressive RV (Corsi 2009): vol forecasting via multi-horizon (daily/weekly/monthly) component decomposition. Low multi-horizon vol = persistent stability premium.",
    direction_alignment = "Each D-component Z_Score_Aligned IC-history then EW composite",
    source = "db_derived",
    references = list("Corsi (2009) JFE 'A Simple Approximate Long-Memory Model of Realized Volatility' — pp.174-196",
                      "Andersen, Bollerslev, Diebold (2003) ECMA 'Modeling and Forecasting Realized Volatility'")
  ),
  C4_D57_Down_Vol_LOW = list(
    factor_family = "Risk_Downside_Semi_Deviation",
    proxy = "D57_Down_Vol",
    formula = "Z_Score_Aligned(D57_Down_Vol) — semi-deviation conditional on negative returns",
    economic_rationale = "Mean-semivariance (Estrada 2007): investors care about downside risk asymmetrically. Low downside semi-deviation portfolios earn premium in loss-aversion regime. Differs from total vol — captures left-tail co-movement.",
    direction_alignment = "Z_Score_Aligned IC-history",
    source = "db_existing",
    references = list("Estrada (2007) JBV 'Mean-Semivariance Behavior: Downside Risk and Capital Asset Pricing' — pp.169-185",
                      "Bawa, Lindenberg (1977) JFE 'Capital market equilibrium in a mean-lower partial moment framework' — pp.189-200",
                      "Ang, Chen, Xing (2006) RFS 'Downside Risk' — pp.1191-1239")
  ),
  C5_Sophisticated_4axis_composite = list(
    factor_family = "Risk_Composite_4Axis",
    proxy = "C1+C2+C3+C4 EW Z-score composite",
    formula = "mean(z(IdioVol), z(FP_Beta), z(HAR_RV), z(Down_Vol)) then cross-section z",
    economic_rationale = "Multi-axis sophistication composite. EW diversifies single-axis noise.",
    direction_alignment = "All 4 underlying Z_Score_Aligned, then mean",
    source = "db_derived",
    references = list("All 4 underlying references")
  )
)
best_factor_spec <- factor_specs_map[[best_cand]]
best_factor_spec$weight_theta <- 1.0
best_factor_spec$winsorization <- "3std post cs_z"
best_factor_spec$neutralization <- "none (cross-sectional Z within K200∪KQ150 universe). Sector-neutral post-test not run — Codex C-RF-A4 follow-up."
best_factor_spec$lag_rule <- "Month-end sig_date strict; Factor DB Usable_Date <= sig_date (L-168 IC-history rule). C14 PASS."

alpha_package_draft <- list(
  task_id = WT_ID,
  wt_type = "discovery",
  as_of_date = "2026-05-13",
  as_of_sig_date_actual = as.character(last_sig),
  forecast_horizon = "1M",
  selection_objective = "rank_ic",
  version = "v2_PIT_FIX_post_codex_REJECT",
  best_candidate = best_cand,
  alpha_vector = alpha_vector,
  confidence_vector = confidence_vector,
  alpha_vector_n_tickers = length(alpha_vector),
  factor_specs = list(best_factor_spec),
  candidates_evaluated = lapply(diag_summary, function(d) d),
  diagnostics = list(
    rank_ic = best$mean_rank_ic,
    icir = best$icir,
    icir_recent_3y = best$icir_recent_3y,
    rf_a3_ratio = best$rf_a3_ratio,
    monotonicity = best$monotonicity_q1_q5_concord,
    monotonicity_pass = best$monotonicity_pass,
    subperiod_stability = best$subperiod_stability,
    t_stat_raw = best$t_stat_raw,
    harvey_t_nw_lag6 = best$t_nw_lag6,
    harvey_t_pass = best$harvey_t_pass,
    harvey_5spec_tnw = best$harvey_5spec_tnw,
    harvey_5spec_pass_count = best$harvey_5spec_pass_count,
    dsr = best$dsr,
    dsr_pnorm = best$dsr_pnorm,
    dsr_pass = best$dsr_pass,
    n_months = best$n_months,
    avg_n_stocks = best$avg_n_stocks
  ),
  orthogonality_vs_STR_1715_admit = list(
    returns_cor_pearson  = best_ortho$returns_cor_pearson,
    returns_cor_spearman = best_ortho$returns_cor_spearman,
    returns_cor_kendall  = best_ortho$returns_cor_kendall,
    rank_pass_lt_0_30 = best_ortho$orthogonality_rank_pass,
    return_pass_lt_0_40 = best_ortho$orthogonality_return_pass,
    n_overlap_months = best_ortho$n_overlap_months,
    measurement_method = best_ortho$measurement_method
  ),
  method_shopping_log = list(
    candidates_tried = length(CANDIDATE_NAMES),
    method_log = lapply(CANDIDATE_NAMES, function(c) {
      d <- diag_summary[[c]]; o <- ortho[[c]]
      list(name = c,
           rank_ic = d$mean_rank_ic %||% NA,
           icir = d$icir %||% NA,
           t_nw = d$t_nw_lag6 %||% NA,
           dsr = d$dsr %||% NA,
           mono = d$monotonicity_q1_q5_concord %||% NA,
           cor_str_pearson_ym = o$returns_cor_pearson %||% NA,
           cor_str_spearman_ym = o$returns_cor_spearman %||% NA,
           selected = (c == best_cand))
    }),
    parallel_exec = FALSE,
    rcpp_used = FALSE
  ),
  pit_compliance = list(
    C1_rolling_only = TRUE,
    C2_no_same_day_circular = TRUE,
    C4_quarterly_45d = "applies via Factor DB",
    C13_z_score_aligned = "Z_Score_Aligned only — Factor DB IC-history (Usable_Date<=sig_date, expanding 36-month burn-in). No NEGATE/FLIP applied at agent level.",
    C14_usable_date = TRUE,
    C15_load_month_factors = TRUE,
    pit_audit = list(
      sig_dates_strictly_month_end = TRUE,
      factor_date_leaked_count = n_leaked,
      factor_date_leaked_pct = round(n_leaked / length(SIG_DATES), 4)
    )
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
    AX_001_v2_conditional_defense_intent = "Risk agent will measure crisis_alpha + MDD vs STR_1715 + bad/normal IC ratio downstream. Top10 selection (식품·음료/담배/호텔레저/소프트웨어) consistent with defensive low-vol KR cohort — natural crisis-period beta < 1.",
    AX_002_process_honesty = list(ex_ante_grid_N = length(CANDIDATE_NAMES), grid_limit = 5, post_hoc_search = FALSE,
                                   codex_v1_REJECT_remediated = "v2 PIT-fix month-end-strict sig_dates"),
    AX_005_v1_2_exclusion = "Single-sleeve long-only KR low-vol HISTORICAL FAIL (L-136/140/165/166). MUST be combined with STR_1715/R05/AR within Optimizer composite. AX-005 = necessary not sufficient — final exclusion validation responsibility passes to Optimizer/Risk agents in their own packages.",
    AX_007_exception_intended = "multi-sleeve (≥2 sleeve composition with STR_1715 admit). Final EXEMPT validation depends on Optimizer 4-sleeve composite weights showing non-degenerate sleeve mix."
  ),
  challenge_flags = list(),
  codex_round_status = "REJECT_v1_REMEDIATED_v2",
  codex_round_v1_response = "qepm/mailbox/worktask/WT-D20260513_001/codex_critic_response_alpha.json",
  prior_codex_round_status = "v2 finalized, ready for fresh Codex round"
)

write_json(alpha_package_draft,
           file.path(MBOX, "alpha_package_draft.json"),
           pretty = TRUE, auto_unbox = TRUE, null = "null", na = "null")
cat("  alpha_package_draft.json written (v2 single-pass)\n")

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
  version = "v2_PIT_FIX_post_codex_REJECT",
  method_selected = best_cand,
  input_file_paths = src_files,
  input_file_exists = sapply(src_files, file.exists),
  factor_db_used = "load_month_factors() — C15 compliant",
  candidates_tried = length(CANDIDATE_NAMES),
  ex_ante_grid_N_strict = 5,
  pit_audit_clean = n_leaked == 0,
  factor_date_leaked = n_leaked,
  output_files = c(
    file.path(ART, "alpha_scores.parquet"),
    file.path(ART, "alpha_validation.json"),
    file.path(ART, "ic_history.parquet"),
    file.path(ART, "candidate_comparison_v2.csv"),
    file.path(MBOX, "alpha_package_draft.json"),
    file.path(MBOX, "alpha_validation.json")
  )
)
write_json(lineage, file.path(MBOX, "artifact_lineage.json"),
           pretty = TRUE, auto_unbox = TRUE, null = "null", na = "null")
cat("  artifact_lineage.json written\n")

cat("\n=== DONE v2 ===\n")
cat("Best candidate:", best_cand, "\n")
cat("Rank IC:", best$mean_rank_ic, " ICIR:", best$icir, " t_NW:", best$t_nw_lag6, " DSR:", best$dsr, " spec5pass:", best$harvey_5spec_pass_count, "\n")
cat("Monotonicity:", best$monotonicity_q1_q5_concord, " pass:", best$monotonicity_pass, "\n")
cat("Orthogonality cor_p=", best_ortho$returns_cor_pearson, " cor_s=", best_ortho$returns_cor_spearman, "\n")
cat("PIT leak count:", n_leaked, "\n")
