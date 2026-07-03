## run_fof_improve3.R — 패널 발굴 미탐색 레버: ① turnover buffering(no-trade band) ② score-method 앙상블
## buffering: rank-buffer(보유종목은 rank≤buf까지 유지, 빈자리만 신규 top) + weight no-trade band. 회전율↓→net↑.
## ensemble: 최종 score = rank-avg{flat, topK150, shrink} (best-of-26 대신 사전등록 1config → DSR/과적합 해소).
## 측정: SR/MDD/calmar/pt_full/pt_18p/oos + avg turnover + paired-NW-t vs BASE.
suppressPackageStartupMessages({library(data.table); library(arrow); library(sandwich); library(lmtest)})
setDTthreads(1); try(arrow::set_io_thread_count(1),silent=TRUE)
QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
OUT<-"04_Research/factor_rotation/fof_first_slice"; con<-file(file.path(OUT,"_fof_improve3.txt"),"w",encoding="UTF-8"); w<-function(...) writeLines(paste0(...),con)
`%||%`<-function(a,b) if(is.null(a)) b else a
zc<-function(x){ s<-sd(x,na.rm=T); if(is.na(s)||s<1e-9) x-mean(x,na.rm=T) else (x-mean(x,na.rm=T))/s }
w("================ buffering + score 앙상블 ================"); w(sprintf("실행 %s",as.character(Sys.time())))
sc<-as.data.table(read_parquet("outputs/ramp/pure_factor_scores.parquet", col_select=c("signal_date","security_id","factor_id","neutralized_z")))
setnames(sc,"neutralized_z","nz"); sc[,signal_date:=as.Date(signal_date)]; setnames(sc,c("signal_date","security_id"),c("date","tic"))
bo<-readRDS(".cache/_bo_fwdgic.rds"); fwd<-bo$fwd
ret_dt<-as.data.table(fwd$returns_dt)[,.(date=as.Date(Date),tic=Ticker,Ret=Ret_1m)]
bench_dt<-as.data.table(fwd$bench_dt)[,.(date=as.Date(Date),BM=BM_Ret)]
liq_dt<-as.data.table(fwd$liq_dt)[,.(date=as.Date(Date),tic=Ticker,adv)]
FIC0<-readRDS(file.path(OUT,"_factor_ic.rds")); setorder(FIC0,factor_id,Date)
fweight<-function(spec){ F<-copy(FIC0); setorder(F,factor_id,Date); F[,tw:=shift(frollmean(ic,12L,na.rm=TRUE),1L),by=factor_id]; F[,tw:=pmax(tw,0)]
  if(isTRUE(spec$shrink)){ F[,gm:=mean(tw,na.rm=T),by=Date]; F[,tw:=pmax(0.5*tw+0.5*gm,0)] }
  out<-F[,.(date=Date,factor_id,tw)]; if(!is.null(spec$topK)){ out[,rk:=frank(-tw,ties.method="first"),by=date]; out[rk>spec$topK,tw:=0]; out[,rk:=NULL] }; out[is.finite(tw)] }
mkscore<-function(spec){ tw<-fweight(spec); x<-merge(sc,tw,by=c("date","factor_id"))[is.finite(tw)]
  s<-x[,.(score=if(sum(tw)>0) sum(tw*nz)/sum(tw) else mean(nz)),by=.(date,tic)]; s[,score:=zc(score),by=date]; s[,.(date,tic,score)] }
## score 앙상블 = rank-avg{flat, topK150, shrink}
ens_score<-function(){ a<-mkscore(list()); b<-mkscore(list(topK=150)); c<-mkscore(list(shrink=TRUE))
  setnames(a,"score","sa"); setnames(b,"score","sb"); setnames(c,"score","sc2")
  m<-merge(merge(a,b,by=c("date","tic")),c,by=c("date","tic"))
  m[,`:=`(ra=frank(sa),rb=frank(sb),rc=frank(sc2)),by=date]; m[,score:=zc((ra+rb+rc)/3),by=date]; m[,.(date,tic,score)] }
sr<-function(r){r<-r[is.finite(r)];if(length(r)<6)return(NA);mean(r)/sd(r)*sqrt(12)}
cg<-function(r){r<-r[is.finite(r)];prod(1+r)^(12/length(r))-1}; mddf<-function(r){r<-r[is.finite(r)];nav<-cumprod(1+r);max(1-nav/cummax(nav))}
ptv<-function(d,from=NULL){a<-d;if(!is.null(from))a<-a[date>=as.Date(from)];a<-a[is.finite(act)];if(nrow(a)<12)return(NA);f<-lm(act~1,a);as.numeric(coeftest(f,vcov=NeweyWest(f,lag=3,prewhite=F))[1,3])}
oos_ret<-function(d){d<-d[is.finite(act)];n<-nrow(d);rs<-c();for(q in c(0.55,0.65,0.75)){k<-floor(n*q);si<-sr(d$act[1:k]);so<-sr(d$act[(k+1):n]);rs<-c(rs,if(is.finite(si)&&si>0) so/si else NA)};median(rs,na.rm=TRUE)}
## buffering 평가: rank-buffer(보유는 rank≤buf 유지) + weight no-trade band
evalB<-function(score_dt, buf=NULL, wband=0, lambda=2, liqmin=2e8, topN=25, seasW=48){
  S<-merge(score_dt, liq_dt, by=c("date","tic"))[adv>=liqmin]; months<-sort(unique(S$date))
  hc<-function(t,tics){ trd<-tail(months[months<t],seasW); ret_dt[tic %in% tics & date %in% trd & is.finite(Ret), .N, by=tic] }
  ser<-data.table(); prevw<-numeric(0); held<-character(0); st<-which(months>=months[seasW+1L])[1]
  for(ti in st:length(months)){ t<-months[ti]; Sd<-S[date==t][is.finite(score)]; setorder(Sd,-score); Sd[,rk:=.I]
    elig<-Sd[tic %in% hc(t,Sd$tic)[N>=as.integer(0.75*seasW),tic]]; if(nrow(elig)<topN) next
    elig[,rk2:=.I]   # 적격내 순위
    if(is.null(buf)){ sel<-elig[rk2<=topN, tic] } else {
      keep<-elig[tic %in% held & rk2<=buf, tic]; nf<-topN-length(keep); fill<-elig[!(tic %in% keep)][rk2<=buf+50][1:max(nf,0), tic]; sel<-c(keep, fill[!is.na(fill)]); sel<-head(unique(sel),topN) }
    av<-setNames(elig[match(sel,tic),score], sel); fr<-ret_dt[date==t & tic %in% sel]; fwdv<-setNames(fr$Ret,fr$tic)
    sel<-intersect(sel,names(fwdv)); if(length(sel)<8) next; av<-av[sel]
    wv<-exp(lambda*av); wv<-wv/sum(wv)
    if(wband>0 && length(prevw)>0){ for(nm in names(wv)){ pw<-prevw[nm]; if(!is.na(pw) && abs(wv[nm]-pw)<wband) wv[nm]<-pw }; wv<-wv/sum(wv) }
    allt<-union(names(prevw),names(wv)); pv<-setNames(rep(0,length(allt)),allt); cv<-pv; pv[names(prevw)]<-prevw; cv[names(wv)]<-wv
    to<-sum(abs(cv-pv)); prevw<-wv; held<-names(wv)
    ser<-rbind(ser, data.table(date=t, net=sum(wv*fwdv[names(wv)])-0.0015*to, to=to)) }
  merge(ser,bench_dt,by="date")[,act:=net-BM][order(date)] }
metr<-function(d) list(SR=sr(d$net),MDD=100*mddf(d$net),calmar=cg(d$net)/mddf(d$net),pt_full=ptv(d),pt_18p=ptv(d,"2018-01-01"),oos=oos_ret(d),TO=100*mean(d$to,na.rm=T))
pr<-function(lab,d,base=NULL){ m<-metr(d); ln<-sprintf("  [%-20s] SR=%.2f MDD=%.1f calmar=%.2f | pt_full=%+.2f pt_18p=%+.2f oos=%.2f | TO=%d%%",lab,m$SR,m$MDD,m$calmar,m$pt_full,m$pt_18p,m$oos,round(m$TO))
  if(!is.null(base)){ mg<-merge(base[,.(date,ab=act)],d[,.(date,an=act)],by="date"); mg[,dd:=an-ab]; ft<-lm(dd~1,mg); tt<-as.numeric(coeftest(ft,vcov=NeweyWest(ft,lag=3,prewhite=F))[1,3]); ln<-paste0(ln,sprintf(" | Δvs base t=%+.2f",tt)) }
  w(ln); m }
flat<-mkscore(list())
w("\n=== ① turnover buffering (base = flat316 tilt, buffering 없음) ===")
B0<-evalB(flat); pr("BASE(no buffer)", B0)
for(bf in c(30,35,40)){ d<-evalB(flat, buf=bf); pr(sprintf("rank-buffer %d",bf), d, B0) }
for(wb in c(0.005,0.01)){ d<-evalB(flat, wband=wb); pr(sprintf("wband %.1f%%",100*wb), d, B0) }
d35w<-evalB(flat, buf=35, wband=0.005); pr("buf35+wband0.5%", d35w, B0)
w("\n=== ② score-method 앙상블 rank-avg{flat,topK150,shrink} ===")
ENS<-ens_score(); E0<-evalB(ENS); pr("ENSEMBLE", E0, B0)
Eb<-evalB(ENS, buf=35); pr("ENSEMBLE+buf35", Eb, B0)
cat(sprintf("IMP3| base:SR%.2f/TO%.0f/pt%.2f buf35:SR%.2f/TO%.0f ens:SR%.2f/pt%.2f/oos%.2f\n",
  metr(B0)$SR, metr(B0)$TO, metr(B0)$pt_full, metr(evalB(flat,buf=35))$SR, metr(evalB(flat,buf=35))$TO, metr(E0)$SR, metr(E0)$pt_full, metr(E0)$oos))
close(con); cat("FOF_IMPROVE3_DONE\n")
