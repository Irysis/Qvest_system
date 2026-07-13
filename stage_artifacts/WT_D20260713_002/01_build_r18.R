#==============================================================================
# WT-D20260713_002 R18 — Step 01: build F-A (Modified-Jones discretionary accruals)
#   + F-B (Benford FSD) monthly cross-sectional scores. Also AC13-ref (original
#   Jones) for incrementality corr. API=0. Cached fundamentals only. single-thread.
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow) })
setDTthreads(1L); try(arrow::set_io_thread_count(2L), silent=TRUE)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
PAN  <- file.path(ROOT, "stage_artifacts/WT_D20260711_002")   # frozen monthly_panel.rds
OUT  <- file.path(ROOT, "stage_artifacts/WT_D20260713_002")

ym2date <- function(ym) as.Date(sprintf("%d-%02d-01", ym%/%100L, ym%%100L))
ym_add  <- function(ym, k){ y<-ym%/%100L; m<-ym%%100L; t<-(y*12L+(m-1L))+k; (t%/%12L)*100L+(t%%12L)+1L }
dt2ym   <- function(d){ d<-as.Date(d); as.integer(format(d,"%Y"))*100L + as.integer(format(d,"%m")) }

# ---- universe + membership (frozen monthly_panel) ----
mp <- readRDS(file.path(PAN,"monthly_panel.rds")); me <- mp$me
memb <- me[K200==TRUE | KQ150==TRUE, .(Ticker, ym)]
setkey(memb, ym, Ticker)
cat("[01] universe member-months:", nrow(memb), " decision ym:", paste(range(memb$ym),collapse=".."),"\n")

# ---- frozen PIT helpers (R17 convention) ----
expand_hold <- function(sig, H){
  sig <- sig[is.finite(raw)]
  sig[, us := ym_add(rcept_ym, 1L)]                 # first usable decision month (Factor_Date month +1)
  rows <- sig[, {
    dm <- vapply(0:(H-1L), function(k) ym_add(us, k), integer(1))
    .(decision_ym = dm, raw = raw, rcept_ym = rcept_ym)
  }, by=.(Ticker, seq_len(nrow(sig)))]
  rows[, seq_len := NULL]
  setorder(rows, Ticker, decision_ym, -rcept_ym)
  rows <- rows[, .SD[1L], by=.(Ticker, decision_ym)]  # most-recent active signal
  rows[, .(Ticker, ym=decision_ym, raw)]
}
make_scores <- function(sig_monthly, sign){
  x <- merge(sig_monthly, memb, by=c("Ticker","ym"))
  zc <- function(v){ s<-sd(v,na.rm=TRUE); if(!is.finite(s)||s<=0) return(rep(NA_real_,length(v))); (v-mean(v,na.rm=TRUE))/s }
  x[, z := zc(raw), by=ym]
  x <- x[is.finite(z)]
  x[, .(Date=ym2date(ym), Ticker, score = sign*z, raw)]
}
winsor <- function(v, p=0.01){
  q <- quantile(v, c(p,1-p), na.rm=TRUE, names=FALSE)
  pmin(pmax(v, q[1]), q[2])
}

#===================== load fundamentals (annual) =====================
FUND <- as.data.table(read_parquet(file.path(ROOT,".cache/fundamental_merged.parquet")))
FUND[, fy := as.integer(substr(Period,1,4))]
FUND[, pm := as.integer(substr(Period,5,6))]
ann <- FUND[pm==12L & is.finite(Value)]                  # annual only
cat("[01] annual fundamental rows:", nrow(ann), " fy range:", paste(range(ann$fy),collapse=".."),"\n")

# helper: wide annual per (Ticker,fy) for a set of items (take last value if dup)
ann_wide <- function(items){
  s <- ann[Item %in% items, .(Value=Value[.N], Factor_Date=max(Factor_Date)), by=.(Ticker,fy,Item)]
  w <- dcast(s, Ticker+fy ~ Item, value.var="Value")
  fd <- s[, .(Factor_Date=max(Factor_Date)), by=.(Ticker,fy)]
  merge(w, fd, by=c("Ticker","fy"))
}

#===================== F-A: Modified-Jones discretionary accruals =====================
itA <- c("NetIncome","OperatingCF","TotalAssets","Revenue","AccountsRecv","TangibleAssets")
WA <- ann_wide(itA)
setorder(WA, Ticker, fy)
WA[, `:=`(A_lag=shift(TotalAssets), Rev_lag=shift(Revenue), AR_lag=shift(AccountsRecv), fy_lag=shift(fy)), by=Ticker]
WA <- WA[is.finite(A_lag) & A_lag>0 & (fy - fy_lag == 1L)]
WA[, ta_sc  := (NetIncome - OperatingCF)/A_lag]
WA[, inv_ta := 1/A_lag]
WA[, drev_adj := ((Revenue - Rev_lag) - (AccountsRecv - AR_lag))/A_lag]   # modified Jones: dRev - dREC
WA[, ppe_sc := TangibleAssets/A_lag]
WA <- WA[is.finite(ta_sc) & is.finite(drev_adj) & is.finite(ppe_sc)]
# per-FY winsorize (1/99) + cross-sectional regression -> residual = discretionary accrual
faR <- WA[, {
  y <- winsor(ta_sc); x1 <- inv_ta; x2 <- winsor(drev_adj); x3 <- winsor(ppe_sc)
  ok <- is.finite(y)&is.finite(x1)&is.finite(x2)&is.finite(x3)
  if(sum(ok) >= 30L){
    fit <- tryCatch(lm.fit(cbind(x1[ok],x2[ok],x3[ok]), y[ok]), error=function(e) NULL)
    if(!is.null(fit)){
      res <- rep(NA_real_, .N); res[ok] <- fit$residuals
      .(Ticker=Ticker, Factor_Date=Factor_Date, disc_acc=res)
    } else .(Ticker=character(0),Factor_Date=as.Date(character(0)),disc_acc=numeric(0))
  } else .(Ticker=character(0),Factor_Date=as.Date(character(0)),disc_acc=numeric(0))
}, by=fy]
faR <- faR[is.finite(disc_acc)]
cat("[01][F-A] modified-Jones residual firm-years:", nrow(faR), " FY used:", uniqueN(faR$fy),"\n")
fa_list <- faR[, .(Ticker, rcept_ym=dt2ym(Factor_Date), raw=disc_acc)]
fa_sig  <- expand_hold(fa_list, H=12L)
scores_FA <- make_scores(fa_sig, sign=-1)     # high discretionary accrual = short
write_parquet(scores_FA, file.path(OUT,"scores_FA.parquet"))
cat("[01][F-A] scores rows:", nrow(scores_FA), " months:", uniqueN(scores_FA$Date),"\n")

#===================== AC13-ref: ORIGINAL Jones (dRev only), per FY, for corr =====================
acR <- WA[, {
  y <- winsor(ta_sc); x1 <- inv_ta
  drev_only <- (Revenue - Rev_lag)/A_lag                 # original Jones: dRev (no dREC)
  x2 <- winsor(drev_only); x3 <- winsor(ppe_sc)
  ok <- is.finite(y)&is.finite(x1)&is.finite(x2)&is.finite(x3)
  if(sum(ok) >= 30L){
    fit <- tryCatch(lm.fit(cbind(x1[ok],x2[ok],x3[ok]), y[ok]), error=function(e) NULL)
    if(!is.null(fit)){ res<-rep(NA_real_,.N); res[ok]<-fit$residuals; .(Ticker=Ticker,Factor_Date=Factor_Date,ac=res) }
    else .(Ticker=character(0),Factor_Date=as.Date(character(0)),ac=numeric(0))
  } else .(Ticker=character(0),Factor_Date=as.Date(character(0)),ac=numeric(0))
}, by=fy]
acR <- acR[is.finite(ac)]
ac_sig <- expand_hold(acR[,.(Ticker,rcept_ym=dt2ym(Factor_Date),raw=ac)], H=12L)
scores_AC13ref <- make_scores(ac_sig, sign=-1)
write_parquet(scores_AC13ref, file.path(OUT,"scores_AC13ref.parquet"))
cat("[01][AC13ref] scores rows:", nrow(scores_AC13ref),"\n")

#===================== F-B: Benford FSD (MAD) =====================
RAW_MON <- c("TotalAssets","TotalLiab","TotalEquity","CurrentAssets","NonCurrentAssets","CurrentLiab",
 "NonCurrentLiab","CashAndEquiv","AccountsRecv","Inventory","TangibleAssets","IntangibleAssets",
 "ShortTermBorr","LongTermBorr","AccountsPay","LongTermPay","LongTermRecv","RetainedEarnings",
 "CapitalStock","TotalDebt","NetDebt","WorkingCapital","Revenue","COGS","GrossProfit","SGAExpense",
 "OperatingProfit","PretaxIncome","NetIncome","TaxExpense","InterestExp","InterestIncome","DepAmort",
 "EBITDA","EBIT","NOPAT","RandD","Dividends","OperatingCF","InvestCF","FinanceCF","FCF1","FCF2")
bexp <- log10(1 + 1/(1:9))                      # Benford expected first-digit freq
bf <- ann[Item %in% RAW_MON]
bf <- bf[abs(Value) > 0 & is.finite(Value)]
bf[, x := abs(Value)]
bf[, fd := as.integer(floor(x / 10^floor(log10(x))))]
bf <- bf[fd >= 1L & fd <= 9L]
fsd <- bf[, {
  n <- .N
  if(n >= 15L){
    tab <- tabulate(fd, nbins=9L)/n
    mad <- mean(abs(tab - bexp))
    .(Factor_Date=max(Factor_Date), n_items=n, fsd=mad)
  } else .(Factor_Date=as.Date(NA), n_items=n, fsd=NA_real_)
}, by=.(Ticker, fy)]
fsd <- fsd[is.finite(fsd)]
cat("[01][F-B] Benford firm-years (>=15 items):", nrow(fsd),
    " n_items median:", median(fsd$n_items), " fsd q:", paste(round(quantile(fsd$fsd,c(0,.5,.9,1)),4),collapse=","),"\n")
fb_list <- fsd[, .(Ticker, rcept_ym=dt2ym(Factor_Date), raw=fsd)]
fb_sig  <- expand_hold(fb_list, H=12L)
scores_FB <- make_scores(fb_sig, sign=-1)       # high deviation = short
write_parquet(scores_FB, file.path(OUT,"scores_FB.parquet"))
cat("[01][F-B] scores rows:", nrow(scores_FB), " months:", uniqueN(scores_FB$Date),"\n")

#===================== aligned panels (R17 13b convention) =====================
ret_at_t   <- me[, .(Ticker, ym=ym_add(ym,-1L), Ret_1m=mret)]
bench_at_t <- mp$bench_m[, .(ym=ym_add(ym,-1L), BM_Ret=bench_mret)]
saveRDS(list(
  returns_all = ret_at_t[, .(Date=ym2date(ym), Ticker, Ret_1m)],
  bench_all   = bench_at_t[, .(Date=ym2date(ym), BM_Ret)],
  size_all    = me[, .(Date=ym2date(ym), Ticker, Size)],
  liq_all     = me[, .(Date=ym2date(ym), Ticker, adv=adv20)]
), file.path(OUT,"panels.rds"))
cat("[01] DONE — scores + panels saved\n")
