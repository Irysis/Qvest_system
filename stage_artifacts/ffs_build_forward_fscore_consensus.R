suppressMessages({library(data.table); library(arrow); library(xts); library(PerformanceAnalytics)})
setDTthreads(1); options(warn=-1)
root <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(root)
sink(tempfile())  # swallow noisy source() messages
source("04_Research/method_frontier/wt006_exog_forecast/eval_harness.R")
sink()

cc <- file.path(root,".cache/consensus")
SZ <- .FAM[!is.na(Size), .(Date,Ticker,Size)]   # FIX: capital Size for diag_cap_tier

# ---- metrics helper ----
metr <- function(res){
  pr <- res$period_returns; a <- pr$ret_net - pr$benchmark_ret; n<-length(a)
  fr<-c(.55,.65,.75); sr<-function(x){s<-sd(x);if(!is.finite(s)||s<=0)return(NA);mean(x)/s*sqrt(12)}
  oos<-median(sapply(fr,function(f){k<-floor(n*f);if(k<6||n-k<6)return(NA);is<-sr(a[1:k]);oo<-sr(a[(k+1):n]);if(is.na(is)||is<=0)return(NA);oo/is}),na.rm=TRUE)
  x<-xts(pr$ret_net,order.by=as.Date(pr$date)); ann<-prod(1+coredata(x))^(12/nrow(x))-1; mdd<-as.numeric(maxDrawdown(x)); cal<-if(is.finite(mdd)&&mdd>0) ann/mdd else NA
  ct<-res$diag_cap_tier; mega<-if(isTRUE(ct$available)) ct$weight_share_avg$MEGA else NA; mid<-if(isTRUE(ct$available)) ct$weight_share_avg$MID else NA
  list(port_t=res$portfolio_alpha_t_nw_lag3, ew_uni_t=res$diag_ew_universe$portfolio_alpha_t_nw_lag3,
       net_sr=res$net_sr, oos_ret=oos, calmar=cal, mega_w=mega, mid_w=mid, TO=res$turnover_annual, n=res$n_months, pr=pr)
}
runbt <- function(score_dt) suppressWarnings(canonical_screen_bt(score_dt[!is.na(score),.(Date,Ticker,score)], .Rg,.BMg,
   top_n=25L, cost_bps_oneway=15, liq_dt=.LQg, liq_min=2e8, run_id="ffs", strategy_id="ffs",
   periods_per_year=12L, diag_dual_basis=TRUE, size_dt=SZ))
pr1 <- function(lab,m) cat(sprintf("%-24s PORT_t=%.3f ew_uni=%.3f net_sr=%.3f oos=%.3f calmar=%.3f mega_w=%.4f mid_w=%.4f TO=%.1f n=%d\n",
   lab, m$port_t, m$ew_uni_t, m$net_sr, m$oos_ret, m$calmar, m$mega_w, m$mid_w, m$TO, m$n))

# ---- baseline quality (control, measured identically) ----
m_q <- metr(runbt(.FAM[,.(Date,Ticker,score=quality)]))
pr1("quality_baseline(FAM)", m_q)

# ---- as-of join consensus onto ALL FAM month-end dates (Date<=sig_date, PIT) ----
grid <- .FAM[,.(Date,Ticker)]
asof <- function(metric){
  d <- as.data.table(read_parquet(file.path(cc,paste0(metric,".parquet")))); d[,Date:=as.Date(Date)]
  d <- d[Date <= max(grid$Date)]; setnames(d, metric, "val"); setkey(d,Ticker,Date)
  g <- copy(grid); setkey(g,Ticker,Date)
  r <- d[g, roll=TRUE]; r[,.(Date,Ticker,val)]
}
P <- copy(grid)
for(m in c("eps_1y","bps_1y","eps_chg_1m","eps_chg_3m","esbr","escr","sue","revenue_fy1","op_profit_fy1")){
  a <- asof(m); setnames(a,"val",m); P <- merge(P,a,by=c("Date","Ticker"),all.x=TRUE)
}

# ---- FORWARD F-SCORE (single deterministic economic hypothesis) ----
# forward op margin & forward ROE (level-quality); cross-sectional median per date (PIT: same-date only)
P[, fwd_margin := ifelse(is.finite(revenue_fy1) & abs(revenue_fy1)>1e-9, op_profit_fy1/revenue_fy1, NA_real_)]
P[, fwd_roe    := ifelse(is.finite(bps_1y) & abs(bps_1y)>1e-9, eps_1y/bps_1y, NA_real_)]
med <- function(v) { m<-median(v,na.rm=TRUE); as.numeric(v > m) }
P[, `:=`(
  b_eps_pos  = as.numeric(eps_1y > 0),
  b_op_pos   = as.numeric(op_profit_fy1 > 0),
  b_sue_pos  = as.numeric(sue > 0),
  b_rev1_up  = as.numeric(eps_chg_1m > 0),
  b_rev3_up  = as.numeric(eps_chg_3m > 0)
)]
P[, b_breadth := med(esbr),    by=Date]
P[, b_margin  := med(fwd_margin), by=Date]
P[, b_roe     := med(fwd_roe),  by=Date]
P[, b_consist := med(escr),     by=Date]
bcols <- c("b_eps_pos","b_op_pos","b_sue_pos","b_rev1_up","b_rev3_up","b_breadth","b_margin","b_roe","b_consist")
P[, n_avail := rowSums(!is.na(.SD)), .SDcols=bcols]
P[, ffs_frac := rowSums(.SD, na.rm=TRUE), .SDcols=bcols]   # sum of satisfied
P[, ffs := ifelse(n_avail>=6, ffs_frac / n_avail, NA_real_)] # fraction satisfied, require >=6 comps
cat(sprintf("\n[panel] rows=%d  ffs non-NA=%d (%.1f%%)  median n_avail=%.0f  span %s~%s\n",
   nrow(P), sum(!is.na(P$ffs)), 100*mean(!is.na(P$ffs)), median(P$n_avail), min(P$Date), max(P$Date)))

# ---- measure forward F-score ----
m_f <- metr(runbt(P[,.(Date,Ticker,score=ffs)]))
pr1("forward_fscore", m_f)

# ---- lag1 PIT stress: extra 1-month lag (use prior month-end ffs) ----
dts <- sort(unique(P$Date)); lm <- data.table(Date=dts, prevDate=shift(dts,1))[!is.na(prevDate)]
Pl <- merge(P[,.(prevDate=Date,Ticker,ffs_prev=ffs)], lm, by="prevDate", allow.cartesian=TRUE)[,.(Date,Ticker,score=ffs_prev)]
m_l <- metr(runbt(Pl))
pr1("forward_fscore_LAG1", m_l)

# save panel + returns for orthogonality step
saveRDS(list(P=P[,.(Date,Ticker,ffs)], pr_f=m_f$pr, pr_q=m_q$pr, m_f=m_f, m_q=m_q, m_l=m_l),
        file.path(root,"stage_artifacts/ffs_build.rds"))
cat("\nCAPW_REALIZABLE (PORT_t>0.385 & mega_w>0.042): ",
    (m_f$port_t>0.385 && isTRUE(m_f$mega_w>0.042)), "\n")
cat(sprintf("  fwd PORT_t=%.3f vs 0.385 ; fwd mega_w=%.4f vs base %.4f (0.042 ref)\n",
    m_f$port_t, m_f$mega_w, m_q$mega_w))
