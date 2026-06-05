# data.table::shift Sign Convention Rule (Level 1)

**작성**: 2026-05-20 Cycle 51 Phase 2 (도훈 mandate B안)
**위반 = AX-002 동급** (process honesty + PIT lookahead bias 회귀)
**Root cause**: Cycle 50 발견 `02_target_builder.R` line 39 backward label bug 사후 분석

---

## 1. shift convention 4 조합

`data.table::shift(x, n, type)` semantics 정확한 해석:

| 호출 | 의미 | 결과 |
|------|------|------|
| `shift(x, n=H, type="lag")` | `x[t-H]` | **BACKWARD** (past) |
| `shift(x, n=H, type="lead")` | `x[t+H]` | **FORWARD** (future) |
| `shift(x, n=-H, type="lag")` | `x[t+H]` (sign-flip) | **FORWARD** (future) |
| **`shift(x, n=-H, type="lead")`** | **`x[t-H]` (double negation)** | **BACKWARD** (past) ⚠️ |

### 함정 (도훈 발견 2026-05-20)

```r
# WRONG (Cycle 43~49 bug):
bm[, ret_h := shift(BM_Close, -H, type="lead") / BM_Close - 1]
# 의도: forward h-day return r(t, t+h) = BM[t+H] / BM[t] - 1
# 실제: backward h-day return = BM[t-H] / BM[t] - 1 (현재가 21일 전 대비 등락률, 부호 반전)
```

`n=-H` + `type="lead"` 조합은 double negation으로 backward 작동 — **intention 모호**.
Cycle 50 fix:

```r
# CORRECT:
bm[, ret_h := shift(BM_Close, n=H, type="lead") / BM_Close - 1]
```

---

## 2. 권장 패턴

### 2.1 Forward return (label 생성, t에서 t+H 후 등락률 예측)

```r
bm[, ret_h := shift(BM_Close, n = H, type = "lead") / BM_Close - 1]
# 또는 동등:
bm[, ret_h := shift(BM_Close, n = -H, type = "lag")  / BM_Close - 1]
```

### 2.2 Backward return (history feature, t에서 t-H 후 등락률)

```r
bm[, ret_h_past := BM_Close / shift(BM_Close, n = H, type = "lag") - 1]
# 또는 동등 (sign-flip 회피 권장):
bm[, ret_h_past := BM_Close / shift(BM_Close, n = -H, type = "lead") - 1]
```

### 2.3 Lag for PIT (overlay / momentum prev-day)

```r
# t-1 lag (yesterday's value)
dt[, vol_lag := shift(vol, n = 1L, type = "lag")]
```

---

## 3. 금지 패턴 (code review block)

다음 패턴은 **intention 모호** + **현장 detection 어려움**으로 금지:

```r
# ❌ 금지 #1: negative n + "lead" (Cycle 50 bug 재발 risk)
shift(x, n = -H, type = "lead")  # double negation → 실제 BACKWARD

# ❌ 금지 #2: negative n + "lag" 명시
shift(x, n = -H, type = "lag")  # 실제 FORWARD, 의도 모호

# ✅ 권장: type만으로 방향 표시 (n은 항상 positive)
shift(x, n = H, type = "lead")  # FORWARD 명확
shift(x, n = H, type = "lag")   # BACKWARD 명확
```

---

## 4. Forward label sanity check 의무 (CI / bootstrap)

신규 forecast label 생성 시:

1. `02_Infrastructure/validation/pit_enforcement.R::validate_label_direction()` 호출 (target_df + bm_df, expected_direction = "forward")
2. `02_Infrastructure/sanity_checks/bear_date_audit.R` 호출 (4 known bear dates)
3. 두 함수 모두 PASS 후 forward label 사용 허가

`bootstrap.sh` Step 4d (또는 4e)에서 자동 실행 — `bear_date_audit.R` HARD fail 시 bootstrap 중단.

---

## 5. Cycle 50 incident 사례

### 사건 경위

- 2026-05-19 ~ 2026-05-20: Cycle 43~49 진행 중 모든 `y_tail_q15` label 기반 모델이 비정상적으로 높은 PR-AUC 산출 (0.5~0.65).
- v1.3 M2 5-way: 0.608. 이전 baseline (`bearish_forecast_v1` plan v0.4.2): PR-AUC ~0.15.
- Cycle 45B v3b_inst: 0.6417 (#1 buggy ranking) ← 발견 trigger.
- 2026-05-20 KST 21:00 무렵: Cycle 48A subagent가 `02_target_builder.R` line 39 점검 중 `shift(BM_Close, -H, type="lead")` semantics 의심.

### Forward 재baseline 결과 (Cycle 50)

| Cycle | Buggy PR-AUC | Forward PR-AUC | Δ |
|-------|--------------|----------------|---|
| v1.3 M2 Regime (5-way) | 0.608 | **0.1450** | -0.463 |
| v1.3 best M4_Bayes | ~0.63 | **0.1917** | -0.438 |
| Cycle 45B v3b_inst (#1 buggy) | **0.6417** | **0.1413** (#4 worst) | -0.500 |
| Cycle 45E PatchTST individual | ~0.45 | **0.2345** | -0.215 |

**Buggy vs Forward 정량 inversion**:
- Spearman ρ = **-0.40** (랭킹 역전)
- Cohen kappa = **-0.016** (label 거의 무관)
- COVID 2020-02-19: forward -34.05% vs backward +1.82% (label 정반대)

### Root cause analysis

`shift(x, n=-H, type="lead")` 가 R / data.table 둘 다 사용 가능한 호출 형식이라 IDE / linter도 detect 안 함. data.table semantics를 정확히 알지 못한 채 `negative + lead = 의도 forward` 라 잘못 추론.

**도훈 핵심 인사이트**: "현재 피처로 과거 예측" — 정확히 trivial concurrent classification. features와 label이 같은 시점 `BM_Close` backward window 함수 → trivial autocorrelation.

---

## 6. 위반 시 처리

1. 즉시 중단
2. 결과 무효 표시 (`STATUS_BUGGY_ERA.md` 작성)
3. 영향 영역 monitor disable (V10 / V1aV3 등)
4. fix 적용 + 재baseline + bear_date_audit PASS 후 재진입

---

## 참조

- `02_Infrastructure/sanity_checks/bear_date_audit.R` (4 known bear dates)
- `02_Infrastructure/validation/pit_enforcement.R::validate_label_direction()` (PIT v2)
- `04_Research/decision_framework/bearish_forecast_v2_alt_data/STATUS_BUGGY_ERA.md` (Cycle 51 사건 SOT)
- `.claude/rules/pit.md` C1~C15 (Level 0 PIT)
- AX-002 (process honesty)
- 후속 L-code (Cycle 51 종료 시 적립)

---

## Change log

- **2026-05-20 Cycle 51 Phase 2**: 작성 (도훈 mandate B안 — data.table::shift 함정 명문화).
