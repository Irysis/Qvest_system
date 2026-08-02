# =============================================================================
# run_wt010_telegram.R — WT-D20260802_010 Alpha 브리핑 (tg_agent_brief 단일 진입점)
# 실행: Rscript -e 'source("stage_artifacts/WT_D20260802_010/run_wt010_telegram.R")'
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT_D20260802_010")
source("02_Infrastructure/telegram/telegram_notify.R")
source("02_Infrastructure/telegram/tg_chart_pack.R")

R <- readRDS(file.path(OUT, "wt010_eval_results.rds"))
b <- R$bt$OT_W1_RTAIL_63
pr <- as.data.frame(b$period_returns)

charts <- tg_chart_pack(pr, out_dir = file.path(OUT, "charts"),
  title = "WT-010 최적수송 분포형상 팩터 (Wasserstein)",
  metrics_note = sprintf("알파 t값 %+.2f · 순 샤프지수 %.2f · 회전율 연 %.0f%%",
                         b$portfolio_alpha_t_nw_lag3, b$net_sr, 100 * b$turnover_annual))

lab <- c("PRIMARY 우미부", "좌미부", "형상 총거리", "비정규화", "위치 성분", "스케일 성분",
         "왜도 대조", "첨도 대조", "MAX5 대조", paste0("치환 대조군 ", 1:5))
vals <- c(b$portfolio_alpha_t_nw_lag3,
          sapply(R$bt[c("OT_W1_LTAIL_63", "OT_W1_SHAPE_63", "OT_W1_RAW_63",
                        "OT_MEANC_63", "OT_SCALEC_63", "SKEW63", "KURT63", "MAX5_63")],
                 function(x) x$portfolio_alpha_t_nw_lag3),
          sapply(R$placebo, `[[`, "port_t"))
ch2 <- tg_chart_sweep(lab, vals, out_dir = file.path(OUT, "charts"),
  title = "WT-010 방향 분해·스칼라 대조군·치환 대조군",
  value_label = "포트폴리오 알파 t값", hline = 2.95, hline_label = "자본 게이트 2.95",
  highlight = "PRIMARY 우미부")

tg_agent_brief(
  agent = "Alpha",
  title = "WT-D20260802_010 ALPHA_DONE — 최적수송 분포형상: 게이트 미달·기전 반증",
  sections = list(
    list(type = "summary", emoji = "\U0001F4CC",
         body = "수학 심화 2호(Wasserstein) — 신호는 치환 대조군과 구분 불가, 기전은 수급으로 반증. 후속 3건 등재."),
    list(type = "kv", emoji = "\U0001F4CA", heading = "핵심 실측 (259개월, canonical)",
         kv = list(
           "포트폴리오 알파 t값" = "-1.24 — 자본 게이트 2.95 미달, 치환 대조군 대역 [-1.52,-0.25] 내부",
           "동일가중 벤치 기준" = "-2.05 — 벤치 구성 문제로 구제 안 됨 (양쪽 기각)",
           "정보계수" = "+0.019 (t값 3.57) — 대조군 밖, 회피-신호는 실재하나 상위 25종 편입으로 전이 실패",
           "스칼라 대조군" = "MAX5 정보계수 +0.047 > 본 팩터 +0.019 — 분포-거리의 우월 주장 실측 미성립",
           "직교성" = "기존 6팩터와 상관 0.17 이하 (정규화가 모멘텀·변동성 채널을 구성적으로 소거)",
           "기전 검정" = "신호창 개인 순매수 t값 -7.27 — 부호 역전, 추격 서사 기각",
           "회전율" = "연 1557% — 제약 1100% 초과",
           "구현 검증" = "닫힌형 이론값 대조 9건 전부 통과 (위반 주입 2종 검출 확인)")),
    list(type = "bullet", emoji = "\U0001F9E0", heading = "쉬운 설명",
         items = list(
           "최근 3개월 일간수익의 분포 모양 전체를 시장 평균 모양과 비교해 편차를 잰 팩터입니다",
           "오른쪽 꼬리(큰 상승일)가 두꺼운 복권형 종목은 다음 달 성과가 나쁘다는 가설이었습니다",
           "실측: 개인은 그런 종목을 사는 게 아니라 팔고 있었고(가설 반증), 분포 전체를 재도",
           "왜도·첨도 같은 단순 요약값보다 예측력이 나아지지 않았습니다")),
    list(type = "bullet", emoji = "\U0001F6A9", heading = "판정 평문 + 주요 결함",
         items = list(
           "판정: 종목 선정 편입 불가 — 신호가 형상 정보를 지운 치환 대조군과 구분 안 됨",
           "사전등록 기전(개인 복권수요 추격) 반증 — 개인은 점프 종목을 순매도 (역방향 규칙성)",
           "재탕 판별: 기존 팩터 재조합은 아니나(상관 0.5 미만) 예측력 추가도 없음",
           "원인: 63일 창의 분포 형상 추정이 표본 잡음 수준 (실측 편차 = 잡음 바닥)",
           "시그니처(1호)와 같은 벽 재확인 — 병목은 표현력이 아니라 상위 25종 편입 전이층")),
    list(type = "bullet", emoji = "\U000027A1", heading = "다음 단계",
         items = list(
           "1순위: 복권형 제외-필터 소비면 — 강한 스칼라(MAX5)로 사전등록 후 북 한계기여 측정",
           "2순위: 수급-흡수 조건부 점프 라운드 — 개인 순매도를 흡수한 주체 조건부 수익 분화",
           "3순위: 전이-벽 반증 증거를 계층 병목 지도에 적립 + 리스크 모델에 꼬리형상 제안"))),
  charts = c(charts, ch2))
cat("[tg] 발송 완료\n")
