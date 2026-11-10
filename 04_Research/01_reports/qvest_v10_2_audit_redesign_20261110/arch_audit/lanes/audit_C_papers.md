# 감사 레인 C — 논문 수집 · 라우팅 · 재료 큐 (2026-11-10)

증거 등급: [확인] = 코드 · 로그 · 산출물로 직접 확인 · [판정] = 감사자가 초록을 읽고 내린 판단 · [미확인] = 확인 못 함.

## 1. 배선 지도 [확인]

```
Qvest_MorningBrief(07:10 매일 · .cmd → scheduler/Qvest_MorningBrief.bat · QVEST_PAPER_ROUTER_ENABLE=1)
 └ morning_run.sh
   [0]    paper_recharge_daily.sh → tools/paper_recharge_daily.R
            ├ tools/paper_recharge_mcp.py → uvx arxiv-mcp(유일한 동적 원천) · 질의 30 × 10건 · sort=relevance · recency 0
            │     → stage_artifacts/paper_recharge/mcp_discovery_<D>.json
            ├ config/paper_recharge_sources.csv(정적 기관 PDF 26 · 링크 건강도 curl)
            ├ paper_key 3단 dedup(ops/paper_id_norm.py) → PDF 다운로드 → 01_Literature/Alpha_Search_Recharge/<D>/ · 06_Registry/paper_registry.json
            └ (소비자 없는 부산물) alpha_search_handoff_<D>.json · alpha_search_triage_<D>.json · notable_authors.json
   [0.5]  paper_router_run.sh → prefilter(신규 paper_key 0 → route 스텁 · claude 미호출)
                              → 신규>0 → claude -p(sonnet/high · ops/paper_router_prompt.md v5) — 발견 목록 **전체**를 다시 분류
                              → alpha_search_route_<D>.json(+ LLM 이 06_Registry/data_pipeline_queue.json 직접 append)
   [0.51] programs/program_paper_sync.R → research_programs.json P1/P2/P3 queue(처음 본 판정 · 멱등)
   [0.52] paper_atlas_run.sh — 게이트 꺼짐(지도 없음)
 충실구현 레인(Qvest_ReinforceAutoLoop · 지금 Disabled) → programs/next_replication.R → ops/rf_replication_slots.py
   → ops/rf_next_paper_pick.py → ops/research_pool_predicates.py::alpha_pending(**route JSON 전 파일** · 처음 본 순서)
   → 06_Registry/replication_request.json / replication_slots/*
```
★핵심 배선 사실: **레인이 읽는 큐(alpha_pending · route JSON)와 프로그램 재료 큐(research_programs.json queue)는 서로 다른 큐다.**
`pr_dequeue` 의 생산 호출자 0(grep) — 프로그램 큐의 논문 항목은 쓰기만 되고 소비되지 않는다(P1 69 중 14 · P3 39 중 3 = 이미 L1 원장에 있는 논문).

## 2. 수집이 실제로 도는가 [확인]

| 출처 | 코드 | 마지막 성공 | 최근 30일(10-11~11-10) | 상태 |
|---|---|---|---|---|
| arXiv(arxiv-mcp) | paper_recharge_mcp.py | 11-10 07:12 mcp_ok | 실행 13일 / 31일 · 새 다운로드 **4편**(10-15 1 · 10-17 1 · 11-07 2) | 살아 있으나 **고정점**: 후보 252(prefilter)가 매일 같은 집합 |
| 기관 PDF(정적 CSV 26) | paper_recharge_daily.R | 매 실행 링크 점검 | 신규 0(시드 26 전량 소비) | 24/26 정상 · 404 2개(WINTON 외)가 매일 1통 발송 원인 |
| SSRN · 저널 | 없음 | — | — | 코드 없음 |
| RSS · 블로그(quant_sources.json::blog_sources) | 없음 | — | — | 설정만 있고 수집기 없음 |

- 실행이 빠진 18일(10-11 · 10-13~14 · 10-19 · 10-21~27 · 10-29~31 · 11-02~06)은 morning_run 자체가 안 돈 날이다(morning_run.log 에 그날 헤더 없음 — PC 꺼짐 · 노트북→메인 이관 기간). 수집은 아침 체인 [0] 단계에 매달려 있어 체인과 같이 죽는다. 오늘 MorningBrief 267014 는 [0]~[0.52] **뒤**에서 났다(오늘 수집 · 라우터 · 동기화 exit=0).
- 고정점의 원인: 08-29 질의 재편(도훈 지시 '최신성 불요' → recency 0 + relevance). relevance 상위 10건은 날마다 거의 같다 → dedup 이 전부 거른다 → 새 유입은 '전 기간 관련도 상위 10'을 새로 뚫는 논문뿐. 매일 MCP 30질의(약 1.5분)가 같은 252건을 받아 버린다.
- arXiv 축 사망(read_failed · python_unavailable · mcp_error 등)은 **로그 한 줄뿐 · 경보 0**이었다(실측 read_failed 3회 · 09-13 exit=143) → 이번에 마커 수리.

## 3. 무엇을 모으나 대 무엇이 필요한가 — 표본 40편 판정 [판정]

표본 = 11-07 LLM 라우팅 243편에서 층화 무작위(seed 20261110) 40편 · 초록 수준 판정. 기준: 적합 = 한국 전 종목 월간 롱온리 ≤25종으로 옮길 수 있는 **거래 가능한 전략(횡단면 선택 · 방어 보유 · 시장 타이밍 · 구성 규칙)을 실증 성과와 함께** 내는 논문 / 부적합 = 전략이 아님(추정량 · 서술 통계 · 이론 · 지수 예측 일반론 · 비주식) / 데이터 불가 = 적합하나 우리에게 없는 자료.

| # | id | 제목(줄임) | 라우터(엔진/판정) | 감사 판정 | 엔진 | 판정 |
|---|---|---|---|---|---|---|
|0|1501.01155|Entropy-Based Asset Pricing|return/testable|부적합(위험척도 설명력 · 전략 없음)|✗|✗|
|1|2508.20426|Retail cash flows Hurst(KR)|return/testable|부적합(집계 흐름 장기기억 서술)|✗|✗|
|2|1309.7119|KOSPI/HSI 방향 예측|return/testable|부적합(지수 방향 예측 · 시장 타이밍이면 defense)|✗|△|
|3|2004.01504|ML for asset price forecasting|return/testable|부적합(기법 비교 일반론)|○|✗|
|4|2202.08968|Stock Embeddings|return/testable|부적합(유사도 표현학습)|✗|✗|
|5|2201.05570|Indian sector LSTM + portfolio|return/testable|부적합(소수 종목 가격 예측)|○|△|
|6|2209.12014|Asset Pricing and Deep Learning|return/testable|적합(조건부 · 횡단면 위험프리미엄 학습)|○|○|
|7|2309.15640|LSTM 알고리즘 전략 헤지|defense/testable|부적합(다자산 지수 전략)|○|✗|
|8|2606.09478|CSI300 고빈도 국면 변동성|defense/testable|부적합(고빈도 · 지수)|○|✗|
|9|2303.09330|CSIE 포트 변동성 추정|defense/testable|부적합(추정량)|✗|✗|
|10|1308.0210|Gold, Oil, Stocks 웨이블릿|defense/testable|부적합(상관 서술)|✗|✗|
|11|2407.10175|Low-vol via Bayesian cointegration|defense/testable|**적합**(롱온리 저변동 보유)|○|○|
|12|2205.00104|CSIE 변동성 추정량|defense/testable|부적합(추정량)|△|✗|
|13|1306.5302|신흥시장 SPT 수익 분해|defense/testable|부적합(서술 분해)|✗|✗|
|14|2311.04475|BL + 20 factors|construction/testable|적합(약 · 구성층)|○|○|
|15|1008.3718|Monte Carlo portfolio opt.|construction/testable|부적합(방법 일반론 · 실증 전략 없음)|○|△|
|16|2107.11371|Optimum risk vs eigen(인도)|construction/testable|부적합|○|△|
|17|2004.10631|Equity **fund** selection|construction/testable|부적합(펀드 선택)|✗|✗|
|18|2411.05807|Schur complementary allocation|construction/testable|**적합**(HRP·MV 통합 · 롱온리 구성)|○|○|
|19|1708.02424|Cardinality constrained via factors|construction/testable|적합(조건부 · ≤25종 제약과 부합)|○|○|
|20|2609.03552|Entropic factor replication|construction/testable|부적합(벤치 복제 목적)|○|✗|
|21–27|7편|이론 · 비주식 · HFT 옵션 · 주택 등|not_relevant/skip|부적합|○|○|
|28–31|2411.13813 · 2408.06634 · 2411.08726 · 2108.05721|애널리스트 리포트 · 실적 원문 · 뉴스 네트워크|return/data_pipeline|데이터 불가|○|○|
|32|2505.20608|Reference-dependent(중국) 재현|return/redundant|적합|○|○|
|33|2412.12516|Momentum Transformers|return/redundant|부적합(단일자산 시계열)|○|○|
|34|2511.12129|Dynamic stock recommendation|return/redundant|적합(조건부)|○|○|
|35|1403.8125|MDD · recovery · momentum|defense/redundant|적합|○|○|
|36|2411.13555|DL long-short allocation|construction/redundant|적합(조건부)|△|○|
|37|2601.11958|Agentic AI nowcasting|return/skip|부적합(PIT 재현 불가)|○|○|
|38|2610.07006|STOCK-JEPA|return/skip|부적합(입력 명세 불충분)|○|○|
|39|2012.06573|FOMC 기자회견 영상|defense/data_pipeline|데이터 불가|○|○|

**적중률**: 적합 9/40(22.5% · 조건부 포함) · 데이터 불가 5/40(12.5%) · 부적합 26/40(65%).
**혼동표(라우터 판정 × 감사 판정)**:

| 라우터 \ 감사 | 적합 | 부적합 | 데이터 불가 |
|---|---:|---:|---:|
| testable(21) | 5 | **16** | 0 |
| data_pipeline_required(5) | 0 | 0 | 5 |
| redundant(5) | 4 | 1 | 0 |
| skip/not_relevant(9) | 0 | 9 | 0 |

- testable 정밀도 = 5/21(24%) · skip/data/redundant 쪽은 거의 맞다 → **오류는 한 방향(관대)**: '전략이 아닌 논문'이 testable 로 큐에 들어간다.
- 엔진 오분류 8/40(전부 testable 군 · 38%): 추정량 · 서술 논문을 defense 로, 지수 방향 예측을 return 으로.
- 원인(프롬프트 `ops/paper_router_prompt.md:35-46`): testable 조건이 "데이터가 있으면 · 메커니즘이 명확하면 재구성" 뿐 — **논문이 거래 가능한 전략과 성과를 보고하는가**를 묻지 않는다. 엔진 정의(:19-24)도 '위기 낙폭을 줄이는 장치'와 '변동성을 재는 추정량'을 가르지 않는다.
- 질의가 체계적으로 놓치는 것(발견 243편 실측): 위기 · 꼬리 · 하방 · 비대칭 · 분포 예측 낱말 16편(6.6%) · 위기 성과 보고(crisis_evidence=reported) **4편** · 한국 7편 · long-only 7편. 30개 질의 중 방어 2개(변동성 타기팅 · 국면 전환) · 분포 표적 0 · 방어형 주식(저베타 · BAB · 퀄리티 방어) 0 · 추세 오버레이/관리형 변동성 0 · 모멘텀 붕괴 0. 질의 'large language model NLP financial disclosure asset pricing' 이 엔트로피 가격결정 · ML 예측 비교 · 주식 임베딩 · 딥러닝 위험프리미엄을 끌어왔다(질의 표류).

## 4. 라우터 v5 안정성 [확인]
- LLM 은 신규 키가 1~2개여도 발견 목록 전체(163~243편)를 다시 분류한다(11-07: prefilter '신규 2' → LLM 보고 '신규 191 · redundant 52').
- 3회 LLM 실행에서 같은 논문 엔진 뒤집힘 55/234(23.5%) · testable↔그 외 37(대부분 skip→testable 로 관대해지는 쪽).
- 1회 비용: 14~16분(10-17 07:13→07:27 · 11-07 07:17→07:34) · sonnet/high · 신규 수와 무관하게 발견 목록 크기에 비례.
- LLM 이 `06_Registry/data_pipeline_queue.json` 을 직접 append(잠금 · 원자적 교체 · 스키마 검사 없음 — 등록부 writer 원칙 밖).

## 5. 큐 역학 [확인]
- 레인 큐(alpha_pending): 수리 전 76 → 수리 후 65(뒤 실행이 testable 을 거둔 11편 제외). 착수 가능 = 소비 기록 · skiplist · 원문 링크 필터 뒤.
- 순서 = 처음 본 날짜(08-30 대량 분류분이 앞) — 우선순위 없음(next_replication.R:12 '재정렬 금지'). 큐 상단 = 2601.04602(상관 예측 GNN) · 2603.14453(LSTM 추세) · 2106.06164(요일 효과 다중프랙탈) · 1309.7119(지수 방향 예측) — 표본 판정 기준으로 넷 다 부적합 쪽.
- 엔진 구성(마지막 LLM 판정): construction 31 · return 17 · defense 14 — 구성 논문(롱레그를 안 낸다)이 42%.
- 소비 속도: L1 원장 10-11 이후 13건(F 11 · B 2 · 전부 parked) · 11월 3건 · 레인 Disabled. 유입 4편/30일 vs testable 적체 65 → 적체는 '수집이 많아서'가 아니라 08-30 일괄 분류분이 고여 있는 것.
- 중복: paper_key 3단(axv > doi > ttl) + 판 번호 · URL 정규화 — 시나리오 Q4 통과. 프로그램 큐에는 이미 측정된 논문 17편이 남아 있다(pr_dequeue 미사용).
- 롱레그 · 새 계보 우선? 아니다. 큐는 롱숏 여부 · 엔진 수요 · 기저 풀 공백(needs_long_leg 9/12)을 보지 않는다.

## 6. 새 계보 공급 · 데이터 막힘 [확인]
- 논문 지도(mechanism_atlas.jsonl) 없음(게이트 꺼짐) → 계보 빈칸을 보여 주는 장치가 없다.
- data_pipeline_queue: 59건 전부 open(08월 40) · 소비자 = boot_lean.sh 개수 표시뿐 → **올라간 뒤 푸는 주체가 없다**. 대표 결손 = 애널리스트 리포트 텍스트 · 어닝콜 텍스트 · 뉴스 · 공급망 · 인트라데이. 49/59 는 engine 필드 없음(v5 이전).

## 7. 업데이트 누락 감지

| 산출물 | 생산자 | 주기 | 신선도 검사 | 소비자 | 낡았을 때 |
|---|---|---|---|---|---|
| mcp_discovery_<D> | paper_recharge_mcp.py | 매일(체인) | prefilter 붕괴 라벨(mcp_suspect_empty) · **11-10 수리: 실패 마커** | recharge · router | 체인이 안 돌면 아무도 모름(부팅 · Superfan 구성요소에 수집 없음) |
| paper_registry.json | recharge | 매일 | 없음 | dedup · router | dedup 기준 낡음 |
| alpha_search_route_<D> | router(LLM/스텁) | 신규>0 날 | 백로그 7일 창 + 명시 백필 | alpha_pending · program_paper_sync | 레인이 옛 판정을 계속 집음 → **11-10 수리: 마지막 결정 판정 우선** |
| research_programs.json queue | program_paper_sync.R | 매일 | 없음 | 표시 · mechanism_atlas 만 | 소비 안 됨 · 처음 판정 고정(P-C4) |
| data_pipeline_queue.json | LLM 라우터 | 신규>0 날 | 없음 | boot_lean 개수 | 영구 open |
| 수집 무실행 일수 | — | — | **없음**(P-C6) | — | 18/31일 무실행이 무경보 |

## 8. 시나리오 시험 결과

| 시나리오 | 기대 | 수리 전 실제 | 조치 | 시험 |
|---|---|---|---|---|
| 정상(스텁 경로) | 신규 0 → claude 미호출 · 무음 | 그렇다(로그 11-08~10) | — | 기존 test_paper_router_prefilter.sh |
| arXiv 원천 실패 | 마커 1회 · 기관 축 계속 | 로그 한 줄 · 경보 0 | 마커 추가 | test_scn_paper_collect.R C5 |
| 기관 원천 파일 깨짐 | 그 축만 skip + 마커 | 그렇다 | — | 기존 test_curated_sources_isolation.sh(12 통과) |
| 죽은 기관 링크 반복 | 새로 죽은 것만 1통 | 매 실행 1통(66일) | 상태 파일로 새 소식 판정 | C1 · C2(돌연변이) |
| 깨진 route 항목/파일 | 나머지 계속 | 그렇다 | — | Q5 · C3 |
| 판 번호만 다른 중복 | 1편 | 1편 | — | Q4 |
| 라우터 재판정(testable→거둠) | 큐에서 빠짐 | 남음(9~11편) | 마지막 결정 판정 우선 | Q1 · Q1b · Q2 · Q3 · M1(돌연변이) |
| 라우터 호출 실패 | route 없음 → 다음 날 백로그 · 마커 | 코드상 그렇다(paper_router_run.sh:16-18 · 백로그 7일) | — | 기존 test_paper_router_backlog_axis.sh · test_router_backfill_paths.sh(실행 안 함 · 미확인) |
| 큐 파일 동시 쓰기 | 잠금 · 원자 교체 | qv_lock + rename(program_registry.R:102-113) | — | 기존 test_ledger_write_locks.py(실행 안 함) · data_pipeline_queue 는 잠금 없음(P-C3) |
| 두 슬롯이 같은 재료 | 배제 | --exclude 동작 | — | Q6 |
| 포트폴리오 없는 논문 | 레인 표준 구성 | 라우터는 판정 안 함(레인 D 소관) | — | — |
| 데이터 없는 논문 | 파이프라인 큐 적재 | LLM 이 직접 append · 결정론 writer 없음 | 패치 제안 P-C3 | — |

## 9. 패치 제안(소유 밖 · 규칙 변경 · 도훈 결정)

- **P-C1 질의 재편(도훈 결정 · 08-29 지시와 관련)**: (a) 방어 · 분포 질의 추가 — "defensive equity low beta betting against beta drawdown" · "tail risk hedging equity crash protection portfolio" · "downside beta asymmetric correlation cross-section" · "time-series momentum trend following equity index crash" · "managed volatility conditional exposure equity" · "momentum crash dynamic momentum" · "quantile regression distributional forecast stock returns" · "conditional skewness left tail stock selection" · "crisis alpha bear market stock performance" · "Korean stock market foreign investor flow defensive" (근거: 발견 243편 중 위기 성과 보고 4 · 방어 낱말 16 · 헌장 §7 위기 하락 포착↓). (b) 고정점 해소 — 일부 질의만 sort_by=date(질의별 정렬 필드 추가 · paper_recharge_mcp.py:246 · q-fin 범주 유지라 firehose 위험 없음 — 같은 파일 _categories_note 의 관측). '최신성 불요'(08-29)를 뒤집는 일이라 도훈 결정.
- **P-C2 라우터 입력 축소(소유 · 미구현)**: prefilter 가 이미 신규 키를 계산한다(paper_router_run.sh:256-345) → 신규 키만 담은 discovery 사본을 LLM 에 넘기고 프롬프트 :11 을 그 사본으로. 효과 = 회당 14~16분 → 신규 수 비례 · 재분류 뒤집힘(23.5%) 제거. claude 실행 없이 검증할 수 없어 이번엔 미구현.
- **P-C3 testable 정의 강화(프롬프트 :35-46)**: `strategy_reported`(거래 가능한 포트폴리오 성과 보고 yes/no) · `long_leg`(롱레그/롱온리 성과 분리 보고) 필드 추가 · testable 조건에 strategy_reported=yes. data_pipeline_queue append 는 LLM 대신 결정론 writer(R · 잠금 · dedup)로 — program_paper_sync 가 route 의 data_pipeline_required 를 받아 쓰게.
- **P-C4 프로그램 큐 판정 고정(program_paper_sync.R:24-45)**: 재분류가 큐 항목에 반영되지 않는다 · 이미 측정된 논문(L1)이 큐에 남는다(17편). 큐 항목에 마지막 판정 갱신 + L1 소비분 consumed 이관. 단 레인이 이 큐를 안 읽으므로(§1) 근본은 '어느 큐가 정본인가' 결정.
- **P-C5 다음 논문 순서(next_replication.R:12 · rf_next_paper_pick.py '재정렬 금지')**: lean-loop '입력 — 등록부가 정한다' 규칙이라 도훈 결정. 제안 = 기저 풀 공백 가중(엔진 수요: 롱레그 return · defense 우선 · construction 은 기저가 있을 때) · 정렬 키는 τ_D 이전 정보만(논문 메타 · 라우터 필드 — 성과 수치 무사용).
- **P-C6 수집 신선도 감시**: superfan_components.json 에 paper_collection(마지막 mcp_ok 날짜 · 최근 7일 신규 수) · boot_lean 에 '논문 수집 마지막 성공 n일 전' 1줄. (06_Registry · boot 는 소유 밖)
- **P-C7 시험 오염**: router 시험 일부가 운영 로그에 DRYRUN 줄을 남긴다(.cache/scheduler_logs/paper_router_20261107.log 08:22 '명시 백필 합류: 20260612') — 원장 D4 와 같은 결함.
- 관측: 08_Tests/ops/test_replication_slots.py 가 2분 39초 · S12 가 NameError 'S'(boot_lean.sh:132 PEND 가 S() 를 쓰는데 시험의 exec 네임스페이스에 S 없음) — 이번 수정과 무관(boot_lean 측 변경 · 레인 E/총괄 소관).

## 10. 속도 [확인]
- 임계 경로(아침 [0]~[0.52]): 07:10:15 → 07:12:56 ≈ 2분 40초(신규 0 날). 상위 3: ① MCP 30질의(uvx 기동 + 검색 ≈ 1.5분 · 매일 같은 252건) ② 기관 링크 curl 26개(최대 30초 × 26 · 정상 날 ≈ 30초) ③ program_paper_sync(R 기동 · 수 초). 신규 > 0 날은 ④ LLM 라우터 14~16분이 지배.
- 판정을 바꾸지 않는 단축: P-C2(라우터 신규만) · 기관 링크 점검 주 1회(정적 시드 · 소식은 새로 죽은 것만) · 고정점이면 MCP 질의를 날마다 다 돌릴 이유가 없다(P-C1 b 와 함께).
