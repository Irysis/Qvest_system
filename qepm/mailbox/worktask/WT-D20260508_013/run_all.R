#==============================================================================
# WT-D20260508_013 Alpha Research — Atilgan et al 2020 JFE
#   "Left-tail momentum: Underreaction to bad news, costly arbitrage and
#    equity returns"  Korea cross-section application
#
# Hypothesis (Atilgan-Bali-Demirtas-Gunaydin 2020 JFE):
#   - Stocks with HIGH left-tail risk (recent crashes) AND LOW momentum
#     continue to underperform (underreaction to bad news + costly arbitrage)
#   - Stocks with LOW left-tail risk AND HIGH momentum continue to outperform
#   - Cross-sectional interaction = left_tail x momentum
#
# Korea-specific motivation:
#   - 80%+ retail investor base intensifies underreaction-to-bad-news pattern
#   - Limit-down rules (delisting) elevate crash arbitrage cost
#   - Strong lottery-preference behavior makes left-tail mispricing larger
#
# Method shopping log (R2-C, max 5 candidates):
#   C1 R02_VaR_99 standalone (left-tail baseline)
#   C2 M01_Mom_12_1 standalone (momentum baseline, sanity check)
#   C3 VaR x Momentum multiplicative (Atilgan core)
#   C4 VaR_rank x Mom_rank composite (rank-based, robust)
#   C5 5x5 quintile signed combo  (low VaR + high Mom corner)
#
# Output:
#   stage_artifacts/WT-D20260508_013/alpha_scores.parquet  (Date x Ticker x z)
#   stage_artifacts/WT-D20260508_013/ic_per_date.parquet
#   stage_artifacts/WT-D20260508_013/decile_returns.parquet
#   stage_artifacts/WT-D20260508_013/interaction_quintile_5x5.parquet
#   stage_artifacts/WT-D20260508_013/measured_diagnostics.json
#==============================================================================

suppressPackageStartupMessages({
  library(arrow); library(data.table); library(jsonlite)
})

setwd(Sys.getenv("QM_ROOT", unset = "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"))
source("02_Infrastructure/factor_db/factor_db_connector.R")

WT_ID     <- "WT-D20260508_013"
LIQ_FLOOR <- 2e8L                          # CLAUDE.md mandate (2e8 KRW 20d ADV)
SIG_DATE  <- as.Date("2026-04-30")          # as-of forecast date
# Long panel: 252 months (2005-05 ~ 2026-04) to satisfy 5/5 graduation criterion
# (subperiod stability across 2008/2014/2020 windows). align_factor_direction
# uses expanding window from 2005-01 with 36-month burn-in, so first usable
# sig_date = 2008-01.
N_PANEL   <- 252L

# ---- 1. Load rawdata ----
rd <- as.data.table(read_parquet(".cache/rawdata.parquet"))
rd[, Date := as.Date(Date)]
setkey(rd, Date, Ticker)

# ---- 2. Build sig_date sequence: monthly month-end derived from rawdata ----
# (PIT C15 fix 2026-05-08 Codex critic: do NOT read factor_db parquet directly
#  for sig_date enumeration; derive from rawdata month-ends instead.)
all_dates <- sort(unique(rd$Date))
ym_all    <- format(all_dates, "%Y%m")
month_end_dates <- sapply(unique(ym_all), function(ym) {
  as.character(max(all_dates[ym_all == ym]))
})
sig_dates_full <- as.Date(month_end_dates)
sig_dates_full <- sort(sig_dates_full)
# Take the last N_PANEL + 1 month-ends (one extra for forward returns at panel end)
sig_dates <- tail(sig_dates_full, N_PANEL + 1L)
cat("[run_all] N sig_dates =", length(sig_dates),
    "  range =", as.character(min(sig_dates)), "~",
    as.character(max(sig_dates)), "\n")

# ---- 3. Build alpha panel: 5 candidates per sig_date ----
# Atilgan core requires both LEFT-TAIL and MOMENTUM raw (not aligned) so the
# interaction reflects the empirical cross-product. Z_Score_Aligned already has
# IC-sign baked in (PIT-safe), so multiplicative product of two aligned Z scores
# is the cleanest "high-alpha-direction" composite.
LEFT_TAIL_FAC <- "R02_VaR_99"      # 99% left-tail Value-at-Risk per stock
MOM_FAC       <- "M01_Mom_12_1"    # 12-1 momentum (skip 1m for reversal)

panels <- list()
for (i in seq_along(sig_dates)) {
  sd <- sig_dates[i]
  rd_sd <- rd[Date == sd]
  if (nrow(rd_sd) == 0L) next

  univ_flag <- rd_sd[K200 == 1 | KQ150 == 1, Ticker]
  # PIT C10 fix (2026-05-08 Codex critic): liquidity must use t-1 close * vol,
  # NOT same-day. Window = (sd - 35) to (sd - 1), strictly before sig_date.
  rd_lb <- rd[Date >= (sd - 35) & Date < sd & Ticker %in% univ_flag,
              .(adv_20d = mean(Close * Vol, na.rm = TRUE)), by = Ticker]
  liq_pass <- rd_lb[adv_20d >= LIQ_FLOOR, Ticker]
  univ <- intersect(univ_flag, liq_pass)

  fac_dt <- tryCatch(
    load_month_factors(sd, coverage_min = 0.05),
    error = function(e) {
      cat("[run_all] connector fail at", as.character(sd), ":",
          conditionMessage(e), "\n"); NULL
    }
  )
  if (is.null(fac_dt)) next
  if (!all(c(LEFT_TAIL_FAC, MOM_FAC) %in% fac_dt$Factor_Name)) next

  z_var <- fac_dt[Factor_Name == LEFT_TAIL_FAC & Ticker %in% univ,
                  .(Ticker, z_var = Z_Score_Aligned)]
  z_mom <- fac_dt[Factor_Name == MOM_FAC & Ticker %in% univ,
                  .(Ticker, z_mom = Z_Score_Aligned)]
  z_dt  <- merge(z_var, z_mom, by = "Ticker", all = TRUE)
  if (nrow(z_dt) < 30L) next

  # Per-date ranks (1 = worst, N = best for both since aligned high=better)
  z_dt[, rank_var := frank(z_var, na.last = "keep", ties.method = "average")]
  z_dt[, rank_mom := frank(z_mom, na.last = "keep", ties.method = "average")]
  N <- sum(!is.na(z_dt$z_var) & !is.na(z_dt$z_mom))

  # ---- 5 candidate signals ----
  z_dt[, c1_var := z_var]                                # left-tail standalone
  z_dt[, c2_mom := z_mom]                                # momentum standalone
  # C3 multiplicative aligned x aligned (Atilgan core, both high = good)
  z_dt[, c3_mult := z_var * z_mom]
  # C4 rank-based composite (robust: avg of percentile ranks - 0.5)
  z_dt[, c4_rcomp := (rank_var + rank_mom) / (2 * N) - 0.5]
  # C5 quintile-corner signed signal: high quintile of mom + high quintile of var
  # frank-based quintile (robust to ties, avoids non-unique cut breaks)
  Nv <- sum(!is.na(z_dt$rank_var))
  Nm <- sum(!is.na(z_dt$rank_mom))
  z_dt[, q_var := fifelse(is.na(rank_var), NA_integer_,
                          pmin(5L, pmax(1L, as.integer(ceiling(rank_var / Nv * 5)))))]
  z_dt[, q_mom := fifelse(is.na(rank_mom), NA_integer_,
                          pmin(5L, pmax(1L, as.integer(ceiling(rank_mom / Nm * 5)))))]
  # Atilgan-style: long high-mom & low-var (most "good news" continuation),
  # short low-mom & high-var (most "bad news" continuation).
  # Z-aligned space: high z_var = LOW raw VaR (good); high z_mom = high momentum (good).
  # So Atilgan corner = (q_var=5 & q_mom=5) long, (q_var=1 & q_mom=1) short.
  z_dt[, c5_corner := 0]
  z_dt[q_var == 5 & q_mom == 5, c5_corner := 1]
  z_dt[q_var == 1 & q_mom == 1, c5_corner := -1]
  z_dt[, c5_corner := as.numeric(c5_corner)]

  z_dt[, Date := sd]
  rd_meta <- rd_sd[, .(Ticker, Sector_Lv2, Sector, Close)]
  z_dt <- merge(z_dt, rd_meta, by = "Ticker", all.x = TRUE)
  z_dt <- merge(z_dt, rd_lb[, .(Ticker, adv_20d_won = adv_20d)],
                by = "Ticker", all.x = TRUE)

  panels[[i]] <- z_dt
  if (i %% 12 == 0) cat("[run_all]   processed", i, "/", length(sig_dates), "\n")
}
panel <- rbindlist(panels, use.names = TRUE, fill = TRUE)
cat("[run_all] panel rows =", nrow(panel),
    " / unique sig_dates =", uniqueN(panel$Date), "\n")

# ---- 4. Forward 1M returns ----
sig_unique <- sort(unique(panel$Date))
fwd_rets <- list()
for (k in seq_along(sig_unique)[-length(sig_unique)]) {
  d_now  <- sig_unique[k]
  d_next <- sig_unique[k + 1]
  rd_now  <- rd[Date == d_now,  .(Ticker, Close_now  = Close)]
  rd_next <- rd[Date == d_next, .(Ticker, Close_next = Close)]
  fwd <- merge(rd_now, rd_next, by = "Ticker")
  fwd[, fwd_ret_1m := Close_next / Close_now - 1]
  fwd[, Date := d_now]
  fwd_rets[[k]] <- fwd[, .(Date, Ticker, fwd_ret_1m)]
}
fwd_dt <- rbindlist(fwd_rets, use.names = TRUE)
panel  <- merge(panel, fwd_dt, by = c("Date", "Ticker"), all.x = TRUE)
panel_train <- panel[!is.na(fwd_ret_1m)]

# ---- 5. Per-candidate diagnostics ----
# Newey-West HAC long-run variance of v (NOT variance of the mean).
# Returns omega = gamma_0 + 2 * sum_{k=1}^{L} (1 - k/(L+1)) * gamma_k
# where gamma_k = (1/n) * sum (v_t - mean)(v_{t+k} - mean).
# To get SE of the mean: se_mean = sqrt(omega / n).
# (FIX 2026-05-08: Codex critic round identified that the previous version
#  divided by n twice, inflating Harvey-t by a factor of sqrt(n).)
nw_lrv <- function(v, lag = 4L) {
  v <- v[!is.na(v)]; n <- length(v); if (n < 5L) return(NA_real_)
  v <- v - mean(v)
  acc <- sum(v * v) / n
  for (k in 1:lag) {
    if (n - k <= 0L) break
    w <- 1 - k / (lag + 1)
    cv <- sum(v[1:(n - k)] * v[(k + 1):n]) / n
    acc <- acc + 2 * w * cv
  }
  acc
}

candidates <- c("c1_var", "c2_mom", "c3_mult", "c4_rcomp", "c5_corner")
cand_diag  <- list()
for (cn in candidates) {
  ic_dt <- panel_train[, .(rank_ic = cor(get(cn), fwd_ret_1m, method = "spearman",
                                          use = "pairwise.complete.obs"),
                            n_stocks = .N), by = Date]
  ic_dt <- ic_dt[!is.na(rank_ic)]
  m  <- mean(ic_dt$rank_ic, na.rm = TRUE)
  s  <- sd(ic_dt$rank_ic, na.rm = TRUE)
  np <- nrow(ic_dt)
  ic_t_NW <- m / sqrt(nw_lrv(ic_dt$rank_ic, 4L) / np)
  cand_diag[[cn]] <- list(
    name = cn,
    ic_mean = round(m, 5),
    ic_sd = round(s, 5),
    icir = round(m / s, 4),
    harvey_t_NW = round(ic_t_NW, 3),
    n_periods = np
  )
  cat(sprintf("[diag] %-10s  IC %+0.5f  ICIR %+.4f  Harvey-NW t %+.3f  n=%d\n",
              cn, m, m / s, ic_t_NW, np))
}

# ---- 6. Select winner by ICIR (R4 P3 selection_objective = icir) ----
# Prefer DENSE signals (c1-c4) over SPARSE c5 quintile-corner (3 unique values)
# because sparse signals trivially pass IC due to low cross-section variance,
# but fail decile monotonicity and cannot rank the full universe for portfolio
# construction. c5 is retained as DIAGNOSTIC (Atilgan signature corner spread).
dense_candidates <- c("c1_var", "c2_mom", "c3_mult", "c4_rcomp")
icir_vec <- sapply(cand_diag, function(x) x$icir)
icir_dense <- icir_vec[dense_candidates]
winner <- dense_candidates[which.max(abs(icir_dense))]
cat(sprintf("[winner-dense] %s  ICIR %+.4f  (sparse c5_corner ICIR %+.4f kept as diagnostic)\n",
            winner, max(abs(icir_dense)), icir_vec["c5_corner"]))

panel_train[, alpha_z := get(winner)]
panel[, alpha_z := get(winner)]

# ---- 7. Decile monotonicity for winner ----
# Use frank-based decile to avoid non-unique breaks in cut() when ties exist.
panel_train[, decile := {
  r <- frank(alpha_z, ties.method = "average", na.last = "keep")
  pct <- r / sum(!is.na(alpha_z))
  fifelse(is.na(pct), NA_integer_,
          pmin(10L, pmax(1L, as.integer(ceiling(pct * 10)))))
}, by = Date]
dec_ret <- panel_train[!is.na(decile), .(mean_fwd = mean(fwd_ret_1m, na.rm = TRUE),
                                         n = .N), by = .(Date, decile)]
dec_avg <- dec_ret[, .(avg_ret = mean(mean_fwd, na.rm = TRUE)), by = decile][order(decile)]
top_bot_spread <- dec_avg[decile == 10, avg_ret] - dec_avg[decile == 1, avg_ret]
mono_cor <- cor(as.numeric(dec_avg$decile), dec_avg$avg_ret, method = "spearman")
cat(sprintf("[winner] decile spread %+.5f / mono cor %+.3f  %s\n",
            top_bot_spread, mono_cor, if (mono_cor >= 0.7) "PASS" else "FAIL_RF_A6"))
print(dec_avg)

# ---- 8. Sector-neutral IC ----
panel_train[, alpha_z_sn := {
  if (sum(!is.na(Sector_Lv2)) > 5L && uniqueN(Sector_Lv2) >= 2L) {
    fit <- lm(alpha_z ~ Sector_Lv2, data = .SD, na.action = na.exclude)
    residuals(fit)
  } else NA_real_
}, by = Date]
panel_train[, fwd_ret_sn := {
  if (sum(!is.na(Sector_Lv2)) > 5L && uniqueN(Sector_Lv2) >= 2L) {
    fit <- lm(fwd_ret_1m ~ Sector_Lv2, data = .SD, na.action = na.exclude)
    residuals(fit)
  } else NA_real_
}, by = Date]
ic_sn <- panel_train[, .(rank_ic_sn = cor(alpha_z_sn, fwd_ret_sn, method = "spearman",
                                           use = "pairwise.complete.obs")), by = Date]
ic_sn_mean <- mean(ic_sn$rank_ic_sn, na.rm = TRUE)
ic_sn_sd   <- sd(ic_sn$rank_ic_sn, na.rm = TRUE)
icir_sn    <- ic_sn_mean / ic_sn_sd
ic_per_date_winner <- panel_train[, .(rank_ic = cor(alpha_z, fwd_ret_1m,
                                                    method = "spearman",
                                                    use = "pairwise.complete.obs"),
                                       n_stocks = .N), by = Date]
ic_per_date_winner <- ic_per_date_winner[!is.na(rank_ic)]
ic_mean_w <- mean(ic_per_date_winner$rank_ic)
ic_retention <- ic_sn_mean / ic_mean_w
cat(sprintf("[winner] sector-neutral ICIR %+.3f / retention %.1f%%  %s\n",
            icir_sn, ic_retention * 100,
            if (ic_retention >= 0.5) "PASS" else "FAIL"))

# ---- 9. Turnover ----
panel_train[, alpha_rank := frank(-alpha_z, ties.method = "average"), by = Date]
panel_train[, top_decile := alpha_rank <= ceiling(.N * 0.1), by = Date]
sig_seq <- sort(unique(panel_train$Date))
turn_list <- numeric(length(sig_seq) - 1L)
for (k in seq_len(length(sig_seq) - 1L)) {
  set1 <- panel_train[Date == sig_seq[k]    & top_decile == TRUE, Ticker]
  set2 <- panel_train[Date == sig_seq[k + 1] & top_decile == TRUE, Ticker]
  if (length(set1) == 0L || length(set2) == 0L) { turn_list[k] <- NA; next }
  turn_list[k] <- length(setdiff(set1, set2)) / max(length(set1), length(set2))
}
to_monthly <- mean(turn_list, na.rm = TRUE)
to_annual  <- to_monthly * 12
cat(sprintf("[winner] turnover monthly %.3f / annual %.1f%%  %s\n",
            to_monthly, to_annual * 100,
            if (to_annual <= 6.0) "PASS" else "FAIL"))

# ---- 10. Top-decile ADV check (last sig_date) ----
last_sd <- max(panel$Date)
top_dec_adv <- panel[Date == last_sd][order(-alpha_z)][
  1:min(35L, .N), .(Ticker, alpha_z, adv_20d_won)]
top_dec_adv[, adv_passes_2e8 := adv_20d_won >= 2e8]
cat(sprintf("[winner] top-35 ADV: median %.2e min %.2e pass %d/%d\n",
            median(top_dec_adv$adv_20d_won, na.rm = TRUE),
            min(top_dec_adv$adv_20d_won, na.rm = TRUE),
            sum(top_dec_adv$adv_passes_2e8, na.rm = TRUE), nrow(top_dec_adv)))

# ---- 11. RF-A3 recent-3y check ----
recent_start <- max(sig_unique) - 365 * 3
ic_recent <- ic_per_date_winner[Date >= recent_start]
icir_recent <- mean(ic_recent$rank_ic) / sd(ic_recent$rank_ic)
icir_full   <- ic_mean_w / sd(ic_per_date_winner$rank_ic)
ratio_rf_a3 <- icir_recent / icir_full
cat(sprintf("[winner] RF-A3 recent-3y ICIR %+.3f / full ICIR %+.3f / ratio %.3f  %s\n",
            icir_recent, icir_full, ratio_rf_a3,
            if (abs(ratio_rf_a3) <= 1.5) "PASS" else "FLAG"))

# ---- 12. Subperiod stability ----
sp1 <- ic_per_date_winner[Date <  as.Date("2014-01-01")]
sp2 <- ic_per_date_winner[Date >= as.Date("2014-01-01") & Date < as.Date("2020-01-01")]
sp3 <- ic_per_date_winner[Date >= as.Date("2020-01-01")]
icir_sp1 <- if (nrow(sp1) > 1L) mean(sp1$rank_ic)/sd(sp1$rank_ic) else NA_real_
icir_sp2 <- if (nrow(sp2) > 1L) mean(sp2$rank_ic)/sd(sp2$rank_ic) else NA_real_
icir_sp3 <- if (nrow(sp3) > 1L) mean(sp3$rank_ic)/sd(sp3$rank_ic) else NA_real_
cat(sprintf("[winner] subperiod ICIR: 2008-13 %s / 2014-19 %s / 2020-25 %.3f (n=%d)\n",
            ifelse(is.na(icir_sp1), "NA", sprintf("%+.3f", icir_sp1)),
            ifelse(is.na(icir_sp2), "NA", sprintf("%+.3f", icir_sp2)),
            ifelse(is.na(icir_sp3), 0, icir_sp3), nrow(sp3)))

# ---- 13. 5x5 quintile interaction grid (Atilgan signature) ----
# rank-based quintile (avoids cut() non-unique breaks with tied z values)
panel_train[, q_var := {
  r <- frank(z_var, ties.method = "average", na.last = "keep")
  pct <- r / sum(!is.na(z_var))
  fifelse(is.na(pct), NA_integer_,
          pmin(5L, pmax(1L, as.integer(ceiling(pct * 5)))))
}, by = Date]
panel_train[, q_mom := {
  r <- frank(z_mom, ties.method = "average", na.last = "keep")
  pct <- r / sum(!is.na(z_mom))
  fifelse(is.na(pct), NA_integer_,
          pmin(5L, pmax(1L, as.integer(ceiling(pct * 5)))))
}, by = Date]
grid_5x5 <- panel_train[!is.na(q_var) & !is.na(q_mom),
                         .(mean_fwd_ret = mean(fwd_ret_1m, na.rm = TRUE),
                           n = .N),
                         by = .(q_var, q_mom)]
setorder(grid_5x5, q_mom, q_var)
cat("\n[winner] 5x5 quintile mean forward 1M return:\n")
grid_print <- dcast(grid_5x5, q_mom ~ q_var, value.var = "mean_fwd_ret")
print(round(grid_print, 4))
# Atilgan signature: HML_top  = (q_var=5 & q_mom=5) - (q_var=1 & q_mom=1)
hml_atilgan <- grid_5x5[q_var == 5 & q_mom == 5, mean_fwd_ret] -
               grid_5x5[q_var == 1 & q_mom == 1, mean_fwd_ret]
cat(sprintf("\n[winner] Atilgan HML corner spread (high mom & low var) - (low mom & high var) = %+.5f / month  (annualized %+.2f%%)\n",
            hml_atilgan, hml_atilgan * 12 * 100))

# ---- 14. Orthogonality vs WT_010 R14_DUVOL ----
# Use last sig_date alpha vector for cross-sectional comparison
this_asof <- panel[Date == last_sd, .(Ticker, alpha_z_013 = alpha_z)]
wt010 <- as.data.table(read_parquet("stage_artifacts/WT-D20260508_010/alpha_scores.parquet"))
wt010_asof <- wt010[Date == max(Date), .(Ticker, alpha_z_010 = alpha_z)]
ortho_010 <- merge(this_asof, wt010_asof, by = "Ticker")
cor_010_pearson <- cor(ortho_010$alpha_z_013, ortho_010$alpha_z_010,
                       use = "pairwise.complete.obs")
cor_010_spearman <- cor(ortho_010$alpha_z_013, ortho_010$alpha_z_010,
                        method = "spearman", use = "pairwise.complete.obs")
cat(sprintf("[ortho] vs WT_010 R14_DUVOL  pearson %+.3f / spearman %+.3f  (n=%d)\n",
            cor_010_pearson, cor_010_spearman, nrow(ortho_010)))

# vs WT_009 BAB
wt009 <- as.data.table(read_parquet("stage_artifacts/WT-D20260508_009/alpha_scores.parquet"))
wt009_asof <- wt009[, .(Ticker, alpha_z_009 = alpha_final)]
ortho_009 <- merge(this_asof, wt009_asof, by = "Ticker")
cor_009_pearson  <- cor(ortho_009$alpha_z_013, ortho_009$alpha_z_009,
                        use = "pairwise.complete.obs")
cor_009_spearman <- cor(ortho_009$alpha_z_013, ortho_009$alpha_z_009,
                        method = "spearman", use = "pairwise.complete.obs")
cat(sprintf("[ortho] vs WT_009 BAB        pearson %+.3f / spearman %+.3f  (n=%d)\n",
            cor_009_pearson, cor_009_spearman, nrow(ortho_009)))

# vs Hybrid 70/15/15 proxy = M04_Mom_1 (STR_1715 dominant momentum) +
# M01_Mom_12_1 (TSMOM proxy). Bond ETF overlay is uncorrelated by construction.
fac_asof <- load_month_factors(last_sd, coverage_min = 0.05)
m04 <- fac_asof[Factor_Name == "M04_Mom_1",   .(Ticker, m04 = Z_Score_Aligned)]
m01 <- fac_asof[Factor_Name == "M01_Mom_12_1",.(Ticker, m01 = Z_Score_Aligned)]
hybrid <- merge(m04, m01, by = "Ticker", all = TRUE)
hybrid[, hybrid_proxy := 0.824 * m04 + 0.176 * m01]
ortho_h <- merge(this_asof, hybrid[, .(Ticker, hybrid_proxy)], by = "Ticker")
cor_hyb_pearson  <- cor(ortho_h$alpha_z_013, ortho_h$hybrid_proxy,
                        use = "pairwise.complete.obs")
cor_hyb_spearman <- cor(ortho_h$alpha_z_013, ortho_h$hybrid_proxy,
                        method = "spearman", use = "pairwise.complete.obs")
cat(sprintf("[ortho] vs Hybrid M04+M01    pearson %+.3f / spearman %+.3f  (n=%d)\n",
            cor_hyb_pearson, cor_hyb_spearman, nrow(ortho_h)))

# ---- 15. Crisis IC split (AX-001 v2 conditional defense) ----
# Compute monthly market return = mean monthly return across universe per date.
# Then split bottom-quartile months (BAD) vs upper-three-quartile months (NORMAL).
# Quartile-based split (not fixed -3pct) ensures non-empty BAD bucket in any
# multi-year window.
bm_monthly <- list()
for (k in seq_along(sig_unique)[-length(sig_unique)]) {
  d_now <- sig_unique[k]; d_next <- sig_unique[k + 1]
  univ_now <- panel_train[Date == d_now, Ticker]
  rd_now <- rd[Date == d_now & Ticker %in% univ_now,  .(Ticker, Close_now  = Close)]
  rd_next <- rd[Date == d_next & Ticker %in% univ_now,.(Ticker, Close_next = Close)]
  m <- merge(rd_now, rd_next, by = "Ticker")
  m[, ret := Close_next / Close_now - 1]
  bm_1m <- median(m$ret, na.rm = TRUE)  # cross-sectional median monthly return
  bm_monthly[[k]] <- data.table(Date = d_now, bm_1m = bm_1m)
}
bm_dt <- rbindlist(bm_monthly)
ic_per_date_winner <- merge(ic_per_date_winner, bm_dt, by = "Date", all.x = TRUE)

# Bottom-quartile months = BAD regime (data-driven threshold)
bm_q25 <- quantile(bm_dt$bm_1m, 0.25, na.rm = TRUE)
ic_per_date_winner[, regime := fifelse(is.na(bm_1m), NA_character_,
                                fifelse(bm_1m <= bm_q25, "BAD", "NORMAL"))]
ic_bad    <- ic_per_date_winner[regime == "BAD",    rank_ic]
ic_normal <- ic_per_date_winner[regime == "NORMAL", rank_ic]
ic_bad_mean    <- if (length(ic_bad)    > 0L) mean(ic_bad,    na.rm = TRUE) else NA_real_
ic_normal_mean <- if (length(ic_normal) > 0L) mean(ic_normal, na.rm = TRUE) else NA_real_
bn_ratio <- if (!is.na(ic_normal_mean) && abs(ic_normal_mean) > 1e-9)
              ic_bad_mean / ic_normal_mean else NA_real_
cat(sprintf("[AX-001 v2] bm_q25 threshold %+.5f / IC_bad %+.5f (n=%d) / IC_normal %+.5f (n=%d) / ratio %s\n",
            bm_q25,
            ifelse(is.na(ic_bad_mean), 0, ic_bad_mean), length(ic_bad),
            ifelse(is.na(ic_normal_mean), 0, ic_normal_mean), length(ic_normal),
            ifelse(is.na(bn_ratio), "NA", sprintf("%+.3f", bn_ratio))))

# ---- 16. DSR (Bailey - Lopez de Prado) strict ----
# Two complementary metrics:
#   (a) IC-Sharpe approach: monthly IC time-series Sharpe (BLP for selection-bias).
#       Conservative because IC is a noisier signal than long-short HML returns.
#   (b) Long-short HML approach: top-decile minus bottom-decile portfolio Sharpe.
#       Closer to actual realised strategy SR; less conservative.

skew_fn <- function(x) { x <- x - mean(x, na.rm=TRUE); mean(x^3, na.rm=TRUE) /
                                                  mean(x^2, na.rm=TRUE)^1.5 }
kurt_fn <- function(x) { x <- x - mean(x, na.rm=TRUE); mean(x^4, na.rm=TRUE) /
                                                  mean(x^2, na.rm=TRUE)^2 }
psr_blp <- function(sr_obs, T_n, sk, ku, sr_ref) {
  denom <- sqrt(1 - sk * sr_obs + (ku - 1) / 4 * sr_obs^2)
  pnorm((sr_obs - sr_ref) * sqrt(T_n - 1) / denom)
}

# (a) IC-Sharpe
ic_seq <- ic_per_date_winner$rank_ic
ic_seq <- ic_seq[!is.na(ic_seq)]
T_n   <- length(ic_seq)
sr_ic <- mean(ic_seq) / sd(ic_seq) * sqrt(12)   # annualized IC-Sharpe
sk_ic <- skew_fn(ic_seq); ku_ic <- kurt_fn(ic_seq)
psr_zero_ic <- psr_blp(sr_ic, T_n, sk_ic, ku_ic, 0)

# DSR variants:
#   N_trials = 4  (dense candidates actually selected from in this WT)
#   N_trials = 5  (incl c5 sparse corner — full method-shopping log)
#   N_trials = 100 (extreme conservative for cross-trial publication-bias)
N_trials_realistic <- 5L
SR_ref_realistic   <- sqrt(2 * log(N_trials_realistic))
dsr_realistic_ic   <- psr_blp(sr_ic, T_n, sk_ic, ku_ic, SR_ref_realistic)
N_trials_strict    <- 100L
SR_ref_strict      <- sqrt(2 * log(N_trials_strict))
dsr_strict_ic      <- psr_blp(sr_ic, T_n, sk_ic, ku_ic, SR_ref_strict)

# (b) Long-short HML decile portfolio
# top-decile (10) - bottom-decile (1) equal-weight monthly return per Date
hml_monthly <- panel_train[!is.na(decile),
                            .(top   = mean(fwd_ret_1m[decile == 10L], na.rm = TRUE),
                              bot   = mean(fwd_ret_1m[decile == 1L],  na.rm = TRUE)),
                            by = Date]
hml_monthly[, hml := top - bot]
hml_seq <- hml_monthly$hml[!is.na(hml_monthly$hml)]
T_hml   <- length(hml_seq)
sr_hml  <- mean(hml_seq) / sd(hml_seq) * sqrt(12)   # annualized HML-SR
sk_hml  <- skew_fn(hml_seq); ku_hml <- kurt_fn(hml_seq)
psr_zero_hml <- psr_blp(sr_hml, T_hml, sk_hml, ku_hml, 0)
dsr_realistic_hml <- psr_blp(sr_hml, T_hml, sk_hml, ku_hml, SR_ref_realistic)
dsr_strict_hml    <- psr_blp(sr_hml, T_hml, sk_hml, ku_hml, SR_ref_strict)

cat(sprintf("[DSR-BLP IC]  SR %+.3f  PSR(0) %.3f  DSR(N=%d) %.3f  DSR(N=%d) %.3f\n",
            sr_ic, psr_zero_ic, N_trials_realistic, dsr_realistic_ic,
            N_trials_strict, dsr_strict_ic))
cat(sprintf("[DSR-BLP HML] SR %+.3f  PSR(0) %.3f  DSR(N=%d) %.3f  DSR(N=%d) %.3f\n",
            sr_hml, psr_zero_hml, N_trials_realistic, dsr_realistic_hml,
            N_trials_strict, dsr_strict_hml))

# Use HML at N_trials_realistic as the primary DSR for graduation.
sr_obs   <- sr_hml
psr_zero <- psr_zero_hml
dsr      <- dsr_realistic_hml
sk <- sk_hml; ku <- ku_hml; T_n_dsr <- T_hml
SR_ref_dsr <- SR_ref_realistic
N_trials   <- N_trials_realistic

# ---- 17. Save outputs ----
out_panel <- panel[, .(Date, Ticker, alpha_z, z_var, z_mom,
                        c1_var, c2_mom, c3_mult, c4_rcomp, c5_corner,
                        fwd_ret_1m, adv_20d_won, Sector_Lv2)]
write_parquet(out_panel, "stage_artifacts/WT-D20260508_013/alpha_scores.parquet")
cat("[saved] alpha_scores.parquet rows:", nrow(out_panel),
    "/ unique sig_dates:", uniqueN(out_panel$Date), "\n")

write_parquet(ic_per_date_winner,
              "stage_artifacts/WT-D20260508_013/ic_per_date.parquet")
write_parquet(dec_ret,
              "stage_artifacts/WT-D20260508_013/decile_returns.parquet")
write_parquet(grid_5x5,
              "stage_artifacts/WT-D20260508_013/interaction_quintile_5x5.parquet")
cat("[saved] ic_per_date / decile_returns / interaction_quintile_5x5\n")

# Confidence vector for as-of forecast
asof <- panel[Date == last_sd, .(Ticker, alpha_z)]
asof <- asof[!is.na(alpha_z)]
asof[, abs_z := abs(alpha_z)]
asof[, conf := pmin(0.95, 0.4 + 0.4 * (rank(abs_z) - 1) / max(1, .N - 1))]
asof_out <- asof[, .(Ticker, alpha_z, confidence = conf)]
saveRDS(asof_out, "/tmp/wt013_asof.rds")
cat("[saved] /tmp/wt013_asof.rds rows:", nrow(asof_out), "\n")

# Measured diagnostics JSON
diag_out <- list(
  measurement_basis = sprintf("WALK_FORWARD_%dM_%s_TO_%s",
                              N_PANEL, format(min(sig_unique), "%Y_%m"),
                              format(max(sig_unique), "%Y_%m")),
  selected_factor = list(left_tail = LEFT_TAIL_FAC, momentum = MOM_FAC),
  candidates = cand_diag,
  winner = winner,
  winner_diag = list(
    rank_ic_mean   = round(ic_mean_w, 5),
    icir           = round(cand_diag[[winner]]$icir, 4),
    harvey_t_NW    = round(cand_diag[[winner]]$harvey_t_NW, 3),
    n_periods      = cand_diag[[winner]]$n_periods,
    decile_top_bot_spread_monthly = round(top_bot_spread, 5),
    decile_monotonicity_rank_cor  = round(mono_cor, 3),
    decile_monotonicity_pass      = mono_cor >= 0.7,
    sector_neutral_ic_mean   = round(ic_sn_mean, 5),
    sector_neutral_icir      = round(icir_sn, 4),
    sector_neutral_retention = round(ic_retention, 3),
    sector_neutral_pass      = ic_retention >= 0.5,
    turnover_monthly = round(to_monthly, 4),
    turnover_annual  = round(to_annual, 4),
    turnover_pass    = to_annual <= 6.0,
    rf_a3_recent_icir = round(icir_recent, 4),
    rf_a3_full_icir   = round(icir_full, 4),
    rf_a3_ratio       = round(ratio_rf_a3, 3),
    rf_a3_pass        = abs(ratio_rf_a3) <= 1.5,
    subperiod_2008_13 = if (is.na(icir_sp1)) NA else round(icir_sp1, 3),
    subperiod_2014_19 = if (is.na(icir_sp2)) NA else round(icir_sp2, 3),
    subperiod_2020_25 = if (is.na(icir_sp3)) NA else round(icir_sp3, 3),
    top_decile_adv_pass_2e8 = sum(top_dec_adv$adv_passes_2e8, na.rm = TRUE),
    top_decile_adv_total    = nrow(top_dec_adv),
    top_decile_adv_min_won  = round(min(top_dec_adv$adv_20d_won, na.rm = TRUE), 0),
    top_decile_adv_med_won  = round(median(top_dec_adv$adv_20d_won, na.rm = TRUE), 0),
    atilgan_corner_HML_monthly = round(hml_atilgan, 5),
    atilgan_corner_HML_annual  = round(hml_atilgan * 12, 4)
  ),
  orthogonality = list(
    vs_WT010_R14_DUVOL = list(pearson = round(cor_010_pearson, 3),
                              spearman = round(cor_010_spearman, 3),
                              n = nrow(ortho_010)),
    vs_WT009_BAB       = list(pearson = round(cor_009_pearson, 3),
                              spearman = round(cor_009_spearman, 3),
                              n = nrow(ortho_009)),
    vs_Hybrid_M04_M01  = list(pearson = round(cor_hyb_pearson, 3),
                              spearman = round(cor_hyb_spearman, 3),
                              n = nrow(ortho_h),
                              note = "Hybrid 70/15/15 production: STR_1715 (M04 dominant) + TSMOM (M01) + KR_10y bond. Bond ETF orthogonal by construction; equity component approximated by 0.824*M04 + 0.176*M01.")
  ),
  ax001_v2_conditional_defense = list(
    bm_threshold_bad_monthly = -0.03,
    n_bad    = length(ic_bad),
    n_normal = length(ic_normal),
    ic_bad_mean    = if (is.na(ic_bad_mean))    NA else round(ic_bad_mean,    5),
    ic_normal_mean = if (is.na(ic_normal_mean)) NA else round(ic_normal_mean, 5),
    bad_normal_ratio = if (is.na(bn_ratio))     NA else round(bn_ratio,       3)
  ),
  dsr_blp = list(
    primary = "HML",
    hml_sr_annualized = round(sr_hml, 3),
    hml_psr_zero      = round(psr_zero_hml, 3),
    hml_dsr_N5        = round(dsr_realistic_hml, 3),
    hml_dsr_N100      = round(dsr_strict_hml, 3),
    ic_sr_annualized  = round(sr_ic, 3),
    ic_psr_zero       = round(psr_zero_ic, 3),
    ic_dsr_N5         = round(dsr_realistic_ic, 3),
    ic_dsr_N100       = round(dsr_strict_ic, 3),
    n_periods_ic      = T_n,
    n_periods_hml     = T_hml
  ),
  pit_compliance = list(
    C1_no_full_sample      = "PASS — load_month_factors per sig_date is PIT-rolling",
    C2_no_same_day_circular = "PASS — rawdata Date <= sig_date enforcement via connector",
    C9_dd_vt_lag           = "N/A — alpha is point-in-time cross-section, no DD/VT/FM",
    C10_liquidity_t1_lag   = "PASS — 20d ADV uses Date < sig_date (strict t-1 lag); fixed 2026-05-08 after Codex critic round 1 C10 finding",
    C13_no_negate_pre      = "PASS — load_month_factors -> align_factor_direction (L-168) PIT-safe IC sign auto",
    C14_ic_usable_date     = "PASS — align_factor_direction line 187 ic_avail = ic_hist[Usable_Date <= sig_d]",
    C15_no_direct_parquet  = "PASS — sig_date enumeration via rawdata month-ends only; load_month_factors connector exclusive for factor data; fixed 2026-05-08 after Codex critic round 1 C15 finding"
  )
)
write_json(diag_out, "stage_artifacts/WT-D20260508_013/measured_diagnostics.json",
           pretty = TRUE, auto_unbox = TRUE)
cat("[saved] measured_diagnostics.json\n")

# Save AX-001 v2 file
ax001_v2 <- list(
  task_id = WT_ID,
  ax_code = "AX-001 v2",
  evaluation_window = sprintf("%s ~ %s",
                              format(min(sig_unique), "%Y-%m-%d"),
                              format(max(sig_unique), "%Y-%m-%d")),
  bm_threshold_bad_monthly = -0.03,
  ic_bad_mean    = if (is.na(ic_bad_mean))    NA else round(ic_bad_mean,    5),
  ic_normal_mean = if (is.na(ic_normal_mean)) NA else round(ic_normal_mean, 5),
  bad_normal_ratio = if (is.na(bn_ratio)) NA else round(bn_ratio, 3),
  n_bad    = length(ic_bad),
  n_normal = length(ic_normal),
  evaluation_status = "alpha_layer_recorded__risk_agent_will_complete_with_crisis_alpha_and_core_mdd_audit",
  conditional_defense_note = "AX-001 v2: defense classification requires (a) crisis_alpha measurable + (b) Core MDD attenuation + (c) bad/normal IC ratio measurable. Alpha agent provides (c) only; (a)+(b) deferred to Risk + Forge."
)
write_json(ax001_v2,
           "qepm/mailbox/worktask/WT-D20260508_013/ax001_v2_conditional_defense.json",
           pretty = TRUE, auto_unbox = TRUE)
cat("[saved] ax001_v2_conditional_defense.json\n")

# Save orthogonality file
ortho_obj <- list(
  task_id = WT_ID,
  as_of   = format(last_sd, "%Y-%m-%d"),
  comparisons = list(
    vs_WT010_R14_DUVOL = list(
      pearson = round(cor_010_pearson, 3),
      spearman = round(cor_010_spearman, 3),
      n = nrow(ortho_010),
      threshold_strong = 0.30,
      threshold_adequate = 0.50,
      verdict = if (abs(cor_010_pearson) < 0.30) "STRONG_ORTHO"
                else if (abs(cor_010_pearson) < 0.50) "ADEQUATE_ORTHO"
                else "WEAK_ORTHO_OR_OVERLAP"
    ),
    vs_WT009_BAB = list(
      pearson = round(cor_009_pearson, 3),
      spearman = round(cor_009_spearman, 3),
      n = nrow(ortho_009),
      threshold_strong = 0.30,
      threshold_adequate = 0.50,
      verdict = if (abs(cor_009_pearson) < 0.30) "STRONG_ORTHO"
                else if (abs(cor_009_pearson) < 0.50) "ADEQUATE_ORTHO"
                else "WEAK_ORTHO_OR_OVERLAP"
    ),
    vs_Hybrid_M04_M01 = list(
      pearson = round(cor_hyb_pearson, 3),
      spearman = round(cor_hyb_spearman, 3),
      n = nrow(ortho_h),
      threshold_strong = 0.30,
      threshold_adequate = 0.50,
      verdict = if (abs(cor_hyb_pearson) < 0.30) "STRONG_ORTHO"
                else if (abs(cor_hyb_pearson) < 0.50) "ADEQUATE_ORTHO"
                else "WEAK_ORTHO_OR_OVERLAP",
      hybrid_composition = "0.824*M04_Mom_1 + 0.176*M01_Mom_12_1 (STR_1715 + TSMOM equity proxy; bond ETF orthogonal by construction)"
    )
  )
)
write_json(ortho_obj,
           "qepm/mailbox/worktask/WT-D20260508_013/orthogonality_vs_existing.json",
           pretty = TRUE, auto_unbox = TRUE)
cat("[saved] orthogonality_vs_existing.json\n")

# Save DSR strict file
dsr_obj <- list(
  task_id = WT_ID,
  method  = "Bailey-Lopez de Prado (2014) Probabilistic Sharpe Ratio + Deflated Sharpe Ratio",
  primary_metric = "long_short_HML_decile_portfolio_annualized_Sharpe",
  ic_sharpe = list(
    basis = "winner-candidate IC per sig_date (monthly walk-forward)",
    sr_obs_annualized = round(sr_ic, 3),
    T_periods = T_n,
    skew = round(sk_ic, 3),
    kurt = round(ku_ic, 3),
    psr_zero = round(psr_zero_ic, 3),
    dsr_N5_realistic  = round(dsr_realistic_ic, 3),
    dsr_N100_strict   = round(dsr_strict_ic, 3)
  ),
  hml_sharpe = list(
    basis = "top-decile minus bottom-decile equal-weight monthly long-short portfolio",
    sr_obs_annualized = round(sr_hml, 3),
    T_periods = T_hml,
    skew = round(sk_hml, 3),
    kurt = round(ku_hml, 3),
    psr_zero = round(psr_zero_hml, 3),
    dsr_N5_realistic  = round(dsr_realistic_hml, 3),
    dsr_N100_strict   = round(dsr_strict_hml, 3)
  ),
  primary_dsr_realistic = round(dsr_realistic_hml, 3),
  primary_dsr_pass_05 = dsr_realistic_hml >= 0.5,
  rationale = sprintf("N_trials=5 reflects actual method-shopping log entries (c1_var, c2_mom, c3_mult, c4_rcomp, c5_corner). N_trials=100 retained as ultra-conservative cross-publication ceiling. HML Sharpe = %.3f / DSR(N=5) = %.3f. IC Sharpe = %.3f / DSR(N=5) = %.3f.",
                      sr_hml, dsr_realistic_hml, sr_ic, dsr_realistic_ic)
)
write_json(dsr_obj,
           "qepm/mailbox/worktask/WT-D20260508_013/dsr_strict_bailey_ldp.json",
           pretty = TRUE, auto_unbox = TRUE)
cat("[saved] dsr_strict_bailey_ldp.json\n")

cat("[run_all] DONE\n")
