# Research Charter v2 — Forward Labels Baseline (Post-Cycle 51 cleanup)

**작성**: 2026-05-20 Cycle 51 Phase 3 (도훈 mandate B안)
**Supersedes**: 모든 buggy era (Cycle 43~49) 절대값 PR-AUC 기준
**Effective**: Cycle 50 forward 재baseline 적용 이후 모든 신규 cycle

---

## 1. 새 official baseline (forward 21d return label)

### 1.1 v1.3 (5-way ensemble) baseline

| Approach | Forward PR-AUC | Memo |
|----------|----------------|------|
| **v1.3 M2 Regime** | **0.1450** | 5-way ensemble (XGB / CatBoost / RF / LSTM / TFT) regime-weighted |
| **v1.3 best (M4_Bayes)** | **0.1917** | Bayesian model averaging across 5 models |
| **v1.3 best individual** | ~0.18 | XGB / CatBoost / RF / LSTM 다비 |

### 1.2 Forward leaderboard (Cycle 50 측정 — Top 3)

| Rank | Cycle | Method | Forward PR-AUC | Note |
|------|-------|--------|----------------|------|
| **#1** | **48A** | **q126 M2 long horizon (US macro 6m leading)** | **0.3079** | 신규 발견 — fix 적용 후 측정 |
| **#2** | **45E** | **PatchTST individual** | **0.2345** | Architecture 발견 (N-BEATS > LSTM > TFT 비교) |
| **#3** | **43** | **v2_2feat M4_Bayes (foreign breadth + 5d MA)** | **0.2129** | Dynamic synthesis 발견 |

### 1.3 Buggy era 무효 처리 (Cycle 43~49 절대값 PR-AUC)

| Cycle | Buggy PR-AUC | 절대값 처분 | Relative ranking 정합 |
|-------|--------------|------------|--------------------|
| 43 v1a / 5way | ~0.59~0.61 | **무효** | foreign breadth single > 추가 variants (collinearity) ✅ |
| 45B v3b_inst (#1 buggy) | 0.6417 | **무효** | inst flow 4 features alive (ranking valid, 절대값 reset) ✅ |
| 45D combined axes | ~0.6 | **무효** | M3 Hedge 45D-specific (47C cross-dataset 부정) ✅ |
| 45E architecture | ~0.45 | **무효** | N-BEATS > LSTM > TFT individual ✅ |
| 45F meta stacking | ~0.4 | **무효** | Stacking 무가치 (45F-specific) ✅ |
| 46~49 inverse/hybrid | model INCIDENTAL | **L-332/L-333 retain** (model-free trigger) | KOSPI_DD_Hybrid_V1aV3 spec 재검증 의무 |

---

## 2. 현실적 target 재설정

### 2.1 Tier-based target

| Tier | PR-AUC | 학술 기준 |
|------|--------|----------|
| **Floor** | **≥ 0.20** | v1.3 best M4_Bayes (0.1917) above. baseline 능가 의무 |
| **Standard** | **≥ 0.25** | Cycle 43 + 45E 능가. forward leaderboard #2/#3 above |
| **Stretch** | **≥ 0.30** | Cycle 48A q126 (long horizon US macro 통합) 능가 |
| **Ceiling 추정** | **0.35~0.40** | base rate 13% × 3x lift 한계 (Hand-Til 2001 max lift heuristic) |

### 2.2 PR-AUC vs PnL conversion 분리 명시

**중요 (L-332 통찰)**: PR-AUC ≠ realized return.

- **Daily PR-AUC**: bearish 분류 task. 0.20~0.35 forward = signal source quality 측정.
- **Monthly close ret 예측력**: 별도 평가 (IC, hit rate, Sharpe over benchmark) — model-free trigger (KOSPI 6m DD) 단독으로도 alpha 가능.
- **KOSPI_DD_Hybrid_V1aV3 (L-332/L-333)**: model PR-AUC 0.608 (buggy)이었음에도 **실질 trigger = KOSPI 6m DD model-free** → forward label 재baseline 후 trigger logic 재검증 의무. Strategy spec retain, model component 별도 검증.

### 2.3 Statistical significance bar

새 baseline 적용 시 Harvey-Liu-Zhu 2016 / Bailey-Lopez de Prado 2014 정합:

- **Harvey-t > 3.0** (multiple testing 보수적) for any single model claim
- **DSR (Deflated Sharpe) > 0.95 percentile** for ensemble / pipeline claim
- **Spearman ρ > 0.30** for cross-cycle ranking consistency
- **bear_date_audit.R PASS** (4/4 PASS 의무) for label semantics

---

## 3. Relative ranking — Retain VALID (architecture/family findings)

Forward label 적용 후에도 정합한 cycle 43~49 발견 (절대값 reset, ranking retain):

### 3.1 Feature family findings (relative)

| 발견 | Cycle | 정합 status |
|------|-------|------------|
| foreign breadth single feature > 추가 breadth variants | 43 | ✅ Forward retain (collinearity 본질) |
| institutional flow 4 features alive (절대값 reset) | 45B | ✅ Forward retain (feature ranking valid) |
| VKOSPI short horizon dilution | 45A | ✅ Forward retain (architecture 본질) |
| **US macro PROVEN @ q126 horizon** | **48A** | ⭐ Forward 강화 (0.3079) |
| Gaein / Kita breadth feature alive (다양화) | 45E | ✅ Forward retain |

### 3.2 Architecture findings (relative)

| 발견 | Cycle | 정합 status |
|------|-------|------------|
| **N-BEATS > LSTM > TFT individual** | 45E | ✅ Forward retain |
| PatchTST < N-BEATS (architecture) | 45E | ✅ Forward retain |
| TimeMixer < PatchTST (49B) | 49B | ✅ Forward retain |
| LASSO pruning 무가치 (48B) | 48B | ✅ Forward retain |

### 3.3 Method findings (relative)

| 발견 | Cycle | 정합 status |
|------|-------|------------|
| M3 Hedge 45D-specific (47C cross-dataset 부정) | 45D / 47C | ✅ Forward retain |
| Stacking meta-learner 무가치 (45F) | 45F | ✅ Forward retain |
| Dynamic synthesis M4_Bayes > static (43) | 43 | ✅ Forward retain |

---

## 4. 다음 cycle 권고 (forward labels 기준)

### 4.1 Highest priority — Cycle 43 + 45E 결합 (forward 재baseline)

가장 promising:
- **Cycle 43 v2_2feat foreign breadth (M4_Bayes 0.2129)** + **Cycle 45E architecture (PatchTST + N-BEATS)** 결합
- 두 cycle 모두 forward 재baseline 진행됨 + relative ranking valid
- 예상 forward PR-AUC: 0.22~0.28 (Cycle 43 base + architecture boost)
- Standard target (≥ 0.25) 달성 가능

### 4.2 High priority — Cycle 48A q126 long horizon

- US macro 6m leading horizon @ q126 (M2 Bayesian averaging) forward 0.3079
- Stretch target (≥ 0.30) 달성, 별도 sub-pipeline 가능
- 본 channel은 cycle 43/45E와 직교 (horizon dimension 별도)
- 후속 작업: q126 horizon만 standalone 평가 + 다른 cycle ensemble과 결합 가능성 평가

### 4.3 LOW priority / 재시도 부적합

- **Cycle 45B v3b_inst (buggy era #1 winner)**:
  - Forward 재baseline에서 **#4 worst** (0.1413)
  - Spearman ρ = -0.40 (랭킹 inversion)
  - 동일 feature suite 재시도는 **부적합** — 새 feature space 탐색 의무
- **Cycle 46~49 inverse betting variants**:
  - Model INCIDENTAL (L-332 finding (10))
  - Inverse betting reject (FP > TP V-shape recovery)
  - **KOSPI_DD_Hybrid_V1aV3 (L-332/L-333) trigger logic은 model-free retain** — 단 model component 재검증 의무

### 4.4 Forward research path

```
                  ┌─ Cycle 43 (foreign breadth M4_Bayes 0.2129) ──┐
   다음 cycle ────┼─ Cycle 45E (PatchTST/N-BEATS 0.2345) ─────────┼── Ensemble → Stretch 0.30+
                  └─ Cycle 48A (q126 long horizon 0.3079) ────────┘
```

---

## 5. Research integrity 의무 (Cycle 51 lesson 정합)

신규 cycle 진입 시 의무 checklist (`NEW_CYCLE_CHECKLIST.md` 참조):

- [ ] `bear_date_audit.R` 4/4 PASS (Lehman / Euro / COVID / Stagflation)
- [ ] `validate_label_direction()` ≥ 95% 일치율 PASS (PIT v2)
- [ ] PR-AUC absolute value sanity (base rate 13% × 1.5x ~ 3x range = 0.20 ~ 0.40)
- [ ] Spot check 2020-02-19 forward ret -34.05% match (`targets_full.parquet` 직접 lookup)
- [ ] Cross-cycle relative comparison 절대값 confound 회피 (Spearman ρ 검증)
- [ ] AX-008 multi-source (Forge + Codex + Architect 2/3 PASS) — admit cycle 필수
- [ ] 도훈 audit checkpoint (큰 verdict 전, paradigm shift 결정 전)

---

## 6. 참조

- **Cycle 50 incident & forward rebaseline**: `scripts/114_v1_3_rebaseline_forward.R` ~ `118_cycle50_comparative_analysis.R`
- **Buggy era 무효 공지**: `STATUS_BUGGY_ERA.md`
- **L-332 / L-333 (methodology_active.md)**: KOSPI_DD_Hybrid_V1aV3 admit-ready (model INCIDENTAL trigger)
- **L-330 / L-331**: v0.4.2 NULL RESULT + v1.0 alt data cycle 결성
- **본 폴더 README.md**: v1.0 alt data cycle SOT
- **`.claude/rules/data_table_shift_convention.md`** (Cycle 51 신규): shift convention 함정 명문화
- **`02_Infrastructure/sanity_checks/bear_date_audit.R`** (Cycle 51 신규): 4 bear date sanity check
- **`02_Infrastructure/validation/pit_enforcement.R::validate_label_direction()`** (Cycle 51 신규): PIT v2 label direction validation

학술 정통:
- Harvey-Liu-Zhu 2016: multiple testing t > 3.0
- Bailey-Lopez de Prado 2014: DSR (Deflated Sharpe Ratio)
- Lopez de Prado 2018: walk-forward + grid robustness
- Hand-Til 2001: AUC max lift heuristic
- L-332 통찰: PR-AUC ≠ realized return (model INCIDENTAL detection)

---

## Change log

- **2026-05-20 Cycle 51 Phase 3**: 작성 (도훈 mandate B안 — forward label baseline 명시 + 현실적 target tier 재설정 + relative ranking retain + 다음 cycle 권고).
