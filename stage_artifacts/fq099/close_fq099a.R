source("02_Infrastructure/contracts/close_round.R")
r <- close_round(
  round_id = "FQ099A_20260808_BOOK_CONSUMPTION_PATH",
  verdict_type = "incumbent_confirmed",
  layer = "0_데이터",
  mechanism_diagnosis = paste(
    "★FQ-099 이 남긴 미측정 항목('PG2 북이 유량의존 51 팩터 중 무엇을 소비하는가')을 확정했다 — 답은 **0종**이다.",
    "생산 경로 추적: forward_weights_D3_M4gAE.R 은 팩터를 직접 계산하지 않고 사전계산 패널 2벌을 읽는다 — base = stage_artifacts/WT_D20260425_010/alpha_scores.parquet, m4 = qepm/mailbox/worktask/WT-D20260430_001/stage_artifacts/alpha_scores.parquet.",
    "base 엔진(factor_engine_proposal.R:108,116) 팩터 집합 = CONSENSUS_4F(C01_SUE·C02_EPS_Chg_1m·C04_ESBR·C06_TP_Gap) + SLEEVE_DEFENSE(Q07_Earnings_Stability·M08_Residual_Mom·Q25_Ohlson_O) **7종**.",
    "★두 독립 축이 일치: ①7종 ∩ 유량의존 51건 = **0** ②7종 각각의 레지스터리 정의문에 유량 원항목(Revenue/OperatingProfit/OperatingCF/EBITDA 등 19종) 등장 = **0건**.",
    "m4 엔진은 factor_engine.R:896 에서 `C15_load_month_factors = 'N/A — no Factor DB factor; STR_1715 returns + cached regime only'` 를 자기선언하며, 내 독립 스캔(팩터코드 문자열 추출 0종)과 일치한다. ⚠단 자기선언은 파일 안의 주장이지 독립 측정이 아니다 — 두 축이 합치해 채택하되 라벨을 붙여 둔다.",
    "⇒ **결론: FQ-099 의 혼합 스케일 결함은 현행 PG2 북에 도달하지 않는다.** 북은 컨센서스 4종 + 방어 3종으로 구성되며 유량 재무항목 경로를 타지 않는다.",
    "★그러나 결함의 중대성은 낮아지지 않는다 — 성격이 바뀔 뿐이다: '자본 위험'이 아니라 **'미래 리서치의 측정 무결성'** 결함이다. 앞으로 value·quality·growth 계열(유량의존 51건 = 레지스터리의 13.7%)을 건드리는 알파 라운드는 **오염된 패널 위에서 측정된다**. 이는 CLAUDE.md 인프라 즉시수리 2기준 중 ②(측정 신뢰 훼손)에 정확히 해당한다.",
    "★부수 방법 확립: 본 라운드에서 스캐너가 두 번 '0건'을 냈는데 한 번은 진짜(base_recompute — 양성 대조 2/6 통과)이고 한 번은 계측 실패(m4 factor_engine — 양성 대조 **0/6**)였다. **양성 대조를 같은 실행에 넣은 것이 둘을 갈랐다.** 오늘 확립한 '검사기의 0 은 정지 신호' 규약의 실행 형태."),
  next_probes = c(
    "FQ-099b(실행 중) 판정 — 교정이 IC 를 개선하는지. 사전등록 fq099b_prereg.json 에 3갈래 처분 고정. 북 영향이 0 으로 확정됐으므로 이 결과가 수리 우선순위의 유일한 결정 인자가 된다.",
    "FQ-099d 신규 — 유량의존 51 팩터가 과거 alpha-search·QEPM 라운드에서 몇 번 기각됐는지 census. 오염된 패널 위에서 기각된 재료가 있다면 그 기각은 무효이며 재심 대상이다. 오늘 alpha-search 창(2005~)이 순풍이라 기각이 유효하다고 판정한 것과 같은 종류의 소급 감사이나, 이번엔 벤치가 아니라 **입력 패널**이 축이다.",
    "부수 — base 엔진 7종이 유량 무관이라는 사실 자체가 소비면 정보다: 현행 북은 재무 유량 채널을 전혀 쓰지 않는다. 이는 '미개척 채널' 인가 '이미 시도해 탈락한 채널' 인가? hypothesis_index 로 확인하면 신규 알파 방향 후보가 된다."),
  consumer_surfaces = c("팩터랭킹", "선별라벨", "타모드이식"),
  frontier_update = "FQ-099a 확정: 북 소비 0종(두 독립 축) · FQ-099 성격 재규정(자본 위험 아님, 미래 리서치 측정 무결성) · FQ-099d 신규(오염 패널 위 기각 재심 census) · 양성 대조 동시실행 규약 실증",
  live_trigger = "FQ-099d 가 오염 패널 위에서 기각된 재료를 찾아내면 그 재료들은 교정 후 재심 대상 — 기각 자체가 무효가 된다",
  evidence_refs = c("stage_artifacts/fq099/fq099a_verdict.R",
                    "stage_artifacts/fq099/fq099a_probe2.R",
                    "qepm/mailbox/worktask/WT-D20260425_010/factor_engine_proposal.R",
                    "qepm/mailbox/worktask/WT-D20260430_001/stage_artifacts/factor_engine.R")
)
cat("[close_fq099a] RC_OK\n")
