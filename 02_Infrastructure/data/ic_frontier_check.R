#==============================================================================
# ic_frontier_check.R — 월별 IC 프론티어 상시 감시 (P3, 2026-07-26)
#
# 문제:
#   factor_ic_monthly.parquet 는 월말 factor_db 재빌드 뒤 compute_all_factor_ic_monthly()
#   가 자동 갱신한다. 이 체인(월말 cron → factor_db 월말 스냅샷 → IC 재계산)이 실패하면
#   IC 프론티어가 조용히 뒤처진다. 기존 registry 신선도 축(Usable_Date 캘린더 lag ≤ 40일)은
#   이 실패를 최대 ~5주까지 FRESH 로 통과시킨다 — 실측(2026-07-26): Usable_Date max
#   2026-06-30, lag 26일 → FRESH. 7/31 재빌드가 통째로 실패해도 9월 초까지 FRESH.
#   "며칠 지났나"와 "산출 가능한 월을 다 산출했나"는 다른 명제다.
#
# 판정 규약 (compute_all_factor_ic_monthly() 의 incomplete-terminal-pair guard 와 동일 operand):
#   guard (factor_db_builder.R:1543-1568) 는 pair (t, t+1) 을 2조건 OR 로 버린다
#     ① cal_end(month(sig_d_t1)) > today                 ... 달력 미종료
#     ② sig_d_t1 < max(RAWDATA$Date[month == month(sig_d_t1)])  ... 그달 RAWDATA 최종 거래일 미달
#   즉 pair 가 살아남는(= IC 가 산출되는) 조건은 ①,② 둘 다 거짓.
#   본 감시는 같은 두 operand(달력 종료 여부 · 그달 RAWDATA 최종 거래일)로 역방향을 푼다:
#     forward month F = RAWDATA 에 존재하는 월 중 cal_end(F) <= today 인 최신 월   (①의 부정)
#     기대 프론티어 월 E = RAWDATA 상 F 바로 앞 월
#     기대 프론티어 Date = max(RAWDATA$Date[month == E])                          (②와 동일 operand)
#   월말 재빌드가 정상 수행되면 factor_db_{F}.parquet 의 sig 가 m_last(F) 가 되어 guard 를
#   통과하고, IC 는 Date = m_last(E) 까지 채워진다. 따라서 IC max(Date) < m_last(E) = 체인 지연.
#
#   ★중복 구현 금지: 정본 판정부는 factor_db/ic_pair_completeness.R (P1 추출분) 이며
#     본 파일은 `.icfc_pair_complete` 로 **위임**한다(아래 .ICFC_GUARD 참조).
#     전역 이름을 만들지 않는다 — 같은 이름 미러링이 실제 충돌을 냈다(그 절 주석 참조).
#
# 오탐 방지 (당월 진행 중 = 정상):
#   오늘이 2026-07-26 이면 F=2026-06, E=2026-05 → IC 가 2026-05 에 서 있는 것이 정상이다.
#   7월 IC(Date=2026-07-31)는 8월 수익이 있어야 산출되므로 기대치가 아니다.
#
# 유예 (grace):
#   E 가 산출 가능해지는 시점 = cal_end(F) + 1일. 월말 cron → factor_db 빌드 → IC 재계산은
#   시간이 걸리므로(실측 재빌드 수 시간) grace_days(기본 3일) 안에서는 경보하지 않는다.
#
# 소비처: 02_Infrastructure/data/cache_freshness_audit.R (registry 엔트리
#   .cache/factor_db/factor_ic_monthly.parquet 에 부착되는 "::frontier" 결과 1건).
#==============================================================================
suppressPackageStartupMessages({
  library(jsonlite)
  library(arrow)
  library(data.table)
})

if (!exists("PROJECT_ROOT")) {
  PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR",
                             Sys.getenv("QM_ROOT", getwd()))
}

if (!exists("%||%")) {
  `%||%` <- function(a, b) if (is.null(a)) b else a
}

# 달력상 그 달의 마지막 날 (guard 의 cal_end_t1 과 동일 산식)
.ic_cal_end <- function(d) {
  seq(as.Date(format(d, "%Y-%m-01")), by = "month", length.out = 2L)[2L] - 1L
}

# ─── guard 술어 위임 (2026-07-26 통합검증에서 수리) ──────────────────────────
# 이 파일은 P1 추출 전에 작성돼 술어를 `.ic_pair_complete` 라는 **같은 이름**으로
# 미러링했고, 위임 훅은 존재하지도 않는 이름(`fdb_ic_pair_complete`)을 찾고 있었다.
# P1 이 실제로 export 한 이름은 `.ic_pair_complete` — 즉 두 파일이 같은 이름을 서로
# 다른 시그니처로 정의하는 상태였다(동명 함수 2파일 함정,
# memory project-us-incremental-parser-promoted-20260725).
#
# 실측 충돌 (2026-07-26, 한 세션에 둘 다 source):
#   · builder → audit 순: 빌더 호출부가 `ERROR: unused argument (raw_month_last=)`
#     → pair 루프의 tryCatch 가 전건 삼켜 IC 전량 skip (이어서 setorder 에서 abort).
#   · audit → builder 순: 프론티어의 위치인자 호출이 P1 시그니처에 잘못 바인딩돼
#     반환 list 에 isTRUE() 가 걸려 `guard_agrees` 가 **항상 FALSE** (조용한 오판정).
# 정본 판정부(ic_pair_completeness.R)를 **전용 환경에 적재해 위임**한다 — 전역
# 이름을 만들지 않으므로 어느 순서로 source 해도 충돌하지 않고, 중복 구현도 사라진다.
.ICFC_GUARD <- local({
  e <- new.env(parent = globalenv())
  p <- file.path(PROJECT_ROOT, "02_Infrastructure/factor_db/ic_pair_completeness.R")
  if (file.exists(p)) {
    ok <- tryCatch({ sys.source(p, envir = e); TRUE }, error = function(err) FALSE)
    if (ok && exists(".ic_pair_complete", envir = e, inherits = FALSE)) e else NULL
  } else NULL
})

#' 길이-1 유한 Date 로 정규화. 실패·비유한(-Inf: 빈 벡터 max 의 산물)은 NA Date.
#' (정본 ic_pair_completeness.R::.ic_as_date1 과 같은 규약 — 여기선 파일 I/O 결과에도 쓴다)
.icfc_as_date1 <- function(x) {
  if (is.null(x) || length(x) == 0L) return(structure(NA_real_, class = "Date"))
  x <- x[1L]
  d <- suppressWarnings(tryCatch(as.Date(x), error = function(e) NA))
  if (length(d) != 1L || is.na(d) || !is.finite(as.numeric(d))) {
    return(structure(NA_real_, class = "Date"))
  }
  as.Date(d)
}

#' pair 완결 술어 — guard 2조건 OR 의 부정. (전역 이름 미생성: `.icfc_` 접두)
#' 정본이 있으면 위임, 없으면 같은 규약을 미러링(fail-safe).
.icfc_pair_complete <- function(sig_d_t1, raw_dates, today = Sys.Date()) {
  sig_d_t1 <- .icfc_as_date1(sig_d_t1)
  # fail-closed: sig 판정 불가면 '완결'이 아니다 (정본 .ic_pair_complete 와 동일 규약).
  # 미러가 이 분기를 안 갖고 있으면 NA sig 에서 as.Date("NA-01") → seq() 로 죽어,
  # 위임이 끊긴 순간(폴백 가동) 판정이 크래시로 바뀐다.
  if (is.na(sig_d_t1)) return(FALSE)
  m_t1 <- format(sig_d_t1, "%Y-%m")
  in_m <- raw_dates[format(raw_dates, "%Y-%m") == m_t1]
  raw_m_last <- if (length(in_m) > 0L) max(in_m) else as.Date(NA)       # ②
  if (!is.null(.ICFC_GUARD)) {
    return(isTRUE(.ICFC_GUARD$.ic_pair_complete(
      sig_d_t1, today = today, raw_month_last = raw_m_last)$complete))
  }
  cal_end_t1 <- .ic_cal_end(sig_d_t1)                                   # ①
  file_partial <- !is.na(raw_m_last) && sig_d_t1 < raw_m_last
  !(cal_end_t1 > today || file_partial)
}

#' RAWDATA 거래일에서 월-말 거래일 시계열을 뽑는다 (Date 컬럼만 read — 421MB full-load 회피).
ic_load_raw_month_ends <- function(rawdata_path = NULL) {
  if (is.null(rawdata_path)) {
    rawdata_path <- file.path(PROJECT_ROOT, ".cache", "RAWDATA.parquet")
  }
  if (!file.exists(rawdata_path)) return(NULL)
  d <- tryCatch(
    as.data.table(read_parquet(rawdata_path, col_select = "Date")),
    error = function(e) NULL)
  if (is.null(d) || !("Date" %in% names(d))) return(NULL)
  dd <- sort(unique(as.Date(d$Date)))
  dd[!is.na(dd)]
}

#' 오늘 기준 기대 IC 프론티어.
#' @return list(expected_date, expected_month, forward_month, computable_since) 또는 NULL
ic_expected_frontier <- function(raw_dates, today = Sys.Date()) {
  if (is.null(raw_dates) || length(raw_dates) == 0L) return(NULL)
  raw_dates <- sort(unique(as.Date(raw_dates)))
  ym <- format(raw_dates, "%Y-%m")
  m_last <- tapply(raw_dates, ym, max)
  months <- sort(names(m_last))
  m_last_d <- as.Date(unname(unlist(m_last[months])), origin = "1970-01-01")

  # ① 달력 종료: cal_end(M) <= today 인 월만 forward month 후보
  cal_ends <- as.Date(vapply(months, function(m)
    as.character(.ic_cal_end(as.Date(paste0(m, "-01")))), character(1)))
  ok <- which(cal_ends <= today)
  if (length(ok) < 2L) return(NULL)

  fi <- max(ok)                 # forward month F (IC 의 t+1)
  ei <- fi - 1L                 # 기대 프론티어 월 E (IC 의 t)
  if (ei < 1L) return(NULL)

  list(
    expected_date    = unname(m_last_d[ei]),   # ② 와 동일 operand: m_last(E)
    expected_month   = unname(months[ei]),
    forward_month    = unname(months[fi]),
    forward_sig_date = unname(m_last_d[fi]),
    computable_since = unname(cal_ends[fi]) + 1L
  )
}

#' 월별 IC 프론티어 감시 본체.
#'
#' @param ic_path            factor_ic_monthly.parquet 경로 (기본 = registry 경로)
#' @param raw_dates          RAWDATA 거래일 벡터 (기본 = 파일에서 로드)
#' @param today              기준일 (테스트 주입용)
#' @param ic_max_date_override  IC max(Date) 강제 주입 — 위반 주입 테스트용
#'                              (실파일을 건드리지 않고 지연 시나리오를 재현)
#' @param grace_days         산출 가능 시점 이후 유예일 (기본 3)
#' @return list — cache_freshness_audit results 에 그대로 append 가능한 형태
ic_frontier_check <- function(ic_path = NULL,
                              raw_dates = NULL,
                              today = Sys.Date(),
                              ic_max_date_override = NULL,
                              grace_days = 3L) {
  rel <- ".cache/factor_db/factor_ic_monthly.parquet"
  if (is.null(ic_path)) ic_path <- file.path(PROJECT_ROOT, rel)

  res <- list(
    path = paste0(rel, "::frontier"),
    tier = 2L, schedule = "monthly",
    registered = TRUE, check = "ic_month_frontier"
  )

  # 실제 IC 프론티어
  ic_max <- if (!is.null(ic_max_date_override)) {
    .icfc_as_date1(ic_max_date_override)
  } else if (file.exists(ic_path)) {
    tryCatch({
      d <- as.data.table(read_parquet(ic_path, col_select = "Date"))
      suppressWarnings(max(as.Date(d$Date), na.rm = TRUE))
    }, error = function(e) as.Date(NA))
  } else as.Date(NA)

  # 0행 parquet 은 read 에 성공한다 — max(numeric(0)) = **-Inf** 이고 is.na(-Inf) 는 FALSE 라
  # 그대로 흘러가 format() 이 "-Inf", .mi() 가 NA, `if (lag_months < 0L)` 에서 abort 했다
  # (실측 2026-07-26: "missing value where TRUE/FALSE needed"). 판정 불가는 크래시가 아니라
  # UNKNOWN 으로 떨어져야 한다 — 감시기가 죽으면 소비처 tryCatch 가 사유를 삼킨다.
  ic_max <- .icfc_as_date1(ic_max)

  if (is.na(ic_max)) {
    res$status <- "IC_FRONTIER_UNKNOWN"; res$severity <- "WARN"
    res$note <- "IC parquet 부재/read 실패 — Date max 판정 불가"
    return(res)
  }

  if (is.null(raw_dates)) raw_dates <- ic_load_raw_month_ends()
  exp_f <- ic_expected_frontier(raw_dates, today = today)
  if (is.null(exp_f)) {
    res$status <- "IC_FRONTIER_UNKNOWN"; res$severity <- "WARN"
    res$note <- "RAWDATA 거래일 로드 실패 또는 완결월 < 2 — 기대 프론티어 산정 불가"
    res$ic_max_date <- format(ic_max)
    return(res)
  }

  # 규약 자기검증: 기대 프론티어의 forward pair 는 guard 를 통과해야 한다.
  res$guard_agrees <- .icfc_pair_complete(exp_f$forward_sig_date, raw_dates, today)

  ic_month <- format(ic_max, "%Y-%m")
  .mi <- function(m) {
    p <- as.integer(strsplit(m, "-")[[1]])
    p[1] * 12L + p[2]
  }
  lag_months <- .mi(exp_f$expected_month) - .mi(ic_month)
  days_since <- as.integer(today - exp_f$computable_since)

  res$ic_max_date        <- format(ic_max)
  res$ic_month           <- ic_month
  res$expected_month     <- exp_f$expected_month
  res$expected_date      <- format(exp_f$expected_date)
  res$forward_month      <- exp_f$forward_month
  res$computable_since   <- format(exp_f$computable_since)
  res$days_since_computable <- days_since
  res$lag_months         <- lag_months
  res$grace_days         <- as.integer(grace_days)

  if (lag_months < 0L) {
    # IC 가 기대보다 앞섬 = 미완결 forward month 를 완결로 기록했을 가능성
    # (guard 무력화 / 부분월 IC). 조용히 넘기면 안 되는 무결성 신호.
    res$status <- "IC_FRONTIER_AHEAD"; res$severity <- "WARN"
    res$note <- sprintf("IC max %s 가 기대 프론티어 %s 보다 앞섬 — 부분월 pair 기록 의심 (guard 점검)",
                        ic_month, exp_f$expected_month)
  } else if (lag_months == 0L) {
    res$status <- "IC_FRONTIER_CURRENT"; res$severity <- "OK"
    res$note <- sprintf("IC 프론티어 %s = 기대치 (당월 %s 진행 중 — 정상)",
                        ic_month, format(today, "%Y-%m"))
  } else if (days_since < grace_days) {
    res$status <- "IC_FRONTIER_GRACE"; res$severity <- "OK"
    res$note <- sprintf("%s 산출 가능 %d일 경과 (<유예 %d일) — 월말 재빌드 진행 중으로 간주",
                        exp_f$expected_month, days_since, as.integer(grace_days))
  } else if (lag_months == 1L) {
    res$status <- "IC_FRONTIER_LAG"; res$severity <- "WARN"
    res$note <- sprintf("IC 프론티어 %s, 기대 %s (1개월 지연, 산출가능 후 %d일) — 월말 재빌드/IC 재계산 체인 점검",
                        ic_month, exp_f$expected_month, days_since)
  } else {
    res$status <- "IC_FRONTIER_LAG"; res$severity <- "CRITICAL"
    res$note <- sprintf("IC 프론티어 %s, 기대 %s (%d개월 지연, 산출가능 후 %d일) — 체인 연속 실패",
                        ic_month, exp_f$expected_month, lag_months, days_since)
  }
  res
}

cat("[ic_frontier_check] Loaded.\n")
