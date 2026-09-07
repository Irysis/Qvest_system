#==============================================================================
# benchmark_level_axis.R — 벤치마크 **레벨 축** 단일 정본 (2026-09-07 신설)
#
# ─── 왜 (실측 2026-09-07) ─────────────────────────────────────────────────────
# `.cache/benchmark.parquet::BM_Close` 가 실제 코스피200 지수 레벨의 **8.834448배**
# 위에 있었다. BM_Ret 은 결백하다(코스피200과 일치). 어긋난 것은 레벨뿐이고,
# 하루 사이 배수 점프가 0건이라 "연속이면 정상" 으로 보여 두 달 넘게 안 보였다.
#
# ★ 8.834 는 마이그레이션 상수가 아니다 — 실측으로 배수는 **구간마다 다르다**:
#     1990-01-05 ~ 1998-12-04 : 9.80 → 12.58 → 9.29 로 **주 단위로 계단 이동**
#                               (구간 433개, 각 구간 길이 정확히 5거래일)
#     1998-12-07 ~ 2024-12-27 : 8.800942 (6,430세션 고정)
#     2025-01-02 ~ 현재       : 8.834448 (독립 소스 KRX 코스피200 40/40일 일치)
#   계단의 위치가 전부 `indices.parquet` 에는 있는데 `benchmark.parquet` 에는 없는
#   세션(토요장 438건 + 2024-12-30 + 2건)의 날짜와 정확히 일치한다. 검증:
#     ratio(2025-01-02) / ratio(2024-12-27) = 1.003807186458
#     1 / (1 + kospi200 2024-12-30 수익률)  = 1.003807186458   (일치 오차 <1e-9)
#   즉 BM_Close 는 **지수 레벨이 아니라 벤치 자신의 거래일 위에서 BM_Ret 을 체인한
#   NAV** 다(내부 정합 실측: |BM_Ret - Close/lagClose+1| 최대 2.2e-16, 9,021행 전부).
#   ⇒ **상수 나눗셈으로는 전 구간을 되돌릴 수 없다.** 되돌릴 수 있는 것은 현행 구간뿐이고,
#     그 이전의 잔차는 재척도가 만든 오차가 아니라 **결손 세션 441건이라는 기존 결함**이
#     8.8배 오프셋 안에 숨어 있다가 드러나는 것이다(드러나는 편이 낫다).
#
# ─── 레벨 축 규약 (선언) ─────────────────────────────────────────────────────
# 정본 축 = **공표 코스피200 지수 레벨**(seam_guard_config.json::BENCH_LEVEL_AXIS).
# 근거는 취향이 아니라 재현가능성이다:
#   · 원천에서 **자기참조 없이** 재도출된다. 8.834 축은 median(BM_Close/index) 로만
#     정의되므로 자기 자신을 봐야 알 수 있고, 그래서 두 달을 살아남았다.
#   · writer 4곳 중 3곳이 이미 생 지수 레벨을 낸다:
#       build_index_cache.py  bm["BM_Close"] = df["kospi200"]        (생 레벨)
#       krx_build_rawdata.R   CLSPRC_IDX 그대로                        (생 레벨)
#       naver_benchmark_update.py  생 KPI200 을 받아 **파일이 이미 쓰던 배수로 되돌린다**
#         → 축을 정하지 않고 승계만 한다. 그래서 전체 파이프라인이 bistable 하다:
#           마지막 전체재빌드 writer 가 남긴 축이 그대로 굳는다.
#   · build_cache.R:47 의 기존 sanity 가드가 이미 이 축을 불변식으로 적고 있었다.
#
# ─── 이 파일이 하는 일 ───────────────────────────────────────────────────────
# 순수 함수만 둔다(부작용 0 · 어떤 캐시도 쓰지 않는다). 소비자 2곳이 같은 판정을 쓴다:
#   · 02_Infrastructure/data/benchmark_currency_gate.R  축 C (daily_refresh 상시 경로)
#   · 02_Infrastructure/data/build_cache.R              전체 재빌드 직후
# 두 배관이 다른 이름으로 같은 일을 하면 다음 사람이 또 한쪽만 고친다.
#==============================================================================

suppressWarnings(suppressMessages({
  library(arrow); library(data.table); library(jsonlite)
}))

# 코스피200 / 코스피(종합)의 KRX 지수명. ★한글 리터럴을 비교식에 직접 박지 않는다 —
# Windows 네이티브 인코딩 세션에서 parquet(UTF-8) 문자열과 바이트가 갈린다.
BLA_IDX_NM_KOSPI200 <- intToUtf8(c(0xCF54, 0xC2A4, 0xD53C, 0x20, 0x32, 0x30, 0x30))  # KOSPI 200
BLA_IDX_NM_KOSPI    <- intToUtf8(c(0xCF54, 0xC2A4, 0xD53C))                          # KOSPI (composite)

#' 레벨 축 설정 — seam_guard_config.json 단일 정본. 부재 시 폴백을 **알리고** 쓴다.
#' (naver_benchmark_update.py 와 같은 규약: 일일 배관이라 설정 부재로 죽지 않는다.)
bench_level_config <- function(root) {
  p <- file.path(root, "02_Infrastructure/data/seam_guard_config.json")
  fb <- list(BENCH_LEVEL_AXIS = "raw_index_level", BENCH_LEVEL_TOL = 0.01,
             BENCH_LEVEL_MIN_SESSIONS = 5L, BENCH_LEVEL_WINDOW_SESSIONS = 20L)
  if (!file.exists(p)) {
    cat(sprintf("   [bench-level] 설정 부재 — 파일 내 폴백값 사용: %s\n", p))
    return(fb)
  }
  cfg <- tryCatch(jsonlite::fromJSON(p, simplifyVector = TRUE), error = function(e) NULL)
  if (is.null(cfg)) {
    cat(sprintf("   [bench-level] 설정 판독 실패 — 폴백값 사용: %s\n", p)); return(fb)
  }
  for (k in names(fb)) if (!is.null(cfg[[k]])) fb[[k]] <- cfg[[k]]
  fb$BENCH_LEVEL_TOL <- as.numeric(fb$BENCH_LEVEL_TOL)
  fb$BENCH_LEVEL_MIN_SESSIONS <- as.integer(fb$BENCH_LEVEL_MIN_SESSIONS)
  fb$BENCH_LEVEL_WINDOW_SESSIONS <- as.integer(fb$BENCH_LEVEL_WINDOW_SESSIONS)
  fb
}

#' KRX 일별 지수 캐시에서 코스피200 종가를 읽는다 (신선 · 독립 소스).
#'
#' @param root      저장소 루트
#' @param n_files   최근 몇 개 파일을 읽을지 (전량 읽기는 느리다)
#' @param idx_nm    지수명. 기본 코스피200. 오선택 진단 시 BLA_IDX_NM_KOSPI 를 넘긴다.
#' @return data.table(Date, ref_close) — 없으면 0행
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
    # 날짜는 BAS_DD 우선, 없으면 파일명(둘 다 YYYYMMDD)
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

#' indices.parquet 의 kospi200 컬럼 (전 기간 · 갱신 주기는 벤치와 다르다).
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

#' 독립 참조 레벨 — KRX(신선) 우선, indices(전기간) 보충. 둘 다 없으면 0행.
bench_level_reference <- function(root) {
  k <- bench_level_ref_krx(root)
  i <- bench_level_ref_indices(root)
  if (nrow(k) && nrow(i)) {
    i <- i[!Date %in% k$Date]
    r <- rbindlist(list(k[, .(Date, ref_close, ref_source = "krx_kospi_index")],
                        i[, .(Date, ref_close, ref_source = "indices_parquet")]))
  } else if (nrow(k)) {
    r <- k[, .(Date, ref_close, ref_source = "krx_kospi_index")]
  } else if (nrow(i)) {
    r <- i[, .(Date, ref_close, ref_source = "indices_parquet")]
  } else {
    return(data.table(Date = as.Date(character(0)), ref_close = numeric(0),
                      ref_source = character(0)))
  }
  r[order(Date)]
}

#' 레벨 축 판정.
#'
#' 최근 공통 세션 창의 **중앙값 배수**로 판정한다 — 하루짜리 이상치가 판정을 뒤집지
#' 못하게. 창 밖(1999년 이전 결손 세션 구간)은 보지 않는다: 그 구간의 잔차는 레벨
#' 규약이 아니라 결손 세션의 문제이고, 여기서 재면 상시 빨강이 된다.
#'
#' @return list(status, scale, n, tol, latest_date, ref_source, detail)
#'   status: "ok" | "violation" | "no_measure"   ★부재를 "정상" 으로 읽지 않는다.
bench_level_axis_check <- function(bm, ref, tol = 0.01,
                                    min_sessions = 5L, window_sessions = 20L) {
  mk <- function(status, detail, scale = NA_real_, n = 0L, latest = as.Date(NA),
                 src = NA_character_)
    list(status = status, scale = scale, n = n, tol = tol,
         latest_date = latest, ref_source = src, detail = detail)

  if (is.null(bm) || !nrow(bm) || !("BM_Close" %in% names(bm)))
    return(mk("no_measure", "benchmark 에 BM_Close 컬럼 없음"))
  if (is.null(ref) || !nrow(ref))
    return(mk("no_measure", "독립 참조 지수 레벨 부재(.cache/krx/kospi_index · indices.parquet)"))

  b <- data.table(Date = as.Date(bm$Date), BM_Close = as.numeric(bm$BM_Close))
  b <- b[is.finite(BM_Close) & BM_Close > 0]
  r <- data.table(Date = as.Date(ref$Date), ref_close = as.numeric(ref$ref_close),
                  ref_source = as.character(ref$ref_source))
  m <- merge(b, r, by = "Date")[order(Date)]
  if (nrow(m) < min_sessions)
    return(mk("no_measure", sprintf("공통 세션 %d개 (<%d) — 판정 불가", nrow(m), min_sessions),
              n = nrow(m)))

  m <- tail(m, window_sessions)
  m[, ratio := BM_Close / ref_close]
  sc  <- as.numeric(stats::median(m$ratio))
  lat <- max(m$Date)
  src <- m[Date == lat]$ref_source[1]
  if (!is.finite(sc) || sc <= 0)
    return(mk("no_measure", "배수 산출 불가", n = nrow(m), latest = lat, src = src))

  if (abs(sc - 1) <= tol)
    return(mk("ok", sprintf("배수 %.6f (허용 %.4f) — 최근 %d세션 · 참조 %s", sc, tol, nrow(m), src),
              scale = sc, n = nrow(m), latest = lat, src = src))
  mk("violation",
     sprintf("BM_Close 가 공표 코스피200 레벨의 %.6f배 (허용 |배수-1|<=%.4f) — 최근 %d세션 중앙값 · 참조 %s · 최신 공통일 %s",
             sc, tol, nrow(m), src, format(lat)),
     scale = sc, n = nrow(m), latest = lat, src = src)
}

#' 레벨 재척도 — **BM_Ret 을 한 값도 건드리지 않는다**(수익률은 스케일 불변).
#' 위반 주입(scale>1)과 수리(scale=측정배수) 양방향에 같은 함수를 쓴다.
bench_level_rescale <- function(bm, scale) {
  if (!is.finite(scale) || scale <= 0) stop("[bench-level] scale 은 양수여야 한다: ", scale)
  out <- as.data.table(copy(bm))
  out[, BM_Close := BM_Close / scale]
  out
}
