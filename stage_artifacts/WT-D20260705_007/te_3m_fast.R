suppressWarnings(suppressMessages({ library(data.table); library(arrow); library(dplyr); library(jsonlite) }))
data.table::setDTthreads(4L); try(arrow::set_cpu_count(4L), silent=TRUE)
.flog <- function(...){cat(sprintf(...),file=stderr());flush(stderr())}
`%||%` <- function(a,b) if(is.null(a)||length(a)==0||(length(a)==1&&is.na(a))) b else a
P<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; C<-file.path(P,".cache"); O<-file.path(P,"stage_artifacts","WT-D20260705_007")
source(file.path(P,"02_Infrastructure","contracts","canonical_screen_bt.R"))
S <- readRDS(file.path(O,"te_stage2_full.rds"))$S; .flog("S=%d\n",nrow(S))
univ <- unique(S$Ticker); .flog("univ=%d\n",length(univ))
# lean: only universe tickers' Ret, pushdown
RD <- open_dataset(file.path(C,"RAWDATA_pin20260703.parquet")) %>%
  filter(Date >= as.Date("2004-06-01"), Ticker %in% univ) %>% select(Date,Ticker,Ret) %>% collect() %>% as.data.table()
.flog("RD=%d\n",nrow(RD))
RD[, ym:=format(Date,"%Y-%m")]
MR <- RD[is.finite(Ret), .(m=prod(1+Ret)-1), by=.(Ticker,ym)]; setorder(MR,Ticker,ym)
MR[, `:=`(r1=shift(m,1L,"lead"),r2=shift(m,2L,"lead"),r3=shift(m,3L,"lead")), by=Ticker]
MR[, R3:=(1+r1)*(1+r2)*(1+r3)-1]; .flog("MR=%d\n",nrow(MR))
S2<-copy(S); S2[,ym:=format(Date,"%Y-%m")]
S2<-merge(S2,MR[,.(Ticker,ym,R3)],by=c("Ticker","ym"),all.x=TRUE)
S2[,mo:=as.integer(substr(ym,6,7))]
q<-S2[mo %in% c(3L,6L,9L,12L) & is.finite(R3)]; .flog("q=%d d=%d\n",nrow(q),uniqueN(q$Date))
BM<-as.data.table(read_parquet(file.path(C,"benchmark_pin20260703.parquet"))); BM[,Date:=as.Date(Date)]; BM[,ym:=format(Date,"%Y-%m")]
BMm<-BM[is.finite(BM_Ret),.(b=prod(1+BM_Ret)-1),by=ym]; setorder(BMm,ym)
BMm[,`:=`(b1=shift(b,1L,"lead"),b2=shift(b,2L,"lead"),b3=shift(b,3L,"lead"))]; BMm[,B3:=(1+b1)*(1+b2)*(1+b3)-1]
qb<-unique(q[,.(Date,ym)]); qb<-merge(qb,BMm[,.(ym,B3)],by="ym",all.x=TRUE)
bench<-qb[is.finite(B3),.(Date,BM_Ret=B3)]; rt<-q[,.(Date,Ticker,Ret_1m=R3)]; ld<-unique(q[,.(Date,Ticker,adv=AvgTV20)])
r3<-function(col,tn,lab){sc<-q[is.finite(get(col)),.(Date,Ticker,score=get(col))]
  r<-tryCatch(canonical_screen_bt(sc,rt,bench,top_n=tn,cost_bps_oneway=15,liq_dt=ld,liq_min=2e8,run_id=lab,strategy_id=lab,periods_per_year=4L),error=function(e){.flog("E %s\n",conditionMessage(e));NULL})
  if(is.null(r))return(NULL); .flog("[3M %s t%d] PORT_t=%.3f IR=%.3f netSR=%.3f n=%d\n",lab,tn,r$portfolio_alpha_t_nw_lag3%||%NA,r$information_ratio%||%NA,r$net_sr%||%NA,r$n_months)
  list(port_t=r$portfolio_alpha_t_nw_lag3,ir=r$information_ratio,net_sr=r$net_sr,n_q=r$n_months)}
out<-list(resid_top20=r3("Score_resid",20L,"resid20"),raw_top20=r3("Score",20L,"raw20"))
write_json(list(horizon="3M_quarterly",results=out),file.path(O,"te_3m_horizon.json"),auto_unbox=TRUE,pretty=TRUE,digits=6,na="null")
.flog("DONE\n")
