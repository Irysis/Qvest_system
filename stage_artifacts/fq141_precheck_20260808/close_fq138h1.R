source("02_Infrastructure/contracts/close_round.R")
r <- close_round(
  round_id = "FQ138H1_20260808_POWER_AUDIT_FEASIBILITY_AND_4CASE",
  verdict_type = "capability_established",
  layer = "측정무결성/원장",
  mechanism_diagnosis = paste(
    "과거 negative 의 검정력 감사를 시도했고, 감사 가능성 자체가 1차 결과다.",
    "큐 negative 52건 중 표본크기 표기 31% · 효과크기 표기 13% · **둘 다 있는 감사 가능분 4건(8%)**. 국면/조건부 언급은 25건이므로 노출은 큰데 감사 가능분이 4건이다.",
    "⇒ FQ-160(큐 결과 스키마 부재)이 **오늘 두 번째로 소비를 막았다** — 첫째는 NP-157c 창-핸디캡 조회표의 기존 기각 결합, 둘째가 본 감사다. 스키마 도입 논거가 가설이 아니라 실증이 됐다.",
    "★4건 개별 판정(도구는 4건 모두 INCONCLUSIVE 반환했으나 그대로 보고하면 과잉주장):",
    "FQ-064 = 진짜 적중 — t -1.267 · n=20 으로 '풀 편향 가설 기각' 을 주장했는데 n=20 에선 26.43%/yr 미만을 검출 못 한다(관측 -1.80%). 단 별도 유의 결과(-2.147)가 있어 전체 negative 는 설 수 있고 무너지는 것은 그 하위 주장이다.",
    "FQ-121 = 이미 옳게 라벨됨 — '게이트 유효성 NOT_ESTABLISHED' 라 썼지 '효과 없음' 이라 하지 않았다. 감사가 그들의 표기를 확인한 셈.",
    "FQ-152 = negative 유지 — OOS retention 0.089 · Calmar 0.049 · MDD 59.6%>>25% 는 검정력 무관 하드 제약 위반.",
    "FQ-118 = 필자의 범주 오류 — 실판정은 라벨 품질 사전검정 FAIL(recall 0.351<=base 0.413 · fisher p=0.795)이고 +2.10%/yr 은 오라클 상한이지 추정치가 아니다. 알파 스프레드 sd 적용이 부적절했다.",
    "★도구 한계 확립 후 계약 파일에 기록: verdict_with_power 는 효과크기만 보므로 (a)독립 HARD 실패 (b)다른 종류의 검정 (c)상한/오라클 값을 구별하지 못한다. 1차 스크린으로만 쓸 것."),
  next_probes = c(
    "FQ-138h1a FQ-064 하위 주장 재판정 — '풀 편향 가설 기각' 은 n=20 비유의에 근거하므로 철회 또는 재측정 대상이다. 전체 negative 를 지탱하는 -2.147 결과와 분리해 원장에 표기할 것",
    "FQ-138h1b 감사 커버리지 확대 경로 — 큐 8% 로는 감사가 성립하지 않는다. source_refs 아티팩트에서 (n, 효과, sd)를 역추출하는 비율을 재고(NP-160b 기준 경로 해결 48.8%), 그래도 낮으면 FQ-160 스키마 도입이 유일 경로임이 확정된다",
    "FQ-138h1c 계열별 sd 라이브러리 — 도구가 top-25 EW 스프레드 sd 하나만 갖고 있어 오적용이 났다. 비교축별(게이트 on/off·오버레이·FF3 잔차) 대표 sd 를 실측해 등록하면 1차 스크린 정확도가 오른다"),
  consumer_surfaces = c("선별라벨", "팩터랭킹", "monitoring", "타모드이식"),
  frontier_update = "검정력 감사 시도 — 큐 커버리지 8%(4/52)로 감사 불성립 · FQ-160 스키마 논거 2차 실증 · 4건 개별 판정(진짜 적중 1·기존 표기 확인 1·독립 HARD 유지 1·도구 오적용 1) · 도구 한계 3축 계약 기록 · FQ-138h1a/b/c 신규",
  live_trigger = "FQ-160 스키마가 도입되면 본 감사를 전 negative 에 재실행 — 그때 비로소 '무검정력 기각' 규모가 확정된다",
  evidence_refs = c("stage_artifacts/fq141_precheck_20260808/np_fq138h1_audit4.R",
                    "02_Infrastructure/contracts/required_effect_size.R")
)
cat("[close_fq138h1] RC_OK\n")
