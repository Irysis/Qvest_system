## =============================================================================
## WT-012 probe: hawkes_own_crash_overlay
##   진단 정면공략 (wt012): EVT market tail-ES가 momentum 포트 *자체* crash를
##   타이밍 못함(corr −0.086). → 포트-자체 월수익의 self-exciting(Hawkes) crash
##   intensity λ(t)로 de-risk. calmar 개선 + upside 보존하나?
##   비교: (a) Hawkes-only overlay  (b) Hawkes × 현 M4∩AE 게이트 (add하나)
##   PIT: intensity는 t-1까지 포트 실현수익만. lag1·placebo(random-exposure) 대조.
##   측정: weighted_screen_bt(exposure_dt) + .calmar_of (PerformanceAnalytics, 벤치-불변)
## =============================================================================
suppressMessages({library(data.table); library(arrow); library(PerformanceAnalytics); library(xts); library(jsonlite)})
setDTthreads(1); set.seed(20260719)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(ROOT)
source(file.path(ROOT,"04_Research/method_frontier/wt006_exog_forecast/eval_harness.R"))
source(file.path(ROOT,"02_Infrastructure/contracts/weighted_screen_bt.R"))

`%||%` <- function(a,b) if(is.null(a)||length(a)==0||is.na(a)) b else a

## ---- 0. base momentum: reconstruct top-25 EW W_dt (canonical과 동일 selection) ----
mom_score <- .score_from_theta(.mom_theta)                          # Date,Ticker,score
base_res  <- .canon(mom_score)                                      # canonical 실측 (anchor)
S <- as.data.table(mom_score)[!is.na(score)]
S <- S[Date %in% .Rg$Date & Date %in% .oos_dates]
S <- merge(S, .LQg[,.(Date,Ticker,adv)], by=c("Date","Ticker"), all.x=TRUE)
S <- S[is.na(adv) | adv >= 2e8]; S[, adv:=NULL]
setorder(S, Date, -score)
W_dt <- S[, { n<-min(25L,.N); .(Ticker=Ticker[seq_len(n)], w=rep(1/n,n)) }, by=Date]
R_dt <- .Rg[,.(Date,Ticker,Ret_1m)]; BM_dt <- .BMg[,.(Date,BM_Ret)]

base_ws <- weighted_screen_bt(W_dt, R_dt, BM_dt, cost_bps_oneway=15, run_id="mom_base")
base_pr <- as.data.table(base_ws$period_returns)                   # date, ret_net, benchmark_ret
cat(sprintf("[parity] canon PORT_t=%.3f | ws PORT_t=%.3f | ws calmar=%.3f MDD=%.4f n=%d\n",
    base_res$portfolio_alpha_t_nw_lag3, base_ws$portfolio_alpha_t_nw_lag3,
    .calmar_of(base_pr), as.numeric(maxDrawdown(xts(base_pr$ret_net,order.by=base_pr$date))), nrow(base_pr)))

## ---- 1. own-return self-exciting crash intensity (PIT: t-1까지 포트수익만) ----
setorder(base_pr, date)
r <- base_pr$ret_net; dt_all <- base_pr$date; n <- length(r)
loss <- pmax(0, -r)                                                 # 하방 loss magnitude (own)

## 1a. parameter-free causal Hawkes(지수커널) intensity: λ_t = w·λ_{t-1} + loss_{t-1}
##     w=exp(-log2/H). loss_{t-1}=전월 실현 loss(월 t 시작 시 known) → 순수 causal.
hawkes_ewma <- function(loss, H){ w <- exp(-log(2)/H); lam <- numeric(length(loss))
  for(t in 2:length(loss)) lam[t] <- w*lam[t-1] + loss[t-1]; lam }         # lam[1]=0 (no past)
H_PRIMARY <- 3L
lam <- hawkes_ewma(loss, H_PRIMARY)

## 1b. Hawkes MLE (자기여기 존재 여부 descriptive stat) — 지수커널 point process on crash months.
##     crash event = ret_net < expanding-median − 1·expanding-sd (causal flag, burn=24).
##     branching ratio n*=α/β>0 이면 자기여기 실재. full-sample fit(서술용)·overlay엔 미사용.
burn <- 24L
ev <- rep(FALSE, n)
for(t in (burn+1):n){ h<-r[1:(t-1)]; thr<-median(h)-1*sd(h); if(is.finite(thr) && r[t]<thr) ev[t]<-TRUE }
ev_times <- which(ev)                                              # month index of crashes
hawkes_negll <- function(par, tt, T){ mu<-exp(par[1]); a<-exp(par[2]); b<-exp(par[3])
  if(b<=0) return(1e10)
  # intensity at each event from prior events
  ll <- 0; comp <- mu*T
  for(i in seq_along(tt)){ past<-tt[tt<tt[i]]; lam_i<-mu + a*sum(exp(-b*(tt[i]-past))); ll<-ll+log(lam_i) }
  comp <- comp + (a/b)*sum(1-exp(-b*(T-tt)))
  -(ll - comp) }
hawkes_stat <- tryCatch({
  if(length(ev_times) < 5) list(ok=FALSE, note="too few crash events") else {
    op <- optim(c(log(length(ev_times)/n), log(0.3), log(0.5)), hawkes_negll, tt=ev_times, T=n,
                method="L-BFGS-B", lower=c(-10,-10,-6), upper=c(2,3,3))
    mu<-exp(op$par[1]); a<-exp(op$par[2]); b<-exp(op$par[3])
    list(ok=TRUE, mu=mu, alpha=a, beta=b, branching_ratio=a/b, n_events=length(ev_times),
         halflife_mo=log(2)/b) }
}, error=function(e) list(ok=FALSE, note=conditionMessage(e)))

## ---- 2. exposure map (causal): expanding-z 표준화 후 de-risk (never lever up) ----
##   z_t = (λ_t − mean(λ_{burn..t-1}))/sd(...). exposure = clip(1 − g·max(0,z_t), floor, 1).
##   a-priori 중앙 파라미터: g=0.5, floor=0.3 (verdict). robustness 그리드 병기(argmax-select 아님).
make_exposure <- function(lam, g=0.5, floor=0.3, burn=24L){
  n<-length(lam); z<-numeric(n)
  for(t in 2:n){ h<-lam[max(1,t-1)]; hist<-lam[1:(t-1)]; hist<-hist[is.finite(hist)]
    if(length(hist)>=burn){ m<-mean(hist); s<-sd(hist); z[t]<- if(is.finite(s)&&s>0) (lam[t]-m)/s else 0 } else z[t]<-0 }
  exposure <- pmin(1, pmax(floor, 1 - g*pmax(0,z))); exposure }
exp_primary <- make_exposure(lam, g=0.5, floor=0.3, burn=burn)
exposure_dt <- data.table(Date=dt_all, exposure=exp_primary)

## ---- 3. measurement helper ----
measure <- function(exp_vec, label){
  ed <- data.table(Date=dt_all, exposure=exp_vec)
  res <- weighted_screen_bt(W_dt, R_dt, BM_dt, cost_bps_oneway=15, run_id=label, exposure_dt=ed)
  pr <- as.data.table(res$period_returns)
  x <- xts(pr$ret_net, order.by=pr$date)
  list(label=label, port_t=round(res$portfolio_alpha_t_nw_lag3,3),
       calmar=round(.calmar_of(pr),4), mdd=round(as.numeric(maxDrawdown(x)),4),
       cagr=round(as.numeric(Return.annualized(x,scale=12,geometric=TRUE)),4),
       net_sr=round(res$net_sr,3), turnover=round(res$turnover_annual,2),
       mean_exp=round(mean(exp_vec),3), frac_derisk=round(mean(exp_vec<0.999),3)) }

base_m   <- measure(rep(1,n), "base_mom")
hawkes_m <- measure(exp_primary, "hawkes_only")

## ---- 4. (b) M4∩AE 게이트 재구성 + 결합 ----
ym_of <- function(d) as.integer(format(as.Date(d),"%Y%m"))
m4 <- as.data.table(read_parquet(file.path(ROOT,"qepm/mailbox/worktask/WT-D20260430_001/stage_artifacts/alpha_scores.parquet")))
m4[,Date:=as.Date(Date)]; m4u <- unique(m4[,.(ym=ym_of(Date), w_m4=weight_str1715)])[order(ym)]
m4u <- m4u[, .(w_m4=w_m4[1]), by=ym]
ae <- as.data.table(read_parquet(file.path(ROOT,"stage_artifacts/WT_D20260718_007/ae_regime_signal_ext.parquet")))
ae[,decision_date:=as.Date(decision_date)]; aeu <- unique(ae[,.(ym=ym_of(decision_date), fire=fire_seq)])[order(ym)]
aeu <- aeu[, .(fire=max(fire,na.rm=TRUE)), by=ym]
gate_dt <- data.table(Date=dt_all, ym=ym_of(dt_all))
gate_dt <- merge(gate_dt, m4u, by="ym", all.x=TRUE); gate_dt <- merge(gate_dt, aeu, by="ym", all.x=TRUE)
gate_dt[is.na(w_m4), w_m4:=1]; gate_dt[is.na(fire), fire:=0]
gate_dt[, m4_fires := as.integer(w_m4 < 0.999)]
gate_dt[, gate := fifelse(m4_fires==1L & fire==1L, 0.70, 1.00)]
setorder(gate_dt, Date)
exp_gate <- gate_dt$gate
exp_combo <- exp_gate * exp_primary                                  # 곱셈 결합
gate_m  <- measure(exp_gate, "m4ae_gate_only")
combo_m <- measure(exp_combo, "hawkes_x_m4ae")

## ---- 5. PIT self-checks ----
## 5a. lag1 스트레스: exposure를 1개월 추가 shift (t-2 정보 사용) → base보다 좋으면 누출 의심
exp_lag1 <- c(1, exp_primary[-n])
lag1_m <- measure(exp_lag1, "hawkes_lag1")
## 5b. placebo: exposure multiset을 무작위 permute (평균 de-risk 동일, 타이밍 파괴). 300 seeds.
placebo_cal <- numeric(300)
for(s in 1:300){ set.seed(1000+s); ep <- sample(exp_primary); placebo_cal[s] <- .calmar_of(
  as.data.table(weighted_screen_bt(W_dt,R_dt,BM_dt,cost_bps_oneway=15,run_id="plc",
    exposure_dt=data.table(Date=dt_all,exposure=ep))$period_returns)) }
plc_p95 <- as.numeric(quantile(placebo_cal,0.95,na.rm=TRUE)); plc_p50<-as.numeric(quantile(placebo_cal,0.5,na.rm=TRUE))
plc_rank <- mean(placebo_cal < hawkes_m$calmar)                     # actual가 placebo 분포 상위 몇%
## 5c. timing corr: exposure_t vs 동월 own ret_net (양수 = de-risk이 crash월과 정렬 = good timing)
timing_corr <- cor(exp_primary, r)
## de-risk 시점 다음달 수익 (EVT 실패 진단 재현: EVT는 de-risk tercile이 최고수익)
derisk <- 1 - exp_primary
corr_derisk_ownret <- cor(derisk, r)                               # 음수 원함 (de-risk ↔ 저수익)

## ---- 6. robustness 그리드 (sign-stability, argmax-select 아님) ----
grid <- CJ(H=c(2L,3L,6L), g=c(0.3,0.5,0.7), floor=c(0.2,0.3,0.5))
grid_res <- rbindlist(lapply(1:nrow(grid), function(i){
  lm <- hawkes_ewma(loss, grid$H[i]); ev <- make_exposure(lm, g=grid$g[i], floor=grid$floor[i], burn=burn)
  m <- measure(ev, sprintf("H%d_g%.1f_f%.1f",grid$H[i],grid$g[i],grid$floor[i]))
  data.table(H=grid$H[i], g=grid$g[i], floor=grid$floor[i], calmar=m$calmar, port_t=m$port_t, mdd=m$mdd, cagr=m$cagr) }))
setorder(grid_res, -calmar)

## ---- 7. verdict ----
improves_calmar <- hawkes_m$calmar > base_m$calmar
beats_placebo   <- hawkes_m$calmar > plc_p95
lag1_clean      <- lag1_m$calmar <= hawkes_m$calmar + 0.02          # lag1이 base보다 크게 좋지 않아야
combo_adds      <- combo_m$calmar > gate_m$calmar

out <- list(
  probe="hawkes_own_crash_overlay",
  base=base_m, hawkes_only=hawkes_m, m4ae_gate_only=gate_m, hawkes_x_m4ae=combo_m,
  hawkes_mle=hawkes_stat,
  pit=list(lag1=lag1_m, lag1_clean=lag1_clean,
           placebo_p50=round(plc_p50,4), placebo_p95=round(plc_p95,4),
           placebo_rank_of_actual=round(plc_rank,3), beats_placebo=beats_placebo,
           timing_corr_exp_ownret=round(timing_corr,4),
           corr_derisk_ownret=round(corr_derisk_ownret,4)),
  grid_top=head(grid_res,5), grid_full=grid_res,
  verdict=list(improves_calmar=improves_calmar, gate_reached=hawkes_m$calmar>=0.64,
               beats_placebo=beats_placebo, combo_adds=combo_adds, lag1_clean=lag1_clean))
dir.create(file.path(ROOT,"04_Research/method_frontier/wt012_hawkes"), showWarnings=FALSE, recursive=TRUE)
write_json(out, file.path(ROOT,"04_Research/method_frontier/wt012_hawkes/hawkes_results.json"),
           auto_unbox=TRUE, pretty=TRUE, digits=6)

cat("\n================ HAWKES OWN-CRASH OVERLAY ================\n")
cat(sprintf("BASE momentum   : calmar=%.4f MDD=%.4f CAGR=%.4f PORT_t=%.3f\n", base_m$calmar,base_m$mdd,base_m$cagr,base_m$port_t))
cat(sprintf("HAWKES-only     : calmar=%.4f MDD=%.4f CAGR=%.4f PORT_t=%.3f | mean_exp=%.3f derisk_frac=%.3f\n",
    hawkes_m$calmar,hawkes_m$mdd,hawkes_m$cagr,hawkes_m$port_t,hawkes_m$mean_exp,hawkes_m$frac_derisk))
cat(sprintf("M4AE-gate only  : calmar=%.4f MDD=%.4f CAGR=%.4f PORT_t=%.3f | derisk_frac=%.3f\n",
    gate_m$calmar,gate_m$mdd,gate_m$cagr,gate_m$port_t,gate_m$frac_derisk))
cat(sprintf("HAWKES x M4AE   : calmar=%.4f MDD=%.4f CAGR=%.4f PORT_t=%.3f\n", combo_m$calmar,combo_m$mdd,combo_m$cagr,combo_m$port_t))
cat(sprintf("\nHawkes MLE      : ok=%s branching_ratio(n*)=%s halflife_mo=%s n_events=%s\n",
    hawkes_stat$ok, round(hawkes_stat$branching_ratio %||% NA,3), round(hawkes_stat$halflife_mo %||% NA,2), hawkes_stat$n_events %||% NA))
cat(sprintf("PIT lag1        : calmar=%.4f (clean=%s: lag1<=hawkes+0.02)\n", lag1_m$calmar, lag1_clean))
cat(sprintf("PIT placebo     : p50=%.4f p95=%.4f | actual=%.4f rank=%.3f beats_p95=%s\n",
    plc_p50,plc_p95,hawkes_m$calmar,plc_rank,beats_placebo))
cat(sprintf("timing_corr(exp,ownret)=%.4f  corr(derisk,ownret)=%.4f  (양수 exp / 음수 derisk = good timing)\n",
    timing_corr, corr_derisk_ownret))
cat("\n-- robustness grid (top5 by calmar) --\n"); print(grid_res[1:5])
cat(sprintf("\nVERDICT: improves_calmar=%s gate_reached=%s beats_placebo=%s combo_adds=%s\n",
    improves_calmar, hawkes_m$calmar>=0.64, beats_placebo, combo_adds))
cat("[done] -> 04_Research/method_frontier/wt012_hawkes/hawkes_results.json\n")
