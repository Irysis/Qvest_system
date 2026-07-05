# =============================================================================
# flow_diag_v2.R — Cycle 2 flow near-miss resolution (consumes Python-prepped
#   monthly tables to avoid R arrow segfault on 419MB rawdata).
# Adds MISSING diagnostics to prior Cycle 1 Track S fair-trial:
#   (A) closet-indexing: active-share, top-2 mega-cap weight, EX-MEGA-CAP re-test
#   (B) 1-month cross-sectional reversal secondary test
# Conditions identical to prior Stage A (top-25 EW, 15bps delta, K200|KQ150,
#   liq>=2e8 t-1, canonical_screen_bt contract-grade). Reuses prior INV-Z chunks.
# =============================================================================
suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite)
  library(xts); library(PerformanceAnalytics)
})
setDTthreads(1L)

PR   <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
OUT  <- file.path(PR, "stage_artifacts/flow_microstructure_cycle2")
CHUNKS <- file.path(PR, "04_Research/composition_search/cycle1_trackS/invz_chunks")
source(file.path(PR, "02_Infrastructure/config.R"))
source(file.path(PR, "02_Infrastructure/contracts/backtest_result_contract.R"))
source(file.path(PR, "02_Infrastructure/contracts/canonical_screen_bt.R"))

TOP_N <- 25L; COST_BPS <- 15
SIG_FIRST <- "200501"; SIG_LAST <- "202603"; D2017 <- as.Date("2017-01-01")

rp <- function(f) as.data.table(read_parquet(file.path(OUT, f)))  # small local parquets — safe
returns_dt <- rp("returns_dt.parquet"); returns_dt[, Date := as.Date(Date)]
bench_dt   <- rp("bench_dt.parquet");   bench_dt[, Date := as.Date(Date)]
me_uni     <- rp("me_uni.parquet");     me_uni[, Date := as.Date(Date)]
mret       <- rp("mret.parquet")
cat(sprintf("[load] returns=%d bench=%d uni=%d mret=%d\n",
            nrow(returns_dt), nrow(bench_dt), nrow(me_uni), nrow(mret)))

ym2date <- unique(me_uni[, .(ym, Date)])
uni <- me_uni[, .(ym, Ticker, Size)]

# top-2 mega-cap per ym
setorder(uni, ym, -Size)
mega2 <- uni[, .(Ticker = Ticker[seq_len(min(2L,.N))]), by = ym][, is_mega := TRUE]

# INV-Z chunks (prior raw Z, 255m)
sig_months <- sort(ym2date$ym); sig_months <- sig_months[sig_months>=SIG_FIRST & sig_months<=SIG_LAST]
FZ <- rbindlist(lapply(sig_months, function(m){
  p <- file.path(CHUNKS, paste0("invz_",m,".parquet"))
  if (file.exists(p)) as.data.table(read_parquet(p)) else NULL
}), fill=TRUE)
cat(sprintf("[load] FZ rows=%d factors=%d months=%d\n", nrow(FZ), uniqueN(FZ$Factor_Name), uniqueN(FZ$ym)))

# ---- score builders ----
build_single <- function(fac,dir){
  sc <- FZ[Factor_Name==fac, .(ym,Ticker,score=dir*Z)]
  merge(sc, ym2date, by="ym")[, .(Date,Ticker,score)]
}
build_S04 <- function(){
  facs <- c("INV02_Foreign_NetBuy_60d","INV04_Inst_NetBuy_60d",
            "INV09_Flow_Persistence","INV11_Foreign_Concentration","INV07_Retail_Contrarian")
  CW <- dcast(FZ[Factor_Name %in% facs], ym+Ticker~Factor_Name, value.var="Z")
  fcols <- intersect(facs,names(CW))
  CW[, raw_mean := rowMeans(.SD,na.rm=TRUE), .SDcols=fcols]
  CW <- CW[is.finite(raw_mean)]
  CW[, score := -1*raw_mean]
  CW[, score := (score-mean(score,na.rm=TRUE))/sd(score,na.rm=TRUE), by=ym]
  merge(CW[,.(ym,Ticker,score)], ym2date, by="ym")[, .(Date,Ticker,score)]
}
build_reversal <- function(){
  rv <- merge(mret[,.(ym,Ticker,prev=mret)], uni[,.(ym,Ticker)], by=c("ym","Ticker"))
  rv[, score := -1*prev]
  merge(rv[,.(ym,Ticker,score)], ym2date, by="ym")[, .(Date,Ticker,score)]
}

# ---- measurement helpers ----
run_screen <- function(sdt, tag){
  sdt <- sdt[Date %in% bench_dt$Date & !is.na(score)]
  if (nrow(sdt)==0 || uniqueN(sdt$Date)<12) return(list(portfolio_alpha_t_nw_lag3=NA_real_, net_sr=NA_real_,
                                                        information_ratio=NA_real_, turnover_annual=NA_real_, n_months=uniqueN(sdt$Date)))
  canonical_screen_bt(sdt, returns_dt, bench_dt, top_n=TOP_N, cost_bps_oneway=COST_BPS,
                      liq_dt=NULL, run_id=tag, strategy_id=tag)
}
oos_ret_median <- function(sdt, tag){
  sdt <- sdt[Date %in% bench_dt$Date & !is.na(score)]
  ad <- sort(unique(sdt$Date)); n<-length(ad); rr<-c()
  for (fr in c(0.55,0.65,0.75)){
    cd <- ad[floor(n*fr)]
    isr <- run_screen(sdt[Date<=cd], paste0(tag,"_IS"))
    oor <- run_screen(sdt[Date> cd], paste0(tag,"_OOS"))
    rr <- c(rr, if(!is.na(isr$net_sr) && isr$net_sr!=0) oor$net_sr/isr$net_sr else NA_real_)
  }
  median(rr, na.rm=TRUE)
}
closet <- function(sdt){
  sdt <- sdt[Date %in% bench_dt$Date & !is.na(score)]
  setorder(sdt, Date, -score)
  W <- sdt[, {n<-min(TOP_N,.N); .(Ticker=Ticker[seq_len(n)], w=rep(1/n,n))}, by=Date]
  W[, ym := format(Date,"%Y%m")]
  W2 <- merge(W, mega2[,.(ym,Ticker,is_mega)], by=c("ym","Ticker"), all.x=TRUE)
  megaw <- W2[, .(mega_w = sum(w[is_mega==TRUE], na.rm=TRUE)), by=ym]
  # cap-weight benchmark proxy per ym = Size/sum(Size) in eligible universe
  ucw <- uni[, .(Ticker, wbench = Size/sum(Size)), by=ym]
  as_v <- sapply(unique(W$ym), function(m){
    bk <- W[ym==m, .(Ticker,w)]; bn <- ucw[ym==m, .(Ticker,wbench)]
    mm <- merge(bk,bn,by="Ticker",all=TRUE); mm[is.na(w),w:=0]; mm[is.na(wbench),wbench:=0]
    0.5*sum(abs(mm$w-mm$wbench))
  })
  list(active_share_mean=mean(as_v), active_share_median=median(as_v),
       mega_top2_w_mean=mean(megaw$mega_w), mega_top2_w_median=median(megaw$mega_w))
}
run_exmega <- function(sdt, tag){
  s <- copy(sdt); s[, ym := format(Date,"%Y%m")]
  s <- merge(s, mega2[,.(ym,Ticker,is_mega)], by=c("ym","Ticker"), all.x=TRUE)
  run_screen(s[is.na(is_mega)][, .(Date,Ticker,score)], tag)
}
pk <- function(x,nm){ v<-x[[nm]]; if(is.null(v)||length(v)==0) NA_real_ else as.numeric(v) }

# ---- run ----
specs <- list(S04_composite=build_S04(),
              S01_foreign60=build_single("INV02_Foreign_NetBuy_60d",-1),
              S03_retailfollow=build_single("INV07_Retail_Contrarian",-1),
              REV_1m=build_reversal())
res <- list()
for (nm in names(specs)){
  cat(sprintf("== %s ==\n", nm)); sdt <- specs[[nm]]
  full <- run_screen(sdt, paste0("d_",nm))
  s17  <- run_screen(sdt[Date>=D2017], paste0("d_",nm,"_17"))
  oosm <- tryCatch(oos_ret_median(sdt, paste0("d_",nm)), error=function(e) NA_real_)
  cl   <- closet(sdt)
  exf  <- run_exmega(sdt, paste0("d_",nm,"_ex"))
  ex17 <- run_exmega(sdt[Date>=D2017], paste0("d_",nm,"_ex17"))
  res[[nm]] <- list(
    port_t_full=round(pk(full,"portfolio_alpha_t_nw_lag3"),3),
    ir_full=round(pk(full,"information_ratio"),3),
    net_sr_full=round(pk(full,"net_sr"),3),
    turnover=round(pk(full,"turnover_annual"),2),
    n_months=pk(full,"n_months"),
    port_t_2017p=round(pk(s17,"portfolio_alpha_t_nw_lag3"),3),
    net_sr_2017p=round(pk(s17,"net_sr"),3),
    oos_retention_median=round(oosm,3),
    active_share_mean=round(cl$active_share_mean,3),
    active_share_median=round(cl$active_share_median,3),
    mega_top2_w_mean=round(cl$mega_top2_w_mean,3),
    mega_top2_w_median=round(cl$mega_top2_w_median,3),
    exmega_port_t_full=round(pk(exf,"portfolio_alpha_t_nw_lag3"),3),
    exmega_port_t_2017p=round(pk(ex17,"portfolio_alpha_t_nw_lag3"),3),
    metric_type="canonical_screen")
  r<-res[[nm]]
  cat(sprintf("   PORT_t=%.3f (2017+ %.3f) oos=%.3f | AS=%.2f mega2w=%.2f | exMega PORT_t=%.3f (2017+ %.3f) TO=%.1f\n",
      r$port_t_full,r$port_t_2017p,r$oos_retention_median,r$active_share_mean,r$mega_top2_w_mean,
      r$exmega_port_t_full,r$exmega_port_t_2017p,r$turnover))
}
out <- list(meta=list(
  program="Cycle 2 flow near-miss: closet-index + reversal diagnostics",
  measured_at=format(Sys.time(),"%Y-%m-%dT%H:%M:%S%z"),
  builds_on="Cycle1 Track S FLOW-S01..S09 (2026-06-12); investor_wide max 2026-03-26 UNCHANGED -> base 9-spec frozen",
  sig_window=c(SIG_FIRST,SIG_LAST),
  universe="K200|KQ150 PIT + no bad-flag + 20d ADV>=2e8 (t-1 C10)",
  portfolio="top-25 EW monthly, 15bps delta",
  metric_type="canonical_screen (screening tier — forge authoritative)",
  active_share_note="AS vs Size-weighted eligible-universe cap-weight proxy",
  prep="monthly tables via Python (R arrow segfaults on 419MB rawdata); INV-Z reused from prior chunks"),
  results=res)
write_json(out, file.path(OUT,"flow_closet_reversal_result.json"), pretty=TRUE, auto_unbox=TRUE, digits=6, na="null")
cat("\n===== RESULT TABLE =====\n")
print(rbindlist(lapply(names(res), function(n) cbind(spec=n, as.data.table(res[[n]]))), fill=TRUE)[
  , .(spec,port_t_full,port_t_2017p,oos_retention_median,active_share_mean,mega_top2_w_mean,exmega_port_t_full,exmega_port_t_2017p)])
writeLines(format(Sys.time(),"%Y-%m-%d %H:%M:%S"), file.path(OUT,"DONE_DIAG"))
cat("DONE_DIAG\n")
