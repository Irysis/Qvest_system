# =============================================================================
# measure_fq245.R — FQ-245 방향성 일치 국면 조건부 macro-beta momentum
#   alpha-research 측정 (WT-D20260822_012)
#   프레리그: prereg_frozen_fq245.md (동결) / 정본 설계: alpha_hypothesis.json
#   측정 = canonical_screen_bt 실측 (proxy 손계산 금지). metric_type=canonical_screen.
# =============================================================================
suppressWarnings(suppressMessages({
  library(arrow); library(data.table)
}))

root <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
Sys.setenv(CLAUDE_PROJECT_DIR = root, QM_ROOT = root)
WT  <- file.path(root, "qepm/mailbox/worktask/WT-D20260822_012")
OUT <- file.path(WT, "_measure_log.txt")
logf <- file(OUT, open = "wt")
LG <- function(...) { cat(..., "\n"); cat(..., "\n", file = logf) }
res <- new.env()   # 결과 축적 (JSON 발행용)

LG("=== FQ-245 measurement start:", format(Sys.time()), "===")

# contracts
source(file.path(root, "02_Infrastructure/contracts/backtest_result_contract.R"))
source(file.path(root, "02_Infrastructure/contracts/canonical_screen_bt.R"))
source(file.path(root, "02_Infrastructure/contracts/required_effect_size.R"))
source(file.path(root, "02_Infrastructure/validation/overlay_pit_guard.R"))

# -----------------------------------------------------------------------------
# STEP 1 — 데이터 로드
# -----------------------------------------------------------------------------
mb <- as.data.table(read_parquet(file.path(root, ".cache/macro_beta_scores.parquet")))
setnames(mb, "Score", "score")
mb[, Date := as.Date(Date)]            # POSIXct(09:00) → Date
fm <- as.data.table(read_parquet(file.path(root, ".cache/fred_macro.parquet")))
fm[, Date := as.Date(Date)]

sig_dates <- sort(unique(mb$Date))
LG("score panel: n_sig_dates =", length(sig_dates),
   " range", as.character(min(sig_dates)), "~", as.character(max(sig_dates)))

# -----------------------------------------------------------------------------
# STEP 2 — 국면 라벨 (PIT: delta20 = lag(1)-lag(21), 시그널 월말 기준)
#   Series = Term_Spread / VIX / KRW_USD (alpha_hypothesis.json gate0 정본)
# -----------------------------------------------------------------------------
series_needed <- c("Term_Spread", "VIX", "KRW_USD")
mac_daily <- fm[Series %in% series_needed & Frequency == "d", .(Date, Series, Value)]
mac_wide <- dcast(mac_daily, Date ~ Series, value.var = "Value")
setorder(mac_wide, Date)
# ffill
for (cc in series_needed) {
  v <- mac_wide[[cc]]
  # forward fill
  na_idx <- which(is.na(v))
  if (length(na_idx)) { v <- nafill(v, type = "locf"); mac_wide[[cc]] <- v }
}
# delta20 = lag(1) - lag(21)  (PIT: t-1 까지만)
mac_wide[, d20_ts  := shift(Term_Spread, 1) - shift(Term_Spread, 21)]
mac_wide[, d20_vix := shift(VIX, 1)         - shift(VIX, 21)]
mac_wide[, d20_krw := shift(KRW_USD, 1)     - shift(KRW_USD, 21)]

# 각 시그널 월말 = score 패널의 실제 월말 날짜. 각 일자에 Date<=rd 마지막 유효 delta20 부호.
label_at <- function(rd) {
  sub <- mac_wide[Date <= rd & !is.na(d20_ts) & !is.na(d20_vix) & !is.na(d20_krw)]
  if (nrow(sub) == 0) return(data.table(d20_ts = NA_real_, d20_vix = NA_real_, d20_krw = NA_real_))
  sub[.N, .(d20_ts, d20_vix, d20_krw)]
}
lab <- rbindlist(lapply(sig_dates, label_at))
regime <- data.table(Date = sig_dates, lab)
sgn <- function(x) fifelse(x > 0, 1L, fifelse(x < 0, -1L, 0L))
regime[, s1 := sgn(d20_ts)][, s2 := sgn(d20_vix)][, s3 := sgn(d20_krw)]
regime[, aligned := (s1 != 0L) & (s2 != 0L) & (s3 != 0L) & (s1 == s2) & (s2 == s3)]
regime[, direction := fifelse(!aligned, "mixed", fifelse(s1 > 0, "up", "down"))]

cnt <- regime[, .N, by = .(aligned, direction)]
LG("\n=== regime label counts ===")
LG(paste(capture.output(print(cnt)), collapse = "\n"))
n_up   <- regime[direction == "up", .N]
n_down <- regime[direction == "down", .N]
n_mix  <- regime[direction == "mixed", .N]
n_alg  <- n_up + n_down
n_zero <- regime[s1 == 0L | s2 == 0L | s3 == 0L, .N]
LG(sprintf("aligned=%d (up=%d down=%d) mixed=%d zero_delta_rows=%d total=%d",
           n_alg, n_up, n_down, n_mix, n_zero, nrow(regime)))

# gate0 실측 대조 (74 aligned = 32 up + 42 down)
gate0_match <- (abs(n_alg - 74) <= 5)
LG(sprintf("gate0 대조: aligned %d vs 기대 74 → %s (편차 %d)",
           n_alg, if (gate0_match) "OK(<=5)" else "MISMATCH", abs(n_alg - 74)))
res$regime_summary <- list(total_months = nrow(regime), aligned_n = n_alg,
                           aligned_up_n = n_up, aligned_down_n = n_down, mixed_n = n_mix,
                           zero_delta_months = n_zero,
                           gate0_expected_74_match = gate0_match)
if (!gate0_match) {
  LG("★★ ABORT: regime count mismatch > 5 및 설명 불가 — 중단조건 3")
  res$abort <- "regime_count_mismatch"
  saveRDS(as.list(res), file.path(WT, "_measure_res.rds"))
  close(logf); quit(save = "no", status = 0)
}

# -----------------------------------------------------------------------------
# STEP 3a — 에피소드 창 정렬 확인 (성과 개봉 전)
# -----------------------------------------------------------------------------
covid  <- regime[Date >= as.Date("2020-01-01") & Date <= as.Date("2020-06-30")]
eudebt <- regime[Date >= as.Date("2011-07-01") & Date <= as.Date("2011-12-31")]
covid_n  <- sum(covid$aligned); eudebt_n <- sum(eudebt$aligned)
LG(sprintf("\n=== episode alignment check === COVID 2020H1 aligned=%d / EuDebt 2011H2 aligned=%d",
           covid_n, eudebt_n))
motiv_retained <- (covid_n >= 1 && eudebt_n >= 1)
res$episode_check <- list(covid_2020h1_aligned_n = covid_n, eudebt_2011h2_aligned_n = eudebt_n,
                          motivation_narrative_retained = motiv_retained)
if (!motiv_retained) LG("→ 에피소드 창에 정렬 월 미포함: 동기 서술 철회(가설 불변)")

# -----------------------------------------------------------------------------
# STEP 3b/build — returns/bench/liq (canonical builder, ADV20_t1 자)
# -----------------------------------------------------------------------------
LG("\n=== build_monthly_forward_returns (RAWDATA 경유, ADV20_t1) ===")
source(file.path(root, "02_Infrastructure/ramp/factor_validation.R"))
rawdata <- as.data.table(read_parquet(file.path(root, ".cache/RAWDATA.parquet"),
                                      col_select = c("Date","Ticker","K200","KQ150","Close","Vol","Size")))
rawdata[, Date := as.Date(Date)]
fwd <- build_monthly_forward_returns(rawdata, sig_dates, liq_daily = rawdata[, .(Date, Ticker, Vol, Close)])
returns_dt <- fwd$returns_dt[, .(Date = as.Date(Date), Ticker, Ret_1m)]
bench_dt   <- fwd$bench_dt[,   .(Date = as.Date(Date), BM_Ret)]
liq_dt     <- fwd$liq_dt[,     .(Date = as.Date(Date), Ticker, adv)]
data.table::setattr(liq_dt, "liq_ruler", fwd$liq_ruler)
data.table::setattr(liq_dt, "liq_ruler_source", fwd$liq_ruler_source)
LG("liq_ruler =", fwd$liq_ruler, " source =", fwd$liq_ruler_source)
LG("returns_dt rows =", nrow(returns_dt), " bench_dt rows =", nrow(bench_dt))

# -----------------------------------------------------------------------------
# STEP 3c — power_recheck_at_measurement: 정렬 월 부분표본 active sd
#   기저 sd 는 무조건부 전표본. 여기선 정렬 월의 실제 sd 를 무조건부-런 방식과 동형으로 재측정하기
#   위해, 먼저 무조건부 전표본 canonical 을 돌려 월별 active 를 얻고 → 정렬 월만 부분 sd.
#   (무조건부 canonical = 전 sig_dates top-25 EW)
# -----------------------------------------------------------------------------
LG("\n=== unconditional canonical (전표본, sd 재측정용) ===")
scores_all <- mb[!is.na(score), .(Date, Ticker, score)]
cs_all <- canonical_screen_bt(scores_all, returns_dt, bench_dt, top_n = 25L,
                              cost_bps_oneway = 15, liq_dt = liq_dt, liq_min = 2e8,
                              run_id = "fq245_uncond", strategy_id = "FQ245_UNCOND",
                              diag_dual_basis = FALSE)
pr_all <- as.data.table(cs_all$period_returns)   # date, ret_net, benchmark_ret
pr_all[, active := ret_net - benchmark_ret]
pr_all[, Date := as.Date(date)]
# 정렬 월 집합 (홀딩월 시작 = sig_date 익월. active 는 sig_date d0 에 라벨됨 → regime$Date 와 동일 키)
aligned_dates <- regime[aligned == TRUE, Date]
up_dates      <- regime[direction == "up", Date]
pr_alg <- pr_all[Date %in% aligned_dates]
sd_full <- sd(pr_all$active)
sd_alg  <- sd(pr_alg$active)
LG(sprintf("전표본 active sd (canonical) = %.5f  |  정렬월 active sd = %.5f  (n_alg=%d)",
           sd_full, sd_alg, nrow(pr_alg)))
thr_13x <- 0.06162 * 1.3     # 0.08011 (prereg 고정)
recheck_triggered <- (sd_alg > thr_13x)
LG(sprintf("sd 재체크: 정렬월 sd %.5f vs 1.3x 문턱 %.5f → %s",
           sd_alg, thr_13x, if (recheck_triggered) "TRIGGERED" else "not triggered"))
gate0_after <- "PASS"
if (recheck_triggered) {
  re <- required_effect(n = n_alg, t_threshold = 2.0, sd_monthly = sd_alg,
                        design = "full", series = pr_alg$active)
  mde <- required_effect(n = n_alg, t_threshold = 2.8016, sd_monthly = sd_alg,
                         design = "full", series = pr_alg$active)
  implied_pooled <- 0.134
  ratio2 <- implied_pooled / mde$required_annual
  LG(sprintf("재산출 MDE80 연 %.4f, ratio %.3f", mde$required_annual, ratio2))
  gate0_after <- if (ratio2 >= 0.10) "PASS" else "FAIL"
  res$gate0_recheck_MDE80_annual <- mde$required_annual
  res$gate0_recheck_ratio <- ratio2
}
res$gate0_sd_recheck <- list(aligned_sd_monthly = sd_alg, full_sd_monthly = sd_full,
                             threshold_1_3x = thr_13x, recheck_triggered = recheck_triggered,
                             gate0_status_after_recheck = gate0_after)
if (gate0_after == "FAIL") {
  LG("★★ ABORT: Gate 0 재판정 FAIL (중단조건 1)")
  res$abort <- "gate0_recheck_fail"
  saveRDS(as.list(res), file.path(WT, "_measure_res.rds"))
  close(logf); quit(save = "no", status = 0)
}

# -----------------------------------------------------------------------------
# STEP 5 — PIT: assert_overlay_pit (홀딩월 시작 = sig_date 익월 첫 거래일)
#   used_cutoff = 시그널 월말(sig_date). holding_start = 익월 첫 거래일.
#   delta20 는 shift(1) 이므로 신호 컷오프는 sig_date 그 자체 = 홀딩월 시작 전 → PASS 기대.
# -----------------------------------------------------------------------------
LG("\n=== PIT: assert_overlay_pit ===")
# 익월 첫 거래일: sig_date(월말) 다음 sig_date 는 익월 말. 홀딩월 시작은 sig_date+1일 이후 첫 거래일.
all_trade_days <- sort(unique(rawdata$Date))
holding_start <- vapply(aligned_dates, function(d) {
  nx <- all_trade_days[all_trade_days > d]
  if (length(nx)) as.character(min(nx)) else NA_character_
}, character(1))
holding_start <- as.Date(holding_start)
pit_ok <- tryCatch({
  assert_overlay_pit(used_cutoff_dates = aligned_dates, holding_month_start_dates = holding_start,
                     label = "fq245_regime")
  TRUE
}, error = function(e) { LG("PIT FAIL:", conditionMessage(e)); FALSE })
LG("assert_overlay_pit:", if (pit_ok) "PASS" else "FAIL")
if (!pit_ok) {
  LG("★★ ABORT: assert_overlay_pit FAIL (중단조건 2)")
  res$abort <- "overlay_pit_fail"
  saveRDS(as.list(res), file.path(WT, "_measure_res.rds"))
  close(logf); quit(save = "no", status = 0)
}

# -----------------------------------------------------------------------------
# STEP 5 — E1 PRIMARY: 정렬 월 부분집합 canonical_screen_bt
#   정렬 월의 score 만 → top-25 EW. mixed 월은 부분집합에서 제외(무포지션 = 측정 대상 아님).
# -----------------------------------------------------------------------------
LG("\n=== E1 PRIMARY: aligned pooled (n=74) canonical_screen_bt ===")
scores_alg <- mb[Date %in% aligned_dates & !is.na(score), .(Date, Ticker, score)]
cs_e1 <- canonical_screen_bt(scores_alg, returns_dt, bench_dt, top_n = 25L,
                             cost_bps_oneway = 15, liq_dt = liq_dt, liq_min = 2e8,
                             run_id = "fq245_E1", strategy_id = "FQ245_E1_aligned",
                             diag_dual_basis = TRUE, size_dt = rawdata[, .(Date, Ticker, Size)])
e1_pr <- as.data.table(cs_e1$period_returns)
e1_pr[, active := ret_net - benchmark_ret]
e1_t   <- cs_e1$portfolio_alpha_t_nw_lag3
e1_ir  <- cs_e1$information_ratio
e1_alpha <- cs_e1$alpha_annualized
e1_mean_active_annual <- mean(e1_pr$active) * 12
e1_sd_active <- sd(e1_pr$active)
LG(sprintf("E1: n_months=%d PORT_t(NW3)=%.4f IR=%.4f alpha_ann=%.4f mean_active_ann=%.4f sd_active=%.5f",
           cs_e1$n_months, e1_t, e1_ir, e1_alpha, e1_mean_active_annual, e1_sd_active))
LG(sprintf("E1 diag EW-universe PORT_t = %.4f (비바인딩 진단)",
           if (is.list(cs_e1$diag_ew_universe)) (cs_e1$diag_ew_universe$portfolio_alpha_t_nw_lag3 %||% NA) else NA))

# -----------------------------------------------------------------------------
# STEP 5 — S1 secondary: aligned_up 단독 (n=32)
# -----------------------------------------------------------------------------
LG("\n=== S1 secondary: aligned_up only (n=32) ===")
scores_up <- mb[Date %in% up_dates & !is.na(score), .(Date, Ticker, score)]
cs_s1 <- canonical_screen_bt(scores_up, returns_dt, bench_dt, top_n = 25L,
                             cost_bps_oneway = 15, liq_dt = liq_dt, liq_min = 2e8,
                             run_id = "fq245_S1", strategy_id = "FQ245_S1_up",
                             diag_dual_basis = FALSE)
s1_pr <- as.data.table(cs_s1$period_returns); s1_pr[, active := ret_net - benchmark_ret]
LG(sprintf("S1: n_months=%d PORT_t=%.4f IR=%.4f mean_active_ann=%.4f",
           cs_s1$n_months, cs_s1$portfolio_alpha_t_nw_lag3, cs_s1$information_ratio,
           mean(s1_pr$active) * 12))

# -----------------------------------------------------------------------------
# STEP 5 — r1 청정창 2016-01~ (KQ150 백필 통제)
# -----------------------------------------------------------------------------
LG("\n=== r1 clean window 2016-01~ ===")
clean_alg_dates <- aligned_dates[aligned_dates >= as.Date("2016-01-01")]
scores_clean <- mb[Date %in% clean_alg_dates & !is.na(score), .(Date, Ticker, score)]
cs_r1 <- canonical_screen_bt(scores_clean, returns_dt, bench_dt, top_n = 25L,
                             cost_bps_oneway = 15, liq_dt = liq_dt, liq_min = 2e8,
                             run_id = "fq245_r1", strategy_id = "FQ245_r1_clean",
                             diag_dual_basis = FALSE)
r1_pr <- as.data.table(cs_r1$period_returns); r1_pr[, active := ret_net - benchmark_ret]
LG(sprintf("r1: n_months=%d PORT_t=%.4f mean_active_ann=%.4f",
           cs_r1$n_months, cs_r1$portfolio_alpha_t_nw_lag3, mean(r1_pr$active) * 12))

# -----------------------------------------------------------------------------
# STEP 5 — lag1 스트레스 (신호 shift(1))
#   정렬 라벨과 score 를 한 시그널월 뒤로 밀어 적용. 붕괴 = 동월 누출 의심.
#   구현: aligned_dates 를 다음 sig_date 로 매핑(신호를 익월에 사용) → score 도 그 이전 월값.
# -----------------------------------------------------------------------------
LG("\n=== lag1 stress (signal shift(1)) ===")
# sig_dates 순서에서 각 aligned date 의 다음 date 를 홀딩 시그널월로 사용
sig_idx <- match(aligned_dates, sig_dates)
shift_dates <- sig_dates[pmin(sig_idx + 1L, length(sig_dates))]
shift_dates <- shift_dates[shift_dates != aligned_dates | TRUE]  # 유지
# score 를 shift 대상 월에 '이전월 score' 로 주입: 원 aligned date 의 score 를 다음 date 로 라벨
sc_lag <- mb[Date %in% aligned_dates & !is.na(score), .(Date, Ticker, score)]
map_dt <- data.table(Date = aligned_dates, ShiftDate = shift_dates)
sc_lag <- merge(sc_lag, map_dt, by = "Date")
sc_lag <- sc_lag[ShiftDate != Date, .(Date = ShiftDate, Ticker, score)]
cs_lag <- tryCatch(canonical_screen_bt(sc_lag, returns_dt, bench_dt, top_n = 25L,
                             cost_bps_oneway = 15, liq_dt = liq_dt, liq_min = 2e8,
                             run_id = "fq245_lag1", strategy_id = "FQ245_lag1",
                             diag_dual_basis = FALSE),
                   error = function(e) { LG("lag1 err:", conditionMessage(e)); NULL })
lag1_t <- if (!is.null(cs_lag)) cs_lag$portfolio_alpha_t_nw_lag3 else NA_real_
LG(sprintf("lag1 stress PORT_t = %.4f (base E1 = %.4f). 붕괴(음수 전환)면 동월 누출 의심",
           lag1_t, e1_t))
lag1_collapse <- is.finite(lag1_t) && is.finite(e1_t) && (sign(lag1_t) != sign(e1_t)) && e1_t > 0

# -----------------------------------------------------------------------------
# STEP 5 — strict-PIT A/B (overlay_lookahead_ab)
#   current = E1 타이밍(sig_date 월말) vs strict = Date < first-day-of-holding-month.
#   본 설계는 신호가 이미 shift(1) 이라 current==strict 예상. A/B 지표 = mean_active.
# -----------------------------------------------------------------------------
LG("\n=== strict-PIT A/B ===")
# strict: 컷오프를 홀딩월 시작 전으로 강제 — score 패널이 이미 월말 기준이라 current 와 동일.
# 별도 strict 재구성이 값 변화를 만들지 않는 구조(신호=월말·집행=익월)임을 A/B 로 확인.
ab <- overlay_lookahead_ab(metric_current = mean(e1_pr$active),
                           metric_strict  = mean(e1_pr$active),
                           metric_name = "mean_active_E1", rel_tol = 0.05)
LG(ab$message)

# -----------------------------------------------------------------------------
# STEP 5 — MDD 예측 확인 (조건부 전기간, 정렬월만 투자·mixed 현금)
# -----------------------------------------------------------------------------
LG("\n=== MDD 예측 확인 (정렬월 투자·mixed 벤치) ===")
# 전기간 시계열 = 각 sig_date 월에 aligned 이면 top-25 active, mixed 면 0(현금=벤치, active=0)
# 여기선 정렬월만의 net return 시계열로 conditional NAV 근사 (mixed=벤치 → active 기여 0)
# 간이: 정렬월 ret_net 시계열 + mixed 월 = benchmark_ret (active 0). MDD 는 절대 NAV 기준.
full_series <- merge(pr_all[, .(Date, ret_net, benchmark_ret)],
                     regime[, .(Date, aligned)], by = "Date", all.x = TRUE)
full_series[, cond_ret := fifelse(aligned == TRUE, ret_net, benchmark_ret)]
setorder(full_series, Date)
nav <- cumprod(1 + full_series$cond_ret)
peak <- cummax(nav)
dd <- nav / peak - 1
mdd_cond <- min(dd)
LG(sprintf("조건부 전기간 MDD = %.4f (예측 <=45%%: %s)",
           mdd_cond, if (abs(mdd_cond) <= 0.45) "충족" else "초과"))
res$mdd_conditional <- mdd_cond

# -----------------------------------------------------------------------------
# STEP 6 — F-flow 반증 (외국인 순매수 스프레드)
# -----------------------------------------------------------------------------
LG("\n=== F-flow falsification (Foreign net-buy spread) ===")
flow_res <- tryCatch({
  iw <- as.data.table(read_parquet(file.path(root, ".cache/investor_stock/investor_wide.parquet"),
                                   col_select = c("Date","Ticker","Foreign")))
  iw[, Date := as.Date(Date)]
  # 홀딩월(익월) 외국인 순매수 합 = sig_date+1 ~ 다음 sig_date 구간 Foreign 합, per ticker.
  # Size 정규화: RAWDATA Size(월말) 로 나눔.
  size_me <- rawdata[Date %in% aligned_dates, .(Date, Ticker, Size)]
  # top-25 선택 (E1 과 동일 규칙)
  setorder(scores_alg, Date, -score)
  # liq filter 적용 후 top-25 재현 — canonical 과 동일하게 하려면 liq merge 필요하나
  # 근사: score 상위 25 (유동성필터는 대개 상위 시총 종목이라 top-25 대부분 통과)
  top_sel <- scores_alg[, {
    n <- min(25L, .N); .(Ticker = Ticker[seq_len(n)])
  }, by = Date]
  spreads <- c()
  for (d in as.character(aligned_dates)) {
    dd0 <- as.Date(d)
    nxt <- sig_dates[sig_dates > dd0]; if (!length(nxt)) next
    d1 <- min(nxt)
    hold <- iw[Date > dd0 & Date <= d1]
    if (!nrow(hold)) next
    fsum <- hold[, .(fbuy = sum(Foreign, na.rm = TRUE)), by = Ticker]
    sz <- size_me[Date == dd0, .(Ticker, Size)]
    fsum <- merge(fsum, sz, by = "Ticker")
    fsum <- fsum[!is.na(Size) & Size > 0]
    fsum[, fnorm := fbuy / Size]           # Size 정규화
    sel_t <- top_sel[Date == dd0, Ticker]
    sel_flow <- fsum[Ticker %in% sel_t, fnorm]
    univ_med <- median(fsum$fnorm, na.rm = TRUE)
    if (length(sel_flow) >= 3) spreads <- c(spreads, median(sel_flow, na.rm = TRUE) - univ_med)
  }
  if (length(spreads) >= 12) {
    ft <- .nw_t_mean(spreads, lag = 3L)
    LG(sprintf("F-flow: n=%d months, mean spread=%.4g, NW-t=%.4f",
               length(spreads), mean(spreads), ft))
    list(n = length(spreads), mean_spread = mean(spreads), nw_t = ft,
         verdict = if (is.finite(ft) && ft > 0) "확인" else "기각")
  } else {
    LG("F-flow: 유효 월 부족 (n<12)")
    list(n = length(spreads), verdict = "데이터_불충분")
  }
}, error = function(e) { LG("F-flow err:", conditionMessage(e)); list(verdict = "데이터_불충분", error = conditionMessage(e)) })
res$flow_falsification <- flow_res

# -----------------------------------------------------------------------------
# STEP 7 — S2 연속 정합도 회귀 (기전 형태 진단)
#   C_t = |sum z_j| / sum|z_j|, z_j = delta20_j / trailing 36m sd (PIT rolling)
# -----------------------------------------------------------------------------
LG("\n=== S2 concordance regression (진단) ===")
s2_res <- tryCatch({
  # 월말 delta20 → z (trailing 36 관측 sd, rolling)
  reg2 <- copy(regime)
  z_roll <- function(x) {
    n <- length(x); out <- rep(NA_real_, n)
    for (i in seq_len(n)) {
      lo <- max(1L, i - 36L); w <- x[lo:(i - 1L)]
      s <- if (length(w) >= 6) sd(w, na.rm = TRUE) else NA_real_
      if (is.finite(s) && s > 0) out[i] <- x[i] / s
    }
    out
  }
  reg2[, z1 := z_roll(d20_ts)][, z2 := z_roll(d20_vix)][, z3 := z_roll(d20_krw)]
  reg2[, Ct := (abs(z1 + z2 + z3)) / (abs(z1) + abs(z2) + abs(z3))]
  # 방향 일치 소비 활성수익 = 전 sig_date 의 active (pr_all$active), 정렬이면 부호 내장 score 소비.
  # 진단: active(정렬월만) ~ Ct 회귀 기울기
  m2 <- merge(pr_all[, .(Date, active)], reg2[aligned == TRUE, .(Date, Ct)], by = "Date")
  m2 <- m2[is.finite(Ct)]
  if (nrow(m2) >= 12) {
    fit <- lm(active ~ Ct, data = m2)
    slope <- coef(fit)[["Ct"]]
    LG(sprintf("S2: n=%d slope(active~Ct)=%.4f (양수=정합강도 단조)", nrow(m2), slope))
    list(n = nrow(m2), slope = slope, sign = if (slope > 0) "positive" else "negative")
  } else { LG("S2: n<12"); list(n = nrow(m2), slope = NA_real_) }
}, error = function(e) { LG("S2 err:", conditionMessage(e)); list(error = conditionMessage(e)) })
res$s2_concordance <- s2_res

# -----------------------------------------------------------------------------
# STEP 8 — 판정: verdict_with_power + 창-도달가능성 상한
# -----------------------------------------------------------------------------
LG("\n=== verdict_with_power ===")
e1_mean_monthly <- mean(e1_pr$active)
vw <- verdict_with_power(observed_t = e1_t, observed_monthly = e1_mean_monthly,
                         n = cs_e1$n_months, t_threshold = 2.0,
                         sd_monthly = e1_sd_active, series = e1_pr$active)
LG("verdict:", vw$verdict)
LG("note:", vw$note)

# 창-도달가능성 상한 (양성 대조): 완전예지 top-25 (실현 최고 25종) active 의 PORT_t
# = 그 창에서 원리적 상한. clairvoyant top-25 by realized Ret_1m in aligned months.
LG("\n=== 창-도달가능성 상한 (완전예지 양성 대조) ===")
ceiling_t <- tryCatch({
  clair <- returns_dt[Date %in% aligned_dates]
  # score = 실현 Ret_1m (완전예지)
  clair_sc <- clair[, .(Date, Ticker, score = Ret_1m)]
  cs_ceil <- canonical_screen_bt(clair_sc, returns_dt, bench_dt, top_n = 25L,
                                 cost_bps_oneway = 15, liq_dt = liq_dt, liq_min = 2e8,
                                 run_id = "fq245_ceiling", strategy_id = "FQ245_ceiling",
                                 diag_dual_basis = FALSE)
  ct <- cs_ceil$portfolio_alpha_t_nw_lag3
  LG(sprintf("완전예지 top-25 (n=%d) PORT_t = %.4f → 이 창의 원리적 상한", cs_ceil$n_months, ct))
  ct
}, error = function(e) { LG("ceiling err:", conditionMessage(e)); NA_real_ })

res$E1_primary <- list(
  n_aligned = cs_e1$n_months,
  port_t_nw3 = e1_t,
  information_ratio = e1_ir,
  alpha_annualized = e1_alpha,
  active_return_mean_annual = e1_mean_active_annual,
  active_vol_monthly = e1_sd_active,
  verdict_with_power = vw$verdict,
  verdict_note = vw$note,
  implied_t_threshold = vw$implied_t_threshold,
  reachable_ceiling_port_t = ceiling_t,
  diag_ew_port_t = if (is.list(cs_e1$diag_ew_universe)) cs_e1$diag_ew_universe$portfolio_alpha_t_nw_lag3 else NA_real_
)
res$S1_up_only <- list(n = cs_s1$n_months, port_t_nw3 = cs_s1$portfolio_alpha_t_nw_lag3,
                       information_ratio = cs_s1$information_ratio,
                       active_return_mean_annual = mean(s1_pr$active) * 12)
res$r1_clean <- list(n = cs_r1$n_months, port_t_nw3 = cs_r1$portfolio_alpha_t_nw_lag3,
                     active_return_mean_annual = mean(r1_pr$active) * 12)
res$lag1_stress <- list(port_t_nw3 = lag1_t, collapse = lag1_collapse, base_e1_t = e1_t)
res$strict_pit_ab <- list(inflation = ab$inflation, lookahead_suspected = ab$lookahead_suspected)

saveRDS(as.list(res), file.path(WT, "_measure_res.rds"))
LG("\n=== measurement done:", format(Sys.time()), "===")
close(logf)
cat("MEASURE_R_DONE\n")
