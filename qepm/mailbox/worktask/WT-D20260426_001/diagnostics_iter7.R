#==============================================================================
# WT-D20260426_001 Iter 7 — Alpha Diagnostics
#   IC / ICIR / Harvey t / Subperiod / Monotonicity / TDC vs STR_1700 / 5-spec
#==============================================================================

suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite)
})
PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
setwd(PROJECT_ROOT)

WT_ID  <- "WT-D20260426_001"
ART    <- file.path("stage_artifacts", "WT_D20260426_001")

# ---- Load alpha + STR_1700 + RAWDATA ----
alpha_ts <- read_parquet(file.path(ART, "alpha_scores.parquet")) |> setDT()
str1700  <- read_parquet("stage_artifacts/WT_D20260425_011/alpha_scores.parquet") |> setDT()
rd       <- read_parquet(".cache/rawdata.parquet") |> setDT()

cat("[Iter7-Diag] alpha rows:", nrow(alpha_ts), " | tickers:",
    uniqueN(alpha_ts$Ticker), " | sig_dates:", uniqueN(alpha_ts$sig_date), "\n")

# ---- Compute monthly forward returns (1M ahead from sig_date) ----
rd[, Date := as.Date(Date)]
rd <- rd[!is.na(Ret) & !is.na(Ticker) & !is.na(Date)]
# Use period after sig_date — "Ret_fwd1m" = total return over the calendar month
# starting at sig_date (which is first-of-month).
rd[, ym_first := as.Date(format(Date, "%Y-%m-01"))]
fwd1m <- rd[, .(Ret_1m = prod(1 + Ret, na.rm = TRUE) - 1L,
                Vol_20d = mean(Vol, na.rm = TRUE)),
            by = .(Ticker, sig_date = ym_first)]

# ---- Liquidity filter (20d avg TV) ----
# rough: keep top 70% by Vol*Close to avoid super-illiquid
rd[, TV := Close * Vol]
liq_avg <- rd[, .(TV_avg = mean(TV, na.rm = TRUE)),
              by = .(Ticker, sig_date = ym_first)]
liq_avg[, top70 := frank(-TV_avg, ties.method = "first") /
          .N <= 0.70, by = sig_date]

# ---- Merge alpha with returns ----
setkey(alpha_ts, sig_date, Ticker)
setkey(fwd1m, sig_date, Ticker)
merged <- fwd1m[alpha_ts, on = c("sig_date", "Ticker")]
merged <- merge(merged, liq_avg[, .(Ticker, sig_date, TV_avg, top70)],
                by = c("Ticker", "sig_date"), all.x = TRUE)
merged <- merged[!is.na(Ret_1m) & !is.na(alpha) & top70 == TRUE]
cat("[Iter7-Diag] merged rows post-liq:", nrow(merged), "\n")

# ---- IC per month ----
ic_per_month <- merged[, .(IC = cor(alpha, Ret_1m, method = "spearman"),
                            N = .N), by = sig_date]
ic_per_month <- ic_per_month[!is.na(IC) & N >= 30L]
rank_ic <- mean(ic_per_month$IC, na.rm = TRUE)
ic_sd   <- sd(ic_per_month$IC, na.rm = TRUE)
icir    <- if (ic_sd > 1e-9) rank_ic / ic_sd else NA_real_
n_months <- nrow(ic_per_month)
harvey_t <- if (!is.na(icir)) icir * sqrt(n_months) else NA_real_

cat("\n=== [Iter7-Diag] Predictive Power ===\n")
cat("rank_IC (mean):", round(rank_ic, 4), "\n")
cat("IC sd:         ", round(ic_sd, 4), "\n")
cat("ICIR:          ", round(icir, 3), "\n")
cat("Harvey t (IC): ", round(harvey_t, 2), " (N=", n_months, ")\n")

# ---- Subperiod stability (3 splits) ----
ic_per_month[, period := fifelse(sig_date <= as.Date("2014-12-31"), "P1_04_14",
                                 fifelse(sig_date <= as.Date("2019-12-31"),
                                         "P2_15_19", "P3_20_23"))]
sp_ic <- ic_per_month[, .(IC_sp = mean(IC), IC_sd_sp = sd(IC), N = .N),
                       by = period]
setorder(sp_ic, period)
sp_ic[, ICIR_sp := IC_sp / IC_sd_sp]
sp_ic[, t_sp := ICIR_sp * sqrt(N)]
cat("\n=== [Iter7-Diag] Subperiod ===\n"); print(sp_ic)

same_sign <- mean(sign(sp_ic$IC_sp) == sign(rank_ic), na.rm = TRUE)
subperiod_stab <- same_sign  # 1.0 = all 3 same sign as full

# ---- Monotonicity (full sample decile) ----
merged[, decile := cut(alpha,
                       breaks = quantile(alpha, probs = seq(0, 1, 0.1),
                                         na.rm = TRUE),
                       include.lowest = TRUE, labels = 1:10),
       by = sig_date]
dec_ret <- merged[!is.na(decile),
                  .(Ret_avg = mean(Ret_1m, na.rm = TRUE)),
                  by = .(decile)]
dec_ret[, decile_n := as.integer(as.character(decile))]
setorder(dec_ret, decile_n)
mono <- if (nrow(dec_ret) >= 5L) {
  cor(dec_ret$decile_n, dec_ret$Ret_avg, method = "spearman")
} else NA_real_
cat("\n=== [Iter7-Diag] Monotonicity ===\n")
print(dec_ret)
cat("Spearman rank-correlation (decile→ret):", round(mono, 3), "\n")

# ---- Long-Short portfolio return (Q10-Q1, EW) ----
qret <- merged[!is.na(decile),
               .(Ret = mean(Ret_1m, na.rm = TRUE)),
               by = .(sig_date, decile)]
qret_w <- dcast(qret, sig_date ~ decile, value.var = "Ret")
setnames(qret_w, c("sig_date", paste0("Q", 1:10)))
qret_w[, LS := Q10 - Q1]
qret_w[, LO := Q10]   # long-only top decile

ls_mean   <- mean(qret_w$LS, na.rm = TRUE)
ls_sd     <- sd(qret_w$LS, na.rm = TRUE)
ls_t      <- ls_mean / (ls_sd / sqrt(sum(!is.na(qret_w$LS))))
ls_sr_ann <- ls_mean / ls_sd * sqrt(12)

lo_mean   <- mean(qret_w$LO, na.rm = TRUE)
lo_sd     <- sd(qret_w$LO, na.rm = TRUE)
lo_sr_ann <- lo_mean / lo_sd * sqrt(12)

cat("\n=== [Iter7-Diag] LS Q10-Q1 portfolio ===\n")
cat("Mean monthly:", round(ls_mean*100, 3), "% | sd:", round(ls_sd*100, 3),
    "% | t-stat:", round(ls_t, 2), " | SR_ann:", round(ls_sr_ann, 3), "\n")
cat("Long-only Q10 SR_ann:", round(lo_sr_ann, 3), "\n")

# ---- 5-spec Harvey test (signal-stability under composition variations) ----
spec_results <- list()

run_spec <- function(name, factor_subset, weights = NULL) {
  if (is.null(weights)) weights <- rep(1/length(factor_subset), length(factor_subset))
  source("02_Infrastructure/factor_db/factor_db_connector.R", local = TRUE)
  sd_pool <- sort(unique(merged$sig_date))
  per_month_ic <- numeric(length(sd_pool))
  for (i in seq_along(sd_pool)) {
    sd_i <- sd_pool[i]
    fdt <- tryCatch(
      suppressMessages(load_month_factors(sig_date = sd_i, coverage_min = 0.05)),
      error = function(e) NULL)
    if (is.null(fdt) || nrow(fdt) == 0) { per_month_ic[i] <- NA; next }
    setDT(fdt)
    sub <- fdt[Factor_Name %in% factor_subset]
    if (nrow(sub) == 0) { per_month_ic[i] <- NA; next }
    w <- dcast(sub, Ticker ~ Factor_Name, value.var = "Z_Score_Aligned",
               fun.aggregate = mean)
    w[, alpha_spec := 0]
    for (k in seq_along(factor_subset)) {
      fn <- factor_subset[k]
      if (fn %in% names(w)) {
        v <- w[[fn]]; v[is.na(v)] <- 0
        w[, alpha_spec := alpha_spec + weights[k] * v]
      }
    }
    rt <- fwd1m[sig_date == sd_i, .(Ticker, Ret_1m)]
    m  <- merge(w[, .(Ticker, alpha_spec)], rt, by = "Ticker")
    m  <- merge(m, liq_avg[sig_date == sd_i & top70 == TRUE,
                            .(Ticker, top70)], by = "Ticker")
    m  <- m[!is.na(Ret_1m) & !is.na(alpha_spec)]
    if (nrow(m) < 30) { per_month_ic[i] <- NA; next }
    per_month_ic[i] <- cor(m$alpha_spec, m$Ret_1m, method = "spearman")
  }
  ic_clean <- per_month_ic[!is.na(per_month_ic)]
  list(name = name, n = length(ic_clean),
       mean_ic = mean(ic_clean), icir = mean(ic_clean) / sd(ic_clean),
       harvey_t = (mean(ic_clean) / sd(ic_clean)) * sqrt(length(ic_clean)),
       factors = factor_subset, weights = weights)
}

cat("\n=== [Iter7-Diag] 5-spec Harvey Test ===\n")
spec_results[["S1_full_4axis"]] <- run_spec(
  "S1_full_4axis",
  c("L01_Amihud", "L11_Kyle_Lambda", "L12_PS_Gamma", "R13_NCSKEW"),
  c(0.25, 0.25, 0.25, 0.25))
cat("S1 done\n")

spec_results[["S2_liquidity_only"]] <- run_spec(
  "S2_liquidity_only",
  c("L01_Amihud", "L11_Kyle_Lambda", "L12_PS_Gamma"),
  c(1/3, 1/3, 1/3))
cat("S2 done\n")

spec_results[["S3_amihud_ncskew"]] <- run_spec(
  "S3_amihud_ncskew",
  c("L01_Amihud", "R13_NCSKEW"),
  c(0.5, 0.5))
cat("S3 done\n")

spec_results[["S4_3_axis_ex_PSG"]] <- run_spec(
  "S4_3_axis_ex_PSG",
  c("L01_Amihud", "L11_Kyle_Lambda", "R13_NCSKEW"),
  c(1/3, 1/3, 1/3))
cat("S4 done\n")

spec_results[["S5_amihud_only"]] <- run_spec(
  "S5_amihud_only", c("L01_Amihud"), c(1.0))
cat("S5 done\n")

spec_summary <- rbindlist(lapply(spec_results, function(x)
  data.table(name = x$name, n = x$n,
             mean_ic = x$mean_ic, icir = x$icir, harvey_t = x$harvey_t)))
print(spec_summary)
spec_pass_count <- sum(spec_summary$harvey_t > 3.0, na.rm = TRUE)
cat(sprintf("Harvey t>3.0 specs: %d / 5\n", spec_pass_count))

# ---- TDC vs STR_1700 ----
cat("\n=== [Iter7-Diag] TDC vs STR_1700 ===\n")
str1700_dt <- str1700[, .(sig_date = Date, Ticker, alpha_str1700 = score_eff)]
setkey(str1700_dt, sig_date, Ticker)
joined <- merge(merged[, .(sig_date, Ticker, alpha)], str1700_dt,
                by = c("sig_date", "Ticker"))
joined <- joined[!is.na(alpha) & !is.na(alpha_str1700)]
cat("Joined rows:", nrow(joined), "\n")

# Cross-sectional rank correlation per month, then average
xs_corr <- joined[, .(rho = cor(alpha, alpha_str1700, method = "spearman"),
                       N = .N), by = sig_date]
xs_corr <- xs_corr[N >= 30L]
mean_rho <- mean(xs_corr$rho, na.rm = TRUE)
cat("Cross-sec mean Spearman correlation (Iter7 vs STR_1700):",
    round(mean_rho, 3), "\n")

# TDC: lower-tail dependence — fraction of months in which top decile of one
# coincides with top decile of the other (proxy for crisis crowding).
# Use top-decile co-occurrence rate (tail = top 10%, both bullish).
tdc_per_month <- joined[, {
  if (.N < 30) {
    list(coin = NA_real_)
  } else {
    q90_a <- quantile(alpha, 0.9, na.rm = TRUE)
    q90_b <- quantile(alpha_str1700, 0.9, na.rm = TRUE)
    top_a <- alpha       >= q90_a
    top_b <- alpha_str1700 >= q90_b
    n_both <- sum(top_a & top_b, na.rm = TRUE)
    n_top_a <- sum(top_a, na.rm = TRUE)
    list(coin = if (n_top_a > 0) n_both / n_top_a else NA_real_)
  }
}, by = sig_date]
tdc_proxy <- mean(tdc_per_month$coin, na.rm = TRUE)
cat("Top-decile coincidence proxy (TDC top10% upper-tail):",
    round(tdc_proxy, 3), "\n")
# Note: STR_1700 / Iter7 use score_eff vs Liquidity composite
# both higher_better → upper-tail TDC is the relevant crowding metric for long-only.

# Same TDC for lower-tail (10% bottom)
tdc_lower <- joined[, {
  if (.N < 30) {
    list(coin = NA_real_)
  } else {
    q10_a <- quantile(alpha, 0.1, na.rm = TRUE)
    q10_b <- quantile(alpha_str1700, 0.1, na.rm = TRUE)
    bot_a <- alpha       <= q10_a
    bot_b <- alpha_str1700 <= q10_b
    n_both <- sum(bot_a & bot_b, na.rm = TRUE)
    n_b_a  <- sum(bot_a, na.rm = TRUE)
    list(coin = if (n_b_a > 0) n_both / n_b_a else NA_real_)
  }
}, by = sig_date]
tdc_lower_avg <- mean(tdc_lower$coin, na.rm = TRUE)
cat("Bottom-decile TDC proxy:", round(tdc_lower_avg, 3), "\n")

# Conservative TDC = max(upper, lower) — Sequential Admission threshold
tdc_active <- max(tdc_proxy, tdc_lower_avg, na.rm = TRUE)
cat("Active TDC proxy (max upper/lower):", round(tdc_active, 3), "\n")

# ---- KR FF5 v2 portfolio alpha (long-only top decile) ----
cat("\n=== [Iter7-Diag] KR FF5 v2 OLS (long-only top decile) ===\n")
ff5_path <- ".cache/kr_factor_returns_v2.parquet"
ff5_alpha <- ff5_alpha_t <- NA_real_
if (file.exists(ff5_path)) {
  ff5 <- read_parquet(ff5_path) |> setDT()
  cat("FF5 cols:", paste(colnames(ff5), collapse = ", "), "\n")
  if ("Date" %in% names(ff5)) ff5[, Date := as.Date(Date)]
  if ("date" %in% names(ff5)) setnames(ff5, "date", "Date")
  ff5[, ym := as.Date(format(Date, "%Y-%m-01"))]
  # use month-level ff5: avg
  ff5_m <- ff5[, lapply(.SD, mean, na.rm=TRUE), by=ym,
               .SDcols = setdiff(names(ff5), c("Date", "ym"))]
  setnames(ff5_m, "ym", "sig_date")
  port <- qret_w[, .(sig_date, ret_top = LO)]
  full <- merge(port, ff5_m, by = "sig_date")
  cat("FF5-merged rows:", nrow(full), "\n")
  # Find columns: try common schemas
  rhs_candidates <- c("MKT", "Mkt_RF", "Mkt", "MKTRF", "MKTRF_KR",
                      "SMB", "HML", "UMD", "MOM", "QMJ", "RMW", "CMA",
                      "BAB", "Liquidity", "LIQ", "MKT_KR", "SMB_KR",
                      "HML_KR", "RMW_KR", "CMA_KR", "MOM_KR")
  use_rhs <- intersect(rhs_candidates, names(full))
  cat("FF5 RHS used:", paste(use_rhs, collapse = ", "), "\n")
  if (length(use_rhs) >= 3 && nrow(full) >= 24) {
    fmla <- as.formula(paste("ret_top ~", paste(use_rhs, collapse = " + ")))
    fit <- lm(fmla, data = full)
    s <- summary(fit)
    ff5_alpha   <- coef(s)[1, "Estimate"]
    ff5_alpha_t <- coef(s)[1, "t value"]
    cat("FF5 α (intercept):", round(ff5_alpha*12*100, 3), "% ann | t-stat:",
        round(ff5_alpha_t, 2), "\n")
    cat("Adj R²:", round(s$adj.r.squared, 3), "\n")
  } else {
    cat("[WARN] insufficient FF5 columns — skipping OLS\n")
  }
}

# ---- DSR (Bailey-Lopez de Prado, post penalty) ----
# DSR = (SR - SR_BM) / sqrt(...) — approximate via skew/kurt adjusted
# We use simple penalty: DSR ≈ SR_ann * (1 - method_shopping/100) * sqrt((n_months-1)/12)
candidates_tried <- 5L  # 5-spec test
mshop_penalty <- 0.05 * candidates_tried  # 0.25
dsr_post <- ls_sr_ann * (1 - mshop_penalty)
dsr_post_lo <- lo_sr_ann * (1 - mshop_penalty)
cat("\n=== [Iter7-Diag] DSR ===\n")
cat("LS SR_ann:", round(ls_sr_ann, 3), "| DSR_post (penalty=0.25):",
    round(dsr_post, 3), "\n")
cat("LO SR_ann:", round(lo_sr_ann, 3), "| DSR_post (penalty=0.25):",
    round(dsr_post_lo, 3), "\n")

# ---- Persist diagnostics ----
diag <- list(
  rank_ic         = rank_ic,
  icir            = icir,
  harvey_t        = harvey_t,
  n_months        = n_months,
  ic_sd           = ic_sd,
  subperiod_ic    = sp_ic,
  subperiod_stab  = subperiod_stab,
  monotonicity    = mono,
  decile_returns  = dec_ret,
  ls_quantile     = list(mean = ls_mean, sd = ls_sd, t = ls_t,
                          sr_ann = ls_sr_ann),
  long_only_q10   = list(mean = lo_mean, sd = lo_sd, sr_ann = lo_sr_ann),
  spec_summary    = spec_summary,
  spec_pass_count = spec_pass_count,
  tdc_upper       = tdc_proxy,
  tdc_lower       = tdc_lower_avg,
  tdc_active      = tdc_active,
  xs_corr_mean    = mean_rho,
  ff5_alpha_ann   = if (!is.na(ff5_alpha)) ff5_alpha * 12 else NA_real_,
  ff5_alpha_t     = ff5_alpha_t,
  dsr_post_ls     = dsr_post,
  dsr_post_lo     = dsr_post_lo
)
saveRDS(diag, file.path(ART, "alpha_diagnostics.rds"))
cat("\n[Iter7-Diag] Saved alpha_diagnostics.rds\n")
