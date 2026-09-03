# S5b — strict-PIT A/B (ast_verify FAIL_LOOKAHEAD 대응)
#   ast_field_map_v0 의 A1_RAWDATA_OHLCVS_daily 가용성 규칙 = "t1" (일자 d 의 종가는 d+1 에 가용).
#   request.json data_lag_rules 도 price = "t-1 close" 다.
#   그런데 하네스 관행(canonical_screen_bt · 기저 arm · 2/20 cell4 · 3/20)은 월말 t 종가로 결정하고
#   같은 종가로 집행한다 = 규약 불일치. 합리화하지 않고 **양쪽을 다 재서** 차이를 정량화한다.
#   published 사양 = strict (신호를 월말 직전 거래일 종가로 계산 -> TS_LAG(k=1, unit='d')).
suppressWarnings(suppressMessages({
  library(data.table); library(jsonlite); library(arrow); library(sandwich); library(lmtest); library(RcppRoll)}))
ROOT <- Sys.getenv("QM_ROOT"); if (!nzchar(ROOT)) ROOT <- getwd(); setwd(ROOT)
Sys.setenv(CLAUDE_PROJECT_DIR = ROOT)
`%or%` <- function(a,b) if (is.null(a) || length(a)==0L || !is.finite(a[1])) b else a
source(file.path(ROOT, "02_Infrastructure/contracts/backtest_result_contract.R"))
source(file.path(ROOT, "02_Infrastructure/contracts/canonical_screen_bt.R"))
OUT <- file.path(ROOT, "stage_artifacts/WT_R20260829_007")
O2 <- readRDS(file.path(OUT, "s2_objects.rds")); O5 <- readRDS(file.path(OUT, "s5_objects.rds"))
E0 <- O2$E0; R <- O2$R; bench <- O2$bench
SIZE <- unique(E0[, .(Date, Ticker, Size)])
ME <- sort(unique(E0$Date)); COST_BPS <- 15

beta_alpha <- function(x, b) { k <- which(is.finite(x) & is.finite(b)); x <- x[k]; b <- b[k]
  f <- lm(x ~ b); ct <- coeftest(f, vcov = NeweyWest(f, lag = 3, prewhite = FALSE))
  list(alpha_ann = 12*ct[1,1], t_alpha = ct[1,3], se_alpha_ann = abs(12*ct[1,1])/abs(ct[1,3]),
       beta = ct[2,1], t_beta = ct[2,3], beta_contrib_ann = (ct[2,1]-1)*12*mean(b), n = length(x)) }

## ── 월말 직전 거래일(t-1) 종가 기준 근접도 ──────────────────────────────────
RAW <- as.data.table(arrow::read_parquet(".cache/RAWDATA.parquet",
        col_select = c("Date","Ticker","Close","K200","KQ150")))
RAW[, Date := as.Date(Date)]
ever <- unique(RAW[K200 == TRUE | KQ150 == TRUE, Ticker])
RAW <- RAW[Ticker %in% ever & Date >= as.Date("2003-01-01") & is.finite(Close) & Close > 0]
setorder(RAW, Ticker, Date)
RAW[, hi252 := { n <- .N; if (n < 2L) NA_real_ else RcppRoll::roll_max(Close, n = min(252L, n), align="right", fill=NA) }, by = Ticker]
RAW[, fh_d := fifelse(is.finite(hi252) & hi252 > 0, Close/hi252, NA_real_)]
## 종목 시계열에서 1 거래일 lag -> 월말 t 행에 t-1 거래일 값이 실린다
RAW[, fh_lag1d := shift(fh_d, 1L), by = Ticker]
STRICT <- RAW[Date %in% ME, .(Date, Ticker, fh_lag1d, fh_same = fh_d)]
rm(RAW); gc(verbose = FALSE)

X <- merge(E0[, .(Date, Ticker, fh252)], STRICT, by = c("Date","Ticker"), all.x = TRUE)
cat(sprintf("[S5b] 대조: cor(fh252, fh_same) = %.6f (동일해야 함) | cor(fh252, fh_lag1d) Spearman 월평균 = %.5f | lag1d 가용 %.4f\n",
            cor(X$fh252, X$fh_same, use="pairwise"),
            X[is.finite(fh252) & is.finite(fh_lag1d), .(r = cor(fh252, fh_lag1d, method="spearman")), by=Date][, mean(r)],
            mean(is.finite(X$fh_lag1d))))

## ── strict 후보 실측 ────────────────────────────────────────────────────────
SCs <- X[is.finite(fh_lag1d), .(Date, Ticker, score = fh_lag1d)]
cs_s <- canonical_screen_bt(SCs, R, bench, top_n = 25L, cost_bps_oneway = COST_BPS, liq_dt = NULL,
                            run_id = "WT-R20260829_007_prod_strict",
                            strategy_id = "GH2004_52wHigh_proximity_top25_strictPIT",
                            diag_dual_basis = TRUE, size_dt = SIZE)
pr_s <- as.data.table(cs_s$period_returns); ba_s <- beta_alpha(pr_s$ret_net, pr_s$benchmark_ret)
act_s <- pr_s$ret_net - pr_s$benchmark_ret

SS <- copy(SCs); setorder(SS, Date, -score)
Wn <- SS[, { n <- .N; k <- min(25L, n); list(Ticker = Ticker[seq_len(k)], w = rep(1/k, k)) }, by = Date]
dts <- sort(unique(Wn$Date)); traded <- numeric(length(dts)); prev <- data.table(Ticker=character(0), w=numeric(0))
for (i in seq_along(dts)) { cur <- Wn[Date == dts[i], .(Ticker, w)]
  m <- merge(cur, prev, by="Ticker", all=TRUE, suffixes=c("_cur","_prev"))
  m[is.na(w_cur), w_cur := 0]; m[is.na(w_prev), w_prev := 0]
  traded[i] <- sum(abs(m$w_cur - m$w_prev)); prev <- cur }
to_s <- mean(traded)*12
n_by <- Wn[, .N, by = Date]

## ── 보유 종목 겹침 (두 사양의 실질 차이) ────────────────────────────────────
W0 <- O5$W
ov <- merge(W0[, .(Date, Ticker, a = TRUE)], Wn[, .(Date, Ticker, b = TRUE)], by = c("Date","Ticker"), all = TRUE)
ov_rate <- ov[, .(k = sum(!is.na(a) & !is.na(b)), n = 25), by = Date][, mean(k/n)]

## ── A/B 판정 ────────────────────────────────────────────────────────────────
ba0 <- O5$ba; pr0 <- O5$pr; act0 <- pr0$ret_net - pr0$benchmark_ret
ab <- list(
  same_close_convention = list(
    label = "동일종가 규약 (하네스 관행 — 기저 arm / 2/20 cell4 / 3/20 과 동일)",
    port_t = num0 <- O5$cs$portfolio_alpha_t_nw_lag3,
    beta_controlled = ba0, turnover_annual = O5$turnover_annual,
    active_ann = 12*mean(act0), net_sr = mean(act0)/sd(act0)*sqrt(12), n_months = length(act0)),
  strict_pit_t_minus_1 = list(
    label = "strict-PIT (신호 = 월말 직전 거래일 종가 · ast_field_map 'A1 t1' 규칙 정합 · TS_LAG(k=1,unit='d'))",
    port_t = cs_s$portfolio_alpha_t_nw_lag3, beta_controlled = ba_s, turnover_annual = to_s,
    active_ann = 12*mean(act_s), net_sr = mean(act_s)/sd(act_s)*sqrt(12), n_months = length(act_s),
    n_names_max = max(n_by$N), n_names_median = median(n_by$N),
    diag_ew_universe = cs_s$diag_ew_universe, diag_cap_tier = cs_s$diag_cap_tier,
    selected_ret_coverage = cs_s$selected_ret_coverage %or% NA_real_),
  holdings_overlap_rate = ov_rate,
  inflation_from_same_close = list(
    port_t_delta = O5$cs$portfolio_alpha_t_nw_lag3 - cs_s$portfolio_alpha_t_nw_lag3,
    beta_alpha_delta_ann = ba0$alpha_ann - ba_s$alpha_ann,
    active_ann_delta = 12*mean(act0) - 12*mean(act_s),
    relative_inflation_pct = 100*(12*mean(act0) - 12*mean(act_s))/abs(12*mean(act_s))),
  verdict_rule = "strict 대비 동일종가 규약의 인플레가 >5% 면 strict 값으로 재판정한다(PIT 오버레이 규약 준용).",
  published_spec = "strict_pit_t_minus_1 — PIT 가 제1법이므로 발행 사양은 엄격판이다.")
cat(sprintf("\n[S5b] same-close: PORT_t %+.3f a %+.2f%%/yr t %+.3f TO %.2f | strict: PORT_t %+.3f a %+.2f%%/yr t %+.3f TO %.2f | 보유 겹침 %.3f\n",
            ab$same_close_convention$port_t, 100*ba0$alpha_ann, ba0$t_alpha, ab$same_close_convention$turnover_annual,
            ab$strict_pit_t_minus_1$port_t, 100*ba_s$alpha_ann, ba_s$t_alpha, to_s, ov_rate))
cat(sprintf("[S5b] 인플레: PORT_t %+.3f · beta-통제 alpha %+.2f%%p · 활성수익 %+.2f%%p (상대 %+.1f%%)\n",
            ab$inflation_from_same_close$port_t_delta, 100*ab$inflation_from_same_close$beta_alpha_delta_ann,
            100*ab$inflation_from_same_close$active_ann_delta, ab$inflation_from_same_close$relative_inflation_pct))

## ── strict 진단 배터리 ──────────────────────────────────────────────────────
nw_t <- function(x) { x <- x[is.finite(x)]; if (length(x) < 8L) return(NA_real_)
  m <- lm(x ~ 1); as.numeric(coeftest(m, vcov=NeweyWest(m, lag=3, prewhite=FALSE))[1,3]) }
PRp <- merge(X[, .(Date, Ticker, fh_lag1d)], R, by = c("Date","Ticker"))
ic <- PRp[is.finite(fh_lag1d) & is.finite(Ret_1m), .(ic = cor(fh_lag1d, Ret_1m, method="spearman"), n=.N), by=Date][n>=30]
sub <- data.table(date = pr_s$date, a = act_s)[, per := fifelse(date < as.Date("2015-01-01"), "P1_2005_2014",
                     fifelse(date < as.Date("2020-01-01"), "P2_2015_2019", "P3_2020_2026"))]
subs <- sub[, .(n = .N, active_ann = 12*mean(a), sr = mean(a)/sd(a)*sqrt(12), nw_t = nw_t(a)), by = per][order(per)]
oosr <- vapply(c(0.55,0.65,0.75), function(f) { k <- floor(length(act_s)*f)
  i1 <- mean(act_s[1:k])/sd(act_s[1:k]); o1 <- mean(act_s[(k+1):length(act_s)])/sd(act_s[(k+1):length(act_s)])
  if (!is.finite(i1) || i1 <= 0) NA_real_ else o1/i1 }, numeric(1))
sr_m <- mean(act_s)/sd(act_s); n_m <- length(act_s)
sk <- mean(((act_s-mean(act_s))/sd(act_s))^3); ku <- mean(((act_s-mean(act_s))/sd(act_s))^4)
dsr <- pnorm((sr_m*sqrt(n_m-1))/sqrt(1 - sk*sr_m + (ku-1)/4*sr_m^2))
adv <- list(rank_ic = mean(ic$ic), icir = mean(ic$ic)/sd(ic$ic), harvey_t_stat = nw_t(ic$ic),
            subperiod = lapply(split(subs, seq_len(nrow(subs))), as.list),
            subperiod_stability = mean(subs$sr > 0),
            oos_retention_v2_median = median(oosr, na.rm=TRUE), oos_retention_splits = oosr,
            deflated_sharpe_ratio = dsr)
reach <- list(n_months = length(act_s), sd_monthly_active = sd(act_s),
              required_active_ann_for_t295 = 2.95*sd(act_s)/sqrt(length(act_s))*12,
              observed_active_ann = 12*mean(act_s),
              coverage_ratio = (12*mean(act_s))/(2.95*sd(act_s)/sqrt(length(act_s))*12))
cat(sprintf("[S5b] strict: rank_IC %.4f ICIR %.3f harvey_t %+.3f | oos_ret %.3f | DSR %.3f | 도달비율 %.3f\n",
            adv$rank_ic, adv$icir, adv$harvey_t_stat, adv$oos_retention_v2_median, dsr, reach$coverage_ratio))
print(subs)

## ── period_returns_production.csv 를 strict 로 재발행 ───────────────────────
PRD <- data.table(signal_date = pr_s$date, signal_ym = format(pr_s$date, "%Y-%m"),
  holding_ym = format(as.Date(vapply(pr_s$date, function(d)
    as.character(seq(as.Date(format(d, "%Y-%m-01")), by="month", length.out=2)[2]), character(1))), "%Y-%m"),
  ret_gross = pr_s$ret_net + traded[match(pr_s$date, dts)]*COST_BPS/1e4,
  cost = traded[match(pr_s$date, dts)]*COST_BPS/1e4,
  ret_net = pr_s$ret_net, benchmark_ret = pr_s$benchmark_ret,
  active_net = pr_s$ret_net - pr_s$benchmark_ret,
  n_names = n_by$N[match(pr_s$date, n_by$Date)],
  traded_notional = traded[match(pr_s$date, dts)],
  spec = "strict_pit_t_minus_1")
fwrite(PRD, file.path(OUT, "period_returns_production.csv"))
fwrite(O5$PRD[, spec := "same_close_convention"], file.path(OUT, "period_returns_same_close_ab.csv"))
cat(sprintf("[S5b] period_returns_production.csv (strict) %d행 재발행 + same-close A/B 별도 저장\n", nrow(PRD)))

write_json(list(
  meta = list(wt_id = "WT-R20260829_007", test = "strict-PIT A/B", metric_type = "canonical_screen",
              trigger = "ast_verify.py FAIL_LOOKAHEAD — ast_field_map_v0 A1_RAWDATA_OHLCVS_daily 가용성 't1' vs 하네스 동일종가 관행",
              principle = "합리화 금지(PIT 금지표현). 양쪽을 다 재고 엄격판을 발행 사양으로 삼는다."),
  ab = ab, strict_advisory = adv, strict_reachability = reach,
  strict_turnover_annual = to_s), file.path(OUT, "s5b_strict_pit.json"),
  pretty = TRUE, auto_unbox = TRUE, digits = 8, na = "null")
saveRDS(list(cs_s = cs_s, pr_s = pr_s, ba_s = ba_s, Wn = Wn, PRD = PRD, X = X, ab = ab,
             adv = adv, reach = reach, to_s = to_s, n_by = n_by), file.path(OUT, "s5b_objects.rds"))
cat("[S5b] done\n")
