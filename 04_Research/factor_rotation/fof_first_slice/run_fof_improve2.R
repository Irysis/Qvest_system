## run_fof_improve2.R — 승자 결합 + top-K robustness + paired-NW-t 유의성 (과적합 가드)
## 승자(단일격리): topK100(강도·oos↑) · liq1e8(MDD↓) · shrink(MDD↓). 결합 시너지 + K민감도 + base 대비 유의성.
suppressPackageStartupMessages({library(data.table); library(arrow); library(sandwich); library(lmtest)})
setDTthreads(1); try(arrow::set_io_thread_count(1),silent=TRUE)
QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
OUT<-"04_Research/factor_rotation/fof_first_slice"; con<-file(file.path(OUT,"_fof_improve2.txt"),"w",encoding="UTF-8"); w<-function(...) writeLines(paste0(...),con)
`%||%`<-function(a,b) if(is.null(a)) b else a
zc<-function(x){ s<-sd(x,na.rm=T); if(is.na(s)||s<1e-9) x-mean(x,na.rm=T) else (x-mean(x,na.rm=T))/s }
w("================ 승자 결합 + K robustness + 유의성 ================"); w(sprintf("실행 %s",as.character(Sys.time())))
sc<-as.data.table(read_parquet("outputs/ramp/pure_factor_scores.parquet", col_select=c("signal_date","security_id","factor_id","neutralized_z")))
setnames(sc,"neutralized_z","nz"); sc[,signal_date:=as.Date(signal_date)]; setnames(sc,c("signal_date","security_id"),c("date","tic"))
bo<-readRDS(".cache/_bo_fwdgic.rds"); fwd<-bo$fwd
ret_dt<-as.data.table(fwd$returns_dt)[,.(date=as.Date(Date),tic=Ticker,Ret=Ret_1m)]
bench_dt<-as.data.table(fwd$bench_dt)[,.(date=as.Date(Date),BM=BM_Ret)]
liq_dt<-as.data.table(fwd$liq_dt)[,.(date=as.Date(Date),tic=Ticker,adv)]
FIC0<-readRDS(file.path(OUT,"_factor_ic.rds")); setorder(FIC0,factor_id,Date)
fweight<-function(spec){ lb<-spec$lb %||% 12; F<-copy(FIC0); setorder(F,factor_id,Date)
  if(isTRUE(spec$ewma)){ eww<-0.5^((lb:1)/6); F[,tw:=shift(frollapply(ic,lb,function(z) sum(z*eww[1:length(z)],na.rm=T)/sum(eww[1:length(z)]),fill=NA),1L),by=factor_id] }
  else { F[,tw:=shift(frollmean(ic,lb,na.rm=TRUE),1L),by=factor_id] }
  F[,tw:=pmax(tw,0)]
  if(isTRUE(spec$shrink)){ F[,gm:=mean(tw,na.rm=T),by=Date]; F[,tw:=pmax(0.5*tw+0.5*gm,0)] }
  out<-F[,.(date=Date,factor_id,tw)]
  if(!is.null(spec$topK)){ out[,rk:=frank(-tw,ties.method="first"),by=date]; out[rk>spec$topK,tw:=0]; out[,rk:=NULL] }
  out[is.finite(tw)] }
bscore<-function(spec){ tw<-fweight(spec); x<-merge(sc,tw,by=c("date","factor_id"))[is.finite(tw)]
  s<-x[,.(score=if(sum(tw)>0) sum(tw*nz)/sum(tw) else mean(nz)),by=.(date,tic)]; s[,score:=zc(score),by=date]; s[,.(date,tic,score)] }
sr<-function(r){r<-r[is.finite(r)];if(length(r)<6)return(NA);mean(r)/sd(r)*sqrt(12)}
cg<-function(r){r<-r[is.finite(r)];prod(1+r)^(12/length(r))-1}; mddf<-function(r){r<-r[is.finite(r)];nav<-cumprod(1+r);max(1-nav/cummax(nav))}
ptv<-function(d,from=NULL){a<-d;if(!is.null(from))a<-a[date>=as.Date(from)];a<-a[is.finite(act)];if(nrow(a)<12)return(NA);f<-lm(act~1,a);as.numeric(coeftest(f,vcov=NeweyWest(f,lag=3,prewhite=F))[1,3])}
oos_ret<-function(d){d<-d[is.finite(act)];n<-nrow(d);rs<-c();for(q in c(0.55,0.65,0.75)){k<-floor(n*q);si<-sr(d$act[1:k]);so<-sr(d$act[(k+1):n]);rs<-c(rs,if(is.finite(si)&&si>0) so/si else NA)};median(rs,na.rm=TRUE)}
evalS<-function(score_dt, lambda=2, liqmin=2e8, topN=25, seasW=48){
  S<-merge(score_dt, liq_dt, by=c("date","tic"))[adv>=liqmin]; months<-sort(unique(S$date))
  hc<-function(t,tics){ trd<-tail(months[months<t],seasW); ret_dt[tic %in% tics & date %in% trd & is.finite(Ret), .N, by=tic] }
  ser<-data.table(); prevw<-numeric(0); st<-which(months>=months[seasW+1L])[1]
  for(ti in st:length(months)){ t<-months[ti]; sel<-S[date==t][order(-score)][1:min(topN,.N)][is.finite(score)]
    sel<-sel[tic %in% hc(t,sel$tic)[N>=as.integer(0.75*seasW),tic]]; if(nrow(sel)<8) next
    fr<-ret_dt[date==t & tic %in% sel$tic]; fwdv<-setNames(fr$Ret,fr$tic); cn<-intersect(sel$tic,names(fwdv)); if(length(cn)<8) next
    av<-setNames(sel[match(cn,tic),score],cn); wv<-exp(lambda*av); wv<-wv/sum(wv)
    allt<-union(names(prevw),cn); pv<-setNames(rep(0,length(allt)),allt); cv<-pv; pv[names(prevw)]<-prevw; cv[cn]<-wv; to<-sum(abs(cv-pv)); prevw<-wv
    ser<-rbind(ser, data.table(date=t, net=sum(wv*fwdv[cn])-0.0015*to)) }
  merge(ser,bench_dt,by="date")[,act:=net-BM][order(date)] }
metr<-function(d) list(SR=sr(d$net),MDD=100*mddf(d$net),calmar=cg(d$net)/mddf(d$net),pt_full=ptv(d),pt_18p=ptv(d,"2018-01-01"),oos=oos_ret(d))
pr<-function(lab,d){ m<-metr(d); w(sprintf("  [%-22s] SR=%.2f MDD=%.1f%% calmar=%.2f | pt_full=%+.2f pt_18p=%+.2f oos=%.2f",lab,m$SR,m$MDD,m$calmar,m$pt_full,m$pt_18p,m$oos)); m }

w("\n=== (1) top-K robustness (otherwise base; K=팩터수) ===")
base_d<-evalS(bscore(list())); pr("BASE(K=316)", base_d)
for(K in c(50,75,100,125,150,200)) pr(sprintf("topK%d",K), evalS(bscore(list(topK=K))))
w("\n=== (2) 승자 결합 ===")
cmb<-list(
  "topK100"               = list(topK=100),
  "topK100+liq1e8"        = list(topK=100, liq=1e8),
  "topK100+shrink"        = list(topK=100, shrink=TRUE),
  "topK100+shrink+liq1e8" = list(topK=100, shrink=TRUE, liq=1e8),
  "topK100+ewma+liq1e8"   = list(topK=100, ewma=TRUE, liq=1e8))
combo_d<-list()
for(nm in names(cmb)){ s<-cmb[[nm]]; lq<-s$liq %||% 2e8; sp<-s[setdiff(names(s),"liq")]; d<-evalS(bscore(sp), liqmin=lq); combo_d[[nm]]<-d; pr(nm,d) }
w("\n=== (3) paired-NW-t: (best combo − BASE) 월별 active 차 유의성 ===")
best<-"topK100+shrink+liq1e8"; bd<-combo_d[[best]]
mg<-merge(base_d[,.(date,act_base=act)], bd[,.(date,act_new=act)], by="date"); mg[,dd:=act_new-act_base]
ft<-lm(dd~1,mg); tt<-as.numeric(coeftest(ft,vcov=NeweyWest(ft,lag=3,prewhite=F))[1,3])
w(sprintf("  %s vs BASE: 월평균 Δactive=%+.3f%% | paired-NW-t=%+.2f (t>2=유의개선)", best, 100*mean(mg$dd), tt))
mg18<-mg[date>=as.Date("2018-01-01")]; ft8<-lm(dd~1,mg18); tt8<-as.numeric(coeftest(ft8,vcov=NeweyWest(ft8,lag=3,prewhite=F))[1,3])
w(sprintf("  2018+ 한정: Δactive=%+.3f%% paired-NW-t=%+.2f", 100*mean(mg18$dd), tt8))
mbest<-metr(bd); cat(sprintf("IMP2| best=%s SR=%.2f MDD=%.1f calmar=%.2f pt_full=%.2f pt_18p=%.2f oos=%.2f | pairedT=%.2f pairedT18=%.2f\n",
  best, mbest$SR,mbest$MDD,mbest$calmar,mbest$pt_full,mbest$pt_18p,mbest$oos, tt, tt8))
saveRDS(list(base=base_d, combos=combo_d), file.path(OUT,"_improve2_series.rds"))
close(con); cat("FOF_IMPROVE2_DONE\n")
