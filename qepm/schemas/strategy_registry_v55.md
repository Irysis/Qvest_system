# Strategy Registry v55 Schema Extension

**적용 시점**: 2026-04-19 (v55)
**대상 파일**: `06_Registry/strategy_registry.json`
**마이그레이션 방침**: 기존 1800+건은 점진적. 신규 전략부터 v55 필드 필수.

---

## 신규 추가 필드

### 1. role (확장)

**기존 3종**: `core_alpha` / `diversifier` / `defense`

**v55 확장 6종**:
```json
"role": "core_alpha" | "diversifier" | "defense" | "cash_allocation" | "regime_adaptive" | "ml_predictive"
```

### 2. trail (신규 필수)

```json
"trail": "standard" | "ml_empirical_first" | "kr_statistical"
```

**기본값 (마이그레이션)**: 기존 전략은 `trail = "standard"` 자동 적용.

### 3. cash_component (cash_allocation role 전용)

```json
"cash_component": null | {
  "uses_cash_signal": true,
  "max_cash_weight": 0.30,
  "regime_conditional": {
    "Good": 0.0,
    "Normal": 0.05,
    "Bad": 0.15,
    "Crisis": 0.30
  },
  "opportunity_cost_basis": "3M_rates"
}
```

### 4. gap_targeting_axes (신규 필수)

```json
"gap_targeting_axes": ["SR", "MDD_regime", "KR_structural", "cash_efficiency"]
```

배열, 1+ 원소. 4축 정의는 `v55_consensus_addendum.md` §4 참조.

### 5. role_honesty_audit (S6 검증 결과, 자동 생성)

```json
"role_honesty_audit": {
  "declared_role": "defense",
  "detected_role": "defense",
  "confidence": 0.87,
  "violations": [],
  "audit_date": "2026-04-19",
  "crisis_alpha_test": true,
  "bad_normal_ic_ratio": 0.65,
  "core_mdd_reduction": 0.08
}
```

### 6. consensus_stance (S6 판정, 점수제 대체)

```json
"consensus_stance": "SUPPORT" | "VETO" | "UNRESOLVED"
```

### 7. unresolved_disputes (S0→S1 승격 gate)

```json
"unresolved_disputes": [
  "walk_forward_stability_unproven",
  "ic_to_return_coupling_untested"
]
```

S1 단계에서 실측 의무. 해당 항목 통과 전까지 Grade 결정 유보.

---

## 기존 필드 (유지)

- `id` (STR_XXXX)
- `family` (Value/Quality/Momentum/Defense/Illiquidity 등)
- `grade` (A/B/C/F)
- `grade_v21` (하위호환 유지)
- `RoleBias` (role_honesty_audit이 주 필드, RoleBias는 legacy)

---

## 마이그레이션 체크리스트

### 신규 전략 (v55 이후)
- [ ] role 6종 중 하나
- [ ] trail 3종 중 하나 (기본 standard)
- [ ] gap_targeting_axes 배열 (1+)
- [ ] cash_component (role=cash_allocation이면 필수)
- [ ] role_honesty_audit (S6 완료 시 자동 주입)

### 기존 전략 (1800+건)
- [ ] trail = "standard" 기본값 자동 주입
- [ ] role 변환 불필요 (기존 3종 값 유지)
- [ ] gap_targeting_axes 수동 입력 권장 (신규 연구 시)
- [ ] role_honesty_audit은 재심사 시 주입

---

## Validation

`artifact_validator.sh`가 다음을 검증:
- 신규 s0_record 파일: 6개 필수 필드 검증
- 누락 시 `{FILE}.missing_v55_fields` 접미사로 격리 + block
