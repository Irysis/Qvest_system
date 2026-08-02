## R43 텔레그램 v7 보고 (원칙 9 차트 첨부 + 비전공자 3장치)
suppressPackageStartupMessages({library(jsonlite)})
QM <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(QM)
source("02_Infrastructure/telegram/telegram_notify.R")
OUT <- "stage_artifacts/WT_D20260802_012"
V  <- fromJSON(file.path(OUT,"verdict.json"))
cA <- file.path(QM, OUT, "chart_A_silence_coverage.png")
cB <- file.path(QM, OUT, "chart_B_group_safety.png")
cC <- file.path(QM, OUT, "chart_C_window_matched.png")

cov <- V$a_coverage_change; pri <- V$primary_result; tier <- V$c_tier_decomposition
bk  <- V$d_current_book_readjudication; sf <- V$structural_finding_new
g   <- V$b_increment_paired$groups_mid_habitat

sections <- list(
  list(type="summary", emoji="📌",
    body="감시 커버리지는 2배로 늘지만 안전 분리력은 미달 — 보조축 병합 기각 (자본 아님)"),

  list(type="bullet", emoji="📖", heading="쉬운 설명",
    items=c(
      "배경: 임원이 자사주를 꾸준히 사면 그 종목은 '덜 위험'하다는 감시 신호가 이미 있습니다.",
      "시도: 여기에 '얼마나 크게 걸었나' 축을 보조로 더하면 감시가 나아지는지 봤습니다.",
      "결과1: 감시 가능한 달이 126→253개월, 안전 후보도 24% 늘었습니다.",
      "결과2: 새로 늘어난 후보는 무신호 종목과 구별되지 않았습니다(0.82 vs 합격선 2.0).",
      "결과3: 늘어난 몫의 41.8%가 대형주 — 이 신호를 믿지 말라고 판정된 구간입니다.",
      "★발견: 현행 장치가 253개월 중 126개월(49.8%) 발화 불가 상태였습니다.",
      "발화 불가 이유: 종목이 없어서가 아니라 문턱에 닿을 수 없는 달이었습니다.",
      "의미: 병합은 안 합니다. '이번 달 문턱 도달 불가' 표시를 제안합니다.")),

  list(type="kv", emoji="📊", heading="핵심 수치 (MID 시총층 = 안전신호 서식지 · 실측)",
    kv=list(
      "감시 가능월 (A → A′)"=sprintf("%d → %d개월 / 전체 %d", cov$months_tripwire_can_speak$A, cov$months_tripwire_can_speak$Aprime, cov$months_tripwire_can_speak$total),
      "SAFE 종목-월 (전체)"=sprintf("%d → %d (%+.1f%%)", cov$safe_name_months$ALL$A, cov$safe_name_months$ALL$Aprime, cov$safe_name_months$ALL$delta_pct),
      "★증분 판정 (보조축만 vs 무신호)"=sprintf("NW-t %+.2f — 합격선 2.0 미달 · 월평균 %.2f종목(하한 3) ⇒ 검정력 미달", pri$t_inc_mid_ret, pri$power_floor$avg_names_actual),
      "위험축 (보조축만 vs 무신호)"=sprintf("하방 %.2f%% vs %.2f%% · 급락 %.1f%% vs %.1f%% (방향은 안전)", -g$MAG_ONLY$downside*100, -g$NEITHER$downside*100, g$MAG_ONLY$tail*100, g$NEITHER$tail*100),
      "대조: 현행축만 vs 무신호"=sprintf("NW-t %+.2f (유의) — 기존 신호는 살아있다", g$A_ONLY$paired_t_vs_NEITHER),
      "시총층 분해"=sprintf("대형주 확장 %+.1f%%(신뢰 t %+.2f) / 중소형 확장 %+.1f%%(증분 t %+.2f)", tier$MEGA_TOP30$safe_expansion_pct, tier$MEGA_TOP30$MAG_ONLY_vs_NEITHER_t, tier$REST_MID_OTHER$safe_expansion_pct, tier$REST_MID_OTHER$MAG_ONLY_vs_NEITHER_t),
      "★현행축 침묵"=sprintf("%d/%d개월(%.1f%%) 문턱 도달 불가 — 침묵월 최대 z 중앙값 0.862", 126L, 253L, 49.8),
      "직전월 밀기 스트레스"=sprintf("보조축 t %+.2f (붕괴 아님 = 동월누출 지문 없음)", V$measurement_discipline$lag1_stress$MAG_ONLY_mid),
      "소스 정합 감사"=sprintf("현행 패널 ↔ 신규 패널 월별 순위상관 %.4f · 발화 일치율 %.4f (같은 원천 확인)", V$measurement_discipline$source_parity$spearman_mean, V$measurement_discipline$source_parity$flag_agreement))),

  list(type="bullet", emoji="🚩", heading="판정 · 주의 (평문)",
    items=c(
      "판정: 증분 검정력 미달 — 보조축을 안전 라벨에 합치지 않습니다.",
      "보유 비중은 하나도 바뀌지 않습니다(자본 무관·monitoring 진단).",
      "★자가검증이 잡은 것: 월집합 맞춘 통제에서 보조축이 좋아 보였습니다(t +3.52→+4.11).",
      "그러나 그 값은 종목-월 137개(중형 20개)가 만든 것이고 개별 유의성이 없습니다.",
      "신규 편입분의 하방·급락은 기존보다 오히려 나쁨 — '개선' 보고를 철회했습니다.",
      "현 북 영향: 실질 발화 변화 1건(A005930, 3.64%)뿐, 그마저 대형주=저신뢰 구간.",
      "나머지 3건은 라벨 이름만 달랐습니다(실질 변화 아님).",
      "오늘 현행축은 침묵 상태 — 시장 전체 최대 z 0.912 < 문턱 1.0.",
      "즉 오늘의 'SAFE 0종목'은 자격자 부재가 아니라 문턱 도달 불가입니다.",
      "한계①: 두 축을 같은 z=1.0 비교 — 유계 비율 vs 무계 합이라 선별강도 미정합.",
      "한계②: 기준 패널 2026-04까지 — 최근 3개월 증분은 주장하지 않습니다.",
      "위반 주입 테스트 4종(문턱 경계·돌연변이·가드 2종·최악 대입) 전부 발화 확인.")),

  list(type="bullet", emoji="➡️", heading="다음 (next_probe) · 배선 제안",
    items=c(
      "NP-1(P1): 선택률-정합 문턱 재측정 — 현행축 장기 발화율 15.8%에 보조축을 맞춘 단일 고정 규칙(sweep 아님).",
      "NP-2(P1): 침묵 126개월의 국면 귀속 — 침묵이 2016-17·2022-26 에 군집. 특정 국면 무감시라면 증분보다 상위 결함.",
      "NP-3(P2): 'on-run 구멍 메우기' 제한형 — 유일하게 양(+)인 셀(단발→지속 재분류, n=49 t+1.56)만 사전등록 재측정.",
      "NP-4(P2): 대형주 편중 기전 — 매수비중의 분모가 보유지분이라 지분구조가 큰 대형주에서 왜곡되는지 점검.",
      "배선 제안①(채택권고): '이번 달 문턱 도달 불가' 표시 필드 추가 — 문턱 변경 아님.",
      "배선 제안②(기각): 보조축을 안전 라벨에 합집합 병합.",
      "배선 제안③(보류): 별도 참고 채널 표기 — NP-1 결과와 정식 패널 산출 후 재검토.",
      "본 라운드는 설계도만 — 실배선은 Q-Lead 수집 후 별도 태스크입니다."))
)

tg_agent_brief(
  agent = "Monitoring",
  title = "WT-D20260802_012 R43 insider 보조 tripwire 증분 — 커버리지는 2배, 안전 분리력은 미달(배선 기각) · 현행축 49.8% 침묵 발견 (자본 아님)",
  sections = sections,
  charts = c(cA, cB, cC),
  as_of = "2026-08-02")
cat("[telegram] sent with 3 charts\n")
