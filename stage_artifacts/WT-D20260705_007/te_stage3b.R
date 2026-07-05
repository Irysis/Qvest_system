suppressWarnings(suppressMessages({ library(data.table); library(arrow); library(dplyr); library(jsonlite) }))
data.table::setDTthreads(2L); try(arrow::set_cpu_count(2L), silent=TRUE)
.flog <- function(...) { cat(sprintf(...), file=stderr()); flush(stderr()) }
`%||%` <- function(a,b) if (is.null(a)||length(a)==0||(length(a)==1&&is.na(a))) b else a
PROJ <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; CACHE <- file.path(PROJ,".cache")
OUT <- file.path(PROJ,"stage_artifacts","WT-D20260705_007")
source(file.path(PROJ,"02_Infrastructure","contracts","canonical_screen_bt.R"))
S <- readRDS(file.path(OUT,"te_stage2_full.rds"))$S
.flog("S rows=%d\n", nrow(S))
univ <- unique(S$Ticker)
# monthly returns for universe tickers only (lean)
RD <- open_dataset(file.path(CACHE,"RAWDATA_pin20260703.parquet")) %>%
  filter(Date >= as.Date("2004-06-01")) %>% select(Date,Ticker,Ret) %>% collect() %>% as.data.table()
RD <- RD[Ticker %in% univ & is.finite(Ret)]
RD[, ym := format(Date,"%Y-%m")]
MR <- RD[, .(MRet=prod(1+Ret)-1), by=.(Ticker,ym)]
.flog("MR rows=%d\n", nrow(MR))
setorder(MR, Ticker, ym)
MR[, `:=`(r1=shift(MRet,1L,type="lead"), r2=shift(MRet,2L,type="lead"), r3=shift(MRet,3L,type="lead")), by=Ticker]
MR[, Ret_3m := (1+r1)*(1+r2)*(1+r3)-1]
S2 <- copy(S); S2[, ym := format(Date,"%Y-%m")]
S2 <- merge(S2, MR[, .(Ticker,ym,Ret_3m)], by=c("Ticker","ym"), all.x=TRUE)
S2[, mo := as.integer(substr(ym,6,7))]
q <- S2[mo %in% c(3L,6L,9L,12L) & is.finite(Ret_3m)]
.flog("q rows=%d dates=%d\n", nrow(q), uniqueN(q$Date))
# bm 3M
BM <- as.data.table(read_parquet(file.path(CACHE,"benchmark_pin20260703.parquet")))
BM[, Date := as.Date(Date)]; BM[, ym := format(Date,"%Y-%m")]
BMm <- BM[is.finite(BM_Ret), .(bm=prod(1+BM_Ret)-1), by=ym]; setorder(BMm, ym)
BMm[, `:=`(b1=shift(bm,1L,type="lead"),b2=shift(bm,2L,type="lead"),b3=shift(bm,3L,type="lead"))]
BMm[, BM3 := (1+b1)*(1+b2)*(1+b3)-1]
qb <- unique(q[, .(Date, ym)])
qb <- merge(qb, BMm[,.(ym,BM3)], by="ym", all.x=TRUE)
bench_dt <- qb[is.finite(BM3), .(Date, BM_Ret=BM3)]
returns_dt <- q[, .(Date,Ticker,Ret_1m=Ret_3m)]
liq_dt <- unique(q[, .(Date,Ticker,adv=AvgTV20)])
run3 <- function(col,tn,lab){
  sc <- q[is.finite(get(col)), .(Date,Ticker,score=get(col))]
  r <- tryCatch(canonical_screen_bt(sc,returns_dt,bench_dt,top_n=tn,cost_bps_oneway=15,liq_dt=liq_dt,liq_min=2e8,
       run_id=paste0("te3_",lab),strategy_id=paste0("te3_",lab),periods_per_year=4L),
       error=function(e){.flog("ERR %s %s\n",lab,conditionMessage(e));NULL})
  if(is.null(r)) return(NULL)
  .flog("[3M %s top%d] PORT_t=%.3f IR=%.3f netSR=%.3f n_q=%d\n",lab,tn,
        r$portfolio_alpha_t_nw_lag3%||%NA,r$information_ratio%||%NA,r$net_sr%||%NA,r$n_months)
  list(port_t=r$portfolio_alpha_t_nw_lag3,ir=r$information_ratio,net_sr=r$net_sr,n_q=r$n_months)
}
out <- list(resid_top20=run3("Score_resid",20L,"resid"), raw_top20=run3("Score",20L,"raw"))
write_json(list(horizon="3M_quarterly",results=out), file.path(OUT,"te_3m_horizon.json"),
           auto_unbox=TRUE,pretty=TRUE,digits=6,na="null")
.flog("DONE\n")
