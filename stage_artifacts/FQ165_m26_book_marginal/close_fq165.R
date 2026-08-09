setwd(Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
source("02_Infrastructure/contracts/close_round.R")
r <- close_round(
  round_id = "FQ165_20260809_M26_BOOK_MARGINAL",
  verdict_type = "config_scoped_negative",
  layer = "④construction",
  mechanism_diagnosis = paste(
    "M26 을 현행 PG2 북에 결합하는 3형태(blend/filter/carve) 전건 ΔIR 음수 — 단 기전은 'M26 무용'이 아니라",
    "**슬롯 대체 비용**이다. 정보 0(순열 M26)인데도 개입 규모에 비례해 ΔIR 이 음으로 가므로",
    "**base 대비 ΔIR 은 정보의 척도가 아니다**(이 라운드의 방법론적 1급 산출).",
    "FMB 증분 기울기는 상위 점수 영역에서 사라지지 않고 커진다(전체 +1.502%/yr/sd → top-20 +3.985) —",
    "전이 실패 원인은 '상위에 정보가 없어서'가 아니다. 북 top-20 슬롯 하나를 밀어내는 비용이 연 −13.7% 인데",
    "M26 은 +1.8%p 만 회수한다. 교환비 0.205~0.213 으로 사전적 음의 거래.",
    "검정력: ΔIR≥0.05 게이트(연 +0.95%)가 이 설계의 paired 검출 바닥(연 +2.81%, 외부기준)의 1/3 —",
    "게이트 통과와 통계적 확립은 다른 사건이며, 관측 전건 바닥 미만이라 '효과 부재'가 아니라 '검출 못함'.",
    "유일 검출 셀 = lag1 스트레스(−3.30%/yr, |t| 2.572) — M26 신호수명 짧음 재확인.",
    "착수 전 검거: M26 lag_rule=same-day 로 naive join 시 IC t 3.34배 부풀림(offset0 8.758 vs +1 2.620) 회피.",
    "판정 한정: ①인컴번트 sleeve 내 재구성만 측정(독립 sleeve 는 standalone HARD 로 닫힘) ②tophi φ=3 config 조건부."),
  next_probes = c(
    "NP-1 유니버스 축소 필터 형태(F_B 유일 무해) — required_effect 재산출 후 착수 판단",
    "NP-2 증분 기울기를 대체 비용 없는 소비면으로(오버레이 집계/monitoring 경보/tie-break)",
    "FQ-175(신규 등재) base score_eff offset+1 IC 우위의 vintage-swap 판별 — 북 전체에 걸리는 축, 확립 전 소비 금지"),
  consumer_surfaces = c("팩터랭킹", "유니버스필터", "monitoring신호"),
  frontier_update = "FQ-165 measured_config_scoped_negative · FQ-175 신규(NP-3 승격) · NP-1/2/4 항목 내 기록 · 'base ΔIR ≠ 정보 척도' 방법론 확립",
  live_trigger = paste(
    "부활 조건(next_probes.json::revival_conditions 승계): ①M26 standalone 이 HARD 를 향해 개선",
    "(PORT_t 1.544→2.95 또는 oos 0.123→0.5) ②북 선별규칙이 슬롯대체 아닌 형태로 전환 ③신호수명 개선 변형.",
    "발화 시 F_B(필터) 형태부터 재측정."),
  evidence_refs = c("stage_artifacts/FQ165_m26_book_marginal/alpha_validation.json",
                    "stage_artifacts/FQ165_m26_book_marginal/challenge_note.md",
                    "stage_artifacts/FQ165_m26_book_marginal/next_probes.json")
)
cat("[close_165] RC_OK\n")
