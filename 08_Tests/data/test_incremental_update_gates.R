#!/usr/bin/env Rscript
#==============================================================================
# test_incremental_update_gates.R — Update_File 적재 수리 F3 · F4 · F5 (양방향 · 2026-11-06 · 2차 보강 같은 날)
#
# 왜: 계획서 04_Research/01_reports/quantiwise_data_expansion_20261106/PLAN.md §3.0
#   F3 컨센서스가 eps_1y 하나의 max 이후만 붙였다 → 뒤처진 지표의 날을 영구 손실(4지표 10-19).
#      수급도 패널 전체 max 이후만 붙였다 → 한 유형만 빈 날(10-20~10-30 개인 · 기타법인)은 다시 받아도 못 메웠다.
#   F4 시트 지평선 · 채움 관문이 OHLCVS 에만 있었다 → 부분 갱신본이 그대로 적재됐다.
#   F5 미등록 xlsx 가 '처리됨'으로 묻히고, 이름 부분 문자열로 엉뚱한 적재기가 돌았다.
#   (2차 · 독립 검증 지적) ① 수급 1차 판이 4유형 창의 합집합으로 지워 시트 창이 다른 유형의 행을 잃었다 → 유형별 교체 고정(I8)
#     ② date_axis_missing · not_query_sheet · sheet_read_error 를 고정하는 사례가 없었다(그 줄을 지운 사본이 46/46 통과) → H9~H11 · I7
#     ③ C6 가 성공 반환값(TRUE)에 $ 를 써 컨센서스가 거부를 멈추면 스크립트가 죽었다 → 반환값 안전 접근(rf · rsn)
#
# 무엇을 재나(전부 tempdir 모래상자 · 합성 xlsx/parquet · 운영 .cache · 06_Registry · 03_Universe 쓰기 0):
#   P 사전 점검 — openxlsx · 파이썬 탐침 카나리아(실패 = 결과 미발행 · preflight 로 끊는다)
#   G 채움비 판정 순수 함수 — 양성 대조 + 부분 · 0칸 · 이력 따라 내려가는 문턱 · 구멍 이력 · 이력 부족 · 기준 0 · 창 0일(window_empty)
#   H 머리 판정(탐침 실물 경로) — 양성 + B6 미해석 · B6 < 목표일 · 지평선 불일치 · 시트 부재 · 깨진 파일 · 목표일 부재 ·
#     날짜축 없음 · 질의 시트 아님 · 시트 판독 오류
#   I 수급 통합 — 양성 · 부분 시트 거부(캐시 md5 불변) · 구멍 복구(F3) · 날짜축 없는 시트 거부 · 시트별 창 = 유형별 교체
#   C 컨센서스 통합(실 파서 consensus_parser.R 사본) — F3 뒤처진 지표 창 교체 · 부분 시트 거부 · 지표별 창 교체
#   U 유니버스 통합(실 파서 us_update_stream_parse.py 사본) — 양성 · Sector_Lv2 정체 거부 · B6 미해석 거부 · 시트별 창 교체
#   D F5 디스패치 — 미등록 · 부분 문자열 이름 · 정상 · 관문 거부 · 구판 기록 잔재
#   R rc 계약 — 실제 Rscript 자식 프로세스 종료 코드(거부 3 · 미등록 4 · 정상 0) + 도달 표지(죽은 프로세스 rc 와 구분)
#   M 돌연변이 — 소스 텍스트 치환(정확히 1줄 · 치환 성사 단정) 후 해당 판정이 red 여야 한다
#
# 실행: R_ENVIRON_USER=<빈 파일> Rscript 08_Tests/data/test_incremental_update_gates.R   (QW_UF_GATES_SRC 로 검사 대상 교체 가능)
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow); library(readxl) })
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
ROOT <- .root_resolve()
TEST_NAME <- "incremental_update_gates"
PASS <- 0L; FAIL <- 0L
ok  <- function(m) { PASS <<- PASS + 1L; cat("  OK  ", m, "\n") }
ng  <- function(m, why = "") { FAIL <<- FAIL + 1L; cat("  FAIL", m, if (nzchar(why)) paste0(" — ", why) else "", "\n") }
chk <- function(cond, m, why = "") if (isTRUE(cond)) ok(m) else ng(m, why)
preflight_fail <- function(why) {
  cat(sprintf("FAIL(preflight): %s — 계측이 살아 있지 않아 케이스 결과를 발행하지 않는다\n", why))
  cat(sprintf('{"test":"%s","pass":0,"fail":1,"preflight":"%s"}\n', TEST_NAME, gsub('"', "'", why)))
  quit(status = 1)
}
if (is.na(ROOT)) preflight_fail("프로젝트 루트 미발견(자기 위치 · CLAUDE_PROJECT_DIR · QM_ROOT 어디에도 표지 없음)")
SRC  <- Sys.getenv("QW_UF_GATES_SRC", file.path(ROOT, "02_Infrastructure/data/incremental_update_file.R"))
DATA_REAL <- file.path(ROOT, "02_Infrastructure/data")
RSCRIPT <- file.path(R.home("bin"), if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript")
md5 <- function(p) unname(tools::md5sum(p))
# R 4.5 seq.Date 는 정수 저장 Date 를 낸다 — identical() 은 저장형까지 비교하므로 날짜 비교는 값으로 한다
same_date <- function(a, b) length(a) == length(b) && isTRUE(all(as.numeric(a) == as.numeric(b)))
# 적재기 반환값 안전 접근 — 성공 시 TRUE(컨센서스) · NULL · 오류 조건이 올 수 있다. $ 를 바로 쓰면 원자 벡터에서 스크립트가 죽어
#   마지막 JSON 줄 없이 끝난다(1차 C6 — 독립 검증 재현). 판정은 FAIL 로 남기고 다음 사례로 간다.
rf  <- function(x, k) if (is.list(x) && !inherits(x, "condition")) x[[k]] else NULL
rsn <- function(x) { r <- rf(x, "reasons"); if (is.null(r)) character(0) else names(r) }
desc <- function(x) if (inherits(x, "condition")) conditionMessage(x) else if (is.list(x)) paste(rsn(x), collapse = ",") else
  paste(class(x), collapse = "/")
# 시나리오(이름 붙은 논리 벡터를 내는 함수)를 돌린다 — 시험 코드 · 대상 코드 어느 쪽이 죽어도 스크립트는 산다(사유 = attr "err").
safe_sc <- function(fn, lines) tryCatch(fn(lines), error = function(e) structure(logical(0), err = conditionMessage(e)))
sk <- function(s, k) isTRUE(unname(s[k]))   # 키가 없으면 NA → FALSE(미측정을 통과로 접지 않는다)

if (!requireNamespace("openxlsx", quietly = TRUE)) preflight_fail("openxlsx 없음 — 합성 xlsx 를 못 만든다")
src_lines <- sub("\r$", "", readLines(SRC, warn = FALSE, encoding = "UTF-8"))
cat(sprintf("[%s] 대상: %s (%d줄)\n", TEST_NAME, SRC, length(src_lines)))

TMP <- tempfile("uf_gates_"); dir.create(TMP)

#------------------------------------------------------------------------------
# 적재기 파일에서 필요한 정의만 격리 env 에 올린다(config · 캘린더 · 운영 경로 적재 없음)
#------------------------------------------------------------------------------
WANT_RE <- "^(\\.uf_|\\.UF_|incremental_|\\.consensus_append_increment$|detect_update_changes$|\\.get_last_processed$|\\.save_last_processed$)"
NEED <- c(".UF_PROBE_PY", ".uf_probe_book", ".uf_fill_check", ".uf_gate_header", ".uf_gate_fill", ".uf_refuse",
          "incremental_investor", "incremental_consensus", ".consensus_append_increment",
          "incremental_universe_support", "incremental_update_all", "detect_update_changes")
load_defs <- function(lines, env) {
  exprs <- parse(text = lines, keep.source = FALSE, encoding = "UTF-8")
  for (e in exprs)
    if (is.call(e) && identical(as.character(e[[1]]), "<-") && is.name(e[[2]]) && grepl(WANT_RE, as.character(e[[2]])))
      eval(e, envir = env)
  miss <- setdiff(NEED, ls(env, all.names = TRUE))
  if (length(miss)) stop("정의 미발견: ", paste(miss, collapse = ", "))
  invisible(env)
}
# 실 파서의 표(시트 → 지표 · 유니버스 시트 메타)를 그 파일에서 그대로 읽는다(사본 표를 따로 들고 있지 않는다)
eval_assignment <- function(path, name) {
  ex <- parse(text = readLines(path, warn = FALSE, encoding = "UTF-8"), keep.source = FALSE, encoding = "UTF-8")
  for (e in ex) if (is.call(e) && identical(as.character(e[[1]]), "<-") && identical(as.character(e[[2]]), name))
    return(eval(e[[3]], envir = new.env(parent = globalenv())))
  stop("정의 미발견: ", name, " in ", path)
}
CMETRICS <- eval_assignment(file.path(DATA_REAL, "consensus_parser.R"), "CONSENSUS_METRICS")
US_META  <- eval_assignment(file.path(DATA_REAL, "parse_universe_support.R"), "UNIVERSE_SUPPORT_SHEET_META")

new_env <- function(lines = src_lines, tag = "e") {
  env <- new.env(parent = globalenv())
  base <- file.path(TMP, paste0(tag, "_", sample.int(1e8, 1)))
  env$PROJECT_ROOT <- ROOT          # 파이썬 해석(.venv_qvest_ml 경로)에만 쓴다 — 쓰기 경로 아님
  env$CACHE_DIR  <- file.path(base, "cache"); env$UPDATE_DIR <- file.path(base, "upd"); env$DATA_DIR <- file.path(base, "data")
  for (d in c(env$CACHE_DIR, env$UPDATE_DIR, env$DATA_DIR, file.path(base, "cache", c("investor_stock", "consensus", "universe_support"))))
    dir.create(d, recursive = TRUE, showWarnings = FALSE)
  env$LAST_PROCESSED_FILE <- file.path(env$CACHE_DIR, "update_file_last_processed.rds")
  env$UNIVERSE_SUPPORT_CACHE <- file.path(env$CACHE_DIR, "universe_support")
  env$UNIVERSE_SUPPORT_SHEET_META <- US_META
  invisible(file.copy(file.path(DATA_REAL, c("consensus_parser.R", "us_update_stream_parse.py")), env$DATA_DIR))
  load_defs(lines, env)
  env
}
quiet <- function(expr) { out <- NULL; capture.output(out <- tryCatch(expr, error = function(e) e)); out }
# 사례 하나가 시험 코드 쪽에서 죽어도(합성 파일 판독 등) 스크립트를 끝내지 않는다 — 그 사례만 FAIL
case <- function(id, expr) tryCatch(expr, error = function(e) ng(id, paste("사례 실행 오류:", conditionMessage(e))))
read_pq <- function(p) tryCatch(as.data.table(read_parquet(p)), error = function(e) NULL)

#------------------------------------------------------------------------------
# 합성 수출본 — 실물 형식(11-06 사본 판독): 1 Refresh · 4 Frequency · 5 Period(From) · 6 Period(To) 'CPD-1TD [YYYYMMDD]'
#   · 8 Code · 9 Name · 10 Item Code · 11 Unit · 12 Base Date · 14 'D A T E' · 15~ 날짜 셀(엑셀 날짜) + 값 · DATA_Key
#------------------------------------------------------------------------------
set.seed(20261106)
TICK <- sprintf("A%06d", seq(10L, 120L, by = 10L))
bizdays <- function(from, to) { d <- seq(as.Date(from), as.Date(to), by = "day"); d[!format(d, "%u") %in% c("6", "7")] }
DAYS <- bizdays("2025-08-01", "2026-11-05")
TGT  <- max(DAYS)                      # 목표일(벤치 최신일) = 2026-11-05
WIN  <- tail(DAYS, 5L)                 # 받은 창 10-30 ~ 11-05
WIN12 <- tail(DAYS, 12L)               # 시트 하나만 더 긴 창(앞 7일은 기존 이력 안) — 시트별 창 사례
HIST <- head(DAYS, -5L)
EARLY7 <- head(WIN12, 7L)              # WIN12 \ WIN = 그 시트만 받은 앞 7일
B6_OK <- sprintf("CPD-1TD [%s]", format(TGT, "%Y%m%d"))

write_book <- function(path, sheets, freq = "D", data_key = TRUE) {
  wb <- openxlsx::createWorkbook()
  nt <- length(TICK)
  for (s in names(sheets)) {
    sp <- sheets[[s]]
    hdr <- matrix(NA_character_, nrow = 14L, ncol = 1L + nt)
    hdr[1, 1:2] <- c("     Refresh     ", "Last Update : 2026-11-06 07:32:50"); hdr[2, 1] <- "0"
    hdr[3, 1] <- "Time Series (Company)"; hdr[4, 1:2] <- c("Frequency", freq)
    hdr[5, 1:2] <- c("Period(From)", "20261031"); hdr[6, 1:2] <- c(sp$a6 %||% "Period(To)", sp$b6)
    hdr[8, ] <- c("Code", TICK); hdr[9, ] <- c("Name", paste0("N", seq_len(nt)))
    hdr[10, ] <- c("Item Code", rep("S000000", nt)); hdr[11, ] <- c("Unit", rep("Local", nt)); hdr[12, 1] <- "Base Date"
    hdr[14, ] <- c("D A T E", rep(s, nt))
    openxlsx::addWorksheet(wb, s)
    openxlsx::writeData(wb, s, as.data.frame(hdr, stringsAsFactors = FALSE), colNames = FALSE, startRow = 1)
    if (length(sp$dates))
      openxlsx::writeData(wb, s, data.frame(D = as.Date(sp$dates), sp$vals, stringsAsFactors = FALSE),
                          colNames = FALSE, startRow = 15)
  }
  if (data_key) {
    openxlsx::addWorksheet(wb, "DATA_Key")
    openxlsx::writeData(wb, "DATA_Key", data.frame(a = c("상폐종목포함 KSE+KOSDAQ 전체종목 리스트", TICK),
                                                   b = c("이름", paste0("N", seq_along(TICK)))), colNames = FALSE)
  }
  openxlsx::saveWorkbook(wb, path, overwrite = TRUE)
  path
}
num_vals <- function(nd, lo = 1, hi = 1000) matrix(round(runif(nd * length(TICK), lo, hi), 2), nrow = nd)

#==============================================================================
cat("\n[P] 사전 점검 — 탐침 카나리아\n")
E0 <- new_env(tag = "P")
py <- E0$.uf_python()
if (is.na(py)) preflight_fail("파이썬 실행 경로 미발견(QVEST_PY · .venv_qvest_ml)")
cx <- write_book(file.path(TMP, "canary.xlsx"), list(S1 = list(dates = WIN, vals = num_vals(5), b6 = B6_OK)))
cp <- E0$.uf_probe_book(cx)
canary_ok <- isTRUE(cp$ok) && same_date(cp$sheets[sheet == "S1"]$dates[[1]], WIN) &&
  same_date(cp$sheets[sheet == "S1"]$b6_date, TGT) && isTRUE(cp$sheets[sheet == "S1"]$query) &&
  identical(cp$sheets[sheet == "DATA_Key"]$n_dates, 0L)
if (!canary_ok) preflight_fail(sprintf("탐침 카나리아 실패(python=%s): %s", gsub("\\\\", "/", py),
  if (!isTRUE(cp$ok)) cp$err else paste(sprintf("%s:%d일:%s:%s:%s", cp$sheets$sheet, cp$sheets$n_dates, format(cp$sheets$horizon),
                                                 cp$sheets$b6, cp$sheets$query), collapse = " / ")))
ok(sprintf("P1 탐침 카나리아: 날짜축 5일 · B6 %s · 질의 시트 판별 · DATA_Key 날짜축 0 (python=%s)", format(TGT), basename(py)))
# openxlsx 저장본은 <dimension ref="A1"/> 로 선언한다(실물 퀀티 저장본 = 'A1:NTP164'). 탐침은 선언을 무시하지만(위 카나리아가
#   바로 그 'A1' 파일이다) 실 유니버스 파서(us_update_stream_parse.py · read_only)는 선언을 믿으므로, 그 책만 시트 XML 의
#   선언을 실제 셀 범위로 고쳐 쓴다(openpyxl 일반 모드 재저장은 openxlsx 의 없는 drawing 참조에서 죽는다 — 실측).
FIXPY <- file.path(TMP, "fix_dims.py")
writeLines(c(
  "import sys, re, os, zipfile",
  "p = sys.argv[1]; tmp = p + '.fix'",
  "def colnum(c):",
  "    n = 0",
  "    for ch in c: n = n * 26 + (ord(ch) - 64)",
  "    return n",
  "with zipfile.ZipFile(p) as zin, zipfile.ZipFile(tmp, 'w', zipfile.ZIP_DEFLATED) as zout:",
  "    for it in zin.infolist():",
  "        data = zin.read(it.filename)",
  "        if it.filename.startswith('xl/worksheets/sheet') and it.filename.endswith('.xml'):",
  "            s = data.decode('utf-8')",
  "            refs = re.findall(r'<c r=\"([A-Z]+)([0-9]+)\"', s)",
  "            if refs:",
  "                mc = max(refs, key=lambda x: colnum(x[0]))[0]; mr = max(int(x[1]) for x in refs)",
  "                s = re.sub(r'<dimension ref=\"[^\"]*\"/>', '<dimension ref=\"A1:%s%d\"/>' % (mc, mr), s, count=1)",
  "            data = s.encode('utf-8')",
  "        zout.writestr(it, data)",
  "os.replace(tmp, p)",
  "print('DIMS_FIXED')"), FIXPY)
fix_dims <- function(path) {
  o <- suppressWarnings(system2(py, c(shQuote(FIXPY), shQuote(path)), stdout = TRUE, stderr = TRUE))
  if (!any(grepl("DIMS_FIXED", o))) stop("fix_dims 실패: ", paste(tail(o, 2), collapse = " | "))
  path
}
# 시트 하나의 XML 을 중간에서 자른다(나머지 시트 · 통합문서 구조는 정상) → 탐침이 그 시트에서만 판독 오류를 낸다.
#   시트 이름 → 파일 = xl/workbook.xml(r:id) + xl/_rels/workbook.xml.rels(Target) — openxlsx 의 시트 순서에 기대지 않는다.
CORRUPTPY <- file.path(TMP, "corrupt_sheet.py")
writeLines(c(
  "import sys, os, zipfile, xml.etree.ElementTree as ET",
  "p, name = sys.argv[1], sys.argv[2]; tmp = p + '.bad'",
  "NS = {'m': 'http://schemas.openxmlformats.org/spreadsheetml/2006/main',",
  "      'r': 'http://schemas.openxmlformats.org/officeDocument/2006/relationships',",
  "      'p': 'http://schemas.openxmlformats.org/package/2006/relationships'}",
  "with zipfile.ZipFile(p) as z:",
  "    wbx = ET.fromstring(z.read('xl/workbook.xml')); rel = ET.fromstring(z.read('xl/_rels/workbook.xml.rels'))",
  "rid = [s.get('{%s}id' % NS['r']) for s in wbx.find('m:sheets', NS) if s.get('name') == name]",
  "tgt = [r.get('Target') for r in rel if r.get('Id') in rid]",
  "if len(tgt) != 1: print('CORRUPT_FAIL target=%r' % tgt); sys.exit(2)",
  "target = 'xl/' + tgt[0].lstrip('/').replace('xl/', '', 1)",
  "hit = 0",
  "with zipfile.ZipFile(p) as zin, zipfile.ZipFile(tmp, 'w', zipfile.ZIP_DEFLATED) as zout:",
  "    for it in zin.infolist():",
  "        data = zin.read(it.filename)",
  "        if it.filename == target:",
  "            data = data[: len(data) // 2]; hit += 1",
  "        zout.writestr(it, data)",
  "os.replace(tmp, p)",
  "print('CORRUPTED %d %s' % (hit, target))"), CORRUPTPY)
corrupt_sheet <- function(path, sheet) {
  o <- suppressWarnings(system2(py, c(shQuote(CORRUPTPY), shQuote(path), shQuote(sheet)), stdout = TRUE, stderr = TRUE))
  if (!any(grepl("^CORRUPTED 1 ", o))) stop("corrupt_sheet 실패: ", paste(tail(o, 2), collapse = " | "))
  path
}

#==============================================================================
cat("\n[G] 채움비 판정 순수 함수\n")
mk_hist <- function(days, fill = 12L, jitter = TRUE) {
  n <- rep(as.numeric(fill), length(days))
  if (jitter) n <- n - rbinom(length(days), 2L, 0.15)
  data.table(output = "x", Date = days, n = n)
}
newc <- function(n) data.table(output = "x", Date = WIN[seq_along(n)], n = n)
g1 <- E0$.uf_fill_check(mk_hist(HIST), newc(c(12, 12, 11)), list(x = WIN[1:3]))
chk(all(g1$why == "ok") && all(g1$thr == 0.5) && all(abs(g1$q - 1 / median(table(format(HIST, "%Y")))) < 1e-12),
    "G1 양성 대조: 정상 창 3일 통과 · 문턱 = 과반 상한 0.5 · 분위 = 1/(연간 축 날짜 수 중앙값)",
    paste(g1$why, g1$thr, collapse = ";"))
g2 <- E0$.uf_fill_check(mk_hist(HIST), newc(c(12, 4, 0)), list(x = WIN[1:3]))
chk(identical(g2$why, c("ok", "fill_low", "fill_low")) && g2$ratio[3] == 0,
    "G2 부분(4/12 ≈ 0.33) · 0칸 → fill_low", paste(g2$why, collapse = ","))
hd <- mk_hist(HIST); hd[seq(25L, .N, by = 20L), n := 3]           # 연 1회보다 자주 1/4 로 내려가는 항목
g4 <- E0$.uf_fill_check(hd, newc(4), list(x = WIN[1]))
chk(g4$thr < 0.5 && g4$thr <= 0.3 && g4$why == "ok",
    "G3 문턱이 이력을 따라 내려간다(이력에 1/4 날이 연 1회보다 잦음 → 문턱 ≈0.26 · 4/12 통과 · 영구 거부 방지)",
    sprintf("thr=%.3f why=%s", g4$thr, g4$why))
hh <- mk_hist(HIST); hh[Date %in% tail(HIST, 9L), n := 0]          # 창 직전 9일 구멍(실측 10-20~10-30 과 같은 길이)
g5 <- E0$.uf_fill_check(hh, newc(12), list(x = WIN[1]))
chk(g5$why == "ok" && g5$ref >= 10, "G4 비교 창 안 구멍 9일 — 중앙값 기준 불변(붕괴점) → 정상 날 통과",
    sprintf("ref=%s why=%s", g5$ref, g5$why))
g6 <- E0$.uf_fill_check(mk_hist(head(HIST, 15L)), newc(12), list(x = WIN[1]))
chk(g6$why == "history_short", "G5 이력 15일 → history_short(문턱 · 기준 미산출은 통과로 접지 않는다)", g6$why)
hz <- mk_hist(HIST); hz[Date %in% tail(HIST, 25L), n := 0]
g7 <- E0$.uf_fill_check(hz, newc(0), list(x = WIN[1]))
chk(g7$why == "ref_zero", "G6 직전 비교 창 전부 0 · 그날도 0 → ref_zero", g7$why)
gg <- E0$.uf_gate_fill(list(ok = TRUE, reasons = character(0)), g1, outputs_missing = "sue")
chk(!gg$ok && identical(names(gg$reasons), "outputs_missing"), "G7 파싱 산출 누락 지표 → outputs_missing 거부",
    paste(names(gg$reasons), collapse = ","))
sc_window_empty <- function(lines) {
  e <- new_env(lines, "G8")
  pos <- e$.uf_gate_fill(list(ok = TRUE, reasons = character(0)), g1, windows = list(x = WIN[1:3]))
  neg <- e$.uf_gate_fill(list(ok = TRUE, reasons = character(0)), g1, windows = list(x = WIN[1:3], y = as.Date(character(0))))
  one <- e$.uf_gate_fill(list(ok = TRUE, reasons = character(0)), g1, windows = list(x = WIN[1], y = WIN[1]))   # 11-06 원 세션: 1일 창 경계
  c(G_window_all_present_ok = isTRUE(pos$ok) && !length(pos$reasons),
    G_window_one_day_ok = isTRUE(one$ok) && !length(one$reasons),
    G_window_empty = !isTRUE(neg$ok) && identical(names(neg$reasons), "window_empty") && grepl("y", neg$reasons[["window_empty"]], fixed = TRUE))
}
s_we <- safe_sc(sc_window_empty, src_lines)
chk(sk(s_we, "G_window_all_present_ok"), "G8a 양성 대조: 출력 모두 받은 창 있음 → 관문 ② 통과(사유 0)", attr(s_we, "err") %||% "")
chk(sk(s_we, "G_window_empty"), "G8b 받은 창 0일인 출력(y) → window_empty 거부(교체 단계 앞 두 번째 방어선)", attr(s_we, "err") %||% "")
chk(sk(s_we, "G_window_one_day_ok"), "G8c 받은 창 1일인 출력들(정상 밤 증분) → 통과 — 경계 `== 0L` 고정(`<= 1L` 로 바뀌면 매일 밤 rc 3 정지 · 2차 검증 MX1)", attr(s_we, "err") %||% "")

#==============================================================================
cat("\n[H] 머리 판정 — 탐침 실물 경로(합성 수출본)\n")
INV_SHEETS <- c("외인", "기관", "개인", "기타법인")
inv_book <- function(path, mod = function(s, sp) sp) {
  sh <- setNames(lapply(INV_SHEETS, function(s) mod(s, list(dates = WIN, vals = num_vals(5, 1e3, 1e8), b6 = B6_OK))), INV_SHEETS)
  write_book(path, sh)
}
hgate <- function(path, target = TGT, env = E0) env$.uf_gate_header("Investor_Act", env$.uf_probe_book(path), INV_SHEETS, target)
h1 <- hgate(inv_book(file.path(TMP, "h1.xlsx")))
chk(isTRUE(h1$ok) && same_date(h1$horizon, TGT), "H1 양성 대조: 4시트 · 지평선 일치 · B6 = 목표일 → 통과",
    paste(names(h1$reasons), collapse = ","))
h2 <- hgate(inv_book(file.path(TMP, "h2.xlsx"), function(s, sp) { if (s == "개인") sp$b6 <- "CPD-1TD"; sp }))
chk(!h2$ok && identical(names(h2$reasons), "b6_unresolved"), "H2 한 시트 B6 = 'CPD-1TD'(괄호 없음 · 실패 저장본) → b6_unresolved",
    paste(names(h2$reasons), collapse = ","))
h3 <- hgate(inv_book(file.path(TMP, "h3.xlsx"), function(s, sp) { if (s == "외인") sp$b6 <- sprintf("CPD-1TD [%s]", format(TGT - 1, "%Y%m%d")); sp }))
chk(!h3$ok && identical(names(h3$reasons), "b6_behind"), "H3 B6 괄호 < 목표일 → b6_behind", paste(names(h3$reasons), collapse = ","))
h4 <- hgate(inv_book(file.path(TMP, "h4.xlsx"), function(s, sp) { if (s == "기타법인") { sp$dates <- head(WIN, -1L); sp$vals <- sp$vals[-5, ] }; sp }))
chk(!h4$ok && "horizon_mismatch" %in% names(h4$reasons) && is.na(h4$horizon), "H4 한 시트 하루 뒤짐 → horizon_mismatch",
    paste(names(h4$reasons), collapse = ","))
h5p <- file.path(TMP, "h5.xlsx")
invisible(write_book(h5p, setNames(lapply(INV_SHEETS[1:3], function(s) list(dates = WIN, vals = num_vals(5), b6 = B6_OK)), INV_SHEETS[1:3])))
h5 <- hgate(h5p)
chk(!h5$ok && identical(names(h5$reasons), "sheet_missing"), "H5 질의 시트 부재(기타법인) → sheet_missing", paste(names(h5$reasons), collapse = ","))
h6p <- file.path(TMP, "h6.xlsx"); writeBin(as.raw(sample(0:255, 4096, TRUE)), h6p)
h6 <- hgate(h6p)
chk(!h6$ok && identical(names(h6$reasons), "probe_failed"), "H6 깨진 파일 → probe_failed(미측정을 통과로 접지 않는다)",
    paste(names(h6$reasons), collapse = ","))
h7 <- hgate(file.path(TMP, "h1.xlsx"), target = as.Date(NA))
chk(!h7$ok && identical(names(h7$reasons), "target_unmeasured"), "H7 목표일(벤치) 미측정 → target_unmeasured",
    paste(names(h7$reasons), collapse = ","))
bp <- file.path(TMP, "bench.parquet"); write_parquet(data.table(Date = DAYS, BM_Close = 1), bp)
chk(same_date(E0$.uf_target_date(bp), TGT) && is.na(E0$.uf_target_date(file.path(TMP, "none.parquet"))),
    "H8 목표일 = 벤치 최신일 · 벤치 부재 = NA")
# H9~H11 — 1차 시험이 고정하지 않던 사유 3종(지운 사본이 통과했다). 합성 책은 한 번 만들고 돌연변이 사본도 같은 책을 잰다.
H9P  <- inv_book(file.path(TMP, "h9.xlsx"),  function(s, sp) { if (s == "개인") { sp$dates <- as.Date(character(0)); sp$vals <- NULL }; sp })
H10P <- inv_book(file.path(TMP, "h10.xlsx"), function(s, sp) { if (s == "개인") sp$a6 <- "Base Date"; sp })
H11P <- corrupt_sheet(inv_book(file.path(TMP, "h11.xlsx")), "개인")
sc_header_cases <- function(lines) {
  e <- new_env(lines, "H9")
  r9 <- hgate(H9P, env = e); r10 <- hgate(H10P, env = e); r11 <- hgate(H11P, env = e)
  c(H_axis_missing = !isTRUE(r9$ok) && identical(names(r9$reasons), "date_axis_missing") &&
      grepl("개인", r9$reasons[["date_axis_missing"]], fixed = TRUE) && same_date(r9$horizon, TGT),
    H_not_query = !isTRUE(r10$ok) && identical(names(r10$reasons), "not_query_sheet") &&
      grepl("개인", r10$reasons[["not_query_sheet"]], fixed = TRUE),
    H_read_error = !isTRUE(r11$ok) && "sheet_read_error" %in% names(r11$reasons) &&
      grepl("개인", r11$reasons[["sheet_read_error"]], fixed = TRUE) && isTRUE(r11$sheets[sheet == "외인"]$n_dates == 5L))
}
s_h <- safe_sc(sc_header_cases, src_lines)
chk(sk(s_h, "H_axis_missing"), "H9 개인 시트 'D A T E' 아래 날짜 0개(나머지 정상 · 지평선 일치) → date_axis_missing 단독", attr(s_h, "err") %||% "")
chk(sk(s_h, "H_not_query"), "H10 개인 시트 A6 = 'Base Date'(질의 시트 아님 · B6 괄호는 정상) → not_query_sheet 단독", attr(s_h, "err") %||% "")
chk(sk(s_h, "H_read_error"), "H11 개인 시트 XML 손상(나머지 3시트 정상 판독) → sheet_read_error(그 시트 이름 명시)", attr(s_h, "err") %||% "")

#==============================================================================
cat("\n[I] 수급 통합 (incremental_investor)\n")
TYPES <- c("외인" = "Foreign", "기관" = "Institutional", "개인" = "Individual", "기타법인" = "OtherCorp")
mk_investor <- function(e, variant = "ok") {
  days <- if (variant == "restore") DAYS else HIST
  g <- CJ(Date = days, Ticker = TICK, InvestorType = unname(TYPES))
  g[, NetBuy := round(rnorm(.N, 0, 1e8)) + 0.5]
  g <- g[runif(.N) > 0.03]
  if (variant == "restore") g <- g[!(InvestorType == "Individual" & Date %in% WIN[1:3])]   # 한 유형만 빈 날(실측 10-20~10-30 형)
  write_parquet(g, file.path(e$CACHE_DIR, "investor_stock", "investor_all.parquet"))
  sh <- setNames(lapply(names(TYPES), function(s) {
    d <- if (variant == "per_sheet" && s == "개인") WIN12 else if (variant == "noaxis" && s == "개인") as.Date(character(0)) else WIN
    v <- matrix(round(runif(length(d) * length(TICK), 1e6, 9e8)) + 0.5, nrow = length(d))
    if (variant == "partial" && s == "개인") v[] <- NA
    list(dates = d, vals = if (length(d)) v else NULL, b6 = B6_OK)
  }), names(TYPES))
  write_book(file.path(e$UPDATE_DIR, "Investor_Act_update.xlsx"), sh)
  list(old = g, sheets = sh)
}
read_rec <- function(e, book) tryCatch(jsonlite::fromJSON(file.path(e$CACHE_DIR, sprintf("update_file_gate_%s.json", book))),
                                       error = function(x) NULL)
inv_all <- function(e) file.path(e$CACHE_DIR, "investor_stock", "investor_all.parquet")
case("I1", {
  ei <- new_env(tag = "I1"); fi <- mk_investor(ei, "ok")
  ri <- quiet(ei$incremental_investor(target = TGT))
  ia <- read_pq(inv_all(ei))
  chk(isFALSE(rf(ri, "refused")) && !is.null(ia) && ia[Date %in% WIN, .N] == length(WIN) * length(TICK) * 4L &&
        identical(read_rec(ei, "investor_act")$status, "loaded") &&
        file.exists(file.path(ei$CACHE_DIR, "investor_stock", "investor_wide.parquet")),
      "I1 양성 대조: 정상 책 적재(받은 창 5일 × 12종목 × 4유형) · 판정 기록 loaded · 파생 파일 재생성",
      if (is.null(ia)) desc(ri) else sprintf("%s rows_in_win=%d", desc(ri), ia[Date %in% WIN, .N]))
})
sc_investor_partial <- function(lines) {
  e <- new_env(lines, "I2"); mk_investor(e, "partial")
  p <- inv_all(e); m0 <- md5(p)
  r <- quiet(e$incremental_investor(target = TGT))
  c(I_partial_refused = isTRUE(rf(r, "refused")) && "fill_low" %in% rsn(r),
    I_partial_cache_untouched = identical(md5(p), m0) &&
      !file.exists(file.path(e$CACHE_DIR, "investor_stock", "investor_wide.parquet")),
    I_partial_recorded = identical(read_rec(e, "investor_act")$status, "refused"))
}
s_ip <- safe_sc(sc_investor_partial, src_lines)
chk(sk(s_ip, "I_partial_refused"), "I2 개인 시트 창 전체 빈칸(실측 10-20~10-30 형) → fill_low 거부", attr(s_ip, "err") %||% "")
chk(sk(s_ip, "I_partial_cache_untouched"), "I3 거부 시 investor_all md5 불변 · 파생 파일 미생성(적재 0)", attr(s_ip, "err") %||% "")
chk(sk(s_ip, "I_partial_recorded"), "I4 판정 기록 refused", attr(s_ip, "err") %||% "")
case("I5", {
  er <- new_env(tag = "I5"); fr <- mk_investor(er, "restore")
  rr <- quiet(er$incremental_investor(target = TGT))
  ra <- read_pq(inv_all(er))
  chk(isFALSE(rf(rr, "refused")) && !is.null(ra) && ra[InvestorType == "Individual" & Date %in% WIN[1:3], .N] == 3L * length(TICK),
      "I5 F3 구멍 복구: 패널 max 안쪽의 개인 빈 날(창 첫 3일)이 다시 받은 창으로 채워진다(구판 'Date > max' 는 버렸다)",
      if (is.null(ra)) desc(rr) else sprintf("%s ind_rows=%d", desc(rr), ra[InvestorType == "Individual" & Date %in% WIN[1:3], .N]))
  chk(!is.null(ra) && isTRUE(all.equal(ra[InvestorType == "Foreign" & Date == WIN[1] & Ticker == TICK[1]]$NetBuy, fr$sheets[["외인"]]$vals[1, 1])) &&
        ra[Date %in% HIST, .N] == fr$old[Date %in% HIST, .N],
      "I6 창 날짜의 기존 값은 새 값으로 교체 · 창 밖 날짜는 그대로")
  ## 11-06 원 세션(2차 검증 MX8): 유형별 교체의 완전성 — 창 날짜 행 = 창 일수 × 종목 × 4유형 · (Date, Ticker, InvestorType) 중복 0
  chk(!is.null(ra) && ra[Date %in% WIN, .N] == length(WIN) * length(TICK) * 4L && !anyDuplicated(ra[, .(Date, Ticker, InvestorType)]),
      "I5b 창 날짜는 4유형 모두 정확히 한 벌(창 × 종목 × 4) · (Date, Ticker, InvestorType) 중복 0 — win_key 에서 유형이 빠지면 중복이 남는다",
      if (is.null(ra)) "" else sprintf("win_rows=%d dup=%d", ra[Date %in% WIN, .N], sum(duplicated(ra[, .(Date, Ticker, InvestorType)]))))
})
# I7 — 날짜축 없는 시트(개인)가 든 책: 거부 · 캐시 무접촉(구 VD 돌연변이 = 이 책을 받아 개인 창 행을 지웠다 60→0)
sc_investor_noaxis <- function(lines) {
  e <- new_env(lines, "I7"); mk_investor(e, "noaxis")
  p <- inv_all(e); m0 <- md5(p)
  r <- quiet(e$incremental_investor(target = TGT))
  c(I_noaxis_refused = isTRUE(rf(r, "refused")) && "date_axis_missing" %in% rsn(r),
    I_noaxis_untouched = identical(md5(p), m0) && !file.exists(file.path(e$CACHE_DIR, "investor_stock", "investor_wide.parquet")))
}
s_ina <- safe_sc(sc_investor_noaxis, src_lines)
chk(sk(s_ina, "I_noaxis_refused"), "I7a 개인 시트 날짜축 없음 → date_axis_missing 거부(유형 하나라도 받은 창이 없으면 책 전체 0)", attr(s_ina, "err") %||% "")
chk(sk(s_ina, "I_noaxis_untouched"), "I7b 그 거부에서 investor_all md5 불변 · 파생 파일 미생성", attr(s_ina, "err") %||% "")
# I8 — 시트별 창이 다르다(개인 12일 · 나머지 5일 · 같은 끝일): 유형마다 그 유형 창만 교체(1차 판 = 합집합 교체로 3유형 앞 7일 소실)
sc_investor_per_sheet <- function(lines) {
  e <- new_env(lines, "I8"); fx <- mk_investor(e, "per_sheet")
  r <- quiet(e$incremental_investor(target = TGT))
  a <- read_pq(inv_all(e))
  if (is.null(a)) return(c(I_per_sheet_loaded = FALSE, I_per_sheet_others_kept = FALSE, I_per_sheet_long_replaced = FALSE))
  key <- c("Date", "Ticker", "InvestorType")
  oth_old <- fx$old[InvestorType != "Individual" & Date %in% EARLY7][order(Date, Ticker, InvestorType)]
  oth_new <- a[InvestorType != "Individual" & Date %in% EARLY7][order(Date, Ticker, InvestorType)]
  ind <- a[InvestorType == "Individual" & Date %in% WIN12]
  newv <- fx$sheets[["개인"]]$vals                      # 12일 × 12종목(전부 0 아님 → 전부 저장)
  exp_v <- data.table(Date = rep(WIN12, times = length(TICK)), Ticker = rep(TICK, each = length(WIN12)),
                      NetBuy = as.vector(newv))
  got <- merge(exp_v, ind[, .(Date, Ticker, NetBuy)], by = c("Date", "Ticker"), all = TRUE)
  c(I_per_sheet_loaded = isFALSE(rf(r, "refused")) && identical(read_rec(e, "investor_act")$status, "loaded"),
    I_per_sheet_others_kept = nrow(oth_old) > 0L && nrow(oth_new) == nrow(oth_old) &&
      isTRUE(all.equal(oth_new[, ..key], oth_old[, ..key], check.attributes = FALSE)) &&
      isTRUE(all.equal(oth_new$NetBuy, oth_old$NetBuy)),
    I_per_sheet_long_replaced = nrow(ind) == length(WIN12) * length(TICK) && nrow(got) == nrow(exp_v) &&
      isTRUE(all.equal(got$NetBuy.x, got$NetBuy.y)))
}
s_ips <- safe_sc(sc_investor_per_sheet, src_lines)
chk(sk(s_ips, "I_per_sheet_loaded"), "I8a 양성 대조: 개인 12일 · 나머지 5일(같은 끝일) → 적재 · 기록 loaded", attr(s_ips, "err") %||% "")
chk(sk(s_ips, "I_per_sheet_others_kept"), "I8b 외국인 · 기관 · 기타법인의 앞 7일(개인만 받은 날) 기존 행은 그대로(합집합 교체 소실 없음)", attr(s_ips, "err") %||% "")
chk(sk(s_ips, "I_per_sheet_long_replaced"), "I8c 개인은 자기 창 12일 전부 새 값으로 교체(12일 × 12종목)", attr(s_ips, "err") %||% "")

#==============================================================================
cat("\n[C] 컨센서스 통합 (incremental_consensus · 실 파서 사본)\n")
mk_consensus <- function(e, partial_sheet = NULL, long_sheet = NULL) {
  cd <- file.path(e$CACHE_DIR, "consensus"); old <- list()
  for (s in names(CMETRICS)) {
    m <- CMETRICS[[s]]
    days <- if (m == "eps_1y") c(HIST, WIN[1:2]) else if (m == "coverage") head(HIST, -2L) else HIST   # coverage = 뒤처진 지표
    g <- CJ(Date = days, Ticker = TICK)[runif(.N) > 0.03]
    g[, (m) := round(runif(.N, 1, 1000), 2)]
    write_parquet(g, file.path(cd, paste0(m, ".parquet"))); old[[m]] <- g
  }
  write_parquet(data.table(Ticker = TICK, Name = paste0("OLD", seq_along(TICK))), file.path(cd, "ticker_map.parquet"))
  sh <- setNames(lapply(names(CMETRICS), function(s) {
    d <- if (identical(s, long_sheet)) WIN12 else WIN
    v <- num_vals(length(d), 2000, 3000)                           # 기존 값(1~1000)과 겹치지 않는 범위 → 교체 여부가 값으로 보인다
    if (identical(s, partial_sheet)) v[length(d), -(1:3)] <- NA    # 마지막 날 3종목만
    list(dates = d, vals = v, b6 = B6_OK)
  }), names(CMETRICS))
  write_book(file.path(e$UPDATE_DIR, "Consensus_update.xlsx"), sh)
  list(old = old, sheets = sh)
}
run_consensus <- function(e) {
  assign("PROJECT_ROOT", ROOT, envir = globalenv()); assign("CACHE_DIR", e$CACHE_DIR, envir = globalenv())
  quiet(e$incremental_consensus(target = TGT))
}
sc_consensus_f3 <- function(lines) {
  e <- new_env(lines, "C1"); fx <- mk_consensus(e)
  r <- run_consensus(e)
  cd <- file.path(e$CACHE_DIR, "consensus")
  cov <- read_pq(file.path(cd, "coverage.parquet")); eps <- read_pq(file.path(cd, "eps_1y.parquet")); bps <- read_pq(file.path(cd, "bps_1y.parquet"))
  if (is.null(cov) || is.null(eps) || is.null(bps))
    return(c(C_loaded = FALSE, C_f3_lagging_window_filled = FALSE, C_f3_overlap_replaced = FALSE, C_outside_window_untouched = FALSE,
             C_tmp_cleaned = FALSE))
  c(C_loaded = isTRUE(r) && identical(read_rec(e, "consensus")$status, "loaded"),
    C_f3_lagging_window_filled = all(WIN %in% cov$Date) && !any(tail(HIST, 2L) %in% cov$Date),
    C_f3_overlap_replaced = eps[Date %in% WIN[1:2], all(eps_1y >= 2000)] && eps[Date %in% WIN[1:2], .N] == 2L * length(TICK),
    C_outside_window_untouched = isTRUE(all.equal(bps[Date %in% HIST][order(Date, Ticker)], fx$old$bps_1y[order(Date, Ticker)],
                                                  check.attributes = FALSE)),
    C_tmp_cleaned = !dir.exists(file.path(e$CACHE_DIR, "consensus_tmp")))
}
s_c <- safe_sc(sc_consensus_f3, src_lines)
chk(sk(s_c, "C_loaded"), "C1 양성 대조: 12시트 정상 → 적재 · 판정 기록 loaded", attr(s_c, "err") %||% "")
chk(sk(s_c, "C_f3_lagging_window_filled"), "C2 F3: 뒤처진 지표(coverage)가 받은 창 5일을 전부 받는다(eps_1y max 이후 3일만이 아니다) · 창 밖 구멍 2일은 그대로", attr(s_c, "err") %||% "")
chk(sk(s_c, "C_f3_overlap_replaced"), "C3 F3: 창과 겹친 기존 날(eps_1y 창 첫 2일)은 새 값으로 교체", attr(s_c, "err") %||% "")
chk(sk(s_c, "C_outside_window_untouched"), "C4 창 밖 날짜(bps_1y 이력)는 한 칸도 안 바뀐다", attr(s_c, "err") %||% "")
chk(sk(s_c, "C_tmp_cleaned"), "C5 consensus_tmp 정리", attr(s_c, "err") %||% "")
case("C6", {
  ec <- new_env(tag = "C6"); invisible(mk_consensus(ec, partial_sheet = "ESBR(지배)"))
  cfiles <- list.files(file.path(ec$CACHE_DIR, "consensus"), full.names = TRUE); m0 <- md5(cfiles)
  rc6 <- run_consensus(ec)
  # ★1차 판은 rc6$refused 를 바로 읽어, 거부를 멈춘 사본(성공 = TRUE)에서 스크립트가 죽었다 — rf()/rsn() 로 FAIL 기록
  chk(isTRUE(rf(rc6, "refused")) && "fill_low" %in% rsn(rc6) && identical(md5(cfiles), m0) &&
        identical(read_rec(ec, "consensus")$status, "refused") && !dir.exists(file.path(ec$CACHE_DIR, "consensus_tmp")),
      "C6 한 시트(ESBR) 마지막 날 3/12 → fill_low 거부 · 13개 캐시 파일 md5 불변 · 기록 refused · tmp 정리", desc(rc6))
})
case("C7", {
  el <- new_env(tag = "C7")
  td <- file.path(TMP, "c7_tmp"); cd7 <- file.path(TMP, "c7_cache"); dir.create(td); dir.create(cd7)
  write_parquet(data.table(Date = as.Date(c("2026-08-27", "2026-08-28")), Ticker = "A000020", Value = c(1, 2)), file.path(cd7, "m.parquet"))
  write_parquet(data.table(Date = as.Date(c("2026-08-28", "2026-08-31")), Ticker = "A000020", Value = c(9, 3)), file.path(td, "m.parquet"))
  o7 <- capture.output(el$.consensus_append_increment(td, cd7, as.Date("2026-08-28")))
  m7 <- read_pq(file.path(cd7, "m.parquet"))
  chk(any(grepl("base_max", o7)) && !is.null(m7) && identical(m7[Date == as.Date("2026-08-28")]$Value, 9) && nrow(m7) == 3L,
      "C7 구 위치 인자(base_max 날짜 1개)는 경고 후 받은 창 교체로 처리(08-28 = 새 값 9)")
})
# C8 — 지표별 창이 다르다(BPS_1Y 12일 · 나머지 5일): 지표마다 그 지표 창만 교체(합집합 교체 회귀 방지 — 컨센서스는 이미 지표별)
sc_consensus_per_metric <- function(lines) {
  e <- new_env(lines, "C8"); fx <- mk_consensus(e, long_sheet = "BPS_1Y")
  r <- run_consensus(e)
  cd <- file.path(e$CACHE_DIR, "consensus")
  eps <- read_pq(file.path(cd, "eps_1y.parquet")); dps <- read_pq(file.path(cd, "dps_1y.parquet")); bps <- read_pq(file.path(cd, "bps_1y.parquet"))
  if (is.null(eps) || is.null(dps) || is.null(bps)) return(c(C_per_metric_loaded = FALSE, C_per_metric_others_kept = FALSE, C_per_metric_long_replaced = FALSE))
  kept <- function(now, m) { a <- now[Date %in% EARLY7][order(Date, Ticker)]; b <- fx$old[[m]][Date %in% EARLY7][order(Date, Ticker)]
                             nrow(b) > 0L && isTRUE(all.equal(a, b, check.attributes = FALSE)) }
  c(C_per_metric_loaded = isTRUE(r) && identical(read_rec(e, "consensus")$status, "loaded"),
    C_per_metric_others_kept = kept(dps, "dps_1y") && kept(eps, "eps_1y"),
    C_per_metric_long_replaced = bps[Date %in% WIN12, .N] == length(WIN12) * length(TICK) && bps[Date %in% WIN12, all(bps_1y >= 2000)])
}
s_cm <- safe_sc(sc_consensus_per_metric, src_lines)
chk(sk(s_cm, "C_per_metric_loaded"), "C8a 양성 대조: BPS_1Y 시트만 12일 · 나머지 5일(같은 끝일) → 적재", attr(s_cm, "err") %||% "")
chk(sk(s_cm, "C_per_metric_others_kept"), "C8b 다른 지표(dps_1y · eps_1y)의 앞 7일 기존 행은 그대로", attr(s_cm, "err") %||% "")
chk(sk(s_cm, "C_per_metric_long_replaced"), "C8c bps_1y 는 자기 창 12일 전부 새 값으로 교체", attr(s_cm, "err") %||% "")

#==============================================================================
cat("\n[U] 유니버스 통합 (incremental_universe_support · 실 파서 사본)\n")
UHIST <- local({ d <- bizdays("2021-10-01", "2026-09-30"); d[c(diff(as.integer(format(d, "%m"))) != 0L, TRUE)] })
UWIN  <- as.Date(c("2026-10-30", "2026-11-05"))
UEXTRA <- max(UHIST)                   # 2026-09-30 — 시트 하나만 더 받은 앞 스냅샷(시트별 창 사례)
SECT  <- c("에너지", "소재", "금융")
mk_universe <- function(e, stale_lv2 = FALSE, b6 = B6_OK, long_sheet = NULL) {
  ud <- e$UNIVERSE_SUPPORT_CACHE; old <- list()
  for (s in names(US_META)) {
    mt <- US_META[[s]]; vc <- mt$value_col
    g <- CJ(Date = UHIST, Ticker = TICK)
    if (mt$value_type == "numeric") g[, (vc) := as.numeric(sample(0:1, .N, TRUE))] else g[, (vc) := sample(SECT, .N, TRUE)]
    write_parquet(g, file.path(ud, sprintf("us_%s.parquet", mt$cache_name))); old[[mt$cache_name]] <- g
  }
  sh <- setNames(lapply(names(US_META), function(s) {
    mt <- US_META[[s]]
    d <- if (stale_lv2 && s == "Sector_Lv2") as.Date("2026-10-19") else if (identical(s, long_sheet)) c(UEXTRA, UWIN) else UWIN
    # 긴 창 시트의 새 값은 기존 값과 겹치지 않게(숫자 = 2 · 문자 = '신규') → 교체 여부가 값으로 보인다
    v <- if (mt$value_type == "numeric") matrix(if (identical(s, long_sheet)) 2 else as.numeric(sample(0:1, length(d) * length(TICK), TRUE)),
                                                nrow = length(d), ncol = length(TICK)) else
      matrix(if (identical(s, long_sheet)) "신규" else sample(SECT, length(d) * length(TICK), TRUE), nrow = length(d), ncol = length(TICK))
    list(dates = d, vals = v, b6 = b6)
  }), names(US_META))
  fix_dims(write_book(file.path(e$UPDATE_DIR, "Universe_Support_update.xlsx"), sh, freq = "M"))
  invisible(list(old = old))
}
us_files <- function(e) list.files(e$UNIVERSE_SUPPORT_CACHE, pattern = "^us_.*\\.parquet$", full.names = TRUE)
case("U1", {
  eu <- new_env(tag = "U1"); invisible(mk_universe(eu))
  ru <- quiet(eu$incremental_universe_support(cache_dir = eu$UNIVERSE_SUPPORT_CACHE, target = TGT))
  k2 <- read_pq(file.path(eu$UNIVERSE_SUPPORT_CACHE, "us_k200.parquet"))
  l2 <- read_pq(file.path(eu$UNIVERSE_SUPPORT_CACHE, "us_sector_lv2.parquet"))
  chk(isFALSE(rf(ru, "refused")) && identical(rf(ru, "n_merged"), length(US_META)) && !is.null(k2) && !is.null(l2) &&
        k2[Date %in% UWIN, .N] == 2L * length(TICK) && l2[Date %in% UWIN, .N] == 2L * length(TICK) &&
        identical(read_rec(eu, "universe_support")$status, "loaded"),
      "U1 양성 대조: 8시트 정상(월간 스냅샷 축) → 8/8 적재 · 기록 loaded", desc(ru))
})
case("U2", {
  eu2 <- new_env(tag = "U2"); invisible(mk_universe(eu2, stale_lv2 = TRUE)); m0 <- md5(us_files(eu2))
  ru2 <- quiet(eu2$incremental_universe_support(cache_dir = eu2$UNIVERSE_SUPPORT_CACHE, target = TGT))
  chk(isTRUE(rf(ru2, "refused")) && "horizon_mismatch" %in% rsn(ru2) && identical(md5(us_files(eu2)), m0),
      "U2 Sector_Lv2 만 10-19 정체(실측 11-06 저장본 형) → horizon_mismatch 거부 · 8개 패널 md5 불변(책 단위)", desc(ru2))
})
case("U3", {
  eu3 <- new_env(tag = "U3"); invisible(mk_universe(eu3, b6 = "CPD-1TD")); m0 <- md5(us_files(eu3))
  ru3 <- quiet(eu3$incremental_universe_support(cache_dir = eu3$UNIVERSE_SUPPORT_CACHE, target = TGT))
  chk(isTRUE(rf(ru3, "refused")) && "b6_unresolved" %in% rsn(ru3) && identical(md5(us_files(eu3)), m0),
      "U3 8시트 모두 B6 미해석(드라이버 실패 저장본) → b6_unresolved 거부 · md5 불변", desc(ru3))
})
# U4 — 시트별 창이 다르다(Sector_Lv1 = 09-30 · 10-30 · 11-05 · 나머지 = 10-30 · 11-05): 시트마다 그 시트 창만 교체
sc_universe_per_sheet <- function(lines) {
  e <- new_env(lines, "U4"); fx <- mk_universe(e, long_sheet = "Sector_Lv1")
  r <- quiet(e$incremental_universe_support(cache_dir = e$UNIVERSE_SUPPORT_CACHE, target = TGT))
  l1 <- read_pq(file.path(e$UNIVERSE_SUPPORT_CACHE, "us_sector_lv1.parquet"))
  k2 <- read_pq(file.path(e$UNIVERSE_SUPPORT_CACHE, "us_k200.parquet"))
  l2 <- read_pq(file.path(e$UNIVERSE_SUPPORT_CACHE, "us_sector_lv2.parquet"))
  if (is.null(l1) || is.null(k2) || is.null(l2)) return(c(U_per_sheet_loaded = FALSE, U_per_sheet_others_kept = FALSE, U_per_sheet_long_replaced = FALSE))
  kept <- function(now, nm) { a <- now[Date == UEXTRA][order(Ticker)]; b <- fx$old[[nm]][Date == UEXTRA][order(Ticker)]
                              nrow(b) == length(TICK) && isTRUE(all.equal(a, b, check.attributes = FALSE)) }
  c(U_per_sheet_loaded = isFALSE(rf(r, "refused")) && identical(rf(r, "n_merged"), length(US_META)),
    U_per_sheet_others_kept = kept(k2, "k200") && kept(l2, "sector_lv2"),
    U_per_sheet_long_replaced = l1[Date == UEXTRA, .N] == length(TICK) && l1[Date == UEXTRA, all(Sector_Lv1 == "신규")])
}
s_us <- safe_sc(sc_universe_per_sheet, src_lines)
chk(sk(s_us, "U_per_sheet_loaded"), "U4a 양성 대조: Sector_Lv1 만 09-30 스냅샷까지(같은 끝일) → 8/8 적재", attr(s_us, "err") %||% "")
chk(sk(s_us, "U_per_sheet_others_kept"), "U4b 다른 시트(k200 · sector_lv2)의 09-30 기존 행은 그대로", attr(s_us, "err") %||% "")
chk(sk(s_us, "U_per_sheet_long_replaced"), "U4c sector_lv1 은 자기 창의 09-30 을 새 값으로 교체", attr(s_us, "err") %||% "")

#==============================================================================
cat("\n[D] F5 이름 → 적재기 명시 표 디스패치 (incremental_update_all · 적재기 대역)\n")
LD <- c(Consensus_update.xlsx = "stub_cons", Investor_Act_update.xlsx = "stub_ref", Universe_Support_update.xlsx = "stub_ok")
dispatch_env <- function(lines, tag, files) {
  e <- new_env(lines, tag)
  e$calls <- list()
  e$stub_cons <- function() { e$calls$cons <- (e$calls$cons %||% 0L) + 1L; invisible(TRUE) }
  e$stub_ok   <- function() { e$calls$ok   <- (e$calls$ok   %||% 0L) + 1L; invisible(TRUE) }
  e$stub_ref  <- function() { e$calls$ref  <- (e$calls$ref  %||% 0L) + 1L
                              invisible(list(refused = TRUE, reasons = c(fill_low = "합성"))) }
  for (f in files) writeBin(as.raw(1:16), file.path(e$UPDATE_DIR, f))
  e
}
recorded <- function(e) names(readRDS(e$LAST_PROCESSED_FILE)$files)
e1 <- dispatch_env(src_lines, "D1", c("Consensus_update.xlsx", "Foo_update.xlsx"))
d1 <- quiet(e1$incremental_update_all(loaders = LD))
chk(inherits(d1, "update_file_unregistered") && grepl("UNREGISTERED", conditionMessage(d1)) &&
      grepl("Foo_update.xlsx", conditionMessage(d1)) && identical(e1$calls$cons, 1L) &&
      "Consensus_update.xlsx" %in% recorded(e1) && !"Foo_update.xlsx" %in% recorded(e1),
    "D1 미등록 xlsx → 경고 · 처리 미기록 · 끝에서 update_file_unregistered 오류(등록 책은 처리 · 기록)",
    if (inherits(d1, "error")) conditionMessage(d1) else "오류 없음")
d1b <- quiet(e1$incremental_update_all(loaders = LD))
chk(inherits(d1b, "update_file_unregistered") && identical(e1$calls$cons, 1L),
    "D2 다음 실행에도 미등록은 다시 경고(묻히지 않는다) · 이미 처리된 책은 다시 안 돈다")
sc_dispatch_substring <- function(lines) {
  e <- dispatch_env(lines, "D3", "Consensus_update_old.xlsx")
  d <- quiet(e$incremental_update_all(loaders = LD))
  c(D_substring_no_misdispatch = is.null(e$calls$cons),
    D_substring_flagged = inherits(d, "update_file_unregistered") && !"Consensus_update_old.xlsx" %in% recorded(e))
}
s_d <- safe_sc(sc_dispatch_substring, src_lines)
chk(sk(s_d, "D_substring_no_misdispatch"), "D3 'Consensus_update_old.xlsx'(부분 문자열) → 컨센서스 적재기 안 돈다(구판 grepl 오디스패치)", attr(s_d, "err") %||% "")
chk(sk(s_d, "D_substring_flagged"), "D4 그 파일은 미등록으로 경고 · 처리 미기록", attr(s_d, "err") %||% "")
e5 <- dispatch_env(src_lines, "D5", c("Consensus_update.xlsx", "Universe_Support_update.xlsx"))
d5 <- quiet(e5$incremental_update_all(loaders = LD))
chk(!inherits(d5, "error") && isTRUE(rf(d5, "updated")) && identical(e5$calls$cons, 1L) && identical(e5$calls$ok, 1L) &&
      all(c("Consensus_update.xlsx", "Universe_Support_update.xlsx") %in% recorded(e5)),
    "D5 양성 대조: 등록 이름만 → 오류 없음 · 각 적재기 1회 · 둘 다 기록",
    if (inherits(d5, "error")) conditionMessage(d5) else "")
e6 <- dispatch_env(src_lines, "D6", c("Consensus_update.xlsx", "Investor_Act_update.xlsx"))
d6 <- quiet(e6$incremental_update_all(loaders = LD))
d6b <- quiet(e6$incremental_update_all(loaders = LD))
chk(inherits(d6, "update_file_gate_refused") && grepl("GATE_REFUSED", conditionMessage(d6)) &&
      grepl("Investor_Act_update.xlsx(fill_low)", conditionMessage(d6), fixed = TRUE) &&
      "Consensus_update.xlsx" %in% recorded(e6) && !"Investor_Act_update.xlsx" %in% recorded(e6) &&
      identical(e6$calls$ref, 2L) && identical(e6$calls$cons, 1L),
    "D6 관문 거부 책 → GATE_REFUSED 오류 · 그 책만 미기록 · 다음 실행이 재시도(2회) · 다른 책은 1회",
    if (inherits(d6, "error")) conditionMessage(d6) else "오류 없음")
e7 <- dispatch_env(src_lines, "D7", "Foo_update.xlsx")
saveRDS(list(time = Sys.time(), files = list(Foo_update.xlsx = file.mtime(file.path(e7$UPDATE_DIR, "Foo_update.xlsx")))),
        e7$LAST_PROCESSED_FILE)                                   # 구판이 '처리됨'으로 묻어 둔 잔재
d7 <- quiet(e7$incremental_update_all(loaders = LD))
chk(inherits(d7, "update_file_unregistered") && !"Foo_update.xlsx" %in% recorded(e7),
    "D7 구판이 '처리됨'으로 기록해 둔 미등록 파일(변경 없음)도 드러나고 기록에서 빠진다")

#==============================================================================
cat("\n[R] rc 계약 — 실제 Rscript 자식 프로세스(daily_refresh.sh run_r 과 같은 비대화형 최상위 호출)\n")
DRIVER <- file.path(TMP, "rc_driver.R")
writeLines(c(
  'args <- commandArgs(trailingOnly = TRUE); src <- args[1]; mode <- args[2]; base <- args[3]',
  'suppressPackageStartupMessages({ library(data.table); library(arrow) })',
  'lines <- sub("\\r$", "", readLines(src, warn = FALSE, encoding = "UTF-8"))',
  sprintf('re <- "%s"', gsub("\\\\", "\\\\\\\\", WANT_RE)),
  'env <- new.env(parent = globalenv())',
  'for (e in parse(text = lines, keep.source = FALSE, encoding = "UTF-8"))',
  '  if (is.call(e) && identical(as.character(e[[1]]), "<-") && is.name(e[[2]]) && grepl(re, as.character(e[[2]]))) eval(e, envir = env)',
  'env$UPDATE_DIR <- file.path(base, "upd"); env$CACHE_DIR <- base',
  'env$LAST_PROCESSED_FILE <- file.path(base, "last.rds"); dir.create(env$UPDATE_DIR, recursive = TRUE, showWarnings = FALSE)',
  'env$stub_ok  <- function() invisible(TRUE)',
  'env$stub_ref <- function() invisible(list(refused = TRUE, reasons = c(fill_low = "x")))',
  'f <- switch(mode, refused = "Investor_Act_update.xlsx", unreg = "Foo_update.xlsx", clean = "Consensus_update.xlsx")',
  'writeBin(as.raw(1:8), file.path(env$UPDATE_DIR, f))',
  'cat("RC_DRIVER_READY\\n")',
  'env$incremental_update_all(loaders = c(Consensus_update.xlsx = "stub_ok", Investor_Act_update.xlsx = "stub_ref"))',
  'cat("RC_DRIVER_RETURNED\\n")'), DRIVER)
rc_run <- function(src_path, mode) {
  base <- file.path(TMP, paste0("rc_", mode, "_", sample.int(1e8, 1))); dir.create(base)
  out <- suppressWarnings(system2(RSCRIPT, c("--no-environ", shQuote(DRIVER), shQuote(src_path), mode, shQuote(base)),
                                  stdout = TRUE, stderr = TRUE))
  st <- attr(out, "status"); if (is.null(st)) st <- 0L
  list(status = as.integer(st), ready = any(grepl("RC_DRIVER_READY", out)), returned = any(grepl("RC_DRIVER_RETURNED", out)),
       tail = paste(tail(out, 2L), collapse = " | "))
}
r_clean <- rc_run(SRC, "clean")
if (!(r_clean$status == 0L && r_clean$ready && r_clean$returned))
  ng("R0 카나리아: 정상 호출이 rc 0 · 반환 표지로 끝나야 한다(인터프리터 · 적재 경로 생존)", r_clean$tail) else
  ok("R0 카나리아: 정상 → rc 0 · 반환 표지(자식 프로세스 계측 생존)")
r_ref <- rc_run(SRC, "refused")
chk(r_ref$status == 3L && r_ref$ready && !r_ref$returned, "R1 관문 거부가 잡히지 않고 끝나면 Rscript rc 3(도달 표지 있음 — 죽은 프로세스 rc 아님)",
    sprintf("rc=%d ready=%s %s", r_ref$status, r_ref$ready, r_ref$tail))
r_unr <- rc_run(SRC, "unreg")
chk(r_unr$status == 4L && r_unr$ready && !r_unr$returned, "R2 미등록 xlsx 만 → rc 4",
    sprintf("rc=%d ready=%s %s", r_unr$status, r_unr$ready, r_unr$tail))

#==============================================================================
cat("\n[M] 돌연변이 — 소스 텍스트 치환(정확히 1줄 · 치환 성사 단정) 후 해당 판정이 red 여야 한다\n")
mutate_line <- function(lines, exact, repl) {
  hit <- which(lines == exact)
  if (length(hit) != 1L) stop(sprintf("돌연변이 대상 줄 %d개(1개여야): %s", length(hit), exact))
  out <- lines; out[hit] <- repl
  if (identical(out, lines)) stop("치환이 적용되지 않았다")
  if (sum(out != lines) != 1L) stop("치환된 줄이 1줄이 아니다")
  out
}
MUT <- list(
  list(id = "M1 F3 지표별 창 → eps_1y max 이후(구판 앵커)", red = "C_f3_lagging_window_filled", run = sc_consensus_f3,
       exact = "    win <- sort(unique(as.Date(if (is.null(windows)) tmp_dt[, Date] else windows[[mkey]])))",
       repl  = paste0("    win <- sort(unique(as.Date(if (is.null(windows)) tmp_dt[, Date] else windows[[mkey]]))); ",
                      "win <- win[win > max(as.Date(read_parquet(file.path(cons_cache_dir, \"eps_1y.parquet\"), col_select = \"Date\")$Date))]")),
  list(id = "M2 F4 채움비 비교 삭제(항상 ok)", red = "I_partial_refused", run = sc_investor_partial,
       exact = "        if (ratio < thr) \"fill_low\" else \"ok\"", repl = "        \"ok\""),
  list(id = "M3 F5 완전 일치 → 부분 문자열 디스패치(구판)", red = "D_substring_no_misdispatch", run = sc_dispatch_substring,
       exact = "    if (!nm %in% changed_names) next",
       repl  = "    if (!any(grepl(sub(\"_update.xlsx\", \"\", nm, fixed = TRUE), changed_names, fixed = TRUE))) next"),
  # ── 2차 보강 — 1차 시험이 못 잡던 자리(독립 검증 VD 등) ─────────────────────────────
  list(id = "M5 date_axis_missing 판정 줄 삭제(독립 검증 VD)", red = "H_axis_missing", run = sc_header_cases,
       exact = "  if (length(noax)) g <- .uf_gate_add(g, \"date_axis_missing\", sprintf(\"'D A T E' 아래 날짜축 없음/0일: %s\", lst(noax)))",
       repl  = "  # (돌연변이) date_axis_missing 판정 삭제"),
  list(id = "M5b 같은 돌연변이 — 통합 경로(날짜축 없는 개인 시트 책)", red = "I_noaxis_refused", run = sc_investor_noaxis,
       exact = "  if (length(noax)) g <- .uf_gate_add(g, \"date_axis_missing\", sprintf(\"'D A T E' 아래 날짜축 없음/0일: %s\", lst(noax)))",
       repl  = "  # (돌연변이) date_axis_missing 판정 삭제"),
  list(id = "M6 not_query_sheet 판정 줄 삭제", red = "H_not_query", run = sc_header_cases,
       exact = "  if (length(nq)) g <- .uf_gate_add(g, \"not_query_sheet\", sprintf(\"A6 가 Period(To) 가 아님: %s\", lst(nq)))",
       repl  = "  # (돌연변이) not_query_sheet 판정 삭제"),
  list(id = "M7 sheet_read_error 판정 줄 삭제", red = "H_read_error", run = sc_header_cases,
       exact = "  if (nrow(bad)) g <- .uf_gate_add(g, \"sheet_read_error\", paste(sprintf(\"%s: %s\", bad$sheet, bad$err), collapse = \" | \"))",
       repl  = "  # (돌연변이) sheet_read_error 판정 삭제"),
  list(id = "M8 수급 교체 단위 → 4유형 창 합집합(1차 판)", red = "I_per_sheet_others_kept", run = sc_investor_per_sheet,
       exact = "  combined <- rbind(if (nrow(win_key)) existing[!win_key, on = c(\"InvestorType\", \"Date\")] else existing, new_dt, fill = TRUE)",
       repl  = "  combined <- rbind(existing[!Date %in% unique(win_key$Date)], new_dt, fill = TRUE)"),
  list(id = "M9 컨센서스 교체 창 → 12지표 창 합집합", red = "C_per_metric_others_kept", run = sc_consensus_per_metric,
       exact = "    win <- sort(unique(as.Date(if (is.null(windows)) tmp_dt[, Date] else windows[[mkey]])))",
       repl  = "    win <- sort(unique(as.Date(if (is.null(windows)) tmp_dt[, Date] else do.call(c, unname(windows)))))"),
  list(id = "M10 유니버스 교체 창 → 8시트 창 합집합", red = "U_per_sheet_others_kept", run = sc_universe_per_sheet,
       exact = "    upd_dates  <- windows[[meta$cache_name]]                 # 받은 창(관문이 날짜마다 채움을 확인한 날짜축)",
       repl  = "    upd_dates  <- sort(unique(do.call(c, unname(windows))))"),
  list(id = "M11 window_empty 판정 끄기", red = "G_window_empty", run = sc_window_empty,
       exact = "  if (length(we))", repl = "  if (FALSE)")
)
for (m in MUT) {
  ml <- tryCatch(mutate_line(src_lines, m$exact, m$repl), error = function(e) e)
  if (inherits(ml, "error")) { ng(m$id, paste("돌연변이 적용 실패:", conditionMessage(ml))); next }
  mr <- tryCatch(m$run(ml), error = function(e) e)
  if (inherits(mr, "error")) { ng(m$id, paste("돌연변이 실행 오류:", conditionMessage(mr))); next }
  if (!m$red %in% names(mr)) { ng(m$id, sprintf("돌연변이 결과에 판정 키 %s 없음", m$red)); next }
  chk(isFALSE(unname(mr[[m$red]])), sprintf("%s → %s red", m$id, m$red), "돌연변이 무반응(green 으로 남음)")
}
# 두 방어선의 분업 — M5 사본(date_axis_missing 삭제)에서도 window_empty 가 같은 책을 거부해 캐시가 무접촉이어야 하고,
#   둘 다 지운 사본에서는 그 책이 '적재'로 기록돼 캐시가 바뀌어야 한다(= I7 이 실제로 손실 경로를 잰다는 양성 대조).
M5X <- MUT[[which(vapply(MUT, function(m) startsWith(m$id, "M5b"), logical(1)))]]
M11X <- MUT[[which(vapply(MUT, function(m) startsWith(m$id, "M11"), logical(1)))]]
case("M12", {
  l5 <- mutate_line(src_lines, M5X$exact, M5X$repl)
  r5 <- sc_investor_noaxis(l5)
  e5w <- new_env(l5, "M12w"); mk_investor(e5w, "noaxis")
  r5w <- quiet(e5w$incremental_investor(target = TGT))
  chk(isTRUE(r5[["I_noaxis_untouched"]]) && "window_empty" %in% rsn(r5w) && !"date_axis_missing" %in% rsn(r5w),
      "M12a date_axis_missing 만 지운 사본 → window_empty 가 같은 책을 거부 · 캐시 무접촉(두 번째 방어선 실동)", desc(r5w))
  l511 <- mutate_line(l5, M11X$exact, M11X$repl)
  r511 <- sc_investor_noaxis(l511)
  chk(isFALSE(r511[["I_noaxis_refused"]]) && isFALSE(r511[["I_noaxis_untouched"]]),
      "M12b 두 줄 다 지운 사본 → 날짜축 없는 책이 '적재'(캐시 변경) — I7 이 그 손실 경로를 잰다(양성 대조)")
})
m4 <- tryCatch(mutate_line(src_lines, "      .old_err <- options(error = function() quit(save = \"no\", status = .rc, runLast = FALSE))",
                           "      .old_err <- list()"), error = function(e) e)
if (inherits(m4, "error")) ng("M4 rc 종료 코드 처리 삭제", paste("돌연변이 적용 실패:", conditionMessage(m4))) else {
  mp <- file.path(TMP, "mutant_rc.R"); writeLines(m4, mp, useBytes = TRUE)
  rm4 <- rc_run(mp, "refused")
  chk(rm4$ready && rm4$status != 3L, sprintf("M4 rc 종료 코드 처리 삭제 → R1 red(거부 rc=%d · 구판처럼 1)", rm4$status), rm4$tail)
}

unlink(TMP, recursive = TRUE)
cat(sprintf("\n[%s] PASS: %d  FAIL: %d\n", TEST_NAME, PASS, FAIL))
cat(sprintf('{"test":"%s","pass":%d,"fail":%d}\n', TEST_NAME, PASS, FAIL))
quit(status = if (FAIL == 0L) 0L else 1L)
