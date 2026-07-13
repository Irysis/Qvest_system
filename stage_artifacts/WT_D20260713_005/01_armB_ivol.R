# R21 / WT-D20260713_005 — arm B: 칼만-잔차 IVOL 팩터
# IVOL_K = 60d 잔차 sd, e_d = Ret_d − β̂_Kalman,t·BM_Ret_d (월말 β̂_t constant over trailing 60d)
# IVOL_O = 동일 산식, β_OLS,t. 저-IVOL long. paired(K vs O) 추정기 효과 격리 + 기존 LowRisk 중복성.
suppressMessages({library(arrow); library(data.table)})
arrow::set_cpu_count(2L); try(arrow::set_io_thread_count(2L), silent=TRUE); setDTthreads(2L)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(ROOT)
OUT <- "stage_artifacts/WT_D20260713_005"
R19 <- "stage_artifacts/WT_D20260713_003"
source("02_Infrastructure/contracts/backtest_result_contract.R")   # .nw_t_mean
source("02_Infrastructure/contracts/canonical_screen_bt.R")
source("02_Infrastructure/ramp/factor_validation.R")               # build_monthly_forward_returns

cat("[B1] load rawdata daily + beta panels...\n")
rawdata <- as.data.table(read_parquet(".cache/RAWDATA.parquet",
             col_select=c("Date","Ticker","Close","Vol","Size","K200","KQ150","BM_Ret")))
rawdata[, Date := as.Date(Date)]
rawdata[, K200 := (K200==1 | K200==TRUE)]; rawdata[, KQ150 := (KQ150==1 | KQ150==TRUE)]
setorder(rawdata, Ticker, Date)
rawdata[, Ret_d := Close/shift(Close)-1, by=Ticker]

beta <- as.data.table(read_parquet(file.path(R19,"beta_monthly.parquet")))   # Date,Ticker,beta_ols,beta_kalman
sig_dates <- sort(unique(beta$Date))

fwd <- build_monthly_forward_returns(rawdata, sig_dates)
RET  <- fwd$returns_dt[, .(Date=as.Date(Date), Ticker, Ret_1m)]
BENCH<- fwd$bench_dt[,  .(Date=as.Date(Date), BM_Ret)]
LIQ  <- fwd$liq_dt[,    .(Date=as.Date(Date), Ticker, adv)]
SIZE <- rawdata[Date %in% sig_dates, .(Size=last(Size)), by=.(Date,Ticker)][is.finite(Size)]

# ── IVOL: trailing 60d 잔차 sd per (sig_date, ticker) ──
cat("[B2] compute trailing-60d residual vol (K & O)...\n")
daily <- rawdata[is.finite(Ret_d) & is.finite(BM_Ret), .(Date,Ticker,Ret_d,BM_Ret)]
MINOBS <- 40L; WIN <- 60L
ivol_list <- vector("list", length(sig_dates))
for (i in seq_along(sig_dates)) {
  t <- sig_dates[i]
  bt <- beta[Date==t & is.finite(beta_ols) & is.finite(beta_kalman), .(Ticker,beta_ols,beta_kalman)]
  if (!nrow(bt)) next
  win <- daily[Date<=t & Date>t-130L]                       # ~130 calendar days ⊇ 60 trading
  win <- win[Ticker %in% bt$Ticker]
  # last WIN obs per ticker
  win <- win[order(Ticker,-Date)][, .SD[seq_len(min(WIN,.N))], by=Ticker]
  win <- merge(win, bt, by="Ticker")
  agg <- win[, .(n=.N,
                 ivol_K = sd(Ret_d - beta_kalman*BM_Ret),
                 ivol_O = sd(Ret_d - beta_ols*BM_Ret)), by=Ticker][n>=MINOBS]
  if (nrow(agg)) ivol_list[[i]] <- cbind(Date=t, agg[, .(Ticker,ivol_K,ivol_O)])
}
ivol <- rbindlist(ivol_list)
ivol[, Date := as.Date(Date, origin="1970-01-01")]
cat(sprintf("  ivol panel: %d rows, %d months\n", nrow(ivol), length(unique(ivol$Date))))
write_parquet(ivol, file.path(OUT,"ivol_panel.parquet"))

# ── scores: z = −IVOL (저-IVOL long), winsor 3std within RET universe ──
build_scores <- function(col) {
  b <- merge(RET[,.(Date,Ticker)], ivol[,.(Date,Ticker,v=get(col))], by=c("Date","Ticker"))
  b <- b[is.finite(v) & v>0]
  b[, z := { m<-mean(v); s<-sd(v); vw<-pmin(pmax(v,m-3*s),m+3*s); -((vw-mean(vw))/sd(vw)) }, by=Date]
  b[is.finite(z), .(Date,Ticker,score=z)]
}
sc_K <- build_scores("ivol_K"); sc_O <- build_scores("ivol_O")

# ── prediag: 랭킹상관 IVOL_K vs IVOL_O (추정기 무차별?) ──
rk <- ivol[is.finite(ivol_K)&is.finite(ivol_O)]
sp <- rk[, .(rho=suppressWarnings(cor(ivol_K,ivol_O,method="spearman")),n=.N), by=Date][n>=20]
prediag <- list(mean_rho=round(mean(sp$rho,na.rm=T),4), median_rho=round(median(sp$rho,na.rm=T),4),
   min_rho=round(min(sp$rho,na.rm=T),4), pct_ge_0.97=round(100*mean(sp$rho>=0.97,na.rm=T),1), n_months=nrow(sp))

cat("[B3] canonical arm K + arm O...\n")
run_arm <- function(scores, id) canonical_screen_bt(scores, RET, BENCH, top_n=25L,
             cost_bps_oneway=15, liq_dt=LIQ, liq_min=2e8, size_dt=SIZE,
             run_id=id, strategy_id=id, periods_per_year=12L, diag_dual_basis=TRUE)
res_K <- run_arm(sc_K, "R21_ivolK"); res_O <- run_arm(sc_O, "R21_ivolO")

oos_calmar <- function(res) {
  pr <- as.data.table(res$period_returns); setorder(pr, date)
  act <- pr$ret_net - pr$benchmark_ret; n <- length(act)
  sr <- function(x) if(length(x)>6 && sd(x)>0) mean(x)/sd(x)*sqrt(12) else NA
  ret_v <- vapply(c(.55,.65,.75), function(f){ k<-floor(n*f)
     is<-sr(act[1:k]); oos<-sr(act[(k+1):n]); if(is.na(is)||is<=0) NA else oos/is}, numeric(1))
  nav <- cumprod(1+pr$ret_net); yrs<-n/12; cagr<-nav[n]^(1/yrs)-1
  peak<-cummax(nav); mdd<-max((peak-nav)/peak)
  list(oos_retention=round(median(ret_v,na.rm=TRUE),3), calmar=round(ifelse(mdd>0,cagr/mdd,NA),3),
       cagr=round(cagr,4), mdd=round(mdd,4))
}
oc_K<-oos_calmar(res_K); oc_O<-oos_calmar(res_O)

# ── paired NW-t: active_K − active_O (본 arm 권위 질문) ──
prK<-as.data.table(res_K$period_returns)[,.(date,aK=ret_net-benchmark_ret)]
prO<-as.data.table(res_O$period_returns)[,.(date,aO=ret_net-benchmark_ret)]
pj<-merge(prK,prO,by="date"); pj[,d:=aK-aO]
paired_nw_t<-.nw_t_mean(pj$d,3L); paired_mean_annual<-mean(pj$d)*12

# ── redundancy: 기존 LowRisk 팩터와 랭킹상관 (sample sig_dates via load_month_factors) ──
cat("[B4] redundancy vs existing LowRisk (sampled)...\n")
redundancy <- tryCatch({
  source("02_Infrastructure/factor_db/factor_db_connector.R")
  sd_all <- sort(unique(ivol$Date)); samp <- sd_all[round(seq(1,length(sd_all),length.out=20))]
  targ <- c("D01_IdioVol","R12_Idiosyncratic_Risk","D03_RealVol","D02_Beta")
  accum <- list()
  for (t in samp) {
    mf <- tryCatch(as.data.table(load_month_factors(as.Date(t))), error=function(e) NULL)
    if (is.null(mf) || !nrow(mf)) next
    iv <- ivol[Date==t, .(Ticker, ivK=ivol_K)]
    # detect wide vs long
    if ("Factor_Name" %in% names(mf)) {
      for (fn in intersect(targ, unique(mf$Factor_Name))) {
        m <- merge(iv, mf[Factor_Name==fn & is.finite(Z_Score), .(Ticker, z=Z_Score)], by="Ticker")
        if (nrow(m)>=20) accum[[paste0(fn,"_",t)]] <- data.table(factor=fn, rho=cor(m$ivK,m$z,method="spearman"))
      }
    } else {
      for (fn in intersect(targ, names(mf))) {
        m <- merge(iv, mf[is.finite(get(fn)), .(Ticker, z=get(fn))], by="Ticker")
        if (nrow(m)>=20) accum[[paste0(fn,"_",t)]] <- data.table(factor=fn, rho=cor(m$ivK,m$z,method="spearman"))
      }
    }
  }
  if (length(accum)) { ac<-rbindlist(accum); ac[, .(mean_rho=round(mean(rho,na.rm=T),3), n=.N), by=factor] } else NULL
}, error=function(e) { cat("  redundancy ERR:",conditionMessage(e),"\n"); NULL })

# ── rank IC advisory ──
rank_ic <- function(scores){ m<-merge(scores,RET,by=c("Date","Ticker"))
  ic<-m[,.(ic=suppressWarnings(cor(score,Ret_1m,method="spearman"))),by=Date][is.finite(ic)]
  list(rank_ic=round(mean(ic$ic),4), icir=round(mean(ic$ic)/sd(ic$ic),3),
       harvey_t=round(mean(ic$ic)/(sd(ic$ic)/sqrt(nrow(ic))),3), n=nrow(ic)) }
ic_K<-rank_ic(sc_K); ic_O<-rank_ic(sc_O)

strip <- function(res) list(
  portfolio_alpha_t_nw_lag3=round(res$portfolio_alpha_t_nw_lag3,3),
  portfolio_alpha_t_pvalue=round(res$portfolio_alpha_t_pvalue,4),
  net_sr=round(res$net_sr,3), information_ratio=round(res$information_ratio,3),
  mean_active_net=round(res$mean_active_net,5), turnover_annual=round(res$turnover_annual,3),
  n_months=res$n_months,
  diag_ew_universe_port_t=tryCatch(round(res$diag_ew_universe$portfolio_alpha_t_nw_lag3,3),error=function(e)NA),
  diag_ew_universe_post2017_t=tryCatch(round(res$diag_ew_universe$post2017_t_nw_lag3,3),error=function(e)NA),
  diag_cap_tier=tryCatch(res$diag_cap_tier$contrib_gross_annualized,error=function(e)NA),
  diag_cap_tier_hold_pct=tryCatch(res$diag_cap_tier$hold_pct,error=function(e)NA))

summary <- list(
  wt_id="WT-D20260713_005", arm="B_kalman_residual_ivol",
  arm_K_ivolK=c(strip(res_K),oc_K,rank_ic=list(ic_K)),
  arm_O_ivolO=c(strip(res_O),oc_O,rank_ic=list(ic_O)),
  estimator_marginal=list(paired_nw_t=round(paired_nw_t,3), paired_mean_active_annual=round(paired_mean_annual,5),
     interpret="paired_nw_t = active(IVOL_K) − active(IVOL_O) NW lag-3. |t|<~2 이면 추정기 무차별."),
  prediag_ranking_corr=prediag,
  redundancy_vs_lowrisk=redundancy,
  cost_model_version="v2.4_kr_retail_15bps", universe="KR_top342 (K200∪KQ150, LIQ 2e8)",
  selection_objective="canonical_port_t", n_trials=2, selection_type="sweep")
writeLines(jsonlite::toJSON(summary, auto_unbox=TRUE, pretty=TRUE, digits=6, null="null"),
           file.path(OUT,"armB_ivol_summary.json"))
write_parquet(rbindlist(list(sc_K[,arm:="ivolK"], sc_O[,arm:="ivolO"])), file.path(OUT,"armB_scores.parquet"))
cat("[B] DONE.\n")
cat(sprintf("  IVOL_K PORT_t=%.2f EWuni=%.2f oos=%.2f calmar=%.2f | IVOL_O PORT_t=%.2f\n",
    res_K$portfolio_alpha_t_nw_lag3, strip(res_K)$diag_ew_universe_port_t, oc_K$oos_retention, oc_K$calmar,
    res_O$portfolio_alpha_t_nw_lag3))
cat(sprintf("  estimator paired_NW_t=%.2f | prediag mean_rho=%.3f (%%>=0.97: %.0f%%)\n",
    paired_nw_t, prediag$mean_rho, prediag$pct_ge_0.97))
if(!is.null(redundancy)) print(redundancy)
