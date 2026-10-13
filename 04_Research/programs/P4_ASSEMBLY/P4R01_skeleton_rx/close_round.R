## P4R01 종료 — ① 보고서 ② 등록부 기록 · 상태 ③ 교훈(L-code · 보는 창 수치만 · 기전 특정 시) ④ 보고 1통 · A 관문 산출 확인(Judge 트리거)
## 실행: Rscript close_round.R [record] [send]
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
Sys.setenv(CLAUDE_PROJECT_DIR = ROOT, QM_ROOT = ROOT); setwd(ROOT)
source("02_Infrastructure/programs/rx_round.R")
source("02_Infrastructure/programs/program_registry.R")
source("02_Infrastructure/programs/program_report.R")
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
A <- commandArgs(trailingOnly = TRUE); RECORD <- "record" %in% A; SEND <- "send" %in% A
PROGRAM <- "P4_ASSEMBLY"; ROUND <- "P4R01_skeleton_rx"
P <- rx_paths(PROGRAM, ROUND, ROOT); RD <- P$round_dir
SA <- P$prereg_dir
pre <- fromJSON(file.path(SA, "prereg.json"), simplifyVector = FALSE)
ev <- fromJSON(file.path(RD, "results/evaluation.json"), simplifyVector = FALSE)
rv <- tryCatch(rx_parse_json(readLines(file.path(P$lane("reviewer"), "out.md"), warn = FALSE, encoding = "UTF-8")), error = function(e) NULL)
pct <- function(x) prep_fmt_pct(as.numeric(x %||% NA), 1L); rt <- function(x) prep_fmt_ratio(as.numeric(x %||% NA), 2L)
L <- character(0); a <- function(...) L <<- c(L, paste0(...))
a("# P4R01 조립 · 처방 루프 1라운드 — 보고서"); a("")
a("> 골격 = ", pre$skeleton$skeleton, "(", pre$skeleton$engine, " × ", pre$skeleton$component, ") · 사전등록 md5 ", ev$prereg_md5, " · 측정 축 ", pre$measurement_axis$epoch)
a(""); a("| 처방 | 상태 | 반증 | 보는 창 상승 포착 | 위기 누적 포착 | CAGR | Calmar | PORT_t | 등급(전기간 · 권위) | S |"); a("|---|---|---|---|---|---|---|---|---|---|")
a("| 골격 | — | — | ", rt(ev$base$uc), " | ", sprintf("%.3f", as.numeric(ev$base$dc)), " | — | ", rt(ev$base$calmar), " | ", rt(ev$base$port_t), " | — | — |")
gradeA <- character(0)
for (r in ev$rows) {
  v <- r$visible %||% list()
  a("| ", r$id, " | ", r$status, " | ", if (isTRUE(r$rejected)) "기각" else if (isTRUE(r$undetermined)) "판정 불가" else "통과", " | ", rt(v$uc), " | ",
    if (is.numeric(v$dc)) sprintf("%.3f", v$dc) else "—", " | ", pct(v$cagr), " | ", rt(v$calmar), " | ", rt(v$port_t), " | ", r$grade %||% "—", " | ",
    if (is.numeric(r$S)) sprintf("%.3f", r$S) else "—", " |")
  if (identical(r$grade, "A")) gradeA <- c(gradeA, r$code)
}
a(""); a("- 최종 선택(사전등록 기계 규칙): **", ev$selected$id %||% "없음", "**")
if (!is.null(rv)) { a("- 리뷰어: 권고 ", rv$recommendation %||% "—", " · 기계 판정 동의 ", isTRUE(rv$agree_with_machine), " · 잡음 판독 ", rv$noise_judgement %||% "—")
  for (m in rv$mechanism_readings %||% list()) a("  - ", m$id, ": ", m$reading) }
## A 관문 산출 확인 — 처방 칸은 셀 러너 경로(구판 judge_request.json) · 충실구현 어댑터 관문은 타지 않는다(러너 §11 셀 분기)
jr <- character(0)
for (cd in gradeA) { e <- fromJSON(file.path(RD, "results", cd, "eval.json"), simplifyVector = FALSE)
  for (f in c("judge_request.eligible.json", "judge_request.held.json", "judge_request.json")) if (file.exists(file.path(e$artifacts, f))) jr <- c(jr, sprintf("%s: %s", cd, f)) }
if (length(gradeA)) { a(""); a("## 등급 A 칸"); a(""); a("- ", paste(gradeA, collapse = " · "), " — A 관문 산출: ", if (length(jr)) paste(jr, collapse = " · ") else "없음")
  a("- Judge(PIT 전담)는 A 관문 통과 산출(judge_request.eligible.json) 또는 셀 경로 요청이 있을 때 세션이 스폰한다 · BOOK 등록은 도훈 confirm") }
REP <- file.path(SA, "ROUND_REPORT.md"); writeLines(enc2utf8(L), REP, useBytes = TRUE); cat("보고서:", REP, "\n")
if (RECORD) {
  rr <- Filter(function(r) identical(r$round_id, ROUND), pr_get(pr_load(ROOT), PROGRAM)$rounds)[[1]]
  pr_record_round(PROGRAM, list(round_id = ROUND, prereg = rr$prereg, prereg_md5 = rr$prereg_md5, status = "complete",
                                selected = ev$selected$code %||% NULL, grade_a = as.list(gradeA), reviewer = rv$recommendation %||% NA,
                                report = sub(paste0("^", ROOT, "/"), "", REP)), root = ROOT)
  pr_set_status(PROGRAM, "ready", reason = sprintf("P4R01 완료 — 선택 %s · 리뷰어 %s", ev$selected$id %||% "없음", rv$recommendation %||% "—"), root = ROOT)
}
card <- if (!is.null(ev$selected$code)) fromJSON(file.path(RD, "results", ev$selected$code, "full", "behavior_card.json"), simplifyVector = TRUE) else NULL
items <- vapply(ev$rows, function(r) { v <- r$visible %||% list()
  sprintf("%s — %s · 상승 %s · 위기 %s · Calmar %s · PORT_t %s", r$id, if (isTRUE(r$rejected)) "기각" else "통과", rt(v$uc),
          if (is.numeric(v$dc)) sprintf("%.2f", v$dc) else "—", rt(v$calmar), rt(v$port_t)) }, character(1))
if (SEND || !RECORD) {
  if (!SEND) Sys.setenv(QVEST_TG_DRY_RUN = "1")
  res <- prep_send(program = "조립 · 처방 루프", target = sprintf("P4 1라운드(골격 %s × %s · 처방 %d건)", pre$skeleton$engine, pre$skeleton$component, length(ev$rows)),
                   status = list(stage = "P4 조립 · 처방 루프 — 분석가 → 처방 담당 → 사전등록 → 측정 → 리뷰어", position = "라운드 종료 · 보고",
                                 previous = "P0 도달 · 골격 고정 · P1 · P2 · P3 라운드 완료"),
                   card = card, verdict_line = sprintf("선택 %s · 리뷰어 권고 %s%s", ev$selected$id %||% "없음", rv$recommendation %||% "—",
                                                      if (length(gradeA)) sprintf(" · 등급 A %d칸(관문 확인)", length(gradeA)) else ""),
                   next_step = if (identical(rv$recommendation, "stop")) "R7 — 이 골격의 다음 라운드를 열지 않는다" else "다음 라운드(리뷰어 권고) — 도훈 확인",
                   artifact = REP, push = TRUE, extra = list(list(heading = "처방 결과(보는 창)", type = "bullet", items = items)), root = ROOT)
  cat("prep_send ok =", isTRUE(res$ok), "\n")
}
