#!/usr/bin/env Rscript
#==============================================================================
# test_rf_audit_disposition_required.R — 미실행·파손 ≠ 감사자의 unverifiable (2026-09-06)
#
# 실사고 2026-09-05: 킬스위치·claude CLI 부재로 감사가 3건 안 돌았는데, rf_audit_read 의 "감사 미실행"
#   unverifiable 이 감사자의 unverifiable(원문 판독 실패)과 같은 칸(proceed)에 들어가 전부 소비·개설됐다.
#   09-06 에는 역슬래시 QM_ROOT 로 병합기가 즉사(merge_done rc=1)한 뒤에도 같은 경로로 proceed 했다.
# 술어: rf_audit_read 가 판정을 못 읽었을 때만 싣는 `reason` 의 유무. 정상 분기가 reason 을 실으면 구분이 죽는다.
# 양방향: 부재/파손 → audit_required · 감사자 unverifiable(reason 없음) → proceed(불변) ·
#         misdeclared → reimplement/proceed_suspect(회귀) · faithful/adapted → proceed ·
#         감사자 파일에 적힌 reason 필드는 옮기지 않는다 · 팬아웃 병합 산출의 중첩 reason 은 트리거가 아니다.
#==============================================================================
suppressMessages({ library(jsonlite) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
## 운영 저널 격리 (검사 픽스처가 audit_rejected 를 운영 로그에 박던 실사고 재발 방지)
Sys.setenv(QVEST_RP_JLOG = file.path(tempdir(), sprintf("rf_test_jlog_%d.jsonl", Sys.getpid())))
PASS <- 0L; FAIL <- 0L
ok <- function(m) { PASS <<- PASS + 1L; cat(sprintf("  OK   %s\n", m)) }
ng <- function(m, d = "") { FAIL <<- FAIL + 1L; cat(sprintf("  FAIL %s%s\n", m, if (nzchar(d)) paste0(" — ", d) else "")) }

suppressMessages(source(file.path(ROOT, "02_Infrastructure/ops/rf_fidelity_audit_lib.R"), local = TRUE))
TMP <- file.path(tempdir(), sprintf("fid_disp_%d", Sys.getpid()))
dir.create(TMP, recursive = TRUE, showWarnings = FALSE)
# ★최상위 on.exit 은 조용한 no-op — R 이 세션 종료 시 tempdir 을 청소한다
AP <- file.path(TMP, "fidelity_audit.json")
wr <- function(x) write(toJSON(x, auto_unbox = TRUE, null = "null"), AP)
act <- function(a, n = 0L) as.character(rf_audit_disposition(a, n)$action %||% "")

cat("=== A. 부재·파손 → audit_required (실사고 방향) ===\n")
unlink(AP, force = TRUE)
a <- rf_audit_read(AP); d <- rf_audit_disposition(a, 0L)
if (identical(d$action, "audit_required")) ok("A1 감사 파일 부재 → audit_required ★실사고") else ng("A1 부재 처분", d$action)
if (nzchar(as.character(d$reason %||% ""))) ok(sprintf("A2 사유가 실린다(%s)", d$reason)) else ng("A2 사유 없음")
writeLines("{not json", AP)
a <- rf_audit_read(AP)
if (identical(act(a), "audit_required")) ok("A3 감사 파일 파손 → audit_required") else ng("A3 파손 처분", act(a))
if (grepl("파손", as.character(a$reason %||% ""), fixed = TRUE)) ok("A4 파손 사유가 부재 사유와 구분된다") else ng("A4 파손 사유", a$reason %||% "")
unlink(AP, force = TRUE)
if (identical(act(rf_audit_read(AP), 1L), "audit_required"))
  ok("A5 재구현 뒤(retries_done=1)에도 미실행은 미실행 — proceed_suspect 로 새지 않는다") else ng("A5 재구현 후 미실행 처분")

cat("\n=== B. 감사자 자신의 unverifiable(원문 판독 실패) → proceed (불변 · 대조) ===\n")
wr(list(verdict = "unverifiable", note = "arxiv html 전문을 못 읽었다", confidence = "low"))
a <- rf_audit_read(AP)
if (is.null(a$reason)) ok("B1 정상 판독은 reason 을 싣지 않는다(술어의 반대편)") else ng("B1 정상 판독에 reason", a$reason)
if (identical(act(a), "proceed")) ok("B2 감사자 unverifiable → proceed(멈추진 않는다 · 기록은 남는다)") else ng("B2 처분", act(a))
wr(list(verdict = "unverifiable", reason = "감사 미실행", note = "감사자가 reason 필드를 적었다"))
a <- rf_audit_read(AP)
if (is.null(a$reason) && identical(act(a), "proceed"))
  ok("B3 감사자 파일의 reason 필드는 옮기지 않는다 — 미실행 술어는 판독기만 세운다") else
  ng("B3 파일의 reason 이 판독기를 통과했다", sprintf("reason=%s action=%s", a$reason %||% "NULL", act(a)))
wr(list(verdict = "unverifiable", mode = "fanout", confidence = "low",
        axis_verdicts = list(list(axis = "signal", verdict = "unverifiable", admissible = FALSE,
                                  reason = "축 미산출(레인 실패·타임아웃)"))))
a <- rf_audit_read(AP)
if (identical(act(a), "proceed"))
  ok("B4 팬아웃 병합 산출(축 행에 reason 중첩)은 감사자 판정 — proceed") else ng("B4 중첩 reason 이 트리거됐다", act(a))

cat("\n=== C. 회귀 — misdeclared·faithful·adapted 처분 불변 ===\n")
md <- list(verdict = "misdeclared",
           undeclared_changes = list("논문 §3.1 식 (2) 는 형성기간 J=6 인데 engine.R:104 는 J=12 — FIDELITY.changed 에 없음"),
           signal_mismatch = list(), evidence = "§3.1 식 (2) 및 Table 2")
wr(md); a <- rf_audit_read(AP)
if (identical(act(a, 0L), "reimplement")) ok("C1 misdeclared 초회 → reimplement") else ng("C1", act(a, 0L))
if (identical(act(a, 1L), "proceed_suspect")) ok("C2 misdeclared 2회차 → proceed_suspect") else ng("C2", act(a, 1L))
if (grepl("미신고 변경", rf_audit_disposition(a, 0L)$feedback, fixed = TRUE)) ok("C3 재구현 피드백 조립 불변") else ng("C3 피드백")
wr(list(verdict = "faithful", note = "n")); if (identical(act(rf_audit_read(AP)), "proceed")) ok("C4 faithful → proceed") else ng("C4")
wr(list(verdict = "adapted", note = "n"));  if (identical(act(rf_audit_read(AP)), "proceed")) ok("C5 adapted → proceed") else ng("C5")
wr(list(verdict = "looks_fine", note = "n")); a <- rf_audit_read(AP)
if (identical(a$verdict, "unverifiable") && is.null(a$reason) && identical(act(a), "proceed"))
  ok("C6 허용값 아닌 verdict 는 unverifiable(감사자 판정으로 취급 · reason 없음) → proceed — 구판과 같다") else
  ng("C6 임의 verdict 처리", sprintf("verdict=%s reason=%s action=%s", a$verdict, a$reason %||% "NULL", act(a)))

cat("\n=== D. 술어 직접 — 합성 입력으로 경계를 잰다 ===\n")
if (identical(act(list(verdict = "unverifiable", reason = "감사 파일 파손")), "audit_required"))
  ok("D1 unverifiable + reason → audit_required") else ng("D1")
if (identical(act(list(verdict = "unverifiable")), "proceed")) ok("D2 unverifiable + reason 없음 → proceed") else ng("D2")
if (identical(act(list(verdict = "faithful", reason = "x")), "proceed"))
  ok("D3 reason 은 unverifiable 에서만 뜻이 있다(faithful+reason → proceed)") else ng("D3")
r <- rf_audit_disposition(list(verdict = "unverifiable", reason = "감사 미실행"), 0L)
if (identical(names(r)[1], "action") && is.character(r$reason) && length(r$reason) == 1L)
  ok("D4 audit_required 반환 형태 = list(action, reason<chr 1>)") else ng("D4 반환 형태", paste(names(r), collapse = ","))

cat(sprintf("\n합계: 통과 %d · 실패 %d\n", PASS, FAIL))
cat(sprintf('{"test":"rf_audit_disposition_required","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
quit(status = if (FAIL > 0L) 1L else 0L)
