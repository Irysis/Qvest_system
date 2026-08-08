source("02_Infrastructure/contracts/close_round.R")
r <- close_round(
  round_id = "FQ138H1A_20260808_AUDIT_SELF_RETRACTION",
  verdict_type = "incumbent_confirmed",
  layer = "측정무결성/원장",
  mechanism_diagnosis = paste(
    "★직전 라운드의 '진짜 적중 1건(FQ-064)' 주장을 철회한다 — 필자의 감사가 틀렸다.",
    "오류 1(수치): FQ-064 의 표본은 n_months=118(2016-03~2026-06)인데 필자 정규식이 잡은 n=20 은 random25_null_n_seeds, 즉 **시드 개수**였다. 'n=20' 이라는 문자열을 그 n 이 무엇인지 확인하지 않고 표본크기로 썼다 — 오늘 적립한 [[feedback-identify-before-existence-check]] 를 필자가 다시 어겼다.",
    "정정 수치: n=118 → 필요 효과 연 10.88%(필자가 말한 26.43% 아님). 관측 -1.80%/yr 이므로 크기 기준 INCONCLUSIVE 라는 방향 자체는 유지되나 근거 숫자가 틀렸다.",
    "오류 2(더 중요): 원 항목의 실제 표기는 attribution_verdict = '풀 편향 비유의(-1.267, p 0.205) → 음(-)의 **주성분**은 신호 자체' 이다. '풀 편향은 0' 이라 하지 않았고 '주성분' 이라 썼다.",
    "그리고 판정을 지탱하는 증거는 **신호 vs 자기 풀 EW = -2.147(유의)** 이며 이는 풀-시장 비교와 독립이다. 따라서 FQ-064 의 negative 는 무검정력 null 에 기대지 않는다.",
    "⇒ 실제로는 next_action 요약문의 \"'풀 편향' 가설 기각\" 표현이 attribution_verdict 의 신중한 서술보다 센 것뿐이며 **실질 오류가 아니다**. 원장 수정 불요 — incumbent 확인.",
    "★교훈 강화: 감사 도구가 원장을 비판할 때, 그 비판 자체가 원장의 **어느 필드**를 읽었는지에 좌우된다. 요약 필드와 판정 필드가 다르면 판정 필드가 정본이다. 요약문만 보고 비판하면 없는 결함을 만든다."),
  next_probes = c(
    "FQ-138h1a1 감사 도구에 필드 우선순위 규약 — 원장 비판 시 요약 필드(next_action 등)가 아니라 판정 필드(verdict/attribution_verdict/measure_result)를 정본으로 읽도록 명문화. 오늘 없는 결함을 만들 뻔했다",
    "FQ-138h1a2 n 추출의 정체 검사 — 'n=' 패턴이 표본크기인지 시드수인지 종목수인지 구별하는 확인 단계를 감사 절차에 넣는다. 필자가 시드수를 표본크기로 읽었다",
    "FQ-138h1b 이월 — 큐 커버리지 8% 문제는 그대로다. FQ-160 스키마 없이는 감사가 성립하지 않으며, 오늘 4건 시도에서 실질 적중 0건이 나온 것도 그 표본이 너무 작아서일 수 있다(검정력 부족의 자기적용)"),
  consumer_surfaces = c("선별라벨", "monitoring", "타모드이식"),
  frontier_update = "FQ-138h1 의 'FQ-064 적중' 철회(실질 적중 0/4) · FQ-064 negative 유지 확인 · 감사 도구 필드 우선순위·n 정체검사 규약 필요 · FQ-138h1a1/a2 신규",
  live_trigger = "FQ-160 스키마 도입 후 감사 재실행 시 본 라운드의 두 오류(잘못된 n 추출·요약필드 오독)를 절차로 차단할 것",
  evidence_refs = c("06_Registry/alpha_frontier_queue.json (FQ-064 measure_result_20260726)",
                    "stage_artifacts/fq141_precheck_20260808/np_fq138h1_audit4.R")
)
cat("[close_fq138h1a] RC_OK\n")
