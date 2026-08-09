#!/usr/bin/env Rscript
# tg_report5.R — 소비면 순회 결과 텔레그램 (라운드 마감 보고, v7 SOT · 원칙 9)
suppressPackageStartupMessages({ library(jsonlite) })
PROJ <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", ""))
if (!nzchar(PROJ)) PROJ <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
setwd(PROJ)
OUT <- file.path(PROJ, "stage_artifacts/scrap_ensemble_20260809")
CH  <- file.path(OUT, "charts")

source(file.path(PROJ, "02_Infrastructure/telegram/tg_chart_pack.R"))
p1 <- tg_chart_sweep(
  labels = c("랭킹 소비 (상위 10 선별)", "필터 소비 (하위 30 배제)", "필터 소비 (하위 20 배제)",
             "필터 소비 (하위 10 배제)"),
  values = c(1.310, 2.682, 3.049, 3.206),
  out_dir = CH, title = "같은 재료, 반대 소비 — 랭킹은 죽고 필터는 산다",
  value_label = "풀 동일가중 대비 t값 (NW lag-3)", hline = 2.0, hline_label = "유의선 2.0",
  highlight = "필터 소비 (하위 10 배제)", filename = "face2_filter.png")
p2 <- tg_chart_sweep(
  labels = c("풀 산포 → 다음달 급락 (감시신호)", "국면 라벨 지속성", "성과 순위 지속성(무조건부)",
             "시장 민감도 지속성"),
  values = c(-0.05, 0.09, 0.24, 0.564),
  out_dir = CH, title = "무엇이 지속되는가 — 성과가 아니라 위험 성질이 지속된다",
  value_label = "예측 상관 (높을수록 예측 가능)", hline = 0,
  highlight = "시장 민감도 지속성", filename = "face_persistence.png")
charts <- c(p1, p2)
cat("[charts]", length(charts), "\n")

source(file.path(PROJ, "02_Infrastructure/telegram/telegram_notify.R"))
tg_agent_brief(
  agent = "Q-Lead",
  title = "폐지 재활용 마감 — 버릴 것을 고르는 눈과 위험을 재는 자만 남았습니다",
  sections = list(
    list(type = "summary", emoji = "📌",
         body = "일곱 가지 쓰임새를 전부 검사 — 살아남은 것은 '나쁜 것 배제'와 '위험 측정' 둘입니다."),

    list(type = "bullet", emoji = "📖", heading = "쉬운 설명",
         items = c(
           "순회: 폐지 전략을 버리기 전에 일곱 가지 다른 쓰임새를 전부 검사했습니다",
           "발견1: 좋은 것을 고르는 눈은 없는데 나쁜 것을 걸러내는 눈은 있습니다",
           "발견2: 성과는 예측이 안 되지만 시장 민감도는 강하게 예측됩니다",
           "기전: 지속되는 것은 승자가 아니라 패자입니다 — 최악만 계속 최악입니다",
           "의미: 폐지 풀은 수익 재료가 아니라 위생 규칙과 위험 계측기로 씁니다")),

    list(type = "kv", emoji = "📊", heading = "핵심 수치",
         kv = list(
           "필터소비" = "하위 10 배제 t값 3.21 · 하위 20 배제 3.05 (풀 대비)",
           "위험계측" = "시장 민감도 예측 상관 0.564 (t값 15.4)",
           "무판별"   = "감시신호 lift 0.95배 · 국면 라벨 0.133 대 기저 0.122",
           "천장확정" = "완전예지 선별 2.04 < 자본 문턱 2.95",
           "이관"     = "시장 민감도 실측 3건 → 노출 조절 연구로")),

    list(type = "bullet", emoji = "🚩", heading = "주의",
         items = c(
           "필터 t값은 풀 내부 기준입니다 — 자본 자격 수치가 아닙니다",
           "정당한 쓰임 = 모듈 풀 심사 전에 지속 패자를 미리 배제하는 위생 규칙",
           "선별 정교화·머신러닝 방향은 천장에 막혀 철회했습니다",
           "낙폭 개선은 필터로도 안 됩니다 (41% 수준 유지)")),

    list(type = "bullet", emoji = "➡️", heading = "다음",
         items = c(
           "지속 패자 배제를 모듈 풀 심사 전처리로 승격 검토 (사전등록 후 A/B)",
           "시장 민감도 예측력을 위험모델 입력으로 공급 검토",
           "새 데이터 원천 모듈이 들어오면 천장을 다시 잽니다",
           "판정: 자본 배정 없음 — 전 결과 참고용이며 운용 반영 없습니다"))
  ),
  charts = charts,
  footer = "📚 FQ-174 마감 · p2_consumption_sweep.json · FR_002 등재 · metric_type=diagnostic_precheck",
  force = TRUE)  # 30분 중복잠금 명시 우회 — 동일 세션 내 별개 내용의 후속 보고 (SOT 부록 B)
cat("[tg] 발송 완료\n")
