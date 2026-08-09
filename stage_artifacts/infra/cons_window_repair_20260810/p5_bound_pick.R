#==============================================================================
# p5_bound_pick.R — FQ-218 (A) 상한 확정 + 커버리지 재기준
#
# p4 의 두 흠을 고친다:
#   (1) cover_frac 분모가 "전 역사 누적 티커"였다 → 오도. 진짜 기준선은
#       **현행 결함 코드가 실제로 배출하는 티커 집합(W0)** 이다.
#   (2) 상한을 커버리지 최대화로 고르면 3년을 "4분기"라 부르게 된다.
#       상한은 **정상 분기 격자가 legit 하게 차지하는 최대 span** 에서 나와야 한다.
#
# 방법: 인접 런 간격이 전부 [55,130]일인 티커 = "정상 분기 격자" 하위모집단.
#       그 안에서 sig_d − oldest_run_start 분포의 상단을 상한으로 잡는다.
#
# 읽기 전용.
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
ROOT <- gsub("\\\\", "/", ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/infra/cons_window_repair_20260810")

sig_dates <- as.Date(c("2006-06-30", "2010-06-30", "2014-06-30", "2018-06-29",
                       "2022-06-30", "2024-06-28", "2011-03-15", "2019-09-30"))
BOUNDS <- c(400L, 460L, 520L, 600L, 730L)
healthy_rows <- list(); cov_rows <- list()

for (spec in list(list(m = "sue", n = 4L), list(m = "esbr", n = 3L))) {
  metric <- spec$m; n_take <- spec$n
  h <- as.data.table(read_parquet(file.path(ROOT, ".cache/consensus",
                                            paste0(metric, ".parquet"))))
  if (!inherits(h$Date, "Date")) h[, Date := as.Date(Date)]
  h <- h[!is.na(get(metric))]

  for (k in seq_along(sig_dates)) {
    sig_d <- sig_dates[k]
    x <- h[Date <= sig_d]
    if (!nrow(x)) next
    setorderv(x, c("Ticker", "Date"), c(1L, -1L))

    # ★기준선 W0 = 현행 결함 코드의 배출 집합 (최신 N행 평균, 항상 값이 나옴)
    w0 <- x[, .(w0_latest = get(metric)[1L],
                w0_avg = mean(get(metric)[seq_len(min(.N, n_take))])), by = Ticker]
    n_w0 <- nrow(w0)

    rt <- x[, {
      r <- rleid(get(metric))
      .(run = r, v = get(metric), d = Date)
    }, by = Ticker][, .(v = v[1L], run_start = min(d), run_end = max(d)),
                    by = .(Ticker, run)]
    setorderv(rt, c("Ticker", "run"))
    rt[, idx := seq_len(.N), by = Ticker]
    rt[, gap := as.integer(shift(run_start, type = "lag") - run_start), by = Ticker]

    win <- rt[idx <= n_take]
    # 정상 분기 격자 = 창 안 인접 간격이 전부 [55,130]
    ok_grid <- win[, .(n_runs = .N,
                       all_q = all(is.na(gap) | (gap >= 55L & gap <= 130L)),
                       age_oldest = as.integer(sig_d - min(run_start))),
                   by = Ticker][n_runs == n_take]
    hh <- ok_grid[all_q == TRUE]
    if (nrow(hh)) {
      healthy_rows[[length(healthy_rows) + 1L]] <- data.table(
        metric = metric, sig_date = sig_d, n_healthy = nrow(hh),
        p50 = quantile(hh$age_oldest, .50), p90 = quantile(hh$age_oldest, .90),
        p99 = quantile(hh$age_oldest, .99), pmax = max(hh$age_oldest))
    }

    # 상한별 커버리지 — 분모를 W0 배출 집합으로
    for (B in BOUNDS) {
      sel <- win[as.integer(sig_d - run_start) <= B]
      agg <- sel[, .(n_used = .N, avg = mean(v),
                     latest = v[idx == min(idx)][1L]), by = Ticker][n_used >= 2L]
      cov_rows[[length(cov_rows) + 1L]] <- data.table(
        metric = metric, sig_date = sig_d, bound = B,
        n_w0 = n_w0, n_emit = nrow(agg), cover_vs_w0 = nrow(agg) / n_w0,
        frac_eq_latest = if (nrow(agg)) mean(abs(agg$avg - agg$latest) < 1e-12) else NA_real_,
        median_n_used = if (nrow(agg)) median(agg$n_used) else NA_real_,
        frac_full_n = if (nrow(agg)) mean(agg$n_used == n_take) else NA_real_)
    }
  }
}

hr <- rbindlist(healthy_rows); cr <- rbindlist(cov_rows)
fwrite(hr, file.path(OUT, "p5_healthy_span.csv"))
fwrite(cr, file.path(OUT, "p5_coverage_vs_w0.csv"))

cat("\n==== 정상 분기격자 하위모집단의 oldest-run age (일) ====\n")
print(hr[, .(n_healthy = sum(n_healthy), p50 = median(p50), p90 = median(p90),
             p99 = median(p99), pmax = max(pmax)), by = metric])
cat("\n==== 상한별: 분모 = 현행 결함코드 배출 티커(W0) ====\n")
print(cr[, .(n_w0 = round(mean(n_w0)), n_emit = round(mean(n_emit)),
             cover_vs_w0 = mean(cover_vs_w0), frac_eq_latest = mean(frac_eq_latest),
             frac_full_n = mean(frac_full_n)), by = .(metric, bound)][order(metric, bound)])
