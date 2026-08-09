#!/usr/bin/env Rscript
# tg_summary_20260809.R — 오늘 논문 라우트 3레인 종합 보고 (도훈 지시 "텔레그램도 누락하지말고 보내").
# 단일 진입점 tg_agent_brief() 만 사용 (qvest-telegram SOT).
suppressMessages(library(data.table))
setwd(Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
source("02_Infrastructure/telegram/telegram_notify.R")

secs <- list(
  list(type = "summary", heading = "오늘 한 일",
       body = paste0("논문 라우트 3레인(optimizer/risk/regime) 점검 → risk·regime 레인이 측정은 되는데 ",
                     "판정·보고가 없던 상태를 수리하고, 측정창을 269개월 → 271개월(2026-08)로 확장했습니다. ",
                     "자본 편입은 없습니다(governor 정지).")),

  list(type = "summary", heading = "쉬운 설명",
       body = paste0("논문을 읽어 자동으로 검증하는 파이프라인이 3개 레인으로 나뉘어 있는데, ",
                     "오늘 아침 기준 실제로 도는 건 1개(optimizer)뿐이었습니다. ",
                     "risk 레인은 계산은 하면서 결과를 '측정 안 했다'고 잘못 보고하고 있었고, ",
                     "regime 레인은 논문 제목만 적고 아무것도 재지 않았습니다. ",
                     "둘 다 고쳐서 지금은 세 레인 모두 실제로 재고 판정합니다. ",
                     "그리고 성과를 재는 기간이 2개월 뒤처져 있던 것도 최신으로 맞췄습니다.")),

  list(type = "bullet", heading = "3레인 판정 (271개월, KOSPI200 대비)",
       items = c(
         "optimizer 4편 — book IR 1.433 최고. 최선 타방법 MVO_lw 1.411, ΔIR -0.021 (문턱 0.05 미달) → 채택 0",
         "risk 3편 — 논문 2건 실측 합류. GAS필터 Σ 0.956 vs 대조 minvar_lw 1.175 (ΔIR -0.219) · PRD 0.702 vs book (ΔIR -0.731) → 개선 0건",
         "regime 2편 — 논문 1건 구현·합류(Hurst), 1건 차단(신호 없음). 최선 후보 ΔIR +0.012 → 채택 0",
         "★세 레인 모두 '현 book 을 이기는 후보 없음'. 자본 변경 없음")),

  list(type = "bullet", heading = "오늘 고친 결함 4건",
       items = c(
         "risk 레인이 실측 2건을 재고도 산출물·텔레그램에 '자동 측정 아직 없음' 하드코딩 문자열을 보내고 있었음 → 실측 파생으로 교체",
         "배터리 발화가 optimizer 편수에만 걸려 있어 risk-only 날에는 0회 실행 → 두 레인 합집합으로 확대",
         "regime 하네스는 있었으나 퇴역 캐리어·퇴역 오버레이를 읽고 있었음 → 현 PG2 기준으로 교정 후 배선",
         "측정창이 북보다 2개월 뒤처져 있었는데 아무 로그도 말해주지 않았음 → 커버리지 게이트 신설(지금은 '캐리어 2026-08 = 북 2026-08' OK)")),

  list(type = "bullet", heading = "리서치 수확 (regime 라운드)",
       items = c(
         "추세추종 논문의 Hurst 신호를 오버레이로 검증 → 사전등록 반증 성립(negative)",
         "기전: 현 book 의 구속 낙폭 구간(2006-01~06, -22.7%)에서 국면 라벨 계열은 0/6 발화(6개월 내내 RISK_ON), 변동성 축만 6/6 발화",
         "★잔여 낙폭 방어의 소재는 국면 라벨이 아니라 변동성 — 다음 라운드 대상",
         "오버레이는 IR 레버가 아니라 낙폭 레버임을 재확인: bare IR 1.465(MDD -40.7%) vs book 1.433(MDD -23.3%)")),

  list(type = "bullet", heading = "도훈 확인 필요",
       items = c(
         "FQ-095 셀 판정 — 'IR↔낙폭 교환비' 질문이 D2 에서 이미 죽인 셀과 같은지. 같으면 dead 재라벨, 다르면 셀 분할 등재",
         "그 외 자본 게이트 변경 없음 — book_state 미변경, 실주문 없음"))
)

ok <- tg_agent_brief(agent = "Q-Lead", title = "논문 라우트 3레인 — 수리·재측정 종합 (2026-08-09)",
                     relaxed = TRUE, force = TRUE, lock_scope = "paper_lanes_summary_20260809",
                     sections = secs)
cat(sprintf("[tg] 발송 결과: %s\n", ok))
