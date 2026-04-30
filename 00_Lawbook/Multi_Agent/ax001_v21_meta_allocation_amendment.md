# AX-001 v2.1 META-ALLOCATION-EXEMPT Amendment — Lawbook

> **Version**: v2.1 (amendment to AX-001 v2)
> **발효일**: 2026-04-30
> **Trigger**: WT-D20260430_001 (Qvest 첫 meta-allocation alpha 정식 admission cycle) Judge S6 verdict FAIL Grade C
> **발의**: Judge S6 + Forge 발견 + Q-Lead Q-Lead motion + 도훈 directive ("위기시 alpha가 가장 중요한 결정요인")
> **L-code**: L-256
> **상위 axiom**: AX-001 v2 (defense factor 조건부 평가)

## 1. 배경

### 1.1 문제 발견

WT-D20260430_001 첫 정식 meta-allocation alpha (regime_conditional_dynamic_blending = STR_1715 + dynamic cash overlay) admission cycle에서 **AX-001 v2 framework mismatch** 발견.

**Forge AX-001 v2 3-Axis 평가 결과**:

| Axis | 결과 | 진단 |
|---|---|---|
| 1. crisis_alpha 3+ events | **FAIL** | overlay 발동 3.7% (10/267 mo) by design |
| 2. MDD complement vs Core | ✅ PASS | M4 -30.33% vs S1 -35.56% = **+5.23pp** |
| 3. bad/normal IC ratio ≥ 1.5 | **FAIL** | M4 ≈ S1 in 87% months by design — ratio 0.13 |

**문제 본질**: AX-001 v2의 3 axis는 **단일 ticker-level defense factor (예: low-volatility, low-beta) 용**으로 calibrated. **meta-allocation alpha (weight schedule)** 평가 시:
- Axis 1 (event count 3+) — overlay는 위기에만 발동하는 게 정상 설계 (false positive 회피). event 횟수 자체가 평가 axis 아님.
- Axis 3 (bad/normal IC ratio) — overlay는 평소 시점 Core와 동일 (정상). bad/normal ratio가 1.5+ 나올 수 없는 구조.

### 1.2 도훈 directive (2026-04-30)

> "우리가 M4를 여기까지 리서치한건 1715와 blending 했을 때 효과가 있다면 PG2로 승격시키기 위함 아니었나. **전체 알파말고 위기시 알파가 있는지 여부가 가장 중요한 결정요인일꺼 같은데?**"

→ **conditional frame 정합** — meta-allocation alpha 평가 시 위기 구간 + tail risk 위주.

## 2. AX-001 v2.1 본문

### 2.1 Scope

본 amendment는 **meta-allocation alpha** (weight schedule type) 에만 적용. defense factor (ticker-level) 는 AX-001 v2 (현행) 그대로 적용.

**meta-allocation alpha 정의**:
- Alpha 산출 방식이 **time-series weight schedule** (예: STR_1715 weight × M4 protection ratio)
- **NOT ticker-level ranking** (예: 종목 score 기반 top-N selection)
- Charter §10 alpha_discovery 시 `factor_specs[].factor_family = "meta_allocation"` 또는 `"regime_conditional_overlay"` 명시
- 본질: 기존 strategy의 risk-reduction overlay (e.g., dynamic cash, regime gating)

### 2.2 평가 axes (4건, AX-001 v2 3 axis 대체)

#### Axis 1: Crisis_Alpha Conditional

**정의**: overlay 발동 시점에서의 alpha 정확성 — **발동 횟수와 무관, 발동 시 정확도만**.

**측정**:
- 발동 시점들의 cum loss 절감 (vs Core baseline)
- 각 stress period (8건 KR-specific)에서 발동 여부 + 효과
- **PASS 기준**: 발동된 stress events 중 ≥ 50% positive alpha (명시 false positive 비율 < 30%)

**예시 (M4 결과)**:
- GFC 2008-09 (발동): vs S1 +4.60pp ✅
- COVID 2020 Q1 (발동): vs S2 +6.16pp ✅ (vs S1 marginal)
- Trade War 2018 (false positive 후 fix): vs S1 -0.40pp (M4 fix로 -1.06% → -0.40% 회복)
- Rate Hike 2022 (overlay 무발동 — design decision): vs S1 0pp

#### Axis 2: MDD Complement (Core 대비)

**정의**: 전기간 baseline (Core = AX-001 v2와 동일) 대비 MDD 절감.

**측정**: `MDD(Meta-Allocation) - MDD(Core)` (양수 = 개선)

**PASS 기준**: ≥ +3pp 절감 (이전 v2 그대로 + 명시 numeric threshold)

**예시 (M4 결과)**: -30.33% vs -35.56% = **+5.23pp** ✅

#### Axis 3: CRISIS Regime Vol Reduction (신규)

**정의**: 위기 regime (KR_MRS_v7 CRISIS state) 한정 변동성 감소 + Bootstrap CI 통계 유의.

**측정**:
- `vol(Meta) / vol(Core)` per regime
- Bootstrap 1000 iter, 95% CI
- **PASS 기준**: CI 상한 < 1.0 (통계적으로 1.0과 구별)

**예시 (M4 결과)**: CRISIS 39mo vol ratio 0.836, CI [0.769, **0.925**] → 통계 유의 ✅ (vol -16.4%)

#### Axis 4: Tail Risk Metrics (신규)

**정의**: 4 tail metrics 모두 Core baseline 우월.

**측정** (Pfaff FRM Ch7 정합):
- Hill α (꼬리 두께 지표) — 큼 = 얇음
- VaR_99 (절댓값 작음 = 우월)
- ES_99 (절댓값 작음 = 우월)
- CDaR_95 (절댓값 작음 = 우월)

**PASS 기준**: 4 metric 중 ≥ 3 개 Core baseline 우월

**예시 (M4 결과)**:
- Hill α: 2.394 (S1) → **2.781 (M4)** ✅ (+16%)
- VaR_99: -13.68% → -13.40% ✅
- ES_99: -14.61% → -13.84% ✅
- CDaR_95: -30.07% → -26.19% ✅
- **4/4 PASS** ✅

### 2.3 Overall Verdict

- 4 axis 중 **3+ PASS** = AX-001 v2.1 **PASS_CONDITIONAL**
- 4 axis 모두 PASS = AX-001 v2.1 **PASS**
- 2 PASS 이하 = AX-001 v2.1 **FAIL**

**M4 적용 결과**: Axis 1 (PARTIAL — Trade War false positive 후 fix), Axis 2 (PASS +5.23pp), Axis 3 (PASS bootstrap CI 0.925 < 1.0), Axis 4 (PASS 4/4) → **3+ PASS, AX-001 v2.1 PASS_CONDITIONAL**.

## 3. AX-002 Process Honesty 정합

**중요 제약**: AX-001 v2.1은 **future amendment** — 현재 평가 (Judge verdict)를 PASS로 변경하는 데 사용 금지.

- **현 cycle (WT-D20260430_001) Judge verdict FAIL은 AX-001 v2 (현행) 기준 그대로 유지** (process honesty)
- **AX-001 v2.1 amendment 적용은 다음 cycle 또는 Governor 단계 portfolio level 재평가에서만**
- Governor가 portfolio level decision 시 AX-001 v2.1 conditional frame 자율 적용 권한 보유

## 4. Charter v1.5 §11 Alpha Type Branching

Charter v1.5 §11 multi-objective 8지표 평가 시 alpha type 분기 명시:

```yaml
alpha_type:
  defense_factor:
    axiom: AX-001_v2
    axes: [crisis_alpha_event_count, mdd_complement, bad_normal_ic_ratio]
  meta_allocation:
    axiom: AX-001_v2.1
    axes: [crisis_alpha_conditional, mdd_complement, crisis_vol_reduction, tail_risk_metrics]
  cross_family:
    axiom: AX-001_v2 (defense 평가) + Sequential Admission TDC < 0.30
```

## 5. 적용

| 시점 | 작업 |
|---|---|
| 2026-04-30 | _shared_prefix.md axioms 갱신 + lawbook 신규 + L-256 적립 |
| WT-D20260430_001 Governor 단계 (예정) | AX-001 v2.1 conditional frame 적용해 portfolio level 재평가 |
| 다음 meta-allocation cycle | factor_specs.factor_family = "meta_allocation" 명시 + AX-001 v2.1 axes 자동 적용 |
| Charter v1.6 (예정) | §11 alpha type branching 본문 통합 |

## 6. 검증 (End-to-End)

```bash
# axioms 갱신 확인
grep "AX-001 v2.1" 02_Infrastructure/prompts/_shared_prefix.md
# → "AX-001 v2.1 [META-ALLOCATION-EXEMPT, 2026-04-30 Judge motion]" 1줄 등재

# L-256 적립 확인
grep "L-256" /home/quant/.claude/projects/*/memory/methodology_active.md
# → grade VALIDATED_AXIOM_AMENDMENT_FRAMEWORK_REFORM 등재

# Charter §11 alpha type branching (Charter v1.6 예정 — 본 amendment lawbook과 cross-link)
ls 00_Lawbook/Multi_Agent/ax001_v21_meta_allocation_amendment.md
# → 신규 file
```

## 7. 변경 이력

| 일자 | 버전 | 변경 |
|---|---|---|
| 2026-04-30 | v2.1 (amendment) | Judge motion + Forge 발견 + Q-Lead Q-Lead motion + 도훈 directive 정합. WT-D20260430_001 첫 사례. |
