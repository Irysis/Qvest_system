## run_fof_advance2.R — FoF 개념 고도화 Phase B (w_f 추정 개선 + 팩터 메타신호, 단일격리 + 조합 + paired-NW-t)
## B1 fam_shrink: IC를 family-mean으로 수축(global shrink 실패와 다름) · B2 robust_med: 12m median IC(denoise)
## B4 stability: IC × 팩터 rank-자기상관(저-churn 우대, cost-aware) · B6 persist+shrink · B7 shrink+robust · B8 stability+persist
## + cluster(IC-상관 데이터군, family계층 A4 실패 대안). base=3.57.
suppressPackageStartupMessages({library(data.table); library(arrow); library(sandwich); library(lmtest)})
setDTthreads(1); try(arrow::set_io_thread_count(1),silent=TRUE)
QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
OUT<-"04_Research/factor_rotation/fof_first_slice"; con<-file(file.path(OUT,"_fof_advance2.txt"),"w",encoding="UTF-8"); w<-function(...) writeLines(paste0(...),con)
zc<-function(x){ s<-sd(x,na.rm=T); if(is.na(s)||s<1e-9) x-mean(x,na.rm=T) else (x-mean(x,na.rm=T))/s }
fam_of<-function(fid){ p<-toupper(substr(fid,1,2)); p1<-substr(p,1,1)
  if(p1=="V")"Value" else if(p1=="M")"Momentum" else if(p1=="Q"||p=="GR")"Quality" else if(p1=="D")"LowRisk"
  else if(p1=="L")"Liquidity" else if(p1=="A")"Accrual" else if(p1=="C")"Consensus" else if(p1=="I"||p=="XF")"Flow"
  else if(p=="CR"||p=="SE")"Crowding" else if(p1=="R")"Risk" else if(p1=="G")"Growth" else "Other" }
w("================ FoF 개념 고도화 Phase B ================"); w(sprintf("실행 %s",as.character(Sys.time())))
sc<-as.data.table(read_parquet("outputs/ramp/pure_factor_scores.parquet", col_select=c("signal_date","security_id","factor_id","neutralized_z")))
setnames(sc,"neutralized_z","nz"); sc[,signal_date:=as.Date(signal_date)]; setnames(sc,c("signal_date","security_id"),c("date","tic"))
bo<-readRDS(".cache/_bo_fwdgic.rds"); fwd<-bo$fwd
ret_dt<-as.data.table(fwd$returns_dt)[,.(date=as.Date(Date),tic=Ticker,Ret=Ret_1m)]
bench_dt<-as.data.table(fwd$bench_dt)[,.(date=as.Date(Date),BM=BM_Ret)]
liq_dt<-as.data.table(fwd$liq_dt)[,.(date=as.Date(Date),tic=Ticker,adv)]
FIC<-readRDS(file.path(OUT,"_factor_ic.rds")); setorder(FIC,factor_id,Date)
FIC[,fam:=sapply(factor_id,fam_of)]
FIC[,tw   :=shift(frollmean(ic,12L,na.rm=TRUE),1L),by=factor_id]                 # base 12m mean IC
FIC[,twmed:=shift(frollapply(ic,12L,median,na.rm=TRUE,fill=NA),1L),by=factor_id] # robust median
FIC[,ic6  :=shift(frollmean(ic,6L ,na.rm=TRUE),1L),by=factor_id]
FIC[,ic24 :=shift(frollmean(ic,24L,na.rm=TRUE),1L),by=factor_id]
FIC[,fam_mean:=mean(tw,na.rm=TRUE),by=.(Date,fam)]                               # family-mean IC (동일월)
## 팩터 rank-stability: nz 월대월 cross-sectional 자기상관
setorder(sc,factor_id,tic,date); sc[,nz_lag:=shift(nz),by=.(factor_id,tic)]
stab<-sc[is.finite(nz)&is.finite(nz_lag), .(ra=suppressWarnings(cor(nz,nz_lag,method="spearman"))), by=.(date,factor_id)]
setorder(stab,factor_id,date); stab[,stability:=shift(frollmean(ra,12L,na.rm=TRUE),1L),by=factor_id]
FW<-merge(FIC[,.(date=Date,factor_id,fam,tw,twmed,ic6,ic24,fam_mean)], stab[,.(date,factor_id,stability)], by=c("date","factor_id"),all.x=TRUE)
FW[,z_stab:=zc(stability),by=date]
## 스코어 빌더 (weight rule별)
mkS<-function(rule){
  x<-merge(sc[,.(date,tic,factor_id,nz)], FW, by=c("date","factor_id")); x<-x[is.finite(tw)]
  x[, wf := switch(rule,
     base       = pmax(tw,0),
     B1_famshr  = pmax(0.6*tw+0.4*fifelse(is.finite(fam_mean),fam_mean,tw),0),
     B2_robmed  = pmax(fifelse(is.finite(twmed),twmed,tw),0),
     B4_stab    = pmax(tw,0)*pmax(1+0.4*fifelse(is.finite(z_stab),z_stab,0),0),
     B6_pers_shr= pmax(0.6*tw+0.4*fifelse(is.finite(fam_mean),fam_mean,tw),0)*as.numeric(ic6>0 & ic24>0),
     B7_shr_rob = pmax(0.6*fifelse(is.finite(twmed),twmed,tw)+0.4*fifelse(is.finite(fam_mean),fam_mean,tw),0),
     B8_stab_prs= pmax(tw,0)*pmax(1+0.4*fifelse(is.finite(z_stab),z_stab,0),0)*as.numeric(ic6>0 & ic24>0) )]
  x<-x[is.finite(wf)]
  s<-x[,.(score=if(sum(wf,na.rm=T)>0) sum(wf*nz,na.rm=T)/sum(wf,na.rm=T) else mean(nz)),by=.(date,tic)]
  s[,score:=zc(score),by=date]; s[,.(date,tic,score)] }
## eval (시즌드+틸트)
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
w("\n=== Phase B (vs base paired-NW-t) ===")
D<-list(); D$base<-evalS(mkS("base")); res<-data.table()
rules<-c("base","B1_famshr","B2_robmed","B4_stab","B6_pers_shr","B7_shr_rob","B8_stab_prs")
for(rl in rules){ d<-if(rl=="base") D$base else evalS(mkS(rl)); D[[rl]]<-d
  dv<-NA; if(rl!="base"){ mg<-merge(D$base[,.(date,ab=act)],d[,.(date,an=act)],by="date"); mg[,dd:=an-ab]; ft<-lm(dd~1,mg); dv<-as.numeric(coeftest(ft,vcov=NeweyWest(ft,lag=3,prewhite=F))[1,3]) }
  res<-rbind(res,data.table(rule=rl,SR=round(sr(d$net),2),MDD=round(100*mddf(d$net),1),pt_full=round(ptv(d),2),pt_18p=round(ptv(d,"2018-01-01"),2),oos=round(oos_ret(d),2),dvst=round(dv,2)))
  w(sprintf("  [%-11s] SR=%.2f MDD=%.1f | pt_full=%+.2f pt_18p=%+.2f oos=%.2f%s", rl,sr(d$net),100*mddf(d$net),ptv(d),ptv(d,"2018-01-01"),oos_ret(d), ifelse(is.na(dv),"",sprintf(" | Δt=%+.2f",dv)))) }
fwrite(res,file.path(OUT,"advance2_results.csv")); saveRDS(D,file.path(OUT,"_advance2_series.rds"))
cat("ADV2|", paste(sprintf("%s:pt%.2f/18p%.2f/SR%.2f%s",res$rule,res$pt_full,res$pt_18p,res$SR,ifelse(is.na(res$dvst),"",sprintf("/dt%.1f",res$dvst))),collapse=" "),"\n")
close(con); cat("FOF_ADVANCE2_DONE\n")
