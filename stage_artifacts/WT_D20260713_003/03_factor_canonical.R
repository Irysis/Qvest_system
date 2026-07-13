# R19 / WT-D20260713_003 — Stage 3: 2차 endpoint(팩터-레벨) + 진단 + AX-001v2 조건부
# arm O(β_ols) vs arm K(β_kalman tuned) : z=−β top-25 EW long-only canonical
suppressMessages({library(arrow); library(data.table)})
arrow::set_cpu_count(2L); try(arrow::set_io_thread_count(2L), silent=TRUE); setDTthreads(2L)
OUT <- "stage_artifacts/WT_D20260713_003"
source("02_Infrastructure/contracts/backtest_result_contract.R")   # .nw_t_mean
source("02_Infrastructure/contracts/canonical_screen_bt.R")
source("02_Infrastructure/ramp/factor_validation.R")               # build_monthly_forward_returns

cat("[03] load rawdata + build forward returns...\n")
rawdata <- as.data.table(read_parquet(".cache/RAWDATA.parquet",
             col_select=c("Date","Ticker","Close","Vol","Size","K200","KQ150","BM_Ret")))
rawdata[, Date := as.Date(Date)]
rawdata[, K200 := (K200==1 | K200==TRUE)]; rawdata[, KQ150 := (KQ150==1 | KQ150==TRUE)]

beta_ols <- as.data.table(read_parquet(file.path(OUT,"beta_monthly.parquet")))[,.(Date,Ticker,beta_ols)]
beta_kal <- as.data.table(read_parquet(file.path(OUT,"beta_kalman_tuned.parquet")))[,.(Date,Ticker,beta_kalman)]
sig_dates <- sort(unique(beta_ols$Date))

fwd <- build_monthly_forward_returns(rawdata, sig_dates)
RET  <- fwd$returns_dt[, .(Date=as.Date(Date), Ticker, Ret_1m)]
BENCH<- fwd$bench_dt[,  .(Date=as.Date(Date), BM_Ret)]     # cap-w universe forward (authoritative basis)
LIQ  <- fwd$liq_dt[,    .(Date=as.Date(Date), Ticker, adv)]
SIZE <- rawdata[Date %in% sig_dates, .(Size=last(Size)), by=.(Date,Ticker)][is.finite(Size)]

# ── scores: z = −β cross-sectional (winsorize 3std → zscore) within RET universe ──
build_scores <- function(beta_dt, bcol) {
  b <- merge(RET[,.(Date,Ticker)], beta_dt, by=c("Date","Ticker"))
  setnames(b, bcol, "beta")
  b <- b[is.finite(beta)]
  b[, z := {
    m<-mean(beta); s<-sd(beta)
    bw <- pmin(pmax(beta, m-3*s), m+3*s)
    -( (bw-mean(bw))/sd(bw) )          # z of −β (저베타 상위)
  }, by=Date]
  b[is.finite(z), .(Date, Ticker, score=z)]
}
sc_O <- build_scores(beta_ols, "beta_ols")
sc_K <- build_scores(beta_kal, "beta_kalman")

cat("[03] canonical arm O + arm K...\n")
run_arm <- function(scores, id) canonical_screen_bt(scores, RET, BENCH, top_n=25L,
             cost_bps_oneway=15, liq_dt=LIQ, liq_min=2e8, size_dt=SIZE,
             run_id=id, strategy_id=id, periods_per_year=12L, diag_dual_basis=TRUE)
res_O <- run_arm(sc_O, "R19_armO_ols")
res_K <- run_arm(sc_K, "R19_armK_kalman")

# ── oos_retention (anchored 3분할 중앙값) + calmar from active series ──
oos_calmar <- function(res) {
  pr <- as.data.table(res$period_returns); setorder(pr, date)
  act <- pr$ret_net - pr$benchmark_ret; n <- length(act)
  sr <- function(x) if(length(x)>6 && sd(x)>0) mean(x)/sd(x)*sqrt(12) else NA
  ret_v <- vapply(c(.55,.65,.75), function(f){ k<-floor(n*f)
     is<-sr(act[1:k]); oos<-sr(act[(k+1):n]); if(is.na(is)||is<=0) NA else oos/is}, numeric(1))
  oos_ret <- median(ret_v, na.rm=TRUE)
  # calmar on net port (not active): CAGR/MDD
  nav <- cumprod(1+pr$ret_net); yrs<-n/12
  cagr <- nav[n]^(1/yrs)-1
  peak<-cummax(nav); mdd<-max((peak-nav)/peak)
  list(oos_retention=round(oos_ret,3), calmar=round(ifelse(mdd>0,cagr/mdd,NA),3),
       cagr=round(cagr,4), mdd=round(mdd,4), net_sr=round(res$net_sr,3))
}
oc_O <- oos_calmar(res_O); oc_K <- oos_calmar(res_K)

# ── paired NW-t: active_K − active_O (칼만 한계기여 격리) ──
prO <- as.data.table(res_O$period_returns)[,.(date, actO=ret_net-benchmark_ret)]
prK <- as.data.table(res_K$period_returns)[,.(date, actK=ret_net-benchmark_ret)]
pj <- merge(prO, prK, by="date"); pj[, d := actK-actO]
paired_nw_t <- .nw_t_mean(pj$d, lag=3L)
paired_mean_annual <- mean(pj$d)*12

# ── ranking spearman (monthly, −β_O vs −β_K) ──
rk <- merge(beta_ols, beta_kal, by=c("Date","Ticker"))
rk <- rk[is.finite(beta_ols)&is.finite(beta_kalman)]
sp <- rk[, .(rho=suppressWarnings(cor(-beta_ols, -beta_kalman, method="spearman")), n=.N), by=Date][n>=20]
spearman_summary <- list(mean_rho=round(mean(sp$rho,na.rm=T),3), median_rho=round(median(sp$rho,na.rm=T),3),
   min_rho=round(min(sp$rho,na.rm=T),3), pct_months_ge_0.95=round(100*mean(sp$rho>=0.95,na.rm=T),1),
   n_months=nrow(sp))

# ── rank IC + ICIR (advisory, per arm) ──
rank_ic <- function(scores){
  m <- merge(scores, RET, by=c("Date","Ticker"))
  ic <- m[, .(ic=suppressWarnings(cor(score, Ret_1m, method="spearman"))), by=Date][is.finite(ic)]
  list(rank_ic=round(mean(ic$ic),4), icir=round(mean(ic$ic)/sd(ic$ic),3),
       harvey_t=round(mean(ic$ic)/(sd(ic$ic)/sqrt(nrow(ic))),3), n=nrow(ic), ic_series=ic)
}
ic_O <- rank_ic(sc_O); ic_K <- rank_ic(sc_K)

# ── placebo: 랜덤 top-25 선택 대비 arm K PORT_t 우위 (N=500) ──
cat("[03] placebo...\n")
set.seed(19)
mk_active <- function(sel_by_date){  # sel_by_date: list Date->tickers
  pr <- rbindlist(lapply(names(sel_by_date), function(dc){
    d<-as.Date(dc); tk<-sel_by_date[[dc]]
    r<-RET[Date==d & Ticker %in% tk, Ret_1m]; b<-BENCH[Date==d, BM_Ret]
    if(!length(r)||!length(b)) return(NULL)
    data.table(date=d, act=mean(r,na.rm=T)-b)
  }))
  if(!nrow(pr)) return(NA); .nw_t_mean(pr$act, lag=3L)
}
univ_by_date <- split(RET$Ticker, RET$Date)
plac_t <- numeric(0)
dts_chr <- names(univ_by_date)
for (b in 1:500) {
  sel <- lapply(dts_chr, function(dc){ u<-univ_by_date[[dc]]; if(length(u)<25) u else sample(u,25)})
  names(sel)<-dts_chr
  plac_t <- c(plac_t, mk_active(sel))
}
plac_t <- plac_t[is.finite(plac_t)]
armK_port_t <- res_K$portfolio_alpha_t_nw_lag3
placebo_p <- round(mean(plac_t >= armK_port_t), 4)

# ── AX-001v2 조건부: 위기구간 alpha + bad/normal IC ratio ──
BMm <- BENCH[order(Date)]; BMm[, roll6 := frollsum(BM_Ret,6)]
crisis_dates <- BMm[BM_Ret < -0.05 | (is.finite(roll6) & roll6 <= quantile(roll6,0.2,na.rm=T)), Date]
crisis_alpha <- function(res){
  pr<-as.data.table(res$period_returns); pr[, act:=ret_net-benchmark_ret]
  cr<-pr[date %in% crisis_dates]; no<-pr[!date %in% crisis_dates]
  list(crisis_mean_active=round(mean(cr$act),4), crisis_n=nrow(cr),
       crisis_active_t=round(ifelse(nrow(cr)>3,.nw_t_mean(cr$act,3),NA),3),
       normal_mean_active=round(mean(no$act),4))
}
bad_normal_ic <- function(ic){
  s<-ic$ic_series; bad<-s[Date %in% crisis_dates, ic]; nor<-s[!Date %in% crisis_dates, ic]
  round(mean(bad,na.rm=T)/abs(mean(nor,na.rm=T)),3)
}
ax001 <- list(
  crisis_months=length(crisis_dates),
  armO=c(crisis_alpha(res_O), bad_normal_ic_ratio=bad_normal_ic(ic_O)),
  armK=c(crisis_alpha(res_K), bad_normal_ic_ratio=bad_normal_ic(ic_K)),
  note="AX-001v2: 방어형은 전기간 SR 채점 금지. 위기구간 alpha + bad/normal IC ratio로 조건부 평가.")

# ── assemble ──
strip <- function(res) list(
  portfolio_alpha_t_nw_lag3=round(res$portfolio_alpha_t_nw_lag3,3),
  portfolio_alpha_t_pvalue=round(res$portfolio_alpha_t_pvalue,4),
  information_ratio=round(res$information_ratio,3),
  net_sr=round(res$net_sr,3), mean_active_net=round(res$mean_active_net,5),
  turnover_annual=round(res$turnover_annual,3), n_months=res$n_months,
  diag_ew_universe_port_t=tryCatch(round(res$diag_ew_universe$portfolio_alpha_t_nw_lag3,3),error=function(e)NA),
  diag_ew_universe_post2017_t=tryCatch(round(res$diag_ew_universe$post2017_t_nw_lag3,3),error=function(e)NA),
  diag_cap_tier=tryCatch(res$diag_cap_tier$contrib_gross_annualized,error=function(e)NA),
  diag_cap_tier_hold_pct=tryCatch(res$diag_cap_tier$hold_pct,error=function(e)NA))

summary <- list(
  wt_id="WT-D20260713_003", endpoint="secondary_factor_level",
  arm_O_ols=c(strip(res_O), oc_O), arm_K_kalman=c(strip(res_K), oc_K),
  kalman_marginal=list(paired_nw_t=round(paired_nw_t,3), paired_mean_active_annual=round(paired_mean_annual,5),
     interpret="paired_nw_t = active_K − active_O NW lag-3 t. |t|<~2 이면 칼만 한계기여 무의미(추정기 교체 실질 동일)."),
  ranking_spearman=spearman_summary,
  rank_ic_advisory=list(armO=ic_O[c("rank_ic","icir","harvey_t","n")], armK=ic_K[c("rank_ic","icir","harvey_t","n")]),
  placebo=list(armK_port_t=round(armK_port_t,3), placebo_mean_t=round(mean(plac_t),3),
     placebo_p_value=placebo_p, n=length(plac_t),
     interpret="랜덤 top-25 대비 저베타 선택 우위 검정. p<0.05 이면 신호 실재."),
  ax001v2_conditional=ax001,
  cost_model_version="v2.4_kr_retail_15bps", universe="KR_top342 (K200∪KQ150, LIQ 2e8)",
  selection_objective="canonical_port_t", n_trials=2, selection_type="sweep")
writeLines(jsonlite::toJSON(summary, auto_unbox=TRUE, pretty=TRUE, digits=6),
           file.path(OUT,"factor_canonical_summary.json"))
# save scores parquet (alpha_scores)
sc_all <- rbindlist(list(sc_O[,arm:="ols"], sc_K[,arm:="kalman"]))
write_parquet(sc_all, file.path(OUT,"alpha_scores.parquet"))
cat("[03] DONE.\n")
cat(sprintf("  arm O(OLS)    PORT_t=%.2f  EWuni=%.2f  net_sr=%.2f oos=%.2f calmar=%.2f\n",
    res_O$portfolio_alpha_t_nw_lag3, strip(res_O)$diag_ew_universe_port_t, res_O$net_sr, oc_O$oos_retention, oc_O$calmar))
cat(sprintf("  arm K(Kalman) PORT_t=%.2f  EWuni=%.2f  net_sr=%.2f oos=%.2f calmar=%.2f\n",
    res_K$portfolio_alpha_t_nw_lag3, strip(res_K)$diag_ew_universe_port_t, res_K$net_sr, oc_K$oos_retention, oc_K$calmar))
cat(sprintf("  Kalman marginal paired_NW_t=%.2f | spearman mean_rho=%.3f (%%>=0.95: %.0f%%) | placebo_p=%.3f\n",
    paired_nw_t, spearman_summary$mean_rho, spearman_summary$pct_months_ge_0.95, placebo_p))
