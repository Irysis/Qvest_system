#!/usr/bin/env Rscript
#==============================================================================
# test_rf_avoid_target.R — 기전 회피 **표적 판정** 양방향 검사 (2026-09-05)
#
# 왜 이 검사가 있는가 (실사고 2026-09-05 09:14 · promo2 B2 첫 칸):
#   ① 집행부가 att$n 을 등록(att <- rf_append_attempt) **전에** 읽어 러너가 fatal 로 죽었다 —
#      8분마다 같은 자리에서 반복되는 결정론적 정지(재개 장치에 출구 없음).
#   ② 죽지 않았다면 더 나빴다: 표적 판정이 "셀 코드가 문장 어디에든 있는가" 라서 조부모 B4
#      회피문("세 칸이 전부 B2_6 아래이고 … 생존편향")이 손자 B2_6(CDaR_LP · 설계 머리 칸)을
#      측정 무효로 잡아 **조용히 미측정**으로 남겼을 것이다(reinforce §0.3 위반).
#      같은 규칙은 B3_11 회피문의 "B3_13 이 대체한다" 로 **권고 칸**까지 건너뛴다.
#
# 판정 축 (실사고 문장이 픽스처 — 실물 L-code 에서 읽고, 없으면 인라인 사본):
#   A1 코드로 시작하는 측정 무효 회피는 집행 (양성 대조 — 고쳐서 반대쪽을 죽이지 않았나)
#   A2 비교 기준으로 언급된 코드는 표적이 아니다 ★실사고
#   A3 같은 문장의 대체 언급(권고 칸)은 표적이 아니다
#   A4 성과 사유는 표적이어도 집행 아님(기록만 · AX-000)
#   A5 돌연변이 통제 — 구 규칙이면 실사고가 재현돼야 한다(픽스처의 판별력)
#   S1~S5 러너 정적 — 등록 전 att 참조 없음 · 헬퍼 소비 · 구 정규식 잔존 없음 · 로그 이름 보존 · parse
#
# ★배터리 등록(test_reinforce_auto.sh)은 다른 세션이 그 파일을 수리 중이라 이 판에서는 보류 —
#   단독 실행: Rscript 08_Tests/reinforcement/test_rf_avoid_target.R
#==============================================================================
suppressMessages(library(jsonlite))
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
PASS <- 0L; FAIL <- 0L
ok <- function(m) { PASS <<- PASS + 1L; cat("  OK  ", m, "\n") }
ng <- function(m, why = "") { FAIL <<- FAIL + 1L; cat("  FAIL", m, if (nzchar(why)) paste0(" — ", why) else "", "\n") }
.done <- function() {
  cat(sprintf("\n합계: 통과 %d · 실패 %d\n", PASS, FAIL))
  cat(sprintf('{"test":"rf_avoid_target","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
  quit(status = if (FAIL == 0L) 0L else 1L)
}

hp <- file.path(ROOT, "02_Infrastructure/reinforcement/rf_avoid.R")
rp <- file.path(ROOT, "02_Infrastructure/ops/reinforce_auto_parallel.R")

cat("=== 0. 헬퍼 적재 ===\n")
h <- tryCatch({ source(hp, local = TRUE, encoding = "UTF-8"); TRUE },
              error = function(e) { ng("rf_avoid.R source", conditionMessage(e)); FALSE })
if (!h) .done()
ok("rf_avoid.R 적재")

## 픽스처 — 실사고 문장을 실물 L-code 에서 읽는다 (없으면 인라인 사본)
LCD <- file.path(ROOT, "stage_artifacts/l_code/reinforcement")
GP  <- "RP_20260904_163647_18444_rescued_rulefast"
.avoid_of <- function(base, blk) {
  f <- file.path(LCD, sprintf("l_code_%s_%s.json", base, blk))
  if (!file.exists(f)) return(character(0))
  as.character(unlist(tryCatch(fromJSON(f, simplifyVector = TRUE)$avoid, error = function(e) NULL)))
}
fx_b4 <- .avoid_of(GP, "B4"); fx_b4 <- fx_b4[grepl("B2_6", fx_b4, fixed = TRUE)]
fx_b2 <- .avoid_of(GP, "B2"); fx_b2 <- fx_b2[grepl("B3_11", fx_b2, fixed = TRUE)]
src_b4 <- if (length(fx_b4)) "실물" else "인라인"; src_b2 <- if (length(fx_b2)) "실물" else "인라인"
if (!length(fx_b4)) fx_b4 <- "소형 유니버스(시총 0~33 분위) 위에서 결합 칸 추가 — 세 칸이 전부 B2_6 아래이고, 2015-07 분리 전에는 어떤 값도 생존편향과 분리되지 않는다."
if (!length(fx_b2)) fx_b2 <- "B3_11(KOSDAQ150 단독) — 2015-07 이전 KQ150 멤버십이 퇴출 미기록 누적 명부(C6 상방 편의)라 단독 유니버스는 그 결함이 100% 가 된다. 벽이 아니라 측정 무효 사유이며 근거는 이 블록 밖(KQ150 백필 카드)이다. 소형 축은 B3_13(시총 하위 1/3)이 Size 기반 우회로 대체한다."
fx_b4 <- fx_b4[[1L]]; fx_b2 <- fx_b2[[1L]]
cat(sprintf("  픽스처 출처: B4=%s · B2=%s\n", src_b4, src_b2))

cat("=== 1. 양성 대조 — 코드로 시작하는 측정 무효 회피는 집행 ===\n")
r1 <- rf_avoid_target(fx_b2, "B3_11")
if (!is.null(r1$hit)) ok("A1 B3_11 선례 → hit") else ng("A1 B3_11 선례를 못 잡는다", "고쳐서 반대쪽을 죽였다")

cat("=== 2. 실사고 — 비교 기준으로 언급된 코드는 표적이 아니다 ===\n")
r2 <- rf_avoid_target(fx_b4, "B2_6")
if (is.null(r2$hit) && !length(r2$noted)) ok("A2 조부모 B4 문장이 손자 B2_6 을 안 잡는다 ★실사고") else
  ng("A2 B2_6 오판 재현", "설계 머리 칸이 미결로 빈다")

cat("=== 3. 권고 칸 — 같은 문장의 대체 언급은 표적이 아니다 ===\n")
r3 <- rf_avoid_target(fx_b2, "B3_13")
if (is.null(r3$hit) && !length(r3$noted)) ok("A3 B3_13(권고) 을 안 잡는다") else ng("A3 권고 칸 B3_13 을 회피로 오판")

cat("=== 4. 성과 사유 — 표적이지만 집행 아님(기록만) ===\n")
r4 <- rf_avoid_target(c("B5_19 dd_brake_q 재측정 — CAGR 0.174 로 비례 반납, 상한 관측됨", fx_b4), "B5_19")
if (is.null(r4$hit) && length(r4$noted) == 1L) ok("A4 성과 사유 → noted 1 · hit 0") else ng("A4 성과 사유를 집행하거나 기록을 놓친다")

cat("=== 5. 판별력 — 구 규칙이면 실사고가 재현돼야 한다 (돌연변이 통제) ===\n")
old_hit <- grepl(sprintf("(^|[^A-Za-z0-9_])%s([^0-9]|$)", "B2_6"), fx_b4) && grepl(RF_AVOID_INVALID_RE, fx_b4)
if (isTRUE(old_hit)) ok("A5 구 규칙은 B2_6 을 잡는다 → 픽스처가 결함을 가른다") else
  ng("A5 픽스처가 구 규칙에서도 안 잡힌다", "검사가 아무것도 못 가른다")

cat("=== 6. 러너 정적 ===\n")
src  <- readLines(rp, encoding = "UTF-8", warn = FALSE)
use  <- which(grepl("att$n", src, fixed = TRUE))
defn <- which(startsWith(trimws(src), "att <- tryCatch(rf_append_attempt"))
if (length(defn) == 1L && length(use) && min(use) > defn)
  ok(sprintf("S1 att$n 첫 사용 %d행 > 정의 %d행", min(use), defn)) else ng("S1 att 를 정의 전에 읽는다 ★실사고(fatal)")
if (any(grepl("reinforcement/rf_avoid.R", src, fixed = TRUE)) && any(grepl("rf_avoid_target(", src, fixed = TRUE)))
  ok("S2 러너가 rf_avoid.R 을 source 하고 rf_avoid_target 을 부른다") else ng("S2 헬퍼가 죽은 사본이다")
if (!any(grepl("(^|[^A-Za-z0-9_])%s([^0-9]|$)", src, fixed = TRUE))) ok("S3 구 무앵커 정규식 잔존 없음") else ng("S3 구 정규식이 남아 있다")
if (any(grepl("avoid_enforced", src, fixed = TRUE)) && any(grepl("avoid_noted", src, fixed = TRUE)) && any(grepl("AX-000", src, fixed = TRUE)))
  ok("S4 avoid_enforced·avoid_noted·AX-000 보존(schema 검사 G1·G2 생존)") else ng("S4 로그 이름이 사라졌다")
pz <- tryCatch({ parse(file = rp, encoding = "UTF-8"); TRUE }, error = function(e) { ng("S5 러너 parse", conditionMessage(e)); FALSE })
if (pz) ok("S5 러너 parse")
.done()
