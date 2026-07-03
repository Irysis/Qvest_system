#=============================================================================#
# 앙상블 + Vol-Target — CAGR·SR 동시 원본 추월 검증 (dvfs_voltarget)
# 앙상블(0.5*base+0.25*RP+0.25*GEM)은 SR/MDD 우수하나 vol 축소로 CAGR 희생.
# rolling vol-target(직전 63일 vol → 레버=target/vol, PIT)로 vol을 원본 수준(16.75%)
# 까지 스케일 → CAGR 회복. 레버리지 비용은 SHV(무위험) 금리 차감으로 근사(보수적).
#=============================================================================#
suppressMessages(pacman::p_load("quantmod","PerformanceAnalytics","xts","tidyverse"))
qm_root <- Sys.getenv("QM_ROOT", unset="C:/Users/99922/OneDrive/Quant_Module_Moltbot")
out_dir <- file.path(qm_root,"04_Research","dvaa_dvfs_revalidation")

nets <- readRDS(file.path(out_dir,"paradigm_nets.rds"))
base <- nets$base; rp <- nets$rp; gem <- nets$gem
shv <- na.omit(Return.calculate(Ad(getSymbols('SHV',src='yahoo',from='2007-01-01',auto.assign=FALSE))))  # 무위험 근사(차입금리)

ens <- na.omit(0.5*base + 0.25*rp + 0.25*gem); colnames(ens)<-"ens"
target_vol <- 0.1675   # 원본 vol

# rolling vol-target (PIT: 직전 63일 vol로 당일 레버 결정)
rv <- rollapply(ens, width=63, FUN=sd, align="right")*sqrt(252)
lev <- target_vol / rv
lev <- lag.xts(lev, 1)             # 직전 정보만 (look-ahead 차단)
lev[is.na(lev)] <- 1; lev[lev>2.5] <- 2.5; lev[lev<0.3] <- 0.3   # 레버 cap [0.3, 2.5]
shv_a <- as.numeric(merge(ens, shv, join='left')[,2]); shv_a[is.na(shv_a)] <- 0
# 레버리지 수익 = lev*ens - (lev-1)*무위험(차입비용)
ens_vt <- as.numeric(lev)*ens - (as.numeric(lev)-1)*shv_a; colnames(ens_vt)<-"ens_voltarget"

stratStats <- function(x){s<-rbind(table.AnnualizedReturns(x),maxDrawdown(x));s[5,]<-s[1,]/s[4,];s[6,]<-s[1,]/UlcerIndex(x);rownames(s)[4:6]<-c("MaxDD","Calmar","UlcerPI");s}
cmp <- na.omit(cbind(base, ens, ens_vt)); colnames(cmp)<-c("base(원본)","ensemble","ens_voltarget")

cat("===== 원본 vs 앙상블 vs 앙상블+VolTarget =====\n원본: CAGR 14.24 / SR 0.850 / MDD 22.83 / Calmar 0.624\n\n")
print(round(stratStats(cmp),4))
cat("\n평균 레버리지:", round(mean(as.numeric(lev),na.rm=TRUE),2), " 범위:[", round(min(as.numeric(lev)),2),",",round(max(as.numeric(lev)),2),"]\n")
cat("\n연도별 수익률(%):\n")
yr <- apply.yearly(cmp, Return.cumulative)*100; rownames(yr)<-format(index(yr),"%Y"); print(round(yr,1))
cat("\n2008 GFC:", round(as.numeric(Return.cumulative(cmp["2008-01/2009-06","ens_voltarget"]))*100,1),
    "% / 2022:", round(as.numeric(Return.cumulative(cmp["2022","ens_voltarget"]))*100,1),"% (원본 2008 +15.2/2022 -9.3)\n")
saveRDS(ens_vt, file.path(out_dir,"dvfs_voltarget_net.rds"))
cat("\n저장:", out_dir, "\n")
