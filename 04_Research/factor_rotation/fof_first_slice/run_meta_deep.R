## run_meta_deep.R — depth 수리: 진단이 검증한 fammean 신호를 제대로 배선 (튜닝 + 예측-IC 가중)
## 결함1(튜닝0) 수리: family-shrink λ 그리드. 결함3 수리: 진단 회귀식(IS-only)을 직접 가중에 사용(예측-IC).
## 전부 base(3.57) 대비 paired-NW-t. fammean은 t+3.24 증분예측 검증됨 — 배선이 이를 살리나?
suppressPackageStartupMessages({library(data.table); library(arrow); library(sandwich); library(lmtest)})
setDTthreads(1); try(arrow::set_io_thread_count(1),silent=TRUE)
QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
OUT<-"04_Research/factor_rotation/fof_first_slice"; con<-file(file.path(OUT,"_meta_deep.txt"),"w",encoding="UTF-8"); w<-function(...) writeLines(paste0(...),con)
zc<-function(x){ s<-sd(x,na.rm=T); if(is.na(s)||s<1e-9) x-mean(x,na.rm=T) else (x-mean(x,na.rm=T))/s }
fam_of<-function(fid){ p<-toupper(substr(fid,1,2)); p1<-substr(p,1,1)
  if(p1=="V")"Value" else if(p1=="M")"Momentum" else if(p1=="Q"||p=="GR")"Quality" else if(p1=="D")"LowRisk"
  else if(p1=="L")"Liquidity" else if(p1=="A")"Accrual" else if(p1=="C")"Consensus" else if(p1=="I"||p=="XF")"Flow"
  else if(p=="CR"||p=="SE")"Crowding" else if(p1=="R")"Risk" else if(p1=="G")"Growth" else "Other" }
w("======== fammean 신호 deep 배선 (튜닝 + 예측-IC) ========"); w(sprintf("실행 %s",as.character(Sys.time())))
sc<-as.data.table(read_parquet("outputs/ramp/pure_factor_scores.parquet", col_select=c("signal_date","security_id","factor_id","neutralized_z")))
setnames(sc,"neutralized_z","nz"); sc[,signal_date:=as.Date(signal_date)]; setnames(sc,c("signal_date","security_id"),c("date","tic"))
bo<-readRDS(".cache/_bo_fwdgic.rds"); fwd<-bo$fwd
ret_dt<-as.data.table(fwd$returns_dt)[,.(date=as.Date(Date),tic=Ticker,Ret=Ret_1m)]
bench_dt<-as.data.table(fwd$bench_dt)[,.(date=as.Date(Date),BM=BM_Ret)]
liq_dt<-as.data.table(fwd$liq_dt)[,.(date=as.Date(Date),tic=Ticker,adv)]
FIC<-readRDS(file.path(OUT,"_factor_ic.rds")); setorder(FIC,factor_id,Date); FIC[,fam:=sapply(factor_id,fam_of)]
FIC[, icmean := shift(frollmean(ic,12L,na.rm=TRUE),1L), by=factor_id]
FIC[, ichit  := shift(frollmean(as.numeric(ic>0),12L,na.rm=TRUE),1L), by=factor_id]
FIC[, fammean:= mean(icmean,na.rm=TRUE), by=.(Date,fam)]
FIC[, fwd_ic := shift(ic,-1L), by=factor_id]
## 예측-IC: expanding pooled 회귀 fwd_ic ~ icmean+fammean+ichit (annual refit, IS-only)
FIC[, pred_ic := NA_real_]; dates<-sort(unique(FIC$Date)); OOS<-dates[dates>=dates[61]]
cf<-NULL
for(i in seq_along(OOS)){ t<-OOS[i]
  if((i-1)%%12==0){ tr<-FIC[Date<t & is.finite(fwd_ic) & is.finite(icmean) & is.finite(fammean) & is.finite(ichit)]
    cf<-tryCatch(coef(lm(fwd_ic~icmean+fammean+ichit,tr)),error=function(e) cf) }
  if(!is.null(cf)){ FIC[Date==t & is.finite(icmean)&is.finite(fammean)&is.finite(ichit),
    pred_ic := cf[1]+cf[2]*icmean+cf[3]*fammean+cf[4]*ichit] } }
FW<-FIC[,.(date=Date,factor_id,icmean,fammean,pred_ic)]
## 스코어 빌더 (weight rule)
mkS<-function(rule,lam=NULL){
  x<-merge(sc[,.(date,tic,factor_id,nz)], FW, by=c("date","factor_id")); x<-x[is.finite(icmean)]
  x[, wf := switch(rule,
    base   = pmax(icmean,0),
    shrink = pmax((1-lam)*icmean + lam*fifelse(is.finite(fammean),fammean,icmean), 0),
    predic = pmax(fifelse(is.finite(pred_ic),pred_ic,icmean), 0) )]
  x<-x[is.finite(wf)]; s<-x[,.(score=if(sum(wf,na.rm=T)>0) sum(wf*nz,na.rm=T)/sum(wf,na.rm=T) else mean(nz)),by=.(date,tic)]
  s[,score:=zc(score),by=date]; s[,.(date,tic,score)] }
## eval
months<-sort(unique(sc$date)); W<-48L
hist_cnt<-function(t,tics){ trd<-tail(months[months<t],W); ret_dt[tic %in% tics & date %in% trd & is.finite(Ret), .N, by=tic] }
sr<-function(r){r<-r[is.finite(r)];if(length(r)<6)return(NA);mean(r)/sd(r)*sqrt(12)}
mddf<-function(r){r<-r[is.finite(r)];nav<-cumprod(1+r);max(1-nav/cummax(nav))}
ptv<-function(d,from=NULL){a<-d;if(!is.null(from))a<-a[date>=as.Date(from)];a<-a[is.finite(act)];if(nrow(a)<12)return(NA);f<-lm(act~1,a);as.numeric(coeftest(f,vcov=NeweyWest(f,lag=3,prewhite=F))[1,3])}
oos_ret<-function(d){d<-d[is.finite(act)];n<-nrow(d);rs<-c();for(q in c(0.55,0.65,0.75)){k<-floor(n*q);si<-sr(d$act[1:k]);so<-sr(d$act[(k+1):n]);rs<-c(rs,if(is.finite(si)&&si>0) so/si else NA)};median(rs,na.rm=TRUE)}
evalS<-function(sdt){ S<-merge(sdt, liq_dt, by=c("date","tic"))[adv>=2e8]; ser<-data.table(); prevw<-numeric(0); st<-which(months>=months[W+1L])[1]
  for(ti in st:length(months)){ t<-months[ti]; sel<-S[date==t][order(-score)][1:min(25,.N)][is.finite(score)]
    sel<-sel[tic %in% hist_cnt(t,sel$tic)[N>=as.integer(0.75*W),tic]]; if(nrow(sel)<8) next
    fr2<-ret_dt[date==t & tic %in% sel$tic]; fwdv<-setNames(fr2$Ret,fr2$tic); cn<-intersect(sel$tic,names(fwdv)); if(length(cn)<8) next
    av<-setNames(sel[match(cn,tic),score],cn); wv<-exp(2*av); wv<-wv/sum(wv)
    allt<-union(names(prevw),cn); pv<-setNames(rep(0,length(allt)),allt); cv<-pv; pv[names(prevw)]<-prevw; cv[cn]<-wv; to<-sum(abs(cv-pv)); prevw<-wv
    ser<-rbind(ser, data.table(date=t, net=sum(wv*fwdv[cn])-0.0015*to)) }
  merge(ser,bench_dt,by="date")[,act:=net-BM][order(date)] }
w("\n=== fammean deep: shrink λ 그리드 + 예측-IC (vs base paired-NW-t) ===")
base_d<-evalS(mkS("base"))
rep1<-function(lab,d){ mg<-merge(base_d[,.(date,ab=act)],d[,.(date,an=act)],by="date"); mg[,dd:=an-ab]; ft<-lm(dd~1,mg); dv<-as.numeric(coeftest(ft,vcov=NeweyWest(ft,lag=3,prewhite=F))[1,3])
  w(sprintf("  [%-12s] pt_full=%+.2f pt_18p=%+.2f SR=%.2f MDD=%.1f oos=%.2f | Δt=%+.2f", lab, ptv(d),ptv(d,"2018-01-01"),sr(d$net),100*mddf(d$net),oos_ret(d),dv)); dv }
w(sprintf("  [%-12s] pt_full=%+.2f pt_18p=%+.2f SR=%.2f MDD=%.1f oos=%.2f", "base", ptv(base_d),ptv(base_d,"2018-01-01"),sr(base_d$net),100*mddf(base_d$net),oos_ret(base_d)))
best<-list(dv=-9,lab="");
for(lam in c(0.15,0.3,0.45,0.6,0.8)){ d<-evalS(mkS("shrink",lam)); dv<-rep1(sprintf("shrink λ=%.2f",lam),d); if(dv>best$dv) best<-list(dv=dv,lab=paste0("λ",lam)) }
dp<-evalS(mkS("predic")); dvp<-rep1("pred-IC",dp); if(dvp>best$dv) best<-list(dv=dvp,lab="predIC")
w(sprintf("\n  최고 Δt=%+.2f (%s). >2면 fammean 배선이 유의 개선 = depth가 새 알파 발굴.", best$dv, best$lab))
cat(sprintf("METADEEP| best_dt=%.2f (%s)\n", best$dv, best$lab))
close(con); cat("META_DEEP_DONE\n")
