#!/usr/bin/env Rscript
# auto_weighting_ab.R — H1 가중 A/B 하니스 (도훈 mandate 2026-06-18, "셋다 구축" / faithful 캐리어 재배선).
#
# 목적: 현 book의 *faithful per-stock 캐리어*(06_Registry/book_carrier/, selection+score+weight_strategy+forward 실현수익)를 고정하고
#       *가중만* 바꿔 weighted_screen_bt(계약백테, NW lag-3)로 A/B. optimizer/risk 논문 라우트 공용 하니스.
#   비교셋: EW · score_tilt · strategy(기존전략방법론=weight_strategy passthrough, 검증앵커) [+논문법은 add_weighter()로 주입].
#
# 정합(faithful 캐리어): 종목수익 ret_fwd는 보유창 (start_d,eval_date] RAWDATA forward 복리(전략 run_all.R verbatim).
#   bt 시간축 = eval_date. 벤치 = .cache/benchmark.parquet 일별 → 동일 (start_d,eval_date] 복리(전략 05_benchmark는 전부 0 버그라 미사용).
# 단일스레드 권장(arrow): OMP_NUM_THREADS=1 ARROW_NUM_THREADS=1.
suppressMessages({ library(data.table); library(arrow) })
`%||%` <- function(a, b) if (!is.null(a) && length(a) > 0 && !all(is.na(a))) a else b
root <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); if (dir.exists(root)) setwd(root)
source("02_Infrastructure/contracts/weighted_screen_bt.R")
source("02_Infrastructure/portfolio/strategy_tilt_weights.R")   # linear_tilt_qd(rank-tilt) — book 가중 분해용

# ── 가중 함수들: 보유패널 P(decision_date,eval_date,Ticker,score,weight_strategy) → weights(Date=eval_date,Ticker,w) ──
# ★용어주의: 현 book 가중 = strategy(rank-tilt λ=1.5 + TOphi φ=3). score_prop/rank_tilt는 book과 *다른* 변형.
.w_ew <- function(P) P[, .(Date = eval_date, Ticker, w = 1 / .N), by = .(eval_date)][, eval_date := NULL][]
.w_score_prop <- function(P) {   # raw 점수 비례: w ∝ (score - min + eps). rank변환·TOphi 없음 (book 아님)
  P[, .(Date = eval_date, Ticker, w = { s <- score - min(score) + 0.1; s / sum(s) }), by = .(eval_date)][, eval_date := NULL][]
}
.w_rank_tilt <- function(P) {    # book의 rank-tilt(λ=1.5)만, TOphi 패널티 無 — raw↔rank 효과 분리용
  P[, {
    w <- linear_tilt_qd(setNames(score, Ticker), lambda = 1.5, lb = 0, ub = 0.20)
    list(Ticker = Ticker, w = as.numeric(w))
  }, by = .(eval_date)][, .(Date = eval_date, Ticker, w)]
}
.w_strategy <- function(P) {     # 현 book(기존전략방법론): rank-tilt λ=1.5 + TOphi φ=3 = 저장된 weight_strategy passthrough
  P[, .(Date = eval_date, Ticker, w = weight_strategy / sum(weight_strategy)), by = .(eval_date)][, eval_date := NULL][]
}
WEIGHTERS <- list(EW = .w_ew, score_prop = .w_score_prop, rank_tilt = .w_rank_tilt, strategy = .w_strategy)
#' 논문/외부 가중법 주입점 (optimizer 라우트): name + fn(P)->(Date,Ticker,w)
add_weighter <- function(name, fn) { WEIGHTERS[[name]] <<- fn; invisible(WEIGHTERS) }

#' .cache/benchmark.parquet 일별 BM_Ret → 각 보유창 (start_d, eval_date] 복리로 per-period 벤치수익.
#'   start_d_i = first bench Date >= decision_date_i (전략 start_d 등가). 창은 연속(eval_date_i = start_d_{i+1}).
build_period_bench <- function(periods, bench_path = ".cache/benchmark.parquet") {
  bp <- as.data.table(read_parquet(bench_path))
  bp[, d := as.Date(Date)]
  setorder(bp, d)
  pr <- copy(periods); setorder(pr, eval_date)
  out <- vector("list", nrow(pr))
  for (i in seq_len(nrow(pr))) {
    dd <- as.Date(pr$decision_date[i]); ed <- as.Date(pr$eval_date[i])
    sd_i <- bp[d >= dd, min(d)]
    if (is.infinite(sd_i) || is.na(sd_i)) { out[[i]] <- data.table(Date = ed, BM_Ret = NA_real_); next }
    win <- bp[d > sd_i & d <= ed, BM_Ret]
    bm <- if (length(win) == 0) NA_real_ else prod(1 + win, na.rm = TRUE) - 1
    out[[i]] <- data.table(Date = ed, BM_Ret = bm)
  }
  rbindlist(out)
}

#' 현 book의 *실현 오버레이 노출* β_combined = m4_weight_lag × beta_threshold_lag(AR) × beta_R05_V5(admit)
#'   를 period_returns_layer5.csv에서 추출 (anchor_date == 캐리어 eval_date). 가중-무관 스칼라(선택/시장 driven)라
#'   EW/score_tilt/strategy 동일 schedule 적용 = 공정 "with-overlay" 비교. admit variant=V5(forward_weights_R05_AR.R 정합).
build_overlay_exposure <- function(layer5_csv =
        "05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/04_backtest_results/period_returns_layer5.csv",
        r05_variant = "V5") {
  if (!file.exists(layer5_csv)) { cat(sprintf("[ab] period_returns_layer5 없음: %s\n", layer5_csv)); return(NULL) }
  L <- fread(layer5_csv)
  bcol <- paste0("beta_R05_", r05_variant)
  need <- c("anchor_date", "m4_weight_lag", "beta_threshold_lag", bcol)
  if (!all(need %in% names(L))) { cat(sprintf("[ab] layer5 컬럼 누락: %s\n", paste(setdiff(need, names(L)), collapse=","))); return(NULL) }
  L[, exposure := as.numeric(m4_weight_lag) * as.numeric(beta_threshold_lag) * as.numeric(get(bcol))]
  list(exposure = L[, .(Date = as.Date(anchor_date), exposure)],
       ref = L[, .(Date = as.Date(anchor_date), ret_L5 = as.numeric(get(paste0("ret_L5_", r05_variant))))])
}

#' faithful 캐리어로 가중 A/B 실행 (bare + optional with-overlay).
#' @param carrier_path parquet (decision_date,eval_date,Ticker,score,weight_strategy,ret_fwd,selected)
#' @param methods 가중법 이름 (WEIGHTERS 키)
#' @param with_overlay TRUE면 현 book 실현 β_combined 노출 적용(=현 book과 동일 오버레이로 head-to-head)
run_weighting_ab <- function(carrier_path =
        "06_Registry/book_carrier/carrier_STR_1715_AR_on_M4_R05_overlay_PG2.parquet",
        methods = c("EW", "score_prop", "rank_tilt", "strategy"), cost_bps = 15, with_overlay = FALSE) {
  car <- as.data.table(read_parquet(carrier_path))
  car <- car[selected == TRUE & !is.na(ret_fwd)]
  car[, `:=`(decision_date = as.Date(decision_date), eval_date = as.Date(eval_date))]
  P <- car[, .(decision_date, eval_date, Ticker, score, weight_strategy)]
  returns_dt <- car[, .(Date = eval_date, Ticker, Ret_1m = ret_fwd)]   # weighted_screen_bt는 Ret_1m 컬럼명 요구
  periods <- unique(car[, .(decision_date, eval_date)])
  bench_dt <- build_period_bench(periods)
  bench_dt <- bench_dt[!is.na(BM_Ret)]
  exp_dt <- NULL
  if (isTRUE(with_overlay)) {
    ov <- build_overlay_exposure()
    if (!is.null(ov)) exp_dt <- ov$exposure
  }
  cat(sprintf("[ab] 캐리어 months=%d, 벤치 months=%d, held rows=%d, overlay=%s\n",
              length(unique(car$eval_date)), nrow(bench_dt), nrow(car), if (is.null(exp_dt)) "OFF" else "ON(β_combined V5)"))

  res <- list()
  for (mth in methods) {
    wf <- WEIGHTERS[[mth]]; if (is.null(wf)) { cat(sprintf("[ab] unknown method %s\n", mth)); next }
    W <- wf(P)
    r <- weighted_screen_bt(W, returns_dt, bench_dt, cost_bps_oneway = cost_bps,
                            run_id = paste0("ab_", mth), strategy_id = paste0("ab_", mth),
                            exposure_dt = exp_dt)
    res[[mth]] <- data.table(method = mth, n_months = r$n_months,
                             abs_SR = r$abs_net_sr, abs_CAGR = r$abs_cagr, abs_MDD = r$abs_mdd,
                             IR = r$information_ratio, PORT_t = r$portfolio_alpha_t_nw_lag3,
                             alpha_ann = r$alpha_annualized, active_SR = r$net_sr,
                             turnover = r$turnover_annual)
  }
  rbindlist(res, fill = TRUE)
}

if ((sys.nframe() == 0L || identical(environment(), globalenv())) && Sys.getenv("QVEST_WEIGHTING_AB_NORUN") != "1") {
  tab_bare <- run_weighting_ab(with_overlay = FALSE)
  cat("\n=== H1 가중 A/B [BARE] (faithful 캐리어 selection 고정, 오버레이 없음) ===\n")
  print(tab_bare)
  tab_ov <- run_weighting_ab(with_overlay = TRUE)
  cat("\n=== H1 가중 A/B [WITH-OVERLAY] (현 book 실현 β_combined=M4×AR×R05_V5 적용 = 현 book과 동일 오버레이 head-to-head) ===\n")
  print(tab_ov)
  # 검증앵커: strategy + overlay = 현 book L5(admit) 재현?
  ov <- build_overlay_exposure()
  if (!is.null(ov)) {
    ref <- ov$ref[!is.na(ret_L5)]
    sr_book <- mean(ref$ret_L5)/sd(ref$ret_L5)*sqrt(12)
    mdd <- function(r){cum<-cumprod(1+r); min(cum/cummax(cum)-1,na.rm=TRUE)}
    cat(sprintf("\n[검증앵커] 현 book L5_V5 직접계산: SR=%.3f CAGR=%.2f%% MDD=%.1f%% (overlay_cascade 표기 SR1.954/CAGR41.5/MDD24.8)\n",
                sr_book, (prod(1+ref$ret_L5)^(12/nrow(ref))-1)*100, mdd(ref$ret_L5)*100))
    cat("   → strategy[WITH-OVERLAY] abs_SR가 이 값에 근접하면 오버레이 tier faithful.\n")
  }
  # 결과 저장
  fwrite(tab_bare, "06_Registry/book_carrier/h1_weighting_ab_bare.csv")
  fwrite(tab_ov,   "06_Registry/book_carrier/h1_weighting_ab_overlay.csv")
  cat("\n주: strategy=기존전략방법론. WITH-OVERLAY tier가 현 book과 동일조건(M4/R05/AR) 비교 — 의사결정용.\n")
}
