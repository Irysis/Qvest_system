# R21 텔레그램 v7 보고 (원칙 9 차트 의무)
suppressMessages({library(data.table)})
source("02_Infrastructure/telegram/telegram_notify.R")
source("02_Infrastructure/telegram/tg_chart_pack.R")
OUT <- "stage_artifacts/WT_D20260713_005"; CH <- file.path(OUT,"charts"); dir.create(CH, showWarnings=FALSE)

# ── Chart 1 (LEAD): arm B IVOL — PORT_t + 추정기 한계기여 (졸업선 2.95 대비) ──
c1 <- tg_chart_sweep(
  labels=c("IVOL_K PORT_t","IVOL_O PORT_t","추정기 한계기여 paired_t","EW-uni PORT_t"),
  values=c(-1.58, -1.50, -1.01, -2.19),
  out_dir=CH, title="arm B 칼만-잔차 IVOL (t값, 졸업선 2.95)",
  value_label="t값", hline=2.95, hline_label="졸업선", filename="c1_armB_ivol.png")

# ── Chart 2: arm A 위기-조건부 저베타 틸트 — arm 비교 + paired ──
c2 <- tg_chart_sweep(
  labels=c("base PORT_t","armA_K PORT_t","칼만 한계기여 K-O_t","위기틸트 K-base_t(n18)","placebo 시프트_t"),
  values=c(-0.50, -0.495, 0.99, 1.27, -1.16),
  out_dir=CH, title="arm A 위기 저베타 틸트 (paired t, 양수=개선)",
  value_label="t값", hline=0, filename="c2_armA_tilt.png")

# ── Chart 3: arm B 중복성 — 기존 LowRisk 팩터와 랭킹상관 |rho| ──
c3 <- tg_chart_sweep(
  labels=c("D35_RealVol_63d","D01_IdioVol","R12_IdioRisk","D03_RealVol","D02_Beta"),
  values=c(0.97, 0.80, 0.80, 0.79, 0.23),
  out_dir=CH, title="arm B IVOL 중복성 (기존 LowRisk와 |랭킹상관|)",
  value_label="|랭킹상관|", hline=0.90, hline_label="중복 임계", filename="c3_redundancy.png")

sections <- list(
  list(type="text", heading="쉬운 설명", body="R19에서 확정된 칼만필터 β의 정확도 우위(실현β 예측오차 −10%)를 실제 포트폴리오 '위험 관리'에 두 방식으로 써봤습니다. 결론: 둘 다 config-scoped 부정 — 칼만 정확도가 위험-소비로 전이되지 않습니다."),
  list(type="kv", emoji="\U0001F4CA", heading="측정 요약 (칼만 정확도의 위험-소비 2종)", kv=list(
    "A 위기틸트 순효과"="현 북 슬리브 개선 ~0 (최대낙폭 완화 0.0002)",
    "A 칼만 한계기여"="칼만 대 OLS 쌍대 t 0.99 (무의미)",
    "A 위기구간 효과"="t 1.27 (표본 18개월 · 비유의)",
    "B 잔차변동성 초과수익 t"="−1.58 (음) · 추정기 무차별 t −1.01",
    "B 칼만·OLS 랭킹상관"="0.999 = 사실상 동일 신호",
    "B 중복성"="기존 D35 실현변동성과 0.97 = 재현",
    "B 정보계수→초과수익 벽"="정보계수 0.049·다중검정 t 4.57 양호나 초과수익 음")),
  list(type="bullet", emoji="\U2696\UFE0F", heading="판정 (양 arm config-scoped 부정 + 프론티어)", items=c(
    "칼만 한계기여 = 3채널(저베타 팩터·위기틸트·잔차변동성) 전부 무익",
    "벽 = 잔차의 개별잡음 지배(추정기 상쇄) + 저베타=소형주 음-초과수익",
    "추가로 현 북은 이미 현금 오버레이로 위기 방어 → 틸트 중복",
    "B는 신규 아님 = 기존 실현변동성 재현(중복 0.97)",
    "칼만 β-정확도 자체는 실재 — 부정은 좁게 '초과수익 소비'뿐")),
  list(type="bullet", emoji="\U0001F52C", heading="다음 탐침 (next_probe)", items=c(
    "A-P1: 위기틸트를 저베타 아닌 직교 방어신호(품질·부실회피)로",
    "A-P2: 공격 슬리브·비방어 북에 틸트 — 저베타 미포화 지점",
    "B-P1: 잔차변동성을 단독 팩터 아닌 오버레이 후보(과밀·배제)로",
    "B-P2: 변동성 수준 아닌 변화량(ΔIVOL) — 기존 변동성과 덜 중복")))

tg_agent_brief(agent="Alpha",
  title="R21 칼만 정확도의 리스크-소비 2종 — arm A 위기틸트 / arm B 잔차 IVOL (WT-D20260713_005 / FQ-034)",
  sections=sections, charts=c(c1, c2, c3),
  as_of="2026-07-13")
cat("[04] telegram sent. charts:", c1, c2, c3, "\n")
