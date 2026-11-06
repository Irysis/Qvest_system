#!/usr/bin/env Rscript
#==============================================================================
# test_incremental_update_file_guards.R — Update_File 증분 적재기 가드 3종 (양방향 · 2026-09-19 · 2026-11-06 새 계약 재도출)
#
# 왜 (실사고 2026-09-19 00:5x): 퀀티 갱신기가 Consensus_update.xlsx 를 여는 사이 적재기가 돌자
#   ① 엑셀 잠금 파일 '~$Consensus_update.xlsx' 가 '변경된 xlsx' 로 잡혀 **갱신 중인 옛 파일**로 컨센서스 적재가 돌았고
#   ② 파서가 함께 쓰는 ticker_map.parquet(Date 없음)에서 증분 루프가 죽었다 — 그 뒤 알파벳 순서의 메트릭은
#      붙지 못한다(지금까지는 12종이 전부 'ti' 앞이라 운 좋게 피했다)
#   ③ 그 오류를 cat 으로 삼켜, incremental_update_all 이 mtime 을 '처리됨' 으로 기록 → 재시도 없음
#
# ★2026-11-06 계약 변경(F3 받은 창 교체 · F4 공용 관문 — 08_Tests/data/test_incremental_update_gates.R)에 맞춘 재도출:
#   B3 구 단정 = 'base_max(08-28) 이하 행은 안 건드린다'. 지키던 위험 = **증분이 기존 이력을 망가뜨리지 않는다**(덮어쓰기 ·
#      중복). 새 계약에선 받은 창 날짜(08-28 포함)가 교체 대상이므로 같은 위험을 이렇게 다시 잰다: 창 밖(08-27) = 기존값 그대로 ·
#      창 안(08-28) = 새 값 9 로 **한 번만**(같은 (Date, Ticker) 중복 0) · 행 수 = 창 밖 + 새 행. 구 단정보다 좁아지지 않는다(중복까지 잰다).
#   B6 구 돌연변이 = ticker_map 분기 + Date 가드 제거 → 죽고 뒤 메트릭 미적재. 지금 정상 경로(관문 창 named list)에서는 창 표에
#      없는 ticker_map 이 '받은 창 정보 없음'으로 건너뛰어져 죽지는 않는다 — 대신 종목명 합집합이 사라진다(B4 가 잡는다: B6b).
#      창 없이 부르는 경로(구 위치 인자 · NULL)에서는 여전히 죽는다(B6a = 구 단정 그대로).
#   C4 구 단정 = '정상 파서 → 반환 · 적재'(C1 의 양성 대조). 10바이트 가짜 xlsx 로는 이제 관문(탐침)이 통과할 수 없으므로,
#      양성 대조를 **실제 관문을 통과하는 합성 책**(질의 시트 · B6 괄호 = 목표일 · 1년치 이력)으로 다시 세운다 — 하네스가 '전부 실패'
#      하는 상태가 아니어야 C1 의 '오류 전파'가 의미를 가진다. 가짜 xlsx 는 C6(probe_failed 거부 · 캐시 무접촉)으로 고정한다.
#
# 방법: 적재기 파일을 **파싱해서 필요한 정의만** 격리 환경에 올린다(config·캘린더 적재 없음 · 운영 파일 쓰기 0).
#   각 가드마다 돌연변이(해당 줄 제거) 사본이 결함을 재현하는지까지 잰다.
#
# 실행: R_ENVIRON_USER=<빈 파일> Rscript 08_Tests/data/test_incremental_update_file_guards.R   (QW_UF_GUARDS_SRC 로 검사 대상 교체 가능)
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow) })
# 루트 = 자기 위치 먼저(테스트 러너 self-first · r-portability.md ④-b) → CLAUDE_PROJECT_DIR → QM_ROOT(④). 표지 = 검사 대상 파일.
.root_resolve <- function(marker = "02_Infrastructure/data/incremental_update_file.R") {
  fa <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
  self <- if (length(fa)) file.path(dirname(gsub("\\\\", "/", sub("^--file=", "", fa[1]))), "..", "..") else ""
  cands <- c(self = self, CLAUDE_PROJECT_DIR = Sys.getenv("CLAUDE_PROJECT_DIR", ""), QM_ROOT = Sys.getenv("QM_ROOT", ""))
  cands <- gsub("\\\\", "/", cands)
  hit <- cands[nzchar(cands) & file.exists(file.path(cands, marker))]
  if (!length(hit)) return(NA_character_)
  if (names(hit)[1] != "self" && nzchar(self))
    message(sprintf("⚠ ANCHOR OVERRIDE: 자기 위치(%s)에 표지 없음 → %s=%s", self, names(hit)[1], hit[[1]]))
  hit[[1]]
}
TEST_NAME <- "incremental_update_file_guards"
PASS <- 0L; FAIL <- 0L
ok <- function(m) { PASS <<- PASS + 1L; cat("  OK  ", m, "\n") }
ng <- function(m, why = "") { FAIL <<- FAIL + 1L; cat("  FAIL", m, if (nzchar(why)) paste0(" — ", why) else "", "\n") }
preflight_fail <- function(why) {
  cat(sprintf("FAIL(preflight): %s — 계측이 살아 있지 않아 케이스 결과를 발행하지 않는다\n", why))
  cat(sprintf('{"test":"%s","pass":0,"fail":1,"preflight":"%s"}\n', TEST_NAME, gsub('"', "'", why)))
  quit(status = 1)
}
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
# 사례 하나가 시험 코드 쪽에서 죽어도 스크립트를 끝내지 않는다(마지막 JSON 줄이 없으면 배터리가 판정하지 못한다) — 그 사례만 FAIL
case <- function(id, expr) tryCatch(expr, error = function(e) ng(id, paste("사례 실행 오류:", conditionMessage(e))))
read_pq <- function(p) tryCatch(as.data.table(read_parquet(p)), error = function(e) NULL)

ROOT <- .root_resolve()
if (is.na(ROOT)) preflight_fail("프로젝트 루트 미발견(자기 위치 · CLAUDE_PROJECT_DIR · QM_ROOT 어디에도 표지 없음)")
SRC  <- Sys.getenv("QW_UF_GUARDS_SRC", file.path(ROOT, "02_Infrastructure/data/incremental_update_file.R"))
src_lines <- sub("\r$", "", readLines(SRC, warn = FALSE, encoding = "UTF-8"))
cat(sprintf("[%s] 대상: %s (%d줄)\n", TEST_NAME, SRC, length(src_lines)))

# 파일에서 이름이 wanted 인(또는 정규식 want_re 에 맞는) 최상위 정의만 골라 env 에 올린다 (lines = 돌연변이 사본 가능)
load_fns <- function(lines, wanted, env, want_re = NULL) {
  exprs <- parse(text = lines, keep.source = FALSE, encoding = "UTF-8")
  for (e in exprs) {
    if (is.call(e) && identical(as.character(e[[1]]), "<-") && is.name(e[[2]]) &&
        (as.character(e[[2]]) %in% wanted || (!is.null(want_re) && grepl(want_re, as.character(e[[2]]))))) eval(e, envir = env)
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
case("A", {
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
})

#------------------------------------------------------------------------------
# ② 컨센서스 증분 붙이기 — ticker_map 은 합집합, Date 없는 파일은 건너뛰고, 그 뒤 메트릭도 붙는다 · 받은 창 교체(2026-11-06)
#------------------------------------------------------------------------------
D_OLD <- as.Date(c("2026-08-27", "2026-08-28")); D_NEW <- as.Date(c("2026-08-28", "2026-08-31", "2026-09-18"))
mk_cons <- function() {
  root <- file.path(tmp, paste0("cons_", sample.int(1e6, 1)))
  td <- file.path(root, "tmp"); cd <- file.path(root, "cache"); dir.create(td, recursive = TRUE); dir.create(cd)
  for (m in c("eps_1y", "zz_after_ticker_map")) {           # zz_* 는 알파벳상 ticker_map 뒤 — 구판의 희생자
    write_parquet(data.table(Date = D_OLD, Ticker = "A000020", Value = c(1, 2)), file.path(cd, paste0(m, ".parquet")))
    write_parquet(data.table(Date = D_NEW, Ticker = "A000020", Value = c(9, 3, 4)), file.path(td, paste0(m, ".parquet")))
  }
  write_parquet(data.table(Ticker = c("A000020", "A000030"), Name = c("OLD", "OLDONLY")), file.path(cd, "ticker_map.parquet"))
  write_parquet(data.table(Ticker = c("A000020", "A999990"), Name = c("NEW", "IPO")), file.path(td, "ticker_map.parquet"))
  list(td = td, cd = cd)
}
# 받은 창 = 관문 탐침이 내는 지표별 시트 날짜축(정상 경로 incremental_consensus 가 넘기는 모양 그대로)
W_B <- list(eps_1y = D_NEW, zz_after_ticker_map = D_NEW)
b_run <- function(lines, third) {
  e <- load_fns(lines, ".consensus_append_increment", new_env())
  c2 <- mk_cons()
  res <- tryCatch({ capture.output(r <- e$.consensus_append_increment(c2$td, c2$cd, third)); r }, error = function(err) err)
  list(res = res, zz = read_pq(file.path(c2$cd, "zz_after_ticker_map.parquet")), eps = read_pq(file.path(c2$cd, "eps_1y.parquet")),
       tm = read_pq(file.path(c2$cd, "ticker_map.parquet")), tmp_left = list.files(c2$cd, pattern = "\\.tmp$"))
}
# 창 교체가 기존 이력을 망가뜨리지 않았나 — 창 밖 그대로 · 창 안 새 값 한 번만 · 중복 0 · 행 수
history_intact <- function(x) !is.null(x) && nrow(x) == 4L && !anyDuplicated(x[, .(Date, Ticker)]) &&
  identical(x[Date == as.Date("2026-08-27"), Value], 1) && identical(x[Date == as.Date("2026-08-28"), Value], 9)
case("B", {
  b <- b_run(src_lines, W_B)
  if (!inherits(b$res, "error")) ok("B1 ticker_map 이 섞여도 오류 없이 끝난다(정상 경로 = 지표별 받은 창)") else ng("B1", conditionMessage(b$res))
  if (!is.null(b$zz) && max(b$zz$Date) == as.Date("2026-09-18") && nrow(b$zz) == 4L)
    ok("B2 ticker_map 뒤 알파벳 메트릭도 붙는다(08-27 유지 · 08-28 교체 · 08-31 · 09-18 추가 = 4행)") else
    ng("B2", if (is.null(b$zz)) "zz 판독 불가" else sprintf("max=%s n=%d", max(b$zz$Date), nrow(b$zz)))
  if (history_intact(b$eps))
    ok("B3 증분이 이력을 망가뜨리지 않는다(새 계약): 창 밖 08-27 = 기존값 1 · 창 안 08-28 = 새 값 9 한 번만 · (Date,Ticker) 중복 0 · 4행") else
    ng("B3", if (is.null(b$eps)) "eps 판독 불가" else paste(sprintf("%s=%s", b$eps$Date, b$eps$Value), collapse = ";"))
  if (!is.null(b$tm) && setequal(b$tm$Ticker, c("A000020", "A000030", "A999990")) && b$tm[Ticker == "A000020", Name] == "NEW")
    ok("B4 ticker_map = 합집합(구 종목 보존 · 신규 상장 추가 · 새 이름 우선)") else
    ng("B4", if (is.null(b$tm)) "ticker_map 판독 불가" else paste(b$tm$Ticker, b$tm$Name, collapse = ";"))
  if (!length(b$tmp_left)) ok("B5 임시 파일(.tmp) 잔재 없음(원자 교체)") else ng("B5", paste(b$tmp_left, collapse = ","))
  # 창 없이 부르는 경로(구 위치 인자 base_max 날짜 1개 → 경고 후 파싱 산출 날짜로 교체)도 같은 결과여야 한다
  bl <- b_run(src_lines, as.Date("2026-08-28"))
  if (!inherits(bl$res, "error") && !is.null(bl$zz) && max(bl$zz$Date) == as.Date("2026-09-18") && history_intact(bl$eps))
    ok("B7 구 위치 인자(base_max) 경로도 오류 없이 같은 결과(zz 붙음 · 이력 무손상)") else
    ng("B7", if (inherits(bl$res, "error")) conditionMessage(bl$res) else "결과 불일치")
})
# 돌연변이: ticker_map 분기와 Date 가드를 지운다(= 구판)
case("B6", {
  mut <- src_lines
  i0 <- grep('if (identical(metric, "ticker_map.parquet")) {', mut, fixed = TRUE)
  i1 <- grep('cat(sprintf("  %s: Date 열 없음', mut, fixed = TRUE)
  if (length(i0) == 1L && length(i1) == 1L && i1 > i0 && identical(trimws(mut[i1 + 2L]), "}")) {
    # ticker_map 분기 시작 ~ Date 가드 블록 끝(cat 다음 'next' · '}')까지 제거
    mut <- mut[-(i0:(i1 + 2L))]
    # (a) 창 없는 경로(NULL · 구 위치 인자) — 구 단정 그대로: ticker_map 에서 죽고 뒤 메트릭 미적재
    ma <- b_run(mut, NULL)
    if (inherits(ma$res, "error") && !is.null(ma$zz) && max(ma$zz$Date) == as.Date("2026-08-28"))
      ok("B6a [돌연변이] 가드 제거 · 창 없는 경로 → ticker_map 에서 죽고 뒤 메트릭 미적재(= B1·B2·B7 이 결함을 잡는다)") else
      ng("B6a 돌연변이 무반응", sprintf("error=%s zz_max=%s", inherits(ma$res, "error"), if (is.null(ma$zz)) NA else format(max(ma$zz$Date))))
    # (b) 정상 경로(지표별 창) — 창 표에 없는 ticker_map 이 건너뛰어져 죽지 않는 대신 종목명 합집합이 사라진다(B4 가 잡는다)
    mb <- b_run(mut, W_B)
    if (!inherits(mb$res, "error") && !is.null(mb$tm) && !"A999990" %in% mb$tm$Ticker)
      ok("B6b [돌연변이] 가드 제거 · 정상 경로 → 신규 상장 종목명 유실(= B4 가 결함을 잡는다)") else
      ng("B6b 돌연변이 무반응", sprintf("error=%s tm=%s", inherits(mb$res, "error"), if (is.null(mb$tm)) "NA" else paste(mb$tm$Ticker, collapse = ",")))
  } else ng("B6 돌연변이 적용 실패", sprintf("i0=%d i1=%d", length(i0), length(i1)))
})

#------------------------------------------------------------------------------
# ③ fail-closed — 파서가 죽으면 incremental_consensus 가 오류를 **전파**한다(삼키지 않는다) · 관문 양성 대조(2026-11-06)
#------------------------------------------------------------------------------
UF_RE <- "^(\\.uf_|\\.UF_)"     # 공용 관문(탐침 · 채움 · 기록) 정의 전부 — 실제 관문을 태운다
mk_consensus_env <- function(lines, parser_body, xlsx_writer = NULL) {
  env <- load_fns(lines, c("incremental_consensus", ".consensus_append_increment"), new_env(), want_re = UF_RE)
  root <- file.path(tmp, paste0("ic_", sample.int(1e6, 1)))
  dirs <- list(upd = file.path(root, "upd"), cache = file.path(root, "cache"), data = file.path(root, "data"))
  for (d in dirs) dir.create(d, recursive = TRUE)
  dir.create(file.path(dirs$cache, "consensus"))
  xl <- file.path(dirs$upd, "Consensus_update.xlsx")
  if (is.null(xlsx_writer)) writeBin(as.raw(1:10), xl) else xlsx_writer(xl)
  write_parquet(data.table(Date = as.Date("2026-08-28"), Ticker = "A000020", Value = 1),
                file.path(dirs$cache, "consensus", "eps_1y.parquet"))
  writeLines(parser_body, file.path(dirs$data, "consensus_parser.R"))
  env$UPDATE_DIR <- dirs$upd; env$CACHE_DIR <- dirs$cache; env$DATA_DIR <- dirs$data
  env$PROJECT_ROOT <- ROOT          # 파이썬 해석(.venv_qvest_ml 경로)에만 쓴다 — 쓰기 경로 아님
  assign("CONSENSUS_CACHE", "ORIG_CACHE", envir = globalenv())
  assign("CONSENSUS_XLSX", "ORIG_XLSX", envir = globalenv())
  list(env = env, dirs = dirs, xlsx = xl)
}
broken <- 'consensus_build_cache <- function(force = FALSE) stop("parser boom")'
case("C1-3", {
  k3 <- mk_consensus_env(src_lines, broken)
  # 목표일 인자를 주지 않는다 — 파서가 먼저 죽으므로 기본값(벤치 판독)은 평가되지 않는다(시그니처와 무관하게 오류 전파만 잰다)
  r3 <- tryCatch({ k3$env$incremental_consensus(); "returned" }, error = function(e) conditionMessage(e))
  if (grepl("parser boom", r3, fixed = TRUE)) ok("C1 파서 실패 → incremental_consensus 가 오류를 전파(재시도 가능)") else ng("C1", r3)
  if (identical(get("CONSENSUS_CACHE", envir = globalenv()), "ORIG_CACHE")) ok("C2 실패해도 전역 CONSENSUS_CACHE 원복(finally)") else ng("C2")
  if (!dir.exists(file.path(k3$dirs$cache, "consensus_tmp"))) ok("C3 실패해도 임시 폴더 정리") else ng("C3")
})

## C4 양성 대조 — 실제 관문(탐침 · B6 · 채움)을 통과하는 합성 책 + 정상 파서 대역 → 반환 · 적재 · 기록 loaded
if (!requireNamespace("openxlsx", quietly = TRUE)) preflight_fail("openxlsx 없음 — C4 양성 대조(관문 통과 합성 책)를 못 만든다")
TICK <- sprintf("A%06d", seq(10L, 120L, by = 10L))
bizdays <- function(from, to) { d <- seq(as.Date(from), as.Date(to), by = "day"); d[!format(d, "%u") %in% c("6", "7")] }
C_DAYS <- bizdays("2025-06-02", "2026-09-18")
C_WIN  <- tail(C_DAYS, 3L)                                 # 받은 창 09-16 ~ 09-18
C_TGT  <- max(C_WIN)                                       # 목표일(B6 괄호와 같게 — 대역 파서라 벤치를 따로 두지 않고 인자로 준다)
write_cons_book <- function(path) {
  wb <- openxlsx::createWorkbook(); nt <- length(TICK)
  hdr <- matrix(NA_character_, nrow = 14L, ncol = 1L + nt)
  hdr[1, 1:2] <- c("     Refresh     ", "Last Update : 2026-09-19 07:32:50"); hdr[2, 1] <- "0"
  hdr[3, 1] <- "Time Series (Company)"; hdr[4, 1:2] <- c("Frequency", "D")
  hdr[5, 1:2] <- c("Period(From)", format(min(C_WIN), "%Y%m%d"))
  hdr[6, 1:2] <- c("Period(To)", sprintf("CPD-1TD [%s]", format(C_TGT, "%Y%m%d")))
  hdr[8, ] <- c("Code", TICK); hdr[9, ] <- c("Name", paste0("N", seq_len(nt)))
  hdr[10, ] <- c("Item Code", rep("S000000", nt)); hdr[11, ] <- c("Unit", rep("Local", nt)); hdr[12, 1] <- "Base Date"
  hdr[14, ] <- c("D A T E", rep("EPS_1Y", nt))
  openxlsx::addWorksheet(wb, "EPS_1Y")
  openxlsx::writeData(wb, "EPS_1Y", as.data.frame(hdr, stringsAsFactors = FALSE), colNames = FALSE, startRow = 1)
  openxlsx::writeData(wb, "EPS_1Y", data.frame(D = C_WIN, matrix(5, nrow = length(C_WIN), ncol = nt)), colNames = FALSE, startRow = 15)
  openxlsx::saveWorkbook(wb, path, overwrite = TRUE)
  path
}
good <- c('CONSENSUS_METRICS <- c("EPS_1Y" = "eps_1y")',
          'consensus_build_cache <- function(force = FALSE) {',
          sprintf('  d <- as.Date(c(%s))', paste(sprintf('"%s"', format(C_WIN)), collapse = ", ")),
          sprintf('  tk <- c(%s)', paste(sprintf('"%s"', TICK), collapse = ", ")),
          '  arrow::write_parquet(data.table::CJ(Date = d, Ticker = tk)[, eps_1y := 5], file.path(CONSENSUS_CACHE, "eps_1y.parquet"))',
          '  arrow::write_parquet(data.table::data.table(Ticker = tk, Name = "N"), file.path(CONSENSUS_CACHE, "ticker_map.parquet"))',
          '}')
with_history <- function(k) {     # 관문 ② 채움비 기준 = 1년치 이상 적재분 이력(날짜마다 12종목)
  write_parquet(CJ(Date = head(C_DAYS, -3L), Ticker = TICK)[, eps_1y := round(runif(.N, 1, 1000), 2)],
                file.path(k$dirs$cache, "consensus", "eps_1y.parquet"))
  k
}
read_gate <- function(k) tryCatch(jsonlite::fromJSON(file.path(k$dirs$cache, "update_file_gate_consensus.json")), error = function(e) NULL)
case("C4", {
  k3g <- with_history(mk_consensus_env(src_lines, good, write_cons_book))
  # 계기 생존 — 탐침이 이 책을 실제로 읽는가(죽은 탐침의 거부를 '관문이 잘 막았다'로 읽지 않는다)
  cp <- k3g$env$.uf_probe_book(k3g$xlsx)
  if (!isTRUE(cp$ok) || !identical(cp$sheets[sheet == "EPS_1Y"]$n_dates, 3L))
    preflight_fail(sprintf("탐침 카나리아 실패(python=%s): %s", k3g$env$.uf_python(), if (!isTRUE(cp$ok)) cp$err else "날짜축 3일 아님"))
  r3g <- tryCatch({ capture.output(rv <- k3g$env$incremental_consensus(target = C_TGT)); rv }, error = function(e) e)
  e3g <- read_pq(file.path(k3g$dirs$cache, "consensus", "eps_1y.parquet"))
  rec <- read_gate(k3g)
  if (isTRUE(r3g) && !is.null(e3g) && max(e3g$Date) == C_TGT && e3g[Date %in% C_WIN, .N] == length(C_WIN) * length(TICK) &&
      e3g[Date %in% C_WIN, all(eps_1y == 5)] && identical(rec$status, "loaded"))
    ok("C4 정상 파서 + 관문 통과 책 → 반환·적재(받은 창 3일 × 12종목 · 기록 loaded — 양성 대조)") else
    ng("C4", sprintf("%s · max=%s · gate=%s", if (inherits(r3g, "error")) conditionMessage(r3g) else paste(class(r3g), collapse = "/"),
                     if (is.null(e3g)) NA else format(max(e3g$Date)), paste(names(rec$reasons), collapse = ",")))
})
case("C6", {
  # 가짜 xlsx(10바이트) + 정상 파서 → 관문이 탐침 실패로 거부: 오류가 아니라 거부 표지 · 캐시 무접촉 · 기록 refused
  k6 <- mk_consensus_env(src_lines, good)
  p6 <- file.path(k6$dirs$cache, "consensus", "eps_1y.parquet"); m0 <- unname(tools::md5sum(p6))
  r6 <- tryCatch({ capture.output(rv <- k6$env$incremental_consensus(target = C_TGT)); rv }, error = function(e) e)
  rec6 <- read_gate(k6)
  if (is.list(r6) && !inherits(r6, "condition") && isTRUE(r6$refused) && "probe_failed" %in% names(r6$reasons) &&
      identical(unname(tools::md5sum(p6)), m0) && identical(rec6$status, "refused") && !dir.exists(file.path(k6$dirs$cache, "consensus_tmp")))
    ok("C6 판독 불가 책(가짜 xlsx) → probe_failed 거부(오류 아님 · eps_1y md5 불변 · 기록 refused · tmp 정리)") else
    ng("C6", if (inherits(r6, "condition")) conditionMessage(r6) else if (is.list(r6)) paste(names(r6$reasons), collapse = ",") else
      paste(class(r6), collapse = "/"))
})
# 돌연변이: stop 줄을 지운 사본(= 구판처럼 삼킴)은 오류 없이 '반환' 해야 한다
case("C5", {
  k3m <- mk_consensus_env(drop_line(src_lines, 'stop(sprintf("[incr_consensus] 오류: %s"'), broken)
  r3m <- tryCatch({ k3m$env$incremental_consensus(); "returned" }, error = function(e) conditionMessage(e))
  if (identical(r3m, "returned")) ok("C5 [돌연변이] stop 제거 → 실패가 삼켜진다(= C1 이 결함을 잡는다)") else ng("C5 돌연변이 무반응", r3m)
})

unlink(tmp, recursive = TRUE)
cat(sprintf("\n합계: 통과 %d · 실패 %d\n", PASS, FAIL))
cat(sprintf('{"test":"%s","pass":%d,"fail":%d,"total":%d}\n', TEST_NAME, PASS, FAIL, PASS + FAIL))
if (FAIL > 0L) quit(status = 1)
