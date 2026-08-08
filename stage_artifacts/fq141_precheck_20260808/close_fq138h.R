source("02_Infrastructure/contracts/close_round.R")
r <- close_round(
  round_id = "FQ138H_20260808_POWER_TABLE_AND_ROUND_REDEFINITION",
  verdict_type = "capability_established",
  layer = "측정무결성/원장",
  mechanism_diagnosis = paste(
    "검정력 계산을 재사용 계약으로 일반화하고(02_Infrastructure/contracts/required_effect_size.R), 그 표가 필자의 직전 개정을 정정했다.",
    "필요 연효과 표(문턱 2.0 · 스프레드 월 sd 0.0394 실측 · NW k=1.25): full n=269 7.21% / n=163 9.26% / n=80 13.22% / n=28 22.34% · split n=28 31.59% · **interaction n=80(ON 35%) 27.71%** / n=163 19.41% / n=269 15.11%.",
    "★자기 정정 2: 직전 개정에서 '전표본 회귀로 검정력 개선' 근거로 full 공식(n=80 → 18.70%)을 인용했으나 국면 더미 계수의 유효표본은 n*p*(1-p) 이므로 interaction 공식이 맞다. 실제 개선은 31.59% → 27.71% = **12%** 에 불과하며 '더 높은 검정력' 은 사실이나 개선폭을 과장했다.",
    "★귀결: 개정본도 심각한 저검정력이다. 연 27.71% 는 현실적 알파보다 한참 위이므로 **FQ-138 은 t>=2.0 문턱으로 답할 수 없는 질문**이다.",
    "⇒ 라운드를 pass/fail 게이트에서 **구간추정**으로 재정의했다. delta 점추정 + 95% CI 를 보고하고 통과 여부를 선언하지 않는다. CI 가 0 을 포함하면 '구간이 0을 포함' 이라 쓰고 '효과 없음' 이라 쓰지 않으며, CI 상한이 현실적 알파 범위보다 낮을 때만 '실질적 효과 배제' 를 주장한다.",
    "★일반 함의: interaction 설계는 유효표본이 n*p*(1-p) 로 급감하므로 **국면-조건부 주장은 이 저장소 표본 규모에서 대체로 저검정력**이다(n=163 도 19.41% 필요). 과거 국면-조건부 negative 들이 무검정력이었을 개연이 있다."),
  next_probes = c(
    "FQ-138h1 과거 국면-조건부 negative 재검토 — required_effect_size.R 로 과거 라운드의 (n, design)에서 필요 효과를 산출해, 보고된 효과크기가 그 미만이면 'NEGATIVE' 를 'INCONCLUSIVE_UNDERPOWERED' 로 재분류. 재료가 잘못 묻혔는지 판정",
    "FQ-138h2 사전등록 표준 항목화 — required_effect / verdict_with_power 를 사전등록 필수 항목으로 넣을지 판단. 오늘 이 라운드는 검정력 계산이 없었으면 무정보 null 을 기각으로 기록했을 것이다",
    "FQ-138h3 검정력 개선 설계 — 스프레드 sd 0.0394 를 낮추는 구성(섹터중립·짝짓기·공통성분 제거)으로 필요 효과를 낮출 수 있는지. sd 를 절반으로 낮추면 필요 효과도 절반이며, 이것이 표본 축적보다 빠른 경로일 수 있다"),
  consumer_surfaces = c("팩터랭킹", "선별라벨", "위험모델", "타모드이식"),
  frontier_update = "required_effect_size.R 계약 신설 · FQ-138 4차 개정(구간추정으로 재정의, 문턱 판정 무효) · 국면-조건부 주장의 구조적 저검정력 확립 · FQ-138h1/2/3 신규",
  live_trigger = "FQ-138h1 이 과거 negative 중 무검정력 건을 찾아내면 그 재료들이 재측정 대상으로 되살아난다",
  evidence_refs = c("02_Infrastructure/contracts/required_effect_size.R",
                    "stage_artifacts/fq141_precheck_20260808/demo_required_effect.R",
                    "stage_artifacts/fq141_precheck_20260808/fq138_preregistration.json")
)
cat("[close_fq138h] RC_OK\n")
