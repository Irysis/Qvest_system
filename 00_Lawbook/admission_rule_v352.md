<!-- FREEZE_OVERRIDE_APPROVED_BY_QLEAD=true -->
<!-- 승인 일자: 2026-04-19 -->
<!-- 승인 사유: v55 Plan (unified-tumbling-mitten) Tier 2.3 — 확장(addition) 프레이밍. 기존 v3.5.1 hard fail 유지, 신규 3종 role(cash_allocation/regime_adaptive/ml_predictive) admission threshold 추가 및 gap_misaligned veto 신설. v54 Freeze 호환: "하드 블로커 발생 시에만 Q-Lead 승인으로 수정" 규정 준수. -->

# Admission Rule v3.5.2 — Role-Specific Thresholds + Gap-Misaligned Veto + Sequential TDC

**발효 일자**: 2026-04-19 (v55)
**이전 버전**: v3.5.1 (Session 66, v54 Freeze 중 동결)
**변경 성격**: **확장(addition)** — 기존 hard fail 및 11 gates 유지, 6종 role 지원 및 gap_misaligned veto 신설
**Q-Lead 승인**: `FREEZE_OVERRIDE_APPROVED_BY_QLEAD=true` (2026-04-19)

---

## 0. v54 Freeze 호환 조항

> v54 Freeze Period (Session 68~71) 규칙: "Admission Rule 동결. 새 amendment 하드 블로커 발생 시에만 Q-Lead 승인으로 허용."
>
> **v3.5.2 적용**: **확장(addition) 규정**으로 분류. 기존 hard fail, 11 gates, Sequential Admission 로직 **모두 유지**. 신규 role 3종 지원을 위한 threshold 추가만 허용. Q-Lead 승인으로 v54 freeze 예외 처리 완료.

**유지되는 hard fail (v3.5.1 동일)**:
- `MDD > 45%` → REJECT
- `Turnover > 600%` → REJECT
- C1~C15 PIT 위반 → REJECT

---

## 1. Role-Specific Admission Thresholds (6종)

### 1.1 Core Alpha (기존 유지)
```
SR >= 0.8
CAGR >= 16%
MDD < 45%
FF5 alpha t >= 2.0
max_corr (기존 Core와) <= 0.70
```

### 1.2 Diversifier (기존 유지)
```
max_corr (portfolio 기존 전체와) <= 0.50
div_benefit (편입 시 portfolio SR 개선) > 0
IC >= 0.015
Turnover <= 200%
```

### 1.3 Defense (AX-001 v2 적용, 전면 수정)
```
multi_sleeve_only = TRUE           ← standalone 금지 (AX-005)
crisis_alpha > 0                   ← 6대 위기 구간 alpha
bad_normal_ic_ratio > 0.6          ← IC(Bad+Crisis) / IC(Good+Normal)
core_mdd_reduction >= 0.05         ← 편입 시 portfolio MDD 5% 이상 완화
전기간 SR/CAGR/MDD 적용 금지        ← AX-001 IMMUTABLE
```

### 1.4 Cash_Allocation (신규)
```
tail_risk = 0                      ← 정의상 (cash = risk-free equivalent)
opportunity_cost_bps_ann < 20      ← vs 3M rate spread
regime_conditional = TRUE          ← 고정 cash% 금지, regime 기반 동적 배분
max_cash_weight <= 0.35            ← 단일 sleeve 35% 초과 금지
avg_cash_weight <= 0.15            ← 전체 평균 15% 이하 (Core alpha 희생 방지)
```

### 1.5 Regime_Adaptive (신규)
```
switching_alpha > 0.10             ← (regime-conditional SR) - (unconditional SR)
transition_cost < 50bps            ← 월간 weight 변경 × turnover impact
regime_signal_lag <= 1 month       ← forward-looking 금지
stability_score_36M >= 0.60        ← 36개월 rolling feature importance 안정
```

### 1.6 ML_Predictive (신규)
```
SR_OOS / SR_IS >= 0.70             ← out-of-sample decay 제한
feature_concentration_max < 0.4    ← 단일 feature 지배 방지
holdout_12M_strict = TRUE          ← 2020년+ holdout 최소 12개월
trail = "ml_empirical_first"       ← trail 명시 필수
FDR_correction_applied = TRUE      ← 다중검정 보정
walk_forward_expanding = TRUE      ← L-123 ML Guard 준수
```

---

## 2. Gap-Misaligned Veto (신규)

### 목적
포트폴리오 현재 GAP(SR/MDD_regime/KR_structural/cash_efficiency)에 대응하지 않는 가설은 Governor가 veto 가능. Core 포화 상태에서 또 다른 Core 제안을 차단.

### 발동 조건
```
Governor.veto_flag = "gap_misaligned" 가능 시점:
1. 제안 전략 role = X
2. 현재 portfolio_gap_vector.json에서 role X에 대한 sleeve_needs = 0 또는 low priority
3. 더 우선순위 높은 gap_axis가 존재 (예: MDD_regime gap > 0.5)
```

### 구체 매트릭스 (2026-04-19 현재 gap 기준)

현재 GAP:
```
SR_gap             = 0.807 (높음, 최우선)
MDD_regime_gap     = ~0.5 (중간, defense 공석)
KR_structural_gap  = ~0.7 (높음, KR-specific 가설 부족)
cash_efficiency_gap = ~0.8 (매우 높음, cash sleeve 공석)
```

**veto 발동 예시**:
| 제안 role | gap_axis | veto? | 이유 |
|---------|---------|-------|------|
| core_alpha (strong SR) | SR | NO | SR gap 최우선, 허용 |
| core_alpha (weak SR < 0.5) | SR | YES | SR gap이지만 기여도 낮음 |
| diversifier | SR | NO | SR gap 기여 가능 |
| defense | MDD_regime | NO | Defense sleeve 공석, 최우선 |
| cash_allocation | cash_efficiency | NO | 공석 상태 |
| ml_predictive | KR_structural | 조건부 | Trail=ml_empirical_first인지 확인 |
| Core 포화 이후 신규 core | SR | YES | Core 슬리브 이미 5건+ |

### Veto 해제 조건
Scout이 재설계 시:
- gap_axis 명시 (gap_targeting_axes 배열)
- 왜 이 axis가 현재 최우선인지 근거 (core_reference + conditional_ic_matrix)
- 기존 포트폴리오 상관 예상치 (correlation_with_existing)

---

## 3. Sequential Admission TDC (L-156 v2 정식화)

### 배경
STR_1679v2 retroactive audit (L-156 v2) 결과: pair 간 tail dependence(TDC)가 0.50+ 시 stress 구간 drawdown 동시 발생. Sequential Admission으로 예방.

### 자동화 로직 (Governor PG2 단계)

```r
# pairwise_tdc_check() — Governor가 PG2 전에 자동 호출
# 모든 기존 sleeve 쌍 + 후보 전략의 pairwise TDC 계산

for_each_pair_with_candidate:
  tdc_crisis <- compute_tdc(returns_a, returns_b, threshold = "Crisis_regime")
  if (tdc_crisis > 0.30):
    warning: "Pair (A, candidate) TDC = {tdc_crisis} > 0.30"
    if (tdc_crisis > 0.50):
      admission_blocked: "TDC > 0.50 Sequential Admission 위반"
      recommendation: "candidate sleeve 편입 전 A 또는 candidate 재설계 필요"
```

### Threshold
```
pairwise_tdc_max = 0.30    ← 권장 상한
pairwise_tdc_block = 0.50  ← 강제 차단
```

### 측정 기준
- Crisis regime 기간만 (MRS ≥ 70 또는 과거 6대 위기 구간)
- Copula 기반 lower tail dependence (Clayton / t-copula)
- 최소 24개월 공통 기간 필요

---

## 4. 11 Gates 체크리스트 (기존 v3.5.1 유지)

### Gate 1-2: Hard Fail
- [ ] MDD ≤ 45%
- [ ] Turnover ≤ 600%

### Gate 3-4: PIT
- [ ] C1~C15 전수 통과
- [ ] lookahead_detector.R 클린

### Gate 5-6: Statistical Defense
- [ ] Harvey et al. (2016) t > 3.0
- [ ] DSR (Deflated Sharpe Ratio) 계산

### Gate 7: Role-Specific Threshold (v3.5.2 확장)
- [ ] 제안 role의 1.1~1.6 threshold 모두 PASS

### Gate 8: Anti-Pattern 13종
- [ ] 과적합 / OOS 열화 / IC 퇴화 / Mutation 미활용 등 13종 체크

### Gate 9: LOO (Leave-One-Out)
- [ ] GFC / COVID / RATE 각 기간 제외 재검증 PASS

### Gate 10: Role Honesty Audit (v55 확장)
- [ ] declared_role = detected_role
- [ ] confidence >= 0.75
- [ ] AX-001 v2 defense 조건부 평가 (defense role만)

### Gate 11: Sequential TDC (v3.5.2 확장)
- [ ] pairwise TDC < 0.30 (기존 전체 sleeve 대비)
- [ ] TDC >= 0.50 시 admission_blocked

---

## 5. Admission Decision Tree

```
Start: 후보 전략 arrives at Governor PG1
  │
  ├─ [Gate 1-2] Hard Fail 체크 → FAIL? REJECT
  │
  ├─ [Gate 3-4] PIT 체크 → FAIL? REJECT
  │
  ├─ [Gate 5-6] Harvey t/DSR → FAIL? REJECT
  │
  ├─ [Gate 7] Role-Specific Threshold
  │   └─ role=core_alpha/diversifier/defense/cash_allocation/regime_adaptive/ml_predictive
  │      각각의 1.1~1.6 threshold → FAIL? CONDITIONAL_PASS (Governor 재평가)
  │
  ├─ [Gap-Misaligned Veto] Governor 판단
  │   └─ GAP에 직접 대응하지 않으면 veto → REVISE (Scout 재설계)
  │
  ├─ [Gate 8] Anti-Pattern 13종 → FAIL? REJECT
  │
  ├─ [Gate 9] LOO → FAIL? REJECT
  │
  ├─ [Gate 10] Role Honesty Audit (v55) → FAIL? CONDITIONAL_PASS or REVISE
  │
  ├─ [Gate 11] Sequential TDC → BLOCK (TDC>0.50)? 재설계 요구
  │
  └─ ALL PASS → ADMIT → PG2 배분 단계로 진입
```

---

## 6. Conditional Pass 처리

Gate 7/10에서 CONDITIONAL_PASS 발생 시:
- Governor가 명시적 condition 기록 (예: "crisis_alpha 0.03 < 0.05, 재측정 요구")
- Forge에게 TODO_PG1_CONDITION_{STR_XXX}.json 발행
- Forge 재측정 후 재심사 (최대 2회)

Conditional 2회 실패 → REJECT.

---

## 7. v3.5.2 변경 요약 테이블

| 구분 | v3.5.1 | v3.5.2 |
|------|--------|--------|
| Role 종류 | 3종 (core/diversifier/defense) | **6종** (+cash_allocation/regime_adaptive/ml_predictive) |
| Defense 평가 | 전기간 SR/CAGR/MDD | **AX-001 v2 conditional** (multi-sleeve only) |
| Gap-Misaligned Veto | 없음 | **Governor 권한 신설** |
| Sequential TDC | L-156 v1 (수동 권고) | **자동화 (Gate 11)** |
| hard fail | MDD>45%, TO>600% | **동일 유지** |
| ML 지원 | 없음 | **ml_empirical_first trail 정식 편입** |

---

## 8. 참조

- `00_Lawbook/v55_consensus_addendum.md` (S0 Consensus + Role taxonomy 6종)
- `00_Lawbook/ax001_v2_defense_conditional.md` (Defense 조건부 평가)
- `qepm/schemas/strategy_registry_v55.md` (스키마)
- `qepm/trails/trail_registry.json` (3 Trail 메타데이터)
- `02_Infrastructure/prompts/governor_init.md` (Governor v8.0)
- `02_Infrastructure/validation/role_honesty_audit.R` (Role Honesty Audit — Tier 2.1에서 6종 확장)
- L-156 v2 (pairwise TDC retroactive audit)
