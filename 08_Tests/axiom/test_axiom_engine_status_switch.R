# test_axiom_engine_status_switch.R -- Axiom 엔진 처분 스위치(06_Registry/axiom_engine_status.json) (2026-11-10 · v10.2)
#
# 지키는 것:
#   v10.2 처분 = 기록 · 조회만 남기고 승격 기계 · DIST 수명주기 · 주입 변동부를 닫는다. 그 처분은 등록부 설정 두 칸으로 건다
#   (promotion_enabled · inject_variable_part). 주입 변동부를 끄면 종전의 '주입 길이 초과' 보류가 풀리므로, 주간 스윕이 이 설정을
#   직접 읽어 후보 순회를 건너뛰지 않으면 닫았다는 승격 기계가 다시 돈다.
#
# 축:
#   A  판독 함수(.axiom_promotion_retired) — false 일 때만 TRUE · true · 칸 없음 · 파일 없음 · 깨진 파일 = FALSE(종전 동작)
#   B  배선 — 주간 스윕의 후보 목록이 그 판독 아래에서 비워진다 · 수확(lcode_harvester)은 판독과 무관하게 돈다
#   C  운영 설정 — 두 칸이 처분대로(false) · 처분 근거 문서가 실재
#   (주입 훅 쪽 스위치는 08_Tests/hooks/test_axiom_inject_tau_d.sh §G 가 잰다)
#
# 방식: 소스에서 함수를 꺼내 임시 루트에 대고 실행. 운영 파일은 읽기만.

suppressPackageStartupMessages(library(jsonlite))
.self <- tryCatch({
  a <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", a[grepl("^--file=", a)])
  if (length(f)) dirname(f[1]) else "."
}, error = function(e) ".")
root <- file.path(.self, "..", "..")
if (!file.exists(file.path(root, "02_Infrastructure", "config.R")))
  root <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
root <- gsub("\\\\", "/", root)

pass <- 0L; fail <- 0L
ok <- function(m) { cat(sprintf("  [PASS] %s\n", m)); pass <<- pass + 1L }
ng <- function(m) { cat(sprintf("  [FAIL] %s\n", m)); fail <<- fail + 1L }
chk <- function(cond, m) if (isTRUE(cond)) ok(m) else ng(m)
done <- function() {
  cat(sprintf('{"test":"axiom_engine_status_switch","pass":%d,"fail":%d,"total":%d}\n', pass, fail, pass + fail))
  if (sys.nframe() == 0L) quit(save = "no", status = if (fail > 0L) 1L else 0L)
}

SWEEP <- file.path(root, "02_Infrastructure", "ops", "weekly_cleaner_sweep.R")
STAT  <- file.path(root, "06_Registry", "axiom_engine_status.json")
if (!file.exists(SWEEP)) { ng("주간 스윕 소스 부재"); done() } else {
  src <- readLines(SWEEP, warn = FALSE, encoding = "UTF-8")
  i0 <- grep("^\\.axiom_promotion_retired <- function\\(root\\) \\{", src)
  if (length(i0) != 1L) { ng("A0 판독 함수 정의가 정확히 1개여야 한다"); done() } else {
    j <- i0; while (j <= length(src) && src[j] != "}") j <- j + 1L
    E <- new.env(parent = globalenv()); eval(parse(text = src[i0:j], keep.source = FALSE), envir = E)
    f <- E$.axiom_promotion_retired
    mk <- function(txt) { r <- file.path(tempdir(), sprintf("axst_%d_%d", Sys.getpid(), as.integer(runif(1, 1, 1e6))))
      dir.create(file.path(r, "06_Registry"), recursive = TRUE); if (!is.null(txt)) writeLines(txt, file.path(r, "06_Registry", "axiom_engine_status.json")); r }
    cat("== A 판독 함수 ==\n")
    chk(isTRUE(f(mk('{"promotion_enabled": false}'))), "A1 promotion_enabled = false → 퇴역(TRUE)")
    chk(identical(f(mk('{"promotion_enabled": true}')), FALSE), "A2 true → 종전 동작")
    chk(identical(f(mk('{"inject_variable_part": false}')), FALSE), "A3 칸 없음 → 종전 동작(다른 칸으로 추론하지 않는다)")
    chk(identical(f(mk(NULL)), FALSE), "A4 파일 없음 → 종전 동작")
    chk(identical(f(mk('{broken')), FALSE), "A5 깨진 파일 → 종전 동작(스윕이 죽지 않는다)")
    chk(identical(f(mk('{"promotion_enabled": "false"}')), FALSE), "A6 문자열 \"false\" 는 받지 않는다(논리값만)")

    cat("== B 배선 ==\n")
    g <- grep("if (.axiom_promotion_retired(root)) {", src, fixed = TRUE)
    chk(length(g) == 1L && any(grepl("cands <- character(0)", src[g:min(length(src), g + 4L)], fixed = TRUE)), "B1 판독 아래에서 후보 목록을 비운다(1곳)")
    h <- grep('for (scr in c("lcode_harvester.py", "cluster_extractor.py"))', src, fixed = TRUE)
    chk(length(h) == 1L && length(g) == 1L && h < g, "B2 수확은 판독 앞에서 돈다(기록 · 조회 층은 닫지 않는다)")
    lp <- grep("for (pre_cand in cands)", src, fixed = TRUE)
    chk(length(lp) == 1L && length(g) == 1L && g < lp, "B3 판독이 후보 순회(사전판정 · dry-run · promote)보다 앞에 있다")

    cat("== C 운영 설정 ==\n")
    st <- tryCatch(fromJSON(STAT, simplifyVector = FALSE), error = function(e) NULL)
    chk(!is.null(st) && identical(st$promotion_enabled, FALSE) && identical(st$inject_variable_part, FALSE), "C1 운영 설정 두 칸 = false(v10.2 처분)")
    ev <- if (!is.null(st)) sub(" §.*$", "", as.character(st$evidence)) else ""
    chk(nzchar(ev) && file.exists(file.path(root, ev)), "C2 처분 근거 문서가 실재한다")
    chk(isTRUE(f(root)), "C3 운영 루트에서 판독 = 퇴역")
    done()
  }
}
