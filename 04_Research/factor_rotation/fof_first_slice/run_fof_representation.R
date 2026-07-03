## run_fof_representation.R — 표현(representation) 레버: FWL-직교화(neutralized_z)가 알파를 캡했나?
## 같은 pure_factor_scores.parquet의 raw/winsorized/z/neutralized_z/rank로 각각 IC 재계산 → FoF(IC가중+시즌드+틸트) → 비교.
## 가설: neutralized_z가 상관-성분(공통 알파) 제거 → z/raw가 더 강할 수 있음. 우리 FoF 전체가 neutralized_z만 썼음.
suppressPackageStartupMessages({library(data.table); library(arrow); library(sandwich); library(lmtest)})
setDTthreads(1); try(arrow::set_io_thread_count(1),silent=TRUE)
QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
OUT<-"04_Research/factor_rotation/fof_first_slice"; con<-file(file.path(OUT,"_fof_repr.txt"),"w",encoding="UTF-8"); w<-function(...) writeLines(paste0(...),con)
zc<-function(x){ s<-sd(x,na.rm=T); if(is.na(s)||s<1e-9) x-mean(x,na.rm=T) else (x-mean(x,na.rm=T))/s }
w("================ 표현 레버: FWL-직교화 vs raw/z (FoF 전체가 놓친 축) ================"); w(sprintf("실행 %s",as.character(Sys.time())))
sc<-as.data.table(read_parquet("outputs/ramp/pure_factor_scores.parquet",
     col_select=c("signal_date","security_id","factor_id","raw","winsorized","z","neutralized_z","rank")))
sc[,signal_date:=as.Date(signal_date)]; setnames(sc,c("signal_date","security_id"),c("date","tic"))
bo<-readRDS(".cache/_bo_fwdgic.rds"); fwd<-bo$fwd
ret_dt<-as.data.table(fwd$returns_dt)[,.(date=as.Date(Date),tic=Ticker,Ret=Ret_1m)]
bench_dt<-as.data.table(fwd$bench_dt)[,.(date=as.Date(Date),BM=BM_Ret)]
liq_dt<-as.data.table(fwd$liq_dt)[,.(date=as.Date(Date),tic=Ticker,adv)]
months<-sort(unique(sc$date)); W<-48L
hist_cnt<-function(t,tics){ trd<-tail(months[months<t],W); ret_dt[tic %in% tics & date %in% trd & is.finite(Ret), .N, by=tic] }
sr<-function(r){r<-r[is.finite(r)];if(length(r)<6)return(NA);mean(r)/sd(r)*sqrt(12)}
mddf<-function(r){r<-r[is.finite(r)];nav<-cumprod(1+r);max(1-nav/cummax(nav))}
ptv<-function(d,from=NULL){a<-d;if(!is.null(from))a<-a[date>=as.Date(from)];a<-a[is.finite(act)];if(nrow(a)<12)return(NA);f<-lm(act~1,a);as.numeric(coeftest(f,vcov=NeweyWest(f,lag=3,prewhite=F))[1,3])}
oos_ret<-function(d){d<-d[is.finite(act)];n<-nrow(d);rs<-c();for(q in c(0.55,0.65,0.75)){k<-floor(n*q);si<-sr(d$act[1:k]);so<-sr(d$act[(k+1):n]);rs<-c(rs,if(is.finite(si)&&si>0) so/si else NA)};median(rs,na.rm=TRUE)}
evalS<-function(score_dt){ S<-merge(score_dt, liq_dt, by=c("date","tic"))[adv>=2e8]; ser<-data.table(); prevw<-numeric(0); st<-which(months>=months[W+1L])[1]
  for(ti in st:length(months)){ t<-months[ti]; sel<-S[date==t][order(-score)][1:min(25,.N)][is.finite(score)]
    sel<-sel[tic %in% hist_cnt(t,sel$tic)[N>=as.integer(0.75*W),tic]]; if(nrow(sel)<8) next
    fr<-ret_dt[date==t & tic %in% sel$tic]; fwdv<-setNames(fr$Ret,fr$tic); cn<-intersect(sel$tic,names(fwdv)); if(length(cn)<8) next
    av<-setNames(sel[match(cn,tic),score],cn); wv<-exp(2*av); wv<-wv/sum(wv)
    allt<-union(names(prevw),cn); pv<-setNames(rep(0,length(allt)),allt); cv<-pv; pv[names(prevw)]<-prevw; cv[cn]<-wv; to<-sum(abs(cv-pv)); prevw<-wv
    ser<-rbind(ser, data.table(date=t, net=sum(wv*fwdv[cn])-0.0015*to)) }
  merge(ser,bench_dt,by="date")[,act:=net-BM][order(date)] }

## 표현별: IC 재계산(spearman, 12m trailing +1shift PIT) → IC가중 score → eval
run_rep<-function(repcol){
  x<-sc[,.(date,tic,factor_id,val=get(repcol))][is.finite(val)]
  xr<-merge(x, ret_dt, by=c("date","tic"))
  ic<-xr[, .(ic=suppressWarnings(cor(val,Ret,method="spearman",use="complete.obs"))), by=.(date,factor_id)]
  setorder(ic,factor_id,date); ic[, tic2:=shift(frollmean(ic,12L,na.rm=TRUE),1L), by=factor_id]
  xw<-merge(x, ic[,.(date,factor_id,tw=tic2)], by=c("date","factor_id")); xw<-xw[is.finite(tw)]; xw[,wf:=pmax(tw,0)]
  s<-xw[,.(score=if(sum(wf)>0) sum(wf*val)/sum(wf) else mean(val)),by=.(date,tic)]; s[,score:=zc(score),by=date]
  d<-evalS(s[,.(date,tic,score)])
  list(SR=sr(d$net),MDD=100*mddf(d$net),pt=ptv(d),p18=ptv(d,"2018-01-01"),oos=oos_ret(d),d=d) }

w("\n=== 표현별 FoF (IC가중+시즌드+틸트) | full/2018+ port_t · SR · oos ===")
tab<-data.table()
for(rp in c("neutralized_z","z","winsorized","raw","rank")){
  m<-tryCatch(run_rep(rp),error=function(e){message(rp,": ",conditionMessage(e));NULL}); if(is.null(m)) next
  tab<-rbind(tab,data.table(repr=rp,SR=round(m$SR,2),MDD=round(m$MDD,1),pt_full=round(m$pt,2),pt_18p=round(m$p18,2),oos=round(m$oos,2)))
  w(sprintf("  [%-14s] SR=%.2f MDD=%.1f | pt_full=%+.2f pt_18p=%+.2f oos=%.2f", rp,m$SR,m$MDD,m$pt,m$p18,m$oos))
  assign(paste0("d_",rp), m$d) }
## z vs neutralized_z paired-NW-t
if(exists("d_z")&&exists("d_neutralized_z")){ mg<-merge(d_neutralized_z[,.(date,ab=act)],d_z[,.(date,an=act)],by="date"); mg[,dd:=an-ab]; ft<-lm(dd~1,mg)
  w(sprintf("\n  z − neutralized_z: 월평균 Δ=%+.3f%% paired-NW-t=%+.2f (>2면 raw표현이 유의 우월)", 100*mean(mg$dd), as.numeric(coeftest(ft,vcov=NeweyWest(ft,lag=3,prewhite=F))[1,3]))) }
setorder(tab,-pt_full); fwrite(tab,file.path(OUT,"repr_results.csv"))
cat("REPR|", paste(sprintf("%s:pt%.2f/18p%.2f/SR%.2f/oos%.2f",tab$repr,tab$pt_full,tab$pt_18p,tab$SR,tab$oos),collapse=" "),"\n")
close(con); cat("FOF_REPR_DONE\n")
