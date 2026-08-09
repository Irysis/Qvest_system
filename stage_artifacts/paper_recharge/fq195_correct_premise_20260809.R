#!/usr/bin/env Rscript
# fq195_correct_premise_20260809.R — FQ-195 전제 정정: 능력 게이트가 아니라 **재처리·재수집 미실행**.
suppressMessages(library(jsonlite))
setwd(Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
source("02_Infrastructure/ops/frontier_queue_io.R")
Q <- read_frontier_queue()
i <- which(vapply(Q$entries, function(x) identical(as.character(x$id %||% ""), "FQ-195"), logical(1)))
stopifnot(length(i) == 1L)

Q$entries[[i]]$hypothesis_prior_20260809 <- Q$entries[[i]]$hypothesis    # 원문 보존
Q$entries[[i]]$status <- "reprocessing_gate_open"
Q$entries[[i]]$title <- "DART 계약공시 pre2019 — 파싱 능력이 아니라 **재처리·재수집 미실행**(체크포인트 영구 동결)"

Q$entries[[i]]$premise_correction_20260809 <- paste0(
  "★등재 당시 전제('파서 v3 수리 이후에도 95.7% 실패 = 능력 부족')는 **행 단위 검증에서 반증됐다**. ",
  "실측(.cache/dart/contract_backfill 113개월, 7,497행): ",
  "①**doc_encoding·parser_version 이 실패 1147건 전부 NA** — v3 는 이 행들을 처리한 적이 없다. ",
  "v3 태그는 성공 29건·no_source 23건에만 붙어 있다. 체크포인트가 **구판 실행 결과를 그대로 들고 있고 재처리가 안 됐다**. ",
  "내가 '수리 이후 수치'라 한 것은 **파일 mtime 기준**이었고 행 단위로는 구판 산물이었다. ",
  "②UNZIP_FAIL 527건의 parse_note 가 **고유 1개 = 'unzip fail (147 bytes)' 전건 동일**. ",
  "정상 문서가 이렇게 균일할 수 없다 — DART API 에러 응답(한도 소진 등)을 zip 으로 받은 지문이고, ",
  "'일한도 소진(020)이 원문 없음으로 체크포인트에 영구 동결'이라는 기왕의 경고와 정확히 일치한다. **재시도 대상**. ",
  "③PARSER_ERROR 620건의 parse_note 가 **전건 빈 문자열** — 사유가 기록되지 않았다. 재처리해야 사유를 안다. ",
  "④★'2005~2016 조선·플랜트 사이클' 구간은 **파싱 실패가 아니라 미수집**이다 — 체크포인트 범위는 2017-03~2026-07 이고 ",
  "2017 이전 행은 **0건**. pre2019 라 불린 것은 실제로 **2017~2018 뿐**이다.")

Q$entries[[i]]$next_action <- paste0(
  "①**재처리(비용 낮음, 선행)**: 이미 받은 문서에 v3 파서를 다시 돌려 1147건의 parse_status/parse_note 를 재산출. ",
  "PARSER_ERROR 620건의 진짜 사유가 여기서 드러난다(현재 공란). ",
  "②**147바이트 재다운로드**: UNZIP_FAIL 527건은 동일 에러 응답이므로 재크롤 대상. ",
  "★API 일한도가 걸리는 작업이라 **무인 시간대 실행**이 맞다. 한도 소진을 다시 'UNZIP_FAIL'로 뭉개지 않도록 ",
  "상태 라벨 분리(한도소진 / DART 014 원문부재 / 진짜 손상)를 먼저 배선할 것. ",
  "③**2005~2016 은 별개 항목** — 파싱이 아니라 수집 미실행이다. FQ-002 revival 의 그 구간은 크롤 범위 확장이 선행. ",
  "④①②가 끝나야 '능력 게이트인가'를 비로소 물을 수 있다 — 지금 닫는 것은 **측정 안 된 것을 불가로 확정**하는 것이다.")

Q$entries[[i]]$wall_check <- paste0(
  "실측 근거 = stage_artifacts/paper_recharge/fq195_pre2019_decomp_20260809.json + 행 단위 parse_note/parser_version 분해. ",
  "pre2019(=2017-03~2018-12) 1199행 중 OK 29 · UNZIP_FAIL 527(147B 균일) · PARSER_ERROR 620(사유 공란) · no_source 23. ",
  "2019+ 실패는 전혀 다른 사유(NO_REVENUE 134 · NO_AMOUNT 102 · DECODE_FAIL 3)로 **겹치지 않는다**.")

Q$updated <- "2026-08-09"
res <- write_frontier_queue(Q)
cat(sprintf("FQ-195 전제 정정 — added=%d removed=%d 총 %d\n", res$added, res$removed, res$n))
cat(sprintf("  status → %s\n", Q$entries[[i]]$status))
