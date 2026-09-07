#!/usr/bin/env Rscript
# test_rf_prompt_format_safety.R — 프롬프트 문자열은 포맷터를 통과해야 한다 (2026-09-07 실사고)
#
# 실사고: 감사 팬아웃 프롬프트에 예시 문구 '[숏 레그 그로스 익스포저 24% 미달]' 를 넣었다.
#   그 프롬프트는 파이썬 `"""...""" % (...)` 로 조립되는데 `%` 뒤에 포맷 문자가 아닌 글자가
#   오면 **TypeError 로 죽는다**. 계획 파일이 안 만들어지고 레인은 halt_no_plan 으로 조용히
#   물러났다 — 감사가 3회 스폰 전부 실패했고, 오늘 만든 "감사 없이 개설 불가" 가드가
#   그 침묵을 잡아 논문을 안 열었다(가드는 옳게 작동). 원인은 프롬프트 한 글자였다.
# ★기존 test_rf_prompt_quote_parity 는 따옴표만 본다 — 포맷 문자는 그 검사의 사각이었다.
#   양방향: 양성(현행 블록이 실제로 조립된다) + 위반 주입(미이스케이프 % 를 넣으면 빨강).
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
PASS <- 0L; FAIL <- 0L
ok <- function(m) { PASS <<- PASS + 1L; cat("  OK  ", m, "\n") }
ng <- function(m, why = "") { FAIL <<- FAIL + 1L; cat("  FAIL", m, if (nzchar(why)) paste0(" — ", why) else "", "\n") }
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
PY   <- Sys.getenv("QVEST_PY", file.path(ROOT, ".venv_qvest_ml/Scripts/python.exe"))
SH   <- file.path(ROOT, "02_Infrastructure/ops/rf_fidelity_fanout.sh")

## 셸 스크립트 안의 파이썬 heredoc 블록을 뽑는다 (블록 경계는 소스에서 재도출 — 행번호 못박지 않는다)
extract_block <- function(path) {
  ln <- readLines(path, encoding = "UTF-8", warn = FALSE)
  st <- grep("<<'PYEOF'", ln, fixed = TRUE)
  en <- grep("^PYEOF$", ln)
  if (!length(st) || !length(en)) return(NULL)
  en <- en[en > st[1]][1]
  ln[(st[1] + 1L):(en - 1L)]
}
blk <- extract_block(SH)
if (!is.null(blk) && length(blk) > 20L) ok(sprintf("A0 파이썬 블록 추출 %d줄", length(blk))) else {
  ng("A0 블록을 못 찾았다 — 검사가 표적을 잃었다"); }

## 파이썬 문자열 리터럴로 안전하게 감싼다(경로 백슬래시가 이스케이프로 읽히지 않게 슬래시 통일)
.q <- function(s) paste0("'", gsub("'", "\\\\'", gsub("\\\\", "/", s)), "'")
run_block <- function(lines, tag) {
  sbx <- file.path(tempdir(), sprintf("pfmt_%s_%d", tag, Sys.getpid()))
  dir.create(sbx, recursive = TRUE, showWarnings = FALSE)
  writeLines("x", file.path(sbx, "engine.R"))
  py <- file.path(sbx, "blk.py")
  plan <- file.path(sbx, "plan.tsv")
  ## ★system2(env=) 는 이 저장소 금칙 1(r-portability)이다 — Windows 에서 env 가 argv 로 새어
  ##   파이썬이 "AXB=[공리]" 를 파일명으로 연다(이 검사를 쓰다 실제로 밟았다). 대신 블록 앞에
  ##   os.environ 주입 머리를 붙인다 — 블록 본문은 한 글자도 안 바꾸므로 표적이 그대로다.
  hdr <- c("import os",
           sprintf("os.environ.update({'AXB': %s, 'HTMLU': %s, 'PURL': %s, 'WDIR': %s, 'ART': %s, 'AXES': %s, 'PLAN': %s})",
                   .q("[공리]"), .q("https://arxiv.org/html/0000.0000v1"), .q("https://arxiv.org/abs/0000.0000"),
                   .q(sbx), .q(sbx), .q(file.path(ROOT, "06_Registry/rf_fidelity_axes.json")), .q(plan)))
  writeLines(c(hdr, lines), py, useBytes = TRUE)
  out <- suppressWarnings(system2(PY, shQuote(py), stdout = TRUE, stderr = TRUE))
  rc <- attr(out, "status") %||% 0L
  list(rc = as.integer(rc), out = paste(out, collapse = " "), plan = plan,
       made = file.exists(plan) && file.info(plan)$size > 0)
}

cat("=== A. 양성 — 현행 프롬프트가 실제로 조립된다 ===\n")
if (!is.null(blk)) {
  r <- run_block(blk, "cur")
  if (identical(r$rc, 0L)) ok("A1 블록 실행 rc=0") else ng("A1 블록이 죽는다", substr(r$out, 1, 200))
  if (isTRUE(r$made)) ok("A2 계획 파일이 만들어진다(레인이 halt_no_plan 으로 안 물러난다)") else
    ng("A2 계획 미생성 — 레인이 조용히 멈춘다")
  if (grepl("axes=", r$out, fixed = TRUE)) ok("A3 축 수를 보고한다") else ng("A3 축 보고 없음", substr(r$out,1,120))
}

cat("=== B. 위반 주입 — 미이스케이프 %가 들어가면 잡히는가 ===\n")
if (!is.null(blk)) {
  ## 실사고 그대로: 프롬프트 본문에 "24% 미달" 을 넣는다(포맷 문자가 아닌 글자가 % 뒤에 온다)
  bad <- blk
  i <- grep("적대적 검증자", bad, fixed = TRUE)[1]
  if (is.na(i)) i <- which(nchar(bad) > 40)[1]
  bad[i] <- paste0(bad[i], " 예: 24% 미달")
  rb <- run_block(bad, "bad")
  if (!identical(rb$rc, 0L) || !isTRUE(rb$made))
    ok("B1 미이스케이프 % 주입 → 블록 실패(검출력 실증)") else
    ng("B1 주입해도 통과 — 이 검사는 사고를 못 잡는다")
  ## 정상 이스케이프(%%)는 통과해야 한다 — 과잉 차단 금지
  good <- blk
  good[i] <- paste0(good[i], " 예: 24%% 미달")
  rg <- run_block(good, "good")
  if (identical(rg$rc, 0L) && isTRUE(rg$made)) ok("B2 %% 는 정상 통과(과잉 차단 아님)") else
    ng("B2 이스케이프한 %% 까지 막는다", substr(rg$out, 1, 160))
}

cat("=== C. 정적 스캔 — 포맷 문자열 안의 % 규약 ===\n")
if (!is.null(blk)) {
  txt <- paste(blk, collapse = "\n")
  ## 허용: %s %d %r %f %g %% · 그 외 % 뒤 문자는 위반 후보
  m <- gregexpr("%[^sdrfg%( ]", txt)[[1]]
  if (m[1] < 0) ok("C1 미이스케이프 % 0건") else {
    ctx <- vapply(m, function(k) substr(txt, max(1, k - 20), k + 20), character(1))
    ng(sprintf("C1 미이스케이프 %% %d건", length(m)), paste(head(ctx, 2), collapse = " | "))
  }
}

cat(sprintf("\n합계: 통과 %d · 실패 %d\n", PASS, FAIL))
cat(sprintf('{"test":"rf_prompt_format_safety","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
quit(status = if (FAIL == 0L) 0L else 1L)
