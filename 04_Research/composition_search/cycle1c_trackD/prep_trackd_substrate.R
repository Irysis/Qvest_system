# =============================================================================
# prep_trackd_substrate.R — Track D (Cycle 1c) substrate + conditioning signals
#   Prereg: TRACKD_3SLEEVE_DYNAMIC_PREREG_v1 (FROZEN 2026-06-12)
#
# Builds (to intermediate/):
#   1. sleeve_monthly.csv      — S_core / S_def / S_val calendar-aligned monthly net
#   2. bench_monthly.csv       — KOSPI200/KQ150 BM monthly (Return.cumulative)
#   3. value_spread_z.csv      — V02_EP raw quintile-gap expanding z (T3 signal), t-1 ready
#   4. consensus_esbr_z.csv    — esbr market-mean 3m-MA expanding z (T4 signal), t-1 ready
#
# PIT/alignment:
#   - S_core/S_def: b1 panel score @ month-end(t) -> Ret_1m @ calendar month t+1.
#       r_idx = month_end(t+1) = TRUE calendar return month. (b1_step3 verbatim conv.)
#   - S_val: corrected rds realized_ym = TRUE calendar return month (run_blend L83-86).
#   - join key = calendar return month "%Y-%m".
#   - conditioning signals (value_spread, esbr): indexed at FORMATION month-end
#       (= the score/decision month). expanding z. consumed at t-1 in engine
#       (signal of formation month m applied to weights formed at m, returns at m+1
#        -> uses info <= m which is <= return-month-1, PIT-safe).
#   - C15: value spread uses load_month_value_raw() connector EXTENSION (mirrors
#       load_month_factors file-resolution + Coverage filter; exposes Raw_Value for
#       ONE factor only). NOT a raw-parquet bypass. Documented (probe_spread.R proved
#       Z_Score is sd=1 normalized => no timing info => Raw_Value required).
# =============================================================================
suppressPackageStartupMessages({
  library(data.table); library(arrow); library(xts); library(zoo)
  library(PerformanceAnalytics)
})
setDTthreads(2)

PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
TD_DIR  <- file.path(PROJECT_ROOT, "04_Research/composition_search/cycle1c_trackD")
INT_DIR <- file.path(TD_DIR, "intermediate")
dir.create(INT_DIR, showWarnings = FALSE, recursive = TRUE)

FDB_DIR <- file.path(PROJECT_ROOT, ".cache/factor_db")
CC_DIR  <- file.path(PROJECT_ROOT, ".cache/consensus")

month_end <- function(d) seq(as.Date(format(d, "%Y-%m-01")), by = "1 month", length.out = 2)[2] - 1L
ym_of <- function(d) format(as.Date(d), "%Y-%m")

# =============================================================================
# 1. Core / Defense sleeves from b1 panel
# =============================================================================
pan <- as.data.table(read_parquet(file.path(PROJECT_ROOT,
        "04_Research/pg2_forensics/intermediate/factor_panel_7f.parquet")))
pan[, Date := as.Date(Date)]
last_d <- max(pan$Date)
stopifnot(pan[Date < last_d, sum(is.na(Ret_1m))] == 0)   # mid-sample NA Ret must be 0
panB <- pan[Date < last_d]                                # drop last (all NA Ret)
panB[, w_idx := as.Date(vapply(Date, function(d) as.character(month_end(d)), character(1)))]
panB[, r_idx := as.Date(vapply(Date, function(d)
        as.character(month_end(seq(as.Date(d), by = "1 month", length.out = 2)[2])), character(1)))]
panB[is.na(Ret_1m), Ret_1m := 0]

core13 <- panB[!is.na(score_core_z),
               .SD[order(-score_core_z)][1:min(13, .N)], by = Date,
               .SDcols = c("Ticker","Ret_1m","w_idx","r_idx")]
def12  <- panB[!is.na(score_defense_z),
               .SD[order(-score_defense_z)][1:min(12, .N)], by = Date,
               .SDcols = c("Ticker","Ret_1m","w_idx","r_idx")]

# EW sleeve monthly net via Return.portfolio (NO hand synthesis).
# sleeve-internal turnover cost: per-name |dW| delta 15bps (v2.4-delta in weight space)
COMMISSION <- 0.0015
sleeve_series <- function(sel, n_keep) {
  sel <- copy(sel)
  sel[, w := 1 / .N, by = Date]
  tickers <- sort(unique(sel$Ticker))
  Rdt <- dcast(sel, r_idx ~ Ticker, value.var = "Ret_1m")
  Rxts <- xts(as.matrix(Rdt[, -1, with = FALSE]), order.by = Rdt$r_idx)
  Rxts[is.na(Rxts)] <- 0
  Wdt <- dcast(sel, w_idx ~ Ticker, value.var = "w", fill = 0)
  Wxts <- xts(as.matrix(Wdt[, -1, with = FALSE]), order.by = Wdt$w_idx)
  Wxts <- Wxts[, colnames(Rxts)]
  pf <- Return.portfolio(Rxts, weights = Wxts, verbose = TRUE)
  g <- pf$returns
  bop <- pf$BOP.Weight; eop <- pf$EOP.Weight
  nT <- nrow(g); traded <- numeric(nT)
  traded[1] <- sum(abs(as.numeric(bop[1, ])))
  if (nT > 1) for (i in 2:nT) traded[i] <- sum(abs(as.numeric(bop[i, ]) - as.numeric(eop[i-1, ])))
  net <- as.numeric(g) - traded * COMMISSION
  data.table(r_idx = as.Date(index(g)), ret_net = net, traded = traded)
}

core_s <- sleeve_series(core13, 13)[, .(ym = ym_of(r_idx), core_ret = ret_net)]
def_s  <- sleeve_series(def12, 12)[, .(ym = ym_of(r_idx), def_ret = ret_net)]
cat(sprintf("[1] core sleeve %d months %s..%s | def %d months %s..%s\n",
            nrow(core_s), core_s$ym[1], core_s$ym[nrow(core_s)],
            nrow(def_s), def_s$ym[1], def_s$ym[nrow(def_s)]))

# =============================================================================
# 2. Value sleeve (consume corrected rds; realized_ym = calendar month)
# =============================================================================
V <- as.data.table(readRDS(file.path(PROJECT_ROOT,
      "04_Research/composition_search/value_sleeve_combination/corrected/aligned_series_corrected.rds")))
val_s <- V[, .(ym = realized_ym, value_ret)]
cat(sprintf("[2] value sleeve %d months %s..%s\n", nrow(val_s), val_s$ym[1], val_s$ym[nrow(val_s)]))

# =============================================================================
# 3. Benchmark monthly (apply.monthly + Return.cumulative — standard fns)
# =============================================================================
bm <- as.data.table(read_parquet(file.path(PROJECT_ROOT, ".cache/benchmark.parquet")))
bm[, Date := as.Date(Date)]
bm_x <- xts(bm$BM_Ret, order.by = bm$Date)
bm_m <- apply.monthly(bm_x, PerformanceAnalytics::Return.cumulative)
bench_s <- data.table(ym = ym_of(as.Date(index(bm_m))), bm_ret = as.numeric(bm_m))
cat(sprintf("[3] bench %d months %s..%s\n", nrow(bench_s), bench_s$ym[1], bench_s$ym[nrow(bench_s)]))

# =============================================================================
# 4. Merge sleeves + bench on calendar ym
# =============================================================================
S <- Reduce(function(a, b) merge(a, b, by = "ym", all = FALSE),
            list(core_s, def_s, val_s, bench_s))
setorder(S, ym)
S <- S[!is.na(core_ret) & !is.na(def_ret) & !is.na(value_ret) & !is.na(bm_ret)]
S[, r_idx := as.Date(vapply(ym, function(y) as.character(month_end(as.Date(paste0(y, "-01")))), character(1)))]
# formation month = return month - 1 (decision month-end)
prev_me <- function(y) {
  d1 <- as.Date(paste0(y, "-01"))
  pm <- seq(d1, by = "-1 month", length.out = 2)[2]
  month_end(pm)
}
S[, f_idx := as.Date(vapply(ym, function(y) as.character(prev_me(y)), character(1)))]
fwrite(S, file.path(INT_DIR, "sleeve_monthly.csv"))
cat(sprintf("[4] MERGED sleeve panel: %d calendar months %s..%s\n", nrow(S), S$ym[1], S$ym[nrow(S)]))
cat(sprintf("    sleeve standalone (raw mean/sd*sqrt12): core_SR=%.3f def_SR=%.3f val_SR=%.3f\n",
            mean(S$core_ret)/sd(S$core_ret)*sqrt(12),
            mean(S$def_ret)/sd(S$def_ret)*sqrt(12),
            mean(S$value_ret)/sd(S$value_ret)*sqrt(12)))
cat(sprintf("    cor(core,val)=%.3f cor(def,val)=%.3f cor(core,def)=%.3f\n",
            cor(S$core_ret,S$value_ret), cor(S$def_ret,S$value_ret), cor(S$core_ret,S$def_ret)))

# =============================================================================
# 5. T3 value spread signal — V02_EP Raw_Value quintile gap, expanding z
#    indexed at FORMATION month-end (decision month). t-1 applied in engine.
#    C15-compliant connector extension: load_month_value_raw()
# =============================================================================
load_month_value_raw <- function(sig_date, factor = "V02_EP", coverage_min = 0.05) {
  sig_d <- as.Date(sig_date); ym_tag <- format(sig_d, "%Y%m")
  fpath <- file.path(FDB_DIR, paste0("factor_db_", ym_tag, ".parquet"))
  if (!file.exists(fpath)) {
    avail <- list.files(FDB_DIR, pattern = "^factor_db_\\d{6}\\.parquet$")
    ya <- sort(gsub("factor_db_(\\d{6})\\.parquet", "\\1", avail))
    closest <- max(ya[ya <= ym_tag]); if (is.na(closest)) return(NULL)
    fpath <- file.path(FDB_DIR, paste0("factor_db_", closest, ".parquet"))
  }
  dt <- as.data.table(read_parquet(fpath,
          col_select = c("Ticker","Factor_Name","Raw_Value","Z_Score","Coverage")))
  v <- dt[Factor_Name == factor & Coverage == TRUE & !is.na(Raw_Value)]
  if (nrow(v) < 30) return(NULL)
  v[, .(Ticker, Raw_Value)]
}

# formation months = S$f_idx (decision months). compute spread at each.
f_months <- sort(unique(S$f_idx))
spread_dt <- rbindlist(lapply(f_months, function(fd) {
  v <- load_month_value_raw(fd, "V02_EP")
  if (is.null(v)) return(data.table(f_idx = fd, spread = NA_real_))
  q <- quantile(v$Raw_Value, c(0.2, 0.8), na.rm = TRUE)
  data.table(f_idx = fd, spread = as.numeric(q[2] - q[1]))
}))
setorder(spread_dt, f_idx)
# expanding z (mean/sd of spread up to and including current month — PIT: spread
# at formation month fd uses only info <= fd; z normalization uses expanding history
# which is also <= fd). Min 12 obs before z is defined.
spread_dt[, mu := cumsum(ifelse(is.na(spread),0,spread)) / cumsum(!is.na(spread))]
sp_z <- rep(NA_real_, nrow(spread_dt))
sp <- spread_dt$spread
for (i in seq_len(nrow(spread_dt))) {
  hist <- sp[1:i]; hist <- hist[!is.na(hist)]
  if (length(hist) >= 12) {
    s <- sd(hist); sp_z[i] <- if (s > 0) (sp[i] - mean(hist)) / s else 0
  }
}
spread_dt[, spread_z := sp_z]
fwrite(spread_dt[, .(f_idx, spread, spread_z)], file.path(INT_DIR, "value_spread_z.csv"))
cat(sprintf("[5] value spread (V02_EP raw q80-q20) %d months | non-NA z: %d | range z [%.2f, %.2f]\n",
            nrow(spread_dt), sum(!is.na(spread_dt$spread_z)),
            min(spread_dt$spread_z, na.rm=TRUE), max(spread_dt$spread_z, na.rm=TRUE)))

# =============================================================================
# 6. T4 consensus momentum — esbr market mean 3m-MA expanding z
#    indexed at FORMATION month-end. t-1 in engine.
# =============================================================================
esbr <- as.data.table(read_parquet(file.path(CC_DIR, "esbr.parquet")))
esbr[, Date := as.Date(Date)]
esbr[, ym := format(Date, "%Y-%m")]
# month-end snapshot per ticker (last obs in month) then market mean
esbr_me <- esbr[!is.na(esbr), .SD[which.max(Date)], by = .(Ticker, ym), .SDcols = "esbr"]
mkt <- esbr_me[, .(esbr_mkt = mean(esbr, na.rm = TRUE), n = .N), by = ym]
setorder(mkt, ym)
mkt[, f_idx := as.Date(month_end(as.Date(paste0(ym, "-01")))), by = ym]
# 3m MA (trailing, includes current — current month-end is observable at formation)
mkt[, esbr_ma3 := frollmean(esbr_mkt, 3, align = "right")]
# expanding z of the 3m-MA (PIT: history <= current formation month)
xm <- mkt$esbr_ma3
ez <- rep(NA_real_, length(xm))
for (i in seq_along(xm)) {
  hist <- xm[1:i]; hist <- hist[!is.na(hist)]
  if (length(hist) >= 12) {
    s <- sd(hist); ez[i] <- if (s > 0) (xm[i] - mean(hist)) / s else 0
  }
}
mkt[, esbr_z := ez]
fwrite(mkt[, .(f_idx, ym, esbr_mkt, esbr_ma3, esbr_z, n)], file.path(INT_DIR, "consensus_esbr_z.csv"))
cat(sprintf("[6] esbr market %d months %s..%s | non-NA z: %d | range z [%.2f, %.2f]\n",
            nrow(mkt), mkt$ym[1], mkt$ym[nrow(mkt)], sum(!is.na(mkt$esbr_z)),
            min(mkt$esbr_z, na.rm=TRUE), max(mkt$esbr_z, na.rm=TRUE)))

cat("PREP_TRACKD_OK\n")
