# =============================================================================
# run_wt001_telegram.R — WT-D20260803_001 Alpha 브리핑 (tg_agent_brief 단일 진입점)
# 실행: Rscript -e 'source("stage_artifacts/WT_D20260803_001/run_wt001_telegram.R")'
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT_D20260803_001")
source("02_Infrastructure/telegram/telegram_notify.R")
source("02_Infrastructure/telegram/tg_chart_pack.R")

R <- readRDS(file.path(OUT, "wt001_fm_results.rds"))

# 차트 1 — 스펙별 상호작용 t값 (판별 문턱 +2.0 대비)
lab1 <- c("통제 전 (Arm A)", "★사전등록 primary (D35+D45 통제)", "rank x D35 병렬 (Arm C)",
          "신호 1개월 지연 (lag1)", "상위 40종 국소 검정", "승계: 배제-대체 스프레드 (WT-022)")
val1 <- round(c(R$verdict$t_A, R$verdict$t_B, R$verdict$t_C, R$verdict$t_lag1,
                R$top40$ctrl$t, 1.54), 2)
ch1 <- tg_chart_sweep(
  labels = lab1, values = val1, out_dir = file.path(OUT, "charts"),
  title = "WT-001 MAX5 x 알파랭크 상호작용 t값 — 전 스펙 판별 문턱(+2.0) 미달",
  value_label = "Newey-West t값 (lag 3)", hline = 2.0, hline_label = "사전등록 판별 문턱 +2.0",
  highlight = "★사전등록 primary (D35+D45 통제)")

# 차트 2 — 알파랭크 5분위별 MAX5 상하위 스프레드 (%/월)
sp <- as.data.table(R$double_sort$spread_by_rank)
ch2 <- tg_chart_sweep(
  labels = sprintf("랭크 %d분위%s (t %+.2f)", sp$q_rank,
                   ifelse(sp$q_rank == 5, " (최상위)", ifelse(sp$q_rank == 1, " (최하위)", "")), sp$t_nw),
  values = round(100 * sp$mean_spread, 2),
  out_dir = file.path(OUT, "charts"),
  title = "WT-001 알파랭크 분위별 MAX5 상하위 익월수익 스프레드 — 커지지만 어느 분위도 유의 미달",
  value_label = "MAX5 상위 - 하위 익월수익 스프레드 (%/월)",
  highlight = sprintf("랭크 5분위 (최상위) (t %+.2f)", sp[q_rank == 5, t_nw]))

tg_agent_brief(
  agent = "Alpha",
  title = "WT-D20260803_001 ALPHA_DONE — MAX5 승자 표지 가설 미확정: 어제의 +1.16%/월은 우연 범위",
  sections = list(
    list(type = "summary", emoji = "\U0001F4CC",
         body = "알파랭크 x MAX5 상호작용 t +0.234 (문턱 +2.0) — 배제도 가산도 실코드 소비 근거 없음, 현행 유지가 실측 정답"),
    list(type = "kv", emoji = "\U0001F4CA", heading = "핵심 실측 (256개월 · 월평균 231종 · 사전등록 단일시험)",
         kv = list(
           "판별 기준" = "상호작용 t +2.0 이상 = 승자 표지 / 2 미만 = 미확정 (사전 고정)",
           "★단일 판별값" = "t +0.234 — 미확정 (사전등록 판정)",
           "보조 스펙" = "통제 전 -0.08 / 병렬 +1.28 / 지연 +1.19 — 전부 미달",
           "국소 검정" = "상위 40종 안 t +0.34 · 최상위 분위 스프레드 t +1.54 — 3갈래 일관 미달",
           "검정 실효" = "무작위 순열 5회 전부 |t| 1.2 이하 + 동월 라벨 위반 주입 차단 발화 실증",
           "알파랭크 자체" = "주효과 t +6.23 — 현행 랭킹의 예측력은 건재 (본 라운드는 보조신호 판별)",
           "주의 국면 셀" = "t +2.05 (13개월) — 어제와 독립 2회 정합, 승격 아닌 후속 사전등록 대상",
           "초대형주 셀" = "t +2.76 — 축약 스펙 저검정력, 미확정 프론티어",
           "팩터 DB 발견" = "63일 변동성 팩터(D35)는 등재돼 있는데 소비자 0 — 본 라운드가 첫 사용")),
    list(type = "bullet", emoji = "\U0001F9E0", heading = "쉬운 설명",
         items = list(
           "어제 '급등 이력 종목을 빼면 오히려 손해(+1.16%/월)'가 나와, 반대로 얹으면 이득인지 오늘 정식 검정했습니다",
           "결론: 그 +1.16%는 통계적으로 우연의 범위입니다 — 뺄 근거도, 얹을 근거도 없습니다",
           "즉 지금 운용 중인 포트폴리오를 바꾸지 않는 것이 데이터가 지지하는 정답입니다",
           "급등 이력 재료의 쓸모는 수익 예측이 아니라 위험 관리 쪽임이 다시 확인됐습니다",
           "부수 발견: '주의' 국면에서만 효과가 있어 보이는 신호가 이틀 연속 잡혀 후속 검증 예정입니다")),
    list(type = "bullet", emoji = "\U0001F6A9", heading = "판정 평문 + 유의점",
         items = list(
           "판정: 미확정 (INCONCLUSIVE) — 사전등록 문턱 미달, 그 자체가 결론 (자본 주장 없음)",
           "방향 반전 소비 측정은 사전등록대로 미실행 (발동 조건 t +2.0 미충족)",
           "스코프: 선형 상호작용·1개월 지평 조건부 — 국면·초대형주·비선형 축은 미검",
           "무결성: Self-Adversarial 5건 기록 · 공분산/비중 산출 없음 · PIT 위반 주입 발화 확인")),
    list(type = "bullet", emoji = "\U000027A1", heading = "다음 단계",
         items = list(
           "1순위: 주의 국면 조건부 MAX5 소비 사전등록 라운드 (독립 2회 정합 — 검정력 보강 설계)",
           "2순위: 초대형주 한정 상호작용 재검 (pooled 패널로 변동성 통제 포함)",
           "3순위: D35 63일 변동성 팩터의 위험모델 첫 배선 (생산-소비 단절 회수)",
           "Risk Agent 전달: MAX5 재료는 위험모델 소비면이 정공 — WT-020 제안과 합류"))),
  charts = c(ch1, ch2))
cat("[tg] 발송 완료\n")
