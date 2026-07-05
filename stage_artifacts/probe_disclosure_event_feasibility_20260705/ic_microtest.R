# Cheap-kill gate 2/3: directional IC sign + orthogonality proxy (no doc parse; occurrence signal)
suppressPackageStartupMessages({library(data.table); library(arrow)})
setDTthreads(1)
OUT <- "stage_artifacts/probe_disclosure_event_feasibility_20260705"

ev <- fread(file.path(OUT,"events_raw_2022_2024.csv"), colClasses=list(character=c("stock_code","corp_code","rcept_dt","rcept_no")))
ev[, stock_code := sprintf("%06d", as.integer(stock_code))]
ev[, Ticker := paste0("A", stock_code)]
ev[, rdate := as.Date(rcept_dt, format="%Y%m%d")]
ev[, YM := format(rdate, "%Y-%m")]
cat("events loaded:", nrow(ev), " supply:", sum(ev$is_supply), " earn:", sum(ev$is_earn), "\n")

# --- RAWDATA -> monthly panel (universe K200|KQ150, monthly last close, fwd ret, size, mom) ---
src <- ".cache/RAWDATA.parquet"; tmp <- file.path(tempdir(),"raw_ic.parquet")
file.copy(src,tmp,overwrite=TRUE)
raw <- as.data.table(read_parquet(tmp, col_select=c("Date","Ticker","K200","KQ150","Close","Size","Ret")))
raw[, Date := as.Date(Date)]
raw <- raw[Date >= as.Date("2021-06-01") & Date <= as.Date("2025-02-28")]
raw <- raw[(K200==1 | KQ150==1)]
raw[, YM := format(Date, "%Y-%m")]
setorder(raw, Ticker, Date)
# monthly last obs per ticker
mo <- raw[, .SD[.N], by=.(Ticker, YM), .SDcols=c("Date","Close","Size")]
setorder(mo, Ticker, YM)
# monthly return from close
mo[, mret := Close/shift(Close) - 1, by=Ticker]
# forward 1M return
mo[, fwd1 := shift(mret, -1), by=Ticker]
# 12M momentum (t-1): cumulative last 12 monthly returns excluding current
mo[, mom12 := shift(frollapply(mret, 12, function(x) prod(1+x, na.rm=TRUE)-1, align="right"), 1), by=Ticker]
mo[, size_ln := log(pmax(Size, 1))]
cat("monthly panel rows:", nrow(mo), " YM range:", min(mo$YM), max(mo$YM), "\n")

# --- Signal: event occurrence in month YM (binary) + count, per event type ---
build_sig <- function(evsub) {
  s <- evsub[, .(evcount = .N), by=.(Ticker, YM)]
  s[, evbin := 1L]
  s
}
sig_supply <- build_sig(ev[is_supply==TRUE])
sig_earn   <- build_sig(ev[is_earn==TRUE])

ic_test <- function(sig, label) {
  # merge onto panel; non-event universe tickers get 0
  p <- merge(mo, sig, by=c("Ticker","YM"), all.x=TRUE)
  p[is.na(evbin), `:=`(evbin=0L, evcount=0)]
  p <- p[!is.na(fwd1)]
  # per-month cross-sectional Spearman IC of evbin vs fwd1 (need variation)
  ics <- p[, {
    if (sum(evbin)>=2 && .N>=20) .(ic = cor(evbin, fwd1, method="spearman"), n=.N, nev=sum(evbin))
    else .(ic=NA_real_, n=.N, nev=sum(evbin))
  }, by=YM]
  ics <- ics[!is.na(ic)]
  m_ic <- mean(ics$ic); t_ic <- m_ic/(sd(ics$ic)/sqrt(nrow(ics)))
  # count-based IC (magnitude proxy via # events)
  ics_c <- p[, {
    if (sum(evcount)>=2 && .N>=20) .(ic = cor(evcount, fwd1, method="spearman"))
    else .(ic=NA_real_)
  }, by=YM]
  ics_c <- ics_c[!is.na(ic)]
  m_icc <- mean(ics_c$ic); t_icc <- m_icc/(sd(ics_c$ic)/sqrt(nrow(ics_c)))
  # orthogonality: pooled corr of evbin with mom12 and size (event tickers vs rest)
  pv <- p[!is.na(mom12)]
  cor_mom <- suppressWarnings(cor(pv$evbin, pv$mom12, method="spearman"))
  cor_size <- suppressWarnings(cor(p$evbin, p$size_ln, method="spearman"))
  cat(sprintf("\n=== %s ===\n", label))
  cat(sprintf("  n_months_scored: %d\n", nrow(ics)))
  cat(sprintf("  binary IC: mean=%.4f  t=%.2f  (>0 sign=%s)\n", m_ic, t_ic, ifelse(m_ic>0,"POS","NEG")))
  cat(sprintf("  count  IC: mean=%.4f  t=%.2f\n", m_icc, t_icc))
  cat(sprintf("  orthogonality: cor(evbin, mom12)=%.3f   cor(evbin, size)=%.3f\n", cor_mom, cor_size))
  data.table(signal=label, n_months=nrow(ics), ic_bin=m_ic, t_bin=t_ic, ic_cnt=m_icc, t_cnt=t_icc, cor_mom=cor_mom, cor_size=cor_size)
}

r1 <- ic_test(sig_supply, "supply_contract_occurrence")
r2 <- ic_test(sig_earn,   "earnings_provisional_occurrence")
res <- rbind(r1, r2)
fwrite(res, file.path(OUT,"ic_microtest_results.csv"))
cat("\nSaved ic_microtest_results.csv\n")
