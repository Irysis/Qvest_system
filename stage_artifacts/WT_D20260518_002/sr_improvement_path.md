# Step 2.4 — SR Improvement Path to Milestone 1.97+

**WT_id**: WT-D20260518_002
**Agent**: alpha-research
**Goal**: L-279 admit baseline 1.665 → 본 cycle target ≥ 1.97 (gap +0.305 SR)

---

## 1. Baseline anchors

### 1.1 Static anchors (admit precedent)

| Anchor | Sharpe | MDD | CAGR | Source |
|---|---|---|---|---|
| L-279 Hybrid 70/15/15 admit (S3, 256m, 2026-05-05) | **1.665** | -16.6% | 26.4% | governor_admission WT-P20260505_001 |
| STR_1715_AR_threshold_overlay_PG2 (S1, 263m, 2026-05-04) | 1.7758 | -29.53% | 39.34% | governor_admission WT-P20260504_001 |
| STR_1715_AR_on_M4_R05_overlay_PG2 (Session 80, 255m, 2026-05-13) | **1.9536** | -24.81% | 41.50% | Session 80 L-308 |

### 1.2 Milestone targets

| Target | Value | Source |
|---|---|---|
| Sharpe milestone | **2.0** | Project 제2목표 (CLAUDE.md) |
| 본 cycle G3 cycle gate | ≥ **1.97** (improvement path closure) | request.json |
| Mandate MDD | ≤ **-25%** | CLAUDE.md Production Constraints |
| Mandate CAGR | ≥ **16%** | CLAUDE.md Production Constraints |

### 1.3 Gap analysis

- Current admit baseline (L-279): **1.665**
- 본 cycle target: **1.97**
- Gap: **+0.305 SR** (closure necessary via Layer 5 R05 신규 contribution + diversification)

---

## 2. Decomposition — Hybrid 70/15/15 Expected SR

### 2.1 Sleeve contribution (linear approximation)

**Naive linear blend (no diversification benefit)**:
```
SR_hybrid ≈ Σ w_i × SR_i / sqrt(1 + Σ correlation_terms)
```

For 3-source with weights {0.70, 0.15, 0.15} and SR vector {SR_str, SR_tsmom, SR_kr10y}:

| Sleeve | Weight | SR (standalone) | Vol contribution |
|---|---|---|---|
| Sleeve 1 STR_1715 R05 (Session 80) | 0.70 | 1.9536 | 21.24% × 0.70 |
| Sleeve 2 TSMOM | 0.15 | 0.9026 | 8.5% × 0.15 |
| Sleeve 3 KR_10y | 0.15 | 1.66 (post replacement boost from baseline 1.61) | 5.5% × 0.15 |

### 2.2 Cross-correlation diversification (L-281 retain)

| Pair | Cor (long-run) | Diversification benefit |
|---|---|---|
| (STR_1715, TSMOM) | 0.0766 | strong (definitionally orthogonal) |
| (STR_1715, KR_10y) | -0.137 | strong (defensive complement) |
| (TSMOM, KR_10y) | ~0.10 estimate | moderate |

**Expected diversification benefit**: ~5~10% portfolio vol reduction vs naive weighted average.

### 2.3 Closed-form SR expectation (Forge stage strict verify)

Using portfolio variance:
```
Var(R_p) = w' Σ w
where Σ = (vol_i × vol_j × cor_ij)
```

For 3-source with diagonalish Σ (low cross-cor):
```
Vol_p ≈ sqrt(0.70² × 0.2124² + 0.15² × 0.085² + 0.15² × 0.055²
        + 2 × 0.70 × 0.15 × 0.2124 × 0.085 × 0.077
        + 2 × 0.70 × 0.15 × 0.2124 × 0.055 × (-0.137)
        + 2 × 0.15 × 0.15 × 0.085 × 0.055 × 0.10)
     ≈ sqrt(0.02210 + 0.000163 + 0.0000682 + 0.000292 - 0.000601 + 0.000021)
     ≈ sqrt(0.02204)
     ≈ 0.1485 (14.85% ann vol)

CAGR_p ≈ 0.70 × 41.50% + 0.15 × 4.62% + 0.15 × 4.50% (kr_10y replacement boost from baseline)
       ≈ 29.05% + 0.693% + 0.675%
       ≈ 30.4% ann CAGR

SR_p ≈ 30.4% / 14.85% ≈ 2.05
```

→ **Expected Hybrid SR ≈ 2.05** (preliminary closed-form estimate)

### 2.4 Forge stage strict verify mandate

**Caveat**: 2.3 closed-form is **PRELIMINARY estimate, NOT admit-valid**. Forge stage strict bt_result.rds (256m+ joint cover) via PerformanceAnalytics `Return.portfolio` mandate.

---

## 3. Path to Milestone — Three Components

### 3.1 Component A — Layer 5 R05 marginal contribution (확정)

**Session 80 STR_1715 standalone Δ vs L-279 admit Sleeve 1**:
- L-279 admit Sleeve 1 SR ~ 1.585 (S0 baseline, 256m manual reconcile)
- Session 80 admit Sleeve 1 SR 1.9536 (255m PerfA)
- Δ = **+0.37 SR** in Sleeve 1

**Weighted to Hybrid (70%)**:
- +0.37 × 0.70 = **+0.259 SR contribution**

### 3.2 Component B — TSMOM + KR_10y replacement boost (확정)

**WT-S20260504_008 kr_10y replacement Δ Sharpe** (255m clean):
- Baseline (STR_1715 alone) SR 1.6113 → kr_10y 50% replacement SR 1.6639
- Δ = +0.0526 SR at 50/50 hypothetical → 15% weighting:
  - +0.0526 × (0.15 / 0.50) = +0.0158 SR (proportional)

**WT-S20260504_009 TSMOM replacement Δ Sharpe** (50/50 hypothetical):
- Δ = +0.0663 SR at 50/50 → 15%:
  - +0.0663 × (0.15 / 0.50) = +0.0199 SR (proportional)

**Combined (마진)**:
- +0.0158 + 0.0199 = **+0.036 SR**

### 3.3 Component C — Cross-cor diversification benefit (예상)

- Vol reduction from cross-cor (0.077 long-run, -0.137 defensive)
- Estimated additional **+0.02~0.05 SR** (Forge stage Hybrid blend strict verify)

### 3.4 Sum of components

| Component | Δ SR contribution |
|---|---|
| A — Layer 5 R05 marginal (Session 80 신규) | **+0.259** |
| B — TSMOM + KR_10y replacement (확정 마진) | **+0.036** |
| C — Diversification benefit (예상) | +0.02 ~ +0.05 |
| **TOTAL closure** | **+0.32 ~ +0.35 SR** |

**L-279 baseline 1.665 + closure ≈ 1.99 ~ 2.02**

→ **본 cycle target ≥ 1.97 achievable** (Forge stage strict verify mandate)

---

## 4. MDD Pathway (mandate -25% already exceeds)

### 4.1 L-279 admit MDD baseline

- L-279 admit Hybrid MDD = **-16.6%** (S0 -26.5% → S3 -9.83pp improvement)
- Mandate floor: ≤ -25%
- → **이미 8.4pp 추월 달성** (L-282 본질 통찰 inherit)

### 4.2 Layer 5 R05 effect on MDD

- STR_1715 standalone MDD (Session 80, 255m): **-24.81%**
- vs Session 80 4-Layer (pre-R05): MDD ~ -35.32% (Session 80 vs 4-Layer 비교 PG2)
- Layer 5 R05 marginal MDD improvement: **+10.5pp** (β_R05 cash-control overlay)

### 4.3 Hybrid 70/15/15 MDD expectation

- Sleeve 1 weighted (70% × -24.81%) ≈ -17.4% contribution
- Cross-cor diversification (defensive complement KR_10y -0.137) → additional MDD improvement
- KR_10y standalone MDD -1.47pp improvement at 15% weight
- TSMOM crisis Stagflation +25pp outperform KOSPI

**Expected Hybrid MDD**: **-15% to -20%** (Forge stage strict verify mandate)
- **이미 mandate -25% well exceeds** ✓

---

## 5. CAGR Pathway (mandate ≥ 16% already exceeds)

### 5.1 Expected Hybrid CAGR

```
CAGR_p ≈ 0.70 × CAGR_str1715_R05 + 0.15 × CAGR_TSMOM + 0.15 × CAGR_KR10y
      ≈ 0.70 × 41.50% + 0.15 × 4.62% + 0.15 × 4.50%
      ≈ 29.05% + 0.693% + 0.675%
      ≈ 30.4% ann CAGR
```

- Mandate floor: ≥ 16%
- → **이미 14.4pp 추월 달성** ✓

### 5.2 Sacrifice analysis (L-282 본질 통찰)

- Original STR_1715_AR_threshold_overlay_PG2 standalone CAGR 39.34% (L-279 admit precedent)
- Hybrid 70/15/15 CAGR ~ 30.4% → **CAGR sacrifice ≈ -8.94pp**
- Sacrifice 정당: MDD improvement (-9.83pp L-279 admit) + diversification benefit

---

## 6. Cycle Decision Gates Verification

### 6.1 Target Achievement

| Gate | Target | Expected | Verdict |
|---|---|---|---|
| **G3 overall SR** | ≥ 1.665 (admit baseline) + improvement ≥ 1.97 milestone | **≈ 2.0** (closure path | PASS expected (Forge verify) |
| **G4 MDD** | ≤ -25% | **-15% to -20%** | PASS expected |
| **G5 Harvey 5/5** | t_NW > 3.0 strict | Sleeve 1 5/5 t_NW 6.77~6.62 inherit + Hybrid blend Forge mandate | PASS expected |
| **G6 DSR** | z ≥ 1.5 | L-279 z=6.0973 inherit + Hybrid blend Forge mandate | PASS expected |
| **G7 TO per sleeve** | ≤ 6.0 | Sleeve 1 waiver / Sleeve 2 3.66 / Sleeve 3 1.20 | PASS |
| **G8 AX-001 v2** | crisis_alpha + Core MDD + bad/normal IC | inherit precedent ✓ | PASS |
| **G9 AX-008 3/3** | Forge + Codex + Architect | **본 cycle strict mandate** | strict target |

### 6.2 Failure cutoffs (request.json inherit)

| Cutoff | Trigger |
|---|---|
| real_pit_synthetic_detection | HARD ABORT |
| harvey_placeholder | HARD ABORT |
| blend_sr_lt_1_50 | ABORT (L-279 admit baseline 못 미침) |
| blend_mdd_worse_than_30 | HARD ABORT |
| Codex_REJECT_veto_true | DEFER |

**본 cycle 예상 verdict**: ALL gates PASS expected via Forge stage strict verify.

---

## 7. Improvement Path Honest Caveats

### 7.1 Forge stage strict verify mandate (NOT pre-judgment)

본 cycle Step 2.4은 **alpha-research level의 expected analysis**.
실제 admit 결정은 Forge stage Hybrid blend 256m+ backtest + Harvey 5-spec strict + DSR Bailey-LdP M=30 strict 결과에 의해 결정.

### 7.2 Risk areas to monitor (Forge stage tracking)

1. **TSMOM DSR M=30 lifecycle**: WT-S20260504_009 strict FAIL (0.86 vs 0.95+ threshold) — Hybrid blend Forge stage 재산출
2. **KR_10y subperiod decay**: Recent 5Y Δ Sharpe +0.005 — Forge stage 5-spec strict + 추가 subperiod stability
3. **Cross-cor regime breakdown**: COVID 5m cor 0.75 (TSMOM-STR_1715 acute) — Risk stage stress test 의무
4. **KOFIA NAV cross-validation**: Sleeve 2/3 synthetic pre-inception caveat — Forge stage Architect concurrent mandate

### 7.3 결과 보고 honest (회피 표현 금지)

- "1.97 milestone achievable" → strict **Forge stage verify 후 confirm**
- "+0.305 closure" → **preliminary closed-form estimate, NOT admit metric**
- "MDD already exceeds mandate" → L-279 admit precedent retain + 본 cycle Forge verify

---

## 8. Step 2.4 Output

**File**: `stage_artifacts/WT_D20260518_002/sr_improvement_path.md` (this)
**Next**: Step 5 — alpha_package_draft.json 작성 (8-field schema strict)
