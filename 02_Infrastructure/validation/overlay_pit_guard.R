# =============================================================================
# overlay_pit_guard.R — 오버레이 신호 타이밍 PIT 가드 (2026-07-06, 도훈 지시)
# =============================================================================
# 사건(재발 방지 대상): BearProb 오버레이가 신호를 `Date < anchor_date`로 로드했으나
#   anchor_date = 홀딩월(return_ym)의 *다음달* 첫 거래일(간격 ~31일) → 홀딩월 '말' 정보로
#   그 홀딩월 수익을 스케일 = ~1개월 동월 look-ahead. (faith 오버레이 버그 재발)
#   증상은 placebo/OOS/DSR/subperiod 전부 통과, **lag1 스트레스 + strict-PIT A/B만 판별**.
#
# 원칙(C5 구체화): 오버레이 신호는 **홀딩월이 시작되기 전** 데이터로만 계산·적용한다.
#   - 홀딩월 = 수익(ret)이 실제로 벌리는 캘린더 월.
#   - clean 컷오프 = first-day-of-holding-month. 신호는 Date < 이 값 만 사용.
#   - 패널별 홀딩월 식별:
#       aggregate(period_returns_*): 홀딩월 = return_ym.            컷오프 = ymd(paste0(return_ym,"-01"))
#       holdings(alpha_scores_*):    홀딩월 = month(Date)+1 (β-scan offset+1). 컷오프 = floor_month(Date) %m+% months(1)
#   - anchor_date/realized_ym(라벨)로 컷오프를 잡지 말 것(홀딩월보다 뒤라 look-ahead).
#
# 사용법(오버레이 리서치 의무):
#   source("02_Infrastructure/validation/overlay_pit_guard.R")
#   cutoff <- overlay_signal_cutoff(holding_ym)            # 또는 holdings_cutoff(Date)
#   assert_overlay_pit(my_used_cutoff, cutoff)             # HARD: 컷오프가 홀딩월 시작 전인지
#   ab <- overlay_lookahead_ab(metric_current, metric_strict)   # current≫strict면 look-ahead 의심
#   # + lag1 스트레스: 신호를 shift(1) 적용판이 base 대비 붕괴하는지 확인(유일 판별검정)
# =============================================================================
suppressWarnings(suppressMessages({ library(data.table); if(!requireNamespace("lubridate", quietly=TRUE)) NULL }))

# 홀딩월(YYYY-MM) 시작일 — 신호는 이 시점 '전' 데이터만 사용 가능
overlay_signal_cutoff <- function(holding_ym) as.Date(paste0(as.character(holding_ym), "-01"))

# holdings 패널: Date(month(D)) → 홀딩월 = month(D)+1 시작일 (β-scan offset+1 실증)
holdings_signal_cutoff <- function(panel_date) {
  d <- as.Date(panel_date)
  fm <- as.Date(format(d, "%Y-%m-01"))
  # +1개월
  y <- as.integer(format(fm, "%Y")); m <- as.integer(format(fm, "%m"))
  m2 <- m + 1L; y2 <- y + (m2 - 1L) %/% 12L; m2 <- ((m2 - 1L) %% 12L) + 1L
  as.Date(sprintf("%04d-%02d-01", y2, m2))
}

# HARD assert: 사용한 신호 컷오프가 홀딩월 시작 이후면 = look-ahead → stop()
assert_overlay_pit <- function(used_cutoff_dates, holding_month_start_dates, label = "overlay") {
  u <- as.Date(used_cutoff_dates); h <- as.Date(holding_month_start_dates)
  bad <- which(is.finite(u) & is.finite(h) & u > h)
  if (length(bad) > 0) {
    stop(sprintf(paste0("[overlay_pit_guard] ★LOOK-AHEAD 차단: %s 신호 컷오프가 홀딩월 시작 이후 %d/%d행. ",
                        "예: cutoff=%s > holding_start=%s. 오버레이 신호는 홀딩월 시작 전 데이터만 사용하라 ",
                        "(anchor_date/realized_ym로 컷오프 잡지 말 것)."),
                 label, length(bad), length(u), as.character(u[bad[1]]), as.character(h[bad[1]])))
  }
  invisible(TRUE)
}

# strict-PIT A/B: 현재 타이밍 성과가 strict보다 rel_tol 이상 좋으면 look-ahead 의심
overlay_lookahead_ab <- function(metric_current, metric_strict, metric_name = "metric",
                                 rel_tol = 0.05, higher_is_better = TRUE) {
  d <- if (higher_is_better) (metric_current - metric_strict) else (metric_strict - metric_current)
  infl <- d / abs(metric_strict)
  flag <- is.finite(infl) && infl > rel_tol
  msg <- sprintf("[overlay_pit_guard] %s: current=%.4f strict=%.4f 인플레=%.1f%% → %s",
                 metric_name, metric_current, metric_strict, 100 * infl,
                 if (flag) "★LOOK-AHEAD 의심 — strict-PIT 값으로 재판정 필수" else "clean")
  list(inflation = infl, lookahead_suspected = flag, message = msg)
}

if (sys.nframe() == 0L) cat("[overlay_pit_guard] Loaded — overlay_signal_cutoff / holdings_signal_cutoff / assert_overlay_pit / overlay_lookahead_ab\n")
