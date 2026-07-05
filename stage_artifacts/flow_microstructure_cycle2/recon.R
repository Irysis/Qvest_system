suppressPackageStartupMessages({library(data.table); library(arrow)}); setDTthreads(1L)
PR<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; OUT<-file.path(PR,"stage_artifacts/flow_microstructure_cycle2")
CH<-file.path(PR,"04_Research/composition_search/cycle1_trackS/invz_chunks")
source(file.path(PR,"02_Infrastructure/contracts/backtest_result_contract.R"))
source(file.path(PR,"02_Infrastructure/contracts/canonical_screen_bt.R"))
rp<-function(f) as.data.table(read_parquet(file.path(OUT,f)))
returns_dt<-rp("returns_dt.parquet"); returns_dt[,Date:=as.Date(Date)]
bench_dt<-rp("bench_dt.parquet"); bench_dt[,Date:=as.Date(Date)]
me_uni<-rp("me_uni.parquet"); me_uni[,Date:=as.Date(Date)]
ym2date<-unique(me_uni[,.(ym,Date)])
sig<-sort(ym2date$ym); sig<-sig[sig>="200501" & sig<="202603"]
FZ<-rbindlist(lapply(sig,function(m){p<-file.path(CH,paste0("invz_",m,".parquet")); if(file.exists(p)) as.data.table(read_parquet(p)) else NULL}),fill=TRUE)
facs<-c("INV02_Foreign_NetBuy_60d","INV04_Inst_NetBuy_60d","INV09_Flow_Persistence","INV11_Foreign_Concentration","INV07_Retail_Contrarian")
CW<-dcast(FZ[Factor_Name %in% facs], ym+Ticker~Factor_Name, value.var="Z")
fcols<-intersect(facs,names(CW)); CW[,raw_mean:=rowMeans(.SD,na.rm=TRUE),.SDcols=fcols]; CW<-CW[is.finite(raw_mean)]
CW[,score:=-1*raw_mean]; CW[,score:=(score-mean(score,na.rm=TRUE))/sd(score,na.rm=TRUE),by=ym]
sdt<-merge(CW[,.(ym,Ticker,score)],ym2date,by="ym")[,.(Date,Ticker,score)]
run<-function(dd,tag) canonical_screen_bt(dd[Date %in% bench_dt$Date & !is.na(score)],returns_dt,bench_dt,top_n=25L,cost_bps_oneway=15,run_id=tag,strategy_id=tag)
f_all<-run(sdt,"all")
f_cap<-run(sdt[Date<=as.Date("2025-12-31")],"cap2512")
f_c6<-run(sdt[Date<=as.Date("2025-06-30")],"cap2506")
# also: cap forward returns/bench to exclude the 2026 mega tail entirely (returns_dt Date<=202512)
returns_dt2<-returns_dt[Date<=as.Date("2025-12-31")]; bench_dt2<-bench_dt[Date<=as.Date("2025-12-31")]
run2<-function(dd,tag) canonical_screen_bt(dd[Date %in% bench_dt2$Date & !is.na(score)],returns_dt2,bench_dt2,top_n=25L,cost_bps_oneway=15,run_id=tag,strategy_id=tag)
f_pre<-run2(sdt,"prebench")
writeLines(c(
 sprintf("S04 full(sig->202603): PORT_t=%.3f n=%d", f_all$portfolio_alpha_t_nw_lag3, f_all$n_months),
 sprintf("S04 sig<=202512:       PORT_t=%.3f n=%d", f_cap$portfolio_alpha_t_nw_lag3, f_cap$n_months),
 sprintf("S04 sig<=202506:       PORT_t=%.3f n=%d", f_c6$portfolio_alpha_t_nw_lag3, f_c6$n_months),
 sprintf("S04 bench+sig<=202512: PORT_t=%.3f n=%d", f_pre$portfolio_alpha_t_nw_lag3, f_pre$n_months)
), file.path(OUT,"recon.txt"))
cat("done\n")
