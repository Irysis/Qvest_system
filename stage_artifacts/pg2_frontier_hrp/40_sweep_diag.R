## Schur γ-sweep = sweep selection → DSR / OOS retention / recent-2021+ diagnostics.
suppressPackageStartupMessages({library(data.table); library(sandwich); library(lmtest)})
OUT<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot/stage_artifacts/pg2_frontier_hrp"
runs<-readRDS(file.path(OUT,"runs_cheap.rds"))
nwt<-function(x,lag=3L){x<-as.numeric(x);x<-x[is.finite(x)];n<-length(x);if(n<10)return(NA);as.numeric(coeftest(lm(x~1),vcov=sandwich::NeweyWest(lm(x~1),lag=lag,prewhite=FALSE))[1,3])}
IRf<-function(x){x<-x[is.finite(x)];if(length(x)<6)return(NA);mean(x)/sd(x)*sqrt(12)}
oosr<-function(act){n<-length(act);median(sapply(c(.55,.65,.75),function(fr){k<-floor(n*fr);if(k<12||(n-k)<6)return(NA);is<-IRf(act[1:k]);oo<-IRf(act[(k+1):n]);if(!is.na(is)&&is>0)oo/is else NA}),na.rm=TRUE)}
# DSR (Bailey-Lopez de Prado) for a sweep over N_trials variants, using SR of active
dsr<-function(sr_list,sr_star_idx){
  # sr_list = annualized SR of each variant's active series; approximate via monthly
  NULL
}
# For each Schur-pure and Schur-tilt variant: SR of overlay return (deflated basis), OOS, 2021+ PORT_t
sweeps<-list(
  pure=grep("^Schur_g[0-9.]+$",names(runs),value=TRUE),
  tilt=grep("^Schur_g[0-9.]+_tilt$",names(runs),value=TRUE)
)
res<-list()
for(grp in names(sweeps)){
  vs<-sweeps[[grp]]
  # SR (monthly, on ret_ov) per variant for DSR expected-max deflation
  srm<-sapply(vs,function(k){mg<-runs[[k]];mean(mg$ret_ov)/sd(mg$ret_ov)})  # monthly SR
  N<-length(vs)
  # expected max of N iid N(0,1/T) SR under H0 (BLP): SR0 = sqrt(Var)*((1-g)*Z(1-1/N)+g*Z(1-1/(N e)))
  Tn<-nrow(runs[[vs[1]]]); varsr<-var(srm)  # cross-variant SR variance as proxy for selection dispersion
  emc<-0.5772156649; z<-function(p)qnorm(p)
  sr0<-sqrt(varsr)*((1-emc)*z(1-1/N)+emc*z(1-1/(N*exp(1))))
  best<-vs[which.max(srm)]; mgb<-runs[[best]]
  srb<-mean(mgb$ret_ov)/sd(mgb$ret_ov)
  # DSR = Phi( (srb - sr0)*sqrt(T-1) / sqrt(1 - skew*srb + (kurt-1)/4*srb^2) )
  sk<-mean(scale(mgb$ret_ov)^3);ku<-mean(scale(mgb$ret_ov)^4)
  dsrv<-pnorm((srb-sr0)*sqrt(Tn-1)/sqrt(1-sk*srb+(ku-1)/4*srb^2))
  act<-mgb$active
  mg21<-mgb[realized_ym>="2021-01"]
  res[[grp]]<-data.table(sweep=grp,N_trials=N,best=best,
    best_SR_ann=round(srb*sqrt(12),4),SR0_deflate_ann=round(sr0*sqrt(12),4),
    DSR=round(dsrv,4),oos_retention=round(oosr(act),4),
    PORT_t_2021=round(nwt(mg21$active),3),n_2021=nrow(mg21))
}
R<-rbindlist(res)
fwrite(R,file.path(OUT,"sweep_diagnostics.csv"))
print(R)
