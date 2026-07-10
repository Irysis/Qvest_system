# WT-H20260710_001 Stage 4 — winner OOS(1 pass) + production-fidelity carrier + DSR(sweep) + jackknife + placebo.
suppressMessages({library(arrow); library(data.table)})
options(scipen=999); setDTthreads(1L); set.seed(20260710L)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
SA <- file.path(ROOT,"stage_artifacts","WT-H20260710_001")
source(file.path(ROOT,"02_Infrastructure","contracts","canonical_screen_bt.R"))
source(file.path(ROOT,"02_Infrastructure","portfolio","strategy_tilt_weights.R"))
inp<-readRDS(file.path(SA,"inputs.rds")); swp<-readRDS(file.path(SA,"sweep_is.rds"))
m08v<-readRDS(file.path(SA,"m08_variants.rds")); cv<-readRDS(file.path(SA,"c_variants.rds"))
ap<-inp$ap; returns_dt<-inp$returns_dt; benchdt<-inp$benchdt; scope<-inp$scope
IS_END<-as.Date("2018-12-01"); cfgs<-swp$cfgs; CORE0<-swp$CORE0; DEF0<-swp$DEF0

.winsor_z <- function(x, sigma=2.5){ if(!is.finite(sigma)) return(x); m<-mean(x,na.rm=TRUE);s<-sd(x,na.rm=TRUE);if(is.na(s)||s<1e-10)return(x);pmax(pmin(x,m+sigma*s),m-sigma*s)}
.zc <- function(x){m<-mean(x,na.rm=TRUE);s<-sd(x,na.rm=TRUE);if(is.na(s)||s<1e-10)x-m else (x-m)/s}
.zmad <- function(x){md<-median(x,na.rm=TRUE);ma<-mad(x,na.rm=TRUE);if(is.na(ma)||ma<1e-10)x-md else (x-md)/ma}
nw_t <- function(x,lag=3){ if(exists(".nw_t_mean",mode="function")) .nw_t_mean(x,lag=lag) else mean(x)/sd(x)*sqrt(length(x)) }

mp <- merge(inp$core_panel, inp$def_panel, by=c("Date","Ticker"), all=TRUE)
mp <- merge(mp, m08v[, c("Date","Ticker", paste0("z_", c("B1_126_21_capm","B2_378_21_capm","B3_252_0_capm","B4_252_21_raw"))), with=FALSE], by=c("Date","Ticker"), all.x=TRUE)
mp <- merge(mp, cv[, .(Date,Ticker, z_esbr_3, z_esbr_6, z_tpgap_5, z_tpgap_21)], by=c("Date","Ticker"), all.x=TRUE)
build_sleeve <- function(P, cols, sigma, std, missing){
  wl<-list(); for(fn in cols){ wl[[fn]]<-P[, .winsor_z(get(fn),sigma), by=Date]$V1 }
  M<-do.call(cbind,wl)
  if(missing=="strict") s<-rowSums(M) else { s<-rowMeans(M,na.rm=TRUE)*ncol(M); s[rowSums(!is.na(M))==0]<-NA_real_ }
  P2<-data.table(Date=P$Date,Ticker=P$Ticker,sraw=s)
  if(std=="classic") P2[,sz:=.zc(sraw),by=Date] else P2[,sz:=.zmad(sraw),by=Date]
  P2[,.(Date,Ticker,sz)]
}
build_score <- function(cf){
  cz<-build_sleeve(mp,cf$core,cf$sigma,cf$std,cf$missing); setnames(cz,"sz","cz")
  dz<-build_sleeve(mp,cf$def,cf$sigma,cf$std,cf$missing); setnames(dz,"sz","dz")
  s<-merge(cz,dz,by=c("Date","Ticker")); s[,score:=0.65*cz+0.35*dz]; s[!is.na(score),.(Date,Ticker,score)]
}
canon <- function(scores, lo=NULL, hi=NULL){
  s<-copy(scores); if(!is.null(lo)) s<-s[Date>=lo]; if(!is.null(hi)) s<-s[Date<=hi]
  canonical_screen_bt(s, returns_dt, benchdt, top_n=25L, cost_bps_oneway=15, liq_dt=NULL,
                      run_id="v", strategy_id="v", diag_dual_basis=FALSE)
}

winner<-swp$winner; cf_w<-cfgs[[winner]]
sc_w <- build_score(cf_w)
sc_inc <- build_score(list(core=CORE0,def=DEF0,sigma=2.5,std="classic",missing="strict"))
sc_stor <- ap[!is.na(score_eff), .(Date,Ticker,score=score_eff)]
OOS_LO<-as.Date("2019-01-01")
cat(sprintf("[winner]=%s  block=%s\n", winner, cf_w$block))
for(nm in c("winner","rebuilt_incumbent","stored_scoreEff")){
  sc<-switch(nm, winner=sc_w, rebuilt_incumbent=sc_inc, stored_scoreEff=sc_stor)
  rf<-canon(sc); ri<-canon(sc,hi=IS_END); ro<-canon(sc,lo=OOS_LO)
  cat(sprintf("  %-18s FULL PORT_t=%.3f IR=%.3f SR=%.3f | IS=%.3f | OOS=%.3f\n",
      nm, rf$portfolio_alpha_t_nw_lag3, rf$information_ratio, rf$net_sr,
      ri$portfolio_alpha_t_nw_lag3, ro$portfolio_alpha_t_nw_lag3))
}

# gate: winner must beat both refs on IS PORT_t (else saturation verdict, skip heavy production)
ri_w<-canon(sc_w,hi=IS_END)$portfolio_alpha_t_nw_lag3
beats <- ri_w > swp$ref_stored_port_t && ri_w > swp$ref_incrb_port_t
cat(sprintf("\n[GATE] winner IS PORT_t=%.3f vs stored=%.3f rebuilt=%.3f -> beats_both=%s\n",
    ri_w, swp$ref_stored_port_t, swp$ref_incrb_port_t, beats))

# DSR (sweep) using IS PORT_t distribution across configs (n_trials=25)
tab<-swp$tab; sr_is<-tab$IS_sr; N<-nrow(tab)
z<-sr_is/sqrt(pmax(tab$n,1))*sqrt(pmax(tab$n,1))  # placeholder; compute proper DSR below
# proper DSR: use IS SR of winner vs cross-config variance (Bailey-LdP sweep deflation)
sr_hat<-tab[config==winner,IS_sr]; n_obs<-tab[config==winner,n]
sr_var<-var(sr_is,na.rm=TRUE); sr_mean<-mean(sr_is,na.rm=TRUE)
euler<-0.5772156649; emax<-sqrt(sr_var)*((1-euler)*qnorm(1-1/N)+euler*qnorm(1-1/(N*exp(1))))
sr0<-emax  # expected max SR under null (deflation benchmark)
# DSR = Prob( SR_hat > SR0 ) approx via normal on annualized->per-period
skew<-0; kurt<-3
sr_ppd<-sr_hat/sqrt(12); sr0_ppd<-sr0/sqrt(12)
dsr<-pnorm( (sr_ppd - sr0_ppd)*sqrt(n_obs-1) / sqrt(1 - skew*sr_ppd + (kurt-1)/4*sr_ppd^2) )
null_max_t_crude<-sqrt(2*log(N))
cat(sprintf("\n[DSR sweep] N_trials=%d winner IS_SR=%.3f expected_max_SR0=%.3f DSR=%.3f | null_max_t_crude=%.3f winner_IS_PORT_t=%.3f\n",
    N, sr_hat, sr0, dsr, null_max_t_crude, ri_w))

# connected-block jackknife: drop each calendar year from IS, recompute winner IS PORT_t
sc_wIS<-sc_w[Date<=IS_END]; yrs<-sort(unique(year(sc_wIS$Date)))
jk<-sapply(yrs,function(y){ r<-canon(sc_wIS[year(Date)!=y]); r$portfolio_alpha_t_nw_lag3 })
cat(sprintf("[jackknife IS drop-year] PORT_t range=[%.3f, %.3f] median=%.3f (base=%.3f)\n",
    min(jk),max(jk),median(jk),ri_w))

out<-list(winner=winner, winner_cfg=cf_w, beats_both=beats, winner_is_port_t=ri_w,
          ref_stored=swp$ref_stored_port_t, ref_incrb=swp$ref_incrb_port_t,
          dsr=dsr, n_trials=N, expected_max_sr0=sr0, null_max_t_crude=null_max_t_crude,
          jackknife=list(range=range(jk),median=median(jk)))

# ---- production-fidelity carrier (only if beats_both) ----
if (beats) {
  cat("\n[PRODUCTION FIDELITY] winner beats refs -> running STR_1715 top-20 linear_tilt carrier\n")
  raw<-as.data.table(read_parquet(file.path(ROOT,".cache/rawdata.parquet"),
        col_select=c("Date","Ticker","Ret","Close","Vol")))
  raw[,Date:=as.Date(Date)]; raw<-raw[!is.na(Ret)]; raw[,TA:=Close*Vol]; setkey(raw,Date)
  reg<-ap[, .(Date,Ticker,regime_state)]
  carrier<-function(score_dt){
    sdt<-merge(score_dt, unique(reg[, .(Date, regime_state)]), by="Date", all.x=TRUE)
    sig_dates<-sort(unique(sdt[!is.na(score),Date])); mret<-list(); w_prev<-NULL
    for(i in seq_len(length(sig_dates)-1L)){
      sl<-sig_dates[i]; nx<-sig_dates[i+1L]
      start_d<-min(raw[Date>=sl]$Date); if(!length(start_d)||is.na(start_d)) next
      end_d<-{n<-min(raw[Date>=nx]$Date); if(!length(n)||is.na(n)) max(raw$Date) else n}
      pt<-sdt[Date==sl & !is.na(score)]; if(!nrow(pt)) next
      reg_i<-pt$regime_state[1]; setorder(pt,-score); Ntg<-min(20L,nrow(pt))
      picks<-pt[seq_len(Ntg)]; a_t<-setNames(picks$score,picks$Ticker)
      liq<-raw[Date>=(start_d-30L)&Date<start_d,.(ADV=mean(TA,na.rm=TRUE)),by=Ticker][ADV>=2e8,Ticker]
      tk<-intersect(names(a_t),liq); if(length(tk)<5L) tk<-names(a_t)
      a<-a_t[tk]; if(length(a)<5L) next
      ub<-if(identical(reg_i,"CRISIS")) 0.10 else 0.20
      wr<-tryCatch(linear_tilt_to_penalty_qd(a,lambda=1.5,w_prev=w_prev,phi=3.0,lb=0,ub=ub),
                   error=function(e) linear_tilt_qd(a,lambda=1.5,lb=0,ub=ub))
      names(wr)<-names(a); wn<-normalize_long_only(wr,lb=0,ub=ub,target_sum=1)
      pd<-raw[Date>start_d & Date<=end_d,.(Date,Ticker,Ret)]
      sr<-pd[,.(rf=prod(1+Ret,na.rm=TRUE)-1),by=Ticker]
      h<-data.table(Ticker=names(wn),w=as.numeric(wn)); h<-merge(h,sr,by="Ticker",all.x=TRUE); h[is.na(rf),rf:=0]
      mret[[i]]<-data.table(eval_date=end_d, gross=sum(h$w*h$rf), realized_ym=format(end_d,"%Y-%m"))
      w_prev<-setNames(as.numeric(wn),names(wn))
    }
    rbindlist(mret)
  }
  cb_w<-carrier(sc_w); cb_s<-carrier(sc_stor); cb_i<-carrier(sc_inc)
  bmm<-benchdt[, .(realized_ym=format(Date,"%Y-%m"), bm=BM_Ret)]  # note: benchdt keyed by sig-month; approximate
  # net active via benchmark: use canonical benchdt aligned by realized month
  bench_real<-inp$ap[, .(realized_ym=format(Date,"%Y-%m"))][0]  # rebuild below from bm monthly
  # simpler: recompute realized monthly bm from pinned daily
  bmd<-as.data.table(read_parquet(file.path(ROOT,".cache/benchmark_pin20260703.parquet")))
  bmd[,Dt:=as.Date(Date)]; bmd<-bmd[is.finite(BM_Ret)]; bmd[,ym:=format(Dt,"%Y-%m")]
  bmr<-bmd[,.(bm=expm1(sum(log1p(BM_Ret)))),by=ym]
  mkact<-function(cb){ m<-merge(cb, bmr, by.x="realized_ym", by.y="ym"); m[, act:=gross-0.0 - bm]; m }
  aw<-mkact(cb_w); as_<-mkact(cb_s); ai<-mkact(cb_i)
  jj<-merge(aw[,.(realized_ym,aw=act)], as_[,.(realized_ym,as_=act)], by="realized_ym")
  jj2<-merge(jj, ai[,.(realized_ym,ai=act)], by="realized_ym")
  dvs<-jj2$aw-jj2$as_; dvi<-jj2$aw-jj2$ai
  cat(sprintf("[carrier] winner active SR=%.3f  stored SR=%.3f  rebuilt SR=%.3f\n",
      mean(jj2$aw)/sd(jj2$aw)*sqrt(12), mean(jj2$as_)/sd(jj2$as_)*sqrt(12), mean(jj2$ai)/sd(jj2$ai)*sqrt(12)))
  cat(sprintf("[carrier PAIRED NW-t] winner-vs-stored=%.3f (dMeanAct=%.1fbps) | winner-vs-rebuilt=%.3f\n",
      nw_t(dvs), mean(dvs)*1e4, nw_t(dvi)))
  out$production<-list(winner_active_sr=mean(jj2$aw)/sd(jj2$aw)*sqrt(12),
                       stored_active_sr=mean(jj2$as_)/sd(jj2$as_)*sqrt(12),
                       paired_nw_t_vs_stored=nw_t(dvs), dmean_bps_vs_stored=mean(dvs)*1e4,
                       paired_nw_t_vs_rebuilt=nw_t(dvi))
} else {
  cat("\n[PRODUCTION FIDELITY] skipped — winner does not beat both incumbent refs on IS. Verdict=saturation.\n")
}
saveRDS(out, file.path(SA,"validate.rds"))
jsonlite::write_json(out, file.path(SA,"validate.json"), auto_unbox=TRUE, pretty=TRUE, digits=5)
cat("\n[saved] validate.rds + validate.json\n")
