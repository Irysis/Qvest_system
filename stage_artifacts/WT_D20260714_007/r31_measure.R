## ============================================================================
## R31 (FQ-047) Stage 2 — B2 (non-mega tier-conditional value tilt) per sub-axis.
##   cap-w top-25 authoritative screening. base = clean 0_stored_S7. B2 verbatim from R30.
##   Adds recency axis: paired pre-2024 vs 2024+ (FQ-046 found EBIT/EV pre +3.96 -> post -1.67).
## ============================================================================
suppressPackageStartupMessages({library(arrow); library(data.table); library(sandwich); library(lmtest)})
setDTthreads(1); try(arrow::set_cpu_count(1), silent=TRUE); try(arrow::set_io_thread_count(2), silent=TRUE)
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
WT <- file.path(QM,"stage_artifacts/WT_D20260714_007")
source(file.path(QM,"02_Infrastructure/contracts/weighted_screen_bt.R"))
source(file.path(QM,"02_Infrastructure/contracts/canonical_screen_bt.R"))
save_safe <- function(obj, path, writer){tmp<-paste0(path,".tmp_",Sys.getpid()); writer(obj,tmp)
  if(file.exists(path))file.remove(path); if(!file.rename(tmp,path))stop("rename ",path)}
zc <- function(x){m<-mean(x,na.rm=TRUE);s<-sd(x,na.rm=TRUE);if(is.na(s)||s<1e-9)x-m else (x-m)/s}
cap_norm<-function(w){w[!is.finite(w)|w<0]<-0;if(sum(w)<=0)return(rep(1/length(w),length(w)));w<-w/sum(w)
  for(it in 1:50){if(all(w<=0.2000001))break;w[w>0.20]<-0.20;rem<-1-sum(w);ix<-w<0.20
    if(sum(ix)==0||rem<=0)break;w[ix]<-w[ix]+rem*w[ix]/sum(w[ix])};w[w>0.20]<-0.20;w/sum(w)}
nw_t<-function(x,lag=3L){x<-x[is.finite(x)];if(length(x)<8)return(NA_real_);fit<-lm(x~1)
  se<-sqrt(NeweyWest(fit,lag=lag,prewhite=FALSE)[1,1]);unname(coef(fit)[1]/se)}
IR_ann<-function(v){v<-v[is.finite(v)];if(length(v)<6)return(NA_real_);s<-sd(v);if(!is.finite(s)||s<=0)return(NA_real_);mean(v)/s*sqrt(12)}
W_BLEND <- 0.30; IS_END <- as.Date("2024-06-30"); Y24 <- as.Date("2024-01-01")

## ---- inputs ----
PAN <- as.data.table(read_parquet(file.path(QM,"stage_artifacts/WT_D20260714_004/recon_panels.parquet"))); PAN[,Date:=as.Date(Date)]
SP7 <- as.data.table(read_parquet(file.path(WT,"subaxis_panels.parquet"))); SP7[,Date:=as.Date(Date)]
SI  <- readRDS(file.path(QM,"stage_artifacts/WT_D20260714_004/screen_inputs.rds"))
fwd_ret<-SI$fwd_ret; bench<-SI$bench; liqf<-SI$liqf; SIZE<-SI$SIZE
FR <- fwd_ret[,.(Date,Ticker,Ret_1m)]
AX <- c("BM","EP","CFP","FCF","SP","SHY","EBIT_EV")

DT <- merge(PAN[,.(Date,Ticker,`0_stored_S7`)], SP7[,c("Date","Ticker",AX),with=FALSE], by=c("Date","Ticker"), all.x=TRUE)
## cap-tier per month (MEGA 1-10 / MID 11-30 / OTHER 31+)
ST <- SIZE[!is.na(Size),.(Date,Ticker,Size)]; setorder(ST,Date,-Size); ST[,cap_rank:=seq_len(.N),by=Date]
ST[,tier:=fifelse(cap_rank<=10L,"MEGA",fifelse(cap_rank<=30L,"MID","OTHER"))]
DT <- merge(DT, ST[,.(Date,Ticker,tier)], by=c("Date","Ticker"), all.x=TRUE); DT[is.na(tier),tier:="OTHER"]

mk_capw <- function(dt, scorecol){
  S <- merge(dt[is.finite(get(scorecol)),.(Date,Ticker,sc=get(scorecol))], SIZE, by=c("Date","Ticker"))
  S <- merge(S, liqf, by=c("Date","Ticker"), all.x=TRUE); S <- S[is.na(adv)|adv>=2e8]
  dd <- sort(unique(S$Date)); W<-list()
  for(i in seq_along(dd)){d<-dd[i]; sub<-S[Date==d]; if(nrow(sub)<25) next
    setorder(sub,-sc); hd<-head(sub,25); W[[as.character(d)]]<-data.table(Date=d,Ticker=hd$Ticker,w=cap_norm(hd$Size))}
  rbindlist(W)}
screen_capw <- function(dt, scorecol, tag){
  W <- mk_capw(dt, scorecol); if(nrow(W)==0) return(NULL)
  res <- weighted_screen_bt(W, fwd_ret, bench, cost_bps_oneway=15, run_id=tag, strategy_id=tag)
  pr <- as.data.table(res$period_returns); pr[,active:=ret_net-benchmark_ret]
  list(pr=pr, res=res, W=W)}
## B2 conditional blend: base_z + w*value_z boosted only on non-mega tiers
add_cond_blend <- function(dt, valcol, tiers=c("MID","OTHER"), w=W_BLEND){
  d <- copy(dt[is.finite(`0_stored_S7`), .(Date,Ticker,tier, b=`0_stored_S7`, v=get(valcol))])
  d[, b_z := zc(b), by=Date]; d[, v_z := zc(v), by=Date]; d[is.na(v_z), v_z := 0]
  d[, v_boost := fifelse(tier %in% tiers, v_z, 0)]
  d[, csc := (1-w)*b_z + w*v_boost]
  d[,.(Date,Ticker,csc)]
}

## ---- base ----
BASE <- screen_capw(DT, "0_stored_S7", "R31_base_clean")
cat(sprintf("[BASE clean 0_stored_S7] cap-w PORT_t=%.3f IR=%.3f n=%d TO=%.1f\n",
  BASE$res$portfolio_alpha_t_nw_lag3, BASE$res$information_ratio, BASE$res$n_months, BASE$res$turnover_annual))
BA <- BASE$pr[,.(date,ba=active)]

## ---- per sub-axis B2 ----
rows <- list(); prmap <- list()
for(sx in AX){
  bl <- add_cond_blend(DT, sx)
  bdt <- merge(DT[,.(Date,Ticker)], bl, by=c("Date","Ticker"), all.x=TRUE)
  sv <- screen_capw(bdt, "csc", paste0("R31_",sx)); if(is.null(sv)){cat(sx," NULL\n"); next}
  m <- merge(sv$pr[,.(date,va=active)], BA, by="date"); m[,dd:=va-ba]
  paired <- nw_t(m$dd); dIR <- IR_ann(m$va)-IR_ann(m$ba); cor_act<-suppressWarnings(cor(m$va,m$ba))
  is_m<-m[date<=IS_END]; ho_m<-m[date>IS_END]
  paired_is<-nw_t(is_m$dd); paired_ho<-nw_t(ho_m$dd)
  ## recency: pre-2024 vs 2024+
  pre<-m[date<Y24]; post<-m[date>=Y24]
  paired_pre<-nw_t(pre$dd); paired_post<-nw_t(post$dd)
  dIR_pre<-IR_ann(pre$va)-IR_ann(pre$ba); dIR_post<-IR_ann(post$va)-IR_ann(post$ba)
  meandd_pre<-mean(pre$dd,na.rm=TRUE)*1200; meandd_post<-mean(post$dd,na.rm=TRUE)*1200  # ann bp
  p17<-m$date>=as.Date("2017-01-01"); post17<-nw_t(m$dd[p17])
  ## dual-basis EW-uni
  ews <- tryCatch(canonical_screen_bt(bdt[is.finite(csc),.(Date,Ticker,score=csc)], FR, bench, top_n=25L,
          cost_bps_oneway=15, liq_dt=liqf[,.(Date,Ticker,adv)], liq_min=2e8, run_id=paste0("ew_",sx),
          strategy_id=paste0("ew_",sx), size_dt=SIZE, diag_dual_basis=TRUE), error=function(e) NULL)
  ewuni_pt<-if(!is.null(ews))ews$diag_ew_universe$portfolio_alpha_t_nw_lag3 else NA_real_
  ewuni_oos<-if(!is.null(ews))ews$diag_ew_universe$oos_retention_approx else NA_real_
  gate_pass <- isTRUE(paired>=2.0) && isTRUE(dIR>=0.05)
  rows[[sx]] <- data.table(subaxis=sx, base_port_t=BASE$res$portfolio_alpha_t_nw_lag3,
    variant_port_t=sv$res$portfolio_alpha_t_nw_lag3, paired_full=paired,
    paired_is=paired_is, paired_ho=paired_ho, paired_pre2024=paired_pre, paired_post2024=paired_post,
    dIR_full=dIR, dIR_pre2024=dIR_pre, dIR_post2024=dIR_post,
    meandd_pre_bp=meandd_pre, meandd_post_bp=meandd_post,
    post2017_t=post17, cor_active=cor_act, turnover=sv$res$turnover_annual, n=nrow(m),
    ewuni_port_t=ewuni_pt, ewuni_oos=ewuni_oos, AND_gate=gate_pass)
  prmap[[sx]] <- m
  cat(sprintf("[%-8s] var_pt=%.2f paired=%.3f (pre24 %.2f / post24 %.2f | IS %.2f/HO %.2f) dIR=%.3f(pre %.3f/post %.3f) meandd pre=%.0f/post=%.0fbp post17=%.2f cor=%.3f ew=%.2f/oos%.2f AND=%s\n",
    sx, sv$res$portfolio_alpha_t_nw_lag3, paired, paired_pre, paired_post, paired_is, paired_ho,
    dIR, dIR_pre, dIR_post, meandd_pre, meandd_post, post17, cor_act, ewuni_pt, ewuni_oos, gate_pass))
}
RG <- rbindlist(rows, fill=TRUE)
cat("\n----- R31 sub-axis B2 grid (cap-w authoritative, base clean 0_stored_S7) -----\n")
print(RG[,.(subaxis,var_pt=round(variant_port_t,2),paired=round(paired_full,3),
  pre24=round(paired_pre2024,2),post24=round(paired_post2024,2),
  dIR=round(dIR_full,3),dIRpost=round(dIR_post2024,3),post17=round(post2017_t,2),
  cor=round(cor_active,3),ew=round(ewuni_port_t,2),AND=AND_gate)])
cat(sprintf("\nR30 EBIT_EV B2 reference: paired 2.378 dIR +0.232 var_pt 4.23 post17 1.73 ewuni 6.59 (HO 1.17, holdout dIR -0.022)\n"))
save_safe(RG, file.path(WT,"subaxis_b2_grid.parquet"), function(o,p) write_parquet(o,p))
saveRDS(prmap, file.path(WT,"subaxis_prmap.rds"))
saveRDS(list(base_port_t=BASE$res$portfolio_alpha_t_nw_lag3, base_ir=BASE$res$information_ratio,
             base_to=BASE$res$turnover_annual, ba=BA), file.path(WT,"base_ref.rds"))
cat("MEASURE_DONE\n")
