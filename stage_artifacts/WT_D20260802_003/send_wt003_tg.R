## send_wt003_tg.R — WT003 텔레그램 재발송 (표 2열 재구성; 차트 기생성분 재사용)
suppressPackageStartupMessages({library(data.table)})
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
OUT <- "stage_artifacts/WT_D20260802_003"
source("02_Infrastructure/telegram/telegram_notify.R")
charts <- c(
  file.path(OUT, "WT003_PORT_t_20260802_102315_37680_001_equity_curve.png"),
  file.path(OUT, "sweep_WT003_canonical_PORT_t_cap_w_20260802_102315_37680_002.png"))
stopifnot(all(file.exists(charts)))
tg_agent_brief(
  agent = "Alpha",
  title = "WT-D20260802_003 ALPHA_DONE — 가중 정렬 유의(+2.57) · 천장 미달(1.34<2.94)",
  sections = list(
    list(type = "summary", emoji = "📌",
         body = "멀티팩터 조합에서 '얼마나 섞을지'(가중)를 실현 성과 기준으로 정하면 등가중보다 유의하게 좋아짐을 확인 — 다만 절대 성과는 자본 기준 미달이라 편입 후보는 아님."),
    list(type = "bullet", emoji = "📖", heading = "쉬운 설명",
         items = c("시도: 팩터를 '고르는' 기준이 아니라 '섞는 비율'을 실제 포트 성과 기준으로 정하는 마지막 미검 조합을 시험했습니다",
                   "방법: 동일한 팩터 20개 위에서 가중 규칙 4종만 바꿔 221개월 실측 비교(다른 조건 전부 동일)했습니다",
                   "결과: 실현성과-정렬 가중이 등가중 대비 통계적으로 유의하게 우수(paired t +2.57)",
                   "한계: 절대 성과 1.34는 자본 문턱 2.95와 기존 천장 2.94에 크게 미달 — 지식 가치는 있으나 투자 후보 아님")),
    list(type = "table", emoji = "📊", heading = "가중 규칙별 실측 (canonical PORT_t / paired t vs 등가중)",
         df = data.frame(
           "규칙" = c("등가중(base)", "고정 가족균등", "정보계수 비례", "★실현성과 정렬", "역분산"),
           "PORT_t | paired" = c("0.59 | -", "0.21 | -0.97", "0.85 | +0.89", "1.34 | +2.57", "0.79 | -0.01"),
           check.names = FALSE)),
    list(type = "bullet", emoji = "🚩", heading = "주의",
         items = c("graduation 3종 전부 미달 (PORT_t 1.34 / 검증구간 유지율 -0.41 / Calmar 0.40)",
                   "2015~2019 정보계수 침하 0.018 — 부기간 불안정",
                   "lag-1 스트레스 통과(2.57→2.48) — 미래참조 누출 반증 완료",
                   "하네스 정합: R6 앵커 2.6124 정확 재현(오차 0.0000)")),
    list(type = "bullet", emoji = "➡️", heading = "다음",
         items = c("판정: 기전 양성 + config 한정 negative(천장 미달) — 지배 통로는 '선별' 재확인",
                   "next_probe 1: 실현성과-정렬 가중을 비-return 패널(내부자 공시)에 적용",
                   "next_probe 2: 가중형 완만화(sqrt)·풀 크기 축은 조건부 — 채택은 도훈 판단",
                   "Q-Lead 수신 → Ledger 적립 + risk 단계 전이 여부 판단"))),
  charts = charts)
cat("TG_SENT\n")
