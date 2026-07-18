# WT-D20260718_002 — Self-adversarial robustness: alternative sell-intensity definitions
# Preempts "signal definition" challenge. Same L=6 P=10% exclusion frame, 3 alt definitions:
#   (1) net value/mcap   [primary, already done]
#   (2) GROSS sell value/mcap (qty<0 only, ignore offsetting insider buys)
#   (3) seller BREADTH   (# distinct officer 장내매도 reports over L=6)
#   (4) net SHARES/shares_out proxy (net qty / (mcap/price_avg))  -- use net value already ~ this
suppressWarnings(suppressMessages({library(arrow); library(data.table)}))
setDTthreads(1)
R <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
OUT <- file.path(R, "stage_artifacts/WT_D20260718_002")
source(file.path(R, "02_Infrastructure/contracts/canonical_screen_bt.R"))
if (!exists(".nw_t_mean", mode="function")) source(file.path(R,"02_Infrastructure/contracts/backtest_result_contract.R"))
INSDIR <- file.path(R, ".cache/dart/insider_backfill")

base <- as.data.table(arrow::read_parquet(file.path(OUT,"base_panel.parquet")))
bench<- as.data.table(arrow::read_parquet(file.path(OUT,"bench_panel.parquet")))
ym_date <- as.data.table(arrow::read_parquet(file.path(OUT,"ym_date_map.parquet")))
returns_dt<-base[,.(Date,Ticker,Ret_1m)]; bench_dt<-bench[,.(Date,BM_Ret)]
liq_dt<-base[,.(Date,Ticker,adv)]; size_dt<-base[,.(Date,Ticker,Size)]
base_scores<-base[,.(Date,Ticker,score=mom_score)]

# reload insider raw, build alt monthly signals (officer, on-market)
csvs<-sort(list.files(INSDIR,pattern=glob2rx("*.csv"),full.names=TRUE))
ins<-rbindlist(lapply(csvs,function(f) fread(f,colClasses=list(character="corp_code"),showProgress=FALSE)),fill=TRUE)
ins[,Ticker:=paste0("A",formatC(as.integer(corp_code),width=6,flag="0"))]
ins[,qty_change:=suppressWarnings(as.numeric(qty_change))]; ins[,price:=suppressWarnings(as.numeric(price))]
ins[,is_officer:=(tolower(as.character(is_officer))%in%c("true","t","1"))]
ins[,rcept_dt:=as.character(rcept_dt)]; ins[,sig_ym:=paste0(substr(rcept_dt,1,4),"-",substr(rcept_dt,5,6))]
ins[,on_market:=grepl("장내",report_reason,fixed=TRUE)]
ins<-ins[on_market==TRUE & is_officer==TRUE & !is.na(qty_change)&!is.na(price)&is.finite(qty_change*price)]
ins[,tv:=qty_change*price]
# monthly aggregates
mk<-function(ym) as.integer(substr(ym,1,4))*12L+as.integer(substr(ym,6,7))
agg<-ins[,.(gross_sell=-sum(pmin(tv,0)), n_sell=sum(qty_change<0), netv=sum(tv)),by=.(Ticker,sig_ym)]
agg[,midx:=mk(sig_ym)]
forms<-sort(unique(mk(ym_date$ym)))
roll<-function(col,L){
  tick<-unique(agg$Ticker); allm<-seq(min(forms)-11L,max(forms))
  g<-merge(CJ(Ticker=tick,midx=allm),agg[,c("Ticker","midx",col),with=FALSE],by=c("Ticker","midx"),all.x=TRUE)
  setnames(g,col,"v"); g[is.na(v),v:=0]; setorder(g,Ticker,midx)
  g[,s:=frollsum(v,L,align="right"),by=Ticker]; g[midx%in%forms,.(Ticker,t=midx,s)]
}
L<-6L
gs<-roll("gross_sell",L); setnames(gs,"s","gross_sell"); ns<-roll("n_sell",L); setnames(ns,"s","n_sell")
sig<-merge(gs,ns,by=c("Ticker","t")); sig<-merge(sig,ym_date[,.(t=mk(ym),ym,Date)],by="t")
B<-merge(base,sig[,.(ym,Ticker,gross_sell,n_sell)],by=c("ym","Ticker"),all.x=TRUE)
B[is.na(gross_sell),gross_sell:=0]; B[is.na(n_sell),n_sell:=0]
B[,si_gross:=gross_sell/Size]     # gross sell intensity (ignore offsetting buys)
B[,si_breadth:=as.numeric(n_sell)] # count of sell reports

run_arm<-function(sd,rid) canonical_screen_bt(sd,returns_dt,bench_dt,top_n=25L,cost_bps_oneway=15,
  liq_dt=liq_dt,liq_min=2e8,run_id=rid,strategy_id=rid,periods_per_year=12L,diag_dual_basis=FALSE)
A<-run_arm(base_scores,"base"); pa<-as.data.table(A$period_returns)[,.(date,ret_net_A=ret_net,bench=benchmark_ret)]
excl<-function(col,P){x<-B[in_univ==1L,.(Date,Ticker,si=get(col))];x[,n:=.N,by=Date]
  x[,rk:=frank(-si,ties.method="min"),by=Date];x[,thr:=pmax(1L,ceiling(P/100*n))];x[si>0&rk<=thr,.(Date,Ticker)]}
paired<-function(col,P,tag){ex<-excl(col,P);keep<-fsetdiff(base_scores[,.(Date,Ticker)],ex)
  sd<-merge(keep,base_scores,by=c("Date","Ticker"));Bt<-run_arm(sd,tag)
  pb<-as.data.table(Bt$period_returns)[,.(date,ret_net_B=ret_net)];m<-merge(pa,pb,by="date")
  m[,diff:=(ret_net_B-bench)-(ret_net_A-bench)]
  cat(sprintf("[%s] port_t_B=%.3f (A=%.3f) paired_diff_ann=%.4f paired_t_nw3=%.3f avg_excl/mo=%.1f\n",
    tag,Bt$portfolio_alpha_t_nw_lag3,A$portfolio_alpha_t_nw_lag3,mean(m$diff)*12,.nw_t_mean(m$diff,lag=3),
    nrow(ex)/uniqueN(ex$Date)))}
cat("=== Alt intensity definitions (officer, L=6, P=10%) ===\n")
paired("si_gross",10,"gross_sell_p10")
paired("si_breadth",10,"seller_breadth_p10")
# also stricter P=20 for gross
paired("si_gross",20,"gross_sell_p20")
cat("[DONE] intensity robustness\n")
