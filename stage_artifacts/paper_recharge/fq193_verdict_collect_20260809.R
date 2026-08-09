#!/usr/bin/env Rscript
# fq193_verdict_collect_20260809.R — FQ-193 판정 수집 + FQ-002 revival 선행조건 정정.
suppressMessages(library(jsonlite))
setwd(Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
source("02_Infrastructure/ops/frontier_queue_io.R")
Q <- read_frontier_queue()
gi <- function(id) which(vapply(Q$entries, function(x) identical(as.character(x$id %||% ""), id), logical(1)))
ids <- vapply(Q$entries, function(x) as.character(x$id %||% ""), character(1))
nxt <- max(as.integer(sub("^FQ-0*", "", grep("^FQ-[0-9]+$", ids, value = TRUE))), na.rm = TRUE)

i193 <- gi("FQ-193"); stopifnot(length(i193) == 1L)
Q$entries[[i193]]$status <- "measured_era_confounded_open"
Q$entries[[i193]]$verdict_20260809 <- paste0(
  "★대상 축소: 명시 4필드(n_contracts·amend_n·round_n·fx_n)가 커버 종목 안 0비율 62.5~97.9%, ",
  "분할불가 월 17~71/79 로 **전부 측정 제외**. w_n 은 w_ratio(F1 반증 종료)와 rho +0.785 = 부분 재탕으로 제외. ",
  "⇒ **w_amt 단독**(w_ratio 와 rho +0.304 = 분모를 뺀 독립 축). 단일 테스트라 다중검정 보정 불요. ",
  "★실측(79개월 2020-01~2026-07, 커버 24.0%, 월 제외 1.29종): ",
  "기준선 book IR 1.0950/PORT_t 2.768 → 하위3분위 제외 IR 1.2108(**ΔIR +0.1158**)/PORT_t 3.020(+0.251). ",
  "F1 통과(음성대조 q95 +0.0537 초과) · F2 통과(회수율 **27.9%**, 문턱 25%) · ",
  "F5 통과(w_amt vs book rank rho -0.096 / weight +0.180 = size 교락 낮음) · ",
  "양성대조 완전예지 +0.4153 재현. ",
  "★★그러나 **F3 반증 — 전반 -0.0634 / 후반 +0.2556 부호 갈림**. 사전등록이 '단일 판정 금지'로 못박음. ",
  "기전 판별 시도: 커버가 2020 11% → 2026 36% 추세라 커버-시대가 **구조적 교락**. ",
  "회귀 diff~n_cov+era 에서 **둘 다 비유의**(p 0.320 / 0.342), 2원 표는 커버 고정 후에도 후반이 3/3 층에서 높으나 ",
  "셀 표본이 (2,6)까지 떨어져 분리 불가. ⇒ **w_amt 는 죽지 않았으나 확립도 안 됐다.**")
Q$entries[[i193]]$next_action <- paste0(
  "확립하려면 커버-시대 교락을 깨는 **독립 구간**이 필요하다. 그 구간(2005~2016)은 파서에 막혀 있다 — ",
  "FQ-", sprintf("%03d", nxt + 1), " 참조. 파서 능력 확보 전까지 본 항목은 재측정 불가(대기).")
Q$entries[[i193]]$l_code <- "L-AR-20260809_234500"

i2 <- gi("FQ-002"); stopifnot(length(i2) == 1L)
Q$entries[[i2]]$revival_conditions_corrected_20260809 <- paste0(
  "★구 revival('2005~2016 구간 커버리지 확보 시 재개')은 **크롤 예산 문제로 오기록**돼 있었다. ",
  "실측(FQ-125 stage1 corpus, 2026-08-03 12:06 — 파서 v3 CP949 수리 09:08 **이후**): ",
  "pre2019 rows 1199 중 ok 29 · **parse_fail 1147 = 실패율 95.7%**. 2019+ 는 성공률 92.0%(5793/6298). ",
  "⇒ 인코딩 수리를 하고도 pre2019 가 안 읽힌다 — 원인은 인코딩이 아니라 **공시 규정 자체가 다름**",
  "(본 항목 data_gate 노트의 '2005~2016 공시 규정 상이'와 정합). ",
  "★선행 조건은 **크롤 예산(1.5~3.2일)이 아니라 pre2019 파싱 능력**이다. 크롤해도 95.7% 가 버려진다.")

new <- list(
  id = sprintf("FQ-%03d", nxt + 1), lane = "non_return",
  title = "DART 계약공시 pre2019 파싱 능력 — 계약 lane 전체의 선행 조건(실패율 95.7%)",
  status = "capability_gate_open",
  owner = "Q-Lead (FQ-193 판정에서 도출, 2026-08-09)",
  hypothesis = "2019년 이전 계약공시는 규정·서식이 달라 현행 파서(v3, CP949 수리 포함)가 95.7% 실패한다. 이 능력이 없으면 계약 lane 의 커버-시대 교락을 깨는 독립 구간을 확보할 수 없다.",
  ev_rationale = paste0(
    "★이것이 열리면 두 가지가 동시에 풀린다: ①FQ-193 w_amt 의 F3 교락(커버-시대 분리) ",
    "②FQ-002 revival 의 '2005~2016 조선·플랜트 수주 사이클' 미검 구간. ",
    "반대로 열리지 않으면 계약 lane 은 2019+ 79개월에 영구 갇힌다(현 커버-시대 교락 해소 불가)."),
  next_action = paste0(
    "①pre2019 실패 1147건의 **실패 사유 분해**(서식 버전·태그 구조·본문 부재) — 인코딩은 이미 배제됨. ",
    "②단일 사유가 다수면 그 서식 전용 분기 추가 후 회귀 테스트(dart_contract_parser_regression.R 확장). ",
    "③분해 결과 '규정상 필드 자체가 없음'이면 **능력 게이트 폐쇄**로 확정하고 계약 lane 을 2019+ scoped 로 라벨."),
  wall_check = "실측 근거 = fq125_stage1_results.json::corpus (파서 v3 수리 이후 측정). pre2019 ok 29/1199 · 2019+ ok 5793/6298",
  created = "2026-08-09")

Q$entries <- c(Q$entries, list(new)); Q$updated <- "2026-08-09"
res <- write_frontier_queue(Q)
cat(sprintf("판정 수집 — added=%d removed=%d 총 %d\n", res$added, res$removed, res$n))
cat(sprintf("  FQ-193 → %s\n  FQ-002 revival 정정\n  신규 %s [%s]\n",
            Q$entries[[i193]]$status, new$id, substr(new$title, 1, 60)))
