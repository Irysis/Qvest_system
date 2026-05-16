# Crowding Score Protocol — WT-D20260517_001 risk-research Step 5.3

**Author**: risk-research agent
**Date**: 2026-05-17
**Lineage**: Phase 2.C (도훈 mandate 2026-05-14, 7 QEPM Modern Trends Principle 5)
**Infra**: `02_Infrastructure/factor_db/crowding_score_per_factor.R` (Acadian 2026 정합)

---

## 1. Why crowding for DPL?

**Traditional factor crowding** = single named factor (Value EP / Momentum / Low-vol) 공모기관 + ETF 집중도. Acadian 2026 standard.

**DPL crowding 차이**:
- DPL output weights = 634 features의 latent combination — **단일 factor 아님**
- 그러나 각 feature의 attribution (gradient × input) 측정 가능 → **per-feature crowding 측정**
- Top-K=20 selected stocks → portfolio-level crowding은 traditional 그대로 적용 가능

**본 protocol 2-track 설계**:
1. **Per-feature crowding** (634 features) — 학술적 신규 contribution
2. **Portfolio-level crowding** (top-20 selected) — Acadian 2026 standard inherit

---

## 2. Per-feature Crowding (Track 1, DPL-novel)

### 2.1 Feature attribution → per-feature exposure

```r
# Forge cycle PyTorch autograd
# For each sig_date_t and ticker i:
#   gradient_attribution[i, f] = ∂w_i / ∂feature_f  (input × gradient)
#   integrated over 124 sig_dates → mean abs attribution per feature

# R bridge: PyTorch saved to .npy → R import
attr_per_feature <- ...  # data.table(Ticker, factor_name=feature_f, exposure=attribution)
# 634 features × 500 tickers (avg)
```

### 2.2 crowding_score_per_factor() 호출

```r
source("02_Infrastructure/factor_db/crowding_score_per_factor.R")

# 124 sig_dates × 634 features × top_20
result <- crowding_timeseries(
  factor_exposures_panel = attr_per_feature,  # built from PyTorch attribution
  sig_dates = sig_dates_124,
  RAWDATA = rawdata_panel,
  benchmark_tickers = kospi200_constituents,
  top_n = 20
)
# Output: 124 × 634 = 79,016 rows (factor_name × sig_date)
# Columns: crowding_score [0~1], hhi_top, vol_concentration, passive_overlap_proxy, demand_elasticity_proxy
```

### 2.3 Alert threshold (Acadian 2026 정합)

- **crowding_score ≥ 0.75** → `LEVEL_HIGH` alert
- **3m delta ≥ 0.15** → `RAPID_INCREASE` alert (decay/crowding emergence 사전)
- **BOTH** → `BOTH_HIGH_AND_RISING` critical

```r
alerts <- crowding_alert(result, threshold_high = 0.75, threshold_increase_3m = 0.15)
# top 10 most-crowded features → risk_summary.crowding_score_per_factor 등재
```

---

## 3. Portfolio-level Crowding (Track 2, Standard)

### 3.1 DPL output weights → portfolio Crowding

```r
# DPL emits top-20 weights per sig_date
# Treat as single "synthetic factor" with weights as exposure
synthetic_dpl_factor <- weights_panel  # data.table(Ticker, factor_name="DPL_KR_v1", exposure=weight)

crowding_portfolio <- crowding_timeseries(
  factor_exposures_panel = synthetic_dpl_factor,
  sig_dates = sig_dates_124,
  RAWDATA = rawdata_panel,
  benchmark_tickers = kospi200_constituents,
  top_n = 20
)
# Output: 124 × 1 = 124 rows (single "DPL_KR_v1" factor across time)
```

### 3.2 vs Baseline STR_1715 비교

```r
# STR_1715_AR_on_M4_R05_overlay_PG2 alpha_scores 같은 schema로 crowding
str1715_factor <- ...  # production alpha_scores → factor_exposures

crowding_str1715 <- crowding_timeseries(str1715_factor, sig_dates_124, ...)

# Comparison: DPL vs STR_1715 mean crowding_score
# Hypothesis: DPL is less crowded (orthogonal 4th-source 자격 시) → mean(crowding_DPL) < mean(crowding_STR1715)
```

---

## 4. Output schema

```json
// qepm/stage_artifacts/WT_D20260517_001/crowding_summary.json (Forge cycle emission)
{
  "track_1_per_feature": {
    "mean_crowding_score_overall": 0.XX,
    "top_10_crowded_features": [
      {"factor_name": "...", "mean_score": 0.XX, "max_score": 0.XX, "alert_count_3y": N},
      ...
    ],
    "alerts_count_LEVEL_HIGH": N,
    "alerts_count_RAPID_INCREASE": N,
    "alerts_count_BOTH": N
  },
  "track_2_portfolio_level": {
    "DPL_KR_v1_mean_crowding": 0.XX,
    "STR_1715_baseline_mean_crowding": 0.XX,
    "DPL_vs_baseline_relative": "...",
    "regime_conditional": {
      "NORMAL": 0.XX,
      "CAUTION": 0.XX,
      "CRISIS": 0.XX
    }
  },
  "decision_implications": "..."
}
```

---

## 5. Decision implications for DPL admission

| Crowding Result | Admission Action |
|----------------|-----------------|
| DPL portfolio crowding < STR_1715 + per-feature mean < 0.5 | 4th orthogonal source 자격 강화 |
| DPL portfolio crowding ≈ STR_1715 + per-feature top10 alert majority | substitution sleeve 검토 |
| DPL portfolio crowding > STR_1715 OR per-feature LEVEL_HIGH > 100 sig_dates | DEFER admit — crowding risk dominates |

위 logic은 **Optimizer Agent** decision_objective와 결합 (risk-research는 진단만, weight 결정 X).

---

## 6. PIT compliance

- Date ≤ sig_date strict (RAWDATA filter at sig_date)
- `crowding_score_per_factor.R` line 60: `rd <- rd[Date <= sig_d]`
- 사용 Vol / Size는 t-1 lag PIT 정합 (factor_db 표준)

---

## 7. References

- Acadian Asset Management (2026) "Systematic Crowding Monitoring" research note
- Behmaram et al. (2024) "Demand Elasticity in Equity Markets" — elasticity proxy
- Lou D., Polk C. (2013) "Comomentum" *RFS* — DTC (Days-to-Cover) factor
- `qepm_research_philosophy.md` v1.0 §Principle 5
- Phase 2.C SOT: `02_Infrastructure/factor_db/crowding_score_per_factor.R`
