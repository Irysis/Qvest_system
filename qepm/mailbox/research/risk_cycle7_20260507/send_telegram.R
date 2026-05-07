#!/usr/bin/env Rscript
# Send Risk Cycle 7 Telegram brief

PROJ <- "/mnt/c/Users/User/OneDrive/\xeb\xb0\x94\xed\x83\x95 \xed\x99\x94\xeb\xa9\xb4/Quant_Module_Moltbot"
source(file.path(PROJ, "02_Infrastructure/telegram/telegram_notify.R"))

tg_agent_brief(
  agent = "Risk",
  title = "Risk Cycle 7 — PG2 active book + monitoring 인계 / TERMINATE_HANDOFF_READY",
  sections = list(
    list(type = "summary",
         body = "사이클 6 blocker #7 해소 + monitoring agent 인계 schema 산출 + 6/1 발효 사전 체크. 7번째 연속 코덱스 REJECT — 메타 path saturation 결정적."),
    list(type = "kv", emoji = "📌", heading = "3축 핵심",
         kv = list("PG2 활성 북 진단" = "3 source × 4 국면 상관/꼬리의존성/HHI/MCTV 정량",
                   "monitoring 인계" = "사이클 5+6+7 통합 alert schema 발급",
                   "6/1 발효 평가" = "8 check CONDITIONAL_PROCEED")),
    list(type = "table", emoji = "🔬", heading = "원천별 현재 위험 신호",
         df = data.frame(
           원천   = c("주식 알파", "ETF 추세", "국채 캐리"),
           감쇠   = c("OK 4%",     "경계 32%",   "위험 88%"),
           추세   = c("음수 τ",     "음수 τ",     "음수 τ")
         )),
    list(type = "bullet", emoji = "🚨", heading = "신규 발견 4건",
         items = c("위기국면 주식-추세 상관 0.6438 (정상 대비 4.21배 — 위기 직교성 약화)",
                   "주식 알파 변동성 비율 88-101% (Hybrid 사실상 1원천 책)",
                   "주식 알파 60개월 롤링 샤프 추세 음수 τ -0.27 (사이클 5 미보고)",
                   "코덱스 자기 정정: 초기 awk 검증 false positive — Σw=1 R정밀도 PASS")),
    list(type = "bullet", emoji = "➡️", heading = "다음 단계",
         items = c("forge 에이전트 audit (재실행 X) — 종목 중복 검증 A148070 cross-leg",
                   "monitoring 에이전트 spawn — handoff 인계",
                   "다음 사이클 정식 알파리서치 작업 (BAB + Q07 + 8개 위기)",
                   "Architect POST_DEPLOY_006 T+30 due 추적"))
  ),
  footer = "📚 산출: qepm/mailbox/research/risk_cycle7_20260507/"
)
