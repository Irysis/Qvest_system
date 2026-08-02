# =============================================================================
# run_wt015_telegram.R — WT-D20260802_015 Alpha 브리핑 (tg_agent_brief 단일 진입점)
# 실행: Rscript -e 'source("stage_artifacts/WT_D20260802_015/run_wt015_telegram.R")'
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT_D20260802_015")
source("02_Infrastructure/telegram/telegram_notify.R")
source("02_Infrastructure/telegram/tg_chart_pack.R")

R <- readRDS(file.path(OUT, "wt015_results.rds"))
b <- R$bt$PRIMARY
pr <- as.data.frame(b$period_returns)

charts <- tg_chart_pack(pr, out_dir = file.path(OUT, "charts"),
  title = "WT-015 튜닝 5팩터 국면 로테이션 (primary)",
  metrics_note = sprintf("알파 t값 %+.2f · 순 샤프지수 %.2f · 회전율 연 %.0f%%",
                         b$portfolio_alpha_t_nw_lag3, b$net_sr, 100 * b$turnover_annual))

lab <- c("튜닝 로테이션", "튜닝 EW 정적", "base 로테이션", "모멘텀 단일(최강)")
vals <- c(R$bt$PRIMARY$portfolio_alpha_t_nw_lag3, R$bt$C1_EW$portfolio_alpha_t_nw_lag3,
          R$bt$C2_BROT$portfolio_alpha_t_nw_lag3, R$bt$C3_SINGLE$portfolio_alpha_t_nw_lag3)
ch2 <- tg_chart_sweep(lab, vals, out_dir = file.path(OUT, "charts"),
  title = "WT-015 알파 t값 — 로테이션 대 대조군 3종 (295개월)",
  value_label = "portfolio alpha t값 (NW lag-3)", hline = 2.95, hline_label = "자본 관문 2.95",
  highlight = "튜닝 로테이션")

tg_agent_brief(
  agent = "Alpha",
  title = "WT-D20260802_015 ALPHA_DONE — 국면 로테이션: 재탕 이하 판정 (D1 반증)",
  sections = list(
    list(type = "summary", emoji = "\U0001F4CC",
         body = "튜닝 5팩터 국면-조건부 로테이션 — 대조군 전부에 열위, 국면 전환월 기여 0. 판정: NEGATIVE (config 한정)"),
    list(type = "kv", emoji = "\U0001F4CA", heading = "canonical 실측 (top-25, 295개월, 순비용 15bps)",
         kv = list(
           "튜닝 로테이션 (primary)" = "알파 t값 +0.90 — 자본 관문 2.95에 크게 미달",
           "base 로테이션 (재탕 판별 대조군)" = "+1.40 — 튜닝판이 오히려 연 -1.9%p 열위 (t -1.22)",
           "튜닝 EW 정적 합성" = "+0.34 — 로테이션 우위 +2.7%p/yr는 유의 아님, 2017 이후 역전(-1.59)",
           "모멘텀 경로효율 단일" = "+2.05 — 로테이션이 최강 단일 팩터에도 열위 (t -1.26)",
           "국면 전환월 기여" = "라벨이 바뀐 69개월 한정 t -0.27 — 로테이션이 '움직인' 달의 기여가 없음",
           "회전율" = "연 7.5회 — 상한 11.0 이내 (관문 아님)")),
    list(type = "bullet", emoji = "\U0001F9E0", heading = "쉬운 설명",
         items = list(
           "시장 국면(위기/경계/중립/호황)에 따라 5개 팩터의 배합 비율을 매달 바꾸는 모델을 만들어 실측했습니다",
           "결과: 비율을 고정한 단순 배합보다 낫다고 말할 수 없고, 가장 강한 팩터 하나만 쓰는 것보다 오히려 나빴습니다",
           "결정적 증거: 국면이 실제로 바뀐 달만 골라 보면 이 모델의 기여가 0 — 겉보기 개선은 국면 대응이 아니라 그냥 특정 팩터를 오래 눌러담은 결과였습니다",
           "미래 국면 라벨을 몰래 미리 보여주는 실험(진단 전용)에서도 성적이 오히려 나빠짐 — 현 국면 라벨에는 팩터 배합에 쓸 정보 자체가 거의 없다는 뜻입니다",
           "도훈 님이 제시한 차별 가설(튜닝판은 팩터 간 상관이 낮아 국면 배분이 잘 될 것)은 실측으로 반증 — 튜닝판이 base판 로테이션보다도 나빴습니다")),
    list(type = "bullet", emoji = "\U0001F6A9", heading = "판정 평문 + 검증",
         items = list(
           "판정: 자본 편입 아님, 구 실패 config(국면 배분 계열)의 재탕 이하 — 정직 기각",
           "미래참조 검증 3중 통과: 라벨 타이밍 강제 가드 PASS + 위반 주입 시 차단 발화 확인 + 시차 스트레스 무붕괴",
           "기전 진단: 정보계수 비례 배분은 '정보계수는 좋은데 실현 수익은 나쁜' 팩터(저변동)에 비중을 몰아주는 구조적 역선택 — 시스템의 기존 실측 지식(전이 벽)과 정합",
           "배관 수리 2건: ① 측정기에 유니버스 오염 감지 가드 신설(어제 실사고 재발방지) ② 계약 로더의 침묵 미로드 결함 수리 — 둘 다 위반 주입 테스트로 실증")),
    list(type = "bullet", emoji = "\U000027A1", heading = "다음 단계",
         items = list(
           "국면 라벨 자체의 재설계가 상류 병목 — 현 라벨은 2026년 폭등장을 위기로 표기(실측) — 실현-하락 정합 라벨 검정 과제 등재",
           "배분 통계량을 정보계수가 아닌 실현 초과수익으로 바꾼 1규칙 재검은 조건부(기대값 낮음 — 큐 심사 후)",
           "진행 중인 모멘텀 순수판 검증(WT-013) 완료 후, 양수 팩터만의 소풀 정적 합성 재측정"))),
  charts = c(charts, ch2))
cat("[tg] 발송 완료\n")
