#!/usr/bin/env Rscript
# te_stage3_horizon.R — 3M decay-matched holding 검증 (WT 강화축 (b)).
#   TE는 저주파 정보전파 → 1M보다 3M horizon에서 신호가 더 강할 수 있다는 가설.
#   quarterly 리밸(cadence 4), forward 3M 수익. resid + raw 둘 다.
suppressWarnings(suppressMessages({ library(data.table); library(arrow); library(dplyr); library(jsonlite) }))
data.table::setDTthreads(2L); try(arrow::set_cpu_count(2L), silent = TRUE)
`%||%` <- function(a,b) if (is.null(a)||length(a)==0||(length(a)==1&&is.na(a))) b else a
PROJ <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; CACHE <- file.path(PROJ,".cache")
OUT <- file.path(PROJ,"stage_artifacts","WT-D20260705_007")
source(file.path(PROJ,"02_Infrastructure","contracts","canonical_screen_bt.R"))

full <- readRDS(file.path(OUT, "te_stage2_full.rds"))
S <- full$S   # 이미 K200∪KQ150 + resid + 특성 병합됨

# forward 3M 수익 (sig_date t -> t+1..t+3 월 실현) + 분기말 sig_date만
RAWDATA <- open_dataset(file.path(CACHE,"RAWDATA_pin20260703.parquet")) %>%
  filter(Date >= as.Date("2004-06-01")) %>% select(Date,Ticker,Ret) %>% collect() %>% as.data.table()
RAWDATA[, Date := as.Date(Date)]; RAWDATA[, ym := format(Date,"%Y-%m")]
MR <- RAWDATA[is.finite(Ret), .(MRet = prod(1+Ret)-1), by=.(Ticker,ym)]
cal <- unique(RAWDATA[, .(ym)]); setorder(cal, ym)
cal[, `:=`(n1=shift(ym,1L,type="lead"), n2=shift(ym,2L,type="lead"), n3=shift(ym,3L,type="lead"))]

# S의 sig_date ym
S2 <- copy(S); S2[, ym := format(Date,"%Y-%m")]
S2 <- merge(S2, cal, by="ym", all.x=TRUE)
# 3M forward return = (1+r1)(1+r2)(1+r3)-1
get3 <- function(tk, a,b,c) {
  # merge helper via data.table
}
f3 <- merge(S2[, .(Date,Ticker,ym,n1,n2,n3,Score,Score_resid,AvgTV20)],
            MR[, .(Ticker, ym1=ym, r1=MRet)], by.x=c("Ticker","n1"), by.y=c("Ticker","ym1"), all.x=TRUE)
f3 <- merge(f3, MR[, .(Ticker, ym2=ym, r2=MRet)], by.x=c("Ticker","n2"), by.y=c("Ticker","ym2"), all.x=TRUE)
f3 <- merge(f3, MR[, .(Ticker, ym3=ym, r3=MRet)], by.x=c("Ticker","n3"), by.y=c("Ticker","ym3"), all.x=TRUE)
f3[, Ret_3m := (1+r1)*(1+r2)*(1+r3)-1]

# 분기말 sig_date만 (3,6,9,12월) — non-overlapping quarterly rebal
f3[, mo := as.integer(substr(ym,6,7))]
q <- f3[mo %in% c(3L,6L,9L,12L) & is.finite(Ret_3m)]

# benchmark 3M
BM <- as.data.table(read_parquet(file.path(CACHE,"benchmark_pin20260703.parquet")))
BM[, Date := as.Date(Date)]; BM[, ym := format(Date,"%Y-%m")]
BMm <- BM[is.finite(BM_Ret), .(bm=prod(1+BM_Ret)-1), by=ym]
qb <- unique(q[, .(Date, n1,n2,n3)])
qb <- merge(qb, BMm[,.(ym,b1=bm)], by.x="n1", by.y="ym", all.x=TRUE)
qb <- merge(qb, BMm[,.(ym,b2=bm)], by.x="n2", by.y="ym", all.x=TRUE)
qb <- merge(qb, BMm[,.(ym,b3=bm)], by.x="n3", by.y="ym", all.x=TRUE)
qb[, BM_Ret := (1+b1)*(1+b2)*(1+b3)-1]
bench_dt <- qb[is.finite(BM_Ret), .(Date, BM_Ret)]

returns_dt <- q[, .(Date, Ticker, Ret_1m = Ret_3m)]  # 3M을 Ret_1m 슬롯에 (분기 cadence)
liq_dt <- unique(q[, .(Date, Ticker, adv = AvgTV20)])

run3 <- function(scorecol, top_n, label) {
  sc <- q[is.finite(get(scorecol)), .(Date, Ticker, score = get(scorecol))]
  r <- tryCatch(canonical_screen_bt(sc, returns_dt, bench_dt, top_n=top_n, cost_bps_oneway=15,
                liq_dt=liq_dt, liq_min=2e8, run_id=paste0("te3_",label), strategy_id=paste0("te3_",label),
                periods_per_year=4L), error=function(e){cat("ERR",label,conditionMessage(e),"\n");NULL})
  if(is.null(r)) return(NULL)
  cat(sprintf("[s3][3M %s top%d] PORT_t=%.3f IR=%.3f netSR=%.3f TO=%.1f n_q=%d\n",
              label, top_n, r$portfolio_alpha_t_nw_lag3%||%NA, r$information_ratio%||%NA,
              r$net_sr%||%NA, r$turnover_annual%||%NA, r$n_months))
  list(port_t=r$portfolio_alpha_t_nw_lag3, ir=r$information_ratio, net_sr=r$net_sr,
       turnover_ann=r$turnover_annual, n_q=r$n_months)
}
out <- list(
  resid_top20 = run3("Score_resid",20L,"resid"),
  resid_top25 = run3("Score_resid",25L,"resid25"),
  raw_top20   = run3("Score",20L,"raw"))
write_json(list(horizon="3M_quarterly", results=out), file.path(OUT,"te_3m_horizon.json"),
           auto_unbox=TRUE, pretty=TRUE, digits=6, na="null")
cat("[s3] DONE\n")
