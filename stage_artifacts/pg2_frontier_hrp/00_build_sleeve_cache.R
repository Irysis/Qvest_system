## ============================================================================
## PG2 Frontier-HRP measurement — Part 0: build shared sleeve cache
## STR_1715 sleeve = top-20 by score_eff (panel factor_panel_7f). Identical
## selection each month across ALL weighting methods; methods vary ONLY weights.
## PIT: signal at panel Date t (score_eff), forward realized Ret_1m (month t+1).
## Trailing 36m cov from monthly RAWDATA returns realized THROUGH t (PIT-valid).
## Overlay m4×β_R05 + pinned KOSPI200 matched by realized month (t+1).
## ============================================================================
suppressPackageStartupMessages({library(data.table); library(arrow); library(lubridate)})
setDTthreads(1)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
SCR  <- "C:/Users/99922/AppData/Local/Temp/claude/C--Users-99922-OneDrive-Quant-Module-Moltbot/414b5ddb-bdea-41dd-a7b1-54de22437ae3/scratchpad"
OUT  <- file.path(ROOT, "stage_artifacts/pg2_frontier_hrp")
dir.create(OUT, showWarnings = FALSE, recursive = TRUE)
TOP_N <- 20L; LIQ <- 2e8

## --- panel: selection universe + score_eff + regime + forward return ---------
pan <- as.data.table(read_parquet(file.path(ROOT,"04_Research/pg2_forensics/intermediate/factor_panel_7f.parquet")))
pan[, Date := as.Date(Date)]; pan[, ym := format(Date,"%Y-%m")]

## --- monthly returns + adv (built by build_monthly.R) ------------------------
mon  <- readRDS(file.path(SCR,"monthly_returns.rds"))
mret <- mon$mret                       # Ticker, ym, mret, ndays, adv
## wide monthly return matrix (rows=ym asc, cols=Ticker) for trailing cov
yms  <- sort(unique(mret$ym))
RMm  <- dcast(mret, ym ~ Ticker, value.var = "mret")
setorder(RMm, ym); ymrows <- RMm$ym; RMm[, ym := NULL]
RMm  <- as.matrix(RMm); rownames(RMm) <- ymrows
## adv wide (contemporaneous month adv used as liquidity proxy; prod uses t-1 —
## we require adv at signal month t which is known at t end; conservative)
advw <- dcast(mret, ym ~ Ticker, value.var = "adv")
setorder(advw, ym); advrows <- advw$ym; advw[, ym := NULL]
advw <- as.matrix(advw); rownames(advw) <- advrows

## --- overlay panel (m4, β_R05) by realized month -----------------------------
p5 <- fread(file.path(ROOT,"05_Production/2.Factor_Model/2-2.STR_1715_FaithTrend_on_M4_R05_overlay_PG2/04_backtest_results/period_returns_layer5_faith.csv"))
p5[, realized_ym := as.character(realized_ym)]
p5[, anchor_date := as.Date(anchor_date)]
setorder(p5, realized_ym)
p5[, dR05 := abs(beta_R05 - shift(beta_R05, 1, fill = 1.0))]   # clean β-rotation cost base

## --- pinned benchmark (KOSPI200 IKS200), cumulated over ANCHOR windows -------
## Authoritative construction matching book_state incumbent IR 1.416 (forge_w2):
## benchmark per realized month = cumulative pinned KOSPI200 over
## (anchor_date[i-1], anchor_date[i]]. Verified: incumbent ret_orig×overlay
## anchor-bm active IR = 1.4055 ≈ 1.416.
suppressPackageStartupMessages({library(xts); library(PerformanceAnalytics)})
bmp <- as.data.table(read_parquet(file.path(ROOT,"stage_artifacts/pg2_offense_overlay/benchmark_pinned_20260702.parquet")))
bmp[, Date := as.Date(Date)]; bmp <- bmp[is.finite(BM_Ret)]; setorder(bmp, Date)
bm_x <- xts(bmp$BM_Ret, order.by = bmp$Date)
a <- p5$anchor_date; bmw <- rep(NA_real_, nrow(p5))
for (i in 2:nrow(p5)) {
  seg <- bm_x[index(bm_x) > a[i-1] & index(bm_x) <= a[i]]
  if (nrow(seg) > 0) bmw[i] <- as.numeric(Return.cumulative(seg))
}
bmw[1] <- 0
p5[, bm_anchor := bmw]

## --- build per-month sleeve selection ---------------------------------------
dts <- sort(unique(pan$Date))
sel_list <- vector("list", length(dts))
for (i in seq_along(dts)) {
  d <- dts[i]; ymt <- format(d, "%Y-%m")
  cur <- pan[Date == d & is.finite(score_eff), .(Ticker, score_eff, Ret_1m, regime_state)]
  if (nrow(cur) < TOP_N) next
  ## liquidity filter using contemporaneous adv (known at t)
  if (ymt %in% rownames(advw)) {
    av <- advw[ymt, ]
    liq_ok <- names(av)[is.finite(av) & av >= LIQ]
    cur_liq <- cur[Ticker %in% liq_ok]
    if (nrow(cur_liq) >= TOP_N) cur <- cur_liq   # else keep unfiltered (rare early years)
  }
  setorder(cur, -score_eff)
  sel <- cur[1:TOP_N]
  sel[, Date := d]; sel[, ym := ymt]
  ## realized month = t+1
  rym <- format(as.Date(paste0(ymt,"-01")) %m+% months(1), "%Y-%m")
  sel[, realized_ym := rym]
  sel_list[[i]] <- sel
}
SEL <- rbindlist(sel_list)
cat(sprintf("[cache] sleeve months=%d  ym %s..%s\n",
            length(unique(SEL$Date)), min(SEL$ym), max(SEL$ym)))

## --- benchmark axis keyed by realized_ym (anchor-window cumulative) -----------
bm_m <- p5[, .(realized_ym, bm_ret = bm_anchor)]

## --- incumbent book series (authoritative): ret_orig × overlay − β-cost ------
IR <- function(x){ x <- x[is.finite(x)]; mean(x)/stats::sd(x)*sqrt(12) }
inc <- copy(p5)
inc[, inc_ret := beta_R05 * m4 * ret_orig - dR05 * 0.0015]
inc <- merge(inc[, .(realized_ym, anchor_date, inc_ret, beta_R05, m4, dR05, regime)],
             bm_m, by = "realized_ym"); setorder(inc, realized_ym)
inc[, inc_active := inc_ret - bm_ret]
cat(sprintf("[cache] incumbent book IR(active) = %.4f  [book_state 1.416]\n", IR(inc$inc_active)))

saveRDS(list(SEL = SEL, RMm = RMm, advw = advw, p5 = p5, bm_m = bm_m,
             inc = inc, dts = dts, TOP_N = TOP_N),
        file.path(SCR, "frontier_sleeve_cache.rds"))
cat("[cache] saved frontier_sleeve_cache.rds\n")
cat(sprintf("  RMm dim %d x %d (ym %s..%s)\n", nrow(RMm), ncol(RMm),
            rownames(RMm)[1], rownames(RMm)[nrow(RMm)]))
cat(sprintf("  overlay realized_ym %s..%s (n=%d)\n", min(p5$realized_ym), max(p5$realized_ym), nrow(p5)))
cat(sprintf("  bm_m realized months n=%d\n", nrow(bm_m)))
