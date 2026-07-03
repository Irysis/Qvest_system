#=============================================================================#
# 앙상블 고정 레버 스윕 — CAGR·SR·MDD 최적점 메뉴 (dvfs_lever)
# 무레버 앙상블(0.5 base+0.25 RP+0.25 GEM)은 SR/MDD 우수·CAGR 양보.
# 고정 레버 1.0~1.7로 스케일(차입비용 SHV 차감) → CAGR-MDD trade-off 곡선.
# 고정 레버는 look-ahead 없음(상수 스케일). vol-target보다 MDD 거동 온건.
#=============================================================================#
suppressMessages(pacman::p_load("quantmod","PerformanceAnalytics","xts","tidyverse"))
qm_root <- Sys.getenv("QM_ROOT", unset="C:/Users/99922/OneDrive/Quant_Module_Moltbot")
out_dir <- file.path(qm_root,"04_Research","dvaa_dvfs_revalidation")

nets <- readRDS(file.path(out_dir,"paradigm_nets.rds"))
ens <- na.omit(0.5*nets$base + 0.25*nets$rp + 0.25*nets$gem); colnames(ens)<-"ens"
shv <- na.omit(Return.calculate(Ad(getSymbols('SHV',src='yahoo',from='2007-01-01',auto.assign=FALSE))))
shv_a <- as.numeric(merge(ens, shv, join='left')[,2]); shv_a[is.na(shv_a)] <- 0
base <- nets$base; colnames(base)<-"base"

stratStats <- function(x){s<-rbind(table.AnnualizedReturns(x),maxDrawdown(x));s[5,]<-s[1,]/s[4,];s[6,]<-s[1,]/UlcerIndex(x);rownames(s)[4:6]<-c("MaxDD","Calmar","UlcerPI");s}

levs <- c(1.0, 1.1, 1.2, 1.3, 1.4, 1.5, 1.6)
cols <- list(base = base)
for (L in levs) {
  nl <- L*ens - (L-1)*shv_a       # 레버 L: 초과분 L-1을 무위험 차입비용 차감
  cols[[paste0("L", format(L,nsmall=1))]] <- nl
}
alln <- na.omit(do.call(cbind, cols))
colnames(alln) <- c("base", paste0("L",format(levs,nsmall=1)))

cat("===== 앙상블 고정레버 스윕 vs 원본 =====\n원본: CAGR 14.24 / SR 0.850 / MDD 22.83 / Calmar 0.624\n\n")
ss <- stratStats(alln)
print(round(ss,4))

cat("\n===== 요약(원본 대비 동시추월 판정) =====\n")
cat(sprintf("%-7s %7s %7s %7s %7s  %s\n","arm","CAGR","SR","MDD","Calmar","원본대비"))
for (cn in colnames(alln)) {
  cagr<-ss["Annualized Return",cn]; sr<-ss["Annualized Sharpe (Rf=0%)",cn]; mdd<-ss["MaxDD",cn]; cal<-ss["Calmar",cn]
  beats <- c(if(cagr>0.1424)"CAGR" else NA, if(sr>0.850)"SR" else NA, if(mdd<0.2283)"MDD" else NA, if(cal>0.624)"Calmar" else NA)
  beats <- paste(na.omit(beats), collapse="+")
  cat(sprintf("%-7s %6.1f%% %7.3f %6.1f%% %7.3f  %s\n", cn, cagr*100, sr, mdd*100, cal, beats))
}
cat("\n저장:", out_dir, "\n")
