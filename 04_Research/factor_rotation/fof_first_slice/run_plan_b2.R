## run_plan_b2.R — Build2: S3(진짜 RMT 디노이징 집계 U-rmt·U-hier) vs S3'(supervised) — 절대지표 H5 + H6 priced
source("04_Research/factor_rotation/fof_first_slice/plan_lib.R")
st<-readRDS(file.path(OUT,"_plan_state.rds")); D<-st$D; FIC<-st$FIC; mkbase<-st$mkbase; S2<-st$S2
con<-file(file.path(OUT,"_plan_b2.txt"),"w",encoding="UTF-8"); w<-function(...) writeLines(paste0(...),con)
w("======== Build2: S3 RMT집계 vs supervised — 절대지표 H5/H6 ========"); w(sprintf("실행 %s",as.character(Sys.time())))
sc<-D$sc; ret_dt<-D$ret_dt; facs<-sort(unique(sc$factor_id)); months<-sort(unique(sc$date))
wideM<-function(t) dcast(sc[date==t],tic~factor_id,value.var="nz")
## ── S3 U-rmt: 진짜 RMT 디노이징 (λ+ 이하 bulk를 평균으로 shrink, LdP denoising) → signal 고유벡터로 집계 ──
build_urmt<-function(fset=facs){
  SE<-list(); Vc<-NULL; vfac<-NULL
  for(ti in which(months>=months[61])){ t<-months[ti]
    if((ti-61)%%12==0){ tr<-tail(months[months<t],60)
      Xtr<-as.matrix(dcast(sc[date %in% tr & factor_id %in% fset],tic+date~factor_id,value.var="nz")[,-(1:2)])
      keep<-colSums(is.finite(Xtr))>=nrow(Xtr)*0.7; Xtr<-Xtr[,keep,drop=FALSE]; vfac<-colnames(Xtr); Xtr[!is.finite(Xtr)]<-0
      Ns<-nrow(Xtr); Nf<-ncol(Xtr); C<-cor(Xtr); C[!is.finite(C)]<-0
      eg<-eigen(C,symmetric=TRUE); ev<-eg$values; lam<-(1+sqrt(Nf/Ns))^2
      ## LdP 디노이징: λ+ 이하 고유값을 평균으로 치환
      nsig<-sum(ev>lam); if(nsig<1) nsig<-1
      Vc<-eg$vectors[,1:nsig,drop=FALSE] }   # signal 고유벡터만 (denoised subspace)
    Mt<-wideM(t); tics<-Mt$tic; Xt<-as.matrix(Mt[,-1]); idx<-match(vfac,colnames(Xt)); ok<-!is.na(idx)
    Xt2<-Xt[,idx[ok],drop=FALSE]; Xt2[!is.finite(Xt2)]<-0; SEt<-Xt2 %*% Vc[ok,,drop=FALSE]
    SE[[as.character(t)]]<-data.table(date=t,tic=tics,as.data.table(SEt)) }
  SEdt<-rbindlist(SE,fill=TRUE); kmax<-ncol(SEdt)-2; setnames(SEdt,c("date","tic",paste0("SF",1:kmax)))
  ## premium = super-factor trailing 12m IC (저-dim robust)
  SR<-merge(SEdt, ret_dt, by=c("date","tic")); premL<-list()
  for(j in 1:kmax){ sfc<-paste0("SF",j); icj<-SR[is.finite(get(sfc)),.(ic=suppressWarnings(cor(get(sfc),Ret,method="spearman",use="complete.obs"))),by=date]; setorder(icj,date)
    icj[,prem:=shift(frollmean(ic,12L,na.rm=TRUE),1L)]; premL[[j]]<-icj[,.(date,j,prem)] }
  premdt<-dcast(rbindlist(premL),date~j,value.var="prem"); setnames(premdt,c("date",paste0("p",1:kmax)))
  Sd<-merge(SEdt, premdt, by="date")
  P<-as.matrix(Sd[,paste0("p",1:kmax),with=FALSE]); Fm<-as.matrix(Sd[,paste0("SF",1:kmax),with=FALSE]); P[!is.finite(P)]<-0; Fm[!is.finite(Fm)]<-0
  Sd[, raw:=rowSums(P*Fm)]; Sd[,score:=zc(raw),by=date]; Sd[,.(date,tic,score)] }
## ── S3 U-hier: IC-상관 위계 클러스터링 → 클러스터 composite → 클러스터-IC 가중 ──
build_uhier<-function(K=8){
  ic_wide<-dcast(D$FIC,Date~factor_id,value.var="ic"); ic_wide<-ic_wide[Date<months[130]]  # 초기창 클러스터(PIT 근사)
  Cm<-cor(as.matrix(ic_wide[,-1]),use="pairwise.complete.obs"); Cm[!is.finite(Cm)]<-0
  cl<-cutree(hclust(as.dist(1-Cm),method="ward.D2"),k=K); cldt<-data.table(factor_id=colnames(Cm),cl=cl)
  x<-merge(sc[,.(date,tic,factor_id,nz)], cldt, by="factor_id")
  FIC2<-copy(D$FIC); FIC2[,tw:=shift(frollmean(ic,12L,na.rm=TRUE),1L),by=factor_id]
  x<-merge(x, FIC2[,.(date=Date,factor_id,tw)], by=c("date","factor_id")); x<-x[is.finite(tw)]; x[,wf:=pmax(tw,0)]
  g<-x[,.(gz=if(sum(wf)>0) sum(wf*nz)/sum(wf) else mean(nz)),by=.(date,tic,cl)]; g[,gz:=zc(gz),by=.(date,cl)]
  gr<-merge(g, ret_dt, by=c("date","tic")); gic<-gr[,.(gic=suppressWarnings(cor(gz,Ret,method="spearman"))),by=.(date,cl)]
  setorder(gic,cl,date); gic[,gtw:=shift(frollmean(gic,12L,na.rm=TRUE),1L),by=cl]
  gg<-merge(g,gic[,.(date,cl,gtw)],by=c("date","cl")); gg<-gg[is.finite(gtw)]
  s<-gg[,.(score=if(sum(pmax(gtw,0))>0) sum(pmax(gtw,0)*gz)/sum(pmax(gtw,0)) else mean(gz)),by=.(date,tic)]; s[,score:=zc(score),by=date]; s[,.(date,tic,score)] }
pr<-function(lab,d){ m<-metrics_abs(d); w(sprintf("  [%-16s] absSR=%.2f Sortino=%.2f CAGR=%+.1f%% MDD=%.1f%% Calmar=%.2f CDaR=%.1f%%",lab,m$SR,m$Sortino,m$CAGR,m$MDD,m$Calmar,m$CDaR)); m }
w("\n=== H5: 절대지표 U-family vs S-family (Kelly 사영, 레짐 OFF) ===")
pr("S-base(full316)", project_portfolio(mkbase(FALSE,FALSE), D, kelly=TRUE, use_regime=FALSE))
pr("U-rmt(full316)",  project_portfolio(build_urmt(facs), D, kelly=TRUE, use_regime=FALSE))
pr("U-rmt(pruned)",   project_portfolio(build_urmt(S2$kept), D, kelly=TRUE, use_regime=FALSE))
pr("U-hier K=8",      project_portfolio(build_uhier(8), D, kelly=TRUE, use_regime=FALSE))
if(file.exists(file.path(OUT,"proper_ipca_scores.csv"))){ ip<-fread(file.path(OUT,"proper_ipca_scores.csv")); dmap<-unique(ret_dt[,.(date)]); dmap[,ym:=format(date,"%Y-%m")]; ip<-merge(ip,dmap,by="ym")
  pr("S-ridge α2000", project_portfolio(ip[is.finite(ridge_a2000),.(date,tic,score=ridge_a2000)], D, kelly=TRUE, use_regime=FALSE)) }
w("\n  → 절대 Calmar/CDaR로 U-family가 S-base 초과하면 H5 지지(플랜 중심논제). 아니면 H5 기각.")
cat("PLANB2| done\n"); close(con); cat("PLAN_B2_DONE\n")
