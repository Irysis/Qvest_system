## P2R03 분기점 알림(도훈 10-13 '개선 프로세스는 분기점마다 1통(푸시)' · 정본 발송기 prep_send) — notify_done.sh 가 센티널을 보고 부른다.
##   알리는 것: 측정 · 판정이 끝났다(보는 창 판정 라벨 · 장치별 결과) / 측정하지 않았다(precheck · 배리어) / 평가 실패 / 마감 지연.
##   결과 보고(요약 + 차트 + 다음 리서치 브리핑 — SKILL §0.7)는 세션이 따로 보낸다. 시험 창 수치는 싣지 않는다(evaluation_visible.json 만 읽는다).
## 실행: Rscript notify.R [--timeout] [--eval=<evaluation_visible.json>] [--state=<센티널 폴더>]   (QVEST_TG_DRY_RUN=1 이면 발송 없이 본문만)
suppressPackageStartupMessages(library(jsonlite))
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
Sys.setenv(CLAUDE_PROJECT_DIR = ROOT, QM_ROOT = ROOT); setwd(ROOT)
`%or%` <- function(a, b) if (is.null(a) || length(a) == 0L || (length(a) == 1L && is.na(a))) b else a
source("02_Infrastructure/programs/program_report.R")
a <- commandArgs(trailingOnly = TRUE)
arg <- function(k, d) { v <- sub(paste0("^--", k, "="), "", grep(paste0("^--", k, "="), a, value = TRUE)); if (length(v)) v[1] else d }
RD <- "04_Research/programs/P2_DEFENSE/P2R03_conditional_overlay"
EVJ <- arg("eval", file.path(ROOT, RD, "results", "evaluation_visible.json"))
ST <- arg("state", file.path(ROOT, "04_Research/programs/_lib/night_state"))
sent <- function(f) { p <- file.path(ST, f); if (file.exists(p)) readLines(p, warn = FALSE)[1] else NA_character_ }
kv <- function(s, k) { if (is.na(s)) return(NA_character_); m <- regmatches(s, regexpr(paste0(k, "=[^ ]+"), s)); if (length(m)) sub(paste0("^", k, "="), "", m) else NA_character_ }
ms <- sent("p2r03_measured.done"); es <- sent("p2r03_evaluated.done")
VW <- c(supported = "지지", partial = "부분 지지", falsified = "반증", untested = "미시험")
DN <- c(D1 = "하방베타 축소", D2 = "특이변동 축소", D3 = "상태 거리 게이트", D4 = "꼬리 확률 게이트", D5 = "추세 현금", D6 = "낙폭 브레이크", D7 = "재진입 게이트")
EN <- c(E2 = "DNN 원형", E3 = "B6_36")
CW <- c(pass = "통과", exposure_only = "노출(β) 방어", slow_only = "느린 약세 · 여진 방어", defense_but_strength_or_path = "방어만 · 복리 미달",
        beta_unmeasured = "β 대조 미측정", fast_unmeasured = "빠른 급락 미측정", not_decisive = "방어 판정 미달", untested = "미시험")
TARGET <- "조건부 시변 노출 층 7종 × 엔진 2"
status <- list(stage = "방어 엔진 — P2R03 측정 · 셀 평가 · 판정(분리 실행 · 데이터 갱신 뒤)", position = NA, previous = "P3R03 구성 5종 — 노출(β) 방어 · 구성 레버 포화")
NEXT <- "세션에서 결과 보고(누적 수익 · 낙폭 · 증분 알파 차트 — 시험 창은 사람 쪽 보고) + 다음 리서치 브리핑 · 철학 Superfan P2(방향 판정)"
send <- function(target, verdict_line, extra = NULL, next_step = NEXT, artifact = NULL) {
  r <- prep_send(program = "방어 엔진", target = target, status = status, verdict_line = verdict_line, next_step = next_step,
                 artifact = artifact, push = TRUE, extra = extra, root = ROOT)
  cat("prep_send ok =", isTRUE(r$ok), "\n"); invisible(r)
}
if ("--timeout" %in% a) {
  status$position <- "측정 지연"
  send(paste(TARGET, "— 측정 지연"), sprintf("마감까지 측정 · 판정이 끝나지 않았다(측정 센티널: %s · 평가 센티널: %s)", kv(ms, "status") %or% "없음", kv(es, "status") %or% "없음"),
       next_step = "세션에서 측정 로그(results/measure.log) 확인 뒤 재측정 · 평가")
} else if (!is.na(ms) && kv(ms, "status") %in% c("precheck_fail", "barrier_held")) {
  status$position <- "측정 안 함"
  why <- c(precheck_fail = "측정 직전 핀 대조(precheck) 불일치 — 사전등록과 다른 코드 · 데이터 조건", barrier_held = "데이터 갱신 배리어가 2시간 뒤에도 잡혀 있었다")[[kv(ms, "status")]]
  send(paste(TARGET, "— 측정 안 함"), why, next_step = "세션에서 원인 확인(results/precheck.json · 측정 로그) 뒤 다시 띄운다", artifact = file.path(RD, "results"))
} else if (!is.na(es) && !identical(kv(es, "status"), "evaluated")) {
  status$position <- "평가 실패"
  send(paste(TARGET, "— 평가 실패"), sprintf("측정 ok %s · 셀 평가 · 판정이 rc=%s 로 멈췄다(핀 · 지문 · 측정 연기 · 캐시 단정 중 하나 — 평가 로그에 사유)", kv(es, "ok") %or% "?", kv(es, "rc") %or% "?"),
       next_step = "세션에서 평가 로그(evaluate.log) 확인 — 지문 불일치 · 측정 연기면 그 묶음 재측정 뒤 평가", artifact = file.path(RD, "evaluate.log"))
} else {
  ev <- fromJSON(EVJ, simplifyVector = FALSE)
  status$position <- sprintf("측정 · 판정 완료 — 측정 ok %s", kv(es, "ok") %or% "?")
  nm <- function(x) if (length(x)) paste(DN[unlist(x)], collapse = " · ") else "없음"
  vl <- sprintf("%s(판정 %s/%s칸) — 두 엔진 통과 %s · 한 엔진 통과 %s · 집중 제외 %s · lag-1 보류 %s", VW[[ev$verdict]] %or% ev$verdict, ev$n_judged %or% "?", ev$n_total %or% "?",
                nm(ev$pass_both), nm(ev$pass_one), if (length(ev$excluded)) paste(DN[vapply(ev$excluded, function(x) x$device, "")], collapse = " · ") else "없음", nm(ev$held_lag1_slow))
  items <- vapply(names(DN), function(d) {
    xs <- Filter(function(x) identical(x$device, d) && !isTRUE(x$lag), ev$cells)
    paste0(DN[[d]], " — ", paste(vapply(xs, function(x) sprintf("%s %s", EN[[x$engine]], CW[[x$verdict]] %or% x$verdict), ""), collapse = " · "))
  }, character(1))
  sel <- if (length(ev$selected)) sprintf("선택: %s(S 증분 평균 %+.3f)", DN[[ev$selected[[1]]$device]], as.numeric(ev$selected[[1]]$dS)) else "선택 없음"
  send(paste(TARGET, "— 측정 · 판정 완료"), vl,
       extra = list(list(heading = "장치별 판정(보는 창 · 엔진 2)", type = "bullet", items = unname(c(items, sel)))),
       artifact = file.path(RD, "results", "evaluation_visible.json"))
}
