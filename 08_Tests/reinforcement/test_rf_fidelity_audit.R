#!/usr/bin/env Rscript
#==============================================================================
# test_rf_fidelity_audit.R — 적대적 충실도 감사 (2026-09-04)
#
# 배경: 검증 4관문은 전부 산출물(계약·고정축·PIT·원장)을 본다. "논문대로 구현했는가" 만
#   재도출이 없었고 FIDELITY.json 은 에이전트의 진술이었다 — 2608.23944 는 하지도 않은
#   변경을 스스로 신고했고 원문 대조로만 잡혔다.
#   ★값어치는 A등급 보호가 아니라 **F 판정의 신뢰**다: F 면 ledger_consumed 로 논문이
#   영구 소비되므로, 구현이 틀려서 F 였다면 논문이 잘못된 이유로 버려진다.
#   ⇒ 그래서 이 검사에서 가장 중요한 항목은 **감사가 소비보다 앞에 서는가**(C절)다.
#
# 양방향: 정상 판정은 통과하는가 + 근거 없는 기각·형식 위반을 실제로 잡는가.
#==============================================================================
suppressMessages({ library(jsonlite) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
PASS <- 0L; FAIL <- 0L
ok <- function(m) { PASS <<- PASS + 1L; cat(sprintf("  OK   %s\n", m)) }
ng <- function(m, d = "") { FAIL <<- FAIL + 1L; cat(sprintf("  FAIL %s%s\n", m, if (nzchar(d)) paste0(" — ", d) else "")) }

LIB <- file.path(ROOT, "02_Infrastructure/ops/rf_fidelity_audit_lib.R")
suppressMessages(source(LIB, local = TRUE))
TMP <- file.path(tempdir(), sprintf("fid_audit_%d", Sys.getpid()))
dir.create(TMP, recursive = TRUE, showWarnings = FALSE)
on.exit(unlink(TMP, recursive = TRUE, force = TRUE), add = TRUE)
AP <- file.path(TMP, "fidelity_audit.json")
wr <- function(x) write(toJSON(x, auto_unbox = TRUE, null = "null"), AP)

cat("=== A. 스키마 — 정상 판정은 통과한다 (음성 대조) ===\n")
for (v in c("faithful", "adapted", "unverifiable")) {
  wr(list(verdict = v, note = "n"))
  if (isTRUE(rf_audit_verify(AP))) ok(sprintf("A verdict=%s 통과", v)) else ng(sprintf("A verdict=%s 기각됨", v))
}
wr(list(verdict = "misdeclared", undeclared_changes = list("논문은 J=6 인데 구현은 J=12"),
        evidence = "§3.1 식 (2)"))
if (isTRUE(rf_audit_verify(AP))) ok("A 근거 있는 misdeclared 통과") else ng("A 근거 있는 misdeclared 가 기각됨")

cat("\n=== B. 위반 주입 — 형식과 근거 ===\n")
wr(list(verdict = "looks_fine", note = "n"))
if (!isTRUE(rf_audit_verify(AP))) ok("B1 허용값 아닌 verdict 기각") else ng("B1 임의 verdict 통과")
wr(list(verdict = "misdeclared", note = "느낌상 다름"))
if (!isTRUE(rf_audit_verify(AP))) ok("B2 지적 0건 misdeclared 기각(근거 없는 기각은 잡음)") else
  ng("B2 근거 없는 기각이 통과")
wr(list(verdict = "misdeclared", signal_mismatch = list("부호가 반대")))
if (!isTRUE(rf_audit_verify(AP))) ok("B3 evidence 없는 misdeclared 기각") else ng("B3 원문 근거 없이 통과")
writeLines("{not json", AP)
if (!isTRUE(rf_audit_verify(AP))) ok("B4 파손 JSON 기각") else ng("B4 파손 JSON 통과")
unlink(AP, force = TRUE)
if (identical(rf_audit_read(AP)$verdict, "unverifiable"))
  ok("B5 감사 파일 부재 = unverifiable (침묵을 통과로 읽지 않는다)") else ng("B5 부재를 통과로 읽는다")

cat("\n=== C. 처분 — 도훈 선택(자동 재구현 1회 + 소비 보류) ===\n")
d0 <- rf_audit_disposition(list(verdict = "faithful"), 0L)
if (identical(d0$action, "proceed")) ok("C1 faithful → 진행") else ng("C1 faithful 처분", d0$action)
if (identical(rf_audit_disposition(list(verdict = "unverifiable"), 0L)$action, "proceed"))
  ok("C2 unverifiable → 진행(멈추진 않는다 · 기록은 남는다)") else ng("C2 unverifiable 처분")
d1 <- rf_audit_disposition(list(verdict = "misdeclared",
                                undeclared_changes = list("u1"), signal_mismatch = list("s1"),
                                evidence = "§2"), 0L)
if (identical(d1$action, "reimplement")) ok("C3 misdeclared 초회 → 재구현") else ng("C3 초회 처분", d1$action)
if (grepl("미신고 변경", d1$feedback, fixed = TRUE) && grepl("신호 불일치", d1$feedback, fixed = TRUE))
  ok("C4 지적사항이 재구현 프롬프트로 전달된다(되풀이 차단)") else ng("C4 피드백 조립")
d2 <- rf_audit_disposition(list(verdict = "misdeclared", undeclared_changes = list("u1"), evidence = "§2"), 1L)
if (identical(d2$action, "proceed_suspect"))
  ok("C5 재구현도 기각 → 소비하되 꼬리표(무한 재시도 아님)") else ng("C5 2회차 처분", d2$action)

cat("\n=== D. 조립 순서 — 감사가 **소비보다 앞**에 서는가 (이 검사의 핵심) ===\n")
vf <- readLines(file.path(ROOT, "02_Infrastructure/ops/rf_replication_verify.R"), warn = FALSE)
code <- sub("#.*$", "", vf)
i_aud <- which(grepl("rf_audit_disposition", code, fixed = TRUE))[1]
i_con <- which(grepl("ledger_consumed", code, fixed = TRUE))[1]
i_opn <- which(grepl("rf_open_entry(1L, BID", code, fixed = TRUE))[1]
if (!is.na(i_aud) && !is.na(i_con) && i_aud < i_con)
  ok(sprintf("D1 감사(%d행)가 ledger_consumed(%d행) 앞 — 잘못 구현된 논문이 소비되지 않는다", i_aud, i_con)) else
  ng("D1 감사가 소비 뒤에 있다", sprintf("aud=%s con=%s", i_aud, i_con))
if (!is.na(i_aud) && !is.na(i_opn) && i_aud < i_opn)
  ok("D2 감사가 entry 개설 앞") else ng("D2 감사가 개설 뒤")
if (any(grepl('identical(.disp$action, "reimplement")', code, fixed = TRUE)) &&
    any(grepl("quit(status = 0)", code, fixed = TRUE)))
  ok("D3 재구현이면 조기 종료 — 원장에 아무것도 열지 않는다") else ng("D3 조기 종료 배선")

cat("\n=== E. 배선 (주석 제외) ===\n")
code_of <- function(f) paste(sub("#.*$", "", readLines(file.path(ROOT, f), warn = FALSE)), collapse = "\n")
au <- code_of("02_Infrastructure/ops/rf_replication_auto.sh")
sh <- paste(readLines(file.path(ROOT, "02_Infrastructure/ops/rf_fidelity_audit.sh"), warn = FALSE), collapse = "\n")
if (grepl("audit_feedback", au, fixed = TRUE)) ok("E1 재구현 시 지적사항을 프롬프트에 얹는다") else ng("E1 피드백 미전달")
if (grepl("engine.rejected", code_of("02_Infrastructure/ops/rf_replication_verify.R"), fixed = TRUE))
  ok("E2 기각된 엔진을 남긴다(무엇이 틀렸는지 볼 수 있게)") else ng("E2 기각 엔진 폐기")
if (grepl("arxiv.org/html/", sh, fixed = TRUE))
  ok("E3 전문 경로(html 엔드포인트)를 프롬프트에 박는다 — /abs 는 초록뿐") else ng("E3 원문 경로 미지정")
if (grepl("반증하라", sh, fixed = TRUE)) ok("E4 임무가 반증이다(일치 확인이 아니라)") else ng("E4 적대적 프레이밍 부재")
if (grepl('"Bash,Agent,Edit"', sh, fixed = TRUE)) ok("E5 감사자는 엔진을 못 고친다(읽기 전용)") else ng("E5 권한 축소 부재")
if (grepl("fidelity_audit", code_of("06_Registry/reinforce_auto_config.json"), fixed = TRUE))
  ok("E6 kill switch 존재") else ng("E6 kill switch 부재")

cat(sprintf("\n합계: 통과 %d · 실패 %d\n", PASS, FAIL))
cat(sprintf('{"test":"rf_fidelity_audit","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
quit(status = if (FAIL > 0L) 1L else 0L)
