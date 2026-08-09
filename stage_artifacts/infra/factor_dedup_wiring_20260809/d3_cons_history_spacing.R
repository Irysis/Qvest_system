#==============================================================================
# d3_cons_history_spacing.R — C10/C13 동일성이 "중복 등록"인가 "무력 창(defect)"인가
#
# 가설: .cons_history() 는 관측 행을 최신순으로 주고 하류가 x[1:4] 를 취한다.
#       원천 sue/esbr 이 **일간**이면 그 4행 = 4영업일 = 같은 분기값 4벌 ⇒
#       mean(4) == latest ⇒ C10 ≡ C01, C13 ≡ C04 가 **구조적으로 강제**된다.
#       (= 중복 등록이 아니라 롤링 창이 무력화된 결함. C15 와 같은 뿌리)
# 반증: 원천이 분기 간격이면 mean(4분기) != latest 여야 하고, 동일성은 다른 기전.
#
# 읽기만 한다 — factor_db 재빌드 없음.
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
OUT  <- file.path(ROOT, "stage_artifacts/infra/factor_dedup_wiring_20260809")

res <- list()
for (metric in c("sue", "esbr")) {
  p <- file.path(ROOT, ".cache/consensus", paste0(metric, ".parquet"))
  h <- as.data.table(read_parquet(p))
  if (!inherits(h$Date, "Date")) h[, Date := as.Date(Date)]
  h <- h[!is.na(get(metric))]
  cat(sprintf("\n===== %s : rows=%s  tickers=%s  date range %s .. %s\n",
              metric, format(nrow(h), big.mark = ","), uniqueN(h$Ticker),
              min(h$Date), max(h$Date)))

  # 관측 간격 (티커 내 연속 관측일 차)
  setorderv(h, c("Ticker", "Date"))
  h[, gap := as.integer(Date - shift(Date)), by = Ticker]
  g <- h[!is.na(gap), gap]
  cat(sprintf("  관측 간격(일): median=%d  mean=%.2f  p90=%d\n",
              median(g), mean(g), as.integer(quantile(g, 0.90))))

  # ★결정적 측정: 임의 sig_date 에서 .cons_history 규약대로 최신 4행을 뽑아
  #   mean(4) 와 latest 가 같은 티커 비율
  for (sig_d in as.Date(c("2010-06-30", "2018-06-29", "2024-06-28"))) {
    x <- h[Date <= sig_d]
    if (!nrow(x)) next
    setorderv(x, c("Ticker", "Date"), c(1L, -1L))   # 최신이 먼저 (규약 동일)
    n_take <- if (metric == "sue") 4L else 3L        # C10=4, C13=3
    s <- x[, {
      v <- get(metric)[seq_len(min(.N, n_take))]
      list(latest = get(metric)[1L], avg = mean(v),
           n_used = length(v),
           span_days = as.integer(Date[1L] - Date[min(.N, n_take)]),
           n_distinct = uniqueN(v))
    }, by = Ticker]
    same <- s[, mean(abs(avg - latest) < 1e-12)]
    cat(sprintf("  sig=%s  n_ticker=%4d  창 span 중앙=%3d일  창 내 고유값 중앙=%.1f  mean(%d)==latest 비율=%.4f\n",
                sig_d, nrow(s), median(s$span_days), median(s$n_distinct),
                n_take, same))
    res[[length(res) + 1L]] <- data.table(
      metric = metric, sig_date = sig_d, n_take = n_take, n_ticker = nrow(s),
      median_span_days = median(s$span_days),
      median_distinct_in_window = median(s$n_distinct),
      frac_avg_eq_latest = same)
  }
}
out <- rbindlist(res)
fwrite(out, file.path(OUT, "d3_cons_history_spacing.csv"))
cat("\n[d3] 판정 기준: frac_avg_eq_latest ~ 1.0 이고 span 이 분기(~90일)보다 훨씬 짧으면\n")
cat("     C10/C13 동일성 = 무력 창 결함(중복 등록 아님).\n")
print(out)
