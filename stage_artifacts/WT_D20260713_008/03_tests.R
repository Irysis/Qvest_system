# R24 Step 03 — episode-level test battery (frozen prereg e13d4251...).
# PRIMARY = firm-clustered logistic with year-FE on HARDENED target (authoritative).
`%||%` <- function(a,b) if(is.null(a)||length(a)==0||(length(a)==1&&is.na(a))) b else a
suppressMessages({library(data.table); library(sandwich); library(lmtest)})
setDTthreads(1L); set.seed(42)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
OUT  <- file.path(ROOT,"stage_artifacts/WT_D20260713_008")
S <- readRDS(file.path(OUT,"episode_panel.rds"))

wilson <- function(x,n){ if(n==0) return(c(NA,NA)); p<-x/n; z<-1.96; d<-1+z^2/n
  ctr<-(p+z^2/(2*n))/d; hw<-z*sqrt(p*(1-p)/n + z^2/(4*n^2))/d; c(ctr-hw, ctr+hw) }

# firm-cluster bootstrap of lift (resample firms) — the R23 test that failed at 6 firms
boot_lift_firm <- function(ep, tcol, R=1000){
  tk <- unique(ep$sc); e<-ep$E; pr<-ep[[tcol]]
  idx <- split(seq_len(nrow(ep)), ep$sc); br<-numeric(R)
  for(r in 1:R){ samp<-sample(tk,length(tk),replace=TRUE); ii<-unlist(idx[samp],use.names=FALSE)
    ee<-e[ii]; pp<-pr[ii]; d<-mean(ee); br[r]<- if(sum(pp==1)>0 && d>0) mean(ee[pp==1])/d else NA }
  quantile(br, c(.025,.975), na.rm=TRUE)
}

or_ci_p <- function(m, cl_vec, tcol){
  cl <- tryCatch(coeftest(m, vcov=vcovCL(m, cluster=cl_vec)), error=function(e) coef(summary(m)))
  b<-coef(m)[tcol]; se<-cl[tcol,"Std. Error"]; p<-cl[tcol,4]
  list(or=as.numeric(exp(b)), ci=c(exp(b-1.96*se),exp(b+1.96*se)), p=as.numeric(p), se=as.numeric(se))
}

run_target <- function(ep, nm, tcol="worst_decile_late"){
  ep <- ep[is.finite(delay_d)]
  base<-mean(ep$E); n1<-ep[get(tcol)==1,.N]; x1<-ep[get(tcol)==1,sum(E)]
  evr1<- if(n1>0) x1/n1 else NA; lift<- if(!is.na(evr1)&&base>0) evr1/base else NA
  lift_wl<- if(n1>0) wilson(x1,n1)/base else c(NA,NA)
  lift_bt<- if(n1>0) boot_lift_firm(ep,tcol,1000) else c(NA,NA)
  nfirm_wd <- uniqueN(ep[get(tcol)==1, sc])
  f_fe <- as.formula(paste0("E ~ ",tcol," + size_z + adv_z + KOSPI + factor(fy)"))
  f_no <- as.formula(paste0("E ~ ",tcol," + size_z + adv_z + KOSPI"))
  m_fe <- tryCatch(glm(f_fe, data=ep, family=binomial), error=function(e) NULL)
  m_no <- tryCatch(glm(f_no, data=ep, family=binomial), error=function(e) NULL)
  m_raw<- glm(as.formula(paste0("E ~ ",tcol)), data=ep, family=binomial)
  r_fe <- if(!is.null(m_fe)) or_ci_p(m_fe, ep$sc, tcol) else list(or=NA,ci=c(NA,NA),p=NA,se=NA)
  r_no <- if(!is.null(m_no)) or_ci_p(m_no, ep$sc, tcol) else list(or=NA,ci=c(NA,NA),p=NA,se=NA)
  list(nm=nm, tcol=tcol, n=nrow(ep), base=base, n1=n1, x1=x1, evr1=evr1, nfirm_wd=nfirm_wd,
       lift=lift, lift_wilson=lift_wl, lift_boot=lift_bt,
       or_raw=as.numeric(exp(coef(m_raw)[tcol])),
       or_fe=r_fe$or, ci_fe=r_fe$ci, p_fe=r_fe$p, or_no=r_no$or, ci_no=r_no$ci, p_no=r_no$p)
}

run_split <- function(ep){
  res<-list()
  for(seg in c("pre2016","post2016")){
    sub <- if(seg=="pre2016") ep[fy<2016] else ep[fy>=2016]
    ne<-sub[worst_decile_late==1,sum(E)]; n1<-sub[worst_decile_late==1,.N]
    if(nrow(sub)<100 || n1<10){ res[[seg]]<-list(estimable=FALSE,n=nrow(sub),n1=n1,ev1=ne,or=NA,p=NA,lift=NA); next }
    base<-mean(sub$E); lift<-sub[worst_decile_late==1,mean(E)]/base
    m<-tryCatch(glm(E~worst_decile_late+size_z+adv_z+KOSPI,data=sub,family=binomial),error=function(e) NULL)
    if(is.null(m)){res[[seg]]<-list(estimable=FALSE,n=nrow(sub),n1=n1,ev1=ne,or=NA,p=NA,lift=lift);next}
    r<-or_ci_p(m, sub$sc, "worst_decile_late")
    res[[seg]]<-list(estimable=TRUE,n=nrow(sub),n1=n1,ev1=ne,or=r$or,p=r$p,lift=lift)
  }
  res
}

# aux: continuous delay hazard on delisting-only
run_aux <- function(ep, sev_hard){
  del <- sev_hard[type=="Delisting"]
  ep2 <- copy(ep)
  ep2[, delay_z := as.numeric(scale(delay_d)), by=fy]; ep2[is.na(delay_z),delay_z:=0]
   evd <- unique(del[,.(sc,ev_ym)]); setkey(evd,sc)
  ym_add<- function(ym,k){ y<-ym%/%100L; m<-ym%%100L; t<-(y*12L+(m-1L))+k; (t%/%12L)*100L+(t%%12L)+1L }
  ep2[, lo:=ym_add(rcept_ym,1L)]; ep2[, hi:=ym_add(rcept_ym,12L)]
  j<-evd[ep2,on="sc",allow.cartesian=TRUE,nomatch=NULL]; dh<-j[ev_ym>=lo&ev_ym<=hi,.(D=1L),by=.(sc,fy)]
  ep2<-merge(ep2,dh,by=c("sc","fy"),all.x=TRUE); ep2[is.na(D),D:=0L]
  m<-tryCatch(glm(D~delay_z+size_z+adv_z+KOSPI,data=ep2,family=binomial),error=function(e) NULL)
  if(is.null(m)) return(list(or=NA,p=NA,n=nrow(ep2),n_del=sum(ep2$D)))
  cl<-tryCatch(coeftest(m,vcov=vcovCL(m,cluster=ep2$sc)),error=function(e) coef(summary(m)))
  list(or=as.numeric(exp(coef(m)["delay_z"])), p=as.numeric(cl["delay_z",4]), n=nrow(ep2), n_del=sum(ep2$D))
}

RES<-list()
RES[["hardened"]]        <-run_target(S$Ehard,"hardened_FROZEN_PRIMARY","worst_decile_late")
RES[["pureflag"]]        <-run_target(S$Eflag,"pureflag_FROZEN","worst_decile_late")
RES[["diag_wd_strict"]]  <-run_target(S$Ehard,"DIAG_strict_topdecile","wd_strict")
RES[["diag_late30"]]     <-run_target(S$Ehard,"DIAG_late>=30d","late30")
SPL<-run_split(S$Ehard); AUX<-run_aux(S$Ehard, S$sev_hard)

# per-type worst-decile forward hits (composition) on hardened
comp <- {
  ep<-S$Ehard; ym_add<- function(ym,k){ y<-ym%/%100L; m<-ym%%100L; t<-(y*12L+(m-1L))+k; (t%/%12L)*100L+(t%%12L)+1L }
  wd<-ep[worst_decile_late==1]; wd[, lo:=ym_add(rcept_ym,1L)]; wd[, hi:=ym_add(rcept_ym,12L)]
  cnt<-list()
  for(tp in c("Delisting","AdminStock","UnfaithfulDisc")){
    sv<-unique(S$sev_hard[type==tp,.(sc,ev_ym)]); setkey(sv,sc)
    j<-sv[wd,on="sc",allow.cartesian=TRUE,nomatch=NULL]; h<-j[ev_ym>=lo&ev_ym<=hi,uniqueN(paste(sc,fy))]
    cnt[[tp]]<-h
  }
  cnt
}

# LOO firm robustness on strict-tail diagnostic (addresses R23 fragility directly) + fy spread
epx <- S$Ehard[wd_strict==1]
ev_firms <- unique(epx[E==1, sc])
loo <- data.table(drop_firm=character(0), or_no=numeric(0), p_no=numeric(0), n1=integer(0), x1=integer(0))
allfirms <- unique(epx$sc)
for(f in allfirms){
  sub <- S$Ehard[!(wd_strict==1 & sc==f)]   # drop that firm's strict-tail episodes
  m <- tryCatch(glm(E~wd_strict+size_z+adv_z+KOSPI, data=sub, family=binomial), error=function(e) NULL)
  if(is.null(m)) next
  r <- or_ci_p(m, sub$sc, "wd_strict")
  loo <- rbind(loo, data.table(drop_firm=f, or_no=r$or, p_no=r$p, n1=sub[wd_strict==1,.N], x1=sub[wd_strict==1,sum(E)]))
}
loo_summary <- list(min_or=min(loo$or_no,na.rm=TRUE), max_p=max(loo$p_no,na.rm=TRUE),
                    n_firms=length(allfirms), n_event_firms=length(ev_firms),
                    any_kills_p05=any(loo$p_no>=0.05), any_kills_or1=any(loo$or_no<=1))
fy_strict <- S$Ehard[wd_strict==1, .N, by=fy][order(fy)]

saveRDS(list(RES=RES,SPL=SPL,AUX=AUX,comp=comp,loo=loo,loo_summary=loo_summary,fy_strict=fy_strict),
        file.path(OUT,"test_results.rds"))

cat("\n================= R24 EPISODE-LEVEL RESULTS =================\n")
for(nm in c("hardened","pureflag","diag_wd_strict","diag_late30")){ r<-RES[[nm]]
  cat(sprintf("\n[%s] n=%d base=%.5f | worst-decile-late n=%d ev=%d evrate=%.4f (distinct wd firms=%d)\n",
      nm, r$n, r$base, r$n1, r$x1, r$evr1 %||% NA, r$nfirm_wd))
  cat(sprintf("   LIFT=%.3f Wilson95=[%.3f,%.3f] firmBoot95=[%.3f,%.3f]\n",
      r$lift %||% NA, r$lift_wilson[1] %||% NA, r$lift_wilson[2] %||% NA, r$lift_boot[1] %||% NA, r$lift_boot[2] %||% NA))
  cat(sprintf("   OR_raw=%.3f | OR_ctrl_noFE=%.3f [%.3f,%.3f] p=%.4g | OR_ctrl_yearFE(PRIMARY)=%.3f [%.3f,%.3f] p=%.4g\n",
      r$or_raw %||% NA, r$or_no %||% NA, r$ci_no[1] %||% NA, r$ci_no[2] %||% NA, r$p_no %||% NA,
      r$or_fe %||% NA, r$ci_fe[1] %||% NA, r$ci_fe[2] %||% NA, r$p_fe %||% NA)) }
cat("\n================= STABILITY (hardened pre/post 2016) =================\n")
for(seg in c("pre2016","post2016")){ q<-SPL[[seg]]
  cat(sprintf("[%s] estimable=%s n=%d wd_n=%d ev=%d lift=%.2f OR=%.3f p=%.4g\n",
      seg, q$estimable, q$n, q$n1, q$ev1, q$lift %||% NA, q$or %||% NA, q$p %||% NA)) }
cat("\n================= AUX (continuous delay -> delisting-only) =================\n")
cat(sprintf("[aux] OR/SD(delay_z)=%.3f p=%.4g n=%d delist-hits=%d\n", AUX$or %||% NA, AUX$p %||% NA, AUX$n, AUX$n_del))
cat("\n[composition] hardened FROZEN-primary worst-decile forward-12m hits by type:\n"); print(unlist(comp))
cat("\n================= STRICT-TAIL DIAGNOSTIC LOO (drop each firm) =================\n")
cat(sprintf("[LOO strict-tail] firms=%d event-firms=%d | min OR(noFE)=%.3f max p=%.4g | any drop kills OR<=1: %s | any kills p>=0.05: %s\n",
  loo_summary$n_firms, loo_summary$n_event_firms, loo_summary$min_or, loo_summary$max_p,
  loo_summary$any_kills_or1, loo_summary$any_kills_p05))
cat("[strict-tail fy spread]:\n"); print(fy_strict)
cat("\n[03] DONE\n")
