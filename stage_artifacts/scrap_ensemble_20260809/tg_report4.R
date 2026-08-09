#!/usr/bin/env Rscript
# tg_report4.R — FR_002 정식 등재 + 절대 천장 판정 텔레그램 (v7 SOT · 원칙 9)
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
PROJ <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", ""))
if (!nzchar(PROJ)) PROJ <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
setwd(PROJ)
OUT <- file.path(PROJ, "stage_artifacts/scrap_ensemble_20260809")
CH  <- file.path(OUT, "charts"); dir.create(CH, showWarnings=FALSE, recursive=TRUE)

source(file.path(PROJ, "02_Infrastructure/telegram/tg_chart_pack.R"))
bt <- readRDS(file.path(PROJ, "04_Research/factor_rotation/output/FR_002_bt_result.rds"))
p1 <- tg_chart_pack_from_bt(bt, out_dir = CH,
        title = "FR_002 폐지 풀 배분 (무조건부 top-10)",
        metrics_note = "샤프 0.786 · PORT_t 1.242 · 칼마 0.398 · 표본외 유지율 0.046",
        prefix = "fr002_")
p2 <- tg_chart_sweep(
  labels = c("폐지 풀 무작위탐색", "폐지 풀 완전예지", "폐지 풀 개별최강",
             "우량 풀 완전예지 13종", "우량 풀 완전예지 10종", "우량 풀 완전예지 5종", "우량 풀 개별최강"),
  values = c(1.647, 2.036, 2.226, 2.207, 2.632, 3.545, 3.923),
  out_dir = CH, title = "절대 PORT_t 천장 — 폐지 풀은 완전예지로도 문턱 미달",
  value_label = "다중검정 t값 (벤치마크 대비 NW lag-3)", hline = 2.95,
  hline_label = "자본 문턱 2.95", highlight = "폐지 풀 완전예지", filename = "abs_ceiling.png")
p3 <- tg_chart_sweep(
  labels = c("5종", "10종", "20종", "30종", "50종", "85종 전체"),
  values = c(2.036, 2.006, 1.722, 1.510, 1.123, 0.342),
  out_dir = CH, title = "폐지 풀 완전예지 선별 — 좁힐수록 오르지만 문턱엔 못 닿음",
  value_label = "다중검정 t값 (벤치마크 대비)", hline = 2.95, hline_label = "자본 문턱 2.95",
  highlight = "5종", filename = "expost_k_curve.png")
charts <- c(p1, p2, p3)
cat("[charts]", length(charts), "\n")

source(file.path(PROJ, "02_Infrastructure/telegram/telegram_notify.R"))
tg_agent_brief(
  agent = "Q-Lead",
  title = "폐지 전략 재활용 종결 판정 — 방법이 아니라 재료의 문제였습니다 (FR_002 등재)",
  sections = list(
    list(type = "summary", emoji = "📌",
         body = "미리 정답을 알고 골라도 문턱에 못 갑니다 — 폐지 풀에 자격 알파가 없습니다."),

    list(type = "bullet", emoji = "📖", heading = "쉬운 설명",
         items = c(
           "질문: 선별을 더 정교하게 하면 자본 문턱을 넘을 수 있는지 확인했습니다",
           "방법: 미리 정답을 아는 상태로 최적 조합을 골라 도달 가능한 상한을 쟀습니다",
           "결과: 완전예지 상한이 2.04 로 문턱 2.95 에 못 미칩니다",
           "대조: 똑같은 방법으로 우량 풀은 3.55 까지 올라갑니다",
           "의미: 선별 기법 문제가 아니라 재료 자체의 한계입니다")),

    list(type = "kv", emoji = "📊", heading = "핵심 수치",
         kv = list(
           "폐지천장" = "완전예지 2.036 · 개별최강 2.226 (문턱 2.95)",
           "우량천장" = "완전예지 3.545 · 개별최강 3.923",
           "실측회수" = "FR_002 실측 1.242 = 천장의 61%",
           "문턱통과" = "폐지 85개 중 0개 · 우량 13개 중 1개",
           "정식등재" = "FR_002 grade C · 자본 관문 4개 전부 미달")),

    list(type = "bullet", emoji = "🚩", heading = "주의",
         items = c(
           "좁혀 고를수록 낙폭이 커집니다 (5종 54.1% 대 85종 40.5%)",
           "칼마는 어느 조합에서도 0.27~0.34 에 갇힙니다 (합격선 0.64)",
           "축소추정·머신러닝은 천장에 막혀 실익이 없습니다",
           "직전 보고의 t값 2.86 은 풀 내부 기준이었습니다 — 시장 대비는 1.24",
           "표본외 유지율 0.046 으로 최근 구간에서 우위가 소멸합니다")),

    list(type = "bullet", emoji = "➡️", heading = "다음",
         items = c(
           "선별 정교화 방향은 접고 재료 교체로 재조준합니다",
           "폐지 모듈을 소비면 7종에 순회 적용해 다른 쓰임을 찾습니다",
           "비수익 원천 모듈이 풀에 들어오면 천장이 재산정됩니다",
           "판정: 자본 배정 없음 — FR_002 는 참고용 등재이며 운용 반영 없습니다"))
  ),
  charts = charts,
  footer = "📚 FR_002 · factor_rotation_registry.json · p0n_absolute_ceiling.json")
cat("[tg] 발송 완료\n")
