## run_fof_overlay.R — 시즌드+틸트 북에 regime de-risk 오버레이 → 졸업게이트 도달?
## 오버레이: lag-1 PIT regime(BM trailing 신호)에서 bad면 invested=β로 디리스크(나머지 현금). 전환비용 15bps.
## regime 3종(TREND6/TREND12/DDVOL) × β∈{0,0.3,0.5}. 측정: SR/CAGR/MDD/calmar/active port_t/oos_retention.
suppressPackageStartupMessages({library(data.table); library(arrow); library(sandwich); library(lmtest)})
setDTthreads(1); try(arrow::set_io_thread_count(1),silent=TRUE)
QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
OUT<-"04_Research/factor_rotation/fof_first_slice"; con<-file(file.path(OUT,"_fof_overlay.txt"),"w",encoding="UTF-8"); w<-function(...) writeLines(paste0(...),con)
zc<-function(x){ s<-sd(x,na.rm=T); if(is.na(s)||s<1e-9) x-mean(x,na.rm=T) else (x-mean(x,na.rm=T))/s }
w("================ 시즌드+틸트 + 오버레이 (졸업 시도) ================"); w(sprintf("실행 %s",as.character(Sys.time())))
sc<-as.data.table(read_parquet("outputs/ramp/pure_factor_scores.parquet", col_select=c("signal_date","security_id","factor_id","neutralized_z")))
setnames(sc,"neutralized_z","nz"); sc[,signal_date:=as.Date(signal_date)]
bo<-readRDS(".cache/_bo_fwdgic.rds"); fwd<-bo$fwd
ret_dt<-as.data.table(fwd$returns_dt)[,.(date=as.Date(Date),tic=Ticker,Ret=Ret_1m)]
bench_dt<-as.data.table(fwd$bench_dt)[,.(date=as.Date(Date),BM=BM_Ret)]; setorder(bench_dt,date)
liq_dt<-as.data.table(fwd$liq_dt)[,.(date=as.Date(Date),tic=Ticker,adv)]
FIC<-readRDS(file.path(OUT,"_factor_ic.rds")); setorder(FIC,factor_id,Date)
FIC[,tt:=shift(frollmean(ic,12L,na.rm=TRUE),1L),by=factor_id]; tic<-FIC[,.(signal_date=Date,factor_id,tic=tt)]
x<-merge(sc,tic,by=c("signal_date","factor_id")); x<-x[is.finite(tic)]; x[,wf:=pmax(tic,0)]
S<-x[,.(score=if(sum(wf)>0) sum(wf*nz)/sum(wf) else mean(nz)),by=.(signal_date,security_id)]; S[,score:=zc(score),by=signal_date]
setnames(S,c("signal_date","security_id"),c("date","tic")); S<-merge(S, liq_dt, by=c("date","tic")); S<-S[adv>=2e8]
months<-sort(unique(S$date)); W<-48L
hist_cnt<-function(t,tics){ trd<-tail(months[months<t],W); ret_dt[tic %in% tics & date %in% trd & is.finite(Ret), .N, by=tic] }
## ── base 시즌드+틸트 net 시계열 (λ2) ──
ser<-data.table(); prevw<-numeric(0); st<-which(months>=months[W+1L])[1]
for(ti in st:length(months)){ t<-months[ti]
  sel<-S[date==t][order(-score)][1:min(25,.N)]; sel<-sel[is.finite(score)]
  sel<-sel[tic %in% hist_cnt(t,sel$tic)[N>=as.integer(0.75*W),tic]]; if(nrow(sel)<8) next
  fr<-ret_dt[date==t & tic %in% sel$tic]; fwdv<-setNames(fr$Ret,fr$tic); cn<-intersect(sel$tic,names(fwdv)); if(length(cn)<8) next
  av<-setNames(sel[match(cn,tic),score],cn); wv<-exp(2*av); wv<-wv/sum(wv)
  allt<-union(names(prevw),cn); pv<-setNames(rep(0,length(allt)),allt); cv<-pv; pv[names(prevw)]<-prevw; cv[cn]<-wv; to<-sum(abs(cv-pv)); prevw<-wv
  ser<-rbind(ser, data.table(date=t, net=sum(wv*fwdv[cn])-0.0015*to)) }
ser<-merge(ser, bench_dt, by="date"); setorder(ser,date)
## ── regime 신호 (lag-1 PIT, BM trailing) ──
bm<-bench_dt; bm[, nav:=cumprod(1+BM)]; bm[, dd:=nav/cummax(nav)-1]
bm[, tr6:=shift(frollmean(BM,6L),1L)]; bm[, tr12:=shift(frollapply(BM,12L,function(z) prod(1+z)-1),1L)]
bm[, vol6:=shift(frollapply(BM,6L,sd),1L)]; bm[, dd_l:=shift(dd,1L)]; bm[, volmed:=shift(frollapply(vol6,60L,function(z) median(z,na.rm=T)),1L)]
reg<-bm[,.(date, tr6, tr12, dd_l, vol6, volmed)]
ser<-merge(ser, reg, by="date"); setorder(ser,date)
ser[, bad_TREND6 := as.integer(tr6<0)]
ser[, bad_TREND12:= as.integer(tr12<0)]
ser[, bad_DDVOL  := as.integer(dd_l < -0.08 & vol6 > volmed)]
## ── 측정 ──
sr<-function(r){r<-r[is.finite(r)];if(length(r)<6)return(NA);mean(r)/sd(r)*sqrt(12)}
cg<-function(r){r<-r[is.finite(r)];prod(1+r)^(12/length(r))-1}; mdd<-function(r){r<-r[is.finite(r)];nav<-cumprod(1+r);max(1-nav/cummax(nav))}
ptv<-function(d,from=NULL){a<-d;if(!is.null(from))a<-a[date>=as.Date(from)];a<-a[is.finite(act)];if(nrow(a)<12)return(NA);f<-lm(act~1,a);as.numeric(coeftest(f,vcov=NeweyWest(f,lag=3,prewhite=F))[1,3])}
oos_ret<-function(d){ d<-d[is.finite(act)]; n<-nrow(d); rs<-c(); for(q in c(0.55,0.65,0.75)){ k<-floor(n*q); is_<-d$act[1:k]; oo<-d$act[(k+1):n]
  s_is<-sr(is_); s_oo<-sr(oo); rs<-c(rs, if(is.finite(s_is)&&s_is>0) s_oo/s_is else NA) }; median(rs,na.rm=TRUE) }
evalbook<-function(invested, lab){ d<-copy(ser); d[, inv:=invested]; d[, dinv:=abs(inv-shift(inv,1L,fill=1))]
  d[, net_ov := inv*net - 0.0015*0.5*dinv]; d[, act:=net_ov-BM]
  cal<-cg(d$net_ov)/mdd(d$net_ov)
  w(sprintf("  [%-18s] SR=%.2f CAGR=%+.1f%% MDD=%.1f%% calmar=%.2f | active pt full=%+.2f 2018+=%+.2f | oos_ret=%.2f",
    lab, sr(d$net_ov),100*cg(d$net_ov),100*mdd(d$net_ov), cal, ptv(d), ptv(d,"2018-01-01"), oos_ret(d)))
  data.table(book=lab, SR=sr(d$net_ov), CAGR=cg(d$net_ov), MDD=mdd(d$net_ov), calmar=cal, pt_full=ptv(d), pt_18p=ptv(d,"2018-01-01"), oos=oos_ret(d)) }
w("\n=== 오버레이 없음 (base 시즌드+틸트) ===")
tab<-evalbook(rep(1,nrow(ser)), "NO_OVERLAY")
w("\n=== regime × β 오버레이 (졸업: SR≥2.5·MDD≤25%·calmar≥0.64·pt≥2.95·oos≥0.7) ===")
for(rg in c("bad_TREND6","bad_TREND12","bad_DDVOL")) for(beta in c(0,0.3,0.5)){
  inv<-ifelse(ser[[rg]]==1 & is.finite(ser[[rg]]), beta, 1); inv[!is.finite(inv)]<-1
  tab<-rbind(tab, evalbook(inv, sprintf("%s_b%.1f", sub("bad_","",rg), beta))) }
setorder(tab,-SR)
w(sprintf("\n  최고 SR: %s (%.2f). 졸업 통과(SR2.5·MDD25·cal.64·pt2.95·oos.7) 있나 확인.", tab$book[1], tab$SR[1]))
fwrite(tab,file.path(OUT,"overlay_results.csv"))
cat("OVERLAY|", paste(sprintf("%s:SR%.2f/MDD%.0f/cal%.2f/18p%.2f",tab$book,tab$SR,100*tab$MDD,tab$calmar,tab$pt_18p),collapse=" "),"\n")
close(con); cat("FOF_OVERLAY_DONE\n")
