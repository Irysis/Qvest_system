## run_fof_decay_diag.R — "왜 2017 감쇠?" 메커니즘 분해 (실측)
## 후보: ① 신호 죽음(rank-IC↓) ② 신호OK·실현premium 죽음(LS-spread↓=translation) ③ 횡단면분산 붕괴 ④ breadth 협소/메가캡 집중.
## 연도별 aggregate 팩터-IC · LS-spread(top-bot quintile) · LO-active(top-BM) · 횡단면분산 · breadth + rolling + 상관.
suppressPackageStartupMessages({library(data.table); library(arrow)})
setDTthreads(1); try(arrow::set_io_thread_count(1),silent=TRUE)
QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
OUT<-"04_Research/factor_rotation/fof_first_slice"; con<-file(file.path(OUT,"_fof_decay.txt"),"w",encoding="UTF-8"); w<-function(...) writeLines(paste0(...),con)
w("================ 왜 2017 감쇠? 메커니즘 분해 ================"); w(sprintf("실행 %s",as.character(Sys.time())))

sc<-as.data.table(read_parquet("outputs/ramp/pure_factor_scores.parquet", col_select=c("signal_date","security_id","factor_id","neutralized_z")))
setnames(sc,"neutralized_z","nz"); sc[,signal_date:=as.Date(signal_date)]
bo<-readRDS(".cache/_bo_fwdgic.rds"); fwd<-bo$fwd
ret_dt<-as.data.table(fwd$returns_dt)[,.(signal_date=as.Date(Date),security_id=Ticker,Ret_1m)]
bench_dt<-as.data.table(fwd$bench_dt)[,.(signal_date=as.Date(Date),BM_Ret)]
liq_dt<-as.data.table(fwd$liq_dt)[,.(signal_date=as.Date(Date),security_id=Ticker,adv)]
FIC<-readRDS(file.path(OUT,"_factor_ic.rds"))   # Date, factor_id, ic

## ── (A) aggregate 팩터 rank-IC (월별 mean across 316 factors) ──
aic<-FIC[, .(agg_ic=mean(ic,na.rm=TRUE), pos_frac=mean(ic>0,na.rm=TRUE)), by=.(date=Date)]
setorder(aic,date)

## ── (B) 팩터 LS-spread(top-bot quintile) + LO-active(top-BM) ──
m<-merge(sc[,.(signal_date,security_id,factor_id,nz)], ret_dt, by=c("signal_date","security_id"))
m[, q:=frank(nz,ties.method="first")/.N, by=.(signal_date,factor_id)]
fls<-m[, .(top=mean(Ret_1m[q>0.8],na.rm=TRUE), bot=mean(Ret_1m[q<=0.2],na.rm=TRUE)), by=.(signal_date,factor_id)]
fls[, ls:=top-bot]
agg_ls<-fls[, .(LS_spread=mean(ls,na.rm=TRUE), top_ret=mean(top,na.rm=TRUE)), by=.(date=signal_date)]
agg_ls<-merge(agg_ls, bench_dt[,.(date=signal_date,BM_Ret)], by="date")
agg_ls[, LO_active:=top_ret-BM_Ret]

## ── (C) 횡단면 분산 + breadth (월별, 종목간) ──
md<-merge(ret_dt, bench_dt, by="signal_date")
disp<-md[, .(disp=sd(Ret_1m,na.rm=TRUE), breadth=mean(Ret_1m>BM_Ret,na.rm=TRUE), nstk=.N), by=.(date=signal_date)]
## 메가캡 집중 proxy: 상위 5종목(adv) 거래대금 점유 (유동성 집중) — 시총 대용
liqc<-liq_dt[, { setorder(.SD,-adv); .(top5_adv_share=sum(head(adv,5))/sum(adv,na.rm=TRUE)) }, by=.(date=signal_date)]

D<-Reduce(function(a,b) merge(a,b,by="date",all=TRUE), list(aic, agg_ls[,.(date,LS_spread,LO_active)], disp, liqc))
setorder(D,date); D[, yr:=year(date)]

## ── 연도별 요약 ──
w("\n=== 연도별 (agg_IC=팩터 rank-IC평균 · LS=top-bot premium · LO=top-BM · disp=횡단면분산 · breadth · top5거래점유) ===")
yt<-D[, .(agg_IC=round(mean(agg_ic,na.rm=T),4), LS_pct=round(100*mean(LS_spread,na.rm=T),2),
          LO_pct=round(100*mean(LO_active,na.rm=T),2), disp_pct=round(100*mean(disp,na.rm=T),1),
          breadth=round(100*mean(breadth,na.rm=T),0), top5=round(100*mean(top5_adv_share,na.rm=T),0), nstk=round(mean(nstk))), by=yr]
for(i in 1:nrow(yt)) w(sprintf("  %d: agg_IC=%+.4f | LS=%+.2f%% | LO=%+.2f%% | disp=%.1f%% | breadth=%d%% | top5점유=%d%% | n=%d",
  yt$yr[i],yt$agg_IC[i],yt$LS_pct[i],yt$LO_pct[i],yt$disp_pct[i],yt$breadth[i],yt$top5[i],yt$nstk[i]))

## ── pre/post 2017 대비 + 상관 ──
pre<-D[date<as.Date("2017-07-01")]; post<-D[date>=as.Date("2017-07-01")]
w("\n=== pre vs post 2017-07 (구조 break 후보) ===")
w(sprintf("  agg_IC:   pre=%+.4f  post=%+.4f  (Δ %+.4f)", mean(pre$agg_ic,na.rm=T), mean(post$agg_ic,na.rm=T), mean(post$agg_ic,na.rm=T)-mean(pre$agg_ic,na.rm=T)))
w(sprintf("  LS_spread:pre=%+.3f%% post=%+.3f%% (Δ %+.3f%%)", 100*mean(pre$LS_spread,na.rm=T),100*mean(post$LS_spread,na.rm=T),100*(mean(post$LS_spread,na.rm=T)-mean(pre$LS_spread,na.rm=T))))
w(sprintf("  LO_active:pre=%+.3f%% post=%+.3f%% (Δ %+.3f%%)", 100*mean(pre$LO_active,na.rm=T),100*mean(post$LO_active,na.rm=T),100*(mean(post$LO_active,na.rm=T)-mean(pre$LO_active,na.rm=T))))
w(sprintf("  disp:     pre=%.2f%%  post=%.2f%%", 100*mean(pre$disp,na.rm=T),100*mean(post$disp,na.rm=T)))
w(sprintf("  breadth:  pre=%d%%   post=%d%%", round(100*mean(pre$breadth,na.rm=T)),round(100*mean(post$breadth,na.rm=T))))
w(sprintf("  top5점유: pre=%d%%   post=%d%%", round(100*mean(pre$top5_adv_share,na.rm=T)),round(100*mean(post$top5_adv_share,na.rm=T))))
cc<-D[is.finite(agg_ic)&is.finite(disp)]
w(sprintf("\n  상관 cor(agg_IC, disp)=%+.2f | cor(LS_spread, disp)=%+.2f | cor(agg_IC, breadth)=%+.2f",
  cor(cc$agg_ic,cc$disp,use="complete.obs"), cor(cc$LS_spread,cc$disp,use="complete.obs"), cor(cc$agg_ic,cc$breadth,use="complete.obs")))

fwrite(yt,file.path(OUT,"decay_by_year.csv")); fwrite(D,file.path(OUT,"decay_monthly.csv"))
cat("DECAY|", paste(sprintf("%d:IC%.3f/LS%.1f/disp%.0f",yt$yr,yt$agg_IC,yt$LS_pct,yt$disp_pct),collapse=" "),"\n")
close(con); cat("FOF_DECAY_DONE\n")
