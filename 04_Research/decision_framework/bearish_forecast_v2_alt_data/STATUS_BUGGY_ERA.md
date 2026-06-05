# STATUS — Buggy Era (Cycle 43~50) Label 무효화 공지

**작성일**: 2026-05-20 KST (Cycle 51 Phase 1)
**원인**: `scripts/02_target_builder.R` line 39 backward label bug
**Severity**: CRITICAL — buggy era 모든 cycle 절대값 PR-AUC 무효
**Cycle 50 fix 적용**: line 43에 `shift(BM_Close, n=H, type="lead")` 정정

---

## 1. Bug Description

### 1.1 발견 경위

2026-05-20 KST 21:00 무렵, Cycle 48A subagent가 `scripts/02_target_builder.R` line 39 점검 중 다음 발견:

```r
# Buggy (Cycle 43~49):
bm[, ret_h := shift(BM_Close, -H, type="lead") / BM_Close - 1]
```

`data.table::shift` semantics 정확한 해석:

| 호출 | 의미 |
|------|------|
| `shift(x, n=H, type="lag")` | `x[t-H]` (BACKWARD, past) |
| `shift(x, n=H, type="lead")` | `x[t+H]` (FORWARD, future) ← 의도 |
| `shift(x, n=-H, type="lag")` | `x[t+H]` (sign flip → FORWARD) |
| **`shift(x, n=-H, type="lead")`** | **`x[t-H]` (sign flip → BACKWARD, past)** ← 실제 |

→ `n=-H` + `type="lead"` 조합은 double negation으로 BACKWARD 작동 (의도 정반대).

### 1.2 의도 vs 실제

- **의도**: forward h-day return `r(t, t+h) = BM[t+H] / BM[t] - 1`
- **실제**: backward sign-flipped `BM[t-H] / BM[t] - 1` (현재가 21일 전 대비 등락률, 부호 반전)

→ `y_tail_q15` label = "현재가 21일 전 대비 peak 상승 상태인지" 분류 task.
→ 모델은 features와 같은 시점 BM_Close backward window 함수를 분류 — **trivial concurrent classification**.

### 1.3 근거 — Forward 재baseline (Cycle 50)

Cycle 50에서 fix 적용 후 4 cycle (v1.3, 43, 45B, 45E) forward 재baseline:

| Cycle | Buggy PR-AUC | Forward PR-AUC | Δ |
|-------|--------------|----------------|---|
| v1.3 M2 Regime (5-way) | ~0.608 | **0.1450** | -0.463 |
| v1.3 best (M4_Bayes) | ~0.63 | **0.1917** | -0.438 |
| Cycle 43 v2_2feat M4_Bayes | ~0.52 | **0.2129** | -0.307 |
| Cycle 45B v3b_inst (#1 buggy) | **0.6417** | **0.1413** (#4 worst) | -0.500 |
| Cycle 45E PatchTST individual | ~0.45 | **0.2345** | -0.215 |
| Cycle 48A q126 M2 long horizon | TBD | **0.3079** | — |

**Buggy vs Forward 정량 inversion**:
- Spearman ρ = **-0.40** (랭킹 역전)
- Cohen kappa = **-0.016** (거의 무관)
- COVID 2020-02-19 case: forward -34.05% vs backward +1.82% (label 정반대)

---

## 2. Affected Cycles (절대값 PR-AUC 무효)

이 폴더 내 다음 cycle의 **절대값 PR-AUC는 무효 처리**:

| Cycle | 작업 | Buggy PR-AUC | Forward 재baseline 후 |
|-------|------|--------------|---------------------|
| 43 (v1a / 5way) | v1a comprehensive validation | ~0.59~0.61 | 재baseline 필요 |
| 45B (v3b_inst) | inst breadth suite | 0.6417 (#1 buggy) | 0.1413 (#4 worst) ⭐ |
| 45D (combined axes) | combined axes 5-way | ~0.6 | 재baseline 필요 |
| 45E (architecture) | PatchTST + N-BEATS individual | ~0.45 | 0.2345 (정합) |
| 45F (meta stacking) | meta stacking | ~0.4 | 무가치 (45F-specific) |
| 46~49 (KOSPI_DD_Hybrid) | inverse betting → hybrid spec | model PR-AUC INCIDENTAL (L-332/L-333) | 모델 fold 무관, trigger model-free |
| 50 (rebaseline) | forward baseline 측정 | — | ⭐ **FORWARD BASELINE 진입점** |

### 2.1 Relative ranking — Retain VALID (architecture/family findings)

다음 findings는 architecture/family 비교라 **forward label 적용 후에도 정합**:

- foreign breadth single feature > 추가 breadth variants (collinearity)
- institutional flow 4 features alive (forward 절대 가치 reset)
- VKOSPI / US macro short horizon dilution
- q126 horizon에서 US macro PROVEN (fix 적용 후 측정 → 진짜 valid)
- N-BEATS > LSTM / TFT individual (45E)
- PatchTST < N-BEATS architecture
- TimeMixer < PatchTST (49B)
- LASSO pruning 무가치 (48B)
- M3 Hedge 45D-specific (47C cross-dataset 부정)
- Stacking meta-learner 무가치 (45F)

### 2.2 KOSPI_DD_Hybrid_V1aV3 — Model INCIDENTAL (L-332/L-333)

L-332 발견: "model INCIDENTAL — daily PR-AUC 0.608은 진짜지만 monthly close ret 예측력 random (IC ~0). Shuffled regime test fail = 모델 정보 essential 아님. 진짜 alpha = bear_trigger (KOSPI 6m DD) 단독."

→ KOSPI_DD_Hybrid_V1aV3는 **model-free trigger** (KOSPI 6m DD ≤ -10%) 기반이므로 buggy label 무관. **단** model PR-AUC 0.608 자체는 buggy 측정값이므로 hybrid spec 내 model component 재검증 의무 (이미 model INCIDENTAL로 detect됨).

→ L-332/L-333 retain. **하지만** monitoring/deployment ready 표시 후속 cycle 재검증 의무.

---

## 3. Cycle 50 fix 적용

```r
# Fixed (Cycle 50, 2026-05-20, scripts/02_target_builder.R line 43):
bm[, ret_h := shift(BM_Close, n = H, type = "lead") / BM_Close - 1]
```

- 출력 파일: `outputs/02_targets/targets_full_forward.parquet` (신규) + `targets_full.parquet` (canonical mirror)
- 백업: `targets_full_buggy_backup.parquet` (이전 buggy 결과)

---

## 4. 새 official baseline (forward 기준)

| Tier | PR-AUC | Reference |
|------|--------|-----------|
| **v1.3 M2 Regime (5-way)** | **0.1450** | Cycle 50 forward 재baseline |
| **v1.3 best M4_Bayes** | **0.1917** | Cycle 50 forward 재baseline |
| **best individual (XGB / CatBoost / RF / LSTM 다비)** | ~0.18 | Cycle 50 |
| **Cycle 43 v2_2feat M4_Bayes** | **0.2129** | foreign breadth + 5d MA |
| **Cycle 45E PatchTST individual** | **0.2345** | architecture |
| **Cycle 48A q126 M2 long horizon** | **0.3079** | US macro 6m leading |

---

## 5. Buggy era 자료 처분 정책

| 영역 | 정책 |
|------|------|
| **`outputs/02_targets/targets_full.parquet`** | Cycle 50 forward 재baseline로 atomic replace 완료 |
| **`outputs/02_targets/targets_full_buggy_backup.parquet`** | 보존 (audit 증거용, 삭제 금지) |
| **`outputs/03_models/` cycle 43~49 결과** | 절대값 PR-AUC 무효 표시 retain, 삭제 금지 (architecture/family ranking relative comparison 유효) |
| **`outputs/04_evaluation/` JSON** | 절대값 PR-AUC 무효 표시 retain, ranking 표 forward 재baseline 후 갱신 |
| **L-332 / L-333 (methodology_active.md)** | retain — KOSPI_DD_Hybrid_V1aV3 model-free trigger 기반 + model INCIDENTAL 이미 detect (L-332 finding (10)). 후속 cycle forward 재검증 의무 표시 |
| **V10 monitor (`daily_bearish_monitor.R`)** | DISABLE Cycle 51 (morning_briefing.sh + triple_monitor.sh) |
| **V1aV3 Hybrid monitor (`live_monitor_v1av3.R`)** | DISABLE Cycle 51 (safety stop, forward 재baseline 후 결정) |

---

## 6. V10 / V1aV3 re-enable 조건 (Phase 5 future cycle 후)

다음 4 조건 ALL PASS 후 도훈 명시 mandate 시 재가동:

1. `02_Infrastructure/sanity_checks/bear_date_audit.R` 4 known bear dates PASS (Lehman 2008-09-15 / Euro 2011-08-08 / COVID 2020-02-19 / Stagflation 2022-09-26)
2. `02_Infrastructure/validation/lookahead_detector.R` (또는 `pit_enforcement.R`) `validate_label_direction()` ≥ 95% 일치율 PASS
3. AX-008 2/3 PASS (Forge + Codex + Architect)
4. 도훈 mandate 명시 재가동 결정

---

## 7. 참조

- **Cycle 50 incident report**: `outputs/04_evaluation/` (TBD by Cycle 50 작업)
- **Cycle 51 integrated report**: `CYCLE51_INTEGRATED_REPORT.md` (본 cleanup)
- **L-330 / L-331** (methodology_active.md): v0.4.2 plan + null result 적립 — bug 발견 이전 작업, plan retain
- **L-332 / L-333** (methodology_active.md): KOSPI_DD_Hybrid_V1aV3 admit-ready — model INCIDENTAL 통찰 (10)이 buggy label bug 무관 vindication
- **본 폴더 README.md**: v1.0 alt data cycle 결성 SOT (v0.4.2 NULL RESULT 후 시작)
- **상위 폴더 v1**: `04_Research/decision_framework/bearish_forecast_v1/` (v0.4.2 폐기 cycle)

---

## Change log

- **2026-05-20 Cycle 51 Phase 1**: 작성 (도훈 mandate B안 — foundational integrity recovery).
