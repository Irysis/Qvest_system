## run_fof_factchar.R — 팩터의 팩터: 팩터-레벨 특성 모델 (도훈 본래 개념: 팩터 모멘텀·밸류·변동성·사이즈)
## 각 팩터를 자산처럼 → 그 팩터의 momentum/value/volatility/size 점수화 → 팩터-매력도 합성 → 팩터 배분 → 25종 long-only.
## 특성(전부 PIT causal, 횡단면 z across 316 factors):
##   mom = 팩터 top-quintile 수익의 trailing 12-1m
##   vol = 팩터 top-quintile 수익의 trailing 12m std  (저변동 선호 → −z)
##   value = 팩터 long-leg 저평가도(top-quintile 종목 value_z 평균)의 자기역사 대비 spread (contrarian: 싸진 팩터 overweight)
##   size = 팩터 long-leg 종목 size_z 평균 (대형/소형 틸트)
## 합성 매력도로 팩터 가중 → score = Σ w_f·nz_f → canonical_screen_bt top-25. full + 2018+ 측정.
suppressPackageStartupMessages({library(data.table); library(arrow); library(sandwich); library(lmtest)})
setDTthreads(1); try(arrow::set_io_thread_count(1),silent=TRUE)
QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
source("02_Infrastructure/contracts/canonical_screen_bt.R")
OUT<-"04_Research/factor_rotation/fof_first_slice"; con<-file(file.path(OUT,"_fof_factchar.txt"),"w",encoding="UTF-8"); w<-function(...) writeLines(paste0(...),con)
zc<-function(x){ s<-sd(x,na.rm=T); if(is.na(s)||s<1e-9) x-mean(x,na.rm=T) else (x-mean(x,na.rm=T))/s }
fam_of<-function(fid){ p<-toupper(substr(fid,1,2)); p1<-substr(p,1,1)
  if(p1=="V")"Value" else if(p1=="L"||p1=="S"&&p!="SE"||p=="TR")"Size" else "Other" }
w("================ 팩터-특성 모델 (momentum/value/volatility/size) ================"); w(sprintf("실행 %s",as.character(Sys.time())))

sc<-as.data.table(read_parquet("outputs/ramp/pure_factor_scores.parquet", col_select=c("signal_date","security_id","factor_id","neutralized_z")))
setnames(sc,"neutralized_z","nz"); sc[,signal_date:=as.Date(signal_date)]
bo<-readRDS(".cache/_bo_fwdgic.rds"); fwd<-bo$fwd
ret_dt<-as.data.table(fwd$returns_dt)[,.(Date=as.Date(Date),Ticker,Ret_1m)]; bench_dt<-as.data.table(fwd$bench_dt)[,.(Date=as.Date(Date),BM_Ret)]; liq_dt<-as.data.table(fwd$liq_dt)[,.(Date=as.Date(Date),Ticker,adv)]

## 종목 value_z / size_z (Value, Size 패밀리 평균)
sc[, vfam:=sapply(factor_id, fam_of)]
stockchar <- sc[vfam!="Other", .(v=mean(nz[vfam=="Value"],na.rm=T), s=mean(nz[vfam=="Size"],na.rm=T)), by=.(signal_date,security_id)]
# 일부 종목/월 Value 또는 Size 결측 가능 → 따로
stk_v <- sc[vfam=="Value", .(value_z=mean(nz,na.rm=T)), by=.(signal_date,security_id)]
stk_s <- sc[vfam=="Size",  .(size_z =mean(nz,na.rm=T)), by=.(signal_date,security_id)]

## 팩터 top-quintile (nz 상위 20%) → forward 수익·value_z·size_z 평균
m <- merge(sc[,.(signal_date,security_id,factor_id,nz)], ret_dt[,.(signal_date=Date,security_id=Ticker,Ret_1m)], by=c("signal_date","security_id"))
m[, rk := frank(-nz, ties.method="first")/.N, by=.(signal_date,factor_id)]
top <- m[rk<=0.2]
fr <- top[, .(fret=mean(Ret_1m,na.rm=T)), by=.(signal_date,factor_id)]   # 팩터 long-leg 수익
fr <- merge(fr, top[,.(signal_date,factor_id,security_id)], by=c("signal_date","factor_id"))
fr <- merge(fr, stk_v, by=c("signal_date","security_id"), all.x=TRUE)
fr <- merge(fr, stk_s, by=c("signal_date","security_id"), all.x=TRUE)
fc <- fr[, .(fret=fret[1], cheap=mean(value_z,na.rm=T), fsize=mean(size_z,na.rm=T)), by=.(signal_date,factor_id)]
setorder(fc, factor_id, signal_date)

## 특성 (causal trailing)
fc[, lret := log1p(fret)]
fc[, mom := shift(frollsum(lret,12L),2L), by=factor_id]                       # 12-1m (최근월 제외)
fc[, vol := shift(frollapply(fret,12L,sd),1L), by=factor_id]                  # trailing 12m std
fc[, cheap_tr := shift(frollmean(cheap,36L,na.rm=TRUE),1L), by=factor_id]     # 자기역사 평균 저평가도
fc[, value := cheap - cheap_tr ]                                              # spread: 지금 평소보다 싼가(contrarian)
fc[, size := fsize ]
## 횡단면 z across factors (월별)
for(cc in c("mom","vol","value","size")) fc[, (paste0("z_",cc)) := zc(get(cc)), by=signal_date]
w(sprintf("\n팩터 특성패널: %d (factor×month), 특성 가용월 mom=%d value=%d", nrow(fc), sum(is.finite(fc$z_mom)), sum(is.finite(fc$z_value))))

## 팩터 가중 → 종목 score
sc2 <- merge(sc[,.(signal_date,security_id,factor_id,nz)], fc[,.(signal_date,factor_id,z_mom,z_vol,z_value,z_size)], by=c("signal_date","factor_id"))
run_sc<-function(sdt,id) canonical_screen_bt(scores_dt=sdt[,.(Date=as.Date(signal_date),Ticker=security_id,score)],returns_dt=ret_dt,bench_dt=bench_dt,top_n=25L,cost_bps_oneway=15,liq_dt=liq_dt,liq_min=2e8,run_id=id,strategy_id=id)
ptsub<-function(cs,from=NULL){ pr<-as.data.table(cs$period_returns); pr[,date:=as.Date(date)]; if(!is.null(from)) pr<-pr[date>=as.Date(from)]
  if(nrow(pr)<12) return(NA_real_); v<-pr$ret_net-pr$benchmark_ret; f<-lm(v~1); as.numeric(coeftest(f,vcov=sandwich::NeweyWest(f,lag=3,prewhite=FALSE))[1,3]) }
build<-function(attr_expr){ x<-copy(sc2); x[, A := eval(attr_expr, x)]; x<-x[is.finite(A)]; x[, wf:=pmax(A,0)]
  s<-x[,.(score=if(sum(wf)>0) sum(wf*nz)/sum(wf) else mean(nz)),by=.(signal_date,security_id)]; s[,score:=zc(score),by=signal_date]; s }

CFG<-list(
  F_mom    = quote(z_mom),
  F_value  = quote(z_value),          # contrarian: 싸진 팩터 overweight
  F_lowvol = quote(-z_vol),
  F_size_s = quote(-z_size),          # 소형틸트 팩터 overweight
  F_size_l = quote(z_size),           # 대형틸트
  F_mvv    = quote(z_mom + z_value - z_vol),
  F_all    = quote(z_mom + z_value - z_vol - z_size),
  F_valmom = quote(z_value + z_mom)
)
w("\n=== 팩터-특성 합성별 (full / 2018+ port_t) ===")
tab<-data.table()
for(nm in names(CFG)){ s<-build(CFG[[nm]]); cs<-run_sc(s,nm)
  ff<-cs$portfolio_alpha_t_nw_lag3; p18<-ptsub(cs,"2018-01-01"); ppre<-ptsub(cs,NULL)
  pre<-{ pr<-as.data.table(cs$period_returns); pr[,date:=as.Date(date)]; pr<-pr[date<as.Date("2018-01-01")]; v<-pr$ret_net-pr$benchmark_ret; f<-lm(v~1); as.numeric(coeftest(f,vcov=sandwich::NeweyWest(f,lag=3,prewhite=FALSE))[1,3]) }
  tab<-rbind(tab,data.table(config=nm, full=ff, pre2018=pre, y2018p=p18, net_SR=cs$net_sr))
  w(sprintf("  [%-9s] full=%+.2f | pre2018=%+.2f | 2018+=%+.2f | net_SR=%+.3f", nm, ff, pre, p18, cs$net_sr)) }
setorder(tab,-y2018p)
w("\n  → 2018+ 양수 구성 있나? (특히 F_value contrarian이 감쇠팩터 reversion 잡나)")
fwrite(tab,file.path(OUT,"factchar_results.csv")); saveRDS(list(tab=tab,fc=fc),file.path(OUT,"_fof_factchar.rds"))
cat("FACTCHAR|", paste(sprintf("%s:full%.2f/18p%.2f",tab$config,tab$full,tab$y2018p),collapse=" "),"\n")
close(con); cat("FOF_FACTCHAR_DONE\n")
