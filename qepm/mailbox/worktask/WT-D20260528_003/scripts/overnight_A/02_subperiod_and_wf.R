#==============================================================================
# WT-D20260528_003 Hypothesis A — Step 2
# - Subperiod stability (2007-14 / 2015-19 / 2020-23)
# - Walk-forward expanding ICIR (PIT — sig_date t의 weight는 t-1까지 IC만)
# - Multi-sleeve construction (Sleeve A: D43 top10 / Sleeve B: D44 top10)
# - alpha_vector composition + sleeve overlap diag
# - Harvey t / Deflated SR / Newey-West / Bootstrap CI
# - AX-001 v2 bad/normal regime IC
#==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(jsonlite)
})

t0 <- Sys.time()

PROJ <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
setwd(PROJ)

OUT_DIR <- "stage_artifacts/WT_D20260528_003_overnight_A"

panel_dt <- as.data.table(readRDS(file.path(OUT_DIR, "panel_neut.rds")))
ic_dt    <- as.data.table(readRDS(file.path(OUT_DIR, "ic_per_sigdate.rds")))

# Newey-West HAC adjusted t-stat
nw_tstat <- function(x, lags = 6) {
  x <- x[!is.na(x)]
  n <- length(x)
  if (n < 12) return(list(t = NA, se = NA, n = n))
  m <- mean(x)
  ex <- x - m
  s2 <- sum(ex^2) / n
  for (k in 1:lags) {
    w <- 1 - k / (lags + 1)
    s2 <- s2 + 2 * w * sum(ex[1:(n-k)] * ex[(k+1):n]) / n
  }
  se <- sqrt(s2 / n)
  list(t = m / se, se = se, n = n)
}

# ---- Subperiod stability ----
cat("[Step 2.1] Subperiod stability (3 windows)\n")
ic_dt[, period := fcase(
  sig_date < as.Date("2015-01-01"), "p1_2007_2014",
  sig_date < as.Date("2020-01-01"), "p2_2015_2019",
  default = "p3_2020_2023"
)]

subperiod_summary <- function(ic_vec, periods, label) {
  res <- list()
  for (p in c("p1_2007_2014", "p2_2015_2019", "p3_2020_2023")) {
    v <- ic_vec[periods == p]
    v <- v[!is.na(v)]
    nw <- nw_tstat(v, lags = 6)
    res[[p]] <- list(
      ic_mean = round(mean(v), 4),
      ic_sd   = round(sd(v),   4),
      icir    = round(if (sd(v) > 0) mean(v) / sd(v) else NA_real_, 3),
      n       = length(v),
      t_nw    = round(nw$t, 2)
    )
  }
  cat(sprintf("  %s — p1 ICIR=%.3f t_nw=%.2f / p2 ICIR=%.3f t_nw=%.2f / p3 ICIR=%.3f t_nw=%.2f\n",
              label,
              res$p1_2007_2014$icir, res$p1_2007_2014$t_nw,
              res$p2_2015_2019$icir, res$p2_2015_2019$t_nw,
              res$p3_2020_2023$icir, res$p3_2020_2023$t_nw))
  res
}

sub_d43_neut <- subperiod_summary(ic_dt$IC_43_neut, ic_dt$period, "D43_neut")
sub_d44_neut <- subperiod_summary(ic_dt$IC_44_neut, ic_dt$period, "D44_neut")

# Subperiod stability scalar: min(p_i ICIR sign matches overall) / 3
stab_score <- function(sub, overall_sign) {
  vals <- sapply(sub, function(x) x$icir)
  sign_match <- sum(sign(vals) == overall_sign, na.rm = TRUE)
  sign_match / length(vals)
}

overall_43 <- sign(mean(ic_dt$IC_43_neut, na.rm = TRUE))
overall_44 <- sign(mean(ic_dt$IC_44_neut, na.rm = TRUE))
stab_43 <- stab_score(sub_d43_neut, overall_43)
stab_44 <- stab_score(sub_d44_neut, overall_44)

cat(sprintf("  Stability score (sign match / 3): D43=%.2f / D44=%.2f\n", stab_43, stab_44))

# ---- Walk-forward expanding ICIR (PIT mandate) ----
# At sig_date t, weight = ICIR computed on IC up to t-1 only.
cat("\n[Step 2.2] Walk-forward expanding ICIR (PIT — t uses ≤ t-1 only)\n")

setorder(ic_dt, sig_date)
ic_dt[, idx := .I]
n_total <- nrow(ic_dt)

BURNIN <- 36L  # 3 years burn-in (require 36 monthly IC obs before signal use)

ic_dt[, w_43_wf := NA_real_]
ic_dt[, w_44_wf := NA_real_]

for (k in (BURNIN + 1):n_total) {
  hist43 <- ic_dt$IC_43_neut[1:(k-1)]
  hist44 <- ic_dt$IC_44_neut[1:(k-1)]
  m43 <- mean(hist43, na.rm = TRUE); s43 <- sd(hist43, na.rm = TRUE)
  m44 <- mean(hist44, na.rm = TRUE); s44 <- sd(hist44, na.rm = TRUE)
  ir43 <- if (s43 > 0) m43 / s43 else 0
  ir44 <- if (s44 > 0) m44 / s44 else 0
  ic_dt$w_43_wf[k] <- ir43
  ic_dt$w_44_wf[k] <- ir44
}

# Walk-forward selected sig_dates (post burn-in)
ic_wf <- ic_dt[!is.na(w_43_wf)]
cat(sprintf("  WF sig_dates active: %d (burn-in cut: %s onward)\n",
            nrow(ic_wf), as.character(min(ic_wf$sig_date))))

# Realized IC per sig_date via walk-forward weights
ic_wf[, IC_composite_wf := (w_43_wf * IC_43_neut + w_44_wf * IC_44_neut) /
                            pmax(abs(w_43_wf) + abs(w_44_wf), 1e-6)]
m_comp <- mean(ic_wf$IC_composite_wf, na.rm = TRUE)
s_comp <- sd(  ic_wf$IC_composite_wf, na.rm = TRUE)
ir_comp <- if (s_comp > 0) m_comp / s_comp else NA_real_
nw_comp <- nw_tstat(ic_wf$IC_composite_wf, lags = 6)

cat(sprintf("  Composite WF IC: mean=%+.4f sd=%.4f ICIR=%+.3f t_nw=%+.2f N=%d\n",
            m_comp, s_comp, ir_comp, nw_comp$t, nw_comp$n))

# WF single-factor restated
m43_wf <- mean(ic_wf$IC_43_neut, na.rm = TRUE); s43_wf <- sd(ic_wf$IC_43_neut, na.rm = TRUE)
m44_wf <- mean(ic_wf$IC_44_neut, na.rm = TRUE); s44_wf <- sd(ic_wf$IC_44_neut, na.rm = TRUE)
ir43_wf <- if (s43_wf > 0) m43_wf / s43_wf else NA_real_
ir44_wf <- if (s44_wf > 0) m44_wf / s44_wf else NA_real_
nw43_wf <- nw_tstat(ic_wf$IC_43_neut, lags = 6)
nw44_wf <- nw_tstat(ic_wf$IC_44_neut, lags = 6)

cat(sprintf("  D43_neut WF: ICIR=%+.3f t_nw=%+.2f N=%d\n", ir43_wf, nw43_wf$t, nw43_wf$n))
cat(sprintf("  D44_neut WF: ICIR=%+.3f t_nw=%+.2f N=%d\n", ir44_wf, nw44_wf$t, nw44_wf$n))

# ---- Multi-sleeve construction ----
# Sleeve A: top 10 by Z43_neut
# Sleeve B: top 10 by Z44_neut (exclude Sleeve A overlap → fill from D44 ranked)
# alpha_vector(i): Z43_neut(i) if in A only, Z44_neut(i) if in B only, max(Z43_neut, Z44_neut) if both
cat("\n[Step 2.3] Multi-sleeve alpha vector construction\n")

build_sleeves <- function(snap_dt, k_per = 10) {
  ord43 <- snap_dt[order(-Z43_neut), Ticker]
  ord44 <- snap_dt[order(-Z44_neut), Ticker]
  sleeve_A <- head(ord43, k_per)
  sleeve_B_cand <- setdiff(ord44, sleeve_A)
  sleeve_B <- head(sleeve_B_cand, k_per)
  list(A = sleeve_A, B = sleeve_B,
       overlap_intent = sum(sleeve_A %in% head(ord44, k_per)),  # how many top D44 would overlap
       n_A = length(sleeve_A), n_B = length(sleeve_B))
}

# walk-forward valid sig_dates (post burn-in)
sig_list <- ic_wf$sig_date
alpha_rows <- list()

for (sd in as.character(sig_list)) {
  snap <- panel_dt[sig_date == as.Date(sd)]
  if (nrow(snap) < 30) next
  slv <- build_sleeves(snap, k_per = 10)
  if (slv$n_A + slv$n_B < 20) next

  # alpha per ticker:
  # in A only: Z43_neut
  # in B only: Z44_neut
  # in neither: 0
  setkey(snap, Ticker)
  arow <- data.table(
    sig_date = as.Date(sd),
    Ticker = c(slv$A, slv$B),
    sleeve = c(rep("A_skew", length(slv$A)), rep("B_kurt", length(slv$B)))
  )
  arow[, alpha := ifelse(sleeve == "A_skew",
                         snap[arow$Ticker, Z43_neut, on = "Ticker"],
                         snap[arow$Ticker, Z44_neut, on = "Ticker"])]
  arow[, fwd_1m := snap[arow$Ticker, fwd_1m, on = "Ticker"]]
  arow[, Sector_Lv2 := snap[arow$Ticker, Sector_Lv2, on = "Ticker"]]
  arow[, overlap_intent := slv$overlap_intent]
  alpha_rows[[sd]] <- arow
}

alpha_dt <- rbindlist(alpha_rows, fill = TRUE)
cat(sprintf("  alpha_dt rows: %d, sig_dates: %d\n", nrow(alpha_dt), length(unique(alpha_dt$sig_date))))
cat(sprintf("  sleeve A count: %d, sleeve B count: %d\n",
            sum(alpha_dt$sleeve == "A_skew"), sum(alpha_dt$sleeve == "B_kurt")))

# ---- Portfolio return (EW long-only top 20) ----
port_ret <- alpha_dt[, .(
  ret = mean(fwd_1m, na.rm = TRUE),
  N   = .N,
  n_A = sum(sleeve == "A_skew"),
  n_B = sum(sleeve == "B_kurt"),
  overlap_intent = first(overlap_intent)
), by = sig_date]
setorder(port_ret, sig_date)

# Benchmark (KOSPI200 total return — use BM_Ret per sig_date next month)
raw <- as.data.table(read_parquet(".cache/rawdata.parquet"))
raw[, Date := as.Date(Date)]
bm_ts <- raw[, .(BM_Ret = first(BM_Ret)), by = Date]
setorder(bm_ts, Date)

# month-end → next month-end BM
me_seq <- sort(unique(raw$Date[raw$Date >= as.Date("2007-01-01")]))
# compute next-month BM cumulative return per sig_date
sig_dates_alpha <- port_ret$sig_date
bm_next_ret <- numeric(length(sig_dates_alpha))
for (i in seq_along(sig_dates_alpha)) {
  sd <- sig_dates_alpha[i]
  # next month-end
  ym_next <- format(seq(sd, by = "1 month", length.out = 2)[2], "%Y%m")
  dates_next <- bm_ts$Date[format(bm_ts$Date, "%Y%m") == ym_next]
  if (length(dates_next) == 0) { bm_next_ret[i] <- NA; next }
  bm_subset <- bm_ts[Date %in% dates_next, BM_Ret]
  bm_next_ret[i] <- prod(1 + bm_subset, na.rm = TRUE) - 1
}
port_ret[, BM_next_1m := bm_next_ret]
port_ret[, ER := ret - BM_next_1m]   # excess return

# Performance metrics
er_v <- port_ret$ER
er_v <- er_v[!is.na(er_v)]
mean_er <- mean(er_v)
sd_er   <- sd(er_v)
sr_mon  <- if (sd_er > 0) mean_er / sd_er else NA
sr_ann  <- sr_mon * sqrt(12)
nw_er <- nw_tstat(er_v, lags = 6)

cat(sprintf("\n[Portfolio EW top 20] N=%d months, mean_ER=%+.4f sd=%.4f SR_mon=%+.3f SR_ann=%+.2f t_nw=%+.2f\n",
            length(er_v), mean_er, sd_er, sr_mon, sr_ann, nw_er$t))

# ---- AX-001 v2: bad / normal regime IC ----
# Bad regime: BM next 1M < -5% (e.g., 2008 / 2020-03 / 2022 bear)
# Normal regime: otherwise
ic_wf[, regime := fcase(
  is.na(NA_real_), "skip",  # placeholder
  default = "tmp"
)]
# Merge BM next-month return to ic_wf
bm_map <- port_ret[, .(sig_date, BM_next_1m)]
ic_wf <- merge(ic_wf, bm_map, by = "sig_date", all.x = TRUE)
ic_wf[, regime := fifelse(BM_next_1m < -0.05, "bad", "normal")]

regime_ic <- ic_wf[!is.na(regime) & !is.na(BM_next_1m), .(
  D43_neut_IC = mean(IC_43_neut, na.rm = TRUE),
  D44_neut_IC = mean(IC_44_neut, na.rm = TRUE),
  N = .N
), by = regime]
print(regime_ic)

ratio_43 <- regime_ic[regime == "bad", D43_neut_IC] /
            pmax(abs(regime_ic[regime == "normal", D43_neut_IC]), 1e-6)
ratio_44 <- regime_ic[regime == "bad", D44_neut_IC] /
            pmax(abs(regime_ic[regime == "normal", D44_neut_IC]), 1e-6)

cat(sprintf("  AX-001 v2 bad/normal ratio: D43_neut=%+.2f D44_neut=%+.2f\n",
            ratio_43, ratio_44))

# ---- Harvey t-stat per sig_date IC sequence ----
# Harvey-Liu-Zhu adjusted t: for n_trials = total candidates tried (≤5 per init_prompt R2-C)
# Bonferroni: t_adj_threshold = qnorm(1 - 0.025/n_trials)
n_trials <- 5L  # conservative cap (initial: D43_raw, D44_raw, D43_neut, D44_neut, composite)
harvey_threshold <- qnorm(1 - 0.025 / n_trials)
cat(sprintf("\n[Harvey-Liu-Zhu] n_trials=%d, threshold t=%.2f (at α=0.05, Bonferroni)\n",
            n_trials, harvey_threshold))

harvey_check <- function(ic_vec, label) {
  nw <- nw_tstat(ic_vec, lags = 6)
  pass <- abs(nw$t) > harvey_threshold
  cat(sprintf("  %-15s t_nw=%+.2f vs harvey=%.2f  %s\n",
              label, nw$t, harvey_threshold,
              if (pass) "PASS" else "FAIL"))
  list(t = round(nw$t, 2), pass = pass)
}

hv_d43_neut <- harvey_check(ic_wf$IC_43_neut, "D43_neut_WF")
hv_d44_neut <- harvey_check(ic_wf$IC_44_neut, "D44_neut_WF")
hv_d43_raw  <- harvey_check(ic_wf$IC_43_raw,  "D43_raw_WF")
hv_d44_raw  <- harvey_check(ic_wf$IC_44_raw,  "D44_raw_WF")
hv_comp     <- harvey_check(ic_wf$IC_composite_wf, "Composite_WF")

harvey_pass_count <- sum(sapply(list(hv_d43_neut, hv_d44_neut, hv_d43_raw, hv_d44_raw, hv_comp),
                                 function(x) x$pass))
cat(sprintf("  Harvey PASS count: %d / 5\n", harvey_pass_count))

# ---- Deflated Sharpe Ratio (Bailey-Lopez de Prado 2014) ----
# SR_adj = SR * sqrt(1 - skew/T * SR + (kurt-1)/(4T) * SR^2)
# DSR uses sqrt(T-1) and accounts for n_trials selection
dsr_compute <- function(returns, n_trials = 1L) {
  r <- returns[!is.na(returns)]
  T <- length(r)
  if (T < 24) return(NA_real_)
  sr <- mean(r) / sd(r)
  sk <- mean((r - mean(r))^3) / sd(r)^3
  kt <- mean((r - mean(r))^4) / sd(r)^4
  # variance of SR estimator (Bailey-Lopez de Prado)
  var_sr <- (1 - sk * sr + (kt - 1)/4 * sr^2) / (T - 1)
  # Expected max SR under null (Bailey-Lopez de Prado)
  euler_mascheroni <- 0.5772156649
  E_max_sr <- sqrt(var_sr) * (
    (1 - euler_mascheroni) * qnorm(1 - 1/n_trials) +
    euler_mascheroni * qnorm(1 - 1/(n_trials * exp(1)))
  )
  # DSR (one-sided p-value via pnorm)
  z <- (sr - E_max_sr) / sqrt(var_sr)
  pnorm(z)
}

dsr_er <- dsr_compute(er_v, n_trials = 5L)
cat(sprintf("\n[Deflated SR] Portfolio ER DSR p-value (n_trials=5): %.3f\n", dsr_er))

# ---- Bootstrap IC CI ----
B <- 1000L
set.seed(42L)
boot_d43 <- replicate(B, {
  idx <- sample(seq_len(nrow(ic_wf)), replace = TRUE)
  mean(ic_wf$IC_43_neut[idx], na.rm = TRUE)
})
boot_d44 <- replicate(B, {
  idx <- sample(seq_len(nrow(ic_wf)), replace = TRUE)
  mean(ic_wf$IC_44_neut[idx], na.rm = TRUE)
})

ci43 <- quantile(boot_d43, c(0.025, 0.975), na.rm = TRUE)
ci44 <- quantile(boot_d44, c(0.025, 0.975), na.rm = TRUE)
cat(sprintf("\n[Bootstrap CI95 (B=1000)]\n"))
cat(sprintf("  D43_neut mean IC: %+.4f  [%+.4f, %+.4f]  excludes_0: %s\n",
            mean(boot_d43), ci43[1], ci43[2],
            if (ci43[1] > 0 || ci43[2] < 0) "YES" else "NO"))
cat(sprintf("  D44_neut mean IC: %+.4f  [%+.4f, %+.4f]  excludes_0: %s\n",
            mean(boot_d44), ci44[1], ci44[2],
            if (ci44[1] > 0 || ci44[2] < 0) "YES" else "NO"))

# ---- Save artifacts ----
saveRDS(alpha_dt, file.path(OUT_DIR, "alpha_dt_sleeves.rds"))
saveRDS(port_ret, file.path(OUT_DIR, "port_ret.rds"))
saveRDS(ic_wf, file.path(OUT_DIR, "ic_wf.rds"))

step2_summary <- list(
  hypothesis = "A",
  walk_forward_sig_dates = nrow(ic_wf),
  burn_in_months = BURNIN,
  subperiod = list(
    D43_neut = sub_d43_neut,
    D44_neut = sub_d44_neut,
    stability_score_D43 = stab_43,
    stability_score_D44 = stab_44
  ),
  walk_forward_metrics = list(
    D43_neut_WF = list(icir = round(ir43_wf, 3), t_nw = round(nw43_wf$t, 2)),
    D44_neut_WF = list(icir = round(ir44_wf, 3), t_nw = round(nw44_wf$t, 2)),
    Composite_WF = list(icir = round(ir_comp, 3), t_nw = round(nw_comp$t, 2),
                        ic_mean = round(m_comp, 4))
  ),
  portfolio_perf = list(
    months = length(er_v),
    mean_er_monthly = round(mean_er, 4),
    sd_er_monthly   = round(sd_er, 4),
    sharpe_monthly  = round(sr_mon, 3),
    sharpe_annualized = round(sr_ann, 2),
    t_nw_er = round(nw_er$t, 2)
  ),
  ax_001_v2_regime = list(
    bad_normal_ratio_D43 = round(ratio_43, 2),
    bad_normal_ratio_D44 = round(ratio_44, 2),
    by_regime = regime_ic
  ),
  harvey_check = list(
    n_trials = n_trials,
    threshold = round(harvey_threshold, 2),
    D43_neut_WF = hv_d43_neut,
    D44_neut_WF = hv_d44_neut,
    D43_raw_WF  = hv_d43_raw,
    D44_raw_WF  = hv_d44_raw,
    Composite_WF = hv_comp,
    pass_count = harvey_pass_count
  ),
  dsr_pvalue = round(dsr_er, 3),
  bootstrap_ci = list(
    D43_neut = list(mean = round(mean(boot_d43),4), lo = round(ci43[1],4), hi = round(ci43[2],4),
                    excludes_0 = (ci43[1] > 0 || ci43[2] < 0)),
    D44_neut = list(mean = round(mean(boot_d44),4), lo = round(ci44[1],4), hi = round(ci44[2],4),
                    excludes_0 = (ci44[1] > 0 || ci44[2] < 0))
  )
)
write_json(step2_summary, file.path(OUT_DIR, "step2_summary.json"),
           pretty = TRUE, auto_unbox = TRUE)

cat("\n[Step 2 DONE] elapsed:", round(as.numeric(Sys.time() - t0, units = "secs"), 1), "s\n")
cat("  alpha_dt:    ", file.path(OUT_DIR, "alpha_dt_sleeves.rds"), "\n")
cat("  summary:     ", file.path(OUT_DIR, "step2_summary.json"), "\n")
