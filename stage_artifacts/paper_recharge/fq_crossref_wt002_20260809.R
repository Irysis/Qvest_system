#!/usr/bin/env Rscript
# fq_crossref_wt002_20260809.R — FQ-183 에 WT-D20260809_002 프레임 불일치 교차참조 등재.
# 착수 전 확인에서 발견: 두 라운드가 **같은 축(심도-표적 노출 축소)** 을 **다른 base** 에서 재고 있다.
suppressMessages(library(jsonlite))
setwd(Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
source("02_Infrastructure/ops/frontier_queue_io.R")

Q <- read_frontier_queue()
hit <- which(vapply(Q$entries, function(x) identical(as.character(x$id %||% ""), "FQ-183"), logical(1)))
stopifnot(length(hit) == 1L)

Q$entries[[hit]]$concurrent_round_conflict <- paste0(
  "★WT-D20260809_002 (theme=tail_targeted_regime_overlay) 가 **같은 축**을 동시 측정 중이다 — ",
  "제목 '국면 라벨 꼬리 표적 오버레이 — 사건-조건부 자격을 **심도-표적 노출 축소로만** 소비'. ",
  "본 FQ 의 깊이 축과 같은 질문이다. ",
  "★★그런데 **base 가 다르다**: WT-002 incumbent_base = 05_Production/2-2.STR_1715_FaithTrend(퇴역 슬롯) + ",
  "산식 `ret_noL4 = beta_R05 × m4 × ret_orig − |Δbeta_R05|×15bps`. ",
  "본 FQ = 2-4 현 admitted 캐리어 + **ret_net 앵커 권위** 노출. ",
  "⇒ 2026-08-09 β_R05 권위 판정 실측에 따르면 `β×m4` 는 rds 앵커월 162/271 에서 ret_net 을 재현하지 못한다",
  "(cor 0.575 · 100개월 0.02 초과 이탈). WT-002 의 base 산식이 바로 그 재계산 산식이다. ",
  "★두 라운드 결론을 나란히 인용하기 전에 base 를 반드시 병기할 것 — ",
  "중복 측정보다 위험한 건 중복을 모른 채 두 판정이 다른 프레임에서 갈리는 것이다.")

Q$entries[[hit]]$qlead_actions_pending <- paste0(
  "① WT-002 request.json 은 alpha-research 가 브리핑에서 **재구성**한 파일이고 provenance_note 가 ",
  "'Q-Lead 는 이 파일을 정본으로 승인하거나 교체할 것' 을 요구한다 — 미처리. ",
  "② WT-002 id_namespace_warning: 브리핑 인용 'FQ-143' 은 실제로 CV_Vol(config_scoped_negative_20260804)이라 ",
  "본 라운드와 무관하며 실제 계보 앵커는 FQ-119 + 08-08 라벨 자격 실측 — **Q-Lead 발번 정정 필요**, 미처리. ",
  "③ base 정합: WT-002 를 현 admitted(2-4) base 로 재측정할지, 또는 2-2 base 결과를 'legacy-base scoped' 로 라벨할지 판정 필요.")

Q$updated <- "2026-08-09"
res <- write_frontier_queue(Q)
cat(sprintf("FQ-183 교차참조 등재 — added=%d removed=%d 총 %d\n", res$added, res$removed, res$n))
