# derive_value_quality_spread.R — PIT-safe monthly value-dispersion series (revival signal substrate)
#
# 계약(revival_spec v1, 구현 C 정찰 plan):
#   실패지식 재부상 신호 'value_quality_spread' 의 실측 신호원.
#   AX-003 ('KR value EP_STANDALONE 실패')의 spread-reversion 전제조건이 재도래하는 시점을
#   추적하기 위해, EP 밸류 팩터(V02_EP)의 월간 횡단면 dispersion 을 산출한다.
#
# 산출: .cache/value_quality_spread.parquet {Date, spread}
#   spread[m] = quantile(z, 0.75) - quantile(z, 0.25)  (월 m 내 V02_EP Z_Score_Aligned 의 IQR)
#   = cheap-vs-expensive 갭 proxy. 넓을수록 mean-reversion 잠재력 큼.
#
# PIT (look-ahead-free by construction):
#   각 월 spread 는 그 월 자신의 횡단면만 사용(within-month dispersion 통계).
#   rolling/expanding 통계·미래데이터·full-sample 정규화 없음 → C1 만족.
#   정렬부호는 load_month_factors 내부 PIT-safe expanding IC(Usable_Date<=sig_date)로 이미 해소 → C13/C14 추가처리 불필요.
#   C15: factor DB 는 load_month_factors 커넥터로만 접근(직접 parquet read 금지).
#
# 실행(한글 -e 금지 — .R 파일 source 경유):
#   Rscript --no-save -e 'source("02_Infrastructure/ops/derive_value_quality_spread.R")'
#   또는 함수 직접: derive_value_quality_spread().

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
})

.vqs_root <- function() {
  cands <- c(Sys.getenv("CLAUDE_PROJECT_DIR", ""), Sys.getenv("QM_ROOT", ""),
             "C:/Users/99922/OneDrive/Quant_Module_Moltbot", getwd())
  for (p in cands) if (nzchar(p) && dir.exists(p)) return(p)
  getwd()
}

# ── 월말 sig_date 시퀀스 (2005-08 ~ 최신 factor DB 월) ────────────────────────
.vqs_month_ends <- function(root, start = "2005-08-01") {
  fdb <- file.path(root, ".cache", "factor_db")
  avail <- list.files(fdb, pattern = "^factor_db_\\d{6}\\.parquet$")
  if (!length(avail)) stop("[vqs] factor DB parquet 없음: ", fdb)
  yms <- sort(gsub("factor_db_(\\d{6})\\.parquet", "\\1", avail))
  last_ym <- yms[length(yms)]
  last_d  <- as.Date(paste0(substr(last_ym, 1, 4), "-", substr(last_ym, 5, 6), "-01"))
  start_d <- as.Date(start)
  # 월초 시퀀스 생성 후 각 월의 말일로 변환.
  firsts <- seq(start_d, last_d, by = "month")
  # 다음달 1일 - 1일 = 이번달 말일.
  nexts  <- seq(as.Date(format(firsts[1], "%Y-%m-01")), by = "month", length.out = length(firsts) + 1L)[-1L]
  month_ends <- nexts - 1L
  month_ends
}

#' PIT-safe monthly value-dispersion (IQR) of V02_EP Z_Score_Aligned.
#' @param root project root
#' @param factor value factor name (default V02_EP — AX-003 EP_STANDALONE 기계정합)
#' @param min_names thin-month guard: 유효 종목 수 < min_names 이면 spread=NA
#' @param out_path 산출 parquet 경로(기본 .cache/value_quality_spread.parquet)
#' @return data.table(Date, spread) — 부수효과로 parquet 기록
derive_value_quality_spread <- function(root = .vqs_root(),
                                        factor = "V02_EP",
                                        min_names = 30L,
                                        out_path = NULL,
                                        verbose = TRUE) {
  # ★arrow 스레드: set_io_thread_count(1L) 금지 — 커넥터의 open_dataset()%>%collect() 경로가
  #   단일 IO 스레드에서 HANG(실측: 1개월 >400s vs 기본 8스레드 0.2s). RAMP의 read_parquet HANG
  #   가드는 다른 연산이라 여기 부적용. 기본 멀티스레드 유지.

  # C15: 커넥터 경유 factor DB 접근.
  conn <- file.path(root, "02_Infrastructure", "factor_db", "factor_db_connector.R")
  if (!file.exists(conn)) stop("[vqs] connector 없음: ", conn)
  if (!exists("load_month_factors", mode = "function")) {
    old_wd <- getwd(); on.exit(setwd(old_wd), add = TRUE)
    setwd(root)
    source(conn)
  }

  month_ends <- .vqs_month_ends(root)
  rows <- vector("list", length(month_ends))
  n_ok <- 0L; n_thin <- 0L

  for (i in seq_along(month_ends)) {
    m <- month_ends[i]
    spread_m <- tryCatch({
      dt <- load_month_factors(sig_date = m, coverage_min = 0.05, factor_names = factor)
      # 커넥터는 요청 factor 부재/thin 월엔 0행 or 다른 월 fallback 가능 → 방어적으로 factor 필터.
      z <- dt[Factor_Name == factor, Z_Score_Aligned]
      z <- z[is.finite(z)]
      if (length(z) < min_names) { NA_real_ }
      else as.numeric(quantile(z, 0.75, names = FALSE) - quantile(z, 0.25, names = FALSE))
    }, error = function(e) NA_real_)

    if (is.na(spread_m)) n_thin <- n_thin + 1L else n_ok <- n_ok + 1L
    rows[[i]] <- data.table(Date = m, spread = spread_m)
  }

  res <- rbindlist(rows)
  # thin/NA 월은 시계열에서 제외(백분위 계산의 substrate 는 실측 월만).
  res <- res[!is.na(spread)]
  setorder(res, Date)

  if (is.null(out_path)) out_path <- file.path(root, ".cache", "value_quality_spread.parquet")
  dir.create(dirname(out_path), showWarnings = FALSE, recursive = TRUE)
  arrow::write_parquet(res, out_path)

  if (verbose) {
    cat(sprintf("[vqs] V02_EP dispersion 산출 완료 — rows=%d (ok=%d, thin/NA=%d)\n",
                nrow(res), n_ok, n_thin))
    if (nrow(res)) {
      cat(sprintf("[vqs] Date 범위: %s ~ %s\n", format(min(res$Date)), format(max(res$Date))))
      cat(sprintf("[vqs] spread 최근값: %.4f (전체 대비 백분위 %.3f)\n",
                  res$spread[nrow(res)], mean(res$spread <= res$spread[nrow(res)])))
    }
    cat(sprintf("[vqs] → %s\n", out_path))
  }
  invisible(res)
}

# top-level source / CLI Rscript = 1회 자동 실행.
if (!isTRUE(getOption("vqs_no_autorun", FALSE))) {
  derive_value_quality_spread()
}
