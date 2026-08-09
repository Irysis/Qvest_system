#!/usr/bin/env Rscript
# p3b_close.R — NP-1 결과 FQ 반영 + 텔레그램 (라운드 연속 마감)
suppressPackageStartupMessages({ library(jsonlite) })
PROJ <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", ""))
if (!nzchar(PROJ)) PROJ <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
setwd(PROJ); OUT <- file.path(PROJ, "stage_artifacts/scrap_ensemble_20260809")

## ── FQ-174 NP-1 결과 반영 (정본 writer) ──────────────────────────────
source(file.path(PROJ, "02_Infrastructure/ops/frontier_queue_io.R"))
Q <- read_frontier_queue()
ids <- vapply(Q$entries, function(e) as.character(e$id)[1], character(1))
i <- which(ids == "FQ-174"); stopifnot(length(i) == 1)
Q$entries[[i]]$np1_result_20260809 <- paste0(
  "NP-1 실측 완료(p3_np1_pool_hygiene, 사전등록 = 스크립트 헤더): 통합 풀 99 dedup(A/B 14 + C/F 85→83)에서 ",
  "지속-패자 배제 3 arm 전부 수익축 강양성 — hyg10 t_NW3 +3.527 / hyg20 +3.557 / hygQ1 +3.355 ",
  "(Bonferroni 2.39 전부 통과 · 무작위 배제 대조 median +0.56 과 분리 · Calmar 0.288→0.315). ",
  "★기전 확인: 배제된 하위 20 = **100% grade F** — 규칙이 NAV 만으로 기존 등급 라벨을 재발견. ",
  "그러나 **사전등록 판정 = NEGATIVE**: MDD 비악화 조건 위반(38.3→38.8~38.9%, +0.5%p 악화). ",
  "기전 = 패자 배제가 저베타 방어 실패작까지 걷어내 풀 beta 를 올림 — 수익과 낙폭이 beta 로 묶인 ",
  "본 라운드 핵심 구조의 재확인. ⇒ 처분: (a) '수익 위생' 능력은 확립(capability_established) — 단 소비처는 ",
  "MDD 무관 맥락(예: FR 무조건부 광역 풀 소비 시 전처리)에 한정 (b) RCMA 와의 정합 주의 — RCMA 는 ",
  "F-overall 국면 specialist 를 의도적으로 차용하므로(스킬 §5) 일괄 F-배제와 충돌, 위생 규칙은 ",
  "**무조건부 소비 경로에만** 적용 가능 (c) MDD 레버로는 부적격 — 도훈 핵심 관심축에서 이 규칙은 답이 아님."
)
res <- write_frontier_queue(Q)
cat("[fq174-np1] n=", res$n, " added=", length(res$added), " removed=", length(res$removed), "\n", sep="")

## ── 텔레그램 ──────────────────────────────────────────────────────────
source(file.path(PROJ, "02_Infrastructure/telegram/tg_chart_pack.R"))
CH <- file.path(OUT, "charts")
p1 <- tg_chart_sweep(
  labels = c("무작위 10개 배제 (대조)", "하위 25% 배제", "하위 10개 배제", "하위 20개 배제"),
  values = c(0.564, 3.355, 3.527, 3.557),
  out_dir = CH, title = "통합 풀 99개 — 패자 배제는 수익엔 통하나 낙폭엔 실패",
  value_label = "기준 대비 t값 (NW lag-3)", hline = 2.39, hline_label = "다중검정 참고선 2.39",
  highlight = "하위 20개 배제", filename = "np1_hygiene.png")
source(file.path(PROJ, "02_Infrastructure/telegram/telegram_notify.R"))
tg_agent_brief(
  agent = "Q-Lead",
  title = "후속 검증 — 패자 걸러내기는 수익엔 통했지만 낙폭 조건에서 탈락했습니다",
  sections = list(
    list(type = "summary", emoji = "📌",
         body = "우량+폐지 통합 99개에서 패자 배제를 검증 — 수익 개선은 확실하나 낙폭이 늘어 사전 기준 탈락."),
    list(type = "bullet", emoji = "📖", heading = "쉬운 설명",
         items = c(
           "검증: 전체 전략 풀에서 성적 나쁜 것을 매달 걸러내는 규칙을 시험했습니다",
           "수익: 세 가지 배제 폭 전부 t값 3.4~3.6 으로 확실히 개선됩니다",
           "확인: 걸러진 하위 20개가 전부 F등급 — 규칙이 등급표를 스스로 재발견했습니다",
           "탈락: 최대낙폭이 0.5%p 늘었습니다 — 미리 정한 기준에 걸립니다",
           "기전: 패자 중엔 방어 실패작도 있어 걷어내면 시장 민감도가 올라갑니다")),
    list(type = "kv", emoji = "📊", heading = "핵심 수치",
         kv = list(
           "수익개선" = "하위 20 배제 t값 3.56 (참고선 2.39 통과)",
           "대조분리" = "무작위 배제 0.56 대 실제 3.4~3.6",
           "낙폭악화" = "38.3% → 38.8~38.9% (+0.5%p)",
           "칼마"     = "0.288 → 0.315 (합격선 0.64 미달)",
           "판정"     = "사전등록 기준 NEGATIVE — 수익 위생 능력만 확립")),
    list(type = "bullet", emoji = "🚩", heading = "주의",
         items = c(
           "국면 심사(RCMA)는 F등급 국면 전문가를 의도적으로 쓰므로 일괄 배제와 충돌합니다",
           "적용 가능 범위는 국면 무관 광역 풀 소비 경로뿐입니다",
           "낙폭 관점에서 이 규칙은 답이 아닙니다 — 수익과 낙폭이 시장 민감도로 묶여 있습니다")),
    list(type = "bullet", emoji = "➡️", heading = "다음",
         items = c(
           "수익 위생 능력은 FR 광역 소비 경로 한정으로 기록해 두었습니다",
           "낙폭 축은 노출 조절 연구(별도 진행 중)가 유일한 남은 레버입니다",
           "판정: 자본 반영 없음 — 프론티어 큐에 처분 기록 완료"))
  ),
  charts = p1,
  footer = "📚 FQ-174 NP-1 · p3_np1_hygiene.json · metric_type=diagnostic_precheck",
  force = TRUE)  # 한글 제목 scope 정규화로 30분 잠금 동일-scope 충돌 — 별개 내용 후속 보고 명시 우회
cat("[tg] 발송 완료\n")
