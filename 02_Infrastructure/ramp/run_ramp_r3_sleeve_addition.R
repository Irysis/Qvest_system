## run_ramp_r3_sleeve_addition.R — RAMP R3: 지정 재도전 경로 2개 배분-레벨 소비
## 후보 A: tail-risk 방어 sleeve (D47/D48 계열, overlay-부재 국면배합) 성분 추가 vs 제외 (paired)
## 후보 B: V02_EP EW-가중 sleeve 성분 추가 vs 제외 (paired)
## base = M_regdd 국면-IC 가중 11-family 블렌드 (run_ramp_graduation 재현). cap-w authoritative.
## 실측-only(canonical_screen_bt), 단일스레드, pin_cache vintage 고정, IS-only 선별.
suppressPackageStartupMessages({library(data.table); library(arrow); library(dplyr)})
setDTthreads(1); try(arrow::set_cpu_count(1),silent=TRUE); try(arrow::set_io_thread_count(2),silent=TRUE)
QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
source("02_Infrastructure/config.R")
source("02_Infrastructure/ramp/factor_validation.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")
source("02_Infrastructure/data/pin_cache.R")
suppressMessages({library(sandwich);library(lmtest)})
zc<-function(x){m<-mean(x,na.rm=T);s<-sd(x,na.rm=T);if(is.na(s)||s<1e-9) x-m else (x-m)/s}
nwt<-function(x,lag=3L){x<-x[is.finite(x)];if(length(x)<12)return(NA_real_);m<-lm(x~1);as.numeric(coeftest(m,vcov=sandwich::NeweyWest(m,lag=lag,prewhite=F))[1,3])}
srf<-function(x){x<-x[is.finite(x)];if(length(x)<6)return(NA_real_);s<-sd(x);if(s<=0)return(NA_real_);mean(x)/s*sqrt(12)}
con<-file(".cache/_ramp_r3.txt","w",encoding="UTF-8"); w<-function(...)writeLines(paste0(...),con)

## ── vintage pin ──────────────────────────────────────────────────────────────
PIN_TAG<-format(Sys.time(),"ramp_r3_%Y%m%d_%H%M%S")
pin_cache(c(".cache/rawdata.parquet","outputs/ramp/factor_group_scores.parquet"), PIN_TAG)
pfs_info<-file.info("outputs/ramp/pure_factor_scores.parquet")
w(sprintf("[pin] tag=%s | pure_factor_scores vintage mtime=%s size=%.0fMB",
          PIN_TAG, as.character(pfs_info$mtime), pfs_info$size/1e6))

## ── base blend inputs (pinned) ─────────────────────────────────────────────────
g<-as.data.table(read_parquet(read_pinned("outputs/ramp/factor_group_scores.parquet",PIN_TAG)))
g[,signal_date:=as.Date(signal_date)]
gw<-dcast(g,signal_date+security_id~family,value.var="group_z"); grp<-setdiff(names(gw),c("signal_date","security_id"))
a<-as.data.table(read_parquet("stage_artifacts/WT_D20260425_010/alpha_scores.parquet")); a[,Date:=as.Date(Date)]
reg<-unique(a[,.(ym=format(Date,"%Y-%m"),regime=regime_state)])[,.SD[1],by=ym]
gw[,ym:=format(signal_date,"%Y-%m")]; gw<-merge(gw,reg,by="ym",all.x=TRUE); gw[is.na(regime),regime:="NORMAL"]
.need<-c("Date","Ticker","Close","K200","KQ150","Vol","Size","Ret","Sector","BM_Ret")
rawdata<-as.data.table(read_parquet(read_pinned(".cache/rawdata.parquet",PIN_TAG), col_select=all_of(.need))); rawdata[,Date:=as.Date(Date)]
sig_dates<-sort(unique(gw$signal_date)); fwd<-build_monthly_forward_returns(rawdata,sig_dates)
oos_cut<-sig_dates[length(sig_dates)-23]
ewb<-fwd$returns_dt[,.(ew=mean(Ret_1m,na.rm=TRUE)),by=.(date=as.Date(Date))]
regmap<-unique(gw[,.(signal_date,regime)])
w(sprintf("[data] n_sig=%d range=%s..%s oos_cut=%s | families=%s",
          length(sig_dates),as.character(min(sig_dates)),as.character(max(sig_dates)),as.character(oos_cut),paste(grp,collapse=",")))

## ── base score = M_regdd (국면 조건부 과거-IC 가중 composite; run_ramp_graduation 재현) ──
ic<-merge(g[,.(signal_date,security_id,family,group_z)],
          fwd$returns_dt[,.(signal_date=as.Date(Date),security_id=Ticker,Ret_1m)],by=c("signal_date","security_id"))
gic<-ic[,.(ic=if(.N>=10&&sd(group_z)>0&&sd(Ret_1m)>0)cor(group_z,Ret_1m,method="spearman")else NA_real_),by=.(signal_date,family)]
gic<-merge(gic,unique(gw[,.(signal_date,regime)]),by="signal_date"); setorder(gic,family,signal_date)
mk_base<-function(){rows<-list()
  for(d in as.character(sig_dates)){dd<-as.Date(d);rg<-gw[signal_date==dd,regime][1]
    wts<-sapply(grp,function(fm){p<-gic[family==fm&regime==rg&signal_date<dd,ic];p<-p[is.finite(p)];if(length(p)>=3)max(mean(p),0)else 0})
    if(sum(wts)<1e-9)wts<-setNames(rep(1,length(grp)),grp);ww<-wts/sum(wts)
    sub<-gw[signal_date==dd];X<-as.matrix(sub[,..grp]);X[is.na(X)]<-0
    rows[[d]]<-data.table(signal_date=dd,security_id=sub$security_id,base=as.numeric(X%*%ww))}
  s<-rbindlist(rows); s[,base:=zc(base),by=signal_date]; s}
base_sc<-mk_base()

## ── sleeve inputs from pure_factor_scores (tail + EP) ─────────────────────────
ds<-arrow::open_dataset("outputs/ramp/pure_factor_scores.parquet")
tailf<-c("D47_CVaR_5pct","D48_VaR_5pct","R03_CVaR_95","R04_CVaR_99","R05_Tail_Risk")
epf<-c("V02_EP","V15_NetDebt_Adj_EP")
refvol<-"D03_RealVol"
pf<-ds %>% filter(factor_id %in% c(tailf,epf,refvol)) %>%
  select(signal_date,security_id,factor_id,z,neutralized_z) %>% collect() %>% as.data.table()
pf[,signal_date:=as.Date(signal_date)]
Wz<-dcast(pf, signal_date+security_id~factor_id, value.var="z")           # aligned raw z
Wn<-dcast(pf, signal_date+security_id~factor_id, value.var="neutralized_z")# FWL 잔차 z
# risk pole (PIT-clean cross-sec: 각 tail z가 RealVol과 같은 방향이면 +1). 저-tail-risk 방어 = -pole*z
xcor<-function(dt,a,b){s<-dt[!is.na(get(a))&!is.na(get(b)),.(c=if(.N>=20&&sd(get(a))>0&&sd(get(b))>0)cor(get(a),get(b),method="spearman")else NA_real_),by=signal_date];mean(s$c,na.rm=TRUE)}
poles_z<-sapply(tailf,function(f) sign(xcor(Wz,f,refvol)))
poles_n<-sapply(tailf,function(f) sign(xcor(Wn,f,refvol)))
w(sprintf("[pole raw z ] %s",paste(tailf,poles_z,sep="=",collapse=" ")))
w(sprintf("[pole neut z] %s",paste(tailf,poles_n,sep="=",collapse=" ")))
mk_tail<-function(Wtab,poles){
  X<-copy(Wtab); for(f in tailf) X[,(f):=get(f)*(-poles[f])]
  X[,tail:=rowMeans(.SD,na.rm=TRUE),.SDcols=tailf]
  X[,tail:=zc(tail),by=signal_date]; X[,.(signal_date,security_id,sleeve=tail)]}
tail_raw<-mk_tail(Wz,poles_z)      # raw 저-tail-risk 방어 노출 (스타일 포함)
tail_neu<-mk_tail(Wn,poles_n)      # FWL 잔차 tail 신호 (스타일 제거)
# EP sleeve (aligned higher=better)
ep_v02<-Wz[!is.na(V02_EP),.(signal_date,security_id,sleeve=V02_EP)][,sleeve:=zc(sleeve),by=signal_date]
Wz[,ep_comp:=rowMeans(.SD,na.rm=TRUE),.SDcols=epf]
ep_comp<-Wz[!is.na(ep_comp),.(signal_date,security_id,sleeve=ep_comp)][,sleeve:=zc(sleeve),by=signal_date]

## regime-conditional weight schedule (soft tilt, no hard switch)
sched<-function(rg,lo,cau,cri,bull=0){ w<-rep(lo,length(rg)); w[rg=="BULL"]<-bull; w[rg=="CAUTION"]<-cau; w[rg=="CRISIS"]<-cri; w }

## ── treatment 조립: score = (1-w)*base + w*sleeve (성분 추가) ──────────────────
build_treat<-function(sleeve_dt,wvec_or_scalar){
  m<-merge(base_sc,sleeve_dt,by=c("signal_date","security_id"),all.x=TRUE)
  m[is.na(sleeve),sleeve:=0]
  if(length(wvec_or_scalar)==1){ m[,wt:=wvec_or_scalar] } else {
    wd<-data.table(signal_date=sig_dates, wt=wvec_or_scalar); m<-merge(m,wd,by="signal_date",all.x=TRUE)
  }
  m[,score:=(1-wt)*base + wt*sleeve]; m[,score:=zc(score),by=signal_date]
  m[,.(Date=signal_date,Ticker=security_id,score)]
}
regw<-sched(regmap$regime,lo=0.05,cau=0.25,cri=0.40,bull=0.0)[match(sig_dates,regmap$signal_date)]

## ── canonical 측정 + paired 증분 ────────────────────────────────────────────────
run_cs<-function(scores){
  canonical_screen_bt(scores, fwd$returns_dt[,.(Date=as.Date(Date),Ticker,Ret_1m)],
    fwd$bench_dt[,.(Date=as.Date(Date),BM_Ret)], top_n=25L, cost_bps_oneway=15,
    liq_dt=fwd$liq_dt[,.(Date=as.Date(Date),Ticker,adv)], liq_min=2e8,
    run_id="ramp_r3", strategy_id="ramp_r3", diag_dual_basis=TRUE,
    size_dt=rawdata[,.(Date,Ticker,Size)])
}
metr<-function(pr,lab){
  pr<-as.data.table(pr); pr[,date:=as.Date(date)]; pr<-merge(pr,ewb,by="date",all.x=TRUE)
  pr[,act_capw:=ret_net-benchmark_ret]; pr[,act_ew:=ret_net-ew]; pr[,is_oos:=date>=oos_cut]
  ptc<-nwt(pr$act_capw); pte<-nwt(pr$act_ew)
  nav<-cumprod(1+pr$ret_net); dd<-min(nav/cummax(nav)-1); ann<-prod(1+pr$ret_net)^(12/nrow(pr))-1
  cal<-if(dd<0) ann/abs(dd) else NA_real_
  .sp<-c(0.55,0.65,0.75); .r<-sapply(.sp,function(fr){k<-floor(nrow(pr)*fr);if(k<12||(nrow(pr)-k)<6)return(NA_real_);i<-srf(pr$act_capw[1:k]);o<-srf(pr$act_capw[(k+1):nrow(pr)]);if(!is.na(i)&&i>0)o/i else NA_real_})
  list(pr=pr, tab=data.table(model=lab, port_t_capw=ptc, port_t_ew=pte, oos_retention=median(.r,na.rm=T),
       calmar=cal, capw_sr=srf(pr$act_capw), ew_sr=srf(pr$act_ew)))
}
# base
csb<-run_cs(base_sc[,.(Date=signal_date,Ticker=security_id,score=base)]); mb<-metr(csb$period_returns,"base_M_regdd")
base_pr<-mb$pr[,.(date,base_ret=ret_net)]
w("\n=== BASE (M_regdd, 국면-IC 가중 11-family) ===")
w(sprintf("  port_t_capw=%+.2f port_t_ew=%+.2f oos=%+.2f calmar=%+.2f capw_SR=%+.2f",
          mb$tab$port_t_capw,mb$tab$port_t_ew,mb$tab$oos_retention,mb$tab$calmar,mb$tab$capw_sr))

configs<-list(
  # 후보 A — tail 방어 sleeve
  A1=list(cand="A",desc="tail_raw static w=0.15", sleeve=tail_raw, wt=0.15),
  A2=list(cand="A",desc="tail_raw static w=0.25", sleeve=tail_raw, wt=0.25),
  A3=list(cand="A",desc="tail_raw regime-cond {N.05/CAU.25/CRI.40/B0}", sleeve=tail_raw, wt=regw),
  A4=list(cand="A",desc="tail_neut(residual) regime-cond", sleeve=tail_neu, wt=regw),
  # 후보 B — V02_EP EW-가중 sleeve
  B1=list(cand="B",desc="V02_EP static w=0.15", sleeve=ep_v02, wt=0.15),
  B2=list(cand="B",desc="V02_EP static w=0.25", sleeve=ep_v02, wt=0.25),
  B3=list(cand="B",desc="V02_EP static w=0.35", sleeve=ep_v02, wt=0.35),
  B4=list(cand="B",desc="EP-composite(V02+V15) static w=0.25", sleeve=ep_comp, wt=0.25)
)
regvec<-regmap$regime[match(sig_dates,regmap$signal_date)]
res<-list()
for(nm in names(configs)){
  cf<-configs[[nm]]
  sc<-build_treat(cf$sleeve, cf$wt)
  cs<-run_cs(sc); mm<-metr(cs$period_returns, nm)
  # paired increment vs base (동일 월)
  pj<-merge(mm$pr[,.(date,ret_net,is_oos)], base_pr, by="date")
  pj[,d:=ret_net-base_ret]
  pj<-merge(pj, data.table(date=sig_dates,regime=regvec), by="date", all.x=TRUE)
  paired_t_full<-nwt(pj$d); paired_t_is<-nwt(pj[is_oos==FALSE,d]); paired_t_oos<-nwt(pj[is_oos==TRUE,d])
  is_mean<-mean(pj[is_oos==FALSE,d],na.rm=T)*12
  # regime 분해
  crisis_d<-pj[regime %in% c("CRISIS","CAUTION"),d]; normal_d<-pj[regime %in% c("NORMAL","BULL"),d]
  cr_mean<-mean(crisis_d,na.rm=T)*12; nm_mean<-mean(normal_d,na.rm=T)*12
  cr_t<-nwt(crisis_d,lag=1L)
  tab<-cbind(mm$tab, data.table(
    paired_t_full=paired_t_full, paired_t_is=paired_t_is, paired_t_oos=paired_t_oos,
    is_mean_ann=is_mean, crisis_d_ann=cr_mean, normal_d_ann=nm_mean, crisis_t=cr_t,
    d_capw_delta=mm$tab$port_t_capw-mb$tab$port_t_capw, cand=cf$cand, desc=cf$desc))
  res[[nm]]<-tab
  w(sprintf("  [%s|%s] port_t_capw=%+.2f(Δ%+.2f) port_t_ew=%+.2f oos=%+.2f cal=%+.2f | paired_t: full=%+.2f IS=%+.2f OOS=%+.2f | is_mean=%+.4f cris_d=%+.4f(t%+.2f) norm_d=%+.4f",
          nm,cf$desc,tab$port_t_capw,tab$d_capw_delta,tab$port_t_ew,tab$oos_retention,tab$calmar,
          paired_t_full,paired_t_is,paired_t_oos,is_mean,cr_mean,ifelse(is.na(cr_t),NA,cr_t),nm_mean))
}
R<-rbindlist(res,fill=TRUE)

## ── IS-only 선별 (후보별 IS paired 증분 최대) → 선택안의 full-period 판정 ──────────
sel<-R[,.SD[which.max(paired_t_is)],by=cand]
w("\n=== IS-only 선별 (후보별 IS paired 증분 t 최대) ===")
for(i in seq_len(nrow(sel))){s<-sel[i]
  verdict<-ifelse(!is.na(s$paired_t_full)&&s$paired_t_full>=2.0,"SURVIVE(≥2.0)","EXHAUSTED(<2.0)")
  w(sprintf("  후보%s 선택=%s (%s) → full-period paired_t_capw=%+.2f | cap-w PORT_t=%+.2f(base %+.2f) → %s",
            s$cand,s$model,s$desc,s$paired_t_full,s$port_t_capw,mb$tab$port_t_capw,verdict))}

## 산출 저장
gen<-format(Sys.time(),"%Y-%m-%dT%H:%M:%S%z")
out<-list(as_of_date=as.character(Sys.Date()), generated_at=gen, source_version="ramp_r3_v1.0",
          pin_tag=PIN_TAG, security_id="Ticker(K200∪KQ150)",
          base=as.list(mb$tab), configs=lapply(res,as.list),
          selection=lapply(seq_len(nrow(sel)),function(i)as.list(sel[i])),
          gate_paired_t=2.0, oos_cut=as.character(oos_cut), n_months=nrow(base_pr),
          n_trials_per_candidate=4, date_range=c(as.character(min(sig_dates)),as.character(max(sig_dates))))
jsonlite::write_json(out,"outputs/ramp/r3_summary_20260711.json",auto_unbox=TRUE,pretty=TRUE,digits=5,na="null")
write_parquet(R,"outputs/ramp/r3_config_gates.parquet")
saveRDS(list(R=R,base=mb$tab,sel=sel),".cache/_ramp_r3.rds")
close(con); cat("R3_DONE\n")
