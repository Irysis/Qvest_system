## R38 텔레그램 v7 판정 보고 (원칙 9 — 차트 첨부 의무 · 비전공자 3장치)
suppressPackageStartupMessages({library(jsonlite)})
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
source("02_Infrastructure/telegram/tg_chart_pack.R")
source("02_Infrastructure/telegram/telegram_notify.R")
OUT <- "stage_artifacts/WT_D20260715_007"
r <- fromJSON(file.path(OUT,"r38_results.json"))
v <- r$verdict
cA <- file.path(QM, OUT, "chart_A_entry_vs_exit.png")
cB <- file.path(QM, OUT, "chart_B_duration.png")

P1 <- r$P1_symmetry$mid; P2 <- r$P2_duration
sc <- r$state_counts$mid

sections <- list(
  list(type="summary", emoji="📌",
    body="임원 순매수 안전신호가 꺼질 때(청산) 위험은 되살아나지 않음(no hangover) — 보호막 점착·청산 경보규칙 불요(자본 아님)."),
  list(type="bullet", emoji="📖", heading="쉬운 설명",
    items=c(
      "임원이 6개월 꾸준히 사 모은 종목 = '상대적 안전' 신호(R33/R34 확립).",
      "이번 질문: 그 신호가 '꺼질 때' 위험이 대칭적으로 되살아나나?",
      "상태 4단계 추적 — 켜짐(진입)/유지/꺼짐(청산)/무신호.",
      "①수익: 프리미엄은 신호 '유지' 동안만 신뢰(t=+3.63), 청산 시 조용히 사라짐.",
      "②위험: 청산 후에도 하방·급락은 무신호보다 낮게 유지 = 보호막 점착.",
      "③지속: 오래 켜진 신호가 더 신뢰(단발은 무신뢰), '신선 절벽' 없음.",
      "★청산은 '위험 경보' 아닌 '라벨 강도 낮춤(SAFE→SAFE_FADING)'으로 충분.")),
  list(type="kv", emoji="📊", heading=sprintf("핵심 수치 (MID 시총층 = 안전신호 서식지 · 상태별 종목-월: 유지 %d·청산 %d)", sc$SUSTAIN, sc$EXIT),
    kv=list(
      "수익축: 유지 vs 무신호"=sprintf("연 %+.1f%% · NW-t %+.2f (유의)", P1$SUSTAIN_vs_OFF_raw$gap_ann*100, P1$SUSTAIN_vs_OFF_raw$gap_t),
      "수익축: 청산 vs 무신호"=sprintf("NW-t %+.2f (무유의=프리미엄 복귀)", P1$EXIT_vs_OFF_raw$gap_t),
      "수익축: 청산 vs 유지(전이델타)"=sprintf("NW-t %+.2f (무유의)", P1$EXIT_vs_SUSTAIN_raw$gap_t),
      "위험축: 청산 하방손실"=sprintf("%.1f%% vs 무신호 %.1f%% (더 안전)", v$mid_exit_downside*100, v$mid_off_downside*100),
      "위험축: 청산 급락(-15%↓) 빈도"=sprintf("%.1f%% vs 무신호 %.1f%% (더 안전)", v$mid_exit_tail*100, v$mid_off_tail*100),
      "지속기간 신뢰 (vs 무신호)"=sprintf("단발 t %+.2f / 2-3월 t %+.2f / 4월+ t %+.2f", P2$mid_vs_off$d1$gap_t, P2$mid_vs_off$d2_3$gap_t, P2$mid_vs_off$d4plus$gap_t),
      "직전월 밀기 스트레스"=sprintf("유지 t %+.2f (붕괴 아님=동월누출 아님)", r$lag1_stress$sustain_t),
      "북 보유 슬리브 독립확증"=sprintf("유지 t %+.2f · 청산 t %+.2f (북 잔존종목 청산후 위험재상승 없음)", r$held_confirm$sustain_t, r$held_confirm$exit_t))),
  list(type="bullet", emoji="🚩", heading="판정 · 주의 (평문)",
    items=c(
      "판정: 능력확립(capability_established) — 청산=비대칭 양성(위험 protection 점착).",
      "★자본 아님: 종목별 '유지 안전' 특성화이지 비중·매매 신호 아님.",
      "청산규칙 = SOFT-LAG(불필요) — 신호 꺼짐은 위험 아님, 라벨 강도만 하향.",
      "안전 수익신호 = '지속 클러스터' 현상 — 단발 신호(t=+0.05)는 저신뢰.",
      "한계①: 청산 표본 얇음(MID 115·북 29)·수익축 무유의(위험축은 순서+스트레스+북확증).",
      "한계②: 신호 꺼짐과 동시 상폐·유동성붕괴 종목 검열 → no hangover는 투자가능 조건부.",
      "기준 패널=운영코드 정합(§7b) 재사용·DART API 없음·북 무변경.")),
  list(type="bullet", emoji="➡️", heading="다음 (next_probe) · insider 라인 청산-타이밍 마지막 진단",
    items=c(
      "검열-스트레스: 청산후 다중월(t+1~t+3) 궤적 + 패널이탈 worst-case 대입으로 검열편향 정량.",
      "SAFE_FADING 라벨 실배선 + 지속기간 가중신뢰(filing_delay_watch.R Part C 상태전이).",
      "insider 재료(R9~R38) = monitoring 소비면 확립 완료(자본 미검 불변)."))
)

tg_agent_brief(
  agent = "Monitoring",
  title = "WT-D20260715_007 R38 insider SAFE 청산-타이밍 대칭 — 청산=위험 아님(no hangover)·청산규칙 불요 (자본 아님)",
  sections = sections,
  charts = c(cA, cB),
  as_of = "2026-07-15")
cat("[telegram] sent with 2 charts\n")
