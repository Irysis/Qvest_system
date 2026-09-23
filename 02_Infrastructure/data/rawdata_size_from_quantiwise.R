#==============================================================================
# rawdata_size_from_quantiwise.R — RAWDATA.Size 복원 구간을 퀀티와이즈 정본 시가총액으로 교체
#
# 결정 (도훈 2026-09-23): "복원 Size 의 PIT 엄격화 = 퀀티와이즈 데이터로 대체".
#   같은 날 W-02 수리가 2026-09-07~09-22 Size 를 재구성 주식수 × 종가로 채웠다. 그 주식수는
#   median(09-04 관측, 09-23 관측)이다 — 09-23 관측이 창 안의 날짜에 섞이므로 최대 0.95% 의
#   미래 정보가 들어간다(PIT 엄격하지 않음). 이 도구는 그 구간을 퀀티 수출본
#   (03_Universe/Update_File/OHLCVS_update.xlsx, 'Size' 시트 = 시가총액)의 값으로 바꾼다.
#
# ★출처·단위 재도출 (2026-09-23 실측, 08-29 판 xlsx 대 RAWDATA):
#   - 시트 'Size' · 8행 'Code' · 11행 'Unit' = local(원) · 14행 'D A T E' = 시가총액 · 15행~ 데이터.
#     (Unit/Item 행은 코드 열 뒤로도 옛 셀이 남아 있다 — 실측 local 6,383칸 vs 코드 3,717칸.
#      그래서 선언 판정은 **코드가 있는 열에서만** 한다.)
#   - 겹치는 구간(03-27~08-28, source quantiwise/quantiwise_update) 266,912행 중 **전부 정확히 일치**
#     (배율·반올림 없음, 원 단위 정수). 적재기(incremental_update_file.R::incremental_ohlcvs)가
#     값을 그대로 옮긴다는 뜻이다.
#   - 결측 규칙: QW Size 가 있다 ⇔ QW Close > 0 (불일치 0행). RAWDATA 는 Close>0 행만 적재된다.
#   - QW Size 는 **실제 시가총액**(당일 상장주식수 × 당일 종가)이다 — Close 는 수정주가라서
#     과거일의 Size/Close 는 정수가 아닐 수 있다(04-01 실측 91%만 정수). 그날 장 마감에 알 수 있는
#     값이므로 PIT 조건을 만족한다.
#
# ★이 도구가 아는 한계와 이웃 경로:
#   - daily_refresh.sh [0b] 는 incremental_update_all() 을 부른다. OHLCVS_update.xlsx 의 mtime 이
#     update_file_last_processed.rds 기록보다 새로우면 incremental_ohlcvs() 가 돌아
#     **base 이후 전 날짜의 전 값 열**(Open~Size·Ret·source)을 퀀티 값으로 바꾼다(행 삭제 후 append,
#     킬스위치 미경유). 도훈 09-07 원천 우선순위("퀀티 그대로 덮기")가 인정한 경로다. 이 도구는
#     그 경로를 대체하지도 막지도 않는다 — Size 열 하나만, 지정 구간만, 킬스위치 아래에서 바꾼다.
#
# 게이트(하나라도 실패 = 거부. dry-run 에서도 판정하고 보고서에 남긴다):
#   xlsx_locked          — '~$<파일명>' 잠금 파일 존재(엑셀이 열었거나 저장 중)
#   layout               — 'Size' 시트·라벨 행(Code/Unit/D A T E) 인식 실패, 코드 없는 열에 값
#   unit_declared        — 코드 열의 Unit ≠ local 또는 항목 ≠ 시가총액
#   horizon_short        — QW 지평선(A열 마지막 날짜) < 종료일  ★갱신 판정은 스탬프가 아니라 이것
#   window_dates_missing — 구간 안 RAWDATA 거래일 중 QW 에 없는 날
#   calibration          — 구간 전 겹침(source=quantiwise*)에서 QW==RAWDATA 비율 < calib_min_equal (측정 단위)
#   window_scale         — 구간 안 median(QW/현재) 가 1±scale_tol 밖 (scale_tol = naver size_shares_tol)
#   qw_fill              — 구간 날짜별 RAWDATA 행 대비 QW 결측률 > max_na_rate (cache_registry fill_rate)
#   duplicate_keys       — QW 코드 중복 · RAWDATA (Date,Ticker) 중복
#   qw_nonpositive       — QW Size ≤ 0
#
# 실행 모드(dry_run=FALSE) — 함수 안에서 전부 수행하고 어떤 종료 경로에서도 러너를 되돌린다:
#   ① 러너 일시정지 = reinforce_auto_config.json 최상위 "enabled" true→false (두 줄만 교체,
#      나머지 바이트 불변 확인). 이것이 naver_data_collector.R::.naver_assert_write_allowed 가 읽는
#      킬스위치와 같은 키다(그 함수는 enabled=true 면 과거 행 재작성을 막는다).
#   ② 백업 = RAWDATA 사본 + md5 대조   ③ Size 열의 계획 행만 교체
#   ④ tmp 기록 → **백업 대비 열별 identical() 대조**(Size 외 전 열 · Size 는 계획 행 밖 불변 · 계획 행 = QW 값)
#      + 스키마 대조   ⑤ RAWDATA 가 그 사이 바뀌었으면 중단   ⑥ rename(선삭제 없음·유한 재시도)
#   ⑦ (선택) factor_db 재빌드 — 스냅샷 Date ≥ start 인 월만, 백업 후   ⑧ 러너 복원 + 바이트 동일 확인
#
# 사용:
#   source("02_Infrastructure/config.R"); source("02_Infrastructure/data/rawdata_size_from_quantiwise.R")
#   r <- rawdata_size_from_quantiwise()                                   # dry-run (구간 = W-02 보수 보고서)
#   r <- rawdata_size_from_quantiwise(dry_run = FALSE, rebuild_fdb = TRUE)
# 검사: 08_Tests/data/test_rawdata_size_from_quantiwise.R
#==============================================================================
suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(readxl)
  library(jsonlite)
})

if (!exists("%||%")) `%||%` <- function(a, b) if (is.null(a)) b else a

.qws_root <- function() {
  if (exists("PROJECT_ROOT") && nzchar(PROJECT_ROOT)) return(PROJECT_ROOT)
  r <- gsub("\\\\", "/", Sys.getenv("QM_ROOT", unset = ""))
  if (nzchar(r) && dir.exists(r)) return(r)
  stop("[qw_size] PROJECT_ROOT/QM_ROOT 미설정 — 경로를 인자로 주거나 config.R 을 먼저 source 할 것")
}

# 판정 상수의 정본(코드에 되살리지 않는다):
#   scale_tol   = naver_collector_config.json::size_shares_tol (복원 경로와 같은 허용오차)
#   max_na_rate = cache_registry.json RAWDATA value_checks.fill_rate.max_na_rate (Size 경보와 같은 문턱)
.qws_scale_tol <- function(root = .qws_root()) {
  p <- file.path(root, "02_Infrastructure/data/naver_collector_config.json")
  v <- suppressWarnings(as.numeric(fromJSON(p)$size_shares_tol))
  if (length(v) != 1L || !is.finite(v) || v <= 0) stop("[qw_size] size_shares_tol 판독 실패: ", p)
  v
}
.qws_max_na_rate <- function(root = .qws_root()) {
  p <- file.path(root, "02_Infrastructure/data/cache_registry.json")
  reg <- fromJSON(p, simplifyVector = FALSE)
  ent <- Filter(function(c) identical(c$path, ".cache/RAWDATA.parquet"), reg$caches)
  v <- if (length(ent)) suppressWarnings(as.numeric(ent[[1]]$value_checks$fill_rate$max_na_rate)) else NA_real_
  if (length(v) != 1L || !is.finite(v) || v < 0 || v > 1) stop("[qw_size] fill_rate.max_na_rate 판독 실패: ", p)
  v
}

QWS_EXPECTED_UNIT <- "local"                       # 08-29 판 실측 (원 단위)
QWS_EXPECTED_ITEM <- "시가총액"    # '시가총액'
QWS_CALIB_SOURCES <- c("quantiwise", "quantiwise_update")

.qws_md5 <- function(p) unname(tools::md5sum(p))
.qws_fp <- function(p) {
  fi <- file.info(p)
  list(path = p, size = as.numeric(fi$size), mtime = format(fi$mtime, "%Y-%m-%d %H:%M:%OS3"),
       md5 = .qws_md5(p))
}

#------------------------------------------------------------------------------
# 1) QW 수출본 읽기 — readxl 은 파일을 통째로 읽고 핸들을 남기지 않는다
#------------------------------------------------------------------------------
#' @return list(long = data.table(Date, Ticker, QW_Size), meta = list(...), problems = character)
qws_read_qw_size <- function(xlsx, sheet = "Size", expected_unit = QWS_EXPECTED_UNIT,
                             expected_item = QWS_EXPECTED_ITEM, hdr_rows = 30L) {
  if (!file.exists(xlsx)) stop("[qw_size] xlsx 부재: ", xlsx)
  probs <- character(0)
  lock <- file.path(dirname(xlsx), paste0("~$", basename(xlsx)))
  meta <- list(file = .qws_fp(xlsx), lock_file_present = file.exists(lock), sheet = sheet)
  sh <- excel_sheets(xlsx)
  meta$sheets <- sh
  if (!sheet %in% sh) {
    return(list(long = NULL, meta = meta, problems = c(layout = sprintf("시트 '%s' 부재 (있는 것: %s)", sheet,
                                                                       paste(sh, collapse = ",")))))
  }
  hdr <- suppressWarnings(as.data.table(read_xlsx(xlsx, sheet = sheet, range = cell_rows(seq_len(hdr_rows)),
                                                  col_names = FALSE, col_types = "text",
                                                  .name_repair = "minimal")))
  lab <- trimws(hdr[[1]])
  r_code <- which(lab == "Code")[1]; r_unit <- which(lab == "Unit")[1]
  r_date <- which(lab == "D A T E")[1]; r_item_code <- which(lab == "Item Code")[1]
  r_b1 <- which(lab == "Refresh")[1]; r_from <- which(lab == "Period(From)")[1]; r_to <- which(lab == "Period(To)")[1]
  .cell <- function(r, j = 2L) if (is.na(r) || ncol(hdr) < j) NA_character_ else hdr[[j]][r]
  meta$stamp_b1 <- .cell(r_b1); meta$period_from <- .cell(r_from); meta$period_to <- .cell(r_to)
  meta$item_code <- .cell(r_item_code)
  if (anyNA(c(r_code, r_unit, r_date))) {
    return(list(long = NULL, meta = meta,
                problems = c(layout = "라벨 행(Code/Unit/D A T E) 인식 실패 — 수출본 형식 변경")))
  }
  codes_all <- vapply(hdr, function(v) v[r_code], character(1))
  units_all <- vapply(hdr, function(v) v[r_unit], character(1))
  items_all <- vapply(hdr, function(v) v[r_date], character(1))
  cj <- which(!is.na(codes_all) & nzchar(trimws(codes_all)))
  cj <- cj[cj >= 2L]
  if (!length(cj)) return(list(long = NULL, meta = meta, problems = c(layout = "코드 열 0개")))
  codes <- trimws(codes_all[cj])
  meta$n_codes <- length(codes)
  ub <- which(is.na(units_all[cj]) | trimws(units_all[cj]) != expected_unit)
  ib <- which(is.na(items_all[cj]) | trimws(items_all[cj]) != expected_item)
  .tab <- function(x) { t <- table(x, useNA = "ifany"); n <- names(t); n[is.na(n)] <- "<NA>"; as.list(setNames(as.integer(t), n)) }
  meta$unit_values <- .tab(units_all[cj])
  meta$item_values <- .tab(items_all[cj])
  if (length(ub) || length(ib))
    probs <- c(probs, unit_declared = sprintf("선언 불일치 — Unit≠'%s' %d열 · 항목≠'%s' %d열 (예: %s)",
                                              expected_unit, length(ub), expected_item, length(ib),
                                              paste(head(codes[unique(c(ub, ib))], 3), collapse = ",")))
  if (anyDuplicated(codes))
    probs <- c(probs, duplicate_keys = sprintf("QW 코드 중복 %d건", sum(duplicated(codes))))

  body <- suppressWarnings(read_xlsx(xlsx, sheet = sheet, skip = r_date, col_names = FALSE,
                                     col_types = "numeric", .name_repair = "minimal"))
  d <- as.Date(body[[1]], origin = "1899-12-30")
  keep <- which(!is.na(d))
  meta$n_dates <- length(keep)
  if (!length(keep)) return(list(long = NULL, meta = meta, problems = c(probs, layout = "데이터 행 0")))
  meta$first_date <- format(min(d[keep])); meta$horizon <- format(max(d[keep]))
  # 코드 없는 열에 값이 있으면 어느 종목 값인지 모른다 = 형식 오류
  extra <- setdiff(seq_len(ncol(body))[-1L], cj)
  if (length(extra)) {
    n_orphan <- sum(vapply(extra, function(j) sum(is.finite(body[[j]][keep])), numeric(1)))
    if (n_orphan > 0) probs <- c(probs, layout = sprintf("코드 없는 열에 값 %d칸", as.integer(n_orphan)))
  }
  vals <- lapply(cj, function(j) if (j <= ncol(body)) as.numeric(body[[j]][keep]) else rep(NA_real_, length(keep)))
  names(vals) <- codes
  m <- as.data.table(vals)
  m[, Date := d[keep]]
  long <- melt(m, id.vars = "Date", variable.name = "Ticker", value.name = "QW_Size", variable.factor = FALSE)
  if (anyDuplicated(long, by = c("Date", "Ticker")))
    probs <- c(probs, duplicate_keys = "QW (Date,Ticker) 중복")
  nonpos <- long[is.finite(QW_Size) & QW_Size <= 0, .N]
  if (nonpos > 0) probs <- c(probs, qw_nonpositive = sprintf("QW Size ≤ 0 %d칸", nonpos))
  rm(body, m, vals, hdr); gc(verbose = FALSE)
  list(long = long, meta = meta, problems = probs)
}

#------------------------------------------------------------------------------
# 2) 계획(순수 함수) — 구간 행마다 무엇을 할지
#------------------------------------------------------------------------------
#' @param win data.table(Date, Ticker, Size [, prov]) — RAWDATA 구간 행
#' @param qw  data.table(Date, Ticker, QW_Size)
#' @param on_qw_absent "na" = QW 에 값이 없으면 현재값(복원값)을 지운다(PIT 엄격) · "keep" = 둔다
qws_plan <- function(win, qw, on_qw_absent = c("na", "keep")) {
  on_qw_absent <- match.arg(on_qw_absent)
  p <- merge(as.data.table(win), qw[, .(Date, Ticker, QW_Size)], by = c("Date", "Ticker"),
             all.x = TRUE, sort = FALSE)
  p[, `:=`(qw_ok = is.finite(QW_Size), old_ok = is.finite(Size))]
  p[, action := fcase(qw_ok & old_ok & QW_Size == Size, "same",
                      qw_ok & old_ok, "replace",
                      qw_ok & !old_ok, "fill",
                      !qw_ok & old_ok & on_qw_absent == "na", "absent_to_na",
                      !qw_ok & old_ok, "absent_keep",
                      default = "both_na")]
  p[, new_Size := fcase(action %chin% c("same", "replace", "fill"), QW_Size,
                        action == "absent_to_na", NA_real_,
                        default = Size)]
  p[, rel := fifelse(qw_ok & old_ok & Size > 0, QW_Size / Size - 1, NA_real_)]
  p[, change := action %chin% c("replace", "fill", "absent_to_na")]
  setorder(p, Date, Ticker)
  p[]
}

.qws_q <- function(x, probs = c(0, .01, .05, .25, .5, .75, .95, .99, 1)) {
  x <- x[is.finite(x)]
  if (!length(x)) return(NULL)
  as.list(setNames(signif(quantile(x, probs, names = FALSE), 6), sprintf("p%g", probs * 100)))
}

#' 차이 분포 — 전체 · 출처(prov)별 · 날짜별 · 최대 사례
qws_diff_report <- function(p, tol) {
  both <- p[qw_ok & old_ok]
  by_prov <- if ("prov" %in% names(p)) p[, .(n = .N, n_change = sum(change), n_both = sum(qw_ok & old_ok),
                                           median_rel = if (any(is.finite(rel))) median(rel, na.rm = TRUE) else NA_real_,
                                           p99_abs_rel = if (any(is.finite(rel))) quantile(abs(rel), .99, na.rm = TRUE, names = FALSE) else NA_real_,
                                           n_abs_rel_gt_tol = sum(abs(rel) > tol, na.rm = TRUE)),
                                       by = .(prov, action)][order(prov, action)] else NULL
  by_date <- p[, .(n = .N, n_change = sum(change), n_fill = sum(action == "fill"),
                   n_absent_to_na = sum(action == "absent_to_na"),
                   median_rel = if (any(is.finite(rel))) median(rel, na.rm = TRUE) else NA_real_,
                   p99_abs_rel = if (any(is.finite(rel))) quantile(abs(rel), .99, na.rm = TRUE, names = FALSE) else NA_real_,
                   max_abs_rel = if (any(is.finite(rel))) max(abs(rel), na.rm = TRUE) else NA_real_,
                   n_abs_rel_gt_tol = sum(abs(rel) > tol, na.rm = TRUE)), by = Date][order(Date)]
  list(n_both = nrow(both),
       rel_quantiles = .qws_q(both$rel),
       abs_rel_quantiles = .qws_q(abs(both$rel)),
       n_abs_rel_gt_tol = both[abs(rel) > tol, .N], tol = tol,
       by_prov = by_prov, by_date = by_date,
       top_abs_rel = head(both[order(-abs(rel)), intersect(c("Date", "Ticker", "Size", "QW_Size", "rel", "prov"),
                                                         names(both)), with = FALSE], 30))
}

#------------------------------------------------------------------------------
# 3) 게이트 — 전부 계산하고(조기 종료 없음) 보고서에 남긴 뒤 거부한다
#------------------------------------------------------------------------------
qws_gates <- function(qwr, win, plan, calib, start, end, tol, max_na_rate, calib_min_equal) {
  g <- list()
  add <- function(name, pass, detail) g[[name]] <<- list(pass = isTRUE(pass), detail = detail)
  pr <- qwr$problems
  add("xlsx_locked", !isTRUE(qwr$meta$lock_file_present),
      if (isTRUE(qwr$meta$lock_file_present)) "~$ 잠금 파일 존재 — 엑셀이 열었거나 저장 중" else "잠금 파일 없음")
  add("layout", !any(names(pr) == "layout"), if (any(names(pr) == "layout")) paste(pr[names(pr) == "layout"], collapse = " | ") else "인식")
  add("unit_declared", !any(names(pr) == "unit_declared"),
      if (any(names(pr) == "unit_declared")) pr[["unit_declared"]] else sprintf("Unit=%s · 항목=%s", QWS_EXPECTED_UNIT, "시가총액"))
  hz <- suppressWarnings(as.Date(qwr$meta$horizon %||% NA_character_))
  add("horizon_short", is.finite(as.numeric(hz)) && hz >= end,
      sprintf("QW 지평선 %s vs 종료일 %s", format(hz), format(end)))
  wd <- sort(unique(win$Date))
  qd <- if (!is.null(qwr$long)) unique(qwr$long$Date) else as.Date(character(0))
  miss <- wd[!wd %in% qd]
  add("window_dates_missing", length(wd) > 0L && !length(miss),
      if (!length(wd)) "구간 안 RAWDATA 거래일 0 — 미측정" else if (length(miss))
        sprintf("QW 에 없는 구간 거래일 %d: %s", length(miss), paste(format(head(miss, 8)), collapse = ",")) else
        sprintf("구간 거래일 %d 전부 QW 보유", length(wd)))
  add("duplicate_keys", !any(names(pr) == "duplicate_keys") && !anyDuplicated(win, by = c("Date", "Ticker")),
      paste(c(pr[names(pr) == "duplicate_keys"],
              if (anyDuplicated(win, by = c("Date", "Ticker"))) "RAWDATA 구간 (Date,Ticker) 중복"), collapse = " | "))
  add("qw_nonpositive", !any(names(pr) == "qw_nonpositive"),
      if (any(names(pr) == "qw_nonpositive")) pr[["qw_nonpositive"]] else "양수")
  cs <- if (calib$n > 0) calib$n_equal / calib$n else NA_real_
  add("calibration", calib$n > 0 && is.finite(cs) && cs >= calib_min_equal,
      if (calib$n == 0) "구간 전 겹침 0행 — 단위 미측정(정상으로 접지 않는다)" else
        sprintf("구간 전 겹침 %d행 중 일치 %d (%.6f, 요구 ≥ %s)", calib$n, calib$n_equal, cs, format(calib_min_equal)))
  if (!is.null(plan)) {
    b <- plan[qw_ok & old_ok]
    if (nrow(b)) {
      med <- median(b$QW_Size / b$Size)
      add("window_scale", abs(med - 1) <= tol, sprintf("구간 median(QW/현재) = %.6f (허용 1±%s, n=%d)", med, format(tol), nrow(b)))
    } else add("window_scale", TRUE, "구간 안 양쪽 유효 0행 — 단위는 calibration 이 판정")
    fr <- plan[, .(n = .N, na_rate = mean(!qw_ok)), by = Date]
    badf <- fr[na_rate > max_na_rate]
    add("qw_fill", nrow(fr) > 0L && !nrow(badf),
        if (nrow(badf)) sprintf("QW 결측률 초과 %d일 (최대 %.4f > %s): %s", nrow(badf), max(badf$na_rate), format(max_na_rate),
                                paste(format(head(badf$Date, 6)), collapse = ",")) else
          sprintf("구간 날짜별 QW 결측률 최대 %.4f ≤ %s", if (nrow(fr)) max(fr$na_rate) else NA_real_, format(max_na_rate)))
  } else {
    add("window_scale", FALSE, "계획 미산출(xlsx 판독 실패)")
    add("qw_fill", FALSE, "계획 미산출(xlsx 판독 실패)")
  }
  g
}

#------------------------------------------------------------------------------
# 4) 러너 일시정지(= 킬스위치 해제) · 복원 — 두 줄만 바꾸고 나머지 바이트는 그대로
#------------------------------------------------------------------------------
.qws_read_text <- function(p) {
  b <- readBin(p, "raw", file.info(p)$size)
  s <- rawToChar(b); Encoding(s) <- "bytes"
  s
}
.qws_write_text_atomic <- function(p, s) {
  tmp <- file.path(dirname(p), sprintf(".%s.tmp_qws%d", basename(p), Sys.getpid()))
  con <- file(tmp, "wb"); writeBin(charToRaw(s), con); close(con)
  for (i in 1:8) {
    if (isTRUE(suppressWarnings(file.rename(tmp, p)))) return(invisible(TRUE))
    Sys.sleep(min(0.25, 0.02 * 2^(i - 1)))
  }
  suppressWarnings(file.remove(tmp))
  stop("[qw_size] 설정 파일 원자 교체 실패(rename): ", p)
}
.qws_top_lines <- function(s, key) {
  # 최상위 키 = 정확히 2칸 들여쓰기(중첩 블록 director.enabled 등은 4칸 이상)
  m <- gregexpr(sprintf('(?m)^  "%s": [^\\n]*$', key), s, perl = TRUE, useBytes = TRUE)[[1]]
  if (m[1] < 0) return(list(start = integer(0), len = integer(0)))
  list(start = as.integer(m), len = attr(m, "match.length"))
}

#' 최상위 enabled 를 false 로 내리고 paused_reason 을 표지로 바꾼다.
#' @return state list — restore 에 그대로 넘긴다. 이미 false 면 손대지 않는다(state="already_paused").
qws_runner_pause <- function(cfg_path, mark) {
  if (!file.exists(cfg_path)) return(list(state = "absent", path = cfg_path))
  s0 <- .qws_read_text(cfg_path)                       # "bytes" 표지 — substr/정규식이 바이트 오프셋으로 돈다
  j0 <- fromJSON(.qws_as_utf8(s0), simplifyVector = FALSE)
  if (!isTRUE(j0$enabled)) return(list(state = "already_paused", path = cfg_path, md5_orig = .qws_md5(cfg_path)))
  en <- .qws_top_lines(s0, "enabled"); pr <- .qws_top_lines(s0, "paused_reason")
  if (length(en$start) != 1L || length(pr$start) != 1L)
    stop(sprintf("[qw_size] 러너 설정의 최상위 enabled/paused_reason 줄을 하나로 특정 못함(%d/%d) — 손대지 않음",
                 length(en$start), length(pr$start)))
  l_en <- substr(s0, en$start, en$start + en$len - 1L)
  if (!grepl('^  "enabled": true,\r?$', l_en, useBytes = TRUE))
    stop("[qw_size] 최상위 enabled 줄 형식이 예상과 다름 — 손대지 않음: ", l_en)
  eol <- if (grepl("\r$", l_en, useBytes = TRUE)) "\r" else ""
  new_en <- paste0('  "enabled": false,', eol)
  new_pr <- paste0('  "paused_reason": ', as.character(toJSON(enc2utf8(mark), auto_unbox = TRUE)), ',', eol)
  Encoding(new_pr) <- "bytes"
  # 뒤쪽 줄부터 갈아끼워 앞쪽 오프셋을 보존
  segs <- list(list(st = en$start, ln = en$len, txt = new_en), list(st = pr$start, ln = pr$len, txt = new_pr))
  segs <- segs[order(-vapply(segs, `[[`, integer(1), "st"))]
  s1 <- s0
  for (g in segs) s1 <- paste0(substr(s1, 1L, g$st - 1L), g$txt, substr(s1, g$st + g$ln, nchar(s1, type = "bytes")))
  j1 <- fromJSON(.qws_as_utf8(s1), simplifyVector = FALSE)
  j0x <- j0; j1x <- j1; j0x$enabled <- NULL; j1x$enabled <- NULL; j0x$paused_reason <- NULL; j1x$paused_reason <- NULL
  if (!identical(j1$enabled, FALSE) || !identical(j0x, j1x))
    stop("[qw_size] 러너 설정 편집 검증 실패(enabled 외 값이 바뀌었거나 false 가 아님) — 쓰지 않음")
  md5_orig <- .qws_md5(cfg_path)
  .qws_write_text_atomic(cfg_path, s1)
  list(state = "paused_by_us", path = cfg_path, orig = s0, mine = s1, md5_orig = md5_orig,
       md5_paused = .qws_md5(cfg_path))
}
.qws_as_utf8 <- function(s) { s <- rawToChar(charToRaw(s)); Encoding(s) <- "UTF-8"; s }

#' 우리가 쓴 두 줄이 그대로일 때만 원본 바이트로 되돌린다(남이 바꿨으면 손대지 않고 알린다).
qws_runner_restore <- function(st) {
  if (is.null(st) || !identical(st$state, "paused_by_us")) return(list(restored = FALSE, reason = st$state %||% "none"))
  cur <- .qws_read_text(st$path)
  if (identical(cur, st$orig)) return(list(restored = TRUE, reason = "already_original", byte_identical = TRUE))
  if (!identical(cur, st$mine)) {
    warning("[qw_size] 러너 설정이 작업 중 제3자에 의해 바뀌었다 — 복원하지 않음: ", st$path)
    return(list(restored = FALSE, reason = "changed_by_other"))
  }
  .qws_write_text_atomic(st$path, st$orig)
  ok <- identical(.qws_md5(st$path), st$md5_orig)
  if (!ok) warning("[qw_size] 러너 설정 복원 후 md5 불일치: ", st$path)
  list(restored = TRUE, reason = "restored", byte_identical = ok)
}

#' .naver_assert_write_allowed 와 같은 술어(파일 부재 = 허용 · 판독 실패 = 차단).
qws_write_allowed <- function(cfg_path) {
  if (!file.exists(cfg_path)) return(TRUE)
  en <- tryCatch(isTRUE(fromJSON(cfg_path)$enabled), error = function(e) TRUE)
  !en
}

#------------------------------------------------------------------------------
# 5) 기록 후 대조 — 백업(원본) 대비 열별 identical()
#------------------------------------------------------------------------------
#' @param ref  원본 parquet(백업) · @param cand 새 parquet(tmp)
#' @param idx  계획상 Size 가 바뀌는 행 번호 · @param new_vals 그 행의 새 값
qws_verify_file <- function(ref, cand, idx, new_vals) {
  s_ref <- open_dataset(ref)$schema; s_cnd <- open_dataset(cand)$schema
  out <- list(schema_equal = isTRUE(s_ref$Equals(s_cnd)), cols = list(), problems = character(0))
  if (!out$schema_equal) out$problems <- c(out$problems, "스키마 불일치")
  cols <- s_ref$names
  if (!identical(cols, s_cnd$names)) { out$problems <- c(out$problems, "열 목록 불일치"); return(out) }
  for (cc in cols) {
    a <- read_parquet(ref, col_select = tidyselect::all_of(cc), mmap = FALSE)[[1]]
    b <- read_parquet(cand, col_select = tidyselect::all_of(cc), mmap = FALSE)[[1]]
    if (length(a) != length(b)) { out$problems <- c(out$problems, sprintf("%s 행 수 불일치", cc)); next }
    if (cc != "Size") {
      same <- identical(a, b)
      out$cols[[cc]] <- same
      if (!same) out$problems <- c(out$problems, sprintf("%s 열이 바뀌었다(Size 외 열 변경 금지)", cc))
    } else {
      diffpos <- which(!((a == b) %in% TRUE) & !(is.na(a) & is.na(b)))
      outside <- setdiff(diffpos, idx)
      inside_ok <- identical(b[idx], new_vals)
      out$cols[[cc]] <- list(n_changed = length(diffpos), n_outside_plan = length(outside), plan_values_ok = inside_ok)
      if (length(outside)) out$problems <- c(out$problems, sprintf("Size 가 계획 밖 %d행에서 바뀌었다", length(outside)))
      if (!inside_ok) out$problems <- c(out$problems, "계획 행의 Size 가 QW 값과 다르다")
    }
    rm(a, b)
  }
  gc(verbose = FALSE)
  out$ok <- !length(out$problems)
  out
}

#------------------------------------------------------------------------------
# 6) 구간·출처 재도출
#------------------------------------------------------------------------------
.qws_window_from_report <- function(p) {
  if (is.null(p) || !file.exists(p)) return(NULL)
  r <- fromJSON(p)
  if (!isTRUE(r$size_only) || isTRUE(r$dry_run)) return(NULL)
  list(start = as.Date(r$start), end = as.Date(r$end), source = p)
}
.qws_prov <- function(win, pre_repair_backup, start, end) {
  if (is.null(pre_repair_backup) || !file.exists(pre_repair_backup)) {
    win[, prov := "unknown"]; return(list(win = win, source = NA_character_))
  }
  pre <- as.data.table(read_parquet(pre_repair_backup, col_select = c("Date", "Ticker", "Size"), mmap = FALSE))
  pre[, Date := as.Date(Date)]
  pre <- pre[Date >= start & Date <= end, .(Date, Ticker, Size_pre = Size)]
  win <- merge(win, pre, by = c("Date", "Ticker"), all.x = TRUE, sort = FALSE)
  win[, prov := fcase(!is.finite(Size), "na_now",
                      !is.finite(Size_pre), "reconstructed",
                      Size_pre == Size, "pre_existing",
                      default = "pre_existing_changed")]
  win[, Size_pre := NULL]
  rm(pre); gc(verbose = FALSE)
  list(win = win, source = pre_repair_backup)
}
.qws_latest_repair_backup <- function(dir) {
  f <- list.files(dir, pattern = "^RAWDATA\\.parquet\\.bak_size_repair_\\d{8}_\\d{6}$", full.names = TRUE)
  if (!length(f)) NULL else sort(f, decreasing = TRUE)[1]
}

.qws_write_json <- function(x, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  js <- toJSON(x, auto_unbox = TRUE, digits = NA, na = "null", pretty = TRUE, null = "null")
  tmp <- paste0(path, ".tmp", Sys.getpid())
  writeLines(js, tmp, useBytes = TRUE)
  if (!isTRUE(file.rename(tmp, path))) { suppressWarnings(file.remove(tmp)); stop("[qw_size] 보고서 기록 실패: ", path) }
  path
}

.qws_refuse <- function(msg, report) {
  structure(class = c("qw_size_refused", "error", "condition"),
            list(message = msg, call = NULL, report = report))
}

#------------------------------------------------------------------------------
# 7) factor_db 재빌드 — 스냅샷 Date ≥ start 인 월만(그 달 팩터가 구간 Size 를 읽는다)
#------------------------------------------------------------------------------
.qws_rebuild_fdb <- function(start, fdb_dir, backup_dir, builder, stamp) {
  f <- list.files(fdb_dir, pattern = "^factor_db_\\d{6}\\.parquet$", full.names = TRUE)
  res <- list()
  for (fp in sort(f)) {
    sd <- tryCatch(unique(as.Date(read_parquet(fp, col_select = "Date", mmap = FALSE)$Date)), error = function(e) NA)
    if (length(sd) != 1L || !is.finite(as.numeric(sd)) || sd < start) next
    ym <- sub("^factor_db_(\\d{6})\\.parquet$", "\\1", basename(fp))
    bdir <- file.path(backup_dir, sprintf("fdb_bak_qws_%s", stamp)); dir.create(bdir, recursive = TRUE, showWarnings = FALSE)
    bk <- file.path(bdir, basename(fp))
    if (!isTRUE(file.copy(fp, bk, overwrite = FALSE)) || !identical(.qws_md5(bk), .qws_md5(fp)))
      stop("[qw_size] factor_db 백업 실패 — 재빌드 중단: ", fp)
    side <- file.path(fdb_dir, "_asof", sprintf("factor_db_%s.json", ym))
    if (file.exists(side)) file.copy(side, file.path(bdir, basename(side)), overwrite = FALSE)
    gc(verbose = FALSE)
    t0 <- Sys.time()
    builder(sd)
    sd2 <- tryCatch(unique(as.Date(read_parquet(fp, col_select = "Date", mmap = FALSE)$Date)), error = function(e) NA)
    res[[ym]] <- list(sig_date = format(sd), backup = bk, rebuilt_label = paste(format(sd2), collapse = ","),
                      label_kept = identical(sd2, sd), secs = round(as.numeric(difftime(Sys.time(), t0, units = "secs")), 1))
  }
  res
}

#------------------------------------------------------------------------------
# 본체
#------------------------------------------------------------------------------
#' @param start,end  교체 구간. NULL 이면 W-02 Size 보수 보고서(latest_apply_size_backfill.json)에서 재도출.
#' @param dry_run    TRUE(기본) = 계획·게이트·차이 분포만. RAWDATA·러너 설정 무접촉.
#' @param on_qw_absent "na"(기본 — 복원값 제거, PIT 엄격) | "keep"
#' @param rebuild_fdb 교체 후 factor_db 재빌드(스냅샷 Date ≥ start 인 월만) — 러너 정지 중 수행
#' @param .inject, .hook_before_rename, .fdb_build  검사 전용 주입점(운영 호출에서 쓰지 말 것)
rawdata_size_from_quantiwise <- function(start = NULL, end = NULL,
                                         xlsx = NULL, rawdata = NULL,
                                         dry_run = TRUE,
                                         on_qw_absent = c("na", "keep"),
                                         rebuild_fdb = FALSE,
                                         out_dir = NULL, backup_dir = NULL,
                                         runner_config = NULL, fdb_dir = NULL,
                                         pre_repair_backup = "auto",
                                         window_report = "auto",
                                         calib_min_equal = 0.999,
                                         scale_tol = NULL, max_na_rate = NULL,
                                         .inject = NULL, .hook_before_rename = NULL, .fdb_build = NULL) {
  on_qw_absent <- match.arg(on_qw_absent)
  t_start <- Sys.time(); stamp <- format(t_start, "%Y%m%d_%H%M%S")
  root <- tryCatch(.qws_root(), error = function(e) NA_character_)
  .need_root <- function(what) if (is.na(root)) stop("[qw_size] ", what, " 기본값에 PROJECT_ROOT 필요 — 인자로 줄 것") else root
  xlsx <- xlsx %||% file.path(.need_root("xlsx"), "03_Universe/Update_File/OHLCVS_update.xlsx")
  rawdata <- rawdata %||% file.path(.need_root("rawdata"), ".cache/RAWDATA.parquet")
  out_dir <- out_dir %||% file.path(dirname(rawdata), "rawdata_size_qw")
  backup_dir <- backup_dir %||% dirname(rawdata)
  runner_config <- runner_config %||% file.path(.need_root("runner_config"), "06_Registry/reinforce_auto_config.json")
  fdb_dir <- fdb_dir %||% file.path(dirname(rawdata), "factor_db")
  scale_tol <- scale_tol %||% .qws_scale_tol(.need_root("scale_tol"))
  max_na_rate <- max_na_rate %||% .qws_max_na_rate(.need_root("max_na_rate"))
  if (identical(window_report, "auto")) window_report <- file.path(dirname(rawdata), "naver_recollect", "latest_apply_size_backfill.json")
  if (identical(pre_repair_backup, "auto")) pre_repair_backup <- .qws_latest_repair_backup(dirname(rawdata))

  # ── 구간 ──
  win_src <- "argument"
  if (is.null(start) || is.null(end)) {
    w <- .qws_window_from_report(window_report)
    if (is.null(w)) stop("[qw_size] start/end 미지정이고 W-02 보수 보고서에서 재도출 불가: ", window_report %||% "NULL")
    start <- start %||% w$start; end <- end %||% w$end; win_src <- paste0("report:", w$source)
  }
  start <- as.Date(start); end <- as.Date(end)
  if (!is.finite(as.numeric(start)) || !is.finite(as.numeric(end)) || start > end) stop("[qw_size] 구간 오류: ", start, " ~ ", end)
  cat(sprintf("[qw_size] 구간 %s~%s (%s) · dry_run=%s · on_qw_absent=%s\n", start, end, win_src, dry_run, on_qw_absent))

  # ── QW ──
  qwr <- qws_read_qw_size(xlsx)
  cat(sprintf("[qw_size] QW %s · 지평선 %s · 날짜 %s · 코드 %s · B1 '%s' · To '%s'\n", basename(xlsx),
              qwr$meta$horizon %||% "?", qwr$meta$n_dates %||% "?", qwr$meta$n_codes %||% "?",
              qwr$meta$stamp_b1 %||% "?", qwr$meta$period_to %||% "?"))

  # ── RAWDATA ──
  if (!file.exists(rawdata)) stop("[qw_size] RAWDATA 부재: ", rawdata)
  fp0 <- .qws_fp(rawdata)
  cols_needed <- c("Date", "Ticker", "Size", "source")
  lite <- as.data.table(read_parquet(rawdata, col_select = tidyselect::all_of(cols_needed), mmap = FALSE))
  lite[, Date := as.Date(Date)]
  win <- lite[Date >= start & Date <= end, .(Date, Ticker, Size, source)]
  # 단위 측정 — 구간 전 겹침(퀀티 출처 행)
  calib <- list(n = 0L, n_equal = 0L, by_source = NULL, mismatch_examples = NULL)
  if (!is.null(qwr$long)) {
    qmin <- min(qwr$long$Date)
    cb <- lite[Date >= qmin & Date < start & source %chin% QWS_CALIB_SOURCES & is.finite(Size)]
    cb <- merge(cb, qwr$long[is.finite(QW_Size)], by = c("Date", "Ticker"))
    calib$n <- nrow(cb); calib$n_equal <- cb[QW_Size == Size, .N]
    calib$date_range <- if (nrow(cb)) c(format(min(cb$Date)), format(max(cb$Date))) else NULL
    calib$by_source <- cb[, .(n = .N, n_equal = sum(QW_Size == Size)), by = source]
    calib$mismatch_examples <- head(cb[QW_Size != Size][order(-abs(QW_Size / Size - 1))], 30)
    rm(cb)
  }
  rm(lite); gc(verbose = FALSE)
  pv <- .qws_prov(win, pre_repair_backup, start, end)
  win <- pv$win

  plan <- if (!is.null(qwr$long)) qws_plan(win, qwr$long, on_qw_absent) else NULL
  gates <- qws_gates(qwr, win, plan, calib, start, end, scale_tol, max_na_rate, calib_min_equal)
  failed <- names(gates)[!vapply(gates, `[[`, logical(1), "pass")]
  qw_only <- if (!is.null(qwr$long)) qwr$long[Date >= start & Date <= end & is.finite(QW_Size)][!win, on = .(Date, Ticker), .N] else NA_integer_

  report <- list(
    schema = "rawdata_size_from_quantiwise_v1",
    generated_at = format(t_start, "%Y-%m-%dT%H:%M:%S%z"),
    decision_ref = "도훈 2026-09-23 '복원 Size 의 PIT 엄격화 = 퀀티와이즈 데이터로 대체'",
    dry_run = dry_run, status = if (length(failed)) "REFUSED" else if (dry_run) "PLANNED" else "APPLYING",
    refused_gates = failed,
    window = list(start = format(start), end = format(end), source = win_src,
                  rawdata_dates = format(sort(unique(win$Date))), n_rows = nrow(win)),
    qw = qwr$meta, qw_problems = as.list(qwr$problems),
    rawdata = fp0, provenance_source = pv$source,
    params = list(on_qw_absent = on_qw_absent, calib_min_equal = calib_min_equal,
                  scale_tol = scale_tol, max_na_rate = max_na_rate,
                  scale_tol_source = "naver_collector_config.json::size_shares_tol",
                  max_na_rate_source = "cache_registry.json RAWDATA fill_rate.max_na_rate"),
    gates = gates, calibration = calib,
    plan_counts = if (!is.null(plan)) as.list(setNames(plan[, .N, by = action]$N, plan[, .N, by = action]$action)) else NULL,
    n_change = if (!is.null(plan)) sum(plan$change) else NA_integer_,
    qw_only_rows_ignored = qw_only,
    diff = if (!is.null(plan)) qws_diff_report(plan, scale_tol) else NULL
  )
  rp <- file.path(out_dir, sprintf("qw_size_%s_%s.json", if (dry_run) "dryrun" else "apply", stamp))

  if (length(failed)) {
    .qws_write_json(report, rp)
    for (nm in failed) cat(sprintf("[qw_size] ⛔ 거부 [%s] %s\n", nm, gates[[nm]]$detail))
    cat(sprintf("[qw_size] 보고서: %s\n", rp))
    stop(.qws_refuse(sprintf("[qw_size] 거부 — %s", paste(failed, collapse = ",")), c(report, list(path = rp))))
  }
  cat(sprintf("[qw_size] 계획: %s · 교체 대상 %d행\n",
              paste(sprintf("%s=%d", names(report$plan_counts), unlist(report$plan_counts)), collapse = " "), report$n_change))
  if (isTRUE(dry_run)) {
    .qws_write_json(report, rp)
    cat(sprintf("[qw_size] DRY-RUN — RAWDATA·러너 설정 미수정 · 보고서: %s\n", rp))
    return(invisible(list(report = report, plan = plan, path = rp)))
  }

  #============================== 실행 모드 ==============================
  if (report$n_change == 0L) {
    report$status <- "NOOP"; .qws_write_json(report, rp)
    cat("[qw_size] 교체 대상 0행 — 쓰지 않는다\n")
    return(invisible(list(report = report, plan = plan, path = rp)))
  }
  apply_log <- list()
  rs <- NULL; restored <- NULL
  tmp <- file.path(dirname(rawdata), sprintf(".%s.tmp_qws%d", basename(rawdata), Sys.getpid()))
  on.exit({
    if (file.exists(tmp)) suppressWarnings(file.remove(tmp))
    if (is.null(restored) && !is.null(rs)) {
      rr <- tryCatch(qws_runner_restore(rs), error = function(e) list(restored = FALSE, reason = conditionMessage(e)))
      cat(sprintf("[qw_size] (종료 경로) 러너 설정 복원: %s\n", rr$reason))
    }
  }, add = TRUE)

  mark <- sprintf("(QW Size 교체 일시정지) %s rawdata_size_from_quantiwise %s~%s — 종료 시 자동 복원",
                  format(t_start, "%Y-%m-%d %H:%M"), format(start), format(end))
  rs <- qws_runner_pause(runner_config, mark)
  apply_log$runner <- rs$state
  cat(sprintf("[qw_size] 러너: %s\n", rs$state))
  if (!qws_write_allowed(runner_config))
    stop("[qw_size] ⛔ 킬스위치(reinforce_auto_config.json::enabled) 가 여전히 true — 과거 행 재작성 차단")

  # 백업
  dir.create(backup_dir, recursive = TRUE, showWarnings = FALSE)
  bk <- file.path(backup_dir, sprintf("%s.bak_size_qw_%s", basename(rawdata), stamp))
  if (!isTRUE(file.copy(rawdata, bk, overwrite = FALSE))) stop("[qw_size] ⛔ 백업 실패 — 쓰기 중단: ", bk)
  if (!identical(.qws_md5(bk), fp0$md5)) stop("[qw_size] ⛔ 백업 md5 불일치(또는 RAWDATA 가 계획 뒤 바뀜) — 쓰기 중단: ", bk)
  apply_log$backup <- list(path = bk, md5 = fp0$md5)
  cat(sprintf("[qw_size] 백업: %s\n", bk))

  # 전량 로드 → Size 만 교체
  raw <- as.data.table(read_parquet(rawdata, mmap = FALSE))
  wi <- which(as.Date(raw$Date) >= start & as.Date(raw$Date) <= end)   # 키 문자열은 구간 안에서만 만든다(14M행 전량 금지)
  kr <- paste0(format(as.Date(raw$Date[wi])), "|", raw$Ticker[wi])
  chg <- plan[change == TRUE]
  idx <- wi[match(paste0(format(chg$Date), "|", chg$Ticker), kr)]
  if (anyNA(idx) || anyDuplicated(idx)) stop("[qw_size] ⛔ 계획 행이 RAWDATA 에 없다/중복(키 불일치) — 쓰기 중단")
  rm(kr, wi); gc(verbose = FALSE)
  if (!identical(raw$Size[idx], chg$Size)) stop("[qw_size] ⛔ 계획 뒤 RAWDATA Size 가 바뀌었다 — 쓰기 중단")
  new_vals <- as.numeric(chg$new_Size)
  set(raw, i = idx, j = "Size", value = new_vals)
  if (is.function(.inject)) raw <- .inject(raw)

  write_parquet(raw, tmp)
  rm(raw); gc(verbose = FALSE)
  ver <- qws_verify_file(bk, tmp, idx, new_vals)
  apply_log$verify <- ver[c("ok", "schema_equal", "problems", "cols")]
  if (!isTRUE(ver$ok)) {
    report$status <- "ABORTED"; report$apply <- apply_log; .qws_write_json(report, rp)
    stop(sprintf("[qw_size] ⛔ 기록물 대조 실패 — RAWDATA 미수정: %s (보고서 %s)", paste(ver$problems, collapse = " | "), rp))
  }
  cat(sprintf("[qw_size] 대조 통과 — Size 외 %d열 identical · Size 변경 %d행(계획 밖 0)\n",
              sum(vapply(ver$cols[names(ver$cols) != "Size"], isTRUE, logical(1))), ver$cols$Size$n_changed))
  if (is.function(.hook_before_rename)) .hook_before_rename()
  fp1 <- .qws_fp(rawdata)
  if (!identical(fp1$md5, fp0$md5) || !identical(fp1$size, fp0$size)) {
    report$status <- "ABORTED"; apply_log$concurrency <- list(before = fp0, now = fp1); report$apply <- apply_log
    .qws_write_json(report, rp)
    stop("[qw_size] ⛔ 작업 중 RAWDATA 가 다른 쓰기로 바뀌었다 — 덮지 않고 중단(보고서 ", rp, ")")
  }
  md5_tmp <- .qws_md5(tmp)
  gc(verbose = FALSE)
  renamed <- FALSE
  for (i in 1:8) {
    if (isTRUE(suppressWarnings(file.rename(tmp, rawdata)))) { renamed <- TRUE; break }
    Sys.sleep(min(0.25, 0.02 * 2^(i - 1)))
  }
  if (!renamed) stop("[qw_size] ⛔ rename 실패(소비자가 RAWDATA 점유 중) — RAWDATA 미수정")
  if (!identical(.qws_md5(rawdata), md5_tmp)) {
    file.copy(bk, rawdata, overwrite = TRUE)
    stop("[qw_size] ⛔ 교체 후 md5 불일치 — 백업으로 되돌림")
  }
  apply_log$rawdata_after <- .qws_fp(rawdata)
  apply_log$n_size_changed <- length(idx)
  cat(sprintf("[qw_size] RAWDATA 갱신: Size %d행 (구간 %s~%s)\n", length(idx), start, end))

  # factor_db 재빌드(선택) — 러너 정지 중
  if (isTRUE(rebuild_fdb)) {
    builder <- .fdb_build %||% local({
      function(sig) {
        if (!exists("build_factor_db")) source(file.path(.need_root("factor_db"), "02_Infrastructure/factor_db/factor_db_builder.R"))
        .load_base_data(force = TRUE)       # 세션에 옛 RAWDATA 가 실려 있으면 그걸로 빌드한다 — 강제 재적재
        build_factor_db(sig, save = TRUE, force = TRUE)
        invisible(TRUE)
      }
    })
    apply_log$fdb <- .qws_rebuild_fdb(start, fdb_dir, backup_dir, builder, stamp)
    cat(sprintf("[qw_size] factor_db 재빌드: %s\n", if (length(apply_log$fdb)) paste(names(apply_log$fdb), collapse = ",") else "대상 없음"))
  }

  restored <- qws_runner_restore(rs)
  apply_log$runner_restore <- restored
  cat(sprintf("[qw_size] 러너 설정 복원: %s%s\n", restored$reason,
              if (isTRUE(restored$byte_identical)) " (바이트 동일)" else ""))
  report$status <- "APPLIED"; report$apply <- apply_log
  .qws_write_json(report, rp)
  cat(sprintf("[qw_size] 보고서: %s\n", rp))
  invisible(list(report = report, plan = plan, path = rp, backup = bk))
}

cat("[rawdata_size_from_quantiwise] Loaded. rawdata_size_from_quantiwise(dry_run = TRUE)\n")
