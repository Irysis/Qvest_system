#==============================================================================
# WT-D20260528_003 Hypothesis A — Step 6: Codex Critic Revisions
#
# Apply Codex REJECT rebuttals:
#   R1. t-1 liquidity (TV_20d using Date<sig_date only)
#   R2. Nonnegative aligned weights (clip negative w to 0, re-normalize)
#   R3. Quarantine fwd_1m from alpha_scores.parquet
#   R4. A-specific challenge_note + lineage (separate from STR_1722)
#   R5. AX-001 salvage: report constraint (we don't have STR_1722 Core MDD here,
#       so document the gap rather than overstate)
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
SIG_CUTOFF <- as.Date("2023-12-22")
LIQ_THRESHOLD <- 2e8

# Reload base panel + apply revisions
raw <- as.data.table(read_parquet(".cache/rawdata.parquet"))
raw[, Date := as.Date(Date)]
raw[, TV := Close * Vol]
setorder(raw, Ticker, Date)

# ---- R1. t-1 liquidity ----
# TV_20d_lag = mean(TV) over Date < current_date (shift by 1) — uses 20 prior days only
cat("[Codex R1] t-1 liquidity (TV_20d excludes signal-date volume)\n")
raw[, TV_lag := shift(TV, n = 1L, type = "lag"), by = Ticker]
raw[, TV_20d_lag := frollmean(TV_lag, n = 20L, na.rm = TRUE), by = Ticker]

source("02_Infrastructure/factor_db/factor_db_connector.R")

month_ends <- raw[, .(Date = max(Date)), by = .(YM = format(Date, "%Y%m"))]
setkey(month_ends, YM)
avail <- list.files(".cache/factor_db", pattern = "^factor_db_\\d{6}\\.parquet$")
ym_avail <- gsub("factor_db_(\\d{6})\\.parquet", "\\1", avail)
ym_avail <- sort(ym_avail)
sig_dates <- month_ends[YM %in% ym_avail & Date <= SIG_CUTOFF, sort(Date)]
sig_dates <- sig_dates[sig_dates >= as.Date("2007-01-01")]

build_universe_t1 <- function(sd) {
  snap <- raw[Date == sd]
  if (nrow(snap) == 0) return(character(0))
  uni <- snap[(K200 == TRUE | KQ150 == TRUE) &
              TV_20d_lag >= LIQ_THRESHOLD &
              AdminStock == FALSE &
              TradingHalt == FALSE &
              UnfaithfulDisc == FALSE &
              !is.na(TV_20d_lag),
              Ticker]
  unique(uni)
}

uni_list_t1 <- lapply(sig_dates, build_universe_t1)
names(uni_list_t1) <- as.character(sig_dates)
uni_size_t1 <- sapply(uni_list_t1, length)
cat(sprintf("  t-1 univ size: min=%d med=%d max=%d (vs same-day in step1: min=%d med=%d max=%d)\n",
            min(uni_size_t1), median(uni_size_t1), max(uni_size_t1),
            274, 318, 366))   # from step1 (approx)

# Compare: how many tickers per sig_date in same-day vs t-1
panel_old <- as.data.table(readRDS(file.path(OUT_DIR, "panel_neut.rds")))
diff_count_v <- numeric(length(sig_dates))
for (i in seq_along(sig_dates)) {
  sd <- sig_dates[i]
  uni_old <- unique(panel_old[sig_date == sd, Ticker])
  uni_new <- uni_list_t1[[as.character(sd)]]
  diff_count_v[i] <- length(setdiff(uni_old, uni_new))
}
cat(sprintf("  Tickers REMOVED by t-1 filter (per sig_date): mean=%.1f median=%.0f max=%d\n",
            mean(diff_count_v), median(diff_count_v), max(diff_count_v)))

# Rebuild panel with t-1 universe
sector_map_fn <- function(sd) {
  snap <- raw[Date == sd, .(Ticker, Sector_Lv2)]
  setkey(snap, Ticker)
  snap
}

cat("[Codex R1 → rebuild panel with t-1 universe + sector neutralize]\n")
panel <- list()
for (i in seq_along(sig_dates)) {
  sd <- sig_dates[i]
  fac <- tryCatch(load_month_factors(sd), error = function(e) NULL)
  if (is.null(fac)) next
  d43 <- fac[Factor_Name == "D43_Skewness", .(Ticker, Z43 = Z_Score_Aligned)]
  d44 <- fac[Factor_Name == "D44_Kurtosis", .(Ticker, Z44 = Z_Score_Aligned)]
  if (nrow(d43) == 0 || nrow(d44) == 0) next

  uni <- uni_list_t1[[as.character(sd)]]
  if (length(uni) == 0) next

  smap <- sector_map_fn(sd)
  p <- merge(d43, d44, by = "Ticker")
  p <- p[Ticker %in% uni]
  p <- merge(p, smap, by = "Ticker", all.x = TRUE)
  p[is.na(Sector_Lv2), Sector_Lv2 := "UNKNOWN"]
  if (nrow(p) < 30) next
  sec_n <- p[, .N, by = Sector_Lv2][N >= 2, Sector_Lv2]
  p <- p[Sector_Lv2 %in% sec_n]
  if (nrow(p) < 30) next
  p[, Sector_Lv2 := factor(Sector_Lv2)]
  f43 <- lm(Z43 ~ Sector_Lv2, data = p)
  f44 <- lm(Z44 ~ Sector_Lv2, data = p)
  p[, Z43_neut := residuals(f43)]
  p[, Z44_neut := residuals(f44)]
  p[, Z43_neut := (Z43_neut - mean(Z43_neut)) / sd(Z43_neut)]
  p[, Z44_neut := (Z44_neut - mean(Z44_neut)) / sd(Z44_neut)]
  p[, sig_date := sd]
  panel[[i]] <- p[, .(sig_date, Ticker, Sector_Lv2, Z43, Z44, Z43_neut, Z44_neut)]
}
panel_t1 <- rbindlist(panel, fill = TRUE)
cat(sprintf("  panel_t1 rows=%d sig_dates=%d\n",
            nrow(panel_t1), length(unique(panel_t1$sig_date))))

# Forward 1M return
me_seq <- sort(month_ends[YM %in% ym_avail, Date])
fwd <- list()
for (sd in sig_dates) {
  next_me <- me_seq[me_seq > sd][1]
  if (is.na(next_me)) next
  sn  <- raw[Date == sd,      .(Ticker, P0 = Close)]
  snn <- raw[Date == next_me, .(Ticker, P1 = Close)]
  m <- merge(sn, snn, by = "Ticker")
  m[, fwd_1m := P1 / P0 - 1]
  m[, sig_date := sd]
  fwd[[as.character(sd)]] <- m[, .(sig_date, Ticker, fwd_1m)]
}
fwd_dt <- rbindlist(fwd)
panel_t1 <- merge(panel_t1, fwd_dt, by = c("sig_date", "Ticker"), all.x = TRUE)
panel_t1 <- panel_t1[!is.na(fwd_1m)]

# Per-sig_date IC under t-1 universe
ic_t1 <- panel_t1[, .(
  IC_43_neut = cor(Z43_neut, fwd_1m, method = "spearman", use = "pairwise.complete.obs"),
  IC_44_neut = cor(Z44_neut, fwd_1m, method = "spearman", use = "pairwise.complete.obs"),
  IC_43_raw  = cor(Z43,      fwd_1m, method = "spearman", use = "pairwise.complete.obs"),
  IC_44_raw  = cor(Z44,      fwd_1m, method = "spearman", use = "pairwise.complete.obs"),
  N_stock    = .N
), by = sig_date]
setorder(ic_t1, sig_date)

# NW t function
nw_tstat <- function(x, lags = 6) {
  x <- x[!is.na(x)]
  n <- length(x)
  if (n < 12) return(list(t = NA, se = NA, n = n))
  m <- mean(x); ex <- x - m; s2 <- sum(ex^2) / n
  for (k in 1:lags) {
    w <- 1 - k / (lags + 1)
    s2 <- s2 + 2 * w * sum(ex[1:(n-k)] * ex[(k+1):n]) / n
  }
  list(t = m / sqrt(s2 / n), se = sqrt(s2 / n), n = n)
}

cat("\n[Codex R1 IC under t-1 liquidity, full set N=", nrow(ic_t1), "]\n")
for (col in c("IC_43_neut", "IC_44_neut", "IC_43_raw", "IC_44_raw")) {
  v <- ic_t1[[col]]
  v <- v[!is.na(v)]
  m  <- mean(v); s <- sd(v); ir <- if (s>0) m/s else NA
  nw <- nw_tstat(v)
  cat(sprintf("  %-12s mean=%+.4f sd=%.4f ICIR=%+.3f t_nw=%+.2f N=%d\n",
              col, m, s, ir, nw$t, nw$n))
}

# ---- R2. Nonnegative aligned weights walk-forward ----
cat("\n[Codex R2] Walk-forward weights with nonnegative clamp\n")
BURNIN <- 36L
ic_t1[, idx := .I]
n_total <- nrow(ic_t1)
ic_t1[, w_43_wf := NA_real_]
ic_t1[, w_44_wf := NA_real_]
ic_t1[, w_43_wf_nneg := NA_real_]
ic_t1[, w_44_wf_nneg := NA_real_]

for (k in (BURNIN + 1):n_total) {
  hist43 <- ic_t1$IC_43_neut[1:(k-1)]
  hist44 <- ic_t1$IC_44_neut[1:(k-1)]
  m43 <- mean(hist43, na.rm = TRUE); s43 <- sd(hist43, na.rm = TRUE)
  m44 <- mean(hist44, na.rm = TRUE); s44 <- sd(hist44, na.rm = TRUE)
  ir43 <- if (s43 > 0) m43 / s43 else 0
  ir44 <- if (s44 > 0) m44 / s44 else 0
  ic_t1$w_43_wf[k] <- ir43
  ic_t1$w_44_wf[k] <- ir44
  ic_t1$w_43_wf_nneg[k] <- pmax(ir43, 0)
  ic_t1$w_44_wf_nneg[k] <- pmax(ir44, 0)
}

ic_wf <- ic_t1[!is.na(w_43_wf)]
neg_43 <- sum(ic_wf$w_43_wf < 0, na.rm = TRUE)
neg_44 <- sum(ic_wf$w_44_wf < 0, na.rm = TRUE)
cat(sprintf("  Negative-weight sig_dates: w_43_wf=%d/%d, w_44_wf=%d/%d (under t-1 universe)\n",
            neg_43, nrow(ic_wf), neg_44, nrow(ic_wf)))

# Composite IC with nonnegative weights
ic_wf[, IC_composite_wf_nneg := (w_43_wf_nneg * IC_43_neut + w_44_wf_nneg * IC_44_neut) /
                                  pmax(w_43_wf_nneg + w_44_wf_nneg, 1e-6)]
v <- ic_wf$IC_composite_wf_nneg
v <- v[!is.na(v)]
m  <- mean(v); s <- sd(v); ir <- if (s>0) m/s else NA
nw <- nw_tstat(v)
cat(sprintf("  Composite WF (nneg) IC mean=%+.4f sd=%.4f ICIR=%+.3f t_nw=%+.2f N=%d\n",
            m, s, ir, nw$t, nw$n))

# Also compute single factor WF t-stats
nw43 <- nw_tstat(ic_wf$IC_43_neut)
nw44 <- nw_tstat(ic_wf$IC_44_neut)
ir43_wf <- mean(ic_wf$IC_43_neut, na.rm=TRUE) / sd(ic_wf$IC_43_neut, na.rm=TRUE)
ir44_wf <- mean(ic_wf$IC_44_neut, na.rm=TRUE) / sd(ic_wf$IC_44_neut, na.rm=TRUE)
cat(sprintf("  D43_neut WF (t-1): ICIR=%+.3f t_nw=%+.2f\n", ir43_wf, nw43$t))
cat(sprintf("  D44_neut WF (t-1): ICIR=%+.3f t_nw=%+.2f\n", ir44_wf, nw44$t))

# Harvey threshold
harvey_threshold <- qnorm(1 - 0.025 / 5)  # n_trials=5
harvey_pass_t1 <- sum(c(nw43$t, nw44$t, nw$t) > harvey_threshold)
cat(sprintf("  Harvey n_trials=5 threshold=%.2f, PASS count under t-1 = %d/3\n",
            harvey_threshold, harvey_pass_t1))

# Build multi-sleeve portfolio under t-1 universe + nonneg weights
build_sleeves <- function(snap_dt, k_per = 10) {
  ord43 <- snap_dt[order(-Z43_neut), Ticker]
  ord44 <- snap_dt[order(-Z44_neut), Ticker]
  sleeve_A <- head(ord43, k_per)
  sleeve_B <- head(setdiff(ord44, sleeve_A), k_per)
  list(A = sleeve_A, B = sleeve_B)
}

sig_list <- ic_wf$sig_date
alpha_rows <- list()
for (sd in as.character(sig_list)) {
  snap <- panel_t1[sig_date == as.Date(sd)]
  if (nrow(snap) < 30) next
  slv <- build_sleeves(snap, 10)
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
  alpha_rows[[sd]] <- arow
}
alpha_t1 <- rbindlist(alpha_rows, fill = TRUE)

# Portfolio EW ret + BM next
bm_ts <- raw[, .(BM_Ret = first(BM_Ret)), by = Date]
setorder(bm_ts, Date)
port_t1 <- alpha_t1[, .(ret = mean(fwd_1m, na.rm = TRUE), N = .N), by = sig_date]
bm_next_v <- numeric(nrow(port_t1))
for (i in seq_len(nrow(port_t1))) {
  sd <- port_t1$sig_date[i]
  ym_next <- format(seq(sd, by = "1 month", length.out = 2)[2], "%Y%m")
  dn <- bm_ts$Date[format(bm_ts$Date, "%Y%m") == ym_next]
  if (length(dn) == 0) { bm_next_v[i] <- NA; next }
  bs <- bm_ts[Date %in% dn, BM_Ret]
  bm_next_v[i] <- prod(1 + bs, na.rm = TRUE) - 1
}
port_t1[, BM_next_1m := bm_next_v]
port_t1[, ER := ret - BM_next_1m]

er <- port_t1$ER[!is.na(port_t1$ER)]
m <- mean(er); s <- sd(er); sr_ann <- m/s*sqrt(12)
nwer <- nw_tstat(er)
cat(sprintf("\n  Multi-sleeve (t-1 univ) portfolio: mean_ER=%+.4f sd=%.4f SR_ann=%+.2f t_nw=%+.2f N=%d\n",
            m, s, sr_ann, nwer$t, length(er)))

# ---- R3. Quarantine fwd_1m (write alpha_scores.parquet WITHOUT fwd_1m) ----
cat("\n[Codex R3] Quarantine fwd_1m — rewrite alpha_scores_clean.parquet\n")
panel_score <- merge(panel_t1, ic_wf[, .(sig_date, w_43_wf_nneg, w_44_wf_nneg)],
                     by = "sig_date", all.x = TRUE)
panel_score <- panel_score[!is.na(w_43_wf_nneg)]
panel_score[, alpha_score := w_43_wf_nneg * Z43_neut + w_44_wf_nneg * Z44_neut]
panel_score[, alpha_score_z := (alpha_score - mean(alpha_score, na.rm = TRUE)) /
                                sd(alpha_score, na.rm = TRUE), by = sig_date]

out_score <- panel_score[, .(sig_date, Ticker, Sector_Lv2,
                              Z43_neut, Z44_neut,
                              alpha_score = round(alpha_score, 6),
                              alpha_score_z = round(alpha_score_z, 6))]
write_parquet(out_score, file.path(OUT_DIR, "alpha_scores_clean.parquet"))
cat("  alpha_scores_clean.parquet (no fwd_1m): rows=", nrow(out_score), "\n")

# Separate validation table (fwd_1m + alpha_score) for audit only
out_valid <- panel_score[, .(sig_date, Ticker, Z43_neut, Z44_neut,
                              alpha_score_z = round(alpha_score_z, 6),
                              fwd_1m = round(fwd_1m, 6))]
write_parquet(out_valid, file.path(OUT_DIR, "alpha_validation_panel.parquet"))
cat("  alpha_validation_panel.parquet (fwd_1m quarantined): rows=", nrow(out_valid), "\n")

# Recompute graduation gates under revised setup
snap_2023 <- panel_score[sig_date == max(panel_score$sig_date)]
last_w <- ic_wf[sig_date == max(sig_date)]
w43_final <- last_w$w_43_wf_nneg
w44_final <- last_w$w_44_wf_nneg
cat(sprintf("\n  Final WF weights (nneg, latest pre-snap): w43=%+.4f w44=%+.4f\n", w43_final, w44_final))

# Build alpha_vector for emit (snapshot 2023-11-30)
snap_2023[, alpha_score_z2 := (alpha_score - mean(alpha_score)) / sd(alpha_score)]
alpha_vector <- setNames(round(snap_2023$alpha_score_z2, 4), snap_2023$Ticker)
alpha_vector <- alpha_vector[order(-alpha_vector)]

# confidence_vector
snap_2023[, conf := pmin(0.75, pmax(0.45, 0.55 + 0.05 * abs(alpha_score_z2)))]
confidence_vector <- setNames(round(snap_2023$conf, 3), snap_2023$Ticker)
confidence_vector <- confidence_vector[order(-confidence_vector)]

# multi_sleeve top 20 at 2023-11-30
ord43_snap <- snap_2023[order(-Z43_neut), Ticker]
ord44_snap <- snap_2023[order(-Z44_neut), Ticker]
sleeve_A_final <- head(ord43_snap, 10)
sleeve_B_final <- head(setdiff(ord44_snap, sleeve_A_final), 10)

# Save artifacts for emit
saveRDS(panel_t1, file.path(OUT_DIR, "panel_t1.rds"))
saveRDS(ic_wf,    file.path(OUT_DIR, "ic_wf_t1.rds"))
saveRDS(alpha_t1, file.path(OUT_DIR, "alpha_t1.rds"))
saveRDS(port_t1,  file.path(OUT_DIR, "port_t1.rds"))

saveRDS(list(
  alpha_vector = alpha_vector,
  confidence_vector = confidence_vector,
  sleeve_A = sleeve_A_final,
  sleeve_B = sleeve_B_final,
  w43 = w43_final, w44 = w44_final,
  neg_43_count = neg_43, neg_44_count = neg_44,
  harvey_pass = harvey_pass_t1,
  harvey_threshold = harvey_threshold,
  composite_icir_nneg = ir,
  composite_t_nneg = nw$t,
  d43_icir_t1 = ir43_wf, d43_t_t1 = nw43$t,
  d44_icir_t1 = ir44_wf, d44_t_t1 = nw44$t,
  portfolio_mean_er = m, portfolio_sd = s,
  portfolio_sr_ann = sr_ann, portfolio_t_nw = nwer$t,
  portfolio_n = length(er),
  uni_size_t1 = list(min = min(uni_size_t1), median = median(uni_size_t1), max = max(uni_size_t1))
), file.path(OUT_DIR, "emit_payload_t1.rds"))

# ---- R5. AX-001 salvage: report constraint (no Core MDD available in this WT) ----
cat("\n[Codex R5] AX-001 v2 salvage gap documentation\n")
cat("  Bad regime IC (D43=+0.0442 / D44=+0.0508) was computed on 11 bad months only (BM_next < -5%).\n")
cat("  No realized crisis portfolio alpha or Core-relative MDD mitigation computed in Alpha stage.\n")
cat("  Documented as NON_SUFFICIENT for AX-001 v2 sustained salvage claim.\n")

cat("\n[Step 6 DONE] elapsed:", round(as.numeric(Sys.time() - t0, units = "secs"), 1), "s\n")
