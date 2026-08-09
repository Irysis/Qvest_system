## factor_validation.R — RAMP Gate 4 (3차): 순수팩터 후보 실측 검증 + 승인
## 룰 §4 (alpha-research). 각 순수팩터(neutralized_z)를 canonical_screen_bt()로 → top-N EW long-only net 15bps.
## 산출: rank_ic_ir_oos, net_quintile_spread_oos, cost_drag, DSR (metric_type=backtested via canonical_screen).
## approve_factors() = config gate4_pure_factor.approve_rule 충족분만 status=approved + lineage.
##
## ★실측-only: 모든 성능수치 canonical_screen_bt 경유. prod/cumprod 자체합성 금지.

suppressMessages({ library(data.table) })
source("02_Infrastructure/ramp/ramp_io.R")
# contract 함수(build_benchmark_compare)를 먼저 명시 source — canonical_screen_bt가
# sys.frame 상대경로로 자동 source 하나 간접 source 시 해석 실패 → 명시 보장.
if (!exists("build_benchmark_compare")) source("02_Infrastructure/contracts/backtest_result_contract.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")

#==============================================================================
# 1. 월별 forward 1M 수익 + 벤치마크 (rawdata에서 PIT-aligned 구성)
#    sig_date(t)의 신호 → t→t+1M 실현수익. 자체합성 아님: 일별 Ret을 월구간 단순누적은
#    피하고, '월말 종가 대비 다음 월말 종가' 변화율(실현 forward return)을 직접 산출.
#==============================================================================
#==============================================================================
# [FQ-181 2026-08-09] 유동성 자(ruler) 이원화 수리
#
# 결함(확정): 구판은 주석에 "20d ADV at t-1" 이라 써 놓고 `adv = Vol0 * Close0`
#   (= 월말 **당일 1일치** 거래대금)를 계산했다. 헌법 정의(CLAUDE.md Production
#   Constraints · .claude/rules/pit.md C10)는 **20일 평균 거래대금 >= 2e8**이다.
#   두 자의 상관 0.929 · 판정 불일치 2.61% · 실선별 top-25 중 3.04%가 20일-자 미달.
#   → 자는 헌법이 이미 정의했으므로 선택 문제가 아니다. 구현을 헌법에 맞춘다.
#
# ★규약 (자 라벨 의무 — 두 자 병존 기간):
#   이 함수의 `liq_dt` 를 소비하는 모든 산출물은 반환값 `liq_ruler`(= liq_dt 의
#   attr "liq_ruler")를 **그대로 기록**해야 한다. 자 라벨 없는 유동성 수치를
#   서로 비교하거나 인용하지 말 것 — 교정 전후 산출물은 서로 다른 자로 잰 값이다.
#
# ★입력 형태가 자를 결정한다 (2026-08-09 census 실측):
#   호출부 149건 중 103건(69%)이 rawdata 를 **월말 거래일만으로 slim** 해서 넘긴다
#   (`rawdata[Date %in% .me]` — asof_close 전체스캔 회피 목적). 월말 행만 있는
#   패널에서는 20일 평균을 **원리적으로 계산할 수 없다**(일간 관측이 입력에 없다).
#   그런 입력에 `frollmean(.,20)` 을 걸면 20 *개월* 평균이 나온다 — 조용히 틀린 값.
#   ⇒ 함수가 입력 관측단위를 **실측**해서 분기하고, 계산 불가일 때는 라벨로 자백한다.
#   ⇒ NA 로 비우지 않는다: canonical_screen_bt 는 `is.na(adv) | adv >= liq_min` 이라
#     NA 가 **통과**한다(= 제약 완화 방향). 결손을 정상값으로 내려앉히지 않는다.
#==============================================================================

#' 20일 평균 거래대금(t-1 기준) — 일간 패널에서만 계산 가능
#'
#' 창 = 신호일 **직전 거래일까지의 20 거래일** (당일 미포함, C10 t-1 PIT).
#' 워밍업(종목의 첫 20 거래일)은 NA 로 비우지 않고 **가용 일수만큼의 확장평균**으로
#' 채운다 — NA 는 하류에서 필터를 통과해버리므로(위 규약) 결손을 완화로 바꾸지 않는다.
#' i >= 20 구간에서는 adaptive 창 폭이 20 으로 고정되어 표준 frollmean(.,20) 과 동일하다.
#' @param daily data.table(Date, Ticker, Vol, Close) 일간 패널
#' @param at_dates 값을 뽑을 날짜(월말 거래일). NULL 이면 전 구간 반환.
#' @return data.table(Date, Ticker, adv)
build_adv20_t1 <- function(daily, at_dates = NULL) {
  stopifnot(all(c("Date", "Ticker", "Vol", "Close") %in% names(daily)))
  DV <- data.table::as.data.table(daily)[, .(Ticker, Date = as.Date(Date), dval = Vol * Close)]
  data.table::setorder(DV, Ticker, Date)
  # adaptive: 창 폭 = min(누적 관측수, 20). 그 다음 shift(1) 로 당일을 창에서 제외한다.
  DV[, adv := data.table::shift(
        data.table::frollmean(dval, n = pmin(seq_len(.N), 20L),
                              adaptive = TRUE, na.rm = TRUE), 1L), by = Ticker]
  res <- if (is.null(at_dates)) DV[, .(Date, Ticker, adv)]
         else DV[Date %in% as.Date(at_dates), .(Date, Ticker, adv)]
  res[]
}

#' @return list(returns_dt(Date=sig월말, Ticker, Ret_1m=forward), bench_dt(Date, BM_Ret),
#'              liq_dt(Date, Ticker, adv), ret_firewall_dropped, liq_ruler)
build_monthly_forward_returns <- function(rawdata, sig_dates) {
  # 각 종목 월말 종가 → 다음 월말 종가 forward return
  sig_dates <- sort(as.Date(sig_dates))
  out <- list(); bench <- list(); liq <- list()
  n_ret_firewall <- 0L   # [R44] monthly Ret_1m sanity 격리 카운트
  # 월말 거래일 매핑
  asof_close <- function(d) {
    sub <- rawdata[Date <= d]
    if (nrow(sub) == 0) return(NULL)
    md <- max(sub$Date)
    rawdata[Date == md]
  }

  # ── [FQ-181] 입력 관측단위 실측 → 유동성 자 결정 ───────────────────────────
  #   판정 지표: 캘린더월당 고유 거래일 수의 중앙값. 일간 패널 ~21, 월말-slim = 1.
  .udates <- sort(unique(as.Date(rawdata$Date)))
  .dpm_med <- if (length(.udates)) {
    stats::median(as.integer(table(format(.udates, "%Y-%m"))))
  } else 0
  .has_px <- all(c("Vol", "Close") %in% names(rawdata))
  .daily_ok <- (.dpm_med >= 15) && .has_px
  adv_tbl <- NULL
  if (.daily_ok) {
    liq_ruler <- "adv20_t1"          # 헌법 정의 — 20일 평균 거래대금, 당일 미포함
    .md <- unique(vapply(sig_dates, function(d) {
      v <- .udates[.udates <= d]
      if (length(v)) as.character(max(v)) else NA_character_
    }, character(1)))
    .md <- as.Date(.md[!is.na(.md)])
    adv_tbl <- build_adv20_t1(rawdata[Date <= max(sig_dates), .(Date, Ticker, Vol, Close)],
                              at_dates = .md)
    data.table::setkeyv(adv_tbl, c("Date", "Ticker"))
  } else {
    liq_ruler <- "adv1_sameday_DEGRADED"   # 20일 자 계산 불가 — 구판과 동일한 1일치
    cat(sprintf(paste0(
      "[build_monthly_forward_returns] ★유동성 자 저하(FQ-181): 입력 패널의 캘린더월당 ",
      "거래일 중앙값 = %.0f (일간 아님%s).\n",
      "  20일 평균 거래대금을 입력에서 계산할 수 없어 **월말 1일치 Vol*Close** 로 대체합니다.\n",
      "  → liq_ruler='adv1_sameday_DEGRADED'. 헌법 자(20일 평균)로 재려면 slim 하지 말고 ",
      "일간 rawdata 를 넘기십시오.\n"),
      .dpm_med, if (!.has_px) ", Vol/Close 결측" else ""))
    warning("build_monthly_forward_returns: liq_ruler='adv1_sameday_DEGRADED' ",
            "— 월말-slim 입력이라 20일 평균 거래대금 계산 불가 (FQ-181)", call. = FALSE)
  }
  for (i in seq_len(length(sig_dates) - 1L)) {
    d0 <- sig_dates[i]; d1 <- sig_dates[i + 1L]
    c0 <- asof_close(d0); c1 <- asof_close(d1)
    if (is.null(c0) || is.null(c1)) next
    m <- merge(c0[, .(Ticker, Close0 = Close, K200, KQ150, Vol0 = Vol, Size0 = Size)],
               c1[, .(Ticker, Close1 = Close)], by = "Ticker")
    m <- m[(K200 == TRUE | KQ150 == TRUE) & !is.na(Close0) & Close0 > 0 & !is.na(Close1)]
    m[, Ret_1m := Close1 / Close0 - 1]
    # [R44 2026-07-15, WT-D20260715_013] monthly Ret_1m sanity — 물리불가 격리(월 >+500% /
    #   <-100%). clean 유니버스 월 |fwd| 최대 ~2.47(R43 census) ≪ 5.0 → 미발화·parity 보장.
    .bad <- is.finite(m$Ret_1m) & (m$Ret_1m > 5.0 | m$Ret_1m < -1.0)
    if (any(.bad)) { n_ret_firewall <- n_ret_firewall + sum(.bad); m <- m[!.bad] }
    out[[length(out) + 1L]] <- m[, .(Date = d0, Ticker, Ret_1m)]
    # [FQ-181] liquidity = 20일 평균 거래대금(t-1). 계산 불가 입력이면 1일치로 저하 + 라벨.
    if (!is.null(adv_tbl)) {
      md0 <- c0$Date[1L]
      .a <- adv_tbl[.(md0, m$Ticker), .(adv), on = c("Date", "Ticker")]$adv
      liq[[length(liq) + 1L]] <- data.table(Date = d0, Ticker = m$Ticker, adv = .a)
    } else {
      liq[[length(liq) + 1L]] <- m[, .(Date = d0, Ticker, adv = Vol0 * Close0)]
    }
    # benchmark forward return = 유니버스 시총(Size)가중 forward return (실측 cross-section,
    #   compounding 없는 단일구간 가중평균 — KOSPI200∪KQ150 cap-weighted market proxy).
    bm_w <- if (sum(!is.na(m$Size0) & m$Size0 > 0) > 0)
      stats::weighted.mean(m$Ret_1m, w = ifelse(is.na(m$Size0), 0, m$Size0), na.rm = TRUE)
    else mean(m$Ret_1m, na.rm = TRUE)
    bench[[length(bench) + 1L]] <- data.table(Date = d0, BM_Ret = bm_w)
  }
  if (n_ret_firewall > 0)
    cat(sprintf("[build_monthly_forward_returns] Ret_1m sanity 방화벽: %d 물리불가 월수익 격리(>+500%%/<-100%%).\n", n_ret_firewall))
  liq_out <- if (length(liq)) rbindlist(liq) else data.table()
  # [FQ-181] 자 라벨을 데이터에 붙여 보낸다 — 소비자가 list 를 풀어 liq_dt 만 넘겨도
  #   라벨이 따라가도록. (반환 list 의 liq_ruler 와 동일 값, 이중 경로)
  data.table::setattr(liq_out, "liq_ruler", liq_ruler)
  list(
    returns_dt = if (length(out)) rbindlist(out) else data.table(),
    bench_dt = if (length(bench)) rbindlist(bench) else data.table(),
    liq_dt = liq_out,
    ret_firewall_dropped = n_ret_firewall,  # [R44] 격리 카운트(진단)
    liq_ruler = liq_ruler                   # [FQ-181] 자 라벨(기록 의무 — 상단 규약)
  )
}

#==============================================================================
# 2. 단일 순수팩터 검증 (canonical_screen_bt 경유)
#==============================================================================
#' @param scores_dt data.table(signal_date, security_id, factor_id, neutralized_z) for ONE factor
#' @param fwd list from build_monthly_forward_returns
#' @return list(factor_id, n_months, rank_ic_mean, rank_ic_ir, net_quintile_spread, cost_drag,
#'              net_sr, portfolio_alpha_t, dsr, metric_type)
validate_factor <- function(scores_dt, fwd, top_n = 20L, cost_bps = 15) {
  fid <- scores_dt$factor_id[1]
  # canonical_screen 입력: Date, Ticker, score (= neutralized_z, higher=better)
  sc <- scores_dt[, .(Date = as.Date(signal_date), Ticker = security_id, score = neutralized_z)]
  sc <- sc[!is.na(score)]
  ret <- fwd$returns_dt[, .(Date = as.Date(Date), Ticker, Ret_1m)]
  bench <- fwd$bench_dt[, .(Date = as.Date(Date), BM_Ret)]
  liq <- fwd$liq_dt[, .(Date = as.Date(Date), Ticker, adv)]

  cs <- tryCatch(
    canonical_screen_bt(sc, ret, bench, top_n = top_n, cost_bps_oneway = cost_bps,
                        liq_dt = liq, liq_min = 2e8,
                        run_id = paste0("ramp_pf_", fid), strategy_id = paste0("PF_", fid)),
    error = function(e) list(metric_type = "error", note = conditionMessage(e)))

  # rank IC (cross-sectional spearman of score vs forward return), per month
  ic_dt <- merge(sc, ret, by = c("Date", "Ticker"))
  ic_by_m <- ic_dt[, {
    if (.N >= 10 && stats::sd(score) > 0 && stats::sd(Ret_1m) > 0)
      .(ic = stats::cor(score, Ret_1m, method = "spearman"))
    else .(ic = NA_real_)
  }, by = Date]
  rank_ic_mean <- mean(ic_by_m$ic, na.rm = TRUE)
  rank_ic_sd <- stats::sd(ic_by_m$ic, na.rm = TRUE)
  n_ic <- sum(!is.na(ic_by_m$ic))
  rank_ic_ir <- if (!is.na(rank_ic_sd) && rank_ic_sd > 0) rank_ic_mean / rank_ic_sd else NA_real_

  # net quintile spread (top quintile - bottom quintile, net) — canonical_screen은 top-N만이므로
  #   별도 quintile long-short(검증 진단; long-only 운용 아님, 신호력 측정용)
  qspread <- ic_dt[, {
    if (.N >= 10 && stats::sd(score) > 0) {
      q <- cut(frank(score), breaks = 5, labels = FALSE)
      top <- mean(Ret_1m[q == 5], na.rm = TRUE); bot <- mean(Ret_1m[q == 1], na.rm = TRUE)
      .(spread = top - bot)
    } else .(spread = NA_real_)
  }, by = Date]
  net_quintile_spread <- mean(qspread$spread, na.rm = TRUE) - (cost_bps / 1e4)  # net 근사(1 leg cost)

  # cost drag = turnover_annual * cost (이미 canonical_screen net 반영; drag = gross_sr - net 영향 proxy)
  cost_drag <- if (!is.null(cs$turnover_annual) && !is.na(cs$turnover_annual))
    cs$turnover_annual * (cost_bps / 1e4) else NA_real_

  # DSR (deflated sharpe) — 단일팩터 검증, n_trials는 호출자 집계. 여기선 SR 기록만.
  net_sr <- cs$net_sr %||% NA_real_

  list(
    factor_id = fid,
    metric_type = if (identical(cs$metric_type, "canonical_screen")) "backtested" else (cs$metric_type %||% "error"),
    n_months = cs$n_months %||% 0L,
    n_ic_months = n_ic,
    rank_ic_mean = rank_ic_mean,
    rank_ic_ir = rank_ic_ir,
    net_quintile_spread_oos = net_quintile_spread,
    cost_drag = cost_drag,
    net_sr = net_sr,
    portfolio_alpha_t_nw = cs$portfolio_alpha_t_nw_lag3 %||% NA_real_,
    information_ratio = cs$information_ratio %||% NA_real_,
    turnover_annual = cs$turnover_annual %||% NA_real_,
    note = cs$note %||% NA_character_
  )
}

#==============================================================================
# 3. 승인 정책 (config gate4_pure_factor.approve_rule)
#==============================================================================
#' @param metrics_dt data.table from validate_factor rows
#' @param econ_labels named (factor_id -> economic_rationale present TRUE/FALSE)
#' @return data.table(factor_id, ..., status[approved/rejected], reject_reason, lineage)
approve_factors <- function(metrics_dt, config, econ_present = NULL) {
  ar <- config$gate4_pure_factor$approve_rule
  m <- copy(metrics_dt)
  m[, econ_ok := if (is.null(econ_present)) TRUE else (factor_id %in% names(econ_present)[unlist(econ_present)])]
  m[, rule_ic := !is.na(rank_ic_ir) & rank_ic_ir >= (ar$rank_ic_ir_oos_min %||% 0)]
  m[, rule_spread := !is.na(net_quintile_spread_oos) & net_quintile_spread_oos >= (ar$net_quintile_spread_oos_min %||% 0)]
  m[, rule_cost := is.na(cost_drag) | cost_drag <= (ar$cost_drag_max %||% 0.05)]
  m[, rule_metric := metric_type == "backtested"]
  m[, status := fifelse(econ_ok & rule_ic & rule_spread & rule_cost & rule_metric, "approved", "rejected")]
  m[, reject_reason := fifelse(status == "approved", NA_character_,
      paste0(
        fifelse(!econ_ok, "no_econ_rationale;", ""),
        fifelse(!rule_ic, "rank_ic_ir<min;", ""),
        fifelse(!rule_spread, "spread<min;", ""),
        fifelse(!rule_cost, "cost_drag>max;", ""),
        fifelse(!rule_metric, "metric_type!=backtested;", "")))]
  m[, lineage := paste0("source_signal=factor_db:", factor_id,
                        "; neutralizers=sector+log_mktcap+beta+vol+liquidity(FWL)")]
  m[]
}

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L || (length(a) == 1L && is.na(a))) b else a

cat("[factor_validation.R] Loaded — build_monthly_forward_returns / build_adv20_t1 / validate_factor / approve_factors\n")
