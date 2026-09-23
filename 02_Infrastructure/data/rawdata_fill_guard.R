#==============================================================================
# rawdata_fill_guard.R — RAWDATA 값 열 **채움률** 가드 (W-02, 2026-09-23)
#
# 사고: RAWDATA.Size 가 09-07 95.66% → 09-10~09-22 100% 결측이었다. 신선도 계기는
#   전부 초록이었다 — 행(Date,Ticker)은 매일 붙었고 max(Date) 는 최신이었다. 값-sanity 의
#   parity/abs_ret 축은 결측을 **먼저 지우고** 재므로(cache_freshness_audit.R .read_date_col
#   의 `dt[!is.na(get(col))]`) 100% 결측도 '위반 0' 이었다. 그 결과 factor_db_202609 에서
#   V01~V24·S01·S02·L26 27종이 0행이 됐다(emission_report_202609 class_R=27, reader 0).
#   ★"행이 있다" 와 "값이 있다" 는 다른 명제다 — 이 가드는 후자를 잰다.
#
# 문턱 정본 = 02_Infrastructure/data/cache_registry.json 의 RAWDATA 항목
#   value_checks.fill_rate {cols, max_na_rate, n_dates}. 코드에 되살리지 않는다.
#   소비자 셋이 같은 선언을 읽는다 — ①cache_freshness_audit.R (fill_rate → VALUE_FAIL)
#   ②daily_refresh.sh [1] 말미 (이 파일 CLI, Size → DR_FAILED rawdata_size_na)
#   ③naver_data_collector.R .naver_size_anchor_date (복원 앵커일 = 채움률 정상 마지막 날)
#
# CLI: Rscript rawdata_fill_guard.R [--path <parquet>] [--cols Size,BM_Ret] [--registry <json>]
#   stdout 마지막 줄: RAWDATA_FILL status=<OK|FAIL|UNMEASURED> date=<d> max_na=<r> <col>=<rate> ...
#   exit 0 = OK · 3 = FAIL(결측률 초과·열 부재) · 2 = UNMEASURED(판독 실패)
#   ★판독 실패를 OK 로 접지 않는다(부재 != 정상) — 호출자가 rc 2 를 따로 적는다.
#
# 검사: 08_Tests/data/test_rawdata_size_guard.R (양성 대조 · 위반 주입 · 돌연변이)
#==============================================================================
suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(jsonlite)
})

.rfg_root <- function() {
  if (exists("PROJECT_ROOT")) return(PROJECT_ROOT)
  r <- gsub("\\\\", "/", Sys.getenv("QM_ROOT", unset = ""))
  if (nzchar(r) && dir.exists(r)) r else getwd()
}

#' 선언 로드 — registry 의 RAWDATA 항목 value_checks.fill_rate. 부재 = stop.
rawdata_fill_spec <- function(registry_path = file.path(.rfg_root(), "02_Infrastructure/data/cache_registry.json"),
                              cache_path = ".cache/RAWDATA.parquet") {
  if (!file.exists(registry_path)) stop("[rawdata_fill_guard] registry 부재: ", registry_path)
  reg <- fromJSON(registry_path, simplifyVector = FALSE)
  ent <- Filter(function(c) identical(c$path, cache_path), reg$caches)
  if (!length(ent)) stop("[rawdata_fill_guard] registry 에 ", cache_path, " 항목 부재")
  fr <- ent[[1]]$value_checks$fill_rate
  rawdata_fill_spec_from(fr)
}

#' 선언 객체(list) → 정규화. cache_freshness_audit 의 caches_override 도 이 경로를 쓴다.
rawdata_fill_spec_from <- function(fr) {
  if (is.null(fr)) stop("[rawdata_fill_guard] fill_rate 선언 부재 — 문턱을 코드에 되살리지 말 것")
  cols <- as.character(unlist(fr$cols))
  mx <- suppressWarnings(as.numeric(fr$max_na_rate))
  nd <- suppressWarnings(as.integer(fr$n_dates %||% 1L))
  if (!length(cols) || !is.finite(mx) || mx < 0 || mx > 1 || !is.finite(nd) || nd < 1L)
    stop("[rawdata_fill_guard] fill_rate 선언 형식 오류 (cols/max_na_rate/n_dates)")
  list(cols = cols, max_na_rate = mx, n_dates = nd)
}

if (!exists("%||%")) `%||%` <- function(a, b) if (is.null(a)) b else a

#' 순수 함수 — 최근 n_dates 개 날짜의 열별 결측률. 열 부재는 present=FALSE 로 남는다.
#' 결측 = !is.finite (NA·NaN·Inf). 분모 = 그 날짜의 행 수.
rawdata_fill_rates <- function(dt, cols, n_dates = 1L) {
  dt <- as.data.table(dt)
  if (!"Date" %in% names(dt) || !nrow(dt))
    return(data.table(Date = as.Date(character(0)), col = character(0), n = integer(0),
                      n_na = integer(0), na_rate = numeric(0), present = logical(0)))
  dd <- as.Date(dt$Date)
  ds <- sort(unique(dd), decreasing = TRUE)
  ds <- ds[seq_len(min(as.integer(n_dates), length(ds)))]
  sel <- dd %in% ds
  rbindlist(lapply(cols, function(cc) {
    if (!cc %in% names(dt))
      return(data.table(Date = ds, col = cc, n = NA_integer_, n_na = NA_integer_,
                        na_rate = NA_real_, present = FALSE))
    v <- dt[[cc]][sel]
    r <- data.table(Date = dd[sel], miss = !is.finite(suppressWarnings(as.numeric(v))))
    r[, .(n = .N, n_na = sum(miss), na_rate = mean(miss)), by = Date][
      , `:=`(col = cc, present = TRUE)][]
  }), use.names = TRUE, fill = TRUE)[order(-Date, col)]
}

#' 판정 — 결측률 > max_na_rate 또는 열 부재 = 위반.
rawdata_fill_verdict <- function(rates, max_na_rate) {
  viol <- rates[!present | is.na(na_rate) | na_rate > max_na_rate]
  list(status = if (!nrow(rates)) "UNMEASURED" else if (nrow(viol)) "FAIL" else "OK",
       violations = viol, rates = rates, max_na_rate = max_na_rate)
}

#' 파일 판정 — 필요한 열만 읽는다(RAWDATA 400MB+ 전체 로드 회피).
rawdata_fill_check <- function(path = file.path(.rfg_root(), ".cache/RAWDATA.parquet"),
                               cols = NULL, spec = NULL) {
  spec <- spec %||% rawdata_fill_spec()
  cols <- cols %||% spec$cols
  if (!file.exists(path)) stop("[rawdata_fill_guard] 파일 부재: ", path)
  sch <- arrow::open_dataset(path)$schema$names
  have <- intersect(cols, sch)
  dt <- as.data.table(read_parquet(path, col_select = tidyselect::all_of(c("Date", have))))
  rates <- rawdata_fill_rates(dt, cols, spec$n_dates)
  v <- rawdata_fill_verdict(rates, spec$max_na_rate)
  v$path <- path; v$cols <- cols; v$n_dates <- spec$n_dates
  v
}

rawdata_fill_line <- function(v) {
  if (is.null(v$rates) || !nrow(v$rates))
    return(sprintf("RAWDATA_FILL status=%s", v$status))
  d0 <- max(v$rates$Date)
  last <- v$rates[Date == d0]
  sprintf("RAWDATA_FILL status=%s date=%s max_na=%s %s", v$status, as.character(d0),
          format(v$max_na_rate),
          paste(sprintf("%s=%s", last$col,
                        ifelse(last$present, sprintf("%.4f", last$na_rate), "absent")),
                collapse = " "))
}

# ── CLI ─────────────────────────────────────────────────────────────────────
if (sys.nframe() == 0L && !interactive()) {
  args <- commandArgs(trailingOnly = TRUE)
  .arg <- function(k) { i <- match(k, args); if (is.na(i) || i == length(args)) NULL else args[i + 1L] }
  path <- .arg("--path") %||% file.path(.rfg_root(), ".cache/RAWDATA.parquet")
  cols <- .arg("--cols"); if (!is.null(cols)) cols <- strsplit(cols, ",", fixed = TRUE)[[1]]
  reg  <- .arg("--registry")
  rc <- 0L
  v <- tryCatch({
    spec <- if (!is.null(reg)) rawdata_fill_spec(reg) else rawdata_fill_spec()
    rawdata_fill_check(path, cols = cols, spec = spec)
  }, error = function(e) list(status = "UNMEASURED", error = conditionMessage(e), rates = NULL))
  if (identical(v$status, "FAIL")) {
    vv <- v$violations
    for (i in seq_len(nrow(vv)))
      cat(sprintf("[rawdata_fill] ★%s %s 결측률 %s > %s (n=%s)\n", as.character(vv$Date[i]), vv$col[i],
                  if (vv$present[i]) sprintf("%.4f", vv$na_rate[i]) else "열부재",
                  format(v$max_na_rate), format(vv$n[i])))
    rc <- 3L
  } else if (!identical(v$status, "OK")) {
    cat(sprintf("[rawdata_fill] 미측정 — %s\n", v$error %||% "판정 대상 0행"))
    rc <- 2L
  }
  cat(rawdata_fill_line(v), "\n", sep = "")
  quit(save = "no", status = rc)
}
