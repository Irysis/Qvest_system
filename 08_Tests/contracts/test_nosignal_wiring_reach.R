## test_nosignal_wiring_reach.R — 배선 "도달" 검사기 (2026-08-22 신설)
## ─────────────────────────────────────────────────────────────────────────────
## 왜 필요한가 (같은 날 3회 실측):
##   배선할 때마다 **"붙였다" 와 "도달한다" 가 갈렸다**.
##   ① 감사 CSV 만 있고 읽는 쪽이 0
##   ② module_dispatcher 에 넣으려 했으나 그건 풀을 고르지 않는 순수함수(실 결정자는 에이전트)
##   ③ auto_spawn 신규 엔트리만 배선해 **이월 엔트리가 우회** (verdict=None 5건)
##   셋 다 "검증 안 했으면 완료로 보고했을" 상태였다. 이 검사기가 그 계통을 기계화한다.
##
## ★정본 보호: 이 검사는 **사본**(tempdir)에서만 돈다. 06_Registry 정본을 절대 쓰지 않는다
##   (2026-08-22 '검사가 정본 레지스트리를 변형' 실사고 규약).
## ─────────────────────────────────────────────────────────────────────────────
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
`%||%` <- function(a, b) if (is.null(a)) b else a
ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
setwd(ROOT)

PASS <- 0L; FAIL <- 0L
chk <- function(nm, ok, d = "") {
  if (isTRUE(ok)) { PASS <<- PASS + 1L; cat(sprintf("  [ok]   %s\n", nm)) }
  else { FAIL <<- FAIL + 1L; cat(sprintf("  [FAIL] %s %s\n", nm, d)) }
}

## ── 사본 작업장 ───────────────────────────────────────────────────────────────
mk_sandbox <- function(tag) {
  d <- file.path(tempdir(), sprintf("nswire_%s_%d", tag, as.integer(runif(1, 1e6, 9e6))))
  ok <- dir.create(file.path(d, "06_Registry"), recursive = TRUE, showWarnings = TRUE)
  ## ★조용한 실패 금지 — 오늘 3회 겪은 계통(생성 실패를 정상으로 내려앉힘)을 막는다
  if (!isTRUE(ok) || !dir.exists(file.path(d, "06_Registry")))
    stop(sprintf("사본 작업장 생성 실패: %s", d))
  d
}
## ★on.exit 를 최상위에서 쓰지 않는다 — sourced 스크립트에서는 프레임이 즉시 종료돼
##   사본이 **선삭제**된다(r-portability 금칙② '스크립트 최상위 on.exit 미발화' 와 같은 계열,
##   여기선 반대로 *너무 일찍* 발화한다). 정리는 스크립트 말미에서 명시적으로 한다.
SB <- mk_sandbox("main")
SANDBOXES <- c(SB)

## 합성 감사 CSV (정본 미사용)
AUD <- data.table(
  id = c("CAND_A", "CAND_B", "CAND_C"),
  name = c("a", "b", "c"), grade = c("C", "C", "F"), n = c(200L, 200L, 200L),
  diff_ann = c(0.10, 0.001, -0.02), diff_nw_t = c(2.50, 0.05, -2.20),
  t_alpha = c(3.0, 2.2, 0.5), beta = c(1.0, 1.1, 0.9),
  port_t = c(2.0, 1.5, -0.5), beta_contrib = c(0.0, 0.01, -0.01),
  verdict = c("SIGNAL_ADDS_VALUE", "INDISTINGUISHABLE_FROM_NO_SIGNAL", "SIGNAL_HURTS"))
fwrite(AUD, file.path(SB, "06_Registry", "no_signal_queue_audit_r99_test.csv"))

## ── A. 큐 빌더의 부착 함수 — 신규 경로 ────────────────────────────────────────
cat("=== A. attach_no_signal_audit — 신규 경로 도달 ===\n")
## 함수만 가져오려고 소스를 읽어 실행부를 제외하고 eval
src <- readLines("02_Infrastructure/regime/overlay_candidate_queue.R", warn = FALSE)
env <- new.env(parent = globalenv())
assign("%||%", `%||%`, envir = env)
i0 <- grep("^attach_no_signal_audit <- function", src)
i1 <- grep("^# .. main", src)
chk("attach_no_signal_audit 정의 존재", length(i0) == 1L, sprintf("(hits=%d)", length(i0)))
if (length(i0) == 1L) {
  blk <- src[grep("^NOSIG_AUDIT_GLOB", src)[1]:(if (length(i1)) i1[1] - 1L else length(src))]
  eval(parse(text = paste(blk, collapse = "\n")), envir = env)
  cands <- list(list(id = "CAND_A"), list(id = "CAND_B"), list(id = "CAND_ZZ"))
  out <- env$attach_no_signal_audit(cands, root = SB)
  chk("전 후보에 no_signal 부착", all(vapply(out, function(x) !is.null(x$no_signal), TRUE)))
  chk("CAND_A verdict = SIGNAL_ADDS_VALUE", identical(out[[1]]$no_signal$verdict, "SIGNAL_ADDS_VALUE"),
      sprintf("(%s)", out[[1]]$no_signal$verdict))
  chk("CAND_B verdict = INDISTINGUISHABLE", identical(out[[2]]$no_signal$verdict, "INDISTINGUISHABLE_FROM_NO_SIGNAL"))
  chk("★감사에 없는 id → NOT_AUDITED(통과로 접지 않음)",
      identical(out[[3]]$no_signal$verdict, "NOT_AUDITED"), sprintf("(%s)", out[[3]]$no_signal$verdict))
  chk("수치 필드 동반(diff_nw_t)", isTRUE(abs(out[[1]]$no_signal$diff_nw_t - 2.50) < 1e-9))

  cat("\n=== B. 위반 주입 — 감사 파일이 없을 때 ===\n")
  SB2 <- mk_sandbox("empty")
  SANDBOXES <<- c(SANDBOXES, SB2)
  out2 <- env$attach_no_signal_audit(cands, root = SB2)
  chk("감사 부재 시 전건 NOT_AUDITED",
      all(vapply(out2, function(x) identical(x$no_signal$verdict, "NOT_AUDITED"), TRUE)))
  chk("★부재를 '통과' 로 접지 않음(SIGNAL_ADDS_VALUE 0건)",
      !any(vapply(out2, function(x) identical(x$no_signal$verdict, "SIGNAL_ADDS_VALUE"), TRUE)))
}

## ── C. auto_spawn 이월 경로 — 오늘 검거한 갭 ─────────────────────────────────
cat("\n=== C. auto_spawn 이월 엔트리 재보강 (2026-08-22 검거 갭) ===\n")
asq <- readLines("02_Infrastructure/ops/auto_spawn_queue.R", warn = FALSE)
has_new  <- any(grepl("no_signal_verdict = nsv", asq, fixed = TRUE))
has_prev <- any(grepl("ents\\[\\[eid\\]\\]\\$no_signal_verdict <- nsv", asq))
chk("신규 엔트리 경로에 verdict 배선", has_new)
chk("★이월 엔트리 경로에도 verdict 재보강 배선", has_prev,
    "— 신규만 배선하면 done/in_progress 이월분이 영구히 정보 없이 남는다")
## 재보강 블록이 이월 병합 **뒤**에 오는지(순서가 뒤바뀌면 무효)
i_prev <- grep("prev_ents\\[\\[eid\\]\\]", asq)
i_enrich <- grep("ents\\[\\[eid\\]\\]\\$no_signal_verdict", asq)
chk("재보강이 이월 병합 뒤에 위치", length(i_prev) && length(i_enrich) && max(i_enrich) > max(i_prev),
    sprintf("(prev=%s enrich=%s)", paste(i_prev, collapse=","), paste(i_enrich, collapse=",")))

## ── D. 소비 규칙이 에이전트 지시에 도달했는가 ────────────────────────────────
cat("\n=== D. 2층(결정자) 배선 — dispatch-orchestrator ===\n")
ag <- paste(readLines(".claude/agents/dispatch-orchestrator.md", warn = FALSE), collapse = "\n")
chk("에이전트 지시에 no_signal 확인 의무", grepl("no_signal", ag, fixed = TRUE))
chk("INDISTINGUISHABLE 행동 규칙 명시", grepl("INDISTINGUISHABLE_FROM_NO_SIGNAL", ag, fixed = TRUE))
chk("★NOT_AUDITED 를 통과로 취급하지 말라는 명문", grepl("NOT_AUDITED", ag, fixed = TRUE) &&
      grepl("통과가 아니", ag))

## ── E. 규범 반영 확인 ────────────────────────────────────────────────────────
cat("\n=== E. 규범(§2/§3) 반영 ===\n")
mg <- paste(readLines(".claude/rules/measurement-graduation.md", warn = FALSE), collapse = "\n")
chk("§2 β-통제 α 병기 의무", grepl("β-통제 α 병기 의무", mg))
chk("§3 무신호 대조 통과 의무", grepl("무신호 대조 통과 의무", mg))
chk("계약 파일 실재", file.exists("02_Infrastructure/contracts/no_signal_control.R"))

## ── F. 정본 무변형 확인 ──────────────────────────────────────────────────────
cat("\n=== F. 정본 보호 ===\n")
chk("사본 작업장만 사용(정본 06_Registry 미기록)",
    !file.exists("06_Registry/no_signal_queue_audit_r99_test.csv"))

cat(sprintf("\n=== 결과: PASS %d / FAIL %d ===\n", PASS, FAIL))
cat(sprintf('{"test":"nosignal_wiring_reach","pass":%d,"fail":%d,"total":%d,"skipped":0}\n', PASS, FAIL, PASS + FAIL))
if (FAIL > 0) quit(status = 1)
