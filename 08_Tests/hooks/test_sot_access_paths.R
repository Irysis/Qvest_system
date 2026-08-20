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

cat("== [E] 별칭 추적 (2026-08-20 추가) ==
")
# ★ON/OFF 대조가 본체 — ON 만 재면 "원래 잡히던 것"과 구별이 안 된다.
#   worktask_manager.R 은 별칭 재접근이 0건이라 실제 파일로는 이 축을 실증할 수 없어
#   전용 픽스처를 쓴다(2단 체인 포함).
FX <- file.path(ROOT, ".cache", "_test_alias_fx")
unlink(FX, recursive = TRUE); dir.create(FX, recursive = TRUE, showWarnings = FALSE)
fx <- file.path(FX, "fx.R")
writeLines(c(
  'defaults <- fromJSON("x.json")',
  'ts <- defaults$tier_soft_deployment',
  'a <- ts$max_names',
  'b <- ts[["weight_bounds"]]',
  'inner <- defaults[["tier_hard_mandate"]]',
  'c2 <- inner$liquidity_floor_won_20d_avg',
  'deep <- ts$beta_target_tier',
  'd2 <- deep$MEDIUM'), fx, useBytes = TRUE)
if (file.exists(fx)) ok("[선행검증] 픽스처 생성 확인") else ng("[선행검증] 픽스처 생성 실패")
pon  <- extract_paths(fx, "defaults", follow_alias = TRUE)
poff <- extract_paths(fx, "defaults", follow_alias = FALSE)
want <- c("defaults$tier_soft_deployment$max_names",
          "defaults$tier_soft_deployment$weight_bounds",
          "defaults$tier_hard_mandate$liquidity_floor_won_20d_avg",
          "defaults$tier_soft_deployment$beta_target_tier$MEDIUM")
nbad <- 0L
for (w in want) if (!(w %in% pon)) { nbad <- nbad + 1L; cat("      ON 미검출:", w, "
") }
if (nbad == 0L) ok(sprintf("별칭 경유 4종 전부 검출 (2단 체인 포함, ON=%d)", length(pon))) else
  ng(sprintf("별칭 추적 %d건 미검출", nbad))
nleak <- sum(want %in% poff)
if (nleak == 0L) ok(sprintf("OFF 에서는 전부 미검출 (OFF=%d) - ON/OFF 대조 성립", length(poff))) else
  ng(sprintf("OFF 인데 %d건 검출 - 대조 무효(원래 잡히던 것)", nleak))
unlink(FX, recursive = TRUE)

cat("== [F] 재할당 무효화 (2026-08-20 추가) ==
")
# ★python 판에서 실결함으로 적발된 축을 R 에도 고정한다.
#   deployed_holdings_check.py:85 `t = pq.read_table(...)` 가 별칭 t 를 덮어쓰는데
#   추출기가 계속 정본 별칭으로 봐서 $Date 를 허위 추출했다. R 판도 같은 결함이었다.
#   ⚠수리 직후 반대 방향도 재야 한다 — 무효화를 넣자 과잉 교정으로 정당 접근까지 죽었다.
RX <- file.path(ROOT, ".cache", "_test_realias")
unlink(RX, recursive = TRUE); dir.create(RX, recursive = TRUE, showWarnings = FALSE)
rf <- file.path(RX, "fx.R")
writeLines(c(
  'defaults <- fromJSON("x.json")',
  'ts <- defaults$tier_soft_deployment',
  'a <- ts$max_names',
  'ts <- read.csv("other.csv")',
  'b <- ts$SomeColumn'), rf, useBytes = TRUE)
if (file.exists(rf)) ok("[선행검증] 재할당 픽스처 생성") else ng("[선행검증] 픽스처 실패")
pr <- extract_paths(rf, "defaults")
if (!("defaults$tier_soft_deployment$SomeColumn" %in% pr))
  ok("재할당 후 접근이 오탐으로 안 들어감") else
  ng("재할당 무효화 미작동 - 다른 값의 필드가 정본 경로로 잡힘")
if ("defaults$tier_soft_deployment$max_names" %in% pr)
  ok("재할당 *이전* 정당 접근은 보존 (과잉 교정 아님)") else
  ng("과잉 교정 - 재할당 이전 접근까지 죽었다")
unlink(RX, recursive = TRUE)

cat("== [D] 소비면 산출 스모크 ==
")
r <- sot_unconsumed(SOT, list(c(SRC, "defaults")))
if (r$n_leaf > 0 && r$n_consumed > 0)
  ok(sprintf("리프 %d 중 소비 %d - 미소비 %d건 후보", r$n_leaf, r$n_consumed, length(r$unconsumed))) else
  ng("소비면 산출 실패")

cat(sprintf("
== 결과: %d PASS / %d FAIL ==
", PASS, FAIL))
# 2026-08-20: 배터리는 마지막 유효 JSON 줄만 읽는다 — 이 줄이 없어 UNREPORTED(=1 fail)로
#   계상됐다(내부는 전건 통과). 계약 결측이지 결함이 아님.
cat(sprintf("{\"test\":\"sot_access_paths\",\"pass\":%d,\"fail\":%d,\"total\":%d}
", PASS, FAIL, PASS + FAIL))
if (FAIL > 0L) quit(status = 1L)
