#!/usr/bin/env Rscript
# auto_sigma_weighting_ab.R — H1b Σ-가중 A/B (도훈 mandate 2026-06-18, optimizer 논문 소비).
#
# 소비 논문: arXiv 2606.14798 "Two Sides of Schur Damping"(HRP↔min-var 1-param 보간, 최적 damping = Ledoit-Wolf 강도)
#           + 2606.12612 "Mathematics of HPO"(EW/IV/RP/HRP/RA-HRP forecast-light rule class).
# 설계: 현 book의 faithful 캐리어(selection 고정) 위에, *Σ 기반 forecast-light 가중*을 매월 PIT 추정(t 이전 일별수익 trailing)해
#       weighted_screen_bt(계약백테, NW lag-3)로 EW·기존전략(strategy)과 A/B. bare + with-overlay(현 book β_combined) 2-tier.
#   ★알파(score) 미사용 가중(IV/HRP/min-var)이 score-tilt book을 위험조정으로 이기는지 검증. adopt 수동(governor 정지).
# PIT: 가중은 (start_d 이전) trailing 일별수익으로 Σ 추정 → forward ret_fwd로 실현. C1/C9 준수.
# 단일스레드(arrow segfault 회피): OMP_NUM_THREADS=1 ARROW_NUM_THREADS=1.
suppressMessages({ library(data.table); library(arrow) })
`%||%` <- function(a, b) if (!is.null(a) && length(a) > 0 && !all(is.na(a))) a else b
root <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); if (dir.exists(root)) setwd(root)
source("02_Infrastructure/contracts/weighted_screen_bt.R")
source("02_Infrastructure/portfolio/hrp_core.R")            # calc_hrp_weights / .get_cor_cov / .build_ret_matrix
source("02_Infrastructure/portfolio/strategy_tilt_weights.R")  # normalize_long_only (long-only cap)

LOOKBACK_DAYS <- 250L   # 약 1년 일별 — Σ 추정창(20종목엔 충분, LW가 N≈T 보정)
UB <- 0.20

# ── 벤치(현 book과 동일): .cache/benchmark.parquet 일별 → (start_d,eval_date] 복리 ──
build_period_bench <- function(periods, bench_path = ".cache/benchmark.parquet") {
  bp <- as.data.table(read_parquet(bench_path)); bp[, d := as.Date(Date)]; setorder(bp, d)
  pr <- copy(periods); setorder(pr, eval_date); out <- vector("list", nrow(pr))
  for (i in seq_len(nrow(pr))) {
    dd <- as.Date(pr$decision_date[i]); ed <- as.Date(pr$eval_date[i])
    sd_i <- bp[d >= dd, min(d)]
    if (is.infinite(sd_i) || is.na(sd_i)) { out[[i]] <- data.table(Date = ed, BM_Ret = NA_real_); next }
    win <- bp[d > sd_i & d <= ed, BM_Ret]
    out[[i]] <- data.table(Date = ed, BM_Ret = if (length(win) == 0) NA_real_ else prod(1 + win, na.rm = TRUE) - 1)
  }
  rbindlist(out)
}
# ── 현 book 실현 오버레이 노출 β_combined ──
build_overlay_exposure <- function(layer5_csv =
        "05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/04_backtest_results/period_returns_layer5.csv",
        r05_variant = "V5") {
  if (!file.exists(layer5_csv)) return(NULL)
  L <- fread(layer5_csv); bcol <- paste0("beta_R05_", r05_variant)
  if (!all(c("anchor_date","m4_weight_lag","beta_threshold_lag",bcol) %in% names(L))) return(NULL)
  L[, exposure := as.numeric(m4_weight_lag) * as.numeric(beta_threshold_lag) * as.numeric(get(bcol))]
  L[, .(Date = as.Date(anchor_date), exposure)]
}

# ── 가중 헬퍼 ──
.fill_dropped <- function(w_surv, all_tk) {   # 이력부족(survived 외) 종목은 EW(1/N)로, survived는 (1-dropped) 스케일
  w <- setNames(numeric(length(all_tk)), all_tk)
  dropped <- setdiff(all_tk, names(w_surv))
  if (length(dropped)) { w[dropped] <- 1 / length(all_tk); scale <- 1 - sum(w[dropped]) }
  else scale <- 1
  w[names(w_surv)] <- w_surv * scale
  if (sum(w) > 0) w <- w / sum(w)
  w
}
.iv_w <- function(Sigma) { s <- sqrt(diag(Sigma)); w <- 1 / s; w[!is.finite(w)] <- 0; w / sum(w) }
.minvar_w <- function(Sigma) {
  p <- ncol(Sigma); Sigma <- Sigma + diag(1e-8, p)
  inv1 <- tryCatch(solve(Sigma, rep(1, p)), error = function(e) rep(1 / p, p))
  w <- pmax(inv1, 0); if (sum(w) <= 0) w <- rep(1 / p, p)
  names(w) <- colnames(Sigma)
  # ★(2026-08-08 수리) 합-정규화를 캡 적용 **전에**. normalize_long_only 은 `w[w>ub] <- ub` 를
  #   정규화 전에 수행하므로(production verbatim), solve(Σ,1) 의 원 스케일(실측 1147~3439)을
  #   그대로 넣으면 전 원소가 ub 로 잘려 **정확히 EW** 가 됐다. 06-18 이래 minvar/MVO 3종이
  #   EW 를 이름만 바꿔 재고 있었다(실측 range 0.040000~0.040000 = 1/25).
  w <- w / sum(w)
  normalize_long_only(w, lb = 0, ub = UB, target_sum = 1)
}
# 알파+Σ 하이브리드 (Markowitz/HPO implied-return tangency 방향): w ∝ Σ⁻¹ μ̂, long-only cap.
#   μ̂ = score_eff(현 book 알파). 알파 *방향* + Σ *위험구조* 결합. forecast-light(IV/HRP/minvar)와 달리 알파 사용.
.mvo_w <- function(Sigma, mu_named) {
  p <- ncol(Sigma); Sigma <- Sigma + diag(1e-8, p)
  mu <- mu_named[colnames(Sigma)]; mu[is.na(mu)] <- 0
  w_raw <- tryCatch(solve(Sigma, mu), error = function(e) mu)   # Σ⁻¹ μ̂
  w <- pmax(w_raw, 0); if (sum(w) <= 0) w <- rep(1 / p, p)      # 전부 음알파면 EW 폴백
  names(w) <- colnames(Sigma)
  normalize_long_only(w, lb = 0, ub = UB, target_sum = 1)
}

# ── (2026-08-08 (b)안) 논문 유래 method 어댑터 레지스트리 ───────────────────────
#   구 상태: method 집합이 이 파일에 하드코딩된 상수(2026-06-18 논문 2편 기준)라, 이후 라우팅된
#   optimizer 논문은 **낄 자리가 없어** mode_queue 에 제목만 남고 소비되지 않았다.
#   (b)안 = 그 집합을 **인자**로 바꾼다. 등록 어댑터는 `SIGMA_EXTRA_ADAPTERS` 에 실려 들어온다.
#   ★제약(long-only/Σw=1/w≤UB)은 어댑터가 아니라 wrap_adapter 가 강제한다.
SIGMA_EXTRA_ADAPTERS <- list()   # method_id -> wrapped adapter fn. run_sigma_ab() 인자로 주입.

#' Σ-가중 per-month: 보유종목 tk + PIT ret_sub(start_d 이전) [+ mu(MVO용 score)] → method weights(named, 합1, cap UB).
sigma_weights_month <- function(tk, ret_sub, method, mu = NULL,
                                extra = SIGMA_EXTRA_ADAPTERS,
                                decision_date = NA, eval_date = NA) {
  rm <- .build_ret_matrix(tk, ret_sub, LOOKBACK_DAYS)   # survived only (>=30 obs), NA→0
  if (is.null(rm) || ncol(rm) < 3) return(setNames(rep(1 / length(tk), length(tk)), tk))  # fallback EW
  if (method %in% c("HRP_sample", "HRP_lw")) {
    cm <- if (method == "HRP_lw") "ledoit_wolf" else "sample"
    w <- calc_hrp_weights(tk, ret_sub, n_days = LOOKBACK_DAYS, max_w = UB, cov_method = cm)  # 이미 full tk + cap
    return(w / sum(w))
  }
  cm <- if (grepl("_lw$", method)) "ledoit_wolf" else "sample"
  cc <- tryCatch(.get_cor_cov(rm, cm), error = function(e) .get_cor_cov(rm, "sample"))
  Sigma <- cc$cov
  # ★등록 어댑터 우선 조회 — 빌트인 이름과 충돌하지 않도록 정확 일치만.
  if (!is.null(extra[[method]])) {
    ctx <- list(Sigma = Sigma, R = rm, mu = mu, assets = colnames(Sigma), ub = UB,
                lookback_days = LOOKBACK_DAYS,
                decision_date = decision_date, eval_date = eval_date)
    return(.fill_dropped(extra[[method]](ctx), tk))
  }
  w_surv <- switch(sub("_.*$", "", method),
                   IV     = { w <- .iv_w(Sigma); names(w) <- colnames(Sigma); w },
                   minvar = .minvar_w(Sigma),
                   MVO    = .mvo_w(Sigma, mu),   # 알파+Σ 하이브리드
                   stop(sprintf("unknown sigma method: %s (빌트인도 등록 어댑터도 아님)", method)))
  .fill_dropped(w_surv, tk)
}

run_sigma_ab <- function(carrier_path =
        "06_Registry/book_carrier/carrier_STR_1715_AR_on_M4_R05_overlay_PG2.parquet",
        rawdata = ".cache/rawdata.parquet",
        sigma_methods = c("IV", "HRP_lw", "minvar_lw", "MVO_sample", "MVO_lw"),
        cost_bps = 15, with_overlay = FALSE,
        extra_adapters = SIGMA_EXTRA_ADAPTERS) {
  # (2026-08-08 (b)안) 등록 어댑터를 method 목록에 합류. 빌트인과 이름 충돌 시 빌트인 우선(경고).
  if (length(extra_adapters)) {
    .dup <- intersect(names(extra_adapters), sigma_methods)
    if (length(.dup)) {
      cat(sprintf("[sigma_ab] ★method_id 충돌 — 빌트인 우선, 등록분 제외: %s\n", paste(.dup, collapse=", ")))
      extra_adapters <- extra_adapters[setdiff(names(extra_adapters), .dup)]
    }
    sigma_methods <- c(sigma_methods, names(extra_adapters))
    cat(sprintf("[sigma_ab] 논문 유래 method 합류: %s\n", paste(names(extra_adapters), collapse=", ")))
  }
  car <- as.data.table(read_parquet(carrier_path))
  car <- car[selected == TRUE & !is.na(ret_fwd)]
  car[, `:=`(decision_date = as.Date(decision_date), eval_date = as.Date(eval_date))]
  returns_dt <- car[, .(Date = eval_date, Ticker, Ret_1m = ret_fwd)]
  periods <- unique(car[, .(decision_date, eval_date)])
  bench_dt <- build_period_bench(periods)[!is.na(BM_Ret)]
  exp_dt <- if (isTRUE(with_overlay)) build_overlay_exposure() else NULL
  held_tk <- unique(car$Ticker)
  raw <- as.data.table(read_parquet(rawdata, col_select = c("Date","Ticker","Ret")))[Ticker %in% held_tk]
  setkey(raw, Date)
  cat(sprintf("[sigma_ab] months=%d, held_tickers=%d, raw rows(held)=%s, overlay=%s\n",
              nrow(periods), length(held_tk), format(nrow(raw), big.mark=","), if (is.null(exp_dt)) "OFF" else "ON"))

  # baselines (EW, strategy passthrough) — Σ 불요
  base_W <- list(
    EW = car[, .(Date = eval_date, Ticker, w = 1 / .N), by = .(eval_date)][, .(Date, Ticker, w)],
    strategy = car[, .(Date = eval_date, Ticker, w = weight_strategy / sum(weight_strategy)), by = .(eval_date)][, .(Date, Ticker, w)]
  )

  # Σ-methods: per-month 가중
  setorder(periods, decision_date)
  sigma_W <- setNames(lapply(sigma_methods, function(m) vector("list", nrow(periods))), sigma_methods)
  for (i in seq_len(nrow(periods))) {
    dd <- periods$decision_date[i]; ed <- periods$eval_date[i]
    hp <- car[eval_date == ed, .(Ticker, score)]
    tk <- hp$Ticker; mu <- setNames(hp$score, hp$Ticker)   # MVO용 μ̂=score_eff
    start_d <- raw[Date >= dd, min(Date)]
    if (is.infinite(start_d) || is.na(start_d)) next
    ret_sub <- raw[Date < start_d, .(Date, Ticker, Ret)]   # PIT: 매수 이전
    for (m in sigma_methods) {
      w <- tryCatch(sigma_weights_month(tk, ret_sub, m, mu = mu, extra = extra_adapters,
                                        decision_date = dd, eval_date = ed),
                    error = function(e) setNames(rep(1/length(tk), length(tk)), tk))
      sigma_W[[m]][[i]] <- data.table(Date = ed, Ticker = names(w), w = as.numeric(w))
    }
  }
  W_all <- c(base_W, lapply(sigma_W, function(x) rbindlist(x)))

  res <- list()
  for (mth in names(W_all)) {
    W <- W_all[[mth]]
    r <- weighted_screen_bt(W, returns_dt, bench_dt, cost_bps_oneway = cost_bps,
                            run_id = paste0("sig_", mth), strategy_id = paste0("sig_", mth),
                            exposure_dt = exp_dt)
    res[[mth]] <- data.table(method = mth, n_months = r$n_months,
                             abs_SR = r$abs_net_sr, abs_CAGR = r$abs_cagr, abs_MDD = r$abs_mdd,
                             IR = r$information_ratio, PORT_t = r$portfolio_alpha_t_nw_lag3,
                             active_SR = r$net_sr, turnover = r$turnover_annual)
  }
  rbindlist(res, fill = TRUE)
}

if ((sys.nframe() == 0L || identical(environment(), globalenv())) && Sys.getenv("QVEST_SIGMA_AB_NORUN") != "1") {
  cat("\n##### H1b Σ-가중 A/B — optimizer 논문(Schur Damping 2606.14798 + HPO 2606.12612) 소비 #####\n")
  tb <- run_sigma_ab(with_overlay = FALSE)
  cat("\n=== [BARE] Σ-가중 vs EW/strategy (오버레이 없음) ===\n"); print(tb)
  to <- run_sigma_ab(with_overlay = TRUE)
  cat("\n=== [WITH-OVERLAY] (현 book β_combined 적용 = 동일조건 head-to-head, 의사결정용) ===\n"); print(to)
  fwrite(tb, "06_Registry/book_carrier/h1b_sigma_ab_bare.csv")
  fwrite(to, "06_Registry/book_carrier/h1b_sigma_ab_overlay.csv")
  cat("\n주: IV/HRP/minvar = forecast-light Σ-가중(알파 score 미사용). minvar_lw = Schur damping 최적(LW 강도). strategy=현 book(score-tilt+TOphi). adopt 수동.\n")
}
