## p3_diagnostics.R — WT-R20260829_001 Phase 3
## ① 기전 부수관측(사전등록 2급) ② advisory 진단 배터리 ③ 무신호 대조 ④ β-통제 α
## ⑤ lag1 PIT 스트레스(C01_SUE same-day known_discrepancy 대응) ⑥ 증분(이익 축 단독 대비)
suppressPackageStartupMessages({library(data.table); library(arrow); library(jsonlite)
                                library(sandwich); library(lmtest)})
setDTthreads(2)
QM <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(QM)
source(file.path(QM,"02_Infrastructure/contracts/backtest_result_contract.R"))
source(file.path(QM,"02_Infrastructure/contracts/canonical_screen_bt.R"))
source(file.path(QM,"02_Infrastructure/contracts/no_signal_control.R"))
source(file.path(QM,"02_Infrastructure/validation/statistical_defense.R"))
`%||%` <- function(a,b) if (is.null(a)) b else a

OUT <- "stage_artifacts/WT_R20260829_001"
TOP_N <- 25L; COST <- 15; LIQ_MIN <- 2e8; NQ <- 3L

FW    <- as.data.table(read_parquet(file.path(OUT,"panel_factors.parquet")))
RET   <- as.data.table(read_parquet(file.path(OUT,"panel_returns.parquet")))
BENCH <- as.data.table(read_parquet(file.path(OUT,"panel_bench.parquet")))
LIQ   <- as.data.table(read_parquet(file.path(OUT,"panel_liq.parquet")))
SC    <- as.data.table(read_parquet(file.path(OUT,"alpha_scores.parquet")))
for (nmx in c("FW","RET","BENCH","LIQ","SC")) { d <- get(nmx); d[, Date := as.Date(Date)] }
CS <- readRDS(file.path(OUT,"canonical_arms.rds"))
SIZE_DT <- FW[is.finite(Size), .(Date,Ticker,Size)]
## 자 라벨 복원 — adv 값은 p1 의 build_adv20_t1(당일 제외 20일 평균) 산출이나
## parquet 왕복에서 attr 가 소실된다(p2 경고의 원인). 값은 불변, 라벨만 재부착.
setattr(LIQ, "liq_ruler", "adv20_t1")
setattr(LIQ, "liq_ruler_source", "p1_build_adv20_t1_reattached")

.nwt <- function(x, lag=3L){ x <- x[is.finite(x)]; if(length(x) < 12L) return(NA_real_)
  m <- lm(x ~ 1); as.numeric(coeftest(m, vcov=NeweyWest(m, lag=lag, prewhite=FALSE))[1,3]) }
.ba <- function(r, bm, lag=3L){
  k <- is.finite(r) & is.finite(bm); if(sum(k) < 24L) return(list(alpha_ann=NA,beta=NA,t_alpha=NA))
  f <- lm(r[k] ~ bm[k]); ct <- coeftest(f, vcov=NeweyWest(f, lag=lag, prewhite=FALSE))
  list(alpha_ann=12*ct[1,1], beta=ct[2,1], t_alpha=ct[1,3],
       beta_contrib_ann=(ct[2,1]-1)*12*mean(bm[k])) }

RES <- list()

## ── 1. 기전 부수관측 (사전등록 2급) — joint-top vs joint-bottom 후속 개정 우위 ──
## PIT 라벨: 이 검정은 **사후 기전 검증**이다 — 신호 구성에 t+k 값을 쓰지 않는다.
SEL <- SC[, .(Date,Ticker,tm,ts)]
dts <- sort(unique(SEL$Date))
rev_cols <- c("C02_EPS_Chg_1m","C03_EPS_Chg_3m","C04_ESBR")
REVP <- FW[, c("Date","Ticker", rev_cols), with=FALSE]
mech <- rbindlist(lapply(seq_along(dts), function(i){
  d <- dts[i]
  tops <- SEL[Date==d & tm==NQ & ts==NQ, Ticker]
  bots <- SEL[Date==d & tm==1L & ts==1L, Ticker]
  if (length(tops) < 5L || length(bots) < 5L) return(NULL)
  rbindlist(lapply(1:3, function(k){
    if (i+k > length(dts)) return(NULL)
    dk <- dts[i+k]; P <- REVP[Date==dk]
    a <- P[Ticker %in% tops]; b <- P[Ticker %in% bots]
    if (nrow(a) < 5L || nrow(b) < 5L) return(NULL)
    data.table(Date=d, k=k,
      d_C02 = mean(a$C02_EPS_Chg_1m,na.rm=TRUE) - mean(b$C02_EPS_Chg_1m,na.rm=TRUE),
      d_C03 = mean(a$C03_EPS_Chg_3m,na.rm=TRUE) - mean(b$C03_EPS_Chg_3m,na.rm=TRUE),
      d_C04 = mean(a$C04_ESBR,na.rm=TRUE)       - mean(b$C04_ESBR,na.rm=TRUE),
      n_top=nrow(a), n_bot=nrow(b))
  }))
}), fill=TRUE)
MECH <- mech[, .(n_months=.N,
                 mean_C02=mean(d_C02,na.rm=TRUE), t_C02=.nwt(d_C02),
                 mean_C03=mean(d_C03,na.rm=TRUE), t_C03=.nwt(d_C03),
                 mean_C04=mean(d_C04,na.rm=TRUE), t_C04=.nwt(d_C04)), by=k]
setorder(MECH, k)
cat("\n===== 기전 부수관측: joint-top(3,3) vs joint-bottom(1,1) 후속 개정 z 격차 =====\n")
print(MECH)
RES$mechanism_observable <- as.list(MECH)
RES$mechanism_note <- "C02_EPS_Chg_1m 은 modal_frac 0.82 (커버 행의 82%가 동일값) — 질량점이 커 격차 해상도가 낮다. C04_ESBR(modal 0.024) 병기."

## ── 2. advisory 진단 배터리 ────────────────────────────────────────────────
SR <- merge(SC, RET, by=c("Date","Ticker"))
ic_of <- function(col){
  s <- SR[is.finite(get(col)) & is.finite(Ret_1m),
          .(ic = suppressWarnings(cor(get(col), Ret_1m, method="spearman")), n=.N), by=Date][n>=30]
  list(rank_ic=mean(s$ic,na.rm=TRUE), icir=mean(s$ic,na.rm=TRUE)/sd(s$ic,na.rm=TRUE),
       t_ic=.nwt(s$ic), n_months=nrow(s), series=s)
}
IC_joint <- ic_of("score_min_all"); IC_mom <- ic_of("score_mom"); IC_sue <- ic_of("score_sue")
cat(sprintf("\n[rank-IC] min-rank(2way연속) %.4f (ICIR %.3f, NW-t %.2f) | mom %.4f (%.3f, %.2f) | sue %.4f (%.3f, %.2f)\n",
  IC_joint$rank_ic, IC_joint$icir, IC_joint$t_ic, IC_mom$rank_ic, IC_mom$icir, IC_mom$t_ic,
  IC_sue$rank_ic, IC_sue$icir, IC_sue$t_ic))

## monotonicity — 십분위 단조성 (min-rank 연속판)
dec <- SR[is.finite(score_min_all) & is.finite(Ret_1m)]
dec[, dq := pmin(10L, floor(frank(score_min_all, ties.method="average")/.N*10)+1L), by=Date]
decm <- dec[, .(r=mean(Ret_1m)), by=.(Date,dq)][, .(r=mean(r)), by=dq][order(dq)]
mono <- suppressWarnings(cor(decm$dq, decm$r, method="spearman"))
cat(sprintf("[monotonicity] 십분위 Spearman = %.3f | 십분위 평균수익(%%): %s\n", mono,
  paste(sprintf("%.2f",100*decm$r), collapse=" ")))

## post-neutralization IC — size(log) 중립화 후
NEU <- merge(SR, SIZE_DT, by=c("Date","Ticker"))
NEU <- NEU[is.finite(Size) & Size>0 & is.finite(score_min_all) & is.finite(Ret_1m)]
NEU[, lsz := log(Size)]
NEU[, resid_score := { f <- try(lm(score_min_all ~ lsz), silent=TRUE)
                       if (inherits(f,"try-error")) NA_real_ else as.numeric(residuals(f)) }, by=Date]
pn <- NEU[is.finite(resid_score), .(ic=suppressWarnings(cor(resid_score, Ret_1m, method="spearman")), n=.N), by=Date][n>=30]
post_ic <- mean(pn$ic, na.rm=TRUE)
cat(sprintf("[post-neutral IC] size 중립화 후 %.4f (raw %.4f, 유지율 %.2f)\n",
  post_ic, IC_joint$rank_ic, post_ic/IC_joint$rank_ic))

## ── 3. arm 별 β-통제 α · subperiod · DSR · 무신호 대조 ──────────────────────
armstat <- list()
for (nm in names(CS)) {
  x <- CS[[nm]]; if (is.null(x) || is.null(x$period_returns)) next
  pr <- as.data.table(x$period_returns); pr[, date := as.Date(date)]
  act <- pr$ret_net - pr$benchmark_ret
  ba <- .ba(pr$ret_net, pr$benchmark_ret)
  sub <- rbindlist(lapply(list(c("2005-01-01","2014-12-31"),c("2015-01-01","2019-12-31"),
                               c("2020-01-01","2026-12-31")), function(w){
    k <- pr$date >= as.Date(w[1]) & pr$date <= as.Date(w[2])
    data.table(win=paste(substr(w[1],1,4),substr(w[2],1,4),sep="-"), n=sum(k),
               ann=12*mean(act[k],na.rm=TRUE), nw_t=.nwt(act[k]))
  }))
  sr_m <- mean(act,na.rm=TRUE)/sd(act,na.rm=TRUE)
  dsr <- compute_dsr(sr_m*sqrt(12), length(act), n_trials=5)
  armstat[[nm]] <- list(
    n_months = x$n_months, port_t = x$portfolio_alpha_t_nw_lag3,
    alpha_annual = x$alpha_annual, information_ratio = x$information_ratio,
    turnover_annual = x$turnover_annual, liq_ruler = x$liq_ruler,
    beta_alpha = ba, subperiod = as.list(sub),
    active_sr_ann = sr_m*sqrt(12), dsr = dsr$dsr,
    diag_ew_universe = x$diag_ew_universe, diag_cap_tier = x$diag_cap_tier)
  cat(sprintf("[%s] PORT_t %.3f | t(alpha) %.3f alpha %.2f%%/yr beta %.3f (beta기여 %.2f%%/yr) | subperiod t: %s\n",
    nm, x$portfolio_alpha_t_nw_lag3, ba$t_alpha, 100*ba$alpha_ann, ba$beta,
    100*ba$beta_contrib_ann, paste(sprintf("%.2f", sub$nw_t), collapse="/")))
}
RES$arms <- armstat

## 무신호 대조 (제약형 롱온리 의무)
J <- as.data.table(CS$joint2way$period_returns); J[, date := as.Date(date)]
months_chr <- format(J$date, "%Y-%m")
ctl <- tryCatch(build_no_signal_control(months_chr, n_stocks=TOP_N, cap=0.20, freq=1L, bps=COST),
                error=function(e){cat("[ERR ctl]",conditionMessage(e),"\n"); NULL})
if (!is.null(ctl)) {
  g <- tryCatch(no_signal_gate(J$ret_net, ctl$ret, J$benchmark_ret), error=function(e) NULL)
  if (!is.null(g)) {
    RES$no_signal_gate <- g
    cat(sprintf("\n[무신호 대조] verdict=%s | diff %.3f%%/yr NW-t %.3f | strat PORT_t %.3f vs ctl %.3f\n",
      g$verdict, 100*g$diff_ann, g$diff_nw_t, g$strategy[["port_t"]], g$control[["port_t"]]))
  }
}

## ── 4. lag1 PIT 스트레스 — C01_SUE 를 1개월 지연 적용 ────────────────────────
FL <- FW[, .(Date,Ticker,M02_Mom_6_1,C01_SUE,adv,K200,Size)]
setorder(FL, Ticker, Date)
FL[, sue_lag1 := shift(C01_SUE, 1L), by=Ticker]
FL[, dgap := as.integer(Date - shift(Date,1L)), by=Ticker]
EL <- FL[is.finite(M02_Mom_6_1) & is.finite(sue_lag1) & (is.na(adv)|adv>=LIQ_MIN) & dgap <= 40L]
EL[, n_m := .N, by=Date]; EL <- EL[n_m>=30L]
EL[, pm := (frank(M02_Mom_6_1, ties.method="average")-0.5)/.N, by=Date]
EL[, ps := (frank(sue_lag1,     ties.method="average")-0.5)/.N, by=Date]
EL[, tm := pmin(NQ, floor(pm*NQ)+1L)]; EL[, ts := pmin(NQ, floor(ps*NQ)+1L)]
S_lag <- EL[tm==NQ & ts==NQ, .(Date,Ticker,score=pmin(pm,ps))]
CS_lag <- tryCatch(canonical_screen_bt(S_lag, RET, BENCH, top_n=TOP_N, cost_bps_oneway=COST,
    liq_dt=LIQ, liq_min=LIQ_MIN, size_dt=SIZE_DT, run_id="lag1", strategy_id="joint2way_sue_lag1",
    diag_dual_basis=FALSE), error=function(e) NULL)
if (!is.null(CS_lag)) {
  RES$lag1_stress <- list(n_months=CS_lag$n_months, port_t=CS_lag$portfolio_alpha_t_nw_lag3,
    alpha_annual=CS_lag$alpha_annual, base_port_t=CS$joint2way$portfolio_alpha_t_nw_lag3,
    inflation_ratio = CS$joint2way$portfolio_alpha_t_nw_lag3 / CS_lag$portfolio_alpha_t_nw_lag3)
  cat(sprintf("\n[lag1 스트레스] SUE 1개월 지연: PORT_t %.3f (base %.3f) alpha %.2f%%/yr\n",
    CS_lag$portfolio_alpha_t_nw_lag3, CS$joint2way$portfolio_alpha_t_nw_lag3, 100*CS_lag$alpha_annual))
}

## ── 5. 증분 — 이익 축 단독 대비 2-way (동일 월 그리드 페어드) ────────────────
pr_of <- function(nm){ x <- CS[[nm]]; if (is.null(x)) return(NULL)
  p <- as.data.table(x$period_returns); p[, date := as.Date(date)]
  p[, .(date, act = ret_net - benchmark_ret, ret_net)] }
PJ <- pr_of("joint2way"); PS <- pr_of("sue_only"); PM <- pr_of("mom_only"); PZ <- pr_of("zsum_control")
inc <- function(A,B,lab){ m <- merge(A,B,by="date",suffixes=c("_a","_b"))
  d <- m$act_a - m$act_b
  list(label=lab, n=nrow(m), diff_ann=12*mean(d), nw_t=.nwt(d),
       cor_active=cor(m$act_a,m$act_b), cor_net=cor(m$ret_net_a,m$ret_net_b)) }
RES$increment <- list(vs_sue_only = inc(PJ,PS,"joint2way - sue_only"),
                      vs_mom_only = inc(PJ,PM,"joint2way - mom_only"),
                      vs_zsum     = inc(PJ,PZ,"joint2way - zsum_control"))
for (z in RES$increment) cat(sprintf("[증분] %-28s n=%d %+.3f%%/yr NW-t %+.3f | cor(active) %.3f\n",
  z$label, z$n, 100*z$diff_ann, z$nw_t, z$cor_active))

## ── 6. 기존 admitted 전략과의 상관 (중복 경보 대응) ──────────────────────────
inc_path <- "04_Research/strategies/STR_AS_20260612_161342_1312338/sim_result.rds"
if (file.exists(inc_path)) {
  s <- readRDS(inc_path)
  sx <- s$strategy_xts; bx <- s$bm_xts
  dd <- data.table(date=as.Date(zoo::index(sx)), r=as.numeric(sx), b=as.numeric(bx))
  dd[, ym := format(date, "%Y-%m")]
  mm <- dd[, .(r=prod(1+r)-1, b=prod(1+b)-1), by=ym]
  PJ2 <- copy(PJ)[, ym := format(date, "%Y-%m")]
  z <- merge(PJ2, mm, by="ym")
  RES$incumbent_overlap <- list(id="STR_AS_20260612_161342_1312338", n=nrow(z),
    cor_active = if (nrow(z)>=24) cor(z$act, z$r - z$b) else NA_real_,
    cor_net    = if (nrow(z)>=24) cor(z$ret_net, z$r) else NA_real_)
  cat(sprintf("\n[중복경보] incumbent STR_AS_...1312338 대비 cor(active)=%.3f cor(net)=%.3f (n=%d월)\n",
    RES$incumbent_overlap$cor_active, RES$incumbent_overlap$cor_net, nrow(z)))
}

RES$advisory <- list(rank_ic=IC_joint$rank_ic, icir=IC_joint$icir, harvey_t_rank_ic=IC_joint$t_ic,
  rank_ic_mom=IC_mom$rank_ic, rank_ic_sue=IC_sue$rank_ic,
  monotonicity=mono, decile_mean_ret=decm$r, post_neutralization_ic=post_ic)
saveRDS(RES, file.path(OUT,"diagnostics.rds"))
write_json(RES, file.path(OUT,"diagnostics.json"), auto_unbox=TRUE, na="null", digits=6)
cat("\n[p3] DONE\n")
