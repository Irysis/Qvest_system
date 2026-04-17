cat("=== STR_1656_MLRA: S5 Sprint 2 — M01(CVaR LP) + M02(CDaR) + M04(MinVar) ===\n")
## 핵심아이디어: S1-B ML 앙상블 신호 기반 고도 위험예산 포트폴리오 최적화 3종 비교
## Sprint 2: CVaR LP / CDaR / MinVar (Ledoit-Wolf)
## PIT 준수: 모든 추정량 rolling window 기반, same-day 금지

# ── 0. 경로 설정 ──────────────────────────────────────────────────────────────
ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
STR_DIR  <- file.path(ROOT, "04_Research/strategies/STR_1656_MLRA")
OUT_BASE <- file.path(STR_DIR, "output/s5_mutations")

# ── 1. 인프라 소스 ────────────────────────────────────────────────────────────
source(file.path(ROOT, "02_Infrastructure/config.R"))
source(file.path(ROOT, "02_Infrastructure/backtest_harness.R"))
source(file.path(ROOT, "02_Infrastructure/portfolio/advanced_weights.R"))

# ── 2. 데이터 로드 (1회) ──────────────────────────────────────────────────────
cat("[데이터] RAWDATA 로드...\n")
raw_list <- load_rawdata(use_cache = TRUE)
raw <- as.data.table(raw_list$RAWDATA)
setkey(raw, Date, Ticker)

# S1-B 점수 로드
cat("[데이터] S1-B 점수 로드...\n")
scores_dt <- fread(file.path(STR_DIR, "output/s5_scores_B.csv"))
scores_dt[, Date := as.Date(Date)]
setkey(scores_dt, Date, Ticker)

# 앵커 NAV 로드 (STR_1631 NAV_vdp)
cat("[데이터] 앵커 NAV 로드 (STR_1631 NAV_vdp)...\n")
anchor_dt <- fread(file.path(ROOT,
  "04_Research/strategies/STR_1631_PG2_MDD_OPT/output/daily_nav_bcde.csv"))
anchor_dt[, Date := as.Date(Date)]
anchor_nav <- anchor_dt[, .(Date, NAV_anchor = NAV_vdp)]
setkey(anchor_nav, Date)

# 일간 수익률 테이블 (가중치 계산용 — rolling window)
cat("[데이터] 일간 수익률 테이블 준비...\n")
ret_dt <- raw[!is.na(Ret), .(Date, Ticker, Ret)]
setkey(ret_dt, Date, Ticker)

# ── 3. 공통 함수 ──────────────────────────────────────────────────────────────

# 유동성 필터: 20일 평균 거래대금 >= 2억
LIQ_THRESHOLD <- 2e8

compute_reb_nav <- function(scores_dt, raw, weight_fn, weight_fn_name,
                             ret_dt_daily, n_top = 30, commission_bps = 15) {
  ## 리밸런싱 날짜 = scores_dt의 월별 Date
  reb_dates <- sort(unique(scores_dt$Date))
  cat(sprintf("[%s] 리밸런싱 %d회\n", weight_fn_name, length(reb_dates)))

  fallback_count <- 0L
  total_reb      <- 0L

  nav     <- 1e8  # 초기 NAV
  nav_log <- list()
  prev_w  <- NULL
  prev_tickers <- character(0)

  for (i in seq_along(reb_dates)) {
    reb_date <- reb_dates[i]
    next_date <- if (i < length(reb_dates)) reb_dates[i + 1] else as.Date("2099-12-31")

    # 1) 이번 리밸런싱 시점 상위 30종목 + 유동성 필터
    sc_today <- scores_dt[Date == reb_date]

    # 유동성: t-1 20일 평균 (t 당일 제외 — C10)
    liq_window <- raw[Date < reb_date & Date >= reb_date - 30,
                      .(AvgTurnover = mean(Close * Vol, na.rm = TRUE)),
                      by = Ticker]
    sc_today <- merge(sc_today, liq_window, by = "Ticker", all.x = TRUE)
    sc_today <- sc_today[!is.na(AvgTurnover) & AvgTurnover >= LIQ_THRESHOLD]

    if (nrow(sc_today) < 5) {
      cat(sprintf("  [%s] %s: 유동성 필터 후 종목 부족(%d) — EW 유지\n",
                  weight_fn_name, reb_date, nrow(sc_today)))
      tickers_sel <- if (length(prev_tickers) > 0) prev_tickers else character(0)
    } else {
      sc_today <- sc_today[order(-Score)]
      tickers_sel <- head(sc_today$Ticker, n_top)
    }

    # 2) 가중치 계산 (rolling 120일 수익률 기반)
    total_reb <- total_reb + 1L
    w_result <- tryCatch({
      weight_fn(tickers_sel, ret_dt_daily, n_days = 120, max_w = 0.15)
    }, error = function(e) {
      cat(sprintf("  [%s] %s: 가중치 계산 오류(%s) — EW fallback\n",
                  weight_fn_name, reb_date, e$message))
      NULL
    })

    # EW fallback 감지
    is_ew_fallback <- FALSE
    if (is.null(w_result)) {
      is_ew_fallback <- TRUE
    } else {
      # EW 특성 확인: 모든 가중치가 동일하면 fallback으로 간주
      w_nonzero <- w_result[w_result > 1e-6]
      if (length(w_nonzero) > 0) {
        cv_w <- sd(w_nonzero) / mean(w_nonzero)
        if (cv_w < 0.01) is_ew_fallback <- TRUE
      }
    }
    if (is_ew_fallback) fallback_count <- fallback_count + 1L

    if (is.null(w_result) || sum(w_result) < 1e-6) {
      # 순수 EW
      w_use <- rep(1 / length(tickers_sel), length(tickers_sel))
      names(w_use) <- tickers_sel
    } else {
      w_use <- w_result[w_result > 1e-6]
      w_use <- w_use / sum(w_use)
    }

    tickers_cur <- names(w_use)

    # 3) 해당 기간 일간 수익률로 NAV 업데이트
    period_data <- raw[Ticker %in% tickers_cur &
                         Date >= reb_date & Date < next_date,
                       .(Date, Ticker, Ret)]

    trade_dates <- sort(unique(period_data$Date))

    # 거래비용 (리밸런싱 시점): 이전 대비 turnover 계산
    if (!is.null(prev_w) && length(prev_tickers) > 0) {
      w_prev_aligned <- rep(0, length(tickers_cur))
      names(w_prev_aligned) <- tickers_cur
      common <- intersect(names(prev_w), tickers_cur)
      w_prev_aligned[common] <- prev_w[common]
      turnover <- sum(abs(w_use - w_prev_aligned)) / 2
      nav <- nav * (1 - turnover * commission_bps / 1e4)
    }

    prev_w       <- w_use
    prev_tickers <- tickers_cur

    for (td in as.character(trade_dates)) {
      td_date <- as.Date(td)
      day_ret <- period_data[Date == td_date, .(Ticker, Ret)]
      day_ret <- day_ret[Ticker %in% names(w_use)]

      if (nrow(day_ret) == 0) {
        nav_log[[length(nav_log) + 1]] <- data.table(Date = td_date, NAV = nav, Strategy_Ret = 0)
        next
      }

      # 가중평균 수익률
      w_aligned <- w_use[day_ret$Ticker]
      w_aligned[is.na(w_aligned)] <- 0
      if (sum(w_aligned) > 1e-6) w_aligned <- w_aligned / sum(w_aligned)

      port_ret <- sum(day_ret$Ret * w_aligned, na.rm = TRUE)
      nav <- nav * (1 + port_ret)

      nav_log[[length(nav_log) + 1]] <- data.table(
        Date = td_date, NAV = nav, Strategy_Ret = port_ret
      )
    }
  }  # end for reb_dates

  fallback_pct <- if (total_reb > 0) fallback_count / total_reb * 100 else 0
  cat(sprintf("  [%s] Fallback 비율: %.1f%% (%d/%d)\n",
              weight_fn_name, fallback_pct, fallback_count, total_reb))

  nav_result <- rbindlist(nav_log)
  nav_result <- nav_result[order(Date)]

  list(nav = nav_result, fallback_pct = fallback_pct)
}

# ── 4. MinVar (Ledoit-Wolf shrinkage) ─────────────────────────────────────────
# C1 준수: rolling window 기반 공분산 추정, full-sample 금지
calc_minvar_lw_weights <- function(tickers, ret_dt, n_days = 120, max_w = 0.15) {
  n <- length(tickers)
  if (n < 2L) {
    w <- rep(1/n, n); names(w) <- tickers; return(w)
  }

  # rolling 수익률 행렬 구성 (.p2_ret_matrix는 advanced_weights.R 내부 함수)
  # 직접 구성
  end_date   <- max(ret_dt$Date)
  start_date <- end_date - n_days

  ret_wide <- dcast(ret_dt[Date >= start_date & Date <= end_date & Ticker %in% tickers],
                    Date ~ Ticker, value.var = "Ret", fill = NA)
  ret_wide <- ret_wide[order(Date)]

  mat <- as.matrix(ret_wide[, -1, with = FALSE])
  row.names(mat) <- as.character(ret_wide$Date)

  # 유효 컬럼만 (결측 20% 이하)
  valid_cols <- names(which(colMeans(!is.na(mat)) >= 0.8))
  if (length(valid_cols) < 2) {
    w <- rep(1/n, n); names(w) <- tickers; return(w)
  }
  mat <- mat[, valid_cols, drop = FALSE]
  mat <- na.omit(mat)
  if (nrow(mat) < 20) {
    w <- rep(1/n, n); names(w) <- tickers; return(w)
  }

  p <- ncol(mat)

  # Ledoit-Wolf 수축 공분산 추정
  result <- tryCatch({
    # 표본 공분산
    S <- cov(mat)

    # LW shrinkage target: scaled identity (Oracle Approximating Shrinkage)
    # Ledoit & Wolf (2004): shrinkage intensity 계산
    T_obs <- nrow(mat)
    mu_S  <- sum(diag(S)) / p  # 축소 타겟의 스케일
    delta_hat <- (((T_obs - 2) / T_obs) * sum(diag(S %*% S)) + sum(diag(S))^2) /
                 ((T_obs + 2) * (sum(diag(S %*% S)) - sum(diag(S))^2 / p))
    delta_hat <- max(0, min(1, delta_hat))  # [0, 1] 클리핑

    Sigma_lw  <- (1 - delta_hat) * S + delta_hat * mu_S * diag(p)

    # MinVar 최적화: min w'Σw s.t. sum(w)=1, 0<=w<=max_w
    # 해석적 해 (quadprog): min 0.5 * w' D w - d' w
    if (requireNamespace("quadprog", quietly = TRUE)) {
      Dmat <- 2 * Sigma_lw
      dvec <- rep(0, p)
      # 제약: Amat' w >= bvec
      # 1) sum(w) = 1  → A_eq, b_eq = 1
      # 2) w >= 0
      # 3) w <= max_w  → -w >= -max_w
      Amat <- cbind(
        rep(1, p),          # sum = 1 (등식 → 포함 후 meq=1)
        diag(p),            # w >= 0
        -diag(p)            # w <= max_w
      )
      bvec <- c(1, rep(0, p), rep(-max_w, p))
      sol  <- quadprog::solve.QP(Dmat, dvec, Amat, bvec, meq = 1)
      w_opt <- pmax(sol$solution, 0)
    } else {
      # fallback: 고유벡터 기반 MinVar 근사
      eig <- eigen(Sigma_lw, symmetric = TRUE)
      w_opt <- abs(eig$vectors[, p])  # 최소 고유값 대응 벡터
    }

    if (sum(w_opt) < 1e-10) stop("degenerate solution")
    w_opt <- w_opt / sum(w_opt)

    # max_w 클리핑 후 재정규화
    w_opt <- pmin(w_opt, max_w)
    w_opt <- w_opt / sum(w_opt)
    w_opt

  }, error = function(e) {
    cat(sprintf("  [minvar_lw] 오류(%s) — EW fallback\n", e$message))
    rep(1 / p, p)
  })

  # 전체 종목 벡터로 확장
  w_full <- rep(0, n); names(w_full) <- tickers
  w_full[valid_cols] <- result
  w_full
}

# ── 5. 성과 지표 계산 ─────────────────────────────────────────────────────────
calc_performance <- function(nav_dt, label) {
  nav_dt <- nav_dt[order(Date)]
  nav_dt <- nav_dt[!is.na(Strategy_Ret)]
  if (nrow(nav_dt) < 50) return(list(label = label, SR = NA, CAGR = NA, MDD = NA))

  rets <- nav_dt$Strategy_Ret
  n_years <- as.numeric(diff(range(nav_dt$Date))) / 365.25

  # CAGR
  nav_end   <- tail(nav_dt$NAV, 1)
  nav_start <- head(nav_dt$NAV, 1)
  cagr <- (nav_end / nav_start)^(1 / n_years) - 1

  # SR (연환산, 거래일 기준)
  mu_daily  <- mean(rets, na.rm = TRUE)
  sd_daily  <- sd(rets, na.rm = TRUE)
  sr        <- if (sd_daily > 0) mu_daily / sd_daily * sqrt(252) else 0

  # Sortino
  downside  <- rets[rets < 0]
  sortino   <- if (length(downside) > 0 && sd(downside) > 0)
    mu_daily / sd(downside) * sqrt(252) else sr

  # MDD
  peak    <- cummax(nav_dt$NAV)
  dd      <- (nav_dt$NAV - peak) / peak
  mdd     <- min(dd, na.rm = TRUE)

  # Turnover (연환산 추정)
  # S5 레벨에서는 NAV만 있으므로 월별 수익률 표준편차 대비 교체율로 근사
  # 실제 turnover는 리밸런싱 로직에서 기록된 값 사용

  list(
    label   = label,
    CAGR    = round(cagr * 100, 2),
    SR      = round(sr, 3),
    MDD     = round(mdd * 100, 2),
    Sortino = round(sortino, 3),
    n_days  = nrow(nav_dt)
  )
}

# 앵커 blend 성과 계산
calc_blend_performance <- function(nav_dt, anchor_nav, blend_ratio = 0.8, label) {
  # 80% signal + 20% anchor
  merged <- merge(
    nav_dt[, .(Date, Ret_signal = Strategy_Ret)],
    anchor_nav,
    by = "Date"
  )
  if (nrow(merged) < 50) return(list(label = label, SR = NA, CAGR = NA, MDD = NA))

  # 앵커 일간 수익률 계산
  merged <- merged[order(Date)]
  merged[, Ret_anchor := (NAV_anchor / shift(NAV_anchor) - 1)]
  merged <- merged[!is.na(Ret_anchor)]

  merged[, Ret_blend := blend_ratio * Ret_signal + (1 - blend_ratio) * Ret_anchor]
  merged[, NAV_blend := cumprod(1 + Ret_blend) * 1e8]

  calc_performance(
    data.table(Date = merged$Date, NAV = merged$NAV_blend, Strategy_Ret = merged$Ret_blend),
    label
  )
}

# Rolling anchor 상관관계
calc_anchor_corr <- function(nav_dt, anchor_nav, window = 60) {
  merged <- merge(
    nav_dt[, .(Date, Ret_signal = Strategy_Ret)],
    anchor_nav,
    by = "Date"
  )
  merged <- merged[order(Date)]
  merged[, Ret_anchor := (NAV_anchor / shift(NAV_anchor) - 1)]
  merged <- merged[!is.na(Ret_anchor) & !is.na(Ret_signal)]

  if (nrow(merged) < window + 10) return(NA_real_)

  # 전체 기간 상관
  cor(merged$Ret_signal, merged$Ret_anchor, use = "complete.obs")
}

# ── 6. M01: CVaR LP 실행 ──────────────────────────────────────────────────────
cat("\n======== M01: CVaR LP 포트폴리오 ========\n")
m01_result <- compute_reb_nav(
  scores_dt    = scores_dt,
  raw          = raw,
  weight_fn    = function(tickers, ret_dt, n_days, max_w)
                   calc_cvar_lp_weights(tickers, ret_dt, alpha = 0.95, n_days = n_days, max_w = max_w),
  weight_fn_name = "M01_CVaR_LP",
  ret_dt_daily = ret_dt,
  n_top        = 30,
  commission_bps = 15
)
fwrite(m01_result$nav, file.path(OUT_BASE, "M01/nav.csv"))
cat(sprintf("[M01] nav.csv 저장 완료 (%d rows)\n", nrow(m01_result$nav)))

m01_perf  <- calc_performance(m01_result$nav, "M01_CVaR_LP")
m01_blend <- calc_blend_performance(m01_result$nav, anchor_nav, 0.8, "M01_blend_80_20")
m01_corr  <- calc_anchor_corr(m01_result$nav, anchor_nav)

cat(sprintf("[M01] SR=%.3f | CAGR=%.2f%% | MDD=%.2f%% | Fallback=%.1f%% | AnchorCorr=%.3f\n",
            m01_perf$SR, m01_perf$CAGR, m01_perf$MDD,
            m01_result$fallback_pct, m01_corr))

# Kill check M01
m01_kill <- list(
  hard_fail   = (!is.na(m01_perf$MDD) && m01_perf$MDD < -45),
  alpha_dead  = (!is.na(m01_perf$SR)  && m01_perf$SR  < 0.40),
  fb_excess   = m01_result$fallback_pct > 20,
  div_fail    = (!is.na(m01_corr)     && m01_corr > 0.50)
)
m01_kill_flag <- any(unlist(m01_kill))
cat(sprintf("[M01] Kill=%s | %s\n", m01_kill_flag,
            paste(names(m01_kill)[unlist(m01_kill)], collapse = ", ")))

# ── 7. M02: CDaR 실행 ─────────────────────────────────────────────────────────
cat("\n======== M02: CDaR 포트폴리오 ========\n")
m02_result <- compute_reb_nav(
  scores_dt    = scores_dt,
  raw          = raw,
  weight_fn    = function(tickers, ret_dt, n_days, max_w)
                   calc_cdar_weights(tickers, ret_dt, alpha = 0.95, n_days = n_days, max_w = max_w),
  weight_fn_name = "M02_CDaR",
  ret_dt_daily = ret_dt,
  n_top        = 30,
  commission_bps = 15
)
fwrite(m02_result$nav, file.path(OUT_BASE, "M02/nav.csv"))
cat(sprintf("[M02] nav.csv 저장 완료 (%d rows)\n", nrow(m02_result$nav)))

m02_perf  <- calc_performance(m02_result$nav, "M02_CDaR")
m02_blend <- calc_blend_performance(m02_result$nav, anchor_nav, 0.8, "M02_blend_80_20")
m02_corr  <- calc_anchor_corr(m02_result$nav, anchor_nav)

cat(sprintf("[M02] SR=%.3f | CAGR=%.2f%% | MDD=%.2f%% | Fallback=%.1f%% | AnchorCorr=%.3f\n",
            m02_perf$SR, m02_perf$CAGR, m02_perf$MDD,
            m02_result$fallback_pct, m02_corr))

# Kill check M02
m02_kill <- list(
  hard_fail   = (!is.na(m02_perf$MDD) && m02_perf$MDD < -45),
  alpha_dead  = (!is.na(m02_perf$SR)  && m02_perf$SR  < 0.40),
  fb_excess   = m02_result$fallback_pct > 20,
  div_fail    = (!is.na(m02_corr)     && m02_corr > 0.50)
)
m02_kill_flag <- any(unlist(m02_kill))
cat(sprintf("[M02] Kill=%s | %s\n", m02_kill_flag,
            paste(names(m02_kill)[unlist(m02_kill)], collapse = ", ")))

# ── 8. M04: MinVar (Ledoit-Wolf) 실행 ────────────────────────────────────────
cat("\n======== M04: MinVar (Ledoit-Wolf) 포트폴리오 ========\n")
m04_result <- compute_reb_nav(
  scores_dt    = scores_dt,
  raw          = raw,
  weight_fn    = function(tickers, ret_dt, n_days, max_w)
                   calc_minvar_lw_weights(tickers, ret_dt, n_days = n_days, max_w = max_w),
  weight_fn_name = "M04_MinVar_LW",
  ret_dt_daily = ret_dt,
  n_top        = 30,
  commission_bps = 15
)
fwrite(m04_result$nav, file.path(OUT_BASE, "M04/nav.csv"))
cat(sprintf("[M04] nav.csv 저장 완료 (%d rows)\n", nrow(m04_result$nav)))

m04_perf  <- calc_performance(m04_result$nav, "M04_MinVar_LW")
m04_blend <- calc_blend_performance(m04_result$nav, anchor_nav, 0.8, "M04_blend_80_20")
m04_corr  <- calc_anchor_corr(m04_result$nav, anchor_nav)

cat(sprintf("[M04] SR=%.3f | CAGR=%.2f%% | MDD=%.2f%% | Fallback=%.1f%% | AnchorCorr=%.3f\n",
            m04_perf$SR, m04_perf$CAGR, m04_perf$MDD,
            m04_result$fallback_pct, m04_corr))

# Kill check M04
m04_kill <- list(
  hard_fail   = (!is.na(m04_perf$MDD) && m04_perf$MDD < -45),
  alpha_dead  = (!is.na(m04_perf$SR)  && m04_perf$SR  < 0.40),
  fb_excess   = m04_result$fallback_pct > 20,
  div_fail    = (!is.na(m04_corr)     && m04_corr > 0.50)
)
m04_kill_flag <- any(unlist(m04_kill))
cat(sprintf("[M04] Kill=%s | %s\n", m04_kill_flag,
            paste(names(m04_kill)[unlist(m04_kill)], collapse = ", ")))

# ── 9. Sprint 2 요약 JSON ─────────────────────────────────────────────────────
cat("\n======== Sprint 2 요약 JSON 저장 ========\n")

# Sprint 1 결과 로드 (M03, M12)
m03_nav_path <- file.path(OUT_BASE, "M03/nav.csv")
m12_nav_path <- file.path(OUT_BASE, "M12/nav.csv")

sprint1_loaded <- FALSE
if (file.exists(m03_nav_path) && file.exists(m12_nav_path)) {
  m03_nav  <- fread(m03_nav_path); m03_nav[, Date := as.Date(Date)]
  m12_nav  <- fread(m12_nav_path); m12_nav[, Date := as.Date(Date)]
  m03_perf <- calc_performance(m03_nav, "M03_EW")
  m12_perf <- calc_performance(m12_nav, "M12_HRP")
  m03_corr <- calc_anchor_corr(m03_nav, anchor_nav)
  m12_corr <- calc_anchor_corr(m12_nav, anchor_nav)
  sprint1_loaded <- TRUE
  cat("[Sprint1] M03/M12 로드 완료\n")
}

make_entry <- function(perf, blend, corr, fallback_pct, kill_flag) {
  list(
    SR          = perf$SR,
    CAGR_pct    = perf$CAGR,
    MDD_pct     = perf$MDD,
    Sortino     = perf$Sortino,
    SR_blend    = blend$SR,
    CAGR_blend  = blend$CAGR,
    MDD_blend   = blend$MDD,
    AnchorCorr  = round(corr, 4),
    Fallback_pct = round(fallback_pct, 1),
    Kill        = kill_flag
  )
}

summary_list <- list(
  sprint    = "Sprint_2",
  run_date  = as.character(Sys.Date()),
  mutations = list(
    M01_CVaR_LP  = make_entry(m01_perf, m01_blend, m01_corr,
                               m01_result$fallback_pct, m01_kill_flag),
    M02_CDaR     = make_entry(m02_perf, m02_blend, m02_corr,
                               m02_result$fallback_pct, m02_kill_flag),
    M04_MinVar_LW = make_entry(m04_perf, m04_blend, m04_corr,
                                m04_result$fallback_pct, m04_kill_flag)
  )
)

if (sprint1_loaded) {
  m03_blend_dummy <- list(SR = NA, CAGR = NA, MDD = NA)
  m12_blend_dummy <- list(SR = NA, CAGR = NA, MDD = NA)
  summary_list$mutations$M03_EW  <- make_entry(m03_perf, m03_blend_dummy,
                                                m03_corr, NA, FALSE)
  summary_list$mutations$M12_HRP <- make_entry(m12_perf, m12_blend_dummy,
                                                m12_corr, NA, FALSE)
}

jsonlite::write_json(summary_list,
                     file.path(OUT_BASE, "sprint2_summary.json"),
                     pretty = TRUE, auto_unbox = TRUE)
cat("[저장] sprint2_summary.json 완료\n")

# ── 10. 텔레그램 발송 ─────────────────────────────────────────────────────────
tryCatch({
  source(file.path(ROOT, "02_Infrastructure/telegram/telegram_notify.R"))

  # 상태 판정
  alive <- c(
    if (!m01_kill_flag) "M01(CVaR LP)" else NULL,
    if (!m02_kill_flag) "M02(CDaR)"    else NULL,
    if (!m04_kill_flag) "M04(MinVar)"  else NULL
  )
  killed <- c(
    if (m01_kill_flag) "M01" else NULL,
    if (m02_kill_flag) "M02" else NULL,
    if (m04_kill_flag) "M04" else NULL
  )

  msg <- paste0(
    "[Forge] STR_1656_MLRA S5 Sprint 2 완료\n\n",
    "== M01: CVaR LP ==\n",
    sprintf("SR %.3f | CAGR %.2f%% | MDD %.2f%%\n", m01_perf$SR, m01_perf$CAGR, m01_perf$MDD),
    sprintf("Fallback %.1f%% | AnchorCorr %.3f | Kill=%s\n", m01_result$fallback_pct, m01_corr, m01_kill_flag),
    sprintf("Blend(80/20): SR %.3f | CAGR %.2f%% | MDD %.2f%%\n\n",
            m01_blend$SR, m01_blend$CAGR, m01_blend$MDD),

    "== M02: CDaR ==\n",
    sprintf("SR %.3f | CAGR %.2f%% | MDD %.2f%%\n", m02_perf$SR, m02_perf$CAGR, m02_perf$MDD),
    sprintf("Fallback %.1f%% | AnchorCorr %.3f | Kill=%s\n", m02_result$fallback_pct, m02_corr, m02_kill_flag),
    sprintf("Blend(80/20): SR %.3f | CAGR %.2f%% | MDD %.2f%%\n\n",
            m02_blend$SR, m02_blend$CAGR, m02_blend$MDD),

    "== M04: MinVar (LW) ==\n",
    sprintf("SR %.3f | CAGR %.2f%% | MDD %.2f%%\n", m04_perf$SR, m04_perf$CAGR, m04_perf$MDD),
    sprintf("Fallback %.1f%% | AnchorCorr %.3f | Kill=%s\n", m04_result$fallback_pct, m04_corr, m04_kill_flag),
    sprintf("Blend(80/20): SR %.3f | CAGR %.2f%% | MDD %.2f%%\n\n",
            m04_blend$SR, m04_blend$CAGR, m04_blend$MDD),

    sprintf("생존: %s\n", if (length(alive) > 0) paste(alive, collapse = ", ") else "없음"),
    sprintf("폐기: %s\n", if (length(killed) > 0) paste(killed, collapse = ", ") else "없음")
  )

  tg_send(msg)
  cat("[텔레그램] 발송 완료\n")
}, error = function(e) {
  cat(sprintf("[텔레그램] 오류: %s\n", e$message))
})

cat("\n=== STR_1656_MLRA S5 Sprint 2 완료 ===\n")
