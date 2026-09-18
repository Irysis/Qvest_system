#!/usr/bin/env Rscript
#==============================================================================
# test_incremental_update_file_guards.R — Update_File 증분 적재기 가드 3종 (양방향 · 2026-09-19)
#
# 왜 (실사고 2026-09-19 00:5x): 퀀티 갱신기가 Consensus_update.xlsx 를 여는 사이 적재기가 돌자
#   ① 엑셀 잠금 파일 '~$Consensus_update.xlsx' 가 '변경된 xlsx' 로 잡혀 **갱신 중인 옛 파일**로 컨센서스 적재가 돌았고
#   ② 파서가 함께 쓰는 ticker_map.parquet(Date 없음)에서 증분 루프가 죽었다 — 그 뒤 알파벳 순서의 메트릭은
#      붙지 못한다(지금까지는 12종이 전부 'ti' 앞이라 운 좋게 피했다)
#   ③ 그 오류를 cat 으로 삼켜, incremental_update_all 이 mtime 을 '처리됨' 으로 기록 → 재시도 없음
#
# 방법: 적재기 파일을 **파싱해서 필요한 함수만** 격리 환경에 올린다(config·캘린더 적재 없음 · 운영 파일 쓰기 0).
#   각 가드마다 돌연변이(해당 줄 제거) 사본이 결함을 재현하는지까지 잰다.
#
# 실행: Rscript --no-environ 08_Tests/data/test_incremental_update_file_guards.R
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
SRC  <- file.path(ROOT, "02_Infrastructure/data/incremental_update_file.R")
PASS <- 0L; FAIL <- 0L
ok <- function(m) { PASS <<- PASS + 1L; cat("  OK  ", m, "\n") }
ng <- function(m, why = "") { FAIL <<- FAIL + 1L; cat("  FAIL", m, if (nzchar(why)) paste0(" — ", why) else "", "\n") }
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a

src_lines <- readLines(SRC, warn = FALSE, encoding = "UTF-8")

# 파일에서 이름이 wanted 인 최상위 함수 정의만 골라 env 에 올린다 (lines = 돌연변이 사본 가능)
load_fns <- function(lines, wanted, env) {
  exprs <- parse(text = lines, keep.source = FALSE, encoding = "UTF-8")
  for (e in exprs) {
    if (is.call(e) && identical(as.character(e[[1]]), "<-") && is.name(e[[2]]) &&
        as.character(e[[2]]) %in% wanted) eval(e, envir = env)
  }
  miss <- setdiff(wanted, ls(env, all.names = TRUE))
  if (length(miss)) stop("함수 미발견: ", paste(miss, collapse = ", "))
  invisible(env)
}
# 한 줄(패턴)이 사라진 사본 — 돌연변이
drop_line <- function(lines, pattern) {
  hit <- grepl(pattern, lines, fixed = TRUE)
  if (!any(hit)) stop("돌연변이 대상 줄 미발견: ", pattern)
  lines[!hit]
}
new_env <- function() {
  env <- new.env(parent = globalenv())
  env$`%||%` <- `%||%`
  env
}
tmp <- tempfile("incr_guard_"); dir.create(tmp)

#------------------------------------------------------------------------------
# ① 잠금 파일 제외 — detect_update_changes
#------------------------------------------------------------------------------
setup_detect <- function(env) {
  ud <- file.path(tmp, paste0("upd_", sample.int(1e6, 1))); dir.create(ud)
  f <- file.path(ud, "Consensus_update.xlsx"); writeBin(as.raw(1:10), f)
  lp <- file.path(ud, "last.rds")
  saveRDS(list(time = Sys.time(), files = list(Consensus_update.xlsx = file.mtime(f))), lp)
  env$UPDATE_DIR <- ud; env$LAST_PROCESSED_FILE <- lp
  env$.get_last_processed <- function() readRDS(lp)
  lock <- file.path(ud, "~$Consensus_update.xlsx"); writeBin(as.raw(1:3), lock)
  list(ud = ud, f = f, lock = lock)
}
e1 <- load_fns(src_lines, "detect_update_changes", new_env())
s1 <- setup_detect(e1)
r1 <- e1$detect_update_changes()
if (!length(r1$changed)) ok("A1 잠금 파일(~$Consensus_update.xlsx)만 새로 생겼을 때 변경 0") else
  ng("A1", paste(basename(r1$changed), collapse = ","))
Sys.setFileTime(s1$f, Sys.time() + 5)
r1b <- e1$detect_update_changes()
if (identical(basename(r1b$changed), "Consensus_update.xlsx")) ok("A2 진짜 파일이 바뀌면 그것만 잡힌다(양성 대조)") else
  ng("A2", paste(basename(r1b$changed), collapse = ","))
if (!"~$Consensus_update.xlsx" %in% names(r1b$mtimes)) ok("A3 잠금 파일은 처리 기록(mtimes)에도 안 들어간다") else ng("A3")
# 돌연변이: 제외 줄을 지운 사본은 잠금 파일을 변경으로 잡아야 한다
e1m <- load_fns(drop_line(src_lines, 'startsWith(basename(update_files), "~$")'), "detect_update_changes", new_env())
s1m <- setup_detect(e1m)
r1m <- e1m$detect_update_changes()
if ("~$Consensus_update.xlsx" %in% basename(r1m$changed)) ok("A4 [돌연변이] 제외 줄 제거 → 잠금 파일이 변경으로 잡힌다(= A1 이 결함을 잡는다)") else
  ng("A4 돌연변이 무반응", paste(basename(r1m$changed), collapse = ","))

#------------------------------------------------------------------------------
# ② 컨센서스 증분 붙이기 — ticker_map 은 합집합, Date 없는 파일은 건너뛰고, 그 뒤 메트릭도 붙는다
#------------------------------------------------------------------------------
mk_cons <- function() {
  root <- file.path(tmp, paste0("cons_", sample.int(1e6, 1)))
  td <- file.path(root, "tmp"); cd <- file.path(root, "cache"); dir.create(td, recursive = TRUE); dir.create(cd)
  d_old <- as.Date(c("2026-08-27", "2026-08-28")); d_new <- as.Date(c("2026-08-28", "2026-08-31", "2026-09-18"))
  for (m in c("eps_1y", "zz_after_ticker_map")) {           # zz_* 는 알파벳상 ticker_map 뒤 — 구판의 희생자
    write_parquet(data.table(Date = d_old, Ticker = "A000020", Value = c(1, 2)), file.path(cd, paste0(m, ".parquet")))
    write_parquet(data.table(Date = d_new, Ticker = "A000020", Value = c(9, 3, 4)), file.path(td, paste0(m, ".parquet")))
  }
  write_parquet(data.table(Ticker = c("A000020", "A000030"), Name = c("OLD", "OLDONLY")), file.path(cd, "ticker_map.parquet"))
  write_parquet(data.table(Ticker = c("A000020", "A999990"), Name = c("NEW", "IPO")), file.path(td, "ticker_map.parquet"))
  list(td = td, cd = cd)
}
e2 <- load_fns(src_lines, ".consensus_append_increment", new_env())
c2 <- mk_cons()
res2 <- tryCatch(e2$.consensus_append_increment(c2$td, c2$cd, as.Date("2026-08-28")), error = function(e) e)
if (!inherits(res2, "error")) ok("B1 ticker_map 이 섞여도 오류 없이 끝난다") else ng("B1", conditionMessage(res2))
zz <- as.data.table(read_parquet(file.path(c2$cd, "zz_after_ticker_map.parquet")))
if (max(zz$Date) == as.Date("2026-09-18") && nrow(zz) == 4L) ok("B2 ticker_map 뒤 알파벳 메트릭도 붙는다(+2행 · 기존 08-28 유지 · 겹침 없음)") else
  ng("B2", sprintf("max=%s n=%d", max(zz$Date), nrow(zz)))
eps <- as.data.table(read_parquet(file.path(c2$cd, "eps_1y.parquet")))
if (max(eps$Date) == as.Date("2026-09-18") && eps[Date == as.Date("2026-08-28"), Value] == 2) ok("B3 base_max 이하 행은 건드리지 않는다(08-28 은 기존값 2)") else
  ng("B3", sprintf("08-28=%s", eps[Date == as.Date("2026-08-28"), Value]))
tm <- as.data.table(read_parquet(file.path(c2$cd, "ticker_map.parquet")))
if (setequal(tm$Ticker, c("A000020", "A000030", "A999990")) && tm[Ticker == "A000020", Name] == "NEW")
  ok("B4 ticker_map = 합집합(구 종목 보존 · 신규 상장 추가 · 새 이름 우선)") else
  ng("B4", paste(tm$Ticker, tm$Name, collapse = ";"))
if (!length(list.files(c2$cd, pattern = "\\.tmp$"))) ok("B5 임시 파일(.tmp) 잔재 없음(원자 교체)") else ng("B5")
# 돌연변이: ticker_map 분기와 Date 가드를 지우면(= 구판) 오류로 죽고 zz 가 안 붙는다
mut <- src_lines
i0 <- grep('if (identical(metric, "ticker_map.parquet")) {', mut, fixed = TRUE)
i1 <- grep('cat(sprintf("  %s: Date 열 없음', mut, fixed = TRUE)
if (length(i0) == 1L && length(i1) == 1L) {
  # ticker_map 분기 시작 ~ Date 가드 블록 끝(cat 다음 'next' · '}')까지 제거
  mut <- mut[-(i0:(i1 + 2L))]
  e2m <- load_fns(mut, ".consensus_append_increment", new_env())
  c2m <- mk_cons()
  r2m <- tryCatch(e2m$.consensus_append_increment(c2m$td, c2m$cd, as.Date("2026-08-28")), error = function(e) e)
  zzm <- as.data.table(read_parquet(file.path(c2m$cd, "zz_after_ticker_map.parquet")))
  if (inherits(r2m, "error") && max(zzm$Date) == as.Date("2026-08-28"))
    ok("B6 [돌연변이] 가드 제거 → ticker_map 에서 죽고 뒤 메트릭 미적재(= B1·B2 가 결함을 잡는다)") else
    ng("B6 돌연변이 무반응", sprintf("error=%s zz_max=%s", inherits(r2m, "error"), max(zzm$Date)))
} else ng("B6 돌연변이 적용 실패", sprintf("i0=%d i1=%d", length(i0), length(i1)))

#------------------------------------------------------------------------------
# ③ fail-closed — 파서가 죽으면 incremental_consensus 가 오류를 **전파**한다(삼키지 않는다)
#------------------------------------------------------------------------------
mk_consensus_env <- function(lines, parser_body) {
  env <- load_fns(lines, c("incremental_consensus", ".consensus_append_increment"), new_env())
  root <- file.path(tmp, paste0("ic_", sample.int(1e6, 1)))
  dirs <- list(upd = file.path(root, "upd"), cache = file.path(root, "cache"), data = file.path(root, "data"))
  for (d in dirs) dir.create(d, recursive = TRUE)
  dir.create(file.path(dirs$cache, "consensus"))
  writeBin(as.raw(1:10), file.path(dirs$upd, "Consensus_update.xlsx"))
  write_parquet(data.table(Date = as.Date("2026-08-28"), Ticker = "A000020", Value = 1),
                file.path(dirs$cache, "consensus", "eps_1y.parquet"))
  writeLines(parser_body, file.path(dirs$data, "consensus_parser.R"))
  env$UPDATE_DIR <- dirs$upd; env$CACHE_DIR <- dirs$cache; env$DATA_DIR <- dirs$data
  assign("CONSENSUS_CACHE", "ORIG_CACHE", envir = globalenv())
  assign("CONSENSUS_XLSX", "ORIG_XLSX", envir = globalenv())
  list(env = env, dirs = dirs)
}
broken <- 'consensus_build_cache <- function(force = FALSE) stop("parser boom")'
good <- c('consensus_build_cache <- function(force = FALSE) {',
          '  arrow::write_parquet(data.table::data.table(Date = as.Date("2026-09-18"), Ticker = "A000020", Value = 5),',
          '                       file.path(CONSENSUS_CACHE, "eps_1y.parquet"))',
          '  arrow::write_parquet(data.table::data.table(Ticker = "A000020", Name = "N"), file.path(CONSENSUS_CACHE, "ticker_map.parquet"))',
          '}')
k3 <- mk_consensus_env(src_lines, broken)
r3 <- tryCatch({ k3$env$incremental_consensus(); "returned" }, error = function(e) conditionMessage(e))
if (grepl("parser boom", r3, fixed = TRUE)) ok("C1 파서 실패 → incremental_consensus 가 오류를 전파(재시도 가능)") else ng("C1", r3)
if (identical(get("CONSENSUS_CACHE", envir = globalenv()), "ORIG_CACHE")) ok("C2 실패해도 전역 CONSENSUS_CACHE 원복(finally)") else ng("C2")
if (!dir.exists(file.path(k3$dirs$cache, "consensus_tmp"))) ok("C3 실패해도 임시 폴더 정리") else ng("C3")
k3g <- mk_consensus_env(src_lines, good)
r3g <- tryCatch({ k3g$env$incremental_consensus(); "returned" }, error = function(e) conditionMessage(e))
e3g <- as.data.table(read_parquet(file.path(k3g$dirs$cache, "consensus", "eps_1y.parquet")))
if (identical(r3g, "returned") && max(e3g$Date) == as.Date("2026-09-18")) ok("C4 정상 파서 → 반환·적재(양성 대조)") else
  ng("C4", sprintf("%s · max=%s", r3g, max(e3g$Date)))
# 돌연변이: stop 줄을 지운 사본(= 구판처럼 삼킴)은 오류 없이 '반환' 해야 한다
k3m <- mk_consensus_env(drop_line(src_lines, 'stop(sprintf("[incr_consensus] 오류: %s"'), broken)
r3m <- tryCatch({ k3m$env$incremental_consensus(); "returned" }, error = function(e) conditionMessage(e))
if (identical(r3m, "returned")) ok("C5 [돌연변이] stop 제거 → 실패가 삼켜진다(= C1 이 결함을 잡는다)") else ng("C5 돌연변이 무반응", r3m)

unlink(tmp, recursive = TRUE)
cat(sprintf("\n합계: 통과 %d · 실패 %d\n", PASS, FAIL))
cat(sprintf('{"test":"incremental_update_file_guards","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
if (FAIL > 0L) quit(status = 1)
