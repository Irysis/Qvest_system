## ============================================================================
## R29 (FQ-044) Stage 2 — Z6 value-blend screen across base×value vintage 2x2
## Consumes recon_panels(R28) + value_panels(R29) + screen_inputs(R28).
## Z6 recipe (R27 verbatim): blend = (1-w)*zc(base) + w*zc(value), w=0.30, value NA->0.
## paired NW-t(lag3) vs SAME-vintage base (w=0), ΔIR window-matched, dual-basis EW-uni,
## holdout(IS<=2024-06 / HO 2024-07..2026-04), lag1 value-shift stress.
## ============================================================================
suppressPackageStartupMessages({library(arrow); library(data.table); library(sandwich); library(lmtest)})
setDTthreads(1); try(arrow::set_io_thread_count(2), silent=TRUE)
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
WT <- file.path(QM,"stage_artifacts/WT_D20260714_005")
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
IS_END <- as.Date("2024-06-30"); W_BLEND <- 0.30

PAN <- as.data.table(read_parquet(file.path(QM,"stage_artifacts/WT_D20260714_004/recon_panels.parquet"))); PAN[,Date:=as.Date(Date)]
VP  <- as.data.table(read_parquet(file.path(WT,"value_panels.parquet"))); VP[,Date:=as.Date(Date)]
SI  <- readRDS(file.path(QM,"stage_artifacts/WT_D20260714_004/screen_inputs.rds"))
fwd_ret<-SI$fwd_ret; bench<-SI$bench; liqf<-SI$liqf; SIZE<-SI$SIZE
FR <- fwd_ret[,.(Date,Ticker,Ret_1m)]

DT <- merge(PAN, VP, by=c("Date","Ticker"), all.x=TRUE)

## cap-w top-25 weights from a score column-vector already on DT
mk_capw <- function(dt, scorecol){
  S <- merge(dt[is.finite(get(scorecol)),.(Date,Ticker,sc=get(scorecol))], SIZE, by=c("Date","Ticker"))
  S <- merge(S, liqf, by=c("Date","Ticker"), all.x=TRUE); S <- S[is.na(adv)|adv>=2e8]
  dd <- sort(unique(S$Date)); W<-list()
  for(i in seq_along(dd)){d<-dd[i]; sub<-S[Date==d]; if(nrow(sub)<25) next
    setorder(sub,-sc); hd<-head(sub,25); W[[as.character(d)]]<-data.table(Date=d,Ticker=hd$Ticker,w=cap_norm(hd$Size))}
  rbindlist(W)}

## screen a score column -> list(pr(active per month), res)
screen_col <- function(dt, scorecol, tag){
  W <- mk_capw(dt, scorecol); if(nrow(W)==0) return(NULL)
  res <- weighted_screen_bt(W, fwd_ret, bench, cost_bps_oneway=15, run_id=tag, strategy_id=tag)
  pr <- as.data.table(res$period_returns); pr[,active:=ret_net-benchmark_ret]
  list(pr=pr, res=res)}

## build Z6 blend column on DT for (base col, value col), optional value lag (months)
add_blend <- function(dt, basecol, valcol, w=W_BLEND, val_lag=0L, out="blend"){
  d <- copy(dt[is.finite(get(basecol)), .(Date,Ticker, b=get(basecol), v=get(valcol))])
  if(val_lag>0L){  ## shift value val_lag months earlier (strictly PIT-safe stress)
    vv <- copy(dt[is.finite(get(valcol)),.(Date,Ticker,v=get(valcol))])
    dts <- sort(unique(dt$Date)); idx <- match(vv$Date, dts)
    vv[, Date := dts[pmin(idx+val_lag, length(dts))]]   ## carry value forward val_lag months
    vv <- unique(vv, by=c("Date","Ticker"))
    d[, v:=NULL]; d <- merge(d, vv, by=c("Date","Ticker"), all.x=TRUE)
  }
  d[, b_z := zc(b), by=Date]; d[, v_z := zc(v), by=Date]; d[is.na(v_z), v_z := 0]
  d[, (out) := (1-w)*b_z + w*v_z]
  d[,.(Date,Ticker,blend=get(out))]
}

## ---- base screens (w=0, per vintage) ----
base_cols <- c(clean_stored="0_stored_S7", clean_ic="0_ic_S7", la_stored="1_stored_S7", la_ic="1_ic_S7")
BASE <- list()
for(nm in names(base_cols)){ r <- screen_col(DT, base_cols[[nm]], paste0("base_",nm)); BASE[[nm]] <- r
  cat(sprintf("[BASE %s=%s] PORT_t=%.3f IR=%.3f n=%d TO=%.1f\n", nm, base_cols[[nm]],
    r$res$portfolio_alpha_t_nw_lag3, r$res$information_ratio, r$res$n_months, r$res$turnover_annual)) }

## ---- Z6 variant cells: base vintage x value vintage ----
cells <- list(
  list(id="PRIMARY_clean_base_clean_val", base="clean_stored", basecol="0_stored_S7", valcol="vz_off0"),
  list(id="clean_base_prod_ic_clean_val", base="clean_ic",     basecol="0_ic_S7",     valcol="vz_off0"),
  list(id="clean_base_LA_val",            base="clean_stored", basecol="0_stored_S7", valcol="vz_off1"),
  list(id="clean_base_pfs_val",           base="clean_stored", basecol="0_stored_S7", valcol="vz_pfs"),
  list(id="LA_base_LA_val_refR27",        base="la_stored",    basecol="1_stored_S7", valcol="vz_off1"),
  list(id="LA_base_clean_val",            base="la_stored",    basecol="1_stored_S7", valcol="vz_off0"),
  list(id="LA_base_ic_LA_val",            base="la_ic",        basecol="1_ic_S7",     valcol="vz_off1")
)
res_rows <- list()
prmap <- list()
for(cl in cells){
  bl <- add_blend(DT, cl$basecol, cl$valcol, w=W_BLEND, val_lag=0L)
  bdt <- merge(DT[,.(Date,Ticker)], bl, by=c("Date","Ticker"), all.x=TRUE)
  sv <- screen_col(bdt, "blend", paste0("Z6_",cl$id)); if(is.null(sv)) next
  bpr <- BASE[[cl$base]]$pr
  m <- merge(sv$pr[,.(date,va=active)], bpr[,.(date,ba=active)], by="date")
  paired <- nw_t(m$va-m$ba); dIR <- IR_ann(m$va)-IR_ann(m$ba); cor_act <- suppressWarnings(cor(m$va,m$ba))
  is_m <- m[date<=IS_END]; ho_m <- m[date>IS_END]
  paired_is<-nw_t(is_m$va-is_m$ba); paired_ho<-nw_t(ho_m$va-ho_m$ba)
  dIR_is<-IR_ann(is_m$va)-IR_ann(is_m$ba); dIR_ho<-IR_ann(ho_m$va)-IR_ann(ho_m$ba)
  p17<-m$date>=as.Date("2017-01-01"); post17<-nw_t((m$va-m$ba)[p17])
  ## lag1 stress
  bl1 <- add_blend(DT, cl$basecol, cl$valcol, w=W_BLEND, val_lag=1L)
  b1dt <- merge(DT[,.(Date,Ticker)], bl1, by=c("Date","Ticker"), all.x=TRUE)
  sv1 <- screen_col(b1dt, "blend", paste0("Z6lag1_",cl$id))
  paired_lag1 <- NA_real_
  if(!is.null(sv1)){ m1<-merge(sv1$pr[,.(date,va=active)], bpr[,.(date,ba=active)], by="date"); paired_lag1<-nw_t(m1$va-m1$ba) }
  ## dual-basis EW-uni on the blend
  ews <- tryCatch(canonical_screen_bt(bdt[is.finite(blend),.(Date,Ticker,score=blend)], FR, bench, top_n=25L,
          cost_bps_oneway=15, liq_dt=liqf[,.(Date,Ticker,adv)], liq_min=2e8, run_id=paste0("ew_",cl$id),
          strategy_id=paste0("ew_",cl$id), size_dt=SIZE, diag_dual_basis=TRUE), error=function(e) NULL)
  ewuni_pt <- if(!is.null(ews)) ews$diag_ew_universe$portfolio_alpha_t_nw_lag3 else NA_real_
  ewuni_post17 <- if(!is.null(ews)) ews$diag_ew_universe$post2017_t_nw_lag3 else NA_real_
  ewuni_oos <- if(!is.null(ews)) ews$diag_ew_universe$oos_retention_approx else NA_real_
  res_rows[[cl$id]] <- data.table(cell=cl$id, base=cl$base, value=cl$valcol,
    base_port_t=BASE[[cl$base]]$res$portfolio_alpha_t_nw_lag3, variant_port_t=sv$res$portfolio_alpha_t_nw_lag3,
    base_ir=BASE[[cl$base]]$res$information_ratio, variant_ir=sv$res$information_ratio,
    paired_full=paired, paired_is=paired_is, paired_ho=paired_ho,
    dIR_full=dIR, dIR_is=dIR_is, dIR_ho=dIR_ho, post2017_t=post17, paired_lag1=paired_lag1,
    cor_active=cor_act, turnover=sv$res$turnover_annual, n=nrow(m),
    ewuni_port_t=ewuni_pt, ewuni_post17_t=ewuni_post17, ewuni_oos_approx=ewuni_oos)
  prmap[[cl$id]] <- list(variant=sv$pr, base=bpr)
  cat(sprintf("[Z6 %s] var_pt=%.2f base_pt=%.2f paired_full=%.3f IS=%.3f HO=%.3f dIR=%.3f lag1=%.3f post17=%.2f ewuni_pt=%.2f oos=%.2f TO=%.1f\n",
    cl$id, sv$res$portfolio_alpha_t_nw_lag3, BASE[[cl$base]]$res$portfolio_alpha_t_nw_lag3, paired, paired_is, paired_ho, dIR, paired_lag1, post17, ewuni_pt, ewuni_oos, sv$res$turnover_annual))
}
GD <- rbindlist(res_rows, fill=TRUE)
cat("\n===== R29 Z6 vintage 2x2 grid =====\n"); print(GD[,.(cell,base_pt=round(base_port_t,2),var_pt=round(variant_port_t,2),
  paired=round(paired_full,3),IS=round(paired_is,3),HO=round(paired_ho,3),dIR=round(dIR_full,3),lag1=round(paired_lag1,3),post17=round(post2017_t,2),ewuni=round(ewuni_port_t,2))])
save_safe(GD, file.path(WT,"z6_vintage_grid.parquet"), function(o,p) write_parquet(o,p))
saveRDS(prmap, file.path(WT,"z6_prmap.rds"))
cat("\nGATE (PIT-clean primary): paired>=2.0 AND dIR>=0.05.  R27 reference (LA base): paired 3.807.\n")
cat("SCREEN_DONE\n")
