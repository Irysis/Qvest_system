# R16 — microstructure factor build (Phase 1 daily->month-end scores + Phase 2 panels)
# PIT: signal at month-end d0 uses daily data through d0; forward return d0->d1.
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
suppressPackageStartupMessages({library(data.table); library(arrow); library(jsonlite)})
data.table::setDTthreads(1L)
try(arrow::set_io_thread_count(2L), silent = TRUE)
STAGE <- "stage_artifacts/r16_microstructure"
t0 <- Sys.time()

cat("[1] load RAWDATA (col_select)\n")
cols <- c("Date","Ticker","Close","Vol","Size","Ret","K200","KQ150")
rd <- as.data.table(read_parquet(".cache/RAWDATA.parquet", col_select = all_of(cols)))
rd[, Date := as.Date(Date)]
setorder(rd, Ticker, Date)
cat(sprintf("    rows=%d tickers=%d dates=%s..%s\n", nrow(rd), uniqueN(rd$Ticker),
            as.character(min(rd$Date)), as.character(max(rd$Date))))

# derived daily series
rd[, TV := Close * Vol]                                   # 거래대금 (KRW)
rd[, turnover := fifelse(Size > 0, TV / Size, NA_real_)]  # 회전율 proxy
rd[, aret := abs(Ret)]
rd[, amihud := fifelse(TV > 0, aret / TV, NA_real_)]
rd[, ltv := fifelse(TV > 0, log(TV), NA_real_)]
rd[, ltovr := fifelse(turnover > 0, log(turnover), NA_real_)]

frm <- function(x, n) frollmean(x, n, na.rm = FALSE)     # NA-strict rolling (PIT-clean)

cat("[2] VSHK_P (63d lag-1 AR of log-turnover)\n")
rd[, x := ltovr]
rd[, x1 := shift(x, 1L), by = Ticker]
rd[, xx1 := x * x1]; rd[, x2 := x * x]
rd[, mx  := frm(x, 63),  by = Ticker]
rd[, mx1 := frm(x1, 63), by = Ticker]
rd[, mxx1:= frm(xx1,63), by = Ticker]
rd[, mx2 := frm(x2, 63), by = Ticker]
rd[, VSHK_P := { v <- mx2 - mx*mx; fifelse(v > 0, (mxx1 - mx*mx1)/v, NA_real_) }]

cat("[3] TOD_DT (log MA5/MA252 turnover)\n")
rd[, ma5   := frm(turnover, 5),   by = Ticker]
rd[, ma252 := frm(turnover, 252), by = Ticker]
rd[, TOD_DT := fifelse(ma5 > 0 & ma252 > 0, log(ma5/ma252), NA_real_)]

cat("[4] AMT_ASY (60d up/down amount asymmetry)\n")
rd[, up_tv := fifelse(!is.na(Ret) & Ret > 0 & !is.na(TV), TV, 0)]
rd[, dn_tv := fifelse(!is.na(Ret) & Ret < 0 & !is.na(TV), TV, 0)]
rd[, sup := frm(up_tv, 60) * 60, by = Ticker]
rd[, sdn := frm(dn_tv, 60) * 60, by = Ticker]
rd[, AMT_ASY := log((sup + 1) / (sdn + 1))]

cat("[5] VPRC_CORR (corr60 - corr250 of |Ret| vs log TV)\n")
rd[, a := aret]; rd[, b := ltv]; rd[, ab := a*b]; rd[, a2 := a*a]; rd[, b2 := b*b]
corr_w <- function(dt, n) {
  ma <- frm(dt$a, n); mb <- frm(dt$b, n); mab <- frm(dt$ab, n)
  ma2 <- frm(dt$a2, n); mb2 <- frm(dt$b2, n)
  va <- ma2 - ma*ma; vb <- mb2 - mb*mb
  fifelse(va > 0 & vb > 0, (mab - ma*mb)/sqrt(va*vb), NA_real_)
}
rd[, c60  := corr_w(.SD, 60),  by = Ticker, .SDcols = c("a","b","ab","a2","b2")]
rd[, c250 := corr_w(.SD, 250), by = Ticker, .SDcols = c("a","b","ab","a2","b2")]
rd[, VPRC_CORR := c60 - c250]

cat("[6] ILLIQ_VOL (60d CV of daily amihud)\n")
rd[, m_ai  := frm(amihud, 60),        by = Ticker]
rd[, m_ai2 := frm(amihud*amihud, 60), by = Ticker]
rd[, ILLIQ_VOL := { s <- m_ai2 - m_ai*m_ai; fifelse(s > 0 & m_ai > 0, sqrt(s)/m_ai, NA_real_) }]

cat("[7] 20d ADV (liq filter)\n")
rd[, adv20 := frm(TV, 20), by = Ticker]

# sig_dates = month-end trading days
rd[, ym := format(Date, "%Y%m")]
me <- rd[, .(Date = max(Date)), by = ym][order(Date)]
sig_dates <- me$Date
sig_dates <- sig_dates[sig_dates >= as.Date("2006-01-01")]   # warmup (252d)
cat(sprintf("    sig_dates=%d (%s..%s)\n", length(sig_dates),
            as.character(min(sig_dates)), as.character(max(sig_dates))))

FACS <- c("VSHK_P","TOD_DT","AMT_ASY","VPRC_CORR","ILLIQ_VOL")
SIGN <- c(VSHK_P = 1, TOD_DT = -1, AMT_ASY = 1, VPRC_CORR = 1, ILLIQ_VOL = 1)

# month-end snapshot (universe = K200|KQ150 at d0)
snap <- rd[Date %in% sig_dates &
             ((!is.na(K200) & K200 == 1) | (!is.na(KQ150) & KQ150 == 1)),
           c("Date","Ticker","Size","adv20", FACS), with = FALSE]
cat(sprintf("[8] month-end universe snapshot rows=%d\n", nrow(snap)))

# long scores (sign-aligned: high score = long candidate)
scores_long <- rbindlist(lapply(FACS, function(f) {
  d <- snap[is.finite(get(f)), .(Date, Ticker, factor = f, raw = get(f))]
  d[, score := SIGN[[f]] * raw]
  d
}))
cat("[9] coverage per factor (median tickers/month):\n")
cov_tbl <- scores_long[, .(n_rows = .N, n_months = uniqueN(Date),
                           med_tk = as.integer(median(.SD[, .N, by = Date]$N))),
                       by = factor]
print(cov_tbl)

# Phase 2: forward returns + cap-w bench (blessed helper) + size + liq
source("02_Infrastructure/ramp/factor_validation.R")
cat("[10] build_monthly_forward_returns (cap-w K200|KQ150 bench)\n")
fwd <- build_monthly_forward_returns(rd, sig_dates)
returns_dt <- fwd$returns_dt
bench_dt   <- fwd$bench_dt
size_dt    <- snap[, .(Date, Ticker, Size)]
liq_dt     <- snap[is.finite(adv20), .(Date, Ticker, adv = adv20)]
cat(sprintf("    returns=%d bench=%d size=%d liq=%d\n",
            nrow(returns_dt), nrow(bench_dt), nrow(size_dt), nrow(liq_dt)))

write_parquet(scores_long, file.path(STAGE, "scores_long.parquet"))
write_parquet(returns_dt,  file.path(STAGE, "returns_dt.parquet"))
write_parquet(bench_dt,    file.path(STAGE, "bench_dt.parquet"))
write_parquet(size_dt,     file.path(STAGE, "size_dt.parquet"))
write_parquet(liq_dt,      file.path(STAGE, "liq_dt.parquet"))
write_json(list(built_at = as.character(Sys.time()),
                sig_dates_n = length(sig_dates),
                sig_start = as.character(min(sig_dates)),
                sig_end = as.character(max(sig_dates)),
                coverage = cov_tbl, signs = as.list(SIGN),
                elapsed_s = round(as.numeric(difftime(Sys.time(), t0, units = "secs")), 1)),
           file.path(STAGE, "build_meta.json"), auto_unbox = TRUE, pretty = TRUE)
cat(sprintf("[DONE] build elapsed %.1fs\n", as.numeric(difftime(Sys.time(), t0, units="secs"))))
