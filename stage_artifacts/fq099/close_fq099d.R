source("02_Infrastructure/contracts/close_round.R")
r <- close_round(
  round_id = "FQ099D_20260808_CONTAMINATED_PANEL_CENSUS",
  verdict_type = "capability_established",
  layer = "1_재료",
  mechanism_diagnosis = paste(
    "★유량의존 51 팩터의 연구 이력을 4개 원장(hypothesis_index·knowledge_index·distilled_knowledge·alpha_frontier_queue)에서 census 했다.",
    "결과: 언급 있는 팩터 **11건** / **언급 0회 40건 (78%)**. 총 언급 24회(hypothesis 12·knowledge 9·queue 3·distilled 0).",
    "★양성 대조 통과 — 알려진 팩터코드 4종(Q07·M08·C01·V02) 대비 네 원장 각각 1~3종 등장 확인. 따라서 '40건 0회' 는 계측 실패가 아니라 실제 부재다(오늘 확립한 '0 은 정지 신호' 규약의 적용).",
    "언급 상위: V10_FCF_Yield 4 · Q24_Altman_Z 3 · V03_CFP 3 · IN01_CapEx_to_Assets 2 · IN02_CapEx_to_Revenue 2 · Q01_GPA 2 · V14_EBIT_EV 2 · V15_NetDebt_Adj_EP 2 · V17_Payout_Ratio 2.",
    "★해석이 두 갈래인데 **두 번째가 더 크다**: ①언급 11건 = 오염된 패널 위에서 내려진 판정이므로 재심 후보 ②**언급 0회 40건 = 미탐색인데 동시에 오염 패널 위에 있다** ⇒ 지금 착수하면 무효한 결과가 나온다. 즉 수리는 '과거 오류 정정'보다 **'40건 미탐색 재료의 봉인 해제'** 가 주된 값이다.",
    "★이 결과가 수리 우선순위를 FQ-099b 와 **독립적으로** 끌어올린다: 설령 FQ-099b 가 '재배열뿐'(IC 개선 없음)으로 나와도, 40건 미탐색 재료를 오염 패널 위에서 판정할 수는 없다. FQ-099a 가 '북 영향 0' 을 확정했으므로 이 결함의 비용은 전적으로 **미래 리서치**에 있고, 그 미래 리서치의 규모가 방금 정량화됐다(레지스터리 value/quality/growth 계열의 78% 가 미판정).",
    "★한계(정직): '원장에 언급 0회' 는 '한 번도 시험된 적 없음' 과 동치가 아니다 — L-code 를 남기지 않은 스크리닝은 잡히지 않는다. 확립된 것은 **기록된 판정이 없다**는 사실이며, 그것이 재심·착수 가능성 판단의 근거다. 또한 일부는 레지스터리 신규 등재분이라 미언급이 자연스러울 수 있어, 착수 전 팩터별 등재 시점 확인이 필요하다."),
  next_probes = c(
    "FQ-099d1 — 언급 0회 40건의 레지스터리 등재 시점 확인. 최근 등재분(미언급이 자연스러움)과 오래 전부터 있었는데 아무도 안 본 것(진짜 미탐색 재고)을 분리한다. 후자가 진짜 프론티어이며, 오늘 확립한 '재고 회수' 계열(FQ-006~008 overlay 큐 드레인)과 같은 성격이다.",
    "FQ-099d2 — 언급 11건의 판정 내용 확인. 기각이면 그 기각이 오염 패널 위였는지 원 측정 창·입력을 확인하고, 오염 위였다면 기각을 무효 처리해 재심 큐에 올린다. V10_FCF_Yield(4회)·Q24_Altman_Z(3회)·V03_CFP(3회) 부터.",
    "수리 칩 task_4811b0a6 우선순위 상향 근거 확보 — 본 census 가 '40건 미탐색 재료가 오염 패널에 막혀 있음' 을 보였다. FQ-099b 결과와 무관하게 correctness 수리는 선행돼야 하며, 이는 CLAUDE.md 인프라 즉시수리 기준 ②(측정 신뢰 훼손)의 교과서적 사례다."),
  consumer_surfaces = c("팩터랭킹", "선별라벨", "타모드이식"),
  frontier_update = "FQ-099d 확정: 유량의존 51 중 기록된 판정 0회 **40건(78%)** · 언급 11건은 재심 후보 · 수리 값이 '과거 정정'에서 '미탐색 40건 봉인 해제'로 재규정 · FQ-099d1/d2 신규",
  live_trigger = "FQ-099d1 이 '오래 등재됐는데 미판정' 군을 분리하면 그 목록이 교정 직후 착수할 알파 라운드 대기열이 된다",
  evidence_refs = c("stage_artifacts/fq099/fq099d_census.R",
                    "stage_artifacts/fq099/fq099d_mentioned.txt",
                    "stage_artifacts/fq099/flow_dependent_factors.txt")
)
cat("[close_fq099d] RC_OK\n")
