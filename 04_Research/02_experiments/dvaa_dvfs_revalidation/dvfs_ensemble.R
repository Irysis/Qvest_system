#=============================================================================#
# DVFS 앙상블 1차 분석 — 기존 변형 조합 (상관 + 조합 성과)
# 원본(remeasure) + idx + turb(확인필터) + dcc 의 net을 조합. 상관행렬로 분산효과 판정.
# 고상관이면 → 독립 패러다임 전략(RP/듀얼모멘텀) 필요 결론.
#=============================================================================#
suppressMessages(pacman::p_load("quantmod","PerformanceAnalytics","xts","tidyverse"))
qm_root <- Sys.getenv("QM_ROOT", unset="C:/Users/99922/OneDrive/Quant_Module_Moltbot")
out_dir <- file.path(qm_root,"04_Research","dvaa_dvfs_revalidation")

# 원본 청정 기준선 net 생성 (remeasure 로직 실행)
cat("=== 원본(remeasure) net 생성 중... ===\n")
source(file.path(out_dir,'dvfs_remeasure.R'))
net_base <- VAA_DVFS_ETF$net; colnames(net_base) <- "base"
saveRDS(net_base, file.path(out_dir,"dvfs_remeasure_net.rds"))

# 변형 net 로드
idx_net  <- readRDS(file.path(out_dir,"dvfs_idx_net.rds"));  colnames(idx_net)<-"idx"
turb_net <- readRDS(file.path(out_dir,"dvfs_turb_net.rds")); colnames(turb_net)<-"turb"
dcc_net  <- readRDS(file.path(out_dir,"dvfs_dcc_net.rds"));  colnames(dcc_net)<-"dcc"

nets <- na.omit(cbind(net_base, idx_net, turb_net, dcc_net))
spy  <- na.omit(Return.calculate(Ad(getSymbols('SPY',src='yahoo',from='2007-01-01',auto.assign=FALSE)))); colnames(spy)<-"SPY"

stratStats <- function(x){s<-rbind(table.AnnualizedReturns(x),maxDrawdown(x));s[5,]<-s[1,]/s[4,];s[6,]<-s[1,]/UlcerIndex(x);rownames(s)[4:6]<-c("MaxDD","Calmar","UlcerPI");s}

cat("\n===== 변형 간 상관행렬 (월 수익) =====\n")
print(round(cor(apply.monthly(nets, Return.cumulative)), 3))

# 조합 (동일가중)
ens_all    <- xts(rowMeans(nets),                         order.by=index(nets)); colnames(ens_all)<-"ens_all4"
ens_no_dcc <- xts(rowMeans(nets[,c("base","idx","turb")]),order.by=index(nets)); colnames(ens_no_dcc)<-"ens_no_dcc"
ens_bt     <- xts(rowMeans(nets[,c("base","turb")]),      order.by=index(nets)); colnames(ens_bt)<-"ens_base_turb"

cmp <- na.omit(cbind(nets[,"base"], ens_all, ens_no_dcc, ens_bt, spy))
colnames(cmp) <- c("base(원본)","ens_all4","ens_no_dcc","ens_base+turb","SPY")
cat("\n===== 원본 단독 vs 앙상블 조합 =====\n원본: CAGR 14.30 / SR 0.854 / MDD 22.83 / Calmar 0.626\n\n")
print(round(stratStats(cmp), 4))
cat("\n저장:", out_dir, "\n")
