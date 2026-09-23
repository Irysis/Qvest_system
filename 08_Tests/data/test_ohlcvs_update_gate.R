#!/usr/bin/env Rscript
#==============================================================================
# test_ohlcvs_update_gate.R — OHLCVS_update.xlsx 적재 안전 관문 (양방향 · 2026-09-23)
#
# 왜 (적대 검증 [높음] 2026-09-23): qw_refresh.ps1 은 목표일 도달 판정 전에 $wb.Save() 하고
#   finally 에서 Close($true) 로 또 저장한다 → 갱신 실패·중단에도 xlsx mtime 이 바뀌고,
#   daily_refresh [0b] incremental_update_all() → incremental_ohlcvs() 가 그 파일을 적재한다.
#   지평선이 그대로(08-28)여도 Ret 전 이력 재계산이 naver 이음매(08-31) Ret 을 조정기준 단절 그대로
#   되살린다(실측 1,715행 · A001470 +1,577%). 시트 일부만 갱신된 채 저장되면 Size 가 NA 로 교체될 수 있다.
#
# 무엇을 재나:
#   A 판정 순수 함수 — 양성 대조(전진·일치) + 사유 6종(전진 없음·불일치·직전 미측정·시트 순서·날짜축 부재·판독 오류)
#   B 실물 형식 합성 xlsx 판독 — 7시트 중 날짜축(DATA_Key 제외) · 머리 'Refresh'=0 을 날짜로 안 센다
#   C 직전 적재 지평선 — RAWDATA 퀀티 출처 max(naver 무시) · 부재/0행 = NA
#   D 통합(거부) — incremental_update_all: stop([GATE_REFUSED]) · RAWDATA md5 불변 · OHLCVS 처리 완료 미기록
#     · 다른 파일은 처리·기록 · 판정 기록 JSON · 다음 실행이 재시도(변경 재감지)
#   E 통합(지평선 불일치 — Size 시트 하루 뒤짐) 거부
#   F 통합(양성 대조) — 전진·일치면 관문 통과해 적재 경로로 진행 / 지평선 행이 빈 Size 시트는 파싱 후 거부
#   M 돌연변이 6종 red — 거부 반환 삭제 · 판정 항상 통과 · OHLCVS 기록 유지 삭제 · 끝 stop 삭제 · 불일치 판정 삭제 · 빈 행 거부 삭제
#
# 격리: 적재기 파일을 **파싱해서 필요한 정의만** 격리 env 에 올린다(config·캘린더 적재 없음).
#   UPDATE_DIR·CACHE_DIR·상태 파일·판정 기록 = 전부 tempdir. 운영 .cache·원장·로그 쓰기 0.
#   QW_GATE_SRC 로 검사 대상 파일을 바꿀 수 있다(배포 전 스크래치 사본 검사용).
#
# 실행: R_ENVIRON_USER=<빈 파일> Rscript 08_Tests/data/test_ohlcvs_update_gate.R   (또는 Rscript --no-environ)
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow); library(readxl) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
SRC  <- Sys.getenv("QW_GATE_SRC", file.path(ROOT, "02_Infrastructure/data/incremental_update_file.R"))
if (!requireNamespace("openxlsx", quietly = TRUE)) {
  cat("FAIL: openxlsx 없음 — 합성 xlsx 를 못 만든다(미측정은 통과가 아니다)\n")
  cat('{"test":"ohlcvs_update_gate","pass":0,"fail":1,"total":1,"skipped":0}\n'); quit(status = 1)
}
PASS <- 0L; FAIL <- 0L
ok <- function(m) { PASS <<- PASS + 1L; cat("  OK  ", m, "\n") }
ng <- function(m, why = "") { FAIL <<- FAIL + 1L; cat("  FAIL", m, if (nzchar(why)) paste0(" — ", why) else "", "\n") }
chk <- function(cond, m, why = "") if (isTRUE(cond)) ok(m) else ng(m, why)
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a

src_lines <- sub("\r$", "", readLines(SRC, warn = FALSE, encoding = "UTF-8"))
cat(sprintf("[test_ohlcvs_update_gate] 대상: %s (%d줄)\n", SRC, length(src_lines)))

WANTED <- c(".OHLCVS_VAR_SHEETS", ".OHLCVS_QW_SOURCES", "ohlcvs_sheet_horizons", ".ohlcvs_prior_horizon",
            "ohlcvs_update_gate", ".ohlcvs_horizon_fill_problems", ".ohlcvs_gate_print",
            ".ohlcvs_gate_record", ".ohlcvs_refuse", "incremental_ohlcvs", "incremental_update_all",
            "detect_update_changes", ".get_last_processed", ".save_last_processed")

load_defs <- function(lines, env) {
  exprs <- parse(text = lines, keep.source = FALSE, encoding = "UTF-8")
  for (e in exprs)
    if (is.call(e) && identical(as.character(e[[1]]), "<-") && is.name(e[[2]]) &&
        as.character(e[[2]]) %in% WANTED) eval(e, envir = env)
  miss <- setdiff(WANTED, ls(env, all.names = TRUE))
  if (length(miss)) stop("정의 미발견: ", paste(miss, collapse = ", "))
  invisible(env)
}
# 정확히 한 줄(앞뒤 공백 포함 일치)을 바꾼 사본 — 돌연변이
mutate_line <- function(lines, exact, repl) {
  hit <- which(lines == exact)
  if (length(hit) != 1L) stop(sprintf("돌연변이 대상 줄 %d개(1개여야): %s", length(hit), exact))
  lines[hit] <- repl
  lines
}
mutate_sub <- function(lines, fixed_pat, repl) {
  hit <- which(grepl(fixed_pat, lines, fixed = TRUE))
  if (length(hit) != 1L) stop(sprintf("돌연변이 대상 줄 %d개(1개여야): %s", length(hit), fixed_pat))
  lines[hit] <- sub(fixed_pat, repl, lines[hit], fixed = TRUE)
  lines
}

TMP <- tempfile("ohlcvs_gate_"); dir.create(TMP)   # tempdir() 아래 — R 종료 시 함께 지워진다
serial <- function(d) as.numeric(as.Date(d)) + 25569   # Excel 1900 serial (origin 1899-12-30)
TICK <- c("A000010", "A000020", "A000030")

#------------------------------------------------------------------------------
# 합성 수출본 — 실물 형식(08-29 판 실측): 1 Refresh/0 · 5 Period(From) · 6 Period(To) · 8 Code · 11 Unit
#   · 14 'D A T E' · 15~ 데이터. 시트 7장 = Open High Low Close Vol Size + DATA_Key(날짜축 없음)
#------------------------------------------------------------------------------
make_sheet_matrix <- function(dates, val_fun, empty_last = FALSE) {
  nc <- 1L + length(TICK)
  hdr <- list(c("Refresh", "0"), c("0"), c("Time Series (Company)"), c("Frequency", "Daily"),
              c("Period(From)", "20260330"), c("Period(To)", "CPD-1TD"), character(0),
              c("Code", TICK), c("Name", paste0("N", seq_along(TICK))), c("Item Code", rep("S000", length(TICK))),
              c("Unit", rep("local", length(TICK))), c("Base Date"), character(0), c("D A T E", rep("item", length(TICK))))
  M <- matrix(NA_character_, nrow = length(hdr) + length(dates), ncol = nc)
  for (r in seq_along(hdr)) if (length(hdr[[r]])) M[r, seq_along(hdr[[r]])] <- hdr[[r]]
  for (k in seq_along(dates)) {
    M[length(hdr) + k, 1] <- format(serial(dates[k]))
    v <- val_fun(k, dates[k])
    if (!(empty_last && k == length(dates))) M[length(hdr) + k, -1] <- format(v)
  }
  M
}
write_qw_xlsx <- function(path, sheet_dates, sheet_order = c("Open", "High", "Low", "Close", "Vol", "Size"),
                          empty_last = character(0), data_key = TRUE) {
  wb <- openxlsx::createWorkbook()
  for (s in sheet_order) {
    d <- sheet_dates[[s]]
    M <- make_sheet_matrix(as.Date(d), function(k, dd) 1000 + 10 * k + seq_along(TICK), empty_last = s %in% empty_last)
    openxlsx::addWorksheet(wb, s)
    openxlsx::writeData(wb, s, as.data.frame(M, stringsAsFactors = FALSE), colNames = FALSE)
  }
  if (data_key) {
    openxlsx::addWorksheet(wb, "DATA_Key")
    openxlsx::writeData(wb, "DATA_Key", data.frame(a = c("상폐종목포함 KSE+KOSDAQ 전체종목 리스트", TICK)), colNames = FALSE)
  }
  openxlsx::saveWorkbook(wb, path, overwrite = TRUE)
  path
}
same_dates <- function(d) setNames(rep(list(d), 6), c("Open", "High", "Low", "Close", "Vol", "Size"))

D_OLD <- as.Date(c("2026-08-26", "2026-08-27", "2026-08-28"))           # 지평선 08-28(전진 없음)
D_NEW <- as.Date(c("2026-08-27", "2026-08-28", "2026-08-31", "2026-09-01"))  # 지평선 09-01(전진)

make_rawdata <- function(path) {
  qd <- as.Date(c("2026-03-27", "2026-08-26", "2026-08-27", "2026-08-28"))
  nd <- as.Date(c("2026-08-31", "2026-09-01", "2026-09-02"))
  g <- CJ(Date = c(qd, nd), Ticker = TICK)
  g[, source := fifelse(Date == as.Date("2026-03-27"), "quantiwise", fifelse(Date %in% qd, "quantiwise_update", "naver"))]
  g[, `:=`(Open = 100, High = 101, Low = 99, Close = 100, Vol = 1e5, Size = 1e9, Ret = 0, BM_Ret = 0)]
  write_parquet(g, path)
  path
}

#------------------------------------------------------------------------------
# 격리 env 조립 — 스텁: .extract_qw_dates(base max 03-27) · .load_calendar(관문 뒤 도달 표지) · 컨센서스(호출 기록)
#------------------------------------------------------------------------------
new_env <- function(lines, tag) {
  env <- new.env(parent = globalenv())
  env$`%||%` <- `%||%`
  base <- file.path(TMP, paste0(tag, "_", sample.int(1e8, 1)))
  env$PROJECT_ROOT <- file.path(base, "root"); env$CACHE_DIR <- file.path(base, "cache")
  env$UPDATE_DIR <- file.path(base, "upd")
  for (d in c(env$PROJECT_ROOT, env$CACHE_DIR, env$UPDATE_DIR)) dir.create(d, recursive = TRUE)
  env$LAST_PROCESSED_FILE <- file.path(env$CACHE_DIR, "update_file_last_processed.rds")
  env$OHLCVS_GATE_RECORD  <- file.path(env$CACHE_DIR, "update_file_ohlcvs_gate.json")
  env$DATA_DIR <- file.path(base, "no_data_dir")
  env$.extract_qw_dates <- function(p) as.Date("2026-03-27")
  env$.load_calendar <- function() stop("SENTINEL_PAST_GATE")
  env$consensus_calls <- 0L
  env$incremental_consensus <- function() { env$consensus_calls <- env$consensus_calls + 1L; invisible(TRUE) }
  load_defs(lines, env)
  make_rawdata(file.path(env$CACHE_DIR, "rawdata.parquet"))
  env
}
md5 <- function(p) unname(tools::md5sum(p))

# 한 소스(원본 또는 돌연변이)에 대해 핵심 판정을 모아 이름 붙인 논리 벡터로 돌려준다
core_checks <- function(lines, verbose = FALSE) {
  r <- list()
  out <- if (verbose) function(x) x else function(x) suppressWarnings(capture.output(x))
  ## D 통합 거부(전진 없음)
  e <- new_env(lines, "D")
  xl <- write_qw_xlsx(file.path(e$UPDATE_DIR, "OHLCVS_update.xlsx"), same_dates(D_OLD))
  cf <- file.path(e$UPDATE_DIR, "Consensus_update.xlsx"); writeBin(as.raw(1:9), cf)
  old_t <- Sys.time() - 7200
  saveRDS(list(time = old_t, files = list(OHLCVS_update.xlsx = old_t, Consensus_update.xlsx = old_t)), e$LAST_PROCESSED_FILE)
  rp <- file.path(e$CACHE_DIR, "rawdata.parquet"); m0 <- md5(rp)
  err <- NULL
  out(tryCatch(e$incremental_update_all(), error = function(x) err <<- conditionMessage(x)))
  r$D_stop_gate_refused <- !is.null(err) && grepl("GATE_REFUSED", err, fixed = TRUE) && grepl("not_advanced", err, fixed = TRUE)
  r$D_rawdata_untouched <- identical(md5(rp), m0)
  lp <- readRDS(e$LAST_PROCESSED_FILE)
  r$D_ohlcvs_not_recorded <- isTRUE(abs(as.numeric(lp$files$OHLCVS_update.xlsx) - as.numeric(old_t)) < 1)
  r$D_other_recorded <- isTRUE(abs(as.numeric(lp$files$Consensus_update.xlsx) - as.numeric(file.mtime(cf))) < 1) &&
                        e$consensus_calls == 1L
  rec <- tryCatch(jsonlite::fromJSON(e$OHLCVS_GATE_RECORD), error = function(x) NULL)
  r$D_record_refused <- identical(rec$status, "refused") && identical(rec$horizon, "2026-08-28") &&
                        identical(rec$prior_horizon, "2026-08-28")
  r$D_retry_next_run <- any(grepl("OHLCVS_update", e$detect_update_changes()$changed))
  ## E 통합 거부(Size 시트 하루 뒤짐)
  e <- new_env(lines, "E")
  sd <- same_dates(D_NEW); sd$Size <- head(D_NEW, -1)
  write_qw_xlsx(file.path(e$UPDATE_DIR, "OHLCVS_update.xlsx"), sd)
  rp <- file.path(e$CACHE_DIR, "rawdata.parquet"); m0 <- md5(rp)
  res <- NULL; err <- NULL
  out(tryCatch(res <- e$incremental_ohlcvs(), error = function(x) err <<- conditionMessage(x)))
  r$E_mismatch_refused <- is.null(err) && isTRUE(res$refused) && "horizon_mismatch" %in% names(res$reasons)
  r$E_rawdata_untouched <- identical(md5(rp), m0)
  ## F1 양성 대조 — 전진·일치 → 관문 통과 후 적재 경로(.load_calendar 표지)까지 간다
  e <- new_env(lines, "F1")
  write_qw_xlsx(file.path(e$UPDATE_DIR, "OHLCVS_update.xlsx"), same_dates(D_NEW))
  res <- NULL; err <- NULL
  out(tryCatch(res <- e$incremental_ohlcvs(), error = function(x) err <<- conditionMessage(x)))
  r$F1_passes_to_load <- identical(err, "SENTINEL_PAST_GATE")
  ## F2 지평선 행이 빈 Size 시트 → 파싱 후 거부(RAWDATA 무접촉)
  e <- new_env(lines, "F2")
  write_qw_xlsx(file.path(e$UPDATE_DIR, "OHLCVS_update.xlsx"), same_dates(D_NEW), empty_last = "Size")
  rp <- file.path(e$CACHE_DIR, "rawdata.parquet"); m0 <- md5(rp)
  res <- NULL; err <- NULL
  out(tryCatch(res <- e$incremental_ohlcvs(), error = function(x) err <<- conditionMessage(x)))
  r$F2_empty_row_refused <- is.null(err) && isTRUE(res$refused) && "horizon_row_empty" %in% names(res$reasons)
  r$F2_rawdata_untouched <- identical(md5(rp), m0)
  unlist(r)
}

#==============================================================================
cat("\n[A] 판정 순수 함수\n")
e0 <- new.env(parent = globalenv()); e0$`%||%` <- `%||%`
e0$OHLCVS_GATE_RECORD <- file.path(TMP, "a_gate.json"); load_defs(src_lines, e0)
hz_ok <- data.table(pos = 1:7, sheet = c("Open", "High", "Low", "Close", "Vol", "Size", "DATA_Key"),
                    date_axis = c(rep(TRUE, 6), FALSE), n_dates = c(rep(4L, 6), 0L),
                    horizon = as.Date(c(rep("2026-09-22", 6), NA)), last_row_date = as.Date(c(rep("2026-09-22", 6), NA)),
                    err = NA_character_)
g <- e0$ohlcvs_update_gate(hz_ok, as.Date("2026-08-28"))
chk(isTRUE(g$ok) && !length(g$reasons) && identical(g$horizon, as.Date("2026-09-22")),
    "A1 양성 대조: 6시트 09-22 일치 · 직전 08-28 → 통과(날짜축 없는 DATA_Key 는 불일치로 안 센다)")
g <- e0$ohlcvs_update_gate(hz_ok, as.Date("2026-09-22"))
chk(!g$ok && identical(names(g$reasons), "not_advanced"), "A2 지평선 = 직전 적재 → not_advanced 거부")
h <- copy(hz_ok); h[sheet == "Size", horizon := as.Date("2026-09-21")]
g <- e0$ohlcvs_update_gate(h, as.Date("2026-08-28"))
chk(!g$ok && "horizon_mismatch" %in% names(g$reasons) && is.na(g$horizon), "A3 Size 만 09-21 → horizon_mismatch 거부(공통 지평선 NA)")
g <- e0$ohlcvs_update_gate(hz_ok, as.Date(NA))
chk(!g$ok && identical(names(g$reasons), "prior_unmeasured"), "A4 직전 지평선 NA → prior_unmeasured 거부(통과로 접지 않는다)")
h <- copy(hz_ok); h[4:5, sheet := c("Vol", "Close")]
g <- e0$ohlcvs_update_gate(h, as.Date("2026-08-28"))
chk(!g$ok && "sheet_order" %in% names(g$reasons), "A5 Close/Vol 순서 뒤바뀜 → sheet_order 거부(루프가 번호로 읽는다)")
h <- copy(hz_ok); h[sheet == "Size", `:=`(date_axis = FALSE, n_dates = 0L, horizon = as.Date(NA))]
g <- e0$ohlcvs_update_gate(h, as.Date("2026-08-28"))
chk(!g$ok && "date_axis_missing" %in% names(g$reasons), "A6 Size 날짜축 없음 → date_axis_missing 거부")
h <- copy(hz_ok); h[sheet == "High", `:=`(date_axis = NA, n_dates = NA_integer_, horizon = as.Date(NA), err = "boom")]
g <- e0$ohlcvs_update_gate(h, as.Date("2026-08-28"))
chk(!g$ok && all(c("sheet_read_error", "date_axis_missing") %in% names(g$reasons)), "A7 High 판독 오류 → sheet_read_error 거부")
h <- hz_ok[sheet != "Size"]
g <- e0$ohlcvs_update_gate(h, as.Date("2026-08-28"))
chk(!g$ok && all(c("sheet_order", "date_axis_missing") %in% names(g$reasons)), "A8 Size 시트 자체 부재 → sheet_order+date_axis_missing 거부")
chk(identical(e0$.ohlcvs_horizon_fill_problems(c(Open = 3L, Size = 3L), as.Date("2026-09-01")), character(0)) &&
    identical(names(e0$.ohlcvs_horizon_fill_problems(c(Open = 3L, Size = 0L), as.Date("2026-09-01"))), "horizon_row_empty"),
    "A9 지평선 행 값 칸: 전부 >0 → 문제 0 · Size 0칸 → horizon_row_empty")

cat("\n[B] 합성 수출본(실물 형식) 판독\n")
xb <- write_qw_xlsx(file.path(TMP, "b.xlsx"), same_dates(D_NEW))
hb <- e0$ohlcvs_sheet_horizons(xb)
chk(identical(hb$sheet, c("Open", "High", "Low", "Close", "Vol", "Size", "DATA_Key")), "B1 7시트 전부 읽음(순서 보존)")
chk(all(hb$date_axis[1:6]) && identical(hb$date_axis[7], FALSE), "B2 값 6시트 = 날짜축 · DATA_Key = 날짜축 없음")
chk(all(hb$horizon[1:6] == as.Date("2026-09-01")) && all(hb$n_dates[1:6] == length(D_NEW)),
    "B3 지평선 = A열 마지막 날짜 09-01 · 머리 'Refresh'=0(1899-12-30)을 날짜로 세지 않음(n_dates=4)")
sd <- same_dates(D_NEW); sd$Vol <- head(D_NEW, -2)
hb2 <- e0$ohlcvs_sheet_horizons(write_qw_xlsx(file.path(TMP, "b2.xlsx"), sd))
chk(identical(hb2[sheet == "Vol"]$horizon, as.Date("2026-08-28")) && identical(hb2[sheet == "Close"]$horizon, as.Date("2026-09-01")),
    "B4 시트별 지평선을 따로 잰다(Vol 08-28 · Close 09-01)")

cat("\n[C] 직전 적재 지평선\n")
rp <- make_rawdata(file.path(TMP, "c_raw.parquet"))
chk(identical(e0$.ohlcvs_prior_horizon(rp), as.Date("2026-08-28")), "C1 퀀티 출처 max = 08-28 (naver 09-02 는 무시)")
chk(is.na(e0$.ohlcvs_prior_horizon(file.path(TMP, "none.parquet"))), "C2 RAWDATA 부재 → NA")
nv <- data.table(Date = as.Date("2026-09-01"), Ticker = "A000010", source = "naver"); write_parquet(nv, file.path(TMP, "c_nv.parquet"))
chk(is.na(e0$.ohlcvs_prior_horizon(file.path(TMP, "c_nv.parquet"))), "C3 퀀티 출처 0행 → NA")

cat("\n[D~F] 통합 (격리 env · 운영 파일 무접촉)\n")
base_r <- core_checks(src_lines, verbose = FALSE)
lbl <- c(D_stop_gate_refused = "D1 전진 없는 저장본 → incremental_update_all 이 stop([GATE_REFUSED] not_advanced)",
         D_rawdata_untouched = "D2 RAWDATA md5 불변",
         D_ohlcvs_not_recorded = "D3 OHLCVS 는 '처리 완료' 미기록(직전 mtime 유지)",
         D_other_recorded = "D4 다른 변경 파일(Consensus)은 처리·기록",
         D_record_refused = "D5 판정 기록 JSON = refused · 지평선 08-28 · 직전 08-28",
         D_retry_next_run = "D6 다음 실행이 OHLCVS 를 다시 변경으로 감지(재시도)",
         E_mismatch_refused = "E1 Size 시트 하루 뒤짐 → horizon_mismatch 거부",
         E_rawdata_untouched = "E2 RAWDATA md5 불변",
         F1_passes_to_load = "F1 양성 대조: 전진·일치 → 관문 통과, 적재 경로(캘린더 단계)까지 진행",
         F2_empty_row_refused = "F2 지평선 행이 빈 Size 시트 → 파싱 후 horizon_row_empty 거부",
         F2_rawdata_untouched = "F2' RAWDATA md5 불변")
for (k in names(lbl)) chk(isTRUE(base_r[[k]]), lbl[[k]], if (!isTRUE(base_r[[k]])) paste0("값=", base_r[[k]]) else "")
if (!all(base_r)) { cat("  (상세 재실행 — 로그)\n"); invisible(core_checks(src_lines, verbose = TRUE)) }

cat("\n[M] 돌연변이 — 각각 해당 판정이 red 여야 한다\n")
MUT <- list(
  list(id = "M1 거부 반환 삭제", expect_red = c("D_stop_gate_refused"),   # E 는 빈 행 보강 판정이 이중으로 막는다(심층 방어)
       f = function(l) mutate_line(l, "  if (!isTRUE(.gate$ok)) return(.ohlcvs_refuse(.gate, ohlcvs_update))", "  NULL")),
  list(id = "M2 판정 항상 통과", expect_red = c("D_stop_gate_refused"),
       f = function(l) mutate_sub(l, "list(ok = !length(rs), reasons = rs", "list(ok = TRUE, reasons = rs")),
  list(id = "M3 OHLCVS 기록 유지 삭제", expect_red = c("D_ohlcvs_not_recorded", "D_retry_next_run"),
       f = function(l) mutate_sub(l, "mt_save[[nm]] <- prev_files[[nm]]", "invisible(NULL)")),
  list(id = "M4 끝 stop 삭제", expect_red = c("D_stop_gate_refused"),
       f = function(l) mutate_line(l, "  if (!is.null(ohlcvs_refused))", "  if (FALSE)")),
  list(id = "M5 불일치 판정 삭제", expect_red = c("E_mismatch_refused"),
       f = function(l) mutate_line(l, "  if (length(hzs) != 1L)", "  if (FALSE)")),
  list(id = "M6 빈 행 거부 삭제", expect_red = c("F2_empty_row_refused"),
       f = function(l) mutate_line(l, "    return(.ohlcvs_refuse(.gate, ohlcvs_update))", "    NULL"))
)
for (m in MUT) {
  ml <- tryCatch(m$f(src_lines), error = function(e) e)
  if (inherits(ml, "error")) { ng(m$id, paste("돌연변이 적용 실패:", conditionMessage(ml))); next }
  mr <- tryCatch(core_checks(ml), error = function(e) e)
  if (inherits(mr, "error")) { ng(m$id, paste("돌연변이 실행 오류:", conditionMessage(mr))); next }
  red <- m$expect_red[!mr[m$expect_red]]
  chk(length(red) == length(m$expect_red), sprintf("%s → red: %s", m$id, paste(m$expect_red, collapse = ",")),
      sprintf("green 으로 남은 판정: %s", paste(setdiff(m$expect_red, red), collapse = ",")))
}

cat(sprintf("\n[test_ohlcvs_update_gate] PASS: %d  FAIL: %d\n", PASS, FAIL))
cat(sprintf('{"test":"ohlcvs_update_gate","pass":%d,"fail":%d,"total":%d,"skipped":0}\n', PASS, FAIL, PASS + FAIL))
quit(status = if (FAIL == 0L) 0L else 1L)
