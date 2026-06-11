# =============================================================================
# Lens 3 adversarial verification — subperiod robustness of value-sleeve blend
# Reconstructs blend EXACTLY as run_blend.R blend_one() (Return.portfolio +
# BOP/EOP sleeve-rebal turnover x 15bps), then slices subperiods.
# PerformanceAnalytics standard functions only (SharpeRatio.annualized,
# maxDrawdown, Return.cumulative, table.Drawdowns, StdDev.annualized).
# =============================================================================
suppressPackageStartupMessages({
  library(data.table); library(xts); library(PerformanceAnalytics); library(jsonlite)
})
PROJECT_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
OUTDIR <- file.path(PROJECT_ROOT, "04_Research/composition_search/value_sleeve_combination")

M <- readRDS(file.path(OUTDIR, "aligned_series.rds"))
setDT(M); setorder(M, realized_ym)
cat(sprintf("aligned_series: n=%d  range %s..%s  cols=%s\n",
            nrow(M), M$realized_ym[1], M$realized_ym[nrow(M)], paste(names(M), collapse=",")))

dates <- as.Date(paste0(M$realized_ym, "-01"))
ret_mat <- xts(cbind(book = M$book_ret, value = M$value_ret), order.by = dates)

BLEND_REBAL_BPS <- 15
blend_net <- function(wv) {
  rp <- Return.portfolio(ret_mat, weights = c(book = 1 - wv, value = wv),
                         rebalance_on = "months", verbose = TRUE)
  gross <- rp$returns
  bop <- rp$BOP.Weight; eop <- rp$EOP.Weight
  to <- rep(0, nrow(bop))
  for (i in 2:nrow(bop)) to[i] <- sum(abs(as.numeric(bop[i,]) - as.numeric(eop[i-1,])))
  gross - xts(to * BLEND_REBAL_BPS / 1e4, order.by = index(gross))
}

book  <- ret_mat[, "book"]
value <- ret_mat[, "value"]
b10 <- blend_net(0.10)
b20 <- blend_net(0.20)

# ---- 0. full-sample reproduction anchor (must match forge results.csv) ----
cat(sprintf("\n[ANCHOR full 248m] book SR=%.4f MDD=%.4f | w10 SR=%.4f MDD=%.4f | w20 SR=%.4f MDD=%.4f | cor(v,b)=%.4f\n",
  as.numeric(SharpeRatio.annualized(book, Rf=0)), as.numeric(maxDrawdown(book)),
  as.numeric(SharpeRatio.annualized(b10,  Rf=0)), as.numeric(maxDrawdown(b10)),
  as.numeric(SharpeRatio.annualized(b20,  Rf=0)), as.numeric(maxDrawdown(b20)),
  cor(M$value_ret, M$book_ret)))

# ---- 1. subperiod table ----
slice_stats <- function(x, from, to) {
  s <- x[paste0(from, "/", to)]
  list(n = nrow(s),
       SR  = as.numeric(SharpeRatio.annualized(s, Rf = 0)),
       MDD = as.numeric(maxDrawdown(s)),
       CUM = as.numeric(Return.cumulative(s)),
       VOL = as.numeric(StdDev.annualized(s)))
}
periods <- list(
  OOS_2017p = c("2017-01", "2026-04"),
  OOS_2020p = c("2020-01", "2026-04"),
  IS_2005_2016 = c("2005-09", "2016-12"))

sub_out <- list()
cat("\n===== SUBPERIOD TABLE =====\n")
for (nm in names(periods)) {
  p <- periods[[nm]]
  sb  <- slice_stats(book,  p[1], p[2])
  s10 <- slice_stats(b10,   p[1], p[2])
  s20 <- slice_stats(b20,   p[1], p[2])
  sv  <- slice_stats(value, p[1], p[2])
  sub_out[[nm]] <- list(n = sb$n,
    book = sb[c("SR","MDD","VOL")], w10 = s10[c("SR","MDD")], w20 = s20[c("SR","MDD")],
    value_standalone_SR = sv$SR, value_cum = sv$CUM,
    dSR_w10 = s10$SR - sb$SR, dMDD_w10 = s10$MDD - sb$MDD,
    dSR_w20 = s20$SR - sb$SR, dMDD_w20 = s20$MDD - sb$MDD,
    dVOL_w20 = s20$VOL - sb$VOL)
  cat(sprintf("[%s %s..%s n=%d]\n  book : SR=%.4f MDD=%.4f VOL=%.4f\n  w10  : SR=%.4f (dSR%+.4f) MDD=%.4f (dMDD%+.4f)\n  w20  : SR=%.4f (dSR%+.4f) MDD=%.4f (dMDD%+.4f) VOL=%.4f\n  value: SR=%.4f cum=%+.4f\n",
    nm, p[1], p[2], sb$n, sb$SR, sb$MDD, sb$VOL,
    s10$SR, s10$SR-sb$SR, s10$MDD, s10$MDD-sb$MDD,
    s20$SR, s20$SR-sb$SR, s20$MDD, s20$MDD-sb$MDD, s20$VOL,
    sv$SR, sv$CUM))
}

# ---- 2. drawdown tables (where does MDD relief come from?) ----
cat("\n===== book top-5 drawdowns =====\n")
print(table.Drawdowns(book, top = 5, digits = 4))
cat("\n===== blend w20 top-5 drawdowns =====\n")
print(table.Drawdowns(b20, top = 5, digits = 4))

# ---- 3. crisis windows ----
crises <- list(GFC_2007_11_2009_03 = c("2007-11","2009-03"),
               COVID_2020_01_04    = c("2020-01","2020-04"),
               Y2022_full          = c("2022-01","2022-12"))
cris_out <- list()
cat("\n===== CRISIS WINDOWS =====\n")
for (nm in names(crises)) {
  p <- crises[[nm]]
  sb  <- slice_stats(book,  p[1], p[2])
  s20 <- slice_stats(b20,   p[1], p[2])
  sv  <- slice_stats(value, p[1], p[2])
  cris_out[[nm]] <- list(book_cum = sb$CUM, w20_cum = s20$CUM, value_cum = sv$CUM,
                         book_mdd = sb$MDD, w20_mdd = s20$MDD, value_mdd = sv$MDD)
  cat(sprintf("[%s] cum: book=%+.4f w20=%+.4f value=%+.4f | inner MDD: book=%.4f w20=%.4f value=%.4f\n",
    nm, sb$CUM, s20$CUM, sv$CUM, sb$MDD, s20$MDD, sv$MDD))
}

# calm vs crisis vol split (was MDD relief crisis defense or calm-vol shrink?)
crisis_ym <- c(format(seq(as.Date("2007-11-01"), as.Date("2009-03-01"), by="month"), "%Y-%m"),
               format(seq(as.Date("2020-01-01"), as.Date("2020-04-01"), by="month"), "%Y-%m"),
               format(seq(as.Date("2022-01-01"), as.Date("2022-12-01"), by="month"), "%Y-%m"))
is_crisis <- format(index(book), "%Y-%m") %in% crisis_ym
cat(sprintf("\n[calm/crisis split] crisis n=%d calm n=%d\n", sum(is_crisis), sum(!is_crisis)))
cat(sprintf("  crisis mean monthly: book=%+.4f w20=%+.4f value=%+.4f\n",
    mean(book[is_crisis]), mean(b20[is_crisis]), mean(value[is_crisis])))
cat(sprintf("  calm   mean monthly: book=%+.4f w20=%+.4f value=%+.4f\n",
    mean(book[!is_crisis]), mean(b20[!is_crisis]), mean(value[!is_crisis])))
cat(sprintf("  crisis vol (ann): book=%.4f w20=%.4f | calm vol (ann): book=%.4f w20=%.4f\n",
    as.numeric(StdDev.annualized(book[is_crisis])), as.numeric(StdDev.annualized(b20[is_crisis])),
    as.numeric(StdDev.annualized(book[!is_crisis])), as.numeric(StdDev.annualized(b20[!is_crisis]))))

# ---- 4. rolling 36m SR crossover ----
roll_sr <- function(x, w = 36L) {
  n <- nrow(x); out <- rep(NA_real_, n)
  for (i in w:n) out[i] <- as.numeric(SharpeRatio.annualized(x[(i-w+1):i, ], Rf = 0))
  xts(out, order.by = index(x))
}
rb  <- roll_sr(book)
r20 <- roll_sr(b20)
dd_sr <- na.omit(merge(r20, rb)); colnames(dd_sr) <- c("blend","book")
adv <- as.numeric(dd_sr$blend) - as.numeric(dd_sr$book)
sg <- sign(adv)
flips <- which(sg[-1] != sg[-length(sg)] & sg[-1] != 0 & sg[-length(sg)] != 0) + 1
cat(sprintf("\n===== ROLLING 36m SR (w20 vs book) =====\nwindows n=%d | blend>book in %d (%.1f%%) | mean adv=%.4f\n",
    length(adv), sum(adv > 0), 100*mean(adv > 0), mean(adv)))
if (length(flips) > 0) {
  cat("crossover dates (sign flips of blendSR-bookSR):\n")
  for (i in flips) cat(sprintf("  %s : %+.4f -> %+.4f\n",
      format(index(dd_sr)[i], "%Y-%m"), adv[i-1], adv[i]))
} else cat("no crossovers — one side dominates all windows\n")
last24 <- tail(adv, 24)
cat(sprintf("last-24 windows: blend>book in %d/24, mean adv=%+.4f | latest window (%s) adv=%+.4f\n",
    sum(last24 > 0), mean(last24), format(tail(index(dd_sr),1), "%Y-%m"), tail(adv,1)))

# ---- emit json ----
out <- list(anchor = list(
              book_SR = as.numeric(SharpeRatio.annualized(book, Rf=0)),
              w20_SR  = as.numeric(SharpeRatio.annualized(b20, Rf=0)),
              cor_vb  = cor(M$value_ret, M$book_ret)),
            subperiods = sub_out, crises = cris_out,
            rolling36 = list(n = length(adv), pct_blend_gt_book = mean(adv > 0),
                             mean_adv = mean(adv), n_flips = length(flips),
                             flip_dates = format(index(dd_sr)[flips], "%Y-%m"),
                             last24_share = mean(last24 > 0), last24_mean = mean(last24)))
write_json(out, file.path(OUTDIR, "_verify_lens3/lens3_results.json"),
           pretty = TRUE, auto_unbox = TRUE, digits = 6)
cat("\nDONE\n")
