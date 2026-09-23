#==============================================================================
# test_rawdata_size_from_quantiwise.R — 복원 Size → 퀀티 정본 교체 도구의 상설 검사
#
# 대상: 02_Infrastructure/data/rawdata_size_from_quantiwise.R (도훈 2026-09-23 결정)
# 축(양성 대조 + 위반 주입 + 돌연변이):
#   A 판독기    — 실제 수출본 형식(라벨 행·코드 뒤 옛 셀) 양성 · Unit/항목/고아 열/시트 부재 = 문제 보고
#   B 계획      — replace/fill/same/absent_to_na 정확 · keep 모드 · 구간 밖 무접촉 · 구간 재도출(보고서)
#   C 거부      — 지평선 미달 · 구간 날짜 구멍 · 선언 단위 · 측정 단위(보정) · 구간 배율 · 채움률 ·
#                 잠금 파일 · 보정 미측정 — 전부 qw_size_refused + 보고서 status=REFUSED
#   D 실행 양성 — Size 만 바뀌고(독립 대조) 러너 설정 바이트 복원 · 백업 md5 · 재빌드가 러너 정지 중 1회
#   E 실행 위반 — 다른 열 변경 · 계획 밖 Size · 계획 값 불일치 · 동시 쓰기 · 이미 정지 · 설정 형식 이상 ·
#                 rebuild_fdb=FALSE 면 빌더 미호출(인자 배선)
#   F 러너 토글 — 실제 설정 사본에서 두 줄만 바뀜 · director/l2_auto.enabled 불변 · 제3자 변경 시 미복원
#   M 돌연변이  — 대조 무력화 → 다른 열 변경이 RAWDATA 에 도달(검사가 잡는다) · 지평선 게이트 제거 →
#                 거부 소멸 · 러너 정지 생략 → 킬스위치 술어가 쓰기 차단 · 2칸 들여쓰기 앵커 완화 → fail-closed
#   G 게이트 보강(2026-09-23 적대 검증) — layout(고아 열·시트 부재) · duplicate_keys(QW 코드·RAWDATA 키) ·
#                 qw_nonpositive 를 **run() 경로에서** 거부로 확인 + 게이트별 돌연변이(해당 게이트 TRUE → 거부 소멸)
#   H 내부 안전장치 — 백업 md5(백업 전 제3자 쓰기) · 계획 뒤 Size 재대조 · rename 후 md5(백업 복원) ·
#                 일시정지 JSON 동치(같은 줄의 다른 키 소실) — 위반 주입 + 각 장치 돌연변이 red
#   I 재빌드     — 기본 빌더 경로 ≠ 인자(사본 리허설) = 어떤 쓰기보다 먼저 거부 · 경로 같으면 기본 빌더 사용(가짜 전역 빌더) ·
#                 빌더 안 이중 대조 · 재빌드 실패에도 보고서 APPLIED_FDB_FAILED + 러너 복원 — 돌연변이 2종 red
#   ★기본 빌더 검사는 가짜 전역 build_factor_db/.load_base_data 를 먼저 심는다 — 실패해도 실제 factor_db_builder.R 를
#     source 하지 않게(운영 factor_db 재빌드 경로를 검사가 여는 일이 없게).
#
# 운영 무접촉: 모든 픽스처는 tempdir() 아래. 실제 파일은 **읽기만**(naver_collector_config.json ·
#   cache_registry.json · reinforce_auto_config.json 사본 원천). RAWDATA·러너 설정·factor_db 에 쓰지 않는다.
# 요약 규약: 마지막 줄 {"test":"rawdata_size_from_quantiwise","pass":N,"fail":N,"total":N}
#==============================================================================
suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite); library(readxl); library(openxlsx)
})

.MARKER <- "02_Infrastructure/data/rawdata_size_from_quantiwise.R"
.script_dir <- function() {
  a <- commandArgs(trailingOnly = FALSE)
  m <- grep("^--file=", a, value = TRUE)
  if (!length(m)) return("")
  dirname(sub("^--file=", "", m[1L]))
}
.sd <- .script_dir()
PROJ <- ""
for (.c in c(if (nzchar(.sd)) file.path(.sd, "..", "..") else "", Sys.getenv("CLAUDE_PROJECT_DIR", ""),
             Sys.getenv("QM_ROOT", ""), getwd())) {
  .c <- gsub("\\\\", "/", .c)
  if (nzchar(.c) && file.exists(file.path(.c, .MARKER))) { PROJ <- normalizePath(.c, winslash = "/"); break }
}
if (!nzchar(PROJ)) stop("[test_qw_size] PROJECT_ROOT 해석 실패 — 표지 부재: ", .MARKER)
PROJECT_ROOT <- PROJ
SRC <- Sys.getenv("QWS_SRC", file.path(PROJ, .MARKER))   # QWS_SRC = 배포 전 스크래치 사본 검사용

PASS <- 0L; FAIL <- 0L
ok  <- function(n, m = "") { PASS <<- PASS + 1L; cat(sprintf("  PASS: %s - %s\n", n, m)) }
bad <- function(n, m = "") { FAIL <<- FAIL + 1L; cat(sprintf("  FAIL: %s - %s\n", n, m)) }
chk <- function(n, cond, m = "") if (isTRUE(cond)) ok(n, m) else bad(n, m)

FX <- normalizePath(file.path(tempdir(), sprintf("qws_fx_%d", Sys.getpid())), winslash = "/", mustWork = FALSE)
unlink(FX, recursive = TRUE); dir.create(FX, recursive = TRUE, showWarnings = FALSE)
fin <- function() {
  unlink(FX, recursive = TRUE)
  cat(sprintf("TOTAL: %d pass / %d fail\n", PASS, FAIL))
  cat(toJSON(list(test = "rawdata_size_from_quantiwise", pass = PASS, fail = FAIL, total = PASS + FAIL),
             auto_unbox = TRUE), "\n")
  quit(save = "no", status = if (FAIL > 0L) 1L else 0L)
}

cat("=== rawdata_size_from_quantiwise ===\n")
source(SRC)
md5 <- function(p) unname(tools::md5sum(p))
ITEM <- QWS_EXPECTED_ITEM

#------------------------------------------------------------------------------
# 픽스처
#------------------------------------------------------------------------------
set.seed(20260923)
TK <- sprintf("A%06d", seq(10, 300, by = 10))                 # 30종
cal <- seq(as.Date("2026-08-24"), as.Date("2026-09-11"), by = "day")
DATES <- cal[!format(cal, "%u") %in% c("6", "7")]              # 15 거래일
START <- as.Date("2026-09-07"); END <- as.Date("2026-09-10")
shares <- setNames(as.numeric(sample(1e6:5e7, length(TK))), TK)
QW <- CJ(Date = DATES, Ticker = TK)
QW[, Close := round(runif(.N, 1000, 90000))]
QW[, QW_Size := shares[Ticker] * Close]
QW[Ticker == "A000300" & Date == as.Date("2026-09-09"), `:=`(QW_Size = NA_real_)]   # QW 결측 → absent_to_na

mk_raw <- function() {
  r <- copy(QW)[!(Ticker == "A000300" & Date == as.Date("2026-09-09") & FALSE)]
  r[, source := fifelse(Date <= as.Date("2026-08-28"), "quantiwise_update", "naver")]
  r[, Size := fifelse(Date <= as.Date("2026-08-28"), QW_Size,
               fifelse(Date <= as.Date("2026-09-04"), round(QW_Size / 1e8) * 1e8, round(shares[Ticker] * 1.004) * Close))]
  r[Ticker == "A000300" & Date == as.Date("2026-09-09"), Size := round(shares["A000300"] * 1.004) * Close]
  r[Ticker == "A000020" & Date == as.Date("2026-09-08"), Size := NA_real_]            # 복원 불가 → fill
  r[Ticker == "A000030" & Date == as.Date("2026-09-10"), Size := QW_Size]             # 같은날 스냅샷 → same
  r[, `:=`(Open = Close * 0.99, Vol = round(runif(.N, 1e3, 1e6)), Ret = rnorm(.N, 0, 0.02),
           K200 = as.numeric(Ticker %in% TK[1:10]), Name = paste0("종목", Ticker),
           Sector = "IT", BM_Ret = rnorm(.N, 0, 0.01))]
  r[sample(.N, 7), Open := NA_real_]
  r[, QW_Size := NULL]
  setcolorder(r, c("Date", "Ticker", "K200", "Name", "Sector", "Open", "Close", "Vol", "Size", "Ret", "source", "BM_Ret"))
  setorder(r, Date, Ticker)
  r[]
}
RAW0 <- mk_raw()
PRE <- copy(RAW0)[Date >= START & !(Ticker == "A000030" & Date == as.Date("2026-09-10")), Size := NA_real_]

mk_xlsx <- function(path, qw = QW, dates = DATES, unit = "local", item = ITEM, unit_override = NULL,
                    item_override = NULL, orphan = FALSE, stale = TRUE, sheet = "Size", scale = 1,
                    scale_window = 1, dup_code = NULL) {
  wb <- createWorkbook()
  addWorksheet(wb, "Close"); addWorksheet(wb, sheet)
  hdr <- function(r, c, x) writeData(wb, sheet, x = x, startRow = r, startCol = c, colNames = FALSE)
  hdr(1, 1, "     Refresh     "); hdr(1, 2, "Last Update : 2026-09-23 21:00:00"); hdr(2, 1, 0)
  hdr(3, 1, "Time Series (Company)"); hdr(4, 1, "Frequency"); hdr(4, 2, "D")
  hdr(5, 1, "Period(From)"); hdr(5, 2, 20260328)
  hdr(6, 1, "Period(To)"); hdr(6, 2, sprintf("CPD-1TD [%s]", format(max(dates), "%Y%m%d")))
  units <- rep(unit, length(TK)); items <- rep(item, length(TK))
  if (!is.null(unit_override)) units[unit_override] <- "KRW mil"
  if (!is.null(item_override)) items[item_override] <- "수정주가"
  n <- length(TK)
  wr <- function(r, lab, v) { hdr(r, 1, lab); writeData(wb, sheet, x = as.data.frame(t(v)), startRow = r, startCol = 2, colNames = FALSE) }
  codes <- TK; if (!is.null(dup_code)) codes[dup_code] <- TK[1]
  wr(8, "Code", codes); wr(9, "Name", paste0("N", TK)); hdr(10, 1, "Item Code"); hdr(10, 2, "S102100")
  wr(11, "Unit", units); hdr(12, 1, "Base Date"); wr(14, "D A T E", items)
  if (stale) {   # 실물처럼 코드 뒤 옛 선언 셀(코드 없음) — 판정은 코드 열에서만
    writeData(wb, sheet, x = as.data.frame(t(rep("local", 5))), startRow = 11, startCol = n + 2, colNames = FALSE)
    writeData(wb, sheet, x = as.data.frame(t(rep("수정주가", 5))), startRow = 14, startCol = n + 2, colNames = FALSE)
  }
  q <- qw[Date %in% dates]
  w <- dcast(q, Date ~ Ticker, value.var = "QW_Size")[order(Date)]
  setcolorder(w, c("Date", TK))
  m <- as.matrix(w[, ..TK]) * scale
  if (scale_window != 1) m[w$Date >= START, ] <- m[w$Date >= START, ] * scale_window
  writeData(wb, sheet, x = data.frame(d = w$Date), startRow = 15, startCol = 1, colNames = FALSE)
  writeData(wb, sheet, x = as.data.frame(m), startRow = 15, startCol = 2, colNames = FALSE)
  if (orphan) writeData(wb, sheet, x = 12345, startRow = 16, startCol = n + 3, colNames = FALSE)
  saveWorkbook(wb, path, overwrite = TRUE)
  path
}

CFG_REAL <- file.path(PROJ, "06_Registry/reinforce_auto_config.json")
mk_cfg <- function(path, force_enabled = TRUE, broken = FALSE) {
  b <- readBin(CFG_REAL, "raw", file.info(CFG_REAL)$size)          # 실제 형식 사본(읽기만)
  s <- rawToChar(b); Encoding(s) <- "bytes"
  if (force_enabled) s <- sub('(?m)^  "enabled": false,', '  "enabled": true,', s, perl = TRUE, useBytes = TRUE)
  if (broken) s <- sub('(?m)^  "enabled": true,', '  "enabled":true,', s, perl = TRUE, useBytes = TRUE)
  con <- file(path, "wb"); writeBin(charToRaw(s), con); close(con)
  path
}

mk_env <- function(tag, raw = RAW0, qw_args = list(), cfg_enabled = TRUE, cfg_broken = FALSE, with_pre = TRUE) {
  d <- file.path(FX, tag); unlink(d, recursive = TRUE); dir.create(d, recursive = TRUE)
  rp <- file.path(d, "RAWDATA.parquet"); write_parquet(raw, rp)
  if (with_pre) write_parquet(PRE, file.path(d, "RAWDATA.parquet.bak_size_repair_20260923_184944"))
  xp <- do.call(mk_xlsx, c(list(path = file.path(d, "OHLCVS_update.xlsx")), qw_args))
  cp <- mk_cfg(file.path(d, "reinforce_auto_config.json"), force_enabled = cfg_enabled, broken = cfg_broken)
  if (!cfg_enabled) {
    s <- rawToChar(readBin(cp, "raw", file.info(cp)$size)); Encoding(s) <- "bytes"
    s <- sub('(?m)^  "enabled": true,', '  "enabled": false,', s, perl = TRUE, useBytes = TRUE)
    con <- file(cp, "wb"); writeBin(charToRaw(s), con); close(con)
  }
  fd <- file.path(d, "factor_db"); dir.create(fd)
  write_parquet(data.table(Date = as.Date("2026-08-28"), Ticker = TK, v = 1), file.path(fd, "factor_db_202608.parquet"))
  write_parquet(data.table(Date = as.Date("2026-09-10"), Ticker = TK, v = 1), file.path(fd, "factor_db_202609.parquet"))
  list(dir = d, raw = rp, xlsx = xp, cfg = cp, fdb = fd, out = file.path(d, "out"), bak = file.path(d, "bak"))
}
run <- function(e, ...) rawdata_size_from_quantiwise(start = START, end = END, xlsx = e$xlsx, rawdata = e$raw,
                                                      out_dir = e$out, backup_dir = e$bak, runner_config = e$cfg,
                                                      fdb_dir = e$fdb, ...)
refused <- function(expr) tryCatch({ force(expr); NULL }, qw_size_refused = function(c) c$report)
errmsg <- function(expr) tryCatch({ force(expr); NA_character_ }, error = function(c) conditionMessage(c))

#------------------------------------------------------------------------------
cat("\n[A] 판독기\n")
e <- mk_env("A")
r <- qws_read_qw_size(e$xlsx)
chk("A1 형식 인식(문제 0)", !length(r$problems), paste(r$problems, collapse = "|"))
chk("A2 코드 30 · 지평선 09-11 · 날짜 15", r$meta$n_codes == 30 && r$meta$horizon == "2026-09-11" && r$meta$n_dates == 15)
j <- merge(r$long, QW[, .(Date, Ticker, QW_Size_true = QW_Size)], by = c("Date", "Ticker"))
chk("A3 값 = 원천 (NA 포함 identical)", nrow(j) == nrow(QW) && identical(j$QW_Size, j$QW_Size_true))
chk("A4 코드 뒤 옛 선언 셀은 무시(unit_declared 없음)", !"unit_declared" %in% names(r$problems))
r2 <- qws_read_qw_size(mk_xlsx(file.path(e$dir, "u.xlsx"), unit_override = 3))
chk("A5 [위반] Unit≠local 1열 → unit_declared", "unit_declared" %in% names(r2$problems))
r3 <- qws_read_qw_size(mk_xlsx(file.path(e$dir, "i.xlsx"), item_override = 7))
chk("A6 [위반] 항목≠시가총액 1열 → unit_declared", "unit_declared" %in% names(r3$problems))
r4 <- qws_read_qw_size(mk_xlsx(file.path(e$dir, "o.xlsx"), orphan = TRUE))
chk("A7 [위반] 코드 없는 열에 값 → layout", "layout" %in% names(r4$problems))
r5 <- qws_read_qw_size(mk_xlsx(file.path(e$dir, "s.xlsx"), sheet = "Sz"))
chk("A8 [위반] Size 시트 부재 → layout · long NULL", "layout" %in% names(r5$problems) && is.null(r5$long))

#------------------------------------------------------------------------------
cat("\n[B] 계획 · dry-run\n")
e <- mk_env("B")
raw_md5 <- md5(e$raw); cfg_md5 <- md5(e$cfg)
res <- run(e)
pc <- res$report$plan_counts
chk("B1 status PLANNED", identical(res$report$status, "PLANNED"))
chk("B2 계획 계수 replace 117 · fill 1 · same 1 · absent_to_na 1", identical(pc$replace, 117L) && identical(pc$fill, 1L) &&
      identical(pc$same, 1L) && identical(pc$absent_to_na, 1L) && res$report$n_change == 119L,
    toJSON(pc, auto_unbox = TRUE))
pl <- merge(res$plan, QW[, .(Date, Ticker, T = QW_Size)], by = c("Date", "Ticker"))
chk("B3 교체·채움 행 new = QW 정본", pl[action %in% c("replace", "fill", "same"), all(new_Size == T)])
chk("B4 QW 결측 행 new = NA (PIT 엄격)", pl[action == "absent_to_na", .N == 1L && is.na(new_Size) && Ticker == "A000300"])
chk("B5 구간 밖(09-11) 계획 0행", !any(res$plan$Date > END) && !any(res$plan$Date < START))
chk("B6 보정 150행 전부 일치", res$report$calibration$n == 150L && res$report$calibration$n_equal == 150L)
pv <- res$plan[, .N, by = prov]
chk("B7 출처: reconstructed 118 · pre_existing 1 · na_now 1", identical(pv[prov == "reconstructed"]$N, 118L) &&
      identical(pv[prov == "pre_existing"]$N, 1L) && identical(pv[prov == "na_now"]$N, 1L), toJSON(pv))
chk("B8 차이 분포 = 복원 배율(-0.4%) 재현", abs(res$report$diff$rel_quantiles$p50 - (1 / 1.004 - 1)) < 1e-4,
    sprintf("median rel %.6f", res$report$diff$rel_quantiles$p50))
chk("B9 dry-run 무접촉(RAWDATA·러너 md5)", md5(e$raw) == raw_md5 && md5(e$cfg) == cfg_md5)
chk("B10 보고서 기록", file.exists(res$path) && identical(fromJSON(res$path)$status, "PLANNED"))
res_k <- run(e, on_qw_absent = "keep")
chk("B11 keep 모드 → absent_keep 1 · 교체 118", identical(res_k$report$plan_counts$absent_keep, 1L) && res_k$report$n_change == 118L)
wr <- file.path(e$dir, "naver_recollect"); dir.create(wr)
writeLines(toJSON(list(size_only = TRUE, dry_run = FALSE, start = "2026-09-07", end = "2026-09-10"), auto_unbox = TRUE),
           file.path(wr, "latest_apply_size_backfill.json"))
res_w <- rawdata_size_from_quantiwise(xlsx = e$xlsx, rawdata = e$raw, out_dir = e$out, runner_config = e$cfg, fdb_dir = e$fdb)
chk("B12 구간 재도출(W-02 보수 보고서)", identical(res_w$report$window$start, "2026-09-07") &&
      identical(res_w$report$window$end, "2026-09-10") && grepl("^report:", res_w$report$window$source))
writeLines(toJSON(list(size_only = TRUE, dry_run = TRUE, start = "2026-09-07", end = "2026-09-10"), auto_unbox = TRUE),
           file.path(wr, "latest_apply_size_backfill.json"))
m <- errmsg(rawdata_size_from_quantiwise(xlsx = e$xlsx, rawdata = e$raw, out_dir = e$out, runner_config = e$cfg))
chk("B13 [위반] dry-run 보고서로는 구간을 재도출하지 않는다", grepl("재도출 불가", m), m)

#------------------------------------------------------------------------------
cat("\n[C] 거부 게이트\n")
cr <- function(tag, gate, ..., env_args = list()) {
  e <- do.call(mk_env, c(list(tag), env_args))
  rep <- refused(run(e, ...))
  chk(sprintf("%s [위반] %s → 거부", tag, gate), !is.null(rep) && gate %in% rep$refused_gates,
      if (is.null(rep)) "거부 안 됨" else paste(rep$refused_gates, collapse = ","))
  invisible(list(e = e, rep = rep))
}
x <- cr("C1", "horizon_short", env_args = list(qw_args = list(dates = DATES[DATES <= as.Date("2026-09-09")])))
chk("C1b 거부 보고서 status=REFUSED 기록 · RAWDATA 무접촉", !is.null(x$rep) && file.exists(x$rep$path) &&
      identical(fromJSON(x$rep$path)$status, "REFUSED") && identical(md5(x$e$raw), md5(file.path(x$e$dir, "RAWDATA.parquet"))))
cr("C2", "window_dates_missing", env_args = list(qw_args = list(dates = DATES[DATES != as.Date("2026-09-08")])))
cr("C3", "unit_declared", env_args = list(qw_args = list(unit_override = 5)))
cr("C4", "calibration", env_args = list(qw_args = list(scale = 1e-6)))
cr("C5", "window_scale", env_args = list(qw_args = list(scale_window = 100)))
QWB <- copy(QW); QWB[Date == as.Date("2026-09-08") & Ticker %in% TK[1:5], QW_Size := NA_real_]
cr("C6", "qw_fill", env_args = list(qw_args = list(qw = QWB)))
e7 <- mk_env("C7"); file.create(file.path(e7$dir, "~$OHLCVS_update.xlsx"))
rep7 <- refused(run(e7))
chk("C7 [위반] 엑셀 잠금 파일 → xlsx_locked", !is.null(rep7) && "xlsx_locked" %in% rep7$refused_gates)
RAWN <- copy(RAW0)[source == "quantiwise_update", source := "naver"]
cr("C8", "calibration", env_args = list(raw = RAWN))
e9 <- mk_env("C9")
chk("C9 [양성] 같은 픽스처 무위반은 거부 0", is.null(refused(run(e9))))

#------------------------------------------------------------------------------
cat("\n[D] 실행 양성\n")
e <- mk_env("D")
raw_md5 <- md5(e$raw); cfg_md5 <- md5(e$cfg)
seen <- list()
fake_build <- function(sig) {
  cj <- fromJSON(e$cfg, simplifyVector = FALSE)
  seen[[length(seen) + 1L]] <<- list(sig = sig, enabled = cj$enabled, director = cj$director$enabled,
                                     l2 = cj$l2_auto$enabled, raw_md5 = md5(e$raw))
  invisible(TRUE)
}
res <- run(e, dry_run = FALSE, rebuild_fdb = TRUE, .fdb_build = fake_build)
A <- as.data.table(read_parquet(file.path(e$bak, list.files(e$bak, pattern = "bak_size_qw_")[1]), mmap = FALSE))
B <- as.data.table(read_parquet(e$raw, mmap = FALSE))
chk("D1 status APPLIED · Size 119행 변경", identical(res$report$status, "APPLIED") && res$report$apply$n_size_changed == 119L)
chk("D2 백업 = 원본 md5", identical(md5(file.path(e$bak, list.files(e$bak, pattern = "bak_size_qw_")[1])), raw_md5))
oth <- setdiff(names(A), "Size")
chk("D3 [독립 대조] Size 외 전 열 identical", identical(names(A), names(B)) && all(vapply(oth, function(cc) identical(A[[cc]], B[[cc]]), logical(1))))
jb <- merge(B[, .(Date, Ticker, Size)], QW[, .(Date, Ticker, T = QW_Size)], by = c("Date", "Ticker"))
chk("D4 구간 Size = QW (A000300 09-09 = NA)", jb[Date >= START & Date <= END & !(Ticker == "A000300" & Date == as.Date("2026-09-09")), all(Size == T)] &&
      jb[Ticker == "A000300" & Date == as.Date("2026-09-09"), is.na(Size)])
chk("D5 구간 밖 Size 불변(09-11·08월)", identical(A[Date > END | Date < START]$Size, B[Date > END | Date < START]$Size))
chk("D6 러너 설정 바이트 복원", identical(md5(e$cfg), cfg_md5) && isTRUE(res$report$apply$runner_restore$byte_identical))
chk("D7 재빌드 1회 · 202609 만 · sig 09-10", length(seen) == 1L && identical(seen[[1]]$sig, as.Date("2026-09-10")))
chk("D8 재빌드는 러너 정지 중(enabled=false) · 중첩 enabled 불변 · RAWDATA 교체 뒤",
    length(seen) == 1L && identical(seen[[1]]$enabled, FALSE) && isTRUE(seen[[1]]$director) && isTRUE(seen[[1]]$l2) &&
      !identical(seen[[1]]$raw_md5, raw_md5))
chk("D9 factor_db 백업 존재", length(list.files(e$bak, pattern = "factor_db_202609.parquet", recursive = TRUE)) == 1L)
chk("D10 tmp 잔재 0", !length(list.files(e$dir, pattern = "tmp_qws", all.files = TRUE)))
res2 <- run(e, dry_run = FALSE)
chk("D11 재실행 = NOOP(멱등)", identical(res2$report$status, "NOOP") || identical(res2$report$n_change, 0L))

#------------------------------------------------------------------------------
cat("\n[E] 실행 위반 주입\n")
ev <- function(tag, inject = NULL, before = NULL, expect, env_args = list(), ...) {
  e <- do.call(mk_env, c(list(tag), env_args))
  r0 <- md5(e$raw); c0 <- md5(e$cfg)
  m <- errmsg(run(e, dry_run = FALSE, .inject = inject, .hook_before_rename = before, ...))
  list(e = e, m = m, raw_same = identical(md5(e$raw), r0), cfg_same = identical(md5(e$cfg), c0),
       no_tmp = !length(list.files(e$dir, pattern = "tmp_qws", all.files = TRUE)))
}
x <- ev("E1", inject = function(d) { d[5L, Close := Close + 1]; d })
chk("E1 [위반] 다른 열(Close) 변경 → 중단 · RAWDATA·러너 무변 · tmp 0", grepl("Close 열이 바뀌었다", x$m) && x$raw_same && x$cfg_same && x$no_tmp, x$m)
x <- ev("E2", inject = function(d) { d[Date == as.Date("2026-09-11") & Ticker == TK[1], Size := Size + 1]; d })
chk("E2 [위반] 계획 밖 Size 변경 → 중단", grepl("계획 밖", x$m) && x$raw_same && x$cfg_same, x$m)
x <- ev("E3", inject = function(d) { d[Date == START & Ticker == TK[2], Size := Size * 2]; d })
chk("E3 [위반] 계획 행 값 ≠ QW → 중단", grepl("QW 값과 다르다", x$m) && x$raw_same && x$cfg_same, x$m)
x <- ev("E4", before = function() {
  z <- as.data.table(read_parquet(file.path(FX, "E4", "RAWDATA.parquet"), mmap = FALSE)); z[1L, Vol := Vol + 7]
  write_parquet(z, file.path(FX, "E4", "RAWDATA.parquet")) })
z <- as.data.table(read_parquet(file.path(FX, "E4", "RAWDATA.parquet"), mmap = FALSE))
chk("E4 [위반] 작업 중 제3자 쓰기 → 덮지 않고 중단(제3자 판 보존) · 러너 복원",
    grepl("다른 쓰기", x$m) && identical(z$Vol[1], RAW0$Vol[1] + 7) && x$cfg_same, x$m)
x <- ev("E5", env_args = list(cfg_enabled = FALSE))
chk("E5 이미 정지(제3자) → 진행 · 설정 무접촉", is.na(x$m) && x$cfg_same && !x$raw_same, x$m)
x <- ev("E6", env_args = list(cfg_broken = TRUE))
chk("E6 [위반] 최상위 enabled 줄 형식 이상 → 설정·RAWDATA 무접촉 중단", !is.na(x$m) && x$raw_same && x$cfg_same, x$m)
e7 <- mk_env("E7"); called <- 0L
invisible(run(e7, dry_run = FALSE, rebuild_fdb = FALSE, .fdb_build = function(sig) called <<- called + 1L))
chk("E7 rebuild_fdb=FALSE → 빌더 미호출(인자 배선)", called == 0L)
v_ok <- qws_verify_file(e7$raw, e7$raw, integer(0), numeric(0))
chk("E8 [양성] 대조기: 같은 파일 = ok", isTRUE(v_ok$ok))

#------------------------------------------------------------------------------
cat("\n[F] 러너 토글(실제 설정 사본)\n")
fp <- mk_cfg(file.path(FX, "F_cfg.json"))
b0 <- readBin(fp, "raw", file.info(fp)$size); m0 <- md5(fp)
st <- qws_runner_pause(fp, "테스트 정지")
b1 <- readBin(fp, "raw", file.info(fp)$size)
l0 <- strsplit(rawToChar(b0), "\n", fixed = TRUE)[[1]]; l1 <- strsplit(rawToChar(b1), "\n", fixed = TRUE)[[1]]
j1 <- fromJSON(fp, simplifyVector = FALSE)
chk("F1 두 줄만 바뀐다(줄 수 동일 · CRLF 보존)", length(l0) == length(l1) && sum(l0 != l1) == 2L &&
      all(grepl("\r$", l1[l0 != l1]) == grepl("\r$", l0[l0 != l1])))
chk("F2 최상위 false · director/l2_auto.enabled 불변", identical(j1$enabled, FALSE) && isTRUE(j1$director$enabled) && isTRUE(j1$l2_auto$enabled))
chk("F3 킬스위치 술어 = 쓰기 허용", qws_write_allowed(fp))
rr <- qws_runner_restore(st)
chk("F4 복원 = 원본 바이트(md5)", identical(md5(fp), m0) && isTRUE(rr$byte_identical))
chk("F5 [양성] 복원 뒤 술어 = 차단", !qws_write_allowed(fp))
st2 <- qws_runner_pause(fp, "x")
s <- rawToChar(readBin(fp, "raw", file.info(fp)$size)); s <- sub("\"top_k\": 5", "\"top_k\": 6", s, fixed = TRUE)
con <- file(fp, "wb"); writeBin(charToRaw(s), con); close(con)
rr2 <- suppressWarnings(qws_runner_restore(st2))
chk("F6 [위반] 제3자가 바꾼 설정은 복원하지 않는다", identical(rr2$reason, "changed_by_other") && !isTRUE(rr2$restored))

#------------------------------------------------------------------------------
cat("\n[M] 돌연변이 — 가드를 빼면 검사가 잡는가\n")
mut <- function(from, to) {
  s <- readLines(SRC, encoding = "UTF-8", warn = FALSE)
  hit <- sum(grepl(from, s, fixed = TRUE))
  if (hit != 1L) stop("돌연변이 표적이 정확히 1곳이 아님(", hit, "): ", from)
  s <- sub(from, to, s, fixed = TRUE)
  env <- new.env(parent = globalenv()); tf <- file.path(FX, "mut.R")
  writeLines(s, tf, useBytes = TRUE); sys.source(tf, envir = env, keep.source = FALSE)
  env
}
M1 <- mut("if (!isTRUE(ver$ok)) {", "if (FALSE) {")
e <- mk_env("M1")
m1 <- errmsg(M1$rawdata_size_from_quantiwise(start = START, end = END, xlsx = e$xlsx, rawdata = e$raw, out_dir = e$out,
                                              backup_dir = e$bak, runner_config = e$cfg, fdb_dir = e$fdb, dry_run = FALSE,
                                              .inject = function(d) { d[5L, Close := Close + 1]; d }))
B <- as.data.table(read_parquet(e$raw, mmap = FALSE))
chk("M1 대조 무력화 → 다른 열 변경이 RAWDATA 에 도달(독립 대조가 검출)", !identical(B$Close, RAW0$Close), m1)
M2 <- mut("add(\"horizon_short\", is.finite(as.numeric(hz)) && hz >= end,", "add(\"horizon_short\", TRUE,")
e <- mk_env("M2", qw_args = list(dates = DATES[DATES <= as.Date("2026-09-09")]))
rep <- tryCatch({ M2$rawdata_size_from_quantiwise(start = START, end = END, xlsx = e$xlsx, rawdata = e$raw, out_dir = e$out,
                                                   runner_config = e$cfg, fdb_dir = e$fdb); NULL },
                qw_size_refused = function(c) c$report)
chk("M2 지평선 게이트 제거 → horizon_short 거부 소멸(C1 의 red 는 이 게이트 몫)", is.null(rep) || !"horizon_short" %in% rep$refused_gates)
M3 <- mut("rs <- qws_runner_pause(runner_config, mark)", "rs <- list(state = \"skipped\")")
e <- mk_env("M3"); r0 <- md5(e$raw)
m3 <- errmsg(M3$rawdata_size_from_quantiwise(start = START, end = END, xlsx = e$xlsx, rawdata = e$raw, out_dir = e$out,
                                              backup_dir = e$bak, runner_config = e$cfg, fdb_dir = e$fdb, dry_run = FALSE))
chk("M3 러너 정지 생략 → 킬스위치 술어가 쓰기 차단", grepl("킬스위치", m3) && identical(md5(e$raw), r0), m3)
M4 <- mut("'(?m)^  \"%s\": [^\\\\n]*$'", "'(?m)^ +\"%s\": [^\\\\n]*$'")
fp4 <- mk_cfg(file.path(FX, "M4_cfg.json")); m40 <- md5(fp4)
m4 <- errmsg(M4$qws_runner_pause(fp4, "x"))
chk("M4 2칸 앵커 완화 → 중첩 enabled 까지 잡혀 fail-closed(설정 무접촉)", grepl("특정 못함", m4) && identical(md5(fp4), m40), m4)

#------------------------------------------------------------------------------
cat("\n[G] 게이트 보강 — run() 경로 거부 + 게이트별 돌연변이\n")
g1 <- cr("G1", "layout", env_args = list(qw_args = list(orphan = TRUE)))
chk("G1b 고아 열 거부 시 RAWDATA 무접촉 · 보고서 REFUSED", !is.null(g1$rep) && identical(md5(g1$e$raw), md5(file.path(g1$e$dir, "RAWDATA.parquet"))) &&
      identical(fromJSON(g1$rep$path)$status, "REFUSED"))
g2 <- cr("G2", "layout", env_args = list(qw_args = list(sheet = "Sz")))
chk("G2b Size 시트 부재 → 계획 미산출(window_scale·qw_fill 도 거부)", !is.null(g2$rep) &&
      all(c("window_scale", "qw_fill") %in% g2$rep$refused_gates))
g3 <- cr("G3", "duplicate_keys", env_args = list(qw_args = list(dup_code = 4)))
RAWD <- rbind(RAW0, RAW0[Date == START & Ticker == TK[3]])
g4 <- cr("G4", "duplicate_keys", env_args = list(raw = RAWD))
QWN <- copy(QW); QWN[Date == START & Ticker == TK[4], QW_Size := -5]
g5 <- cr("G5", "qw_nonpositive", env_args = list(qw_args = list(qw = QWN)))
QWZ <- copy(QW); QWZ[Date == END & Ticker == TK[6], QW_Size := 0]
cr("G6", "qw_nonpositive", env_args = list(qw_args = list(qw = QWZ)))
mg <- function(id, from, to, tag, gate, env_args) {
  env <- mut(from, to); e <- do.call(mk_env, c(list(tag), env_args))
  rep <- tryCatch({ env$rawdata_size_from_quantiwise(start = START, end = END, xlsx = e$xlsx, rawdata = e$raw, out_dir = e$out,
                                                    runner_config = e$cfg, fdb_dir = e$fdb); NULL },
                  qw_size_refused = function(c) c$report)
  chk(sprintf("%s %s 게이트 TRUE 고정 → %s 거부 소멸(위 red 는 이 게이트 몫)", id, gate, gate),
      is.null(rep) || !gate %in% rep$refused_gates, if (!is.null(rep)) paste(rep$refused_gates, collapse = ",") else "거부 없음")
}
mg("MG1", 'add("layout", !any(names(pr) == "layout"),', 'add("layout", TRUE,', "MG1", "layout",
   list(qw_args = list(orphan = TRUE)))
mg("MG2", 'add("duplicate_keys", !any(names(pr) == "duplicate_keys") && !anyDuplicated(win, by = c("Date", "Ticker")),',
   'add("duplicate_keys", TRUE,', "MG2", "duplicate_keys", list(raw = RAWD))
mg("MG3", 'add("qw_nonpositive", !any(names(pr) == "qw_nonpositive"),', 'add("qw_nonpositive", TRUE,', "MG3", "qw_nonpositive",
   list(qw_args = list(qw = QWN)))

#------------------------------------------------------------------------------
cat("\n[H] 내부 안전장치 — 위반 주입 + 장치별 돌연변이\n")
tp_vol <- function(path) function(stage) if (identical(stage, "before_backup")) {   # 백업 직전 제3자 쓰기(Vol)
  z <- as.data.table(read_parquet(path, mmap = FALSE)); z[1L, Vol := Vol + 7]; write_parquet(z, path) }
tp_size <- function(path) function(stage) if (identical(stage, "before_load")) {    # 백업 뒤·로드 전 계획 행 Size 변경
  z <- as.data.table(read_parquet(path, mmap = FALSE)); z[Date == START & Ticker == TK[2], Size := Size + 1]; write_parquet(z, path) }
tp_clobber <- function(path) function(stage) if (identical(stage, "after_rename")) { # rename 직후 파일이 다른 내용으로
  z <- as.data.table(read_parquet(path, mmap = FALSE)); z[2L, Close := Close + 3]; write_parquet(z, path) }
eh <- function(tag, hook_fn, fn = rawdata_size_from_quantiwise, env_args = list()) {
  e <- do.call(mk_env, c(list(tag), env_args)); r0 <- md5(e$raw); c0 <- md5(e$cfg)
  m <- errmsg(fn(start = START, end = END, xlsx = e$xlsx, rawdata = e$raw, out_dir = e$out, backup_dir = e$bak,
                 runner_config = e$cfg, fdb_dir = e$fdb, dry_run = FALSE, .hook_stage = hook_fn(e$raw)))
  z <- as.data.table(read_parquet(e$raw, mmap = FALSE))
  list(e = e, m = m, r0 = r0, raw_same = identical(md5(e$raw), r0), cfg_same = identical(md5(e$cfg), c0), z = z)
}
h1 <- eh("H1", tp_vol)
chk("H1 [위반] 백업 전 제3자 쓰기 → '백업 md5 불일치' 중단 · 제3자 판 보존 · 러너 복원",
    grepl("백업 md5 불일치", h1$m) && identical(h1$z$Vol[1], RAW0$Vol[1] + 7) && h1$cfg_same, h1$m)
h2 <- eh("H2", tp_size)
chk("H2 [위반] 계획 뒤 계획 행 Size 변경 → '계획 뒤 RAWDATA Size' 중단 · 제3자 판 보존 · 러너 복원",
    grepl("계획 뒤 RAWDATA Size", h2$m) && isTRUE(h2$z[Date == START & Ticker == TK[2]]$Size ==
                                                  RAW0[Date == START & Ticker == TK[2]]$Size + 1) && h2$cfg_same, h2$m)
h3 <- eh("H3", tp_clobber)
chk("H3 [위반] rename 뒤 내용 불일치 → '교체 후 md5 불일치' · 백업으로 되돌림(원본 md5) · 러너 복원",
    grepl("교체 후 md5 불일치", h3$m) && h3$raw_same && h3$cfg_same, h3$m)
mk_cfg_extra <- function(path) {    # 최상위 paused_reason 줄에 다른 키가 같은 줄로 붙은 설정(유효 JSON)
  mk_cfg(path); s <- rawToChar(readBin(path, "raw", file.info(path)$size)); Encoding(s) <- "bytes"
  s <- sub('(?m)^  "paused_reason": [^\n]*$', '  "paused_reason": "x", "zz_probe": 1,', s, perl = TRUE, useBytes = TRUE)
  con <- file(path, "wb"); writeBin(charToRaw(s), con); close(con); path
}
fh <- mk_cfg_extra(file.path(FX, "H4_cfg.json")); mh0 <- md5(fh)
chk("H4a 픽스처: zz_probe 가 최상위 키로 읽힌다", identical(fromJSON(fh, simplifyVector = FALSE)$zz_probe, 1L))
m4h <- errmsg(qws_runner_pause(fh, "x"))
chk("H4 [위반] 두 줄 교체가 다른 키(zz_probe)를 지우면 '편집 검증 실패' · 설정 무접촉", grepl("편집 검증 실패", m4h) && identical(md5(fh), mh0), m4h)
eh4 <- mk_env("H4r"); mk_cfg_extra(eh4$cfg); c4 <- md5(eh4$cfg); r4 <- md5(eh4$raw)
m4r <- errmsg(run(eh4, dry_run = FALSE))
chk("H4r run() 경로도 설정·RAWDATA 무접촉 중단", !is.na(m4r) && identical(md5(eh4$cfg), c4) && identical(md5(eh4$raw), r4), m4r)
MH1 <- mut("if (!identical(.qws_md5(bk), fp0$md5)) stop(", "if (FALSE) stop(")
x <- eh("MH1", tp_vol, fn = MH1$rawdata_size_from_quantiwise)
chk("MH1 백업 md5 대조 제거 → H1 의 '백업 md5 불일치' 소멸(H1 red 는 이 장치 몫)", !grepl("백업 md5 불일치", x$m), x$m)
MH2 <- mut("if (!identical(raw$Size[idx], chg$Size)) stop(", "if (FALSE) stop(")
x <- eh("MH2", tp_size, fn = MH2$rawdata_size_from_quantiwise)
chk("MH2 Size 재대조 제거 → H2 의 '계획 뒤 RAWDATA Size' 소멸", !grepl("계획 뒤 RAWDATA Size", x$m), x$m)
MH3 <- mut("if (!identical(.qws_md5(rawdata), md5_tmp)) {", "if (FALSE) {")
x <- eh("MH3", tp_clobber, fn = MH3$rawdata_size_from_quantiwise)
chk("MH3 rename 후 md5 제거 → 불일치 파일이 남는다(백업 복원 없음)", is.na(x$m) && !x$raw_same &&
      !identical(md5(x$e$raw), md5(file.path(x$e$bak, list.files(x$e$bak, pattern = "bak_size_qw_")[1]))), x$m)
MH4 <- mut("if (!identical(j1$enabled, FALSE) || !identical(j0x, j1x))", "if (FALSE)")
fm <- mk_cfg_extra(file.path(FX, "MH4_cfg.json")); fm0 <- md5(fm)
st4 <- tryCatch(MH4$qws_runner_pause(fm, "x"), error = function(e) e)
chk("MH4 JSON 동치 제거 → zz_probe 가 지워진 채 기록된다(H4 red 는 이 장치 몫)",
    !inherits(st4, "error") && !identical(md5(fm), fm0) && is.null(fromJSON(fm, simplifyVector = FALSE)$zz_probe))

#------------------------------------------------------------------------------
cat("\n[I] 재빌드 — 기본 빌더 경로 · 실패 보고서\n")
# ★안전: 실제 factor_db_builder.R 를 source 하지 않도록 가짜 전역 빌더를 먼저 심는다(exists 분기)
fake_calls <- list()
set_fake_builder <- function(rawdata_cache, fdb_dir, cache_dir = NULL) {
  assign("build_factor_db", function(sig, save = TRUE, force = FALSE) {
    fake_calls[[length(fake_calls) + 1L]] <<- list(sig = sig, save = save, force = force); invisible(TRUE) }, envir = globalenv())
  assign(".load_base_data", function(force = FALSE) invisible(NULL), envir = globalenv())
  assign("RAWDATA_CACHE", rawdata_cache, envir = globalenv()); assign("FACTOR_DB_DIR", fdb_dir, envir = globalenv())
  if (!is.null(cache_dir)) assign("CACHE_DIR", cache_dir, envir = globalenv())
}
clr_fake_builder <- function() suppressWarnings(rm(list = intersect(c("build_factor_db", ".load_base_data", "RAWDATA_CACHE",
                                                                      "FACTOR_DB_DIR", "CACHE_DIR"), ls(globalenv(), all.names = TRUE)),
                                                   envir = globalenv()))
chk("I0 경로 동일성: 대소문자·구분자 무시 · NA = 다름", .qws_same_path("C:/a/B.parquet", "c:\\a\\b.parquet") &&
      !.qws_same_path("C:/a/B.parquet", "C:/a/C.parquet") && !.qws_same_path(NA_character_, "C:/a"))
ELSE <- file.path(FX, "elsewhere"); dir.create(file.path(ELSE, "factor_db"), recursive = TRUE, showWarnings = FALSE)
set_fake_builder(file.path(ELSE, "RAWDATA.parquet"), file.path(ELSE, "factor_db"))
fake_calls <- list()
ei1 <- mk_env("I1"); r1 <- md5(ei1$raw); c1 <- md5(ei1$cfg)
m1i <- errmsg(run(ei1, dry_run = FALSE, rebuild_fdb = TRUE))
chk("I1 [위반] 사본 경로 + 기본 빌더 → 쓰기 전 거부(RAWDATA·러너 무접촉 · 백업 폴더 없음 · 빌더 미호출)",
    grepl("기본 빌더의 전역 경로와 다르다", m1i) && identical(md5(ei1$raw), r1) && identical(md5(ei1$cfg), c1) &&
      !dir.exists(ei1$bak) && !length(fake_calls), m1i)
chk("I1b dry-run 은 빌더 경로와 무관(거부 없음)", is.na(errmsg(run(ei1, dry_run = TRUE, rebuild_fdb = TRUE))))
ei3 <- mk_env("I3")
set_fake_builder(file.path(ei3$dir, "RAWDATA.parquet"), file.path(ei3$dir, "factor_db"), cache_dir = ei3$dir)
fake_calls <- list(); c3 <- md5(ei3$cfg)
res3 <- tryCatch(run(ei3, dry_run = FALSE, rebuild_fdb = TRUE), error = function(e) e)
chk("I3 [양성] 경로가 전역과 같으면 기본 빌더 사용 — APPLIED · 가짜 빌더 1회(sig 09-10) · 러너 복원",
    !inherits(res3, "error") && identical(res3$report$status, "APPLIED") && length(fake_calls) == 1L &&
      identical(fake_calls[[1]]$sig, as.Date("2026-09-10")) && identical(md5(ei3$cfg), c3),
    if (inherits(res3, "error")) conditionMessage(res3) else "")
ei4 <- mk_env("I4")
set_fake_builder(file.path(ei4$dir, "RAWDATA.parquet"), file.path(ELSE, "factor_db"), cache_dir = ei4$dir)
fake_calls <- list(); c4i <- md5(ei4$cfg); r4i <- md5(ei4$raw)
m4i <- errmsg(run(ei4, dry_run = FALSE, rebuild_fdb = TRUE))
rp4 <- list.files(ei4$out, pattern = "^qw_size_apply_.*\\.json$", full.names = TRUE)
j4 <- if (length(rp4)) fromJSON(rp4[1], simplifyVector = FALSE) else NULL
chk("I4 [위반] 빌더 안 이중 대조(FACTOR_DB_DIR ≠ fdb_dir) → 빌더 미호출 · 재빌드 실패 보고서 APPLIED_FDB_FAILED",
    grepl("재빌드 실패", m4i) && !length(fake_calls) && identical(j4$status, "APPLIED_FDB_FAILED") &&
      grepl("전역 경로", j4$apply$fdb_error %||% ""), m4i)
chk("I4b RAWDATA 는 교체됐고(보고서가 그 사실을 적는다) 러너는 복원 · 202609 = building",
    !identical(md5(ei4$raw), r4i) && identical(md5(ei4$cfg), c4i) && identical(j4$apply$fdb$`202609`$status, "building") &&
      isTRUE(j4$apply$runner_restore$byte_identical))
clr_fake_builder()
ei5 <- mk_env("I5"); c5 <- md5(ei5$cfg)
m5i <- errmsg(run(ei5, dry_run = FALSE, rebuild_fdb = TRUE, .fdb_build = function(sig) stop("boom_fdb")))
rp5 <- list.files(ei5$out, pattern = "^qw_size_apply_.*\\.json$", full.names = TRUE)
j5 <- if (length(rp5)) fromJSON(rp5[1], simplifyVector = FALSE) else NULL
chk("I5 [위반] 빌더 오류 → 보고서 APPLIED_FDB_FAILED(오류·RAWDATA 백업·진행 월) · 러너 복원 · 오류에 보고서 경로",
    grepl("boom_fdb", m5i) && identical(j5$status, "APPLIED_FDB_FAILED") && grepl("boom_fdb", j5$apply$fdb_error %||% "") &&
      file.exists(j5$apply$backup$path %||% "") && identical(md5(ei5$cfg), c5) &&
      length(rp5) == 1L && grepl(basename(rp5[1]), m5i, fixed = TRUE), m5i)
MI1 <- mut("fr <- tryCatch(.qws_rebuild_fdb(start, fdb_dir, backup_dir, builder, stamp, acc = acc), error = function(e) e)",
           "fr <- .qws_rebuild_fdb(start, fdb_dir, backup_dir, builder, stamp, acc = acc)")
em1 <- mk_env("MI1")
invisible(errmsg(MI1$rawdata_size_from_quantiwise(start = START, end = END, xlsx = em1$xlsx, rawdata = em1$raw, out_dir = em1$out,
                                                  backup_dir = em1$bak, runner_config = em1$cfg, fdb_dir = em1$fdb, dry_run = FALSE,
                                                  rebuild_fdb = TRUE, .fdb_build = function(sig) stop("boom_fdb"))))
chk("MI1 재빌드 오류 포착 제거 → 보고서 없음(I5 red 는 이 장치 몫)",
    !length(list.files(em1$out, pattern = "^qw_size_apply_.*\\.json$")))
set_fake_builder(file.path(ELSE, "RAWDATA.parquet"), file.path(ELSE, "factor_db"))   # 돌연변이가 빌더에 닿아도 가짜 + 이중 대조
fake_calls <- list()
MI2 <- mut("if (!.qws_same_path(rawdata, tg$rawdata) || !.qws_same_path(fdb_dir, tg$fdb_dir))", "if (FALSE)")
em2 <- mk_env("MI2"); rm2 <- md5(em2$raw)
mm2 <- errmsg(MI2$rawdata_size_from_quantiwise(start = START, end = END, xlsx = em2$xlsx, rawdata = em2$raw, out_dir = em2$out,
                                               backup_dir = em2$bak, runner_config = em2$cfg, fdb_dir = em2$fdb, dry_run = FALSE,
                                               rebuild_fdb = TRUE))
chk("MI2 사전 경로 대조 제거 → RAWDATA 가 먼저 바뀐다(I1 red 는 이 대조 몫 · 이중 대조가 빌더는 막음)",
    !identical(md5(em2$raw), rm2) && !length(fake_calls), mm2)
clr_fake_builder()

fin()
