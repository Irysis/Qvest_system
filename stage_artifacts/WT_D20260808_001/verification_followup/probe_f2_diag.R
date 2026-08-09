# probe_f2_diag.R — ② 의 핵심 주장(D03 F2 가 회전율 통제로 소멸) 이 표본 선택/공선성
#                    아티팩트가 아님을 확인. ★결과가 결정적일수록 통제를 더 건다.
suppressPackageStartupMessages({library(data.table); library(arrow); library(sandwich); library(lmtest)})
ROOT <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT <- file.path(ROOT,"stage_artifacts/WT_D20260808_001"); IN9 <- file.path(ROOT,"stage_artifacts/WT_D20260802_009")
say <- function(f,...) cat(sprintf(paste0("[f2diag] ",f,"\n"),...))
FILT <- c("D03_EWMA","Q01_EB")
nw_t <- function(x,lag=3L){x<-x[is.finite(x)];if(length(x)<12L)return(NA_real_);f<-lm(x~1)
  tryCatch(as.numeric(lmtest::coeftest(f,vcov.=sandwich::NeweyWest(f,lag=lag,prewhite=FALSE))[1,3]),error=function(e)NA_real_)}
zs <- function(v)(v-mean(v))/sd(v); wins <- function(v,p=.01){q<-quantile(v,c(p,1-p),na.rm=TRUE);pmin(pmax(v,q[1]),q[2])}
rk <- function(v){r<-frank(v)/length(v);(r-mean(r))/sd(r)}

BASE <- as.data.table(read_parquet(file.path(IN9,"base_panel.parquet")))[,Date:=as.Date(Date)]
TUNED <- as.data.table(read_parquet(file.path(IN9,"tuned_panel.parquet")))[,Date:=as.Date(Date)]
RAW <- as.data.table(read_parquet(".cache/RAWDATA.parquet",
        col_select=c("Date","Ticker","Close","Vol","Size","K200","KQ150")))[,Date:=as.Date(Date)]
RAW[,ym:=format(Date,"%Y-%m")]; RAW[,val:=Vol*Close]
VALM <- RAW[,.(val_m=sum(val,na.rm=TRUE)),by=.(ym,Ticker)]
MEND <- sort(RAW[,.(Date=max(Date)),by=ym]$Date)
RAWME <- RAW[Date %in% MEND,.(Date,ym,Ticker,Size,K200,KQ150)]; rm(RAW); gc(verbose=FALSE)
UNIV <- RAWME[(K200==TRUE|KQ150==TRUE),.(Date,Ticker)]
fwd <- readRDS(file.path(OUT,"fwd_cache.rds"))
returns_dt <- as.data.table(fwd$returns_dt)[,.(Date=as.Date(Date),Ticker,Ret_1m)]
liq_dt <- as.data.table(fwd$liq_dt)[,.(Date=as.Date(Date),Ticker,adv)]
score_of <- function(f){sc <- if (f %in% BASE$Factor_Name) BASE[Factor_Name==f,.(Date,Ticker,score=z)]
  else TUNED[Factor_Name==f,.(Date,Ticker,score=score)]; merge(sc[!is.na(score)],UNIV,by=c("Date","Ticker"))}
E <- merge(score_of("M01_PATHQ"),liq_dt,by=c("Date","Ticker"),all.x=TRUE)
E <- E[is.na(adv)|adv>=2e8][,adv:=NULL]; E <- E[Date %in% returns_dt$Date]
FZ <- rbindlist(lapply(FILT,function(f) score_of(f)[,.(Date,Ticker,fz=score,F_=f)]))
FZ <- merge(FZ,E[,.(Date,Ticker)],by=c("Date","Ticker"))
IND <- as.data.table(read_parquet(".cache/investor_stock/investor_individual.parquet",
        col_select=c("Date","Ticker","NetBuy")))[,Date:=as.Date(Date)]
IND[,ym:=format(Date,"%Y-%m")]
INM <- IND[,.(nb=sum(NetBuy,na.rm=TRUE)),by=.(ym,Ticker)]; rm(IND); gc(verbose=FALSE)
P <- merge(RAWME[Date %in% unique(E$Date),.(Date,ym,Ticker,Size)],INM,by=c("ym","Ticker"))
P <- merge(P,VALM,by=c("ym","Ticker"),all.x=TRUE)
P <- merge(P,liq_dt,by=c("Date","Ticker"),all.x=TRUE)
P <- P[is.finite(Size)&Size>0][,`:=`(nb_norm=nb/Size,lsz=log(Size),
  ladv=ifelse(is.finite(adv)&adv>0,log(adv),NA_real_),
  lturn=ifelse(is.finite(val_m)&val_m>0,log(val_m/Size),NA_real_))]

for (f in FILT) {
  D <- merge(FZ[F_==f,.(Date,Ticker,fz)],P[,.(Date,Ticker,nb_norm,lsz,ladv,lturn)],by=c("Date","Ticker"))
  say("=== %s ===", f)
  say("  회귀패널 %d행 · ladv 결측 %.3f%% · lturn 결측 %.3f%%  ⇒ 통제 추가로 인한 표본 축소 %s",
      nrow(D), 100*mean(is.na(D$ladv)), 100*mean(is.na(D$lturn)),
      if (mean(is.na(D$ladv))<0.01 && mean(is.na(D$lturn))<0.01) "없음" else "★있음(선택효과 의심)")
  say("  공선성: cor(fz,lturn)=%+.3f · cor(fz,ladv)=%+.3f · cor(fz,lsz)=%+.3f · cor(lturn,ladv)=%+.3f",
      cor(D$fz,D$lturn,use="complete.obs"), cor(D$fz,D$ladv,use="complete.obs"),
      cor(D$fz,D$lsz,use="complete.obs"), cor(D$lturn,D$ladv,use="complete.obs"))
  # ★위반 주입식 음성 대조: 통제 없이 같은 표본(complete.cases)에서 다시 재면 원값이 나오는가
  Dc <- D[complete.cases(D)]
  s0 <- Dc[,{.(b=unname(coef(lm(zs(wins(nb_norm))~zs(fz)))[2]))},by=Date]
  s4 <- Dc[,{dd<-data.table(y=zs(wins(nb_norm)),x=zs(fz),s=zs(lsz),tu=zs(lturn))
             .(b=unname(coef(lm(y~x+s+tu,data=dd))[2]))},by=Date]
  say("  동일표본 대조: 통제無 t %+.2f → 통제有 t %+.2f  (표본 %d행/%d개월)",
      nw_t(s0$b), nw_t(s4$b), nrow(Dc), uniqueN(Dc$Date))
  # 회전율 자체의 개인 순매수 연관 (교락의 실재 확인)
  st <- Dc[,{dd<-data.table(y=zs(wins(nb_norm)),tu=zs(lturn)); .(b=unname(coef(lm(y~tu,data=dd))[2]))},by=Date]
  say("  회전율 자체 → 개인 순매수: b %+.4f  t %+.2f  (교락 실재)", mean(st$b), nw_t(st$b))
  # VIF 근사
  vv <- Dc[,{dd<-data.table(x=zs(fz),s=zs(lsz),tu=zs(lturn)); .(r2=summary(lm(x~s+tu,data=dd))$r.squared)},by=Date]
  say("  fz ~ (lsz+lturn) 월별 R2 중앙 %.3f ⇒ VIF %.2f  %s", median(vv$r2), 1/(1-median(vv$r2)),
      if (median(vv$r2) > 0.9) "★공선성 과다 — 계수 소멸이 분산팽창 아티팩트일 수 있음" else "공선성 허용범위")
}
