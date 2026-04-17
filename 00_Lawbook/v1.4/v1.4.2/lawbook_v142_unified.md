# QEPM Multi-Agent Lawbook v1.4.2 — Unified Edition

> 이 문서는 `qepm_multiagent_lawbook_v1_4_2_full.zip`의 고유 문서들을 하나의 Markdown으로 통합한 버전입니다.
> `QEPM_Lawbook_v1_4_2_TOC/CHANGELOG/VALIDATION` 파일은 동일 내용 중복이 있어 각 1회만 포함했습니다.



---

## FILE: `00_README.md`

# QEPM 멀티 에이전트 운용 법전 (v1.4.2)

- 작성일: 2026-03-10
- 목적: **퀀트 투자 리서치 → 전략 구현 → 백테스트 → 심사(허들) → 개선 루프 → 월간 리밸런싱 실행안 산출**을 멀티 에이전트 구조로 자동화하기 위한 업무 규칙/표준/체크리스트의 집합.

---

## v1.4.2 핵심 변화(요약)

v1.4.2는 v1.4.1의 **자가발전 / 통계 방어 / 포트폴리오 공학** 구조를 유지하면서,
다음 4가지를 중점 강화한다.

1) **연구 결과 기억 증류 파이프라인 도입**
- 단기 대화 기억이 아니라 **연구 결과 기억**에 집중한다.
- Raw Artifacts → Experiment Digest → Family/Mechanism Memory → Statistical Evidence Store → Regime Payoff Tensor → Portfolio Policy Memory → Post-Trade Learning Memory 로 승격한다.
- 대화 기억은 최소화하고, 전략/실험/국면/포트폴리오 정책 기억을 중점 관리한다.

2) **Self-Evolution과 Memory의 연결 강화**
- `MEMORY_COMMIT` 단계에서 25장 Memory Distillation Pipeline을 호출한다.
- 영구기관(Perpetual Mode)은 연구를 멈추지 않되, 근거 없는 기억 축적과 모드 붕괴를 방지한다.
- Backlog/WIP/briefing이 모두 “기억 승격 결과”를 참조할 수 있게 한다.

3) **런타임 Retrieval 우선순위 정비**
- 월간 리밸런싱/연구 설계 시
  Schema → Statistical Evidence → Regime Payoff → Portfolio Policy → Recent Digests → Working Memory
  순으로 주입한다.
- 기억은 Lawbook/원시 산출물을 대체하지 않으며, 의사결정을 돕는 도구다.

4) **기억 증류 검증(Verification Loop) 도입**
- hallucination / information loss / distortion 검사를 단계별로 수행한다.
- 심각한 왜곡은 재증류하거나 관리자 검토로 escalated 한다.

---

## 목적함수 우선순위 (v1.4.2 고정)
1. Validity (PIT, 데이터 무결성, 재현성)
2. Implementability (TO, 비용, 유동성, 집행 가능성)
3. Robustness (OOS, Stress, Tail Risk)
4. Performance (Sharpe0, CAGR, IR)
5. Novelty (새로운 알파 원천, 직교성, 학습가치)

> 높은 수익률은 validity/implementability를 이길 수 없다.

---

## 문서 맵 (v1.4.2)
- 00~24: v1.4.1 본편 유지/업데이트
- 25 `25_MemoryDistillationPipeline.md`
- 99 `99_References.md`

---

## 운영 전제
- 모든 작업은 **로컬 환경**에서 수행(보안 우선).
- 인터넷은 허용된 순간에만 제한적으로 사용(논문/뉴스/DART/허용 API).
- 월간 리밸런싱은 **전월말까지의 데이터로** 결정, 월초 실행을 목표.
- 코드 기준 언어는 **R**.
- Perpetual Research Engine은 `/pause`, `/resume`, `/stop`, `/loop_on`, `/loop_off` 제어를 따른다.
- 장기기억화 대상은 **대화 전체가 아니라 연구 결과와 확정된 운영 규칙**이다.


---

## FILE: `01_Architecture_and_Roles.md`

# 01. Architecture and Roles (v1.4.1)

## 1) 트리 구조(권장)

- **Manager AI (중간관리자/오케스트레이터)**  
  - 사용자 인터페이스(요구사항 수집, 정책 적용, 최종 브리핑)
  - 하위 에이전트에 작업 발행/우선순위/예산(컴퓨팅) 배분
  - 산출물 “합본” 및 최종 의사결정(월간 포트폴리오/리밸런싱)

하위 에이전트(예시):

- **Data Steward (데이터레이크/DB 관리자)**  
  - Raw 적재, 스냅샷, QC, 결측/이상치 리포트
  - 데이터 계약(Data Contract) 준수 확인

- **Feature Engineer (피처/유니버스 관리자)**  
  - tidy Universe 테이블 생성/검증
  - 공시 시차, 정정/재무 재작성, 룩어헤드 방지 로직 관리

- **Idea Researcher (논문/아이디어 리서치)**  
  - 논문/문헌 기반 아이디어 제안(요약 + 구현 요건)
  - 팩터 정의/대체 프록시 제안 시 “학술 근거” 필수

- **Factor Strategy Builder (팩터모델 전략 설계자)**  
  - 단일/멀티팩터 전략 설계(신호→포트폴리오 구성)
  - 거래비용/제약 반영한 실전형 스펙 제출
  - 최근 실패 전략을 **family 단위로 사후 검토**하고, `FailurePatternCard`와 `MutationProposal`을 생성
  - 탐색 모드는 반드시 `Exploit / Orthogonal / Counterfactual` 세 모드로 분할하여, 같은 family의 승격 패턴만 반복하지 않음

- **Regime Modeler (국면모델 설계자)**  
  - 국면 정의(상태공간/클러스터링/룰 기반 등)
  - 국면별 전략 가중치 정책 제안(과최적화 방지 장치 포함)

- **Factor & Strategy Valuation Agent (밸류에이션 분석관, v1.1 추가)**  
  - 전략/팩터의 **현재 밸류에이션 수준(싼지/비싼지)** 을 정량화
  - (선택) 과거 수익을 **구조적 알파 vs 리밸류에이션 효과**로 분해
  - “밸류에이션 오버레이”를 위한 입력 데이터(지표)만 제공(의사결정권 없음)

- **Factor & Strategy Blender Agent (블렌더/앙상블 실행자, v1.1 추가)**  
  - 합격 후보 전략/팩터를 **블렌딩(조합/가중치 산출)**
  - 기본 배분(동일가중/리스크패리티/제약최적화) + **밸류에이션 오버레이(완만한 틸트)**
  - 조합 폭발 방지 규칙에 따라 탐색을 통제하고, 상위 후보만 제출

- **ResearchOps Agent (v1.3 추가)**  
  - Backlog 우선순위, compute budget, preflight/full-run 스케줄링
  - 중복 실험 탐지, 실험 family 관리, multiple-testing accounting
  - 실험 처리량(throughput)과 정보가치(value of experiment) 최적화

- **Risk Auditor (전략 심사관)**  
  - 허들/리스크 기준에 따른 합격/불합격 판정
  - 불합격 사유를 “수정 가능한 항목”으로 분해해 피드백 제공
  - 전략/앙상블의 통계적 방어선(Sharpe0, ES99, factor-model alpha validation) 검토

- **Portfolio Manager AI (최종 포트폴리오 선택자)**  
  - 합격 전략/앙상블 집합에서 최종 포트폴리오 구성
  - 월간 리밸런싱 트레이드리스트 산출(제약조건 반영)

- **Performance & Monitoring Agent (성과관리/피드백)**  
  - 사후 성과 추적, 드리프트/리스크 이벤트 감지
  - 각 에이전트에 피드백(원인-결과 연결) 제공

---

## 2) 책임/권한 경계(중요)

- Data Steward는 **원시 데이터의 진실(ground truth)** 을 관리하지만,
  - 팩터 정의 변경, 룩어헤드 정책 변경은 할 수 없다(Feature Engineer/Manager 승인 필요).

- Feature Engineer는 “피처/팩터 정의”를 관리하지만,
  - 특정 전략 성능을 올리기 위해 정의를 임의 변경하면 안 된다(데이터 마이닝).

- Strategy Builder는 전략을 제안할 수 있지만,
  - 허들(합격 기준)을 임의로 낮출 권한이 없다(Risk Auditor/Manager 정책).

- Regime Modeler는 국면 분류를 제안하지만,
  - “과거 수익률이 잘 나오도록 만든 클러스터”를 목표로 하면 즉시 탈락(과최적화).

- Valuation Agent는 밸류에이션 지표를 계산하지만,
  - (a) 전략/팩터의 정의를 바꿀 권한이 없고
  - (b) 블렌딩 가중치를 직접 결정하지 않으며
  - (c) 밸류에이션을 “추세 추종” 신호로 왜곡하면 안 된다.

- Blender Agent는 블렌딩 가중치를 산출하지만,
  - (a) 허들 Gate를 통과하지 못한 전략을 몰래 포함할 수 없고
  - (b) Test 구간을 보고 조합을 고르는 행위를 금지하며
  - (c) 밸류에이션 지표를 ‘최적화 대상’으로 삼아 과적합을 유도하면 안 된다.

- ResearchOps Agent는 우선순위/예산을 조정하지만,
  - (a) 허들 기준을 바꿀 권한이 없고
  - (b) 산출물 없는 “진척”을 인정할 수 없으며
  - (c) 성과가 좋아 보인다는 이유로 PIT/데이터/QC 위반을 예외 처리할 수 없다.

- Portfolio Manager는 최종 포트폴리오를 고르지만,
  - 데이터 스냅샷을 바꾸거나, 백테스트 규칙을 깨는 선택은 금지.

---

## 3) 산출물 표준(모든 에이전트 공통)

모든 에이전트는 최소한 아래 4가지를 남긴다.

1. **Artifact(산출물)**: `.md` 또는 `.json/.csv/.parquet` 형태  
2. **Provenance(근거)**: 사용 데이터 스냅샷 ID + 파라미터 + 코드 버전 + 참고문헌  
3. **Decision Log(의사결정 로그)**: 왜 그렇게 했는지, 무엇을 버렸는지  
4. **Fingerprint(전략/실험 식별자)**: 중복 탐지에 필요한 핵심 정의 해시

---

## 4) 실패 처리

- 실패는 숨기지 않는다.
- 에러가 나면:
  - (a) 입력 문제인지
  - (b) 데이터 QC 문제인지
  - (c) 설계 문제인지
  - (d) 구현/버그인지
  - (e) 통계적 유효성 문제인지
  로 분류하고, 재현 가능한 최소 예제로 보고한다.

---

## 5) v1.3 아키텍처 원칙

- **좋은 아이디어 생성**과 **좋은 실험 선택**은 다르다.  
  → ResearchOps는 “무엇을 먼저 돌릴지”를 책임진다.
- **등급(Grade)** 과 **생애주기(Lifecycle)** 는 다르다.  
  → A등급이어도 곧바로 Production은 아니다.
- **산출물 없는 실행/발송/수정 보고는 금지**한다.  
  → 에이전트 최적화의 첫걸음은 “열심히 하는 척”을 못하게 만드는 것이다.

## v1.4 Addendum — Alpha Lab / Idea Compiler / Control Tower / Catalyst

### 1) 신규 역할 추가
- **Alpha Lab Gatekeeper**
  - Stage 0에서 아이디어를 빠르게 위생검사(cheap reject)
  - 공식 WQ 내부 규칙을 복제하지 않고, WQ-inspired heuristic gate만 운영
- **Idea Compiler**
  - 아이디어/논문/카탈리스트 산출물을 `ExperimentProtocol` 형식의 실행가능한 계약서로 컴파일
- **Post-Trade Control Tower**
  - Production 이후 intended vs realized exposure, slippage, capacity, drift, crowding 관리
- **Catalyst Agent**
  - cross-domain 아이디어를 생성하되, 반드시 Compiler를 통해서만 실행 큐에 진입

### 2) 권한 경계 추가
- Alpha Lab Gatekeeper는 Stage 0에서만 Reject/Pass를 부여하며, Production 승격 권한은 없다.
- Idea Compiler는 실험 계약서로 변환만 하며, 성과 평가/승격 권한은 없다.
- Control Tower는 사후 감시 및 상태 전환(WATCHLIST/RETIRED) 권한을 가진다.
- Catalyst는 실험을 직접 실행하지 않고, `IDEA_PROPOSAL`만 제출한다.


## 5) v1.4.1 역할 보강
### Factor Strategy Builder — Failure Intelligence Loop
- 승격 실패 전략을 단순 폐기하지 않고, 아래 4축으로 원인 분해한다.
  1. Signal failure
  2. Construction failure
  3. Implementation failure
  4. Risk failure
- 동일 factor family에서 다음 실험을 만들기 전, 최근 실패 5~20개를 반드시 조회한다.
- 단, 과거 교훈은 **Hard Law**가 아니라 **Soft Prior**로 취급한다.
  - 즉, 최근 교훈을 참고할 의무는 있으나, 동일한 해결책을 강제하지는 않는다.
- 동일 family에서 PASS가 3회 이상 연속 발생하면, 다음 사이클에는 반드시 반대 가설(Counterfactual) 1개를 생성한다.


---

## FILE: `02_DataLake_and_DB_Policy.md`

# 02. DataLake and DB Policy

## 1) 목표

- “엑셀/파일 더미”를 **에이전트들이 동시에 읽고, 검증하고, 재현 가능한 형태**로 바꾼다.
- 최종 목표는 **전략 리서치/운용이 데이터 때문에 멈추지 않는 상태**.

---

## 2) 계층 구조(권장)

### L0. RAW (Immutable)
- 퀀티와이즈/ DART / 기타 소스에서 받은 원본 파일을 **절대 수정하지 않고** 저장
- 파일명 규칙 예:
  - `source=quantywise/type=prices/asof=2026-03-01/file=...`
  - `source=dart/type=fs/asof=2026-03-01/corp=...`

### L1. STAGING (Normalized)
- 원본을 파싱해 “정규화 테이블”로 변환(형식 통일)
- 핵심 키:
  - `date`, `ticker(or corp_code)`, `item_code`, `value`, `currency`, `freq`, `asof_date`

### L2. FEATURES (Point-in-time)
- 피처는 반드시 **as-of** 기준으로 생성
- 공시 시차를 반영:
  - `reporting_period_end`, `filing_date`, `available_date`(투자자가 실제로 알 수 있는 날짜)

### L3. UNIVERSE (Tidy)
- 당신이 이미 운용 중인 “tidy Universe”를 **최종 분석/전략 입력 인터페이스**로 둔다.
- 원칙:
  - 1행 = (date, ticker)  
  - 열 = 종목기본정보 + 팩터/리스크/필터 피처

---

## 3) 로컬 DB를 둘 것인가?

### 결론(권장): **DB + 파일형 데이터레이크 혼합**
- RAW는 파일로(감사/재현/원본 보존).
- STAGING/FEATURES/UNIVERSE는 DB로(증분 적재, 동시 접근, QC 자동화).

### DB 선택 가이드(로컬/단일 사용자 전제)
- 1순위: **DuckDB**
  - 파일 기반이면서 SQL/분석에 강하고, 단일 파일로 백업 용이
- 2순위: **SQLite**
  - 가장 단순/견고. 다만 대용량 분석 성능은 상대적으로 약함
- (추가) Parquet Lake
  - DB 없이도 가능하지만, 멀티 에이전트 오케스트레이션에서는 “락/동시성/증분 적재”가 불편해질 수 있음

---

## 4) 업데이트 워크플로우(데일리)

전제: 사용자가 새벽/장마감 이후 **원본 다운로드**를 직접 수행(또는 벤더 API가 있으면 자동화).

1. RAW 적재 (Data Steward)
2. STAGING 업데이트 (파싱/정규화)
3. QC 실행 (필수)
4. FEATURES 업데이트 (as-of 적용)
5. UNIVERSE 생성 및 검증
6. 스냅샷 봉인 + “데일리 브리핑” 트리거

---

## 5) QC 체크리스트(최소 필수)

### (A) 스키마/키 무결성
- (date, ticker) 유일성
- 필수 컬럼 NULL 비율 경고/차단 기준
- 데이터 타입(숫자/문자/날짜) 강제

### (B) 시계열 합리성
- 가격: 음수/0 값, 극단 수익률(상하한) 플래그
- 거래대금/거래량: 비정상 급증/급감 플래그
- 재무: 자본/자산 등 “논리적으로 불가능한 조합” 탐지

### (C) 범위/커버리지
- 유니버스 종목 수, 섹터 분포, 시총 커버리지 추적
- 신규 상장/상폐 반영 확인

### (D) 룩어헤드 방지 검사
- `available_date` 이전에 피처가 사용된 흔적이 있으면 즉시 실패

---

## 6) DART 구축(2015+)

- 원칙: **공시 원문(원시) 보존 + 표준화 + 정정/재작성 이력 관리**
- 가장 중요한 설계 포인트:
  - `asof_date`(수집일)과 `filing_date`(공시일) 분리
  - 동일 기업/동일 기간 재무제표가 정정되는 경우 **버전 레코드**로 남기고,
    전략 백테스트는 `available_date` 기준으로만 조회

---

## 7) 보안/운영 원칙(로컬)

- 인터넷 허용 시:
  - 화이트리스트 도메인(논문/뉴스/DART 등)
  - 다운로드 파일은 RAW 영역에만 저장
- 산출물/로그는 모두 로컬에 저장하고 외부 전송 금지


---

## FILE: `03_Feature_Store_and_Factor_Definitions.md`

# 03. Feature Store and Factor Definitions

## 1) 목표

- “팩터 계산은 아무렇게나 하면 된다”를 금지한다.  
  팩터는 **정의(Definition)** 가 곧 전략의 정체성이다.

---

## 2) 피처 계약(Feature Contract)

모든 피처는 아래 메타데이터를 갖는다.

- `feature_name`
- `definition` (수식/계산 절차)
- `source_table` (RAW/STAGING 경로)
- `unit` (원/%, 배수 등)
- `frequency` (daily/monthly/quarterly)
- `available_date_rule` (공시/시차 규칙)
- `transformations` (winsorize, zscore, neutralize 등)
- `known_failure_modes` (결측/정정/분모=0 등)

---

## 3) 팩터 정의 원칙(데이터 마이닝 방지)

### 원칙 A: 학술/산업 표준 프록시 우선
- 예: Value는 “저평가(valuation ratio)”를 대표하는 프록시를 우선 사용.
- “마케팅적 합성지표(복잡한 composite score)”는 데이터 마이닝 위험이 급증할 수 있으므로,
  - **단순 프록시 + 명확한 경제적 직관**을 우선한다.

### 원칙 B: ‘가짜 팩터’ 경계
- 같은 이름이라도 프록시가 다르면 다른 팩터다.
- 예: 매출/배당/현금흐름 같은 “펀더멘털 규모” 지표를 Value로 오해하지 않는다.

---

## 4) 표준 변환(권장)

- 결측 처리:
  - 결측이 구조적이면(공시 미제출/신규 상장) → **유니버스 필터**로 처리
  - 결측이 잡음이면(파싱 오류 등) → Data Steward QC로 되돌림

- 극단치:
  - 횡단면 winsorization(예: 1%/99%) 또는 robust z-score
  - 단, winsorize 자체가 성과를 만든다면(경계 민감) 데이터마이닝 가능성 플래그

- 중립화(neutralization):
  - 섹터/시총 중립화는 “원 전략의 의도”에 맞는 경우에만 적용  
  - 중립화 여부가 성과를 좌우한다면, 그 자체가 리스크 요인

---

## 5) 룩어헤드 방지: as-of 조회 규칙

- 모든 피처/재무는 “기준일(date)”과 “가용일(available_date)”이 분리되어야 한다.
- 전략 백테스트 시점 t에서 조회 가능한 데이터만 사용:
  - `available_date <= t` 인 레코드만 허용

---

## 6) 한국시장 특수 이슈(필수 고려)

- 상장폐지/거래정지/관리종목:
  - 유니버스 필터의 **규칙화**가 필요
- 공시 빈도/정정:
  - 정정 공시가 잦을 수 있으므로, “최종본”을 과거에 끼워 넣지 않도록 설계

---

## 7) 유니버스 출력 표준

- 파일/테이블명: `universe_daily` 또는 `universe_monthly`
- 최소 컬럼:
  - `date`, `ticker`, `name`, `exchange`, `sector`, `mktcap`
  - `tradable_flag`, `liquidity_proxy`, `delist_flag`
  - 팩터들(예: value, momentum, quality, lowvol, size, profitability, investment 등)

---

## 8) v1.1 추가: 전략/팩터 레벨 파생 피처(밸류에이션)

목표: 블렌딩/국면배분에서 사용할 밸류에이션 지표를 **일관된 기준으로** 생산한다.

- `strategy_valuation_ratio_{metric}`
  - 예: `strategy_valuation_ratio_pb`, `..._pe`, `..._ps`
- `strategy_valuation_z_{metric}`
  - 로그-밸류에이션 비율의 z-score

필수 메타데이터:
- 어떤 집계 방식인지(가중평균 vs 집계비율)
- 어떤 분모 처리 규칙인지(음수/0 펀더멘털)
- 어떤 히스토리 윈도우인지(예: 120m)

> 본 파생 피처는 **Valuation Agent(11번)** 가 산출하되, 정의/계약은 Feature Engineer가 관리한다.

## v1.4 Addendum — Feature/Factor Taxonomy 메타데이터
각 피처/팩터 정의는 아래 라벨을 메타데이터로 가져야 한다.
- economic_family
- construction_family
- neutrality
- horizon
- capacity_bucket
- evidence_tier

이 라벨은 19장 taxonomy와 일치해야 하며, duplicate control과 blender, catalyst reference bundle에서 재사용된다.


---

## FILE: `04_Strategy_Spec_Template.md`

# 04. Strategy Spec Template

> 이 문서는 에이전트가 Manager/Risk Auditor에게 제출하는 **전략 설계 계약서**다.  
> 스펙이 불완전하면 백테스트 결과가 아무리 좋아도 “심사 불가(Reject)”로 처리한다.

---

## 0) 헤더(YAML 권장)

```yaml
strategy_id: STRAT_YYYYMMDD_xxx
name: "..."
author_agent: "Factor Strategy Builder"
universe: "KOSPI200 | KOSDAQ150 | ALL-KR (rules...)"
rebalance_freq: "monthly"
holding_period: "1M"
benchmark: "KOSPI200 TR"
version: "0.1"
data_snapshot_id: "DS_..."
```

---

## 1) 투자 아이디어(논리)

- 한 문장 요약:
- 경제적/행태적 메커니즘:
- 어떤 리스크를 먹는가(보상받는 리스크 vs 우연):
- 실패하는 환경(언제/왜 망가지는가):

---

## 2) 신호(Signal) 정의(수식 필수)

- 입력 피처:
- 계산 절차:
- 횡단면 처리:
- 중립화 여부(섹터/시총/베타):
- 결측 처리:

---

## 3) 포트폴리오 구성(Portfolio Construction)

- 롱온리/롱숏(한국은 실무상 롱온리 중심):
- 상위/하위 몇 %:
- 가중 방식:
  - equal weight / cap weight / risk parity / 최적화 등
- 제약조건:
  - 종목당 최대 비중
  - 섹터/스타일 제한
  - 회전율(턴오버) 제한
  - 거래가능성(유동성/거래정지 제외)

---

## 4) 거래비용/슬리피지/체결 가정

- 비용 모델(기본):
- 충격비용(선형/비선형):
- 체결 지연(예: T+1 오더 적용):
- 호가단위/거래대금 제약:

---

## 5) 리스크 모델 & 리스크 예산

- 위험지표:
  - 변동성, MDD, VaR/ES, 베타, 팩터 익스포저 등
- 리스크 예산(최대 허용):

---

## 6) 검증(Validation) 계획

- In-sample / Validation / Test 분할:
- 강건성 테스트:
- 민감도(파라미터) 테스트:

---

## 7) 운용/모니터링 규칙

- 리밸런싱 실패 시 대체 규칙:
- 드리프트/이상치 발생 시 경보 트리거:
- 전략 중단 조건:

---

## 8) 산출물

- `backtest_report.md`
- `risk_audit.json`
- `trade_list_yyyymm.csv` (월간)


---

## FILE: `05_Backtest_Protocol_and_Validation.md`

# 05. Backtest Protocol and Validation

## 1) 목적

- “백테스트는 항상 거짓말을 한다”를 전제로, 거짓말을 최소화하는 규칙을 강제한다.
- v1.4.1에서는 **계산 자원 최적화**를 위해 `Preflight → Full Run` 2단계 구조를 도입한다.

---

## 2) 필수 규정(위반 시 무효)

1. **포인트-인-타임 데이터**
2. **생존편향 제거**
3. **상장폐지/거래정지 반영**
4. **거래비용/슬리피지 반영**
5. **리밸런싱 규칙 고정**
6. **테스트 구간은 절대 튜닝 금지**
7. **실험 계약서 없이 실행 금지**(14장 준수)

---

## 3) 실행 단계(Stage-gated Execution)

### Stage A: Preflight (빠른 예비검사)
목표: “돌릴 가치가 있는지”를 빠르게 판단한다.
- 짧은 구간/축소 샘플 가능
- 점검 항목:
  - 데이터 결측/스키마 이상
  - TO 계산 정의 일치 여부
  - 비용 모델 결합 오류 여부
  - 구현상 obvious bug
  - 대략적 성과 방향성(Sharpe0, MDD, TO)
- Preflight FAIL이면 Full Run 금지

### Stage B: Full Run (정식 실험)
목표: 허들/리스크/통계 검증까지 포함한 정식 평가
- IS/OOS/워크포워드 포함
- Stress window 및 factor-model alpha validation 연결

---

## 4) 시간 분할(권장)

- 월간 전략 기준:
  - Train(학습/탐색): 과거 구간
  - Validation(선정/튜닝): 중간 구간
  - Test(최종 확인): 최근 구간(“봉인 구간”)

추가로 “롤링 워크포워드”로 재검증:
- 예: 5년 학습 → 1년 테스트를 한 칸씩 굴림

---

## 5) 비용/제약(보수적으로)

- 거래비용은 최소 2가지 시나리오로 보고:
  - Base / Stress(예: 2배 비용)
- 회전율(턴오버)이 성과의 핵심이면,
  - 실행 가능성(capacity) 테스트를 필수로 수행
- 월간 리밸 전략은 **실제 홀딩 변화 기준 TO**를 사용한다.

---

## 6) 필수 성과 지표(최소)

- 누적수익, CAGR, 연환산 변동성
- **Sharpe0 (Rf=0%)**
- Sortino
- Max Drawdown, Calmar
- **ES99 (월간 기본, 일간 선택)**
- 정보비율(IR) vs Benchmark
- 월별 승률, 최악의 1M/3M 성과
- 턴오버, 거래비용 기여도(성과 분해)

---

## 7) 필수 리스크 진단

- 기간별(롤링) 성과/리스크
- 스트레스 구간 성과(예: 코로나 급락, 금리 급등 구간 등)
- 보유 종목 수/집중도(HHI) 추적
- 상관 급등/유동성 급감/공분산 붕괴 플래그

---

## 8) 강건성(robustness) 테스트(필수)

- 파라미터 민감도:
  - 상위 10% vs 20%
  - winsor 1% vs 2%
  - 리밸런싱 월간 vs 분기 등
- 유니버스 민감도:
  - 대형주만 / 제외 규칙 변경
- 지연 테스트:
  - 공시/체결 1일~5일 지연
- Null / Placebo:
  - 신호 셔플 / 랭킹 반전 / 기간 축소 등 최소 1개

---

## 9) 결과 패키징

- 모든 백테스트 산출물은 `experiment_id`로 폴더링
- 데이터/피처 버전 태그 포함
- 결과물 최소 세트:
  - `backtest_report.md`
  - `backtest_metrics.json`
  - `returns_timeseries.parquet`
  - `holdings_by_rebal.parquet`
  - `parameter_manifest.json`

---

## 10) v1.4.1 주의사항

- Full Run 전에 Strategy Fingerprint를 계산해 **중복 실험인지 확인**한다.
- “좋은 숫자”보다 “비교 가능한 숫자”가 먼저다.
- 지표 정의가 바뀌면 과거 Full Run과 직접 비교하지 않는다(버전 분리).

## v1.4 Addendum — Alpha Lab과 Full Validation의 역할 분리
- Alpha Lab은 cheap reject 용이며, Full Run을 대체하지 않는다.
- Full Validation은 여전히:
  - 비용/리밸 규칙 고정
  - OOS / stress / ES99 / MDD
  - factor-model alpha validation
  - multiple-testing defense
를 포함해야 한다.


---

## FILE: `06_Hurdle_System.md`

# 06. Hurdle System (전략 심사/합격 기준, v1.4.1)

## 0) 왜 허들이 필요한가

- 스마트베타/팩터 전략은 **백테스트 과적합(데이터 마이닝)** 과 **밸류에이션/리레이팅 효과**로 “가짜 알파”가 만들어지기 쉽다.
- 단일 팩터는 긴 사이클 언더퍼폼을 겪을 수 있고, 멀티전략 앙상블은 조합 폭발과 중복 노출 위험이 있다.
- 따라서 “수익률 하나”가 아니라 **Validity → Implementability → Robustness → Performance → Novelty** 순으로 심사해야 한다.

---

## 1) Objective Hierarchy (최상위 규칙)

전략 평가는 다음의 **사전순(lexicographic) 우선순위**를 따른다.

1. **Validity**
   - PIT, 데이터 무결성, 재현성, 지표 정의 일치
2. **Implementability**
   - TO, 비용, 유동성, 집행 가능성, 용량(capacity)
3. **Robustness**
   - OOS 유지력, Stress, ES99, Drawdown 경로
4. **Performance**
   - Sharpe0, CAGR, IR, hit-rate
5. **Novelty**
   - 새로운 알파 소스, 직교성, 학습가치

상위 단계에서 FAIL이면 하위 단계의 성과가 좋아도 승격할 수 없다.

---



## 1A) KPI 표준(부호/빈도 통일)
- 기본 Sharpe 표준: `Sharpe0_m_ann` = **월간 수익률 기반 연환산 Sharpe (Rf=0%)**
- 보조 Sharpe: `Sharpe0_d_ann` = 일간 수익률 기반 연환산 Sharpe (진단용)
- 기본 Tail 표준: `ES99_m` = **월간 수익률 기준 Expected Shortfall(1% tail), 양의 손실 크기 표기**
  - 값이 작을수록 좋다.
- 보조 Tail: `ES99_d` = 일간 기준 (진단용)
- Grade / Promotion / Briefing의 기본 KPI는 `Sharpe0_m_ann`, `ES99_m`를 사용한다.

## 2) 전략 등급 구분

### A. Standalone 전략(단독 편입 후보)
- 목표: 단독으로도 포트폴리오의 핵심이 될 수 있는 전략
- 요구: **비용 차감 후 CAGR ≥ 16%** + 강한 Sharpe0 + Robustness 확보

### B. Component 전략(구성요소/다이버시파이어)
- 목표: 단독 수익률이 낮더라도, 포트폴리오 전체의 효율(Sharpe/IR/CVaR/MDD)을 개선
- 요구: 상관/리스크 기여 관점에서 가치가 있어야 함

### C. Ensemble 전략(블렌딩 결과물)
- 목표: 여러 Standalone/Component의 조합으로 **경로 안정화 + 목표 수익률 달성 확률 개선**
- 요구: 단순 백테스트 수익이 아니라 **조합의 안정성과 재현성**을 증명

### F. Fail
- Goal hierarchy를 통과하지 못한 전략

---

## 3) 게이트 방식(권장)

### Gate 0: Validity
- 포인트-인-타임 위반 없음
- 생존편향/상폐 처리 확인
- 데이터 QC 통과
- 동일 실험 재실행 시 결과 일치

### Gate 1: Implementability
- 실제 홀딩 기반 TO 산출
- 거래비용/슬리피지 반영
- 유동성/종목수/집중도 제약 충족
- 월간/분기 리밸이 실제로 실행 가능한 구조인지 확인

### Gate 2: Robustness
- OOS retention 양호
- Stress window에서 생존성 확보
- MDD 상한, ES99, 최악 기간 손실, 회복기간 점검
- 파라미터/유니버스/비용 민감도에서 붕괴하지 않을 것

### Gate 3: Performance
- **Sharpe0를 핵심 우선 지표**로 사용
- CAGR, IR, Hit Rate는 보조
- A/B/C 등급은 Sharpe0와 CAGR의 조합으로 판단하되, Goal hierarchy 우선

### Gate 4: Statistical Validation (v1.3 신규 핵심)
PASS 또는 Near-pass 전략은 아래 검증을 수행한다.

#### 4-1. Time-series Alpha Validation
월간 초과수익(벤치마크 대비)에 대해 아래 모델로 알파를 검증한다.
- Fama 3-Factor
- Carhart 4-Factor
- Fama 5-Factor

권장 규칙:
- **A 후보**: 적어도 하나의 모델에서 양(+)의 alpha와 유의한 t-stat 또는 경제적으로 유의한 alpha를 보여야 하며, 어떤 모델에서도 의미 있게 음(-)의 alpha가 나오면 경고
- **B/C 후보**: alpha가 약해도 분산/리스크 개선이 뚜렷하면 유지 가능. 단, alpha가 일관되게 음(-)이면 Component 가치 재검토

#### 4-2. Fama–MacBeth Cross-sectional Validation
개별 종목 신호를 사용하는 전략은 가능한 경우 반드시 수행.
- 월별 단면 회귀: 다음 기간 수익률 ~ 신호 + 통제변수
- Newey–West 표준오차 권장
- 결과:
  - slope sign consistency
  - average slope
  - t-stat

Fama–MacBeth는 “전략 수익률”이 아니라 “신호의 단면 설명력” 검증에 사용한다.

#### 4-3. Multiple Testing Defense
- 실험 family별 trials 수를 집계한다.
- 권장 보조 지표:
  - Deflated Sharpe Ratio
  - FDR(False Discovery Rate)
  - Reality Check / SPA (여건 허용 시)
- 동일 family에서 후보를 많이 생성할수록 승격 기준을 더 보수적으로 적용한다.

### Gate 5: Diversification & Redundancy
- 기존 전략/포트와의 상관, 노출 유사도, return-path similarity 확인
- 중복성이 높으면 “새로운 전략”이 아니라 alias 또는 variant로 처리

---

## 4) 점수화(Manager가 전략을 비교할 때)

전략 점수는 5개 축으로 구성한다.

1. **Return**: Sharpe0, CAGR, IR  
2. **Risk**: MDD, ES99, tail risk, beta  
3. **Robustness**: OOS retention, parameter stability, stress_outperformance  
4. **Implementability**: turnover, liquidity, cost sensitivity  
5. **Diversification**: 상관, role 가치, 한계기여(MCTR)

> v1.4.1 원칙: **Sharpe0는 Return 축의 1순위 KPI** 이다.

점수화는 “단일 숫자”로 끝내지 말고, 항상 **레이더 차트/테이블**과 함께 보고한다.

---

## 5) 금지 규칙(즉시 탈락)

- 테스트 구간을 보고 나서 규칙을 바꾸는 행위(누설)
- 허들을 통과시키기 위한 “지표 최적화”  
  (예: MDD를 줄이려고 룩어헤드성 손절 규칙 삽입)
- 결과는 좋은데 “왜 되는지 설명 불가”
- 조합 폭발(수천~수만 조합을 돌려 승자만 제출)
- 통계 검정 없이 높은 Sharpe/CAGR만 보고 PASS 주장

---

## 6) Near-Miss 처리 원칙

Hard Fail이 아니라 임계값 근처에서 실패한 전략은 “가치 있는 실패”로 취급한다.
- 예: MDD 45.4%, CAGR 15.8%, Sharpe0 0.98
- 이 경우 **Repair Ticket**를 생성하고,
  - 목적 축(예: Risk 또는 Return)
  - 기대되는 단일 변경(버퍼존, 쿨다운, n_hold 등)
  - 성공 기준
을 명시한다.

Near-Miss를 Fail과 동일하게 폐기하면 자가발전 효율이 떨어진다.

## v1.4 Addendum — Stage 0 Alpha Lab / Stage 1 Research Validation

### 5) Two-Stage Hurdle Architecture
v1.4는 허들을 아래 두 단계로 분리한다.

#### Stage 0: Alpha Lab (cheap reject)
목적:
- 계산비용이 큰 정식 검증 전에 아이디어를 빠르게 걸러낸다.
- WorldQuant BRAIN 공개 자료의 철학(quality + quantity, IS/OOS 분리, 중복/상관 관리)을 참고하지만, 내부 점수체계를 복제하지는 않는다.

입력 지표(권장):
- IS Sharpe0
- Fitness-like metric
- Turnover band
- Self-correlation
- Sub-universe robustness
- Weight concentration flags

판정:
- ALPHA_LAB_PASS / ALPHA_LAB_FAIL
- 이 단계 통과는 “정식 검증 가치가 있다”는 뜻이지, Production 승격이 아니다.

#### Stage 1: Research Validation (정식 검증)
- 기존 Grade(A/B/C/F) + Statistical Validation + Risk Audit을 그대로 수행
- FF3/Carhart4/FF5, Fama–MacBeth, ES99, multiple testing defense 적용

### 6) WQ-inspired 기준 사용 시 주의
- WorldQuant 공식 공개 문서는 scoring methodology가 단계별로 달라질 수 있음을 명시한다.
- 따라서 Fitness / Self-correlation / Sub-universe 등의 기준은 **내부 hard law가 아니라 heuristic gate** 로만 사용한다.


## 3A) Alpha Lab PASS의 의미 제한
- Alpha Lab PASS는 **정식 검증 가치가 있음**만 의미한다.
- Alpha Lab PASS는 lifecycle 상태를 `ALPHA_LAB`으로만 올릴 수 있다.
- Candidate / Paper / Production 전환에는 직접 사용 금지.

## 3B) 이중 승격 구조
전략은 다음 두 단계를 모두 통과해야 실제 채택 가능하다.
1. **Strategy-level pass**: A/B/C/F 등급 및 Hard gate 통과
2. **Portfolio-level admission**: 기존 전략군 대비 한계 기여(ΔSharpe0_m_ann, ΔMDD, ΔES99_m, ΔDiversification, ΔTO) 확인

상관이 매우 높은 전략(corr > 0.85) 또는 동일 `dup_group` 전략은 새로운 채택이 아니라 `variant/alias`로만 등록한다.


---

## FILE: `07_Risk_Audit_and_Stress_Tests.md`

# 07. Risk Audit and Stress Tests

## 1) 리스크 심사관(Risk Auditor)의 임무

- 전략이 **운용 가능한 리스크 프로파일**을 가지는지 검증
- “잘 될 때”가 아니라 **안 될 때**를 먼저 분석
- v1.4.1에서는 변동성만이 아니라 **ES99, 기간 불일치, 군집위험, 통계적 위장(alpha illusion)** 도 함께 점검한다.

---

## 2) 필수 체크리스트(최소)

### (A) 시장 리스크
- 시장 베타(rolling)
- 하락장(베어) 조건부 성과
- 변동성 급등 국면에서의 성과

### (B) 팩터/스타일 노출
- Value/Momentum/LowVol/Quality/Size 등
- 특정 팩터에 과도하게 의존하는가?
- 다중공선성(겉은 다르지만 속은 같은 전략) 여부

### (C) 섹터/산업/테마 집중
- 섹터 상한 위반 여부
- 특정 섹터/테마 쏠림 위험

### (D) 유동성/거래가능성
- 거래대금 대비 포지션 규모(추정)
- 리밸런싱 시 ‘매매 불가능’ 비율
- 거래정지/상폐 이벤트에 대한 규칙

### (E) 꼬리위험(Tail Risk)
- **ES99 (monthly 기본, daily 선택)**
- 최악 월/분기 성과
- 급락장에서의 동작(“손절”이 아니라, 구조적 방어인지)

### (F) 혼잡도/군집(Crowding/Herding) 리스크
- 팩터가 “유행”이 되면, 기대수익이 줄어들 가능성
- 투자자 군집 행동이 리스크로 작동할 수 있음

### (G) 기간/샘플 정합성
- 앙상블/비교 시 표본 길이가 의도치 않게 짧아졌는가?
- inner join / outer join / 공통구간 제한 규칙이 문서와 일치하는가?

---

## 3) 스트레스 테스트 세트(권장)

- 비용 2배/3배
- 체결 지연 1~5일
- 상위 유동성 종목만(필터 강화)
- 리밸런싱 빈도 변경
- 특정 연도 제외(one-period dependency 탐지)
- crisis correlation jump (상관 급등) 시나리오
- benchmark reversal 구간(강한 V자 반등) 성과

---

## 4) 리스크 리포트 산출물

- `risk_audit.json`:
  - pass/fail
  - fail_reason_codes
  - key_exposures
  - stress_test_summary
  - cvar99_monthly
  - period_alignment_flags
  - crowding_flags
- `risk_audit.md`:
  - 사람용 요약 + 대응 권고(수정 가능한 액션으로)

---

## 5) v1.3 추가 권고

### RA-01. Regime-conditioned drift
- 국면별로 factor/style 노출이 얼마나 흔들리는지 보고한다.
- 예: Stress 국면에서 LowVol 노출이 사라지면 “설계 실패” 가능성 점검

### RA-02. Statistical illusion check
- 높은 Sharpe0가 단일 국면/단일 이벤트에서만 왔는지 확인
- factor-model alpha가 음(-)인데 raw return만 좋으면 “시장/스타일 위장” 경고

### RA-03. Crowding proxy dashboard
- 전략 패밀리별 AUM proxy, ETF 흐름 proxy, 상관 동조화, valuation stretch를 위험 대시보드로 관리


---

## FILE: `08_Ensemble_and_Regime_Playbook.md`

# 08. Ensemble and Regime Playbook

## 1) 앙상블의 목표

- “좋은 전략 하나”가 아니라,
  - **여러 전략의 조합이 목표 CAGR 16%를 더 안정적으로 달성**하도록 설계한다.
- 단일 팩터/단일 전략의 장기 성과가 좋더라도,
  - 실전에서는 **긴 언더퍼폼 구간(드로다운/사이클)** 이 필연적으로 발생할 수 있으므로,
  - 조합의 목적은 “평균 수익 극대화”보다 **경로(Path) 안정화**에 둔다.

---

## 2) 앙상블 탐색 규칙(조합 폭발 방지)

- 후보 전략 풀을 무한히 늘리지 않는다.

권장 단계:
1) 단일 전략 평가(허들)
2) 상위 N개만 후보로 유지(예: 20개)
3) 단순 결합부터(동일가중/리스크패리티)
4) 마지막에만 제약최적화(최소분산/최대샤프)
5) 마지막에만 메타러닝/스태킹(가급적 금지에 가까움)

금지:
- “전략 수 늘리면 언젠가 된다”식 탐색
- 테스트 구간에서 조합을 고르는 행위
- 구성요소를 지나치게 늘려 ‘조합 자체’가 데이터 마이닝이 되는 상황

---

## 3) 국면모델(Regime) 원칙

### (A) 국면 정의는 단순해야 한다
- 변수 수를 최소화(예: 변동성/추세/신용스프레드 등)
- 국면 수는 적게(2~4개 권장)

### (B) 국면은 설명 가능한 경제 상태여야 한다
- “과거 수익률이 잘 나오도록 만든 클러스터”는 탈락

### (C) 국면별 배분은 완만해야 한다
- 극단적 올인/올아웃 금지
- 포트폴리오 분산을 유지

---

## 4) 밸류에이션 기반 팩터/전략 조절(Valuation Overlay)

### 4.1 설계 철학

- 성과 추격(performance chasing) 대신,
  - “상대적으로 싸진 전략/팩터를 조금 더, 비싸진 전략/팩터를 조금 덜” 같은 **완만한 조절**만 허용.
- 밸류에이션은 예측이 아니라, **진입 시점 리스크(Entry point risk)** 를 완화하는 장치다.

### 4.2 운용 구조(권장 분업)

- **Valuation Agent(11번)**: 밸류에이션 지표 산출(싸다/비싸다) + 불안정 플래그
- **Blender Agent(12번)**: 밸류에이션을 “오버레이(조미료)”로 적용하여 앙상블 가중치 제안

> 밸류에이션을 “전략 자체”로 승격시키지 않는다. 오버레이는 언제나 *보수적*이어야 한다.

### 4.3 오버레이 규칙(최소 기준)

- 오버레이는 **베이스라인 배분(동일가중/리스크패리티)** 위에만 얹는다.
- 틸트 강도 상한:
  - `tilt_cap`을 반드시 둔다(예: 전략 비중 변화 20%p 이내 또는 상대 30% 이내)
- 불안정 플래그:
  - 히스토리 부족/지표 불안정이면 틸트 강도를 0에 수렴(shrink)한다.

---

## 5) 앙상블 + 국면 + 밸류에이션의 결합 순서(권장)

1) **전략 합격(허들) → 후보 풀 확정**
2) 국면이 있으면: 국면별 베이스라인 가중치 `w0(regime)` 산출
3) 밸류에이션 오버레이로 작은 조정 `w = overlay(w0, valuation)`
4) 턴오버/거래비용/유동성 제약을 강제

금지:
- 국면 분류와 밸류에이션 오버레이를 동시에 최적화하여 Test 성과를 최대화하는 행위

---

## 6) 앙상블 산출물

- `ensemble_spec.md`
- `ensemble_candidates_ranked.md`
- `ensemble_weights_target.csv`
- `ensemble_backtest_report.md`
- (선택) `ensemble_attribution.md` (구성요소 기여/오버레이 기여 분해)

## v1.4 Addendum — Integrated Construction vs Portfolio Mix

### 7) 스타일/팩터 포트폴리오 결합 방식
- **portfolio mix**: 단일 스타일 포트폴리오들의 기계적 혼합
- **integrated construction**: 스타일 정보를 하나의 포트폴리오 구성 과정에 통합

권장 원칙:
1. baseline sleeves를 먼저 정의
2. 중복/상쇄 노출을 제거
3. integrated score 또는 constrained construction으로 포트폴리오 구축
4. 마지막에 valuation/regime/cost overlay를 작게 적용

### 8) orthogonal sleeves 우선
- Blender는 후보를 고를 때 상관만이 아니라 factor label taxonomy(19장)를 사용하여 서로 다른 economic family 대표 슬리브를 우선 채택한다.


---

## FILE: `09_Monthly_Rebalance_and_Daily_Briefing.md`

# 09. Monthly Rebalance and Daily Briefing

## 1) 월간 리밸런싱(핵심 업무)

### 월말 스냅샷 봉인
- 기준: 매월 말일(또는 마지막 거래일) 장마감 데이터
- 스냅샷 ID 발급 후, 그 달의 리밸런싱 의사결정은 이 스냅샷만 사용

### 월초 트레이드리스트 산출(권장 파이프라인)

1) **전략 리서치/백테스트**
- Factor Strategy Builder / Regime Modeler / (기타) 가 후보 전략 제출

2) **허들/리스크 심사**
- Risk Auditor가 Gate 0~5로 합격/불합격 판정

3) **밸류에이션 레이어 실행(v1.1)**
- Valuation Agent가 합격 전략/팩터에 대해:
  - 상대 밸류에이션 비율, z-score, (선택) 구조적 알파/리밸류에이션 분해
  를 산출

4) **블렌딩(앙상블) 레이어 실행(v1.1)**
- Blender Agent가:
  - 베이스라인(동일가중/리스크패리티)
  - 밸류에이션 오버레이(완만한 틸트)
  를 적용한 앙상블 후보를 제출

5) **최종 포트폴리오 선택 및 트레이드리스트 산출**
- Portfolio Manager AI가
  - 합격 앙상블(또는 단독 전략) 중 최종안 선택
  - 종목별 목표비중 + 예상 매매(매수/매도)
  - 거래비용 추정 + 리스크 변화(전월 대비)

### 브리핑 패키지(필수)

- Top line:
  - 이번 달 목표 포트폴리오
  - 전월 대비 변화(주요 매매 요인)

- 밸류에이션 요약(v1.1):
  - “비싸서 덜 담은 전략/팩터” vs “싸서 더 담은 전략/팩터”
  - 단, 틸트는 항상 `tilt_cap` 이내임을 명시

- 리스크:
  - 최대 비중, 섹터, 팩터 노출, MDD/ES 변화

- 실패 시나리오:
  - “어떤 상황에서 손실이 커질 수 있는가”

- 실행안:
  - 주문 분할/유동성 주의 종목 리스트

---

## 2) 데일리 브리핑(보조 업무)

목표: 월간 포트폴리오를 흔들지 않되, **리스크/이벤트에 대응**한다.

- 데이터 업데이트 완료 후 자동 생성:
  - 전일 성과(포트폴리오/벤치/전략별)
  - 리스크 지표 변화(베타/변동성/익스포저)
  - 이벤트:
    - 거래정지/상폐/관리종목
    - 공시(실적, 정정)
    - 급등락(이상치)

- 대응 정책:
  - “전략을 바꾸는” 대응은 월간 리밸런싱에서만.
  - 데일리는 **리스크 완화/집행 품질** 중심(예: 비중 상한 초과, 거래불가 등)

---

## 3) 성과관리 에이전트(권장)

- 사후 성과를 단순 추적이 아니라,
  - “왜 이겼는지/졌는지”를 **성과 분해**로 피드백해야 한다.
- 피드백 형태:
  - 데이터 품질 문제인가?
  - 비용/회전율 문제인가?
  - 국면 민감도 문제인가?
  - 팩터 밸류에이션/혼잡도 문제인가?

---

## 4) 에이전트 보상(Compute Budget) 설계 아이디어

- 월간 성과만으로 보상하면 노이즈가 크므로,
  - 장기(6~12개월) + 리스크조정(IR/Sharpe) 기반 점수
  - “과최적화 징후”가 있는 에이전트는 패널티
- 보상은 돈이 아니라:
  - 더 많은 탐색 예산(시뮬레이션 횟수)
  - 더 큰 후보 풀 유지 권한
  - 우선순위


---

# v1.2 Addendum — MonthlyRebal 운영 스케줄 (Perpetual과 충돌 방지)

아래 내용은 v1.1 `09_MonthlyRebal` 문서에 “추가”로 삽입한다.

---

## MR-NEW-01. Research vs Production 우선순위
- 월초(1영업일) “주문서 생성/검증”은 **항상 Production 우선**
- 월초 운영 창(window)에서는 Research WIP를 자동 축소하거나 pause할 수 있다

---

## MR-NEW-02. 월간 리밸런싱 산출물 고정 규칙
- 월간 주문서는 “전월말 데이터 스냅샷(PIT)”으로만 생성한다
- 영구기관 연구에서 새 전략이 PASS하더라도, 월초 주문서에는
  - “컷오프 이전에 승인된 전략”만 반영
  - 컷오프 이후 PASS는 다음 달부터 후보로 반영

---

## MR-NEW-03. 텔레그램 브리핑(월초)
월초 주문서 생성 완료 시 반드시 아래를 브리핑한다.
- 전략 포트폴리오 구성(grade/role 기반)
- 종목 리스트 + 비중(상위 n개)
- Turnover 예상치 + 거래비용 민감도
- Risk 요약: MDD, ES99, Sharpe0, 노출(섹터/스타일)

## v1.4 Addendum — Control Tower 연계 브리핑

### 4) Post-Trade Control Tower 브리핑
Production 전략/포트폴리오는 월간 브리핑 외에도 아래를 점검한다.
- intended vs realized exposures
- slippage / realized turnover
- capacity / crowding proxy
- WATCHLIST 전환 여부

### 5) 월초 Production window
- 월초 주문서 생성 창에서는 Research WIP를 자동 축소할 수 있다.
- Control Tower 경보는 Production window에서 연구보다 우선한다.


---

## FILE: `10_Orchestration_Message_Spec.md`

# 10. Orchestration Message Spec (v1.4.2)

## 1) 공통 메시지(작업 발행) 포맷

```json
{
  "task_id": "TASK_YYYYMMDD_0001",
  "parent_task_id": null,
  "task_family": "idioVol_monthly_repair",
  "idempotency_key": "hash(inputs+version)",
  "issued_at": "2026-03-06T02:00:00+09:00",
  "issuer": "ManagerAI",
  "assignee": "RiskAuditor",
  "mode": "research",
  "priority_score": 0.78,
  "objective": "Evaluate strategy STRAT_20260301_abc",
  "inputs": {
    "data_snapshot_id": "DS_20260229_EOM",
    "artifacts": ["strategy_spec.md", "backtest_report.md", "timeseries.csv"]
  },
  "constraints": {
    "market": "KR",
    "rebalance": "monthly",
    "language": "R"
  },
  "deliverables": [
    "risk_audit.json",
    "risk_audit.md"
  ],
  "quality_gates": ["no_lookahead", "cost_model_present", "stress_tests_run"],
  "artifact_hashes": {}
}
```

---

## 2) 상태코드(State)

- `created`
- `queued`
- `running`
- `blocked` (입력 부족/데이터 QC 실패)
- `paused`
- `failed` (재현 가능한 에러 포함)
- `done`
- `rejected` (정책 위반/허들 미달)
- `invalidated` (지표 정의/PIT/기간 정합성 문제로 결과 무효)
- `superseded` (상위 버전/상위 task에 의해 대체)

---

## 3) 재시도 규칙

- 입력이 동일하면 결과도 동일해야 한다(멱등성).
- 실패 시 “같은 입력으로 무한 재시도” 금지:
  - 원인 분류 → 수정 → 재실행
- `idempotency_key`가 동일하면 동일 task로 간주한다.

---

## 4) 산출물 저장 규칙

- 경로:
  - `artifacts/{task_id}/...`
- 모든 산출물에는 최소 메타데이터 포함:
  - `data_snapshot_id`
  - `code_version`
  - `parameters`
  - `metric_version`
  - `artifact_hash`

---

## 5) Queue Economics 필드 (v1.4.2 핵심)

### 5.1 priority_score
ResearchOps가 아래를 반영해 계산한다.
- Expected Gain
- Expected Learning
- Novelty
- Execution Cost
- Dependency Risk
- Family Penalty (다중검정/같은 패밀리 남발)

### 5.2 task_family
동일 계열의 실험을 family로 묶는다.
- 예: `idioVol_monthly_bufferzone`
- family 단위로 시도 횟수, PASS 비율, false-discovery penalty를 집계한다.

### 5.3 mode
- `research`
- `production`
- `infra`

Research mode에서는 LOOP=ON이 가능하지만, Production window에서는 우선순위가 뒤로 밀릴 수 있다.

---

## 6) 작업 예시

### (A) Statistical Validation 작업 발행

```json
{
  "task_id": "TASK_YYYYMMDD_0201",
  "task_family": "alpha_validation",
  "issuer": "ManagerAI",
  "assignee": "RiskAuditor",
  "objective": "Run FF3/Carhart4/FF5 alpha validation for PASS candidate",
  "inputs": {
    "strategy_returns": "returns_monthly.parquet",
    "factor_data": "factor_models_monthly.parquet",
    "benchmark": "KOSPI200_TR"
  },
  "deliverables": ["alpha_validation.json", "alpha_validation.md"],
  "quality_gates": ["monthly_returns_complete", "factor_data_complete"]
}
```

### (B) Fama–MacBeth 작업 발행

```json
{
  "task_id": "TASK_YYYYMMDD_0202",
  "task_family": "cross_sectional_validation",
  "issuer": "ManagerAI",
  "assignee": "RiskAuditor",
  "objective": "Run Fama-MacBeth validation on stock-level signal",
  "inputs": {
    "signal_panel": "signal_panel.parquet",
    "future_returns_panel": "future_returns.parquet",
    "controls": ["size", "value", "momentum"]
  },
  "deliverables": ["fm_validation.json", "fm_validation.md"],
  "quality_gates": ["pit_ok", "enough_cross_section", "enough_time_series"]
}
```

---

## 7) Mode / Loop 제어

- `MODE=PRODUCTION` : 월간 리밸런싱 산출/운용 우선
- `MODE=RESEARCH` : 연구 우선(Perpetual 가능)
- `LOOP=ON` : 청크 종료 후 자동으로 다음 청크 디스패치
- `LOOP=OFF` : 청크 1개 종료 후 정지

기본값(별도 지시 없을 때):
- `MODE=RESEARCH`
- `LOOP=ON`
- 단, 월초 주문서 생성 창에서는 `MODE=PRODUCTION` 우선

## v1.4 Addendum — 아이디어/컴파일/변형 메시지 타입

### 7) 추가 메시지 타입
#### IDEA_PROPOSAL
- Catalyst 또는 IdeaResearcher가 제출
- 목적: 새로운 메커니즘/아이디어를 실험 큐 후보로 등록

#### EXPERIMENT_TICKET
- Idea Compiler가 발행
- 목적: `ExperimentProtocol`을 충족하는 실행가능한 청크로 변환

#### MUTATION_REQUEST
- 실패/근접실패 실험에서 파생
- 목적: 기존 전략/아이디어의 수정 실험을 Backlog에 등록

### 8) mode 확장
- `alpha_lab`
- `validation`
- `production`
- `control_tower`


## 4) 이벤트/브리핑 중복 방지
- 텔레그램/브리핑 메시지는 `msg_hash = hash(event_type + related_id + major_metrics_snapshot + headline_template)` 로 식별한다.
- 동일 `msg_hash`는 24시간 내 재발송 금지.
- 단, 핵심 지표가 사전 정의된 임계치 이상 추가 변화하면 새로운 `msg_hash`로 재발송 가능하다.


## v1.4.2 Addendum — Memory Distillation / Retrieval Messages

### 9) Memory pipeline event types
오케스트레이터는 아래 이벤트를 발행할 수 있다.
- `RAW_BUFFER_FLUSH`
- `EPISODE_CREATED`
- `FACT_PROMOTED`
- `SCHEMA_REFRESHED`
- `RETRIEVAL_PACKET_CREATED`
- `DISTILLATION_VERIFY_FAIL`

### 10) Memory-related task families
- `memory_episode_compression`
- `memory_fact_extraction`
- `memory_schema_synthesis`
- `memory_retrieval_runtime`
- `memory_verification`

### 11) Retrieval packet 표준
연구/운용 런타임에서 기억 주입은 아래 packet으로 표준화한다.

```json
{
  "packet_id": "MEMPKT_YYYYMMDD_0001",
  "query_context": "rebalance|research|validation|control_tower",
  "schema_refs": ["SCHEMA_..."],
  "fact_refs": ["FACT_..."],
  "episode_refs": ["EP_..."],
  "policy_refs": ["POL_..."],
  "token_budget_used": 1330
}
```

### 12) Memory pipeline 우선순위
- Production/월간 리밸런싱에서는 `memory_retrieval_runtime`이 high priority
- 일반 연구 상황에서는 `memory_fact_extraction`, `memory_schema_synthesis`는 low/maintenance priority
- 증류 검증 실패(`DISTILLATION_VERIFY_FAIL`)는 infra-level alert로 승격한다.


---

## FILE: `11_Factor_and_Strategy_Valuation_Agent.md`

# 11. Factor and Strategy Valuation Agent

## 0) 역할 정의

- **팩터/전략의 밸류에이션(싸다/비싸다)을 정량화**하여, 블렌딩/국면배분의 입력 신호로 제공한다.
- 밸류에이션은 “예언”이 아니라 **기대수익의 조건부 조정(contrarian tilt) 근거**로만 사용한다.
- 본 에이전트는 **의사결정권(가중치/매매안 산출)** 이 없다. “측정/진단”만 한다.

---

## 1) 입력(필수)

- `data_snapshot_id` (월말 스냅샷, 예: `DS_YYYYMMDD_EOM`)
- `strategy_holdings` (전략별 보유 종목/비중, 월말 기준)
- `benchmark_holdings_or_universe` (벤치마크 또는 시장 전체)
- `fundamental_fields` (Book, Earnings, Sales, Cashflow, Dividends 등)
- `price_fields` (월말 종가, 수정주가)

> 밸류에이션 계산은 반드시 **포인트-인-타임(available_date <= rebal_date)** 규칙을 준수해야 한다.

---

## 2) 핵심 산출물(필수)

1. `valuation_report.md`
   - 이번 월말 기준: 어떤 팩터/전략이 **상대적으로 비싼지/싼지**
   - 극단(z-score) 구간 진입 여부와 경고 플래그

2. `valuation_table.csv`
   - 최소 컬럼:
     - `date`, `id`(factor/strategy id), `valuation_ratio`, `ln_valuation_ratio`, `zscore`, `metric`(PB/PE/PS/PCF/DY), `history_window`

3. `valuation_flags.json`
   - `extreme_cheap`, `extreme_expensive`, `insufficient_history`, `metric_instability`, `fundamental_quality_flags`

(선택)

4. `structural_vs_revaluation_decomp.csv`
   - `structural_alpha_est`, `revaluation_alpha_est`, `excess_return_est`

5. `expected_return_overlay.csv`
   - 밸류에이션 기반 기대수익 조정치(블렌더용)

---

## 3) 밸류에이션 정의(표준)

### 3.1 전략(Strategy) 밸류에이션 비율

전략 P, 벤치마크 M에 대해

- **전략의 P/F(가격/펀더멘털) 또는 F/P(펀더멘털/가격)** 를 먼저 정의한다.
- 본 법전은 “전략이 시장 대비 얼마나 비싼가/싼가”를 위해 **상대 밸류에이션 비율**을 사용한다.

권장(예: P/B 기준):

- 전략의 집계 P/B:
  - `P/B(P) = (Σ_i w_i * Price_i) / (Σ_i w_i * Book_i)`
- 벤치마크의 집계 P/B:
  - `P/B(M) = (Σ_j w_j * Price_j) / (Σ_j w_j * Book_j)`
- 상대 밸류에이션 비율:
  - `VR(P) = (P/B(P)) / (P/B(M))`

> 주의: 분모(펀더멘털)가 0 또는 음수인 종목은 **사전에 규칙으로 처리**해야 한다(제외/대체/바닥값).

### 3.2 팩터(Factor) 밸류에이션 비율

- 롱숏 팩터(가능한 경우):
  - `VR(F) = (P/F(long_leg)) / (P/F(short_leg))`
- 롱온리 팩터/슬리브(한국 실무 중심):
  - `VR(F) = (P/F(sleeve)) / (P/F(market))`

---

## 4) 표준화: ln + z-score

- 로그 변환:
  - `x_t = ln(VR_t)`
- z-score:
  - `z_t = (x_t - mean(x_{t-L..t-1})) / sd(x_{t-L..t-1})`

여기서 L(윈도우)은 기본 10년(120개월) 권장.

- 히스토리가 짧으면:
  - 최소 5년 미만이면 `insufficient_history = true`로 플래그
  - 블렌더는 해당 입력을 사용하더라도 **틸트 강도를 0에 수렴(shrink)** 시켜야 한다.

---

## 5) (선택) 구조적 알파 vs 리밸류에이션 분해

목표: 과거 초과수익이
- (A) **밸류에이션이 비싸져서 생긴 것(재현 어려움)** 인지,
- (B) **구조적으로 반복 가능한 것**인지
를 구분한다.

권장 절차(연율화 단위):

1) 전략(또는 팩터)의 초과수익을 정의:
- `excess_return_t = r_strategy_t - r_benchmark_t`

2) 밸류에이션 로그의 장기 추세를 회귀로 추정:
- `x_t = a + b * t + e_t`  
  (t는 연 단위)

3) `b`를 **리밸류에이션 알파(revaluation alpha)** 의 추정치로 간주:
- `revaluation_alpha_est = b`

4) 구조적 알파(반복 가능 성분):
- `structural_alpha_est = mean(excess_return) - revaluation_alpha_est`

> 분해 결과는 “전략 폐기/채택”의 단독 근거가 아니라, **블렌딩/타이밍의 과잉 자신감을 억제**하는 안전장치로 사용한다.

---

## 6) (선택) 밸류에이션 기반 기대수익 오버레이

원칙: 밸류에이션이 과거 평균 대비 비싸면 기대수익을 낮추고, 싸면 기대수익을 높인다.

- 기본형:
  - `E[r]_t = structural_alpha_est + beta * z_t`
  - 여기서 `beta < 0` (mean reversion 가정)

안전장치(필수):
- `beta`는 개별 팩터/전략에 대해 과최적화하지 말고,
  - 그룹 평균으로 **shrink** 하거나,
  - 사전 고정된 보수적 값(예: -0.5%p ~ -2.0%p per 1-sigma)을 사용한다.

---

## 7) QC 체크리스트(Valuation Agent)

- [ ] 밸류에이션 계산에 사용된 펀더멘털이 **available_date 규칙**을 만족하는가?
- [ ] 음수/0 펀더멘털 처리 규칙이 명시되어 있는가?
- [ ] 특정 한 지표(P/E 등)에만 의존하지 않고, 최소 2개 지표를 병행했는가?
- [ ] z-score가 극단값일 때(예: |z|>2) 원인(섹터 쏠림/회계이슈)을 점검했는가?
- [ ] 히스토리 길이 부족/지표 불안정 플래그가 올바르게 기록되었는가?

---

## 8) 금지 규칙

- 밸류에이션을 “추세추종(비싼데 더 사기)” 신호로 바꾸는 행위 금지.
- 밸류에이션 정의를 전략 성과가 좋게 나오도록 임의로 변경 금지.
- Test 구간의 성과를 보고 밸류에이션 윈도우/지표/처리 규칙을 바꾸는 행위 금지.

## v1.4 Addendum — Valuation Layer의 위치
- Valuation Agent는 `FactorLabel Taxonomy(19장)` 기준으로 economic family별 비교 가능성/비교 불가능성을 명시한다.
- baseline 대비 overlay budget을 직접 정하지 않는다. 이는 20장/12장 영역이다.


---

## FILE: `12_Factor_and_Strategy_Blender_Agent.md`

# 12. Factor and Strategy Blender Agent

## 0) 역할 정의

- **합격 후보 전략/팩터를 조합하여 “월간 운용 가능한 포트폴리오(앙상블)”를 설계/제출**한다.
- 본 에이전트의 목표는 “백테스트 숫자 최대화”가 아니라,
  - (1) **다이버시피케이션으로 다운사이드/드로다운을 줄이고**
  - (2) 목표 CAGR 16%를 더 **안정적으로** 달성하는 조합을 찾는 것이다.

---

## 1) 입력(필수)

- `data_snapshot_id` (월말 스냅샷)
- `approved_strategy_set`:
  - Risk Auditor의 Gate를 통과한 전략/팩터 후보 목록
  - 각 후보의 `strategy_spec.md`, `backtest_report.md`, `risk_audit.json` 포함
- `valuation_overlay_inputs`:
  - Valuation Agent 산출물: `valuation_table.csv`, `valuation_flags.json`, (선택) `expected_return_overlay.csv`
- `regime_inputs`(선택):
  - Regime Modeler 산출물: `regime_state.csv`, `regime_policy.md`
- `portfolio_constraints`:
  - 시장(KR), 롱온리, 월간 리밸런싱, 종목/섹터 상한, 턴오버 상한, 거래비용 모델

---

## 2) 핵심 산출물(필수)

1. `ensemble_candidates_ranked.md`
   - 후보 앙상블 3~10개 제시(너무 많으면 과최적화 유도)
   - 각 후보에 대해: 핵심 구성요소, 기대 역할, 장단점, 리스크 포인트

2. `ensemble_spec.md`
   - 앙상블 설계 계약서(04_Strategy_Spec_Template의 확장)

3. `ensemble_weights_target.csv`
   - 월초 실행 목표 비중(전략/팩터 단위)

4. `ensemble_backtest_report.md`
   - IS/VAL/TEST 결과 + 스트레스 테스트 + 민감도

5. `ensemble_audit.json`
   - 조합 생성 규칙/파라미터/탐색 공간(“얼마나 뒤졌는지”) 로그

---

## 3) 앙상블 설계 원칙

### 원칙 A: 단순 결합 → 마지막에만 복잡 결합

- 우선순위:
  1) 동일가중(1/N)
  2) 리스크패리티(전략 변동성/공분산 기반)
  3) 제약 최적화(예: 최소분산, 최대샤프)  
  4) 마지막에만 메타러닝/스태킹(단, 과최적화 위험 매우 큼)

### 원칙 B: 후보 전략 풀을 제한한다

- 합격 전략 중 **상위 N개만 유지**(기본 N=20).
- 상관/노출이 거의 같은 전략은 중복으로 간주하고 1개만 남긴다.

### 원칙 C: “밸류에이션 기반 타이밍”은 오버레이(조미료)다

- 밸류에이션은 완만한 틸트만 허용.
- 밸류에이션 하나로 포트폴리오가 뒤집히는 구조(올인/올아웃) 금지.

---

## 4) 표준 워크플로우(권장)

### Step 1. 후보 전략 풀 정리(중복 제거)

- 입력 후보(approved_strategy_set)를
  - `core`(핵심 성장 엔진),
  - `diversifier`(상관 낮은 완충재),
  - `defensive`(저변동/퀄리티/방어형)
  으로 라벨링한다.

- 중복 제거 규칙(예):
  - 36개월 롤링 상관이 0.8 이상이고,
  - 팩터 노출(베타 벡터) 유사도가 높으면
  → 둘 중 1개만 남기고 나머지 drop.

### Step 2. 베이스라인(기본 배분) 생성

- 기본 배분은 “해석 가능 + 안정성” 우선.
- 추천 기본 배분 2종을 반드시 생성:
  - (A) 동일가중  
  - (B) 리스크패리티(전략 변동성/공분산 사용)

### Step 3. 밸류에이션 오버레이(선택)

밸류에이션 오버레이는 **베이스라인 위에 작은 틸트**만 더한다.

- 입력: 각 후보 i의 밸류에이션 z-score `z_i` (Valuation Agent)
- 직관: `z_i > 0` (비쌈) → 비중 조금 감소, `z_i < 0` (쌈) → 비중 조금 증가

권장 함수(예시 1: 지수형, 부호 일관):

- `w_i* = w_i0 * exp(-k * z_i)`
- `w_i = normalize(w_i*)`

여기서
- `w_i0` : 베이스라인 비중
- `k` : 틸트 강도(기본 0.1~0.3 권장)

제약(필수):
- `|w_i - w_i0| <= tilt_cap` (예: 20%p 또는 상대 30%)
- 극단 밸류에이션(|z|>2)이라도 tilt_cap을 초과하지 않는다.

권장 함수(예시 2: 선형형, 더 보수적):

- `w_i = clamp(w_i0 + k * (-z_i), lower_i, upper_i)`
- 이후 전체 합이 1이 되도록 재조정

### Step 4. (선택) 국면(Regime) 오버레이와의 결합

- 국면 정책이 존재하면,
  - `w_i0`(베이스라인)을 국면별로 다르게 설정하고,
  - 밸류에이션 오버레이는 그 위에 얹는다.

금지:
- 국면과 밸류에이션을 동시에 최적화하여 Test 구간 성과를 최대화하는 행위.

### Step 5. 제약/턴오버/거래가능성 점검

- 턴오버 상한(월간) 준수
- 유동성/거래정지/상폐 이벤트에 대한 대체 규칙 포함
- 거래비용 2배/3배 스트레스에서도 “구조적으로” 유지되는지 확인

### Step 6. 검증(허들 + 리스크)

- Blender는 “전략 제출자”이므로, 허들 시스템(06)과 리스크 심사(07)에 맞는 **증빙**을 함께 제출해야 한다.

필수 검증:
- IS/VAL/TEST 분리
- Leave-one-out(구성요소 하나 제거) 테스트:
  - 특정 1개 전략이 성과 대부분을 설명하면 경고
- 비용/지연/리밸런싱 빈도 스트레스

---

## 5) 앙상블 스펙(ensemble_spec.md) 최소 요구 사항

- YAML 헤더:
  - `ensemble_id`, `name`, `author_agent`, `data_snapshot_id`, `benchmark`, `rebalance_freq`
- 구성요소 목록:
  - `component_id`, `role(core/diversifier/defensive)`, `base_weight_rule`
- 오버레이 규칙:
  - `valuation_metric`, `zscore_window`, `tilt_function`, `tilt_cap`, `shrinkage_rule`
- 제약조건:
  - `min_weight`, `max_weight`, `max_turnover`, `sector_caps`, `liquidity_rules`

---

## 6) 체크리스트(Blender Agent)

- [ ] 후보 전략 풀을 상위 N개로 제한했는가?
- [ ] “단순 결합(동일가중/리스크패리티)” 결과를 최소 1개 이상 포함했는가?
- [ ] 밸류에이션 오버레이는 tilt_cap을 넘지 않는가?
- [ ] 밸류에이션 지표가 불안정/히스토리 부족 플래그일 때 shrink가 작동하는가?
- [ ] Test 구간을 보고 조합을 고르는 행위를 하지 않았는가(데이터 누설 방지)?
- [ ] Leave-one-out로 ‘원샷 구성요소’ 의존성을 점검했는가?
- [ ] 거래비용 2배/3배에서도 “개선 효과”가 유지되는가?

---

## 7) 금지 규칙(즉시 Reject)

- “조합을 많이 돌리면 언젠가 된다”식 무제한 탐색
- Test 구간 성과를 보고 조합 규칙/파라미터를 변경
- 밸류에이션 정의를 성과 최적화 대상으로 삼아 과적합 유도
- 합격(Gate 통과)하지 못한 전략을 몰래 포함

## v1.4 Addendum — Blender의 baseline/overlay 책임
- Blender는 baseline sleeves를 먼저 만들고, overlay는 valuation/regime/cost 순으로 작게 적용한다.
- `portfolio mix`와 `integrated construction`을 모두 시도할 수 있으나, 두 방식을 혼합해 설명하지 않는다.
- leave-one-out, turnover budget, label_signature 중복 필터는 필수다.


---

## FILE: `13_SelfEvolution.md`

# 13 Self-Evolution & Perpetual Research Engine (v1.4.2)

## 13.0 목적
본 장은 멀티 에이전트가 **자가발전**(실험→평가→교훈→다음 실험으로 진화)하며,
리서처가 중단 명령을 내리기 전까지 **영구기관 형태로 연구를 지속**하기 위한 운용지침을 정의한다.

---

## 13.1 용어 정의

- **Research Chunk (연구 청크)**  
  “가설 1개”를 **설계→구현→백테스트→허들 평가→리포트→메모리 업데이트**까지 완결하는 최소 단위.
- **Backlog (백로그)**  
  아직 실행되지 않은 연구 청크 후보의 큐(queue).
- **WIP (Work In Progress)**  
  현재 실행 중인 연구 청크의 집합(동시 실행 스레드).
- **Trigger (트리거)**  
  새로운 청크를 생성하거나 텔레그램 브리핑을 발생시키는 조건.
- **Perpetual Mode (영구기관 모드)**  
  STOP/Pause가 오기 전까지 “자율 리서치 루프”가 **IDLE 상태로 떨어지지 않는** 운영 모드.
- **Circuit Breaker (안전 회로)**  
  무한 루프가 자원 고갈/무의미 반복으로 붕괴하지 않도록 하는 강제 제약.

---

## 13.2 절대 원칙 (Self-Evolution 8대 원칙)

### SE-01. 실험은 반드시 “계약서(ExperimentProtocol)”로 시작한다
- 어떤 청크도 `14_ExperimentProtocol.md` 형식의 실험 계약서 없이 시작 불가.

### SE-02. 기억은 “사후 합리화”가 아니라 “증거 기반 요약”이다
- 결과 파일/로그/메트릭 산출물이 존재하지 않으면 Memory 업데이트 금지. (15장 참조)

### SE-03. 영구기관은 “IDLE 금지 + 자원 제한”의 조합이다
- 멈추지 않되, **스레드·일일 실행량·디스크·연산시간**은 제한한다.

### SE-04. 조합 폭발을 일으키는 자동화는 금지한다
- 무작정 “모든 조합”을 돌리는 방식은 금지.  
  반드시 후보 축소(클러스터링/상관 필터/역할 분리/샘플링)를 선행한다.

### SE-05. 리서처의 명령이 최상위 우선순위다
- `/pause` : 현재 단계 완료 후 안전 정지
- `/stop` : 즉시 중단(가능하면 상태 저장)
- `/resume` : 중단 지점부터 재개
- `/loop_off` : 실험 1개 청크 완료 후 정지
- `/loop_on` : 영구기관 모드로 재진입

### SE-06. 연구 루프는 “목표함수”를 가진다
- 최우선 목표: **월간 운용 가능** + **검증 가능한 성과** + **CAGR 16% 목표 달성**
- 단, A/B/C 등급제에서 Component(B)·Ensemble(C)도 가치 있는 산출물로 인정한다.

### SE-07. Objective Hierarchy를 위반하는 진화는 금지
- 성능 개선이 Validity/Implementability 훼손 위에 세워지면 그 개선은 무효다.

### SE-08. 실험 family의 통계 부채를 기록한다
- 많이 시도한 패밀리일수록 더 엄격한 해석을 적용한다.

---



## 13.2A Hard Law vs Soft Prior
- **Hard Law**: PIT, 재현성, 비용 반영, 허들 정의, 중복/fingerprint 검사
- **Soft Prior**: 최근 교훈, 성공 패턴, 권장 neutralization/overlay/buffer 구조
- 에이전트는 Soft Prior를 반드시 참고하되, 그대로 복종할 의무는 없다.
- Soft Prior를 따르지 않을 경우에는 “왜 예외가 필요한지”를 실험 계약서에 명시한다.

## 13.2B 탐색 모드 분할 (Mode Collapse 방지)
Factor/Strategy 연구는 반드시 아래 세 모드로 예산을 분리한다.
- `EXPLOIT`: 승격 가능성이 높은 개선 탐색
- `ORTHOGONAL_SEARCH`: 기존 PASS 풀과 상관/노출이 낮은 아이디어 탐색
- `COUNTERFACTUAL`: 현재 정답처럼 보이는 설계를 반박하는 가설 탐색

권장 연구 예산(기본값):
- Exploit 50%
- Orthogonal Search 30%
- Counterfactual 20%

연구 파이프라인에서 동일 factor family의 활성 청크 비중이 40%를 넘으면 자동 경고를 발생시킨다.

## 13.3 영구기관 모드의 상태기계

### 13.3.1 상태
- `BOOT` → `MEMORY_LOAD` → `BACKLOG_REFRESH` → `DISPATCH` → `RUN_CHUNK` → `EVALUATE` → `MEMORY_COMMIT` → `BRIEF_IF_NEEDED` → `BACKLOG_REFRESH` (반복)

### 13.3.2 IDLE 금지 규칙
- Backlog가 비면 반드시 아래 중 하나를 수행한다.
  1) **Exploit**: 최근 교훈(Lesson) 기반 “빠른 승률” 실험 생성  
  2) **Explore**: 신규 논문/아이디어 리서치 태스크 생성(인터넷 허용 범위 내)  
  3) **Stabilize**: 기존 PASS/상위 Score 전략의 리스크/구현성 개선 실험 생성  
  4) **Repair**: 인프라/지표/레지스트리 회귀 테스트 생성
- 위 1~4 중 무엇을 선택했는지는 메모리에 기록한다.

---

## 13.4 Backlog 생성 규칙

### 13.4.1 Backlog 아이템의 최소 필드
- `chunk_id`
- `objective` (왜 하는가)
- `hypothesis` (예상되는 메커니즘)
- `expected_gain_axis` (Ret/Risk/Rob/Impl/Div 중 어디를 개선하는가)
- `cost_estimate` (대략적 실행 비용: low/med/high)
- `preconditions` (필요 데이터/기능)
- `stop_rule` (실패 시 즉시 중단 조건)
- `task_family`
- `novelty_score`

### 13.4.2 Value of Experiment (VoE) 규칙 — v1.4.2 핵심
Backlog 우선순위는 아래 5요소를 반영한 `priority_score`로 정한다.
- **Expected Gain**: 목표 지표 개선 가능성
- **Expected Learning**: 실패하더라도 교훈 가치가 큰가
- **Novelty**: 기존 실험과 중복이 적은가
- **Execution Cost**: 시간/연산/데이터 요구량
- **Dependency Risk**: 인프라/데이터 선결조건 리스크

권장 개념식:
\[
VoE = Gain + Learning + Novelty - Cost - DependencyRisk
\]

ResearchOps는 VoE를 정규화하여 `priority_score`로 사용한다.

---



## 13.4A 다양성 보존 규칙
- 승격된 전략 간 상관이 높아지는 mode collapse를 방지하기 위해 아래를 적용한다.
  - 활성 Research Chunk의 40% 이상이 동일 factor family이면 안 된다.
  - Candidate/Production 위험예산의 35% 이상이 동일 corr-cluster에 집중되면 안 된다.
  - 동일 family에서 3회 이상 연속 PASS가 발생하면, 다음 사이클에는 반드시 Counterfactual 청크 1개를 생성한다.

## 13.5 스레드(병렬) 운용 규칙

### SE-THREAD-01. WIP 상한
- 기본값: `max_wip = 3`
- heavy backtest / heavy ensemble은 `max_wip = 1`
- Production 창에서는 Research WIP를 축소 가능

### SE-THREAD-02. 신규 연구 주제의 즉시 착수는 “큐 등록”으로 해결
- 실행 중 새로운 가설이 떠오르면:
  - 현재 청크를 중단하지 말고,
  - child chunk를 Backlog에 등록하고,
  - 우선순위에 따라 다음 DISPATCH에서 실행한다.

### SE-THREAD-03. Family cooldown
- 같은 task_family가 3회 연속 Hard Fail이면,
  - 해당 family를 `COOL-DOWN` 상태로 두고
  - 다른 family로 자원을 이동한다.

---

## 13.6 Circuit Breaker (안전 회로)

### SE-CB-01. 반복 실패 감지
- 같은 실패 사유로 3회 연속 실패 시, 해당 패밀리는 자동 `COOL-DOWN`

### SE-CB-02. 자원 한도
- 일일 실행 청크 수 상한: `N_day_max`
- 디스크 사용량 상한: `Disk_max`
- 단일 청크 실행 시간 상한: `T_chunk_max`
- 오류 누적 상한: `E_max`

### SE-CB-03. 신뢰도 추락 감지
- PIT 위반, 미래정보 사용, 데이터 누락/불일치가 감지되면:
  - 즉시 RUN 중단
  - “데이터 사고”로 분류
  - 리서처에게 텔레그램 경보 전송

### SE-CB-04. Graceful Degradation
- 고급 기법(RP/HRP/Opt, multi-factor timing 등)이 불안정하면,
  - 더 단순한 baseline(1/N, IVol, static weight)으로 자동 폴백한다.
- “멈추지 않는 것”보다 “의미 있게 계속되는 것”이 우선이다.

---

## 13.7 텔레그램 브리핑 지침 (이벤트 기반)

### 13.7.1 브리핑 트리거
- 신규 PASS 또는 Grade 상승(A/B/C 변화)
- 목표 달성: Net CAGR ≥ 16% AND 핵심 Risk Gate 통과
- 새로운 교훈(Lesson) 등록
- 데이터 QC 실패 / PIT 위반 의심 / 실행 인프라 장애
- 앙상블/블렌딩에서 조합 폭발 방지 규칙 위반 탐지
- 월간 리밸런싱 산출물 생성 완료

### 13.7.2 v1.4.2 정량 트리거 (즉시 브리핑 권장)
- Sharpe0_ann +0.10 이상 개선
- ES99 (절대손실) 0.30%p 이상 개선
- MDD 2.0%p 이상 개선
- Turnover 100%p/yr 이상 개선
- Fama–MacBeth slope 유의성 또는 factor-model alpha 검증이 새로 통과

### 13.7.3 브리핑 빈도 제한
- 동일 유형 30분 간격
- 일일 즉시 브리핑 최대 12건
- 초과분은 Digest로 묶음

---

## 13.8 Prompt Cards (운영용)

### 카드 1: Orchestrator (Perpetual Mode)
- 기본 상태는 `LOOP=ON`, `MODE=RESEARCH`
- 단, Production window에서는 `MODE=PRODUCTION` 우선
- 청크 종료 시 반드시: 결과 저장 → 허들 평가 → Memory 업데이트 → 브리핑 트리거 체크

### 카드 2: Stop-or-Shift Judge
- 최근 N회 실험에서 개선이 구조적인지, 파라미터 피팅인지 판단하라.
- Stop Rule / Cool-down Rule 발동 여부를 명시하라.

### 카드 3: Budgeter
- 하루 예산 안에서 VoE가 가장 높은 실험부터 실행하라.
- Full Run은 Preflight를 통과한 경우에만 허용하라.

## v1.4 Addendum — Catalyst / Alpha Lab / Research Queue 연동
- Perpetual Mode에서 Backlog가 비면 우선순위는 다음과 같다:
  1) Stabilize (기존 A/B 전략의 risk/cost 개선)
  2) Explore (Catalyst에서 Compiler를 통과한 신규 family)
  3) Diagnose (데이터/지표/중복/인프라 문제)
- Catalyst 아이디어는 직접 실행 금지. 반드시 Idea Compiler를 거쳐 `EXPERIMENT_TICKET`으로 전환된 뒤 Queue에 들어간다.
- Stage 0 Alpha Lab PASS는 “정식 검증 가치가 있다”는 뜻일 뿐, Grade 승격이 아니다.


## 13.10 v1.4.2 Addendum — Research Memory Priority

### SE-09. 장기기억의 기본 단위는 “대화”가 아니라 “연구 결과”다
- 자가발전 엔진이 장기기억화해야 하는 핵심 대상은 아래와 같다.
  1) 실험 결과(Experiment Digest)
  2) 패밀리/메커니즘 수준 교훈
  3) 통계적 증거(FF3/Carhart4/FF5/Fama–MacBeth 등)
  4) 국면별 기대보수와 역할(core/defensive/diversifier)
  5) 포트폴리오 정책(조합/오버레이/리밸 규칙)
- 사용자와의 대화 전체는 장기기억화하지 않는다.
- 대화에서 명시적으로 승인된 제약/운용 원칙/열린 질문만 제한적으로 보존한다.

### SE-10. MEMORY_COMMIT은 25장 파이프라인을 따른다
- Research Chunk 종료 후 MEMORY_COMMIT 단계에서 반드시:
  - Stage R0 raw artifact 저장
  - Stage R1 experiment digest 생성
  - 필요시 Stage R2/R3/R4/R5 승격 여부 평가
- 승격되지 않은 정보는 장기기억에 강제 저장하지 않는다.

### SE-11. Retrieval 목적은 “의사결정 보조”다
- 기억은 법전/원시 산출물을 대체하지 않는다.
- 월간 리밸런싱/전략 설계 시 Retrieval은
  Schema → Statistical Evidence → Regime Payoff → Portfolio Policy → Recent Experiment Digests → Working Memory
  순으로 수행한다.

### SE-12. Memory-driven backlog 생성
- Backlog가 비었을 때, 새 아이디어 생성 전 아래를 먼저 확인한다.
  1) 최근 Family/Mechanism 실패 패턴
  2) 미충족 Regime Payoff 공백
  3) Portfolio Policy의 취약점(예: role imbalance, high ES99)
- 즉, 새로운 청크는 “기억의 공백”을 메우는 방향으로 우선 생성한다.


---

## FILE: `14_ExperimentProtocol.md`

# 14 Experiment Protocol (v1.4.2)

## 14.0 목적
본 장은 “전략/팩터/앙상블” 연구를 **실험 계약서(Experiment Contract)** 형태로 표준화하여,
- 재현성,
- 과최적화 방지,
- 실험 간 비교 가능성,
- 장기기억 누적 가능성,
- 통계적 타당성
을 확보한다.

---

## 14.1 실험 계약서(Contract) 1-8

> 각 Research Chunk는 아래 1~8 항목을 **모두** 채워야 실행 가능하다.

### 1) Experiment ID & Scope
- `exp_id`: 예) `EXP_YYYY-MM-DD_###`
- `parent_exp_id`: 파생 실험이면 부모 ID 명시
- `task_family`: 동일 아이디어 계열 묶음
- `target`: Strategy / Factor / Ensemble / Valuation overlay / Weighting method / Infra
- `universe`: (예) KOSPI200 / KOSDAQ150 / All listed)
- `frequency`: monthly / quarterly
- `benchmark`: (예) KOSPI200 TR
- `transaction_cost_model`: (모형명 + 파라미터)

### 2) Hypothesis (가설)
- 한 문장 가설: “X를 하면 Y가 개선된다”
- 메커니즘: 왜 그런가(팩터 프리미엄/리스크 프리미엄/행동 편향 등)
- 반증 조건: 어떤 결과가 나오면 가설이 틀린 것으로 볼 것인가
- 최소 1개의 **Null/Placebo** 설계를 같이 명시

### 3) Data & PIT 봉인
- `data_snapshot_id`: 실험에 사용한 데이터 스냅샷/버전
- PIT(시점일치) 체크리스트
- 생존편향/상장폐지 처리 여부
- 데이터 QC 결과(결측/이상치/단위)

### 4) Implementation Spec (구현 스펙)
- `strategy_id` / `variant_id`
- 파라미터 목록(고정/탐색 범위 구분)
- 포지션 구성 규칙(롱온리/롱숏, n_holdings, 섹터중립 등)
- 리밸런싱 규칙 + 버퍼존/쿨다운 등 거래 규칙
- 제약조건: (예) TO<600%, 단일종목 max weight, 유동성 필터 등
- `strategy_fingerprint`: 핵심 정의 해시

### 5) Execution Plan (Preflight → Full Run)
#### 5-1. Preflight
- 짧은 검증용 런
- 데이터/지표/TO/비용 결합 오류 확인
#### 5-2. Full Run
- 워크포워드/IS/OOS/스트레스 구간 포함
- Preflight PASS 후에만 수행


### 6) Evaluation Metrics (평가 지표)
아래는 v1.4.2의 **필수 KPI 세트**다.

#### 6-1. 기본 성과/위험 KPI (Primary)
- **Net CAGR**
- **Sharpe0_m_ann**  (월간 수익률 기반 연환산 Sharpe, Rf=0%)
- **MDD (Max Drawdown)**
- **ES99_m**  (= 월간 수익률 기준 Expected Shortfall 99%, 양의 손실 크기 표기)
- **Turnover_ann**  (실제 홀딩 기반 연환산 TO)

#### 6-2. 보조 KPI (Secondary / Diagnostics)
- **Sharpe0_d_ann** (일간 기반 연환산 Sharpe)
- **ES99_d** (일간 Expected Shortfall 99%)
- **Hit Rate / IC / ICIR**
- **OOS retention**
- **Stress window relative performance**

#### 6-3. 구현/거래 지표
- 거래비용 민감도(0 / 기준 / 2배 비용)
- avg_sells_per_rebal / avg_buys_per_rebal
- capacity / liquidity flags



## 14.2 Sharpe0 정의 (기본 = 월간 연환산)
수익률 시계열을 \(r_t\)라 하고, 무위험수익률은 \(r_f=0\)으로 고정한다.

### 14.2.1 월간 Sharpe0 (Primary)
월간 수익률 \(r_m\)에 대해,
\[
\bar r_m = \frac{1}{T}\sum_{t=1}^{T} r_{m,t}, \qquad
\sigma_m = \sqrt{\frac{1}{T-1}\sum_{t=1}^{T}(r_{m,t}-\bar r_m)^2}
\]
\[
Sharpe0_{m,ann} = \sqrt{12}\times\frac{\bar r_m}{\sigma_m}
\]

### 14.2.2 일간 Sharpe0 (Diagnostics)
일간 수익률 \(r_d\)에 대해,
\[
Sharpe0_{d,ann} = \sqrt{252}\times\frac{\bar r_d}{\sigma_d}
\]

## 14.3 ES99 정의 (기본 = 월간 Expected Shortfall)
본 법전은 CVaR 부호 혼동을 피하기 위해, **양의 손실 크기 표기**인 `ES99`를 기본으로 사용한다.

### 14.3.1 월간 ES99 (Primary)
월간 수익률 \(r_m\)의 1% 하위 분위수를 \(q_{0.01}\)라 하면,
\[
ES99_m = -E[r_m \mid r_m \le q_{0.01}]
\]
- `ES99_m`는 항상 **양수**이며, 작을수록 좋다.

### 14.3.2 일간 ES99 (Diagnostics)
일간 수익률 \(r_d\)에 대해,
\[
ES99_d = -E[r_d \mid r_d \le q_{0.01}]
\]

## 14.4 통계 방어 발동 규칙 (v1.4.2)
- Alpha Lab 단계: 통계 방어 생략 가능
- 동일 family trial_count >= 5 또는 `RESEARCH_PASS` 후보:
  - DSR 또는 FDR 계열 최소 1개 필수
- Grade A 후보:
  - DSR + placebo/bootstrap 최소 1개 필수
- Production 후보:
  - family trial accounting + FDR/SPA/Reality Check 계열 최소 1개 필수

## 14.5 운영 주의사항 (v1.4.2)
- 높은 Sharpe0만으로 PASS를 주장하지 않는다.
  → 최소한 하나의 factor-model alpha validation 또는 Fama–MacBeth 결과를 붙인다.
- 동일 family에서 실험을 많이 했으면, 그만큼 통계 해석을 보수적으로 한다.
- 실험은 비교 실험이다. 따라서 **metric version**, **cost model version**, **factor model version**을 고정·기록해야 한다.

## 14.6 v1.4 Addendum — Stage 0 Alpha Lab 연결
### A) Stage 0 결과를 Stage 1로 넘길 때 필수 메타데이터
- alpha_lab_status
- alpha_lab_metrics:
  - is_sharpe0
  - fitness_like
  - turnover
  - self_corr
  - sub_universe_metric
- heuristic_notes
- family_trial_count

### B) Statistical Defense 연결 규칙
- 동일 family에서 trial count가 일정 수준을 넘으면, Stage 1 PASS 전략이라도
  - DSR
  - FDR
  - RC/SPA
중 최소 1개를 추가 요구한다.

### C) local factor models 주의
FF3/Carhart4/FF5 검증은 강력하지만, 한국시장 로컬 구현 시 factor construction 품질에 민감하다.
따라서 반드시:
- factor source
- rebalance rule
- weighting
- benchmark alignment
를 계약서에 명시해야 한다.


## 14.5A Memory Distillation Outputs (v1.4.2)
실험 종료 시 아래 memory-ready 출력도 함께 생성하는 것을 권장한다.
- `experiment_digest.json`
- `family_signal_tags.json`
- `stat_evidence_summary.json`
- `regime_payoff_stub.json` (해당 시)
- `portfolio_policy_stub.json` (해당 시)

이 출력들은 25장 Memory Distillation Pipeline의 입력으로 사용된다.


---

## FILE: `15_MemorySpec.md`

# 15 Memory Specification (v1.4.2)

## 15.0 목적
본 장은 멀티 에이전트의 장기기억이
- “쌓이긴 하는데 쓸 수 없는 로그 더미”가 되지 않도록,
- **검색 가능하고, 증거 기반이며, 실험 설계를 실제로 개선**하는 형태로 축적되도록  
장기기억의 구조·스키마·갱신 규칙을 정의한다.

---

## 15.1 메모리 레이어 설계

### 15.1.1 Layer A: Raw Artifacts (불변)
- 백테스트 결과 파일(수익률 시계열, 포트폴리오 웨이트)
- 로그, 설정(config), 데이터 스냅샷 ID
- 원칙: **생성 후 수정 금지** (immutable)

### 15.1.2 Layer B: Experiment Registry (구조화)
- 각 실험(Research Chunk) 단위의 메타데이터를 JSON/CSV로 기록
- 원칙: “나중에 자동으로 집계/검색/리포팅 가능”해야 함

### 15.1.3 Layer C: Lessons (정제된 규칙)
- 반복적으로 유효했던 인사이트를 `L-###` 형태로 축적
- 원칙: **조건부 지식**(언제/왜/어디까지 통하는지)을 포함해야 함

### 15.1.4 Layer D: Executive Summary (압축본)
- MEMORY.md 같은 “200줄 내외” 요약 파일
- 원칙: 상세는 B/C를 참조하고, D는 “현재 어디까지 왔는지”만 요약

---

## 15.2 증거 기반 기록 규칙 (Anti-Hallucination)

### MS-01. 산출물 없는 기록 금지
- 아래 중 하나라도 없으면 기록 불가:
  - 결과 요약 테이블(핵심 KPI)
  - 로그 파일(실행 흔적)
  - 데이터 스냅샷 ID
  - 코드 버전(커밋/해시/파일 경로)

### MS-02. 숫자는 “출처 경로”를 동반한다
- CAGR, Sharpe0, ES99, MDD 등 수치는
  - `artifact_path` 또는 `result_file` 경로와 함께 기록한다.

### MS-03. Lesson은 반드시 4요소를 포함한다
- 조건(Condition)
- 관측(Observation)
- 증거(Evidence)
- 행동(Action)

---



## 15.2A 메모리 품질 관리
### MS-04. 모순 해결 프로토콜
- 서로 충돌하는 Lesson/규칙이 발견되면, 둘 다 유지하되 `conflict_group`를 부여한다.
- 충돌은 새 실험으로 해결하기 전까지 임의로 삭제하지 않는다.

### MS-05. 브리핑 중복 방지 로그
- `telegram_sent.json`에는 `msg_hash`를 저장한다.
- 같은 `msg_hash`는 24시간 내 중복 발송 금지.

## 15.3 Experiment Registry 스키마 (권장 JSON)

```json
{
  "exp_id": "EXP_2026-03-04_001",
  "parent_exp_id": null,
  "chunk_id": "CHUNK_000123",
  "task_family": "idioVol_monthly_bufferzone",
  "timestamp": "2026-03-04T23:10:00+09:00",
  "target": "Strategy",
  "strategy_id": "STR_283",
  "variant": "v1.0",
  "strategy_fingerprint": "hash(...)",
  "data_snapshot_id": "DS_2026-02-29_PIT",
  "metric_version": "metrics_v1.4.2",
  "universe": "KR_ALL_LISTED",
  "frequency": "quarterly",
  "benchmark": "KOSPI200_TR",
  "metrics": {
    "net_cagr": 0.119,
    "sharpe0_ann": 0.64,
    "mdd": 0.502,
    "cvar99_m": -0.124,
    "turnover_ann": 1.03,
    "icir": 0.43,
    "oos_retention": 0.72
  },
  "alpha_validation": {
    "ff3_alpha": 0.0012,
    "ff3_t": 1.9,
    "carhart4_alpha": 0.0008,
    "carhart4_t": 1.4,
    "ff5_alpha": 0.0010,
    "ff5_t": 1.7
  },
  "fm_validation": {
    "slope": 0.0021,
    "t_stat": 2.3,
    "sign_consistency": 0.71
  },
  "multiple_testing": {
    "family_trial_count": 7,
    "dsr": 0.34
  },
  "grade": "C",
  "role": "diversifier",
  "lifecycle": "CANDIDATE",
  "dup_group_id": null,
  "verdict": "FAIL",
  "fail_reasons": ["MDD > 45%"],
  "artifacts": {
    "hurdle_result": "path/to/hurdle_result.json",
    "equity_curve": "path/to/equity_curve.csv",
    "weights": "path/to/weights.parquet",
    "logs": "path/to/run.log"
  },
  "next_actions": ["Spawn CHUNK_000124: reduce drawdown via risk overlay"]
}
```

---

## 15.4 Lessons 템플릿 (L-###)

```markdown
### L-018: EW 앙상블에서 corr > 0.8 구성요소는 제거해야 한다
- Condition: 동일 리밸런싱 주기 + 유사 팩터 노출 + corr(α) > 0.8
- Observation: EW 조합 시 MDD 개선이 없고 성과가 희석된다
- Evidence: STR_270에서 STR_264 & STR_265 corr=0.908, 앙상블 FAIL
- Action: corr 필터 → 클러스터별 1개 대표만 유지 + leave-one-out 필수
- Confidence: Medium
- Expiry/Revalidation: 6개월 또는 신규 PASS 전략 10개 추가 시 재검토
- Tags: [ensemble, correlation, redundancy]
- Links: EXP_2026-xx-xx_###
```

---

## 15.5 Contradiction Resolution (v1.4.2 추가)

서로 충돌하는 Lesson이 생기면 아래를 따른다.
1. 동일 범위(시장/유니버스/리밸 주기)인지 확인
2. 표본 수/최근성/재현성 근거를 비교
3. 상위 신뢰도 Lesson만 활성 상태로 두고, 나머지는 `conditional` 또는 `superseded` 태그 부여

Lesson도 시간이 지나면 낡을 수 있으므로 `expiry/revalidation` 필드를 둔다.

---

## 15.6 Duplicate / Alias 정책

- fingerprint가 동일하면 새로운 전략으로 등록하지 않는다.
- 거의 동일한 전략(노출/경로 유사)인 경우:
  - `dup_group_id`를 부여
  - 가장 대표 전략만 canonical로 유지
  - 나머지는 `alias_of`로 연결

이 규칙은 “Grade A 개수 부풀리기”를 방지한다.

---

## 15.7 갱신 주기 & 트리거

### MS-UPDATE-01. 청크 종료 시 자동 갱신
Research Chunk 종료 시 반드시 아래를 수행:
1) Registry 레코드 1건 추가  
2) 필요 시 Lesson 0~1건 추가(남발 금지)  
3) MEMORY.md(요약본) 갱신 여부 판단  
4) 브리핑 트리거 체크(13장)

### MS-UPDATE-02. “10개 Lesson 누적” 요약
- Lesson이 10개 누적될 때마다:
  - “누적 교훈 요약본”을 생성
  - 텔레그램으로 발송(13장 규칙)

### MS-UPDATE-03. Lifecycle update
- Grade와 별개로 lifecycle 상태를 갱신한다.
- 예: PASS 전략이더라도 Paper 단계에서 성과 붕괴 시 Watchlist 이동

---

## 15.8 검색/재사용(Retrieval) 규칙

새 실험을 설계하기 전, 에이전트는 반드시:
- 관련 키워드로 methodology_memory.md를 검색하고
- “적용 가능한 Lesson 3개”를 인용한 뒤
- 이번 실험이 그 Lesson을 어떻게 반영하는지 1문장으로 명시한다.

---

## 15.9 메모리 품질 KPI
- MQ-01: 중복 Lesson 비율(동일 내용 반복)
- MQ-02: 모순 미해결 건수(서로 충돌하는 규칙)
- MQ-03: 검색 성공률(실험 설계 시 실제로 Lesson이 반영되었는가)
- MQ-04: 회귀테스트 커버리지(인프라 버그 재발 방지)
- MQ-05: duplicate 전략 비율

## v1.4 Addendum — Reference Bundle / Idea Backlog
- `idea_backlog.md`는 필수 파일이다.
- Catalyst/IdeaResearcher가 생성한 아이디어는 반드시:
  - reference bundle
  - domain/function tags
  - compiler status
를 함께 기록한다.
- 실험으로 승격되지 않은 아이디어도 백로그로 보존하되, duplicate/obsolete 상태를 관리한다.


## v1.4.2 Addendum — Research Result Memory Priority

### 15.10 Conversation vs Research Memory
- Lawbook의 장기기억은 기본적으로 **Research Memory 우선**이다.
- Conversation Memory는 아래에 한해 제한적으로 저장한다.
  - 사용자가 명시적으로 승인한 제약/운용 원칙
  - 미해결 질문(open questions)
  - 다음 행동에 직접 영향을 주는 결정
- 일반 대화의 원문/감정/설명 과정은 장기기억화 대상이 아니다.

### 15.11 Research Memory 승격 단위
연구 결과 기억은 아래 순서로 승격한다.
1. Raw Artifacts
2. Experiment Digest
3. Family / Mechanism Memory
4. Statistical Evidence Store
5. Regime Payoff Tensor
6. Portfolio Policy Memory
7. Post-Trade Learning Memory

각 단계의 승격 조건과 스키마는 25장을 따른다.

### 15.12 Memory Domain 재정의
Memory Domain은 최소 아래 3개를 사용한다.
- `conversation_contract`
- `research_result`
- `governance_rule`

기본 retrieval은 `research_result`를 우선한다.

### 15.13 증거 기반 승격 규칙
- FACT/SCHEMA로 승격되기 전 반드시 source artifact path, exp_id, metric snapshot을 갖춰야 한다.
- source artifact가 없으면 memory draft까지만 허용하고 승격 금지.


---

## FILE: `16_ResearchOps_and_Optimization.md`

# 16 ResearchOps and Optimization (v1.4.2)

## 16.0 목적
본 장은 자가발전 연구엔진이 “멈추지 않는 것”을 넘어, **무엇을 먼저 실험해야 가장 빨리 배우는지**를 결정하는 ResearchOps 규칙을 정의한다.

---

## 16.1 왜 ResearchOps가 필요한가

영구기관(Perpetual Mode)만으로는 연구가 최적화되지 않는다.
다음 문제가 쉽게 발생한다.
- 계산비용이 큰 실험을 먼저 돌려 처리량이 떨어짐
- 비슷한 전략을 반복 실험함
- 통계적으로 이미 많이 시도한 family를 또 탐색함
- 인프라 문제와 전략 문제를 섞어 실행함

ResearchOps는 이를 막기 위해 **Backlog 경제학**을 운영한다.

---

## 16.2 Backlog Priority Score

각 후보 청크는 아래 6개 요소로 우선순위를 계산한다.

1. **Expected Gain**
   - A/B/C 승격 가능성, Sharpe0 개선, MDD/CVaR 감소 가능성
2. **Expected Learning**
   - 실패해도 교훈이 남는가
3. **Novelty**
   - 기존 PASS/최근 실험과 얼마나 다른가
4. **Execution Cost**
   - 시간/메모리/데이터 요구량
5. **Dependency Risk**
   - 필요한 인프라/데이터가 아직 불안정한가
6. **Family Penalty**
   - 같은 family의 trial count가 높을수록 감점

권장 개념식:
\[
Priority = 0.30 Gain + 0.25 Learning + 0.20 Novelty - 0.15 Cost - 0.10 DependencyRisk - FamilyPenalty
\]

정확한 계수는 운영자가 조정 가능하되, **Family Penalty**를 반드시 포함한다.

---



## 16.2A Priority Score 정규화 규칙
각 요소는 기본적으로 0~5 정수 점수로 평가한다.
- Gain: Grade 상승/핵심 KPI 개선 기대
- Learning: 실패해도 새로운 Lesson을 만들 가능성
- Novelty: 최근 20개 실험/현재 PASS 풀과의 차별성
- Cost: 예상 실행시간/메모리/복잡도
- Dependency Risk: 데이터/인프라 의존성 위험
- Family Penalty: 최근 30일 동일 family trial_count 기반 감점

권장 계산 예:
\[
Priority = 0.30 Gain + 0.25 Learning + 0.20 Novelty - 0.15 Cost - 0.10 DependencyRisk - FamilyPenalty
\]

> Priority는 절대값보다 **상대 순위**에 사용한다.

## 16.3 청크 타입 분류

- `EXPLOIT`: 상위 전략 개선(빠른 성과 목적)
- `EXPLORE`: 신규 알파/신규 구조 탐색
- `REPAIR`: Near-miss 수정 / 리스크·TO 개선
- `INFRA`: 지표/하네스/레지스트리/QC 개선
- `VERIFY`: 재현성/통계 검증/회귀테스트

기본 권장 비중(목표 달성 전):
- EXPLOIT 40%
- REPAIR 30%
- EXPLORE 20%
- INFRA+VERIFY 10%

목표 달성 후에는 EXPLORE 비중을 점진적으로 늘릴 수 있다.

---

## 16.4 Preflight-first 원칙

모든 청크는 가급적 아래 순서로 실행한다.
1. 설계서 검토
2. 데이터/PIT 체크
3. Preflight run
4. Full run
5. Statistical validation

Full run은 scarce resource다. Preflight에서 걸러질 수 있으면 그게 이득이다.

---

## 16.5 연구 패밀리(Family) 관리

### 16.5.1 family_trial_count
- 동일 family(예: `idioVol_monthly_bufferzone`)의 시도 횟수 누적
- multiple-testing accounting의 기본 단위

### 16.5.2 family_cooldown
- 같은 family가 연속 3회 Hard Fail이면 cooldown
- cooldown 중에는 다른 family 실험을 우선

### 16.5.3 family_success_rate
- PASS율이 낮은 family는 탐색 빈도를 줄이고, 이론/데이터 재검토 선행

---

## 16.6 생산성 KPI

- RO-01: 청크당 평균 실행 시간
- RO-02: 100개 실험당 A/B/C 전략 수
- RO-03: 유효 교훈(Lesson) 1개당 소요 compute
- RO-04: duplicate 실험 비율
- RO-05: invalidated 실험 비율 (PIT/지표/레지스트리 문제)

---

## 16.7 프롬프트 카드

### 카드 RO-01: ResearchOps Scheduler
- 최근 50개 실험의 결과를 보고, 다음 실행할 청크 3개를 고르라.
- Priority Score를 표로 보여주고, 왜 이 순서인지 설명하라.
- 같은 family를 연속 2개 이상 올리지 마라(특별 사유 없으면).

### 카드 RO-02: Cost-of-Learning Judge
- 후보 실험의 기대 성능 개선뿐 아니라 “실패했을 때 배우는 가치”를 정량 점수로 산정하라.
- 계산비용이 큰데 배우는 게 적으면 후순위로 미뤄라.

## 16.8 v1.4 Addendum — Explore / Exploit / Stabilize / Diagnose

ResearchOps는 backlog를 최소 4개 버킷으로 관리한다.
- **Exploit**: 기존 A/B 전략 개선
- **Explore**: 신규 family/신규 알파 원천
- **Stabilize**: PASS 전략의 TO/리스크/구현성 개선
- **Diagnose**: 인프라/지표/중복/기간정합 문제 해결

권장 기본 비중(목표 달성 전):
- Exploit 35%
- Stabilize 30%
- Explore 20%
- Diagnose 15%

### 16.9 Family Penalty 강화
동일 family에서 반복 시도 시 아래를 감점한다.
- trial_count
- recent_fail_streak
- redundancy vs registry
- lack of novelty vs prior lessons

### 16.10 Alpha Lab 우선순위
Alpha Lab 통과 후보는 정식 검증 우선순위를 부여받지만, Production 승격 가중치는 아니다.


## 16.3A 탐색 예산 분할
기본 연구 예산은 아래 비율을 권장한다.
- EXPLOIT 50%
- ORTHOGONAL_SEARCH 30%
- COUNTERFACTUAL 20%

동일 family 또는 동일 corr-cluster가 전체 활성 청크의 40%를 넘으면 자동 감점 또는 dispatch 금지한다.


## 16.11 v1.4.2 Addendum — Memory-driven Queue Economics

ResearchOps는 우선순위를 계산할 때 25장의 승격 기억을 활용한다.
- `Family/Mechanism Memory`가 강한 실패 패턴을 가진 family는 Family Penalty 강화
- `Statistical Evidence Store`에서 weak alpha로 반복 판정된 구조는 우선순위 감점
- `Regime Payoff` 공백(특정 regime에 적합한 sleeve 부족)은 우선순위 가산
- `Portfolio Policy Memory`에서 확인된 role imbalance(core/defensive/diversifier 부족)는 우선순위 가산

즉, Backlog는 최근 실험 로그가 아니라 “승격된 연구 기억의 공백”을 메우는 방향으로 최적화한다.


---

## FILE: `17_Strategy_Lifecycle_and_Duplicate_Control.md`

# 17 Strategy Lifecycle and Duplicate Control

## 17.0 목적
본 장은 전략이 “발견 → 검증 → 관찰 → 퇴역”되는 생애주기와, 동일 전략을 다른 이름으로 반복 생성하는 문제를 통제한다.

---

## 17.1 Lifecycle 상태 정의

1. `IDEA`
- 아이디어 카드만 존재, 아직 실험 계약서 없음

2. `SANDBOX`
- 첫 실험/간이 백테스트 단계
- 법전 위반 여부와 기본 작동만 확인

3. `CANDIDATE`
- 허들상 A/B/C 가능성이 있어 추가 검증 가치 있음
- 정식 Full Run과 통계검증 대상

4. `PAPER`
- 생산 후보이나 아직 실거래/월간 주문서 반영 전
- shadow allocation 또는 paper portfolio로 관찰

5. `PRODUCTION`
- 월간 리밸런싱 후보로 실제 사용 가능

6. `WATCHLIST`
- 구조/성능/노출 드리프트 의심
- 사용 중단 또는 비중 축소 검토

7. `RETIRED`
- 장기 부진, 구조 붕괴, 중복/대체, 법전 위반 등으로 퇴역

---

## 17.2 Grade vs Lifecycle

- Grade는 “성능/심사 결과”
- Lifecycle은 “운용 프로세스 상태”

예:
- Grade A + PAPER
- Grade B + PRODUCTION (Component로 포트에 유용)
- Grade A + WATCHLIST (최근 드리프트 경고)

둘을 혼동하지 않는다.

---

## 17.3 승격/강등 규칙 (권장)

### IDEA → SANDBOX
- ExperimentProtocol 초안 완성
- 데이터/PIT/구현 가능성 점검 완료

### SANDBOX → CANDIDATE
- Preflight PASS
- 중복 검사 통과

### CANDIDATE → PAPER
- Full Run + Hurdle + Risk Audit 통과
- Sharpe0/ES99 등 핵심 지표 확인
- 통계검증(필요 시 FF3/Carhart4/FF5, Fama–MacBeth) 수행

### PAPER → PRODUCTION
- 최소 관찰기간/재현성 확보
- 기존 Production과의 상호작용(상관/역할) 검증
- Manager/PM 승인

### ANY → WATCHLIST
- 드로우다운 확대
- ES99 악화
- 역할 중복 심화
- 노출 드리프트 / 시장 구조 변화

### WATCHLIST → RETIRED
- 개선 시도 실패
- 대체 전략 등장
- 동일 fingerprint의 더 나은 버전 존재

---

## 17.4 Strategy Fingerprint

전략 fingerprint는 아래 핵심 정의를 해시한다.
- universe filter
- factor family / signal formula
- rebalance rule
- holdings count / selection rule
- weighting rule
- risk overlay / regime gate
- buffer/cooldown rule
- cost model
- benchmark

이 fingerprint가 동일하면 **새 전략이 아니라 동일 전략의 재실행 또는 파생 실험**이다.

---

## 17.5 유사도 보조 기준

fingerprint가 다르더라도 아래가 매우 유사하면 `duplicate candidate`로 태그한다.
- 팩터 노출 벡터 유사
- 리턴 경로 상관이 과도하게 높음
- holdings overlap이 높음
- drawdown path가 거의 동일

이 경우 ResearchOps가 `dup_group_id`를 부여하고, 대표전략(canonical)만 유지한다.

---

## 17.6 Alias 규칙

- 대표 전략: `canonical_strategy_id`
- 파생/변형: `alias_of`
- 중복 전략은 성과 카운트(예: Grade A 개수)에 중복 반영하지 않는다.

---

## 17.7 퇴역(Retirement) 원칙

전략은 아래 중 하나면 퇴역 검토한다.
- 장기 OOS 악화
- 조건부로만 작동하고 그 조건이 사라짐
- 더 단순하고 더 나은 버전이 등장
- 심각한 PIT/데이터/레지스트리 문제로 신뢰 상실

퇴역은 “삭제”가 아니라 상태 전환이다. 기록은 남긴다.

## 17.8 v1.4 Addendum — Lifecycle 확장
Lifecycle에 Stage 0/1을 명시적으로 반영한다.

`IDEA → ALPHA_LAB → RESEARCH_PASS → CANDIDATE → PAPER → PRODUCTION → WATCHLIST → RETIRED`

- IDEA: 아이디어 카드만 존재
- ALPHA_LAB: cheap reject/fast filter 통과
- RESEARCH_PASS: 정식 검증(허들/리스크/통계) 통과
- 이후는 v1.4.1 규칙 유지

### 17.9 Duplicate Control 강화
- fingerprint 외에도 `label_signature`를 사용한다.
- label_signature = economic_family + construction_family + neutrality + horizon + capacity_bucket
- fingerprint가 달라도 label_signature와 exposure overlap이 과도하면 duplicate candidate로 분류


---

## FILE: `18_AlphaLab_Stage.md`

# 18 Alpha Lab Stage

## 18.0 목적
Stage 0 Alpha Lab은 아이디어를 빠르게 위생검사하여, 계산비용이 큰 정식 검증(Stage 1)에 태울 가치가 있는지 판정하는 전처리 층이다.

## 18.1 철학
- 이 단계는 **WorldQuant BRAIN의 내부 승격 규칙을 복제하는 것이 아니다.**
- 공식 공개 자료에서 확인되는 철학은:
  - quality와 quantity를 함께 본다
  - scoring은 stage마다 달라질 수 있다
  - OOS/hidden period가 중요하다
- 따라서 Alpha Lab은 “WQ-inspired heuristic filter” 로 정의한다.

## 18.2 필수 입력
- 간이 백테스트 결과
- turnover
- self-correlation proxy
- sub-universe robustness proxy
- IS / OOS visibility 구간

## 18.3 권장 fast metrics
- IS Sharpe0
- Fitness-like metric
- Turnover band
- Self-correlation
- Sub-universe metric
- Weight concentration flags

## 18.4 권장 판정 규칙
- PASS:
  - 높은 Sharpe 또는 괜찮은 Fitness-like
  - 비현실적 TO/집중도 없음
  - 중복/자기상관 과다 아님
- FAIL:
  - TO 폭발
  - 중복/자기상관 과다
  - 유니버스 좁혀지면 즉시 붕괴
  - PIT 의심



## 18.4A 승격 제한(중요)
- Alpha Lab PASS는 오직 “정식 검증 가치가 있음”만 의미한다.
- Lifecycle 전환은 `IDEA -> ALPHA_LAB`까지만 가능하다.
- Grade(A/B/C/F), Candidate, Paper, Production 판정에는 직접 사용 금지.

## 18.5 절대 금지
- Alpha Lab PASS를 Production 품질로 해석하지 말 것
- Alpha Lab에서 파라미터 최적화를 길게 하지 말 것
- Stage 0의 cutoff를 hard law로 박지 말 것

## 18.6 산출물
- `alpha_lab_report.md`
- `alpha_lab_metrics.json`
- `alpha_lab_status = PASS/FAIL`


---

## FILE: `19_FactorLabel_Taxonomy.md`

# 19 Factor Label Taxonomy (v1.4.1)

## 19.0 목적
이 장은 팩터/전략을 이름이 아니라 **구조적 좌표계**로 관리하기 위한 라벨링 체계를 정의한다.


## 19.1 Economic Family
전략/팩터는 최소한 아래 두 필드를 가진다.
- `economic_family_primary`
- `economic_family_secondary[]` (선택, 다중 라벨 허용)

대표 family 예시:
- value
- momentum
- quality
- investment
- low-risk
- volatility
- profitability
- event
- seasonality
- microstructure
- regime
- valuation_overlay
- cross-domain

> primary는 지배적 메커니즘, secondary는 보조 메커니즘을 뜻한다.

## 19.2 Construction Family

- raw_ratio
- rank
- zscore
- residualized
- spread
- sleeve
- integrated_score
- overlay
- optimizer_based

## 19.3 Neutrality
- none
- sector
- beta
- size
- vol
- multi

## 19.4 Horizon
- short
- medium
- long

## 19.5 Capacity Bucket
- low
- medium
- high

## 19.6 Evidence Tier
- A: 학술 + 실증 + 내부 재현
- B: 학술/실증 일부 + 내부 초기가설
- C: 가설 단계

## 19.7 label_signature
각 전략/팩터는 아래를 연결한 `label_signature`를 가진다.
`economic_family_primary | construction_family | neutrality | horizon | capacity_bucket | evidence_tier`

secondary family는 별도 배열 필드로 유지한다.

## 19.8 활용 규칙
- duplicate control의 1차 필터
- blender의 representative sleeve selection 기준
- catalyst 아이디어 분류와 reference bundle tagging 기준


---

## FILE: `20_PortfolioConstruction_and_Overlays.md`

# 20 Portfolio Construction and Overlays

## 20.0 목적
전략의 성패는 신호(signal)뿐 아니라 **포트폴리오 구성(construction)** 에 의해 크게 좌우된다.
본 장은 factor definition과 portfolio construction을 분리하여 관리한다.

## 20.1 Definition vs Construction
- **Definition**: 무엇을 측정하는가
- **Construction**: 그것을 어떤 유니버스/중립화/가중/제약으로 포트폴리오화하는가

같은 정의라도 construction이 다르면 전혀 다른 결과가 나오므로 별도 승인 항목으로 둔다.

## 20.2 baseline → overlay 순서
권장 순서:
1. baseline sleeves 생성
2. 중복/상쇄 노출 정리
3. equal-vol 또는 risk budget scaling
4. baseline portfolio 결정 (1/N 또는 RP)
5. valuation overlay
6. regime overlay
7. implementation overlay(turnover/cost/liquidity)

## 20.3 equal-vol scaling
비교 단계에서는 가급적 각 sleeve를 동일 변동성 스케일로 맞춰서 비교한다.

## 20.4 Portfolio mix vs Integrated construction
- **Portfolio mix**: 단일 스타일 포트폴리오를 기계적으로 혼합
- **Integrated construction**: 스타일 신호들을 하나의 통합 점수/최적화에 반영

## 20.5 Turnover budget / no-trade band / buffer zone
- turnover budget은 사후점검이 아니라 사전 제약이다.
- no-trade band / buffer zone / cooldown은 공식 도구로 인정한다.
- 리밸런싱 빈도는 “성능”이 아니라 “성능-비용-리스크 trade-off”로 본다.

## 20.6 optimizer 사용 규칙
- unconstrained optimizer 금지
- shrinkage covariance, bounds, turnover penalty 필수
- baseline 대비 왜 나은지 설명 불가하면 optimizer 결과 사용 금지

## 20.7 산출물
- `construction_spec.md`
- `sleeve_exposure_report.json`
- `baseline_vs_overlay_comparison.md`



## 20.8 v1.4.2 Addendum — Memory-aware Construction
포트폴리오 구성 시 25장의 아래 기억을 우선 참조한다.
- Statistical Evidence Store: 어떤 sleeve가 팩터 모델로 설명되지 않는 유의미한 alpha를 보이는가
- Regime Payoff Tensor: 현재 regime에서 어떤 family/role이 기대보수가 높은가
- Portfolio Policy Memory: 과거 baseline/overlay 조합 중 무엇이 강건했는가

구성 순서는 다음을 권장한다.
1. baseline sleeves 선택
2. role balance 확인(core/defensive/diversifier)
3. regime-conditioned expected payoff 반영
4. valuation / implementation overlay 적용
5. turnover budget / no-trade band 점검


---

## FILE: `21_PostTrade_ControlTower.md`

# 21 Post-Trade Control Tower (v1.4.2)

## 21.0 목적
전략은 PASS 후에도 계속 검증되어야 한다.
본 장은 Production/Shadow 상태 전략의 사후 통제를 담당한다.

## 21.1 Core Questions
1. 모델이 의도한 노출을 실제로 들고 있는가?
2. 거래비용/슬리피지가 가정과 얼마나 다른가?
3. 용량(capacity)과 crowding이 악화되고 있는가?
4. 드리프트가 나타나면 WATCHLIST 또는 RETIRED로 내려야 하는가?

## 21.2 필수 모니터링
- intended vs realized factor exposures
- realized turnover vs model
- slippage attribution
- capacity usage
- crowding proxy
- benchmark-relative risk
- regime-conditioned drift



## 21.2A Intended Model Versioning
intended vs realized exposure 비교는 반드시 모델 버전을 명시한다.
- `intended_model_id`
- `intended_model_version`
- `realized_model_id`
- `comparison_basis`

모델 정의가 바뀌면 drift 비교는 직접 비교 금지하고, 별도 regime change로 기록한다.

## 21.3 상태 전환
- PRODUCTION → WATCHLIST:
  - 지속적 alpha decay
  - ES99 악화
  - realized exposures drift
  - slippage 폭증
- WATCHLIST → RETIRED:
  - 개선 실패
  - 대체 전략 존재
  - 구조적 환경 변화

## 21.4 브리핑 규칙
다음은 즉시 브리핑:
- intended vs realized 노출 괴리 급증
- slippage 폭증
- crowding 경고
- WATCHLIST 전환

## 21.5 산출물
- `control_tower_daily.json`
- `drift_report_weekly.md`
- `lifecycle_transition_log.json`



## 21.6 v1.4.2 Addendum — Post-Trade Learning Memory
Control Tower는 운영 결과를 25장의 `Post-Trade Learning Memory`로 승격시켜야 한다.
필수 기록:
- intended vs realized exposure drift
- realized turnover vs model
- realized slippage vs assumptions
- crowding proxy changes
- regime misclassification loss
- watchlist / retire trigger events

이 기록은 다음 리밸런싱과 다음 Research Chunk의 입력으로 사용된다.


---

## FILE: `22_StatisticalDefense.md`

# 22 Statistical Defense (v1.4.1)

## 22.0 목적
영구기관/다량 실험 환경에서 “우연히 좋아 보이는 전략”을 막기 위한 통계적 방어선을 정의한다.

## 22.1 왜 필요한가
실험이 많아질수록 false discovery가 증가한다.
따라서 허들/리스크 점검만으로는 부족하고, multiple-testing defense를 별도 층으로 둔다.

## 22.2 필수 회계 단위
- trial_count per family
- experiment_count total
- variants per parent
- oos usage count

## 22.3 권장 도구
### DSR (Deflated Sharpe Ratio)
- selection bias와 non-normality를 반영한 Sharpe 보정

### FDR
- 다중 실험에서 기대 false discovery 비율 통제

### White’s Reality Check / Hansen SPA
- benchmark 또는 후보군 중 superior predictive ability 검정

### Bootstrap / Placebo
- randomization, label shuffle, date shift 등



## 22.3A 발동 조건(Trigger Rules)
- Alpha Lab 단계: 통계 방어 생략 가능
- 동일 family trial_count >= 5 또는 RESEARCH_PASS 후보:
  - DSR 또는 FDR 계열 최소 1개 필수
- Grade A 후보:
  - DSR + placebo/bootstrap 최소 1개 필수
- Production 후보:
  - family trial accounting + FDR/SPA/Reality Check 계열 최소 1개 필수

## 22.4 운영 규칙
- 동일 family에서 trial_count가 높을수록 PASS 승격 기준을 보수화
- Near-pass 전략은 통계방어를 통과하지 못하면 Candidate로만 유지
- Alpha Lab은 cheap filter일 뿐, 통계방어를 대체하지 않는다

## 22.5 산출물
- `stat_defense_report.md`
- `family_trial_accounting.json`
- `dsr_fdr_summary.json`


---

## FILE: `23_Catalyst_and_IdeaCompiler.md`

# 23 Catalyst and Idea Compiler (v1.4.1)

## 23.0 목적
창의성은 유지하되, 아이디어가 “아이디어로만” 남지 않도록
Catalyst → Idea Compiler → Experiment Ticket → ResearchOps Queue 구조를 정의한다.

## 23.1 역할 분리
### Catalyst
- cross-domain 아이디어 생성
- 메커니즘 추출
- quant translation 초안 작성
- 실행 권한 없음

### Idea Compiler
- 아이디어를 ExperimentProtocol 계약서로 변환
- Feature availability / PIT / implementability / novelty 검사
- 통과 시 `EXPERIMENT_TICKET` 발행

## 23.2 Reference Bundle
각 아이디어는 반드시 Reference Bundle을 가진다.
태그 축:
- Domain: FIN / ECON / STAT / ML / PHY / BIO / LIT / CS / ...
- Function: MECH / EMP / METH / IMPL / CAVEAT

최소 1개 이상의 금융/통계 앵커 레퍼런스를 포함해야 한다.

## 23.3 번역 템플릿
- Source idea
- Abstract mechanism
- Observable proxy
- Signal
- Construction implication
- Falsification
- Failure mode



## 23.3A 메인 아키텍처 결합 규칙
- Catalyst의 산출물은 직접 전략/매매안이 아니다.
- 반드시 `IDEA_PROPOSAL -> Idea Compiler -> EXPERIMENT_TICKET -> ResearchOps Queue` 경로를 거친다.
- 동일 theme에서 최근 FAIL lesson이 존재하면, Compiler는 그 lesson을 실험 계약서에 인용하게 강제한다.

## 23.4 아이디어의 법전 편입 규칙
- Catalyst 아이디어는 직접 전략이 되지 않는다.
- Compiler를 통과해야만 Backlog에 등록된다.
- Backlog 우선순위는 ResearchOps가 결정한다.

## 23.5 메시지 타입
- IDEA_PROPOSAL
- EXPERIMENT_TICKET
- MUTATION_REQUEST

## 23.6 창의성 통제
- 실행 제안 상한
- 중복/유사 아이디어 감점
- 대체데이터 금지(허용 범위 외)


---

## FILE: `24_v1_4_Critical_Validation.md`

# 24 Critical Validation of v1.4

## 목적
이 문서는 v1.4 법전 자체를 비판적으로 검토하여, 구조적 약점과 운영 리스크를 드러내기 위한 내부 감사지침이다.

## 1. 강점
- 역할 분리가 명확하다.
- PIT/재현성/허들/메모리 구조가 강하다.
- Stage 0 Alpha Lab → Stage 1 Validation → Construction → Control Tower 구조가 합리적이다.
- Catalyst를 직접 실행 권한 없이 Compiler 뒤에 붙여 창의성과 엄밀성을 분리한 점

## 2. 주요 약점 / 주의점

### CV-01. Alpha Lab의 “WQ-inspired”는 heuristic일 뿐이다
- 공식 WorldQuant 공개 문서는 scoring이 단계별로 달라질 수 있다고 밝힌다.
- 따라서 Fitness/turnover/self-corr 등 기준은 내부 heuristic으로만 써야 하며, hard production law로 오해하면 안 된다.

### CV-02. FF3/Carhart4/FF5 검증은 로컬 factor construction에 민감하다
- 한국시장 구현 시 factor data의 construction 품질이 낮으면 alpha 검증이 왜곡될 수 있다.
- 이 검증은 필수지만 “절대진리”가 아니라 보조적 진위 확인 장치로 써야 한다.

### CV-03. 법전 복잡도 증가
- 문서가 많아질수록 governance overhead가 커진다.
- 자동화가 부족하면 “규칙은 많은데 아무도 다 안 읽는” 상태가 된다.

### CV-04. Perpetual Mode의 가치/비용 균형
- 멈추지 않는다고 잘 배우는 것은 아니다.
- ResearchOps가 우선순위를 잘못 주면, 영구기관은 low-value search machine이 된다.

### CV-05. Control Tower는 intended exposure model 품질에 의존한다
- intended vs realized를 보려면 intended model 자체가 신뢰 가능해야 한다.
- 품질 낮은 risk model로 drift를 재면 오경보가 늘어난다.

## 3. 반드시 점검해야 할 운영 체크리스트
- [ ] Alpha Lab 기준을 hard law로 오해하고 있지 않은가
- [ ] local factor model이 검증 가능한가
- [ ] ResearchOps queue가 실제로 cost-of-learning를 반영하는가
- [ ] duplicate control이 fingerprint + exposure overlap 두 축에서 작동하는가
- [ ] 브리핑이 너무 많아져 의사결정 신호가 희석되지 않는가

## 4. v1.5로 남기는 과제
- local factor model standardization
- DSR/FDR/RC/SPA 자동화
- intended exposure model 품질 검증
- automated contradiction resolution in memory
- governance overhead reduction via template/automation

## 결론
v1.4는 “엄격한 연구조직”을 “탑티어 퀀트펀드 스타일의 연구 운영체제”로 한 단계 밀어 올린다.
그러나 Alpha Lab의 heuristic 성격, 로컬 factor model 품질, lawbook 복잡도, queue economics 실패 가능성은 여전히 가장 큰 리스크다.



## v1.4.2 Addendum — Memory Distillation 관련 주의점

### CV-06. 기억 승격의 과도함
- 모든 요약을 장기기억으로 승격하면 memory pollution이 발생한다.
- v1.4.2는 대화 전체가 아니라 연구 결과를 우선 기억하도록 수정했으나,
  승격 규칙이 너무 엄격하거나 너무 느슨하면 둘 다 문제가 된다.

### CV-07. Regime Payoff Tensor는 regime 품질에 의존한다
- regime 분류가 불안정하면 R4 기억이 오히려 오판을 고정할 수 있다.
- regime-conditioned metric은 confidence와 표본 수를 반드시 동반해야 한다.

### CV-08. Portfolio Policy Memory의 자기강화 위험
- 과거에 잘 된 조합 규칙이 미래에도 최적이라는 보장은 없다.
- R5 기억은 baseline 대비 비교와 leave-one-out 검증을 필수로 요구해야 한다.


---

## FILE: `25_MemoryDistillationPipeline.md`

# 25 Memory Distillation Pipeline
# QEPM Multi-Agent Lawbook v1.4.2 — Research Result Memory Upgrade

## 25.0 목적
본 장은 멀티 에이전트 시스템의 기억을 **대화 원문 중심**이 아니라
**연구 결과 중심**으로 증류·승격·주입하는 표준 파이프라인을 정의한다.

핵심 목표는 다음과 같다.
1. 실험 결과를 재현 가능한 형태로 장기기억화한다.
2. 개별 전략 기억을 넘어, 패밀리/메커니즘/국면/포트폴리오 정책 수준으로 승격한다.
3. 최종 목표인
   **한국시장 최종 포트폴리오 기준 CAGR 16%+, Sharpe 2+, MDD < 25%, FF3/Carhart4/FF5 및 Fama–MacBeth 통과**
   에 직접 기여하는 기억만 장기 저장한다.
4. 런타임에서 “무슨 대화를 했는가”가 아니라
   **“어떤 전략이 어떤 국면에서 어떤 역할로 통하고, 어떻게 결합해야 하는가”**를 우선 주입한다.

---

## 25.1 적용 범위
본 장은 아래 기억을 대상으로 한다.

### 25.1.1 Research Memory (주 대상)
- 실험 결과
- 전략/팩터 family별 작동 조건
- 통계적 검증 결과
- 국면별 기대보수
- 포트폴리오 정책
- 사후운용 학습

### 25.1.2 Conversation Contract Memory (보조)
- 사용자가 명시적으로 승인한 제약/운용 원칙
- 열린 질문
- 다음 행동에 직접 영향을 주는 결정

> 일반 대화 원문, 감정, 설명 과정은 장기기억화 대상이 아니다.

---

## 25.2 기본 원칙

### MD-01. Raw Artifacts are Source of Truth
- 증류된 기억은 원문(raw artifacts)을 대체하지 않는다.
- 실험/전략 관련 사실의 최종 기준은 항상 원시 산출물이다.

### MD-02. Promotion is conditional
- 기억은 자동 승격되지 않는다.
- 단계별 승격 조건(trigger)과 검증을 통과해야 한다.

### MD-03. Research-first retrieval
- Retrieval은 기본적으로 `research_result`를 우선한다.
- Conversation memory는 운영 계약/열린 질문에 한해 보조적으로만 사용한다.

### MD-04. Verification is mandatory
- 각 증류 단계는 hallucination / information loss / distortion 검증을 거친다.

### MD-05. Token budget is finite
- 런타임 주입은 토큰 버짓 내에서
  Schema → Statistical Evidence → Regime Payoff → Portfolio Policy → Recent Digests → Working Memory
  순으로 우선한다.

---

## 25.3 단계 구조

### Stage R0 — Raw Research Artifacts
목적: 실험/전략의 원시 증거를 그대로 저장

필수 저장 대상:
- experiment contract
- backtest results
- returns series
- holdings/weights
- trades / turnover history
- risk audit
- statistical defense report
- data snapshot id
- code version / parameter hash

원칙:
- immutable
- overwrite 금지
- 모든 승격 기억의 출발점

---

### Stage R1 — Experiment Digest
목적: 개별 실험을 비교 가능한 표준 요약으로 압축

출력 예시:
```json
{
  "exp_id": "EXP_2026-03-10_001",
  "strategy_id": "STR_269",
  "family": "idio_vol",
  "construction": {
    "rebalance": "monthly",
    "weighting": "equal",
    "buffer_zone": true,
    "cooldown": 2,
    "neutralization": "sector"
  },
  "metrics": {
    "net_cagr": 0.162,
    "sharpe0_m_ann": 0.98,
    "mdd": -0.439,
    "es99_m": 0.112,
    "turnover_ann": 1.01,
    "ic_mean": 0.051,
    "icir": 0.43
  },
  "alpha_tests": {
    "ff3_alpha": 0.021,
    "ff3_t": 2.35,
    "carhart4_alpha": 0.018,
    "carhart4_t": 2.11,
    "ff5_alpha": 0.015,
    "ff5_t": 1.91,
    "fmb_slope": 0.0042,
    "fmb_t": 2.18
  },
  "grade": "A",
  "role": "core",
  "verdict": "PASS",
  "artifact_paths": ["..."]
}
```

승격 트리거:
- 모든 실험 종료 시 자동 생성
- 단, Audit FAIL이면 `invalidated=true`

---

### Stage R2 — Family / Mechanism Memory
목적: 유사한 실험들을 묶어 “패밀리 수준 교훈”으로 일반화

예시 필드:
```json
{
  "family_id": "FAM_IDIOVOL",
  "mechanism": "low-risk / residual-risk premium",
  "works_when": [
    "sector neutral",
    "monthly or quarterly",
    "buffer-zone when monthly"
  ],
  "fails_when": [
    "hard top-N replacement",
    "over-concentrated variants"
  ],
  "recommended_construction": [
    "n_hold=30",
    "cooldown=2",
    "buffer_zone=25/50"
  ],
  "forbidden_patterns": [
    "same-family corr > 0.85"
  ],
  "best_role": "core|defensive",
  "confidence": 0.86,
  "evidence_count": 12
}
```

승격 조건:
- 동일 family의 실험이 최소 3개 이상
- 방향성이 일정 수준 이상 일관적
- outlier 1개만으로 승격 금지

---

### Stage R3 — Statistical Evidence Store
목적: 전략/패밀리의 “통계적 정당성”만 따로 보관

필수 항목:
- FF3 alpha / t-stat
- Carhart4 alpha / t-stat
- FF5 alpha / t-stat
- Fama–MacBeth slope / t-stat
- bootstrap / placebo / DSR / FDR / SPA 결과(있으면)
- pass/fail tier

예시:
```json
{
  "evidence_id": "EVID_STR_269",
  "target": "STR_269",
  "ff3": {"alpha": 0.021, "t": 2.35, "pass": true},
  "carhart4": {"alpha": 0.018, "t": 2.11, "pass": true},
  "ff5": {"alpha": 0.015, "t": 1.91, "pass": false},
  "fama_macbeth": {"slope": 0.0042, "t": 2.18, "pass": true},
  "tier": "strong"
}
```

승격 조건:
- 통계 방어선(22장)을 통과한 전략만
- 최소 하나 이상의 요인모형/단면 검증 수행

---

### Stage R4 — Regime Payoff Tensor
목적: 전략이 “어떤 국면에서 어떤 역할로 유효한지”를 기억

개념:
Regime × Family × Construction × Role → ExpectedPayoff

예시:
```json
{
  "regime_id": "Stress",
  "family_id": "FAM_IDIOVOL",
  "construction_id": "EQ_30_SECNEUT_BZ25_50_CD2",
  "role": "defensive",
  "metrics": {
    "cagr_cond": 0.09,
    "sharpe0_cond": 0.82,
    "es99_cond": 0.065,
    "mdd_cond": -0.14
  },
  "confidence": 0.78
}
```

승격 조건:
- 국면별 표본 수가 충분할 것
- regime-conditioned 결과가 지나치게 불안정하지 않을 것

---

### Stage R5 — Portfolio Policy Memory
목적: 최종 포트폴리오 수준에서 “어떤 조합 규칙이 먹혔는지” 저장

필수 내용:
- baseline allocation (1/N, RP 등)
- overlay 정책(valuation/regime/implementation)
- role mix(core/defensive/diversifier)
- leave-one-out 결과
- concentration / redundancy caps
- 최종 포트폴리오 KPI

예시:
```json
{
  "policy_id": "POL_core_def_div_v1",
  "sleeves": ["STR_264", "STR_269", "STR_102"],
  "baseline": "risk_parity",
  "overlay": {
    "valuation_tilt_cap": 0.15,
    "regime_shift": "Stress->defensive +10%p"
  },
  "portfolio_metrics": {
    "net_cagr": 0.171,
    "sharpe0_m_ann": 1.62,
    "mdd": -0.228,
    "es99_m": 0.083
  },
  "admission_status": "candidate|paper|production"
}
```

승격 조건:
- baseline 대비 개선
- leave-one-out 통과
- concentration/duplication cap 통과

---

### Stage R6 — Post-Trade Learning Memory
목적: paper/production 운용 후 “예상 vs 실현” 차이를 기억

필수 내용:
- intended vs realized factor exposures
- realized turnover vs model
- slippage drift
- regime misclassification loss
- crowding proxy changes
- watchlist/retire events

이 단계는 21장 Control Tower와 연결된다.

---

## 25.4 승격 규칙 요약
- R0 → R1: 모든 실험 종료 시
- R1 → R2: 동일 family 실험 3개 이상 + 방향 일관성
- R1 → R3: 통계 검증 수행 시
- R2/R3 → R4: regime-conditioned 표본 충분
- R4 → R5: 포트폴리오 조합에서 baseline 개선 확인
- R5 → R6: paper/production 운용 데이터가 쌓일 때

---

## 25.5 Retrieval & Injection 규칙

### 25.5.1 월말 리밸런싱/포트폴리오 구성 시
주입 우선순위:
1. Schema / Governance rules
2. Statistical Evidence Store
3. Regime Payoff Tensor
4. Portfolio Policy Memory
5. Recent Experiment Digests
6. Working Memory

### 25.5.2 신규 Research Chunk 설계 시
주입 우선순위:
1. 최근 Family / Mechanism Memory
2. 최근 실패 교훈(Lesson)
3. Statistical Evidence Store
4. Current backlog priority context
5. Working Memory

### 25.5.3 대화형 연속성 질문 시
- Conversation contract memory만 제한적으로 조회
- 일반 대화 원문은 retrieval 기본 대상이 아니다

---

## 25.6 Verification Loop

### 25.6.1 검증 대상
- hallucination: 없는 성과/없는 알파/없는 역할을 추가했는가
- information loss: 실패 원인/국면 조건/통계 경고가 빠졌는가
- distortion: 전략 역할(core/defensive/diversifier) 또는 family 메커니즘을 왜곡했는가

### 25.6.2 처리 규칙
- minor: 재증류
- repeated: 프롬프트 수정 제안
- severe: 관리자 검토로 escalated

---

## 25.7 연결 문서
- 13장: MEMORY_COMMIT 단계에서 본 장 호출
- 14장: experiment digest 입력 제공
- 15장: 저장소/레지스트리 스키마 정의
- 20장: Portfolio Policy Memory 활용
- 21장: Post-Trade Learning Memory 활용

---

## 25.8 구현 우선순위
### Phase 1
- R0 + R1
- Experiment Digest 자동 생성
- Registry 연결

### Phase 2
- R2 + R3
- Family memory + statistical evidence store

### Phase 3
- R4 + R5
- regime payoff tensor + portfolio policy memory

### Phase 4
- R6 + verification 강화
- realized vs intended feedback loop 강화

---

## 25.9 결론
본 장은 멀티 에이전트가 단순히 “많은 실험을 하는 시스템”이 아니라,
**무슨 전략이 어떤 국면에서 어떤 역할로 통했고, 어떻게 조합해야 최종 포트폴리오 목표(CAGR 16%+, Sharpe 2+, MDD < 25%, 통계적 알파 검증 통과)에 가까워지는가를 축적하는 시스템**
으로 발전하기 위한 기억 증류 파이프라인을 정의한다.


---

## FILE: `99_References.md`

# 99. References (v1.4.1)

본 법전은 아래 문헌/리포트에서 강조하는 이론·위험요인·검증 관점을 운영 규칙에 반영한다.

## A. QEPM / 연구 프로세스 / 포트폴리오 이론
- Chincarini, L., & Kim, D. *Quantitative Equity Portfolio Management* (Appendix D: research process; Appendix A/B/C: financial theory, valuation, math review)
- Markowitz, H. (1952). *Portfolio Selection.*
- Sharpe, W. F. (1964). *Capital Asset Prices: A Theory of Market Equilibrium under Conditions of Risk.*
- Lintner, J. (1965). *The Valuation of Risk Assets and the Selection of Risky Investments in Stock Portfolios and Capital Budgets.*
- Mossin, J. (1966). *Equilibrium in a Capital Asset Market.*
- Ross, S. A. (1976). *The Arbitrage Theory of Capital Asset Pricing.*

## B. Smart Beta / Factor / Robustness / Capacity
- ERI Scientific Beta. *Robustness of Smart Beta Strategies.*
- Arnott, Beck, Kalesnik, West. *How Can Smart Beta Go Horribly Wrong?*
- Arnott, Beck, Kalesnik. *Timing “Smart Beta” Strategies? Of Course! Buy Low, Sell High!*
- Lazard Insights. *Distilling the Risks of Smart Beta.*
- Huang, Song, Xiang. *The Smart Beta Mirage.*
- Ang, Ratcliffe, Miranda. *Capacity of Smart Beta Strategies: A Transaction Cost Perspective.*
- Amenc, Goltz, Lodh. *Smart Beta Is Not Monkey Business.*
- Johansson, Sabbatucci, Tamoni. *Smart Beta Made Smart.*
- Jacobs & Levy. *Smart Beta versus Smart Alpha.*

## C. Style Portfolio Construction / Optimization
- Fays, Lambert, Papageorgiou. *Strategic Beta and Style Investing: Implication of a (In)dependent Sorting.*
- Fays, Lambert, Papageorgiou. *Smart Equity Investing: Implementing Risk Optimization Techniques on Strategic Beta Portfolios.*
- Clare, Motson, Thomas. *Market cap or monkey?* (Part 1 & 2)

## D. Factor Validation / Asset Pricing Models (v1.3 추가)
- Fama, E. F., & MacBeth, J. D. (1973). *Risk, Return, and Equilibrium: Empirical Tests.*
- Fama, E. F., & French, K. R. (1993). *Common Risk Factors in the Returns on Stocks and Bonds.*
- Carhart, M. M. (1997). *On Persistence in Mutual Fund Performance.*
- Fama, E. F., & French, K. R. (2015). *A Five-Factor Asset Pricing Model.*

## E. Multiple Testing / Statistical Guardrails (v1.3 추가)
- Bailey, D., & López de Prado, M. *The Deflated Sharpe Ratio: Correcting for Selection Bias, Backtest Overfitting and Non-Normality.*
- Harvey, C. R., Liu, Y., & Zhu, H. *... and the Cross-Section of Expected Returns.*
- White, H. *A Reality Check for Data Snooping.*
- Hansen, P. R. *A Test for Superior Predictive Ability.*

## F. Risk / Performance Metrics
- Sharpe, W. F. (1966). *Mutual Fund Performance.*
- Rockafellar, R. T., & Uryasev, S. (2000). *Optimization of Conditional Value-at-Risk.*
- Rockafellar, R. T., & Uryasev, S. (2002). *Conditional Value-at-Risk for General Loss Distributions.*
- Acerbi, C., & Tasche, D. (2002). *On the Coherence of Expected Shortfall.*

## G. Top-tier Quant Research & Portfolio Construction (v1.4 추가)
- WorldQuant BRAIN IQC Guidelines (official public rules; stage-varying scoring, IQC structure):  
  https://www.worldquant.com/brain/iqc-guidelines/
- WorldQuant IQC FAQ (official public “quality and quantity” of alphas, no submission cap):  
  https://www.worldquant.com/brain/iqc/
- WorldQuant University Ranking methodology (official public IS/OOS weighting example):  
  https://www.worldquant.com/brain/leaderboard/

- Two Sigma — Introducing the Two Sigma Factor Lens (parsimonious, orthogonal, actionable):  
  https://www.twosigma.com/wp-content/uploads/Introducing-the-Two-Sigma-Factor-Lens.10.18.pdf
- Two Sigma — Forecasting Factor Returns:  
  https://www.twosigma.com/wp-content/uploads/Forecasting-Factor-Returns.FINAL_-2.pdf
- Two Sigma / Venn — Factor Investing & Analysis Guide:  
  https://www.venn.twosigma.com/resources/factor-investing-analysis

- AQR — Strategic Portfolio Construction: How to Put It All Together:  
  https://www.aqr.com/-/media/AQR/Documents/Insights/Alternative-Thinking/Alternative-Thinking-Strategic-Portfolio-Construction.pdf
- AQR — Long-Only Style Investing: Don’t Just Mix, Integrate:  
  https://images.aqr.com/-/media/AQR/Documents/Insights/White-Papers/Long-Only-Style-Investing-Dont-Just-Mix-Integrate.pdf
- AQR — Understanding Risk Parity:  
  https://www.aqr.com/-/media/AQR/Documents/Insights/White-Papers/Understanding-Risk-Parity.pdf
- AQR — Portfolio Rebalancing: Common Misconceptions:  
  https://www.aqr.com/-/media/AQR/Documents/Whitepapers/AQR_Portfolio-Rebalancing_Common-Misconceptions.pdf?sc_lang=en



## v1.4.2 참고 메모
- 본 장(25)의 Memory Distillation Pipeline은 프로젝트 내부 운영 아키텍처 제안이다.
- 외부 레퍼런스는 retrieval-augmented systems, summarization verification, episodic/semantic memory 아키텍처 일반 논의와 정합적이며,
  구체 구현은 프로젝트 제약(로컬 환경, PIT 우선, 연구 결과 중심 기억)에 맞춰 설계되었다.


---

## FILE: `CHANGELOG_v1_3.md`

# QEPM Multi-Agent Lawbook v1.3 — 변경 요약 코멘트

## 이번 업데이트의 핵심 방향
v1.3는 “규칙을 더 많이 추가”하기보다, **에이전트가 더 적은 계산으로 더 좋은 실험을 더 안정적으로 선택**하도록 구조를 바꾼 버전이다.

### 1) Sharpe 중심화 + Tail Risk 보강
- v1.21의 요청을 반영해 **Sharpe(Rf=0%)를 핵심 성과 KPI**로 승격
- 동시에, Sharpe만 보면 꼬리위험을 놓치므로 **CVaR(99%)**를 리스크 축의 필수 KPI로 유지/강화
- 해석: 수익률이 높아도 tail risk가 나쁘면 좋은 전략이 아님

### 2) PASS 전략에 “팩터 알파 검증” 추가
- PASS/near-pass 전략에 대해 **FF3 / Carhart4 / FF5 alpha validation**을 추가
- 목적: “사실상 시장/스타일 베타인데 알파인 척”하는 전략을 걸러내기 위함
- 단, 이는 Sharpe를 대체하는 것이 아니라 **보조적 진위 확인 장치**로 사용

### 3) Fama–MacBeth 도입
- 개별 종목 신호 전략은 **전략 수익률뿐 아니라 신호 자체의 단면 설명력**을 검증해야 하므로 Fama–MacBeth 절차를 추가
- 목적: “백테스트에서만 예쁜 랭킹”과 “단면적으로 실제 설명력이 있는 신호”를 구분

### 4) ResearchOps 신설
- 영구기관(Perpetual Mode)은 이미 있었지만, “무엇을 먼저 돌릴지”를 계산하는 규칙이 약했음
- v1.3는 **Backlog priority / Value of Experiment / Family penalty**를 도입하여 연구 처리량을 최적화

### 5) Strategy Lifecycle & Duplicate Control 추가
- Grade(A/B/C/F)만으로는 실제 운용 단계 관리가 부족했음
- `IDEA → SANDBOX → CANDIDATE → PAPER → PRODUCTION → WATCHLIST → RETIRED`를 도입
- 동시에 전략 fingerprint와 중복 관리(dup_group_id, alias)를 도입하여 “같은 전략을 새로 발견한 척”하는 문제를 차단

### 6) Objective Hierarchy 명문화
- v1.2까지는 규칙은 많았지만, 충돌 시 우선순위가 완전히 명문화되지는 않았음
- v1.3는 **Validity > Implementability > Robustness > Performance > Novelty** 순서를 고정
- 해석: 높은 CAGR/Sharpe라도 PIT/TO/유동성/재현성이 깨지면 무효

## 실무적 기대효과
- 무한 리서치가 “열심히 돌지만 잘못 배우는” 구조에서 벗어남
- PASS 수의 질적 수준이 올라가고, A/B/C 분류가 실제 운용 단계와 더 자연스럽게 연결됨
- 리서처가 나중에 법전을 다시 볼 때, “왜 이 실험을 먼저 했는지”와 “왜 이 전략을 production에 안 올렸는지”가 더 선명해짐


---

## FILE: `CHANGELOG_v1_4.md`

# QEPM Multi-Agent Lawbook v1.4 — 변경 요약 코멘트

## 이번 업데이트의 핵심 방향
v1.4는 v1.3의 “엄격한 연구조직”을 **글로벌 탑티어 퀀트 리서치 운영체제**로 확장하는 버전입니다.

### 1) Stage 0 Alpha Lab 도입
- 공개적으로 확인 가능한 WorldQuant BRAIN의 철학(quality + quantity, OOS 비중, stage-varying scoring)을 차용해 **빠른 아이디어 위생검사** 계층을 추가했습니다.
- 단, 이것은 **WQ-inspired heuristic**이지, WorldQuant 내부 기준의 복제가 아닙니다.

### 2) Factor Taxonomy & Labeling
- 팩터/전략을 구조적으로 라벨링해 중복/위장/유사 전략 문제를 줄였습니다.
- 이후 Blender, Control Tower, Catalyst가 같은 좌표계를 쓰게 됩니다.

### 3) Portfolio Construction 분리
- 신호와 포트폴리오 구성을 분리해 definition vs construction을 명확히 했습니다.
- baseline(1/N, RP 등)과 overlay(valuation/regime/cost)를 순차적으로 적용하는 법을 문서화했습니다.

### 4) Post-Trade Control Tower 추가
- PASS가 끝이 아니라, realized exposure / slippage / capacity / drift까지 감시하는 운영 체계를 추가했습니다.

### 5) Statistical Defense 강화
- v1.3의 알파 검증에 더해 DSR/FDR/Reality Check/SPA/부트스트랩/플라시보를 별도 장으로 독립시켜, 영구기관 환경에서 false discovery를 더 강하게 통제합니다.

### 6) Catalyst + Idea Compiler 통합
- cross-domain 창의성을 제도권 안으로 끌어들였습니다.
- 이제 아이디어는 반드시 Compiler를 거쳐 Experiment Ticket으로 전환된 뒤, ResearchOps 큐로 들어갑니다.

## 가장 중요한 철학 변화
v1.4는 “좋은 전략을 찾는 조직”이 아니라,
**빨리 거르고(Alpha Lab), 깊게 검증하고(Validation), 제대로 조립하고(Construction), 끝까지 관리하는(Control Tower)** 조직을 지향합니다.


---

## FILE: `CHANGELOG_v1_4_1.md`

# CHANGELOG v1.4.1

## 목적
v1.4의 구조를 유지하면서, 운영 모호성 제거와 연구 수렴(mode collapse) 방지를 위한 마이너 패치를 반영한다.

## 핵심 수정사항
1. **버전/지표 일관성 강화**
- 문서 제목과 KPI 표준을 v1.4.1로 통일
- 기본 Sharpe를 `Sharpe0_m_ann`으로, 기본 tail risk를 `ES99_m`으로 통일

2. **CVaR 부호/빈도 모호성 해소**
- CVaR 대신 기본 표기명을 `ES99`(양의 손실 크기)로 통일
- 월간 기준 `ES99_m`을 기본 KPI, 일간 `ES99_d`를 보조 KPI로 분리

3. **Alpha Lab 의미 제한 강화**
- Alpha Lab PASS는 “정식 검증 가치 있음”만 의미
- lifecycle에서 `ALPHA_LAB`까지만 승격 가능

4. **ResearchOps 우선순위 점수 정규화**
- Gain/Learning/Novelty/Cost/Dependency/FamilyPenalty를 0~5 스케일로 정의
- exploit/orthogonal/counterfactual 예산 분할 추가

5. **Factor Research의 다양성 보존 장치 추가**
- Hard Law vs Soft Prior 분리
- 연구 예산을 Exploit 50 / Orthogonal 30 / Counterfactual 20으로 권장
- family concentration cap, counterfactual obligation 추가

6. **Post-Trade drift 비교의 모델 버전 명시**
- intended vs realized exposure 비교시 intended/realized model version 기록 의무화

7. **브리핑 중복 방지**
- `msg_hash` 기반 24시간 중복 전송 금지

8. **통계 방어 발동 조건 명시**
- family trial_count와 승격 단계에 따라 DSR/FDR/SPA/Reality Check의 최소 발동 기준을 명시


---

## FILE: `CHANGELOG_v1_4_2.md`

# QEPM Lawbook v1.4.2 변경 코멘트

## 성격
v1.4.2는 **“대화 기억”이 아니라 “연구 결과 기억 승격”** 을 공식 도입하는 패치입니다.
핵심 목표는:
1. 실험 결과를 장기기억화하는 구조 정립
2. 국면별 기대보수/포트폴리오 정책을 기억 레벨로 승격
3. 월간 리밸런싱과 자가발전 연구 루프를 더 밀접하게 연결

## 주요 수정사항

### 1) `25_MemoryDistillationPipeline.md` 신설
기억을 아래 단계로 승격:
- R0 Raw Research Artifacts
- R1 Experiment Digest
- R2 Family / Mechanism Memory
- R3 Statistical Evidence Store
- R4 Regime Payoff Tensor
- R5 Portfolio Policy Memory
- R6 Post-Trade Learning Memory

### 2) 대화 기억 최소주의 채택
- 일반 대화 원문은 장기기억 대상에서 제외
- 사용자가 명시적으로 승인한 제약/원칙/열린 질문만 제한적으로 유지
- 장기기억의 우선순위는 `research_result` > `governance_rule` > `conversation_contract`

### 3) Self-Evolution과 Memory 연결 강화
- MEMORY_COMMIT 단계에서 25장 파이프라인 호출
- 새로운 청크는 “기억의 공백”을 메우는 방향으로 우선 생성

### 4) Portfolio Construction / Control Tower와 연결
- 20장은 Regime Payoff / Portfolio Policy Memory를 참조
- 21장은 운영 결과를 Post-Trade Learning Memory로 승격

## 기대효과
- 같은 실험을 이름만 바꿔 반복하는 문제 감소
- “전략 하나의 성과”가 아니라 “패밀리/국면/포트폴리오 정책” 수준 학습 가능
- 최종 목표(CAGR 16%+, Sharpe 2+, MDD<25, 통계적 알파 검증 통과)에 더 직접적으로 연결된 기억 구조 형성


---

## FILE: `TOC.md`

# QEPM Lawbook v1.4.2 목차

## 본편
- `00_README.md` — 법전 목적/원칙/문서 맵/버전 변경 요약
- `01_Architecture_and_Roles.md` — 멀티 에이전트 구조, 역할, 권한 경계
- `02_DataLake_and_DB_Policy.md` — 데이터레이크, DB, 스냅샷, QC 정책
- `03_Feature_Store_and_Factor_Definitions.md` — FeatureStore, PIT 규칙, 팩터 정의 원칙
- `04_Strategy_Spec_Template.md` — 전략 제출 표준 템플릿
- `05_Backtest_Protocol_and_Validation.md` — 백테스트 표준 및 검증 규칙
- `06_Hurdle_System.md` — 허들, 등급, 전략-포트폴리오 이중 승격 구조
- `07_Risk_Audit_and_Stress_Tests.md` — 리스크 심사 및 스트레스 테스트
- `08_Ensemble_and_Regime_Playbook.md` — 앙상블/국면 플레이북
- `09_Monthly_Rebalance_and_Daily_Briefing.md` — 월간 리밸/일일 브리핑 운영 규칙
- `10_Orchestration_Message_Spec.md` — 에이전트 메시지/상태/브리핑/메모리 이벤트 규칙
- `11_Factor_and_Strategy_Valuation_Agent.md` — 밸류에이션 측정 레이어
- `12_Factor_and_Strategy_Blender_Agent.md` — 블렌딩/앙상블 실행 규칙
- `13_SelfEvolution.md` — 자가발전/영구기관 운영 규칙
- `14_ExperimentProtocol.md` — 실험 계약서 표준 + Sharpe0/ES99 + 통계 방어 발동 조건
- `15_MemorySpec.md` — 장기기억 스펙과 증거 기반 기록 규칙
- `16_ResearchOps_and_Optimization.md` — Backlog 경제학, 우선순위, 예산 분할
- `17_Strategy_Lifecycle_and_Duplicate_Control.md` — 전략 생애주기와 중복 통제
- `18_AlphaLab_Stage.md` — WQ-inspired Alpha Lab 휴리스틱 필터
- `19_FactorLabel_Taxonomy.md` — 팩터/전략 라벨링 및 taxonomy
- `20_PortfolioConstruction_and_Overlays.md` — 포트폴리오 구성 및 overlay stack
- `21_PostTrade_ControlTower.md` — 사후 관리, drift, lifecycle 전환
- `22_StatisticalDefense.md` — 다중검정/통계 방어 계층
- `23_Catalyst_and_IdeaCompiler.md` — 창의성 에이전트와 컴파일러 구조
- `24_v1_4_Critical_Validation.md` — v1.4 비판적 검증 요약(참고용)
- `25_MemoryDistillationPipeline.md` — 연구 결과 기억 증류/승격/주입 파이프라인
- `99_References.md` — 참고문헌

## 보조 문서
- `CHANGELOG_v1_3.md`
- `CHANGELOG_v1_4.md`
- `CHANGELOG_v1_4_1.md`
- `CHANGELOG_v1_4_2.md`
- `TOC.md`
- `VALIDATION_SUMMARY_v1_4.md`
- `VALIDATION_SUMMARY_v1_4_1.md`
- `VALIDATION_SUMMARY_v1_4_2.md`


---

## FILE: `VALIDATION_SUMMARY_v1_4.md`

# QEPM Multi-Agent Lawbook v1.4 — 비판적 검증 요약

## 전체 평가
v1.4는 v1.3 대비 확실히 “탑티어 퀀트 리서치 조직”에 가까워졌습니다.
강점은 다음과 같습니다.
- Stage 0 Alpha Lab → Stage 1 Validation → Construction → Control Tower의 4단 구조
- WQ-inspired fast filter를 heuristic으로만 제한한 점
- Two Sigma/AQR류의 factor lens / portfolio construction 원칙을 별도 장으로 독립시킨 점
- Catalyst를 직접 실행 권한 없이 Compiler 뒤에 붙여 창의성과 엄밀성을 분리한 점

## 남은 핵심 리스크
1. Alpha Lab은 heuristic이다. 공식 WQ 내부 점수 재현으로 오해하면 안 된다.
2. FF3/Carhart4/FF5 / Fama–MacBeth는 local factor construction 품질에 민감하다.
3. 문서가 늘어나면서 governance overhead가 증가했다. 자동화 없이는 운영 피로가 누적될 수 있다.
4. ResearchOps가 우선순위를 잘못 주면 영구기관이 저효율 실험을 계속할 수 있다.
5. Control Tower의 intended exposure 모델이 약하면 drift 경보의 질이 떨어진다.

## 운영 권고
- v1.4 채택 직후 2주간은 “법전 회귀테스트 기간”으로 두고, 각 장의 실제 적용 여부를 점검하라.
- local factor model(한국시장용 FF3/5/Carhart 대체/확장) 표준화 작업을 우선하라.
- Alpha Lab 컷오프는 처음 1개월은 advisory로만 사용하고, 운영 데이터를 보고 조정하라.


---

## FILE: `VALIDATION_SUMMARY_v1_4_1.md`

# v1.4.1 Self-Validation

## 총평
v1.4.1은 v1.4의 거버넌스와 구조를 유지하면서, 운영 모호성과 연구 수렴 위험을 줄이는 데 초점을 맞췄다.

## 개선된 점
- KPI 표준(Sharpe0_m_ann, ES99_m)이 명확해졌다.
- Alpha Lab PASS의 오해 가능성이 줄었다.
- ResearchOps의 우선순위 계산이 더 일관되게 작동할 수 있다.
- 동일 family 반복 탐색에 대한 제어가 강해졌다.
- 드리프트 비교와 브리핑 중복 관리가 더 명확해졌다.

## 여전히 남는 리스크
1. DSR/FDR/SPA/Reality Check의 실제 구현 품질은 코드 레이어에 달려 있다.
2. exploit/orthogonal/counterfactual 예산 배분은 운영 데이터가 쌓이면 재튜닝이 필요하다.
3. ES99를 월간 기준으로 삼았지만, 단기 tail risk는 일간 ES99_d를 함께 봐야 한다.
4. 문서가 많아진 만큼, 에이전트별 프롬프트가 법전 내용을 제대로 참조하도록 연결해야 한다.

## 다음 권장 단계
- 에이전트별 시스템 프롬프트/작업 프롬프트 작성
- 핵심 KPI와 Registry 스키마를 코드 레이어에 동기화
- message/event dedupe, fingerprint, family accounting 회귀테스트 추가


---

## FILE: `VALIDATION_SUMMARY_v1_4_2.md`

# QEPM Lawbook v1.4.2 자체 검증 요약

## 총평
v1.4.2는 기존의 “실험/전략/교훈” 중심 메모리 구조를 한 단계 추상화하여,
패밀리/국면/포트폴리오 정책 수준까지 기억을 승격하는 방향으로 개선되었습니다.

## 긍정적 평가
1. **목표 정렬성 강화**
   - 최종 목표가 “전략 단일 성과”가 아니라 “국면 기반 동적 포트폴리오”라는 점과 기억 구조가 더 정합적으로 연결됨
2. **연구 기억 우선**
   - 대화 기억을 최소화하여 메모리 오염과 retrieval 혼선을 줄임
3. **통계 근거 분리**
   - Statistical Evidence Store를 통해 “좋아 보이는 결과”와 “통계적으로 남는 결과”를 분리 가능
4. **정책 수준 학습**
   - Portfolio Policy Memory로 baseline/overlay/role mix의 재사용성과 비교 가능성이 높아짐

## 남은 리스크 / 주의점
1. **구현 복잡도 증가**
   - R4/R5/R6는 실제 코드 레이어로 옮길 때 추가 스키마/ETL 비용이 큼
2. **국면 분류 품질 의존**
   - Regime Payoff Tensor의 품질은 regime engine의 안정성에 크게 좌우됨
3. **승격 기준 과도화 위험**
   - 모든 단계에 승격 규칙을 넣었기 때문에, 너무 엄격하면 기억이 “안 쌓이는” 문제가 생길 수 있음
4. **검증 루프 비용**
   - hallucination/loss/distortion 검증을 모든 단계에 강제하면 compute cost가 증가

## 권장 구현 순서
- Phase 1: R0/R1 + registry 연결
- Phase 2: R2/R3
- Phase 3: R4/R5
- Phase 4: R6 + verification 고도화

## 최종 평가
v1.4.2는 “대화를 오래 기억하는 시스템”이 아니라,
“연구 결과를 구조적으로 승격해 최종 포트폴리오 의사결정에 재사용하는 시스템”으로 방향을 바로잡는 적절한 패치입니다.
