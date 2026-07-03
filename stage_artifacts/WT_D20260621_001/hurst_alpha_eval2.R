#==============================================================================
# Stage 2b: re-eval with FIXED benchmark (real KOSPI200 TR) + fixed M08.
#==============================================================================
Sys.setenv(OMP_NUM_THREADS="1", OPENBLAS_NUM_THREADS="1", MKL_NUM_THREADS="1",
           R_DATATABLE_NUM_THREADS="1")
suppressMessages({ library(data.table); library(jsonlite) })
setDTthreads(1L)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(ROOT)
OUT_A <- file.path(ROOT, "stage_artifacts", "WT_D20260621_001")
LOG <- function(...) cat(sprintf("[%s] ", format(Sys.time(),"%H:%M:%S")), ..., "\n")
source(file.path(ROOT, "02_Infrastructure/contracts/backtest_result_contract.R"))
source(file.path(ROOT, "02_Infrastructure/contracts/canonical_screen_bt.R"))

panel    <- readRDS(file.path(OUT_A, "panel_fixed.rds"))
bench_dt <- readRDS(file.path(OUT_A, "bench_fwd_fixed.rds"))
LOG("panel:", nrow(panel), " bench:", nrow(bench_dt), " BM mean:", round(mean(bench_dt$BM_Ret),4))

zc <- function(v){ m<-mean(v,na.rm=TRUE); s<-sd(v,na.rm=TRUE)
  if(!is.finite(s)||s<1e-12) return(rep(NA_real_,length(v)))
  z<-(v-m)/s; pmax(pmin(z,3),-3) }
for (col in c("M01","M08","M13","H252","H126","H504","HRS252"))
  panel[, paste0("z_",col) := zc(get(col)), by=Date]

# Hurst sanity
hsum <- panel[is.finite(H252), .(mean_H=mean(H252), med_H=median(H252), sd_H=sd(H252),
              q10=quantile(H252,.1), q90=quantile(H252,.9), frac_persistent=mean(H252>0.5), n=.N)]
dfa_rs_cor <- panel[is.finite(H252)&is.finite(HRS252), cor(H252,HRS252)]

# Orthogonality (avg cross-sec Spearman)
xcorr <- function(a,b){ d<-panel[is.finite(get(a))&is.finite(get(b))]
  cs<-d[,.(c=if(.N>=10) cor(get(a),get(b),method="spearman") else NA_real_),by=Date]
  mean(cs$c,na.rm=TRUE) }
orth <- list(H252_vs_M01=xcorr("H252","M01"), H252_vs_M08=xcorr("H252","M08"),
             H252_vs_M13=xcorr("H252","M13"), H126_vs_M01=xcorr("H126","M01"),
             H504_vs_M01=xcorr("H504","M01"),
             M01_vs_M08=xcorr("M01","M08"), M01_vs_M13=xcorr("M01","M13"))
LOG("Hurst:"); print(hsum); LOG("DFA-RS cor:", round(dfa_rs_cor,3))
LOG("Orthogonality:"); print(orth)

gH <- function(H) 1 + pmax(pmin((H-0.5)/0.5,1),-1)
panel[, sig_a := z_M01*gH(H252)]
panel[, mom_gated := fifelse(H252>=0.5, M01, -M01)]; panel[, sig_b := zc(mom_gated), by=Date]
panel[, sig_c := z_H252]
panel[, sig_d := z_M01]
panel[, sig_a126 := z_M01*gH(H126)]
panel[, sig_a504 := z_M01*gH(H504)]
panel[, sig_e := 0.7*z_M01 + 0.3*z_H252]

nw_t <- function(x,lag=3L){ x<-x[is.finite(x)]; n<-length(x); if(n<lag+2L) return(NA_real_)
  mu<-mean(x); e<-x-mu; g0<-sum(e^2)/n; s<-g0
  for(l in 1:lag){w<-1-l/(lag+1); g<-sum(e[(l+1):n]*e[1:(n-l)])/n; s<-s+2*w*g}
  if(s<=0) return(NA_real_); mu/sqrt(s/n) }
ic_diag <- function(sigcol){
  d<-panel[is.finite(get(sigcol))&is.finite(Ret_1m)]
  ics<-d[,.(ic=if(.N>=10) cor(get(sigcol),Ret_1m,method="spearman") else NA_real_),by=Date]
  ics<-ics[is.finite(ic)]; ics<-ics[order(Date)]
  n<-nrow(ics); mic<-mean(ics$ic); sic<-sd(ics$ic); icir_m<-mic/sic
  ics[, era := fifelse(Date<as.Date("2013-01-01"),"e1",fifelse(Date<as.Date("2019-01-01"),"e2","e3"))]
  era_ic<-ics[,.(ic=mean(ic),n=.N),by=era][order(era)]
  list(rank_ic=mic, ic_sd=sic, icir_monthly=icir_m, icir_annualized=icir_m*sqrt(12),
       n_months=n, ic_t_plain=mic/sic*sqrt(n), harvey_t_nw3=nw_t(ics$ic,3L),
       frac_pos=mean(ics$ic>0), era_ic=era_ic,
       sign_stability=mean(sign(era_ic$ic)==sign(mic)))
}
signals <- c(a="sig_a", b="sig_b", c="sig_c", d_baseline="sig_d",
             a126="sig_a126", a504="sig_a504", e_additive="sig_e")
diag_all <- lapply(signals, ic_diag)
LOG("IC diagnostics:")
for(nm in names(diag_all)){x<-diag_all[[nm]]
  LOG(sprintf("  %-12s ic=%.4f icir_m=%.3f harvey_t=%.2f n=%d frac_pos=%.2f sgnstab=%.2f",
      nm,x$rank_ic,x$icir_monthly,x$harvey_t_nw3,x$n_months,x$frac_pos,x$sign_stability))}

ret_dt <- panel[is.finite(Ret_1m), .(Date,Ticker,Ret_1m)]
liq_dt <- panel[is.finite(adv), .(Date,Ticker,adv)]
run_screen <- function(sigcol){
  sc<-panel[is.finite(get(sigcol)), .(Date,Ticker,score=get(sigcol))]
  canonical_screen_bt(sc, ret_dt, bench_dt, top_n=25L, cost_bps_oneway=15,
                      liq_dt=liq_dt, liq_min=2e8,
                      run_id=paste0("hurst_",sigcol), strategy_id=paste0("hurst_",sigcol))
}
screen_all<-list(); for(nm in names(signals)){LOG("screen:",nm); screen_all[[nm]]<-run_screen(signals[[nm]])}
scr_tab<-rbindlist(lapply(names(screen_all),function(nm){r<-screen_all[[nm]]
  data.table(signal=nm,n_months=r$n_months,port_alpha_t_nw3=r$portfolio_alpha_t_nw_lag3,
    IR=r$information_ratio,alpha_ann=r$alpha_annualized,net_sr=r$net_sr,
    mean_active_net=r$mean_active_net,turnover_ann=r$turnover_annual)}),fill=TRUE)
LOG("Canonical screen (top25 EW long-only, 15bps, liq 2e8, REAL KOSPI200 benchmark):")
print(scr_tab)

# --- DSR (diagnostic, chain selection — advisory) for a504 & baseline using net_sr & n_trials
# We treat this as hypothesis-driven A/B (chain), so DSR is advisory/diagnostic only.
# Bailey-LdP DSR via net monthly active series of the chosen signal.
dsr_calc <- function(active, n_trials){
  active<-active[is.finite(active)]; n<-length(active); if(n<24) return(NA_real_)
  sr<-mean(active)/sd(active); g1<-mean((active-mean(active))^3)/sd(active)^3
  g2<-mean((active-mean(active))^4)/sd(active)^4
  # expected max SR under n_trials (Bailey-LdP)
  emc<-0.5772156649; sr0<-sqrt(1/(n-1))*( (1-emc)*qnorm(1-1/n_trials)+emc*qnorm(1-1/(n_trials*exp(1))) )
  num<-(sr-sr0)*sqrt(n-1); den<-sqrt(1 - g1*sr + (g2-1)/4*sr^2)
  pnorm(num/den)
}
# n_trials counts operationalizations actually tried (chain of 7) — diagnostic
dsr_a504 <- dsr_calc(screen_all[["a504"]]$period_returns[, ret_net]-screen_all[["a504"]]$period_returns[, benchmark_ret], 7)
dsr_base <- dsr_calc(screen_all[["d_baseline"]]$period_returns[, ret_net]-screen_all[["d_baseline"]]$period_returns[, benchmark_ret], 7)
LOG("DSR (advisory, chain n_trials=7): a504=", round(dsr_a504,3), " baseline=", round(dsr_base,3))

# incremental test: does a504 beat baseline? paired diff of monthly active
act_a504 <- screen_all[["a504"]]$period_returns[, ret_net - benchmark_ret]
act_base <- screen_all[["d_baseline"]]$period_returns[, ret_net - benchmark_ret]
delta <- act_a504 - act_base
LOG(sprintf("a504 vs baseline monthly active diff: mean=%.5f t=%.2f (a504 NOT meaningfully > baseline if |t|<2)",
    mean(delta), mean(delta)/sd(delta)*sqrt(length(delta))))

saveRDS(list(hsum=hsum,dfa_rs_cor=dfa_rs_cor,orth=orth,
  diag_all=lapply(diag_all,function(x)x),
  screen_tab=scr_tab, dsr_a504=dsr_a504, dsr_base=dsr_base,
  delta_mean=mean(delta), delta_t=mean(delta)/sd(delta)*sqrt(length(delta))),
  file.path(OUT_A,"eval_results_fixed.rds"))

# alpha_scores.parquet — write chosen signal (a504, best-of-Hurst) + baseline for the last sig_date panel
suppressMessages(library(arrow))
last_d <- max(panel$Date)
scores_out <- panel[Date==last_d, .(Date, Ticker, H252, H126, H504, M01,
   z_M01, z_H252, sig_a504_score=sig_a504, sig_d_baseline=sig_d, confidence=NA_real_)]
write_parquet(scores_out, file.path(OUT_A,"alpha_scores.parquet"))
# also full time series of chosen signal for downstream
full_scores <- panel[is.finite(sig_a504), .(Date, Ticker, score_a504=sig_a504, score_baseline=sig_d, H252)]
write_parquet(full_scores, file.path(OUT_A,"alpha_scores_fullts.parquet"))
LOG("Saved eval_results_fixed.rds + alpha_scores.parquet (n last-month=", nrow(scores_out),")")
LOG("DONE stage 2b.")
