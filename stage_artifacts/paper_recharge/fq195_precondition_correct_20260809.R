#!/usr/bin/env Rscript
# fq195_precondition_correct_20260809.R — FQ-195: 내가 '선행 조건'이라 적은 라벨 분리가 이미 있었다.
suppressMessages(library(jsonlite))
setwd(Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
source("02_Infrastructure/ops/frontier_queue_io.R")
Q <- read_frontier_queue()
i <- which(vapply(Q$entries, function(x) identical(as.character(x$id %||% ""), "FQ-195"), logical(1)))
stopifnot(length(i) == 1L)

Q$entries[[i]]$precondition_already_built_20260809 <- paste0(
  "★내가 '선행 조건'이라 적은 **상태 라벨 분리는 이미 배선돼 있었다**(2026-08-03 파서 v3). ",
  "`dart_contract_doc_parser.R` 이 NO_SOURCE_CORRECTION / NO_SOURCE_014 / RATE_LIMIT_020 / ",
  "UNZIP_FAIL(진짜 손상만) 로 이미 분리하고, `dart_contract_backfill.R` 은 RATE_LIMIT_020 시 ",
  "**halt + 그 달 미기록**으로 체크포인트 오염까지 막는다(주석: '한도가 원문 없음으로 굳는' 사고 방지). ",
  "⇒ pre2019 UNZIP_FAIL 527건(147바이트 균일)은 **구판 산물**이며 parser_version 전건 NA 와 정합한다. ",
  "v3 로 재다운로드하면 자동 분해된다. **선행 조건 없음 — 재다운로드만 하면 된다.** ",
  "★이것이 오늘 세 번째 같은 실수다(invested_eff 이미 존재 · v3 파서 이미 수리 · 라벨 분리 이미 배선) — ",
  "'없다'를 확인 없이 단정하는 계통.")

Q$entries[[i]]$next_action <- paste0(
  "★유일 경로 = **재다운로드**(`dart_contract_backfill.R`, v3). **선행 배선 불요** — 라벨 분리·halt 는 이미 있다. ",
  "①대상 = 2017-03~2018-12 실패 1147건(우선). API 일한도 소요 → **무인 시간대 실행**. ",
  "②재다운로드 후 v3 파싱이 UNZIP_FAIL 527 을 RATE_LIMIT_020 / NO_SOURCE_* / 진짜손상 으로 자동 분해하고, ",
  "PARSER_ERROR 620 의 진짜 사유(현재 parse_note 전건 공란)가 그때 처음 드러난다. ",
  "③2005~2016 은 **별개 항목** — 파싱이 아니라 수집 미실행이다(체크포인트 범위 2017-03~, 이전 행 0건). 범위 확장 결정 필요. ",
  "④②결과 전에는 능력 게이트로 닫지 말 것 — 측정된 적 없는 것을 불가로 확정하는 것이다. ",
  "⑤EV: 계약 lane 의 유일한 미확립 lead(w_amt ΔIR +0.1158 · 회수율 27.9%)가 커버-시대 교락으로 막혀 있고, ",
  "이 구간이 그 교락을 깨는 유일한 독립 표본이다.")

Q$updated <- "2026-08-09"
res <- write_frontier_queue(Q)
cat(sprintf("FQ-195 선행조건 정정 — added=%d removed=%d 총 %d\n", res$added, res$removed, res$n))
