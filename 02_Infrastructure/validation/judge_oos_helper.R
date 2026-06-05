#==============================================================================
# Judge OOS Helper — v6.1 Step 6 Part 4
# 2026-04-24
#
# 목적:
#   Judge agent는 lockbox 접근 유일 agent (v6.1 R2-B).
#   Forge가 생성한 equity_curve.png 는 train+validation (~2024-01-22) 구간만.
#   Judge는 lockbox 구간 (2024-01-23 ~ 2026-01-22) OOS 성과까지 포함한 차트를
#   생성해서 verdict에 첨부해야 한다.
#
# Public API:
#   judge_oos_backtest(wt_id, weights_path = NULL, benchmark = "KOSPI200_TR")
#     → list(oos_performance, oos_equity_dt, lockbox_dt, comparison_table,
#            full_equity_dt, windows)
#
#   judge_generate_oos_charts(wt_id, out_dir = NULL)
#     → list(full_chart_path, oos_chart_path, oos_summary_path, oos_performance)
#
# 생성 산출물:
#   <wt_dir>/backtest_result/equity_curve_full.png   (1990-01-04 ~ 2026-01-22)
#   <wt_dir>/backtest_result/equity_curve_oos.png    (2024-01-23 ~ 2026-01-22)
#   <wt_dir>/backtest_result/oos_summary.json
#
# 제약:
#   - Lockbox 접근 Judge만. log_lockbox_access() 호출 필수.
#   - 기존 Forge equity_curve.png 덮어쓰기 금지.
#   - Forge run_all.R 수정 금지.
#   - Rebalance monthly (optimization_package rebalance_frequency 준수).
#   - Cost: request.json cost_model_version (v2.3_kr_retail_15bps → 15bps).
#==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(jsonlite)
  library(xts)
  library(zoo)
  library(PerformanceAnalytics)
  library(ggplot2)
  library(scales)
})

# ─── 프로젝트 루트 판정 ─────────────────────────────────────────
.joh_detect_root <- function() {
  cand <- c(
    Sys.getenv("QVEST_PROJECT_ROOT", ""),
    Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot")),
    getwd()
  )
  cand <- cand[nzchar(cand)]
  for (c in cand) {
    if (file.exists(file.path(c, "02_Infrastructure", "config.R"))) return(c)
  }
  stop("[judge_oos_helper] PROJECT_ROOT 탐지 실패")
}

.JOH_ROOT <- .joh_detect_root()

# backtest_harness + windowing 로드 (중복 source 허용)
suppressMessages({
  source(file.path(.JOH_ROOT, "02_Infrastructure", "config.R"))
  source(file.path(.JOH_ROOT, "02_Infrastructure", "backtest_harness.R"))
  source(file.path(.JOH_ROOT, "02_Infrastructure", "worktask", "windowing.R"))
})

`%||%` <- function(a, b) if (!is.null(a) && length(a) > 0 && !is.na(a[1])) a else b

# ─── 핵심 시뮬레이터 (고정 weight, monthly rebal, cost 차감) ────
# Forge의 run_all.R 로직을 공용 함수로 재사용. 기간만 외부 지정.
.joh_run_static_weight_sim <- function(RAWDATA, weights_dt,
                                        start_date, end_date,
                                        commission = 0.0015,
                                        initial_cap = 1e8) {
  stopifnot(is.data.table(RAWDATA))
  stopifnot(is.data.table(weights_dt))

  # ticker + weight 정규화
  if (!"Ticker" %in% names(weights_dt) && "ticker" %in% names(weights_dt)) {
    setnames(weights_dt, "ticker", "Ticker")
  }
  if (!"Weight" %in% names(weights_dt) && "weight" %in% names(weights_dt)) {
    setnames(weights_dt, "weight", "Weight")
  }

  TARGET_TICKERS <- unique(weights_dt$Ticker)
  mvo_w <- setNames(weights_dt$Weight / sum(weights_dt$Weight), TARGET_TICKERS)

  start_date <- as.Date(start_date)
  end_date   <- as.Date(end_date)

  all_dates <- sort(unique(RAWDATA[Date >= start_date & Date <= end_date, Date]))
  if (length(all_dates) < 20) {
    stop(sprintf("[judge_oos_helper] date range too short: %d days",
                 length(all_dates)))
  }

  # 월말 signal dates
  backtest_dates <- RAWDATA[Date >= start_date & Date <= end_date, .(Date)]
  backtest_dates[, ym := format(Date, "%Y-%m")]
  signal_dt <- backtest_dates[, .(Signal_Date = max(Date)), by = ym]
  setorder(signal_dt, ym)

  # 마지막 월의 signal은 exec가 다음 달 → end_date 넘을 수 있으니 drop
  signal_dates_raw <- sort(unique(signal_dt$Signal_Date))
  signal_dates <- signal_dates_raw[!is.na(sapply(signal_dates_raw,
                                                  get_execution_date,
                                                  all_dates))]

  cash <- initial_cap
  holdings <- list()
  daily_nav <- list()
  portfolio_log <- list()

  prev_date <- min(all_dates)
  turnover_total <- 0

  for (sig_date in signal_dates) {
    sig_date  <- as.Date(sig_date)
    exec_date <- get_execution_date(sig_date, all_dates)
    if (is.na(exec_date)) next
    if (exec_date > end_date) next

    # Daily NAV before rebal
    exec_dates_range <- all_dates[all_dates > prev_date & all_dates <= exec_date]
    if (length(exec_dates_range) > 0 && length(holdings) > 0) {
      nav_chunk <- .compute_daily_nav(RAWDATA, holdings, exec_dates_range, cash)
      for (ri in seq_len(nrow(nav_chunk))) {
        daily_nav[[length(daily_nav) + 1]] <- nav_chunk[ri]
      }
    }

    total_val <- cash
    for (tk in names(holdings)) {
      price_row <- RAWDATA[Ticker == tk & Date == exec_date, Close]
      if (length(price_row) > 0 && !is.na(price_row[1])) {
        total_val <- total_val + holdings[[tk]]$shares * price_row[1]
      }
    }

    exec_prices <- RAWDATA[Ticker %in% TARGET_TICKERS & Date == exec_date,
                            .(Ticker, Close)]
    exec_prices <- exec_prices[!is.na(Close)]
    if (nrow(exec_prices) == 0) { prev_date <- exec_date; next }

    available <- exec_prices$Ticker
    w_local   <- mvo_w[available]
    if (sum(w_local) <= 0) { prev_date <- exec_date; next }
    w_local   <- w_local / sum(w_local)

    prev_w <- rep(0, length(available))
    names(prev_w) <- available
    if (total_val > 0 && length(holdings) > 0) {
      for (tk in available) {
        if (!is.null(holdings[[tk]])) {
          price_row <- RAWDATA[Ticker == tk & Date == exec_date, Close]
          if (length(price_row) > 0 && !is.na(price_row[1])) {
            prev_w[tk] <- holdings[[tk]]$shares * price_row[1] / total_val
          }
        }
      }
    }
    to_pct <- sum(abs(w_local - prev_w[available])) / 2 * 100
    turnover_total <- turnover_total + to_pct

    invest_val <- total_val

    # 청산
    for (tk in names(holdings)) {
      price_row <- RAWDATA[Ticker == tk & Date == exec_date, Close]
      if (length(price_row) > 0 && !is.na(price_row[1])) {
        proceeds <- holdings[[tk]]$shares * price_row[1]
        cash     <- cash + proceeds * (1 - commission)
      }
    }
    holdings <- list()

    # 신규 매수
    for (i in seq_along(available)) {
      tk    <- available[i]
      alloc <- invest_val * w_local[tk]
      pr    <- exec_prices[Ticker == tk, Close]
      if (length(pr) == 0 || is.na(pr)) next
      shares <- (alloc * (1 - commission)) / pr
      cash   <- cash - alloc
      holdings[[tk]] <- list(shares = shares, last_price = pr)
    }

    nav_est <- cash + sum(sapply(names(holdings), function(tk) {
      holdings[[tk]]$shares * holdings[[tk]]$last_price
    }))

    portfolio_log[[length(portfolio_log) + 1]] <- data.table(
      Signal_Date  = sig_date,
      Exec_Date    = exec_date,
      N_stocks     = length(holdings),
      NAV          = nav_est,
      Turnover_Pct = round(to_pct, 2)
    )
    prev_date <- exec_date
  }

  last_dates <- all_dates[all_dates > prev_date]
  if (length(last_dates) > 0 && length(holdings) > 0) {
    nav_chunk <- .compute_daily_nav(RAWDATA, holdings, last_dates, cash)
    for (ri in seq_len(nrow(nav_chunk))) {
      daily_nav[[length(daily_nav) + 1]] <- nav_chunk[ri]
    }
  }

  DAILY_NAV_DT <- rbindlist(daily_nav)
  if (nrow(DAILY_NAV_DT) == 0) {
    stop("[judge_oos_helper] no NAV rows generated")
  }

  DAILY_NAV_DT[, Date := as.Date(Date)]
  setorder(DAILY_NAV_DT, Date)
  DAILY_NAV_DT <- unique(DAILY_NAV_DT, by = "Date")

  n_years <- as.numeric(difftime(max(DAILY_NAV_DT$Date),
                                  min(DAILY_NAV_DT$Date), units = "days")) / 365.25
  ann_to  <- if (n_years > 0) round(turnover_total / n_years, 1) else NA_real_

  list(
    daily_nav = DAILY_NAV_DT,
    portfolio_log = rbindlist(portfolio_log),
    ann_turnover_pct = ann_to,
    n_rebalances = length(portfolio_log)
  )
}

# ─── 수익률/누적/성과 집계 유틸 ───────────────────────────────
.joh_nav_to_ret <- function(dt) {
  nav_xts <- xts(dt$NAV, order.by = dt$Date)
  diff(log(nav_xts))[-1]
}

.joh_bm_to_ret <- function(bm_dt, dates) {
  # BM_Ret 우선. 없으면 BM_Close로 계산.
  bm <- bm_dt[Date %in% dates]
  setorder(bm, Date)
  if ("BM_Ret" %in% names(bm)) {
    xts(bm$BM_Ret, order.by = bm$Date)
  } else {
    bm_x <- xts(bm$BM_Close, order.by = bm$Date)
    diff(log(bm_x))[-1]
  }
}

.joh_perf <- function(ret_xts, label) {
  r <- ret_xts[!is.na(ret_xts)]
  if (length(r) < 20) {
    return(list(label = label, n_days = length(r),
                CAGR = NA, AnnVol = NA, Sharpe = NA, MDD = NA,
                Calmar = NA, WinRate = NA))
  }
  n <- length(r)
  ann <- (prod(1 + r))^(252 / n) - 1
  vol <- sd(r) * sqrt(252)
  sr  <- ann / vol
  mdd <- as.numeric(maxDrawdown(r))
  cal <- if (mdd > 0) ann / mdd else NA_real_
  wr  <- mean(as.numeric(r) > 0) * 100
  list(
    label  = label,
    n_days = length(r),
    CAGR   = round(as.numeric(ann) * 100, 2),
    AnnVol = round(as.numeric(vol) * 100, 2),
    Sharpe = round(as.numeric(sr), 3),
    MDD    = round(mdd * 100, 2),
    Calmar = round(as.numeric(cal), 3),
    WinRate = round(wr, 1)
  )
}

# ─── 정보 비율 (IR) + alpha (benchmark 대비) ─────────────────
.joh_alpha_ir <- function(strat_xts, bm_xts) {
  common <- as.Date(intersect(index(strat_xts), index(bm_xts)))
  if (length(common) < 20) return(list(alpha_ann_pct = NA, IR = NA, TE_ann_pct = NA))
  sx <- as.numeric(strat_xts[common])
  bx <- as.numeric(bm_xts[common])
  active <- sx - bx
  n <- length(active)
  mean_act <- mean(active, na.rm = TRUE)
  sd_act   <- sd(active, na.rm = TRUE)
  list(
    alpha_ann_pct = round(mean_act * 252 * 100, 3),
    TE_ann_pct    = round(sd_act   * sqrt(252) * 100, 3),
    IR            = if (sd_act > 1e-12) round(mean_act / sd_act * sqrt(252), 3) else NA
  )
}

# ─── WT 경로 resolver ──────────────────────────────────────────
.joh_resolve_wt_paths <- function(wt_id) {
  wt_dir    <- file.path(.JOH_ROOT, "qepm", "mailbox", "worktask", wt_id)
  stage_id  <- gsub("-", "_", wt_id)
  stage_dir <- file.path(.JOH_ROOT, "stage_artifacts", stage_id)
  if (!dir.exists(wt_dir)) {
    stop(sprintf("[judge_oos_helper] WT dir not found: %s", wt_dir))
  }
  list(
    wt_id     = wt_id,
    wt_dir    = wt_dir,
    stage_dir = stage_dir,
    request_path = file.path(wt_dir, "request.json"),
    out_dir   = file.path(wt_dir, "backtest_result")
  )
}

#==============================================================================
# PUBLIC: judge_oos_backtest()
#==============================================================================
judge_oos_backtest <- function(wt_id,
                                weights_path = NULL,
                                benchmark    = "KOSPI200_TR") {

  paths <- .joh_resolve_wt_paths(wt_id)

  # request.json → windows, cost
  req <- fromJSON(paths$request_path, simplifyVector = FALSE)

  train_start   <- as.Date(req$evaluation_windows$train_window$start)
  train_end     <- as.Date(req$evaluation_windows$train_window$end)
  val_start     <- as.Date(req$evaluation_windows$validation_window$start)
  val_end       <- as.Date(req$evaluation_windows$validation_window$end)
  lockbox_start <- as.Date(req$evaluation_windows$lockbox_window$start)
  lockbox_end   <- as.Date(req$evaluation_windows$lockbox_window$end)

  # cost: v2.3_kr_retail_15bps → 0.0015
  cv <- req$cost_model_version %||% "v2.3_kr_retail_15bps"
  commission <- if (grepl("15bps", cv)) 0.0015 else {
    m <- regmatches(cv, regexpr("[0-9]+(?=bps)", cv, perl = TRUE))
    if (length(m) == 1 && nzchar(m)) as.numeric(m) / 10000 else 0.0015
  }

  # weights.csv
  if (is.null(weights_path)) {
    weights_path <- file.path(paths$stage_dir, "weights.csv")
  }
  if (!file.exists(weights_path)) {
    stop(sprintf("[judge_oos_helper] weights.csv not found: %s", weights_path))
  }
  weights_dt <- as.data.table(read.csv(weights_path, stringsAsFactors = FALSE))
  if ("ticker" %in% names(weights_dt)) setnames(weights_dt, "ticker", "Ticker")
  if ("weight" %in% names(weights_dt)) setnames(weights_dt, "weight", "Weight")

  # Lockbox access log (judge 전용)
  log_lockbox_access(wt_id, "judge",
                     file.path(.JOH_ROOT, ".cache", "benchmark.parquet"))
  log_lockbox_access(wt_id, "judge", weights_path)

  # RAWDATA + BM
  raw_list <- load_rawdata(use_cache = TRUE)
  RAWDATA  <- raw_list$RAWDATA
  BM_DT    <- raw_list$BM_DT
  RAWDATA[, Date := as.Date(Date)]
  BM_DT[, Date := as.Date(Date)]
  setkey(RAWDATA, Date, Ticker)

  log_lockbox_access(wt_id, "judge", "RAWDATA.parquet[lockbox_slice]")

  # 시뮬레이션 범위: train_start ~ lockbox_end (전 기간)
  full_start <- train_start
  full_end   <- min(lockbox_end, max(RAWDATA$Date))

  cat(sprintf("[judge_oos_helper] Sim window: %s ~ %s (commission=%.4f)\n",
              full_start, full_end, commission))

  sim <- .joh_run_static_weight_sim(RAWDATA, weights_dt,
                                     start_date = full_start,
                                     end_date   = full_end,
                                     commission = commission)

  full_nav <- sim$daily_nav
  full_ret <- .joh_nav_to_ret(full_nav)
  bm_ret   <- .joh_bm_to_ret(BM_DT, full_nav$Date)

  # Sub-period returns
  train_ret   <- full_ret[paste0(train_start, "/", train_end)]
  val_ret     <- full_ret[paste0(val_start,   "/", val_end)]
  lockbox_ret <- full_ret[paste0(lockbox_start, "/", full_end)]

  train_bm    <- bm_ret[paste0(train_start, "/", train_end)]
  val_bm      <- bm_ret[paste0(val_start,   "/", val_end)]
  lockbox_bm  <- bm_ret[paste0(lockbox_start, "/", full_end)]

  # Performance metrics
  perf_full    <- .joh_perf(full_ret,    "FULL (train+val+lockbox)")
  perf_train   <- .joh_perf(train_ret,   "TRAIN")
  perf_val     <- .joh_perf(val_ret,     "VAL")
  perf_lockbox <- .joh_perf(lockbox_ret, "LOCKBOX (OOS)")

  # Alpha / IR (vs BM)
  alpha_full    <- .joh_alpha_ir(full_ret,    bm_ret)
  alpha_train   <- .joh_alpha_ir(train_ret,   train_bm)
  alpha_val     <- .joh_alpha_ir(val_ret,     val_bm)
  alpha_lockbox <- .joh_alpha_ir(lockbox_ret, lockbox_bm)

  # Equity curves (cumulative)
  build_equity <- function(strat_xts, bm_xts) {
    common <- as.Date(intersect(index(strat_xts), index(bm_xts)))
    if (length(common) == 0) return(data.table())
    cum_s <- cumprod(1 + as.numeric(strat_xts[common]))
    cum_b <- cumprod(1 + as.numeric(bm_xts[common]))
    data.table(Date = common, Strategy = cum_s, Benchmark = cum_b)
  }

  full_equity_dt    <- build_equity(full_ret,    bm_ret)
  lockbox_equity_dt <- build_equity(lockbox_ret, lockbox_bm)

  # Peer comparison table
  comparison <- rbindlist(list(
    data.table(period = "train",   n_days = perf_train$n_days,
               CAGR = perf_train$CAGR, Sharpe = perf_train$Sharpe,
               MDD = perf_train$MDD,
               alpha_pct = alpha_train$alpha_ann_pct, IR = alpha_train$IR,
               TE_pct = alpha_train$TE_ann_pct),
    data.table(period = "val",     n_days = perf_val$n_days,
               CAGR = perf_val$CAGR, Sharpe = perf_val$Sharpe,
               MDD = perf_val$MDD,
               alpha_pct = alpha_val$alpha_ann_pct, IR = alpha_val$IR,
               TE_pct = alpha_val$TE_ann_pct),
    data.table(period = "lockbox_oos", n_days = perf_lockbox$n_days,
               CAGR = perf_lockbox$CAGR, Sharpe = perf_lockbox$Sharpe,
               MDD = perf_lockbox$MDD,
               alpha_pct = alpha_lockbox$alpha_ann_pct, IR = alpha_lockbox$IR,
               TE_pct = alpha_lockbox$TE_ann_pct)
  ))

  # oos_is_ratio (Gate F)
  is_sharpe <- mean(c(perf_train$Sharpe, perf_val$Sharpe), na.rm = TRUE)
  oos_is_ratio <- if (!is.na(is_sharpe) && is_sharpe > 0) {
    round(perf_lockbox$Sharpe / is_sharpe, 3)
  } else NA_real_

  list(
    wt_id            = wt_id,
    windows          = list(
      train   = list(start = train_start,   end = train_end),
      val     = list(start = val_start,     end = val_end),
      lockbox = list(start = lockbox_start, end = full_end)
    ),
    oos_performance  = perf_lockbox,
    train_performance = perf_train,
    val_performance   = perf_val,
    full_performance  = perf_full,
    oos_alpha        = alpha_lockbox,
    train_alpha      = alpha_train,
    val_alpha        = alpha_val,
    full_alpha       = alpha_full,
    comparison_table = comparison,
    oos_equity_dt    = lockbox_equity_dt,
    full_equity_dt   = full_equity_dt,
    lockbox_dt       = full_nav[Date >= lockbox_start],
    oos_is_ratio     = oos_is_ratio,
    n_rebalances     = sim$n_rebalances,
    ann_turnover_pct = sim$ann_turnover_pct,
    commission       = commission,
    benchmark        = benchmark
  )
}

#==============================================================================
# PUBLIC: judge_generate_oos_charts()
#==============================================================================
judge_generate_oos_charts <- function(wt_id, out_dir = NULL) {

  paths <- .joh_resolve_wt_paths(wt_id)
  if (is.null(out_dir)) out_dir <- paths$out_dir
  dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

  bt <- judge_oos_backtest(wt_id)

  train_start <- as.Date(bt$windows$train$start)
  val_start   <- as.Date(bt$windows$val$start)
  lb_start    <- as.Date(bt$windows$lockbox$start)
  lb_end      <- as.Date(bt$windows$lockbox$end)

  full_chart_path <- file.path(out_dir, "equity_curve_full.png")
  oos_chart_path  <- file.path(out_dir, "equity_curve_oos.png")
  oos_summary     <- file.path(out_dir, "oos_summary.json")

  # ─── Full equity curve ───────────────────────────────
  full_dt <- bt$full_equity_dt
  if (nrow(full_dt) > 0) {
    full_long <- melt(full_dt, id.vars = "Date",
                      variable.name = "Series", value.name = "Growth")

    p_full <- ggplot() +
      # 구간 배경 음영
      annotate("rect",
               xmin = train_start, xmax = val_start - 1,
               ymin = -Inf, ymax = Inf,
               fill = "#eeeeee", alpha = 0.40) +
      annotate("rect",
               xmin = val_start, xmax = lb_start - 1,
               ymin = -Inf, ymax = Inf,
               fill = "#fff4c2", alpha = 0.45) +
      annotate("rect",
               xmin = lb_start, xmax = lb_end,
               ymin = -Inf, ymax = Inf,
               fill = "#cfe3ff", alpha = 0.55) +
      geom_line(data = full_long,
                 aes(x = Date, y = Growth, color = Series), linewidth = 0.75) +
      geom_vline(xintercept = val_start, linetype = "dashed",
                  color = "#8b7500", linewidth = 0.4) +
      geom_vline(xintercept = lb_start, linetype = "dashed",
                  color = "#184a90", linewidth = 0.6) +
      scale_color_manual(values = c("Strategy" = "#1f77b4",
                                      "Benchmark" = "#ff7f0e")) +
      scale_y_continuous(labels = scales::comma) +
      labs(
        title    = sprintf("[Judge] %s — Full Period Equity Curve (Train + Val + Lockbox OOS)",
                             wt_id),
        subtitle = sprintf("FULL CAGR=%.2f%% / SR=%.3f / MDD=%.2f%%  |  LOCKBOX OOS CAGR=%.2f%% / SR=%.3f / MDD=%.2f%%",
                             bt$full_performance$CAGR,
                             bt$full_performance$Sharpe,
                             bt$full_performance$MDD,
                             bt$oos_performance$CAGR,
                             bt$oos_performance$Sharpe,
                             bt$oos_performance$MDD),
        caption  = sprintf("Gray=Train (%s~%s) / Yellow=Val (%s~%s) / Blue=Lockbox OOS (%s~%s)",
                             train_start, val_start - 1,
                             val_start, lb_start - 1,
                             lb_start, lb_end),
        x = NULL, y = "Cumulative Growth (1 = base)"
      ) +
      theme_minimal(base_size = 12) +
      theme(legend.position = "bottom",
            plot.title = element_text(face = "bold"))

    png(full_chart_path, width = 1400, height = 760, res = 130)
    print(p_full)
    dev.off()
    cat(sprintf("[judge_oos_helper] saved: %s\n", full_chart_path))
  } else {
    cat("[judge_oos_helper] full_equity_dt empty — skip full chart\n")
    full_chart_path <- NA
  }

  # ─── OOS-only equity curve ───────────────────────────
  oos_dt <- bt$oos_equity_dt
  if (nrow(oos_dt) > 0) {
    # rebase to 1.0 at lockbox start
    oos_dt[, Strategy  := Strategy  / Strategy[1]]
    oos_dt[, Benchmark := Benchmark / Benchmark[1]]

    oos_long <- melt(oos_dt, id.vars = "Date",
                      variable.name = "Series", value.name = "Growth")

    sr_str  <- sprintf("SR = %.3f", bt$oos_performance$Sharpe)
    mdd_str <- sprintf("MDD = %.2f%%", bt$oos_performance$MDD)
    cagr_str <- sprintf("CAGR = %.2f%%", bt$oos_performance$CAGR)
    alpha_str <- sprintf("α = %.2f%% / IR = %.3f",
                          bt$oos_alpha$alpha_ann_pct,
                          bt$oos_alpha$IR)

    # 텍스트 위치
    y_txt <- max(oos_dt$Strategy, oos_dt$Benchmark, na.rm = TRUE) * 0.98
    x_txt <- min(oos_dt$Date) + as.integer(diff(range(oos_dt$Date)) / 20)

    p_oos <- ggplot(oos_long,
                      aes(x = Date, y = Growth, color = Series)) +
      geom_hline(yintercept = 1, linewidth = 0.3, color = "grey70") +
      geom_line(linewidth = 0.85) +
      scale_color_manual(values = c("Strategy" = "#1f77b4",
                                      "Benchmark" = "#ff7f0e")) +
      annotate("label", x = x_txt, y = y_txt,
               label = paste(cagr_str, sr_str, mdd_str, alpha_str, sep = "  |  "),
               fill = "#cfe3ff", color = "#0f2a55", size = 3.6,
               hjust = 0, label.size = 0) +
      scale_y_continuous(labels = scales::comma) +
      labs(
        title    = sprintf("[Judge] %s — Lockbox OOS (24M) — Judge Verdict Chart", wt_id),
        subtitle = sprintf("OOS period: %s ~ %s  |  n_days=%d  |  Benchmark=KOSPI200_TR",
                             lb_start, lb_end, bt$oos_performance$n_days),
        caption  = sprintf("oos_is_ratio=%s (Gate F threshold ≥ 0.7)",
                             ifelse(is.na(bt$oos_is_ratio), "NA",
                                    sprintf("%.3f", bt$oos_is_ratio))),
        x = NULL, y = "Cumulative Growth (rebased to 1.0)"
      ) +
      theme_minimal(base_size = 12) +
      theme(legend.position = "bottom",
            plot.title = element_text(face = "bold"))

    png(oos_chart_path, width = 1200, height = 720, res = 130)
    print(p_oos)
    dev.off()
    cat(sprintf("[judge_oos_helper] saved: %s\n", oos_chart_path))
  } else {
    cat("[judge_oos_helper] oos_equity_dt empty — skip OOS chart\n")
    oos_chart_path <- NA
  }

  # ─── oos_summary.json ────────────────────────────────
  summary_json <- list(
    wt_id       = wt_id,
    agent       = "judge",
    as_of_date  = format(Sys.Date(), "%Y-%m-%d"),
    benchmark   = bt$benchmark,
    commission  = bt$commission,
    windows     = list(
      train   = list(start = as.character(bt$windows$train$start),
                      end   = as.character(bt$windows$train$end)),
      val     = list(start = as.character(bt$windows$val$start),
                      end   = as.character(bt$windows$val$end)),
      lockbox = list(start = as.character(bt$windows$lockbox$start),
                      end   = as.character(bt$windows$lockbox$end))
    ),
    performance = list(
      full    = bt$full_performance,
      train   = bt$train_performance,
      val     = bt$val_performance,
      lockbox = bt$oos_performance
    ),
    alpha_ir = list(
      full    = bt$full_alpha,
      train   = bt$train_alpha,
      val     = bt$val_alpha,
      lockbox = bt$oos_alpha
    ),
    gate_f   = list(
      metric      = "oos_is_ratio",
      value       = bt$oos_is_ratio,
      threshold   = 0.7,
      verdict     = if (is.na(bt$oos_is_ratio)) "WARN_NA"
                     else if (bt$oos_is_ratio >= 0.7) "PASS" else "FAIL"
    ),
    comparison_table = bt$comparison_table,
    n_rebalances     = bt$n_rebalances,
    ann_turnover_pct = bt$ann_turnover_pct,
    artifacts = list(
      equity_curve_full = full_chart_path,
      equity_curve_oos  = oos_chart_path
    ),
    lockbox_access_log = sprintf("/tmp/qvest_lockbox_access_%s.log", wt_id)
  )

  write_json(summary_json, oos_summary,
             pretty = TRUE, auto_unbox = TRUE, null = "null")
  cat(sprintf("[judge_oos_helper] saved: %s\n", oos_summary))

  invisible(list(
    full_chart_path  = full_chart_path,
    oos_chart_path   = oos_chart_path,
    oos_summary_path = oos_summary,
    oos_performance  = bt$oos_performance,
    oos_is_ratio     = bt$oos_is_ratio
  ))
}

cat("[judge_oos_helper.R] Loaded. Public:\n")
cat("  judge_oos_backtest(wt_id, weights_path=NULL, benchmark='KOSPI200_TR')\n")
cat("  judge_generate_oos_charts(wt_id, out_dir=NULL)\n")
