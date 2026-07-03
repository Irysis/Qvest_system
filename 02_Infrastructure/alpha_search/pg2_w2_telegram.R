# pg2_w2_telegram.R — AlphaSearch 모드 브리핑 (tg_agent_brief 단일 진입점)
source("C:/Users/99922/OneDrive/Quant_Module_Moltbot/02_Infrastructure/telegram/telegram_notify.R")
OUTDIR <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/stage_artifacts/pg2_w2_earnings3m"

tg_agent_brief(
  agent = "AlphaSearch",
  title = "PG2 강화 P1 — earnings@3M 정제(3-신호합의+보유밴드): 기준선 유의 개선, graduation 미달",
  sections = list(
    list(type = "summary", emoji = "\U0001F4CC",
         body = "PG2 earnings@3M lead를 논문근거 정제신호 3종+보유밴드로 강화 — 내부 기준선 유의 개선, 자본 graduation은 미달."),
    list(type = "bullet", emoji = "\U0001F4DA", heading = "연구 컨텍스트",
         items = c(
           "[목적] score_eff(1M) 감쇠 대체: 혁신리비전분리·TP섹터상대·3신호합의 + 보유밴드",
           "[검토] K200/KQ150, 2005~2026 258개월, top-25 long-only, 15bps delta",
           "[측정] 전 헤드라인 canonical_screen_bt 계약(NW lag-3) — proxy 손계산 없음")),
    list(type = "kv", emoji = "\U0001F4CA", heading = "핵심 비교 (net, 258개월)",
         kv = list(
           "기준선 PORT_t" = "1.08 (내부 earnings family)",
           "최우수 PORT_t" = "2.20 (3신호합의+밴드)",
           "최우수 샤프지수" = "1.04",
           "최우수 칼마지수" = "0.59",
           "회전율" = "360%/년 (밴드로 1306%→360%)",
           "기준선대비 다중검정t" = "+2.03 (유의)")),
    list(type = "bullet", emoji = "\U0001F6A9", heading = "판정·주의",
         items = c(
           "graduation 후보 — forge 재측정 필요. PORT_t 2.20 < HARD 2.95, 칼마 0.59 < 0.64 → 자본 편입 불가",
           "최근 2021+ 전 신호 死(PORT_t<0.12) = cohort-wide 감가 재확인, edge는 전기간/2015이전",
           "TP섹터상대(Da-Schaumburg)는 KR long-only 비이전 = VALIDATED 음",
           "정직 라벨: 브로커 개인레벨 데이터 부재 → 3신호 전부 컨센서스-레벨 충실 사상")),
    list(type = "bullet", emoji = "\U0001F4A1", heading = "메커니즘 통찰",
         items = c(
           "보유밴드는 지속성 신호(합의)에선 PORT_t 상승, 노이즈 신호(기준선)에선 하락 — 밴드는 signal persistence 요구",
           "IC 강(t 6.6~8.5)하나 long-only PORT_t 약 = IC≠PORT_t 재확인(메모리 정합)"))
  ),
  charts = c(file.path(OUTDIR, "equity_curve.png"), file.path(OUTDIR, "annual_returns.png"))
)
cat("[telegram] sent\n")
