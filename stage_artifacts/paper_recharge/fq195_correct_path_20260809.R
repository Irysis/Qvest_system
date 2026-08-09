#!/usr/bin/env Rscript
# fq195_correct_path_20260809.R — FQ-195 next_action ① 불가 정정(재처리할 문서가 없다).
suppressMessages(library(jsonlite))
setwd(Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
source("02_Infrastructure/ops/frontier_queue_io.R")
Q <- read_frontier_queue()
i <- which(vapply(Q$entries, function(x) identical(as.character(x$id %||% ""), "FQ-195"), logical(1)))
stopifnot(length(i) == 1L)

Q$entries[[i]]$local_doc_census_20260809 <- paste0(
  "★재처리 가능성 실측(.cache/dart/contract_docs, 5,583건 24MB): ",
  "연도 분포 2010:1 · 2015:2 · 2016:1 · **2017:52** · **2018:0** · 2019:626 · 2020:695 · 2021:911 · ",
  "2022:548 · 2023:374 · 2024:839 · 2025:986 · 2026:548. ",
  "**147바이트 파일 0건** — 에러 응답은 저장되지 않았다(unzip 실패로 버려짐). ",
  "⇒ 실패 1147건에 대응하는 **로컬 문서가 사실상 없다**(2017 52건 중 ok 29 → 재처리 여지 23건, 2018 은 0). ",
  "★따라서 구 next_action ①('이미 받은 문서에 v3 재실행, 비용 낮음, 선행')은 **불가**다 — 재처리할 원본이 없다.")

Q$entries[[i]]$next_action <- paste0(
  "★유일 경로 = **재다운로드**(API 일한도 소요, 무인 시간대). 그리고 그 앞에 배선 하나가 반드시 선행한다: ",
  "①**상태 라벨 분리** — 현행은 한도소진 / DART 014 원문부재 / 진짜 zip 손상을 전부 `UNZIP_FAIL` 로 뭉갠다. ",
  "실측 지문(147바이트 균일 527건)이 있으므로 크기·응답 본문으로 분리 가능하다. ",
  "라벨을 안 나누고 재다운로드하면 한도 소진이 다시 '원문 없음'으로 체크포인트에 영구 동결된다(3회째 계통). ",
  "②재다운로드 대상 = 2017-03~2018-12 실패 1147건(우선) + 2005~2016 미수집 구간(별개, 범위 확장 결정 필요). ",
  "③재다운로드 후 v3 파싱 → PARSER_ERROR 620 의 **진짜 사유**가 그때 처음 드러난다(현재 parse_note 전건 공란). ",
  "④★그 결과가 나오기 전에는 '능력 게이트'로 닫지 말 것 — 지금 닫는 것은 **측정된 적 없는 것을 불가로 확정**하는 것이다. ",
  "⑤비용/EV: 계약 lane 의 유일한 미확립 lead(w_amt ΔIR +0.1158, 회수율 27.9%)가 커버-시대 교락으로 막혀 있고, ",
  "이 구간이 그 교락을 깨는 유일한 독립 표본이다.")

Q$updated <- "2026-08-09"
res <- write_frontier_queue(Q)
cat(sprintf("FQ-195 경로 정정 — added=%d removed=%d 총 %d\n", res$added, res$removed, res$n))
