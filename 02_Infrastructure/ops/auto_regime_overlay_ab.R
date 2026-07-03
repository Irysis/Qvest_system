#!/usr/bin/env Rscript
# auto_regime_overlay_ab.R — H2 regime 오버레이 A/B (도훈 mandate 2026-06-18, "regime H2 바로 진행").
#
# 목적: §6 SR2.5 유일 입증 레버 = overlay. 현 book 오버레이(M4 BOCPD × AR × R05 tail)에 *추가/대체* regime 신호가 SR 개선하는지 검증.
#   후보 regime 신호: ① unified_regime_signal(MSM+FRED+KTRI+VEA 앙상블 — book의 M4와 *다른* 탐지기) ② vol-target(변동성 타겟팅, 더 granular).
#   각 후보를 (a) standalone 오버레이 (b) book 오버레이에 *stacked* 로 테스트. 비교: bare / book_L5 / 후보들.
#   AX-001 v2: 방어형은 조건부 평가 — CRISIS 라벨 월에서 손실 완화·crisis_alpha 동반 산출.
# 토대: 가중=strategy(현 book) 고정, exposure 스칼라만 변경(weighted_screen_bt exposure_dt). 캐리어 selection 고정.
# PIT: regime 신호는 *직전 월말*(decision 이전 known) lag 적용. vol-target은 trailing 12m(strictly before). 자본 admit 없음(측정만).
# 단일스레드(arrow): OMP_NUM_THREADS=1 ARROW_NUM_THREADS=1.
suppressMessages({ library(data.table); library(arrow) })
`%||%` <- function(a, b) if (!is.null(a) && length(a) > 0 && !all(is.na(a))) a else b
root <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); if (dir.exists(root)) setwd(root)
source("02_Infrastructure/contracts/weighted_screen_bt.R")
Sys.setenv(QVEST_WEIGHTING_AB_NORUN = "1")
source("02_Infrastructure/ops/auto_weighting_ab.R")   # build_period_bench / build_overlay_exposure / WEIGHTERS$strategy

CARRIER <- "06_Registry/book_carrier/carrier_STR_1715_AR_on_M4_R05_overlay_PG2.parquet"
# regime Category → exposure(=1-cash) 디리스크 스케줄 (book deprecated cash NORMAL10/CAUTION20/CRISIS40 정합 + RISK_ON full)
CAT_EXPOSURE <- c(RISK_ON = 1.00, NEUTRAL = 1.00, CAUTION = 0.70, CRISIS = 0.40, RISK_OFF = 0.40)
VT_TARGET_M <- 0.055   # 월간 목표 변동성(~19% 연율) 고정상수(lookahead 없음). long-only no-lev → exposure=min(1, target/trailing).
VT_WIN <- 12L

.prev_month_ym <- function(d) format(as.Date(format(as.Date(d), "%Y-%m-01")) - 1, "%Y-%m")

#' 후보 regime exposure 스케줄(Date=eval_date, exposure) PIT 직전월 lag.
build_unified_cat_exposure <- function(periods) {
  u <- as.data.table(read_parquet(".cache/unified_regime_signal.parquet"))[, .(ym_sig = as.character(YM), Category = as.character(Category))]
  pr <- as.data.table(copy(periods))
  pr[, ym_sig := .prev_month_ym(decision_date)]            # 직전 월말 신호(decision 이전 known)
  pr[u, on = "ym_sig", Category := i.Category]             # data.table join (base merge 회피)
  pr[, exposure := as.numeric(CAT_EXPOSURE[Category])]
  pr[is.na(exposure), exposure := 1.0]                     # 신호 결측 → full(no overlay)
  list(exp = pr[, .(Date = eval_date, exposure)], cat = pr[, .(Date = eval_date, regime_sig = Category)])
}
#' vol-target exposure: bare 포트 gross 수익 trailing 12m sd → min(1, target/vol). PIT(strictly before).
build_voltarget_exposure <- function(bare_gross) {       # bare_gross: data.table(Date, r) eval_date 순
  setorder(bare_gross, Date); n <- nrow(bare_gross); exp <- rep(1.0, n)
  for (i in seq_len(n)) {
    if (i > VT_WIN) {
      v <- sd(bare_gross$r[(i - VT_WIN):(i - 1)], na.rm = TRUE)
      if (is.finite(v) && v > 0) exp[i] <- min(1.0, VT_TARGET_M / v)
    }
  }
  data.table(Date = bare_gross$Date, exposure = exp)
}

run_regime_overlay_ab <- function(carrier_path = CARRIER, cost_bps = 15) {
  car <- as.data.table(read_parquet(carrier_path))[selected == TRUE & !is.na(ret_fwd)]
  car[, `:=`(decision_date = as.Date(decision_date), eval_date = as.Date(eval_date))]
  returns_dt <- car[, .(Date = eval_date, Ticker, Ret_1m = ret_fwd)]
  periods <- unique(car[, .(decision_date, eval_date)]); setorder(periods, eval_date)
  bench_dt <- build_period_bench(periods)[!is.na(BM_Ret)]
  W_strat <- car[, .(Date = eval_date, Ticker, w = weight_strategy / sum(weight_strategy)), by = .(eval_date)][, .(Date, Ticker, w)]
  bare_gross <- car[, .(r = sum((weight_strategy / sum(weight_strategy)) * ret_fwd)), by = .(Date = eval_date)]

  bx <- build_overlay_exposure()                             # auto_weighting_ab판은 list(exposure, ref) 반환
  book_exp <- if (is.null(bx)) NULL else if (is.data.frame(bx)) as.data.table(bx) else as.data.table(bx$exposure)
  if (!is.null(book_exp)) book_exp <- book_exp[, .(Date = as.Date(Date), exposure = as.numeric(exposure))]
  uc <- build_unified_cat_exposure(periods); uni_exp <- as.data.table(uc$exp)
  vt_exp <- as.data.table(build_voltarget_exposure(bare_gross))
  # stacked = book × candidate (data.table join)
  stack <- function(a, b) { a[as.data.table(b), on = "Date", .(Date, exposure = x.exposure * i.exposure)] }
  uni_x_book <- if (!is.null(book_exp)) stack(book_exp, uni_exp) else uni_exp
  vt_x_book  <- if (!is.null(book_exp)) stack(book_exp, vt_exp)  else vt_exp

  scen <- list(bare = NULL, book_L5 = book_exp,
               uni_cat = uni_exp, uni_cat_x_book = uni_x_book,
               voltgt = vt_exp, voltgt_x_book = vt_x_book)
  res <- list()
  for (nm in names(scen)) {
    r <- weighted_screen_bt(W_strat, returns_dt, bench_dt, cost_bps_oneway = cost_bps,
                            run_id = paste0("h2_", nm), strategy_id = paste0("h2_", nm), exposure_dt = scen[[nm]])
    avg_exp <- if (is.null(scen[[nm]])) 1.0 else mean(scen[[nm]]$exposure, na.rm = TRUE)
    res[[nm]] <- data.table(scenario = nm, abs_SR = r$abs_net_sr, abs_CAGR = r$abs_cagr, abs_MDD = r$abs_mdd,
                            IR = r$information_ratio, PORT_t = r$portfolio_alpha_t_nw_lag3, avg_exposure = avg_exp)
  }
  tab <- rbindlist(res, fill = TRUE)

  # AX-001 v2: crisis-conditional eval — 신호가 CRISIS/CAUTION 라벨한 월에서 bare vs overlaid 손실 비교
  cr <- as.data.table(bare_gross)[as.data.table(uc$cat), on = "Date"]   # Date, r, regime_sig
  be <- if (is.null(book_exp)) data.table(Date = bare_gross$Date, book_e = 1.0) else book_exp[, .(Date, book_e = exposure)]
  cr[be, on = "Date", book_e := i.book_e]; cr[is.na(book_e), book_e := 1.0]
  cr[uni_exp, on = "Date", uni_e := i.exposure]; cr[is.na(uni_e), uni_e := 1.0]
  cr[, crisis := regime_sig %in% c("CRISIS", "CAUTION")]
  crisis_tab <- cr[, .(n = .N,
                       bare_mean = mean(r), book_mean = mean(r * book_e),
                       uni_mean = mean(r * uni_e), uni_x_book_mean = mean(r * book_e * uni_e)),
                   by = .(crisis)]

  list(tab = tab, crisis = crisis_tab, n_months = nrow(bench_dt))
}

if ((sys.nframe() == 0L || identical(environment(), globalenv())) && Sys.getenv("QVEST_REGIME_AB_NORUN") != "1") {
  cat("\n##### H2 regime 오버레이 A/B — unified 앙상블(MSM+FRED+KTRI+VEA) + vol-target vs 현 book 오버레이 #####\n")
  out <- run_regime_overlay_ab()
  cat(sprintf("\n=== H2 시나리오 비교 (strategy 가중 고정, %d개월 vs KOSPI200) ===\n", out$n_months))
  print(out$tab)
  cat("\n=== AX-001 crisis-conditional (신호 CRISIS/CAUTION 라벨 월) 월평균수익 ===\n")
  print(out$crisis)
  fwrite(out$tab, "06_Registry/book_carrier/h2_regime_overlay_ab.csv")
  fwrite(out$crisis, "06_Registry/book_carrier/h2_regime_crisis_eval.csv")
  cat("\n주: book_L5=현 book 오버레이. uni_cat=앙상블 regime standalone. *_x_book=book에 stacked(추가레버 검증). voltgt=변동성타겟. adopt 수동.\n")
}
