#=============================================================================#
# 독립 패러다임 전략 + 원본 앙상블 (dvfs_paradigm)
# 원본 VAA-DVFS(추세·모멘텀 방어)와 다른 메커니즘 전략을 구현해 저상관 조합 시도.
#  - RP : 전 자산 inverse-vol 리스크패리티 (항상 분산, 방어 없음)
#  - GEM: 듀얼모멘텀 (주식 상대모멘텀 + 절대모멘텀 vs 현금, 아니면 채권)
# 각 net을 원본 net(dvfs_remeasure_net.rds)과 상관·조합 비교. 비용 20bps/leg 동일.
#=============================================================================#
suppressMessages(pacman::p_load("quantmod","PerformanceAnalytics","xts","tidyverse","magrittr","RiskPortfolios"))
qm_root <- Sys.getenv("QM_ROOT", unset="C:/Users/99922/OneDrive/Quant_Module_Moltbot")
out_dir <- file.path(qm_root,"04_Research","dvaa_dvfs_revalidation")

symbols <- c('SPY','QQQ','IWM','ACWX','EFA','EEM','IYR','GLD','PDBC','IEF','TLT','LQD','HYG','TIP','AGG','EMB','SHV')
getSymbols(symbols, src='yahoo', from='2007-01-01', auto.assign=TRUE)
price <- do.call(cbind, lapply(symbols, function(x) Ad(get(x)))) %>% setNames(symbols)
price <- na.locf(price)
rets  <- Return.calculate(price); rets <- rets[-1,]
ep <- endpoints(rets,'months'); N<-length(symbols)

mk_net <- function(wts_list){
  wdf <- do.call(rbind, lapply(wts_list, function(x) as.data.frame(x) %>% relocate(colnames(price))))
  ra <- rets; ra[is.na(ra)]<-0
  P <- Return.portfolio(ra, wdf, verbose=TRUE)
  to <- rowSums(abs(P$BOP.Weight - xts::lag.xts(P$EOP.Weight)), na.rm=TRUE); to[1]<-rowSums(abs(coredata(P$BOP.Weight)[1,,drop=FALSE]),na.rm=TRUE)
  P$returns - xts(to, order.by=index(P$BOP.Weight))*0.002
}

# --- RP: 전 자산 inverse-vol (252일) ---
run_rp <- function(){
  wts<-list()
  for(i in 13:length(ep)){
    win <- rets[max(1,ep[i]-251):ep[i], ]
    elig <- colnames(win)[colSums(is.na(win))==0]
    vols <- apply(win[,elig,drop=FALSE], 2, sd, na.rm=TRUE)
    w <- (1/vols)/sum(1/vols)
    wt <- setNames(rep(0,N),symbols); wt[elig]<-w
    wts[[i-12]] <- xts(t(wt), order.by=index(rets[ep[i]]))
  }
  mk_net(wts)
}

# --- GEM: 듀얼모멘텀 (주식 상대 + 절대 vs SHV, 아니면 AGG) ---
run_gem <- function(){
  risky<-c("SPY","ACWX","EFA","EEM"); safe<-"AGG"; cashr<-"SHV"
  wts<-list()
  for(i in 13:length(ep)){
    m12 <- as.numeric(Return.cumulative(rets[ep[i-12]:ep[i], c(risky,cashr)])); names(m12)<-c(risky,cashr)
    wt <- setNames(rep(0,N),symbols)
    if(isTRUE(max(m12[risky],na.rm=TRUE) > m12[cashr])){          # 절대모멘텀: 최고 주식 > 현금
      wt[names(which.max(m12[risky]))] <- 1                        # 상대모멘텀: 주식 중 최고
    } else wt[safe] <- 1                                           # 아니면 채권
    wts[[i-12]] <- xts(t(wt), order.by=index(rets[ep[i]]))
  }
  mk_net(wts)
}

cat("RP 실행...\n");  net_rp  <- run_rp();  colnames(net_rp)<-"RP"
cat("GEM 실행...\n"); net_gem <- run_gem(); colnames(net_gem)<-"GEM"
net_base <- readRDS(file.path(out_dir,"dvfs_remeasure_net.rds")); colnames(net_base)<-"base"

stratStats <- function(x){s<-rbind(table.AnnualizedReturns(x),maxDrawdown(x));s[5,]<-s[1,]/s[4,];s[6,]<-s[1,]/UlcerIndex(x);rownames(s)[4:6]<-c("MaxDD","Calmar","UlcerPI");s}
nets <- na.omit(cbind(net_base, net_rp, net_gem))

cat("\n===== 독립 전략 성과 + 원본 상관 =====\n")
print(round(stratStats(nets),4))
cat("\n상관행렬(월):\n"); print(round(cor(apply.monthly(nets,Return.cumulative)),3))

# 조합 (원본 비중을 높게 — 원본이 최강이므로): 70/30, 50/50
combos <- cbind(
  base = nets[,"base"],
  b70_rp30  = 0.7*nets[,"base"]+0.3*nets[,"RP"],
  b70_gem30 = 0.7*nets[,"base"]+0.3*nets[,"GEM"],
  b50_rp25_gem25 = 0.5*nets[,"base"]+0.25*nets[,"RP"]+0.25*nets[,"GEM"],
  b60_gem40 = 0.6*nets[,"base"]+0.4*nets[,"GEM"]
)
cat("\n===== 원본 vs 독립 패러다임 조합 =====\n원본: CAGR 14.27 / SR 0.852 / MDD 22.83 / Calmar 0.625\n\n")
print(round(stratStats(na.omit(combos)),4))
cat("\n저장:", out_dir, "\n")
saveRDS(list(base=net_base,rp=net_rp,gem=net_gem), file.path(out_dir,"paradigm_nets.rds"))
