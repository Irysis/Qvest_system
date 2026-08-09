## FQ-181 P1 — build_monthly_forward_returns 하류 소비자 census
##
## 규율:
##   - 검색은 fixed=TRUE (정규식 이스케이프 함정 회피). 스크립트는 Write 도구로 작성.
##   - ★검사기가 0 을 반환하면 정지 신호 — 양성 대조(정의 파일 자신이 잡히는지) 선행.
##
## 판정 축 3개 (각 호출부에 대해):
##   A. call_site   : 실제 호출인가(주석/문자열 언급이 아니라)
##   B. panel_shape : 넘기는 rawdata 가 일간인가 월말-slim 인가  ← 20일 자 계산 가능성
##   C. liq_wired   : fwd$liq_dt 가 canonical_screen_bt(liq_dt=) 로 실제 전달되는가
##
## read-only. 산출: p1_consumer_census.json / .csv

suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
QM <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
QM <- gsub("\\\\", "/", QM); setwd(QM)
OUT <- file.path(QM, "stage_artifacts/FQ181_liquidity_ruler")

NEEDLE   <- "build_monthly_forward_returns"
DEF_FILE <- "02_Infrastructure/ramp/factor_validation.R"

## ── 대상 파일 수집 (코드만; .git/.cache/renv 제외) ──────────────────────────
exts <- c("R", "r", "py", "sh")
files <- unlist(lapply(exts, function(e)
  list.files(QM, pattern = paste0("\\.", e, "$"), recursive = TRUE, full.names = FALSE)))
drop <- grepl("^(\\.git/|\\.cache/|renv/|\\.venv)", files)
files <- files[!drop]
cat(sprintf("[scan] 코드 파일 %d 개 스캔\n", length(files)))

hits <- list()
for (f in files) {
  ln <- tryCatch(readLines(file.path(QM, f), warn = FALSE, encoding = "UTF-8"),
                 error = function(e) character(0))
  if (!length(ln)) next
  idx <- which(grepl(NEEDLE, ln, fixed = TRUE))   # ★fixed=TRUE
  if (!length(idx)) next
  hits[[length(hits) + 1L]] <- data.table(file = f, line = idx, text = ln[idx])
}
H <- if (length(hits)) rbindlist(hits) else data.table()

## ── 양성 대조: 정의 파일 자신이 잡혀야 한다 ─────────────────────────────────
pc <- DEF_FILE %in% H$file
cat(sprintf("[positive-control] 정의 파일(%s) 검출: %s\n", DEF_FILE,
            if (pc) "OK" else "★FAIL — 스캐너 사망 의심, 결과를 신뢰하지 말 것"))
if (!pc) stop("positive control FAIL — 0/저계수는 결론이 아니라 정지 신호")
if (nrow(H) == 0L) stop("0 hits — 정지 신호")

## ── A. 호출부 판별: 주석(#, ##)·source 주석 꼬리 제거 ───────────────────────
H[, code_part := sub("#.*$", "", text)]
H[, is_call := grepl(paste0(NEEDLE, "("), code_part, fixed = TRUE)]
H[, is_def  := grepl(paste0(NEEDLE, " <- function"), code_part, fixed = TRUE)]

CALLS <- H[is_call == TRUE & is_def == FALSE]
cat(sprintf("[A] 언급 %d 행 / %d 파일  →  실제 호출부 %d 행 / %d 파일\n",
            nrow(H), uniqueN(H$file), nrow(CALLS), uniqueN(CALLS$file)))

## ── B. panel_shape: 첫 인자 변수명 추출 → 그 변수의 생성 방식 조사 ──────────
arg1_of <- function(txt) {
  p <- regmatches(txt, regexpr(paste0(NEEDLE, "\\([^,)]*"), txt, perl = TRUE))
  if (!length(p)) return(NA_character_)
  trimws(sub(paste0(NEEDLE, "\\("), "", p, perl = TRUE))
}
CALLS[, panel_var := vapply(code_part, arg1_of, character(1))]

## 월말-slim 지문: 그 파일 안에서 panel_var 가 month-end 날짜집합으로 제한되는가
SLIM_MARKS <- c("Date %in% .me", "Date %in% ME", "Date %in% .MEND", "Date %in% mend",
                "Date %in% .mend", "month-end", "month_end", "월말")
classify_panel <- function(f, v) {
  ln <- readLines(file.path(QM, f), warn = FALSE, encoding = "UTF-8")
  code <- sub("#.*$", "", ln)
  ## ★fixed=TRUE — panel_var 에 정규식 특수문자(`[`, `$` 등)가 섞여 있어
  ##   정규식으로 짜면 "Invalid character range" 로 죽거나(운 좋은 경우)
  ##   조용히 다른 걸 매치한다(운 나쁜 경우).
  asg <- unique(c(grep(paste0(v, " <-"), code, fixed = TRUE, value = TRUE),
                  grep(paste0(v, "<-"),  code, fixed = TRUE, value = TRUE),
                  grep(paste0(v, "["),   code, fixed = TRUE, value = TRUE)))
  blob <- paste(asg, collapse = " || ")
  slim_hit <- any(vapply(SLIM_MARKS, function(m) grepl(m, blob, fixed = TRUE), logical(1)))
  # 파일 전역에서도 slim 관용구를 본다(변수 재대입이 다른 이름을 거칠 수 있음)
  glob <- paste(code, collapse = " || ")
  slim_glob <- any(vapply(c("Date %in% .me", "Date %in% ME", "Date %in% .MEND",
                            "month-end 거래일만", "month-end 제한"),
                          function(m) grepl(m, glob, fixed = TRUE), logical(1)))
  name_hint <- grepl("me$|_me|RAWME|rawme|MEND", v)
  list(assign_lines = paste(trimws(head(asg, 4)), collapse = " ; "),
       slim_by_assign = slim_hit, slim_by_file = slim_glob, slim_by_name = name_hint,
       verdict = if (slim_hit || slim_glob || name_hint) "month_end_slim(suspect)" else "daily(suspect)")
}

## ── C. liq_wired: 같은 파일에서 liq_dt = 가 canonical_screen_bt 로 전달되는가 ──
classify_liq <- function(f) {
  ln <- readLines(file.path(QM, f), warn = FALSE, encoding = "UTF-8")
  code <- sub("#.*$", "", ln)
  glob <- paste(code, collapse = "\n")
  uses_liq_arg <- grepl("liq_dt", glob, fixed = TRUE)
  uses_fwd_liq <- grepl("liq_dt", glob, fixed = TRUE) &&
                  (grepl("fwd$liq_dt", glob, fixed = TRUE) ||
                   grepl("$liq_dt", glob, fixed = TRUE))
  uses_csbt <- grepl("canonical_screen_bt", glob, fixed = TRUE)
  list(uses_canonical_screen_bt = uses_csbt,
       passes_liq_dt = uses_liq_arg,
       consumes_fwd_liq = uses_fwd_liq,
       verdict = if (!uses_csbt) "no_canonical_screen"
                 else if (uses_fwd_liq) "liq_wired"
                 else if (uses_liq_arg) "liq_arg_present(source_unclear)"
                 else "LIQ_UNWIRED(유동성 판정 미경유)")
}

rows <- list()
for (i in seq_len(nrow(CALLS))) {
  f <- CALLS$file[i]; v <- CALLS$panel_var[i]
  pb <- classify_panel(f, v); lq <- classify_liq(f)
  rows[[i]] <- data.table(
    file = f, line = CALLS$line[i], panel_var = v,
    panel_shape = pb$verdict, slim_by_assign = pb$slim_by_assign,
    slim_flags = paste0("assign=", pb$slim_by_assign, ",file=", pb$slim_by_file, ",name=", pb$slim_by_name),
    liq_verdict = lq$verdict,
    uses_csbt = lq$uses_canonical_screen_bt, passes_liq = lq$passes_liq_dt
  )
}
CEN <- rbindlist(rows)
setorder(CEN, file, line)

cat("\n=== CENSUS ===\n")
print(CEN[, .(file, line, panel_var, panel_shape, liq_verdict)], nrows = 100)

cat("\n--- 집계 ---\n")
cat("[B] panel_shape:\n"); print(CEN[, .N, by = panel_shape])
cat("[C] liq_verdict:\n"); print(CEN[, .N, by = liq_verdict])
cat(sprintf("\n★핵심: 월말-slim 패널을 넘기는 호출부에서는 20일 자를 함수 내부에서 계산할 수 없다 (입력에 일간이 없음).\n"))

## 비코드 언급(문서/JSON)은 별도 집계
docs <- unlist(lapply(c("md", "json"), function(e)
  list.files(QM, pattern = paste0("\\.", e, "$"), recursive = TRUE, full.names = FALSE)))
docs <- docs[!grepl("^(\\.git/|\\.cache/|renv/)", docs)]
ndoc <- 0L
for (f in docs) {
  ln <- tryCatch(readLines(file.path(QM, f), warn = FALSE, encoding = "UTF-8"), error = function(e) character(0))
  if (length(ln) && any(grepl(NEEDLE, ln, fixed = TRUE))) ndoc <- ndoc + 1L
}
cat(sprintf("[비코드] 문서/JSON 언급 파일 %d 개 (호출 아님)\n", ndoc))

fwrite(CEN, file.path(OUT, "p1_consumer_census.csv"))
write_json(list(
  needle = NEEDLE, positive_control_passed = pc,
  n_files_scanned = length(files),
  n_mention_lines = nrow(H), n_mention_files = uniqueN(H$file),
  n_call_lines = nrow(CALLS), n_call_files = uniqueN(CALLS$file),
  n_doc_files = ndoc,
  by_panel_shape = as.list(setNames(CEN[, .N, by = panel_shape]$N, CEN[, .N, by = panel_shape]$panel_shape)),
  by_liq_verdict = as.list(setNames(CEN[, .N, by = liq_verdict]$N, CEN[, .N, by = liq_verdict]$liq_verdict)),
  rows = CEN
), file.path(OUT, "p1_consumer_census.json"), auto_unbox = TRUE, pretty = TRUE, digits = NA)
cat("\n[done] p1_consumer_census.{csv,json}\n")
