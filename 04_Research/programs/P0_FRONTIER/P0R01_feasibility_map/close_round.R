## P0R01 라운드 종료 — ① 보고서(md) ② 등록부 기록(complete · 판정) · 프로그램 상태(도달 = done → P4 차단 해제 · 미도달 = paused + 도훈 안건)
##   ③ 교훈(기전이 특정되면 L-code · 보는 창 수치만) ④ 보고 1통(prep_send)
## 실행: Rscript close_round.R [record] [send]   (인자 없으면 미리보기 — 등록부 · 원장 · 텔레그램 무접촉)
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
Sys.setenv(CLAUDE_PROJECT_DIR = ROOT, QM_ROOT = ROOT); setwd(ROOT)
source("02_Infrastructure/programs/program_registry.R")
source("02_Infrastructure/programs/program_report.R")
source("02_Infrastructure/contracts/matched_controls.R")
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
A <- commandArgs(trailingOnly = TRUE); RECORD <- "record" %in% A; SEND <- "send" %in% A
RD <- file.path(ROOT, "04_Research/programs/P0_FRONTIER/P0R01_feasibility_map")
SA <- file.path(ROOT, "stage_artifacts/programs/P0_FRONTIER/P0R01_feasibility_map")
ev <- fromJSON(file.path(RD, "results/evaluation.json"), simplifyVector = TRUE)
pre <- fromJSON(file.path(SA, "prereg.json"), simplifyVector = FALSE)
T <- as.data.table(ev$table); D <- ev$decisive
UCF <- ev$thresholds$uc_floor; DCS <- suppressWarnings(as.numeric(ev$thresholds$dc_strong[1])); CM <- ev$thresholds$cagr_min
ENGN <- c(E1 = "모멘텀 12-1", E2 = "2002.06975 DNN 원형", E3 = "B6_36(2002.06975 계보)")
CMPN <- c(C0 = "부품 없음", C1 = "추세 현금", C2 = "변동성 타기팅", C3 = "낙폭 제어", C4 = "저변동 틸트", C5 = "퀄리티 틸트", C6 = "추세 현금+저변동")
pct <- function(x) prep_fmt_pct(x, 1L); rt <- function(x) prep_fmt_ratio(x, 2L)
reached <- identical(D$verdict, "reached")
## ── ① 보고서 ──
L <- character(0); a <- function(...) L <<- c(L, paste0(...))
a("# P0R01 실현 가능성 지도 — 라운드 보고서"); a("")
a("> 사전등록 md5 ", ev$prereg_md5, " · 측정 축 ", pre$measurement_axis$epoch, " · 보는 창 = 측정 시작 ~ ", pre$tau_d, " · 평가 ", ev$evaluated_at)
a(""); a("## 1. 질문과 판정"); a("")
a("- 질문: 문헌 표준 단순 부품 × 기존 수익 엔진이 보는 창에서 목표 영역(상승 포착 ≥ ", rt(UCF), " · 위기 누적 포착 ≤ ", sprintf("%.3f", DCS),
  " · CAGR ≥ ", pct(CM), ")에 닿는가.")
a("- **판정: ", if (reached) sprintf("도달 — 목표 영역 %d칸", D$n_in_region) else "미도달 — 목표 영역 0칸", "** (평가 ", ev$n_evaluated, "/", ev$n_cells, "칸)")
a("- 미달 칸 수(축별): 상승 포착 ", D$binding$uc, " · 위기 누적 포착 ", D$binding$dc, " · CAGR ", D$binding$cagr, " — 가장 많이 묶는 축이 구속 축이다.")
if (reached) { s <- D$selected
  a("- 선택(사전등록 규칙 · 보는 창 S_vis 최대): **", ENGN[s$engine], " × ", CMPN[s$component], "** — S_vis ", sprintf("%.3f", s$S_vis),
    " · 상승 ", rt(s$uc), " · 위기 ", sprintf("%.3f", s$dc), " · CAGR ", pct(s$cagr)) }
a(""); a("## 2. 21칸 지도(보는 창 · 진단 패킷)"); a("")
a("| 엔진 | 부품 | 상승 포착 | 위기 누적 포착 | CAGR | Calmar | PORT_t | S_vis | 영역 | 귀속(MC8) | 등급(전기간 · 권위) |"); a("|---|---|---|---|---|---|---|---|---|---|---|")
setorder(T, engine, component)
for (i in seq_len(nrow(T))) with(T[i], a("| ", ENGN[engine], " | ", CMPN[component], " | ", rt(uc), if (isTRUE(uc_ok)) " ✓" else "", " | ",
  if (is.finite(dc)) sprintf("%.3f", dc) else "—", if (isTRUE(dc_ok)) " ✓" else "", " | ", pct(cagr), if (isTRUE(cagr_ok)) " ✓" else "", " | ",
  rt(calmar), " | ", rt(port_t), " | ", sprintf("%.3f", S_vis), " | ", if (isTRUE(in_region)) "**도달**" else "—", " | ",
  c(selection_defense = "선택", size_defense = "크기", exposure_defense = "노출", no_defense = "없음", insufficient = "판정 불가")[attribution] %||% "—",
  " | ", grade %||% "—", " |"))
a(""); a("## 3. 부품별 기대 방향(사전등록 · R 집계)"); a("")
EX <- as.data.table(ev$expectations)
if (nrow(EX)) {
  a("- 적중률 ", pct(ev$expectation_hit_rate), " (", sum(EX$hit, na.rm = TRUE), "/", sum(!is.na(EX$hit)), ")")
  for (cid in unique(EX$component)) { x <- EX[component == cid]
    a("- ", CMPN[cid], ": 적중 ", sum(x$hit, na.rm = TRUE), "/", sum(!is.na(x$hit)), " (",
      paste(sprintf("%s %s %s %s%s", x$engine, ifelse(x$field == "crisis_cum_capture_median", "위기", "상승"), x$op, x$ref,
                    ifelse(is.na(x$hit), "?", ifelse(x$hit, "✓", "✗"))), collapse = " · "), ")") } }
if (reached && !is.null(D$test_window)) {
  a(""); a("## 4. 시험 창(2023-01~) — 목표 영역 칸(사람 쪽 판정 · 선택 규칙 입력 아님)"); a("")
  TW <- as.data.table(D$test_window)
  a("| 칸 | 상승 포착 | 위기 누적 포착 | CAGR | 유지 |"); a("|---|---|---|---|---|")
  for (i in seq_len(nrow(TW))) with(TW[i], a("| ", code, " | ", rt(test_uc), " | ", if (is.finite(test_dc)) sprintf("%.3f", test_dc) else "—", " | ", pct(test_cagr), " | ",
    paste(c(if (isTRUE(uc_hold)) "상승 ✓" else if (isFALSE(uc_hold)) "상승 ✗" else "상승 판정 불가",
            if (isTRUE(dc_hold)) "위기 ✓" else if (isFALSE(dc_hold)) "위기 ✗" else "위기 판정 불가",
            if (isTRUE(cagr_hold)) "CAGR ✓" else if (isFALSE(cagr_hold)) "CAGR ✗" else "CAGR 판정 불가"), collapse = " · "), " |"))
}
a(""); a("## ", if (reached) "5" else "4", ". 다음"); a("")
if (reached) a("- P4 조립 · 처방 루프의 골격 = 선택 칸. 등록부 P0 = done → P4 차단 해제.") else {
  a("- 등록부 kill_or_pivot: 목표 영역 0칸 → 탐색을 늘리지 않고 **도훈 안건(목표 또는 축 재검토)**. P0 = paused · P4 차단 유지.")
  a("- 안건 재료: 구속 축(위 1절) · 프런티어 도판 · 가장 가까운 칸(축별 부족분 합 최소).") }
a("- 엔진 E2 · E3 의 기저 신호 = DNN 예측 점수(엔진 FACTORS · 셀 엔진이 비중보다 점수를 먼저 쓴다) — E2 = 예측 점수 상위 25 · E3 = 예측 점수 + 팩터 3개 결합 순위.")
## 부록 — 같은 기저 구/신 축 비교(측정 축 전환의 남은 항목): B6_36 구 축(P2R01 RX0 · K200∪KQ150 · 2005~) vs 새 축(P0R01 E3_C0)
.au <- function(dir) tryCatch(fromJSON(file.path(dir, "authoritative_remeasure.json"), simplifyVector = TRUE), error = function(e) NULL)
.old <- tryCatch(fromJSON(file.path(ROOT, "04_Research/programs/P2_DEFENSE/P2R01_s2_pilot/results/P2R01_RX0.json"), simplifyVector = TRUE), error = function(e) NULL)
.newe <- tryCatch(fromJSON(file.path(RD, "results/P0R01_E3_C0/eval.json"), simplifyVector = TRUE), error = function(e) NULL)
if (!is.null(.old) && !is.null(.newe)) {
  ao <- .au(.old$artifacts); an <- .au(.newe$artifacts)
  if (!is.null(ao) && !is.null(an)) {
    a(""); a("## 부록. 같은 기저 구/신 측정 축 비교 — B6_36(전기간 · 권위 산출물)"); a("")
    a("| 측정 축 | 창 | 등급 | S | CAGR | 최대낙폭 | Calmar | PORT_t |"); a("|---|---|---|---|---|---|---|---|")
    row <- function(lab, x) a("| ", lab, " | ", x$measurement_axis$start_date_used %||% "2005-01-01", "~ | ", x$essence_grade %||% "—", " | ",
                             sprintf("%.3f", as.numeric(x$grade_v3$S %||% NA)), " | ", pct(x$essence$cagr), " | ", pct(-x$essence$mdd), " | ",
                             rt(x$essence$calmar), " | ", rt(x$essence$portfolio_alpha_t_nw_lag3), " |")
    row("구 축 K200∪KQ150", ao); row("새 축 전 종목 + 위생", an)
    a(""); a("- 창이 다르다(구 축 2005~ · 새 축 2000~ 실효 시작) — 같은 창 비교가 아니라 '측정 축 전환이 같은 사양의 등급을 어떻게 바꾸나'의 기록이다.")
  }
}
a(""); a("도판: `stage_artifacts/programs/P0_FRONTIER/P0R01_feasibility_map/charts/` · 칸 평가: `04_Research/programs/P0_FRONTIER/P0R01_feasibility_map/results/<칸>/`")
REP <- file.path(SA, "ROUND_REPORT.md"); writeLines(enc2utf8(L), REP, useBytes = TRUE)
cat("보고서:", REP, "\n")
## 가장 가까운 칸(미도달일 때 안건 재료)
T[, gap := short_uc + short_dc + short_cagr]; near <- T[status == "evaluated"][order(gap)][1]
## ── ② 등록부 ──
if (RECORD) {
  rr <- Filter(function(r) identical(r$round_id, "P0R01_feasibility_map"), pr_get(pr_load(ROOT), "P0_FRONTIER")$rounds)[[1]]
  pr_record_round("P0_FRONTIER", list(round_id = "P0R01_feasibility_map", prereg = rr$prereg, prereg_md5 = rr$prereg_md5, status = "complete",
                                      verdict = D$verdict, n_in_region = D$n_in_region, in_region = as.list(D$in_region),
                                      selected = if (reached) D$selected$code else NULL, binding = D$binding,
                                      report = sub(paste0("^", ROOT, "/"), "", REP)), root = ROOT)
  if (reached) pr_set_status("P0_FRONTIER", "done", reason = sprintf("P0R01 도달 — 골격 %s(보는 창 S_vis 최대) · P4 차단 해제", D$selected$code), root = ROOT)
  else {
    pr_set_status("P0_FRONTIER", "paused", reason = "P0R01 미도달(목표 영역 0칸) — 등록부 kill_or_pivot: 도훈 안건(목표 또는 축 재검토) · 탐색 확장 금지", root = ROOT)
    suppressMessages(source("02_Infrastructure/reinforcement/reinforce_ledger.R"))
    dr_open("P0-FRONTIER-NOT-REACHED", title = "P0 실현 가능성 지도 미도달 — 목표 또는 축 재검토",
            options = c("목표 재검토 — 상승 포착 하한 · 위기 문턱 · CAGR 16% 중 구속 축 완화(도훈 권한)",
                        "축 재검토 — 측정 축 · 고정 축(현행 유지가 기본)", "탐색 확장 허가 — 부품 · 엔진을 넓힌 P0R02(사전등록 새로)",
                        "P1 수익 엔진 확보 뒤 재시도 — 새 재료로 P0R02"),
            recommendation = sprintf("구속 축 = 미달 칸 최다 축(상승 %d · 위기 %d · CAGR %d) — 보고서 참조", D$binding$uc, D$binding$dc, D$binding$cagr),
            default_until_decided = "P0 paused · P4 차단 유지", blocks = character(0), owner = "dohoon",
            source = sub(paste0("^", ROOT, "/"), "", REP), root = ROOT)
  }
}
## ── ④ 보고 1통 ──
card <- if (reached) fromJSON(file.path(RD, "results", D$selected$code, "full", "behavior_card.json"), simplifyVector = TRUE) else NULL
items <- vapply(seq_len(nrow(T)), function(i) with(T[i], sprintf("%s · %s — 상승 %s · 위기 %s · CAGR %s%s", ENGN[engine], CMPN[component], rt(uc),
  if (is.finite(dc)) sprintf("%.2f", dc) else "—", pct(cagr), if (isTRUE(in_region)) " · 목표 영역" else "")), character(1))
verdict_line <- if (reached) sprintf("목표 영역 도달 %d칸 — 골격 = %s × %s(보는 창 종합점수 최대)", D$n_in_region, ENGN[D$selected$engine], CMPN[D$selected$component]) else
  sprintf("목표 영역 0칸(21칸 중) — 미달 칸 수: 상승 %d · 위기 %d · CAGR %d. 규칙대로 탐색을 늘리지 않고 도훈 안건으로", D$binding$uc, D$binding$dc, D$binding$cagr)
extra <- list(list(heading = "21칸 지도(보는 창 2000~2022)", type = "bullet", items = items))
if (!reached) extra[[2]] <- list(heading = "가장 가까운 칸", type = "bullet",
  items = c(sprintf("%s × %s — 상승 %s(문턱 %s) · 위기 %s(문턱 %.2f) · CAGR %s(문턱 %s)", ENGN[near$engine], CMPN[near$component], rt(near$uc), rt(UCF),
                    sprintf("%.2f", near$dc), DCS, pct(near$cagr), pct(CM)), "도훈 안건: 목표 재검토 · 축 재검토 · 탐색 확장 허가 · 새 수익 엔진 뒤 재시도 중 선택"))
if (SEND || !RECORD) {
  if (!SEND) Sys.setenv(QVEST_TG_DRY_RUN = "1")
  res <- prep_send(program = "실현 가능성 지도", target = "P0 1라운드(부품 7 × 엔진 3)",
                   status = list(stage = "P0 실현 가능성 지도 — 사전등록 → 측정 21칸 → 보는 창 판정",
                                 position = if (reached) "골격 확정 → P4 조립 · 처방 루프" else "도훈 안건(목표 또는 축 재검토) · P4 차단 유지",
                                 previous = "선행 조건 MC1~MC8 완료 · 측정 축 전 종목 + 위생 · 2000~"),
                   card = card, verdict_line = verdict_line,
                   next_step = if (reached) "P4 조립 · 처방 루프 1라운드(골격 = 선택 칸)" else "도훈 결정 대기 — P1 · P2 · P3 라운드는 계속",
                   artifact = REP, charts = c(`프런티어` = file.path(SA, "charts/frontier_visible.png"), `누적 곡선` = file.path(SA, "charts/nav_engines.png")),
                   push = TRUE, window = "overall", extra = extra, root = ROOT)
  cat("prep_send ok =", isTRUE(res$ok), "\n")
}
