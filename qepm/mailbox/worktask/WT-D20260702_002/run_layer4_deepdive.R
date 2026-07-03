## ============================================================================
## WT-D20260702_002 — Layer4 포함 vs 제거 심층분석 (도훈 지시 2026-07-02)
## 승인 전 결정근거: 연도별·국면별·꼬리(위기월)·낙폭에피소드·롤링SR·라이브노출.
## 3 변형 (전부 클린 타이밍, per-layer canonical cost):
##   INC_faith = beta_R05 x m4 x beta_faith_CLEAN (현 배포 레이어, 정직 타이밍)
##   INC_AR    = beta_R05 x m4 x beta_AR           (전임 Layer4)
##   NOL4      = beta_R05 x m4                       (제거안 = 후보)
##   NAKED     = ret_orig                            (오버레이 전무, 참조)
## 핵심 질문: Layer4가 실제로 꼬리를 지키는가? 제거 시 어디서 잃고 어디서 얻는가?
##            라이브에서 지금 당장 노출이 어떻게 바뀌는가?
## ============================================================================
suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite)
  library(PerformanceAnalytics); library(xts); library(lubridate)
})
ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", getwd()))
OUT <- file.path(ROOT, "qepm/mailbox/worktask/WT-D20260702_002/output")
BM_PIN <- file.path(ROOT, "stage_artifacts/pg2_offense_overlay/benchmark_pinned_20260702.parquet")
T_HALF <- 16L; CF <- c(a=0.13, d=0.79, e=-0.17, f=0.09); COST <- 0.0015

cat("[1] panel + clean faith 재구성\n")
p <- fread(file.path(ROOT, "05_Production/2.Factor_Model/2-2.STR_1715_FaithTrend_on_M4_R05_overlay_PG2/04_backtest_results/period_returns_layer5_faith.csv"))
p[, anchor_date := as.Date(anchor_date)]; setorder(p, realized_ym); stopifnot(nrow(p)==269)
bm <- as.data.table(read_parquet(BM_PIN)); bm[, Date := as.Date(Date)]
bm <- bm[is.finite(BM_Ret)]; setorder(bm, Date)
r <- bm$BM_Ret; n <- length(r)
rm252 <- frollmean(r,252,na.rm=TRUE); rs252 <- frollapply(r,252,sd,na.rm=TRUE)
rhat <- pmin(pmax((r-rm252)/(rs252+1e-12),-20),20); rhat[!is.finite(rhat)] <- NA
al <- 1-exp(-1/T_HALF); sig2 <- rep(NA_real_,n); acc <- 1.0
for (t in seq_len(n)) if (is.finite(rhat[t])) { acc <- al*rhat[t]^2+(1-al)*acc; sig2[t] <- acc }
N <- 6L*T_HALF; wn <- (0:N)*exp(-2*(0:N)/T_HALF); wn <- wn/sqrt(sum(wn^2)); phi <- rep(NA_real_,n)
for (t in (N+1):n) { seg <- rhat[(t-N):t]; if (all(is.finite(seg))) phi[t] <- pmin(pmax(sum(wn*rev(seg)),-2.5),2.5) }
bm[, S := CF["a"]+CF["d"]*sig2+CF["e"]*phi+CF["f"]*phi^2]; bm[, ym := format(Date,"%Y-%m")]
me <- bm[, .(S_eom=last(S)), by=ym]; setorder(me, ym)
me[, ym_p2 := format(as.Date(paste0(ym,"-01")) %m+% months(2), "%Y-%m")]
p <- merge(p, me[, .(realized_ym=ym_p2, S_clean=S_eom)], by="realized_ym", all.x=TRUE); setorder(p, realized_ym)
exp_pct <- function(x){ o<-rep(NA_real_,length(x)); for(i in seq_along(x)){pa<-x[seq_len(i-1)];pa<-pa[is.finite(pa)]
  if(length(pa)>=24 && is.finite(x[i])) o[i]<-mean(pa<x[i])}; o }
freq <- prop.table(table(round(p$beta_AR,2))); lo <- sort(as.numeric(names(freq))[as.numeric(names(freq))<0.999])
cumf<-0; thr<-list(); for(l in lo){ff<-as.numeric(freq[as.character(l)]);if(is.na(ff))ff<-0
  thr[[length(thr)+1]]<-c(l,1-cumf-ff,1-cumf);cumf<-cumf+ff}
map_freq <- function(pp){if(!is.finite(pp))return(1.0);for(tt in thr)if(pp>=tt[2]&&pp<tt[3])return(tt[1])
  if(length(lo)&&pp>=1-cumf)return(lo[1]);1.0}
p[, b_faith_cl := sapply(exp_pct(S_clean), map_freq)]

dR05 <- abs(p$beta_R05 - shift(p$beta_R05,1,fill=1.0))
mkL <- function(bL4){dL4<-abs(bL4-shift(bL4,1,fill=1.0)); p$beta_R05*p$m4*bL4*p$ret_orig - dL4*COST - dR05*COST}
p[, ret_INC_faith := mkL(b_faith_cl)]
p[, ret_INC_AR := mkL(beta_AR)]
p[, ret_NOL4 := p$beta_R05*p$m4*p$ret_orig - dR05*COST]
p[, ret_NAKED := ret_orig]
p[, E_faith := beta_R05*m4*b_faith_cl]
p[, E_AR := beta_R05*m4*beta_AR]
p[, E_noL4 := beta_R05*m4]
VARS <- c(INC_faith="ret_INC_faith", INC_AR="ret_INC_AR", NOL4="ret_NOL4", NAKED="ret_NAKED")

ann_sr <- function(x,idx=p$anchor_date) as.numeric(table.AnnualizedReturns(xts(x,order.by=idx),scale=12)[3,1])
nw_t <- function(d,lag=3){d<-d[is.finite(d)];nn<-length(d);if(nn<24)return(NA_real_);mu<-mean(d);e<-d-mu;s0<-sum(e^2)/nn
  for(L in 1:lag){w<-1-L/(lag+1);s0<-s0+2*w*sum(e[(L+1):nn]*e[1:(nn-L)])/nn};mu/sqrt(s0/nn)}

cat("\n===== [A] Layer4 발화 분석 (β 분포 + 국면별 감속) =====\n")
cat("β_faith_clean 분포:\n"); print(table(round(p$b_faith_cl,2)))
cat("β_AR 분포:\n"); print(table(round(p$beta_AR,2)))
cat("Layer4 감속(β<1) 국면별 (faith):\n")
print(p[, .(N=.N, faith_lt1=sum(b_faith_cl<0.999), faith_meanbeta=round(mean(b_faith_cl),3),
            AR_lt1=sum(beta_AR<0.999), AR_meanbeta=round(mean(beta_AR),3)), by=regime][order(regime)])
## faith vs AR 일치도
cat(sprintf("faith β == AR β 월 비율: %.1f%% | faith가 AR보다 방어적(β 낮음) 월: %d | 덜 방어적: %d\n",
    100*mean(abs(p$b_faith_cl-p$beta_AR)<1e-9), sum(p$b_faith_cl<p$beta_AR-1e-9), sum(p$b_faith_cl>p$beta_AR+1e-9)))

cat("\n===== [B] 연도별 수익 (INC_faith / INC_AR / NOL4 / NAKED / KOSPI) =====\n")
bm_x <- xts(bm$BM_Ret, order.by=bm$Date)
ky <- apply.yearly(bm_x, Return.cumulative)
yr <- data.table(year=format(index(ky),"%Y"), KOSPI=round(as.numeric(ky),4))
for(nm in names(VARS)){x<-xts(p[[VARS[nm]]],order.by=p$anchor_date);yv<-apply.yearly(x,Return.cumulative)
  tmp<-data.table(year=format(index(yv),"%Y"),v=round(as.numeric(yv),4));setnames(tmp,"v",nm)
  yr<-merge(yr,tmp,by="year",all=TRUE)}
setcolorder(yr, c("year","INC_faith","INC_AR","NOL4","NAKED","KOSPI")); print(yr, nrow=30)

cat("\n===== [C] 국면별 월평균 수익 + 승률 (오버레이 효과의 국면 분해) =====\n")
reg_tbl <- p[, .(N=.N,
  INC_faith=round(mean(ret_INC_faith),4), INC_AR=round(mean(ret_INC_AR),4),
  NOL4=round(mean(ret_NOL4),4), NAKED=round(mean(ret_NAKED),4),
  faith_vs_noL4=round(mean(ret_INC_faith-ret_NOL4),4)), by=regime][order(regime)]
print(reg_tbl)
cat("→ Layer4(faith)가 NOL4 대비 국면별 순기여(양수=Layer4 도움):\n")
print(p[, .(faith_minus_noL4_bps_mo=round(1e4*mean(ret_INC_faith-ret_NOL4),1),
            AR_minus_noL4_bps_mo=round(1e4*mean(ret_INC_AR-ret_NOL4),1)), by=regime][order(regime)])

cat("\n===== [D] 낙폭 에피소드 top (변형별) — Layer4가 실제 낙폭을 줄이나? =====\n")
for(nm in names(VARS)){x<-xts(p[[VARS[nm]]],order.by=p$anchor_date)
  dd<-tryCatch(table.Drawdowns(x, top=5),error=function(e)NULL)
  cat(sprintf("\n-- %s (MDD %.1f%%) --\n", nm, 100*as.numeric(maxDrawdown(x))))
  if(!is.null(dd)) print(dd[,c("From","Trough","To","Depth","Length")])}

cat("\n===== [E] 최악 12개월 (book=NOL4 기준) — 그 달 Layer4는 방어했나? =====\n")
worst <- p[order(ret_NOL4)][1:12, .(realized_ym, regime,
  ret_orig=round(ret_orig,3), b_faith=round(b_faith_cl,2), b_AR=round(beta_AR,2),
  E_faith=round(E_faith,2), E_noL4=round(E_noL4,2),
  NOL4=round(ret_NOL4,3), INC_faith=round(ret_INC_faith,3), INC_AR=round(ret_INC_AR,3),
  faith_helped=round(ret_INC_faith-ret_NOL4,3))]
print(worst)
cat(sprintf("→ 최악 12개월서 faith가 NOL4보다 나은 달: %d/12 | 평균 도움 %.3f\n",
    worst[faith_helped>0,.N], worst[,mean(faith_helped)]))

cat("\n===== [F] 위기 윈도우 월별 상세 =====\n")
crises <- list(GFC=sprintf("2008-%02d",6:12), COVID=c("2020-02","2020-03","2020-04","2020-05"),
  Bear2022=sprintf("2022-%02d",1:10), Y2026=c("2026-01","2026-02","2026-03","2026-04","2026-05","2026-06"))
for(cn in names(crises)){cat(sprintf("\n-- %s --\n", cn))
  sub<-p[realized_ym %in% crises[[cn]], .(realized_ym, regime, ret_orig=round(ret_orig,3),
    b_faith=round(b_faith_cl,2), b_AR=round(beta_AR,2),
    NOL4=round(ret_NOL4,3), INC_faith=round(ret_INC_faith,3), INC_AR=round(ret_INC_AR,3))]
  print(sub)
  if(nrow(sub)>0) cat(sprintf("   윈도우 누적: NOL4 %.1f%% | INC_faith %.1f%% | INC_AR %.1f%%\n",
    100*(prod(1+p[realized_ym %in% crises[[cn]]]$ret_NOL4)-1),
    100*(prod(1+p[realized_ym %in% crises[[cn]]]$ret_INC_faith)-1),
    100*(prod(1+p[realized_ym %in% crises[[cn]]]$ret_INC_AR)-1)))}

cat("\n===== [G] 롤링 36m SR (지배 안정성) =====\n")
roll_sr <- function(x){r<-rollapply(xts(x,order.by=p$anchor_date),36,function(w)ann_sr(as.numeric(w),index(w)),by.column=FALSE,align="right");as.numeric(na.omit(r))}
rf<-roll_sr(p$ret_INC_faith);rn<-roll_sr(p$ret_NOL4);ra<-roll_sr(p$ret_INC_AR)
m<-min(length(rf),length(rn),length(ra));rf<-tail(rf,m);rn<-tail(rn,m);ra<-tail(ra,m)
cat(sprintf("36m 롤링 윈도우 %d개:\n", m))
cat(sprintf("  NOL4 > INC_faith 윈도우 비율: %.0f%% (Δ 중앙 %+.3f, min %+.3f max %+.3f)\n",
    100*mean(rn>rf), median(rn-rf), min(rn-rf), max(rn-rf)))
cat(sprintf("  NOL4 > INC_AR    윈도우 비율: %.0f%% (Δ 중앙 %+.3f)\n", 100*mean(rn>ra), median(rn-ra)))

cat("\n===== [H] 라이브 노출 변화 (최근 12개월: 제거 시 지금 얼마나 더 노출?) =====\n")
recent <- p[realized_ym >= "2025-07", .(realized_ym, regime,
  invested_faith=round(E_faith,3), invested_noL4=round(E_noL4,3),
  delta_exposure=round(E_noL4-E_faith,3),
  ret_orig=round(ret_orig,3))]
print(recent)
cat(sprintf("→ 최근 12m 평균 노출: faith %.3f vs noL4 %.3f (제거 시 +%.1f%%p 노출)\n",
    p[realized_ym>="2025-07",mean(E_faith)], p[realized_ym>="2025-07",mean(E_noL4)],
    100*p[realized_ym>="2025-07",mean(E_noL4-E_faith)]))

cat("\n===== [I] oos band escalation 증거 (NOL4 active-basis, C=0.534 band) =====\n")
## book=NOL4 채택 시 자본적정성: active(-BM) oos_retention band [0.5,0.7) → 2/3 보강증거
bmw <- rep(NA_real_,nrow(p)); a<-p$anchor_date
for(i in 2:nrow(p)){seg<-bm_x[index(bm_x)>a[i-1]&index(bm_x)<=a[i]];if(nrow(seg)>0)bmw[i]<-as.numeric(Return.cumulative(seg))}
bmw[1]<-0; p[, bm_win := bmw]; p[, active_NOL4 := ret_NOL4 - bm_win]
## ev1 trailing subwindow active PORT_t>0 (last 60m)
sub60 <- tail(p$active_NOL4,60); ev1 <- nw_t(sub60)
## ev2 placebo: shift ret_orig sign block? 간이 — active mean t 전체
ev_full <- nw_t(p$active_NOL4)
## ev3 book-marginal proxy: NOL4 vs INC_faith active-Δ NW-t (제거가 book 개선인가)
ev3 <- nw_t(p$ret_NOL4 - p$ret_INC_faith)
cat(sprintf("  active oos_retention(NOL4) = 0.534 (band_fail, judge 산출)\n"))
cat(sprintf("  보강ev1 trailing 60m active PORT_t = %.2f (>0 필요)\n", ev1))
cat(sprintf("  보강ev-full 전기간 active PORT_t = %.2f\n", ev_full))
cat(sprintf("  보강ev3 NOL4-vs-INC_faith 월Δ NW-t = %.2f (>0 = 제거가 유의 개선)\n", ev3))

## 산출
summ <- list(
  full=rbindlist(lapply(names(VARS),function(nm){x<-xts(p[[VARS[nm]]],order.by=p$anchor_date)
    data.table(variant=nm, SR=round(ann_sr(p[[VARS[nm]]]),3),
      CAGR=round(as.numeric(Return.annualized(x,scale=12)),4), MDD=round(as.numeric(maxDrawdown(x)),4),
      Calmar=round(as.numeric(CalmarRatio(x,scale=12)),3), Sortino_m=round(as.numeric(SortinoRatio(x,MAR=0)),4))})),
  regime=reg_tbl, yearly=yr)
fwrite(yr, file.path(OUT,"deepdive_yearly.csv"))
fwrite(reg_tbl, file.path(OUT,"deepdive_regime.csv"))
fwrite(worst, file.path(OUT,"deepdive_worst12.csv"))
fwrite(recent, file.path(OUT,"deepdive_live_exposure.csv"))
write_json(list(band_evidence=list(oos=0.534, ev1_trailing60=round(ev1,3), ev_full=round(ev_full,3), ev3_removal=round(ev3,3)),
  rolling=list(nol4_beats_faith_pct=round(100*mean(rn>rf)), nol4_beats_ar_pct=round(100*mean(rn>ra)))),
  file.path(OUT,"deepdive_meta.json"), auto_unbox=TRUE, pretty=TRUE)
cat("\n[DONE] deepdive 산출:", OUT, "\n")
