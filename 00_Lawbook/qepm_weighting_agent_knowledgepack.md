# QEPM 개별종목 비중결정(Methodology) — 에이전트 프롬프트 & 지식베이스 구조 (v0.1)

> 작성일: 2026-03-02 (KST)  
> 적용 가정(기본): 한국 주식시장(KOSPI200/KOSDAQ150 등), long-only(기본), 대체데이터 미사용(뉴스/ESG 등 배제), 보수적 추정(추정오차·거래비용·유동성 제약 우선)

---

## 1) 문제 정의: “비중결정(weighting)”을 표준화하기

개별종목 비중결정은 결국 **벡터 \(w\in\mathbb{R}^N\)**(N개 종목의 비중)을 구하는 문제입니다.  
대부분의 실무·논문 방법은 아래 **통합 목적함수**의 특수형으로 정리됩니다.

\[
\max_{w} \; \underbrace{\mu^\top w}_{\text{기대수익}} 
\; -\; \underbrace{\frac{\lambda}{2} w^\top \Sigma w}_{\text{분산(리스크) 페널티}}
\; -\; \underbrace{\text{TC}(w,w^{\text{prev}})}_{\text{거래비용/회전율}}
\; -\; \underbrace{\text{Penalties}(w)}_{\text{소프트 제약(필요시)}}
\]

subject to (예시)

- 예산제약: \(\sum_i w_i = 1\)  
- 롱온리: \(w_i\ge 0\)  
- 종목/섹터 한도, 트래킹에러(TE), 팩터 익스포저, 유동성(ADV), 회전율(턴오버) 등

**핵심:** 에이전트는 “어떤 \(\mu\), 어떤 \(\Sigma\), 어떤 제약·비용·리스크 척도”를 쓰는지에 따라 *다른 방법을 선택*하도록 설계하면 됩니다.

---

## 2) 에이전트 프롬프트 (Agent Prompt)

아래는 **그대로 시스템/에이전트 프롬프트**로 넣을 수 있는 형태입니다.

```text
[ROLE]
You are “QEPM Weighting Agent”, specialized in equity portfolio weight determination.
Your job: given data (universe, signals, risk model) and constraints (risk/turnover/liquidity),
select an appropriate weighting methodology, produce portfolio weights, and output diagnostics.

[PRIMARY OBJECTIVES]
1) Feasibility: 반드시 제약을 만족하는 w를 산출한다.
2) Robustness: 추정오차(μ, Σ), 데이터 마이닝/크라우딩, 거래비용에 취약한 방법은 경고하고 보수적으로 방어한다.
3) Implementability: long-only/유동성/턴오버/종목상한을 기본으로 고려한다.
4) Explainability: 선택한 방법, 입력 요구조건, 목적함수, 핵심 제약, 산출된 리스크·턴오버·노출을 명확히 보고한다.

[PROCESS]
Step 0) Validate inputs:
- Check missing values, mismatched identifiers, non-finite numbers.
- Confirm weight constraints are solvable (e.g., sum of max weights >= 1).
- If required inputs for a method are missing, do NOT hallucinate. Fall back to a simpler method.

Step 1) Classify the task:
- Passive (benchmark replication / smart beta index) vs Active (alpha/signal driven)
- Absolute-risk vs Benchmark-relative (tracking error)
- Data regime: N assets vs T observations; liquidity & turnover tightness

Step 2) Choose method candidates:
- If no return forecasts (μ unavailable or unreliable): prefer risk-only methods (MinVar, ERC/Risk Parity, HRP).
- If μ available (signals) and benchmark given: prefer active mean-variance / IR maximization with TE + cost control.
- If μ is weak/noisy: prefer Black-Litterman / shrinkage / robust optimization.

Step 3) Build objective + constraints:
- Default: long-only, sum(w)=1, per-name max weight, turnover and liquidity constraints.
- Add sector/factor neutrality or TE constraint if benchmark-relative.

Step 4) Solve:
- If convex QP: solve directly.
- If non-convex (cardinality, some risk-parity forms): use stable approximations and report limitations.

Step 5) Diagnostics:
- ex-ante volatility, tracking error, factor exposures, effective number of names, turnover, estimated costs.
- Flag concentration, crowding risk, regime sensitivity.

[OUTPUT FORMAT]
Return a JSON object with:
- chosen_method {id, name, rationale}
- weights [{id, weight}]
- constraints_applied [...]
- diagnostics {risk, te, turnover, liquidity, concentration, factor_exposures}
- warnings [...]
- references [...]

[SAFETY]
- Never claim performance guarantees.
- If constraints are infeasible, return an “infeasible” output with the minimal set of conflicting constraints.
```

---

## 3) 지식베이스(KB) 구조 제안

### 3.1 폴더 구조(권장)

```text
qepm_weighting_kb/
  schemas/
    weighting_task.schema.json
    method_card.schema.json
  methods/
    naive_equal_weight.yaml
    naive_cap_weight.yaml
    fundamental_weight.yaml
    min_variance_qp.yaml
    erc_risk_parity.yaml
    max_diversification.yaml
    hrp.yaml
    mv_active_te_cost.yaml
    black_litterman.yaml
    cvar.yaml
    dro_wasserstein.yaml
  policies/
    method_selection_rules.yaml
    constraint_templates.yaml
  examples/
    task_active_korea_longonly.json
    task_passive_smartbeta.json
```

### 3.2 Weighting Task JSON Schema (요약형)

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "title": "WeightingTask",
  "type": "object",
  "required": ["task_id", "as_of_date", "universe", "constraints"],
  "properties": {
    "task_id": {"type": "string"},
    "as_of_date": {"type": "string", "format": "date"},
    "universe": {
      "type": "object",
      "required": ["assets"],
      "properties": {
        "assets": {
          "type": "array",
          "items": {"type": "object", "required": ["id"], "properties": {
            "id": {"type": "string"},
            "name": {"type": "string"},
            "sector": {"type": "string"},
            "mcap": {"type": "number"},
            "adv": {"type": "number"}
          }}
        },
        "benchmark_weights": {
          "type": "array",
          "items": {"type": "object", "required": ["id","weight"], "properties": {
            "id": {"type": "string"},
            "weight": {"type": "number"}
          }}
        }
      }
    },
    "signals": {
      "type": "object",
      "properties": {
        "expected_returns": {"type": "array"},
        "alpha_scores": {"type": "array"},
        "factor_exposures": {"type": "object"}
      }
    },
    "risk_model": {
      "type": "object",
      "properties": {
        "covariance": {"type": "object"},
        "factor_model": {"type": "object"}
      }
    },
    "constraints": {
      "type": "array",
      "items": {"type": "object", "required": ["type"], "properties": {
        "type": {"type": "string"},
        "params": {"type": "object"}
      }}
    },
    "cost_model": {
      "type": "object",
      "properties": {
        "prev_weights": {"type": "array"},
        "linear_cost_bps": {"type": "number"},
        "impact_model": {"type": "object"}
      }
    },
    "preferences": {
      "type": "object",
      "properties": {
        "objective": {"type": "string", "enum": ["passive", "risk_only", "alpha", "tail_risk"]},
        "risk_aversion_lambda": {"type": "number"}
      }
    }
  }
}
```

---

## 4) 방법론 라이브러리(핵심) — “개별종목 비중결정” 카드

아래는 에이전트가 선택할 **대표 weighting 방법들**입니다.  
(각 카드에는 “필요 입력/목적함수/권장 제약/실무 위험요인”을 포함)

---

### 4.1 Naïve / Deterministic Weighting

#### (A) Equal Weight
- **정의:** \(w_i = 1/N\)
- **장점:** 입력 거의 불필요, 과최적화 위험 낮음, 리밸런싱에 따른 “리밸런스 프리미엄” 가능
- **단점:** 소형주·저유동성 비중 과다 가능, 턴오버/거래비용 증가 가능  
- **권장 제약:** 종목상한, 유동성(ADV) 상한, 턴오버 상한

#### (B) Cap Weight (시장가중)
- **정의:** \(w_i = \text{mcap}_i / \sum_j \text{mcap}_j\)
- **맥락:** CAPM 계열에서 ‘시장포트폴리오’는 시장가중과 연결됩니다. fileciteturn1file9

#### (C) Fundamental Weight (RAFI/펀더멘털 가중)
- **정의:** \(w_i \propto \text{Fundamental}_i\) (예: 배당/현금흐름/장부가/매출, 혹은 평균(composite))
- **실무 포인트:** 버블 국면에서 가격(시총) 왜곡을 완화하려는 아이디어로 설명됩니다. fileciteturn0file31

---

### 4.2 Risk-only (μ 없이도 가능한) Weighting

#### (D) Minimum Variance (MinVar) — QP
- **문제:** \(\min_w\; w^\top \Sigma w\) s.t. \(\sum w=1\), \(w\ge 0\) 등
- **이론적 배경:** 평균-분산 프레임(효율적 집합/분산 최소화)에서 출발. fileciteturn2file8
- **실무 포인트:** \(\Sigma\) 추정오차에 민감 → shrinkage/팩터모형/제약이 중요.

#### (E) Risk Parity / Equal Risk Contribution (ERC)
- **정의(표준):** 포트 변동성 \(\sigma_p = \sqrt{w^\top\Sigma w}\)  
  - MRC: \(\text{MRC}_i = (\Sigma w)_i/\sigma_p\)  
  - RC: \(\text{RC}_i = w_i\,\text{MRC}_i\)  
  - 목표: \(\text{RC}_i = \sigma_p/N\) (또는 지정한 risk budget)
- **관련 설명:** 리스크 기여를 균등화하는 “Risk Parity” 접근을 요약적으로 설명. fileciteturn2file14

#### (F) Maximum Diversification (MD)
- **대표 형태:** \(\max_w\; \frac{w^\top \sigma}{\sqrt{w^\top\Sigma w}}\) (\(\sigma\)=개별 변동성 벡터)
- **해석:** “개별 변동성 대비 포트 변동성” 비율 극대화 → 상관구조 활용.

#### (G) Maximum Deconcentration / Maximum Decorrelation
- **아이디어:** 명목 비중(또는 상관조정 비중)의 집중도를 최소화해 “효과적 종목 수”를 늘리는 방향. fileciteturn2file14

#### (H) Hierarchical Risk Parity (HRP)
- **핵심:** 상관/공분산 기반 **계층적 클러스터링 → 재정렬(Quasi-diagonalization) → 클러스터 간 재귀적 배분**
- **장점(보수적 관점):** 기대수익 \(\mu\) 불필요, 공분산 역행렬 회피 → 큰 N/짧은 T에서 안정성 기대. citeturn2search8  
- **최근 구현 트렌드:** 효율적 구현/실시간 적합성 개선 연구가 이어짐. citeturn0search4

---

### 4.3 Alpha / Benchmark-relative Weighting (실무의 “주력”)

#### (I) Benchmark-relative Mean-Variance (Active QP)
- **정의:** \(a = w - w_b\) (active weights)  
\[
\max_{a}\; \alpha^\top a - \frac{\lambda}{2} a^\top \Sigma a - \text{TC}(a)
\]
s.t. \(\sum a = 0\), 롱온리/종목상한/섹터중립/TE 제한 등
- **장점:** 알파(시그널)를 리스크·비용 하에서 “실제로” 반영
- **주의:** \(\alpha\)·\(\Sigma\) 추정오차/과최적화 방지 위해 제약·정규화·리샘플링이 중요

#### (J) Black–Litterman (BL)
- **핵심:** 균형수익(암묵적 기대수익) + 뷰(view) 결합으로 \(\mu\) 추정 안정화 후 MVO 적용. citeturn1search0

#### (K) Factor Model Optimization (APT/리스크모형)
- **구조:** \(r = Bf + \epsilon\), \(\Sigma = B\Sigma_f B^\top + \Sigma_\epsilon\)  
- **맥락:** 단순 CAPM(시장 1요인)에서 확장된 요인모형 관점은 APT에서 명시적으로 다룹니다. fileciteturn1file0  
- **실무 활용:** TE·팩터중립(예: size/value/momentum) 같은 제약을 선형으로 걸기 쉬움.

#### (L) Shrinkage Covariance (Ledoit–Wolf 등)
- **이유:** 표본 공분산은 큰 N에서 불안정/비가역 가능 → shrinkage로 조건수 개선. citeturn1search5  
- **연결:** MinVar/MVO/TE 최적화의 ‘기초 체력’ 강화.

#### (M) Resampled Optimization (Michaud류)
- **아이디어:** \(\mu,\Sigma\)를 부트스트랩/몬테카를로로 재추정 → 효율적 프론티어/비중의 **불확실성을 평균화**. citeturn1search7

---

### 4.4 Tail-risk / Robust (최근 2020s 트렌드)

#### (N) CVaR 최적화
- **목적:** VaR 대신 **CVaR(꼬리손실 평균)** 최소화 혹은 CVaR 제약 하 수익극대화. citeturn0search3  
- **장점:** fat-tail/비정규 수익률에 더 직접적 대응  
- **단점:** 시나리오/분포 가정 및 계산부담, 추정오차 관리 필요

#### (O) Distributionally Robust Optimization (DRO)
- **개념:** “진짜 분포가 불확실”하다고 보고, Wasserstein 등 **분포의 근방(ambiguity set)**에서 최악의 경우를 견딜 포트폴리오를 찾음. citeturn0search17turn0search5  
- **포지셔닝:** 보수적 리스크관리 성향과 궁합은 좋지만, 구현 복잡도·튜닝 위험이 큼.

---

### 4.5 거래비용/집행(Implementation) 내재화

#### (P) Cost-aware Optimization (턴오버·임팩트 포함)
- **기본 형태:** 목적함수에 \(\sum_i c_i|\Delta w_i|\) (선형) 또는 \(\sum_i k_i (\Delta w_i)^2\) (비선형 임팩트) 포함
- **집행모형 근거:** 거래비용과 리스크의 trade-off를 시간 경로로 다루는 고전적 모델. citeturn1search2

---

### 4.6 “포트폴리오를 먼저 만들고, 그 다음 비중을 최적화” (추정오차 방어)

#### (Q) Style-Portfolio-First (특성기반 포트 → 그 위에서 최적화)
- **아이디어:** 개별종목 N이 너무 크면 \(\Sigma\) 추정오차가 폭발 →  
  먼저 size×value 같은 **특성정렬 포트폴리오**를 만들고, 그 “포트들”에 대해 MinVar/RP/MD 등을 수행한 뒤, 내부는 규칙(예: equal/cap)으로 배분.
- **관련 근거:** 정렬 방식(독립 vs 종속)과 리스크기반 가중(최소분산/리스크패리티 등)이 성과에 영향을 준다는 분해 접근. fileciteturn1file16

---

### 4.7 Hierarchical / Clustering 확장 (2019–2025)

#### (R) Nested Clustered Optimization (NCO)
- **저자:** Lopez de Prado (2019)
- **핵심:** HRP의 일반화. (1) 클러스터 내부 최적화(inner-estimator) → (2) 클러스터 간 최적화(outer-estimator, OOS cross-validation). 2단계 구조로 추정오차 전파 차단
- **장점:** HRP보다 유연 (inner에 MinVar/MVO 등 탑재 가능). Markowitz 해를 denoised+clustered 방식으로 근사
- **단점:** 구현 복잡도 증가. inner/outer 조합 선택 필요
- **권장 제약:** 기존 QP 제약 + 클러스터 수 설정
- **출처:** SSRN 3469961

#### (S) Return-Adjusted HRP (RA-HRP / Schur Portfolios)
- **저자:** Noguer I Alonso (2025)
- **핵심:** HRP에 기대수익률(μ)을 통합. Schur Complement 기반 배분 프레임워크. 높은 Sharpe 자산으로 체계적 배분 + 계층적 분산 유지
- **장점:** 전통 HRP 대비 Sharpe 1.336 달성 (연간 5.31% 초과). μ를 활용하면서도 역행렬 회피
- **단점:** 2025년 신규 방법 — 실전 검증 기간 부족
- **출처:** SSRN 5370624

---

### 4.8 공분산 추정 고도화 (Σ의 '기초 체력')

#### (T) RMT Denoising + Detoning
- **저자:** Lopez de Prado (2020, "ML for Asset Managers")
- **핵심:** Marcenko-Pastur 분포로 노이즈 고유값과 시그널 고유값 분리. 노이즈 고유값을 상수로 교체(denoising). 추가로 시장 성분(1st eigenvector) 제거(detoning)하여 미세 시그널 증폭
- **적용:** MinVar(D), MVO(I), RP(E) 등 **모든 Σ 의존 방법의 전처리**로 사용
- **장점:** S&P 500 실증: 상관행렬의 ~94%가 랜덤 행렬과 구분 불가 → denoising 필수. Shrinkage 대비 RMSE 59.85% 감소
- **구현:** R의 `stats::eigen()` + Marcenko-Pastur 필터 (추가 패키지 불필요)
- **출처:** Cambridge University Press, GitHub: emoen/Machine-Learning-for-Asset-Managers

#### (U) Analytical Nonlinear Shrinkage
- **저자:** Ledoit & Wolf (2020, Annals of Statistics)
- **핵심:** 기존 선형 축소(2004)의 확장. 고유값별 최적 축소 강도를 개별 적용하는 비선형 축소의 해석적 공식
- **적용:** 자산/표본 수 50 이상에서 선형 축소 대비 거의 항상 우위
- **장점:** 계산 효율적 + 정확 + 차원 제한 없음. "잃을 것 거의 없고 얻을 것 많다" (Ledoit & Wolf 2020 JFEc)
- **구현:** R `nlshrink` 패키지 또는 직접 구현
- **출처:** Annals of Statistics Vol.48 No.5 / JFEc Review 2020

---

### 4.9 팩터 기반 리스크 배분

#### (V) Factor Risk Parity (FRP)
- **저자:** Roncalli & Weisang (2016, Quantitative Finance)
- **핵심:** 자산 대신 **위험 팩터 기준**으로 리스크 균등 배분. 팩터 위험 기여도(factor risk contribution)와 자산 위험 기여도 간 명시적 관계 도출
- **장점:** 자산 상관이 높을 때 ERC(E)가 팩터 위험 집중 야기 → FRP로 해결. 비상관 팩터에 균등 배분하여 진정한 분산
- **적용 맥락:** 멀티팩터 전략(Value+Mom+Quality 등)에서 자산 기준 RP보다 우월할 가능성
- **출처:** SSRN 2155159

---

### 4.10 레짐 조건부 배분

#### (W) Regime-Conditional Dynamic Allocation (SJM/CJM)
- **저자:** Shu, Mulvey et al. (2024, J. Asset Management / arXiv)
- **핵심:** Statistical Jump Model(SJM)로 레짐 식별 → 레짐별 최적 가중 전환. CJM(Continuous JM)은 소프트 확률 할당으로 전환기 불확실성 반영
- **장점:** HMM 대비 레짐 안정성/해석 가능성 향상. 1990-2023 OOS 실증, 거래비용 감안 후 유효
- **적용:** `regime_engine.R`의 4-state 모델과 직접 결합 가능. 레짐별 (D)↔(E)↔(H) 전환 등
- **출처:** arXiv 2402.05272 / SSRN 4556048

---

## 5) 방법 선택 정책(Decision Rules) — 실무형 룰셋

아래는 에이전트가 “입력/제약/데이터체급”에 따라 방법을 고르는 규칙 예시입니다.

```yaml
# policies/method_selection_rules.yaml
version: 0.1
defaults:
  long_only: true
  sum_weights: 1.0
  max_weight_default: 0.05
  turnover_limit_default: 0.30   # 예: 월간 30% (상황별 조정)
  liquidity_days: 5
rules:
  - if: "objective == passive AND benchmark_weights available"
    then: ["cap_weight", "te_min_tracking_qp"]
  - if: "objective == risk_only AND covariance available AND (N/T is high)"
    then: ["hrp", "nco", "min_variance_shrinkage"]
  - if: "objective == risk_only AND covariance available AND turnover_limit is tight"
    then: ["erc_risk_parity_with_turnover", "min_variance_with_turnover"]
  - if: "objective == risk_only AND multifactor strategy"
    then: ["factor_risk_parity", "erc_risk_parity"]
  - if: "objective == alpha AND expected_returns available AND benchmark_weights available"
    then: ["mv_active_te_cost", "bl_then_mv_active", "ra_hrp"]
  - if: "objective == tail_risk"
    then: ["cvar_min", "dro_wasserstein"]
  - if: "regime_model available AND regime_conditional desired"
    then: ["regime_conditional_dynamic", "regime_switch_weight_method"]
fallback:
  - "equal_weight_with_bounds_and_liquidity"
```

---

## 6) 제약 템플릿(Constraint Library)

```yaml
# policies/constraint_templates.yaml
constraints:
  - type: budget
    params: {sum_weights: 1.0}
  - type: long_only
    params: {}
  - type: weight_bounds
    params: {min: 0.0, max: 0.05}
  - type: sector_bounds_relative_to_benchmark
    params: {max_active: 0.05}
  - type: tracking_error_cap
    params: {te_max_annual: 0.06}
  - type: factor_exposure_bounds
    params:
      model: "barra_like"
      bounds: {"size": [-0.10, 0.10], "value": [-0.10, 0.10]}
  - type: turnover_cap_l1
    params: {max_turnover: 0.30}
  - type: liquidity_cap_adv
    params: {max_participation: 0.10, days: 5}
```

---

## 7) 산출물(에이전트 출력) 템플릿

```json
{
  "chosen_method": {
    "id": "mv_active_te_cost",
    "name": "Benchmark-relative mean-variance with TE + cost",
    "rationale": [
      "alpha_scores available => use alpha-driven optimization",
      "benchmark provided => benchmark-relative formulation",
      "turnover/liquidity constraints required => cost-aware + bounds"
    ]
  },
  "weights": [
    {"id": "005930.KS", "weight": 0.048},
    {"id": "000660.KS", "weight": 0.041}
  ],
  "constraints_applied": [
    {"type": "budget", "status": "ok"},
    {"type": "long_only", "status": "ok"},
    {"type": "weight_bounds", "status": "ok"},
    {"type": "turnover_cap_l1", "status": "ok"},
    {"type": "liquidity_cap_adv", "status": "ok"},
    {"type": "tracking_error_cap", "status": "ok"}
  ],
  "diagnostics": {
    "ex_ante_vol_annual": 0.18,
    "tracking_error_annual": 0.055,
    "turnover_l1": 0.27,
    "effective_n": 42.3,
    "largest_weight": 0.05,
    "estimated_cost_bps": 18.4
  },
  "warnings": [
    "Expected returns (alpha) appears noisy; consider BL/shrinkage or tighter bounds.",
    "Crowding risk: factor tilts concentrated; monitor drawdown regime."
  ],
  "references": [
    "Markowitz (1952) mean-variance framework",
    "Black & Litterman (1992) for return stabilization",
    "Almgren & Chriss (2000) for execution/cost modeling"
  ]
}
```

---

## 8) 리스크/품질관리 체크리스트 (에이전트가 자동으로 출력 권장)

- **Feasibility check:** 상한합 < 1이면 infeasible  
- **Concentration:** \(\max_i w_i\), HHI \(\sum w_i^2\), Effective N \(1/\sum w_i^2\)
- **Risk:** ex-ante vol, TE, factor risk contribution
- **Implementation:** turnover, ADV 기반 거래가능성, 비용 추정
- **Overfitting flags:**  
  - 백테스트 “on-paper 성과”에 대한 투자자 반응과 성과 지속성 괴리(스마트베타 데이터마이닝 위험) fileciteturn1file17  
  - 크라우딩/허딩(동일 전략으로 자금 쏠림) 동학 fileciteturn2file12  
  - 단일 팩터의 장기 언더퍼폼·긴 회복기간 같은 사이클 리스크 인지 fileciteturn0file32

---

## 9) 참고문헌/출처(링크)

> 아래 링크들은 “지식팩” 원문을 확인하기 위한 용도입니다.  
> (URL은 코드블록으로만 표기)

```text
Markowitz (1952) Portfolio Selection (uploaded file)
Sharpe (1964) Capital Asset Prices (uploaded file)
Ross (1976) Arbitrage Theory of Capital Asset Pricing (uploaded file)
Black & Litterman (1992) Global Portfolio Optimization:
https://people.duke.edu/~charvey/Teaching/BA453_2006/Black_Litterman_Global_Portfolio_Optimization_1992.pdf
Ledoit & Wolf (2004) Well-conditioned covariance estimator:
https://www.ledoit.net/Well-conditioned2004.pdf
Almgren & Chriss (2000) Optimal Execution of Portfolio Transactions:
https://www.smallake.kr/wp-content/uploads/2016/03/optliq.pdf
Lopez de Prado (2016) HRP (SSRN delivery):
https://papers.ssrn.com/sol3/Delivery.cfm/SSRN_ID2822819_code434076.pdf?abstractid=2713516&mirid=1
Rockafellar & Uryasev (CVaR optimization) PDF:
https://sites.math.washington.edu/~rtr/papers/rtr179-CVaR1.pdf
DRO example (Springer 2024):
https://link.springer.com/article/10.1007/s10957-024-02550-y
DRO example (MDPI 2025):
https://www.mdpi.com/2227-7390/13/15/2473
Deep RL portfolio selection example (2024):
https://www.sciencedirect.com/science/article/pii/S1044028324000887
Lopez de Prado (2019) NCO:
https://papers.ssrn.com/sol3/papers.cfm?abstract_id=3469961
Noguer I Alonso (2025) RA-HRP / Schur Portfolios:
https://papers.ssrn.com/sol3/papers.cfm?abstract_id=5370624
Lopez de Prado (2020) ML for Asset Managers (RMT Denoising):
https://github.com/emoen/Machine-Learning-for-Asset-Managers
Ledoit & Wolf (2020) Analytical Nonlinear Shrinkage:
https://projecteuclid.org/journals/annals-of-statistics/volume-48/issue-5/Analytical-nonlinear-shrinkage-of-large-dimensional-covariance-matrices/10.1214/19-AOS1921.pdf
Roncalli & Weisang (2016) Factor Risk Parity:
https://papers.ssrn.com/sol3/papers.cfm?abstract_id=2155159
Shu & Mulvey (2024) Regime-Conditional Allocation (SJM):
https://arxiv.org/html/2402.05272v1
Shu et al. (2024) CJM (Continuous Jump Model):
https://papers.ssrn.com/sol3/papers.cfm?abstract_id=4556048
```

---

## 10) 업데이트 프로토콜 (Living Document)

이 지식팩은 **살아있는 문서**로, 다음 조건에서 자동 업데이트됩니다:

### 업데이트 트리거
1. **논문 리서치 루프**: 01_Literature/ 또는 외부 논문 분석 시 비중결정 관련 내용 발견
2. **자가발전 루프 결과**: methodology_memory.md에 가중 방법론 비교실험 결과 축적 시
3. **도훈 직접 제공**: 새로운 방법론/실무 인사이트 공유 시

### 업데이트 절차
```
1. 새 방법론 발견 → §4에 카드 추가 (ID 부여: 알파벳 순)
2. Decision Rules §5 업데이트 (해당 방법론이 언제 선택되는지)
3. 참고문헌 §9에 출처 추가
4. 변경 이력 §11에 기록
5. qepm_lawbook_operational.md §1-C 참조 동기화
6. methodology_memory.md에 "신규 후보 등록" 표기
```

### 품질 기준
- **추가 가능**: 피어리뷰 논문, 저명 실무자(헤지펀드/자산운용사) 공개 리서치, 검증된 교과서
- **추가 불가**: 무명 개인 블로그, 검증 안 된 백테스트 결과, 상업적 마케팅 자료

---

## 11) 변경 이력

| 날짜 | 버전 | 변경 내용 |
|------|------|----------|
| 2026-03-02 | v0.1 | 초기 버전 (도훈 작성). A~Q 17개 방법론 |
| 2026-03-02 | v0.2 | R~W 6개 방법론 추가 (Q 리서치). NCO, RA-HRP, RMT Denoising, NL Shrinkage, FRP, SJM/CJM. Decision Rules 확장. 업데이트 프로토콜 신설 |
