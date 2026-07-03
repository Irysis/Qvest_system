## run_kns_phaseC.R — KNS 슈퍼팩터 계약등급 검증 (canonical 유니버스, 2005-01..2026-06).
## Phase B 스코어(L2 / PC-sparse) → canonical_screen_bt(top-25 long-only, 15bps delta, liq 2e8, NW lag-3)
## + 방화벽: holdout retention · placebo(월내 셔플) · subperiod · graduation 게이트(PORT_t 2.95/oos 0.7/calmar 0.64).
## 2026-06 holdings(top-25) 스냅샷 출력.
suppressPackageStartupMessages({library(data.table);library(arrow);library(sandwich);library(lmtest)})
setDTthreads(1); try(arrow::set_io_thread_count(1),silent=TRUE)
QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
source("02_Infrastructure/contracts/canonical_screen_bt.R")
OUT<-"04_Research/factor_rotation/fof_first_slice"
con<-file(file.path(OUT,"_kns_phaseC.txt"),"w",encoding="UTF-8"); w<-function(...) writeLines(paste0(...),con)
w("======== KNS 슈퍼팩터 계약등급 검증 (canonical 2005-01..2026-06) ========"); w(sprintf("실행 %s",as.character(Sys.time())))

ret_dt<-as.data.table(read_parquet(file.path(OUT,"kns_returns.parquet")))[,.(Date=as.Date(Date),Ticker,Ret_1m)][is.finite(Ret_1m)]
bench_dt<-as.data.table(read_parquet(file.path(OUT,"kns_bench.parquet")))[,.(Date=as.Date(Date),BM_Ret)][is.finite(BM_Ret)]
bench_dt<-bench_dt[Date %in% ret_dt$Date]   # 실현 창으로 제한 (holdings-only 월 벤치 NaN 제거)
liq_dt<-as.data.table(read_parquet(file.path(OUT,"kns_liq.parquet")))[,.(Date=as.Date(Date),Ticker,adv)][is.finite(adv)]
sr<-function(a) if(sd(a)>0) mean(a)/sd(a)*sqrt(12) else NA_real_
nwt<-function(v){ v<-v[is.finite(v)]; if(length(v)<8) return(NA_real_); f<-lm(v~1); as.numeric(coeftest(f,vcov=NeweyWest(f,lag=3,prewhite=FALSE))[1,3]) }

MAXR<-max(ret_dt$Date)   # 실현 창 상한 (2026-05-31). 2026-06 holdings-only 제외.
run_one<-function(tag,fn){
  supr_full<-as.data.table(read_parquet(file.path(OUT,fn)))[,.(Date=as.Date(Date),Ticker,score)]
  supr<-supr_full[Date<=MAXR & is.finite(score)]
  cs<-canonical_screen_bt(scores_dt=supr,returns_dt=ret_dt,bench_dt=bench_dt,top_n=25L,
                          cost_bps_oneway=15,liq_dt=liq_dt,liq_min=2e8,run_id=paste0("KNS_",tag),strategy_id=paste0("KNS_",tag))
  pr<-as.data.table(cs$period_returns); pr[,date:=as.Date(date)]; setorder(pr,date); pr[,act:=ret_net-benchmark_ret]
  port_t<-cs$portfolio_alpha_t_nw_lag3; net_sr<-cs$net_sr
  p18<-nwt(pr[date>=as.Date("2018-01-01")]$act); ppre<-nwt(pr[date<as.Date("2018-01-01")]$act)
  # calmar (net)
  nav<-cumprod(1+pr$ret_net); dd<-1-nav/cummax(nav); mdd<-max(dd); cg<-prod(1+pr$ret_net)^(12/nrow(pr))-1; calmar<-cg/mdd
  # holdout 마지막 20%
  n<-nrow(pr); cut<-floor(n*0.8); isv<-pr[1:cut]; ho<-pr[(cut+1):n]
  ret_reten<-sr(ho$act)/sr(isv$act)
  # placebo: 월내 score 셔플 x100 → 계약 port_t 분포
  set.seed(7); pl<-c()
  for(i in 1:100){ sp<-copy(supr); sp[,score:=sample(score),by=Date]
    csp<-tryCatch(canonical_screen_bt(scores_dt=sp,returns_dt=ret_dt,bench_dt=bench_dt,top_n=25L,cost_bps_oneway=15,liq_dt=liq_dt,liq_min=2e8,run_id="pl",strategy_id="pl"),error=function(e) NULL)
    if(!is.null(csp)) pl<-c(pl,csp$portfolio_alpha_t_nw_lag3) }
  pct<-100*mean(pl<port_t,na.rm=TRUE)
  w(sprintf("\n===== [%s] 계약등급 (canonical top-25 EW long-only) =====",tag))
  w(sprintf("  기간 %s..%s (%d월) | port_t_NWlag3=%+.2f | net_SR=%.2f | CAGR=%.1f%% | MDD=%.1f%% | calmar=%.2f",
            as.character(min(pr$date)),as.character(max(pr$date)),nrow(pr),port_t,net_sr,100*cg,100*mdd,calmar))
  w(sprintf("  subperiod: pre-2018 t=%+.2f | 2018+ t=%+.2f",ppre,p18))
  w(sprintf("  holdout(마지막20%%): IS active SR=%.2f | holdout=%.2f | retention=%.2f",sr(isv$act),sr(ho$act),ret_reten))
  w(sprintf("  placebo(월내셔플x%d): port_t %+.2f → %.0f%%ile (mean %.2f, p95 %.2f)",length(pl),port_t,pct,mean(pl,na.rm=T),quantile(pl,0.95,na.rm=T)))
  g1<-port_t>=2.95; g2<-!is.na(ret_reten)&&ret_reten>=0.7; g3<-!is.na(calmar)&&calmar>=0.64
  w(sprintf("  ★graduation HARD 3종: PORT_t≥2.95 [%s] | oos_retention≥0.7 [%s] | calmar≥0.64 [%s] → %s",
            ifelse(g1,"PASS","FAIL"),ifelse(g2,"PASS","FAIL"),ifelse(g3,"PASS","FAIL"),ifelse(g1&&g2&&g3,"자본 GRADUATION","미달(screen-tier)")))
  cat(sprintf("%s| port_t=%.2f net_SR=%.2f calmar=%.2f reten=%.2f placebo=%.0f%%ile p18=%.2f\n",tag,port_t,net_sr,calmar,ret_reten,pct,p18))
  list(cs=cs,pr=pr,supr=supr_full,port_t=port_t)
}
rL2<-run_one("L2","kns_scores_L2_canon.parquet")
rPC<-run_one("PCsparse","kns_scores_PCsparse_canon.parquet")

## 2026-06 holdings 스냅샷 (배포 후보 = 더 나은 변형)
best<-if(rL2$port_t>=rPC$port_t) rL2 else rPC; btag<-if(rL2$port_t>=rPC$port_t)"L2" else "PCsparse"
jun<-best$supr[Date==max(Date)][order(-score)][1:25]
jun<-merge(jun,liq_dt[Date==max(Date),.(Ticker,adv)],by="Ticker",all.x=TRUE)[order(-score)]
w(sprintf("\n===== 2026-06 top-25 holdings (배포후보 %s, EW 4%%씩) =====",btag))
for(i in 1:nrow(jun)) w(sprintf("  %2d. %-8s score=%+.3f adv=%.2e",i,jun$Ticker[i],jun$score[i],jun$adv[i]))
w(sprintf("\n[요약] 최고변형=%s port_t=%+.2f. KNS 원전 shrinkage를 KR canonical 유니버스 2005-2026.06에 충실 적용한 결과.",btag,best$port_t))
close(con); cat("KNS_PHASEC_DONE\n")
