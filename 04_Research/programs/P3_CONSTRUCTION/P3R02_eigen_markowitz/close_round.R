## P3R02 종료 — 보고서(md) · 등록부 기록 · 보고 1통(prep_send)
## 실행: Rscript close_round.R [record] [send]   (인자 없으면 미리보기 — 등록부 · 텔레그램 무접촉)
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
Sys.setenv(CLAUDE_PROJECT_DIR = ROOT, QM_ROOT = ROOT); setwd(ROOT)
source("02_Infrastructure/programs/program_registry.R")
source("02_Infrastructure/programs/program_report.R")
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
A <- commandArgs(trailingOnly = TRUE); RECORD <- "record" %in% A; SEND <- "send" %in% A
pct <- function(x) prep_fmt_pct(x, 1L); rt <- function(x) prep_fmt_ratio(x, 2L)
PROGRAM <- "P3_CONSTRUCTION"; ROUND <- "P3R02_eigen_markowitz"
ENGN <- c(E1 = "모멘텀 12-1", E2 = "2002.06975 DNN 원형")
RD <- file.path(ROOT, "04_Research/programs/P3_CONSTRUCTION/P3R02_eigen_markowitz")
ev <- fromJSON(file.path(RD, "results/evaluation.json"), simplifyVector = FALSE)
SA <- file.path(ROOT, "stage_artifacts/programs", PROGRAM, ROUND); dir.create(SA, recursive = TRUE, showWarnings = FALSE)
L <- character(0); a <- function(...) L <<- c(L, paste0(...))
ok_ <- function(x) if (isTRUE(x)) "충족" else "미달"
a("# P3R02 고유모드 정제 공분산 최소분산 — 라운드 보고서"); a("")
a("> 사전등록 v5 md5 ", ev$prereg_md5, "(v4 핀 전용 재핀 · 과학 필드 불변) · 기준 = 같은 배치 RX0(P0R01_E?_C0 사양 재측정) · 판정 창 = 보는 창(2000~2022)")
a(""); a("| 엔진 | 판정 | (a) 위기 누적 포착 중앙값 M5 / RX0 | (b) 위기별 개선 | (c) 강세 참여 M5 | 비열등 | 귀속 | β M5 / RX0 | 선택 기여 개선 위기 | CDaR M5 / RX0 | 연 회전 M5 / RX0 |")
a("|---|---|---|---|---|---|---|---|---|---|---|")
items <- character(0)
for (k in names(ev$engines)) {
  x <- ev$engines[[k]]; d <- x$decisive; ni <- x$non_inferiority; at <- x$attribution
  vk <- switch(x$verdict %||% "", decisive = "통과", not_decisive = "미달", untested = "미시험", x$verdict %||% "—")
  a("| ", ENGN[k], " | ", vk, " | ", rt(d$a_median$m5), " / ", rt(d$a_median$rx0), " | ", d$b_majority$n_better, "/", d$b_majority$n_pair,
    " | ", rt(d$c_participation$m5), "(문턱 ", rt(d$c_participation$floor), ") | ", ok_(ni$ok), "(", ni$basis, ") | ", at$label %||% "—",
    " | ", rt(at$beta$m5), " / ", rt(at$beta$rx0), " | ", at$selection_vs_rx0$n_better, "/", at$selection_vs_rx0$n_pair,
    " | ", pct(x$cdar$m5), " / ", pct(x$cdar$rx0), " | ", rt(x$record$turnover_annual$m5), " / ", rt(x$record$turnover_annual$rx0), " |")
  items <- c(items, sprintf("%s — %s · 위기 누적 포착 %s → %s · 강세 참여 %s(문턱 %s) · 비열등 %s · 귀속 %s · β %s → %s",
                            ENGN[k], vk, rt(d$a_median$rx0), rt(d$a_median$m5), rt(d$c_participation$m5), rt(d$c_participation$floor),
                            ok_(ni$ok), at$label %||% "—", rt(at$beta$rx0), rt(at$beta$m5)))
}
fails <- Filter(function(x) isTRUE(x$tested) && !identical(x$verdict, "decisive"), ev$engines)
passes <- Filter(function(x) identical(x$verdict, "decisive"), ev$engines)
a(""); a("- 판정: **", if (identical(ev$verdict, "falsified")) "반증" else ev$verdict, "** · 선택: ", if (is.null(ev$selected)) "없음(EW 유지)" else as.character(ev$selected))
a("- 규칙(사전등록 rules.falsified): 판정된 엔진 중 하나라도 decisive 불충족이면 반증 — 미달 엔진 = ",
  paste(ENGN[names(fails)], collapse = " · "), if (length(passes)) paste0(" · 통과 엔진 = ", paste(ENGN[names(passes)], collapse = " · ")) else "")
a("- 기록(판정 입력 아님): 처치 전달률 ", paste(vapply(ev$engines, function(x) rt(x$delivery), ""), collapse = " · "),
  " · 계획 해 불능 0 · RX0 와 P0R01 C0 원 측정 지표 일치(같은 판본 · 성능 수정 뒤 재현)")
verdict_line <- if (identical(ev$verdict, "falsified"))
  sprintf("반증 — %s 에서 미달(사전등록: 한 엔진이라도 미달이면 반증)%s", paste(ENGN[names(fails)], collapse = " · "),
          if (length(passes)) sprintf(" · %s 은 전 조건 통과(기전 방어)", paste(ENGN[names(passes)], collapse = " · ")) else "") else
  sprintf("통과 — 두 엔진 모두 위기 누적 포착 개선 · 강세 참여 유지 · 비열등")
next_step <- if (is.null(ev$selected)) "선택 없음(EW 유지) · 엔진 한정 결과는 기록으로만 — 새 가설은 새 사전등록으로" else "구성 부품 후보 → P4 조립"
results <- list(verdict = ev$verdict, selected = ev$selected,
                engines = lapply(ev$engines, function(x) list(verdict = x$verdict, attribution = x$attribution$label)))
REP <- file.path(SA, "ROUND_REPORT.md"); writeLines(enc2utf8(L), REP, useBytes = TRUE); cat("보고서:", REP, "\n")
if (RECORD) {
  rr <- Filter(function(r) identical(r$round_id, ROUND), pr_get(pr_load(ROOT), PROGRAM)$rounds)[[1]]
  pr_record_round(PROGRAM, list(round_id = ROUND, prereg = rr$prereg, prereg_md5 = rr$prereg_md5, status = "complete",
                                results = results, report = sub(paste0("^", ROOT, "/"), "", REP)), root = ROOT)
  pr_set_status(PROGRAM, "ready", reason = sprintf("P3R02 완료 — %s", ev$verdict), root = ROOT)
}
if (SEND || !RECORD) {
  if (!SEND) Sys.setenv(QVEST_TG_DRY_RUN = "1")
  res <- prep_send(program = "구성", target = "정제 공분산 최소분산(1810.08384 · 엔진 2 × M5 + 기준 RX0)",
                   status = list(stage = sprintf("구성 — %s", ROUND), position = "라운드 종료 · 보고",
                                 previous = "P3R01 구성 지도 판정 · 사전등록 v5(핀 전용 재핀)"),
                   verdict_line = verdict_line, next_step = next_step, artifact = REP, push = TRUE,
                   extra = list(list(heading = "판정 표(보는 창)", type = "bullet", items = items)), root = ROOT)
  cat("prep_send ok =", isTRUE(res$ok), "\n")
}
