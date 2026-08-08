source("02_Infrastructure/contracts/close_round.R")
r <- close_round(
  round_id = "FQ099_20260808_SOURCE_AWARE_TTM_UNWIRED",
  verdict_type = "capability_established",
  layer = "0_데이터",
  mechanism_diagnosis = paste(
    "★재료 발굴이 아니라 측정 신뢰 결함이다 — 유량(P/L·CF) 항목이 TTM 정규화 없이 원시값으로 팩터에 들어간다.",
    "배관: TTM 은 parse_fundamental_xlsx.R:274 가 정확히 계산해 .cache/fundamental_xlsx_ttm.parquet(non-NA 96.6%)에 쓴다. 그런데 빌더 factor_db_builder.R:276 은 fundamental_merged.parquet 를 읽고 그 파일에는 TTM_Value 컬럼이 없다 ⇒ compute_value.R:61 의 조건이 **항상 거짓** → use_val := Value. **정확한 표준이 있는데 소비자 0** (오늘 wiring_map 계통과 동형).",
    "결과: 피드 이음매에서 스케일 4배 점프 — XLSX 2000~2014(분기월 비중 0.739 = 분기값) → DART 2015~2026(분기월 비중 0.000 = 연간 단독). 같은 종목 2014 분기평균 대비 2016 DART 연간 = Revenue 4.42 · OperatingProfit 4.72 · COGS 4.34.",
    "횡단면 영구 혼합: 생산 유니버스(K200∪KQ150) DART 비중 0.67~0.71 이고 잔여 약 31% 가 2014 분기 스케일로 동결된 채 연간 스케일과 같은 서열표에서 경쟁한다. 유량비율 평균 백분위 서열 격차 DART−XLSX = +0.207~+0.274(5시점 전건).",
    "⚠ 극단 상위 25 는 0/25 DART(마이크로캡이 꼬리 점유) — **왜곡은 분포의 몸통**이며 '상위가 멀쩡하니 무해'로 읽으면 오독이다.",
    "선별 영향(★공통 지지집합 통제 후 — 1차 측정은 교정이 결측 10.6%를 만들어 후보 풀 자체를 바꿨다, 결손≠차이): top-25 자카드 중앙 **0.429**(OperatingProfit·Revenue)/**0.471**(OperatingCF), 최소 0.316, 10시점 전건 <0.8. 기존 큐 서술 0.786 보다 크며 큐를 갱신했다.",
    "영향 범위: 레지스터리 **51/373 팩터(13.7%)** 가 유량 항목 의존(quality 26·value 12·growth 10). 교정에 신규 산출 불요 — XLSX 계는 기존 TTM 파일 값, DART 는 연간값이 곧 TTM.",
    "★부수 검거(이 라운드를 닫을 뻔한 결함): R 정규식 단어경계 \\b 가 한글 섞인 문자열에서 **오류 없이 FALSE** 를 반환한다(TRE·PCRE 둘 다). 같은 blob 에서 fixed 히트 25건 vs 경계 0건. 레지스터리 스캐너가 '유량 의존 팩터 0건'을 **두 번** 냈고 믿었으면 '소비자 없음 → 무해'로 닫혔다. 규약 = 한글 가능 텍스트엔 fixed=TRUE, **검사기의 0 은 결론이 아니라 정지 신호**.",
    "★미측정(주장 안 함): PG2 북 합성 알파가 51개 중 무엇을 실제 소비하는지. forward_weights*.R 텍스트 검색 0건은 잘못된 계측이다(생산은 사전계산 합성 패널 사용). 교정 후 성과가 좋아지는지도 안 쟀다."),
  next_probes = c(
    "FQ-099a 북 소비 경로 확정 — PG2 합성 알파의 사전계산 패널이 유량의존 51 팩터 중 무엇을 쓰는지 패널 구성에서 직접 확인. 이것이 확정돼야 '북 영향' 을 말할 수 있다. 현재는 팩터 라이브러리 13.7% 오염까지만 확립.",
    "FQ-099b 교정 후 A/B — 소스-인지 TTM 패널로 유량의존 팩터를 재산출해 canonical_screen_bt 로 IC·PORT_t 를 현행 대비 측정. 자카드 0.43 이 성과 개선인지 단순 재배열인지 여기서 갈린다. 교정 자체는 신규 산출 불요라 비용이 낮다.",
    "FQ-099c 합성 상쇄 여부 — 단항 비율에서의 자카드 0.43 이 다항 합성 점수에서 상쇄되는지 증폭되는지. 상쇄되면 우선순위 하향, 증폭되면 즉시 수리.",
    "부수 P1 — r-portability.md 에 금칙⑦ 후보 등재 검토: 한글 혼재 문자열에서 \\b 등 경계/클래스 메타 사용 금지 + 위반 주입 테스트. 오늘 실측 1건이므로 등재 전 재현 확인 필요."),
  consumer_surfaces = c("팩터랭킹", "유니버스필터", "선별라벨"),
  frontier_update = "FQ-099 status=measured_repair_pending · 자카드 0.786→0.429 갱신 · 영향범위 51/373 정량 · FQ-099a/b/c 신규 등재 · 신규 이식성 결함(\\b silent FALSE) L-code 적립",
  live_trigger = "FQ-099b 가 교정 후 IC·PORT_t 개선을 보이면 factor_db 재빌드를 상신(현재는 오염 사실까지만 확립, 개선 여부 미측정이라 상신 근거 부족)",
  evidence_refs = c("stage_artifacts/fq099/findings.md",
                    "stage_artifacts/fq099/probe13.R",
                    "stage_artifacts/fq099/probe16.R",
                    "stage_artifacts/l_code/method_frontier/l_code_SOURCE_AWARE_TTM_UNWIRED.json",
                    "stage_artifacts/l_code/method_frontier/l_code_WORD_BOUNDARY_SILENT_FALSE.json")
)
cat("[close_fq099] RC_OK\n")
