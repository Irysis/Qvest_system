suppressPackageStartupMessages({library(data.table); library(arrow); library(sandwich); library(lmtest)})
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(ROOT)
OUT <- file.path(ROOT,"stage_artifacts/WT_D20260808_001"); IN9 <- file.path(ROOT,"stage_artifacts/WT_D20260802_009")
say <- function(...) cat(sprintf(...), "\n")
nw_t <- function(x,lag=3L){x<-x[is.finite(x)];if(length(x)<12L)return(NA_real_);f<-lm(x~1)
  tryCatch(as.numeric(lmtest::coeftest(f,vcov.=sandwich::NeweyWest(f,lag=lag,prewhite=FALSE))[1,3]),error=function(e)NA_real_)}

TUNED <- as.data.table(read_parquet(file.path(IN9,"tuned_panel.parquet")))[, Date:=as.Date(Date)]
say("[SHAPE] tuned nrow=%d n_month=%d %s~%s factors=%s", nrow(TUNED), uniqueN(TUNED$Date),
    as.character(min(TUNED$Date)), as.character(max(TUNED$Date)), paste(unique(TUNED$Factor_Name),collapse=","))
RAW <- as.data.table(read_parquet(".cache/RAWDATA.parquet",
        col_select=c("Date","Ticker","K200","KQ150")))[, Date:=as.Date(Date)]
RAW[, ym:=format(Date,"%Y-%m")]; MEND <- sort(RAW[, .(Date=max(Date)), by=ym]$Date)
UNIV <- RAW[Date %in% MEND & (K200==TRUE|KQ150==TRUE), .(Date,Ticker)]; rm(RAW); gc(verbose=FALSE)
fwd <- readRDS(file.path(OUT,"fwd_cache.rds"))
ret <- as.data.table(fwd$returns_dt)[, .(Date=as.Date(Date),Ticker,Ret_1m)]
liq <- as.data.table(fwd$liq_dt)[, .(Date=as.Date(Date),Ticker,adv)]

sc_of <- function(f) merge(TUNED[Factor_Name==f & !is.na(score), .(Date,Ticker,score)], UNIV, by=c("Date","Ticker"))
E <- merge(sc_of("M01_PATHQ"), liq, by=c("Date","Ticker"), all.x=TRUE)
E <- E[is.na(adv)|adv>=2e8][, adv:=NULL]; E <- E[Date %in% ret$Date]
say("[SHAPE] eligible nrow=%d n_month=%d 월평균 %.1f", nrow(E), uniqueN(E$Date), E[,.N,by=Date][,mean(N)])

battery <- function(sc, ret_use, nm) {
  D <- merge(sc, ret_use, by=c("Date","Ticker"))
  ic <- D[, if (.N>=10L && sd(score)>0 && sd(Ret_1m)>0) .(ic=cor(score,Ret_1m,method="spearman")) else .(ic=NA_real_), by=Date][is.finite(ic)]
  mo <- D[, {q<-cut(frank(score),breaks=5,labels=FALSE)
    .(m1=mean(Ret_1m[q==1]),m2=mean(Ret_1m[q==2]),m3=mean(Ret_1m[q==3]),m4=mean(Ret_1m[q==4]),m5=mean(Ret_1m[q==5]))}, by=Date]
  qm <- sapply(paste0("m",1:5), function(k) mean(mo[[k]], na.rm=TRUE))*1200
  # median 기반 대조 (왜도 가설 직접 시험)
  mo2 <- D[, {q<-cut(frank(score),breaks=5,labels=FALSE)
    .(m1=median(Ret_1m[q==1]),m3=median(Ret_1m[q==3]),m5=median(Ret_1m[q==5]))}, by=Date]
  qmed <- c(mean(mo2$m1),mean(mo2$m3),mean(mo2$m5))*1200
  sk <- D[, {q<-cut(frank(score),breaks=5,labels=FALSE)
    .(s1=mean(Ret_1m[q==1]>quantile(Ret_1m,0.95)), s5=mean(Ret_1m[q==5]>quantile(Ret_1m,0.95)))}, by=Date]
  say("[%s] n_month=%d rank_IC %+.4f  NW-t %+.2f  ICIR %+.3f  mono %.2f", nm, nrow(ic),
      mean(ic$ic), nw_t(ic$ic), mean(ic$ic)/sd(ic$ic), mean(diff(qm)>0))
  say("       분위 평균 연 Q1..Q5 = %s", paste(sprintf("%+.1f%%",qm),collapse=" "))
  say("       분위 중앙값 연 Q1/Q3/Q5 = %s   상위5%% 꼬리점유 Q1 %.3f vs Q5 %.3f",
      paste(sprintf("%+.1f%%",qmed),collapse="/"), mean(sk$s1), mean(sk$s5))
  invisible(list(ic=mean(ic$ic), t=nw_t(ic$ic), qm=qm))
}
for (f in c("D03_EWMA","Q01_EB","M01_PATHQ")) {
  s <- if (f=="M01_PATHQ") E[,.(Date,Ticker,score)] else merge(sc_of(f), E[,.(Date,Ticker)], by=c("Date","Ticker"))
  battery(s, ret, f)
}
# ---- 위반 주입(양성 대조): 신호를 1개월 앞당겨 동월 실현수익과 정렬 = look-ahead
say("---- 위반 주입: score(d+1) vs Ret_1m(d) [= 동월 look-ahead] ----")
dd <- sort(unique(E$Date)); idx <- setNames(seq_along(dd), as.character(dd))
for (f in c("D03_EWMA","Q01_EB")) {
  s <- merge(sc_of(f), E[,.(Date,Ticker)], by=c("Date","Ticker"))
  s[, i:=idx[as.character(Date)]]; s <- s[is.finite(i) & i>=2L][, Date:=dd[i-1L]][, i:=NULL]
  battery(s, ret, paste0(f,"_LOOKAHEAD_INJECT"))
}
