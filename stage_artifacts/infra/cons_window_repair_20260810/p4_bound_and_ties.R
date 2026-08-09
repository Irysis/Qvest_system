#==============================================================================
# p4_bound_and_ties.R — FQ-218 (A) 채택안 W1 의 두 실패양식 계량
#
# p3 결과: W1(런 dedup)만 창을 실제로 벌린다(고유값 = n_take, span 중앙 362일).
#   그러나 max_span 7,424일 = **무한 소급**. 그리고 esbr 은 비율이라 **동률 병합**
#   위험이 있다(두 분기 값이 같으면 런이 합쳐져 한 분기 더 뒤로 간다).
#
# 이 스크립트는 그 둘을 계량해 최종 파라미터(MAX_LOOKBACK_DAYS, MIN_RUNS)를 정한다.
#
#   B1. 정상 커버리지 티커의 "최근 N런 span" 분포 → 상한 후보 도출
#       정상 = 최신 관측이 sig_d 로부터 90일 이내(= 커버리지 살아있음)
#   B2. 동률 병합률 — 인접 런 시작일 간격이 1분기(61~121일)가 아니라
#       2분기 이상(>150일)인 비율. 병합이 있으면 그만큼 값이 같았다는 뜻.
#   B3. 상한 후보별 커버리지 / frac_avg_eq_latest 트레이드오프
#
# 읽기 전용.
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
ROOT <- gsub("\\\\", "/", ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/infra/cons_window_repair_20260810")

sig_dates <- as.Date(c("2006-06-30", "2010-06-30", "2014-06-30",
                       "2018-06-29", "2022-06-30", "2024-06-28",
                       "2011-03-15", "2019-09-30"))
BOUNDS <- c(400L, 460L, 550L, 730L, 1100L)

span_rows <- list(); tie_rows <- list(); bnd_rows <- list()

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

    # 런 테이블: 최신순으로 런 id, 각 런의 시작일(가장 이른 날) = 가용일
    runs <- x[, {
      r <- rleid(get(metric))
      .(run = r, v = get(metric), d = Date)
    }, by = Ticker]
    rt <- runs[, .(v = v[1L], run_start = min(d), run_end = max(d)), by = .(Ticker, run)]
    setorderv(rt, c("Ticker", "run"))
    rt[, idx := seq_len(.N), by = Ticker]          # 1 = 최신 런
    rt[, latest_obs := max(run_end), by = Ticker]
    rt[, active := as.integer(sig_d - latest_obs) <= 90L]

    # B1: 최근 n_take 런의 span (= 최신 런 end − n_take번째 런 start)
    sp <- rt[idx <= n_take, .(n_runs = .N,
                              span = as.integer(max(run_end) - min(run_start)),
                              active = active[1L]), by = Ticker][n_runs == n_take]
    if (nrow(sp)) {
      span_rows[[length(span_rows) + 1L]] <- data.table(
        metric = metric, sig_date = sig_d, grp = "active",
        n = sum(sp$active == 1L),
        p50 = as.numeric(quantile(sp[active == 1L]$span, .50, na.rm = TRUE)),
        p95 = as.numeric(quantile(sp[active == 1L]$span, .95, na.rm = TRUE)),
        p99 = as.numeric(quantile(sp[active == 1L]$span, .99, na.rm = TRUE)),
        pmax = suppressWarnings(max(sp[active == 1L]$span)))
      span_rows[[length(span_rows) + 1L]] <- data.table(
        metric = metric, sig_date = sig_d, grp = "stale",
        n = sum(sp$active == 0L),
        p50 = as.numeric(quantile(sp[active == 0L]$span, .50, na.rm = TRUE)),
        p95 = as.numeric(quantile(sp[active == 0L]$span, .95, na.rm = TRUE)),
        p99 = as.numeric(quantile(sp[active == 0L]$span, .99, na.rm = TRUE)),
        pmax = suppressWarnings(max(sp[active == 0L]$span)))
    }

    # B2: 동률 병합 — 인접 런 시작일 간격
    rt[, gap := as.integer(shift(run_start, type = "lag") - run_start), by = Ticker]
    gg <- rt[active == 1L & idx <= n_take & !is.na(gap), gap]
    if (length(gg)) {
      tie_rows[[length(tie_rows) + 1L]] <- data.table(
        metric = metric, sig_date = sig_d, n_gap = length(gg),
        frac_1q = mean(gg >= 55L & gg <= 130L),
        frac_merged_2q_plus = mean(gg > 150L),
        median_gap = median(gg))
    }

    # B3: 상한 후보별 — 상한 안에 든 런만 채택, MIN_RUNS=2 미만이면 NA
    for (B in BOUNDS) {
      sel <- rt[idx <= n_take & as.integer(sig_d - run_start) <= B]
      agg <- sel[, .(n_used = .N, avg = mean(v), latest = v[idx == min(idx)][1L],
                     span = as.integer(max(run_end) - min(run_start))), by = Ticker]
      ok <- agg[n_used >= 2L]
      bnd_rows[[length(bnd_rows) + 1L]] <- data.table(
        metric = metric, sig_date = sig_d, bound = B,
        n_ticker_total = uniqueN(rt$Ticker), n_emit = nrow(ok),
        cover_frac = nrow(ok) / uniqueN(rt$Ticker),
        frac_eq_latest = if (nrow(ok)) mean(abs(ok$avg - ok$latest) < 1e-12) else NA_real_,
        median_n_used = if (nrow(ok)) median(ok$n_used) else NA_real_,
        max_span = if (nrow(ok)) max(ok$span) else NA_integer_)
    }
  }
}

sp <- rbindlist(span_rows); ti <- rbindlist(tie_rows); bn <- rbindlist(bnd_rows)
fwrite(sp, file.path(OUT, "p4_span_by_group.csv"))
fwrite(ti, file.path(OUT, "p4_tie_merge.csv"))
fwrite(bn, file.path(OUT, "p4_bound_tradeoff.csv"))

cat("\n==== B1: 최근 N런 span (active = 최신관측 90일 이내) ====\n")
print(sp[, .(n = sum(n), p50 = median(p50), p95 = median(p95),
             p99 = median(p99), pmax = max(pmax)), by = .(metric, grp)])
cat("\n==== B2: 인접 런 간격 (active, 창 안) ====\n")
print(ti[, .(n_gap = sum(n_gap), frac_1quarter = mean(frac_1q),
             frac_merged_2q_plus = mean(frac_merged_2q_plus),
             median_gap = median(median_gap)), by = metric])
cat("\n==== B3: 상한 후보 트레이드오프 (8 sig_date 평균) ====\n")
print(bn[, .(cover_frac = mean(cover_frac), frac_eq_latest = mean(frac_eq_latest),
             median_n_used = median(median_n_used), max_span = max(max_span)),
         by = .(metric, bound)][order(metric, bound)])
