# S5 — 실투형 후보 하나 (단일 측정 · arm 배터리 없음)
#   근접도(fh252 = GH2004 FH, in-house M06 규약) top-25 EW long-only · K200 union KQ150 ·
#   2005-01~2026-08 · 15bps one-way(delta) · Sigma w = 1 · 비중 상한 없음(v10) · 유동성 20일 평균 2e8
suppressWarnings(suppressMessages({
  library(data.table); library(jsonlite); library(arrow); library(sandwich); library(lmtest); library(xts)}))
ROOT <- Sys.getenv("QM_ROOT"); if (!nzchar(ROOT)) ROOT <- getwd(); setwd(ROOT)
Sys.setenv(CLAUDE_PROJECT_DIR = ROOT)
`%or%` <- function(a,b) if (is.null(a) || length(a)==0L || !is.finite(a[1])) b else a
source(file.path(ROOT, "02_Infrastructure/contracts/backtest_result_contract.R"))
source(file.path(ROOT, "02_Infrastructure/contracts/canonical_screen_bt.R"))
OUT <- file.path(ROOT, "stage_artifacts/WT_R20260829_007")
O2 <- readRDS(file.path(OUT, "s2_objects.rds")); O4 <- readRDS(file.path(OUT, "s4_objects.rds"))
E0 <- O2$E0; R <- O2$R; bench <- O2$bench; P <- O4$P
SIZE <- unique(E0[, .(Date, Ticker, Size)])
COST_BPS <- 15; PPY <- 12L

beta_alpha <- function(x, b) { k <- which(is.finite(x) & is.finite(b)); x <- x[k]; b <- b[k]
  f <- lm(x ~ b); ct <- coeftest(f, vcov = NeweyWest(f, lag = 3, prewhite = FALSE))
  list(alpha_ann = 12*ct[1,1], t_alpha = ct[1,3], se_alpha_ann = abs(12*ct[1,1])/abs(ct[1,3]),
       beta = ct[2,1], t_beta = ct[2,3], beta_contrib_ann = (ct[2,1]-1)*12*mean(b), n = length(x)) }
nw_t <- function(x) { x <- x[is.finite(x)]; if (length(x) < 8L) return(NA_real_)
  m <- lm(x ~ 1); as.numeric(coeftest(m, vcov=NeweyWest(m, lag=3, prewhite=FALSE))[1,3]) }

## ── 후보 실측 (canonical_screen_bt = 계약 경유 실측) ────────────────────────
SC <- E0[is.finite(fh252), .(Date, Ticker, score = fh252)]
cs <- canonical_screen_bt(SC, R, bench, top_n = 25L, cost_bps_oneway = COST_BPS, liq_dt = NULL,
                          run_id = "WT-R20260829_007_prod", strategy_id = "GH2004_52wHigh_proximity_top25",
                          diag_dual_basis = TRUE, size_dt = SIZE)
pr <- as.data.table(cs$period_returns)
ba <- beta_alpha(pr$ret_net, pr$benchmark_ret)
act <- pr$ret_net - pr$benchmark_ret
cat(sprintf("[S5] PORT_t=%+.3f | a=%+.2f%%/yr t(a)=%+.3f b=%.3f | IR=%+.3f netSR=%+.3f | TO=%.2f/yr | n=%d\n",
            cs$portfolio_alpha_t_nw_lag3, 100*ba$alpha_ann, ba$t_alpha, ba$beta,
            cs$information_ratio %or% NA_real_, mean(act)/sd(act)*sqrt(12), cs$turnover_annual, nrow(pr)))

## ── 보유 종목 재현 (회전율/집중도/n_max 실측) ───────────────────────────────
SS <- copy(SC); setorder(SS, Date, -score)
W <- SS[, { n <- .N; k <- min(25L, n); list(Ticker = Ticker[seq_len(k)], w = rep(1/k, k)) }, by = Date]
dts <- sort(unique(W$Date)); traded <- numeric(length(dts)); prev <- data.table(Ticker=character(0), w=numeric(0))
for (i in seq_along(dts)) { cur <- W[Date == dts[i], .(Ticker, w)]
  m <- merge(cur, prev, by="Ticker", all=TRUE, suffixes=c("_cur","_prev"))
  m[is.na(w_cur), w_cur := 0]; m[is.na(w_prev), w_prev := 0]
  traded[i] <- sum(abs(m$w_cur - m$w_prev)); prev <- cur }
turnover_annual <- mean(traded)*12
n_by_date <- W[, .N, by = Date]
cat(sprintf("[S5] 회전율 실측 = %.1f%%/yr (월 평균 traded %.3f) | n_max=%d n_med=%.0f\n",
            100*turnover_annual, mean(traded), max(n_by_date$N), median(n_by_date$N)))

## ── period_returns_production.csv (신호월 라벨 + 벤치마크) ──────────────────
PRD <- data.table(signal_date = pr$date,
                  signal_ym = format(pr$date, "%Y-%m"),
                  holding_ym = format(as.Date(vapply(pr$date, function(d)
                    as.character(seq(as.Date(format(d, "%Y-%m-01")), by="month", length.out=2)[2]), character(1))), "%Y-%m"),
                  ret_gross = pr$ret_net + (traded[match(pr$date, dts)]*COST_BPS/1e4),
                  cost = traded[match(pr$date, dts)]*COST_BPS/1e4,
                  ret_net = pr$ret_net,
                  benchmark_ret = pr$benchmark_ret,
                  active_net = pr$ret_net - pr$benchmark_ret,
                  n_names = n_by_date$N[match(pr$date, n_by_date$Date)],
                  traded_notional = traded[match(pr$date, dts)])
fwrite(PRD, file.path(OUT, "period_returns_production.csv"))
cat(sprintf("[S5] period_returns_production.csv 저장 %d행 (%s ~ %s)\n", nrow(PRD),
            min(PRD$signal_ym), max(PRD$signal_ym)))

## ── FF3 / Carhart4 (H5 병기 의무) ───────────────────────────────────────────
mf <- tryCatch({
  source(file.path(ROOT, "02_Infrastructure/factor_portfolios.R"), local = TRUE)
  fdt <- load_kr_factor_returns()
  sx <- xts(pr$ret_net, order.by = as.Date(pr$date))
  bx <- xts(pr$benchmark_ret, order.by = as.Date(pr$date))
  run_multifactor_regression(sx, bx, fdt) }, error = function(e) list(error = conditionMessage(e)))
mf_out <- if (!is.null(mf$error)) list(error = mf$error) else
  lapply(names(mf), function(nm) list(model = nm, alpha_monthly = mf[[nm]]$alpha,
    alpha_annual_pct = 100*12*mf[[nm]]$alpha, alpha_t = mf[[nm]]$alpha_tstat,
    adj_r2 = mf[[nm]]$adj_r2 %or% NA_real_))
if (is.null(mf$error)) names(mf_out) <- names(mf)
cat("[S5] multifactor:\n"); if (is.null(mf$error)) for (nm in names(mf_out))
  cat(sprintf("   %-10s alpha=%+6.2f%%/yr t=%+6.3f\n", nm, mf_out[[nm]]$alpha_annual_pct, mf_out[[nm]]$alpha_t)) else cat("   ERROR:", mf$error, "\n")

## ── 진단 배터리 (advisory) ──────────────────────────────────────────────────
PR <- merge(P[, .(Date, Ticker, fh252, Ret_1m, mkt, Size, rv63)], SIZE, by=c("Date","Ticker"), all.x=TRUE, suffixes=c("",".y"))
ic <- PR[is.finite(fh252) & is.finite(Ret_1m), .(ic = cor(fh252, Ret_1m, method="spearman"), n=.N), by=Date][n>=30]
rank_ic <- mean(ic$ic); icir <- rank_ic/sd(ic$ic); harvey_t <- nw_t(ic$ic)
## size 중립화 후 IC
PR[, fh_resid := { f <- lm(fh252 ~ log(pmax(Size,1)) + rv63, data=.SD); r <- rep(NA_real_, .N)
                   k <- as.integer(names(residuals(f))); r[k] <- residuals(f); r }, by = Date]
ic_n <- PR[is.finite(fh_resid) & is.finite(Ret_1m), .(ic = cor(fh_resid, Ret_1m, method="spearman"), n=.N), by=Date][n>=30]
post_ic <- mean(ic_n$ic)
## 데실 단조성
PR[, dec := as.integer(pmin(10L, 1L + floor((frank(fh252, ties.method="first")-0.5)/.N*10))), by = Date]
decs <- PR[is.finite(Ret_1m), .(r_ann = 12*mean(Ret_1m)), by = dec][order(dec)]
mono <- cor(decs$dec, decs$r_ann, method="spearman")
## subperiod (활성 net)
sub <- data.table(date = pr$date, a = act)[, per := fifelse(date < as.Date("2015-01-01"), "P1_2005_2014",
                      fifelse(date < as.Date("2020-01-01"), "P2_2015_2019", "P3_2020_2026"))]
subs <- sub[, .(n = .N, active_ann = 12*mean(a), sr = mean(a)/sd(a)*sqrt(12), nw_t = nw_t(a)), by = per][order(per)]
sub_stab <- mean(subs$sr > 0)
## oos_retention (anchored 3분할 {55/65/75} 중앙값 — 활성 SR 기준 근사)
oosr <- vapply(c(0.55, 0.65, 0.75), function(f) { k <- floor(length(act)*f)
  is_sr <- mean(act[1:k])/sd(act[1:k]); oo_sr <- mean(act[(k+1):length(act)])/sd(act[(k+1):length(act)])
  if (!is.finite(is_sr) || is_sr <= 0) NA_real_ else oo_sr/is_sr }, numeric(1))
oos_ret <- median(oosr, na.rm = TRUE)
## DSR (진단 — chain 이므로 게이트 아님)
sr_m <- mean(act)/sd(act); n_m <- length(act)
sk <- mean(((act-mean(act))/sd(act))^3); ku <- mean(((act-mean(act))/sd(act))^4)
dsr <- pnorm((sr_m*sqrt(n_m-1))/sqrt(1 - sk*sr_m + (ku-1)/4*sr_m^2))
cat(sprintf("[S5] rank_IC=%.4f ICIR=%.3f harvey_t=%+.3f | post-neut IC=%.4f | mono=%.3f | sub_stab=%.2f | oos_ret=%.3f | DSR=%.3f\n",
            rank_ic, icir, harvey_t, post_ic, mono, sub_stab, oos_ret, dsr))
print(subs)

## ── 창 도달가능성 상한 (2.95 미달 보고 시 의무) ─────────────────────────────
reach <- list(n_months = length(act), sd_monthly_active = sd(act),
              required_active_ann_for_t295 = 2.95*sd(act)/sqrt(length(act))*12,
              observed_active_ann = 12*mean(act),
              coverage_ratio = (12*mean(act))/(2.95*sd(act)/sqrt(length(act))*12))

## ── 사후 검정력 (관측 SE 기준) ──────────────────────────────────────────────
mde80_post <- 2.8016*ba$se_alpha_ann
post_power <- lapply(list(A_raw = 12*0.0016, A_riskadj = 12*0.0027, C_ff3 = 0.0346), function(v)
  list(effect_ann = v, mde80_ann = mde80_post, ratio = v/mde80_post,
       expected_t = (v/mde80_post)*2.8016, power = pnorm((v/mde80_post)*2.8016 - 1.96)))

res <- list(
  meta = list(wt_id = "WT-R20260829_007", metric_type = "canonical_screen",
              engine = "02_Infrastructure/contracts/canonical_screen_bt.R (계약 경유 실측 — proxy 손계산 0)",
              n_months = nrow(pr), window = paste(as.character(range(pr$date)), collapse=" ~ "),
              single_measurement_note = "★도훈 지시 1: arm 배터리 폐지. 대비 arm / 탐색 arm / 아티팩트 대조 / 무신호 대조를 세션 차원에서 짓지 않았다. 한 시도 = 실투형 후보 하나."),
  spec = list(
    signal = "fh252 = Close_t / max(Close, 최근 252 거래일) — GH2004 FH(P/high), in-house M06_High_52w 규약과 bit 동일(S4 parity |rho|=1.0000)",
    selection = "월말 근접도 상위 25종", weighting = "EW · Sigma w = 1 · 개별 비중 상한 없음(v10)",
    long_only = TRUE, max_names = 25L, rebalance = "monthly",
    universe = "K200 union KQ150 (PIT 시변 멤버십)",
    liquidity = "20일 평균 거래대금(t-1) >= 2e8 KRW · liq_ruler = adv20_t1",
    cost = "15bps one-way, delta 기반 (v2.4_kr_retail_15bps)",
    window = "2005-01-31 ~ 2026-08 (신호월 라벨)",
    skip_convention = "실투 후보는 skip 없음(월말 종가로 결정·집행). GH2004 의 1개월 skip 은 **회귀 검정 규약**이며 F1 에만 적용했다(H2 승계).",
    paper_assumption_broken = list(
      paper_spec = "GH2004 = 상위 30% winner(K200 union KQ150 에서 ~100종) · 6개월 보유 · 6 vintage 중첩(최대 ~150종) · EW",
      implemented = "상위 25종 · 1개월 보유 · 단일 vintage · EW",
      n_before_truncation_median = median(SC[, .N, by=Date]$N)*0.30,
      reason = "고정 축 max_names 25 (lean-loop E-5). 종목수 논문값이 25 를 넘으면 상위 25 로 절단하고 절단 사실과 절단 전 N 을 기록한다.",
      note = "제약 완화를 레버로 제시하지 않는다(INV-7). 절단은 문제의 정의이지 결함이 아니다.")),
  measurements = list(
    portfolio_alpha_t_nw_lag3 = cs$portfolio_alpha_t_nw_lag3,
    portfolio_alpha_t_pvalue = cs$portfolio_alpha_t_pvalue %or% NA_real_,
    alpha_annualized = cs$alpha_annualized %or% NA_real_,
    information_ratio = cs$information_ratio %or% NA_real_,
    net_sr_active = mean(act)/sd(act)*sqrt(12),
    mean_active_net_ann = 12*mean(act),
    beta_controlled = ba,
    turnover_annual_measured = turnover_annual,
    turnover_annual_from_contract = cs$turnover_annual,
    n_names_max = max(n_by_date$N), n_names_median = median(n_by_date$N),
    selected_ret_coverage = cs$selected_ret_coverage %or% NA_real_,
    liq_ruler = cs$liq_ruler %or% NA_character_,
    prior_run_turnover_reference = 6.64,
    diag_ew_universe = cs$diag_ew_universe, diag_cap_tier = cs$diag_cap_tier),
  multifactor_alpha = mf_out,
  advisory_battery = list(rank_ic = rank_ic, icir = icir, harvey_t_stat = harvey_t,
    post_neutralization_ic = post_ic, post_neutralization_retention = post_ic/rank_ic,
    monotonicity_spearman = mono, decile_ann_returns = decs$r_ann,
    subperiod = lapply(split(subs, seq_len(nrow(subs))), as.list), subperiod_stability = sub_stab,
    oos_retention_v2_median = oos_ret, oos_retention_splits = oosr,
    deflated_sharpe_ratio = dsr,
    note = "rank-IC 계열은 advisory. portfolio-alpha t 와 명시 구분(measurement-graduation §2)."),
  reachability_ceiling = reach,
  post_hoc_power = post_power)
write_json(res, file.path(OUT, "s5_production.json"), pretty = TRUE, auto_unbox = TRUE, digits = 8, na = "null")
saveRDS(list(cs = cs, pr = pr, W = W, PRD = PRD, ba = ba, PR = PR, ic = ic, decs = decs,
             subs = subs, reach = reach, turnover_annual = turnover_annual, mf_out = mf_out),
        file.path(OUT, "s5_objects.rds"))
cat(sprintf("\n[S5] 창 도달가능성: 필요 활성 %+.2f%%/yr · 관측 %+.2f%%/yr · 비율 %.3f\n",
            100*reach$required_active_ann_for_t295, 100*reach$observed_active_ann, reach$coverage_ratio))
cat("[S5] done\n")
