## run_phase3_urmt.R — 플랜 Phase 3 (H5 본체): 비지도 RMT-집계 vs supervised base
## 메커니즘: 316 팩터 상관행렬 → top-k RMT 고유벡터(super-factor, 비지도 추출·PIT trailing)
##   → 종목의 super-factor 노출 = X·V → 소수 super-factor를 trailing-IC(premium)로 가중 (저-dim robust)
##   → top-25. base(316 supervised IC-가중) 대비 paired-NW-t. k∈{3,5,10,13} (H3 복잡성).
suppressPackageStartupMessages({library(data.table); library(arrow); library(sandwich); library(lmtest)})
setDTthreads(1); try(arrow::set_io_thread_count(1),silent=TRUE)
QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
OUT<-"04_Research/factor_rotation/fof_first_slice"; con<-file(file.path(OUT,"_phase3_urmt.txt"),"w",encoding="UTF-8"); w<-function(...) writeLines(paste0(...),con)
zc<-function(x){ s<-sd(x,na.rm=T); if(is.na(s)||s<1e-9) x-mean(x,na.rm=T) else (x-mean(x,na.rm=T))/s }
w("======== Phase3 H5: 비지도 RMT-집계 vs supervised base ========"); w(sprintf("실행 %s",as.character(Sys.time())))
sc<-as.data.table(read_parquet("outputs/ramp/pure_factor_scores.parquet", col_select=c("signal_date","security_id","factor_id","neutralized_z")))
setnames(sc,"neutralized_z","nz"); sc[,signal_date:=as.Date(signal_date)]; setnames(sc,c("signal_date","security_id"),c("date","tic"))
bo<-readRDS(".cache/_bo_fwdgic.rds"); fwd<-bo$fwd
ret_dt<-as.data.table(fwd$returns_dt)[,.(date=as.Date(Date),tic=Ticker,Ret=Ret_1m)]
bench_dt<-as.data.table(fwd$bench_dt)[,.(date=as.Date(Date),BM=BM_Ret)]
liq_dt<-as.data.table(fwd$liq_dt)[,.(date=as.Date(Date),tic=Ticker,adv)]
FIC<-readRDS(file.path(OUT,"_factor_ic.rds")); setorder(FIC,factor_id,Date)
FIC[,tw:=shift(frollmean(ic,12L,na.rm=TRUE),1L),by=factor_id]
facs<-sort(unique(sc$factor_id)); months<-sort(unique(sc$date)); W<-48L
## 월별 wide 노출 행렬 (tic × factor) 캐시
wideM<-function(t){ M<-dcast(sc[date==t],tic~factor_id,value.var="nz"); M }
## ── super-factor score 빌더 (비지도 추출 + premium 가중) ──
## 고유벡터 V는 trailing 60m 풀 노출로 연 1회 추정(PIT). premium = super-factor trailing 12m IC.
build_urmt<-function(k){
  ser_score<-list(); Vc<-NULL; vfac<-NULL
  # super-factor 노출 시계열 저장 → premium(IC) 계산용
  SE<-list()
  yrs<-months[seq(61,length(months),by=1)]
  for(ti in which(months>=months[61])){ t<-months[ti]
    if((ti-61)%%12==0){  # 연 1회 고유벡터 재추정 (trailing 60m 풀)
      tr<-months[months<t]; tr<-tail(tr,60)
      Xtr<-dcast(sc[date %in% tr],tic+date~factor_id,value.var="nz")
      Xm<-as.matrix(Xtr[,-(1:2)]); keep<-colSums(is.finite(Xm))>=nrow(Xm)*0.7; Xm<-Xm[,keep,drop=FALSE]; vfac<-facs[keep]
      Xm[!is.finite(Xm)]<-0; C<-cor(Xm); C[!is.finite(C)]<-0
      eg<-eigen(C,symmetric=TRUE); Vc<-eg$vectors[,1:k,drop=FALSE] }
    Mt<-wideM(t); tics<-Mt$tic; Xt<-as.matrix(Mt[,-1]); cn<-colnames(Xt)
    idx<-match(vfac,cn); ok<-!is.na(idx); Xt2<-Xt[,idx[ok],drop=FALSE]; Xt2[!is.finite(Xt2)]<-0
    SEt<-Xt2 %*% Vc[ok,,drop=FALSE]   # 종목 × k super-factor 노출
    SE[[as.character(t)]]<-data.table(date=t,tic=tics,SEt)
  }
  SEdt<-rbindlist(SE); setnames(SEdt,c("date","tic",paste0("SF",1:k)))
  # premium = super-factor trailing 12m IC (PIT)
  SR<-merge(SEdt, ret_dt, by=c("date","tic"))
  icl<-list()
  for(j in 1:k){ icj<-SR[,.(ic=suppressWarnings(cor(get(paste0("SF",j)),Ret,method="spearman",use="complete.obs"))),by=date]
    setorder(icj,date); icj[,prem:=shift(frollmean(ic,12L,na.rm=TRUE),1L)]; icl[[j]]<-icj[,.(date,j=j,prem)] }
  premdt<-dcast(rbindlist(icl),date~j,value.var="prem"); setnames(premdt,c("date",paste0("p",1:k)))
  S<-merge(SEdt, premdt, by="date")
  S[, score:=rowSums(sapply(1:k,function(j) get(paste0("SF",j))*fifelse(is.finite(get(paste0("p",j))),get(paste0("p",j)),0)))]
  S[,score:=zc(score),by=date]; S[,.(date,tic,score)] }
## base (supervised 316 IC-가중)
build_base<-function(){ x<-merge(sc[,.(date,tic,factor_id,nz)], FIC[,.(date=Date,factor_id,tw)], by=c("date","factor_id")); x<-x[is.finite(tw)]; x[,wf:=pmax(tw,0)]
  s<-x[,.(score=if(sum(wf)>0) sum(wf*nz)/sum(wf) else mean(nz)),by=.(date,tic)]; s[,score:=zc(score),by=date]; s[,.(date,tic,score)] }
## eval
hist_cnt<-function(t,tics){ trd<-tail(months[months<t],W); ret_dt[tic %in% tics & date %in% trd & is.finite(Ret), .N, by=tic] }
sr<-function(r){r<-r[is.finite(r)];if(length(r)<6)return(NA);mean(r)/sd(r)*sqrt(12)}
mddf<-function(r){r<-r[is.finite(r)];nav<-cumprod(1+r);max(1-nav/cummax(nav))}
ptv<-function(d,from=NULL){a<-d;if(!is.null(from))a<-a[date>=as.Date(from)];a<-a[is.finite(act)];if(nrow(a)<12)return(NA);f<-lm(act~1,a);as.numeric(coeftest(f,vcov=NeweyWest(f,lag=3,prewhite=F))[1,3])}
oos_ret<-function(d){d<-d[is.finite(act)];n<-nrow(d);rs<-c();for(q in c(0.55,0.65,0.75)){k<-floor(n*q);si<-sr(d$act[1:k]);so<-sr(d$act[(k+1):n]);rs<-c(rs,if(is.finite(si)&&si>0) so/si else NA)};median(rs,na.rm=TRUE)}
evalS<-function(sdt){ sdt<-sdt[is.finite(score)]; S<-merge(sdt, liq_dt, by=c("date","tic"))[adv>=2e8]; ser<-data.table(); prevw<-numeric(0); st<-which(months>=months[W+1L])[1]
  for(ti in st:length(months)){ t<-months[ti]; sel<-S[date==t][order(-score)][1:min(25,.N)][is.finite(score)]
    sel<-sel[tic %in% hist_cnt(t,sel$tic)[N>=as.integer(0.75*W),tic]]; if(nrow(sel)<8) next
    fr2<-ret_dt[date==t & tic %in% sel$tic]; fwdv<-setNames(fr2$Ret,fr2$tic); cn<-intersect(sel$tic,names(fwdv)); if(length(cn)<8) next
    av<-setNames(sel[match(cn,tic),score],cn); wv<-exp(2*av); wv<-wv/sum(wv)
    allt<-union(names(prevw),cn); pv<-setNames(rep(0,length(allt)),allt); cv<-pv; pv[names(prevw)]<-prevw; cv[cn]<-wv; to<-sum(abs(cv-pv)); prevw<-wv
    ser<-rbind(ser, data.table(date=t, net=sum(wv*fwdv[cn])-0.0015*to)) }
  merge(ser,bench_dt,by="date")[,act:=net-BM][order(date)] }
w("\n=== H5: U-rmt(k) vs S-base (paired-NW-t) ===")
bd<-evalS(build_base())
w(sprintf("  [%-10s] pt_full=%+.2f pt_18p=%+.2f SR=%.2f MDD=%.1f oos=%.2f","S-base",ptv(bd),ptv(bd,"2018-01-01"),sr(bd$net),100*mddf(bd$net),oos_ret(bd)))
tab<-data.table(m="S-base",pt=ptv(bd),SR=round(sr(bd$net),2))
for(k in c(3,5,10,13)){ d<-evalS(build_urmt(k))
  mg<-merge(bd[,.(date,ab=act)],d[,.(date,an=act)],by="date"); mg[,dd:=an-ab]; ft<-lm(dd~1,mg); dv<-as.numeric(coeftest(ft,vcov=NeweyWest(ft,lag=3,prewhite=F))[1,3])
  w(sprintf("  [U-rmt k=%-2d ] pt_full=%+.2f pt_18p=%+.2f SR=%.2f MDD=%.1f oos=%.2f | Δt vs base=%+.2f", k, ptv(d),ptv(d,"2018-01-01"),sr(d$net),100*mddf(d$net),oos_ret(d),dv))
  tab<-rbind(tab,data.table(m=paste0("urmt",k),pt=ptv(d),SR=round(sr(d$net),2))) }
fwrite(tab,file.path(OUT,"phase3_urmt_results.csv"))
cat("URMT| ", paste(sprintf("%s:pt%.2f/SR%.2f",tab$m,tab$pt,tab$SR),collapse=" "),"\n")
close(con); cat("PHASE3_URMT_DONE\n")
