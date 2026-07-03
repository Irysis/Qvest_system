# =============================================================================
# run_buyback_drift.R — C27 driver: canonical_screen + concentration + grid + ortho
# WT-D20260621_010. Real-computation ONLY (canonical_screen_bt). selection_type='chain'.
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite) })
setDTthreads(1); arrow::set_cpu_count(1L)
options(stringsAsFactors = FALSE)

WT <- "WT-D20260621_010"
OUT_STAGE <- file.path("stage_artifacts", paste0("WT_", gsub("WT-", "", WT)))
dir.create(OUT_STAGE, recursive = TRUE, showWarnings = FALSE)

# ---- load RAWDATA (PIT price/membership) ------------------------------------
cat("[run] loading RAWDATA...\n")
RAWDATA <- as.data.table(read_parquet(".cache/RAWDATA.parquet",
  col_select = c("Date","Ticker","Close","Vol","Size","Ret","K200","KQ150","BM_Ret")))
RAWDATA[, Date := as.Date(Date)]
# fix obvious Size glitches (>100x median jump): cap not needed for ranking; keep
setorder(RAWDATA, Ticker, Date)

# ---- forward Ret_1m (month-end t -> next month-end realized) -----------------
RAWDATA[, ym := format(Date, "%Y-%m")]
.MEND <- sort(RAWDATA[, .(Date = max(Date)), by = ym]$Date)
ME <- RAWDATA[Date %in% .MEND, .(Date, Ticker, Close, BM_Ret_me = BM_Ret)]
setorder(ME, Ticker, Date)
ME[, Close_next := shift(Close, -1L), by = Ticker]
ME[, Date_next  := shift(Date,  -1L), by = Ticker]
ME[, Ret_1m := Close_next / Close - 1]   # forward realized 1M (no same-month, C2)
returns_dt <- ME[is.finite(Ret_1m), .(Date, Ticker, Ret_1m)]

# benchmark: monthly BM return (compound daily within forward month)
# RAWDATA.BM_Ret is ~entirely NA -> use .cache/benchmark.parquet (clean daily KOSPI200 TR)
bm_daily <- as.data.table(read_parquet(".cache/benchmark.parquet"))[, .(Date = as.Date(Date), BM_Ret)]
bm_daily <- bm_daily[!is.na(BM_Ret)]
setorder(bm_daily, Date)
# monthly BM return = product over the month
bm_daily[, ym := format(Date, "%Y-%m")]
bm_m <- bm_daily[, .(BM_Ret = prod(1 + BM_Ret) - 1, Date = max(Date)), by = ym]
# align to month-end signal date: BM at month t = the realized BM over the FORWARD month
setorder(bm_m, Date)
bm_m[, BM_fwd := shift(BM_Ret, -1L)]   # forward-month BM (match forward Ret_1m)
bench_dt <- bm_m[is.finite(BM_fwd), .(Date, BM_Ret = BM_fwd)]

# liq table (t-1 ADV)
RAWDATA[, dollar_vol := Vol * Close]
RAWDATA[, adv20 := frollmean(dollar_vol, 20, align = "right"), by = Ticker]
RAWDATA[, adv20_l1 := shift(adv20, 1L), by = Ticker]
liq_dt <- RAWDATA[Date %in% .MEND, .(Date, Ticker, adv = adv20_l1)]

source("02_Infrastructure/contracts/backtest_result_contract.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")
stopifnot(exists("build_benchmark_compare"))

# ---- helper: run one config -> scores via fe_buyback_drift.R ----------------
run_config <- function(drift_m, half_life, method, intensity, top_n = 20L) {
  Sys.setenv(BB_DRIFT_M = as.character(drift_m), BB_HALF_LIFE = as.character(half_life),
             BB_METHOD = method, BB_INTENSITY = intensity)
  e <- new.env(); e$RAWDATA <- copy(RAWDATA)
  sys.source("02_Infrastructure/alpha_search/fe_buyback_drift.R", envir = e)
  S <- e$SCORES
  if (is.null(S) || nrow(S) == 0) return(NULL)
  res <- canonical_screen_bt(S[, .(Date, Ticker, score)], returns_dt, bench_dt,
                             top_n = top_n, cost_bps_oneway = 15,
                             liq_dt = liq_dt, liq_min = 2e8)
  list(scores = S, res = res)
}

# ===== PRIMARY config (DRIFT_M=12, HL=6, method=primary, intensity=ln, top_n=20) =====
cat("\n===== PRIMARY config =====\n")
prim <- run_config(12, 6, "primary", "ln", 20L)
stopifnot(!is.null(prim))
pr <- prim$res
cat(sprintf("PRIMARY: n_months=%d port_alpha_t_nw=%.3f net_sr=%.3f IR=%.3f turnover=%.2f mean_active=%.4f\n",
            pr$n_months, pr$portfolio_alpha_t_nw_lag3, pr$net_sr, pr$information_ratio,
            pr$turnover_annual, pr$mean_active_net))
SCORES_PRIM <- prim$scores
brc <- SCORES_PRIM[, .(n = uniqueN(Ticker)), by = Date]
cat(sprintf("cohort breadth median=%d min=%d max=%d over %d months (first=%s last=%s)\n",
            as.integer(median(brc$n)), min(brc$n), max(brc$n), nrow(brc),
            as.character(min(brc$Date)), as.character(max(brc$Date))))

# ---- rank-IC / ICIR / harvey-t (ADVISORY, full cross-section incl zeros) ----
# Build full cross-section: all liquid K200∪KQ150 names; non-event=0 score
fullx <- RAWDATA[Date %in% .MEND & (K200==1|KQ150==1), .(Date, Ticker, adv20_l1)]
fullx <- merge(fullx, SCORES_PRIM[, .(Date, Ticker, score)], by = c("Date","Ticker"), all.x = TRUE)
fullx[is.na(score), score := 0]
fullx <- merge(fullx, returns_dt, by = c("Date","Ticker"))
fullx <- fullx[is.na(adv20_l1) | adv20_l1 >= 2e8]
ic_by <- fullx[, .(ic = suppressWarnings(cor(score, Ret_1m, method = "spearman"))), by = Date]
ic_by <- ic_by[is.finite(ic)]
rank_ic <- mean(ic_by$ic); icir <- rank_ic / sd(ic_by$ic)
# NW harvey-t on IC series (lag 3)
.nwt <- function(x, lag = 3) {
  x <- x[is.finite(x)]; n <- length(x)
  if (n < lag + 2) return(NA_real_)
  m <- mean(x); e <- x - m
  g0 <- sum(e^2)/n; v <- g0
  for (l in 1:lag) { w <- 1 - l/(lag+1); gl <- sum(e[(l+1):n]*e[1:(n-l)])/n; v <- v + 2*w*gl }
  if (!is.finite(v) || v <= 0) return(NA_real_)
  m / sqrt(v/n)
}
harvey_t <- .nwt(ic_by$ic, 3)
cat(sprintf("ADVISORY rank-IC=%.4f ICIR=%.3f harvey_t(IC,NW3)=%.3f n_ic_months=%d\n",
            rank_ic, icir, harvey_t, nrow(ic_by)))

# ===== TOP-CONCENTRATION TEST (make-or-break vs C23 flat-top) =====
cat("\n===== CONCENTRATION TESTS =====\n")
# decile within event firms by score (per month), measure forward net-active vs BM
ev <- SCORES_PRIM[, .(Date, Ticker, score)]
ev <- merge(ev, returns_dt, by = c("Date","Ticker"))
ev <- merge(ev, bench_dt, by = "Date")
ev[, active := Ret_1m - BM_Ret]
# per-date decile (1..10) among event firms (rank-based, robust to small N)
ev[, dec := pmin(10L, pmax(1L, as.integer(ceiling(frank(score, ties.method="first")/.N * 10)))), by = Date]
dec_prof <- ev[, .(mean_active = mean(active), n = .N), by = dec][order(dec)]
cat("Decile profile (within-event, mean fwd net-active):\n"); print(dec_prof)

# D10 EW monthly series + NW t-stat (via canonical path on D10 only)
d10_series <- ev[dec == 10, .(active = mean(active)), by = Date]
d9_series  <- ev[dec == 9,  .(active = mean(active)), by = Date]
d10_t <- .nwt(d10_series$active, 3)
# D10-D9 gap series
gap <- merge(d10_series[, .(Date, a10 = active)], d9_series[, .(Date, a9 = active)], by = "Date")
gap[, g := a10 - a9]
gap_t <- .nwt(gap$g, 3)
cat(sprintf("D10 mean_active=%.4f NW-t=%.3f | D10-D9 gap=%.4f NW-t=%.3f\n",
            mean(d10_series$active), d10_t, mean(gap$g), gap_t))

# EVENT-vs-MARKET: ALL event firms EW (Ikenberry base case)
allev <- ev[, .(active = mean(active)), by = Date]
allev_t <- .nwt(allev$active, 3)
cat(sprintf("EVENT-vs-MARKET (all event firms EW): mean_active=%.4f NW-t=%.3f\n",
            mean(allev$active), allev_t))

# Size>median robustness (liquidity/microcap artifact guard)
ev2 <- merge(SCORES_PRIM[, .(Date, Ticker, score, Size_l1)], returns_dt, by=c("Date","Ticker"))
ev2 <- merge(ev2, bench_dt, by="Date"); ev2[, active := Ret_1m - BM_Ret]
ev2[, big := Size_l1 >= median(Size_l1, na.rm=TRUE), by = Date]
big_series <- ev2[big == TRUE, {
  n<-.N; setorder(.SD, -score); .(active = mean(active[seq_len(min(20L,n))]))
}, by = Date]
big_t <- .nwt(big_series$active, 3)
cat(sprintf("Size>median top20 EW: mean_active=%.4f NW-t=%.3f\n", mean(big_series$active), big_t))

# ===== oos_retention (anchored 55/65/75 median) + calmar =====
cat("\n===== OOS RETENTION + CALMAR =====\n")
ser <- pr$period_returns  # date, ret_net, benchmark_ret
ser <- as.data.table(ser); setorder(ser, date)
ser[, active := ret_net - benchmark_ret]
sr_full <- mean(ser$active)/sd(ser$active)*sqrt(12)
oos_split <- function(frac) {
  k <- floor(nrow(ser)*frac); is_<-ser[1:k]; oos_<-ser[(k+1):.N]
  sr_is <- mean(is_$active)/sd(is_$active)*sqrt(12)
  sr_oos<- mean(oos_$active)/sd(oos_$active)*sqrt(12)
  if (sr_is <= 0) NA_real_ else sr_oos/sr_is
}
oos_ret <- median(c(oos_split(.55), oos_split(.65), oos_split(.75)), na.rm=TRUE)
# calmar on net cumulative
nav <- cumprod(1 + ser$ret_net)
peak <- cummax(nav); dd <- nav/peak - 1; mdd <- abs(min(dd))
cagr <- nav[length(nav)]^(12/nrow(ser)) - 1
calmar <- if (mdd > 0) cagr/mdd else NA_real_
cat(sprintf("net SR_full=%.3f oos_retention(median)=%.3f | CAGR=%.3f MDD=%.3f calmar=%.3f\n",
            sr_full, oos_ret, cagr, mdd, calmar))

# subperiod era breakdown
ser[, era := fcase(date < as.Date("2018-01-01"), "pre2018",
                   date < as.Date("2023-01-01"), "2018-2022", default="2023+")]
era_tab <- ser[, .(n=.N, mean_active=mean(active), sr=mean(active)/sd(active)*sqrt(12)), by=era]
cat("Era breakdown:\n"); print(era_tab)

# ===== GRID robustness surface =====
cat("\n===== GRID (robustness surface) =====\n")
grid <- CJ(drift = c(6,9,12,18), hl = c(3,6,12,Inf), method = c("primary","agnostic","directonly"),
           intensity = c("ln","raw","sqrt","frank"), topn = c(15,20,25))
# subsample grid for runtime: keep primary axes + vary one at a time is too sparse;
# run a representative grid (drift x hl x topn at primary method/ln) + method/intensity sweep
grid_run <- rbind(
  CJ(drift=c(6,9,12,18), hl=c(3,6,12,Inf), method="primary", intensity="ln", topn=20L),
  CJ(drift=12, hl=6, method=c("primary","agnostic","directonly"), intensity=c("ln","raw","sqrt","frank"), topn=20L),
  CJ(drift=12, hl=6, method="primary", intensity="ln", topn=c(15L,25L))
)
grid_run <- unique(grid_run)
grid_res <- list()
for (i in seq_len(nrow(grid_run))) {
  g <- grid_run[i]
  rc <- tryCatch(run_config(g$drift, g$hl, g$method, g$intensity, as.integer(g$topn)),
                 error=function(e) NULL)
  pt <- if (!is.null(rc)) rc$res$portfolio_alpha_t_nw_lag3 else NA_real_
  sr <- if (!is.null(rc)) rc$res$net_sr else NA_real_
  grid_res[[i]] <- data.table(drift=g$drift, hl=g$hl, method=g$method,
                              intensity=g$intensity, topn=g$topn, port_t=pt, net_sr=sr)
  cat(sprintf("  grid %d/%d D=%g HL=%g %s/%s top%d -> port_t=%.2f sr=%.2f\n",
              i, nrow(grid_run), g$drift, g$hl, g$method, g$intensity, g$topn, pt, sr))
}
GRID <- rbindlist(grid_res)
pct_pos <- mean(GRID$port_t > 0, na.rm=TRUE)
prim_rank <- mean(GRID$port_t <= pr$portfolio_alpha_t_nw_lag3, na.rm=TRUE)
cat(sprintf("GRID: %.0f%% cells port_t>0; primary rank pct=%.2f; max port_t=%.2f\n",
            100*pct_pos, prim_rank, max(GRID$port_t, na.rm=TRUE)))

# ===== ORTHOGONALITY (active -BM basis, covariates via kr_factor_returns_v2) =====
cat("\n===== ORTHOGONALITY =====\n")
# Use available factor returns proxy: correlate the strategy's monthly active series
# vs kr_factor_returns_v2 factor return series (active-basis return correlation).
ortho <- tryCatch({
  fr <- as.data.table(read_parquet(".cache/kr_factor_returns_v2.parquet"))
  fr_date_col <- intersect(names(fr), c("Date","date"))[1]
  setnames(fr, fr_date_col, "date")
  fr[, date := as.Date(date)]
  s <- ser[, .(date, active)]
  m <- merge(s, fr, by="date")
  fac_cols <- setdiff(names(fr), "date")
  cors <- sapply(fac_cols, function(c) suppressWarnings(cor(m$active, m[[c]], use="complete.obs")))
  cors
}, error=function(e) { cat("ortho err:", conditionMessage(e), "\n"); NULL })
if (!is.null(ortho)) { cat("Active-return corr vs factor return series:\n"); print(round(ortho,3)) }

# ===== SAVE ARTIFACTS =====
write_parquet(SCORES_PRIM, file.path(OUT_STAGE, "alpha_scores.parquet"))
saveRDS(list(primary=pr, decile=dec_prof, grid=GRID, ortho=ortho,
             d10_t=d10_t, gap_t=gap_t, allev_t=allev_t, big_t=big_t,
             oos_ret=oos_ret, calmar=calmar, era=era_tab, brc=brc,
             rank_ic=rank_ic, icir=icir, harvey_t=harvey_t),
        file.path(OUT_STAGE, "buyback_drift_results.rds"))
cat("\n[run] artifacts saved to", OUT_STAGE, "\n")
cat("DONE\n")
