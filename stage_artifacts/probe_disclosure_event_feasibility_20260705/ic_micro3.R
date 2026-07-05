# IC micro-characterization on cached months (occurrence signal, no doc parse)
# NOTE: small-n (3 event-months) — SIGN characterization only, not a graduation t-stat.
suppressPackageStartupMessages({library(data.table); library(arrow)})
setDTthreads(1)
OUT <- "stage_artifacts/probe_disclosure_event_feasibility_20260705"
fs <- list.files(file.path(OUT,"months"), pattern="\.csv$", full.names=TRUE)
ev <- rbindlist(lapply(fs, fread, colClasses=list(character=c("stock_code","corp_code","rcept_dt","rcept_no"))), fill=TRUE)
ev[, stock_code := sprintf("%06d", as.integer(stock_code))]
ev[, Ticker := paste0("A", stock_code)]
ev[, rdate := as.Date(rcept_dt, format="%Y%m%d")]
ev[, YM := format(rdate, "%Y-%m")]
cat("cached event-months:", paste(sort(unique(ev$YM)),collapse=","), "\n")
cat("events: supply=",sum(ev$is_supply)," earn=",sum(ev$is_earn),"\n")

src <- ".cache/RAWDATA.parquet"; tmp <- file.path(tempdir(),"raw_ic3.parquet")
file.copy(src,tmp,overwrite=TRUE)
raw <- as.data.table(read_parquet(tmp, col_select=c("Date","Ticker","K200","KQ150","Close","Size","Ret")))
raw[, Date := as.Date(Date)]
raw <- raw[Date >= as.Date("2022-11-01") & Date <= as.Date("2023-06-30") & (K200==1|KQ150==1)]
raw[, YM := format(Date,"%Y-%m")]
setorder(raw, Ticker, Date)
mo <- raw[, .SD[.N], by=.(Ticker,YM), .SDcols=c("Date","Close","Size")]
setorder(mo, Ticker, YM)
mo[, mret := Close/shift(Close)-1, by=Ticker]
mo[, fwd1 := shift(mret,-1), by=Ticker]
mo[, size_ln := log(pmax(Size,1))]

test1 <- function(evsub, label) {
  s <- evsub[, .(evbin=1L, evcount=.N), by=.(Ticker,YM)]
  p <- merge(mo, s, by=c("Ticker","YM"), all.x=TRUE)
  p[is.na(evbin), `:=`(evbin=0L, evcount=0)]
  p <- p[!is.na(fwd1) & YM %in% unique(evsub$YM)]  # only months with events
  ics <- p[, {
    if (sum(evbin)>=3 && .N>=30) .(ic=cor(evbin,fwd1,method="spearman"), nev=sum(evbin), n=.N) else .(ic=NA_real_,nev=sum(evbin),n=.N)
  }, by=YM]
  ics <- ics[!is.na(ic)]
  cat(sprintf("\n=== %s (occurrence) ===\n", label))
  print(ics)
  if (nrow(ics)>0) cat(sprintf("  mean monthly IC = %+.4f  (sign %s), months=%d\n",
      mean(ics$ic), ifelse(mean(ics$ic)>0,"POS","NEG"), nrow(ics)))
  # pooled event vs non-event fwd return diff (all cached months pooled)
  pe <- p[evbin==1]; pn <- p[evbin==0]
  cat(sprintf("  pooled fwd1: event mean=%+.4f (n=%d) vs non-event mean=%+.4f (n=%d)  diff=%+.4f\n",
      mean(pe$fwd1), nrow(pe), mean(pn$fwd1), nrow(pn), mean(pe$fwd1)-mean(pn$fwd1)))
  tt <- tryCatch(t.test(pe$fwd1, pn$fwd1), error=function(e) NULL)
  if(!is.null(tt)) cat(sprintf("  Welch t (event-vs-rest fwd1): t=%.2f  p=%.3f\n", tt$statistic, tt$p.value))
}
test1(ev[is_supply==TRUE], "supply_contract")
test1(ev[is_earn==TRUE],   "earnings_provisional")
