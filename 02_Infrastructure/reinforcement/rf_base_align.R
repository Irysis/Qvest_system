#==============================================================================
# rf_base_align.R — 기저 신호를 셀 엔진의 월말 격자에 맞춘다(달 스냅 · 2026-11-11 · 판 2 구축 S1)
#
# 왜: 셀 엔진(rf_cell_engine.R)의 시그널일은 월말 거래일이고, 기저 엔진 산출은 날짜가 **정확히 같은** 행에만
#   붙었다. 신호일 격자가 월말이 아닌 엔진(60거래일 · 주간 · 일간)은 신호 대부분이 조용히 버려졌다.
#   실측 11-11: 1908.01112(60거래일 격자) = 신호일 110개 중 월말과 겹치는 날 1개 → 측정이 하루로 섰다
#   (04_Research/01_reports/portfolio_paper_layer_split_20261112/README.md §2-1).
#
# 규칙(달 스냅 · month_snap_v1) — 모수 없음:
#   월말 거래일 d 의 기저 = 구간 (직전 월말 거래일, d] 안의 엔진 신호일 가운데 **가장 늦은 날**의 패널.
#   그 구간에 엔진 신호가 없으면 그 달은 기저가 없다(앞 달 신호를 이월하지 않는다 — 보유 이월은 하네스의 일).
#   · 월말 거래일에 신호를 내는 엔진(월간 · 분기 · 연간)은 항등 사상이다 → 수정 전후 비트 동일.
#   · 신호의 나이는 구조상 한 달 미만이다. 유효 기간 · 만료 상수가 없다(사후 자유도 0).
#
# PIT: 엔진 신호일 s 를 뒤의 날짜 d(s ≤ d)로만 옮긴다 — 더 오래된 정보를 쓰는 방향뿐이다(C2 · C5 방향 안전).
#   거래일이 아닌 날짜의 신호(s 가 그 달 마지막 거래일 뒤)는 **다음 달** 월말로 간다(s ≤ d 를 깨지 않는다).
#   마지막 월말 뒤의 신호는 갈 곳이 없어 빠진다(종전에도 읽히지 않았다).
#
# 계약:
#   rf_base_month_snap(b, cal) → list(panel, diag)
#     b   = data.table(Date, Ticker, .base_sig)  — 기저 엔진 원산출(캐시에 든 모양 그대로)
#     cal = 거래일 벡터(Date) — 셀 엔진의 패널 달력(unique(DT$Date))
#     panel = data.table(Date, Ticker, .base_sig) — Date 가 월말 거래일로 옮겨진 패널(입력은 바꾸지 않는다)
#     diag  = list(rule, n_engine_dates, n_cell_dates, n_identity, n_moved, n_superseded, n_dropped_tail, n_offcal,
#                  max_lag_td, median_lag_td, first_engine_date, last_engine_date)   (지연 = 거래일 수)
#       n_superseded > 0 = 한 달에 신호가 둘 이상(주간 · 일간 격자 — 셀 경로는 월말 표본) · n_offcal > 0 = 달력에 없는 날짜의 신호
#       (그 달 마지막 거래일 뒤 도장이면 한 달 늦게 가거나 다음 달 신호에 덮인다) — 둘 다 소비자(상설 판 코어)가 판정 전에 본다.
#   검사 = 08_Tests/reinforcement/test_rf_base_align.R
#==============================================================================
suppressMessages(library(data.table))

RF_BASE_ALIGN_RULE <- "month_snap_v1"

rf_base_month_snap <- function(b, cal) {
  if (!data.table::is.data.table(b) || !all(c("Date", "Ticker", ".base_sig") %in% names(b)))
    stop("[rf_base_align] 기저 패널은 data.table(Date, Ticker, .base_sig) 여야 한다")
  if (!inherits(b$Date, "Date")) stop("[rf_base_align] 기저 패널 Date 가 Date 형이 아니다")
  cal <- sort(unique(as.Date(cal)))
  if (!length(cal)) stop("[rf_base_align] 거래일 달력이 비었다")
  ## 월말 거래일 = 달마다 달력의 마지막 날(셀 엔진 .sig_dates 와 같은 정의 — 마지막 부분월 포함)
  me <- cal[!duplicated(format(cal, "%Y%m"), fromLast = TRUE)]
  E <- sort(unique(b$Date))
  E <- E[!is.na(E)]
  if (!length(E)) stop("[rf_base_align] 기저 패널에 날짜가 없다")
  ## 엔진 신호일 s → 목표 월말 d(s) = s 이상인 첫 월말 거래일(정수 일 번호 비교)
  ei <- as.integer(E); mi <- as.integer(me)
  pos <- findInterval(ei, mi, left.open = TRUE) + 1L          # mi[pos] = ei 이상인 첫 월말(ei == mi 이면 그 자리)
  ok <- pos <= length(mi)
  map <- data.table::data.table(s = E[ok], d = me[pos[ok]])
  n_tail <- sum(!ok)
  ## 같은 월말로 가는 신호가 여럿이면 가장 늦은 것만 남긴다
  data.table::setorder(map, d, s)
  keep <- map[, .(s = s[.N], n = .N), by = d]
  n_super <- sum(keep$n - 1L)
  ## 지연(거래일 수) — 달력 안 위치 차. 달력에 없는 신호일은 그 날 이상인 첫 거래일 위치로 센다
  ##   (남은 신호는 전부 s ≤ d 이고 d 는 달력 안이므로 위치 차는 0 이상이다)
  ci <- as.integer(cal)
  n_offcal <- sum(!(as.integer(E) %in% ci))                    # 거래일 달력에 없는 엔진 신호일 수
  lag <- match(as.integer(keep$d), ci) - (findInterval(as.integer(keep$s), ci, left.open = TRUE) + 1L)
  out <- b[keep, on = .(Date = s), nomatch = NULL]            # 고른 신호일의 행만 · 열 d = 목표 월말
  out[, Date := d]
  out <- out[, .(Date, Ticker, .base_sig)]
  data.table::setorder(out, Date)
  list(panel = out,
       diag = list(rule = RF_BASE_ALIGN_RULE, n_engine_dates = length(E), n_cell_dates = nrow(keep),
                   n_identity = sum(keep$s == keep$d), n_moved = sum(keep$s != keep$d), n_superseded = n_super,
                   n_dropped_tail = n_tail, n_offcal = n_offcal, max_lag_td = if (nrow(keep)) max(lag) else 0L,
                   median_lag_td = if (nrow(keep)) as.numeric(stats::median(lag)) else 0,
                   first_engine_date = format(min(E)), last_engine_date = format(max(E))))
}
