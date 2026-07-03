## run_fof_sensitivity.R — 시즌드+틸트 gate-pass 과적합 가드: 파라미터 sensitivity
## 변동: 시즌닝창 {36,48,60} · IC 룩백 {6,12,24} · 유동 {1e8,2e8,5e8} · top-N {20,25,30} · λ {1,2}.
## robust면 gate-pass 견고. 작은 변경에 port_t/oos 붕괴면 과적합 플래그.
suppressPackageStartupMessages({library(data.table); library(arrow); library(sandwich); library(lmtest)})
setDTthreads(1); try(arrow::set_io_thread_count(1),silent=TRUE)
QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
OUT<-"04_Research/factor_rotation/fof_first_slice"; con<-file(file.path(OUT,"_fof_sens.txt"),"w",encoding="UTF-8"); w<-function(...) writeLines(paste0(...),con)
zc<-function(x){ s<-sd(x,na.rm=T); if(is.na(s)||s<1e-9) x-mean(x,na.rm=T) else (x-mean(x,na.rm=T))/s }
w("================ 시즌드+틸트 파라미터 sensitivity (과적합 가드) ================"); w(sprintf("실행 %s",as.character(Sys.time())))
sc<-as.data.table(read_parquet("outputs/ramp/pure_factor_scores.parquet", col_select=c("signal_date","security_id","factor_id","neutralized_z")))
setnames(sc,"neutralized_z","nz"); sc[,signal_date:=as.Date(signal_date)]
bo<-readRDS(".cache/_bo_fwdgic.rds"); fwd<-bo$fwd
ret_dt<-as.data.table(fwd$returns_dt)[,.(date=as.Date(Date),tic=Ticker,Ret=Ret_1m)]
bench_dt<-as.data.table(fwd$bench_dt)[,.(date=as.Date(Date),BM=BM_Ret)]
liq_dt<-as.data.table(fwd$liq_dt)[,.(date=as.Date(Date),tic=Ticker,adv)]
FIC0<-readRDS(file.path(OUT,"_factor_ic.rds")); setorder(FIC0,factor_id,Date)
build_S<-function(ic_lb){ F<-copy(FIC0); F[,tt:=shift(frollmean(ic,ic_lb,na.rm=TRUE),1L),by=factor_id]
  tt<-F[,.(signal_date=Date,factor_id,tic=tt)]; x<-merge(sc,tt,by=c("signal_date","factor_id")); x<-x[is.finite(tic)]; x[,wf:=pmax(tic,0)]
  s<-x[,.(score=if(sum(wf)>0) sum(wf*nz)/sum(wf) else mean(nz)),by=.(signal_date,security_id)]; s[,score:=zc(score),by=signal_date]
  setnames(s,c("signal_date","security_id"),c("date","tic")); merge(s, liq_dt, by=c("date","tic")) }
sr<-function(r){r<-r[is.finite(r)];if(length(r)<6)return(NA);mean(r)/sd(r)*sqrt(12)}
mdd<-function(r){r<-r[is.finite(r)];nav<-cumprod(1+r);max(1-nav/cummax(nav))}
ptv<-function(d,from=NULL){a<-d;if(!is.null(from))a<-a[date>=as.Date(from)];a<-a[is.finite(act)];if(nrow(a)<12)return(NA);f<-lm(act~1,a);as.numeric(coeftest(f,vcov=NeweyWest(f,lag=3,prewhite=F))[1,3])}
oos_ret<-function(d){ d<-d[is.finite(act)]; n<-nrow(d); rs<-c(); for(q in c(0.55,0.65,0.75)){ k<-floor(n*q); s_is<-sr(d$act[1:k]); s_oo<-sr(d$act[(k+1):n]); rs<-c(rs, if(is.finite(s_is)&&s_is>0) s_oo/s_is else NA) }; median(rs,na.rm=TRUE) }
runcfg<-function(seas_W, ic_lb, liqmin, topN, lambda){
  S<-build_S(ic_lb)[adv>=liqmin]; months<-sort(unique(S$date)); W<-seas_W
  hc<-function(t,tics){ trd<-tail(months[months<t],W); ret_dt[tic %in% tics & date %in% trd & is.finite(Ret), .N, by=tic] }
  ser<-data.table(); prevw<-numeric(0); st<-which(months>=months[W+1L])[1]
  for(ti in st:length(months)){ t<-months[ti]; sel<-S[date==t][order(-score)][1:min(topN,.N)]; sel<-sel[is.finite(score)]
    sel<-sel[tic %in% hc(t,sel$tic)[N>=as.integer(0.75*W),tic]]; if(nrow(sel)<8) next
    fr<-ret_dt[date==t & tic %in% sel$tic]; fwdv<-setNames(fr$Ret,fr$tic); cn<-intersect(sel$tic,names(fwdv)); if(length(cn)<8) next
    av<-setNames(sel[match(cn,tic),score],cn); wv<-exp(lambda*av); wv<-wv/sum(wv)
    allt<-union(names(prevw),cn); pv<-setNames(rep(0,length(allt)),allt); cv<-pv; pv[names(prevw)]<-prevw; cv[cn]<-wv; to<-sum(abs(cv-pv)); prevw<-wv
    ser<-rbind(ser, data.table(date=t, net=sum(wv*fwdv[cn])-0.0015*to)) }
  d<-merge(ser,bench_dt,by="date")[,act:=net-BM][]; setorder(d,date)
  data.table(SR=sr(d$net), MDD=100*mdd(d$net), pt_full=ptv(d), pt_18p=ptv(d,"2018-01-01"), oos=oos_ret(d)) }
w("\n=== BASE (seas48·ic12·liq2e8·N25·λ2) + 1축씩 변경 (gate: pt≥2.95·oos≥0.7) ===")
grid<-data.table(seas=48,ic=12,liq=2e8,N=25,lam=2,tag="BASE")
for(s in c(36,60)) grid<-rbind(grid,data.table(seas=s,ic=12,liq=2e8,N=25,lam=2,tag=paste0("seas",s)))
for(i in c(6,24)) grid<-rbind(grid,data.table(seas=48,ic=i,liq=2e8,N=25,lam=2,tag=paste0("ic",i)))
for(l in c(1e8,5e8)) grid<-rbind(grid,data.table(seas=48,ic=12,liq=l,N=25,lam=2,tag=paste0("liq",l/1e8,"e8")))
for(nn in c(20,30)) grid<-rbind(grid,data.table(seas=48,ic=12,liq=2e8,N=nn,lam=2,tag=paste0("N",nn)))
res<-data.table()
for(i in 1:nrow(grid)){ g<-grid[i]; r<-tryCatch(runcfg(g$seas,g$ic,g$liq,g$N,g$lam),error=function(e) data.table(SR=NA,MDD=NA,pt_full=NA,pt_18p=NA,oos=NA))
  res<-rbind(res, cbind(tag=g$tag, r))
  w(sprintf("  [%-10s] SR=%.2f MDD=%.1f%% | pt_full=%+.2f pt_18p=%+.2f oos=%.2f %s",
    g$tag, r$SR, r$MDD, r$pt_full, r$pt_18p, r$oos, ifelse(is.finite(r$pt_full)&&r$pt_full>=2.95&&is.finite(r$oos)&&r$oos>=0.7,"PASS","")) ) }
np<-sum(res$pt_full>=2.95 & res$oos>=0.7, na.rm=TRUE)
w(sprintf("\n  → %d/%d 설정이 pt≥2.95∧oos≥0.7 통과. 과반 통과면 robust(과적합 아님), 소수면 BASE 특이.", np, nrow(res)))
fwrite(res,file.path(OUT,"sensitivity_results.csv"))
cat(sprintf("SENS| pass=%d/%d | range pt_full=[%.2f,%.2f] oos=[%.2f,%.2f]\n", np, nrow(res),
  min(res$pt_full,na.rm=T),max(res$pt_full,na.rm=T),min(res$oos,na.rm=T),max(res$oos,na.rm=T)))
close(con); cat("FOF_SENS_DONE\n")
