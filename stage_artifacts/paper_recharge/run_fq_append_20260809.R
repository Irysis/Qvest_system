setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
source("02_Infrastructure/ops/frontier_queue_io.R")

Q <- read_frontier_queue()
cat("[fq_append] current entries:", length(Q$entries), "\n")

# FQ-167: sector-neutral reversal + vol conditional (within_sector_reversal next_probe 1)
fq167 <- list(
  id = "FQ-167",
  lane = "alpha_search",
  title = "섹터-중립 역전 × 변동성 조건부 — 저변동 국면 한정 적용",
  hypothesis = "within_sector_reversal_20260809(Grade F, MDD 60.4%)의 next_probe. OOS 열위가 고변동성 구간 집중인지 확인 후, 시장 변동성 3분위 하단(저변동 국면)에서만 신호 활성화. 근거: 섹터-중립 선형 제거가 급락 구간 비선형 동조를 제거하지 못함 — 저변동 국면에서는 섹터 간 동조성 약화 → 순수 종목-specific 역전 포착 조건 성립 가능.",
  ev_rationale = "within_sector_reversal IC 0.0271(포지티브 비율 57.4%)은 방향성 존재. MDD 구조 결함이 고변동 집중이면 regime-filter가 MDD 선택적 억제 가능. stress 2/4 outperform(GFC+9.3%, EuDebt+22.0%) = 방어성 잠재력 부분 존재.",
  wall_check = "변동성 조건부는 settled-negative 계열(05-07일 2세션 robust FAIL) 가장자리. 단 그 실험들은 ML sizing/선택이었고 이 팩터는 *신호 필터(발화 조건)*로 소비 — 구조 상이. wall check: QUARANTINE 가능성 높으나 체크 비용 낮(동일 팩터 재사용). 중복 재실험 아닌 소비면 전환.",
  data_gate = "없음 (within_sector_reversal 신호 재사용 + VIX/VKOSPI 월간 or 시장 변동성 rolling sd)",
  owner = "미배정",
  status = "frontier_open",
  registered = "2026-08-09 Q-Lead (within_sector_reversal QUARANTINE next_probe 1)",
  parent_fq = "within_sector_reversal_20260809",
  source_paper = "2608.05755",
  next_action = "①시장 변동성 3분위 분위수 정의(KOSPI200 or 전유니버스 rolling 12m sd) ②within_sector_reversal 신호를 저변동 달만 발화 → 나머지 달은 hold 또는 EW ③OOS 구간에서 저/고변동 분리 수익률 비교 ④vol-regime gating이 MDD를 60%→25% 수준으로 개선하는지 확인",
  revival_conditions = list(
    "저변동 국면 한정 시 MDD < 40% AND PORT_t > 2.0(조건부 착수 기준)",
    "OOS retention 0.5 이상 달성 시"
  )
)

# FQ-168: sector reversal as overlay risk signal
fq168 <- list(
  id = "FQ-168",
  lane = "overlay_probe",
  title = "섹터-중립 역전 → 오버레이 리스크 신호 소비 (스코어 하위 25% long 축소 트리거)",
  hypothesis = "within_sector_reversal_20260809 QUARANTINE next_probe 2. IC 0.0271(포지티브 57.4%)는 방향성 있으나 long-only MDD 구조 결함. 소비면 전환: 섹터-조정 역전 스코어 하위 25%(섹터 내 최고 성과 → 역전 기대 低) 종목을 기존 포트 비중 축소 트리거로 소비. 근거: 섹터-중립 역전 high score(=섹터 내 저성과, 역전 기대)가 short-leg 신호 본질 → 오버레이 long 축소에 전용.",
  ev_rationale = "signal의 short-leg 본질을 활용(측정: FMB NW_t=1.01은 long premia 미검출 — short premia 가능성). standalone long 불가 ≠ overlay 소비 불가. 오버레이 소비면(③: 비중 조정 입력)이 untested.",
  wall_check = "QEPM 오버레이 파이프라인 진입 필요. FQ-153(Hurst overlay) 유사 구조. overlay lane에서 먼저 시뮬레이션 가능(alpha-search로 timing 효과 proxy 측정).",
  data_gate = "없음 (within_sector_reversal 신호 재사용)",
  owner = "미배정",
  status = "frontier_open",
  registered = "2026-08-09 Q-Lead (within_sector_reversal QUARANTINE next_probe 2)",
  parent_fq = "within_sector_reversal_20260809",
  source_paper = "2608.05755",
  next_action = "①스코어 하위 25% long 축소 오버레이 설계 ②기존 PG2 포트에 within_sector_reversal risk signal 추가 시 ΔIR 측정(overlay A/B) ③short-leg 신호 reverse 방향(스코어 하위 = long 기피)이 기대 방향 맞는지 month-by-month 확인",
  revival_conditions = list(
    "overlay A/B에서 ΔIR > 0.05 실측(book-marginal 기준)",
    "short-leg 신호 방향 IC < 0 확인(현재 IC+0.0271의 역방향)"
  )
)

Q$entries <- c(Q$entries, list(fq167, fq168))
Q$updated <- "2026-08-09"
cat("[fq_append] adding FQ-167, FQ-168. new total:", length(Q$entries), "\n")

write_frontier_queue(Q)
cat("[fq_append] write complete\n")
