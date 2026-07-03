## run_fof_season_verify.R — 시즌닝(상장이력) 필터가 post-2017 회복의 원인인지 깨끗이 격리 검증
## A(no filter): top-25 by score 전부. B(seasoned): top-25 중 48개월 중 ≥36 trailing 이력 있는 종목만.
## 같은 harness·같은 비용·같은 벤치. 2018+ active가 B≫A면 시즌닝이 레버. + look-ahead 토글(선택 +1m stale).
suppressPackageStartupMessages({library(data.table); library(arrow); library(sandwich); library(lmtest)})
setDTthreads(1); try(arrow::set_io_thread_count(1),silent=TRUE)
QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
OUT<-"04_Research/factor_rotation/fof_first_slice"; con<-file(file.path(OUT,"_fof_season.txt"),"w",encoding="UTF-8"); w<-function(...) writeLines(paste0(...),con)
zc<-function(x){ s<-sd(x,na.rm=T); if(is.na(s)||s<1e-9) x-mean(x,na.rm=T) else (x-mean(x,na.rm=T))/s }
w("================ 시즌닝(상장이력) 필터 A/B 검증 ================"); w(sprintf("실행 %s",as.character(Sys.time())))
sc<-as.data.table(read_parquet("outputs/ramp/pure_factor_scores.parquet", col_select=c("signal_date","security_id","factor_id","neutralized_z")))
setnames(sc,"neutralized_z","nz"); sc[,signal_date:=as.Date(signal_date)]
bo<-readRDS(".cache/_bo_fwdgic.rds"); fwd<-bo$fwd
ret_dt<-as.data.table(fwd$returns_dt)[,.(date=as.Date(Date),tic=Ticker,Ret=Ret_1m)]
bench_dt<-as.data.table(fwd$bench_dt)[,.(date=as.Date(Date),BM=BM_Ret)]
liq_dt<-as.data.table(fwd$liq_dt)[,.(date=as.Date(Date),tic=Ticker,adv)]
FIC<-readRDS(file.path(OUT,"_factor_ic.rds")); setorder(FIC,factor_id,Date)
FIC[,tt:=shift(frollmean(ic,12L,na.rm=TRUE),1L),by=factor_id]; tic<-FIC[,.(signal_date=Date,factor_id,tic=tt)]
x<-merge(sc,tic,by=c("signal_date","factor_id")); x<-x[is.finite(tic)]; x[,wf:=pmax(tic,0)]
S<-x[,.(score=if(sum(wf)>0) sum(wf*nz)/sum(wf) else mean(nz)),by=.(signal_date,security_id)]; S[,score:=zc(score),by=signal_date]
setnames(S,c("signal_date","security_id"),c("date","tic")); S<-merge(S, liq_dt, by=c("date","tic")); S<-S[adv>=2e8]
## trailing 이력 count: 각 (date,tic)에서 과거 48m 중 non-NA Ret 개수 (PIT)
months<-sort(unique(S$date)); W<-48L
hist_cnt<-function(t, tics){ trd<-tail(months[months<t], W); ret_dt[tic %in% tics & date %in% trd & is.finite(Ret), .N, by=tic] }

run_variant<-function(seasoned, stale=FALSE){
  ser<-data.table(); prevw<-numeric(0); nb<-c()
  st<-which(months>=months[W+1L])[1]
  for(ti in st:length(months)){ t<-months[ti]; tsel<- if(stale) months[ti-1] else t
    sel<-S[date==tsel][order(-score)][1:min(25,.N)]; sel<-sel[is.finite(score)]
    if(seasoned){ hc<-hist_cnt(t, sel$tic); keep<-hc[N>=as.integer(0.75*W),tic]; sel<-sel[tic %in% keep] }
    if(nrow(sel)<8) next
    fr<-ret_dt[date==t & tic %in% sel$tic]; fwdv<-setNames(fr$Ret, fr$tic); cn<-intersect(sel$tic, names(fwdv)); if(length(cn)<8) next
    av<-setNames(sel[match(cn,tic),score],cn)
    wv<-setNames(rep(1/length(cn),length(cn)),cn)            # EW
    allt<-union(names(prevw),cn); pv<-setNames(rep(0,length(allt)),allt); cv<-pv; pv[names(prevw)]<-prevw; cv[cn]<-wv
    to<-sum(abs(cv-pv)); prevw<-wv
    ser<-rbind(ser, data.table(date=t, net=sum(wv*fwdv[cn])-0.0015*to, nstk=length(cn)))
  }
  merge(ser, bench_dt, by="date")[, act:=net-BM][]
}
ptv<-function(d,from=NULL,to=NULL){ a<-d; if(!is.null(from)) a<-a[date>=as.Date(from)]; if(!is.null(to)) a<-a[date<as.Date(to)]; a<-a[is.finite(act)]; if(nrow(a)<12) return(NA); f<-lm(act~1,a); as.numeric(coeftest(f,vcov=NeweyWest(f,lag=3,prewhite=F))[1,3]) }
sr<-function(r){r<-r[is.finite(r)];mean(r)/sd(r)*sqrt(12)}
rep1<-function(lab,d) w(sprintf("  [%-18s] absSR=%.2f | active pt: full=%+.2f pre2018=%+.2f 2018+=%+.2f 2020+=%+.2f 2024+=%+.2f | avg n=%.1f",
  lab, sr(d$net), ptv(d), ptv(d,to="2018-01-01"), ptv(d,"2018-01-01"), ptv(d,"2020-01-01"), ptv(d,"2024-01-01"), mean(d$nstk)))
w("\n=== EW top-25, 시즌닝 A/B (active port_t vs cap-weight 지수) ===")
A<-run_variant(FALSE); rep1("A_no_filter", A)
B<-run_variant(TRUE);  rep1("B_seasoned48m", B)
w("\n=== look-ahead 토글 (선택 +1m stale; 누설이면 staler가 크게 악화돼야 정상) ===")
Bs<-run_variant(TRUE, stale=TRUE); rep1("B_seasoned_STALE", Bs)
w(sprintf("\n  → B 2018+ (%+.2f) ≫ A 2018+ (%+.2f) 이면 시즌닝이 레버. STALE(%+.2f)이 B와 비슷하면 PIT OK(누설 아님).",
  ptv(B,"2018-01-01"), ptv(A,"2018-01-01"), ptv(Bs,"2018-01-01")))
fwrite(rbind(A[,v:="A"],B[,v:="B"],Bs[,v:="Bstale"]), file.path(OUT,"season_verify_monthly.csv"))
cat(sprintf("SEASON| A_18p=%.2f B_18p=%.2f Bstale_18p=%.2f | A_full=%.2f B_full=%.2f | A_n=%.1f B_n=%.1f\n",
  ptv(A,"2018-01-01"),ptv(B,"2018-01-01"),ptv(Bs,"2018-01-01"),ptv(A),ptv(B),mean(A$nstk),mean(B$nstk)))
close(con); cat("FOF_SEASON_DONE\n")
