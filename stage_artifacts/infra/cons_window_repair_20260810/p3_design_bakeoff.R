#==============================================================================
# p3_design_bakeoff.R — FQ-218 (A) 창 정의 3선택지 실측 비교
#
# p1/p2 확정 사실:
#   - 원천 행 = 일간 캐리포워드 (관측 간격 중앙 1일)
#   - 값 변경 = 분기 리듬 (변경 간격 중앙 91일)
#   - 변경일 = 4/6/9/12 월 **첫 영업일** (월초 100%, 월말 0%, 주말 0건)
#     ⇒ 한국 분기 법정 제출기한 이후 = **가용일**. 분기말 스탬프 아님.
#
# 그러므로 "값이 바뀐 지점" = 새 분기값이 패널에 나타난 날 = PIT 가용 시점이고,
# 연속-런(run) 경계가 곧 분기 경계다. 이 사실 위에서 3안을 비교한다.
#
#   W0 (현행·결함) : 최신 N개 **행**            → 3~5일
#   W1 (런 기반)   : 연속-런 dedup 후 최신 N런  → 분기 리샘플 == 고유값(연속)
#   W2 (달력 lag)  : sig, -3M, -6M, -9M 각 시점의 최신값
#   W3 (달력 lag+) : sig, -4M, -8M, -12M
#
# ★W1 은 반드시 **연속-런(rleid) dedup** 이어야 한다. 전역 unique() 를 쓰면
#   Q1=0.5, Q2=0.6, Q3=0.5 에서 Q3 를 건너뛴다(재발값 소실).
#
# 비교 축: mean==latest 비율 / 창 내 고유값 / 창 span / 커버리지 / 최대 span
# 읽기 전용.
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
ROOT <- gsub("\\\\", "/", ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/infra/cons_window_repair_20260810")

add_months <- function(d, m) seq(d, by = paste(m, "months"), length.out = 2L)[2L]

bake <- function(h, metric, sig_d, n_take) {
  # ★ for (x in as.Date(v)) 는 Date 클래스를 벗겨 numeric 을 준다. 방어적으로 못박는다.
  stopifnot(inherits(sig_d, "Date"), length(sig_d) == 1L)
  x <- h[Date <= sig_d & !is.na(get(metric))]
  if (!nrow(x)) return(NULL)
  setorderv(x, c("Ticker", "Date"), c(1L, -1L))   # 최신이 먼저 (.cons_history 규약)
  V <- metric

  # --- W0: 최신 N행 (현행 결함) ---
  w0 <- x[, {
    v <- get(V)[seq_len(min(.N, n_take))]
    .(latest = get(V)[1L], avg = mean(v), n_used = length(v),
      span = as.integer(Date[1L] - Date[min(.N, n_take)]), nd = uniqueN(v))
  }, by = Ticker]

  # --- W1: 연속-런 dedup 후 최신 N런 ---
  # 최신순 정렬 상태에서 rleid = 런 id. 각 런의 대표값 = 그 런의 값(불변),
  # 대표일 = 런 안에서 **가장 이른** 날짜 = 그 분기값이 처음 관측된 가용일.
  w1 <- x[, {
    r <- rleid(get(V))
    keep <- !duplicated(r)                 # 각 런의 첫 행(= 최신순이므로 런의 마지막 관측일)
    vv <- get(V)[keep]
    dd <- Date[keep]
    k  <- seq_len(min(length(vv), n_take))
    # 창 하단 = 가장 오래된 채택 런의 **시작일**(그 값이 처음 나타난 날)
    oldest_run <- r[keep][max(k)]
    start_oldest <- min(Date[r == oldest_run])
    .(latest = vv[1L], avg = mean(vv[k]), n_used = length(k),
      span = as.integer(dd[1L] - start_oldest), nd = uniqueN(vv[k]),
      n_runs_avail = length(vv))
  }, by = Ticker]

  # --- W2 / W3: 달력 lag ---
  cal <- function(step_m) {
    anchors <- vapply(seq_len(n_take) - 1L,
                      function(i) as.numeric(add_months(sig_d, -i * step_m)),
                      numeric(1))
    anchors <- as.Date(anchors, origin = "1970-01-01")
    parts <- lapply(seq_along(anchors), function(i) {
      a <- anchors[i]
      y <- x[Date <= a]
      if (!nrow(y)) return(NULL)
      # 최신순 정렬이므로 각 Ticker 첫 행 = a 시점 최신값
      y[, .(slot = i, v = get(V)[1L], d = Date[1L]), by = Ticker]
    })
    parts <- parts[!vapply(parts, is.null, logical(1))]
    if (!length(parts)) return(NULL)
    p <- rbindlist(parts)
    p[, .(latest = v[slot == 1L][1L], avg = mean(v), n_used = .N,
          span = as.integer(max(d) - min(d)), nd = uniqueN(v)), by = Ticker]
  }
  w2 <- cal(3L); w3 <- cal(4L)

  summ <- function(dt, tag) {
    if (is.null(dt) || !nrow(dt)) return(NULL)
    d <- dt[!is.na(avg) & !is.na(latest)]
    data.table(design = tag, metric = metric, sig_date = sig_d, n_take = n_take,
               n_ticker = nrow(d),
               frac_avg_eq_latest = mean(abs(d$avg - d$latest) < 1e-12),
               median_distinct = median(d$nd), mean_distinct = mean(d$nd),
               median_span_days = median(d$span),
               p95_span_days = as.integer(quantile(d$span, .95)),
               max_span_days = max(d$span),
               median_n_used = median(d$n_used))
  }
  rbindlist(list(summ(w0, "W0_rows_current"), summ(w1, "W1_run_dedup"),
                 summ(w2, "W2_cal_3m"), summ(w3, "W3_cal_4m")), fill = TRUE)
}

sig_dates <- as.Date(c("2006-06-30", "2010-06-30", "2014-06-30",
                       "2018-06-29", "2022-06-30", "2024-06-28",
                       "2011-03-15", "2019-09-30"))  # 3월 = Dec런(121일) 안쪽 = W2 취약 구간

all <- list()
for (spec in list(list(m = "sue", n = 4L), list(m = "esbr", n = 3L))) {
  h <- as.data.table(read_parquet(file.path(ROOT, ".cache/consensus",
                                            paste0(spec$m, ".parquet"))))
  if (!inherits(h$Date, "Date")) h[, Date := as.Date(Date)]
  for (k in seq_along(sig_dates)) {
    all[[length(all) + 1L]] <- bake(h, spec$m, sig_dates[k], spec$n)
  }
}
res <- rbindlist(all, fill = TRUE)
fwrite(res, file.path(OUT, "p3_design_bakeoff.csv"))

agg <- res[, .(n_sig = .N,
               frac_eq_latest = mean(frac_avg_eq_latest),
               median_distinct = median(median_distinct),
               median_span = median(median_span_days),
               p95_span = median(p95_span_days),
               max_span = max(max_span_days),
               min_cover = min(n_ticker)),
           by = .(metric, design)][order(metric, design)]
fwrite(agg, file.path(OUT, "p3_design_agg.csv"))
cat("\n==== 설계별 집계 (8 sig_date 평균) ====\n"); print(agg)

cat("\n==== 취약 구간 상세: 2011-03-15 (12/1런 = 121일 안쪽) ====\n")
print(res[sig_date == as.Date("2011-03-15"),
          .(metric, design, frac_avg_eq_latest, median_distinct,
            median_span_days, n_ticker)])
cat("\n[p3] 선택 기준: frac_avg_eq_latest 가 1.0 에서 충분히 내려가고,\n")
cat("     median_distinct 가 n_take 에 가깝고, span 이 분기 격자와 정합하며,\n")
cat("     max_span 이 폭주하지 않을 것.\n")
