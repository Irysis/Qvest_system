# S2 — 4셀 직교 분해 + 양성대조(parity) + 대비 (WT-R20260829_002)
suppressWarnings(suppressMessages({
  library(data.table); library(jsonlite); library(sandwich); library(lmtest)}))
ROOT <- Sys.getenv("QM_ROOT"); if (!nzchar(ROOT)) ROOT <- getwd()
setwd(ROOT); Sys.setenv(CLAUDE_PROJECT_DIR = ROOT)
`%or%` <- function(a, b) if (is.null(a) || length(a) == 0L || !is.finite(a[1])) b else a
source(file.path(ROOT, "02_Infrastructure/contracts/backtest_result_contract.R"))
source(file.path(ROOT, "02_Infrastructure/contracts/canonical_screen_bt.R"))
source(file.path(ROOT, "02_Infrastructure/contracts/required_effect_size.R"))
OUT <- file.path(ROOT, "stage_artifacts/WT_R20260829_002")
P <- readRDS(file.path(OUT, "panel.rds"))
FACTORS <- P$FACTORS; fwd <- P$fwd; SIZE <- P$SIZE

LIQ_MIN <- 2e8; COST_BPS <- 15; PPY <- 12L
returns_dt <- fwd$returns_dt; bench_dt <- fwd$bench_dt; liq_dt <- fwd$liq_dt

## 공통 적격집합: 유니버스 INTERSECT 유동성(20d ADV t-1 >= 2e8) — 4셀 전부 동일
S <- merge(FACTORS[, .(Date, Ticker, score = Score)],
           liq_dt[, .(Date, Ticker, adv)], by = c("Date","Ticker"), all.x = TRUE)
n_before <- nrow(S); n_na <- sum(is.na(S$adv))
S <- S[is.na(adv) | adv >= LIQ_MIN][, adv := NULL]
cat(sprintf("[S2] eligible: %d -> %d (adv NA pass %d) | monthly median names %.0f\n",
            n_before, nrow(S), n_na, median(S[, .N, by = Date]$N)))
elig_n <- S[, .(n = .N), by = Date][order(Date)]

R <- as.data.table(returns_dt)[!is.na(Ret_1m)]

## 범용 셀 엔진 (canonical_screen_bt 내부식과 동일 — 아래 parity 로 실증)
cell_bt <- function(S, R, bench, mode = c("lo","ls"), n_fixed = NA_integer_, frac = NA_real_,
                    run_id = "cell", strategy_id = "cell") {
  mode <- match.arg(mode)
  SS <- copy(S); setorder(SS, Date, -score)
  W <- SS[, {
    n <- .N
    k <- if (is.finite(n_fixed)) min(as.integer(n_fixed), n) else max(2L, as.integer(ceiling(n * frac)))
    if (mode == "lo") {
      list(Ticker = Ticker[seq_len(k)], w = rep(1/k, k))
    } else {
      if (n < 2L*k) list(Ticker = character(0), w = numeric(0))
      else list(Ticker = c(Ticker[seq_len(k)], Ticker[(n-k+1L):n]),
                w = c(rep(1/k, k), rep(-1/k, k)))
    }
  }, by = Date]
  W <- W[!is.na(Ticker)]
  WR <- merge(W, R[, .(Date, Ticker, Ret_1m)], by = c("Date","Ticker"), all.x = TRUE)
  sel_cov <- WR[, mean(!is.na(Ret_1m))]
  WR[is.na(Ret_1m), Ret_1m := 0]
  port <- WR[, .(port_gross = sum(w * Ret_1m)), by = Date]
  dts <- sort(unique(W$Date)); traded <- numeric(length(dts)); names(traded) <- as.character(dts)
  prev <- data.table(Ticker = character(0), w = numeric(0))
  for (i in seq_along(dts)) {
    cur <- W[Date == dts[i], .(Ticker, w)]
    m <- merge(cur, prev, by = "Ticker", all = TRUE, suffixes = c("_cur","_prev"))
    m[is.na(w_cur), w_cur := 0]; m[is.na(w_prev), w_prev := 0]
    traded[i] <- sum(abs(m$w_cur - m$w_prev)); prev <- cur
  }
  port[, traded := traded[as.character(Date)]]
  port[, cost := traded * COST_BPS / 1e4]
  port[, ret_net := port_gross - cost]
  pr <- merge(port[, .(date = Date, ret_net)], bench[, .(date = Date, benchmark_ret = BM_Ret)], by = "date")
  bc <- build_benchmark_compare(
    data.table(date = pr$date, ret_net = pr$ret_net, frequency = "monthly"),
    data.table(date = pr$date, benchmark_ret = pr$benchmark_ret, benchmark_id = "KOSPI200_total_return"),
    run_id = run_id, strategy_id = strategy_id, annualization_factor = PPY)
  g <- function(nm) { v <- bc[metric_name == nm, active_value]; if (!length(v)) NA_real_ else as.numeric(v[1]) }
  active <- pr$ret_net - pr$benchmark_ret
  list(W = W, WR = WR, port = port, pr = pr, bc = bc,
       n_months = nrow(pr), sel_cov = sel_cov,
       port_t = g("Portfolio_Alpha_t_NW_lag3"), port_p = g("Portfolio_Alpha_t_pvalue"),
       ir = g("Information_Ratio"), alpha_ann = g("Alpha_Annualized"),
       net_sr = mean(active)/stats::sd(active)*sqrt(PPY),
       mean_active_net = mean(active),
       turnover_annual = mean(port$traded, na.rm = TRUE) * PPY,
       n_names_med = median(W[, .N, by = Date]$N),
       n_names_max = max(W[, .N, by = Date]$N))
}

## beta-통제 alpha (NW lag-3)
beta_alpha <- function(x, b) {
  k <- which(is.finite(x) & is.finite(b)); x <- x[k]; b <- b[k]
  f <- lm(x ~ b); ct <- coeftest(f, vcov = NeweyWest(f, lag = 3, prewhite = FALSE))
  c(alpha_ann = 12*ct[1,1], t_alpha = ct[1,3], beta = ct[2,1], t_beta = ct[2,3],
    beta_contrib_ann = (ct[2,1]-1)*12*mean(b), n = length(x))
}
nw_t1 <- function(x) { x <- x[is.finite(x)]; m <- lm(x ~ 1)
  as.numeric(coeftest(m, vcov = NeweyWest(m, lag = 3, prewhite = FALSE))[1,3]) }

## 4셀
DEC <- 0.10   # JT1993 데실
cells <- list(
  cell1_LS_decile = cell_bt(S, R, bench_dt, "ls", frac = DEC, run_id="c1", strategy_id="cell1_LS_decile"),
  cell2_LO_decile = cell_bt(S, R, bench_dt, "lo", frac = DEC, run_id="c2", strategy_id="cell2_LO_decile"),
  cell3_LS_top25  = cell_bt(S, R, bench_dt, "ls", n_fixed = 25L, run_id="c3", strategy_id="cell3_LS_top25"),
  cell4_LO_top25  = cell_bt(S, R, bench_dt, "lo", n_fixed = 25L, run_id="c4", strategy_id="cell4_LO_top25"))

## 양성 대조: cell4 == canonical_screen_bt(top_n=25) parity
cs4 <- canonical_screen_bt(S, R, bench_dt, top_n = 25L, cost_bps_oneway = COST_BPS,
                           liq_dt = NULL, run_id = "canon_c4", strategy_id = "cell4_canon",
                           diag_dual_basis = TRUE, size_dt = SIZE)
par_ret <- max(abs(cells$cell4_LO_top25$pr$ret_net - cs4$period_returns$ret_net))
par_t   <- abs(cells$cell4_LO_top25$port_t - cs4$portfolio_alpha_t_nw_lag3)
cat(sprintf("[S2][PARITY] cell4 vs canonical_screen_bt: max abs dret=%.3e | abs dport_t=%.3e | n=%d/%d\n",
            par_ret, par_t, cells$cell4_LO_top25$n_months, cs4$n_months))

## 셀별 진단(EW-유니버스 / cap-tier) — 계약 헬퍼 경유
univ_pre <- unique(S[, .(Date, Ticker)])
diags <- lapply(names(cells), function(nm) {
  cl <- cells[[nm]]
  ew <- tryCatch(.canon_diag_ew_universe(univ_pre, R, cl$pr, nm, nm, PPY),
                 error = function(e) list(error = conditionMessage(e)))
  ct <- tryCatch(.canon_diag_cap_tier(cl$WR, SIZE, PPY),
                 error = function(e) list(available = FALSE, error = conditionMessage(e)))
  list(ew = ew, cap = ct)
}); names(diags) <- names(cells)

## 롱/숏 레그 개별 (IM2013 레그별 분해)
leg_ret <- function(cl, side) {
  x <- cl$WR[if (side == "long") w > 0 else w < 0]
  x[, .(r = sum(abs(w)*Ret_1m)/sum(abs(w))), by = Date][order(Date)]
}
legs <- list(
  win_decile  = leg_ret(cells$cell1_LS_decile, "long"),
  lose_decile = leg_ret(cells$cell1_LS_decile, "short"),
  win_top25   = leg_ret(cells$cell3_LS_top25, "long"),
  lose_bot25  = leg_ret(cells$cell3_LS_top25, "short"))

## 대비(동월 짝지음)
mk <- function(a, b) {
  m <- merge(cells[[a]]$pr[, .(date, ra = ret_net)], cells[[b]]$pr[, .(date, rb = ret_net)], by = "date")
  m <- merge(m, bench_dt[, .(date = Date, bm = BM_Ret)], by = "date")
  m[, d := ra - rb][]
}
C21 <- mk("cell2_LO_decile","cell1_LS_decile")   # 축 A: 숏 레그 제거
C42 <- mk("cell4_LO_top25","cell2_LO_decile")    # 축 B: 데실 -> top25
C31 <- mk("cell3_LS_top25","cell1_LS_decile")    # 축 B (롱숏 하)
mkc <- function(M) list(mean_ann = 12*mean(M$d), nw_t = nw_t1(M$d), sd_monthly = sd(M$d),
                        n = nrow(M), beta_alpha = as.list(beta_alpha(M$d, M$bm)))
contrasts <- list(A_c2_minus_c1 = mkc(C21), B_c4_minus_c2 = mkc(C42), B_LS_c3_minus_c1 = mkc(C31))

## 검정력 계약 (착수 관문 — 실측 sd 로 재산출)
pw <- function(sd_m, n, implied_monthly, series) {
  re <- required_effect(n = n, t_threshold = 2.0, sd_monthly = sd_m, design = "full", series = series)
  mde80 <- re$required_monthly * (2.8016/2.0)
  ratio <- implied_monthly / mde80
  list(n = n, sd_monthly = sd_m, nw_inflation = re$nw_inflation,
       nw_inflation_source = re$nw_inflation_source,
       mde80_monthly = mde80, implied_monthly = implied_monthly,
       ratio = ratio, expected_t = ratio*2.8016, power = pnorm(ratio*2.8016 - 1.96))
}
IM_SHORT_LEG_ANN <- 0.0494   # IM2013 Table 1: Down 포트 CAPM alpha -4.94%/yr
power_A <- pw(sd(C21$d), nrow(C21), IM_SHORT_LEG_ANN/12, C21$d)
is_n <- floor(nrow(C42)/3)
power_B <- pw(sd(C42$d), nrow(C42), abs(mean(C42$d[1:is_n])), C42$d)
power_B$implied_source <- sprintf("IS-only(first %d months) 실측 앵커 — IM2013 은 집중 형태 효과크기 미제공", is_n)

res <- list(
  meta = list(wt_id = "WT-R20260829_002", as_of = "2026-08-29",
              metric_type = "canonical_screen",
              liq_ruler = fwd$liq_ruler, liq_ruler_source = fwd$liq_ruler_source,
              cost_bps_oneway = COST_BPS, liq_min = LIQ_MIN,
              n_sig_months = uniqueN(S$Date), elig_names_median = median(elig_n$n),
              elig_names_min = min(elig_n$n), elig_names_max = max(elig_n$n)),
  parity = list(max_abs_ret_diff = par_ret, abs_port_t_diff = par_t,
                canon_port_t = cs4$portfolio_alpha_t_nw_lag3,
                engine_port_t = cells$cell4_LO_top25$port_t,
                verdict = if (par_ret < 1e-10 && par_t < 1e-8) "PARITY_EXACT" else "PARITY_FAIL"),
  cells = setNames(lapply(names(cells), function(nm) {
    cl <- cells[[nm]]; dg <- diags[[nm]]
    ba <- beta_alpha(cl$pr$ret_net, cl$pr$benchmark_ret)
    list(id = nm, n_months = cl$n_months, n_names_median = cl$n_names_med, n_names_max = cl$n_names_max,
         port_t_capw = cl$port_t, port_p = cl$port_p, ir = cl$ir, alpha_annualized = cl$alpha_ann,
         net_sr = cl$net_sr, mean_active_net_ann = 12*cl$mean_active_net,
         turnover_annual = cl$turnover_annual, selected_ret_coverage = cl$sel_cov,
         beta_controlled = as.list(ba),
         diag_ew_universe = list(port_t = dg$ew$portfolio_alpha_t_nw_lag3,
                                 alpha_ann = dg$ew$alpha_annualized,
                                 ir = dg$ew$information_ratio, n_months = dg$ew$n_months),
         diag_cap_tier = if (isTRUE(dg$cap$available))
             list(weight_share_avg = dg$cap$weight_share_avg,
                  contrib_gross_annualized = dg$cap$contrib_gross_annualized)
           else list(available = FALSE))
  }), names(cells)),
  contrasts = contrasts,
  power = list(primary_axisA = power_A, secondary_axisB = power_B),
  cs4_diag = list(ew_port_t = cs4$diag_ew_universe$portfolio_alpha_t_nw_lag3,
                  cap_weight_share = cs4$diag_cap_tier$weight_share_avg)
)
write_json(res, file.path(OUT, "s2_cells.json"), pretty = TRUE, auto_unbox = TRUE, digits = 8, na = "null")
saveRDS(list(cells = cells, legs = legs, C21 = C21, C42 = C42, C31 = C31,
             S = S, R = R, bench = bench_dt, SIZE = SIZE, elig_n = elig_n, diags = diags),
        file.path(OUT, "s2_objects.rds"))

cat("\n===== 4 CELLS =====\n")
for (nm in names(cells)) { cl <- cells[[nm]]; ba <- beta_alpha(cl$pr$ret_net, cl$pr$benchmark_ret); dg <- diags[[nm]]
  cat(sprintf("%-16s n=%3d nmed=%3.0f | PORT_t(capw)=%+7.3f | a=%+6.2f%%/yr t(a)=%+6.3f b=%+5.2f | EWuniv_t=%+7.3f | IR=%+6.3f TO=%.2f\n",
    nm, cl$n_months, cl$n_names_med, cl$port_t, 100*ba[["alpha_ann"]], ba[["t_alpha"]], ba[["beta"]],
    dg$ew$portfolio_alpha_t_nw_lag3 %or% NA_real_, cl$ir, cl$turnover_annual)) }
cat("\n===== CONTRASTS =====\n")
for (nm in names(contrasts)) { x <- contrasts[[nm]]
  cat(sprintf("%-18s D=%+6.2f%%/yr NW-t=%+6.3f | beta-ctl a=%+6.2f%%/yr t(a)=%+6.3f b=%+5.2f (n=%d)\n",
    nm, 100*x$mean_ann, x$nw_t, 100*x$beta_alpha$alpha_ann, x$beta_alpha$t_alpha, x$beta_alpha$beta, x$n)) }
cat("\n===== POWER =====\n")
cat(sprintf("axisA(1st): sd=%.4f MDE80=%.5f implied=%.5f ratio=%.4f E[t]=%.3f power=%.3f (nw_infl=%.3f %s)\n",
  power_A$sd_monthly, power_A$mde80_monthly, power_A$implied_monthly, power_A$ratio,
  power_A$expected_t, power_A$power, power_A$nw_inflation, power_A$nw_inflation_source))
cat(sprintf("axisB(2nd): sd=%.4f MDE80=%.5f implied=%.5f ratio=%.4f E[t]=%.3f power=%.3f (nw_infl=%.3f %s)\n",
  power_B$sd_monthly, power_B$mde80_monthly, power_B$implied_monthly, power_B$ratio,
  power_B$expected_t, power_B$power, power_B$nw_inflation, power_B$nw_inflation_source))
