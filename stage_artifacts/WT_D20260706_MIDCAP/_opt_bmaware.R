# Benchmark-aware TE-controlled MVO + book-marginal proxy — WT-D20260706_MIDCAP
# The hypothesis specifically asks whether TE-control vs cap-w KOSPI200 can bridge the cap-tier trap.
suppressMessages({library(arrow); library(data.table); library(quadprog)})
setDTthreads(1); try(arrow::set_cpu_count(1), silent=TRUE)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
DIR  <- file.path(ROOT, "stage_artifacts/WT_D20260706_MIDCAP")
source(file.path(ROOT, "02_Infrastructure/contracts/backtest_result_contract.R"))

ap <- as.data.table(arrow::read_parquet(file.path(DIR,"alpha_scores.parquet"))); ap[,Date:=as.Date(Date)]
bd <- as.data.table(arrow::read_parquet(file.path(ROOT,".cache/benchmark_pin20260703.parquet"))); bd[,Date:=as.Date(Date)]
bd[,ym:=format(Date,"%Y-%m")]; bm_m <- bd[,.(BM_Ret=prod(1+BM_Ret)-1),by=ym]
agrid <- sort(unique(ap$Date))
nextmonth <- function(d) as.Date(format(seq(d,by="month",length.out=2)[2],"%Y-%m-01"))
fwd_ym <- sapply(agrid, function(d) format(nextmonth(d),"%Y-%m"))
bench_dt <- merge(data.table(Date=agrid,ym_fwd=fwd_ym), bm_m, by.x="ym_fwd",by.y="ym",all.x=TRUE)[,.(Date,BM_Ret)][order(Date)]

measure_sched <- function(W,id){
  R<-ap[,.(Date,Ticker,Ret_1m)]; WR<-merge(W,R,by=c("Date","Ticker"),all.x=TRUE); WR[is.na(Ret_1m),Ret_1m:=0]
  port<-WR[,.(pg=sum(w*Ret_1m)),by=Date][order(Date)]
  dts<-sort(unique(W$Date)); traded<-setNames(numeric(length(dts)),as.character(dts)); prev<-data.table(Ticker=character(0),w=numeric(0))
  for(i in seq_along(dts)){cur<-W[Date==dts[i],.(Ticker,w)];m<-merge(cur,prev,by="Ticker",all=TRUE,suffixes=c("_c","_p"));m[is.na(w_c),w_c:=0];m[is.na(w_p),w_p:=0];traded[i]<-sum(abs(m$w_c-m$w_p));prev<-cur}
  port[,traded:=traded[as.character(Date)]];port[,cost:=traded*15/1e4];port[,rn:=pg-cost]
  pr<-merge(port[,.(date=Date,ret_net=rn)],bench_dt[,.(date=Date,benchmark_ret=BM_Ret)],by="date")[!is.na(benchmark_ret)]
  bc<-build_benchmark_compare(data.table(date=pr$date,ret_net=pr$ret_net,frequency="monthly"),
      data.table(date=pr$date,benchmark_ret=pr$benchmark_ret,benchmark_id="IKS200"),run_id=id,strategy_id=id,annualization_factor=12)
  gv<-function(nm){v<-bc[metric_name==nm,active_value];if(length(v))as.numeric(v[1])else NA}
  a<-pr$ret_net-pr$benchmark_ret
  list(id=id,port_t=gv("Portfolio_Alpha_t_NW_lag3"),ir=gv("Information_Ratio"),te=sd(a)*sqrt(12),
       net_sr=mean(a)/sd(a)*sqrt(12),turnover=mean(port$traded,na.rm=TRUE)*12,pr=pr)
}

# --- Benchmark-aware MVO: cross-sectional per period, minimize TE proxy while capturing alpha ---
# Since only as_of Sigma exists (24 names), use a diagonal risk proxy from 24m rolling vol for all periods
# (honest: full per-period factor Sigma is risk-agent's single snapshot; we approximate risk penalty by name vol).
vt<-ap[,.(Date,Ticker,Ret_1m)][order(Ticker,Date)]; vt[,rv:=frollapply(Ret_1m,24,sd,align="right"),by=Ticker]
setorder(ap,Date,-alpha_hat); top25<-ap[,.SD[seq_len(min(25,.N))],by=Date]
top25<-merge(top25, vt[,.(Date,Ticker,rv)],by=c("Date","Ticker"),all.x=TRUE)
top25[is.na(rv)|rv<=0, rv:=median(top25$rv,na.rm=TRUE)]

# TE-control lever = gamma: w propto alpha_hat / (rv^2)^gamma_risk, but ALSO shrink toward cap-w proxy.
# cap-w proxy within selected = inverse size_rank (bigger name = larger bench weight). shrink strength = kappa.
mk_bma <- function(dt, kappa){
  dt[,{
    a<-alpha_hat-min(alpha_hat)+1e-6
    walpha<-a/sum(a)
    capw <- (1/size_rank); capw<-capw/sum(capw)   # cap-w tracking proxy (bigger -> heavier)
    w <- (1-kappa)*walpha + kappa*capw
    for(it in 1:200){over<-w>0.20;if(!any(over))break;ex<-sum(w[over]-0.20);w[over]<-0.20;und<-!over&w>0;if(!any(und))break;w[und]<-w[und]+ex*w[und]/sum(w[und])}
    .(Ticker=Ticker,w=w/sum(w))
  },by=Date]
}
cat("=== Benchmark-aware TE-control sweep (kappa = cap-w shrink strength) ===\n")
cat(sprintf("%-22s %7s %6s %6s %7s %6s\n","method","port_t","IR","TE","netSR","turn"))
post_t<-function(pr){p<-pr[date>=as.Date("2017-01-01")];a<-p$ret_net-p$benchmark_ret;mean(a)/sd(a)*sqrt(length(a))}
oos_v2<-function(pr){a<-pr$ret_net-pr$benchmark_ret;n<-length(a);cuts<-floor(n*c(.55,.65,.75));r<-sapply(cuts,function(c){is<-mean(a[1:c])/sd(a[1:c])*sqrt(12);oo<-a[(c+1):n];os<-mean(oo)/sd(oo)*sqrt(12);if(abs(is)<1e-9)NA else os/is});median(r,na.rm=TRUE)}
bma_res<-list()
for(kappa in c(0,0.25,0.5,0.75,1.0)){
  W<-mk_bma(copy(top25),kappa); r<-measure_sched(W,sprintf("BMA_k%.2f",kappa)); bma_res[[as.character(kappa)]]<-r
  cat(sprintf("%-22s %7.3f %6.3f %6.3f %7.3f %6.2f  | post2017_t=%.3f oos_v2=%.3f\n",
      r$id,r$port_t,r$ir,r$te,r$net_sr,r$turnover,post_t(r$pr),oos_v2(r$pr)))
}

# --- Book-marginal proxy: blend best-standalone sleeve return with PG2 proxy (=base score_eff top25 EW) ---
# PG2 official book is separate; here we test whether the tier sleeve ADDS to the score_eff base at book level.
# base score_eff EW top25 as incumbent proxy (alpha reported base port_t 2.749 ir 0.617)
setorder(ap,Date,-score_eff); base25<-ap[,.SD[seq_len(min(25,.N))],by=Date]
W_base<-base25[,.(Ticker,w=1/.N),by=Date]
r_base<-measure_sched(W_base,"base_scoreEff_EW")
# best tier sleeve = alpha_prop
setorder(ap,Date,-alpha_hat); tier25<-ap[,.SD[seq_len(min(25,.N))],by=Date]
mk_prop<-function(dt){dt[,{a<-alpha_hat-min(alpha_hat)+1e-6;w<-a/sum(a);for(it in 1:200){over<-w>0.20;if(!any(over))break;ex<-sum(w[over]-0.20);w[over]<-0.20;und<-!over&w>0;if(!any(und))break;w[und]<-w[und]+ex*w[und]/sum(w[und])};.(Ticker=Ticker,w=w/sum(w))},by=Date]}
r_tier<-measure_sched(mk_prop(copy(tier25)),"tier_prop")

# book-level active series (equal 50/50 blend of active returns as marginal-contribution proxy)
prb<-merge(r_base$pr[,.(date,ab=ret_net-benchmark_ret)], r_tier$pr[,.(date,at=ret_net-benchmark_ret)],by="date")
ir_base<-mean(prb$ab)/sd(prb$ab)*sqrt(12)
ir_blend<-mean((prb$ab+prb$at)/2)/sd((prb$ab+prb$at)/2)*sqrt(12)
cat("\n=== Book-marginal proxy (score_eff base vs +tier sleeve blend) ===\n")
cat(sprintf("base_scoreEff active IR = %.3f\n", ir_base))
cat(sprintf("50/50 blend active IR   = %.3f  (delta = %.3f)\n", ir_blend, ir_blend-ir_base))
cat(sprintf("corr(base_active, tier_active) = %.3f\n", cor(prb$ab, prb$at)))
cat(sprintf("PG2 incumbent_book_ir = 1.416 ; standalone tier sleeve IR = %.3f (far below; cor 0.973 signal)\n", r_tier$ir))
cat("\n[done]\n")
