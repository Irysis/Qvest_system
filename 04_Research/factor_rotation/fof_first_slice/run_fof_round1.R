## run_fof_round1.R — 다양한 구성방법론 Round 1 (도훈 mandate: 반복 다중-방법론 리서치)
## baseline = integrated group_avg(~1.1, 직전 천장). 목표 = 유의 초과(졸업 향).
## 교훈 반영: 11군-단순평균이 강한 개별팩터 희석 → granularity(개별/IC가중/best-of-group) × combination(linear/interaction).
## 전부 canonical_screen_bt 동일하네스(공정). per-factor causal trailing-IC(12m) 사용(PIT).
suppressPackageStartupMessages({library(data.table); library(arrow); library(sandwich); library(lmtest)})
setDTthreads(1); try(arrow::set_io_thread_count(1), silent=TRUE)
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
source("02_Infrastructure/contracts/canonical_screen_bt.R")
OUT <- "04_Research/factor_rotation/fof_first_slice"
con <- file(file.path(OUT,"_fof_round1.txt"),"w",encoding="UTF-8"); w<-function(...) writeLines(paste0(...),con)
fam_of <- function(fid){ p<-toupper(substr(fid,1,2)); p1<-substr(p,1,1)
  if(p1=="V")"Value" else if(p1=="M"&&p!="MA")"Momentum" else if(p1=="Q")"Quality" else if(p1=="D")"LowRisk"
  else if(p1=="L")"Size_Liquidity" else if(p1=="S"&&p!="SE")"Size_Liquidity" else if(p1=="R")"Reversal"
  else if(p=="GR")"Growth_Profit" else if(p=="AC")"Accruals" else if(p1=="C"&&p!="CR")"Consensus"
  else if(p=="CR")"Credit" else if(p=="IN")"Growth_Profit" else if(p=="XF")"Composite" else if(p=="MA")"Macro"
  else if(p=="TR")"Size_Liquidity" else "Composite" }
w("================ Round 1 — 다양한 구성방법론 ================"); w(sprintf("실행 %s", as.character(Sys.time())))

## ── 데이터 ──
sc <- as.data.table(read_parquet("outputs/ramp/pure_factor_scores.parquet",
        col_select=c("signal_date","security_id","factor_id","neutralized_z")))
setnames(sc,"neutralized_z","nz"); sc[, signal_date:=as.Date(signal_date)]
sc[, grp:=sapply(factor_id, fam_of)]; sc <- sc[grp!="Macro"]
bo<-readRDS(".cache/_bo_fwdgic.rds"); fwd<-bo$fwd
ret_dt<-as.data.table(fwd$returns_dt)[,.(Date=as.Date(Date),Ticker,Ret_1m)]
bench_dt<-as.data.table(fwd$bench_dt)[,.(Date=as.Date(Date),BM_Ret)]
liq_dt<-as.data.table(fwd$liq_dt)[,.(Date=as.Date(Date),Ticker,adv)]

## ── per-factor causal trailing-IC (12m) ── (캐시)
icf <- file.path(OUT,"_factor_ic.rds")
if(file.exists(icf)){ FIC<-readRDS(icf) } else {
  m <- merge(sc[,.(Date=signal_date,Ticker=security_id,factor_id,nz)], ret_dt, by=c("Date","Ticker"))
  FIC <- m[, .(ic = if(.N>=15 && sd(nz,na.rm=T)>0 && sd(Ret_1m,na.rm=T)>0) cor(nz,Ret_1m,method="spearman",use="complete.obs") else NA_real_),
           by=.(Date, factor_id)]
  setorder(FIC, factor_id, Date)
  FIC[, t_ic := shift(frollmean(ic, 12L, na.rm=TRUE), 1L), by=factor_id]   # trailing 12m, 현재월 제외(PIT)
  saveRDS(FIC, icf)
}
w(sprintf("factor IC: %d (factor×month), 평균 t_ic 가용월=%d", nrow(FIC), sum(!is.na(FIC$t_ic))))
sc <- merge(sc, FIC[,.(signal_date=Date, factor_id, t_ic)], by=c("signal_date","factor_id"), all.x=TRUE)

## ── canonical_screen_bt 러너 ──
run_sc <- function(sdt, id, topn=25L) canonical_screen_bt(
  scores_dt=sdt[,.(Date=as.Date(signal_date),Ticker=security_id,score)],
  returns_dt=ret_dt, bench_dt=bench_dt, top_n=topn, cost_bps_oneway=15, liq_dt=liq_dt, liq_min=2e8, run_id=id, strategy_id=id)
zc <- function(x){ s<-sd(x,na.rm=T); if(is.na(s)||s<1e-9) x-mean(x,na.rm=T) else (x-mean(x,na.rm=T))/s }

## ── 구성방법론 builders → score_dt(signal_date, security_id, score) ──
# C1 group_avg: 군별 nz평균 → 군간 평균 (현 baseline)
b_group_avg <- function(){ g<-sc[,.(gz=mean(nz,na.rm=T)),by=.(signal_date,security_id,grp)]
  g[,gz:=zc(gz),by=.(signal_date,grp)]; g[,.(score=mean(gz,na.rm=T)),by=.(signal_date,security_id)] }
# C2 ic_weighted_global: 전 팩터 max(t_ic,0) 가중 합성 (개별 granularity)
b_ic_weighted <- function(){ x<-sc[is.finite(t_ic)]; x[,wf:=pmax(t_ic,0)]
  x[, .(score=if(sum(wf)>0) sum(wf*nz)/sum(wf) else mean(nz)), by=.(signal_date,security_id)] }
# C3/C4 top-K 팩터(월별 t_ic 상위) EW
b_topK <- function(K){ ord<-unique(sc[is.finite(t_ic),.(signal_date,factor_id,t_ic)])
  ord[, rk:=frank(-t_ic,ties.method="first"), by=signal_date]; keepf<-ord[rk<=K,.(signal_date,factor_id)]
  x<-merge(sc, keepf, by=c("signal_date","factor_id")); x[,.(score=mean(nz,na.rm=T)),by=.(signal_date,security_id)] }
# C5 best_per_group: 군별 t_ic 최고 팩터의 nz → 군간 평균
b_best_per_group <- function(){ ord<-unique(sc[is.finite(t_ic),.(signal_date,grp,factor_id,t_ic)])
  ord[, rk:=frank(-t_ic,ties.method="first"), by=.(signal_date,grp)]; bf<-ord[rk==1,.(signal_date,grp,factor_id)]
  x<-merge(sc, bf, by=c("signal_date","grp","factor_id")); x[,gz:=zc(nz),by=.(signal_date,grp)]
  x[,.(score=mean(gz,na.rm=T)),by=.(signal_date,security_id)] }
# C6 within_group_ic: 군내 t_ic 가중 → 군간 평균
b_within_ic <- function(){ x<-sc[is.finite(t_ic)]; x[,wf:=pmax(t_ic,0)]
  g<-x[,.(gz=if(sum(wf)>0) sum(wf*nz)/sum(wf) else mean(nz)),by=.(signal_date,security_id,grp)]
  g[,gz:=zc(gz),by=.(signal_date,grp)]; g[,.(score=mean(gz,na.rm=T)),by=.(signal_date,security_id)] }
# C7 interaction: top-20 IC팩터 중 nz 상위quintile 개수 (다팩터 종목 보상)
b_interaction <- function(K=20){ ord<-unique(sc[is.finite(t_ic),.(signal_date,factor_id,t_ic)])
  ord[, rk:=frank(-t_ic,ties.method="first"), by=signal_date]; keepf<-ord[rk<=K,.(signal_date,factor_id)]
  x<-merge(sc, keepf, by=c("signal_date","factor_id")); x[,q:=frank(nz)/.N, by=.(signal_date,factor_id)]
  x[,.(score=sum(q>=0.8,na.rm=T)+ mean(nz,na.rm=T)*1e-3),by=.(signal_date,security_id)] }  # 동점 tie-break 약한 nz

CFG <- list(
  C1_group_avg     = list(b=b_group_avg, topn=25L),
  C2_ic_weighted   = list(b=b_ic_weighted, topn=25L),
  C3_top20_ic      = list(b=function() b_topK(20L), topn=25L),
  C4_top8_ic       = list(b=function() b_topK(8L), topn=25L),
  C5_best_per_grp  = list(b=b_best_per_group, topn=25L),
  C6_within_grp_ic = list(b=b_within_ic, topn=25L),
  C7_interaction   = list(b=function() b_interaction(20L), topn=25L),
  C8_icw_sel15     = list(b=b_ic_weighted, topn=15L)   # 집중도(top-15 선택)
)

## ── 실행 ──
res <- list(); prs <- list()
for(nm in names(CFG)){ s<-CFG[[nm]]$b(); s[,score:=zc(score),by=signal_date]
  cs<-run_sc(s, nm, topn=CFG[[nm]]$topn); res[[nm]]<-cs
  prs[[nm]]<-as.data.table(cs$period_returns)[,.(date=as.Date(date), a=ret_net-benchmark_ret)] }
common <- Reduce(intersect, lapply(prs, function(x) as.character(x$date)))
ptest <- function(b,a){ A<-prs[[a]][as.character(date)%in%common]; B<-prs[[b]][as.character(date)%in%common]
  D<-merge(A,B,by="date"); D[,d:=a.y-a.x]; f<-lm(d~1,data=D)
  as.numeric(coeftest(f,vcov=sandwich::NeweyWest(f,lag=3,prewhite=FALSE))[1,3]) }
w("\n=== Round 1 실측 (canonical_screen_bt advisory, baseline=C1_group_avg) ===")
tab <- data.table()
for(nm in names(CFG)){ cs<-res[[nm]]; tt<-if(nm=="C1_group_avg") NA_real_ else ptest(nm,"C1_group_avg")
  tab<-rbind(tab, data.table(config=nm, port_t=cs$portfolio_alpha_t_nw_lag3, net_SR=cs$net_sr,
             IR=cs$information_ratio, TO=round(100*cs$turnover_annual), paired_t_vs_C1=tt))
  w(sprintf("  [%-16s] port_t=%+.2f | net_SR=%+.3f | IR=%+.3f | TO=%d%% | vs_C1 paired-t=%s",
    nm, cs$portfolio_alpha_t_nw_lag3, cs$net_sr, cs$information_ratio, round(100*cs$turnover_annual),
    ifelse(is.na(tt),"—",sprintf("%+.2f",tt)))) }
setorder(tab, -port_t)
w(sprintf("\n  → 최고 port_t: %s (%.2f), baseline C1=%.2f", tab$config[1], tab$port_t[1], tab[config=="C1_group_avg",port_t]))
fwrite(tab, file.path(OUT,"round1_results.csv")); saveRDS(list(tab=tab,res=res), file.path(OUT,"_fof_round1.rds"))
cat("ROUND1|", paste(sprintf("%s=%.2f", tab$config, tab$port_t), collapse=" "), "\n")
close(con); cat("FOF_ROUND1_DONE\n")
