#!/usr/bin/env Rscript
#==============================================================================
# test_mvo_doc_default_parity.R — mvo_weights 주석 기본값 ↔ 서명 기본값 정합
#
# 배경 (2026-08-20):
#   mean_variance_optimizer.R 의 인자 설명 주석이 서명과 4개 필드에서 갈려 있었다:
#     주석 bounds c(0,0.10) / max_names 20 / min_names 15L / hhi_cap 0.10
#     서명 bounds c(0,0.15) / max_names 25 / min_names 20L / hhi_cap 0.15
#   코드가 실행되므로 동작은 정상이었으나, **이 주석을 읽고 인자를 명시할지 판단하면 틀린다**.
#   (도훈 mandate 2026-05-29 의 20→25 가 주석까지 따라오지 않은 것이 시작점.)
#
# 이 검사가 지키는 것 — 주석은 파생할 수 없으므로(사람이 쓰는 산문) **드리프트를 금지**한다.
#   [A] 서명 기본값이 주석 줄에 실제로 등장하는가 (정합)
#   [B] ★위반 주입 — 서명 값을 바꾼 사본에서 검사가 FAIL 하는가 (검출력)
#   ★값은 정규식이 아니라 R 파서(formals())에서 읽는다 — 서명 형식이 바뀌어도 안 깨진다.
#==============================================================================
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
SRC  <- file.path(ROOT, "02_Infrastructure/portfolio/mean_variance_optimizer.R")

PASS <- 0L; FAIL <- 0L
ok <- function(m) { PASS <<- PASS + 1L; cat(sprintf("  PASS  %s\n", m)) }
ng <- function(m) { FAIL <<- FAIL + 1L; cat(sprintf("  FAIL  %s\n", m)) }

# 주석에서 확인할 인자 (서명 기본값을 문자열로 만들어 주석 줄에 포함되는지 본다)
PARAMS <- c("max_names", "min_names", "hhi_cap", "alpha_winsor", "bounds")

check_parity <- function(path, label) {
  env <- new.env()
  okp <- tryCatch({ sys.source(path, envir = env); TRUE },
                  error = function(e) { ng(sprintf("[%s] source 실패: %s", label, conditionMessage(e))); FALSE })
  if (!okp) return(NA)
  if (!exists("mvo_weights", envir = env)) { ng(sprintf("[%s] mvo_weights 부재", label)); return(NA) }
  fm <- formals(get("mvo_weights", envir = env))
  lines <- readLines(path, warn = FALSE, encoding = "UTF-8")
  n_bad <- 0L
  for (p in PARAMS) {
    if (!p %in% names(fm)) next
    val <- fm[[p]]
    # 서명 기본값을 사람이 읽는 형태로 (예: 25 / 20L / 0.15 / c(0, 0.15))
    txt <- paste(deparse(val), collapse = "")
    txt <- gsub(" ", "", txt, fixed = TRUE)
    doc <- grep(paste0("^#   ", p, ":"), lines, value = TRUE)
    if (!length(doc)) { n_bad <- n_bad + 1L; cat(sprintf("      %s: 주석 줄 부재\n", p)); next }
    docn <- gsub(" ", "", doc[1], fixed = TRUE)
    # 숫자 리터럴 비교: 20L 은 주석에 20L 또는 20 으로 쓰일 수 있어 양쪽 허용
    alt <- sub("L", "", txt, fixed = TRUE)
    hit <- grepl(txt, docn, fixed = TRUE) || grepl(alt, docn, fixed = TRUE)
    if (!hit) { n_bad <- n_bad + 1L; cat(sprintf("      %s: 서명=%s 인데 주석=%s\n", p, txt, doc[1])) }
  }
  n_bad
}

cat("== [A] 현행 정합 ==\n")
bad <- check_parity(SRC, "current")
if (is.na(bad)) ng("판정 불가") else if (bad == 0L) ok("서명 기본값 5종이 주석과 정합") else
  ng(sprintf("주석↔서명 불일치 %d건 — 문서 낙후", bad))

cat("== [B] 위반 주입 — 서명 값을 바꾸면 잡히는가 ==\n")
TMP <- file.path(ROOT, ".cache", "_test_mvo_parity")
unlink(TMP, recursive = TRUE); dir.create(TMP, recursive = TRUE, showWarnings = FALSE)
mut <- file.path(TMP, "mvo_mut.R")
src <- readLines(SRC, warn = FALSE, encoding = "UTF-8")
i <- grep("^                         max_names = 25,$", src)
if (!length(i)) {
  ng("[선행검증] 서명 줄을 못 찾음 — 이 축 판정 불가(패턴이 원문과 어긋남)")
} else {
  ok("[선행검증] 서명 줄 위치 확인")
  src[i[1]] <- "                         max_names = 99,"
  writeLines(src, mut, useBytes = TRUE)
  bad2 <- check_parity(mut, "mutant")
  if (is.na(bad2)) ng("돌연변이 판정 불가") else if (bad2 >= 1L)
    ok(sprintf("서명 변조를 검출 (불일치 %d건) — 검출력 실재", bad2)) else
    ng("서명을 바꿨는데 통과 — 검사 사망")
}
unlink(TMP, recursive = TRUE)

cat(sprintf("\n== 결과: %d PASS / %d FAIL ==\n", PASS, FAIL))
# 2026-08-20: 배터리는 마지막 유효 JSON 줄만 읽는다 — 이 줄이 없어 UNREPORTED(=1 fail)로
#   계상됐다(내부는 전건 통과). 계약 결측이지 결함이 아님.
cat(sprintf("{\"test\":\"mvo_doc_default_parity\",\"pass\":%d,\"fail\":%d,\"total\":%d}
", PASS, FAIL, PASS + FAIL))
if (FAIL > 0L) quit(status = 1L)
