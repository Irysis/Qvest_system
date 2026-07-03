## run_fof_qarp.R — 도훈 레시피: 싼 value × 높은 quality × 높은 price-momentum 팩터 비중↑ (QARP+mom at factor level)
## factchar 갭 3개 close: ① factor-QUALITY 차원 추가 ② 시즌드+틸트 base(3.46 파이프) ③ integrated(rank-avg) vs additive.
## 팩터 메타특성(PIT causal, 횡단 z across 316f): mom(12-1m 롱레그) · quality(팩터Sharpe+IC hit-rate) · cheap(밸류스프레드 되돌림).
suppressPackageStartupMessages({library(data.table); library(arrow); library(sandwich); library(lmtest)})
setDTthreads(1); try(arrow::set_io_thread_count(1),silent=TRUE)
QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
OUT<-"04_Research/factor_rotation/fof_first_slice"; con<-file(file.path(OUT,"_fof_qarp.txt"),"w",encoding="UTF-8"); w<-function(...) writeLines(paste0(...),con)
zc<-function(x){ s<-sd(x,na.rm=T); if(is.na(s)||s<1e-9) x-mean(x,na.rm=T) else (x-mean(x,na.rm=T))/s }
fam1<-function(fid){ p1<-toupper(substr(fid,1,1)); if(p1=="V")"Value" else if(p1 %in% c("L","S")||toupper(substr(fid,1,2))=="TR")"Size" else "Other" }
w("================ QARP+mom (싼value×quality×momentum) 팩터배분 ================"); w(sprintf("실행 %s",as.character(Sys.time())))
sc<-as.data.table(read_parquet("outputs/ramp/pure_factor_scores.parquet", col_select=c("signal_date","security_id","factor_id","neutralized_z")))
setnames(sc,"neutralized_z","nz"); sc[,signal_date:=as.Date(signal_date)]; setnames(sc,c("signal_date","security_id"),c("date","tic"))
bo<-readRDS(".cache/_bo_fwdgic.rds"); fwd<-bo$fwd
ret_dt<-as.data.table(fwd$returns_dt)[,.(date=as.Date(Date),tic=Ticker,Ret=Ret_1m)]
bench_dt<-as.data.table(fwd$bench_dt)[,.(date=as.Date(Date),BM=BM_Ret)]
liq_dt<-as.data.table(fwd$liq_dt)[,.(date=as.Date(Date),tic=Ticker,adv)]
FIC<-readRDS(file.path(OUT,"_factor_ic.rds")); setorder(FIC,factor_id,Date)

## ── 종목 value_z (Value 패밀리 평균) ──
sc[, vfam:=sapply(factor_id, fam1)]
stk_v <- sc[vfam=="Value", .(value_z=mean(nz,na.rm=T)), by=.(date,tic)]

## ── 팩터 long-leg(top-quintile) 수익 + cheap(롱레그 value_z) ──
m<-merge(sc[,.(date,tic,factor_id,nz)], ret_dt, by=c("date","tic"))
m[, rk:=frank(-nz,ties.method="first")/.N, by=.(date,factor_id)]
top<-m[rk<=0.2]
frr<-top[, .(fret=mean(Ret,na.rm=T)), by=.(date,factor_id)]
topv<-merge(top[,.(date,factor_id,tic)], stk_v, by=c("date","tic"))
chp<-topv[, .(cheap=mean(value_z,na.rm=T)), by=.(date,factor_id)]
fc<-merge(frr, chp, by=c("date","factor_id"), all.x=TRUE); setorder(fc,factor_id,date)

## ── 메타특성 (PIT causal) ──
fc[, lret:=log1p(fret)]
fc[, mom := shift(frollsum(lret,12L),2L), by=factor_id]                        # 12-1m price momentum
fc[, sh_m := shift(frollmean(fret,12L,na.rm=TRUE),1L), by=factor_id]           # 팩터 수익 mean
fc[, sh_s := shift(frollapply(fret,12L,sd,fill=NA),1L), by=factor_id]          # 팩터 수익 sd
fc[, qual_sharpe := sh_m/pmax(sh_s,1e-6) ]                                     # 팩터 Sharpe (quality: 신뢰성)
fc[, cheap_tr := shift(frollmean(cheap,36L,na.rm=TRUE),1L), by=factor_id]
fc[, cheap_sp := cheap - cheap_tr ]                                            # 싼가(평소보다) — 높을수록 cheap
IC<-copy(FIC); IC[, ichit := shift(frollmean(as.numeric(ic>0),12L,na.rm=TRUE),1L), by=factor_id]  # IC 적중률
fc<-merge(fc, IC[,.(date=Date,factor_id,ichit)], by=c("date","factor_id"), all.x=TRUE)
fc[, quality := qual_sharpe ]   # 1차 quality = 팩터 Sharpe
## 횡단 z per month
for(cc in c("mom","quality","cheap_sp","ichit")) fc[, (paste0("z_",cc)):=zc(get(cc)), by=date]
fc[, z_qual2 := zc(zc(quality)+zc(ichit)), by=date]   # quality = Sharpe + IC적중률 결합

## ── 팩터가중 → 종목 score (integrated rank-avg 옵션) ──
mk_stockscore<-function(wexpr, integrated=FALSE, comps=NULL){
  x<-merge(sc[,.(date,tic,factor_id,nz)], fc[,.(date,factor_id,z_mom,z_quality,z_qual2,z_cheap_sp,z_ichit)], by=c("date","factor_id"))
  if(integrated){ for(cc in comps){ x[, (paste0("r_",cc)):=frank(get(cc)), by=date] }
    x[, A := zc(rowMeans(as.matrix(.SD),na.rm=TRUE)), by=date, .SDcols=paste0("r_",comps)] }
  else { x[, A := eval(wexpr, x)] }
  x<-x[is.finite(A)]; x[, wf:=pmax(A,0)]
  s<-x[,.(score=if(sum(wf)>0) sum(wf*nz)/sum(wf) else mean(nz)),by=.(date,tic)]; s[,score:=zc(score),by=date]; s[,.(date,tic,score)] }

## ── 시즌드+틸트 eval (3.46 파이프) ──
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
rep1<-function(lab,s){ d<-evalS(s); m<-list(SR=sr(d$net),MDD=100*mddf(d$net),pt=ptv(d),p18=ptv(d,"2018-01-01"),oos=oos_ret(d))
  w(sprintf("  [%-16s] SR=%.2f MDD=%.1f | pt_full=%+.2f pt_18p=%+.2f oos=%.2f", lab,m$SR,m$MDD,m$pt,m$p18,m$oos)); c(m,list(d=d)) }

w("\n=== 팩터-메타 배분별 (시즌드+틸트, full/2018+ active port_t) ===")
R<-list()
R$mom      <- rep1("mom(ref)",       mk_stockscore(quote(z_mom)))
R$qual     <- rep1("quality",        mk_stockscore(quote(z_qual2)))
R$cheap    <- rep1("cheap(value)",   mk_stockscore(quote(z_cheap_sp)))
R$QARP     <- rep1("QARP(qual+cheap)",mk_stockscore(quote(z_qual2 + z_cheap_sp)))
R$qmom     <- rep1("qual+mom",       mk_stockscore(quote(z_qual2 + z_mom)))
R$QARPmom  <- rep1("★qual+cheap+mom", mk_stockscore(quote(z_qual2 + z_cheap_sp + z_mom)))
R$QARPmom_i<- rep1("★integrated rank",mk_stockscore(NULL, integrated=TRUE, comps=c("z_qual2","z_cheap_sp","z_mom")))
R$qc_mom_i <- rep1("integr'd q+mom",  mk_stockscore(NULL, integrated=TRUE, comps=c("z_qual2","z_mom")))
tab<-rbindlist(lapply(names(R),function(k) data.table(config=k, SR=R[[k]]$SR, MDD=R[[k]]$MDD, pt_full=R[[k]]$pt, pt_18p=R[[k]]$p18, oos=R[[k]]$oos)))
## vs mom(ref) paired-NW-t
base<-R$mom$d
for(k in setdiff(names(R),"mom")){ mg<-merge(base[,.(date,ab=act)],R[[k]]$d[,.(date,an=act)],by="date"); mg[,dd:=an-ab]; ft<-lm(dd~1,mg); tab[config==k, dVSmom:=as.numeric(coeftest(ft,vcov=NeweyWest(ft,lag=3,prewhite=F))[1,3])] }
setorder(tab,-pt_full); fwrite(tab,file.path(OUT,"qarp_results.csv"))
w("\n  → QARP+mom(★)이 mom(ref) 초과? dVSmom>2면 quality/value 통합이 실질 기여.")
cat("QARP|", paste(sprintf("%s:pt%.2f/18p%.2f/SR%.2f%s",tab$config,tab$pt_full,tab$pt_18p,tab$SR,ifelse(is.na(tab$dVSmom),"",sprintf("/dvm%.1f",tab$dVSmom))),collapse=" "),"\n")
close(con); cat("FOF_QARP_DONE\n")
