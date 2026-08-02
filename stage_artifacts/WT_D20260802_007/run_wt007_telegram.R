# =============================================================================
# run_wt007_telegram.R — WT-D20260802_007 Alpha 브리핑 (tg_agent_brief 단일 진입점)
# 실행: Rscript -e 'source("stage_artifacts/WT_D20260802_007/run_wt007_telegram.R", encoding="UTF-8")'
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT_D20260802_007")
source("02_Infrastructure/telegram/telegram_notify.R")
source("02_Infrastructure/telegram/tg_chart_pack.R")

R <- readRDS(file.path(OUT, "wt007_eval_results.rds"))
b <- R$bt$INS_MAGQ3
pr <- as.data.frame(b$period_returns)

charts <- tg_chart_pack(pr, out_dir = file.path(OUT, "charts"),
  title = "WT-007 임원 매수 '참여의 질' (커밋 비중 정규화)",
  metrics_note = sprintf("알파 t값 %+.2f · 순 샤프지수 %.2f · 회전율 연 %.0f%%",
                         b$portfolio_alpha_t_nw_lag3, b$net_sr, 100 * b$turnover_annual))

lab <- c("PRIMARY 커밋비중+필터", "커밋비중(필터 없음)", "금액 집계(R9 재현)",
         "시퀀스(연속 방향)", "이벤트-창 매수", "동시 매수폭(R33 재현)",
         paste0("셔플 대조군 ", 1:5))
vals <- c(b$portfolio_alpha_t_nw_lag3,
          sapply(R$bt[c("INS_MAG_NOFILT3", "INS01_BASE3", "INS_SEQ12",
                        "INS_EVT3", "INS02_BREADTH6")],
                 function(x) x$portfolio_alpha_t_nw_lag3),
          sapply(R$placebo, `[[`, "port_t"))
ch2 <- tg_chart_sweep(lab, vals, out_dir = file.path(OUT, "charts"),
  title = "WT-007 3축 비교와 셔플 대조군",
  value_label = "포트폴리오 알파 t값", hline = 2.95, hline_label = "자본 게이트 2.95",
  highlight = "PRIMARY 커밋비중+필터")

tg_agent_brief(
  agent = "Alpha",
  title = "WT-D20260802_007 ALPHA_DONE — 임원 매수 3축: 벽을 구부리나 못 뚫음",
  sections = list(
    list(type = "summary", emoji = "\U0001F4CC",
         body = "임원 매수 신호를 '얼마나 크게 걸었나'로 재정의한 사전등록 라운드 — 기존 집계 대비 개선은 실측됐으나 자본 게이트 미달. 시퀀스 축은 기존 신호의 재탕으로 자체 기각."),
    list(type = "kv", emoji = "\U0001F4CA", heading = "핵심 실측 (258개월, canonical)",
         kv = list(
           "포트폴리오 알파 t값" = "+1.37 — 자본 게이트 2.95 미달",
           "기존 방식(R9 재현) 대비" = "+0.55 → +1.37, 월 +16bps 개선 (t +1.44, 유의 미달)",
           "동일가중 벤치 기준" = "-0.79 — 소형주 광역 프리미엄을 못 이김",
           "시퀀스 축 vs 기존 클러스터" = "순위상관 +0.805 — 같은 정보(재탕 판정)",
           "이벤트-조건부 축" = "월 2종목 커버리지 — 측정 불성립",
           "기전 검정(후속 수급)" = "t +1.41 — 미확립 (WT-006 +4.08과 대조)",
           "회전율" = "연 741% — 제약 1100% 이내")),
    list(type = "bullet", emoji = "\U0001F9E0", heading = "쉬운 설명",
         items = list(
           "임원이 자사주를 샀다는 사실이 아니라, 자기 보유 지분의 몇 퍼센트를 걸었는지로 신호를 다시 쟀습니다",
           "생색내기용 소액 매수를 걸러내면 신호가 살아난다는 논문 가설 — 걸러내기 자체는 효과가 없었고, 비중으로 재는 방식 전환만 소폭 도움이 됐습니다",
           "다만 그 개선도 자본 투입 기준선에는 크게 못 미쳤습니다")),
    list(type = "bullet", emoji = "\U0001F6A9", heading = "판정 평문 + 주요 결함",
         items = list(
           "판정: 종목 선정 편입 불가 — 세 축 모두 자본 게이트 미달",
           "생색내기 매수 제거는 순위를 사실상 바꾸지 않음(상관 0.998) — 논문 기전 기각",
           "셔플 대조군과의 분리 여유가 얇음 — 거래 크기 고유 정보는 얇다",
           "임원 매수 후 기관이 따라 사지 않음(t +1.41) — 정보성 축적 서사 미입증")),
    list(type = "bullet", emoji = "\U000027A1", heading = "다음 단계",
         items = list(
           "1순위: 감시(monitoring) 소비면 — 기존 안전신호 배선에 커밋 비중 보조축 추가 사전등록",
           "공시지연 gap 가중 축은 미측정 잔존 — 별도 사전등록 라운드",
           "커밋 비중 방식 개선의 원천 분해(함수형 vs 크기 정보) 3-way 비교",
           "이벤트 축은 상장폐지 포함 이벤트 수집 확장 후에만 재개"))),
  charts = c(charts, ch2)
)
cat("[wt007t] telegram 발송 완료\n")
