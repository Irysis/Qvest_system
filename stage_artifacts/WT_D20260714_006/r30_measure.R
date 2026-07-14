## ============================================================================
## R30 (FQ-045, WT-D20260714_006) — value 잔여 소비면 실측
##   Branch A: clean Z6 / pure-value EW-상대 배포성 실사 (D3 dossier form)
##   Branch B: MID-tier 조건부 value 슬로팅 (B1 MID-only / B2 MID+OTHER), cap-w authoritative
## Consumes: recon_panels(R28) + value_panels(R29) + screen_inputs(R28) + P-pure holdings(d3).
## Base 권위: 0_stored_S7 = production_parity_verified clean(off0 T-1). READ-ONLY 05_Production/outputs.
## ============================================================================
suppressPackageStartupMessages({library(arrow); library(data.table); library(sandwich); library(lmtest)})
setDTthreads(1); try(arrow::set_cpu_count(1), silent=TRUE); try(arrow::set_io_thread_count(2), silent=TRUE)
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
WT <- file.path(QM,"stage_artifacts/WT_D20260714_006")
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
oos3<-function(a,frac=c(0.55,0.65,0.75)){a<-a[is.finite(a)];n<-length(a);if(n<24)return(NA_real_)
  sr<-function(x){if(length(x)<6)return(NA_real_);s<-sd(x);if(!is.finite(s)||s<=0)return(NA_real_);mean(x)/s*sqrt(12)}
  r<-sapply(frac,function(f){k<-floor(n*f);if(k<6||(n-k)<6)return(NA_real_);is<-sr(a[1:k]);oo<-sr(a[(k+1):n])
    if(is.na(is)||is.na(oo)||is<=0)return(NA_real_);oo/is}); if(all(is.na(r)))NA_real_ else median(r,na.rm=TRUE)}
IS_END <- as.Date("2024-06-30"); W_BLEND <- 0.30; PART_RATE <- 0.10

## ---- inputs ----
PAN <- as.data.table(read_parquet(file.path(QM,"stage_artifacts/WT_D20260714_004/recon_panels.parquet"))); PAN[,Date:=as.Date(Date)]
VP  <- as.data.table(read_parquet(file.path(QM,"stage_artifacts/WT_D20260714_005/value_panels.parquet"))); VP[,Date:=as.Date(Date)]
SI  <- readRDS(file.path(QM,"stage_artifacts/WT_D20260714_004/screen_inputs.rds"))
fwd_ret<-SI$fwd_ret; bench<-SI$bench; liqf<-SI$liqf; SIZE<-SI$SIZE
FR <- fwd_ret[,.(Date,Ticker,Ret_1m)]
DT <- merge(PAN[,.(Date,Ticker,`0_stored_S7`,`0_ic_S7`)], VP[,.(Date,Ticker,vz_off0)], by=c("Date","Ticker"), all.x=TRUE)

## cap-tier per month from SIZE (MEGA 1-10 / MID 11-30 / OTHER 31+), on full size universe
ST <- SIZE[!is.na(Size),.(Date,Ticker,Size)]; setorder(ST,Date,-Size); ST[,cap_rank:=seq_len(.N),by=Date]
ST[,tier:=fifelse(cap_rank<=10L,"MEGA",fifelse(cap_rank<=30L,"MID","OTHER"))]
DT <- merge(DT, ST[,.(Date,Ticker,tier)], by=c("Date","Ticker"), all.x=TRUE)
DT[is.na(tier),tier:="OTHER"]

## ---- cap-w top-25 weights from a score column (R29 mk_capw verbatim) ----
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

## ============================================================================
## BRANCH B — MID-tier conditional value slotting (cap-w authoritative)
## ============================================================================
cat("\n========== BRANCH B — MID-tier conditional value slotting ==========\n")
## clean base cap-w top-25 (paired baseline)
BASE <- screen_capw(DT, "0_stored_S7", "R30_base_clean_stored")
cat(sprintf("[BASE clean 0_stored_S7] cap-w PORT_t=%.3f IR=%.3f n=%d TO=%.1f\n",
  BASE$res$portfolio_alpha_t_nw_lag3, BASE$res$information_ratio, BASE$res$n_months, BASE$res$turnover_annual))

## build conditional-tier blend score on DT: base_z + w*value_z boosted only on tier set
add_cond_blend <- function(dt, basecol, valcol, tiers, w=W_BLEND, out="csc"){
  d <- copy(dt[is.finite(get(basecol)), .(Date,Ticker,tier, b=get(basecol), v=get(valcol))])
  d[, b_z := zc(b), by=Date]
  d[, v_z := zc(v), by=Date]; d[is.na(v_z), v_z := 0]
  d[, v_boost := fifelse(tier %in% tiers, v_z, 0)]      # value 부스트 tier-조건부
  d[, (out) := (1-w)*b_z + w*v_boost]
  d[,.(Date,Ticker,csc=get(out))]
}
B_cells <- list(
  list(id="B1_MID_only",  tiers="MID"),
  list(id="B2_MID_OTHER", tiers=c("MID","OTHER"))
)
b_rows <- list(); b_prmap <- list()
for(cl in B_cells){
  bl <- add_cond_blend(DT, "0_stored_S7", "vz_off0", cl$tiers, w=W_BLEND)
  bdt <- merge(DT[,.(Date,Ticker)], bl, by=c("Date","Ticker"), all.x=TRUE)
  sv <- screen_capw(bdt, "csc", paste0("R30_",cl$id)); if(is.null(sv)) next
  m <- merge(sv$pr[,.(date,va=active)], BASE$pr[,.(date,ba=active)], by="date")
  paired <- nw_t(m$va-m$ba); dIR <- IR_ann(m$va)-IR_ann(m$ba); cor_act<-suppressWarnings(cor(m$va,m$ba))
  is_m<-m[date<=IS_END]; ho_m<-m[date>IS_END]
  paired_is<-nw_t(is_m$va-is_m$ba); paired_ho<-nw_t(ho_m$va-ho_m$ba)
  dIR_is<-IR_ann(is_m$va)-IR_ann(is_m$ba); dIR_ho<-IR_ann(ho_m$va)-IR_ann(ho_m$ba)
  p17<-m$date>=as.Date("2017-01-01"); post17<-nw_t((m$va-m$ba)[p17])
  ## lag1 value-shift stress
  d1 <- copy(DT[is.finite(`0_stored_S7`),.(Date,Ticker,tier,b=`0_stored_S7`,v=vz_off0)])
  dts<-sort(unique(DT$Date)); vv<-copy(DT[is.finite(vz_off0),.(Date,Ticker,v=vz_off0)]); idx<-match(vv$Date,dts)
  vv[,Date:=dts[pmin(idx+1L,length(dts))]]; vv<-unique(vv,by=c("Date","Ticker"))
  d1[,v:=NULL]; d1<-merge(d1,vv,by=c("Date","Ticker"),all.x=TRUE)
  d1[,b_z:=zc(b),by=Date]; d1[,v_z:=zc(v),by=Date]; d1[is.na(v_z),v_z:=0]
  d1[,v_boost:=fifelse(tier %in% cl$tiers,v_z,0)]; d1[,csc:=(1-W_BLEND)*b_z+W_BLEND*v_boost]
  b1dt<-merge(DT[,.(Date,Ticker)],d1[,.(Date,Ticker,csc)],by=c("Date","Ticker"),all.x=TRUE)
  sv1<-screen_capw(b1dt,"csc",paste0("R30lag1_",cl$id)); paired_lag1<-NA_real_
  if(!is.null(sv1)){m1<-merge(sv1$pr[,.(date,va=active)],BASE$pr[,.(date,ba=active)],by="date");paired_lag1<-nw_t(m1$va-m1$ba)}
  ## dual-basis EW-uni on the conditional blend
  ews <- tryCatch(canonical_screen_bt(bdt[is.finite(csc),.(Date,Ticker,score=csc)], FR, bench, top_n=25L,
          cost_bps_oneway=15, liq_dt=liqf[,.(Date,Ticker,adv)], liq_min=2e8, run_id=paste0("ew_",cl$id),
          strategy_id=paste0("ew_",cl$id), size_dt=SIZE, diag_dual_basis=TRUE), error=function(e) NULL)
  ewuni_pt<-if(!is.null(ews))ews$diag_ew_universe$portfolio_alpha_t_nw_lag3 else NA_real_
  ewuni_oos<-if(!is.null(ews))ews$diag_ew_universe$oos_retention_approx else NA_real_
  ## cap-tier weight share of the variant (does value pull MID names in?)
  ct <- if(!is.null(ews)) ews$diag_cap_tier$weight_share_avg else NULL
  gate_pass <- isTRUE(paired>=2.0) && isTRUE(dIR>=0.05)
  b_rows[[cl$id]] <- data.table(cell=cl$id, tiers=paste(cl$tiers,collapse="+"),
    base_port_t=BASE$res$portfolio_alpha_t_nw_lag3, variant_port_t=sv$res$portfolio_alpha_t_nw_lag3,
    paired_full=paired, paired_is=paired_is, paired_ho=paired_ho,
    dIR_full=dIR, dIR_is=dIR_is, dIR_ho=dIR_ho, post2017_t=post17, paired_lag1=paired_lag1,
    cor_active=cor_act, turnover=sv$res$turnover_annual, n=nrow(m),
    ewuni_port_t=ewuni_pt, ewuni_oos=ewuni_oos,
    wshare_MEGA=if(!is.null(ct))ct$MEGA else NA_real_, wshare_MID=if(!is.null(ct))ct$MID else NA_real_,
    wshare_OTHER=if(!is.null(ct))ct$OTHER else NA_real_,
    AND_gate=gate_pass)
  b_prmap[[cl$id]] <- sv$pr
  cat(sprintf("[B %s tiers=%s] var_pt=%.2f paired=%.3f(IS %.3f/HO %.3f) dIR=%.3f lag1=%.3f post17=%.2f ewuni=%.2f oos=%.2f TO=%.1f | wMID=%.2f | AND=%s\n",
    cl$id, paste(cl$tiers,collapse="+"), sv$res$portfolio_alpha_t_nw_lag3, paired, paired_is, paired_ho, dIR, paired_lag1, post17, ewuni_pt, ewuni_oos, sv$res$turnover_annual,
    if(!is.null(ct))ct$MID else NA_real_, gate_pass))
}
BG <- rbindlist(b_rows, fill=TRUE)
cat("\n----- R30 Branch B grid (cap-w authoritative, base clean 0_stored_S7) -----\n")
print(BG[,.(cell,base_pt=round(base_port_t,2),var_pt=round(variant_port_t,2),paired=round(paired_full,3),
  IS=round(paired_is,3),HO=round(paired_ho,3),dIR=round(dIR_full,3),lag1=round(paired_lag1,3),
  post17=round(post2017_t,2),ewuni=round(ewuni_port_t,2),wMID=round(wshare_MID,3),AND=AND_gate)])
cat(sprintf("\nR29 PRIMARY (unconditional value all-tier): paired 1.243 dIR +0.153 var_pt 3.85 ewuni 6.39\n"))
save_safe(BG, file.path(WT,"branchB_grid.parquet"), function(o,p) write_parquet(o,p))
saveRDS(b_prmap, file.path(WT,"branchB_prmap.rds"))
cat("BRANCH_B_DONE\n")
