## run_phase3_h6.R — 플랜 H6: 추출 공통인자가 priced인가? priced-방향 선택이 base를 이기나?
## top-30 denoised 고유벡터 각각의 premium(trailing IC) vs 분산순위 정렬 진단 + premium순 선택 집계.
## 핵심 판정: priced-ness가 분산순위와 어긋나면 → 공통구조≠priced (max-variance 아티팩트) 확정.
suppressPackageStartupMessages({library(data.table); library(arrow); library(sandwich); library(lmtest)})
setDTthreads(1); try(arrow::set_io_thread_count(1),silent=TRUE)
QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
OUT<-"04_Research/factor_rotation/fof_first_slice"; con<-file(file.path(OUT,"_phase3_h6.txt"),"w",encoding="UTF-8"); w<-function(...) writeLines(paste0(...),con)
zc<-function(x){ s<-sd(x,na.rm=T); if(is.na(s)||s<1e-9) x-mean(x,na.rm=T) else (x-mean(x,na.rm=T))/s }
w("======== H6: 공통인자 priced 검정 + premium-선택 집계 ========"); w(sprintf("실행 %s",as.character(Sys.time())))
sc<-as.data.table(read_parquet("outputs/ramp/pure_factor_scores.parquet", col_select=c("signal_date","security_id","factor_id","neutralized_z")))
setnames(sc,"neutralized_z","nz"); sc[,signal_date:=as.Date(signal_date)]; setnames(sc,c("signal_date","security_id"),c("date","tic"))
bo<-readRDS(".cache/_bo_fwdgic.rds"); fwd<-bo$fwd
ret_dt<-as.data.table(fwd$returns_dt)[,.(date=as.Date(Date),tic=Ticker,Ret=Ret_1m)]
bench_dt<-as.data.table(fwd$bench_dt)[,.(date=as.Date(Date),BM=BM_Ret)]
liq_dt<-as.data.table(fwd$liq_dt)[,.(date=as.Date(Date),tic=Ticker,adv)]
FIC<-readRDS(file.path(OUT,"_factor_ic.rds")); setorder(FIC,factor_id,Date); FIC[,tw:=shift(frollmean(ic,12L,na.rm=TRUE),1L),by=factor_id]
facs<-sort(unique(sc$factor_id)); months<-sort(unique(sc$date)); W<-48L; KTOP<-30L
wideM<-function(t) dcast(sc[date==t],tic~factor_id,value.var="nz")
## top-30 super-factor 노출 시계열 (연 1회 고유벡터, PIT)
SE<-list(); Vc<-NULL; vfac<-NULL; evrank<-NULL
for(ti in which(months>=months[61])){ t<-months[ti]
  if((ti-61)%%12==0){ tr<-tail(months[months<t],60)
    Xtr<-as.matrix(dcast(sc[date %in% tr],tic+date~factor_id,value.var="nz")[,-(1:2)])
    keep<-colSums(is.finite(Xtr))>=nrow(Xtr)*0.7; Xtr<-Xtr[,keep,drop=FALSE]; vfac<-facs[keep]; Xtr[!is.finite(Xtr)]<-0
    C<-cor(Xtr); C[!is.finite(C)]<-0; eg<-eigen(C,symmetric=TRUE); Vc<-eg$vectors[,1:KTOP,drop=FALSE] }
  Mt<-wideM(t); tics<-Mt$tic; Xt<-as.matrix(Mt[,-1]); idx<-match(vfac,colnames(Xt)); ok<-!is.na(idx)
  Xt2<-Xt[,idx[ok],drop=FALSE]; Xt2[!is.finite(Xt2)]<-0; SEt<-Xt2 %*% Vc[ok,,drop=FALSE]
  SE[[as.character(t)]]<-data.table(date=t,tic=tics,SEt) }
SEdt<-rbindlist(SE); setnames(SEdt,c("date","tic",paste0("SF",1:KTOP)))
SR<-merge(SEdt, ret_dt, by=c("date","tic"))
## 각 super-factor: 전기간 premium IC + t (priced?) — 분산순위(1=최대) vs priced 정렬
w("\n=== super-factor별: 분산순위 vs premium(IC) — priced가 분산과 정렬되나? ===")
pr<-data.table()
for(j in 1:KTOP){ icj<-SR[,.(ic=suppressWarnings(cor(get(paste0("SF",j)),Ret,method="spearman",use="complete.obs"))),by=date]
  icj<-icj[is.finite(ic)]; f<-lm(ic~1,icj); tt<-as.numeric(coeftest(f,vcov=NeweyWest(f,lag=3,prewhite=F))[1,3])
  pr<-rbind(pr,data.table(SF=j, mean_ic=mean(icj$ic), t=tt)) }
pr[,abst:=abs(t)]
w(sprintf("  분산순위 top5 (SF1-5) premium-t: %s", paste(sprintf("SF%d:%.1f",1:5,pr$t[1:5]),collapse=" ")))
w(sprintf("  |premium-t| 최고 5개: %s", paste(pr[order(-abst)][1:5,sprintf("SF%d(t%.1f)",SF,t)],collapse=" ")))
w(sprintf("  cor(분산순위, |premium-t|)=%.2f  (0 근처면 priced≠분산 → max-variance 아티팩트 확정)", cor(1:KTOP, pr$abst)))
w(sprintf("  priced super-factor 수(|t|>2): %d / %d", sum(pr$abst>2), KTOP))
fwrite(pr,file.path(OUT,"h6_superfactor_priced.csv"))
## premium-선택 집계: |premium| 상위 kk개를 premium 가중 (분산순위 무관) — PIT trailing premium
prem_all<-list()
for(j in 1:KTOP){ icj<-SR[,.(ic=suppressWarnings(cor(get(paste0("SF",j)),Ret,method="spearman",use="complete.obs"))),by=date]; setorder(icj,date)
  icj[,prem:=shift(frollmean(ic,12L,na.rm=TRUE),1L)]; prem_all[[j]]<-icj[,.(date,j,prem)] }
premdt<-dcast(rbindlist(prem_all),date~j,value.var="prem"); setnames(premdt,c("date",paste0("p",1:KTOP)))
build_sel<-function(kk){ S<-merge(SEdt, premdt, by="date")
  # 각 월 |trailing premium| 상위 kk개 super-factor만 premium 가중
  S[, score := {
    ps<-unlist(mget(paste0("p",1:KTOP))); sf<-unlist(mget(paste0("SF",1:KTOP)))
    NA_real_ }]  # placeholder (벡터화 아래)
  # 벡터화: 행별 상위 kk premium 마스크
  P<-as.matrix(S[,paste0("p",1:KTOP),with=FALSE]); Fm<-as.matrix(S[,paste0("SF",1:KTOP),with=FALSE])
  P[!is.finite(P)]<-0
  thr<-apply(abs(P),1,function(z){ if(sum(z>0)<=kk) 0 else sort(z,decreasing=TRUE)[kk] })
  mask<-abs(P)>=thr; sc2<-rowSums(P*Fm*mask,na.rm=TRUE)
  S[,score:=zc(sc2),by=date]; S[,.(date,tic,score)] }
build_base<-function(){ x<-merge(sc[,.(date,tic,factor_id,nz)], FIC[,.(date=Date,factor_id,tw)], by=c("date","factor_id")); x<-x[is.finite(tw)]; x[,wf:=pmax(tw,0)]
  s<-x[,.(score=if(sum(wf)>0) sum(wf*nz)/sum(wf) else mean(nz)),by=.(date,tic)]; s[,score:=zc(score),by=date]; s[,.(date,tic,score)] }
hist_cnt<-function(t,tics){ trd<-tail(months[months<t],W); ret_dt[tic %in% tics & date %in% trd & is.finite(Ret), .N, by=tic] }
sr<-function(r){r<-r[is.finite(r)];if(length(r)<6)return(NA);mean(r)/sd(r)*sqrt(12)}; mddf<-function(r){r<-r[is.finite(r)];nav<-cumprod(1+r);max(1-nav/cummax(nav))}
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
w("\n=== premium-선택 집계 (분산순위 무관 |premium| 상위) vs base ===")
bd<-evalS(build_base()); w(sprintf("  [%-14s] pt_full=%+.2f SR=%.2f","S-base",ptv(bd),sr(bd$net)))
for(kk in c(5,10,20,30)){ d<-evalS(build_sel(kk)); mg<-merge(bd[,.(date,ab=act)],d[,.(date,an=act)],by="date"); mg[,dd:=an-ab]; ft<-lm(dd~1,mg); dv<-as.numeric(coeftest(ft,vcov=NeweyWest(ft,lag=3,prewhite=F))[1,3])
  w(sprintf("  [premSel kk=%-2d ] pt_full=%+.2f pt_18p=%+.2f SR=%.2f MDD=%.1f oos=%.2f | Δt=%+.2f", kk, ptv(d),ptv(d,"2018-01-01"),sr(d$net),100*mddf(d$net),oos_ret(d),dv)) }
cat(sprintf("H6| cor_rank_priced=%.2f n_priced=%d/%d\n", cor(1:KTOP,pr$abst), sum(pr$abst>2), KTOP))
close(con); cat("PHASE3_H6_DONE\n")
