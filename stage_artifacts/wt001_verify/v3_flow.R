# v3_flow.R — 주장 D(개인 순매수 집중, 사이즈 통제) 재현 + 시점 검증 + 대안설명 통제
suppressPackageStartupMessages({ library(data.table); library(arrow); library(sandwich); library(lmtest) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
OUT <- file.path(ROOT,"stage_artifacts/wt001_verify"); W1 <- file.path(ROOT,"stage_artifacts/WT_D20260808_001")
IN9 <- file.path(ROOT,"stage_artifacts/WT_D20260802_009")
say <- function(fmt, ...) cat(sprintf(paste0("[v3] ", fmt, "\n"), ...))

TUNED <- as.data.table(read_parquet(file.path(IN9,"tuned_panel.parquet")))[, Date := as.Date(Date)]
RAW <- as.data.table(read_parquet(".cache/RAWDATA.parquet",
        col_select=c("Date","Ticker","Close","Vol","Size","K200","KQ150")))[, Date := as.Date(Date)]
RAW[, Date := as.Date(Date)][, ym := format(Date,"%Y-%m")]
MEND <- sort(RAW[, .(Date=max(Date)), by=ym]$Date)
# 월간 거래대금 (해당 달 합계 — 신호일까지)
TRD <- RAW[, .(trval = sum(Vol*Close, na.rm=TRUE), maxd = max(Date)), by=.(ym,Ticker)]
RAWME <- RAW[Date %in% MEND]; rm(RAW); gc(verbose=FALSE)
UNIV <- RAWME[(K200==TRUE|KQ150==TRUE), .(Date,Ticker)]
SIZE <- RAWME[, .(Date,Ticker,Size)]

fwd <- readRDS(file.path(W1,"fwd_cache.rds"))
ret <- as.data.table(fwd$returns_dt)[, .(Date=as.Date(Date),Ticker,Ret_1m)]
liq <- as.data.table(fwd$liq_dt)[, .(Date=as.Date(Date),Ticker,adv)]
nw_t <- function(x,lag=3L){x<-x[is.finite(x)];if(length(x)<12L)return(NA_real_)
  f<-lm(x~1);tryCatch(as.numeric(lmtest::coeftest(f,vcov.=sandwich::NeweyWest(f,lag=lag,prewhite=FALSE))[1,3]),error=function(e)NA_real_)}

score_of <- function(f) merge(TUNED[Factor_Name==f & !is.na(score), .(Date,Ticker,score)], UNIV, by=c("Date","Ticker"))
E <- merge(score_of("M01_PATHQ"), liq, by=c("Date","Ticker"), all.x=TRUE)
E <- E[is.na(adv)|adv>=2e8][, adv:=NULL]; setorder(E,Date,-score); E[, rk:=seq_len(.N),by=Date]; E <- E[Date %in% ret$Date]
FILT <- c("D03_EWMA","Q01_EB")
FZ <- rbindlist(lapply(FILT, function(f) score_of(f)[, .(Date,Ticker,fz=score,F_=f)]))
FZ <- merge(FZ, E[, .(Date,Ticker)], by=c("Date","Ticker"))

IND <- as.data.table(read_parquet(".cache/investor_stock/investor_individual.parquet",
        col_select=c("Date","Ticker","NetBuy")))[, Date:=as.Date(Date)]
say("investor_individual nrow=%d 관측단위=DAILY n_day=%d %s~%s", nrow(IND), uniqueN(IND$Date), min(IND$Date), max(IND$Date))
IND[, ym := format(Date,"%Y-%m")]
INM <- IND[, .(nb=sum(NetBuy,na.rm=TRUE), nb_maxd=max(Date)), by=.(ym,Ticker)]; rm(IND); gc(verbose=FALSE)

# ── 시점 검증: nb 집계월 마지막 날 <= 신호일 인가 (미래 정보 유입 여부) ───────
SIGM <- data.table(Date=sort(unique(E$Date)))[, ym := format(Date,"%Y-%m")]
tt <- merge(INM, SIGM, by="ym")
say("=== 시점 검증 ===")
say("  nb 집계 마지막 거래일 > 신호일 인 행: %d / %d  (0 이면 미래정보 없음)",
    sum(tt$nb_maxd > tt$Date), nrow(tt))
say("  nb 집계 마지막 거래일 = 신호일 인 행 비율: %.4f", mean(tt$nb_maxd == tt$Date))

INM2 <- merge(INM[, .(ym,Ticker,nb)], SIGM, by="ym")[, ym:=NULL]
INM2 <- merge(INM2, SIZE, by=c("Date","Ticker"))[is.finite(Size)&Size>0]
TRD2 <- merge(TRD[, .(ym,Ticker,trval)], SIGM, by="ym")[, ym:=NULL]
INM2 <- merge(INM2, TRD2, by=c("Date","Ticker"), all.x=TRUE)
INM2[, `:=`(nb_norm=nb/Size, lsz=log(Size), ltr=log(pmax(trval,1)))]

fmb3 <- function(D, form){
  s <- D[, { ok <- is.finite(fz)&is.finite(nb_norm)&is.finite(lsz)&is.finite(ltr)
    if (sum(ok)>=30L && sd(fz[ok])>1e-8 && sd(nb_norm[ok])>1e-12) {
      yz<-(nb_norm[ok]-mean(nb_norm[ok]))/sd(nb_norm[ok]); xz<-(fz[ok]-mean(fz[ok]))/sd(fz[ok])
      sz<-(lsz[ok]-mean(lsz[ok]))/sd(lsz[ok]); tz<-(ltr[ok]-mean(ltr[ok]))/sd(ltr[ok])
      cf <- switch(form,
        raw  = coef(lm(yz~xz)), size = coef(lm(yz~xz+sz)), both = coef(lm(yz~xz+sz+tz)))
      .(b=unname(cf[2]), n=sum(ok))
    } else .(b=NA_real_, n=sum(ok)) }, by=Date][is.finite(b)]
  list(b=mean(s$b), t=nw_t(s$b), n=nrow(s))
}
say("=== 주장 D 재현 + 대안설명 통제 ===")
for (f in FILT) {
  D <- merge(FZ[F_==f, .(Date,Ticker,fz)], INM2[, .(Date,Ticker,nb_norm,lsz,ltr)], by=c("Date","Ticker"))
  r1 <- fmb3(D,"raw"); r2 <- fmb3(D,"size"); r3 <- fmb3(D,"both")
  say("  %-9s raw %+.4f (t %+.2f) | +log(Size) %+.4f (t %+.2f) 잔존 %.2f | +log(Size)+log(거래대금) %+.4f (t %+.2f) 잔존 %.2f  n=%d",
      f, r1$b, r1$t, r2$b, r2$t, r2$b/r1$b, r3$b, r3$t, r3$b/r1$b, r1$n)
}
# 미래월 flow 로 바꾸면? (누출 민감도 — 코드본은 동시기)
say("=== 민감도: 보유월(t→t+1) flow 로 대체 시 ===")
dts <- sort(unique(E$Date)); nxt <- data.table(Date=dts, Date_f=c(dts[-1],NA))
INF <- merge(INM2[, .(Date_f=Date,Ticker,nb_f=nb_norm)], nxt, by="Date_f")[!is.na(Date)]
for (f in FILT) {
  D <- merge(FZ[F_==f,.(Date,Ticker,fz)], INF[,.(Date,Ticker,nb_norm=nb_f)], by=c("Date","Ticker"))
  D <- merge(D, INM2[,.(Date,Ticker,lsz,ltr)], by=c("Date","Ticker"))
  r2 <- fmb3(D,"size")
  say("  %-9s 보유월 flow, +log(Size): %+.4f (t %+.2f) n=%d", f, r2$b, r2$t, r2$n)
}
say("=== v3 완료 ===")
