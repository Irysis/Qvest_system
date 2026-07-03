suppressMessages({library(arrow); library(data.table)})
arrow::set_io_thread_count(2L); setDTthreads(1L)
options(stringsAsFactors=FALSE)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
source(file.path(ROOT,"02_Infrastructure/contracts/canonical_screen_bt.R"))

# ---- 1. Load rawdata (col_select) ----
pq <- file.path(ROOT,".cache/rawdata.parquet")
dt <- as.data.table(arrow::read_parquet(pq, col_select=c(
  "Date","Ticker","Open","Close","Vol","Ret","K200","KQ150","TradingHalt","AdminStock")))
dt[, Date := as.Date(Date)]
dt <- dt[Date >= as.Date("2005-01-01") & !is.na(Close)]
setorder(dt, Ticker, Date)

# ---- 2. overnight / intraday legs ----
dt[, prevClose := shift(Close,1L,type="lag"), by=Ticker]
dt[, overnight := log(Open/prevClose)]
dt[, intraday  := log(Close/Open)]
# integrity assert
dt[, dec_err := abs(overnight + intraday - log(1+Ret))]
bad <- dt[is.finite(dec_err) & dec_err>1e-6, .N]
cat("decomp_err>1e-6 rows:", bad, "/", nrow(dt), "(", round(100*bad/nrow(dt),4),"%)\n")

# ---- 3. artifact guards ----
dt[is.na(Open)|Open<=0, overnight := NA_real_]
dt[abs(overnight)>0.6, overnight := NA_real_]   # limit/corp-action guard
dt[abs(intraday)>0.6, intraday := NA_real_]

# ---- liquidity: 20d ADV = mean(Close*Vol) ending t-1 ----
dt[, dollar := Close*Vol]
dt[, adv20 := frollmean(dollar, 20, align="right"), by=Ticker]
dt[, adv20_lag := shift(adv20,1L,type="lag"), by=Ticker]   # t-1 PIT

# t-1 eligibility snapshots
dt[, K200_l := shift(K200,1L), by=Ticker]
dt[, KQ150_l := shift(KQ150,1L), by=Ticker]
dt[, halt_l := shift(TradingHalt,1L), by=Ticker]
dt[, admin_l := shift(AdminStock,1L), by=Ticker]

# ---- 4. monthly sig_date grid = last trading day each month ----
dt[, ym := format(Date,"%Y%m")]
mend <- dt[, .(sig_date=max(Date)), by=ym]
sig_dates <- sort(mend$sig_date)
sig_dates <- sig_dates[sig_dates < max(dt$Date)]  # need forward return
cat("n sig_dates:", length(sig_dates), "range", as.character(min(sig_dates)),"-",as.character(max(sig_dates)),"\n")

# index helper: for each Ticker, daily series
setkey(dt, Ticker, Date)

# Build per-sig-date scores for a grid of (L, skip, k=21)
# ON_MOM = sum overnight over (t-L, t-skip]; INTRADAY_RECENT = sum intraday last k=21
build_scores <- function(L, skip, lambda, k=21L){
  res <- vector("list", length(sig_dates))
  for(i in seq_along(sig_dates)){
    t <- sig_dates[i]
    # window of trailing L trading days up to t
    sub <- dt[Date<=t]
    # per ticker: need trailing rows
    sub <- sub[, tail(.SD, L+5L), by=Ticker, .SDcols=c("Date","overnight","intraday","K200_l","KQ150_l","halt_l","admin_l","adv20_lag")]
    # rank days within ticker descending from t
    sub[, rk := .N - seq_len(.N) + 1L, by=Ticker]   # rk=1 oldest ... not ideal; use day offset
    # better: order by Date asc, position from end
    sub[, pos_from_end := rev(seq_len(.N))-1L, by=Ticker]  # 0 = most recent (==t row if present)
    # ON_MOM: overnight where pos in [skip, L)  (exclude last `skip`, include up to L)
    onm <- sub[pos_from_end>=skip & pos_from_end<L,
               .(ON_MOM=sum(overnight,na.rm=TRUE),
                 n_on=sum(!is.na(overnight)),
                 exp_on=.N), by=Ticker]
    # INTRADAY_RECENT: last k days
    inr <- sub[pos_from_end<k, .(INR=sum(intraday,na.rm=TRUE)), by=Ticker]
    # eligibility from the t-row (pos_from_end==0)
    elig <- sub[pos_from_end==0, .(Ticker, K200_l, KQ150_l, halt_l, admin_l, adv20_lag)]
    m <- merge(onm, inr, by="Ticker", all.x=TRUE)
    m <- merge(m, elig, by="Ticker", all.x=TRUE)
    m[, cov := n_on/pmax(exp_on,1L)]
    m <- m[cov>=0.8]
    m[, Date := t]
    res[[i]] <- m
  }
  S <- rbindlist(res, fill=TRUE)
  # eligibility filter
  S <- S[(K200_l==1 | KQ150_l==1) & (is.na(halt_l)|halt_l!=1) & (is.na(admin_l)|admin_l!=1)]
  # winsorize cross-sectionally [1%,99%] then z-score, per Date
  zwin <- function(x){
    q <- quantile(x, c(.01,.99), na.rm=TRUE)
    x <- pmin(pmax(x, q[1]), q[2])
    (x-mean(x,na.rm=TRUE))/sd(x,na.rm=TRUE)
  }
  S[, z_on := zwin(ON_MOM), by=Date]
  S[, z_inr := zwin(INR), by=Date]
  S[, score := z_on - lambda*z_inr]
  S[, .(Date, Ticker, score, adv=adv20_lag, ON_MOM, INR)]
}

# ---- forward 1M return (close-to-close, sig_date t -> next sig_date) ----
# build monthly close per ticker at sig_dates
mc <- dt[Date %in% sig_dates, .(Date, Ticker, Close)]
setorder(mc, Ticker, Date)
mc[, fwdClose := shift(Close,1L,type="lead"), by=Ticker]
mc[, Ret_1m := fwdClose/Close - 1]
returns_dt <- mc[!is.na(Ret_1m), .(Date, Ticker, Ret_1m)]

# ---- benchmark monthly compounded ----
bm <- as.data.table(arrow::read_parquet(file.path(ROOT,".cache/benchmark.parquet")))
bm[, Date := as.Date(Date)]
bm <- bm[Date>=as.Date("2004-12-01") & !is.na(BM_Ret)]
bm[, ym := format(Date,"%Y%m")]
# monthly compound, assign to month-end sig_date
bmm <- bm[, .(bm_m = prod(1+BM_Ret)-1, last=max(Date)), by=ym]
# map ym to our sig_date
mend_map <- mend[, .(ym, sig_date)]
bmm <- merge(bmm, mend_map, by="ym")
bench_dt <- bmm[sig_date %in% sig_dates, .(Date=sig_date, BM_Ret=bm_m)]
cat("bench_dt rows:", nrow(bench_dt), "\n")

saveRDS(list(dt=dt, sig_dates=sig_dates, returns_dt=returns_dt, bench_dt=bench_dt,
             build_scores=build_scores),
        "/tmp/m33_env.rds")
cat("ENV SAVED\n")
