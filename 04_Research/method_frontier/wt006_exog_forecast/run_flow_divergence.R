# run_flow_divergence.R — probe: flow_divergence
# Q: foreign vs institutional net-buy DIVERGENCE (disagreement=info) as cross-sectional
#    signal. Is divergence-adjusted / consensus-buy a BETTER signal than raw flow (wt008:
#    raw net-buy sign-reversed in canonical top-25, 13/13 PORT_t<0)? Is any variant
#    book-orthogonal (|corr_to_book|<0.30) with positive PORT_t = 2nd-sleeve/overlay source?
# PIT: flow features are trailing (netbuy_20d etc.) snapshot at month-end (data <= sig_date),
#      Ret_1m is forward (next month). lag1 stress + intensity=netbuy/liq (cross-sec z).
suppressMessages({library(data.table);library(arrow);library(PerformanceAnalytics);library(xts);library(lubridate)})
setDTthreads(1)
QM <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(QM)
source("04_Research/method_frontier/wt006_exog_forecast/eval_harness.R")
OUT <- "04_Research/method_frontier/wt006_exog_forecast"

# ---- universe: K200 u KQ150 on grid dates ----
UNIV <- .FAM[(K200==1 | KQ150==1)]; UNIV <- UNIV[Date %in% .Rg$Date]
setkey(UNIV, Date, Ticker)

# ---- flow monthly snapshot: last daily obs per (Ticker, year-month), keyed to grid Date ----
fl <- as.data.table(read_parquet(".cache/flow_features_daily.parquet",
  col_select=c("Date","Ticker","foreign_netbuy_20d","inst_netbuy_20d",
               "foreign_netbuy_5d","inst_netbuy_5d","liq_20d")))
fl[, Date:=as.Date(Date)]; fl[, ym:=format(Date,"%Y-%m")]
setorder(fl, Ticker, ym, Date)
flm <- fl[, .SD[.N], by=.(Ticker, ym)]          # last trading day <= month-end in that ym
gd  <- data.table(gDate=sort(unique(.Rg$Date))); gd[, ym:=format(gDate,"%Y-%m")]
flm <- merge(flm, gd, by="ym")                   # attach canonical grid Date
flm[, Date:=gDate]; flm[, gDate:=NULL]
# intensity = 20d/5d net-buy relative to avg daily trading value (scale-free across caps)
flm[, f_int20 := foreign_netbuy_20d/liq_20d]
flm[, i_int20 := inst_netbuy_20d   /liq_20d]
flm[, f_int5  := foreign_netbuy_5d /liq_20d]
flm[, i_int5  := inst_netbuy_5d    /liq_20d]

# join to universe
D <- merge(UNIV[, .(Date,Ticker,momentum)], flm[, .(Date,Ticker,f_int20,i_int20,f_int5,i_int5)],
           by=c("Date","Ticker"), all.x=FALSE)
# cross-sectional z within Date (winsorize at +/-4 sd to tame flow outliers)
zc <- function(x){ m<-mean(x,na.rm=TRUE); s<-sd(x,na.rm=TRUE); if(!is.finite(s)||s<=0) return(rep(NA,length(x)))
  z<-(x-m)/s; pmin(pmax(z,-4),4) }
D[, z_f20 := zc(f_int20), by=Date]
D[, z_i20 := zc(i_int20), by=Date]
D[, z_f5  := zc(f_int5),  by=Date]
D[, z_i5  := zc(i_int5),  by=Date]
D <- D[is.finite(z_f20) & is.finite(z_i20)]
cat(sprintf("[flow] merged panel: %d rows, %d months, %d tickers (median names/mo=%d)\n",
    nrow(D), uniqueN(D$Date), uniqueN(D$Ticker), as.integer(median(D[,.N,by=Date]$N))))

# ---- measure() + book_marginal() (template = run_struct_multisleeve.R) ----
measure <- function(score_dt, label){
  r <- .canon(score_dt); a <- .active_series(r)
  lag1 <- tryCatch({ s<-as.data.table(score_dt); s[,Date:=as.Date(Date)]
    dts<-sort(unique(s$Date)); lm<-data.table(Date=dts,prev=shift(dts,1))[!is.na(prev)]
    s2<-merge(lm,s[,.(prev=Date,Ticker,score)],by="prev",allow.cartesian=TRUE)[,.(Date,Ticker,score)]
    .canon(s2)$portfolio_alpha_t_nw_lag3 }, error=function(e) NA_real_)
  list(label=label, n=r$n_months, port_t=round(r$portfolio_alpha_t_nw_lag3,3),
       ew_uni_t=round(r$diag_ew_universe$portfolio_alpha_t_nw_lag3,3),
       oos_ret=round(.oos_ret_of(r$period_returns),3), net_sr=round(r$net_sr,3),
       calmar=round(.calmar_of(r$period_returns),3), turnover=round(r$turnover_annual,2),
       lag1_port_t=round(lag1,3), active=a)
}
bk <- readRDS("qepm/mailbox/worktask/WT-D20260702_002/output/bt_result_C_noL4_CLEAN_ann12.rds")
bkpr <- as.data.table(bk$period_returns)[, .(date=as.Date(date), ret_net)]
bkbm <- as.data.table(bk$benchmark_returns)[, .(date=as.Date(date), bm=benchmark_ret)]
BK <- merge(bkpr, bkbm, by="date"); BK[, active:=ret_net-bm]; BK[, ym:=format(date,"%Y-%m")]
book_ir <- mean(BK$active)/sd(BK$active)*sqrt(12)
cat(sprintf("[book] IR=%.3f n=%d (expect 1.416)\n", book_ir, nrow(BK)))
book_marginal <- function(cons_active){
  ca <- as.data.table(cons_active)[, .(date=as.Date(date), active, ret_net)]
  cb <- .BMg[, .(date=Date, cbm=BM_Ret)]; ca <- merge(ca, cb, by="date", all.x=TRUE)
  best <- list(k=NA,bcorr=-2,acorr=NA,dIR_max=NA,lam=NA,blend_ir=NA,overlapn=0)
  for(k in -3:3){
    cca <- copy(ca)
    cca[, ym := format(as.Date(paste0(format(date,"%Y-%m"),"-01")) %m+% months(k), "%Y-%m")]
    mg <- merge(cca[,.(ym,cactive=active,cbm)], BK[,.(ym,bactive=active,bbm=bm)], by="ym")
    if(nrow(mg)<24) next
    bc <- suppressWarnings(cor(mg$cbm,mg$bbm,use="complete.obs")); if(is.na(bc)) next
    if(bc>best$bcorr){
      ac <- suppressWarnings(cor(mg$cactive,mg$bactive,use="complete.obs"))
      dmax<--Inf; lbest<-NA; irb<-NA; base_ir<-mean(mg$bactive)/sd(mg$bactive)*sqrt(12)
      for(lam in seq(0,1,0.05)){ bl<-(1-lam)*mg$bactive+lam*mg$cactive
        ir<-mean(bl)/sd(bl)*sqrt(12); d<-ir-base_ir; if(d>dmax){dmax<-d;lbest<-lam;irb<-ir} }
      best <- list(k=k,bcorr=round(bc,3),acorr=round(ac,3),dIR_max=round(dmax,3),
                   lam=lbest,blend_ir=round(irb,3),overlapn=nrow(mg),base_ir=round(base_ir,3))
    }
  }
  best
}

# ============ VARIANTS ============
V <- list()
V[["raw_foreign20"]] <- measure(D[is.finite(z_f20),.(Date,Ticker,score=z_f20)], "raw foreign 20d")
V[["raw_inst20"]]    <- measure(D[is.finite(z_i20),.(Date,Ticker,score=z_i20)], "raw inst 20d")
V[["combined_sum"]]  <- measure(D[,.(Date,Ticker,score=z_f20+z_i20)], "combined z_f+z_i 20d")
# --- CONSENSUS: both buying (agreement) ---
V[["consensus_min"]] <- measure(D[,.(Date,Ticker,score=pmin(z_f20,z_i20))], "consensus min(z_f,z_i) [both-buy]")
V[["consensus_gated"]]<- measure(D[z_f20>0 & z_i20>0,.(Date,Ticker,score=z_f20+z_i20)], "consensus gated (both>0) rank by sum")
# --- DIVERGENCE: disagreement magnitude as selector ---
V[["divergence_abs"]] <- measure(D[,.(Date,Ticker,score=abs(z_f20-z_i20))], "divergence |z_f-z_i| [high disagree]")
V[["foreign_minus_inst"]] <- measure(D[,.(Date,Ticker,score=z_f20-z_i20)], "foreign>inst (F buy, I sell)")
V[["inst_minus_foreign"]] <- measure(D[,.(Date,Ticker,score=z_i20-z_f20)], "inst>foreign (I buy, F sell)")
# --- divergence-ADJUSTED flow: consensus flow shrunk by disagreement ---
V[["divadj_flow"]]   <- measure(D[,.(Date,Ticker,score=(z_f20+z_i20)-abs(z_f20-z_i20))], "consensus - |disagree| (agree-weighted)")
# --- REVERSED direction of raw (wt008 said reversed also negative; verify on divergence too) ---
V[["rev_combined"]]  <- measure(D[,.(Date,Ticker,score=-(z_f20+z_i20))], "REVERSED combined (contrarian to flow)")
V[["rev_consensus"]] <- measure(D[,.(Date,Ticker,score=-pmin(z_f20,z_i20))], "REVERSED consensus (avoid crowded-buy)")
# --- 5d horizon consensus/divergence (shorter) ---
V[["consensus_min5"]]<- measure(D[is.finite(z_f5)&is.finite(z_i5),.(Date,Ticker,score=pmin(z_f5,z_i5))], "consensus min 5d")
V[["fminusi_5"]]     <- measure(D[is.finite(z_f5)&is.finite(z_i5),.(Date,Ticker,score=z_f5-z_i5)], "foreign>inst 5d")

# summary + book-marginal
summ <- rbindlist(lapply(names(V), function(nm){ v<-V[[nm]]; bm<-book_marginal(v$active)
  data.table(variant=nm,label=v$label,n=v$n,port_t=v$port_t,ew_uni_t=v$ew_uni_t,oos_ret=v$oos_ret,
             net_sr=v$net_sr,calmar=v$calmar,turnover=v$turnover,lag1_port_t=v$lag1_port_t,
             bk_k=bm$k,bk_bcorr=bm$bcorr,bk_acorr=bm$acorr,bk_dIRmax=bm$dIR_max,bk_lam=bm$lam,bk_n=bm$overlapn) }))
cat("\n===== FLOW DIVERGENCE RESULTS (cap-w KOSPI200 top-25 EW, 15bps, liq 2e8) =====\n")
print(summ)
cat(sprintf("\nbaseline factor-momentum port_t=%.3f | gate=2.95 | book IR=%.3f | promising=(port_t>1.5 & |bk_acorr|<0.30)\n",
    .BASELINE_MOM_PORT_T, book_ir))
saveRDS(list(summ=summ,book_ir=book_ir), file.path(OUT,"flow_divergence_results.rds"))
fwrite(summ, file.path(OUT,"flow_divergence_results.csv"))
cat("[saved] flow_divergence_results.{rds,csv}\n")
