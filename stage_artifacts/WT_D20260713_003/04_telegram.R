# R19 텔레그램 v7 보고 (원칙 9 차트 의무) — 1차 endpoint 선두
suppressMessages({library(data.table)})
source("02_Infrastructure/telegram/telegram_notify.R")
source("02_Infrastructure/telegram/tg_chart_pack.R")
OUT <- "stage_artifacts/WT_D20260713_003"; CH <- file.path(OUT,"charts"); dir.create(CH, showWarnings=FALSE)

# ── Chart 1 (LEAD): 1차 endpoint — 실현 β 예측 정확도 paired_t (양수=칼만 우세) ──
c1 <- tg_chart_sweep(
  labels=c("전체","MEGA(초대형)","MID(중형)","OTHER(소형)","melt-up 2025+"),
  values=c(56.46, 5.02, 10.23, 55.56, -11.93),
  out_dir=CH, title="1차 β정확도① 실현β 예측 (paired t, 양수=Kalman 우세)",
  value_label="paired t (Kalman vs OLS)", hline=0, filename="c1_realizedbeta.png")

# ── Chart 2: 1차 endpoint — 전방 헤지오차 paired_t + melt-up 분해 (양수=칼만 우세) ──
c2 <- tg_chart_sweep(
  labels=c("전체","2025 이전","melt-up 2025+","MID melt-up","OTHER melt-up"),
  values=c(-1.18, 8.18, -11.87, -2.56, -11.79),
  out_dir=CH, title="1차 β정확도② 전방 헤지오차 (paired t, 양수=Kalman 우세)",
  value_label="paired t", hline=0, filename="c2_hedge.png")

# ── Chart 3: 2차 팩터 arm 비교 + 조건부(위기) ──
c3 <- tg_chart_sweep(
  labels=c("arm O(OLS) PORT_t","arm K(Kalman) PORT_t","Kalman 한계기여 paired_t",
           "arm O 위기알파 t","arm K 위기알파 t"),
  values=c(-1.086, -1.78, -1.62, 1.935, 1.559),
  out_dir=CH, title="2차 팩터 arm 비교 + AX-001v2 위기알파", value_label="t값",
  hline=2.95, hline_label="졸업선", filename="c3_factor.png")

sections <- list(
  list(type="kv", emoji="\U0001F4CA", heading="측정 요약 (추정기 교체 격리)", kv=list(
    "1차 실현β예측"="Kalman 우세 RMSE −10% (t+56)",
    "1차 전방헤지오차"="개선 없음 t−1.18 · melt-up t−11.9",
    "2차 팩터알파"="둘 다 음 O −1.09 / K −1.78",
    "칼만 한계기여"="paired t −1.62 (비유의)",
    "조건부 위기알파"="저베타 방어 실재 O t1.94 · K t1.56",
    "랭킹 상관"="0.78 (≥0.95 6%뿐 = 다른팩터·무익)")),
  list(type="bullet", emoji="\U2696\UFE0F", heading="판정 (config-scoped NEGATIVE)", items=c(
    "칼만 β는 β 점-예측만 개선(진짜) · 헤지·알파·방어는 개선 0 = 운용 inert",
    "승격 바(헤지오차 유의 우세) 미달 → 운용자산 승격 불가",
    "저베타 자체가 음(placebo p 0.998) · ~91% 소형주 = 2025 초대형주 역풍",
    "melt-up서 빠른 칼만(hl 7일)이 노이즈 chase → 두 metric 유의 열화")),
  list(type="bullet", emoji="\U0001F52C", heading="다음 탐침 (next_probe)", items=c(
    "P1: 칼만 β를 alpha 아닌 risk입력(β_R05·book β·TE)으로 소비 — 정확도 관련 소비처",
    "P2: 느린 κ(hl 40~60d) 재튜닝 — melt-up 취약성 완화 (EV 낮음)",
    "P3: Kalman tail-β(D08 시변) — 방어 sharpening, AX-001v2 재평가")))

tg_agent_brief(agent="Alpha",
  title="R19 칼만 시변β BAB — 추정기 격리 판정 (WT-D20260713_003 / FQ-032)",
  sections=sections, charts=c(c1, c2, c3),
  as_of="2026-07-13")
cat("[04] telegram sent. charts:", c1, c2, c3, "\n")
