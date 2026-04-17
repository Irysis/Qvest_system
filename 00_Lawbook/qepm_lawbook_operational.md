# QEPM 운용 법전 v1.4 — 자가발전형 퀀트 에이전트 행동지침
# 핵심 철학: 학술 레퍼런스 기반 무한 탐색 → 실증 검증 → 장기기억 축적 → 전략 적용
# 하드코딩된 방법론을 지정하지 않는다. 메타 프로세스만 정의한다.
# v1.4 반영: Multi-Sleeve Portfolio(§7), Alpha Lab(§8), Factor Taxonomy(§9),
#            Statistical Defense(§10), Strategy Lifecycle(§11), ResearchOps(§12)
# v1.4 Ch.06: Objective Hierarchy + Near-Miss Repair + Gate 4/5
# v1.4 Ch.08/20: orthogonal sleeves + construction 원칙
# v1.4 Ch.16: 4-bucket backlog (Exploit/Stabilize/Explore/Diagnose)

## 0. 자가발전 루프 (핵심 메커니즘)

```
EXPLORE → HYPOTHESIZE → IMPLEMENT → VALIDATE → MEMORIZE → APPLY → EXPLORE ...
```

| 단계 | 행동 | 학술 기반 요구 |
|------|------|----------------|
| Explore | **경로 A**: 레퍼런스 → 아이디어 (henryquant/Literature/SSRN) | 논문 근거 명시 |
|         | **경로 B**: 직관/관찰 → 아이디어 → 사후 논문 서치 | 메커니즘 3문장 + 사후 근거 탐색 |
| Hypothesize | 한국시장 적용 가능성 평가 + 실패 조건 사전 정의 | 경제적 메커니즘 서술 (A: 1문장, B: 3문장) |
| Implement | factor_engine.R 코드화 + 백테스트 | Maxwell 4-Step 준수 |
| Validate | 허들 게이트 + 강건성 테스트 | 통계적 유의성 검증 (t-stat, IC/ICIR) |
| Memorize | 성공/실패 모두 methodology_memory.md에 축적 | 조건부 기록: "X 조건에서 A가 B보다 우월" |
| Apply | 다음 전략에 축적된 최적 방법론 적용 | 기억의 조건과 현재 맥락 일치 시에만 |

- **매 사이클마다**: 탐색 범위를 좁히지 않는다. 이전 실패가 다른 맥락에서 성공할 수 있다.
- **다양성 유지**: 단일 economic_family(예: defensive)에 고착 금지. §9 taxonomy 기준으로
  미구축 family가 있으면 Explore 버킷에서 우선 탐색 (v1.4 Ch.13)
- **기억은 조건부**: "A가 최고"가 아니라 "X 팩터 유형 + Y 시장환경에서 A > B (근거: 논문Z)"
- **양방향 탐색 허용**:
  - **경로 A (논문→아이디어)**: 학술 근거 먼저 → 가설 도출 → 구현. evidence_tier A/B.
  - **경로 B (아이디어→논문)**: 직관/관찰/창의적 조합 먼저 → 메커니즘 3문장 서술
    → Alpha Lab Stage 0 (ICIR ≥ 0.20) → 통과 시 사후 논문 서치로 근거 보강.
    evidence_tier C → Grade A 달성 시 B로 승격.
  - 경로 B 예산: Explore 버킷 내 최대 30% (전체의 ~6%)
  - 경로 B 실패 시: 메커니즘 무효 사유 + 교훈 기록 필수
- **폭주 방지**: 경로 B라도 Alpha Lab 스크리닝은 면제 불가. 메커니즘 서술 없는 무작위 조합은 기각.

## 0-A. 1차 레퍼런스: henryquant QEPM (필수 참조)

**파일**: `memory/henryquant_qepm_reference.md` (799줄)
**원서**: Chincarini & Kim "Quantitative Equity Portfolio Management" 2nd Ed.
**정리자**: 이현열 (증권사 퀀트PM)

자가발전 루프의 Explore 단계에서 **가장 먼저 참조**할 교과서급 레퍼런스.
각 탐색 영역별 해당 섹션:

| 탐색 영역 | QEPM 레퍼런스 섹션 | 핵심 내용 |
|-----------|-------------------|----------|
| 팩터 결합 | §8 팩터 결합 방법 | rank sum vs Z-score vs weighted Z. Magic Formula 사례 |
| 섹터 중립화 | §6 섹터 중립화 | group_by+scale(), IC 0.023→0.041 실증 |
| 포트폴리오 가중 | §10 포트폴리오 가중 방법 | MinVar/MDP/RiskParity/RiskBudget/EW/MCW 6종 + R코드 + KOSPI200 실증 |
| 팩터 검증 | §4 팩터 강건성 검증 | Rank IC 3-5% 기준, 8단계 체크리스트 |
| 이상치 | §7 이상치 처리 | Trim vs Winsorize 비교. 포트폴리오용은 Winsorize 권장 |
| 리밸런싱 | §12 리밸런싱과 거래비용 | Turnover 계산, 빈도 비교, Faber 타이밍 |
| 백테스트 | §13 백테스트 방법론 | Look-ahead/생존편향/데이터스누핑 3대 함정 |
| 성과 평가 | §14 성과 및 위험 평가 | Carhart 4-Factor 회귀, 롤링 윈도우 분석 |
| 한국시장 | §16 한국시장 팩터 실증 | 2001-2017 팩터 성과표, 골고다(2016-17) 분석 |
| 멀티팩터 | §9 멀티팩터 포트폴리오 | QVM 결합 프로세스, Sharpe 1.23/MDD 10.22% 실증 |

**참조 프로토콜**:
1. 새 방법론 실험 전 → 해당 섹션 읽고 교과서 기준점 확인
2. 실험 결과 기록 시 → QEPM 레퍼런스 대비 개선/열화 명시
3. methodology_memory.md 기록 시 → QEPM 섹션 번호 인용 (예: "QEPM §10 기준 MinVar 대비...")

## 1. 탐색 대상 (자율 연구 영역)

Q가 자율적으로 탐색·비교·축적해야 할 방법론 차원:

### 1-A. 팩터 결합 (Factor Combination)
- 탐색 후보: equal-weight rank, IC-weighted, z-score blend, PCA composite,
  Bayesian shrinkage, ML-based stacking, rank-weighted IC decay 등
- 학술 기반: Kakushadze (2016) "101 Formulaic Alphas",
  Ghayur et al. "Equity Smart Beta and Factor Investing"
- 기억 형식: `{method, factor_type, universe, ICIR_delta, sharpe_delta, conditions, ref}`

### 1-B. 섹터/시총 중립화 (Neutralization)
- 탐색 후보: 미중립, group-demean, WLS 잔차, Fama-French 잔차,
  sector-rank-then-combine, Barra-style risk model residual 등
- 학술 기반: Fama-French (1993), Barra risk model framework,
  Menchero (2010) "Characteristics of Factor Portfolios"
- 기억 형식: `{method, target_exposure, residual_alpha, sector_HHI_change, ref}`

### 1-C. 포트폴리오 가중 (Portfolio Weighting)
- **1차 레퍼런스**: `qepm_weighting_agent_knowledgepack.md` (도훈 작성, 17개 방법론 A~Q)
- **2차 레퍼런스**: `portfolio_weighting_research_academic.md` (학술 서베이, 19개 최신 방법론)
- 방법론 분류 체계 (지식팩 §4 기준):
  - Naive/Deterministic: EW(A), Cap(B), Fundamental(C)
  - Risk-only (μ 불필요): MinVar(D), ERC/RP(E), MD(F), MaxDeconc(G), HRP(H)
  - Alpha/Benchmark-relative: Active MV(I), BL(J), Factor Model(K), Shrinkage(L), Resampled(M)
  - Tail-risk/Robust: CVaR(N), DRO(O)
  - Implementation: Cost-aware(P), Style-Portfolio-First(Q)
- 선택 정책: 지식팩 §5 Decision Rules 참조 (objective × data availability 기반)
- 추가 최신 학술: NCO, RMT Denoising, Analytical NL Shrinkage, Factor Risk Parity, SJM Regime-Conditional
- 기억 형식: `{method_id(A~W), factor_type, universe, sharpe, MDD, turnover, stability, ref}`
- **자동 업데이트**: 논문 분석 시 비중결정 관련 발견 → 지식팩 §4에 카드 추가 → 법전 동기화

### 1-D. 리밸런싱/실행 (Execution)
- 탐색 후보: 월초 고정, 신호 기반 트리거, 밴드 리밸런싱,
  partial rebalancing, turnover-constrained optimization 등
- 학술 기반: Novy-Marx & Velikov (2016) "Transaction Costs"

### 1-E. 레짐 조건부 배분 (Regime-Conditional)
- 탐색 후보: 레짐별 팩터 틸트, 레짐별 가중 방식 전환,
  레짐 확률 연속 가중, 레짐 무시(unconditional) 등
- 학술 기반: Ang & Bekaert (2002) "Regime Switches",
  Guidolin & Timmermann (2007)

### 1-F. Multi-Sleeve 구성 (v1.4 Ch.08/20 신규)
- §7 Multi-Sleeve Portfolio 규칙에 따라, 서로 다른 economic_family의
  독립 전략을 sleeve로 구축하여 포트폴리오 수준에서 결합
- 탐색 후보 패밀리: momentum, quality, value (defensive는 포화)
- portfolio mix vs integrated construction 비교 실험
- equal-vol scaling vs 1/N vs RP 비교
- 학술 기반: Asness et al. (2013) "Value and Momentum Everywhere",
  Novy-Marx (2013) "The Other Side of Value",
  Jegadeesh & Titman (1993) "Returns to Buying Winners"

## 2. 검증 프로토콜 (변경 불가 하드 제약)

자가발전 루프가 자유롭게 방법론을 탐색하되, 아래는 절대 위반 불가:

### 2-A. 데이터 무결성
- Point-in-time 강제: `available_date <= t` 위반 시 전략 무효
- 재무 공시 시차: Factor_Date 기준. bsns_year 직접 사용 금지
- 생존편향 제거: 상폐/거래정지 RAWDATA에 포함 유지
- 스냅샷 봉인: 월간 리밸런싱은 전월말 데이터로만 결정

### 2-B. 백테스트 무결성
- 필수: PIT + 생존편향 제거 + 거래비용 + 리밸런싱 규칙 고정
- 비용: commission=0.0015(기본) + 0.003(스트레스) 이중 보고
- 재현성: set.seed() + 동일 입력 = 동일 결과

### 2-C. 허들 게이트 (hurdle_gate.R) — v1.4 Ch.06 반영

**Objective Hierarchy** (사전순 우선순위, 상위 FAIL 시 하위 무효):
1. **Validity** — PIT, 데이터 무결성, 재현성
2. **Implementability** — TO, 비용, 유동성, 집행 가능성
3. **Robustness** — OOS, Stress, CVaR99, MDD 경로
4. **Performance** — Sharpe0 (1순위), CAGR, IR
5. **Novelty** — 새 알파 소스, 직교성, 학습가치

**Hard fail**: MDD > 45% OR Turnover > 600%
**Soft score**: 0-100, Pass: score >= 40 AND no hard fail
**등급**: A(standalone) / B(component) / C(ensemble only) / F(fail)

**Two-Stage Hurdle** (v1.4 Ch.06 §5):
- Stage 0: Alpha Lab — 5Y IC/ICIR 빠른 사전검증
- Stage 1: Research Validation — 정식 Grade 판정 + Statistical Validation

**Near-Miss Repair** (v1.4 Ch.06 §6):
- Hard fail이 아닌 임계값 근처 실패(예: MDD 45.4%, CAGR 15.8%)는 "가치 있는 실패"
- methodology_memory.md에 repair 방향 기록: 목적 축, 기대 변경, 성공 기준
- Near-miss를 Fail과 동일하게 폐기하면 자가발전 효율 저하

**허들 기준 하향 금지.** 리스크/현실성 반영 목적만 허용

### 2-D. 통계적 엄밀성 — v1.4 Ch.06 Gate 4/5, Ch.14, Ch.22 반영

**기본 검증**:
- 팩터 유의성: IC t-stat, ICIR, 횡단면 회귀 t-값 보고
- 강건성: n_holdings 변경, 유니버스 변경, 시간 분할 변경에서 부호 유지 확인

**Gate 4: Statistical Validation** (v1.4 Ch.06 §Gate4, Ch.14):
- PASS/Near-pass 전략은 아래 검증 수행:
  - DSR (Deflated Sharpe Ratio) — §10에서 자동 계산
  - 다중 검정 보정: Harvey et al. (2016) 의식, 동일 family 시도 수 반영
- 참고: FF3/Carhart4/FF5 alpha validation은 로컬 팩터모델 구축 시 적용 예정

**Gate 5: Diversification & Redundancy** (v1.4 Ch.06 §Gate5):
- 기존 전략/포트와의 상관, 노출 유사도 확인
- 중복성 높으면 alias/variant로 처리 (fingerprint + economic_family 기준)

## 3. 장기기억 축적 규칙

### 3-A. 메모리 파일 구조
- `methodology_memory.md` — 방법론 비교 실험 결과 축적 (핵심 파일)
- `factor_taxonomy.md` — 팩터 분류 체계 + 각 팩터별 최적 처리법
- `failure_patterns.md` — 실패 패턴 축적 (L-코드 시리즈)
- `literature_insights.md` — 논문에서 추출한 핵심 인사이트

### 3-B. methodology_memory.md 기록 형식
```
## [영역] 팩터 결합 / 중립화 / 가중 / 리밸런싱 / 레짐
### 실험: {실험 제목}
- 비교: A vs B (vs C)
- 조건: {팩터 유형, 유니버스, 기간, 레짐}
- 결과: A > B (Sharpe +0.12, MDD -2.3pp, Turnover +15%)
- 통계: {IC차이 t-stat, p-value 또는 bootstrap CI}
- 근거: {논문 저자(연도), 경제적 메커니즘}
- 적용 범위: {어떤 조건에서 유효, 어떤 조건에서 무효}
- 전략 사례: STR_XXX에서 검증
```

### 3-C. 기억 품질 기준
- **조건부 기록**: "A가 최고"는 금지. 반드시 "X 조건에서 A > B" 형식
- **반증 업데이트**: 기존 기억과 모순되는 결과 발견 시 조건 세분화 또는 기존 기억 수정
- **출처 필수**: 논문 없는 경험적 발견도 축적 가능하되, "경험적, 근거 논문 미확인" 표기
- **주기적 정리**: 10개 실험 축적마다 패턴 요약 → 상위 원칙 도출

## 4. 적용 규칙

### 4-A. 기억 → 전략 적용 프로세스
1. 새 전략 구성 시 methodology_memory.md 조회
2. 현재 전략의 팩터 유형/유니버스/레짐 맥락 확인
3. 매칭되는 조건의 최적 방법론 적용
4. 매칭 조건 없으면 → 새 실험 사이클 진입
5. 적용 후 결과가 기대와 다르면 → 조건 세분화 기록

### 4-B. 점진적 고도화
- 1세대: 단순 방법론 (equal-weight, 미중립, rank blend)
- 2세대: 기억 축적 후 조건부 최적 방법론 적용
- 3세대: 레짐 조건부 + 팩터 유형별 차별화된 처리
- 세대 전환은 충분한 실험 축적(최소 20+ 비교실험) 후에만

## 5. 금지 사항 (변경 불가)

- 05_Production/ 수정 금지
- 01_Literature/ 수정 금지 (읽기 전용)
- 룩어헤드 삽입 금지
- 허들 결과 보고 후 규칙 변경 금지 (v1.4 Ch.06 §5)
- 설명 불가 전략 금지: "왜 되는지" 경제적 설명 불가하면 탈락
- MDD를 줄이기 위한 룩어헤드성 손절 규칙 삽입 금지 (v1.4 Ch.06 §5)
- 조합 폭발: 수천~수만 조합을 돌려 승자만 제출 금지 (v1.4 Ch.06 §5)
- unconstrained optimizer 금지: shrinkage cov + bounds + TO penalty 필수 (v1.4 Ch.20 §20.6)
- normalizePath() 사용 금지 (WSL 한글 경로 버그)
- 무한 재시도 금지: 원인 분류 → 수정 → 재실행
- 논문 근거 없는 임의 실험 금지 (폭주 방지)
- 데이터 외부 전송 금지 (텔레그램 브리핑 제외)

## 6. 텔레그램/리스크 감사 (운용 규칙)

- 실행 순서: run_analysis() → analysis_ic.csv → run_hurdle_gate() → 텔레그램
- 결과 발송: tg_strategy_result_with_chart() + 코멘터리 + L-코드 교훈
- 양방향: telegram_listener.py 자동 응답
- 섹터 집중도, 원샷 전략, 꼬리위험 자동 플래깅

## 7. Multi-Sleeve Portfolio — 운용 가능한 포트폴리오 구축 (v1.4 Ch.08/20)

### 핵심 원칙
Grade A = standalone 전략. Grade B = **component 전략**.
B등급은 "실패한 A"가 아니라, **다른 economic_family에서 포트폴리오 기여**를 하는 전략이다.
운용 가능한 포트폴리오는 서로 다른 팩터 패밀리의 sleeve를 결합하여 구성한다.

### Sleeve 구성 (v1.4 Ch.08 §8 orthogonal sleeves)
- 각 sleeve는 **서로 다른 economic_family**에서 선발 (Ch.19 taxonomy 기준)
- 동일 economic_family 내 sleeve는 1개만 허용 (대표 전략 선택)
- 최소 2개, 최대 4개 sleeve 권장

### 포트폴리오 구축 순서 (v1.4 Ch.20 §20.2)
1. baseline sleeves 생성 (각 family 대표 전략)
2. 중복/상쇄 노출 정리 (상관 > 0.7이면 제거)
3. **equal-vol scaling** — 각 sleeve를 동일 변동성으로 맞춤
4. baseline portfolio 결정 (1/N 또는 RP)
5. regime overlay (MRS 기반)
6. implementation overlay (TO budget, BZ)

### 등급 적용
- **개별 sleeve**: Grade A(standalone) 또는 Grade B(component) 모두 가능
- **포트폴리오 전체**: CAGR ≥ 16% + Sharpe ≥ 0.8 + MDD ≤ 45% 달성 여부로 판정
- B등급 전략도 포트폴리오 MDD/Sharpe 개선에 기여하면 **CANDIDATE 자격**

### Sleeve 후보 패밀리
| Family | 스코어링 | 현재 상태 |
|--------|---------|----------|
| defensive | IdioVol + Beta | Grade A 47개 (포화) |
| momentum | 12-1M cross-sectional | **미구축** — 최우선 |
| quality | GPA + F-Score | **미구축** |
| value | EBIT/Assets proxy | **미구축** |

### 금지 규칙
- 테스트 구간에서 sleeve 조합 선택 금지 (train/val만)
- sleeve 간 상관을 낮추기 위해 개별 전략 변형하는 행위 금지
- unconstrained optimizer 금지 (shrinkage + bounds 필수)
- 레짐: 2-4개, 소프트 확률 가중만 허용, 극단 배분(올인/올아웃) 금지

## 8. Alpha Lab — Stage 0 사전 스크리닝 (v1.4 Ch.18)

**파일**: `02_Infrastructure/alpha_lab.R`

새 팩터/gate 아이디어를 전체 백테스트(20년)에 투입하기 전에,
최근 5년 IC/ICIR로 빠르게 선별하여 무의미한 실험 90%를 차단.

### 프로세스
1. **alpha_lab_screen()**: 최근 5Y 횡단면 Rank IC 계산
2. **통과 기준**: |ICIR| ≥ 0.15 AND |t-stat| ≥ 1.5
3. PASS → 전체 백테스트 진행, FAIL → 기각 (methodology_memory.md 기록)
4. **alpha_lab_batch()**: 여러 팩터 동시 스크리닝

### 규칙
- Stage 0 통과 없이 전체 백테스트 진입 금지
- **Stage 0 PASS ≠ Production 품질** — 정식 검증(Stage 1) 가치가 있다는 뜻일 뿐 (v1.4 Ch.18 §18.5)
- Stage 0 실패해도 메모리에 기록: "X 팩터, 5Y ICIR=0.08 → 부적합"
- Alpha Lab에서 파라미터 최적화를 길게 하지 말 것 — cheap filter 용도로만 사용
- 복합 팩터는 개별 팩터 각각 Stage 0 통과 후 결합

### Sleeve-aware 탐색 규칙 (v1.4 Ch.08 반영)
비방어 팩터 패밀리(momentum, quality, value 등)의 전략은
**sleeve component 목적**으로 자연스럽게 탐색된다.
이들은 개별 Grade B여도 포트폴리오 기여가 증명되면 가치가 있다.

- 비방어 sleeve 후보는 Alpha Lab 통과 필수 (예외 없음)
- 개별 MDD 45% hard fail은 유지 — B등급으로 분류될 뿐 기각 아님
- B등급 sleeve의 포트폴리오 편입 판단은 §7 Multi-Sleeve 규칙 적용
- 기존 L-코드 "불가" 판정이 있어도 **다른 economic_family**에서는 재도전 가능
  (예: L-78 ResMom 블렌딩 금지 → 방어팩터 내. Momentum sleeve 독립 구축은 별개)

## 9. Factor Label Taxonomy — 팩터 분류 체계 (v1.4 Ch.19)

**파일**: `02_Infrastructure/strategy_registry.R`

모든 팩터에 6차원 라벨 부여 (v1.4 Ch.19 원본 기준):

| 차원 | 값 | 설명 |
|------|---|------|
| economic_family | value / momentum / quality / investment / low-risk / profitability / event / seasonality / microstructure / regime / cross-domain | 경제적 카테고리 |
| construction | raw_ratio / rank / zscore / residualized / spread / sleeve / integrated_score / overlay | 구축 방법 |
| neutrality | none / sector / beta / size / vol / multi | 중립화 수준 |
| horizon | short(<3M) / medium(3-12M) / long(>12M) | 시계열 특성 |
| capacity_bucket | low / medium / high | 투자 용량 |
| evidence_tier | A(학술+실증+재현) / B(학술 일부+초기가설) / C(가설 단계) | 학술 근거 수준 |

**label_signature** = `economic_family|construction|neutrality|horizon|capacity|evidence`
- 동일 label_signature 전략은 중복 의심 → fingerprint와 함께 이중 검사 (v1.4 Ch.17)

### 규칙
- 전략 등록 시 사용 팩터 라벨 필수
- 동일 economic_family 전략 과다 시 → ResearchOps family penalty 적용
- 라벨 기반 탐색 다양성 모니터링
- **§7 Multi-Sleeve 구성 시**: 서로 다른 economic_family 대표 sleeve 우선 채택

## 10. Statistical Defense — 다중검정 보정 (v1.4 Ch.22)

**파일**: `02_Infrastructure/statistical_defense.R`

Bailey & Lopez de Prado (2014) Deflated Sharpe Ratio.
N개 전략 시도 후 관찰된 Sharpe가 통계적으로 유의한지 검증.

### DSR 공식
```
SR_SE = sqrt((1 - skew*SR + (ekurt/4)*SR^2) / (n_obs - 1))
SR*   = E[max(Z_1,...,Z_N)] × SR_SE    (Mertens 2002)
DSR   = Φ((SR_observed - SR*) / SR_SE)
```

### 적용
- **hurdle_gate.R**: D071 진단 코드로 자동 계산 (정보성, 점수 미반영)
- DSR > 0.95 → 다중검정 보정 후에도 유의
- DSR < 0.50 → Sharpe가 순전히 우연일 가능성 높음
- **batch_dsr_audit()**: 기존 Grade A 전략 일괄 DSR 검증

### Family Trial Accounting
- `.cache/family_trial_accounting.json`: 패밀리별 시도 횟수 추적
- **update_family_trial()**: 전략 완료 시 가족 카운터 증가
- 3연속 F등급 → 패밀리 cooldown (해당 방향 탐색 중단)
- n_trials 증가 → DSR 기준 자동 엄격화

## 11. Strategy Lifecycle — 전략 생애주기 (v1.4 Ch.21)

**파일**: `02_Infrastructure/strategy_registry.R`

```
IDEA → ALPHA_LAB → RESEARCH_PASS → CANDIDATE → PAPER → PRODUCTION → WATCHLIST → RETIRED
```

| 상태 | 설명 | 전환 조건 |
|------|------|----------|
| IDEA | 가설 단계 | 경제적 논리 서술 완료 |
| ALPHA_LAB | Stage 0 스크리닝 중 | ICIR ≥ 0.15 |
| RESEARCH_PASS | 전체 백테스트 완료 | Hurdle Gate Grade B+ |
| CANDIDATE | Grade A(standalone) OR Grade B + orthogonal sleeve 가치 | 실전 투입 검토 대상 |
| PAPER | 페이퍼 트레이딩 중 | 3개월 실시간 검증 |
| PRODUCTION | 실전 운용 중 | 05_Production/ 배포 |
| WATCHLIST | 성과 감시 | 하방 알림 트리거 |
| RETIRED | 폐기 | 6개월 연속 열위 |

### Strategy Fingerprint
- `compute_fingerprint(config)`: 8자리 MD5 해시
- 동일 fingerprint = 구조적 중복 → 중복 전략 차단
- 해시 대상: universe, factor_family, rebal_freq, n_holdings, weight, risk_overlay, BZ, gate, commission

## 12. ResearchOps Priority — 연구 우선순위 (v1.4 Ch.21)

### Priority Score
```
Priority = 0.30 × Gain + 0.25 × Learning + 0.20 × Novelty
         - 0.15 × Cost - 0.10 × DependencyRisk - FamilyPenalty
```

| 항목 | 범위 | 설명 |
|------|------|------|
| Gain | 0-10 | 예상 CAGR/Sharpe 개선 폭 |
| Learning | 0-10 | 새로운 지식 기대치 |
| Novelty | 0-10 | 기존 전략 대비 차별성 |
| Cost | 0-10 | 계산/시간 비용 |
| DependencyRisk | 0-10 | 외부 데이터/인프라 의존도 |
| FamilyPenalty | 0-2 | n_trials > 5인 패밀리 감점 |

### Backlog 버킷 배분 (v1.4 Ch.16)
| 버킷 | 비율 | 설명 |
|------|------|------|
| Exploit | 35% | 기존 Grade A/B 전략 개선 (TO, risk, impl) |
| Stabilize | 30% | PASS 전략의 안정화 (OOS 검증, 파라미터 민감도) |
| Explore | 20% | 새 economic_family/알파 소스 탐색 ← **sleeve 구축 여기에 해당** |
| Diagnose | 15% | 인프라/데이터/지표/중복 이슈 해결 |

### 규칙
- Priority ≤ 0 인 실험은 기각
- 자가발전 루프에서 다음 실험 선택 시 Priority 내림차순
- 10개 실험마다 Priority 기준 + 버킷 배분 재검토
- **Explore 버킷**에서 미구축 sleeve family(momentum, quality, value) 우선 배정
