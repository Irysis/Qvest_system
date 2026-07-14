## ============================================================================
## R30 Branch A — EW-상대 배포성 실사 (D3 dossier form) + Branch B 강건성(oos/placebo)
##   A object: clean Z6 blend (0_stored_S7 + vz_off0 w0.30) EW top-25 track
##             + clean pure-value(vz_off0) EW top-25 track (정직 standalone value #3 후보)
##   B robust: B2(non-mega) cap-w oos_retention v2 + placebo(value shuffle) — 선택후 진단(신규 trial 아님)
## READ-ONLY. outputs/ramp 무접촉. stage_artifacts/WT_D20260714_006만.
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

PAN <- as.data.table(read_parquet(file.path(QM,"stage_artifacts/WT_D20260714_004/recon_panels.parquet"))); PAN[,Date:=as.Date(Date)]
VP  <- as.data.table(read_parquet(file.path(QM,"stage_artifacts/WT_D20260714_005/value_panels.parquet"))); VP[,Date:=as.Date(Date)]
SI  <- readRDS(file.path(QM,"stage_artifacts/WT_D20260714_004/screen_inputs.rds"))
fwd_ret<-SI$fwd_ret; bench<-SI$bench; liqf<-SI$liqf; SIZE<-SI$SIZE
FR <- fwd_ret[,.(Date,Ticker,Ret_1m)]
DT <- merge(PAN[,.(Date,Ticker,`0_stored_S7`)], VP[,.(Date,Ticker,vz_off0)], by=c("Date","Ticker"), all.x=TRUE)
ST <- SIZE[!is.na(Size),.(Date,Ticker,Size)]; setorder(ST,Date,-Size); ST[,cap_rank:=seq_len(.N),by=Date]
ST[,tier:=fifelse(cap_rank<=10L,"MEGA",fifelse(cap_rank<=30L,"MID","OTHER"))]
DT <- merge(DT, ST[,.(Date,Ticker,tier)], by=c("Date","Ticker"), all.x=TRUE); DT[is.na(tier),tier:="OTHER"]

## build EW top-25 track (canonical) for a score -> EW-active series + holdings + res
ew_track <- function(scoredt, tag){
  res <- canonical_screen_bt(scoredt, FR, bench, top_n=25L, cost_bps_oneway=15,
           liq_dt=liqf[,.(Date,Ticker,adv)], liq_min=2e8, run_id=tag, strategy_id=tag,
           size_dt=SIZE, diag_dual_basis=TRUE)
  ewd <- as.data.table(res$diag_ew_universe$period_returns)   # date, ret_net, ew_bench_ret, active_ew
  ## reconstruct holdings (EW top-25 with liq filter) to compute capacity/overlap
  S <- merge(scoredt[is.finite(score)], liqf[,.(Date,Ticker,adv)], by=c("Date","Ticker"), all.x=TRUE)
  S <- S[is.na(adv)|adv>=2e8]; setorder(S,Date,-score)
  W <- S[,{n<-min(25L,.N); .(Ticker=Ticker[seq_len(n)], w=rep(1/n,n))}, by=Date]
  list(res=res, ewd=ewd, W=W)}

cat("\n========== BRANCH A — EW-relative deployability audit ==========\n")
## A1: clean Z6 blend (book+value) EW track
blZ <- copy(DT[is.finite(`0_stored_S7`),.(Date,Ticker,b=`0_stored_S7`,v=vz_off0)])
blZ[,b_z:=zc(b),by=Date]; blZ[,v_z:=zc(v),by=Date]; blZ[is.na(v_z),v_z:=0]; blZ[,score:=(1-W_BLEND)*b_z+W_BLEND*v_z]
A_Z6 <- ew_track(blZ[,.(Date,Ticker,score)], "R30A_Z6ew")
## A2: clean pure-value EW track (정직 standalone value #3)
blV <- copy(DT[is.finite(vz_off0),.(Date,Ticker,score=vz_off0)])
A_V  <- ew_track(blV, "R30A_pureVal_ew")

trk_summary <- function(A, label){
  ae <- A$ewd$active_ew
  dt <- data.table(track=label,
    ewuni_port_t = A$res$diag_ew_universe$portfolio_alpha_t_nw_lag3,
    ewuni_ir     = A$res$diag_ew_universe$information_ratio,
    ewuni_oos_v2 = oos3(ae),
    ewuni_post17_t = A$res$diag_ew_universe$post2017_t_nw_lag3,
    te_ew_ann    = sd(ae)*sqrt(12),
    n_months     = A$res$diag_ew_universe$n_months,
    turnover_ann = A$res$turnover_annual,
    capw_port_t  = A$res$portfolio_alpha_t_nw_lag3)   # cap-w basis (authoritative, for context)
  cat(sprintf("[A %s] EWuni_t=%.3f IR=%.3f oos_v2=%.3f post17=%.2f TE=%.4f TO=%.1f | capw_t=%.3f n=%d\n",
    label, dt$ewuni_port_t, dt$ewuni_ir, dt$ewuni_oos_v2, dt$ewuni_post17_t, dt$te_ew_ann, dt$turnover_ann, dt$capw_port_t, dt$n_months))
  dt}
A_sum <- rbind(trk_summary(A_Z6,"Z6_blend_EW"), trk_summary(A_V,"pure_value_EW"))

## trailing 3-split subwindow PORT_t (decay check) on EW-active
tri_split <- function(ae, dates){
  n<-length(ae); k1<-floor(n/3); k2<-floor(2*n/3)
  c(nw_t(ae[1:k1]), nw_t(ae[(k1+1):k2]), nw_t(ae[(k2+1):n]))}
tsZ <- tri_split(A_Z6$ewd$active_ew, A_Z6$ewd$date); tsV <- tri_split(A_V$ewd$active_ew, A_V$ewd$date)
cat(sprintf("  trailing 3-split EW-t: Z6 %.2f/%.2f/%.2f | pureVal %.2f/%.2f/%.2f\n", tsZ[1],tsZ[2],tsZ[3], tsV[1],tsV[2],tsV[3]))

## ---- cost break-even (EW t) grid via traded ----
## need traded per month for EW track: recompute from holdings W
traded_of <- function(W){dts<-sort(unique(W$Date)); tr<-numeric(length(dts)); names(tr)<-as.character(dts)
  prev<-data.table(Ticker=character(0),w=numeric(0))
  for(i in seq_along(dts)){cur<-W[Date==dts[i],.(Ticker,w)]; m<-merge(cur,prev,by="Ticker",all=TRUE,suffixes=c("_c","_p"))
    m[is.na(w_c),w_c:=0]; m[is.na(w_p),w_p:=0]; tr[i]<-sum(abs(m$w_c-m$w_p)); prev<-cur}
  data.table(date=as.Date(names(tr)), traded=tr)}
cost_grid <- function(A, label){
  tr <- traded_of(A$W); pe <- merge(A$ewd[,.(date,active_ew)], tr, by="date", all.x=TRUE); pe[is.na(traded),traded:=0]
  rows<-list(); for(b in c(15,20,30,40,50)){adj<-pe$traded*(b-15)/1e4; ae<-pe$active_ew-adj
    rows[[as.character(b)]]<-data.table(track=label,bps=b,ew_t=nw_t(ae),ew_oos=oos3(ae),drag=mean(pe$traded)*12*b/1e4)}
  dt<-rbindlist(rows)
  ## linear break-even for EW t=2.95
  be<-approx(dt$ew_t, dt$bps, xout=2.95)$y
  cat(sprintf("  [%s] EW-t by bps: 15=%.2f 30=%.2f 50=%.2f | break-even(t=2.95)=%.1fbps\n",label,dt$ew_t[1],dt$ew_t[3],dt$ew_t[5], be))
  list(dt=dt, breakeven=be)}
CG_Z <- cost_grid(A_Z6,"Z6_blend_EW"); CG_V <- cost_grid(A_V,"pure_value_EW")

## ---- capacity (ADV20 from rawdata, PART 10%/day) ----
held <- unique(c(A_Z6$W$Ticker, A_V$W$Ticker))
PP <- as.data.table(read_parquet(file.path(QM,"stage_artifacts/d3_dossier/holdings_monthly_ppure.parquet"))); PP[,Date:=as.Date(Date)]
held <- unique(c(held, PP$Ticker))
DV <- as.data.table(read_parquet(file.path(QM,".cache/rawdata.parquet"), col_select=c("Date","Ticker","Vol","Close")))
DV[,Date:=as.Date(Date)]; cal<-sort(unique(DV$Date)); DV<-DV[Ticker %in% held]; DV[,val:=as.numeric(Vol)*as.numeric(Close)]
DV<-DV[,.(Date,Ticker,val)]; setkey(DV,Date)
hold_dates <- sort(unique(c(A_Z6$W$Date, A_V$W$Date)))
adv_rows<-list(); for(d in as.list(hold_dates)){d<-as.Date(d); wnd<-tail(cal[cal<=d],20); if(length(wnd)<10)next
  sub<-DV[.(wnd),nomatch=0]; a<-sub[,.(adv20=mean(val,na.rm=TRUE),n_obs=sum(is.finite(val))),by=Ticker]; a[,Date:=d]; adv_rows[[as.character(d)]]<-a}
ADV<-rbindlist(adv_rows); rm(DV); invisible(gc())
cap_of <- function(W,label){H<-merge(W,ADV,by=c("Date","Ticker"),all.x=TRUE); H[n_obs<10,adv20:=NA_real_]
  capm<-H[,.(cap_1d=suppressWarnings(min(PART_RATE*adv20/w,na.rm=TRUE)),
             n_below_1e9=sum(adv20<1e9,na.rm=TRUE), med_adv=median(adv20,na.rm=TRUE)),by=Date]
  capm[!is.finite(cap_1d),cap_1d:=NA_real_]; capm[,cap_5d:=5*cap_1d]
  c1med<-median(capm$cap_1d,na.rm=TRUE); c1_36<-median(tail(capm[order(Date)],36)$cap_1d,na.rm=TRUE)
  c1worst<-min(capm$cap_1d,na.rm=TRUE); c5_36<-median(tail(capm[order(Date)],36)$cap_5d,na.rm=TRUE)
  cat(sprintf("  [%s] cap_1d(억): med=%.1f 최근36m=%.1f 최악월=%.2f | cap_5d 36m=%.1f | ADV<10억 보유수 med=%.1f\n",
    label, c1med/1e8, c1_36/1e8, c1worst/1e8, c5_36/1e8, median(capm$n_below_1e9,na.rm=TRUE)))
  list(capm=capm, c1med=c1med, c1_36=c1_36, c1worst=c1worst, c5_36=c5_36, nbelow=median(capm$n_below_1e9,na.rm=TRUE))}
cat("\n-- capacity (참여율 10%/일, ADV20) --\n")
CAP_Z<-cap_of(A_Z6$W,"Z6_blend_EW"); CAP_V<-cap_of(A_V$W,"pure_value_EW")

## ---- overlap / active-corr vs P-pure base track (EW) ----
ov_of <- function(W,label){
  mm<-merge(W[,.(Date,Ticker,inA=1)], PP[,.(Date,Ticker,inP=1)], by=c("Date","Ticker"), all=TRUE)
  per<-mm[,.(nA=sum(!is.na(inA)), nboth=sum(!is.na(inA)&!is.na(inP))), by=Date]
  ov<-mean(per[nA>0, nboth/nA], na.rm=TRUE); ov}
## P-pure EW-active series: rebuild from PP holdings vs EW-universe bench
ppr <- weighted_screen_bt(PP, fwd_ret, bench, cost_bps_oneway=15, run_id="R30_ppure", strategy_id="R30_ppure")
ppr_dt <- as.data.table(ppr$period_returns)  # date, ret_net, benchmark_ret (KOSPI200)
## EW-uni bench for P-pure period: reuse from A_V ewd? bench differs by universe/date; approximate active corr on cap-w BM
merge_ac <- function(A, label){
  m<-merge(A$ewd[,.(date,ae=active_ew)], ppr_dt[,.(date,pae=ret_net-benchmark_ret)], by="date")
  ov<-ov_of(A$W,label); ac<-suppressWarnings(cor(m$ae,m$pae))
  cat(sprintf("  [%s vs P-pure base] holding overlap=%.1f%% | active-corr(EW vs cap-wBM P-pure)=%.3f (n=%d)\n",label,ov*100,ac,nrow(m)))
  data.table(track=label, overlap_ppure=ov, active_corr_ppure=ac, n_overlap=nrow(m))}
cat("\n-- overlap vs P-pure(base) --\n")
OV_Z<-merge_ac(A_Z6,"Z6_blend_EW"); OV_V<-merge_ac(A_V,"pure_value_EW")

## ============================================================================
## BRANCH B robustness (선택후 진단 — B2 non-mega): cap-w oos + placebo
## ============================================================================
cat("\n========== BRANCH B robustness (B2 non-mega, 선택후 진단) ==========\n")
mk_capw <- function(dt, scorecol){
  S <- merge(dt[is.finite(get(scorecol)),.(Date,Ticker,sc=get(scorecol))], SIZE, by=c("Date","Ticker"))
  S <- merge(S, liqf, by=c("Date","Ticker"), all.x=TRUE); S <- S[is.na(adv)|adv>=2e8]
  dd<-sort(unique(S$Date)); W<-list()
  for(i in seq_along(dd)){d<-dd[i];sub<-S[Date==d];if(nrow(sub)<25)next;setorder(sub,-sc);hd<-head(sub,25)
    W[[as.character(d)]]<-data.table(Date=d,Ticker=hd$Ticker,w=cap_norm(hd$Size))}
  rbindlist(W)}
capw_active <- function(scoredt,tag){W<-mk_capw(scoredt,"sc");if(nrow(W)==0)return(NULL)
  res<-weighted_screen_bt(W,fwd_ret,bench,cost_bps_oneway=15,run_id=tag,strategy_id=tag)
  pr<-as.data.table(res$period_returns);pr[,active:=ret_net-benchmark_ret];list(pr=pr,res=res)}
## clean base + B2 variant active
BASEd <- copy(DT[is.finite(`0_stored_S7`),.(Date,Ticker,sc=`0_stored_S7`)])
BA <- capw_active(BASEd,"R30_base_r")
b2 <- copy(DT[is.finite(`0_stored_S7`),.(Date,Ticker,tier,b=`0_stored_S7`,v=vz_off0)])
b2[,b_z:=zc(b),by=Date]; b2[,v_z:=zc(v),by=Date]; b2[is.na(v_z),v_z:=0]
b2[,v_boost:=fifelse(tier %in% c("MID","OTHER"),v_z,0)]; b2[,sc:=(1-W_BLEND)*b_z+W_BLEND*v_boost]
B2 <- capw_active(b2[,.(Date,Ticker,sc)],"R30_B2_r")
mB<-merge(B2$pr[,.(date,va=active)],BA$pr[,.(date,ba=active)],by="date")
cat(sprintf("B2 cap-w: variant oos_v2=%.3f | base oos_v2=%.3f | paired-diff oos_v2=%.3f\n",
  oos3(mB$va), oos3(mB$ba), oos3(mB$va-mB$ba)))
## placebo: shuffle value within month on non-mega, N=40, paired-t null
set.seed(4045); NPL<-40L; pl<-numeric(NPL)
for(k in 1:NPL){
  bp<-copy(DT[is.finite(`0_stored_S7`),.(Date,Ticker,tier,b=`0_stored_S7`,v=vz_off0)])
  bp[,b_z:=zc(b),by=Date]
  bp[, v_sh := { idx<-sample(.N); v[idx] }, by=Date]   # shuffle value within month
  bp[,v_z:=zc(v_sh),by=Date]; bp[is.na(v_z),v_z:=0]
  bp[,v_boost:=fifelse(tier %in% c("MID","OTHER"),v_z,0)]; bp[,sc:=(1-W_BLEND)*b_z+W_BLEND*v_boost]
  pv<-capw_active(bp[,.(Date,Ticker,sc)],paste0("pl",k)); if(is.null(pv)){pl[k]<-NA;next}
  mp<-merge(pv$pr[,.(date,va=active)],BA$pr[,.(date,ba=active)],by="date"); pl[k]<-nw_t(mp$va-mp$ba)
}
pl<-pl[is.finite(pl)]; b2_paired<-2.378
cat(sprintf("B2 placebo (value shuffle, N=%d): null paired max=%.3f mean=%.3f | actual=%.3f | p=%.3f\n",
  length(pl), max(pl), mean(pl), b2_paired, mean(pl>=b2_paired)))

## ---- save ----
save_safe(A_sum, file.path(WT,"branchA_summary.parquet"), function(o,p) write_parquet(o,p))
OUT <- list(
  A_summary=A_sum, trailing_Z6=tsZ, trailing_V=tsV,
  cost_Z6=CG_Z$dt, cost_V=CG_V$dt, breakeven_Z6=CG_Z$breakeven, breakeven_V=CG_V$breakeven,
  cap_Z6=CAP_Z[c("c1med","c1_36","c1worst","c5_36","nbelow")], cap_V=CAP_V[c("c1med","c1_36","c1worst","c5_36","nbelow")],
  overlap=rbind(OV_Z,OV_V),
  B2_oos_variant=oos3(mB$va), B2_oos_base=oos3(mB$ba), B2_oos_paireddiff=oos3(mB$va-mB$ba),
  B2_placebo=list(n=length(pl), null_max=max(pl), null_mean=mean(pl), actual=b2_paired, p=mean(pl>=b2_paired)))
saveRDS(OUT, file.path(WT,"r30_branchA_diag.rds"))
save_safe(rbind(CG_Z$dt,CG_V$dt), file.path(WT,"cost_scenarios.parquet"), function(o,p) write_parquet(o,p))
cat("\nBRANCH_A_DONE\n")
