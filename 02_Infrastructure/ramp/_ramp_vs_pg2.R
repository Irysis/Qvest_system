## _ramp_vs_pg2.R — RAMP M-code가 PG2(book STR_1715_AR_on_M4_R05) 대비 대체/보강 가능한지 실측.
## 동일 벤치(cap-w universe forward)·동일 월그리드에서 active 상관 + book-marginal blend ΔIR.
## 대체 = standalone IR > book IR(1.5754) / 보강 = optimal 2-sleeve blend ΔIR ≥ 0.05.
suppressPackageStartupMessages({library(data.table); library(arrow)})
setDTthreads(1); try(arrow::set_io_thread_count(2),silent=TRUE)
QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
source("02_Infrastructure/config.R"); source("02_Infrastructure/ramp/factor_validation.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")
con<-file(".cache/_ramp_vs_pg2.txt","w",encoding="UTF-8"); w<-function(...)writeLines(paste0(...),con)
zc<-function(x){m<-mean(x,na.rm=T);s<-sd(x,na.rm=T);if(is.na(s)||s<1e-9) x-m else (x-m)/s}
IRf<-function(x){x<-x[is.finite(x)];mean(x)/sd(x)*sqrt(12)}

## --- RAMP M_regdd 월간 net 시계열 재생성 (graduation mk_score와 동일) ---
g<-as.data.table(read_parquet("outputs/ramp/factor_group_scores.parquet")); g[,signal_date:=as.Date(signal_date)]
gw<-dcast(g,signal_date+security_id~family,value.var="group_z"); grp<-setdiff(names(gw),c("signal_date","security_id"))
a<-as.data.table(read_parquet("stage_artifacts/WT_D20260425_010/alpha_scores.parquet")); a[,Date:=as.Date(Date)]
reg<-unique(a[,.(ym=format(Date,"%Y-%m"),regime=regime_state)])[,.SD[1],by=ym]
gw[,ym:=format(signal_date,"%Y-%m")]; gw<-merge(gw,reg,by="ym",all.x=TRUE); gw[is.na(regime),regime:="NORMAL"]
.need<-c("Date","Ticker","Close","K200","KQ150","Vol","Size","Ret","Sector","BM_Ret")
rawdata<-as.data.table(read_parquet(".cache/rawdata.parquet", col_select=all_of(.need))); rawdata[,Date:=as.Date(Date)]
sig_dates<-sort(unique(gw$signal_date)); fwd<-build_monthly_forward_returns(rawdata,sig_dates)
ic<-merge(g[,.(signal_date,security_id,family,group_z)],fwd$returns_dt[,.(signal_date=as.Date(Date),security_id=Ticker,Ret_1m)],by=c("signal_date","security_id"))
gic<-ic[,.(ic=if(.N>=10&&sd(group_z)>0&&sd(Ret_1m)>0)cor(group_z,Ret_1m,method="spearman")else NA_real_),by=.(signal_date,family)]
gic<-merge(gic,unique(gw[,.(signal_date,regime)]),by="signal_date"); setorder(gic,family,signal_date)
rows<-list()
for(d in as.character(sig_dates)){dd<-as.Date(d);rg<-gw[signal_date==dd,regime][1]
  wts<-sapply(grp,function(fm){p<-gic[family==fm&regime==rg&signal_date<dd,ic];p<-p[is.finite(p)];if(length(p)>=3)max(mean(p),0)else 0})
  if(sum(wts)<1e-9)wts<-setNames(rep(1,length(grp)),grp);ww<-wts/sum(wts)
  sub<-gw[signal_date==dd];X<-as.matrix(sub[,..grp]);X[is.na(X)]<-0
  rows[[d]]<-data.table(signal_date=dd,security_id=sub$security_id,score=as.numeric(X%*%ww))}
sc<-rbindlist(rows); sc[,score:=zc(score),by=signal_date]
cs<-canonical_screen_bt(sc[,.(Date=as.Date(signal_date),Ticker=security_id,score)],
      fwd$returns_dt[,.(Date=as.Date(Date),Ticker,Ret_1m)],fwd$bench_dt[,.(Date=as.Date(Date),BM_Ret)],
      top_n=25L,cost_bps_oneway=15,liq_dt=fwd$liq_dt[,.(Date=as.Date(Date),Ticker,adv)],liq_min=2e8,run_id="vspg2",strategy_id="RAMP_M_regdd")
pr<-as.data.table(cs$period_returns); pr[,date:=as.Date(date)]
ramp<-pr[,.(ym=format(date,"%Y-%m"), ramp_net=ret_net, bench=benchmark_ret)]   # bench = cap-w universe forward

## --- book STR_1715 월간 net ---
b<-fread("04_Research/strategies/STR_1715_WT016_Iter31_GridBestProd/output/03_period_returns.csv")
b[,ym:=format(as.Date(date),"%Y-%m")]; book<-b[,.(ym, book_net=ret_net)]

## --- 동일 월그리드 정렬, 동일 벤치(cap-w) active ---
M<-merge(ramp, book, by="ym")            # 교집합 월
M[,book_act:=book_net-bench]; M[,ramp_act:=ramp_net-bench]
M<-M[is.finite(book_act)&is.finite(ramp_act)]
w(sprintf("공통 월 수: %d (%s ~ %s)", nrow(M), min(M$ym), max(M$ym)))

IR_book<-IRf(M$book_act); IR_ramp<-IRf(M$ramp_act); rho<-cor(M$book_act,M$ramp_act)
w(sprintf("\n=== standalone (동일 cap-w 벤치, net 15bps, 공통월) ==="))
w(sprintf("  book(STR_1715) active IR = %.3f", IR_book))
w(sprintf("  RAMP M_regdd  active IR = %.3f", IR_ramp))
w(sprintf("  active 상관 ρ(book,ramp) = %.3f", rho))

## --- 대체 판정 ---
w(sprintf("\n=== 대체(replace) 판정 ==="))
w(sprintf("  RAMP IR %.3f vs book IR %.3f → %s", IR_ramp, IR_book, ifelse(IR_ramp>IR_book,"RAMP 우세(대체가능)","book 우세(대체 불가)")))

## --- 보강 판정 (1) in-sample 최적 blend ---
ws<-seq(0,1,by=0.02); bl<-sapply(ws,function(wb){IRf(wb*M$book_act+(1-wb)*M$ramp_act)})
wb_star<-ws[which.max(bl)]; IR_blend<-max(bl)
w(sprintf("\n=== 보강(complement) — (1) in-sample 최적 (과적합 상한) ==="))
w(sprintf("  최적 blend book %.0f%%/RAMP %.0f%% → IR %.3f | ΔIR %+.3f", wb_star*100,(1-wb_star)*100,IR_blend,IR_blend-IR_book))
w(sprintf("  이론: ρ<IR_ramp/IR_book=%.3f 면 보강. 실측 ρ=%.3f → 직교성 강함", IR_ramp/IR_book, rho))

## --- 보강 판정 (2) OOS 워크포워드 (정직한 수치) ---
## IS(앞 60%)에서 최적 w 결정 → OOS(뒤 40%)에 적용. + 고정 보수가중(book 85/RAMP 15) 비교.
setorder(M,ym); n<-nrow(M); cut<-floor(n*0.6); IS<-M[1:cut]; OOS<-M[(cut+1):n]
wb_is<-ws[which.max(sapply(ws,function(wb)IRf(wb*IS$book_act+(1-wb)*IS$ramp_act)))]
oos_book<-IRf(OOS$book_act); oos_blend_wf<-IRf(wb_is*OOS$book_act+(1-wb_is)*OOS$ramp_act)
oos_blend_85<-IRf(0.85*OOS$book_act+0.15*OOS$ramp_act)
w(sprintf("\n=== 보강 — (2) OOS 워크포워드 (IS=%d월→OOS=%d월, %s~) ===", cut, n-cut, OOS$ym[1]))
w(sprintf("  IS 최적가중: book %.0f%%/RAMP %.0f%%", wb_is*100,(1-wb_is)*100))
w(sprintf("  OOS book-only IR        = %.3f", oos_book))
w(sprintf("  OOS blend(IS최적가중)    = %.3f | ΔIR %+.3f (%s)", oos_blend_wf, oos_blend_wf-oos_book, ifelse(oos_blend_wf-oos_book>=0.05,"OOS 보강 유지 ✓","OOS 미달 ✗")))
w(sprintf("  OOS blend(고정 85/15)    = %.3f | ΔIR %+.3f (%s)", oos_blend_85, oos_blend_85-oos_book, ifelse(oos_blend_85-oos_book>=0.05,"OOS 보강 유지 ✓","OOS 미달 ✗")))

## --- 보강 판정 (3) IS/OOS 각각의 상관·standalone (decay 점검) ---
w(sprintf("\n=== (3) IS vs OOS decay 점검 ==="))
w(sprintf("  IS : ρ=%.3f  RAMP IR=%.3f  book IR=%.3f", cor(IS$book_act,IS$ramp_act),IRf(IS$ramp_act),IRf(IS$book_act)))
w(sprintf("  OOS: ρ=%.3f  RAMP IR=%.3f  book IR=%.3f", cor(OOS$book_act,OOS$ramp_act),IRf(OOS$ramp_act),IRf(OOS$book_act)))
saveRDS(M,".cache/_ramp_vs_pg2.rds"); close(con); cat("VSPG2_DONE\n")
