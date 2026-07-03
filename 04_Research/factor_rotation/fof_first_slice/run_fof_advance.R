## run_fof_advance.R — FoF 개념 고도화 Phase A (도훈 mandate 07-01: 개념 고도화에 자원 高배정)
## 미탐색 팩터-메타 축 5개, base(시즌드+IC틸트, pt 3.46/IR 1.07) 대비 단일격리 + paired-NW-t:
##  A1 crowd-pen: 팩터 롱레그의 CR(crowding)-z 평균 → 혼잡 팩터 down-weight
##  A2 ic-slope: IC 기울기(최근6m − 과거7~18m) → 감쇠 중 팩터 선제 강등 (레벨필터 signstab와 다름)
##  A3 ic-persist: 단기(6m)·장기(24m) IC 부호 일치 팩터만
##  A4 hier2: 2단계 계층 — 군내 IC-가중 composite → 군간 groupIC-가중 (C 계층 정교화)
##  A5 tail-pen: 팩터 롱레그 수익 trailing skew — 음-skew 팩터 강등
suppressPackageStartupMessages({library(data.table); library(arrow); library(sandwich); library(lmtest)})
setDTthreads(1); try(arrow::set_io_thread_count(1),silent=TRUE)
QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
OUT<-"04_Research/factor_rotation/fof_first_slice"; con<-file(file.path(OUT,"_fof_advance.txt"),"w",encoding="UTF-8"); w<-function(...) writeLines(paste0(...),con)
zc<-function(x){ s<-sd(x,na.rm=T); if(is.na(s)||s<1e-9) x-mean(x,na.rm=T) else (x-mean(x,na.rm=T))/s }
fam_of<-function(fid){ p<-toupper(substr(fid,1,2)); p1<-substr(p,1,1)
  if(p1=="V") "Value" else if(p1=="M") "Momentum" else if(p1=="Q"||p=="GR") "Quality"
  else if(p1=="D") "LowRisk" else if(p1=="L") "Liquidity" else if(p1=="A") "Accrual"
  else if(p1=="C") "Consensus" else if(p1=="I"||p=="XF") "Flow" else if(p=="CR"||p=="SE") "Crowding"
  else if(p1=="R") "Risk" else if(p1=="G") "Growth" else "Other" }
w("================ FoF 개념 고도화 Phase A ================"); w(sprintf("실행 %s",as.character(Sys.time())))
sc<-as.data.table(read_parquet("outputs/ramp/pure_factor_scores.parquet", col_select=c("signal_date","security_id","factor_id","neutralized_z")))
setnames(sc,"neutralized_z","nz"); sc[,signal_date:=as.Date(signal_date)]; setnames(sc,c("signal_date","security_id"),c("date","tic"))
bo<-readRDS(".cache/_bo_fwdgic.rds"); fwd<-bo$fwd
ret_dt<-as.data.table(fwd$returns_dt)[,.(date=as.Date(Date),tic=Ticker,Ret=Ret_1m)]
bench_dt<-as.data.table(fwd$bench_dt)[,.(date=as.Date(Date),BM=BM_Ret)]
liq_dt<-as.data.table(fwd$liq_dt)[,.(date=as.Date(Date),tic=Ticker,adv)]
FIC<-readRDS(file.path(OUT,"_factor_ic.rds")); setorder(FIC,factor_id,Date)
## 공통: base 팩터가중 tw (12m IC)
FIC[,tw:=shift(frollmean(ic,12L,na.rm=TRUE),1L),by=factor_id]
## A2: slope = 최근6m mean − 과거7~18m mean (shift1)
FIC[,ic6 :=shift(frollmean(ic,6L ,na.rm=TRUE),1L),by=factor_id]
FIC[,ic18:=shift(frollmean(ic,18L,na.rm=TRUE),1L),by=factor_id]
FIC[,slope:=ic6-(18*ic18-6*ic6)/12]                       # 최근6 − 과거7~18
## A3: 장기 24m
FIC[,ic24:=shift(frollmean(ic,24L,na.rm=TRUE),1L),by=factor_id]
FW<-FIC[,.(date=Date,factor_id,tw,ic6,ic24,slope)]
## A1/A5: 팩터 롱레그 특성 (crowding-z 평균 · 수익 skew)
crf<-unique(sc$factor_id); crf<-crf[grepl("^CR|^SE",crf)]
stk_cr<-sc[factor_id %in% crf, .(cr_z=mean(nz,na.rm=T)), by=.(date,tic)]
m<-merge(sc[,.(date,tic,factor_id,nz)], ret_dt, by=c("date","tic"))
m[, rk:=frank(-nz,ties.method="first")/.N, by=.(date,factor_id)]
top<-m[rk<=0.2]
fr<-top[,.(fret=mean(Ret,na.rm=T)),by=.(date,factor_id)]
tc<-merge(top[,.(date,factor_id,tic)], stk_cr, by=c("date","tic"))
fcr<-tc[,.(crowd=mean(cr_z,na.rm=T)),by=.(date,factor_id)]        # higher=CR-z高=덜혼잡(nz 정렬)
setorder(fr,factor_id,date)
fr[,skew:=shift(frollapply(fret,24L,function(z){z<-z[is.finite(z)];if(length(z)<12)return(NA);mean(((z-mean(z))/sd(z))^3)},fill=NA),1L),by=factor_id]
META<-Reduce(function(a,b) merge(a,b,by=c("date","factor_id"),all=TRUE), list(FW, fcr, fr[,.(date,factor_id,skew)]))
for(cc in c("crowd","slope","skew")) META[,(paste0("z_",cc)):=zc(get(cc)),by=date]
## 스코어 빌더
mkS<-function(mode){
  x<-merge(sc, META, by=c("date","factor_id")); x<-x[is.finite(tw)]
  if(mode=="base")        x[, wf:=pmax(tw,0)]
  else if(mode=="A1_crowd") x[, wf:=pmax(tw,0)*pmax(1+0.5*fifelse(is.finite(z_crowd),z_crowd,0),0)]
  else if(mode=="A2_slope") x[, wf:=pmax(tw,0)*pmax(1+0.5*fifelse(is.finite(z_slope),z_slope,0),0)]
  else if(mode=="A3_persist") x[, wf:=pmax(tw,0)*as.numeric(ic6>0 & ic24>0)]
  else if(mode=="A5_tail")  x[, wf:=pmax(tw,0)*pmax(1+0.3*fifelse(is.finite(z_skew),z_skew,0),0)]
  s<-x[,.(score=if(sum(wf,na.rm=T)>0) sum(wf*nz,na.rm=T)/sum(wf,na.rm=T) else mean(nz)),by=.(date,tic)]
  s[,score:=zc(score),by=date]; s[,.(date,tic,score)] }
mkS_hier<-function(){  ## A4: 군내 tw-가중 composite → 군간 groupIC 가중
  x<-merge(sc, FW[,.(date,factor_id,tw)], by=c("date","factor_id")); x<-x[is.finite(tw)]
  x[, fam:=sapply(factor_id, fam_of)]
  g<-x[,.(gz=if(sum(pmax(tw,0))>0) sum(pmax(tw,0)*nz)/sum(pmax(tw,0)) else mean(nz)),by=.(date,tic,fam)]
  g[,gz:=zc(gz),by=.(date,fam)]
  gr<-merge(g, ret_dt, by=c("date","tic"))
  gic<-gr[,.(gic=suppressWarnings(cor(gz,Ret,method="spearman"))),by=.(date,fam)]
  setorder(gic,fam,date); gic[,gtw:=shift(frollmean(gic,12L,na.rm=TRUE),1L),by=fam]
  gg<-merge(g, gic[,.(date,fam,gtw)], by=c("date","fam")); gg<-gg[is.finite(gtw)]
  s<-gg[,.(score=if(sum(pmax(gtw,0))>0) sum(pmax(gtw,0)*gz)/sum(pmax(gtw,0)) else mean(gz)),by=.(date,tic)]
  s[,score:=zc(score),by=date]; s[,.(date,tic,score)] }
## 시즌드+틸트 평가
months<-sort(unique(sc$date)); W<-48L
hist_cnt<-function(t,tics){ trd<-tail(months[months<t],W); ret_dt[tic %in% tics & date %in% trd & is.finite(Ret), .N, by=tic] }
sr<-function(r){r<-r[is.finite(r)];if(length(r)<6)return(NA);mean(r)/sd(r)*sqrt(12)}
mddf<-function(r){r<-r[is.finite(r)];nav<-cumprod(1+r);max(1-nav/cummax(nav))}
ptv<-function(d,from=NULL){a<-d;if(!is.null(from))a<-a[date>=as.Date(from)];a<-a[is.finite(act)];if(nrow(a)<12)return(NA);f<-lm(act~1,a);as.numeric(coeftest(f,vcov=NeweyWest(f,lag=3,prewhite=F))[1,3])}
oos_ret<-function(d){d<-d[is.finite(act)];n<-nrow(d);rs<-c();for(q in c(0.55,0.65,0.75)){k<-floor(n*q);si<-sr(d$act[1:k]);so<-sr(d$act[(k+1):n]);rs<-c(rs,if(is.finite(si)&&si>0) so/si else NA)};median(rs,na.rm=TRUE)}
evalS<-function(score_dt){ S<-merge(score_dt, liq_dt, by=c("date","tic"))[adv>=2e8]; ser<-data.table(); prevw<-numeric(0); st<-which(months>=months[W+1L])[1]
  for(ti in st:length(months)){ t<-months[ti]; sel<-S[date==t][order(-score)][1:min(25,.N)][is.finite(score)]
    sel<-sel[tic %in% hist_cnt(t,sel$tic)[N>=as.integer(0.75*W),tic]]; if(nrow(sel)<8) next
    fr2<-ret_dt[date==t & tic %in% sel$tic]; fwdv<-setNames(fr2$Ret,fr2$tic); cn<-intersect(sel$tic,names(fwdv)); if(length(cn)<8) next
    av<-setNames(sel[match(cn,tic),score],cn); wv<-exp(2*av); wv<-wv/sum(wv)
    allt<-union(names(prevw),cn); pv<-setNames(rep(0,length(allt)),allt); cv<-pv; pv[names(prevw)]<-prevw; cv[cn]<-wv; to<-sum(abs(cv-pv)); prevw<-wv
    ser<-rbind(ser, data.table(date=t, net=sum(wv*fwdv[cn])-0.0015*to)) }
  merge(ser,bench_dt,by="date")[,act:=net-BM][order(date)] }
w("\n=== Phase A 단일격리 (vs base paired-NW-t) ===")
D<-list(); D$base<-evalS(mkS("base"))
rep1<-function(lab,d){ m<-list(SR=sr(d$net),MDD=100*mddf(d$net),pt=ptv(d),p18=ptv(d,"2018-01-01"),oos=oos_ret(d))
  dv<-NA; if(lab!="base"){ mg<-merge(D$base[,.(date,ab=act)],d[,.(date,an=act)],by="date"); mg[,dd:=an-ab]; ft<-lm(dd~1,mg); dv<-as.numeric(coeftest(ft,vcov=NeweyWest(ft,lag=3,prewhite=F))[1,3]) }
  w(sprintf("  [%-10s] SR=%.2f MDD=%.1f | pt_full=%+.2f pt_18p=%+.2f oos=%.2f%s", lab,m$SR,m$MDD,m$pt,m$p18,m$oos, ifelse(is.na(dv),"",sprintf(" | Δt=%+.2f",dv))))
  c(m,list(dvst=dv)) }
res<-list(); res$base<-rep1("base",D$base)
for(md in c("A1_crowd","A2_slope","A3_persist","A5_tail")){ D[[md]]<-evalS(mkS(md)); res[[md]]<-rep1(md,D[[md]]) }
D$A4_hier2<-evalS(mkS_hier()); res$A4_hier2<-rep1("A4_hier2",D$A4_hier2)
tab<-rbindlist(lapply(names(res),function(k) data.table(mode=k, SR=round(res[[k]]$SR,2), MDD=round(res[[k]]$MDD,1), pt_full=round(res[[k]]$pt,2), pt_18p=round(res[[k]]$p18,2), oos=round(res[[k]]$oos,2), dvst=round(res[[k]]$dvst,2))))
fwrite(tab, file.path(OUT,"advance_results.csv")); saveRDS(D, file.path(OUT,"_advance_series.rds"))
cat("ADV|", paste(sprintf("%s:pt%.2f/18p%.2f/SR%.2f%s",tab$mode,tab$pt_full,tab$pt_18p,tab$SR,ifelse(is.na(tab$dvst),"",sprintf("/dt%.1f",tab$dvst))),collapse=" "),"\n")
close(con); cat("FOF_ADVANCE_DONE\n")
