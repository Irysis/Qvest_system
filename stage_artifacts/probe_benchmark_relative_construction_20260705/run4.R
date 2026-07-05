# run4.R — final controls: (i) benchmark reconstruction sanity, (ii) anchor marginal vs plain alpha,
# (iii) why A1(2 anchors) specifically, (iv) recent2017 robustness of the winner.
suppressMessages({library(arrow); library(data.table); library(jsonlite)})
setDTthreads(1); arrow::set_cpu_count(1)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
SA<-file.path(ROOT,"stage_artifacts","WT-D20260705_004"); OUT<-file.path(ROOT,"stage_artifacts","probe_benchmark_relative_construction_20260705")
source(file.path(ROOT,"02_Infrastructure","contracts","backtest_result_contract.R"))
source(file.path(ROOT,"02_Infrastructure","contracts","weighted_screen_bt.R"))
set.seed(20260705L); ym2date<-function(y)as.Date(paste0(y,"-01"))
pan<-as.data.table(read_parquet(file.path(SA,"alpha_scores.parquet"))); yms<-sort(unique(pan$ym))
bw<-readRDS(file.path(OUT,"benchmark_weights.rds"))
bm<-as.data.table(read_parquet(file.path(ROOT,".cache","benchmark.parquet"))); bm[,ym:=format(as.Date(Date),"%Y-%m")];bm<-bm[!is.na(BM_Ret)]
bm_lr<-bm[,.(lr=sum(log1p(BM_Ret))),by=ym][order(ym)];bm_lr[,bm_fwd:=expm1(shift(lr,type="lead",n=1L))]
benchdt<-bm_lr[!is.na(bm_fwd),.(Date=ym2date(ym),BM_Ret=bm_fwd)]
rets<-pan[,.(Date=ym2date(ym),Ticker,Ret_1m=F1)]; CAP<-0.20;NMAX<-25L;BPS<-15
cap_project<-function(w,cap=CAP){w[w<0]<-0;if(sum(w)<=0)return(w);w<-w/sum(w);for(it in 1:100){over<-w>cap+1e-12;if(!any(over))break;ex<-sum(w[over]-cap);w[over]<-cap;un<-!over&w>0;if(!any(un))break;w[un]<-w[un]+ex*w[un]/sum(w[un])};w/sum(w)}
run_bt<-function(wd,tag,sf=NULL){d<-copy(wd);if(!is.null(sf))d<-d[Date>=as.Date(sf)];weighted_screen_bt(d,rets,benchdt,cost_bps_oneway=BPS,run_id=tag,strategy_id=tag)}
PT<-function(r)r$portfolio_alpha_t_nw_lag3

# (i) Benchmark reconstruction sanity: hold b_i exactly (cap-weight, no cap/no truncation) -> realized active ~ 0?
bexact <- bw[, .(ym, Date=ym2date(ym), Ticker, w=b)]
rb <- run_bt(bexact[,.(Date,Ticker,w)], "BENCH_HOLD")
cat(sprintf("(i) BENCH reconstruction: hold b_i -> active PORT_t=%.3f mean_active=%.5f/mo (want ~0; measures reconstruction vs true BM_Ret)\n",
            PT(rb), rb$mean_active_net))

# (ii) Anchor marginal: does anchoring ADD over plain alpha top-25 EW (BASE)? Build:
#   ALPHA25_ew = BASE (0.97). ANCHOR2 = A1 (2.68). Marginal = 2.68-0.97.
#   But is the anchor's value just from CONCENTRATING alpha winners that happen to be mega-cap?
#   Control: ALPHA_capweighted top-25 (weight top-25 alpha by their b, cap 20%) - lets mega-cap alpha winners
#            get big weight WITHOUT forcing size anchor.
setorder(pan, ym, -mu_hat)
alpha_capw <- rbindlist(lapply(yms, function(y){
  d<-merge(pan[ym==y,.(Ticker,mu_hat)], bw[ym==y,.(Ticker,b)], by="Ticker", all.x=TRUE)
  d[is.na(b),b:=min(bw[ym==y]$b,na.rm=TRUE)]; setorder(d,-mu_hat); d25<-head(d,25L)
  d25[, w:=cap_project(b)]; d25[w>0,.(ym=y,Date=ym2date(y),Ticker,w)] }))
r_acw <- run_bt(alpha_capw[,.(Date,Ticker,w)], "ALPHA_CAPW")
r_acw_rec <- run_bt(alpha_capw[,.(Date,Ticker,w)], "ALPHA_CAPW_rec", sf="2017-01-01")
cat(sprintf("(ii) ALPHA top-25 CAP-WEIGHTED (no forced anchor): full=%.3f rec2017=%.3f\n", PT(r_acw), PT(r_acw_rec)))

# (iii) alpha-fill top-25 but force top-2 SIZE names INTO the held set at their cap-weight (not forced 20%):
#   isolates 'must-hold mega-cap' vs 'must-hold at 20%'.
alpha_plus_megacap <- rbindlist(lapply(yms, function(y){
  bb<-bw[ym==y][order(-Size)]; if(nrow(bb)<3) return(NULL)
  anchors<-head(bb$Ticker,2)
  d<-merge(pan[ym==y,.(Ticker,mu_hat)], bw[ym==y,.(Ticker,b)], by="Ticker",all.x=TRUE)
  d[is.na(b),b:=0]; setorder(d,-mu_hat)
  fill<-head(d[!Ticker %in% anchors]$Ticker,23L)
  tk<-c(anchors,fill)
  # weight: anchors at their b (capped 20), fill EW of remainder
  ab<-bw[ym==y][Ticker %in% anchors]$b; ab<-pmin(ab,0.20)
  fw<-rep((1-sum(ab))/23,23); w<-cap_project(c(ab,fw))
  data.table(ym=y,Date=ym2date(y),Ticker=tk,w=w)[w>0] }))
r_apm <- run_bt(alpha_plus_megacap[,.(Date,Ticker,w)], "ALPHA_MEGACAP_natwt")
r_apm_rec <- run_bt(alpha_plus_megacap[,.(Date,Ticker,w)], "ALPHA_MEGACAP_natwt_rec", sf="2017-01-01")
cat(sprintf("(iii) ALPHA-fill + mega-cap held at NATURAL cap-wt(<=20): full=%.3f rec2017=%.3f\n", PT(r_apm), PT(r_apm_rec)))

# (iv) winner robustness: subperiod PORT_t for A1 (pre2017 vs post2017) + placebo already done.
build_a1<-function(){rbindlist(lapply(yms,function(y){bb<-bw[ym==y][order(-Size)];mm<-pan[ym==y,.(Ticker,mu_hat)]
  if(nrow(bb)<3)return(NULL);anchors<-head(bb$Ticker,2);pool<-mm[!Ticker%in%anchors];setorder(pool,-mu_hat)
  ft<-head(pool$Ticker,23L);w<-cap_project(c(rep(0.20,2),rep(0.60/23,23)));data.table(ym=y,Date=ym2date(y),Ticker=c(anchors,ft),w=w)[w>0]}))}
a1<-build_a1()
r_pre<-run_bt(a1[Date<as.Date("2017-01-01"),.(Date,Ticker,w)],"A1_pre")
r_post<-run_bt(a1[Date>=as.Date("2017-01-01"),.(Date,Ticker,w)],"A1_post")
cat(sprintf("(iv) A1 winner subperiods: pre2017 PORT_t=%.3f (n=%d) | post2017=%.3f (n=%d)\n",
            PT(r_pre),r_pre$n_months,PT(r_post),r_post$n_months))
# oos_retention proxy: post/pre net_sr ratio (anchored, informal)
cat(sprintf("     A1 net_sr pre=%.3f post=%.3f (retention-ish=%.2f)\n", r_pre$net_sr, r_post$net_sr,
            ifelse(r_pre$net_sr>0, r_post$net_sr/r_pre$net_sr, NA)))

saveRDS(list(bench_hold=rb, alpha_capw=list(r_acw,r_acw_rec), alpha_megacap=list(r_apm,r_apm_rec),
             a1_sub=list(pre=r_pre,post=r_post)), file.path(OUT,"phase4_controls.rds"))
cat("SAVED phase4_controls.rds\n")
