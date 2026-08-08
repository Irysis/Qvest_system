source("02_Infrastructure/contracts/close_round.R")
r <- close_round(
  round_id = "C14_20260808_PRECHECK_HALTED_NOT_PRODUCED",
  verdict_type = "screen_tier_routed",
  layer = "0_데이터",
  mechanism_diagnosis = paste(
    "★사전 확인이 라운드를 착수 전에 멈췄다(오늘 5/5) — C14_Revenue_Surprise 는 **factor_db 에 산출되지 않는다**.",
    "실측: 레지스터리 **373** vs factor_db 최신월 산출 **319** ⇒ **등재됐으나 미산출 54종**. C14 는 그 54 안에 있다. C 계열 중 산출되는 것은 C01_SUE·C02_EPS_Chg_1m·C03·C04_ESBR·C05·C06_TP_Gap·C07·C08·C09·C12·C16·C19 이며 C14 는 없다.",
    "⇒ C14 의 '연구 언급 0회'(FQ-099d)는 방치가 아니라 **데이터 부재**다. 오늘 반복 검거한 '등재 ≠ 존재' 가 재료 선택 단계에서 재현됐다 — 나는 레지스터리 등재를 착수 가능으로 읽었다.",
    "★그러나 이로부터 코호트 전체를 의심한 것은 **틀렸다**(자기 정정): FQ-099 '미탐색 25건' 중 **24건은 실제 산출**되며 미산출은 C14 **1건뿐**이다. 유량의존 32건은 **32/32 전부 산출**. **양성 대조 통과**(생산 북 7종 7/7 산출)로 계측 유효 확인. ⇒ FQ-099d/d1 의 '미평가 코호트' 결론은 **유지된다**.",
    "★부수 발견 = 신규 감사 축: **등재 54종 미산출**. 역방향(산출되나 미등재)은 0 이므로 레지스터리가 상위집합이다. 이 54종이 ①의도적 보류인지 ②산출 실패인지 ③폐기 잔재인지 미확인이며, 각각 처분이 다르다. 재료 선택이 레지스터리를 보고 이뤄지는 한 이 갭은 **매번 헛착수를 유발**한다(오늘 내가 그 사례다).",
    "★C14 자체의 처분: 재료로서의 근거는 유효하다(Jegadeesh-Livnat 2006 — 매출 서프라이즈가 이익 서프라이즈 너머 정보를 담는다. 북이 이미 C01_SUE·C04_ESBR 을 쓰므로 book-marginal 설계가 자연스럽다). 다만 착수 전제가 '팩터 산출' 이며 그것은 alpha-research 소관의 factor engine 작업이지 Q-Lead 가 메인에서 할 일이 아니다. 사전등록(prereg.json)은 폐기하지 않고 **산출 후 즉시 재사용**하도록 보존한다."),
  next_probes = c(
    "C14-P1 — 등재 54종 미산출의 사유 census. ①의도적 보류(데이터 없음/폐기) ②산출 실패(조용한 예외) ③잔재 를 구분한다. ②가 있으면 그건 침묵 실패이며 즉시 수리 대상이다. 재료 선택 면에서는 큐/레지스터리에 '산출 여부' 를 노출해야 헛착수가 끊긴다.",
    "C14-P2 — C14_Revenue_Surprise 산출 위임. 컨센서스 원천에 매출 추정치(rev)가 있는지부터 확인해야 한다. 없으면 이 재료는 데이터 부재로 닫히고, 있으면 alpha-research 에 factor engine 작업으로 위임 후 보존된 prereg 로 즉시 측정. ★있는지 없는지가 먼저다.",
    "C14-P3 — 다음 알파 라운드는 유량 코호트 **밖**에서 고른다. 유량의존 24 미평가건은 FQ-099 수리(칩 task_ec8658cc) 대기이므로 지금 착수하면 오염 패널 위 측정이 된다. 프론티어 큐에서 게이트 없음 ∧ 산출 확인됨 ∧ 유량 비의존 조건으로 재정렬할 것 — ★이번엔 '산출 확인됨' 을 정렬 조건에 넣는다(오늘 헛착수의 직접 교훈)."),
  consumer_surfaces = c("팩터랭킹", "선별라벨"),
  frontier_update = "C14 라운드 사전확인 중단(미산출) · ★신규 감사축: 등재 54종 미산출(역방향 0) · FQ-099 코호트 결론은 유지(24/25 산출·양성대조 7/7) · prereg 보존 · C14-P1/P2/P3 신규 · 재료 선택 정렬 조건에 '산출 확인' 추가",
  live_trigger = "C14-P2 가 컨센서스 원천에 매출 추정치 존재를 확인하면 alpha-research 위임 후 보존된 prereg.json 으로 즉시 측정 착수",
  evidence_refs = c("stage_artifacts/c14_revsurprise/precheck2.R",
                    "stage_artifacts/c14_revsurprise/gap.R",
                    "stage_artifacts/c14_revsurprise/registered_not_produced.txt",
                    "stage_artifacts/c14_revsurprise/prereg.json")
)
cat("[close_c14] RC_OK\n")
