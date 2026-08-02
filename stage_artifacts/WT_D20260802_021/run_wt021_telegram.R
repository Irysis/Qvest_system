# =============================================================================
# run_wt021_telegram.R — WT-D20260802_021 Alpha 브리핑 (tg_agent_brief 단일 진입점)
# 실행: Rscript -e 'source("stage_artifacts/WT_D20260802_021/run_wt021_telegram.R")'
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT_D20260802_021")
source("02_Infrastructure/telegram/telegram_notify.R")
source("02_Infrastructure/telegram/tg_chart_pack.R")

R <- readRDS(file.path(OUT, "wt021_results.rds"))

ch1 <- tg_chart_sweep(
  c("EW 5팩터 합성", "모멘텀 단일(최강)", "양-전이 2팩터만(probe)"),
  c(0.338, 2.050, R$pos2$portfolio_alpha_t_nw_lag3),
  out_dir = file.path(OUT, "charts"),
  title = "WT-021 알파 t값 — 조합 손실은 성분 자격의 문제 (295개월)",
  value_label = "portfolio alpha t값 (NW lag-3)",
  hline = 2.95, hline_label = "자본 관문 2.95",
  highlight = "양-전이 2팩터만(probe)")

a <- R$m1$attr
ch2 <- tg_chart_sweep(
  a$advocate, a$contrib_ann_pct,
  out_dir = file.path(OUT, "charts"),
  title = "WT-021 slot 잠식 귀속 — 합성이 밀어 넣은 종목의 실현 기여 (%/yr)",
  value_label = "밀려난 단일-최강 종목 대비 실현 기여 (연 %p)",
  highlight = "Q01_EB")

tg_agent_brief(
  agent = "Alpha",
  title = "WT-D20260802_021 ALPHA_DONE — 다팩터 합성 손실 기전 확정: slot 잠식 지배 (FQ-116)",
  sections = list(
    list(type = "summary", emoji = "\U0001F4CC",
         body = "3회 정합 미스터리(조합이 단일 최강에 지는 현상) 기전 확정 — 약한 팩터의 top-25 자리 잠식이 손실의 75%. 섞기 자체가 아니라 '누구와 섞는가'의 문제"),
    list(type = "kv", emoji = "\U0001F4CA", heading = "사전등록 3기전 판별 (분해 실측, 295개월)",
         kv = list(
           "M1 slot 잠식" = "지지·지배 — 손실 -8.27%/yr의 75% (강건 59~78%)",
           "M2 평균화 뭉갬" = "독립 기여 기각 — 양-전이만 섞으면 손실 소멸",
           "M3 커버리지 이질" = "기각 — 이질 실재하나 |t| 0.88 < 기각선 1",
           "합성-단일 top25 겹침" = "4.4/25 (월 20.6자리 교체) — 잠식 실재",
           "Grinold 깨진 항" = "TC(전이) — 정보계수 5/5 양성, 전이 2/5 음성",
           "극단 반례 D03_EWMA" = "정보계수 t +3.71 1위인데 알파 t -1.73 꼴찌",
           "검증 게이트" = "parity 0.00e+00 + 항등식 5.6e-17 PASS")),
    list(type = "bullet", emoji = "\U0001F9E0", heading = "쉬운 설명",
         items = list(
           "포트폴리오는 25자리뿐 — 5개 팩터 점수를 평균 내면 '여럿이 조금씩 좋아하는 종목'이 뽑힙니다",
           "그 종목들이 '최강 팩터가 확실히 좋아하는 종목'을 자리에서 밀어냅니다 (월평균 20.6자리)",
           "밀어 넣은 쪽이 밀려난 쪽보다 못 벌어서 조합이 지는 것 — 그 몫의 4분의 3이 약한 팩터들",
           "실전 수익이 검증된 2개만 섞으면 손실이 사라짐 — 분산 효과는 성분이 진짜일 때만 작동",
           "결론: 조합 자격 심사는 순위 상관(정보계수)이 아니라 실전 top-25 알파 t값으로")),
    list(type = "bullet", emoji = "\U0001F6A9", heading = "판정 평문 + 정직 경계",
         items = list(
           "판정: 기전 확정 라운드 — 자본 편입 주장 없음 (alpha 발굴 0건 정직 신고)",
           "양-전이 2팩터 probe(t +2.49)는 채택 후보 아님 — in-sample 선별 + 관문 2.95 미달",
           "적대 자기검증 5건: 귀속 규칙 민감도 실측(강건), 판별 문턱 사후 완화 0건",
           "미래참조: 신규 신호 구축 0 — 검증 승계 패널만 재소비, PIT 자가점검 clean")),
    list(type = "bullet", emoji = "\U000027A1", heading = "다음 단계 (frontier 큐 등재 완료)",
         items = list(
           "FQ-121: 조합 자격 게이트를 IS 구간에서 걸고 OOS 확인 — 조합 lane 재개 조건",
           "FQ-122: 전이-음성·정보계수-양성 팩터 2건을 제외필터/타이브레이커로 회수 실측",
           "risk-research 소비면: 저변동 계열은 알파 자리가 아닌 위험 축 입력으로 재배치 권고",
           "부활 조건: 5팩터 EW-류 재도전은 해당 팩터 꼬리-전이 양전 실측 시에만"))),
  charts = c(ch1, ch2))
cat("[tg] 발송 완료\n")
