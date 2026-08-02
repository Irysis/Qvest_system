# =============================================================================
# run_wt006_telegram.R — WT-D20260802_006 Alpha 브리핑 (tg_agent_brief 단일 진입점)
# 실행: Rscript -e 'source("stage_artifacts/WT_D20260802_006/run_wt006_telegram.R")'
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT_D20260802_006")
source("02_Infrastructure/telegram/telegram_notify.R")
source("02_Infrastructure/telegram/tg_chart_pack.R")

R <- readRDS(file.path(OUT, "wt006_eval_results.rds"))
b <- R$bt$SIG_LEVY_PV_63
pr <- as.data.frame(b$period_returns)

charts <- tg_chart_pack(pr, out_dir = file.path(OUT, "charts"),
  title = "WT-006 경로 시그니처 (Levy area)",
  metrics_note = sprintf("알파 t값 %+.2f · 순 샤프지수 %.2f · 회전율 연 %.0f%%",
                         b$portfolio_alpha_t_nw_lag3, b$net_sr, 100 * b$turnover_annual))

lab <- c("PRIMARY 63일", "레벨1 가격", "레벨1 거래대금", "레벨2 시간-가격",
         "레벨2 시간-거래", "레벨3 ppv", "레벨3 pvv", "창 21일", "창 126일",
         paste0("셔플 대조군 ", 1:5))
vals <- c(b$portfolio_alpha_t_nw_lag3,
          sapply(R$bt[c("LVL1_P_63","LVL1_V_63","A_TP_63","A_TV_63",
                        "LOGSIG3_PPV_63","LOGSIG3_PVV_63","A_PV_W21","A_PV_W126")],
                 function(x) x$portfolio_alpha_t_nw_lag3),
          sapply(R$placebo, `[[`, "port_t"))
ch2 <- tg_chart_sweep(lab, vals, out_dir = file.path(OUT, "charts"),
  title = "WT-006 레벨 분해와 셔플 대조군",
  value_label = "포트폴리오 알파 t값", hline = 2.95, hline_label = "자본 게이트 2.95",
  highlight = "PRIMARY 63일")

tg_agent_brief(
  agent = "Alpha",
  title = "WT-D20260802_006 ALPHA_DONE — 경로 시그니처: 수익 미달·기전 확인",
  sections = list(
    list(type = "summary", emoji = "\U0001F4CC",
         body = "수학 심화 스마트베타 1라운드 — 수익 게이트 미달, 매집 기전은 수급으로 실증. 후속 4건 등재."),
    list(type = "kv", emoji = "\U0001F4CA", heading = "핵심 실측 (259개월, canonical)",
         kv = list(
           "포트폴리오 알파 t값" = "+1.23 — 자본 게이트 2.95 미달",
           "동일가중 벤치 기준" = "+1.93, 2017년 이후 -0.07 (양쪽 소멸)",
           "부기간" = "2015년 이전 +3.69, 이후 소멸 (감쇠 패턴)",
           "회전율" = "연 1578% — 제약 1100% 초과",
           "직교성" = "기존 5팩터와 상관 0.11 이하 — 신규 축 성립",
           "기전 검정" = "익월 기관+외인 매집 t값 +4.08 — 기전 지지",
           "구현 검증" = "이론값 대조 11건 전부 통과")),
    list(type = "bullet", emoji = "\U0001F9E0", heading = "쉬운 설명",
         items = list(
           "가격과 거래대금 중 무엇이 먼저 움직였는지, 경로의 순서를 재는 기하학 값입니다",
           "거래가 먼저 늘면 조용한 매집, 가격이 먼저 뛰면 추격 매수로 읽습니다",
           "매집 신호는 다음 달 기관·외국인 순매수로 실제 이어졌으나 초과수익 전이는 실패")),
    list(type = "bullet", emoji = "\U0001F6A9", heading = "판정 평문 + 주요 결함",
         items = list(
           "판정: 종목 선정 편입 불가 — 수익 신호가 게이트에 크게 못 미침",
           "순서 셔플 대조군과의 분리 여유가 얇음 — 수익 신호력 확립 불가",
           "2017년 이후 두 벤치 기준 모두 소멸 — 벤치 구성 문제로 구제 안 됨",
           "회전율 제약 위반 — 평활판은 사전등록 밖이라 후속으로 승계")),
    list(type = "bullet", emoji = "\U000027A1", heading = "다음 단계",
         items = list(
           "1순위: 수급 예측 소비면 — 매집 신호를 모니터링 경보·수급 팩터 강화에 사용",
           "2순위: 3개월 평활판으로 회전율 충족 후 재측정",
           "2순위: 시간-가격 면적 역방향 가설, 부호 사전 고정해 독립 재도전",
           "3순위: 2015년 이전 강세의 감쇠 시점 귀속"))),
  charts = c(charts, ch2))
cat("[tg] 발송 완료\n")
