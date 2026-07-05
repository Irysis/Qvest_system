## WT-D20260705_005 — Alpha Research: RAMP 잔차-직교 sleeve 개별 배포-envelope PORT_t 스크리닝
## measurement-graduation §6 미해결 항목("RAMP 18후보 PORT_t 검증 필요") closure.
## 실측-only: canonical_screen_bt (top-25 EW long-only, K200∪KQ150, 15bps, LIQ 2e8).
## 판정 권위 = port_t_capwt (cap-w market-proxy active, NW lag-3). rank-IC는 진단.
## 단일스레드 + arrow io_thread=2 (HANG 회피). vintage: pin_cache 스냅샷.
suppressPackageStartupMessages({library(data.table); library(arrow); library(sandwich); library(lmtest)})
setDTthreads(1); try(arrow::set_cpu_count(1),silent=TRUE); try(arrow::set_io_thread_count(2),silent=TRUE)
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
source("02_Infrastructure/config.R")
source("02_Infrastructure/ramp/factor_validation.R")   # build_monthly_forward_returns
source("02_Infrastructure/contracts/canonical_screen_bt.R")
source(file.path("02_Infrastructure","data","pin_cache.R"))
zc <- function(x){ m<-mean(x,na.rm=TRUE); s<-sd(x,na.rm=TRUE); if(is.na(s)||s<1e-9) x-m else (x-m)/s }

## ── vintage pin ──
PINTAG <- format(Sys.time(), "wt005_%Y%m%d_%H%M%S")
FGS  <- "outputs/ramp/factor_group_scores.parquet"
# rawdata: month-end K200|KQ150 slim (Python 사전 슬라이스, arrow-R HANG 회피; PIT 동일)
RAWC <- "stage_artifacts/WT-D20260705_005/rawdata_monthend_slim.parquet"
pin_cache(c(FGS, RAWC), PINTAG)
cat(sprintf("[pin] tag=%s\n", PINTAG))

OUT <- "stage_artifacts/WT-D20260705_005"; dir.create(OUT, showWarnings=FALSE, recursive=TRUE)
logf <- file.path(OUT, "sleeve_screening_log.txt")
con <- file(logf,"w",encoding="UTF-8"); w<-function(...){ writeLines(paste0(...),con); flush(con) }

## ── 데이터 (pinned) ──
g <- as.data.table(read_parquet(read_pinned(FGS, PINTAG)))
g[, signal_date := as.Date(signal_date)]
FAMS <- sort(unique(g$family))
gw <- dcast(g, signal_date + security_id ~ family, value.var="group_z")
w(sprintf("[data] families=%d months=%d range=%s..%s",
          length(FAMS), length(unique(g$signal_date)),
          min(g$signal_date), max(g$signal_date)))

.need <- c("Date","Ticker","Close","K200","KQ150","Vol","Size","Ret","BM_Ret")
rawdata <- as.data.table(read_parquet(read_pinned(RAWC, PINTAG), col_select=all_of(.need)))
rawdata[,Date:=as.Date(Date)]
sig_dates <- sort(unique(gw$signal_date))
fwd <- build_monthly_forward_returns(rawdata, sig_dates)   # K200|KQ150 필터 내장
post2017 <- as.Date("2017-01-01")
ewb <- fwd$returns_dt[, .(ew=mean(Ret_1m,na.rm=TRUE)), by=.(date=as.Date(Date))]  # EW-uni 벤치(진단)

## ── 게이트 계산기 ──
srf <- function(x){ x<-x[is.finite(x)]; if(length(x)<6) return(NA_real_); mean(x)/sd(x)*sqrt(12) }
nwt <- function(x){ x<-x[is.finite(x)]; if(length(x)<12) return(NA_real_)
  m<-lm(x~1); as.numeric(coeftest(m, vcov=sandwich::NeweyWest(m,lag=3,prewhite=FALSE))[1,3]) }

## rank-IC (Spearman): sleeve score(t) vs Ret_1m(t) 횡단면, 월별 → 평균/ICIR/Harvey-t
rank_ic_stats <- function(score_dt){
  m <- merge(score_dt[,.(Date=as.Date(signal_date), Ticker=security_id, score)],
             fwd$returns_dt[,.(Date=as.Date(Date), Ticker, Ret_1m)], by=c("Date","Ticker"))
  ics <- m[, .(ic = suppressWarnings(cor(score, Ret_1m, method="spearman", use="complete.obs"))),
           by=Date][is.finite(ic)]
  if(nrow(ics)<12) return(list(ic=NA_real_, icir=NA_real_, harvey_t=NA_real_, n=nrow(ics)))
  ic_mean <- mean(ics$ic); ic_sd <- sd(ics$ic)
  icir <- if(ic_sd>1e-9) ic_mean/ic_sd else NA_real_
  ht <- icir*sqrt(nrow(ics))    # Harvey t (rank-IC t)
  list(ic=ic_mean, icir=icir, harvey_t=ht, n=nrow(ics))
}

gates <- function(score_dt, lab){
  cs <- tryCatch(canonical_screen_bt(
        score_dt[,.(Date=as.Date(signal_date), Ticker=security_id, score)],
        fwd$returns_dt[,.(Date=as.Date(Date), Ticker, Ret_1m)],
        fwd$bench_dt[,.(Date=as.Date(Date), BM_Ret)],
        top_n=25L, cost_bps_oneway=15,
        liq_dt=fwd$liq_dt[,.(Date=as.Date(Date), Ticker, adv)], liq_min=2e8,
        run_id="wt005", strategy_id=lab), error=function(e){ w("  [gates ERR ",lab,"] ",conditionMessage(e)); NULL })
  if(is.null(cs) || is.null(cs$benchmark_compare)) {
    # canonical_screen_bt는 benchmark_compare 대신 period 수준 반환 — 재구성
  }
  if(is.null(cs)) return(NULL)
  # period returns 재구성: canonical_screen_bt 반환 필드 확인
  pr <- tryCatch(as.data.table(cs$period_returns), error=function(e) NULL)
  if(is.null(pr) || !("ret_net" %in% names(pr))){
    # fallback: benchmark_compare에서 net active만 있으면 사용
    w("  [WARN ",lab,"] period_returns 부재 — cs 필드: ", paste(names(cs), collapse=","))
    return(NULL)
  }
  pr[,date:=as.Date(date)]
  pr <- merge(pr, ewb, by="date", all.x=TRUE)
  pr[, act := ret_net - ew]                # EW-uni active (진단)
  pr[, act_bm := ret_net - benchmark_ret]  # cap-w active (authoritative)
  pt      <- nwt(pr$act)
  pt_bm   <- nwt(pr$act_bm)
  nav <- cumprod(1+pr$ret_net); dd <- min(nav/cummax(nav)-1); ann <- prod(1+pr$ret_net)^(12/nrow(pr))-1
  cal <- if(dd<0) ann/abs(dd) else NA_real_
  .splits<-c(0.55,0.65,0.75); .rets<-sapply(.splits,function(fr){ k<-floor(nrow(pr)*fr)
    if(k<12||(nrow(pr)-k)<6) return(NA_real_); .is<-srf(pr$act_bm[1:k]); .oo<-srf(pr$act_bm[(k+1):nrow(pr)])
    if(!is.na(.is)&&.is>0) .oo/.is else NA_real_ })
  retn <- median(.rets, na.rm=TRUE)
  post_sr <- srf(pr[date>=post2017, act_bm]); full_sr <- srf(pr$act_bm)
  post_t  <- nwt(pr[date>=post2017, act_bm])
  data.table(model=lab, port_t_capwt=pt_bm, port_t_EWuni=pt,
             oos_retention=retn, calmar=cal, mdd=dd, ann_ret=ann,
             post2017_bm_sr=post_sr, post2017_t=post_t, full_bm_sr=full_sr,
             net_sr=cs$net_sr, ir=cs$information_ratio,
             turnover=cs$turnover_annual, n_months=nrow(pr))
}

## ── ① 개별 sleeve 독립 게이트 (11개) + rank-IC ──
w("=== Phase-1: 11 직교 sleeve 개별 배포-envelope 실측 (cap-w authoritative) ===")
per <- list(); ric <- list()
for(fm in FAMS){
  tryCatch({
    sub <- gw[!is.na(get(fm)), .(signal_date, security_id, score=get(fm))]
    sub[, score := zc(score), by=signal_date]
    r <- gates(sub, paste0("sleeve_",fm))
    ri <- rank_ic_stats(sub)
    if(!is.null(r)){
      r[, `:=`(rank_ic=ri$ic, icir=ri$icir, harvey_t=ri$harvey_t)]
      per[[fm]] <- r
      w(sprintf("  %-16s PORTt=%+.2f (EW=%+.2f) rankIC=%+.3f ICIR=%+.2f Ht=%+.2f oos=%+.2f cal=%+.2f post17_t=%+.2f TO=%.0f%%",
                fm, r$port_t_capwt, r$port_t_EWuni, ri$ic, ri$icir, ri$harvey_t,
                r$oos_retention, r$calmar, r$post2017_t, r$turnover*100))
    }
  }, error=function(e) w(sprintf("  [SLEEVE ERR %s] %s", fm, conditionMessage(e))))
}
PER <- rbindlist(per, fill=TRUE)
setorder(PER, -port_t_capwt)

## ── ② 판정 ──
GATE_PT <- 2.95
PER[, verdict := fifelse(is.finite(port_t_capwt) & port_t_capwt>=GATE_PT &
                         is.finite(oos_retention) & oos_retention>=0.7 &
                         is.finite(calmar) & calmar>=0.64, "HARD_PASS",
                  fifelse(is.finite(port_t_capwt) & port_t_capwt>=GATE_PT, "PORTt_only",
                  fifelse(is.finite(port_t_capwt) & port_t_capwt>=1.5, "screen-tier", "FAIL")))]
survivors <- PER[port_t_capwt>=GATE_PT, model]

w(sprintf("\n=== 판정: HARD(PORTt>=%.2f ∧ oos>=0.7 ∧ cal>=0.64) 통과 = %d / PORTt>=%.2f = %d ===",
          GATE_PT, PER[verdict=="HARD_PASS",.N], GATE_PT, length(survivors)))
w(sprintf("PORT_t 분포: max=%+.2f median=%+.2f min=%+.2f", max(PER$port_t_capwt,na.rm=T),
          median(PER$port_t_capwt,na.rm=T), min(PER$port_t_capwt,na.rm=T)))

## ── 저장 ──
write_parquet(PER, file.path(OUT, "alpha_scores.parquet"))
saveRDS(list(PER=PER, PINTAG=PINTAG, sig_dates=sig_dates, FAMS=FAMS),
        file.path(OUT, "sleeve_screening.rds"))
w("\n=== VERDICT ===")
any_pass <- length(survivors) > 0
w(sprintf("개별 sleeve HARD 통과 %d / PORTt통과 %d / 11. => %s",
   PER[verdict=="HARD_PASS",.N], length(survivors),
   if(any_pass) "SURVIVOR 존재 → multi-sleeve 스택 후속" else
   "통과 0 → §6 음성: 개별 배포 스크리닝도 IC→PORT_t 전이 벽"))
close(con)
cat(sprintf("SCREEN_DONE. pin=%s log=%s\n", PINTAG, logf))
cat(readLines(logf), sep="\n")
