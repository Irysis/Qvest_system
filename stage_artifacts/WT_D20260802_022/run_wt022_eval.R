# =============================================================================
# run_wt022_eval.R — WT-D20260802_022 복권형 제외-필터 x 현 PG2 실코드 경로 (도훈 직접 지시)
#   사전등록: stage_artifacts/WT_D20260802_022/preregistration.json (측정 전 고정)
#
#   base    = STR_1715_on_M4_R05_noLayer4_PG2 실코드 경로 VERBATIM 재현
#             (Iter31 run_all.R §5 walk-forward + run_layer5 §3~5 β_R05_V5 + noLayer4 공식)
#             parity 게이트: production 03_period_returns.csv (20260802_LIVE) 정확 재현 의무
#   primary = 동일 경로 + MAX5_63 상위 10% 배제(선별 유니버스 단계) full-path
#             (β_R05는 필터판 자신의 top-20으로 재산출 — 실배치 counterfactual)
#   판정    = ΔIR ≥ +0.05 ∧ paired t > 0 유지 / ΔIR < 0 철회 (net_active_recon_v1)
# 실행: Rscript -e 'source("stage_artifacts/WT_D20260802_022/run_wt022_eval.R")'
# =============================================================================
suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite)
  library(PerformanceAnalytics); library(xts); library(lubridate)
  library(sandwich); library(lmtest)
})
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT_D20260802_022")
`%||%` <- function(a, b) if (is.null(a)) b else a
say <- function(fmt, ...) cat(sprintf(paste0("[wt022] ", fmt, "\n"), ...))

source("02_Infrastructure/validation/overlay_pit_guard.R")

nw_t <- function(x, lag = 3L) {
  x <- x[is.finite(x)]
  if (length(x) < 6L) return(NA_real_)
  fit <- lm(x ~ 1)
  tryCatch(as.numeric(lmtest::coeftest(fit,
      vcov. = sandwich::NeweyWest(fit, lag = lag, prewhite = FALSE))[1, 3]),
    error = function(e) NA_real_)
}

# ── 0. 입력 로드 + vintage 기록 ───────────────────────────────────────────────
IN_FILES <- c(
  alpha  = "stage_artifacts/WT_D20260425_010/alpha_scores.parquet",
  raw    = ".cache/rawdata.parquet",
  bench  = ".cache/benchmark.parquet",
  m4     = "stage_artifacts/WT-D20260430_001_m4_extended.csv",
  r05    = "stage_artifacts/WT_D20260512_003/alpha_scores_new.parquet",
  max5   = "stage_artifacts/WT_D20260802_014/alpha_scores.parquet",
  prod_pr = "04_Research/strategies/STR_1715_WT016_Iter31_GridBestProd/output/03_period_returns.csv",
  l5_21  = "05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/04_backtest_results/period_returns_layer5.csv",
  pr_23  = "05_Production/2.Factor_Model/2-3.STR_1715_on_M4_R05_noLayer4_PG2/04_backtest_results/03_period_returns.csv",
  regime = ".cache/unified_regime_signal.parquet"
)
vintage <- data.table(input = names(IN_FILES), path = IN_FILES,
                      mtime = sapply(IN_FILES, function(p) as.character(file.mtime(p))))
say("입력 vintage:"); print(vintage[, .(input, mtime)])

alpha_scores <- as.data.table(read_parquet(IN_FILES["alpha"]))
alpha_scores[, Date := as.Date(Date)]
setkey(alpha_scores, Date, Ticker)

raw <- as.data.table(read_parquet(IN_FILES["raw"],
        col_select = c("Date", "Ticker", "Close", "Vol", "Ret", "Size")))
raw[, Date := as.Date(Date)]
setkey(raw, Date, Ticker)
raw[, TradingAmt := Close * Vol]

bm <- as.data.table(read_parquet(IN_FILES["bench"]))
bm[, Date := as.Date(Date)]; bm <- bm[is.finite(BM_Ret)]; setorder(bm, Date)

m4_raw <- fread(IN_FILES["m4"]); m4_raw[, Date := as.Date(Date)]
setorder(m4_raw, Date)
m4_raw[, ym := format(Date, "%Y-%m")]
m4_raw[, weight_str1715_lag := shift(weight_str1715, 1, fill = 1.0)]

r05_dt <- as.data.table(read_parquet(IN_FILES["r05"]))
r05_dt[, Date := as.Date(Date)]

MAX5 <- as.data.table(read_parquet(IN_FILES["max5"]))
MAX5[, Date := as.Date(Date)]
MAX5 <- MAX5[is.finite(max5), .(d0 = Date, Ticker, max5)]
# d0(전월말 거래일) → 홀딩월 = month(d0)+1 = sig_label 월
MAX5[, sig_ym := format(as.Date(format(d0, "%Y-%m-01")) %m+% months(1), "%Y-%m")]
# lag1 스트레스: 신호 1개월 지연 → sig_ym +1
MAX5[, sig_ym_lag1 := format(as.Date(format(d0, "%Y-%m-01")) %m+% months(2), "%Y-%m")]

prod_pr <- fread(IN_FILES["prod_pr"]); prod_pr[, date := as.Date(date)]; setorder(prod_pr, date)
l5_21 <- fread(IN_FILES["l5_21"]); l5_21[, anchor_date := as.Date(anchor_date)]
pr_23 <- fread(IN_FILES["pr_23"]); pr_23[, date := as.Date(date)]

ureg <- as.data.table(read_parquet(IN_FILES["regime"]))[, .(Date = as.Date(Date), Category)]
ureg[, hold_ym := format(Date, "%Y-%m")]

# ── 1. Iter31 §5 VERBATIM 헬퍼 (run_all.R에서 정확 복제 — 수정 금지) ─────────
normalize_long_only <- function(w, lb = 0, ub = 0.20, target_sum = 1, max_iter = 50) {
  w[!is.finite(w)] <- 0
  w[w < lb] <- lb
  w[w > ub] <- ub
  s <- sum(w)
  if (s <= 1e-12) {
    n <- length(w)
    return(rep(target_sum / n, n))
  }
  w <- w * (target_sum / s)
  for (k in seq_len(max_iter)) {
    over <- w > ub + 1e-12
    if (!any(over)) break
    excess <- sum(w[over] - ub)
    w[over] <- ub
    free <- which(!over & w > lb + 1e-12)
    if (length(free) == 0) {
      w <- w * (target_sum / sum(w)); break
    }
    w[free] <- w[free] + excess * (w[free] / sum(w[free]))
  }
  w / sum(w) * target_sum
}
linear_tilt_qd <- function(alpha_t, lambda = 1.0, lb = 0, ub = 0.20) {
  N <- length(alpha_t)
  if (N <= 1) return(rep(1, N))
  r <- rank(alpha_t, ties.method = "average")
  centered <- (r - mean(r)) / (N - 1)
  w_raw <- pmax(1 + lambda * 2 * centered, 1e-6)
  w <- w_raw / sum(w_raw)
  normalize_long_only(w, lb = lb, ub = ub, target_sum = 1)
}
linear_tilt_to_penalty_qd <- function(alpha_t, lambda = 1.5, w_prev = NULL,
                                       phi = 3.0, lb = 0, ub = 0.20) {
  w_tilt <- linear_tilt_qd(alpha_t, lambda = lambda, lb = lb, ub = ub)
  names(w_tilt) <- names(alpha_t)
  if (is.null(w_prev) || phi <= 0) return(w_tilt)
  wp <- numeric(length(w_tilt)); names(wp) <- names(w_tilt)
  common <- intersect(names(w_tilt), names(w_prev))
  wp[common] <- w_prev[common]
  dropped <- 1 - sum(wp)
  if (dropped > 0) wp <- wp + dropped * w_tilt
  if (sum(wp) > 0) wp <- wp / sum(wp)
  blend <- phi / (1 + phi)
  w_out <- blend * wp + (1 - blend) * w_tilt
  normalize_long_only(w_out, lb = lb, ub = ub, target_sum = 1)
}

LIQ_THRESHOLD  <- 2e8
COMMISSION_BPS <- 15
MAX_NAMES      <- 20L
MIN_NAMES      <- 15L
UB_WEIGHT      <- 0.20
LAMBDA <- 1.5; TOPHI <- 3

# ── 2. 월별 공유 캐시 (동일 수식 — 계산량만 절약, 값 불변) ────────────────────
sig_dates <- sort(unique(alpha_scores[!is.na(score_eff), Date]))
say("sig_dates: %d (%s ~ %s)", length(sig_dates),
    as.character(min(sig_dates)), as.character(max(sig_dates)))
raw_dates <- sort(unique(raw$Date))

n_iter <- length(sig_dates) - 1L
cache <- vector("list", n_iter)
for (i in seq_len(n_iter)) {
  sig_label <- sig_dates[i]
  next_sig_label <- sig_dates[i + 1L]
  idx_s <- findInterval(sig_label - 1, raw_dates) + 1L        # 첫 raw date >= sig_label
  if (idx_s > length(raw_dates)) next
  start_d <- raw_dates[idx_s]
  idx_e <- findInterval(next_sig_label - 1, raw_dates) + 1L
  end_d <- if (idx_e > length(raw_dates)) max(raw_dates) else raw_dates[idx_e]

  panel_t <- alpha_scores[Date == sig_label & !is.na(score_eff)]
  if (nrow(panel_t) == 0L) { cache[[i]] <- NULL; next }

  liq_window_start <- start_d - 30L
  liq_data <- raw[Date >= liq_window_start & Date < start_d,
                  .(AvgTradingAmt = mean(TradingAmt, na.rm = TRUE)), by = Ticker]
  liquid_tickers <- liq_data[AvgTradingAmt >= LIQ_THRESHOLD, Ticker]

  period_data <- raw[Date > start_d & Date <= end_d, .(Date, Ticker, Ret)]
  stock_rets <- if (nrow(period_data) > 0L)
    period_data[, .(stock_ret = prod(1 + Ret, na.rm = TRUE) - 1), by = Ticker] else NULL

  # size tier용: start_d 직전 Size
  size_d <- raw[Date < start_d & Date >= start_d - 15L & Ticker %in% panel_t$Ticker,
                .SD[which.max(Date)], by = Ticker, .SDcols = "Size"]

  cache[[i]] <- list(sig_label = sig_label, start_d = start_d, end_d = end_d,
                     panel_t = panel_t, liquid = liquid_tickers,
                     stock_rets = stock_rets, size_d = size_d)
}
say("월별 캐시 구축: %d/%d", sum(!sapply(cache, is.null)), n_iter)

# ── 3. 배제 집합 구성 (사전등록 규칙 — Iter31 후보 프레임 횡단면 분위) ───────
build_excl_map <- function(X, lag1 = FALSE) {
  ymcol <- if (lag1) "sig_ym_lag1" else "sig_ym"
  out <- new.env(parent = emptyenv())
  for (i in seq_len(n_iter)) {
    cc <- cache[[i]]; if (is.null(cc)) next
    ym_i <- format(cc$sig_label, "%Y-%m")
    m5 <- MAX5[get(ymcol) == ym_i, .(Ticker, max5)]
    if (nrow(m5) == 0L) next
    cand <- merge(cc$panel_t[, .(Ticker)], m5, by = "Ticker", all.x = TRUE)
    v <- cand$max5[is.finite(cand$max5)]
    if (length(v) < 30L) next
    thr <- quantile(v, 1 - X, type = 7, names = FALSE)
    excl <- cand[is.finite(max5) & max5 >= thr, Ticker]
    if (length(excl)) assign(as.character(cc$sig_label), excl, envir = out)
  }
  out
}
excl_x10 <- build_excl_map(0.10)
excl_x05 <- build_excl_map(0.05)
excl_x20 <- build_excl_map(0.20)
excl_x10_lag1 <- build_excl_map(0.10, lag1 = TRUE)
say("배제 맵: X10 %d개월 / X5 %d / X20 %d / X10lag1 %d",
    length(ls(excl_x10)), length(ls(excl_x05)), length(ls(excl_x20)), length(ls(excl_x10_lag1)))

# ── 4. 종목계층 walk-forward (§5 VERBATIM 의미 보존 + 배제 주입점 1곳) ───────
run_stock_layer <- function(excl_map = NULL, regime_off = FALSE, ew = FALSE) {
  monthly_results <- vector("list", n_iter)
  wlist <- vector("list", n_iter)
  w_prev_risk_named <- NULL
  for (i in seq_len(n_iter)) {
    cc <- cache[[i]]; if (is.null(cc)) next
    panel_t <- copy(cc$panel_t)
    regime_i <- panel_t$regime_state[1L]
    cash_i <- 0.0

    filter_fired <- FALSE
    if (!is.null(excl_map)) {
      apply_here <- !(regime_off && regime_i %in% c("CRISIS", "CAUTION"))
      if (apply_here) {
        key <- as.character(cc$sig_label)
        if (exists(key, envir = excl_map, inherits = FALSE)) {
          excl <- get(key, envir = excl_map)
          n0 <- nrow(panel_t)
          panel_t <- panel_t[!Ticker %in% excl]
          filter_fired <- nrow(panel_t) < n0
        }
      }
    }

    setorder(panel_t, -score_eff)
    N_eligible <- nrow(panel_t)
    N_target <- min(MAX_NAMES, N_eligible)
    if (N_target < MIN_NAMES && N_eligible >= MIN_NAMES) N_target <- MIN_NAMES
    if (N_target < 5L) next

    picks <- panel_t[seq_len(N_target)]
    tickers_t <- picks$Ticker
    alpha_t <- picks$score_eff
    names(alpha_t) <- tickers_t

    tickers_liq <- intersect(tickers_t, cc$liquid)
    if (length(tickers_liq) < 5L) tickers_liq <- tickers_t
    alpha_t_liq <- alpha_t[tickers_liq]
    if (is.null(names(alpha_t_liq)) || length(alpha_t_liq) < 5L) next

    ub_use <- if (regime_i == "CRISIS") min(UB_WEIGHT, 0.10) else UB_WEIGHT

    if (ew) {
      w_risk_raw <- setNames(rep(1 / length(alpha_t_liq), length(alpha_t_liq)),
                             names(alpha_t_liq))
    } else {
      w_risk_raw <- tryCatch(
        linear_tilt_to_penalty_qd(alpha_t_liq, lambda = LAMBDA,
                                   w_prev = w_prev_risk_named, phi = TOPHI,
                                   lb = 0, ub = ub_use),
        error = function(e) linear_tilt_qd(alpha_t_liq, lambda = LAMBDA, lb = 0, ub = ub_use))
      names(w_risk_raw) <- names(alpha_t_liq)
      w_risk_raw <- normalize_long_only(w_risk_raw, lb = 0, ub = ub_use, target_sum = 1)
    }
    w_risk <- w_risk_raw * (1 - cash_i)

    if (is.null(cc$stock_rets) || nrow(cc$stock_rets) == 0L) {
      monthly_results[[i]] <- data.table(
        period_start = cc$start_d, period_end = cc$end_d,
        port_ret = NA_real_, port_ret_gross = NA_real_,
        n_held = 0L, turnover = 0, regime = regime_i, filter_fired = filter_fired)
      next
    }
    merged_ret <- merge(
      data.table(ticker = names(w_risk), weight_risk = as.numeric(w_risk)),
      cc$stock_rets, by.x = "ticker", by.y = "Ticker", all.x = TRUE)
    merged_ret[is.na(stock_ret), stock_ret := 0]
    port_ret_gross <- sum(merged_ret$weight_risk * merged_ret$stock_ret, na.rm = TRUE)

    if (is.null(w_prev_risk_named) || length(w_prev_risk_named) == 0L) {
      turnover_est <- 1.0
    } else {
      all_names <- union(names(w_risk), names(w_prev_risk_named))
      w_now_a  <- setNames(rep(0, length(all_names)), all_names)
      w_prev_a <- setNames(rep(0, length(all_names)), all_names)
      w_now_a[names(w_risk)] <- w_risk
      w_prev_a[names(w_prev_risk_named)] <- w_prev_risk_named
      turnover_est <- sum(abs(w_now_a - w_prev_a)) / 2
    }
    cost <- (COMMISSION_BPS / 1e4) * turnover_est * 2
    port_ret_net <- port_ret_gross - cost

    monthly_results[[i]] <- data.table(
      period_start = cc$start_d, period_end = cc$end_d,
      port_ret = port_ret_net, port_ret_gross = port_ret_gross,
      n_held = nrow(merged_ret), turnover = turnover_est,
      regime = regime_i, filter_fired = filter_fired)
    wlist[[i]] <- data.table(sig_label = cc$sig_label, period_end = cc$end_d,
                             Ticker = names(w_risk), w = as.numeric(w_risk))
    w_prev_risk_named <- setNames(as.numeric(w_risk), names(w_risk))
  }
  bt <- rbindlist(monthly_results, use.names = TRUE, fill = TRUE)
  bt <- bt[!is.na(port_ret)]
  setorder(bt, period_end)
  list(bt = bt, weights = rbindlist(wlist[!sapply(wlist, is.null)]))
}

say("── 종목계층 실행 (base + 7 arms) ──")
t0 <- Sys.time()
arm_base   <- run_stock_layer(NULL)
say("base 완료 (%.1fs, n=%d)", as.numeric(Sys.time() - t0, "secs"), nrow(arm_base$bt))

# ── 5. PARITY GATE A — production 03_period_returns.csv 정확 재현 (§7b) ──────
pp <- merge(arm_base$bt[, .(date = period_end, ret_net_mine = port_ret,
                            to_mine = turnover)],
            prod_pr[, .(date, ret_net, turnover)], by = "date", all = TRUE)
gateA_n  <- nrow(arm_base$bt) == nrow(prod_pr)
gateA_dv <- pp[, max(abs(ret_net_mine - ret_net), na.rm = TRUE)]
gateA_dt <- pp[, max(abs(to_mine - turnover), na.rm = TRUE)]
say("GATE A: n %d vs %d | max|Δret| %.2e | max|ΔTO| %.2e",
    nrow(arm_base$bt), nrow(prod_pr), gateA_dv, gateA_dt)
gateA_pass <- gateA_n && is.finite(gateA_dv) && gateA_dv <= 1e-8
if (!gateA_pass) {
  bad <- pp[abs(ret_net_mine - ret_net) > 1e-8 | is.na(ret_net_mine) | is.na(ret_net)]
  say("GATE A FAIL — 불일치 %d개월. STOP (사전등록).", nrow(bad))
  print(head(bad, 12))
  saveRDS(list(gateA = pp, vintage = vintage), file.path(OUT, "wt022_gateA_fail.rds"))
  stop("[wt022] PARITY GATE A FAIL — production 재현 불일치. 배선 진단 필요.")
}
say("GATE A PASS — production_parity_verified (stock layer, 20260802_LIVE 대조)")

arm_f10    <- run_stock_layer(excl_x10)
arm_f10_ro <- run_stock_layer(excl_x10, regime_off = TRUE)
arm_f05    <- run_stock_layer(excl_x05)
arm_f20    <- run_stock_layer(excl_x20)
arm_f10_l1 <- run_stock_layer(excl_x10_lag1)
arm_ew_b   <- run_stock_layer(NULL, ew = TRUE)
arm_ew_f10 <- run_stock_layer(excl_x10, ew = TRUE)
say("전체 arm 완료 (%.1fs)", as.numeric(Sys.time() - t0, "secs"))

# ── 6. β_R05_V5 재산출 (run_layer5 §3~5 VERBATIM + 배제 주입) ────────────────
expanding_quantile <- function(x, dates, q = 0.2) {
  out <- rep(NA_real_, length(x))
  for (i in seq_along(x)) {
    past <- x[dates < dates[i]]
    past <- past[!is.na(past)]
    if (length(past) >= 12) out[i] <- as.numeric(quantile(past, q, na.rm = TRUE))
  }
  out
}
build_beta <- function(excl_map = NULL, regime_off = FALSE) {
  m <- merge(alpha_scores[, .(Date, Ticker, score_eff, regime_state)],
             r05_dt[, .(Date, Ticker, R05_Tail_Risk_Z)],
             by = c("Date", "Ticker"), all.x = TRUE)
  m_valid <- m[!is.na(score_eff)]
  if (!is.null(excl_map)) {
    drop_list <- list()
    for (key in ls(excl_map)) {
      d <- as.Date(key)
      reg_d <- m_valid[Date == d, regime_state[1]]
      if (regime_off && !is.na(reg_d) && reg_d %in% c("CRISIS", "CAUTION")) next
      drop_list[[key]] <- data.table(Date = d, Ticker = get(key, envir = excl_map))
    }
    if (length(drop_list)) {
      DR <- rbindlist(drop_list); DR[, drop := TRUE]
      m_valid <- merge(m_valid, DR, by = c("Date", "Ticker"), all.x = TRUE)
      m_valid <- m_valid[is.na(drop)][, drop := NULL]
    }
  }
  setorder(m_valid, Date, -score_eff)
  top20 <- m_valid[, head(.SD, 20), by = Date]
  p_r05 <- top20[, .(R05_z_avg = mean(R05_Tail_Risk_Z, na.rm = TRUE),
                     n_R05_valid = sum(!is.na(R05_Tail_Risk_Z)),
                     regime = regime_state[1]), by = Date]
  setorder(p_r05, Date)
  p_r05[n_R05_valid == 0L, R05_z_avg := NA_real_]
  p_r05[, realized_ym := format(Date %m+% months(1), "%Y-%m")]
  p_r05[, R05_q20_past := expanding_quantile(R05_z_avg, Date, q = 0.20)]
  p_r05[, beta_R05_V5 := fcase(
    is.na(R05_q20_past) | is.na(R05_z_avg), 1.0,
    regime == "CRISIS"  & R05_z_avg < R05_q20_past, 0.3,
    regime == "CRISIS", 0.5,
    regime == "CAUTION" & R05_z_avg < R05_q20_past, 0.5,
    regime == "CAUTION", 0.7,
    regime %in% c("BULL", "NORMAL") & R05_z_avg < R05_q20_past, 0.85,
    default = 1.0)]
  p_r05[, .(realized_ym, R05_z_avg, R05_q20_past, beta_R05_V5, regime_sig = regime)]
}
beta_base   <- build_beta(NULL)
beta_f10    <- build_beta(excl_x10)
beta_f10_ro <- build_beta(excl_x10, regime_off = TRUE)
beta_f05    <- build_beta(excl_x05)
beta_f20    <- build_beta(excl_x20)
beta_f10_l1 <- build_beta(excl_x10_lag1)

# ── 7. noLayer4 overlay recon (recompute_bt_noLayer4_clean.R 공식 VERBATIM) ──
build_recon <- function(arm, beta_dt) {
  p <- arm$bt[, .(anchor_date = period_end, realized_ym = format(period_end, "%Y-%m"),
                  ret_orig = port_ret, turnover_stock = turnover, regime,
                  filter_fired)]
  p <- merge(p, m4_raw[, .(realized_ym = ym, m4_weight_lag = weight_str1715_lag)],
             by = "realized_ym", all.x = TRUE)
  p[is.na(m4_weight_lag), m4_weight_lag := 1.0]
  p <- merge(p, beta_dt, by = "realized_ym", all.x = TRUE)
  p[is.na(beta_R05_V5), beta_R05_V5 := 1.0]
  setorder(p, anchor_date)
  p[, db_R05 := abs(beta_R05_V5 - shift(beta_R05_V5, 1, fill = 1.0))]
  p[is.na(db_R05), db_R05 := 0]
  p[, ret_noL4 := beta_R05_V5 * m4_weight_lag * ret_orig - db_R05 * 0.0015]
  p
}
rec_base   <- build_recon(arm_base,   beta_base)
rec_f10    <- build_recon(arm_f10,    beta_f10)
rec_f10_ro <- build_recon(arm_f10_ro, beta_f10_ro)
rec_f05    <- build_recon(arm_f05,    beta_f05)
rec_f20    <- build_recon(arm_f20,    beta_f20)
rec_f10_l1 <- build_recon(arm_f10_l1, beta_f10_l1)
rec_ew_b   <- build_recon(arm_ew_b,   beta_base)
rec_ew_f10 <- build_recon(arm_ew_f10, beta_f10)
# same-β 진단: 필터판 종목계층 × base β·m4 스케줄
rec_f10_sameb <- copy(rec_base)[, .(realized_ym, anchor_date, m4_weight_lag,
                                    beta_R05_V5, db_R05)]
rec_f10_sameb <- merge(rec_f10_sameb,
                       arm_f10$bt[, .(anchor_date = period_end, ret_orig_f = port_ret)],
                       by = "anchor_date")
rec_f10_sameb[, ret_noL4 := beta_R05_V5 * m4_weight_lag * ret_orig_f - db_R05 * 0.0015]

# ── 8. PARITY GATE B — overlay recon vs 저장 기록 (2-1 β/m4, 2-3 ret) ────────
gb <- merge(rec_base[, .(anchor_date, beta_mine = beta_R05_V5, m4_mine = m4_weight_lag,
                         ret_noL4_mine = ret_noL4)],
            l5_21[, .(anchor_date, beta_R05_V5, m4_weight_lag)],
            by = "anchor_date")
gb <- merge(gb, pr_23[, .(anchor_date = date, ret_net_23 = ret_net)],
            by = "anchor_date", all.x = TRUE)
mism_beta <- gb[abs(beta_mine - beta_R05_V5) > 1e-9]
mism_m4   <- gb[abs(m4_mine - m4_weight_lag) > 1e-9]
cor_ret23 <- gb[is.finite(ret_net_23), cor(ret_noL4_mine, ret_net_23)]
maxd_ret23 <- gb[is.finite(ret_net_23), max(abs(ret_noL4_mine - ret_net_23))]
say("GATE B: β 불일치 %d/%d (%.1f%%) | m4 불일치 %d | vs 2-3 ret cor %.6f max|Δ| %.2e",
    nrow(mism_beta), nrow(gb), 100 * nrow(mism_beta) / nrow(gb),
    nrow(mism_m4), cor_ret23, maxd_ret23)
gateB_pass <- (nrow(mism_beta) / nrow(gb) <= 0.02) && (cor_ret23 >= 0.999)
if (!gateB_pass) {
  say("GATE B 경계 초과 — STOP-진단 (사전등록). 불일치 월:")
  print(head(mism_beta, 12))
  saveRDS(list(gb = gb, mism_beta = mism_beta, mism_m4 = mism_m4),
          file.path(OUT, "wt022_gateB_diag.rds"))
  stop("[wt022] PARITY GATE B 경계 초과 — 진단 후 재개.")
}
say("GATE B PASS")

# ── 9. 벤치마크 recon (recompute VERBATIM: anchor 윈도우 복리) + GATE D ──────
bm_x <- xts(bm$BM_Ret, order.by = bm$Date)
anchors <- rec_base$anchor_date
bmw <- rep(NA_real_, length(anchors))
for (i in 2:length(anchors)) {
  seg <- bm_x[index(bm_x) > anchors[i - 1] & index(bm_x) <= anchors[i]]
  if (nrow(seg) > 0) bmw[i] <- as.numeric(Return.cumulative(seg))
}
bmw[1] <- 0
BMW <- data.table(anchor_date = anchors, bmw = bmw)
BMW[, return_ym := format(as.Date(format(anchor_date, "%Y-%m-01")) %m-% months(1), "%Y-%m")]
jul_chk <- bm[Date >= as.Date("2026-07-01") & Date <= as.Date("2026-07-31"),
              prod(1 + BM_Ret) - 1]
say("GATE D: 2026-07 벤치월 %.4f (target −0.2363)", jul_chk)
if (abs(jul_chk - (-0.2363)) > 0.001) stop("[wt022] GATE D FAIL — 벤치 정합 실패")

# ── 10. PIT 가드 (C5/C10) + 위반 주입 ────────────────────────────────────────
fired_sigs <- as.Date(ls(excl_x10))
d0_by_sig <- MAX5[, .(d0 = d0[1]), by = sig_ym]
pit_tab <- data.table(sig_label = fired_sigs, sig_ym = format(fired_sigs, "%Y-%m"))
pit_tab <- merge(pit_tab, d0_by_sig, by = "sig_ym")
start_map <- rbindlist(lapply(cache[!sapply(cache, is.null)],
             function(cc) data.table(sig_label = cc$sig_label, start_d = cc$start_d)))
pit_tab <- merge(pit_tab, start_map, by = "sig_label")
assert_overlay_pit(pit_tab$d0, pit_tab$start_d, label = "wt022_max5_filter")
say("assert_overlay_pit PASS — %d/%d 발동월 (컷오프 d0 < 첫 매수일)", nrow(pit_tab), nrow(pit_tab))
inj_fired <- tryCatch({
  assert_overlay_pit(pit_tab$start_d + 27L, pit_tab$start_d, label = "violation_injection")
  FALSE
}, error = function(e) TRUE)
if (!inj_fired) stop("[wt022] GATE C FAIL — PIT 가드 위반 주입 미발화 (가드 사망)")
say("GATE C PASS — 위반 주입 시 stop() 발화 확인 (가드 생존)")

# ── 11. PRIMARY — paired NW lag-3 + ΔIR (net_active_recon_v1) ────────────────
paired_ym <- sort(unique(format(as.Date(paste0(format(fired_sigs, "%Y-%m"), "-01")), "%Y-%m")))
mk_active <- function(rec) {
  x <- merge(rec, BMW[, .(anchor_date, bmw)], by = "anchor_date")
  x[, active := ret_noL4 - bmw]
  x[, hold_ym := format(as.Date(format(anchor_date, "%Y-%m-01")) %m-% months(1), "%Y-%m")]
  x
}
ab <- mk_active(rec_base); af <- mk_active(rec_f10)
PD <- merge(ab[, .(anchor_date, hold_ym, regime, a_b = active, r_b = ret_noL4)],
            af[, .(anchor_date, a_f = active, r_f = ret_noL4)], by = "anchor_date")
# paired 공통월 = max5 가용 홀딩월 (발동 맵 기준 sig 월 = 홀딩월)
PDp <- PD[hold_ym %in% paired_ym & is.finite(a_b) & is.finite(a_f)]
PDp[, d_active := a_f - a_b]
ir_v <- function(a) mean(a) / sd(a) * sqrt(12)
ir_b <- PDp[, ir_v(a_b)]; ir_f <- PDp[, ir_v(a_f)]
delta_ir <- ir_f - ir_b
paired_t <- nw_t(PDp$d_active)
port_t_b <- nw_t(PDp$a_b); port_t_f <- nw_t(PDp$a_f)
say("★ PRIMARY (실코드 full-path, n=%d): ΔIR=%+.4f (IR %.4f→%.4f) | paired NW t=%+.3f | Δ평균 %+.5f/월",
    nrow(PDp), delta_ir, ir_b, ir_f, paired_t, PDp[, mean(d_active)])
say("  PORT_t(NW lag3, active): base %+.3f → filt %+.3f", port_t_b, port_t_f)

abs_stats <- function(r, dts, lab) {
  x <- xts(r, order.by = dts)
  ann <- table.AnnualizedReturns(x, scale = 12, Rf = 0)
  md <- maxDrawdown(x)
  list(label = lab, SR = round(as.numeric(ann[3, 1]), 4),
       CAGR = round(as.numeric(ann[1, 1]), 4), MDD = round(-as.numeric(md), 4))
}
st_b <- PDp[, abs_stats(r_b, anchor_date, "base_recon")]
st_f <- PDp[, abs_stats(r_f, anchor_date, "filt_recon")]
say("  절대(공통월): base SR %.3f CAGR %.1f%% MDD %.1f%% | filt SR %.3f CAGR %.1f%% MDD %.1f%%",
    st_b$SR, 100 * st_b$CAGR, 100 * st_b$MDD, st_f$SR, 100 * st_f$CAGR, 100 * st_f$MDD)

verdict <- if (delta_ir >= 0.05 && paired_t > 0) "UPHOLD (실배치 상신 유지)" else
           if (delta_ir < 0) "WITHDRAW (상신 철회)" else "HOLD (보류 — gray zone)"
say("★ 사전등록 판정: %s", verdict)

# ── 12. 진단 배터리 (사전등록 — 선택 사용 금지) ─────────────────────────────
diag_pair <- function(rec_arm, lab, base_active = NULL) {
  aa <- mk_active(rec_arm)
  D <- merge(ab[, .(anchor_date, hold_ym, a_b = active)],
             aa[, .(anchor_date, a_x = active)], by = "anchor_date")
  D <- D[hold_ym %in% paired_ym & is.finite(a_b) & is.finite(a_x)]
  list(label = lab, n = nrow(D),
       delta_ir = round(D[, ir_v(a_x)] - D[, ir_v(a_b)], 4),
       paired_t = round(nw_t(D[, a_x - a_b]), 3),
       mean_d = round(D[, mean(a_x - a_b)], 6))
}
d_ro   <- diag_pair(rec_f10_ro, "d1_regime_off_CRISIS_CAUTION")
d_x05  <- diag_pair(rec_f05, "d2_X5")
d_x20  <- diag_pair(rec_f20, "d2_X20")
d_sb   <- diag_pair(rec_f10_sameb, "d3_same_beta")
d_l1   <- diag_pair(rec_f10_l1, "d7_lag1_stress")
# EW dual-basis
ab_ew <- mk_active(rec_ew_b); af_ew <- mk_active(rec_ew_f10)
Dew <- merge(ab_ew[, .(anchor_date, hold_ym, a_b = active)],
             af_ew[, .(anchor_date, a_f = active)], by = "anchor_date")
Dew <- Dew[hold_ym %in% paired_ym & is.finite(a_b) & is.finite(a_f)]
d_ew <- list(label = "d4_ew_dual_basis", n = nrow(Dew),
             delta_ir = round(Dew[, ir_v(a_f)] - Dew[, ir_v(a_b)], 4),
             paired_t = round(nw_t(Dew[, a_f - a_b]), 3))
# 종목계층 bare paired (overlay 없음)
Db <- merge(arm_base$bt[, .(anchor_date = period_end, rb = port_ret)],
            arm_f10$bt[, .(anchor_date = period_end, rf = port_ret)], by = "anchor_date")
Db <- merge(Db, BMW[, .(anchor_date, bmw)], by = "anchor_date")
Db[, hold_ym := format(as.Date(format(anchor_date, "%Y-%m-01")) %m-% months(1), "%Y-%m")]
Db <- Db[hold_ym %in% paired_ym & is.finite(bmw)]
d_bare <- list(label = "d6_stock_layer_bare", n = nrow(Db),
               delta_ir = round(Db[, ir_v(rf - bmw)] - Db[, ir_v(rb - bmw)], 4),
               paired_t = round(nw_t(Db[, rf - rb]), 3),
               port_t_base = round(nw_t(Db[, rb - bmw]), 3),
               port_t_filt = round(nw_t(Db[, rf - bmw]), 3))
for (d in list(d_ro, d_x05, d_x20, d_sb, d_l1, d_ew, d_bare))
  say("  [%s] n=%d ΔIR=%+.4f t=%+.3f", d$label, d$n, d$delta_ir, d$paired_t)

# 국면 분해 (production regime + unified Category)
PDp2 <- merge(PDp, ureg[, .(hold_ym, Category)], by = "hold_ym", all.x = TRUE)
reg_prod <- PDp2[, .(n = .N, mean_d = round(mean(d_active), 5),
                     t = round(nw_t(d_active), 2)), by = regime]
reg_uni  <- PDp2[!is.na(Category), .(n = .N, mean_d = round(mean(d_active), 5),
                     t = round(nw_t(d_active), 2)), by = Category]
say("국면 분해 (production regime):"); print(reg_prod)
say("국면 분해 (unified Category):"); print(reg_uni)
ax001 <- PDp2[regime == "CRISIS",
              .(n = .N, mean_d = mean(d_active), t = nw_t(d_active))]

# cap-tier 분해 (종목계층 gross Δ기여, size 순위 tier)
tier_rows <- list()
for (i in seq_len(n_iter)) {
  cc <- cache[[i]]; if (is.null(cc)) next
  ym_i <- format(cc$sig_label, "%Y-%m")
  if (!ym_i %in% paired_ym) next
  wb <- arm_base$weights[sig_label == cc$sig_label]
  wf <- arm_f10$weights[sig_label == cc$sig_label]
  if (nrow(wb) == 0L || nrow(wf) == 0L) next
  ww <- merge(wb[, .(Ticker, w_b = w)], wf[, .(Ticker, w_f = w)],
              by = "Ticker", all = TRUE)
  ww[is.na(w_b), w_b := 0]; ww[is.na(w_f), w_f := 0]
  ww <- merge(ww, cc$stock_rets, by = "Ticker", all.x = TRUE)
  ww[is.na(stock_ret), stock_ret := 0]
  sz <- cc$size_d[order(-Size)]
  sz[, tier := c(rep("MEGA", min(10, .N)),
                 rep("MID", max(0, min(20, .N - 10))),
                 rep("OTHER", max(0, .N - 30)))]
  ww <- merge(ww, sz[, .(Ticker, tier)], by = "Ticker", all.x = TRUE)
  ww[is.na(tier), tier := "OTHER"]
  tier_rows[[length(tier_rows) + 1]] <-
    ww[, .(contrib = sum((w_f - w_b) * stock_ret)), by = tier][, ym := ym_i]
}
tier_dt <- rbindlist(tier_rows)
tier_sum <- tier_dt[, .(contrib_ann = round(12 * mean(contrib), 5)), by = tier]
say("cap-tier Δ기여(종목계층 gross, 연환산):"); print(tier_sum)

# 회전·발동
to_tab <- data.table(
  arm = c("base", "filt_X10"),
  to_annual = c(arm_base$bt[period_end %in% PDp$anchor_date, mean(turnover) * 12],
                arm_f10$bt[period_end %in% PDp$anchor_date, mean(turnover) * 12]),
  beta_to_annual = c(rec_base[anchor_date %in% PDp$anchor_date, sum(db_R05) * 12 / .N],
                     rec_f10[anchor_date %in% PDp$anchor_date, sum(db_R05) * 12 / .N]))
say("회전 실측:"); print(to_tab)
fire_tab <- arm_f10$bt[period_end %in% PDp$anchor_date,
                       .(fired_months = sum(filter_fired), n = .N)]
# 픽 변화율
pk <- merge(arm_base$weights[, .(sig_label, Ticker)][, .(set_b = list(sort(Ticker))), by = sig_label],
            arm_f10$weights[, .(sig_label, Ticker)][, .(set_f = list(sort(Ticker))), by = sig_label],
            by = "sig_label")
pk[, n_diff := mapply(function(a, b) length(setdiff(a, b)), set_b, set_f)]
pk_p <- pk[format(sig_label, "%Y-%m") %in% paired_ym]
say("발동: 필터발동 %d/%d월 | 구성변화월 %.1f%% | 월평균 교체 %.2f종",
    fire_tab$fired_months, fire_tab$n,
    100 * pk_p[, mean(n_diff > 0)], pk_p[, mean(n_diff)])

# β 경로 변화 (full-path의 2차 경로)
bcmp <- merge(rec_base[, .(anchor_date, b_base = beta_R05_V5)],
              rec_f10[, .(anchor_date, b_f = beta_R05_V5)], by = "anchor_date")
n_bdiff <- bcmp[abs(b_base - b_f) > 1e-9, .N]
say("β 경로: 필터로 β_R05가 달라진 월 = %d/%d", n_bdiff, nrow(bcmp))

# ── 13. 저장 ─────────────────────────────────────────────────────────────────
res <- list(
  vintage = vintage,
  gates = list(A = list(pass = gateA_pass, max_dret = gateA_dv, n = nrow(prod_pr)),
               B = list(pass = gateB_pass, beta_mismatch = nrow(mism_beta),
                        n = nrow(gb), cor_vs_23 = cor_ret23, maxd = maxd_ret23),
               C = list(pass = inj_fired), D = list(jul_bm = jul_chk)),
  primary = list(n = nrow(PDp), delta_ir = delta_ir, ir_base = ir_b, ir_filt = ir_f,
                 paired_t = paired_t, port_t_base = port_t_b, port_t_filt = port_t_f,
                 mean_d_monthly = PDp[, mean(d_active)],
                 abs_base = st_b, abs_filt = st_f, verdict = verdict),
  diagnostics = list(regime_off = d_ro, x05 = d_x05, x20 = d_x20, same_beta = d_sb,
                     lag1 = d_l1, ew = d_ew, bare = d_bare,
                     regime_prod = reg_prod, regime_unified = reg_uni,
                     ax001_crisis = ax001, tier = tier_sum, turnover = to_tab,
                     firing = list(fired = fire_tab$fired_months, n = fire_tab$n,
                                   pct_changed = 100 * pk_p[, mean(n_diff > 0)],
                                   mean_swap = pk_p[, mean(n_diff)]),
                     beta_path_diff_months = n_bdiff),
  series = list(PD = PDp2, rec_base = rec_base, rec_f10 = rec_f10, BMW = BMW,
                bare = Db, weights_base = arm_base$weights, weights_f10 = arm_f10$weights)
)
saveRDS(res, file.path(OUT, "wt022_eval_results.rds"))
say("저장: wt022_eval_results.rds")
say("DONE")
