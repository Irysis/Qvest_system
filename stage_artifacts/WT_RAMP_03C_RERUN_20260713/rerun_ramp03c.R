## rerun_ramp03c.R — RAMP_03C_BOOKMOM_CAPW 단일 config 재현 (FQ-020 / 태스크 #65)
## canonical 경로만: weighted_screen_bt(cap-w) + essence_score(oos v2/calmar). proxy 손계산 금지.
## dual benchmark basis(RAMP-native cap-w proxy + 교정 IKS200) × 2 window(full + trailing-164).
suppressPackageStartupMessages({library(arrow); library(data.table); library(jsonlite)})
setDTthreads(1); try(arrow::set_cpu_count(1),silent=TRUE); try(arrow::set_io_thread_count(2),silent=TRUE)
suppressMessages({library(sandwich); library(lmtest)})
QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
WT<-file.path(QM,"stage_artifacts/WT_RAMP_03C_RERUN_20260713")
SCR<-"C:/Users/99922/AppData/Local/Temp/claude/C--Users-99922-OneDrive-Quant-Module-Moltbot/3d6b0eb6-6786-4a56-916d-9681f94897fe/scratchpad"
source("02_Infrastructure/config.R")
source("02_Infrastructure/factor_db/factor_db_connector.R")
source("02_Infrastructure/ramp/factor_validation.R")           # build_monthly_forward_returns
source("02_Infrastructure/contracts/weighted_screen_bt.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")
source("02_Infrastructure/contracts/essence_score.R")
source("02_Infrastructure/data/pin_cache.R")
zc<-function(x){m<-mean(x,na.rm=T);s<-sd(x,na.rm=T);if(is.na(s)||s<1e-9) x-m else (x-m)/s}
cap_norm<-function(w){w[!is.finite(w)|w<0]<-0;if(sum(w)<=0)return(rep(1/length(w),length(w)));w<-w/sum(w);for(it in 1:50){if(all(w<=0.2000001))break;w[w>0.20]<-0.20;rem<-1-sum(w);ix<-w<0.20;if(sum(ix)==0||rem<=0)break;w[ix]<-w[ix]+rem*w[ix]/sum(w[ix])};w[w>0.20]<-0.20;w/sum(w)}
ny<-function(d){m<-as.integer(format(d,"%m"));y<-as.integer(format(d,"%Y"));sprintf("%04d-%02d",ifelse(m==12,y+1,y),ifelse(m==12,1,m+1))}
nwt<-function(x){x<-as.numeric(x);x<-x[is.finite(x)];if(length(x)<10)return(NA);as.numeric(coeftest(lm(x~1),vcov=sandwich::NeweyWest(lm(x~1),lag=3,prewhite=FALSE))[1,3])}
IRf<-function(x){x<-x[is.finite(x)];if(length(x)<6)return(NA);mean(x)/sd(x)*sqrt(12)}
calf<-function(r){nav<-cumprod(1+r);cagr<-prod(1+r)^(12/length(r))-1;cagr/abs(min(nav/cummax(nav)-1))}

## ---- 0) vintage pin (measurement-graduation §7) ----
RAW<-".cache/RAWDATA.parquet"; BM<-".cache/benchmark.parquet"
EXIST<-"ramp03c_rerun_20260713_205545"   # 1차 실행 pin 재사용(421MB 재복사 회피)
PINTAG<-if(file.exists(file.path(".cache/pins",EXIST,"manifest.json"))) EXIST else format(Sys.time(),"ramp03c_rerun_%Y%m%d_%H%M%S")
if(PINTAG!=EXIST) pin_cache(c(RAW,BM), PINTAG)
RAWp<-read_pinned(RAW,PINTAG); BMp<-read_pinned(BM,PINTAG)
cat("PIN_TAG=",PINTAG,"\n")

## ---- 1) RAWDATA → 월말 universe/Size + forward returns (RAMP-native cap-w proxy bench) ----
need<-c("Date","Ticker","Close","K200","KQ150","Vol","Size","Ret")
rd<-as.data.table(read_parquet(RAWp, col_select=all_of(need))); rd[,Date:=as.Date(Date)]
rd<-rd[Date>=as.Date("2004-06-01")]                       # 2005 신호 + warmup 여유
rd[,ym:=format(Date,"%Y-%m")]
mend<-rd[,.(md=max(Date)),by=ym]; setorder(mend,md)
sig_dates<-mend$md[format(mend$md,"%Y-%m")>="2005-01"]     # 신호 월말 (2005-01~)
fwd<-build_monthly_forward_returns(rd, sig_dates)
fwd_ret<-fwd$returns_dt[,.(Date=as.Date(Date),Ticker,Ret_1m)]
bench_proxy<-fwd$bench_dt[,.(Date=as.Date(Date),BM_Ret)]   # cap-w K200uKQ150 proxy (원 RAMP 방법)
liq<-fwd$liq_dt[,.(Date=as.Date(Date),Ticker,adv)]
dts<-sort(unique(fwd_ret$Date)); ND<-length(dts)
cat(sprintf("fwd dts: %d (%s ~ %s)\n",ND,as.character(min(dts)),as.character(max(dts))))

## universe(K200uKQ150) + Size (월말) for each sig_date
umend<-merge(rd,mend,by.x=c("ym","Date"),by.y=c("ym","md"))
umend[,inu:=(!is.na(K200)&K200==TRUE)|(!is.na(KQ150)&KQ150==TRUE)]
UNI<-umend[inu==TRUE,.(Date,Ticker,Size)]

## ---- 2) 교정 IKS200 벤치 → 월간(sig_date 월말 매칭, 그 달 수익 합성 아님: 월말→월말 index return) ----
bmd<-as.data.table(read_parquet(BMp)); bmd[,Date:=as.Date(Date)]
# 각 sig_date d0(월말)→다음 sig_date d1(월말) index total return = BM_Close 비율
bm_me<-bmd[,.(Date,BM_Close)]; setkey(bm_me,Date)
asof_bm<-function(d){s<-bm_me[Date<=d];if(nrow(s)==0)return(NA_real_);s[.N,BM_Close]}
iks<-data.table(Date=dts, BM_Ret=NA_real_)
for(i in seq_len(ND)){d0<-dts[i]; d1<-if(i<ND) dts[i+1] else NA
  if(is.na(d1)){iks$BM_Ret[i]<-NA;next}
  c0<-asof_bm(d0); c1<-asof_bm(d1); iks$BM_Ret[i]<-if(is.finite(c0)&&is.finite(c1)&&c0>0) c1/c0-1 else NA}
bench_iks<-iks[is.finite(BM_Ret)]

## ---- 3) book_z (score_eff, 예측월 ny 정렬) ----
bkp<-"05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/02_holdings_universe/alpha_scores_str1715_268m.parquet"
bk<-as.data.table(read_parquet(bkp))[,.(ym=format(as.Date(Date),"%Y-%m"),Ticker,se=score_eff)][is.finite(se)]

## ---- 4) mom6_z (개별 zc 후 평균) — ZL 캐시(비싼 factor load) ----
mom6<-c("M05_Trended_Mom","M32_Composite_Mom_v2","M09_Composite_Mom","M13_VolAdj_Mom","M01_Mom_12_1","M08_Residual_Mom")
ZLpath<-file.path(SCR,"zl_mom6.rds")
if(file.exists(ZLpath)){ZL<-readRDS(ZLpath); cat("ZL cache loaded\n")} else {
  ZL<-list(); for(d in as.character(dts)){f<-tryCatch(as.data.table(load_month_factors(as.Date(d),factor_names=mom6)),error=function(e)NULL)
    if(is.null(f)||nrow(f)==0)next; w<-dcast(f,Ticker~Factor_Name,value.var="Z_Score_Aligned"); ZL[[d]]<-w}
  saveRDS(ZL,ZLpath); cat("ZL built + cached\n")}

## ---- 5) 결합 score 조립: 0.5*zc(book) + 0.5*mom6평균 (+ 대안: mom6 재-z) ----
SC<-list()
for(i in seq_len(ND)){d<-dts[i]; dk<-as.character(d)
  uni<-UNI[Date==d]; if(nrow(uni)<25)next
  b<-bk[ym==ny(d),.(Ticker,bz=zc(se))]
  fw<-ZL[[dk]]
  dm<-data.table(Ticker=uni$Ticker, Size=uni$Size)
  if(!is.null(fw)){
    mm<-copy(fw); for(mid in mom6){ if(mid%in%names(mm)) mm[[mid]]<-zc(mm[[mid]]) else mm[[mid]]<-NA_real_ }
    mm[,mom6:=rowMeans(as.matrix(.SD),na.rm=TRUE),.SDcols=mom6]
    mm[,mom6_rez:=zc(mom6)]
    dm<-merge(dm,mm[,.(Ticker,mom6,mom6_rez)],by="Ticker",all.x=TRUE)
  } else {dm[,mom6:=NA_real_]; dm[,mom6_rez:=NA_real_]}
  dm<-merge(dm,b,by="Ticker",all.x=TRUE)
  dm[!is.finite(mom6),mom6:=0]; dm[!is.finite(mom6_rez),mom6_rez:=0]
  dm<-dm[is.finite(bz)]                        # book score 필요(사실상 전 universe)
  dm<-merge(dm,liq[Date==d,.(Ticker,adv)],by="Ticker",all.x=TRUE); dm<-dm[is.na(adv)|adv>=2e8]
  if(nrow(dm)<25)next
  dm[,score:=0.5*bz+0.5*mom6]                  # PRIMARY: 개별 z 평균
  dm[,score_rez:=0.5*bz+0.5*mom6_rez]          # ALT: 평균 후 재-z
  dm[,Date:=d]; SC[[dk]]<-dm}
SCdt<-rbindlist(SC,fill=TRUE)
cat(sprintf("SCdt months: %d (%s ~ %s)\n",uniqueN(SCdt$Date),as.character(min(SCdt$Date)),as.character(max(SCdt$Date))))

## ---- 6) 측정기: top-25 select → 3 weighting (EW / score-tilt / cap-w) × 2 bench × 2 window ----
mk_weights<-function(scorecol,wtype){
  W<-list(); uds<-sort(unique(SCdt$Date))   # 인덱스 반복 — Date 클래스 보존(for-over-Date는 numeric으로 강등됨)
  for(di in seq_along(uds)){d<-uds[di]; sub<-SCdt[Date==d][is.finite(get(scorecol))]; if(nrow(sub)<5)next
    setorderv(sub,scorecol,order=-1L)
    hd<-head(sub,25)
    w<-switch(wtype,
      ew   = rep(1/nrow(hd),nrow(hd)),
      score= {s<-hd[[scorecol]]; s<-pmax(s-min(s)+0.1,0.01); cap_norm(s)},
      capw = cap_norm(hd$Size))
    W[[as.character(d)]]<-data.table(Date=d,Ticker=hd$Ticker,w=w)}
  rbindlist(W)}

build_bt_shell<-function(r){
  # r = weighted_screen_bt output. essence_score용 최소 bt_result shell.
  cal<-if(is.finite(r$abs_mdd)&&r$abs_mdd<0) r$abs_cagr/abs(r$abs_mdd) else NA_real_
  metrics<-data.table(metric_name=c("Sharpe","CAGR","MDD","Calmar"),
                      metric_value=c(r$abs_net_sr,r$abs_cagr,abs(r$abs_mdd),cal))
  pr<-as.data.table(r$period_returns)
  list(metrics=metrics, benchmark_compare=as.data.table(r$benchmark_compare),
       period_returns=pr[,.(date,ret_net)],
       benchmark_returns=pr[,.(date,benchmark_ret)])
}
measure<-function(scorecol,wtype,benchdt,benchlab,win="full"){
  W<-mk_weights(scorecol,wtype)
  if(win=="t164"){allm<-sort(unique(W$Date)); keep<-tail(allm,164); W<-W[Date%in%keep]}
  r<-tryCatch(weighted_screen_bt(W,fwd_ret,benchdt,cost_bps_oneway=15,run_id=paste0(wtype,"_",benchlab,"_",win),strategy_id="RAMP_03C"),error=function(e){cat("ERR",conditionMessage(e),"\n");NULL})
  if(is.null(r$period_returns))return(NULL)
  shell<-build_bt_shell(r)
  es<-tryCatch(essence_score(shell,selection_type="chain",oos_stat_version="v2"),error=function(e){cat("ESS ERR",conditionMessage(e),"\n");NULL})
  pr<-as.data.table(r$period_returns); act<-pr$ret_net-pr$benchmark_ret
  data.table(weighting=wtype, bench=benchlab, window=win, n=nrow(pr),
    pt_capwt=r$portfolio_alpha_t_nw_lag3,
    oos_ret=if(!is.null(es)) es$essence$oos_retention else NA_real_,
    oos_band=if(!is.null(es)) es$oos_band_status else NA_character_,
    calmar=if(!is.null(es)) es$essence$calmar else NA_real_,
    SR=r$abs_net_sr, CAGR=r$abs_cagr, MDD=r$abs_mdd, net_IR=r$information_ratio,
    grade=if(!is.null(es)) es$grade else NA_character_,
    TO=r$turnover_annual)
}

## ---- 7) 실행: primary = cap-w(score) × {proxy,IKS} × {full,t164}; pattern check = EW/score/cap-w vs proxy full ----
RES<-list()
# pattern-check (원 g 비교 재현): proxy, full
for(wt in c("ew","score","capw")) RES[[length(RES)+1]]<-measure("score",wt,bench_proxy,"proxy_capw","full")
# primary cap-w × 2 bench × 2 window
for(bl in list(list(bench_proxy,"proxy_capw"), list(bench_iks,"iks200"))){
  for(win in c("full","t164")) RES[[length(RES)+1]]<-measure("score","capw",bl[[1]],bl[[2]],win)
}
# ALT mom6 재-z 민감도 (primary cap-w, proxy, full)
RES[[length(RES)+1]]<-measure("score_rez","capw",bench_proxy,"proxy_capw_ALTrez","full")
R<-rbindlist(Filter(Negate(is.null),RES),fill=TRUE)

## ---- 8) book carrier PORT_t (164mo 정의 pin: full vs trailing-164) ----
carr<-fread("06_Registry/book_carrier/carrier_STR_1715_AR_on_M4_R05_overlay_PG2_monthly.csv")
carr[,ym:=format(as.Date(eval_date),"%Y-%m")]
# book 월수익을 sig_date(예측월 정렬 ny)에 붙임: carrier eval_date의 ym = ny(sig_date) 기준으로 정렬
bookdt<-data.table(Date=dts, ym_next=vapply(seq_along(dts),function(i)ny(dts[i]),character(1)))
bookdt<-merge(bookdt,carr[,.(ym,book=port_ret_gross_recon)],by.x="ym_next",by.y="ym",all.x=TRUE)
setorder(bookdt,Date)
bk_probe<-function(benchdt,blab,win){bd<-merge(bookdt,benchdt,by="Date"); bd<-bd[is.finite(book)&is.finite(BM_Ret)]
  if(win=="t164"){bd<-tail(bd,164)}
  data.table(bench=blab,window=win,n=nrow(bd),book_pt=nwt(bd$book-bd$BM_Ret),book_SR=IRf(bd$book),book_calmar=calf(bd$book))}
BKP<-rbindlist(list(bk_probe(bench_proxy,"proxy_capw","full"),bk_probe(bench_proxy,"proxy_capw","t164"),
                    bk_probe(bench_iks,"iks200","full"),bk_probe(bench_iks,"iks200","t164")))

cat("\n===== RAMP_03C 재현 (weighted_screen_bt + essence_score) =====\n")
cat(sprintf("  %-16s %-16s %-5s %4s %7s %7s %6s %6s %6s %6s %5s %6s\n","weighting","bench","win","n","pt_capw","oos_ret","calmar","SR","CAGR","MDD","grade","TO"))
for(i in seq_len(nrow(R))){r<-R[i];cat(sprintf("  %-16s %-16s %-5s %4d %+7.2f %+7.2f %+6.2f %+6.2f %+6.2f %+6.2f %5s %6.1f\n",
  r$weighting,r$bench,r$window,r$n,r$pt_capwt,ifelse(is.na(r$oos_ret),NA,r$oos_ret),ifelse(is.na(r$calmar),NA,r$calmar),r$SR,r$CAGR,r$MDD,ifelse(is.na(r$grade),"NA",r$grade),ifelse(is.na(r$TO),0,r$TO)))}
cat("\n----- book carrier PORT_t (164mo 정의 pin) -----\n")
cat(sprintf("  %-14s %-5s %4s %7s %7s %8s\n","bench","win","n","book_pt","book_SR","book_cal"))
for(i in seq_len(nrow(BKP))){r<-BKP[i];cat(sprintf("  %-14s %-5s %4d %+7.2f %+7.2f %+8.2f\n",r$bench,r$window,r$n,r$book_pt,r$book_SR,r$book_calmar))}

## ---- 9) config hash + 산출 저장 ----
cfg<-list(strategy_id="RAMP_03C_BOOKMOM_CAPW", source_lcode="L-RAMP-20260620_184815",
  signal="0.5*zc(book_score_eff, ny-aligned) + 0.5*mean(zc(mom6))",
  mom6=mom6, select="top-25 by score", weight="cap_norm(Size), [0,0.20], Sigma_w=1",
  universe="K200 union KQ150", liq="ADV>=2e8", cost_bps=15,
  bench_bases=c("RAMP-native cap-w K200uKQ150 proxy (build_monthly_forward_returns)","corrected IKS200 (benchmark.parquet)"),
  measure="weighted_screen_bt -> build_benchmark_compare NW lag3 + essence_score oos v2/calmar",
  pin_tag=PINTAG)
cfg_json<-toJSON(cfg,auto_unbox=TRUE,pretty=TRUE)
writeLines(cfg_json, file.path(WT,"config_restored.json"))
cfg_hash<-unname(tools::md5sum(file.path(WT,"config_restored.json")))
cat("\nCONFIG_HASH(md5 of config_restored.json)=",cfg_hash,"\n")
saveRDS(list(R=R,BKP=BKP,cfg=cfg,cfg_hash=cfg_hash,pin_tag=PINTAG), file.path(SCR,"ramp03c_results.rds"))
# 차트용 최적 cap-w period_returns 보존 (proxy/full + iks/full)
save_pr<-function(scorecol,wtype,benchdt,benchlab,win,fn){W<-mk_weights(scorecol,wtype)
  if(win=="t164"){allm<-sort(unique(W$Date)); keep<-tail(allm,164); W<-W[Date%in%keep]}
  r<-weighted_screen_bt(W,fwd_ret,benchdt,cost_bps_oneway=15,run_id="save",strategy_id="RAMP_03C")
  saveRDS(as.data.table(r$period_returns), fn)}
save_pr("score","capw",bench_proxy,"proxy","full",file.path(SCR,"pr_capw_proxy_full.rds"))
save_pr("score","capw",bench_iks,"iks","full",file.path(SCR,"pr_capw_iks_full.rds"))
save_pr("score","capw",bench_proxy,"proxy","t164",file.path(SCR,"pr_capw_proxy_t164.rds"))
cat("RERUN_DONE\n")
