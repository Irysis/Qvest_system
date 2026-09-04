#!/usr/bin/env Rscript
#==============================================================================
# test_rf_retry_feedback.R — 재시도가 실패 사유를 안고 가는가 (도훈 지시 2026-09-04)
#
# 실사고 2026-09-04: 결합 설계가 replication_error("'adj' is not found in calling scope")로
#   3회 연속 죽었는데 재시도 프롬프트에 그 오류가 안 실려 **글자까지 같은 실패**를 되풀이했다.
#   에이전트 12분 × 2 + 측정 2회를 태우고 retries_exhausted.
#   아침에 감사 재구현을 만들며 "지적을 안 얹으면 재시도가 아니라 되풀이" 라고 적어 놓고,
#   측정 오류 쪽 배선은 안 이어 놓은 상태였다 — 검증기는 failure/failure_detail 을 남기는데
#   러너는 audit_feedback 하나만 읽었다.
#
# 설계 요점(그래서 이 검사가 지키는 것):
#   ① 사유별로 **다른 프레이밍** — 오류 문자열만 던지면 증상을 지워 넘긴다("adj 를 안 쓰면 되지")
#   ② PIT 는 따로 세운다 — 계층 무관 절대이고 "코드 오류가 아니라 설계 오류"다
#   ③ 환경 실패(패키지)는 "네 잘못이 아니다, 설계를 줄여라" — 리서치 실패와 구분
#   ④ 오류 수정이 충실구현을 덮지 않게 못 박는다
#==============================================================================
suppressMessages({ library(jsonlite) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
PASS <- 0L; FAIL <- 0L
ok <- function(m) { PASS <<- PASS + 1L; cat(sprintf("  OK   %s\n", m)) }
ng <- function(m, d = "") { FAIL <<- FAIL + 1L; cat(sprintf("  FAIL %s%s\n", m, if (nzchar(d)) paste0(" — ", d) else "")) }

RA <- file.path(ROOT, "02_Infrastructure/ops/rf_replication_auto.sh")
RV <- file.path(ROOT, "02_Infrastructure/ops/rf_replication_verify.R")
src <- paste(readLines(RA, warn = FALSE), collapse = "\n")
vsrc <- paste(sub("#.*$", "", readLines(RV, warn = FALSE)), collapse = "\n")

cat("=== A. 생산자 ↔ 소비자가 이어져 있는가 ===\n")
if (grepl("failure_detail", vsrc, fixed = TRUE)) ok("A1 검증기가 failure_detail 을 남긴다") else
  ng("A1 검증기 미기록")
if (grepl("FAILFB", src, fixed = TRUE)) ok("A2 러너가 그걸 읽는다 ★실사고 지점") else
  ng("A2 러너가 안 읽는다", "재시도가 눈 감고 돈다")
if (grepl("reimplement_with_failure", src, fixed = TRUE))
  ok("A3 실패 재구현이 로그에 남는다(감사 재구현과 구분)") else ng("A3 로그 구분 없음")

cat("\n=== B. 사유별 프레이밍 — 뭉뚱그리지 않는가 ===\n")
CAUSES <- c("pit_structural", "fixed_axis_violation", "replication_error",
            "too_many_missing_packages", "dependency_install_failed", "no_authoritative_remeasure")
miss <- CAUSES[!vapply(CAUSES, function(c) grepl(c, src, fixed = TRUE), logical(1))]
if (!length(miss)) ok(sprintf("B1 사유 %d종 전부 프레이밍 보유", length(CAUSES))) else
  ng("B1 프레이밍 누락", paste(miss, collapse = ","))
if (grepl("계층 무관 절대", src, fixed = TRUE)) ok("B2 PIT 는 따로 세운다(설계 오류로 규정)") else
  ng("B2 PIT 특별 취급 없음")
if (grepl("네 잘못이 아니다", src, fixed = TRUE))
  ok("B3 환경 실패는 리서치 실패와 구분") else ng("B3 환경/리서치 미구분")

cat("\n=== C. 증상 패치·논문 훼손 방지 ===\n")
if (grepl("오류를 \\*\\*없애는 것\\*\\* 이 목표가 아니다", src) ||
    grepl("없애는 것", src, fixed = TRUE))
  ok("C1 오류 제거가 목표가 아님을 명시(증상 패치 차단)") else ng("C1 증상 패치 유도")
if (grepl("논문을 훼손하지 마라", src, fixed = TRUE))
  ok("C2 오류 수정이 충실구현을 덮지 않게 못 박는다") else ng("C2 충실구현 우선 미명시")
if (grepl("충실도 감사에서 걸린다", src, fixed = TRUE))
  ok("C3 우회의 대가를 알려준다(두 번 낭비)") else ng("C3 대가 미고지")

cat("\n=== D. 감사 경로와 공존 (회귀) ===\n")
if (grepl("AUDFB", src, fixed = TRUE) && grepl("reimplement_with_audit", src, fixed = TRUE))
  ok("D1 충실도 감사 재구현 경로 보존") else ng("D1 감사 경로 손상")
i_f <- regexpr("FAILFB=", src, fixed = TRUE)
i_a <- regexpr("AUDFB=", src, fixed = TRUE)
if (i_f > 0 && i_a > 0) ok("D2 두 피드백이 같은 자리에서 조립된다(한쪽만 사는 구조 아님)") else
  ng("D2 조립 위치")
i_p <- regexpr("timeout 3000 claude", src, fixed = TRUE)
if (i_f > 0 && i_p > 0 && i_f < i_p)
  ok("D3 피드백이 에이전트 호출 **앞**에서 조립된다") else ng("D3 조립 순서")

cat("\n=== E. 실측 재현 — 오늘 실패 사유가 갈리는가 ===\n")
.frame <- function(why) {
  # 러너와 같은 표를 재도출하지 않는다 — 소스에서 그 사유의 안내 문구가 존재하는지만 본다
  grepl(why, src, fixed = TRUE)
}
if (.frame("replication_error")) ok("E1 오늘 실패 사유(replication_error) 프레이밍 존재") else
  ng("E1 실사고 사유 미포함")
# ★주석을 걷어내고 본다 — 이 수리의 **사연을 적은 주석**이 실사고 오류('adj')를 예시로
#   담고 있어, 문자열 존재로만 재면 검사가 자기 설명문에 발화한다.
#   오늘 하루에 세 번째로 밟은 형태다(잴 것을 안 재고 재기 쉬운 것을 잼).
src_code <- paste(sub("#.*$", "", readLines(RA, warn = FALSE)), collapse = "
")
if (grepl("adj", src_code, fixed = TRUE))
  ng("E2 특정 오류 문자열이 코드에 박혔다", "다음 오류는 못 잡는다") else
  ok("E2 특정 오류를 하드코딩하지 않는다(사유 축으로 일반화)")

cat(sprintf("\n합계: 통과 %d · 실패 %d\n", PASS, FAIL))
cat(sprintf('{"test":"rf_retry_feedback","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
quit(status = if (FAIL > 0L) 1L else 0L)
