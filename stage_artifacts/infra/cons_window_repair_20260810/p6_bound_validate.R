#==============================================================================
# p6_bound_validate.R — 상한 상수 검증 (p5 자가정정)
#
# p5 의 "정상 격자" 하위모집단이 오염돼 있었다: gap 조건만 걸고 **최신성**을
# 안 걸어서, 마지막 4분기가 2005년에 몰린 뒤 값이 캐리포워드된 티커가 통과했다
# (p90 age 3,040일). 상한은 두 축을 동시에 만족해야 한다 —
#   ① 창 안 인접 간격이 분기 격자 ② 최신 런이 실제로 최신.
#
# 여기서는 **패널에 아직 살아있는** 티커(마지막 일간 행이 sig_d 로부터 10일 이내)
# 로 좁혀 legit span 의 상단을 잰다. 후보 상수: MAX_LOOKBACK = n_take * 130.
#   (관측된 정상 분기 간격 최대 121일 → 여유 130. n_take 런 = (n_take-1) 간격
#    + 최신 런의 나이(≤130) ⇒ n_take*130 이 상계.)
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
ROOT <- gsub("\\\\", "/", ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/infra/cons_window_repair_20260810")

sig_dates <- as.Date(c("2006-06-30", "2010-06-30", "2014-06-30", "2018-06-29",
                       "2022-06-30", "2024-06-28", "2011-03-15", "2019-09-30"))
out <- list()
for (spec in list(list(m = "sue", n = 4L), list(m = "esbr", n = 3L))) {
  metric <- spec$m; n_take <- spec$n; BOUND <- n_take * 130L
  h <- as.data.table(read_parquet(file.path(ROOT, ".cache/consensus",
                                            paste0(metric, ".parquet"))))
  if (!inherits(h$Date, "Date")) h[, Date := as.Date(Date)]
  h <- h[!is.na(get(metric))]

  for (k in seq_along(sig_dates)) {
    sig_d <- sig_dates[k]
    x <- h[Date <= sig_d]; if (!nrow(x)) next
    setorderv(x, c("Ticker", "Date"), c(1L, -1L))
    x[, live := as.integer(sig_d - Date[1L]) <= 10L, by = Ticker]
    xl <- x[live == TRUE]                       # 패널에 살아있는 티커만
    if (!nrow(xl)) next
    rt <- xl[, { r <- rleid(get(metric)); .(run = r, v = get(metric), d = Date) },
             by = Ticker][, .(run_start = min(d), run_end = max(d)),
                          by = .(Ticker, run)]
    setorderv(rt, c("Ticker", "run"))
    rt[, idx := seq_len(.N), by = Ticker]
    rt[, gap := as.integer(shift(run_start, type = "lag") - run_start), by = Ticker]
    win <- rt[idx <= n_take]
    g <- win[, .(n_runs = .N,
                 all_q = all(is.na(gap) | (gap >= 55L & gap <= 130L)),
                 age_oldest = as.integer(sig_d - min(run_start))),
             by = Ticker][n_runs == n_take]
    hh <- g[all_q == TRUE]
    if (!nrow(hh)) next
    out[[length(out) + 1L]] <- data.table(
      metric = metric, n_take = n_take, bound = BOUND, sig_date = sig_d,
      n_live_grid = nrow(hh), p50 = quantile(hh$age_oldest, .50),
      p95 = quantile(hh$age_oldest, .95), p99 = quantile(hh$age_oldest, .99),
      pmax = max(hh$age_oldest),
      frac_within_bound = mean(hh$age_oldest <= BOUND))
  }
}
r <- rbindlist(out)
fwrite(r, file.path(OUT, "p6_bound_validate.csv"))
cat("\n==== 살아있는 티커 × 정상 분기격자: oldest-run age(일) ====\n")
print(r[, .(n = sum(n_live_grid), p50 = median(p50), p95 = median(p95),
            p99 = median(p99), pmax = max(pmax),
            frac_within_bound = mean(frac_within_bound)),
        by = .(metric, n_take, bound)])
cat("\n[p6] frac_within_bound 가 1.0 에 가까우면 상수 n_take*130 이 legit 격자를\n")
cat("     자르지 않는다는 뜻 — 상한은 stale 소급만 막는다.\n")
