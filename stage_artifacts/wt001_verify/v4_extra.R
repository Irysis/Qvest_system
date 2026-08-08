# v4 — (i) beta-drag 의 정량적 충분성 (ii) D03 mean-reversal 의 시기 안정성
suppressPackageStartupMessages({library(data.table); library(arrow); library(sandwich); library(lmtest)})
ROOT <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT <- file.path(ROOT,"stage_artifacts/WT_D20260808_001"); IN9 <- file.path(ROOT,"stage_artifacts/WT_D20260802_009")
say <- function(fmt,...) cat(sprintf(paste0("[v4] ",fmt,"\n"),...))
nw_t <- function(x,lag=3L){x<-x[is.finite(x)];if(length(x)<12L)return(NA_real_);f<-lm(x~1)
  tryCatch(as.numeric(lmtest::coeftest(f,vcov.=sandwich::NeweyWest(f,lag=lag,prewhite=FALSE))[1,3]),error=function(e)NA_real_)}
fwd <- readRDS(file.path(OUT,"fwd_cache.rds"))
returns_dt <- as.data.table(fwd$returns_dt)[,.(Date=as.Date(Date),Ticker,Ret_1m)]
bench_dt <- as.data.table(fwd$bench_dt)[,.(Date=as.Date(Date),BM_Ret)]
liq_dt <- as.data.table(fwd$liq_dt)[,.(Date=as.Date(Date),Ticker,adv)]
say("BM: 월평균 %.4f → 연 %+.2f%%  (n=%d)", mean(bench_dt$BM_Ret), 100*12*mean(bench_dt$BM_Ret), nrow(bench_dt))
say("  beta 격차 -0.244 × BM 연 %.2f%% = 기대 drag %+.2f%%/yr", 100*12*mean(bench_dt$BM_Ret), -0.244*100*12*mean(bench_dt$BM_Ret))
BASE <- as.data.table(read_parquet(file.path(IN9,"base_panel.parquet")))[,Date:=as.Date(Date)]
TUNED <- as.data.table(read_parquet(file.path(IN9,"tuned_panel.parquet")))[,Date:=as.Date(Date)]
RAW <- as.data.table(read_parquet(".cache/RAWDATA.parquet",col_select=c("Date","Ticker","K200","KQ150")))[,Date:=as.Date(Date)]
RAW[,ym:=format(Date,"%Y-%m")]; MEND <- sort(RAW[,.(Date=max(Date)),by=ym]$Date)
UNIV <- RAW[Date %in% MEND][(K200==TRUE|KQ150==TRUE),.(Date,Ticker)]; rm(RAW); gc(verbose=FALSE)
score_of <- function(f){sc <- if (f %in% BASE$Factor_Name) BASE[Factor_Name==f,.(Date,Ticker,score=z)]
  else TUNED[Factor_Name==f,.(Date,Ticker,score=score)]; merge(sc[!is.na(score)],UNIV,by=c("Date","Ticker"))}
E <- merge(score_of("M01_PATHQ"),liq_dt,by=c("Date","Ticker"),all.x=TRUE)
E <- E[is.na(adv)|adv>=2e8][,adv:=NULL]; E <- E[Date %in% returns_dt$Date]
FZ <- merge(score_of("D03_EWMA")[,.(Date,Ticker,fz=score)],E[,.(Date,Ticker)],by=c("Date","Ticker"))
D <- merge(FZ, returns_dt, by=c("Date","Ticker"))
M <- D[,{q<-cut(frank(fz),breaks=5,labels=FALSE); .(q=q,r=Ret_1m)},by=Date]
P <- M[,.(mu=mean(r,na.rm=TRUE)),by=.(Date,q)]
W <- dcast(P,Date~q,value.var="mu"); setnames(W,as.character(1:5),paste0("m",1:5))
W[, dq := m1-m5]
W[, era := fifelse(Date<as.Date("2009-01-01"),"E1_2002_2008",
            fifelse(Date<as.Date("2017-01-01"),"E2_2009_2016","E3_2017_2026"))]
say("D03 Q1-Q5 (mean) 전표본: 연 %+.2f%%  NW3 t %+.2f  n=%d", 100*12*mean(W$dq,na.rm=TRUE), nw_t(W$dq), sum(is.finite(W$dq)))
for (e in sort(unique(W$era))) {
  s <- W[era==e]
  say("   %s: 연 %+.2f%%  NW3 t %+.2f  n=%d", e, 100*12*mean(s$dq,na.rm=TRUE), nw_t(s$dq), nrow(s))
}
# monotonicity 추정 안정성: 부트스트랩(월 블록) 재표집
set.seed(11)
mono_boot <- replicate(500, {
  idx <- sample(seq_len(nrow(W)), nrow(W), replace=TRUE)
  qm <- sapply(paste0("m",1:5), function(k) mean(W[[k]][idx], na.rm=TRUE))
  mean(diff(qm) > 0)
})
say("monotonicity(D03, mean-based) 원값 0.25 → 부트스트랩 분포: %s",
    paste(sprintf("%.2f:%.0f%%", sort(unique(mono_boot)), 100*table(mono_boot)/length(mono_boot)), collapse=" "))
say("  P(monotonicity < 0.5) = %.2f  ← 제안된 자동 라벨 규칙의 발화 확률", mean(mono_boot < 0.5))
say("=== v4 완료 ===")
