# S4 — 2급(사전등록): 소비 형태 arm 별 canonical 실측 + 무신호 대조 + EW-유니버스/cap-tier
# WT-R20260829_003 · 엔진은 2/20 과 동일(그때 canonical_screen_bt 와 bit-parity 실증) — 본 라운드도 재실증
suppressWarnings(suppressMessages({
  library(data.table); library(jsonlite); library(sandwich); library(lmtest); library(arrow)}))
ROOT <- Sys.getenv("QM_ROOT"); if (!nzchar(ROOT)) ROOT <- getwd(); setwd(ROOT)
Sys.setenv(CLAUDE_PROJECT_DIR = ROOT)
`%or%` <- function(a, b) if (is.null(a) || length(a) == 0L || !is.finite(a[1])) b else a
source(file.path(ROOT, "02_Infrastructure/contracts/backtest_result_contract.R"))
source(file.path(ROOT, "02_Infrastructure/contracts/canonical_screen_bt.R"))
source(file.path(ROOT, "02_Infrastructure/contracts/no_signal_control.R"))
OUT <- file.path(ROOT, "stage_artifacts/WT_R20260829_003")
O <- readRDS(file.path(OUT, "s2_objects.rds"))
E <- O$E; R <- O$R; bench_dt <- O$bench; SIZE <- O$SIZE
COST_BPS <- 15; PPY <- 12L

beta_alpha <- function(x, b) {
  k <- which(is.finite(x) & is.finite(b)); x <- x[k]; b <- b[k]
  f <- lm(x ~ b); ct <- coeftest(f, vcov = NeweyWest(f, lag = 3, prewhite = FALSE))
  c(alpha_ann = 12*ct[1,1], t_alpha = ct[1,3], beta = ct[2,1], t_beta = ct[2,3],
    beta_contrib_ann = (ct[2,1]-1)*12*mean(b), n = length(x)) }
nw_t1 <- function(x) { x <- x[is.finite(x)]; if (length(x) < 8L) return(NA_real_)
  m <- lm(x ~ 1); as.numeric(coeftest(m, vcov = NeweyWest(m, lag=3, prewhite=FALSE))[1,3]) }

## ── 엔진 (2/20 s2_cells.R 와 동일 코드) ─────────────────────────────────────
cell_bt <- function(S, R, bench, n_fixed = 25L, run_id = "arm", strategy_id = "arm") {
  SS <- copy(S); setorder(SS, Date, -score)
  W <- SS[, { n <- .N; k <- min(as.integer(n_fixed), n)
              list(Ticker = Ticker[seq_len(k)], w = rep(1/k, k)) }, by = Date]
  W <- W[!is.na(Ticker)]
  WR <- merge(W, R[, .(Date, Ticker, Ret_1m)], by = c("Date","Ticker"), all.x = TRUE)
  sel_cov <- WR[, mean(!is.na(Ret_1m))]; WR[is.na(Ret_1m), Ret_1m := 0]
  port <- WR[, .(port_gross = sum(w * Ret_1m)), by = Date]
  dts <- sort(unique(W$Date)); traded <- numeric(length(dts)); names(traded) <- as.character(dts)
  prev <- data.table(Ticker = character(0), w = numeric(0))
  for (i in seq_along(dts)) {
    cur <- W[Date == dts[i], .(Ticker, w)]
    m <- merge(cur, prev, by = "Ticker", all = TRUE, suffixes = c("_cur","_prev"))
    m[is.na(w_cur), w_cur := 0]; m[is.na(w_prev), w_prev := 0]
    traded[i] <- sum(abs(m$w_cur - m$w_prev)); prev <- cur }
  port[, traded := traded[as.character(Date)]]
  port[, cost := traded * COST_BPS / 1e4][, ret_net := port_gross - cost]
  pr <- merge(port[, .(date = Date, ret_net)], bench[, .(date = Date, benchmark_ret = BM_Ret)], by = "date")
  bc <- build_benchmark_compare(
    data.table(date = pr$date, ret_net = pr$ret_net, frequency = "monthly"),
    data.table(date = pr$date, benchmark_ret = pr$benchmark_ret, benchmark_id = "KOSPI200_total_return"),
    run_id = run_id, strategy_id = strategy_id, annualization_factor = PPY)
  g <- function(nm) { v <- bc[metric_name == nm, active_value]; if (!length(v)) NA_real_ else as.numeric(v[1]) }
  active <- pr$ret_net - pr$benchmark_ret
  list(W = W, WR = WR, port = port, pr = pr, n_months = nrow(pr), sel_cov = sel_cov,
       port_t = g("Portfolio_Alpha_t_NW_lag3"), port_p = g("Portfolio_Alpha_t_pvalue"),
       ir = g("Information_Ratio"), alpha_ann = g("Alpha_Annualized"),
       net_sr = mean(active)/stats::sd(active)*sqrt(PPY), mean_active_net = mean(active),
       turnover_annual = mean(port$traded, na.rm = TRUE)*PPY,
       n_names_med = median(W[, .N, by = Date]$N), n_names_max = max(W[, .N, by = Date]$N)) }

## ── arm 정의 ────────────────────────────────────────────────────────────────
S_all <- E[, .(Date, Ticker, score, mkt, tr, vter, adv, Size)]
arms_def <- list(
  A_uncond_top25      = S_all,                                   # 대조군 (= 2/20 cell4)
  B_lowturn_V1_top25  = S_all[vter == 1L],                       # 저회전 조건부 (선별형)
  B2_lowturn_half_top25 = S_all[tr <= 0.5],                      # 저회전 하위 절반 조건부
  C_exclude_V3_top25  = S_all[vter %in% c(1L,2L)],               # 배제형 (고회전 배제 + 후순위 대체)
  D_highturn_V3_top25 = S_all[vter == 3L])                       # 탐색: 반대 arm
arms <- lapply(names(arms_def), function(nm)
  cell_bt(arms_def[[nm]], R, bench_dt, 25L, run_id = nm, strategy_id = nm))
names(arms) <- names(arms_def)

## ── 양성 대조: arm A == canonical_screen_bt(top_n=25) ───────────────────────
csA <- canonical_screen_bt(S_all[, .(Date, Ticker, score)], R, bench_dt, top_n = 25L,
                           cost_bps_oneway = COST_BPS, liq_dt = NULL, run_id = "canon_A",
                           strategy_id = "A_canon", diag_dual_basis = TRUE, size_dt = SIZE)
par_ret <- max(abs(arms$A_uncond_top25$pr$ret_net - csA$period_returns$ret_net))
par_t   <- abs(arms$A_uncond_top25$port_t - csA$portfolio_alpha_t_nw_lag3)
cat(sprintf("[S4][PARITY] armA vs canonical_screen_bt: max|dret|=%.3e |dPORT_t|=%.3e n=%d/%d\n",
            par_ret, par_t, arms$A_uncond_top25$n_months, csA$n_months))

## ── EW-유니버스 / cap-tier 진단 (전 arm 병기 의무) ──────────────────────────
univ_pre <- unique(S_all[, .(Date, Ticker)])
diags <- lapply(names(arms), function(nm) {
  cl <- arms[[nm]]
  list(ew  = tryCatch(.canon_diag_ew_universe(univ_pre, R, cl$pr, nm, nm, PPY), error = function(e) list(error = conditionMessage(e))),
       cap = tryCatch(.canon_diag_cap_tier(cl$WR, SIZE, PPY), error = function(e) list(available = FALSE, error = conditionMessage(e)))) })
names(diags) <- names(arms)

## ── 무신호 대조 (롱온리 전 arm 의무) — 홀딩월(t+1) 라벨 + 대조군 beta 검증 ──
sig_dates <- arms$A_uncond_top25$pr$date
hold_ym <- format(as.Date(vapply(sig_dates, function(d)
  as.character(seq(as.Date(format(d, "%Y-%m-01")), by = "month", length.out = 2)[2]), character(1))), "%Y-%m")
ctl <- build_no_signal_control(months = hold_ym, n_stocks = 25L, cap = 1.0, freq = 1L, bps = 15)
bm_v <- arms$A_uncond_top25$pr$benchmark_ret
ctl_beta <- as.numeric(beta_alpha(ctl$ret, bm_v)["beta"])
cat(sprintf("[S4][NOSIG] control beta = %.3f (1 근처여야 함 — 1/20 라벨 정렬 결함 재발 검사)\n", ctl_beta))
ns <- lapply(names(arms), function(nm) {
  g <- no_signal_gate(arms[[nm]]$pr$ret_net, ctl$ret, bm_v)
  list(arm = nm, n = g$n, diff_ann = g$diff_ann, diff_nw_t = g$diff_nw_t, corr = g$corr, verdict = g$verdict) })
names(ns) <- names(arms)

## ── 2급 판정: cell4(=arm A) 대비 β-통제 α 증분 ─────────────────────────────
base_ba <- beta_alpha(arms$A_uncond_top25$pr$ret_net, arms$A_uncond_top25$pr$benchmark_ret)
incr <- lapply(setdiff(names(arms), "A_uncond_top25"), function(nm) {
  m <- merge(arms[[nm]]$pr[, .(date, r = ret_net)],
             arms$A_uncond_top25$pr[, .(date, r0 = ret_net)], by = "date")
  m <- merge(m, bench_dt[, .(date = Date, bm = BM_Ret)], by = "date")
  m[, d := r - r0]
  ba_arm <- beta_alpha(arms[[nm]]$pr$ret_net, arms[[nm]]$pr$benchmark_ret)
  ba_d   <- beta_alpha(m$d, m$bm)
  list(arm = nm,
       arm_beta_alpha_ann = as.numeric(ba_arm["alpha_ann"]), arm_t_alpha = as.numeric(ba_arm["t_alpha"]),
       arm_beta = as.numeric(ba_arm["beta"]),
       increment_alpha_ann = as.numeric(ba_arm["alpha_ann"]) - as.numeric(base_ba["alpha_ann"]),
       paired_diff_mean_ann = 12*mean(m$d), paired_diff_nw_t = nw_t1(m$d),
       paired_diff_beta_alpha_ann = as.numeric(ba_d["alpha_ann"]), paired_diff_t_alpha = as.numeric(ba_d["t_alpha"]),
       n = nrow(m)) })
names(incr) <- setdiff(names(arms), "A_uncond_top25")

## ── 탐색적(비-사전등록): 패자 사이드 롱온리 반전 매수 ───────────────────────
S_lose <- copy(E)[, .(Date, Ticker, score = -score, mkt, tr, vter, adv, Size)]   # 점수 반전 = 패자 상위
expl <- list(
  E_loser_lowturn_top25 = cell_bt(S_lose[vter == 1L], R, bench_dt, 25L, run_id="E", strategy_id="E_loser_lowturn"),
  F_loser_uncond_top25  = cell_bt(S_lose,             R, bench_dt, 25L, run_id="F", strategy_id="F_loser_uncond"),
  G_loser_highturn_top25= cell_bt(S_lose[vter == 3L], R, bench_dt, 25L, run_id="G", strategy_id="G_loser_highturn"))
expl_diag <- lapply(names(expl), function(nm) {
  cl <- expl[[nm]]
  list(ew  = tryCatch(.canon_diag_ew_universe(univ_pre, R, cl$pr, nm, nm, PPY), error=function(e) list(error=conditionMessage(e))),
       cap = tryCatch(.canon_diag_cap_tier(cl$WR, SIZE, PPY), error=function(e) list(available=FALSE))) })
names(expl_diag) <- names(expl)
expl_ns <- lapply(names(expl), function(nm) {
  g <- no_signal_gate(expl[[nm]]$pr$ret_net, ctl$ret, bm_v); list(arm=nm, diff_ann=g$diff_ann, diff_nw_t=g$diff_nw_t, verdict=g$verdict) })
names(expl_ns) <- names(expl)

pack <- function(cl, dg, nm) {
  ba <- beta_alpha(cl$pr$ret_net, cl$pr$benchmark_ret)
  list(id = nm, n_months = cl$n_months, n_names_median = cl$n_names_med, n_names_max = cl$n_names_max,
       port_t_capw = cl$port_t, port_p = cl$port_p, ir = cl$ir, alpha_annualized = cl$alpha_ann,
       net_sr = cl$net_sr, mean_active_net_ann = 12*cl$mean_active_net,
       turnover_annual = cl$turnover_annual, selected_ret_coverage = cl$sel_cov,
       beta_controlled = as.list(ba),
       diag_ew_universe = list(port_t = dg$ew$portfolio_alpha_t_nw_lag3, alpha_ann = dg$ew$alpha_annualized,
                               ir = dg$ew$information_ratio, n_months = dg$ew$n_months),
       diag_cap_tier = if (isTRUE(dg$cap$available))
         list(weight_share_avg = dg$cap$weight_share_avg, contrib_gross_annualized = dg$cap$contrib_gross_annualized)
       else list(available = FALSE)) }

res <- list(
  meta = list(wt_id = "WT-R20260829_003", metric_type = "canonical_screen",
              cost_bps_oneway = COST_BPS, n_months = arms$A_uncond_top25$n_months,
              arm_definitions = list(
                A_uncond_top25 = "무조건부 모멘텀 top-25 (2/20 cell4 대조군 재현)",
                B_lowturn_V1_top25 = "회전율 시장-내 랭킹 저층(V1) 로 정의역 제한 후 모멘텀 top-25 (선별형)",
                B2_lowturn_half_top25 = "회전율 하위 절반 제한 후 top-25",
                C_exclude_V3_top25 = "고회전 V3 배제 후 top-25 (배제형 — 배제 vs 대체 대비가 자동 내장: 두 arm 모두 25종 보유)",
                D_highturn_V3_top25 = "고회전 V3 제한 top-25 (반대 arm — 탐색)")),
  parity = list(max_abs_ret_diff = par_ret, abs_port_t_diff = par_t,
                canon_port_t = csA$portfolio_alpha_t_nw_lag3, engine_port_t = arms$A_uncond_top25$port_t,
                verdict = if (par_ret < 1e-10 && par_t < 1e-8) "PARITY_EXACT" else "PARITY_FAIL"),
  arms = setNames(lapply(names(arms), function(nm) pack(arms[[nm]], diags[[nm]], nm)), names(arms)),
  baseline_2_20_reference = list(
    cell4_beta_alpha_ann_reported = 0.0514, cell4_t_alpha_reported = 1.205, cell4_port_t_reported = 1.294,
    source = "stage_artifacts/WT_R20260829_002/alpha_validation.json",
    reproduced_here = list(alpha_ann = as.numeric(base_ba["alpha_ann"]), t_alpha = as.numeric(base_ba["t_alpha"]),
                           beta = as.numeric(base_ba["beta"]),
                           note = "본 라운드 arm A 는 회전율 결측 종목 배제(월 중앙 343 vs 2/20 343)로 2/20 cell4 와 미세 차이가 있을 수 있다 — 두 값 병기.")),
  increments_vs_armA = incr,
  no_signal_control = list(control_beta = ctl_beta,
                           control_spec = "build_no_signal_control(months=홀딩월 t+1 라벨, n_stocks=25, cap=1.0, freq=1, bps=15)",
                           gates = ns, exploratory_gates = expl_ns),
  exploratory_loser_side = list(
    label = "exploratory_not_preregistered",
    warning = "이 측정은 본 라운드 판정 근거로 승격 금지 — 용도는 강화 4/20 의 사전등록 1급 좌표 생성 하나뿐이다.",
    arms = setNames(lapply(names(expl), function(nm) pack(expl[[nm]], expl_diag[[nm]], nm)), names(expl))))
write_json(res, file.path(OUT, "s4_arms.json"), pretty = TRUE, auto_unbox = TRUE, digits = 8, na = "null")
saveRDS(list(arms = arms, expl = expl, diags = diags, ctl = ctl, S_all = S_all), file.path(OUT, "s4_objects.rds"))

cat("\n===== ARMS (net, cap-w bench) =====\n")
for (nm in names(arms)) { cl <- arms[[nm]]; ba <- beta_alpha(cl$pr$ret_net, cl$pr$benchmark_ret); dg <- diags[[nm]]
  cat(sprintf("%-22s n=%3d nmed=%3.0f | PORT_t=%+7.3f | a=%+6.2f%%/yr t(a)=%+6.3f b=%+5.2f | EWuniv_t=%+7.3f | IR=%+6.3f TO=%.2f | OTHER=%.3f\n",
    nm, cl$n_months, cl$n_names_med, cl$port_t, 100*ba[["alpha_ann"]], ba[["t_alpha"]], ba[["beta"]],
    dg$ew$portfolio_alpha_t_nw_lag3 %or% NA_real_, cl$ir, cl$turnover_annual,
    if (isTRUE(dg$cap$available)) dg$cap$weight_share_avg$OTHER %or% NA_real_ else NA_real_)) }
cat("\n===== INCREMENTS vs arm A =====\n")
for (nm in names(incr)) { x <- incr[[nm]]
  cat(sprintf("%-22s inc(a)=%+6.2f%%p | paired D=%+6.2f%%/yr NW-t=%+6.3f | D b-ctl a=%+6.2f%%/yr t=%+6.3f\n",
    nm, 100*x$increment_alpha_ann, 100*x$paired_diff_mean_ann, x$paired_diff_nw_t,
    100*x$paired_diff_beta_alpha_ann, x$paired_diff_t_alpha)) }
cat("\n===== NO-SIGNAL GATE =====\n")
for (nm in names(ns)) cat(sprintf("%-22s diff=%+6.2f%%/yr t=%+6.3f corr=%.3f -> %s\n",
  nm, 100*ns[[nm]]$diff_ann, ns[[nm]]$diff_nw_t, ns[[nm]]$corr, ns[[nm]]$verdict))
cat("\n===== EXPLORATORY (loser side · not preregistered) =====\n")
for (nm in names(expl)) { cl <- expl[[nm]]; ba <- beta_alpha(cl$pr$ret_net, cl$pr$benchmark_ret); dg <- expl_diag[[nm]]
  cat(sprintf("%-22s n=%3d | PORT_t=%+7.3f | a=%+6.2f%%/yr t(a)=%+6.3f b=%+5.2f | EWuniv_t=%+7.3f | TO=%.2f | nosig %s\n",
    nm, cl$n_months, cl$port_t, 100*ba[["alpha_ann"]], ba[["t_alpha"]], ba[["beta"]],
    dg$ew$portfolio_alpha_t_nw_lag3 %or% NA_real_, cl$turnover_annual, expl_ns[[nm]]$verdict)) }
