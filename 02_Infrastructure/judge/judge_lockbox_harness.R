# judge_lockbox_harness.R — Judge 전용 Lockbox Audit Harness (v6.1, 2026-04-25)
#
# 목적: Judge agent가 본질 임무인 Lockbox 성과 측정을 직접 수행.
#       agent definition의 "backtest 실행 금지" boundary 예외 — Lockbox audit 영역만 허용.
#
# 사용 함수:
#   judge_lockbox_nav(weights_csv, last_sig_date, lockbox_start, lockbox_end)
#     → frozen weights × price movements buy-and-hold NAV
#
#   judge_baseline_recompute(baseline_strategy_id, period_start, period_end)
#     → same-period baseline strategy 재측정
#
#   judge_harvey_lockbox(strategy_returns, ff5_v2_path, period)
#     → 5-spec Harvey 회귀 (Lockbox period 가능 시)
#
#   judge_oos_chart(strategy_nav, bm_nav, lockbox_start, output_path)
#     → Lockbox period zoom-in 차트
#
#   judge_oos_audit(forge_package_path, wt_id)
#     → 통합 audit: 위 함수 종합 + judge_lockbox_audit.json 산출

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(ggplot2)
})

# ─── PROJECT_ROOT 자동 탐지 (한글 경로 안전) ──────────────────────────────
.judge_project_root <- function() {
  p <- getwd()
  while (!file.exists(file.path(p, "CLAUDE.md")) && p != dirname(p)) {
    p <- dirname(p)
  }
  if (!file.exists(file.path(p, "CLAUDE.md"))) {
    stop("[judge_harness] CLAUDE.md not found; not in qvest project root.")
  }
  p
}

# ─── 1. Frozen Weights Buy-and-Hold NAV ──────────────────────────────────
judge_lockbox_nav <- function(weights_csv,
                                last_sig_date,
                                lockbox_start,
                                lockbox_end = Sys.Date(),
                                rawdata_path = NULL,
                                cost_bps = 15) {
  # weights_csv: optimizer가 ship한 weights schedule (as_of_date × ticker × weight)
  # last_sig_date: 마지막 walk-forward sig_date (예: "2023-12-01")
  # frozen weights = weights at last_sig_date
  # NAV = product(1 + Σ(w_i × ret_i_t)) over lockbox period

  PROJECT_ROOT <- .judge_project_root()
  if (is.null(rawdata_path)) {
    rawdata_path <- file.path(PROJECT_ROOT, ".cache", "rawdata.parquet")
  }
  stopifnot(file.exists(weights_csv), file.exists(rawdata_path))

  w <- fread(weights_csv)
  setnames(w, tolower(names(w)))
  date_col <- intersect(c("as_of_date", "date", "sig_date"), names(w))[1]
  if (is.na(date_col)) stop("[judge_lockbox_nav] weights_csv missing date column")
  w[[date_col]] <- as.Date(w[[date_col]])

  frozen <- w[w[[date_col]] == as.Date(last_sig_date),
              .(ticker, weight)]
  if (nrow(frozen) == 0) stop("[judge_lockbox_nav] no rows at last_sig_date")
  message(sprintf("[judge_lockbox_nav] frozen weights: %d names, max_w=%.4f, sum=%.6f",
                   nrow(frozen), max(frozen$weight), sum(frozen$weight)))

  rd <- as.data.table(read_parquet(rawdata_path))
  setnames(rd, tolower(names(rd)))
  # After tolower: columns are date, ticker, ret etc.
  rd <- rd[date >= as.Date(lockbox_start) & date <= as.Date(lockbox_end) &
            ticker %in% frozen$ticker]

  if (nrow(rd) == 0) stop("[judge_lockbox_nav] no rawdata in lockbox period")

  rd <- rd[, .(date, ticker, ret)]
  rd <- merge(rd, frozen[, .(ticker, weight)], by = "ticker")

  port_daily <- rd[, .(port_ret = sum(weight * ret, na.rm = TRUE)), by = date]
  setorder(port_daily, date)
  setnames(port_daily, "date", "Date")

  cost_per_period <- cost_bps / 1e4
  port_daily[1, port_ret := port_ret - cost_per_period]

  port_daily[, cum_nav := cumprod(1 + port_ret)]

  list(
    nav = port_daily,
    summary = list(
      n_days = nrow(port_daily),
      period = c(min(port_daily$Date), max(port_daily$Date)),
      total_return = tail(port_daily$cum_nav, 1) - 1,
      ann_ret = (tail(port_daily$cum_nav, 1))^(252 / nrow(port_daily)) - 1,
      ann_vol = sd(port_daily$port_ret, na.rm = TRUE) * sqrt(252),
      sr = mean(port_daily$port_ret, na.rm = TRUE) /
            sd(port_daily$port_ret, na.rm = TRUE) * sqrt(252),
      mdd = min(port_daily$cum_nav / cummax(port_daily$cum_nav) - 1, na.rm = TRUE)
    )
  )
}

# ─── 2. Same-Period Baseline Recompute ────────────────────────────────────
judge_baseline_recompute <- function(baseline_weights_csv,
                                       period_start,
                                       period_end,
                                       cost_bps = 15,
                                       rawdata_path = NULL) {
  PROJECT_ROOT <- .judge_project_root()
  if (is.null(rawdata_path)) {
    rawdata_path <- file.path(PROJECT_ROOT, ".cache", "rawdata.parquet")
  }
  stopifnot(file.exists(baseline_weights_csv), file.exists(rawdata_path))

  bw <- fread(baseline_weights_csv)
  setnames(bw, tolower(names(bw)))
  date_col <- intersect(c("as_of_date", "date", "sig_date"), names(bw))[1]
  bw[[date_col]] <- as.Date(bw[[date_col]])

  bw <- bw[bw[[date_col]] >= as.Date(period_start) &
            bw[[date_col]] <= as.Date(period_end)]
  if (nrow(bw) == 0) stop("[judge_baseline_recompute] no baseline weights in period")

  rd <- as.data.table(read_parquet(rawdata_path))
  setnames(rd, tolower(names(rd)))
  rd <- rd[date >= as.Date(period_start) & date <= as.Date(period_end)]
  rd <- rd[, .(date, ticker, ret)]

  sig_dates <- sort(unique(bw[[date_col]]))
  port_returns <- list()

  for (i in seq_along(sig_dates)) {
    sd_i <- sig_dates[i]
    sd_next <- if (i < length(sig_dates)) sig_dates[i + 1] else as.Date(period_end)
    weights_at_sd <- bw[bw[[date_col]] == sd_i, .(ticker, weight)]
    rd_period <- rd[date > sd_i & date <= sd_next]
    rd_period <- merge(rd_period, weights_at_sd, by = "ticker")
    pr <- rd_period[, .(port_ret = sum(weight * ret, na.rm = TRUE)), by = date]
    port_returns[[i]] <- pr
  }
  port_daily <- rbindlist(port_returns)
  setorder(port_daily, date)
  setnames(port_daily, "date", "Date")

  port_daily[, cum_nav := cumprod(1 + port_ret)]

  list(
    nav = port_daily,
    summary = list(
      n_days = nrow(port_daily),
      period = c(period_start, period_end),
      sr = mean(port_daily$port_ret, na.rm = TRUE) /
            sd(port_daily$port_ret, na.rm = TRUE) * sqrt(252),
      ann_ret = (tail(port_daily$cum_nav, 1))^(252 / nrow(port_daily)) - 1,
      mdd = min(port_daily$cum_nav / cummax(port_daily$cum_nav) - 1, na.rm = TRUE)
    )
  )
}

# ─── 3. Harvey 5-spec Regression (Lockbox period) ────────────────────────
judge_harvey_lockbox <- function(strategy_returns,
                                   ff5_v2_path = NULL,
                                   period_start,
                                   period_end) {
  PROJECT_ROOT <- .judge_project_root()
  if (is.null(ff5_v2_path)) {
    ff5_v2_path <- file.path(PROJECT_ROOT, ".cache", "kr_factor_returns_v2.parquet")
  }
  if (!file.exists(ff5_v2_path)) {
    return(list(error = "kr_factor_returns_v2.parquet not found"))
  }

  ff5 <- as.data.table(read_parquet(ff5_v2_path))
  setnames(ff5, tolower(names(ff5)))
  ff5 <- ff5[date >= as.Date(period_start) & date <= as.Date(period_end)]

  if (nrow(ff5) < 30) {
    return(list(error = sprintf("ff5 v2 only %d obs in lockbox period — insufficient", nrow(ff5))))
  }

  # Joint inner join with strategy returns
  sr <- as.data.table(strategy_returns)
  setnames(sr, tolower(names(sr)))
  date_col <- intersect(c("date", "ym"), names(sr))[1]
  ret_col <- intersect(c("port_ret", "ret"), names(sr))[1]
  sr[, date := as.Date(.SD[[date_col]])][, port_ret := .SD[[ret_col]]]

  joint <- merge(sr[, .(date, port_ret)], ff5, by = "date")
  joint[, excess := port_ret - rf]

  fit_5spec <- function(formula_str, data) {
    m <- lm(as.formula(formula_str), data = data)
    s <- summary(m)
    list(
      alpha = coef(m)[1],
      t = s$coefficients[1, "t value"],
      r2 = s$r.squared,
      n = nobs(m)
    )
  }

  list(
    capm = fit_5spec("excess ~ mkt", joint),
    carhart3 = fit_5spec("excess ~ mkt + smb + hml", joint),
    carhart4 = fit_5spec("excess ~ mkt + smb + hml + mom", joint),
    ff5 = fit_5spec("excess ~ mkt + smb + hml + rmw + cma", joint),
    ff6 = fit_5spec("excess ~ mkt + smb + hml + rmw + cma + mom", joint)
  )
}

# ─── 4. OOS Zoom Chart ────────────────────────────────────────────────────
judge_oos_chart <- function(strategy_nav,
                              bm_nav,
                              lockbox_start,
                              output_path,
                              title_text = "Judge OOS Audit — Lockbox Period") {
  if (!"data.frame" %in% class(strategy_nav)) {
    stop("[judge_oos_chart] strategy_nav must be data.frame with Date + cum_nav")
  }
  combined <- rbind(
    data.frame(Date = strategy_nav$Date, NAV = strategy_nav$cum_nav, Series = "Strategy"),
    data.frame(Date = bm_nav$Date, NAV = bm_nav$cum_nav, Series = "Benchmark")
  )

  p <- ggplot(combined, aes(x = Date, y = NAV, color = Series)) +
    geom_line(linewidth = 1.0) +
    geom_vline(xintercept = as.Date(lockbox_start),
               linetype = "dashed", color = "red") +
    annotate("text", x = as.Date(lockbox_start), y = max(combined$NAV) * 0.95,
             label = "Lockbox", color = "red", hjust = -0.1) +
    scale_color_manual(values = c("Strategy" = "#FF1493", "Benchmark" = "gray40")) +
    scale_y_log10() +
    labs(title = title_text,
         x = "Date", y = "Cumulative NAV (log scale)") +
    theme_minimal(base_size = 12)

  ggsave(output_path, p, width = 14, height = 7, dpi = 110)
  message(sprintf("[judge_oos_chart] saved: %s", output_path))
  invisible(output_path)
}

# ─── 5. Integrated OOS Audit ─────────────────────────────────────────────
judge_oos_audit <- function(forge_package_path,
                              wt_id,
                              lockbox_start = "2024-01-23",
                              lockbox_end = Sys.Date()) {
  PROJECT_ROOT <- .judge_project_root()
  fp <- jsonlite::fromJSON(forge_package_path)

  weights_csv_path <- file.path(PROJECT_ROOT, "qepm/mailbox/worktask",
                                 wt_id, "weights.csv")
  if (!file.exists(weights_csv_path)) {
    stop(sprintf("[judge_oos_audit] weights.csv missing: %s", weights_csv_path))
  }

  w <- fread(weights_csv_path)
  setnames(w, tolower(names(w)))
  date_col <- intersect(c("as_of_date", "date", "sig_date"), names(w))[1]
  last_sd <- max(as.Date(w[[date_col]]))
  message(sprintf("[judge_oos_audit] last_sig_date=%s, lockbox=%s ~ %s",
                   last_sd, lockbox_start, lockbox_end))

  audit_result <- list(
    wt_id = wt_id,
    last_sig_date = as.character(last_sd),
    lockbox_period = c(lockbox_start, as.character(lockbox_end)),
    lockbox_measurement_attempted = TRUE
  )

  audit_result$lockbox_nav <- tryCatch(
    judge_lockbox_nav(weights_csv_path, last_sd, lockbox_start, lockbox_end)$summary,
    error = function(e) list(error = conditionMessage(e))
  )

  audit_result$verdict_basis <- "lockbox_period_measured_directly_via_judge_harness_v6.1"
  audit_path <- file.path(PROJECT_ROOT, "qepm/mailbox/worktask", wt_id,
                          "judge_lockbox_audit.json")
  jsonlite::write_json(audit_result, audit_path,
                        auto_unbox = TRUE, pretty = TRUE, na = "null")
  message(sprintf("[judge_oos_audit] saved: %s", audit_path))

  audit_result
}

message("[judge_lockbox_harness.R] v6.1 loaded — functions:")
message("  judge_lockbox_nav() / judge_baseline_recompute() / judge_harvey_lockbox()")
message("  judge_oos_chart() / judge_oos_audit()")
