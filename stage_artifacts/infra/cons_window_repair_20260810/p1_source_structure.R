#==============================================================================
# p1_source_structure.R — FQ-218 (A) 설계 근거 실측
#
# 질문: .cons_history() 의 창을 무엇으로 재정의해야 하는가.
#       선택지 3종(분기 리샘플 / 달력 lag / 고유값)의 전제가 원천에서 성립하는지
#       **먼저 재고** 설계를 고른다. 가정하고 재기 시작하면 안 된다
#       (feedback-assert-input-shape-before-measuring).
#
# 측정:
#   S1. 스키마 — 분기/발표 식별자 컬럼이 실제로 있는가 (분기 리샘플 가능성)
#   S2. 관측 단위 — 행 간격 (일간인가)
#   S3. 값 변경 리듬 — 값이 *바뀌는* 간격 (고유값 선택지의 전제)
#   S4. 값 변경이 분기 리듬인가 (change 간격 분포 · 월별 change 집중도)
#
# 읽기 전용. factor_db 재빌드 없음.
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
ROOT <- gsub("\\\\", "/", ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/infra/cons_window_repair_20260810")
dir.create(OUT, recursive = TRUE, showWarnings = FALSE)

metrics <- c("sue", "esbr", "revenue_fy1", "op_profit_fy1")
rows <- list(); chg <- list()

for (metric in metrics) {
  p <- file.path(ROOT, ".cache/consensus", paste0(metric, ".parquet"))
  if (!file.exists(p)) { cat(sprintf("[SKIP] %s 파일 부재\n", metric)); next }
  h <- as.data.table(read_parquet(p))

  cat(sprintf("\n===== %s =====\n", metric))
  cat(sprintf("  컬럼: %s\n", paste(names(h), collapse = ", ")))
  cat(sprintf("  클래스: %s\n", paste(sapply(h, function(x) class(x)[1]), collapse = ", ")))
  if (!inherits(h$Date, "Date")) h[, Date := as.Date(Date)]
  h <- h[!is.na(get(metric))]
  cat(sprintf("  행=%s  티커=%d  기간 %s .. %s\n",
              format(nrow(h), big.mark = ","), uniqueN(h$Ticker),
              min(h$Date), max(h$Date)))

  # S2: 관측 간격
  setorderv(h, c("Ticker", "Date"))
  h[, gap := as.integer(Date - shift(Date)), by = Ticker]
  g <- h[!is.na(gap), gap]

  # S3: 값 *변경* 간격 — 이전 행 대비 값이 달라진 지점만
  h[, prev_v := shift(get(metric)), by = Ticker]
  h[, changed := !is.na(prev_v) & abs(get(metric) - prev_v) > 1e-12]
  ch <- h[changed == TRUE]
  setorderv(ch, c("Ticker", "Date"))
  ch[, chg_gap := as.integer(Date - shift(Date)), by = Ticker]
  cg <- ch[!is.na(chg_gap), chg_gap]

  # 티커당 연 변경 횟수 (분기 리듬이면 ~4)
  yrs <- h[, .(span_y = as.numeric(max(Date) - min(Date)) / 365.25,
               n_chg = sum(changed, na.rm = TRUE)), by = Ticker][span_y >= 2]
  yrs[, per_year := n_chg / span_y]

  cat(sprintf("  [S2] 관측 간격(일): median=%d  p25=%d  p75=%d  p95=%d\n",
              median(g), as.integer(quantile(g, .25)), as.integer(quantile(g, .75)),
              as.integer(quantile(g, .95))))
  cat(sprintf("  [S3] 값변경 간격(일): n=%s  median=%d  p25=%d  p75=%d  p90=%d\n",
              format(length(cg), big.mark = ","), median(cg),
              as.integer(quantile(cg, .25)), as.integer(quantile(cg, .75)),
              as.integer(quantile(cg, .90))))
  cat(sprintf("  [S3] 변경률: 전체 행 중 값이 바뀐 비율 = %.4f\n",
              mean(h$changed, na.rm = TRUE)))
  cat(sprintf("  [S4] 티커당 연간 변경횟수: median=%.2f  p25=%.2f  p75=%.2f  (분기 리듬이면 ~4)\n",
              median(yrs$per_year), quantile(yrs$per_year, .25), quantile(yrs$per_year, .75)))

  # S4b: 변경이 몰리는 월 (분기 발표월 3/5/8/11 집중이면 분기 리듬)
  mo <- ch[, .N, by = .(m = month(Date))][order(m)]
  mo[, frac := N / sum(N)]
  cat("  [S4b] 값변경 월분포: ")
  cat(paste(sprintf("%d월=%.3f", mo$m, mo$frac), collapse = " "), "\n")

  rows[[metric]] <- data.table(
    metric = metric, n_rows = nrow(h), n_ticker = uniqueN(h$Ticker),
    date_min = min(h$Date), date_max = max(h$Date),
    obs_gap_median = median(g), obs_gap_p75 = as.integer(quantile(g, .75)),
    chg_gap_median = median(cg), chg_gap_p25 = as.integer(quantile(cg, .25)),
    chg_gap_p75 = as.integer(quantile(cg, .75)),
    chg_rate = mean(h$changed, na.rm = TRUE),
    chg_per_year_median = median(yrs$per_year),
    has_period_col = any(grepl("period|fy|quarter|qtr|fiscal|announce|report",
                               names(h), ignore.case = TRUE)))
  chg[[metric]] <- cbind(metric = metric, mo)
}

s <- rbindlist(rows)
fwrite(s, file.path(OUT, "p1_source_structure.csv"))
fwrite(rbindlist(chg), file.path(OUT, "p1_change_month_dist.csv"))
cat("\n---- 요약 ----\n"); print(s)
cat("\n[p1] 판정 규칙:\n")
cat("  obs_gap_median 1~5일  ⇒ 원천 일간 (확정 진단 재확인)\n")
cat("  chg_gap_median ~90일  ⇒ 값 변경이 분기 리듬 ⇒ '고유값' 선택지 성립\n")
cat("  chg_gap_median 짧음   ⇒ 상시 개정 ⇒ '고유값' 붕괴, 달력 lag 필요\n")
