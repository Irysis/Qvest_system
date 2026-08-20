#!/usr/bin/env Rscript
# test_sot_access_paths.R - AST 기반 정본 소비 경로 추출기의 3축 대조
#   배경: 같은 질문에 토큰 grep 이 6번 실패했다(표기 형태 가정). 파서로 교체한 것이 본 도구.
#   [A] 양성 대조 - 추출 경로가 정본에 실재하는가 (허위 추출 0)
#   [B] 음성 대조 - 존재하지 않는 뿌리로는 0건 (무차별 매칭 아님)
#   [C] 위반 주입 - 새 접근을 넣으면 잡히는가 (검출력). 조작 선행검증 포함.
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
source("02_Infrastructure/ops/sot_access_paths.R")
suppressWarnings(suppressMessages(library(jsonlite)))
PASS <- 0L; FAIL <- 0L
ok <- function(m) { PASS <<- PASS + 1L; cat(sprintf("  PASS  %s
", m)) }
ng <- function(m) { FAIL <<- FAIL + 1L; cat(sprintf("  FAIL  %s
", m)) }

SOT <- "02_Infrastructure/worktask/constraint_defaults.json"
SRC <- "02_Infrastructure/worktask/worktask_manager.R"
d <- fromJSON(SOT, simplifyVector = FALSE)
p <- extract_paths(SRC, "defaults")

cat("== [A] 양성 대조 ==
")
if (length(p) >= 10) ok(sprintf("경로 %d건 추출 (>=10)", length(p))) else ng(sprintf("추출 %d건 - 너무 적음", length(p)))
v <- verify_paths_exist(p, d)
if (v$ok) ok(sprintf("%d/%d 전부 정본에 실재 (허위 추출 0)", length(p), length(p))) else
  ng(sprintf("정본 부재 %d건: %s", length(v$missing), paste(head(v$missing,3), collapse=", ")))
# 표기 정규화: [[ ]] 로 쓴 접근도 $ 경로로 모여야 한다
if ("defaults$tier_soft_deployment$max_names" %in% p)
  ok("[[ ]] 표기 접근이 $ 경로로 정규화됨 (grep 이 못 하던 것)") else
  ng("[[ ]] 표기 접근 누락 - 표기 형태에 여전히 종속")

cat("== [B] 음성 대조 ==
")
p0 <- extract_paths(SRC, "NOSUCHVAR_zzz")
if (length(p0) == 0L) ok("가짜 뿌리 -> 0건 (무차별 매칭 아님)") else ng(sprintf("가짜 뿌리인데 %d건 - 오탐", length(p0)))

cat("== [C] 위반 주입 ==
")
TMP <- file.path(ROOT, ".cache", "_test_sot_ast")
unlink(TMP, recursive = TRUE); dir.create(TMP, recursive = TRUE, showWarnings = FALSE)
src <- readLines(SRC, warn = FALSE, encoding = "UTF-8")
i <- grep("defaults <- fromJSON", src)[1]
if (is.na(i)) {
  ng("[선행검증] 로드 줄 미발견 - 이 축 판정 불가")
} else {
  ok(sprintf("[선행검증] 로드 줄 %d 확인", i))
  inj <- "  .probe <- defaults$tier_graduation$severity$calmar"
  src2 <- append(src, inj, after = i)
  mf <- file.path(TMP, "mut.R"); writeLines(src2, mf, useBytes = TRUE)
  if (length(readLines(mf, warn=FALSE)) == length(src) + 1L)
    ok("[선행검증] 주입이 실제로 파일을 바꿈") else ng("[선행검증] 주입 미반영 - 판정 불가")
  p2 <- extract_paths(mf, "defaults")
  if ("defaults$tier_graduation$severity$calmar" %in% p2)
    ok(sprintf("주입 경로 검출 (%d -> %d) - 검출력 실재", length(p), length(p2))) else
    ng("주입했는데 미검출 - 검사 사망")
}
unlink(TMP, recursive = TRUE)

cat("== [D] 소비면 산출 스모크 ==
")
r <- sot_unconsumed(SOT, list(c(SRC, "defaults")))
if (r$n_leaf > 0 && r$n_consumed > 0)
  ok(sprintf("리프 %d 중 소비 %d - 미소비 %d건 후보", r$n_leaf, r$n_consumed, length(r$unconsumed))) else
  ng("소비면 산출 실패")

cat(sprintf("
== 결과: %d PASS / %d FAIL ==
", PASS, FAIL))
if (FAIL > 0L) quit(status = 1L)
