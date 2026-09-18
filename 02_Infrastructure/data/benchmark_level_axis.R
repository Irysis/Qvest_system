#==============================================================================
# benchmark_level_axis.R — 벤치마크 **레벨 축** 단일 정본 (R 측)
#
# 2026-09-07 신설 · **2026-09-18 축 정규화로 전면 개정**(도훈 "근본적으로 좀 수정하자").
#
# ─── 규약 (하나뿐이다) ───────────────────────────────────────────────────────
#   `.cache/benchmark.parquet::BM_Close` = **공표 코스피200 지수 종가(포인트) 그대로**.
#   배율(scale)이라는 개념은 없다. 잴 것은 "정본과 같은가" 하나다.
#
# ─── 왜 배율 개념을 지웠나 (실측 2026-09-07 → 수리 2026-09-18) ────────────────
#   구판은 BM_Close 가 지수의 8.83배 위에 있는 **리베이스 체인**이었다. 체인이면 새 값을
#   붙일 때마다 배수를 추정해야 하고, 추정이 미끄러지면 그날 하루 수익률이 배수비를
#   통째로 삼킨다. 07-27 · 07-29 · 2025-01-02 이 전부 같은 병이고, 앞의 둘만 날짜를 박은
#   일회성 스크립트로 고쳐졌다(그래서 또 재발했다). 그리고 구 축 C 는 |배수-1|<=0.01 을
#   요구했으므로 체인 축에서는 **원리적으로 통과할 수 없었다** — daily_refresh 가
#   2026-09-07 이후 매일 benchmark_currency FAIL 을 냈고, 상시 빨강은 상시 침묵이다.
#   ⇒ 파일을 축에 맞췄다(rebuild_benchmark_canonical.py). 이제 이 검사는 참이 될 수 있다.
#
# ─── 이 파일이 재는 두 축 ────────────────────────────────────────────────────
#   ① 정합(identity)  |BM_Close / 참조지수 - 1| <= tol         ... 값이 같은가
#   ② 이음매(seam)    연속 공통일 사이 그 비율의 변화 <= seam_tol ... 같음이 유지되는가
#   ②가 없으면 "전 구간이 똑같이 1.0038배" 같은 통짜 이탈만 잡고, 정확히 재발했던
#   **하루짜리 계단**은 놓친다. 두 축을 같이 잰다.
#
# ─── 참조 원천 ───────────────────────────────────────────────────────────────
#   · `.cache/indices.parquet$kospi200` — 정본 xlsx(QuantiWise IKS200)의 산출물. 전 기간.
#   · `.cache/krx/kospi_index/*.parquet` — KRX 공표 스냅샷. 최근 구간(정본이 못 덮는 곳).
#   설정 정본 = `.cache/benchmark_axis.json`(manifest). ★구 seam_guard_config.json 의
#   BENCH_LEVEL_* 의존은 끊었다 — 그 파일은 종목 배관(seam_scale_guard.R) 몫만 남긴다.
#
# 순수 함수만 둔다(부작용 0). 소비자: benchmark_currency_gate.R · build_cache.R.
#==============================================================================

suppressWarnings(suppressMessages({
  library(arrow); library(data.table); library(jsonlite)
}))

# ★한글 리터럴을 비교식에 직접 박지 않는다 — Windows 네이티브 인코딩 세션에서
#   parquet(UTF-8) 문자열과 바이트가 갈린다.
BLA_IDX_NM_KOSPI200 <- intToUtf8(c(0xCF54, 0xC2A4, 0xD53C, 0x20, 0x32, 0x30, 0x30))  # KOSPI 200
BLA_IDX_NM_KOSPI    <- intToUtf8(c(0xCF54, 0xC2A4, 0xD53C))                          # KOSPI (composite)

#' 축 설정 — `.cache/benchmark_axis.json` 단일 정본. 부재 시 폴백을 **알리고** 쓴다.
#' (일일 배관이라 설정 부재로 죽지 않는다. 대신 조용하지도 않다.)
bench_level_config <- function(root) {
  p <- file.path(root, ".cache/benchmark_axis.json")
  fb <- list(BENCH_LEVEL_AXIS = "index_points",
             BENCH_LEVEL_TOL = 1e-4,            # |BM/지수 - 1| 허용
             BENCH_LEVEL_SEAM_TOL = 1e-4,       # 하루 사이 비율 변화 허용
             BENCH_LEVEL_MIN_SESSIONS = 5L,
             BENCH_LEVEL_WINDOW_SESSIONS = 0L,  # 0 = 전 구간. 구판(20)은 과거 이음매를 못 봤다
             BENCH_CANONICAL_MAX_LAG_DAYS = 10L)
  if (!file.exists(p)) {
    cat(sprintf("   [bench-level] manifest 부재 — 파일 내 폴백값 사용: %s\n", p))
    return(fb)
  }
  m <- tryCatch(jsonlite::fromJSON(p, simplifyVector = TRUE), error = function(e) NULL)
  if (is.null(m)) {
    cat(sprintf("   [bench-level] manifest 판독 실패 — 폴백값 사용: %s\n", p)); return(fb)
  }
  if (!is.null(m$unit))            fb$BENCH_LEVEL_AXIS <- m$unit
  if (!is.null(m$tolerance))       fb$BENCH_LEVEL_TOL <- as.numeric(m$tolerance)
  if (!is.null(m$seam_tolerance))  fb$BENCH_LEVEL_SEAM_TOL <- as.numeric(m$seam_tolerance)
  if (!is.null(m$min_sessions))    fb$BENCH_LEVEL_MIN_SESSIONS <- as.integer(m$min_sessions)
  if (!is.null(m$window_sessions)) fb$BENCH_LEVEL_WINDOW_SESSIONS <- as.integer(m$window_sessions)
  if (!is.null(m$canonical_max_lag_days))
    fb$BENCH_CANONICAL_MAX_LAG_DAYS <- as.integer(m$canonical_max_lag_days)
  fb
}

#' KRX 일별 지수 캐시에서 코스피200 종가를 읽는다 (신선 · 독립 소스).
bench_level_ref_krx <- function(root, n_files = 40L, idx_nm = BLA_IDX_NM_KOSPI200) {
  dir <- file.path(root, ".cache/krx/kospi_index")
  empty <- data.table(Date = as.Date(character(0)), ref_close = numeric(0))
  if (!dir.exists(dir)) return(empty)
  fs <- sort(list.files(dir, pattern = "^kospi_index_[0-9]{8}[.]parquet$", full.names = TRUE))
  if (!length(fs)) return(empty)
  fs <- tail(fs, n_files)
  out <- vector("list", length(fs))
  for (i in seq_along(fs)) {
    d <- tryCatch(as.data.table(read_parquet(fs[i])), error = function(e) NULL)
    if (is.null(d) || !all(c("IDX_NM", "CLSPRC_IDX") %in% names(d))) next
    nm <- trimws(enc2utf8(as.character(d$IDX_NM)))
    sel <- which(nm == idx_nm)
    if (!length(sel)) next
    v <- suppressWarnings(as.numeric(gsub(",", "", as.character(d$CLSPRC_IDX[sel[1]]), fixed = TRUE)))
    ds <- if ("BAS_DD" %in% names(d)) as.character(d$BAS_DD[sel[1]]) else
      sub("^.*kospi_index_([0-9]{8})[.]parquet$", "\\1", fs[i])
    dt <- suppressWarnings(as.Date(ds, format = "%Y%m%d"))
    if (is.na(dt) || !is.finite(v) || v <= 0) next
    out[[i]] <- data.table(Date = dt, ref_close = v)
  }
  out <- rbindlist(out[!vapply(out, is.null, logical(1))], use.names = TRUE)
  if (!nrow(out)) return(empty)
  unique(out, by = "Date")[order(Date)]
}

#' indices.parquet 의 kospi200 컬럼 — **정본 xlsx(QuantiWise IKS200)의 산출물**이다
#' (build_index_cache.py 가 생 포인트 그대로 쓴다). 전 기간, 갱신 주기는 xlsx 에 달렸다.
bench_level_ref_indices <- function(root) {
  p <- file.path(root, ".cache/indices.parquet")
  empty <- data.table(Date = as.Date(character(0)), ref_close = numeric(0))
  if (!file.exists(p)) return(empty)
  d <- tryCatch(as.data.table(read_parquet(p)), error = function(e) NULL)
  if (is.null(d) || !all(c("Date", "kospi200") %in% names(d))) return(empty)
  d <- d[, .(Date = as.Date(Date), ref_close = as.numeric(kospi200))]
  d <- d[is.finite(ref_close) & ref_close > 0]
  if (!nrow(d)) return(empty)
  unique(d, by = "Date")[order(Date)]
}

#' 독립 참조 레벨 — 정본(indices=xlsx) 우선, KRX 로 최근 구간 보충. 둘 다 없으면 0행.
#' ★우선순위가 구판과 반대로 바뀌었다(구판은 KRX 우선): 정본이 정본이다. KRX 는
#'   정본이 아직 못 덮은 날만 메운다.
bench_level_reference <- function(root) {
  i <- bench_level_ref_indices(root)
  k <- bench_level_ref_krx(root)
  if (nrow(i) && nrow(k)) {
    k <- k[!Date %in% i$Date]
    r <- rbindlist(list(i[, .(Date, ref_close, ref_source = "indices_parquet")],
                        k[, .(Date, ref_close, ref_source = "krx_kospi_index")]))
  } else if (nrow(i)) {
    r <- i[, .(Date, ref_close, ref_source = "indices_parquet")]
  } else if (nrow(k)) {
    r <- k[, .(Date, ref_close, ref_source = "krx_kospi_index")]
  } else {
    return(data.table(Date = as.Date(character(0)), ref_close = numeric(0),
                      ref_source = character(0)))
  }
  r[order(Date)]
}

#' 레벨 축 판정 — ①정합 ②이음매.
#'
#' @param window_sessions 0 이면 전 구간. >0 이면 최근 그만큼의 공통 세션만 본다.
#'   ★구판 기본값 20 은 **과거 이음매를 구조적으로 못 봤다**(2025-01-02 계단이 그 창
#'     밖이라 두 달 넘게 안 걸렸다). 기본을 전 구간으로 바꾼다.
#' @return list(status, scale, max_dev, max_seam, worst_date, worst_seam_date,
#'              n, tol, seam_tol, latest_date, ref_source, failed_axis, detail)
#'   status: "ok" | "violation" | "no_measure"   ★부재를 "정상" 으로 읽지 않는다.
#'   scale = 측정된 비율의 중앙값(= 진단 표시용). 선언값이 아니다 — 새 축에서 기대값은 1.
bench_level_axis_check <- function(bm, ref, tol = 1e-4,
                                   min_sessions = 5L, window_sessions = 0L,
                                   seam_tol = NULL) {
  if (is.null(seam_tol)) seam_tol <- tol
  mk <- function(status, detail, scale = NA_real_, n = 0L, latest = as.Date(NA),
                 src = NA_character_, max_dev = NA_real_, max_seam = NA_real_,
                 worst = as.Date(NA), worst_seam = as.Date(NA), failed = NA_character_)
    list(status = status, scale = scale, max_dev = max_dev, max_seam = max_seam,
         worst_date = worst, worst_seam_date = worst_seam, n = n, tol = tol,
         seam_tol = seam_tol, latest_date = latest, ref_source = src,
         failed_axis = failed, detail = detail)

  if (is.null(bm) || !nrow(bm) || !("BM_Close" %in% names(bm)))
    return(mk("no_measure", "benchmark 에 BM_Close 컬럼 없음"))
  if (is.null(ref) || !nrow(ref))
    return(mk("no_measure", "독립 참조 지수 레벨 부재(.cache/indices.parquet · .cache/krx/kospi_index)"))

  b <- data.table(Date = as.Date(bm$Date), BM_Close = as.numeric(bm$BM_Close))
  b <- b[is.finite(BM_Close) & BM_Close > 0]
  r <- data.table(Date = as.Date(ref$Date), ref_close = as.numeric(ref$ref_close),
                  ref_source = as.character(ref$ref_source))
  m <- merge(b, r, by = "Date")[order(Date)]
  if (nrow(m) < min_sessions)
    return(mk("no_measure", sprintf("공통 세션 %d개 (<%d) — 판정 불가", nrow(m), min_sessions),
              n = nrow(m)))
  if (is.finite(window_sessions) && window_sessions > 0L && nrow(m) > window_sessions)
    m <- tail(m, window_sessions)

  m[, ratio := BM_Close / ref_close]
  lat <- max(m$Date); src <- m[Date == lat]$ref_source[1]
  sc  <- as.numeric(stats::median(m$ratio))
  if (!is.finite(sc) || sc <= 0)
    return(mk("no_measure", "비율 산출 불가", n = nrow(m), latest = lat, src = src))

  dev <- abs(m$ratio - 1)
  i_dev <- which.max(dev); max_dev <- dev[i_dev]
  seam <- abs(m$ratio / shift(m$ratio) - 1)
  i_sm <- if (all(is.na(seam))) NA_integer_ else which.max(replace(seam, is.na(seam), -Inf))
  max_seam <- if (is.na(i_sm)) NA_real_ else seam[i_sm]

  bad <- character(0); axes <- character(0)
  if (max_dev > tol) {
    axes <- c(axes, "identity")
    bad <- c(bad, sprintf("정합 이탈 |BM/지수-1| 최대 %.3e > %.3e (@%s: BM %.4f vs 지수 %.4f)",
                          max_dev, tol, format(m$Date[i_dev]),
                          m$BM_Close[i_dev], m$ref_close[i_dev]))
  }
  if (is.finite(max_seam) && max_seam > seam_tol) {
    axes <- c(axes, "seam")
    bad <- c(bad, sprintf("이음매 — 연속 공통일 사이 비율이 %.3e 변화 > %.3e (@%s)",
                          max_seam, seam_tol, format(m$Date[i_sm])))
  }
  if (length(bad))
    return(mk("violation", sprintf("%s — 공통 %d세션 · 참조 %s · 최신 공통일 %s",
                                   paste(bad, collapse = " | "), nrow(m), src, format(lat)),
              scale = sc, n = nrow(m), latest = lat, src = src,
              max_dev = max_dev, max_seam = max_seam,
              worst = m$Date[i_dev], worst_seam = if (is.na(i_sm)) as.Date(NA) else m$Date[i_sm],
              failed = paste(axes, collapse = "+")))

  mk("ok", sprintf("지수 일치 — 최대편차 %.3e · 최대이음매 %.3e (허용 %.1e/%.1e) · 공통 %d세션 · 참조 %s",
                   max_dev, if (is.finite(max_seam)) max_seam else 0, tol, seam_tol, nrow(m), src),
     scale = sc, n = nrow(m), latest = lat, src = src,
     max_dev = max_dev, max_seam = max_seam,
     worst = m$Date[i_dev], worst_seam = if (is.na(i_sm)) as.Date(NA) else m$Date[i_sm])
}

#' 정본(QuantiWise xlsx) 신선도 — **소비면에서** 잰다.
#'
#' ★파일 mtime 이 아니라 `.cache/indices.parquet` 의 max(Date) 를 본다: 다운로드 성공은
#'   적재 성공이 아니다([[feedback-freshness-must-be-measured-at-the-consumption-panel]]).
#'   mtime 은 참고로만 같이 돌려준다.
#' @return list(status, canonical_max_date, lag_days, xlsx_mtime, detail)
bench_canonical_freshness <- function(root, today = Sys.Date()) {
  idx <- file.path(root, ".cache/indices.parquet")
  xls <- file.path(root, "03_Universe/Benchmark_price.xlsx")
  mt  <- if (file.exists(xls)) as.Date(file.info(xls)$mtime) else as.Date(NA)
  if (!file.exists(idx))
    return(list(status = "no_measure", canonical_max_date = as.Date(NA), lag_days = NA_integer_,
                xlsx_mtime = mt, detail = "indices.parquet 부재 — 정본 신선도 판정 불가"))
  d <- tryCatch(as.data.table(read_parquet(idx, col_select = "Date")), error = function(e) NULL)
  if (is.null(d) || !nrow(d))
    return(list(status = "no_measure", canonical_max_date = as.Date(NA), lag_days = NA_integer_,
                xlsx_mtime = mt, detail = "indices.parquet Date 판독 실패"))
  mx <- max(as.Date(d$Date), na.rm = TRUE)
  lag <- as.integer(today - mx)
  list(status = "ok", canonical_max_date = mx, lag_days = lag, xlsx_mtime = mt,
       detail = sprintf("정본 최신일 %s (lag %d일) · Benchmark_price.xlsx mtime %s",
                        format(mx), lag, if (is.na(mt)) "부재" else format(mt)))
}

#' 레벨 재척도 — **BM_Ret 을 한 값도 건드리지 않는다**(수익률은 스케일 불변).
#' ★새 축에는 '올바른 배수' 가 없다(정답은 항상 1) — 이 함수는 이제 **검사의 위반 주입**과
#'   진단용 보조 도구다. 운영 수리 경로는 rebuild_benchmark_canonical.py 다.
bench_level_rescale <- function(bm, scale) {
  if (!is.finite(scale) || scale <= 0) stop("[bench-level] scale 은 양수여야 한다: ", scale)
  out <- as.data.table(copy(bm))
  out[, BM_Close := BM_Close / scale]
  out
}
