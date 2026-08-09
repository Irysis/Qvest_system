suppressPackageStartupMessages({
  library(data.table); library(arrow); library(sandwich); library(lmtest)
})
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/WT_D20260808_001")
IN9  <- file.path(ROOT, "stage_artifacts/WT_D20260802_009")
VOUT <- file.path(ROOT, "stage_artifacts/wt001_verify/stat_lens")
say <- function(fmt, ...) cat(sprintf(paste0("[BD] ", fmt, "\n"), ...))
FILT <- c("D03_EWMA","Q01_EB")

BASE  <- as.data.table(read_parquet(file.path(IN9,"base_panel.parquet")))[, Date := as.Date(Date)]
TUNED <- as.data.table(read_parquet(file.path(IN9,"tuned_panel.parquet")))[, Date := as.Date(Date)]
RAW <- as.data.table(read_parquet(".cache/RAWDATA.parquet",
        col_select=c("Date","Ticker","Size","K200","KQ150")))[, Date := as.Date(Date)]
RAW[, ym := format(Date,"%Y-%m")]
MEND <- sort(RAW[, .(Date=max(Date)), by=ym]$Date)
RAWME <- RAW[Date %in% MEND]; rm(RAW); gc(verbose=FALSE)
UNIV <- RAWME[(K200==TRUE|KQ150==TRUE), .(Date,Ticker)]
SIZE <- RAWME[, .(Date,Ticker,Size)]
fwd <- readRDS(file.path(OUT,"fwd_cache.rds"))
returns_dt <- as.data.table(fwd$returns_dt)[, .(Date=as.Date(Date),Ticker,Ret_1m)]
bench_dt   <- as.data.table(fwd$bench_dt)[, .(Date=as.Date(Date),BM_Ret)]
liq_dt     <- as.data.table(fwd$liq_dt)[, .(Date=as.Date(Date),Ticker,adv)]
say("INPUT returns_dt MONTHLY nrow=%d ndates=%d | RAWME(월말) nrow=%d ndates=%d",
    nrow(returns_dt), uniqueN(returns_dt$Date), nrow(RAWME), uniqueN(RAWME$Date))

score_of <- function(f){sc <- if (f %in% BASE$Factor_Name) BASE[Factor_Name==f,.(Date,Ticker,score=z)]
  else TUNED[Factor_Name==f,.(Date,Ticker,score=score)]; merge(sc[!is.na(score)],UNIV,by=c("Date","Ticker"))}
E <- merge(score_of("M01_PATHQ"), liq_dt, by=c("Date","Ticker"), all.x=TRUE)
E <- E[is.na(adv)|adv>=2e8][, adv:=NULL]; setorder(E,Date,-score); E[, rk:=seq_len(.N), by=Date]
E <- E[Date %in% returns_dt$Date]
FZ <- rbindlist(lapply(FILT,function(f) score_of(f)[,.(Date,Ticker,fz=score,F_=f)]))
FZ <- merge(FZ, E[,.(Date,Ticker)], by=c("Date","Ticker")); FZ[, q_rank:=frank(fz)/.N, by=.(Date,F_)]

nwt <- function(x, lag){x<-x[is.finite(x)]; f<-lm(x~1)
  as.numeric(lmtest::coeftest(f, vcov.=sandwich::NeweyWest(f, lag=lag, prewhite=FALSE))[1,3])}
lagscan <- function(x, tag){
  ac <- as.numeric(acf(x, lag.max=24, plot=FALSE)$acf)[-1]
  tt <- sapply(c(0,3,6,12,24), function(L) if (L==0) as.numeric(t.test(x)$statistic) else nwt(x,L))
  say("%s: n=%d mean=%+.5f | ACF rho1=%.3f rho3=%.3f rho6=%.3f rho12=%.3f | t: iid=%.2f L3=%.2f L6=%.2f L12=%.2f L24=%.2f",
      tag, length(x), mean(x), ac[1],ac[3],ac[6],ac[12], tt[1],tt[2],tt[3],tt[4],tt[5])
  invisible(list(acf=ac, t=tt))
}

# ============ 주장 B — 순위 vs 평균 ============
say("======== 주장 B: rank-IC vs 분위 평균 ========")
RES <- list()
for (f in c("D03_EWMA","Q01_EB")) {
  sc <- FZ[F_==f, .(Date,Ticker,score=fz)]
  D <- merge(sc, returns_dt, by=c("Date","Ticker"))
  ic <- D[, if (.N>=10L && sd(score)>0 && sd(Ret_1m)>0) .(ic=cor(score,Ret_1m,method="spearman")) else .(ic=NA_real_), by=Date][is.finite(ic)]
  say("--- %s : rank-IC 계열 ---", f)
  ib <- lagscan(ic$ic, sprintf("  IC(%s)", f))
  say("  rank_IC 평균 %+.5f  ICIR %.3f  (원 산출 대조)", mean(ic$ic), mean(ic$ic)/sd(ic$ic))
  # 분위 평균 / 중앙값 / 왜도
  mono <- D[, {
    q <- cut(frank(score), breaks=5, labels=FALSE)
    .(m1=mean(Ret_1m[q==1]),m2=mean(Ret_1m[q==2]),m3=mean(Ret_1m[q==3]),m4=mean(Ret_1m[q==4]),m5=mean(Ret_1m[q==5]),
      md1=median(Ret_1m[q==1]),md3=median(Ret_1m[q==3]),md5=median(Ret_1m[q==5]),
      sk1=mean((Ret_1m[q==1]-mean(Ret_1m[q==1]))^3)/sd(Ret_1m[q==1])^3,
      sk5=mean((Ret_1m[q==5]-mean(Ret_1m[q==5]))^3)/sd(Ret_1m[q==5])^3,
      sd1=sd(Ret_1m[q==1]), sd5=sd(Ret_1m[q==5]),
      d51=mean(Ret_1m[q==5])-mean(Ret_1m[q==1]),
      dmed51=median(Ret_1m[q==5])-median(Ret_1m[q==1]))
  }, by=Date]
  qm <- sapply(paste0("m",1:5), function(k) mean(mono[[k]]))
  say("  분위 평균 연 %%: %s | monotonicity=%.2f", paste(sprintf("%+.1f",100*12*qm),collapse=" "), mean(diff(qm)>0))
  say("  분위 중앙값 연 %%: Q1 %+.1f  Q3 %+.1f  Q5 %+.1f", 100*12*mean(mono$md1), 100*12*mean(mono$md3), 100*12*mean(mono$md5))
  say("  횡단면 왜도 평균: Q1 %.2f  Q5 %.2f | 횡단면 sd 평균: Q1 %.4f  Q5 %.4f", mean(mono$sk1), mean(mono$sk5), mean(mono$sd1), mean(mono$sd5))
  lagscan(mono$d51,   sprintf("  Q5-Q1 평균차(%s)", f))
  lagscan(mono$dmed51,sprintf("  Q5-Q1 중앙값차(%s)", f))
  RES[[f]] <- list(ic=ic, mono=mono, qm=qm)
}

# ============ 주장 D — 사이즈 통제 후 개인 순매수 ============
say("======== 주장 D: F2 size-control ========")
IND <- as.data.table(read_parquet(".cache/investor_stock/investor_individual.parquet",
        col_select=c("Date","Ticker","NetBuy")))[, Date:=as.Date(Date)]
say("INPUT investor_individual nrow=%d DAILY n_day=%d %s~%s", nrow(IND), uniqueN(IND$Date),
    as.character(min(IND$Date)), as.character(max(IND$Date)))
IND[, ym:=format(Date,"%Y-%m")]
INM <- IND[, .(nb=sum(NetBuy,na.rm=TRUE)), by=.(ym,Ticker)]; rm(IND); gc(verbose=FALSE)
SIGM <- data.table(Date=sort(unique(E$Date)))[, ym:=format(Date,"%Y-%m")]
INM <- merge(INM, SIGM, by="ym")[, ym:=NULL]
INM <- merge(INM, SIZE, by=c("Date","Ticker"))[is.finite(Size)&Size>0]
INM[, `:=`(nb_norm=nb/Size, lsz=log(Size))]
DRES <- list()
for (f in FILT) {
  D <- merge(FZ[F_==f,.(Date,Ticker,fz)], INM[,.(Date,Ticker,nb_norm,lsz)], by=c("Date","Ticker"))
  s <- D[, {
    ok <- is.finite(fz)&is.finite(nb_norm)&is.finite(lsz)
    if (sum(ok)>=30L && sd(fz[ok])>1e-8 && sd(nb_norm[ok])>1e-12 && sd(lsz[ok])>1e-8) {
      yz <- (nb_norm[ok]-mean(nb_norm[ok]))/sd(nb_norm[ok])
      xz <- (fz[ok]-mean(fz[ok]))/sd(fz[ok]); sz <- (lsz[ok]-mean(lsz[ok]))/sd(lsz[ok])
      cf <- coef(lm(yz ~ xz + sz)); cf1 <- coef(lm(yz ~ xz))
      # 순위 기반 강건판 (이상치 의존 시험)
      yr <- qnorm((frank(nb_norm[ok])-0.5)/sum(ok)); xr <- qnorm((frank(fz[ok])-0.5)/sum(ok))
      sr <- qnorm((frank(lsz[ok])-0.5)/sum(ok))
      cfr <- coef(lm(yr ~ xr + sr))
      .(b_ctl=unname(cf[2]), b_raw=unname(cf1[2]), b_rank=unname(cfr[2]),
        b_size=unname(cf[3]), n=sum(ok))
    } else .(b_ctl=NA_real_,b_raw=NA_real_,b_rank=NA_real_,b_size=NA_real_,n=sum(ok))
  }, by=Date][is.finite(b_ctl)]
  say("--- %s ---", f)
  lagscan(s$b_raw,  sprintf("  raw slope(%s)", f))
  lagscan(s$b_ctl,  sprintf("  size-ctl slope(%s)", f))
  lagscan(s$b_rank, sprintf("  rank-robust ctl(%s)", f))
  say("  월평균 종목수 %.0f · n_month %d", mean(s$n), nrow(s))
  DRES[[f]] <- s
}
saveRDS(list(B=RES, D=DRES), file.path(VOUT,"claimBD.rds"))
say("saved claimBD.rds")
