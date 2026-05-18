# DPL_KR_v3 Sub-Period Stability Protocol — 3 Macro Sub-Periods + 13 Walk-Forward

**WT-D20260519_001 · alpha-research Mandate Extension**
**Date**: 2026-05-18
**Author**: alpha-research agent (autonomous)
**도훈 mandate 2026-05-19**: Sub-period stability extended (3 macro sub-periods × walk-forward extended)

---

## 1. Three Macro Sub-Periods

| # | Sub-period | Years | Era Characteristics | Key Events |
|---|---|---|---|---|
| **P1** | **Emerging Era** | 1990-2005 | Post-IMF emerging market, KRW liberalization, chaebol restructuring | IMF 1997, Dot-com 2000-02, China entry to WTO 2001 |
| **P2** | **Mid-Cycle Era** | 2005-2015 | Globalization peak, GFC, EU crisis, China A-share rise | GFC 2008, EU 2011-12, China A 2015 |
| **P3** | **Modern Era** | 2015-2026 | Mature market, ML adoption, COVID, inflation | Vol Mag 2018, COVID 2020, Inflation 2022 |

---

## 2. Sub-Period Stability Metrics

### 2.1 Per Sub-Period Aggregation

For each sub-period (P1, P2, P3):
- **median_SR**: per-window median Sharpe within sub-period
- **median_IC**: per-sig_date median rank IC within sub-period
- **median_HHI**: per-sig_date median Herfindahl within sub-period
- **median_TO_annual**: per-sig_date median annualized turnover
- **n_windows_in_subperiod**: walk-forward window count
- **n_test_months_in_subperiod**: total test months

### 2.2 Sub-Period Stability Gate (G3 NEW)

**Pass criteria** (≥ 2 of 3 PASS):
- **IC stability**: |IC_P1 - IC_P2| ≤ 0.05 AND |IC_P2 - IC_P3| ≤ 0.05 (≥ 50% of average IC)
- **SR stability**: |SR_P1 - SR_P2| ≤ 0.5 AND |SR_P2 - SR_P3| ≤ 0.5
- **HHI stability**: HHI > 0.06 in all 3 sub-periods (G7 satisfied per-sub-period)

**Failure**:
- < 2/3 stability metrics → G3 FAIL (regime-specific overfitting)

---

## 3. Sub-Period Walk-Forward Window Mapping

### 3.1 P1 Emerging Era (1990-2005)

Walk-forward windows with test in P1:
- Window 1: test 2001-01 ~ 2002-12 (Dot-com test) — 24m
- Window 2: test 2003-01 ~ 2004-12 — 24m
- Window 3: test 2005-01 ~ 2006-12 (partial in P1, partial in P2 boundary)

**n_windows_P1**: 2 full + 1 boundary = 2.5 effective windows
**n_test_months_P1**: ~60 months

### 3.2 P2 Mid-Cycle Era (2005-2015)

Walk-forward windows with test in P2:
- Window 3: test 2005-01 ~ 2006-12 (partial in P2)
- Window 4: test 2007-01 ~ 2008-12 (GFC) — 24m
- Window 5: test 2009-01 ~ 2010-12 — 24m
- Window 6: test 2011-01 ~ 2012-12 (EU) — 24m
- Window 7: test 2013-01 ~ 2014-12 — 24m
- Window 8: test 2015-01 ~ 2016-12 (boundary P2-P3) — 24m

**n_windows_P2**: 5 full = 5 effective windows
**n_test_months_P2**: ~120 months

### 3.3 P3 Modern Era (2015-2026)

Walk-forward windows with test in P3:
- Window 8: test 2015-01 ~ 2016-12 (partial in P3)
- Window 9: test 2017-01 ~ 2018-12 (Vol Mag) — 24m
- Window 10: test 2019-01 ~ 2020-12 (COVID) — 24m
- Window 11: test 2021-01 ~ 2022-12 (Inflation) — 24m
- Window 12: test 2023-01 ~ 2024-12 — 24m
- Window 13: test 2025-01 ~ 2026-04 — 16m

**n_windows_P3**: 5 full + 1 partial = 5.5 effective windows
**n_test_months_P3**: ~124 months

---

## 4. Sub-Period Comparison Schema

### 4.1 Per-Sub-Period Report (Forge cycle)

```json
{
  "sub_period": "P1_emerging_1990_2005",
  "n_windows": 2.5,
  "n_test_months": 60,
  "median_test_sharpe": 0.8,
  "median_test_mdd": -0.32,
  "median_rank_ic": 0.025,
  "median_icir": 0.18,
  "median_hhi": 0.085,
  "median_to_annual": 5.8,
  "n_crisis_windows": 1,
  "crisis_alpha_pp": 8.2
}
```

### 4.2 Cross-Sub-Period Stability Computation

```r
# Per sub-period aggregation
P1_stats <- compute_sub_period_stats(forge_outputs, period="1990-2005")
P2_stats <- compute_sub_period_stats(forge_outputs, period="2005-2015")
P3_stats <- compute_sub_period_stats(forge_outputs, period="2015-2026")

# Stability metrics
ic_p1p2_diff <- abs(P1_stats$median_rank_ic - P2_stats$median_rank_ic)
ic_p2p3_diff <- abs(P2_stats$median_rank_ic - P3_stats$median_rank_ic)
sr_p1p2_diff <- abs(P1_stats$median_test_sharpe - P2_stats$median_test_sharpe)
sr_p2p3_diff <- abs(P2_stats$median_test_sharpe - P3_stats$median_test_sharpe)

ic_stability <- ic_p1p2_diff <= 0.05 && ic_p2p3_diff <= 0.05
sr_stability <- sr_p1p2_diff <= 0.5 && sr_p2p3_diff <= 0.5
hhi_stability <- P1_stats$median_hhi > 0.06 && P2_stats$median_hhi > 0.06 && P3_stats$median_hhi > 0.06

g3_pass_count <- sum(ic_stability, sr_stability, hhi_stability)
g3_pass <- g3_pass_count >= 2
```

---

## 5. Regime Aware Considerations

### 5.1 P1 (1990-2005) Emerging Regime

**Characteristics**:
- High volatility (post-IMF)
- Lower liquidity (smaller universe ~200-400 stocks)
- Foreign ownership restrictions (until 1998)
- Higher concentration (chaebol-dominated)

**Expected DPL_v3 behavior**:
- Higher HHI (smaller universe → larger HHI naturally)
- More volatile IC (regime drift)
- Cross-section signals weaker (less efficient market)

### 5.2 P2 (2005-2015) Mid-Cycle Regime

**Characteristics**:
- Global financial crisis & recovery
- KRW free-floating
- KOSPI200 institutional adoption
- KOSDAQ growth + tech sector

**Expected DPL_v3 behavior**:
- Mid-range HHI (~0.07-0.10)
- Moderate IC stability
- Crisis robustness test (GFC test window)

### 5.3 P3 (2015-2026) Modern Regime

**Characteristics**:
- Mature market (KOSPI200 + KOSDAQ150 stable)
- Foreign institutional ownership ~40%
- ML/quantitative adoption (incl. retail HFT)
- COVID + Inflation cycle

**Expected DPL_v3 behavior**:
- Stable HHI (~0.08-0.10)
- Lower IC (more efficient market, alpha decay)
- Higher cor risk with established factor strategies (STR_1715, etc.)

### 5.4 Regime Heterogeneity Honest Acknowledgment

**Risk**: IC and SR may differ substantially across P1, P2, P3:
- P1 IC may be higher (less efficient market) but more volatile
- P3 IC may be lower (more efficient) but more stable
- Direct |IC_P1 - IC_P3| comparison may fail stability gate, BUT may reflect genuine regime difference, not overfitting

**Mitigation**:
- G3 stability gate: 2 of 3 PASS (not 3 of 3)
- Relaxed thresholds (0.05 IC diff, 0.5 SR diff)
- Per-sub-period reporting (transparency, not single aggregate)

---

## 6. Sub-Period Stability vs Walk-Forward Stability

**Two complementary measures**:

### 6.1 Within-Sub-Period Walk-Forward Stability (CF-A3 inherit)

- Between-window IC correlation within P1 (between Window 1, 2)
- Between-window IC correlation within P2 (between Window 3, 4, 5, 6, 7, 8)
- Between-window IC correlation within P3 (between Window 8, 9, 10, 11, 12, 13)
- Target: ≥ 0.5 per sub-period

### 6.2 Cross-Sub-Period Stability (G3 NEW)

- Aggregated IC / SR / HHI difference between sub-periods
- Target: 2 of 3 metrics pass (loose)

**Together**: walk-forward stability + sub-period stability provide robustness assessment.

---

## 7. Reporting Schema (Forge cycle)

### 7.1 sub_period_stability_report.json

```json
{
  "task_id": "WT-D20260519_001",
  "report_at": "Forge cycle post-train",
  "P1_emerging_1990_2005": {
    "n_windows": 2.5,
    "n_test_months": 60,
    "median_sharpe": null,
    "median_rank_ic": null,
    "median_icir": null,
    "median_hhi": null,
    "median_to_annual": null
  },
  "P2_mid_cycle_2005_2015": {
    "n_windows": 5,
    "n_test_months": 120,
    "median_sharpe": null,
    "median_rank_ic": null,
    "median_icir": null,
    "median_hhi": null,
    "median_to_annual": null
  },
  "P3_modern_2015_2026": {
    "n_windows": 5.5,
    "n_test_months": 124,
    "median_sharpe": null,
    "median_rank_ic": null,
    "median_icir": null,
    "median_hhi": null,
    "median_to_annual": null
  },
  "cross_sub_period_stability": {
    "ic_p1p2_diff": null,
    "ic_p2p3_diff": null,
    "ic_stability_pass": null,
    "sr_p1p2_diff": null,
    "sr_p2p3_diff": null,
    "sr_stability_pass": null,
    "hhi_stability_pass": null,
    "g3_pass_count": null,
    "g3_status": null
  }
}
```

### 7.2 Within-Sub-Period Walk-Forward Stability

```json
{
  "within_P1": {
    "windows": [1, 2],
    "between_window_ic_corr": null
  },
  "within_P2": {
    "windows": [3, 4, 5, 6, 7, 8],
    "between_window_ic_corr": null
  },
  "within_P3": {
    "windows": [8, 9, 10, 11, 12, 13],
    "between_window_ic_corr": null
  }
}
```

---

## 8. Failure Modes and Diagnostics

### 8.1 P1 Significantly Worse than P2/P3

**Diagnosis**: Likely emerging-market regime mismatch + smaller universe + chaebol concentration

**Action**:
- If P1 IC < 0 but P2, P3 PASS → P1 regime exclude, train on P2+P3 only
- If P1 OK but P2/P3 differ substantially → regime-specific issue

### 8.2 P3 Significantly Worse than P1/P2

**Diagnosis**: Likely alpha decay + market efficiency increase + factor crowding (recent)

**Action**:
- Risk: substitution candidate quality erosion over time
- Mitigation: report decay rate transparency
- If P3 < 0.5 SR → 4th source candidate (cor < 0.3) is more realistic than substitution

### 8.3 All 3 Sub-Periods Stable but Low

**Diagnosis**: Consistent but weak alpha generator

**Action**:
- 4th source candidate (cor < 0.3) acceptable target
- Substitution unrealistic

### 8.4 Volatile / Unstable Across All Sub-Periods

**Diagnosis**: Regime-overfitting OR architecture instability

**Action**:
- Forge ABORT
- v3.1 redesign

---

## 9. Mandate Compliance

**도훈 mandate 2026-05-19 requirements**:
- ✅ 3 sub-period (1990-2005, 2005-2015, 2015-2026) defined
- ✅ Per-sub-period reporting schema (Forge cycle obligation)
- ✅ Cross-sub-period stability gate (G3 NEW)
- ✅ Within-sub-period walk-forward stability (CF-A3 retain)
- ✅ Regime-aware caveats acknowledged honestly
- ✅ Sub-period failure mode diagnostics enumerated

---

## 10. Updated Decision Gates Final

| Gate | Threshold | Source |
|---|---|---|
| G0 | PIT C1~C15 PASS | admission_protocol_v3.md §1.1 |
| G1 | DPL_v3 SR ≥ 1.0 (304 test months) | admission_protocol_v3.md §1.2 + historical_coverage_audit_v3.md §7.3 |
| G2 | cor < 0.3 / 0.5 vs STR_1715 (same-period overlap) | admission_protocol_v3.md §1.3 + historical_coverage_audit_v3.md §7.4 |
| G3 | Sub-period stability ≥ 2/3 metrics (1990-2005, 2005-2015, 2015-2026) | **NEW per 도훈 mandate 2026-05-19 + sub_period_stability_protocol_v3.md §2.2** |
| G3' | Crisis-conditional ≥ 5/7 explicit test windows | **NEW per 도훈 mandate 2026-05-19 + crisis_sample_inclusion_v3.md §3.2** |
| G3_legacy | Harvey-t ≥ 3.0 5-spec genuine ≥ 3 | admission_protocol_v3.md §1.4 (RENAME from G3 → G3_legacy due to G3/G3' new) |
| G4 | DSR Bailey-LdP Z ≥ 1.5 strict, n_trials=100 PRE-REGISTERED (v3 Codex C7 AMENDMENT) | admission_protocol_v3.md §1.5 |
| G5 | Cost Pareto vs STR_1715 | admission_protocol_v3.md §1.6 |
| G6 | AX-008 ≥ 2/3 | admission_protocol_v3.md §1.7 |
| G7 | HHI > 0.06 strict majority sig_dates | admission_protocol_v3.md §1.8 |

**Note**: G3 has been used for both Harvey-t AND sub-period stability. Renaming for clarity:
- **G3 (NEW)**: Sub-period stability ≥ 2/3 metrics
- **G3'** (NEW): Crisis-conditional ≥ 5/7
- **G3_legacy → G_Harvey**: Harvey-t ≥ 3.0 5-spec genuine ≥ 3

Total decision gates: G0, G1, G2, G3, G3', G_Harvey, G4, G5, G6, G7 (10 gates).

---

**End of Sub-Period Stability Protocol v3**

Lineage: 도훈 mandate 2026-05-19 + AX-001 v2 conditional defense + historical_coverage_audit_v3.md §5 walk-forward + crisis_sample_inclusion_v3.md §3 + L-326 STR_1715 baseline robust precedent + L-325/L-326 sub-period bias lessons.
