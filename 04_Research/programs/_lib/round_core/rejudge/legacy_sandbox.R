## 구 evaluate.R 격리 사본 — 그 판의 원래 코드를 오늘 같은 입력으로 다시 돌린다(차이 분류용 · 무거움). 소스 텍스트 치환(치환마다 정확히 1줄 · deparse 금지):
##   루트 = 재현 루트 · 저장된 칸 산출 = 읽기(결과 폴더) · 작업 사본 · 평가 파일 = 출력 디렉터리(스크래치). 라운드 결과 폴더에는 쓰지 않는다.
## 사용: Rscript legacy_sandbox.R <P2R04|P2R03|P3R03> <재현 루트> <저장 칸 산출(results)> <출력 디렉터리>
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
a <- commandArgs(trailingOnly = TRUE); round <- a[1]; root <- gsub("\\\\", "/", a[2]); res <- gsub("\\\\", "/", a[3]); out <- gsub("\\\\", "/", a[4])
MAIN <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
rd <- switch(round, P2R04 = "04_Research/programs/P2_DEFENSE/P2R04_defensive_holdings", P2R03 = "04_Research/programs/P2_DEFENSE/P2R03_conditional_overlay",
             P3R03 = "04_Research/programs/P3_CONSTRUCTION/P3R03_advanced_construction")
src <- readLines(file.path(root, rd, "evaluate.R"), encoding = "UTF-8", warn = FALSE)
sub1 <- function(from, to) { h <- sum(grepl(from, src, fixed = TRUE)); if (h != 1L) stop(sprintf("치환 대상 %d줄(1줄이어야 함): %s", h, from))
                             src <<- sub(from, to, src, fixed = TRUE) }
q <- function(p) sprintf('"%s"', p)
sub1(sprintf('ROOT <- "%s"', MAIN), sprintf("ROOT <- %s", q(root)))
sub1('pc <- file.path(RD, "results", "precheck.json")', sprintf("pc <- %s", q(file.path(res, "precheck.json"))))
sub1('RES <- file.path(RD, "results")', sprintf("RES <- %s", q(res)))
sub1("X <- list(root = ROOT, res = RES, out = RES,", sprintf("X <- list(root = ROOT, res = RES, out = %s,", q(out)))
if (round %in% c("P2R04", "P2R03")) {
  sub1('file.path(RES, "evaluation_full.json")', sprintf('file.path(%s, "evaluation_full.json")', q(out)))
  sub1('file.path(RES, "evaluation_visible.json")', sprintf('file.path(%s, "evaluation_visible.json")', q(out)))
} else {
  sub1("rk_eval_cell(ROOT, RD, cl, env, TAU)", sprintf("rk_eval_cell(ROOT, %s, cl, env, TAU)", q(dirname(res))))
  sub1('rj <- file.path(RD, "results", paste0(cd, ".json"))', sprintf('rj <- file.path(%s, paste0(cd, ".json"))', q(res)))
  sub1('file.path(RES, "evaluation.json")', sprintf('file.path(%s, "evaluation.json")', q(out)))
}
dir.create(out, recursive = TRUE, showWarnings = FALSE)
p <- file.path(out, sprintf("%s_evaluate_sandbox.R", round)); writeLines(src, p, useBytes = TRUE)
t0 <- Sys.time()
o <- suppressWarnings(system2("Rscript", shQuote(p), stdout = TRUE, stderr = TRUE))
writeLines(o, file.path(out, "legacy_sandbox.log"), useBytes = TRUE)
cat(sprintf("[구판 격리] %s · %.0f초 · rc %s\n", round, as.numeric(difftime(Sys.time(), t0, units = "secs")), attr(o, "status") %||% 0))
