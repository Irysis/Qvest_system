# methodology_memory v55 Extensions — trail 필드 + L-200~L-249 신규 카테고리

**발효 일자**: 2026-04-19 (v55)
**대상 파일**: 기존 `methodology_memory.md` 확장 (단일 파일 크기 부담으로 분리 관리)
**적용 범위**: v55 신규 L-code부터 trail 필드 필수, 기존 L-001~L-164는 기본값 `trail="standard"` 자동 적용

---

## 1. 기존 L-code trail 필드 마이그레이션

**원칙**: 소급적 재태깅 없음. 기존 L-code는 모두 `trail="standard"`로 간주 (묵시적 기본값).

**예외**: 구조적으로 ML/통계/KR 특화인 L-code는 명시적 재태깅 (선택, 권장 아님):
- L-123 (ML Guard: MI prefilter 50 + daily chunk + walk-forward) → `trail="ml_empirical_first"` 명시 가능
- L-454 (한국 내부 데이터 > 글로벌 FRED) → `trail="kr_statistical"` 명시 가능
- 나머지는 재태깅 불필요

**신규 L-code (L-165+)**: 생성 시 `trail` 필드 필수.

---

## 2. 신규 L-code 카테고리 (L-200~L-249)

### 2.1 L-200~L-209: cash_allocation 교훈

**영역**: Cash sleeve 기회비용, regime-conditional cash%, drawdown psychology, 비대칭 payoff

**뼈대 (작성 대기)**:
- **L-200**: Cash sleeve regime-conditional basic (STR_CASH_v1 Grade A 근거 축적 시)
  - trail: standard
  - scope: market=KR, role=cash_allocation
  - tags: CASH_BASIC, REGIME_COND, MDD_REDUCE
  
- **L-201**: Opportunity cost threshold 설계
  - trail: standard
  - scope: cash sleeve allocation
  - tags: OPP_COST_20BPS, CASH_DRAG
  
- **L-202**: Cash weight 상한 제약 (max 35%, avg 15%)
  - trail: standard
  - scope: portfolio admission
  - tags: CASH_BOUND, CORE_PROTECT
  
- **L-203**: Crisis 구간 cash ramp-up 효과
  - trail: standard
  - scope: crisis regime MDD 방어
  - tags: CRISIS_CASH, RAMP_UP
  
- **L-204** (예약): Cash sleeve 과다 적재 시 Core alpha 희생 임계치
- **L-205** (예약): 3M rate spread 변동 시 opportunity cost 계산법
- **L-206** (예약): Cash sleeve vs Defense sleeve 병존 조건
- **L-207** (예약): Cash + Regime adaptive 결합 효과
- **L-208** (예약): Cash sleeve pairwise TDC (0 expected, 검증)
- **L-209** (예약): Cash sleeve L-156 v2 retroactive audit 면제 조건

### 2.2 L-210~L-219: regime_adaptive 교훈

**영역**: Switching alpha, signal lag, regime transition cost, stability

**뼈대**:
- **L-210**: Switching alpha 측정 기준 (conditional SR - unconditional SR > 0.10)
  - trail: ml_empirical_first (보통 regime ML 기반)
  - scope: regime_adaptive role
  - tags: SWITCH_ALPHA, REGIME_COND
  
- **L-211**: Transition cost 제어 (월간 weight 변화 × turnover impact < 50bps)
  - trail: standard
  - scope: regime adaptive rebalancing
  - tags: TRANSITION_COST, REBAL_IMPACT
  
- **L-212**: Regime signal lag 제약 (forward-looking 방지, lag ≤ 1 month)
  - trail: standard
  - scope: C11 데이터 시차
  - tags: SIGNAL_LAG, FWD_LOOK_BAN
  
- **L-213**: Stability score 36M rolling (feature importance)
  - trail: ml_empirical_first
  - scope: ML regime model
  - tags: STABILITY_36M, FEATURE_DECAY
  
- **L-214** (예약): Regime transition cost의 EWMA vs raw 비교
- **L-215** (예약): Regime_Adaptive role 신호 다중검정 (FDR)
- **L-216** (예약): Regime 분류 모델 accuracy vs Strategy alpha 상관
- **L-217** (예약): Hybrid regime (HMM + Rule-based) 효과
- **L-218** (예약): Regime break point detection (CUSUM)
- **L-219** (예약): Regime_adaptive 실패 패턴 (Session X 예정)

### 2.3 L-220~L-229: ml_predictive 교훈

**영역**: OOS decay, feature concentration, data leakage, holdout

**뼈대**:
- **L-220**: SR_OOS/SR_IS >= 0.70 threshold 근거
  - trail: ml_empirical_first
  - scope: ML model admission
  - tags: OOS_DECAY, IS_OVERFIT
  
- **L-221**: Feature concentration < 0.4 (단일 feature 지배 방지)
  - trail: ml_empirical_first
  - scope: ML interpretability + robustness
  - tags: FEATURE_CONC, DIVERSITY
  
- **L-222**: Data leakage false positive rate < 5%
  - trail: ml_empirical_first
  - scope: C1 backtest PIT
  - tags: DATA_LEAK, PIT_ML
  
- **L-223**: Holdout 12M+ 강제 (2020년 이후)
  - trail: ml_empirical_first
  - scope: OOS validation
  - tags: HOLDOUT_12M, TEMPORAL_SPLIT
  
- **L-224**: FDR 다중검정 보정 (multiple feature testing)
  - trail: ml_empirical_first + kr_statistical
  - scope: statistical defense
  - tags: FDR, HARVEY_T3
  
- **L-225** (예약): XGBoost vs LightGBM vs MLRA 비교
- **L-226** (예약): GPU 가속 시 reproducibility 이슈 (seed 고정)
- **L-227** (예약): ML feature decay over 36M monitoring
- **L-228** (예약): Black-box ML 해석성 (SHAP) 요구치
- **L-229** (예약): Post-publication decay (ML alpha 소멸 이력)

### 2.4 L-230~L-239: kr_statistical trail 특화

**영역**: 한국시장 고유 통계적 발견, 외국인 수급, 재벌, 환율, 정책, 유동성

**뼈대**:
- **L-230**: Harvey t > 3.0 + DSR + FDR 다중검정 의무화 (kr_statistical trail)
  - trail: kr_statistical
  - scope: 통계적 발견 허들
  - tags: HARVEY_T3, DSR, FDR
  
- **L-231**: 외국인 수급 팩터 (D30~D38 계열) IC 실증
  - trail: kr_statistical
  - scope: KR-specific factor
  - tags: FOREIGN_FLOW, KOSPI_LEAD
  
- **L-232**: 재벌/그룹 cascade (종목간 관계)
  - trail: kr_statistical
  - scope: KR-specific
  - tags: CHAEBOL_CASCADE, GROUP_BETA
  
- **L-233**: 원화 환율 민감도 (수출주 beta)
  - trail: kr_statistical
  - scope: FX-sensitive factors
  - tags: FX_BETA, EXPORTER_SENS
  
- **L-234**: 정책/공시 뉴스 반응 (DART 공시 감응)
  - trail: kr_statistical
  - scope: event-driven
  - tags: POLICY_SENS, DART_EVENT
  
- **L-235**: 유동성 프리미엄 (거래대금 기반 이벤트)
  - trail: kr_statistical
  - scope: micro-structure
  - tags: LIQUIDITY_PREM, TRADVAL_ANOM
  
- **L-236** (예약): 공매도 제한 구간(2023.11~2024.Q3) 가격 왜곡
- **L-237** (예약): 개인투자자 60%+ 모멘텀 과잉 효과
- **L-238** (예약): 반도체 cycle (삼성/하이닉스 20% 비중 시장 drive)
- **L-239** (예약): 재무제표 시차 (분기 45일, 연간 5월) KR-specific

### 2.5 L-240~L-249: multi-sleeve ensemble 교훈

**영역**: 5-sleeve 앙상블, pairwise correlation, regime-conditional blending

**뼈대**:
- **L-240**: 5-sleeve (Core/Div/Def/Cash/ML) pairwise TDC < 0.30
  - trail: standard
  - scope: PG2 allocation
  - tags: PAIRWISE_TDC, SEQUENTIAL_ADMIT
  
- **L-241**: Regime-conditional blending 매트릭스 (Good/Normal/Bad/Crisis)
  - trail: standard
  - scope: Blender 활성화
  - tags: REGIME_MATRIX, SLEEVE_WEIGHT
  
- **L-242**: Blender 활성화 임계 (Grade A 5건+)
  - trail: standard
  - scope: portfolio policy
  - tags: BLENDER_TRIGGER, GRADE_A_5
  
- **L-243**: EW → RP → HRP → CVaR LP 단순→복잡 순서 준수
  - trail: standard
  - scope: allocation methodology
  - tags: EW_FIRST, SIMPLE_BEFORE_COMPLEX
  
- **L-244** (예약): 5-sleeve에서 Core weight 상한 (60% 예상)
- **L-245** (예약): Defense weight regime에 따른 동적 조정 (15~35%)
- **L-246** (예약): Cash + Defense 합산 상한 (crisis 45% 초과 금지)
- **L-247** (예약): Blender LOO 검증 방법론
- **L-248** (예약): Ensemble stability (sleeve 추가/제거 시 shift)
- **L-249** (예약): Multi-sleeve L-156 v2 retroactive audit 자동화

---

## 3. L-code 작성 형식 (v55)

```markdown
### L-XXX: 교훈 제목

**trail**: standard | ml_empirical_first | kr_statistical
**scope**: market=KR, role=<6종>, family=<factor family>
**tags**: [대문자_SNAKE_CASE, 3~5개]
**core_reference**: Part A 참조번호 + 구체적 논문명
**grade**: (if applicable: A/B/C/F)

**발견**: [100~500자. 조건부 기억 필수 — "X 조건에서 A가 B보다 우월" 형식]

**적용**:
- 언제: (trigger 조건)
- 무엇을: (구체 조치)
- 피해야 할 것: (실패 패턴 회피)

**참조**:
- STR_XXX (실험 전략)
- 관련 L-code (cross-reference)
```

---

## 4. 신규 L-code 작성 체크리스트

- [ ] `trail` 필드 명시
- [ ] `scope` 필드 (role 6종 중 하나 + market/family)
- [ ] `tags` 3~5개 (SNAKE_CASE)
- [ ] `core_reference` 실질 인용 (형식적 인용 금지)
- [ ] `lesson_text` 100~500자 조건부 기억
- [ ] STR 전략 번호 참조 (실증 근거)
- [ ] 기존 L-code cross-reference (관련 있으면)

---

## 5. 참조

- 기존 `methodology_memory.md` (L-001~L-164)
- `00_Lawbook/v55_consensus_addendum.md` (trail 정의)
- `qepm/trails/trail_registry.json` (3 Trail 메타데이터)
- `qepm/schemas/strategy_registry_v55.md` (스키마)
- `00_Lawbook/admission_rule_v352.md` (role 6종 threshold)
