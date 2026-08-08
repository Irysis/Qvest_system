suppressPackageStartupMessages({library(data.table); library(arrow); library(sandwich); library(lmtest)})
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(ROOT)
OUT <- file.path(ROOT,"stage_artifacts/WT_D20260808_001"); IN9 <- file.path(ROOT,"stage_artifacts/WT_D20260802_009")
say <- function(...) cat(sprintf(...), "\n")
nw_t <- function(x,lag=3L){x<-x[is.finite(x)];if(length(x)<12L)return(NA_real_);f<-lm(x~1)
  tryCatch(as.numeric(lmtest::coeftest(f,vcov.=sandwich::NeweyWest(f,lag=lag,prewhite=FALSE))[1,3]),error=function(e)NA_real_)}
TUNED <- as.data.table(read_parquet(file.path(IN9,"tuned_panel.parquet")))[, Date:=as.Date(Date)]
RAW <- as.data.table(read_parquet(".cache/RAWDATA.parquet", col_select=c("Date","Ticker","Size","K200","KQ150")))[, Date:=as.Date(Date)]
RAW[, ym:=format(Date,"%Y-%m")]; MEND <- sort(RAW[, .(Date=max(Date)), by=ym]$Date)
RAWME <- RAW[Date %in% MEND]; rm(RAW); gc(verbose=FALSE)
UNIV <- RAWME[(K200==TRUE|KQ150==TRUE), .(Date,Ticker)]; SIZE <- RAWME[, .(Date,Ticker,Size)]
fwd <- readRDS(file.path(OUT,"fwd_cache.rds"))
ret <- as.data.table(fwd$returns_dt)[, .(Date=as.Date(Date),Ticker,Ret_1m)]
liq <- as.data.table(fwd$liq_dt)[, .(Date=as.Date(Date),Ticker,adv)]
sc_of <- function(f) merge(TUNED[Factor_Name==f & !is.na(score), .(Date,Ticker,score)], UNIV, by=c("Date","Ticker"))
E <- merge(sc_of("M01_PATHQ"), liq, by=c("Date","Ticker"), all.x=TRUE)
E <- E[is.na(adv)|adv>=2e8][, adv:=NULL]; E <- E[Date %in% ret$Date]
FZ <- rbindlist(lapply(c("D03_EWMA","Q01_EB"), function(f) sc_of(f)[, .(Date,Ticker,fz=score,F_=f)]))
FZ <- merge(FZ, E[,.(Date,Ticker)], by=c("Date","Ticker"))

IND <- as.data.table(read_parquet(".cache/investor_stock/investor_individual.parquet",
        col_select=c("Date","Ticker","NetBuy")))[, Date:=as.Date(Date)]
say("[SHAPE] investor_individual nrow=%d DAILY n_day=%d %s~%s", nrow(IND), uniqueN(IND$Date),
    as.character(min(IND$Date)), as.character(max(IND$Date)))
IND[, ym:=format(Date,"%Y-%m")]
INM <- IND[, .(nb=sum(NetBuy,na.rm=TRUE)), by=.(ym,Ticker)]; rm(IND); gc(verbose=FALSE)
dts <- sort(unique(E$Date)); SIGM <- data.table(Date=dts, ym=format(dts,"%Y-%m"))
# 동시기 (as-is) + 1개월 지연 (PIT-strict 변형)
mk <- function(shift_m){
  S <- copy(SIGM); if (shift_m>0) S[, ym := format(seq(Date[1],by="month",length.out=1),"%Y-%m")]
  S <- data.table(Date=dts, ym=format(as.Date(format(dts,"%Y-%m-01"))- (shift_m*0) ,"%Y-%m"))
  if (shift_m>0){ prev <- format(seq_len(length(dts))); S[, ym := c(rep(NA_character_,shift_m), format(dts,"%Y-%m")[seq_len(length(dts)-shift_m)])] }
  S[!is.na(ym)]
}
for (sh in c(0L,1L)) {
  S <- mk(sh)
  M <- merge(INM, S, by="ym")[, ym:=NULL]
  M <- merge(M, SIZE, by=c("Date","Ticker"))[is.finite(Size)&Size>0]
  M[, `:=`(nb_norm=nb/Size, lsz=log(Size))]
  for (f in c("D03_EWMA","Q01_EB")) {
    D <- merge(FZ[F_==f,.(Date,Ticker,fz)], M[,.(Date,Ticker,nb_norm,lsz)], by=c("Date","Ticker"))
    s <- D[, {ok<-is.finite(fz)&is.finite(nb_norm)&is.finite(lsz)
      if (sum(ok)>=30L && sd(fz[ok])>1e-8 && sd(nb_norm[ok])>1e-12 && sd(lsz[ok])>1e-8) {
        yz<-(nb_norm[ok]-mean(nb_norm[ok]))/sd(nb_norm[ok]); xz<-(fz[ok]-mean(fz[ok]))/sd(fz[ok]); sz<-(lsz[ok]-mean(lsz[ok]))/sd(lsz[ok])
        c1<-coef(lm(yz~xz+sz)); c0<-coef(lm(yz~xz)); .(b_ctl=unname(c1[2]), b_raw=unname(c0[2]), b_sz=unname(c1[3]))
      } else .(b_ctl=NA_real_,b_raw=NA_real_,b_sz=NA_real_)}, by=Date][is.finite(b_ctl)]
    say("[shift=%dm] %-9s raw %+.4f (t %+.2f) -> size-ctl %+.4f (t %+.2f) 잔존 %.2f | size 자체 %+.4f (t %+.2f) n=%d",
        sh, f, mean(s$b_raw), nw_t(s$b_raw), mean(s$b_ctl), nw_t(s$b_ctl),
        mean(s$b_ctl)/mean(s$b_raw), mean(s$b_sz), nw_t(s$b_sz), nrow(s))
  }
}
