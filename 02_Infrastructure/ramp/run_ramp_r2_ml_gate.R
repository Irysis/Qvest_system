## run_ramp_r2_ml_gate.R — RAMP R2 Track B: ML(lgbm) 국면조건부 종목스코어 cap-w 게이트 실측
## DIST-RAMP-006 미검증 프론티어. r2_ml_scores.parquet(Python lgbm 산출)을 canonical_screen_bt로
## → cap-w PORT_t · oos_retention v2 · calmar · post2017 SR. R1 gates() 산식 완전 복제.
## ★실측-only(canonical_screen_bt) · 자체합성 금지 · 단일스레드 · metric_type=canonical_screen.
## Σ/weight 결정 없음 — 스코어→top-25 EW long-only 측정만.
suppressPackageStartupMessages({library(data.table); library(arrow); library(sandwich); library(lmtest)})
setDTthreads(1); try(arrow::set_cpu_count(1),silent=TRUE); try(arrow::set_io_thread_count(2),silent=TRUE)
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
source("02_Infrastructure/config.R")
source("02_Infrastructure/ramp/factor_validation.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")
OUT <- "outputs/ramp"; RUNTAG <- format(Sys.Date(),"%Y%m%d")
logf <- file.path(".cache", sprintf("_ramp_r2_gate_%s.txt", RUNTAG))
con <- file(logf,"w",encoding="UTF-8"); w<-function(...) writeLines(paste0(...),con)

## ── 데이터 (R1과 동일 forward/bench/liq — export된 slim 기반) ──
sc <- as.data.table(read_parquet(file.path(OUT,"r2_ml_scores.parquet"))); sc[,signal_date:=as.Date(signal_date)]
fwd_ret  <- as.data.table(read_parquet(".cache/_ramp_r2_fwd_ret.parquet")); fwd_ret[,signal_date:=as.Date(signal_date)]
bench_dt <- as.data.table(read_parquet(".cache/_ramp_r2_bench.parquet")); bench_dt[,signal_date:=as.Date(signal_date)]
liq_dt   <- as.data.table(read_parquet(".cache/_ramp_r2_liq.parquet")); liq_dt[,signal_date:=as.Date(signal_date)]

returns_dt <- fwd_ret[, .(Date=signal_date, Ticker=security_id, Ret_1m)]
bench_D    <- bench_dt[, .(Date=signal_date, BM_Ret)]
liq_D      <- liq_dt[, .(Date=signal_date, Ticker=security_id, adv)]
ewb <- returns_dt[, .(ew=mean(Ret_1m,na.rm=TRUE)), by=.(date=as.Date(Date))]   # EW-uni 벤치(진단)
post2017 <- as.Date("2017-01-01")

## ── 게이트 계산기 (R1 gates() 완전 복제; cap-w authoritative) ──
srf <- function(x){ x<-x[is.finite(x)]; if(length(x)<6) return(NA); mean(x)/sd(x)*sqrt(12) }
nwt <- function(x){ x<-x[is.finite(x)]; if(length(x)<12) return(NA)
  m<-lm(x~1); as.numeric(coeftest(m, vcov=sandwich::NeweyWest(m,lag=3,prewhite=FALSE))[1,3]) }
gates <- function(score_dt, lab){
  cs <- tryCatch(canonical_screen_bt(
        score_dt[,.(Date=as.Date(signal_date), Ticker=security_id, score)],
        returns_dt, bench_D, top_n=25L, cost_bps_oneway=15,
        liq_dt=liq_D, liq_min=2e8,
        run_id="r2ml", strategy_id=lab), error=function(e){ w("  [gates ERR ",lab,"] ",conditionMessage(e)); NULL })
  if(is.null(cs) || is.null(cs$period_returns)) return(NULL)
  pr <- as.data.table(cs$period_returns); pr[,date:=as.Date(date)]
  pr <- merge(pr, ewb, by="date", all.x=TRUE)
  pr[, act := ret_net - ew]                      # EW-uni active (진단)
  pr[, act_bm := ret_net - benchmark_ret]        # cap-w active (authoritative)
  pt      <- nwt(pr$act)
  pt_bm   <- nwt(pr$act_bm)
  nav <- cumprod(1+pr$ret_net); dd <- min(nav/cummax(nav)-1); ann <- prod(1+pr$ret_net)^(12/nrow(pr))-1
  cal <- if(dd<0) ann/abs(dd) else NA
  .splits<-c(0.55,0.65,0.75); .rets<-sapply(.splits,function(fr){ k<-floor(nrow(pr)*fr)
    if(k<12||(nrow(pr)-k)<6) return(NA_real_); .is<-srf(pr$act_bm[1:k]); .oo<-srf(pr$act_bm[(k+1):nrow(pr)])
    if(!is.na(.is)&&.is>0) .oo/.is else NA_real_ })
  retn <- median(.rets, na.rm=TRUE)
  post_sr <- srf(pr[date>=post2017, act_bm])
  full_bm_sr <- srf(pr$act_bm)
  list(dt=data.table(model=lab, port_t_EWuni=pt, port_t_capwt=pt_bm, oos_retention=retn,
             calmar=cal, post2017_bm_sr=post_sr, full_bm_sr=full_bm_sr,
             turnover=cs$turnover_annual, n_months=nrow(pr), net_sr=cs$net_sr),
       pr=pr)
}

GATE_PT<-2.95; GATE_OOS<-0.7; GATE_CAL<-0.64
w("=== RAMP R2 Track B: lgbm 국면조건부 ML 스코어 cap-w 게이트 (canonical_screen) ===")
res <- gates(sc, "r2_lgbm_regime_cond")
if(is.null(res)){ w("GATE NULL — screen 실패"); close(con); cat(readLines(logf),sep="\n"); stop("gate null") }
R <- res$dt; PR <- res$pr
w(sprintf("  n_months=%d  turnover=%.1f  net_sr=%.3f", R$n_months, R$turnover, R$net_sr))
w(sprintf("  port_t_capwt = %+.3f   (GATE %.2f  -> %s)", R$port_t_capwt, GATE_PT, ifelse(R$port_t_capwt>=GATE_PT,"PASS","FAIL")))
w(sprintf("  port_t_EWuni = %+.3f   (진단)", R$port_t_EWuni))
w(sprintf("  oos_retention= %+.3f   (GATE %.2f  -> %s)", R$oos_retention, GATE_OOS, ifelse(is.finite(R$oos_retention)&R$oos_retention>=GATE_OOS,"PASS","FAIL")))
w(sprintf("  calmar       = %+.3f   (GATE %.2f  -> %s)", R$calmar, GATE_CAL, ifelse(R$calmar>=GATE_CAL,"PASS","FAIL")))
w(sprintf("  post2017 cap-w SR = %+.3f  (full=%+.3f)", R$post2017_bm_sr, R$full_bm_sr))

## ── look-ahead 자가검증: lag1 스트레스 (스코어를 1개월 지연 → 신호가 우연/누출이면 급락, 진짜면 완만) ──
w("\n=== look-ahead 자가검증: lag1 스트레스 (score를 t+1로 강제 지연) ===")
sc_lag <- copy(sc); setorder(sc_lag, security_id, signal_date)
sc_lag[, sd_next := shift(signal_date, -1, type="shift"), by=security_id]  # 이 score를 다음달에 사용
sc_lag2 <- sc_lag[!is.na(sd_next), .(signal_date=sd_next, security_id, score)]
res_lag <- gates(sc_lag2, "r2_lgbm_lag1")
if(!is.null(res_lag)){
  RL<-res_lag$dt
  w(sprintf("  lag1 port_t_capwt=%+.3f (base %+.3f, Δ=%+.3f)  oos=%+.3f  cal=%+.3f  post17=%+.3f",
     RL$port_t_capwt, R$port_t_capwt, RL$port_t_capwt-R$port_t_capwt, RL$oos_retention, RL$calmar, RL$post2017_bm_sr))
  w("  해석: lag1이 base와 유사(급락 아님)=신호 실재/누출 아님; base≫lag1 급락=최근성 의존/누출 의심")
}

## ── R1 선형 baseline 대비 ──
w("\n=== R1 선형 baseline 대비 ===")
w("  R1 linear best (stack_EW):  port_t_capwt=+2.538  oos=-0.314  cal=0.393  post17=-0.257")
w("  R1 linear InvVol:           port_t_capwt=+2.459  oos=-0.314  cal=0.391  post17=-0.296")
w(sprintf("  R2 ML lgbm regime-cond:     port_t_capwt=%+.3f  oos=%+.3f  cal=%.3f  post17=%+.3f",
   R$port_t_capwt, R$oos_retention, R$calmar, R$post2017_bm_sr))
w(sprintf("  Δ(ML - linear best): port_t = %+.3f", R$port_t_capwt - 2.538))

## ── 결과 저장 ──
gate_pass <- (R$port_t_capwt>=GATE_PT) && (is.finite(R$oos_retention)&&R$oos_retention>=GATE_OOS) && (R$calmar>=GATE_CAL)
res_out <- list(
  model="r2_lgbm_regime_cond", metric_type="canonical_screen",
  port_t_capwt=R$port_t_capwt, port_t_EWuni=R$port_t_EWuni,
  oos_retention=R$oos_retention, calmar=R$calmar,
  post2017_bm_sr=R$post2017_bm_sr, full_bm_sr=R$full_bm_sr,
  net_sr=R$net_sr, turnover=R$turnover, n_months=R$n_months,
  lag1_stress=if(!is.null(res_lag)) list(port_t_capwt=res_lag$dt$port_t_capwt,
     delta_vs_base=res_lag$dt$port_t_capwt-R$port_t_capwt) else NULL,
  gate=list(pt=GATE_PT, oos=GATE_OOS, cal=GATE_CAL, pass=gate_pass),
  linear_baseline=list(stack_EW_pt=2.538, stack_InvVol_pt=2.459),
  delta_vs_linear_best=R$port_t_capwt-2.538)
jsonlite::write_json(res_out, file.path(OUT, sprintf("r2_ml_gate_%s.json",RUNTAG)),
                     auto_unbox=TRUE, pretty=TRUE, digits=4)
write_parquet(PR[,.(date,ret_net,benchmark_ret,act_bm)], file.path(OUT,"r2_ml_period_returns.parquet"))

w("\n=== VERDICT ===")
w(sprintf("  게이트(2.95/0.7/0.64) 통과: %s", ifelse(gate_pass,"PASS","FAIL")))
w(sprintf("  선형 select-stack(2.54) 초과: %s (Δ=%+.3f)",
   ifelse(R$port_t_capwt>2.538,"YES","NO"), R$port_t_capwt-2.538))
w(sprintf("  => %s", if(gate_pass) "ML 국면조건부가 게이트 통과 → book-marginal 후속" else
   "게이트 미통과: 비선형·국면조건부도 동일 벽 (또는 선형 초과하나 자본 미달)"))
close(con); cat(sprintf("R2_GATE_DONE. json=%s\n", file.path(OUT, sprintf("r2_ml_gate_%s.json",RUNTAG))))
cat(readLines(logf), sep="\n")
