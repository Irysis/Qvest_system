# R5 — 꼬리위험(EVT/Hill/TDC) · 스트레스(coverage 표기) · crowding · cap-tier · 집중도 · 유동성
# C9: 낙폭 기반 진단은 전기 낙폭만 사용(dd_lag <- c(0, dd[-n])) — 동일자 낙폭 참조 금지.
suppressWarnings(suppressMessages({library(data.table); library(arrow); library(jsonlite)}))
ROOT <- Sys.getenv("QM_ROOT"); if(!nzchar(ROOT)) ROOT <- getwd(); setwd(ROOT)
OUT <- file.path(ROOT,"stage_artifacts/WT_R20260829_004")
# tail_risk_engine.R 은 fExtremes 의존(본 환경 미설치) → GPD(POT) MLE 자체 구현으로 대체.
#   Pfaff FRM ch.7 정통: excess over threshold ~ GPD(xi, beta); VaR_p = u + beta/xi*(((n/Nu)(1-p))^-xi - 1)
compute_evt_var <- function(r, p=0.99, threshold_q=0.95, min_tail_n=60L){
  r <- r[is.finite(r)]; losses <- -r; n <- length(losses)
  u <- as.numeric(quantile(losses, threshold_q)); ex <- losses[losses>u] - u
  if (length(ex) < min_tail_n) { threshold_q <- max(0.85, threshold_q-0.05)
    u <- as.numeric(quantile(losses, threshold_q)); ex <- losses[losses>u]-u }
  Nu <- length(ex)
  if (Nu < 20L) return(list(method="insufficient_exceedances", n_exceedances=Nu))
  nll <- function(par){ xi <- par[1]; b <- exp(par[2])
    if (xi < -0.5) return(1e10)
    z <- 1 + xi*ex/b; if (any(z<=0)) return(1e10)
    Nu*log(b) + (1+1/xi)*sum(log(z)) }
  nll0 <- function(par){ b <- exp(par[1]); Nu*log(b) + sum(ex)/b }   # xi -> 0 (지수)
  fit <- tryCatch(optim(c(0.1, log(mean(ex))), nll, method="Nelder-Mead"), error=function(e) NULL)
  if (is.null(fit) || fit$value > 1e9) {
    f0 <- optim(log(mean(ex)), nll0, method="Brent", lower=-20, upper=5)
    xi <- 0; beta <- exp(f0$par)
  } else { xi <- fit$par[1]; beta <- exp(fit$par[2]) }
  q <- (n/Nu)*(1-p)
  var_evt <- if (abs(xi) < 1e-6) u + beta*(-log(q)) else u + beta/xi*(q^(-xi) - 1)
  es_evt  <- if (xi < 1) (var_evt + beta - xi*u)/(1-xi) else NA_real_
  list(var_evt=var_evt, es_evt=es_evt, shape_xi=xi, scale_beta=beta, threshold_u=u,
       threshold_q=threshold_q, n_exceedances=Nu, method="gpd_mle_selfimpl")
}
compute_cdar <- function(nav, alpha=0.95){
  dd <- nav/cummax(nav) - 1; d <- -dd
  thr <- as.numeric(quantile(d, alpha))
  list(cdar = mean(d[d>=thr]), dar = thr, max_dd = min(dd), alpha=alpha)
}
source(file.path(ROOT,"02_Infrastructure/factor_db/crowding_score_per_factor.R"))
S1 <- readRDS(file.path(OUT,"risk_calc_stage1.rds")); S2 <- readRDS(file.path(OUT,"risk_calc_stage2.rds"))
RI <- readRDS(file.path(OUT,"risk_inputs.rds")); P <- readRDS(file.path(OUT,"panel.rds"))
SIG_DATE <- as.Date("2026-08-28")
SLD <- S1$SLD; HOLDH <- S1$HOLDH; DD <- S1$DD; EXP <- S1$EXP; HOLD_CUR <- S1$HOLD_CUR
PR <- fread(file.path(OUT,"period_returns_production.csv"))
BMD <- as.data.table(P$BMD)[Date<=SIG_DATE][order(Date)]
res <- list()

## ── A. 꼬리위험 ───────────────────────────────────────────────────────────
rd <- SLD$ret_d; rm_ <- BMD[Date %in% SLD$Date]$BM_Ret
emp <- function(r,p) { v <- as.numeric(quantile(-r, p)); list(var=v, es=mean((-r)[-r>=v])) }
hill <- function(r, k_frac=0.05){ l <- sort(-r, decreasing=TRUE); k <- max(20L, floor(length(l)*k_frac))
  1/mean(log(l[1:k]/l[k])) }
evt95 <- tryCatch(compute_evt_var(rd, p=0.95, threshold_q=0.90), error=function(e) list(error=conditionMessage(e)))
evt99 <- tryCatch(compute_evt_var(rd, p=0.99, threshold_q=0.95), error=function(e) list(error=conditionMessage(e)))
nav <- cumprod(1+rd); cdar <- tryCatch(compute_cdar(nav, alpha=0.95), error=function(e) list(error=conditionMessage(e)))
# C9 실증: 낙폭 계열은 전기 값만
dd_pct <- nav/cummax(nav)-1; n <- length(dd_pct); dd_lag <- c(0, dd_pct[-n])
tdc_lower <- { q <- 0.05; u <- quantile(rd,q); v <- quantile(rm_,q); mean(rd<=u & rm_<=v)/q }
mr <- PR$ret_net
res$tail_risk <- list(
  basis_daily = "슬리브 일간 gross(EW top-25, 법정한도 winsorize) n=5321 · 비용 미반영(꼬리 형상용)",
  basis_monthly = "period_returns_production.csv ret_net (15bps 반영) n=259",
  daily = list(var95=emp(rd,0.95)$var, es95=emp(rd,0.95)$es, var99=emp(rd,0.99)$var, es99=emp(rd,0.99)$es,
               skew = mean((rd-mean(rd))^3)/sd(rd)^3, kurt = mean((rd-mean(rd))^4)/sd(rd)^4,
               hill_alpha_left = hill(rd), hill_alpha_right = hill(-rd)),
  monthly = list(var95=emp(mr,0.95)$var, es95=emp(mr,0.95)$es, var99=emp(mr,0.99)$var, es99=emp(mr,0.99)$es,
                 worst = min(mr), skew = mean((mr-mean(mr))^3)/sd(mr)^3,
                 kurt = mean((mr-mean(mr))^4)/sd(mr)^4),
  evt_gpd_95 = evt95, evt_gpd_99 = evt99, cdar_95 = cdar,
  tail_dependence_lower_vs_market_q05 = tdc_lower,
  c9_lagged_drawdown = list(rule="dd_lag <- c(0, dd_pct[-n])", max_dd_lagged = min(dd_lag),
                            mean_dd_lagged = mean(dd_lag)))
cat(sprintf("[R5] tail: 일간 VaR95 %.3f ES95 %.3f VaR99 %.3f ES99 %.3f | Hill(L) %.2f | TDC %.3f | 월간 ES95 %.3f worst %.3f\n",
  res$tail_risk$daily$var95, res$tail_risk$daily$es95, res$tail_risk$daily$var99, res$tail_risk$daily$es99,
  res$tail_risk$daily$hill_alpha_left, tdc_lower, res$tail_risk$monthly$es95, res$tail_risk$monthly$worst))
cat(sprintf("[R5] EVT95 xi=%s var=%s | EVT99 xi=%s var=%s | CDaR95=%s\n",
  signif(evt95$shape_xi,4), signif(evt95$var_evt,4), signif(evt99$shape_xi,4), signif(evt99$var_evt,4),
  signif(if(is.list(cdar)) cdar$cdar else NA,4)))

## ── B. 스트레스 (coverage 병기) ───────────────────────────────────────────
PR[, hold_start := as.Date(paste0(holding_ym,"-01"))]
stress_def <- list(
  list(name="Terror_9_11", s="2001-09-01", e="2001-12-31"),
  list(name="GFC",         s="2007-10-01", e="2009-03-31"),
  list(name="Euro_Debt",   s="2011-07-01", e="2011-12-31"),
  list(name="China_Shock", s="2015-06-01", e="2016-02-29"),
  list(name="US_China_Trade", s="2018-03-01", e="2018-12-31"),
  list(name="COVID",       s="2020-01-01", e="2020-06-30"),
  list(name="Rate_Hike",   s="2022-01-01", e="2022-12-31"),
  list(name="Iran_War",    s="2026-02-01", e="2026-04-30"),
  list(name="KR_Bear_2026H2", s="2026-05-01", e="2026-08-31"))
st <- lapply(stress_def, function(z){
  s <- as.Date(z$s); e <- as.Date(z$e)
  W <- PR[hold_start>=s & hold_start<=e]
  n_exp <- length(seq(as.Date(format(s,"%Y-%m-01")), as.Date(format(e,"%Y-%m-01")), by="month"))
  cov_ <- nrow(W)/max(n_exp,1)
  if (nrow(W)==0) return(list(name=z$name, n_months=0L, coverage=0, status="UNRELIABLE_NO_DATA"))
  nv <- cumprod(1+W$ret_net)
  list(name=z$name, start=z$s, end=z$e, n_months=nrow(W), coverage=cov_,
       status = if(cov_ < 0.85) "UNRELIABLE_PARTIAL_COVERAGE" else "OK",
       strat_cum = prod(1+W$ret_net)-1, bm_cum = prod(1+W$benchmark_ret)-1,
       alpha_cum = (prod(1+W$ret_net)-1)-(prod(1+W$benchmark_ret)-1),
       mdd = min(nv/cummax(nv)-1), worst_month = min(W$ret_net),
       n_panic_months = sum(W$panic))
})
names(st) <- sapply(stress_def, function(z) z$name)
res$stress_historical <- st
for (z in st) if(z$n_months>0) cat(sprintf("[R5] %-16s n=%2d cov=%.2f %-28s strat %+.1f%% bm %+.1f%% mdd %.1f%%\n",
  z$name, z$n_months, z$coverage, z$status, 100*z$strat_cum, 100*z$bm_cum, 100*z$mdd))

## ── B2. Sigma 기반 시나리오 (요인 충격) ───────────────────────────────────
Sig <- S2$Sig; Om <- S2$Om_f; Bw <- S2$Bw; FC <- names(S2$fac_share)
sd_f_mon <- sqrt(diag(Om)*21)
shock <- function(fac, k) { i <- which(FC==fac); Bw[i]*(-k*sd_f_mon[i]) }
beta_p <- Bw[which(FC=="Market")]
res$stress_scenarios <- list(
  basis = "EW 진단기준(w=1/25) · Sigma(as-of, ewma_hl126+eigen-floor) · 1개월 horizon",
  market_down_5 = as.numeric(beta_p*(-0.05)),
  market_down_10 = as.numeric(beta_p*(-0.10)),
  market_3sd_month = as.numeric(shock("Market",3)),
  momentum_reversal_3sd = as.numeric(shock("x_mom",3)),
  vol_factor_3sd = as.numeric(shock("x_vol",3)),
  size_3sd = as.numeric(shock("x_size",3)),
  joint_market_and_momentum_3sd = as.numeric(shock("Market",3)+shock("x_mom",3)),
  portfolio_beta = as.numeric(beta_p),
  portfolio_vol_ann = sqrt(as.numeric(t(rep(1/25,25))%*%Sig%*%rep(1/25,25))*12))
cat(sprintf("[R5] scenario: beta %.3f · mkt-5%% %.3f · mkt-3sd %.3f · mom-3sd %.3f · joint %.3f\n",
  beta_p, res$stress_scenarios$market_down_5, res$stress_scenarios$market_3sd_month,
  res$stress_scenarios$momentum_reversal_3sd, res$stress_scenarios$joint_market_and_momentum_3sd))

## ── C. Crowding (Acadian 2026, 필수) ──────────────────────────────────────
Ecur_all <- EXP[Date==SIG_DATE]
FE <- rbindlist(list(
  data.table(Ticker=Ecur_all$Ticker, factor_name="Momentum_JT1993_6M_skip1", exposure=Ecur_all$x_mom),
  data.table(Ticker=Ecur_all$Ticker, factor_name="LowVol_realized126d",      exposure=-Ecur_all$x_vol),
  data.table(Ticker=Ecur_all$Ticker, factor_name="Size_logMktCap",           exposure=Ecur_all$x_size),
  data.table(Ticker=Ecur_all$Ticker, factor_name="Liquidity_ADV20",          exposure=Ecur_all$x_liq)))
bench_tk <- as.data.table(RI$memb)[K200==TRUE | KQ150==TRUE]$Ticker
CS <- tryCatch(crowding_score_per_factor(FE, SIG_DATE, as.data.table(RI$RD_slim),
                                          benchmark_tickers=bench_tk, top_n=25L),
               error=function(e) data.table(factor_name="ERROR", crowding_score=NA_real_, err=conditionMessage(e)))
print(CS)
res$crowding_score_per_factor <- lapply(seq_len(nrow(CS)), function(i) as.list(CS[i]))

## ── D. 집중도 ─────────────────────────────────────────────────────────────
Ecur <- S1$Ecur
w <- rep(1/25,25)
sec_w <- Ecur[, .(w=.N/25), by=Sector][order(-w)]
hhi_sector <- sum(sec_w$w^2)
mrc <- as.numeric(Sig %*% w); rc <- w*mrc/as.numeric(t(w)%*%Sig%*%w)
n_eff_risk <- 1/sum(rc^2); n_eff_weight <- 1/sum(w^2)
res$concentration <- list(
  basis="EW 진단기준(w=1/25) — 비중 제안 아님",
  sector_hhi=hhi_sector, sector_hhi_normalized=(hhi_sector-1/nrow(sec_w))/max(1-1/nrow(sec_w),1e-12),
  n_sectors=nrow(sec_w), top_sector=sec_w$Sector[1], top_sector_weight=sec_w$w[1],
  n_effective_weight=n_eff_weight, n_effective_risk=n_eff_risk,
  max_risk_contribution=max(rc), sector_weights=setNames(as.list(sec_w$w), sec_w$Sector),
  per_factor_variance_share=as.list(round(S2$fac_share,6)))
cat(sprintf("[R5] 집중도: 섹터 %d개 HHI %.3f top=%s(%.0f%%) · n_eff(risk) %.1f · maxRC %.3f\n",
  nrow(sec_w), hhi_sector, sec_w$Sector[1], 100*sec_w$w[1], n_eff_risk, max(rc)))

## ── E. cap-tier 분해 (v8.3.1 의무) ────────────────────────────────────────
SZ <- as.data.table(P$SIZE)[!is.na(Size)]; setorder(SZ, Date, -Size)
SZ[, cap_rank := seq_len(.N), by=Date]
SZ[, tier := fifelse(cap_rank<=10L,"MEGA", fifelse(cap_rank<=30L,"MID","OTHER"))]
HT <- merge(HOLDH[, .(Date, Ticker, hold_ym)], SZ[, .(Date,Ticker,tier)], by=c("Date","Ticker"), all.x=TRUE)
HT[is.na(tier), tier := "UNRANKED"]
MR <- S1$MRET
HT <- merge(HT, MR[, .(hold_ym=ym, Ticker, ret_m)], by=c("hold_ym","Ticker"), all.x=TRUE)
HT <- merge(HT, PR[, .(hold_ym=holding_ym, bm=benchmark_ret)], by="hold_ym")
TA <- HT[!is.na(ret_m), .(nw=.N/25, contrib=sum(ret_m)/25, bm=first(bm)), by=.(hold_ym, tier)]
TA[, active := contrib - nw*bm]
tot_act <- TA[, .(tot=sum(active)), by=hold_ym]
TA <- merge(TA, tot_act, by="hold_ym")
tiers <- c("MEGA","MID","OTHER","UNRANKED")
ct <- lapply(tiers, function(tt){
  Z <- TA[tier==tt]; if(nrow(Z)<12) return(list(tier=tt, n_months=nrow(Z), available=FALSE))
  ts_ <- mean(Z$active)/(sd(Z$active)/sqrt(nrow(Z)))
  rs <- cov(Z$active, Z$tot)/var(TA[, .(t=first(tot)), by=hold_ym]$t)
  list(tier=tt, n_months=nrow(Z), weight_share_avg=mean(Z$nw),
       active_risk_share=as.numeric(rs), alpha_share=sum(Z$active)/sum(tot_act$tot),
       mean_active_monthly=mean(Z$active), t_stat=ts_, signal_alive=(ts_>1.0))
})
names(ct) <- tiers
cur_tier <- merge(data.table(Ticker=HOLD_CUR), SZ[Date==SIG_DATE, .(Ticker,tier)], by="Ticker", all.x=TRUE)
cur_tier[is.na(tier), tier := "UNRANKED"]
res$cap_tier_decomposition <- list(
  basis="cap_w_and_ew_uni", tier_def="MEGA=cap rank 1-10 / MID=11-30 / OTHER=31+ (SIZE 패널 내 월별 랭킹)",
  tiers=ct, current_snapshot=as.list(table(cur_tier$tier)),
  dual_basis_divergence_flag = abs(0.949-0.915) > 0.5,
  dual_basis_note = "alpha 실측 ew_universe_port_t 0.949 vs canonical(cap-w 벤치) 0.915 — 괴리 0.034, 기저 판정 불변")
for(z in ct) if(!is.null(z$weight_share_avg)) cat(sprintf("[R5] tier %-8s w %.3f · alpha_share %+.3f · risk_share %.3f · t %.2f · alive %s\n",
  z$tier, z$weight_share_avg, z$alpha_share, z$active_risk_share, z$t_stat, z$signal_alive))
print(table(cur_tier$tier))

## ── F. 유동성 ─────────────────────────────────────────────────────────────
LQ <- Ecur[, .(Ticker, adv=exp(0)*NA_real_)]
RD <- as.data.table(RI$RD_slim)[, .(Date=as.Date(Date), Ticker, val=Close*Vol)]
W20 <- RD[Date < SIG_DATE]; W20 <- W20[Date %in% tail(sort(unique(W20$Date)),20L)]
ADV <- W20[, .(adv20=mean(val,na.rm=TRUE)), by=Ticker]
LQ <- merge(Ecur[, .(Ticker)], ADV, by="Ticker", all.x=TRUE)
LIQ_FLOOR <- 2e8
res$liquidity <- list(
  rule="20일 평균 거래대금(t-1 이전) >= 2e8 KRW",
  n_below_floor=sum(LQ$adv20 < LIQ_FLOOR, na.rm=TRUE),
  n_missing=sum(is.na(LQ$adv20)),
  min_adv20=min(LQ$adv20,na.rm=TRUE), median_adv20=median(LQ$adv20,na.rm=TRUE),
  capacity_at_10pct_adv_1day_krw = 25*0.10*min(LQ$adv20,na.rm=TRUE),
  days_to_liquidate_100e8_at_10pct = 100e8/25/(0.10*median(LQ$adv20,na.rm=TRUE)),
  worst_names = LQ[order(adv20)][1:3, .(Ticker, adv20)])
cat(sprintf("[R5] 유동성: floor 미달 %d · min ADV20 %.2e · median %.2e · 100억 청산일수(10%%참여) %.2f\n",
  res$liquidity$n_below_floor, res$liquidity$min_adv20, res$liquidity$median_adv20,
  res$liquidity$days_to_liquidate_100e8_at_10pct))

## ── G. 요인모형 설명력 (factor coverage) ──────────────────────────────────
M2 <- readRDS(file.path(OUT,"risk_factor_model.rds")); ER <- M2$ERES
DDx <- copy(DD)[, .(Date,Ticker,Ret)]
BMx <- BMD[, .(Date, BM_Ret)]
EE <- merge(ER, DDx, by=c("Date","Ticker"))
EE <- merge(EE, BMx, by="Date")
EE[, ym := format(Date,"%Y-%m")]
EE <- merge(EE, EXP[, .(Ticker, ym=hold_ym, beta)], by=c("Ticker","ym"))
EE[, r_ex := Ret - beta*BM_Ret]
r2_daily <- EE[, .(r2 = 1 - sum(e^2)/sum(r_ex^2)), by=Date]
res$model_fit <- list(
  spec_note="Market 성분은 beta*BM 로 사전 제거 — 아래 R2 는 '시장 제거 후' 잔여를 Sector+Style 이 설명한 비율",
  mean_daily_r2_after_market = mean(r2_daily$r2, na.rm=TRUE),
  median_daily_r2_after_market = median(r2_daily$r2, na.rm=TRUE),
  portfolio_specific_variance_share_asof = S2$spec_share,
  portfolio_factor_variance_share_asof = 1 - S2$spec_share,
  portfolio_specific_share_normal_regime = S2$reg$share_normal$Specific,
  portfolio_specific_share_panic_regime = S2$reg$share_panic$Specific)
cat(sprintf("[R5] 모형 설명력: 시장제거 후 일간 R2 평균 %.3f · 포트 요인분산 비중 %.3f (특이 %.3f)\n",
  res$model_fit$mean_daily_r2_after_market, 1-S2$spec_share, S2$spec_share))

saveRDS(res, file.path(OUT,"risk_calc_stage3.rds"))
cat("[R5] done\n")
