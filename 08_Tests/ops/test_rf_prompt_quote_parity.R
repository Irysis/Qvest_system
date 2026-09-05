#!/usr/bin/env Rscript
#==============================================================================
# test_rf_prompt_quote_parity.R — 셸 프롬프트 문자열 안의 맨따옴표 (2026-09-05)
#
# 실사고: rf_replication_auto.sh:241 `PROMPT="...` 가 큰따옴표 문자열인데 293행 본문에
#   ★"영향이 미미해서 안 적었다" 가 들어가 문자열이 거기서 닫혔다. 그러면 bash 는
#   `PROMPT=<앞부분> 미미해서 안 ...` 를 **명령 앞 임시 환경할당**으로 읽는다 —
#   즉 PROMPT 는 그 명령에만 실리고 셸에는 안 남는다. 뒤에서 set -u 가 unbound variable 로 죽었다.
#   ★bash -n 은 이걸 못 잡는다(문자열이 일찍 닫혀도 문법은 유효). 어제 19:47 커밋에 들어와
#   오늘 13:22 첫 호출까지 18시간 잠복했고, 그동안 루프는 active entry 없이 멈춰 있었다.
#
# 판정: 큰따옴표로 여는 PROMPT 계열 할당 안에서 **비이스케이프 맨따옴표**가 나오면 FAIL.
#       (여는 줄의 첫 따옴표와 닫는 따옴표는 제외)
#==============================================================================
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
PASS <- 0L; FAIL <- 0L
ok <- function(m) { PASS <<- PASS + 1L; cat("  OK  ", m, "\n") }
ng <- function(m, why = "") { FAIL <<- FAIL + 1L; cat("  FAIL", m, if (nzchar(why)) paste0(" — ", why) else "", "\n") }
BS <- rawToChar(as.raw(92)); Q <- '"'

## 여는 줄(VAR=") 부터 닫는 따옴표까지, 비이스케이프 따옴표가 몇 번 나오나
scan_file <- function(f) {
  L <- readLines(f, encoding = "UTF-8", warn = FALSE)
  open_idx <- grep(paste0("^[[:space:]]*[A-Z_]*PROMPT[A-Z_]*=", Q), L)
  bad <- list()
  for (st in open_idx) {
    depth_open <- TRUE
    for (n in st:length(L)) {
      ln <- L[n]
      chars <- strsplit(ln, "")[[1]]
      start <- if (n == st) regexpr(Q, ln)[1] + 1L else 1L
      if (start > length(chars)) next
      k <- start
      while (k <= length(chars)) {
        ## ★명령치환 안의 따옴표는 문자열을 닫지 않는다 — $( ... ) 를 통째로 건너뛴다.
        ##   구판 검사기가 $(cat "$MAT") 를 위반으로 읽어 3건 오탐을 냈다(계기가 잘못 잰 사례).
        if (chars[k] == "$" && k < length(chars) && chars[k + 1L] == "(") {
          d <- 1L; k <- k + 2L
          while (k <= length(chars) && d > 0L) {
            if (chars[k] == "(") d <- d + 1L else if (chars[k] == ")") d <- d - 1L
            k <- k + 1L
          }
          next
        }
        if (chars[k] == Q && (k == 1L || chars[k - 1L] != BS)) {
          ## 닫는 따옴표인가: 줄 끝이거나 뒤가 공백/세미콜론이면 닫힘으로 본다
          rest <- if (k < length(chars)) paste(chars[(k + 1L):length(chars)], collapse = "") else ""
          if (!nzchar(trimws(rest))) { depth_open <- FALSE; break }
          bad[[length(bad) + 1L]] <- list(file = basename(f), line = n, text = substr(ln, 1, 60))
          depth_open <- FALSE; break
        }
        k <- k + 1L
      }
      if (!depth_open) break
    }
  }
  bad
}

files <- c("02_Infrastructure/ops/rf_replication_auto.sh",
           "02_Infrastructure/ops/rf_overlay_propose.sh",
           "02_Infrastructure/ops/rf_b1_design.sh",
           "02_Infrastructure/ops/rf_lcode_mechanism.sh")
files <- files[file.exists(file.path(ROOT, files))]
cat("=== 1. 프롬프트 문자열 맨따옴표 (전 레인) ===\n")
tot <- 0L
for (f in files) {
  b <- scan_file(file.path(ROOT, f))
  tot <- tot + length(b)
  if (!length(b)) ok(sprintf("%s — 비이스케이프 따옴표 없음", basename(f)))
  else for (x in b) ng(sprintf("%s:%d 문자열이 조기 종료", x$file, x$line), x$text)
}

cat("=== 2. 양성 대조 — 위반 주입 ===\n")
tmp <- file.path(tempdir(), paste0("qp_", Sys.getpid(), ".sh"))
writeLines(c('PROMPT="첫 줄', paste0('본문에 ', Q, '따옴표', Q, ' 가 있다'), '마지막 줄."'), tmp, useBytes = TRUE)
if (length(scan_file(tmp)) >= 1L) ok("주입한 위반을 잡는다") else ng("위반 주입을 놓친다 — 죽은 검사")
writeLines(c('PROMPT="첫 줄', paste0('본문에 ', BS, Q, '따옴표', BS, Q, ' 가 있다'), '마지막 줄."'), tmp, useBytes = TRUE)
if (length(scan_file(tmp)) == 0L) ok("이스케이프판은 통과(과잉 차단 아님)") else ng("이스케이프된 따옴표를 위반으로 오판")
unlink(tmp)

cat("=== 3. 실사고 회귀 — 293행 ===\n")
rl <- readLines(file.path(ROOT, "02_Infrastructure/ops/rf_replication_auto.sh"), encoding = "UTF-8", warn = FALSE)
if (length(rl) >= 293 && grepl(paste0(BS, Q, "영향이 미미해서"), rl[293], fixed = TRUE))
  ok("293행 이스케이프 유지") else ng("293행이 구판으로 되돌아갔다")

cat(sprintf("\n합계: 통과 %d · 실패 %d\n", PASS, FAIL))
cat(sprintf('{"test":"rf_prompt_quote_parity","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
quit(status = if (FAIL == 0L) 0L else 1L)
