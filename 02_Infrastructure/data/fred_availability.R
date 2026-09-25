# =============================================================================
# fred_availability.R — 해외(FRED)·ECOS 시계열 가용시점 층 (PIT C11 · 안 B · S0 기반)
# =============================================================================
# 근거: 04_Research/01_reports/pit_c11_20260924/PIT_C11_verdict_20260924.md
#         §② 계열별 lag 규약(원칙 a/b/c) · §⑤ 공통 코드 수리 지점 · §⑤ 안 B '가용시점 층'
#       06_Registry/decision_register.json PIT-C11-REMEDIATION(안 B 후 안 C) · PIT-C11-CONVENTIONS
# 규칙 정본: 06_Registry/fred_availability_rules.json — 오프셋·규칙 수치는 전부 그 파일에 있다.
#   이 파일에는 규칙 수치가 없다(하드코딩 금지). Python 동등판 = fred_availability.py (같은 규칙 파일·같은 결과,
#   08_Tests/data/test_fred_availability.R 가 교차 검사한다).
#
# 원칙: 관측마다 가용일(avail_date)을 붙이고, 관측일이 아니라 가용일로 결합한다.
#   avail_date(obs) = 그 관측이 '한국 d일 15:30 KST 결정'(판정서 ② 형태 a)에 쓰일 수 있는 첫 한국 거래일 d.
#   mode "decision_close"  : 형태 (a)·(c) — 한국 d 종가 결정 → avail_date ≤ d.
#                            월간 보유(c)는 수익 창이 실제로 시작하는 집행일(close_d_legacy=sig_d · close_t1=집행일)을
#                            kr_dates 로 넘긴다. 날짜 라벨(anchor·realized_ym)로 넘기지 말 것(pit.md C5 와 같은 원칙).
#   mode "exposure_return" : 형태 (b) — 노출을 한국 종가→종가 수익 r_t 에 곱함 → 결정 = 한국 t 직전 거래일 15:30
#                            → avail_date ≤ prev_kr(t). ★'1행 lag' 는 미국 t−1 을 들이므로 이 모드를 대신하지 못한다.
# fail-closed: 규칙 없는 계열·status≠active(DEXKOUS) = stop(). 알 수 없는 bound type = 규칙 로드 stop().
#   달력 밖으로 떨어지는 가용일 = NA = '아직 불가' → 결합되지 않는다.
#
# ── 인터페이스(다른 서브시스템이 쓴다 — 이름·인자 고정) ─────────────────────────────
#   fred_avail_rules(rules_path = NULL)                         규칙(검증된 list; 경로+mtime 캐시)
#   fred_series_rule(series_id, rules = NULL)                   한 계열 규칙(id 또는 aliases) — 미등록·금지 = stop
#   fred_kr_calendar(path = NULL)                               한국 거래일 Date 벡터(오름차순)
#   fred_avail_date(series_id, obs_date, kr_calendar = NULL, rules = NULL)   → Date 벡터(NA = 달력 밖·불가)
#   fred_avail_annotate(series_dt, series_id, kr_calendar = NULL, rules = NULL, date_col = "Date")
#                                                               → series_dt 사본 + avail_date·avail_basis 열
#   fred_decision_date(kr_dates, mode, kr_calendar = NULL)      결정 시점 한국 날짜(exposure_return = 직전 거래일)
#   fred_asof_join(kr_dates, series_dt, series_id, mode = c("decision_close","exposure_return"),
#                  kr_calendar = NULL, rules = NULL, date_col = "Date", value_col = "Value", extend_calendar = TRUE)
#       → data.table(kr_date, decision_date, value, obs_date, avail_date, avail_basis, series_id, mode,
#                    vintage, vintage_resolved)   kr_dates 입력 순서 그대로 1:1.
#         extend_calendar=TRUE: 달력 끝 이후의 kr_dates(평일)는 호출자가 거래일로 주장한 것으로 보고 달력에 붙인다
#         (라이브 당일 결정용). 붙였으면 attr(,"calendar_extended") 에 날짜가 남는다.
#   fred_join_violations(kr_date, obs_date, series_id, mode, kr_calendar = NULL, rules = NULL)
#       → 이미 결합된 (kr_date, obs_date) 쌍 중 가용일 위반 행(data.table; 0행 = 적합). pit_verify_fred_lag 용.
#   fred_avail_rules_meta(rules_path = NULL)                    list(version, md5, path, regime_key) — 측정 epoch 키
#
# 사용 예:
#   source(file.path(QM_ROOT, "02_Infrastructure/data/fred_availability.R"))
#   vix <- arrow::read_parquet(".cache/fred_macro.parquet")  # Series_ID == "VIXCLS" 만 골라서
#   j <- fred_asof_join(kr_month_ends, vix[vix$Series_ID == "VIXCLS", ], "VIXCLS", mode = "decision_close")
# =============================================================================

suppressWarnings(suppressMessages({ library(data.table); library(jsonlite) }))

.fa_or <- function(a, b) if (is.null(a) || length(a) == 0L) b else a

.fa_self_path <- function() {
  for (i in rev(seq_len(sys.nframe()))) {
    f <- tryCatch(sys.frame(i)$ofile, error = function(e) NULL)
    if (!is.null(f) && nzchar(f)) return(f)
  }
  NA_character_
}
.FA_SELF <- tryCatch(normalizePath(.fa_self_path(), winslash = "/", mustWork = FALSE),
                     error = function(e) NA_character_)

# 코드 루트(규칙 파일 위치): 옵션 > 이 파일 위치 > QM_ROOT. 워크트리 사본은 자기 규칙 파일을 쓴다.
.fa_code_root <- function() {
  o <- getOption("fred_avail.root")
  if (!is.null(o)) return(gsub("\\\\", "/", o))
  if (!is.na(.FA_SELF) && file.exists(.FA_SELF)) return(dirname(dirname(dirname(.FA_SELF))))
  r <- Sys.getenv("QM_ROOT", "")
  if (nzchar(r)) return(gsub("\\\\", "/", r))
  stop("[fred_avail] 코드 루트 미해석 — options(fred_avail.root=) 또는 QM_ROOT 설정")
}
# 데이터 루트(.cache): 옵션 > QM_ROOT > 코드 루트 (코드 루트 ≠ 데이터 루트일 수 있다 — 워크트리)
.fa_data_root <- function() {
  o <- getOption("fred_avail.data_root")
  if (!is.null(o)) return(gsub("\\\\", "/", o))
  r <- Sys.getenv("QM_ROOT", "")
  if (nzchar(r)) return(gsub("\\\\", "/", r))
  .fa_code_root()
}

.FA_CACHE <- new.env(parent = emptyenv())

.FA_BOUND_PARAMS <- list(
  kr_trading_days_after    = c("n"),
  label_plus_days          = c("days"),
  month_nth_kr_trading_day = c("month_offset", "n"),
  month_day                = c("month_offset", "day"),
  us_release               = character(0)
)
.FA_RELEASE_PARAMS <- list(
  label_plus_days           = c("days"),
  month_nth_weekday         = c("month_offset", "weekday", "nth"),
  us_business_days_after    = c("n"),
  month_nth_us_business_day = c("month_offset", "n")
)

.fa_int_param <- function(b, p, ctx, lo = -Inf) {
  v <- b[[p]]
  if (is.null(v) || length(v) != 1L || !is.numeric(v) || is.na(v) || v != round(v) || v < lo)
    stop(sprintf("[fred_avail] 규칙 파일 오류: %s — 정수 파라미터 '%s' 누락/부적합", ctx, p))
  as.integer(v)
}

.fa_validate <- function(raw, path) {
  if (!identical(raw$schema, "fred_availability_rules/v1"))
    stop("[fred_avail] 규칙 파일 schema 불일치: ", path)
  if (!is.character(raw$version) || !nzchar(raw$version)) stop("[fred_avail] version 누락: ", path)
  ser <- raw$series
  if (!is.list(ser) || length(ser) == 0L) stop("[fred_avail] series 비어 있음: ", path)
  idx <- integer(0); by_id <- list()
  for (i in seq_along(ser)) {
    s <- ser[[i]]
    id <- s$id
    if (!is.character(id) || length(id) != 1L || !nzchar(id)) stop("[fred_avail] series[", i, "] id 누락")
    st <- s$status
    if (!(identical(st, "active") || identical(st, "prohibited")))
      stop(sprintf("[fred_avail] %s: status 는 active|prohibited (받음: %s)", id, paste(st, collapse = ",")))
    if (identical(st, "active")) {
      bs <- s$bounds
      if (!is.list(bs) || length(bs) == 0L) stop(sprintf("[fred_avail] %s: active 인데 bounds 없음", id))
      for (k in seq_along(bs)) {
        b <- bs[[k]]; ctx <- sprintf("%s.bounds[%d]", id, k)
        ty <- b$type
        if (!is.character(ty) || !(ty %in% names(.FA_BOUND_PARAMS)))
          stop(sprintf("[fred_avail] 규칙 파일 오류: %s — 알 수 없는 bound type '%s'", ctx, paste(ty, collapse = ",")))
        if (!is.character(b$basis) || !nzchar(b$basis)) stop(sprintf("[fred_avail] %s — basis(근거) 누락", ctx))
        for (p in .FA_BOUND_PARAMS[[ty]]) .fa_int_param(b, p, ctx, lo = 0)
        if (ty == "us_release") {
          r <- b$release
          if (!is.list(r) || !is.character(r$kind) || !(r$kind %in% names(.FA_RELEASE_PARAMS)))
            stop(sprintf("[fred_avail] %s — release.kind 부적합", ctx))
          for (p in .FA_RELEASE_PARAMS[[r$kind]]) .fa_int_param(r, p, paste0(ctx, ".release"), lo = 0)
          if (identical(r$kind, "month_nth_weekday")) {
            w <- .fa_int_param(r, "weekday", ctx, lo = 1)
            if (w > 7L) stop(sprintf("[fred_avail] %s — weekday 는 ISO 1..7", ctx))
          }
          kr <- .fa_or(b$kr_rule, "strictly_after")
          if (!(kr %in% c("strictly_after", "on_or_after"))) stop(sprintf("[fred_avail] %s — kr_rule 부적합", ctx))
          if (!is.null(b$us_holiday_roll) && !is.logical(b$us_holiday_roll))
            stop(sprintf("[fred_avail] %s — us_holiday_roll 은 bool", ctx))
        }
      }
      ov <- s$release_overrides
      if (!is.null(ov)) for (k in seq_along(ov)) {
        o <- ov[[k]]
        ok <- is.character(o$obs) && is.character(o$us_release) &&
              !is.na(as.Date(o$obs, optional = TRUE)) && !is.na(as.Date(o$us_release, optional = TRUE)) &&
              is.character(o$source) && nzchar(o$source)
        if (!ok) stop(sprintf("[fred_avail] %s.release_overrides[%d] — obs/us_release/source 부적합", id, k))
      }
    }
    keys <- unique(c(id, unlist(s$aliases)))
    dup <- keys[keys %in% names(idx)]
    if (length(dup)) stop(sprintf("[fred_avail] 계열 키 충돌: %s (id/aliases 는 전역 유일)", paste(dup, collapse = ",")))
    idx[keys] <- i
    by_id[[id]] <- s
  }
  uc <- .fa_or(raw$us_calendar, list())
  xc <- vapply(.fa_or(uc$extra_closures, list()), function(e) as.character(e$date), "")
  xcd <- as.Date(xc)
  if (anyNA(xcd)) stop("[fred_avail] us_calendar.extra_closures 날짜 부적합")
  list(raw = raw, path = path, version = raw$version, index = idx, by_id = by_id,
       us = list(mlk_from = as.integer(.fa_or(uc$mlk_from_year, 1986L)),
                 juneteenth_from = as.integer(.fa_or(uc$juneteenth_from_year, 2021L)),
                 extra = as.integer(xcd)),
       md5 = unname(as.character(tools::md5sum(path))))
}

fred_avail_rules <- function(rules_path = NULL) {
  p <- .fa_or(rules_path, file.path(.fa_code_root(), "06_Registry", "fred_availability_rules.json"))
  if (!file.exists(p)) stop("[fred_avail] 규칙 파일 없음(fail-closed): ", p)
  fi <- file.info(p)
  key <- paste("rules", normalizePath(p, winslash = "/", mustWork = TRUE), fi$size, as.numeric(fi$mtime))
  hit <- .FA_CACHE[[key]]
  if (!is.null(hit)) return(hit)
  raw <- jsonlite::fromJSON(p, simplifyVector = FALSE)
  R <- .fa_validate(raw, p)
  assign(key, R, envir = .FA_CACHE)
  R
}

.fa_rules <- function(rules) {
  if (is.null(rules)) return(fred_avail_rules())
  if (is.character(rules)) return(fred_avail_rules(rules))
  if (is.list(rules) && !is.null(rules$index)) return(rules)
  stop("[fred_avail] rules 인자는 NULL·경로·fred_avail_rules() 결과여야 한다")
}

fred_series_rule <- function(series_id, rules = NULL) {
  R <- .fa_rules(rules)
  if (!is.character(series_id) || length(series_id) != 1L || is.na(series_id))
    stop("[fred_avail] series_id 는 문자열 1개")
  i <- R$index[series_id]
  if (is.na(i)) stop(sprintf("[fred_avail] 규칙 없는 계열 '%s' — 결합 거부(fail-closed). 규칙 파일: %s", series_id, R$path))
  s <- R$raw$series[[i]]
  if (!identical(s$status, "active")) {
    rep <- .fa_or(s$replacement, "")
    stop(sprintf("[fred_avail] 계열 '%s'(=%s) 사용 금지 — %s%s", series_id, s$id,
                 .fa_or(s$prohibition_basis, "status!=active"),
                 if (nzchar(rep)) sprintf(" · 대체 계열 id = '%s'", rep) else ""))
  }
  s
}

fred_kr_calendar <- function(path = NULL) {
  p <- .fa_or(path, .fa_or(getOption("fred_avail.calendar_path"),
                            file.path(.fa_data_root(), ".cache", "trading_calendar.parquet")))
  if (!file.exists(p)) stop("[fred_avail] 한국 거래일 달력 없음: ", p, " — kr_calendar 를 주입하라")
  fi <- file.info(p)
  key <- paste("cal", normalizePath(p, winslash = "/"), fi$size, as.numeric(fi$mtime))
  hit <- .FA_CACHE[[key]]
  if (!is.null(hit)) return(hit)
  # mmap=FALSE: 달력은 일간 경로가 덮어쓰는 파일이다 — 매핑을 쥐고 있으면 Windows 에서 교체가 막힌다
  d <- as.Date(arrow::read_parquet(p, col_select = "Date", as_data_frame = TRUE, mmap = FALSE)$Date)
  d <- sort(unique(d[!is.na(d)]))
  if (!length(d)) stop("[fred_avail] 달력이 비어 있음: ", p)
  assign(key, d, envir = .FA_CACHE)
  d
}

.fa_cal <- function(kr_calendar) {
  if (is.null(kr_calendar)) kr_calendar <- fred_kr_calendar()
  cal <- as.Date(kr_calendar)
  if (!length(cal) || anyNA(cal)) stop("[fred_avail] kr_calendar 가 비었거나 NA 포함")
  sort(unique(as.integer(cal)))
}

# ── 날짜 산술(정수 일수) ────────────────────────────────────────────────────────
.fa_iso_wday <- function(x) ((as.POSIXlt(as.Date(x))$wday + 6L) %% 7L) + 1L   # 월=1 … 일=7
.fa_ym <- function(x) { lt <- as.POSIXlt(as.Date(x)); list(y = lt$year + 1900L, m = lt$mon + 1L) }
.fa_ymd <- function(y, m, d) as.integer(as.Date(sprintf("%04d-%02d-%02d", as.integer(y), as.integer(m), as.integer(d))))
.fa_month_first <- function(x, offset) {
  ym <- .fa_ym(x)
  m2 <- ym$m + as.integer(offset)
  y2 <- ym$y + (m2 - 1L) %/% 12L
  m2 <- ((m2 - 1L) %% 12L) + 1L
  .fa_ymd(y2, m2, 1L)
}
.fa_month_last <- function(first_int) .fa_month_first(first_int, 1L) - 1L
.fa_nth_wday_int <- function(first_int, wday_iso, nth) {
  w <- .fa_iso_wday(first_int)
  if (nth > 0L) return(first_int + ((wday_iso - w) %% 7L) + 7L * (nth - 1L))
  last <- .fa_month_last(first_int)
  last - ((.fa_iso_wday(last) - wday_iso) %% 7L)
}

# ── 미국 연방 공휴일(5 U.S.C. §6103) + 추가 휴무 → 정수 일수 집합 ────────────────
.fa_observed <- function(d) { w <- .fa_iso_wday(d); d - (w == 6L) + (w == 7L) }
.fa_us_holidays <- function(years, us) {
  out <- integer(0)
  for (y in years) {
    f <- function(m) .fa_ymd(y, m, 1L)
    h <- c(.fa_observed(.fa_ymd(y, 1L, 1L)),
           if (y >= us$mlk_from) .fa_nth_wday_int(f(1L), 1L, 3L),
           .fa_nth_wday_int(f(2L), 1L, 3L),
           .fa_nth_wday_int(f(5L), 1L, -1L),
           if (y >= us$juneteenth_from) .fa_observed(.fa_ymd(y, 6L, 19L)),
           .fa_observed(.fa_ymd(y, 7L, 4L)),
           .fa_nth_wday_int(f(9L), 1L, 1L),
           .fa_nth_wday_int(f(10L), 1L, 2L),
           .fa_observed(.fa_ymd(y, 11L, 11L)),
           .fa_nth_wday_int(f(11L), 4L, 4L),
           .fa_observed(.fa_ymd(y, 12L, 25L)))
    out <- c(out, h)
  }
  sort(unique(c(out, us$extra)))
}
.fa_us_hol_set <- function(lo_int, hi_int, us) {
  y0 <- .fa_ym(lo_int)$y - 1L; y1 <- .fa_ym(hi_int)$y + 1L
  key <- paste("ushol", y0, y1, paste(us$extra, collapse = ","), us$mlk_from, us$juneteenth_from)
  hit <- .FA_CACHE[[key]]
  if (!is.null(hit)) return(hit)
  h <- .fa_us_holidays(seq.int(y0, y1), us)
  assign(key, h, envir = .FA_CACHE)
  h
}
.fa_is_us_bday <- function(x, hol) .fa_iso_wday(x) <= 5L & !(x %in% hol)
.fa_us_roll <- function(x, hol) {          # 미국 영업일이 아니면 다음 영업일로(≥)
  x <- as.integer(x)
  for (k in 1:40) {
    bad <- !is.na(x) & !.fa_is_us_bday(x, hol)
    if (!any(bad)) return(x)
    x[bad] <- x[bad] + 1L
  }
  stop("[fred_avail] 미국 영업일 탐색 실패")
}
.fa_us_bdays_after <- function(x, n, hol) { # x 이후(엄격) n번째 미국 영업일
  x <- as.integer(x)
  for (k in seq_len(n)) x <- .fa_us_roll(x + 1L, hol)
  x
}

# ── 한국 거래일 위치(1-based, cal = 정수 일수 오름차순) ──────────────────────────
.fa_pick <- function(cal, i) { out <- rep(NA_integer_, length(i)); ok <- !is.na(i) & i >= 1L & i <= length(cal); out[ok] <- cal[i[ok]]; out }
.fa_kr_gt <- function(x, cal) .fa_pick(cal, findInterval(x, cal) + 1L)          # 첫 거래일 > x
.fa_kr_ge <- function(x, cal) .fa_pick(cal, findInterval(x - 1L, cal) + 1L)     # 첫 거래일 ≥ x
.fa_kr_nth_after <- function(x, n, cal) {
  if (n == 0L) return(.fa_kr_ge(x, cal))
  .fa_pick(cal, findInterval(x, cal) + n)
}

.fa_bound <- function(b, obs, cal, us) {
  ty <- b$type
  if (ty == "kr_trading_days_after") return(.fa_kr_nth_after(obs, as.integer(b$n), cal))
  if (ty == "label_plus_days")       return(.fa_kr_ge(obs + as.integer(b$days), cal))
  if (ty == "month_nth_kr_trading_day") {
    ms <- .fa_month_first(obs, as.integer(b$month_offset))
    return(.fa_pick(cal, findInterval(ms - 1L, cal) + as.integer(b$n)))
  }
  if (ty == "month_day") {
    ms <- .fa_month_first(obs, as.integer(b$month_offset))
    me <- .fa_month_last(ms)
    return(.fa_kr_ge(pmin(ms + as.integer(b$day) - 1L, me), cal))
  }
  if (ty == "us_release") {
    r <- b$release
    hol <- .fa_us_hol_set(min(obs), max(obs) + 400L, us)
    R <- switch(r$kind,
      label_plus_days = obs + as.integer(r$days),
      month_nth_weekday = .fa_nth_wday_int(.fa_month_first(obs, as.integer(r$month_offset)),
                                           as.integer(r$weekday), as.integer(r$nth)),
      us_business_days_after = .fa_us_bdays_after(obs, as.integer(r$n), hol),
      month_nth_us_business_day = {
        ms <- .fa_month_first(obs, as.integer(r$month_offset))
        .fa_us_bdays_after(ms - 1L, as.integer(r$n), hol)
      })
    if (isTRUE(.fa_or(b$us_holiday_roll, FALSE))) R <- .fa_us_roll(R, hol)
    if (identical(.fa_or(b$kr_rule, "strictly_after"), "on_or_after")) return(.fa_kr_ge(R, cal))
    return(.fa_kr_gt(R, cal))
  }
  stop("[fred_avail] 알 수 없는 bound type: ", ty)
}

# 내부: 정수 관측일 → list(avail = 정수 가용일, basis = "rule"|"override")
.fa_avail_core <- function(s, obs, cal, R) {
  n <- length(obs)
  avail <- rep(NA_integer_, n); basis <- rep("rule", n)
  ok <- !is.na(obs) & obs >= cal[1L]
  if (!any(ok)) return(list(avail = avail, basis = basis))
  o <- obs[ok]
  m <- NULL
  for (b in s$bounds) {
    v <- .fa_bound(b, o, cal, R$us)
    m <- if (is.null(m)) v else pmax(m, v)       # NA 전파 = fail-closed
  }
  ov <- s$release_overrides
  if (length(ov)) {
    hol <- .fa_us_hol_set(min(o), max(o) + 400L, R$us)
    ob <- as.integer(as.Date(vapply(ov, function(x) x$obs, "")))
    rl <- as.integer(as.Date(vapply(ov, function(x) x$us_release, "")))
    j <- match(o, ob)
    hit <- !is.na(j)
    if (any(hit)) {
      v <- .fa_kr_gt(.fa_us_roll(rl[j[hit]], hol), cal)
      m[hit] <- pmax(m[hit], v)
      bb <- basis[ok]; bb[hit] <- "override"; basis[ok] <- bb
    }
  }
  avail[ok] <- m
  list(avail = avail, basis = basis)
}

fred_avail_date <- function(series_id, obs_date, kr_calendar = NULL, rules = NULL) {
  R <- .fa_rules(rules)
  s <- fred_series_rule(series_id, R)
  cal <- .fa_cal(kr_calendar)
  obs <- as.integer(as.Date(obs_date))
  as.Date(.fa_avail_core(s, obs, cal, R)$avail)
}

.fa_weekday <- function(x) .fa_iso_wday(x) <= 5L
.fa_extend_cal <- function(cal, kd) {
  mx <- max(cal)
  ex <- sort(unique(kd[!is.na(kd) & kd > mx]))
  ex <- ex[.fa_weekday(ex)]
  list(cal = if (length(ex)) sort(unique(c(cal, ex))) else cal, extended = ex)
}

.fa_decision_int <- function(kd, mode, cal) {
  if (identical(mode, "decision_close")) return(kd)
  if (!identical(mode, "exposure_return")) stop("[fred_avail] mode 는 decision_close|exposure_return")
  mx <- max(cal)
  bad <- !is.na(kd) & ((kd <= mx & !(kd %in% cal)) | (kd > mx & !.fa_weekday(kd)))
  if (any(bad)) stop("[fred_avail] exposure_return: 한국 거래일이 아닌 kr_date — ",
                     paste(head(as.Date(kd[bad]), 5), collapse = ","), " (수익 r_t 는 거래일에만 존재)")
  .fa_pick(cal, findInterval(kd - 1L, cal))                         # t 직전 거래일
}

fred_decision_date <- function(kr_dates, mode, kr_calendar = NULL) {
  cal <- .fa_cal(kr_calendar)
  kd <- as.integer(as.Date(kr_dates))
  cal <- .fa_extend_cal(cal, kd)$cal
  as.Date(.fa_decision_int(kd, mode, cal))
}

.fa_series_check <- function(sd, s, series_id) {
  for (col in c("Series_ID", "Series")) {
    if (col %in% names(sd)) {
      u <- unique(as.character(sd[[col]]))
      u <- u[!is.na(u)]
      if (length(u) > 1L) stop(sprintf("[fred_avail] series_dt 에 계열이 섞임(%s: %s) — 한 계열만 넘겨라", col, paste(head(u, 5), collapse = ",")))
      if (length(u) == 1L && !(u %in% c(s$id, unlist(s$aliases), s$name)))
        stop(sprintf("[fred_avail] series_dt 의 %s='%s' 가 요청 계열 '%s'(=%s)와 다름", col, u, series_id, s$id))
    }
  }
  invisible(TRUE)
}

fred_avail_annotate <- function(series_dt, series_id, kr_calendar = NULL, rules = NULL, date_col = "Date") {
  R <- .fa_rules(rules)
  s <- fred_series_rule(series_id, R)
  sd <- as.data.table(copy(series_dt))
  if (!(date_col %in% names(sd))) stop("[fred_avail] date_col 없음: ", date_col)
  .fa_series_check(sd, s, series_id)
  cal <- .fa_cal(kr_calendar)
  a <- .fa_avail_core(s, as.integer(as.Date(sd[[date_col]])), cal, R)
  sd[, avail_date := as.Date(a$avail)]
  sd[, avail_basis := a$basis]
  sd[]
}

# 결합 핵심(언어 공통 알고리즘 — py 판과 한 줄씩 대응):
#   가용 행만 (avail, obs) 오름차순 → obs 누적최대와 같은 행만 남김(늦게 가용해진 옛 관측이 새 관측을 덮지 않게)
#   → 결정일 이하 가용일 중 가장 오른쪽 행.
.fa_join_idx <- function(dec, obs, av) {
  ok <- which(!is.na(av) & !is.na(obs))
  if (!length(ok)) return(rep(NA_integer_, length(dec)))
  o <- ok[order(av[ok], obs[ok])]
  A <- av[o]; O <- obs[o]
  keep <- O == cummax(O)
  A <- A[keep]; src <- o[keep]
  j <- findInterval(dec, A)
  j[is.na(dec) | j == 0L] <- NA_integer_
  src[j]
}

fred_asof_join <- function(kr_dates, series_dt, series_id, mode = c("decision_close", "exposure_return"),
                           kr_calendar = NULL, rules = NULL, date_col = "Date", value_col = "Value",
                           extend_calendar = TRUE) {
  mode <- match.arg(mode)
  R <- .fa_rules(rules)
  s <- fred_series_rule(series_id, R)
  sd <- as.data.table(series_dt)
  for (col in c(date_col, value_col)) if (!(col %in% names(sd))) stop("[fred_avail] 열 없음: ", col)
  .fa_series_check(sd, s, series_id)
  obs <- as.integer(as.Date(sd[[date_col]]))
  val <- sd[[value_col]]
  keep <- !is.na(obs) & !is.na(val)
  obs <- obs[keep]; val <- val[keep]
  if (anyDuplicated(obs)) stop(sprintf("[fred_avail] %s: 같은 관측일이 2행 이상 — 결합 모호(fail-closed)", s$id))
  kd <- as.integer(as.Date(kr_dates))
  cal <- .fa_cal(kr_calendar)
  ext <- if (isTRUE(extend_calendar)) .fa_extend_cal(cal, kd) else list(cal = cal, extended = integer(0))
  cal <- ext$cal
  a <- .fa_avail_core(s, obs, cal, R)
  dec <- .fa_decision_int(kd, mode, cal)
  j <- .fa_join_idx(dec, obs, a$avail)
  rev <- .fa_or(s$vintage$revisions, "possible")
  out <- data.table(kr_date = as.Date(kd), decision_date = as.Date(dec),
                    value = val[j], obs_date = as.Date(obs[j]), avail_date = as.Date(a$avail[j]),
                    avail_basis = a$basis[j], series_id = s$id, mode = mode,
                    vintage = "latest", vintage_resolved = identical(rev, "none_known"))
  setattr(out, "rules_version", R$version)
  setattr(out, "rules_md5", R$md5)
  if (length(ext$extended)) setattr(out, "calendar_extended", as.Date(ext$extended))
  out[]
}

fred_join_violations <- function(kr_date, obs_date, series_id, mode = c("decision_close", "exposure_return"),
                                 kr_calendar = NULL, rules = NULL) {
  mode <- match.arg(mode)
  R <- .fa_rules(rules)
  s <- fred_series_rule(series_id, R)
  kd <- as.integer(as.Date(kr_date)); ob <- as.integer(as.Date(obs_date))
  if (length(kd) != length(ob)) stop("[fred_avail] kr_date 와 obs_date 길이 다름")
  cal <- .fa_extend_cal(.fa_cal(kr_calendar), kd)$cal
  dec <- .fa_decision_int(kd, mode, cal)
  av <- .fa_avail_core(s, ob, cal, R)$avail
  has <- !is.na(ob)
  why <- ifelse(!has, NA_character_,
         ifelse(is.na(dec), "decision_date_unresolved",
         ifelse(is.na(av), "avail_unresolved(fail-closed)",
         ifelse(av > dec, "obs_not_yet_available", NA_character_))))
  bad <- which(!is.na(why))
  data.table(row = bad, kr_date = as.Date(kd[bad]), decision_date = as.Date(dec[bad]),
             obs_date = as.Date(ob[bad]), avail_date = as.Date(av[bad]), reason = why[bad],
             series_id = s$id, mode = mode)
}

fred_avail_rules_meta <- function(rules_path = NULL) {
  R <- fred_avail_rules(rules_path)
  list(version = R$version, md5 = R$md5, path = R$path,
       regime_key = sprintf("c11_avail:%s:%s", R$version, substr(R$md5, 1L, 8L)))
}
