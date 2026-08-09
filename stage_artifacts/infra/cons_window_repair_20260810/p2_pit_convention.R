#==============================================================================
# p2_pit_convention.R — FQ-218 (A) PIT 확보의 전제 검사
#
# ★작업 명세 경고: "분기 리샘플 시 발표일(가용 시점) 기준이어야지 분기 종료일
#   기준이면 미래참조". p1 에서 값 변경이 4/6/9/12 월에 몰리는 것을 봤는데,
#   6/9/12 는 **분기 종료월**과 겹친다. 그래서 창을 고르기 전에
#   "변경일 = 가용일인가 분기말인가" 를 먼저 판별한다.
#
# 판별 축:
#   T1. 변경일의 **일(day-of-month)** 분포 — 말일에 몰리면 분기말 스탬프 의심
#   T2. 변경일이 **거래일**인가 (분기말 스탬프면 비거래일에도 찍힐 수 있음)
#   T3. 한국 분기 발표 달력(대략 4/5·8·11월) 대비 위치
#   T4. ★결정적: 변경일 이후 **당일/직후 수익률**과 변경 방향의 관계.
#       변경일이 진짜 가용일이면 그 정보는 아직 가격에 안 실렸거나 실리는 중 →
#       사후 수익과 강한 동시 관계가 나오면 스탬프(미래참조) 의심.
#       (약한 판별이므로 T1~T3 를 주 근거로 쓰고 T4 는 보조.)
#
# 읽기 전용.
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
ROOT <- gsub("\\\\", "/", ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/infra/cons_window_repair_20260810")

res <- list()
for (metric in c("sue", "esbr")) {
  h <- as.data.table(read_parquet(file.path(ROOT, ".cache/consensus",
                                            paste0(metric, ".parquet"))))
  if (!inherits(h$Date, "Date")) h[, Date := as.Date(Date)]
  h <- h[!is.na(get(metric))]
  setorderv(h, c("Ticker", "Date"))
  h[, prev_v := shift(get(metric)), by = Ticker]
  ch <- h[!is.na(prev_v) & abs(get(metric) - prev_v) > 1e-12]

  cat(sprintf("\n===== %s : 변경 이벤트 %s건 =====\n", metric,
              format(nrow(ch), big.mark = ",")))

  # T1: day-of-month 분포
  ch[, dom := mday(Date)]
  # 정확한 월말일
  ch[, month_end := as.Date(cut(Date, "month")) + 31L]
  ch[, month_end := as.Date(format(month_end, "%Y-%m-01")) - 1L]
  ch[, days_to_eom := as.integer(month_end - Date)]
  dom_tab <- ch[, .N, by = dom][order(dom)]
  top_dom <- dom_tab[order(-N)][1:6]
  cat("  [T1] 변경일 day-of-month 상위6: ",
      paste(sprintf("%d일=%.3f", top_dom$dom, top_dom$N / nrow(ch)), collapse = " "), "\n")
  cat(sprintf("  [T1] 월말(마지막 3일) 발생 비율 = %.4f  (균일이면 ~0.10)\n",
              mean(ch$days_to_eom <= 2)))
  cat(sprintf("  [T1] 월초(1~5일) 발생 비율     = %.4f\n", mean(ch$dom <= 5)))

  # T2: 요일 (주말에 찍히면 스탬프 = 거래일 아님)
  wd <- ch[, .N, by = .(w = weekdays(Date))]
  cat("  [T2] 요일분포: ", paste(sprintf("%s=%d", wd$w, wd$N), collapse = " "), "\n")
  cat(sprintf("  [T2] 주말 발생 = %d건\n",
              sum(wd$N[wd$w %in% c("Saturday", "Sunday", "토요일", "일요일")])))

  # T3: 월×일 조합 최빈 — 특정 고정일이면 벤더 스케줄
  ch[, md := sprintf("%02d-%02d", month(Date), mday(Date))]
  md_tab <- ch[, .N, by = md][order(-N)][1:10]
  cat("  [T3] (월-일) 최빈10: ",
      paste(sprintf("%s:%.3f", md_tab$md, md_tab$N / nrow(ch)), collapse = " "), "\n")
  # 연도별로 같은 (월-일)이 반복되면 = 벤더 일괄 갱신 스케줄
  ch[, yr := year(Date)]
  per_yr <- ch[, .(n_distinct_dates = uniqueN(Date)), by = yr][order(yr)]
  cat(sprintf("  [T3] 연도당 고유 변경일 수: median=%.1f (분기 일괄이면 ~4)\n",
              median(per_yr$n_distinct_dates)))

  res[[metric]] <- data.table(
    metric = metric, n_change = nrow(ch),
    frac_month_end3 = mean(ch$days_to_eom <= 2),
    frac_month_start5 = mean(ch$dom <= 5),
    n_weekend = sum(wd$N[wd$w %in% c("Saturday", "Sunday", "토요일", "일요일")]),
    median_distinct_change_dates_per_year = median(per_yr$n_distinct_dates),
    top_md = md_tab$md[1], top_md_frac = md_tab$N[1] / nrow(ch))
}
out <- rbindlist(res)
fwrite(out, file.path(OUT, "p2_pit_convention.csv"))
cat("\n---- 요약 ----\n"); print(out)
cat("\n[p2] 해석:\n")
cat("  연도당 고유 변경일 ~4 이고 (월-일) 이 소수에 집중 ⇒ **벤더 분기 일괄 갱신**.\n")
cat("  이 경우 변경일 = 패널에 값이 나타난 날 = 가용일이며, 분기말 스탬프와 구분된다.\n")
cat("  단 분기말(6/30, 9/30, 12/31)에 집중되면 **스탬프 의심** — 하류 창 설계에서\n")
cat("  추가 lag 를 물려야 한다.\n")
