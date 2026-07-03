## run_fof_improve.R — 기존 구조 내 성능개선 레버 단일격리 실측 (새 팩터 0)
## 베이스 = 시즌드48 + IC-가중(flat12) + 스코어틸트(λ2) + liq2e8 + top25.
## 레버: A(알파결합 icir/ewma/ens_lb/topK/signstab) · B(winsor/sizeneut) · C(nco/invvol/λ) · D(liq) · E(ensemble).
## 측정: 절대 SR/CAGR/MDD/calmar + active port_t(full/2018+) + oos_retention. 베이스 대비 paired-NW-t.
suppressPackageStartupMessages({library(data.table); library(arrow); library(sandwich); library(lmtest)})
setDTthreads(1); try(arrow::set_io_thread_count(1),silent=TRUE)
QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
source("02_Infrastructure/portfolio/weight_method_registry.R"); load_weight_infra()
OUT<-"04_Research/factor_rotation/fof_first_slice"; con<-file(file.path(OUT,"_fof_improve.txt"),"w",encoding="UTF-8"); w<-function(...) writeLines(paste0(...),con)
zc<-function(x){ s<-sd(x,na.rm=T); if(is.na(s)||s<1e-9) x-mean(x,na.rm=T) else (x-mean(x,na.rm=T))/s }
w("================ 기존 구조 내 성능개선 레버 실측 ================"); w(sprintf("실행 %s",as.character(Sys.time())))
sc<-as.data.table(read_parquet("outputs/ramp/pure_factor_scores.parquet", col_select=c("signal_date","security_id","factor_id","neutralized_z")))
setnames(sc,"neutralized_z","nz"); sc[,signal_date:=as.Date(signal_date)]; setnames(sc,c("signal_date","security_id"),c("date","tic"))
bo<-readRDS(".cache/_bo_fwdgic.rds"); fwd<-bo$fwd
ret_dt<-as.data.table(fwd$returns_dt)[,.(date=as.Date(Date),tic=Ticker,Ret=Ret_1m)]
bench_dt<-as.data.table(fwd$bench_dt)[,.(date=as.Date(Date),BM=BM_Ret)]
liq_dt<-as.data.table(fwd$liq_dt)[,.(date=as.Date(Date),tic=Ticker,adv)]
FIC0<-readRDS(file.path(OUT,"_factor_ic.rds")); setorder(FIC0,factor_id,Date)
months_all<-sort(unique(sc$date))
## 트레일링 vol (PIT): ret_dt 12m sd shifted
setorder(ret_dt, tic, date); ret_dt[, vol12:=shift(frollapply(Ret,12L,sd,fill=NA),1L), by=tic]
vol_dt<-ret_dt[,.(date,tic,vol12)]; ret_dt[,vol12:=NULL]
RDT<-ret_dt[,.(Date=date,Ticker=tic,Ret)]

## ── 팩터가중 tw (date,factor_id,tw) ──
fweight<-function(method, lb=12){
  F<-copy(FIC0); setorder(F,factor_id,Date)
  if(method %in% c("flat","topK50","topK100","signstab")){ F[,tw:=shift(frollmean(ic,lb,na.rm=TRUE),1L),by=factor_id]; F[,tw:=pmax(tw,0)] }
  else if(method=="icir"){ F[,m:=shift(frollmean(ic,lb,na.rm=TRUE),1L),by=factor_id]; F[,s:=shift(frollapply(ic,lb,sd,fill=NA),1L),by=factor_id]; F[,tw:=pmax(m/pmax(s,1e-6),0)] }
  else if(method=="ewma"){ eww<-0.5^((lb:1)/6); F[,tw:=shift(frollapply(ic,lb,function(z){zz<-z*eww[1:length(z)]; sum(zz,na.rm=T)/sum(eww[1:length(z)])},fill=NA),1L),by=factor_id]; F[,tw:=pmax(tw,0)] }
  else if(method=="shrink"){ F[,tw:=shift(frollmean(ic,lb,na.rm=TRUE),1L),by=factor_id]; F[,gm:=mean(tw,na.rm=T),by=Date]; F[,tw:=pmax(0.5*tw+0.5*gm,0)] }  # 횡단 평균으로 수축
  if(method=="signstab"){ F[,pos:=shift(frollmean(as.numeric(ic>0),lb,na.rm=TRUE),1L),by=factor_id]; F[pos<0.58, tw:=0] }
  out<-F[,.(date=Date,factor_id,tw)]
  if(method %in% c("topK50","topK100")){ K<-as.integer(sub("topK","",method)); out[,rk:=frank(-tw,ties.method="first"),by=date]; out[rk>K,tw:=0]; out[,rk:=NULL] }
  out[is.finite(tw)] }

## ── 스코어 빌드 (date,tic,score) ──
bscore<-function(method, proc="none", lb=12){
  if(method=="ens_lb"){ ss<-NULL; for(L in c(6,12,24)){ s1<-bscore("flat",proc,L); setnames(s1,"score",paste0("s",L)); ss<-if(is.null(ss)) s1 else merge(ss,s1,by=c("date","tic")) }
    ss[,score:=zc(rowMeans(.SD,na.rm=T)),by=date,.SDcols=c("s6","s12","s24")]; return(ss[,.(date,tic,score)]) }
  tw<-fweight(method,lb); x<-merge(sc,tw,by=c("date","factor_id")); x<-x[is.finite(tw)]
  s<-x[,.(score=if(sum(tw)>0) sum(tw*nz)/sum(tw) else mean(nz)),by=.(date,tic)]
  if(proc=="winsor"){ s[,score:=zc(score),by=date]; s[,score:=pmax(pmin(score,2),-2)] }
  else if(proc=="sizeneut"){ s<-merge(s, liq_dt, by=c("date","tic")); s[,la:=log(pmax(adv,1))]; s[,score:={r<-tryCatch(resid(lm(score~la)),error=function(e) score-mean(score)); r},by=date]; s[,c("adv","la"):=NULL] }
  s[,score:=zc(score),by=date]; s[,.(date,tic,score)] }

## ── 평가 (score_dt, weighting, params) → metrics ──
sr<-function(r){r<-r[is.finite(r)];if(length(r)<6)return(NA);mean(r)/sd(r)*sqrt(12)}
cg<-function(r){r<-r[is.finite(r)];prod(1+r)^(12/length(r))-1}; mddf<-function(r){r<-r[is.finite(r)];nav<-cumprod(1+r);max(1-nav/cummax(nav))}
ptv<-function(d,from=NULL){a<-d;if(!is.null(from))a<-a[date>=as.Date(from)];a<-a[is.finite(act)];if(nrow(a)<12)return(NA);f<-lm(act~1,a);as.numeric(coeftest(f,vcov=NeweyWest(f,lag=3,prewhite=F))[1,3])}
oos_ret<-function(d){d<-d[is.finite(act)];n<-nrow(d);rs<-c();for(q in c(0.55,0.65,0.75)){k<-floor(n*q);si<-sr(d$act[1:k]);so<-sr(d$act[(k+1):n]);rs<-c(rs,if(is.finite(si)&&si>0) so/si else NA)};median(rs,na.rm=TRUE)}
evalS<-function(score_dt, weighting="tilt", lambda=2, liqmin=2e8, topN=25, seasW=48){
  S<-merge(score_dt, liq_dt, by=c("date","tic")); S<-S[adv>=liqmin]; months<-sort(unique(S$date))
  hc<-function(t,tics){ trd<-tail(months[months<t],seasW); ret_dt[tic %in% tics & date %in% trd & is.finite(Ret), .N, by=tic] }
  ser<-data.table(); prevw<-numeric(0); st<-which(months>=months[seasW+1L])[1]
  for(ti in st:length(months)){ t<-months[ti]; sel<-S[date==t][order(-score)][1:min(topN,.N)]; sel<-sel[is.finite(score)]
    sel<-sel[tic %in% hc(t,sel$tic)[N>=as.integer(0.75*seasW),tic]]; if(nrow(sel)<8) next
    fr<-ret_dt[date==t & tic %in% sel$tic]; fwdv<-setNames(fr$Ret,fr$tic); cn<-intersect(sel$tic,names(fwdv)); if(length(cn)<8) next
    av<-setNames(sel[match(cn,tic),score],cn)
    if(weighting=="ew") wv<-setNames(rep(1,length(cn)),cn)
    else if(weighting=="tilt") wv<-exp(lambda*av)
    else if(weighting=="invvol"){ vv<-vol_dt[date==t & tic %in% cn]; vmap<-setNames(vv$vol12,vv$tic); vsd<-vmap[cn]; vsd[!is.finite(vsd)]<-median(vsd,na.rm=T); wv<-exp(lambda*av)/pmax(vsd,1e-4) }
    else if(weighting=="nco"){ rt<-RDT[Date<t & Ticker %in% cn]; wv<-tryCatch(calc_nco_score_tilt_weights(cn, av, rt, n_days=seasW, max_w=0.20), error=function(e) exp(lambda*av)); if(is.null(names(wv))) names(wv)<-cn }
    wv<-wv[is.finite(wv)&wv>0]; if(length(wv)<5) next; wv<-wv/sum(wv)
    allt<-union(names(prevw),names(wv)); pv<-setNames(rep(0,length(allt)),allt); cv<-pv; pv[names(prevw)]<-prevw; cv[names(wv)]<-wv; to<-sum(abs(cv-pv)); prevw<-wv
    ser<-rbind(ser, data.table(date=t, net=sum(wv*fwdv[names(wv)])-0.0015*to)) }
  d<-merge(ser,bench_dt,by="date")[,act:=net-BM][]; setorder(d,date)
  list(d=d, SR=sr(d$net), CAGR=100*cg(d$net), MDD=100*mddf(d$net), calmar=cg(d$net)/mddf(d$net),
       pt_full=ptv(d), pt_18p=ptv(d,"2018-01-01"), oos=oos_ret(d)) }

## ── 변형 실행 ──
VAR<-list(
  BASE         =list(sm="flat", proc="none", wt="tilt", lam=2, liq=2e8, N=25),
  A1_icir      =list(sm="icir", proc="none", wt="tilt", lam=2, liq=2e8, N=25),
  A2_ewma6     =list(sm="ewma", proc="none", wt="tilt", lam=2, liq=2e8, N=25),
  A3_ens_lb    =list(sm="ens_lb",proc="none",wt="tilt", lam=2, liq=2e8, N=25),
  A4_topK100   =list(sm="topK100",proc="none",wt="tilt",lam=2, liq=2e8, N=25),
  A4_topK50    =list(sm="topK50",proc="none",wt="tilt",lam=2, liq=2e8, N=25),
  A5_shrink    =list(sm="shrink",proc="none",wt="tilt",lam=2, liq=2e8, N=25),
  A6_signstab  =list(sm="signstab",proc="none",wt="tilt",lam=2,liq=2e8, N=25),
  B1_winsor    =list(sm="flat", proc="winsor",wt="tilt",lam=2, liq=2e8, N=25),
  B2_sizeneut  =list(sm="flat", proc="sizeneut",wt="tilt",lam=2,liq=2e8,N=25),
  C1_nco       =list(sm="flat", proc="none", wt="nco", lam=2, liq=2e8, N=25),
  C2_invvol    =list(sm="flat", proc="none", wt="invvol",lam=2,liq=2e8, N=25),
  C3_lam3      =list(sm="flat", proc="none", wt="tilt", lam=3, liq=2e8, N=25),
  D1_liq1e8    =list(sm="flat", proc="none", wt="tilt", lam=2, liq=1e8, N=25)
)
w("\n=== 단일레버 격리 (베이스 대비) | SR/MDD/calmar/pt_full/pt_18p/oos ===")
res<-data.table()
for(nm in names(VAR)){ v<-VAR[[nm]]; m<-tryCatch(evalS(bscore(v$sm,v$proc), v$wt, v$lam, v$liq, v$N), error=function(e){message(nm,": ",conditionMessage(e)); NULL})
  if(is.null(m)){ w(sprintf("  [%-12s] ERROR", nm)); next }
  res<-rbind(res, data.table(var=nm, SR=round(m$SR,2), MDD=round(m$MDD,1), calmar=round(m$calmar,2), pt_full=round(m$pt_full,2), pt_18p=round(m$pt_18p,2), oos=round(m$oos,2)))
  w(sprintf("  [%-12s] SR=%.2f MDD=%.1f%% calmar=%.2f | pt_full=%+.2f pt_18p=%+.2f oos=%.2f", nm, m$SR,m$MDD,m$calmar,m$pt_full,m$pt_18p,m$oos)) }
fwrite(res, file.path(OUT,"improve_results.csv"))
base<-res[var=="BASE"]
w(sprintf("\n  베이스: SR=%.2f MDD=%.1f pt_full=%.2f oos=%.2f. SR개선 top: %s. MDD개선 top: %s.",
  base$SR, base$MDD, base$pt_full, base$oos,
  paste(res[order(-SR)][1:3,paste0(var,"(",SR,")")],collapse=", "),
  paste(res[order(MDD)][1:3,paste0(var,"(",MDD,")")],collapse=", ")))
cat("IMPROVE|", paste(sprintf("%s:SR%.2f/MDD%.0f/pt%.2f/oos%.2f",res$var,res$SR,res$MDD,res$pt_full,res$oos),collapse=" "),"\n")
close(con); cat("FOF_IMPROVE_DONE\n")
