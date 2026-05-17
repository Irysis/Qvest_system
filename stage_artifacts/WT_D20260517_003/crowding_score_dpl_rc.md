# Crowding Score per Factor — DPL-RC 80 Features Acadian 2026

**WT-D20260517_003 · risk-research Step 5.5**
**Author**: risk-research agent
**Date**: 2026-05-17
**Parent**: `02_Infrastructure/factor_db/crowding_score_per_factor.R` (Phase 2.C Acadian 2026) + alpha_package complement_scorer_4_stage.md (80 features)
**Purpose**: 80 features 의 crowding diagnosis + 1715 vs complement crowding 차이 측정 protocol — Research Philosophy P5 (Crowding-aware) 정합

---

## 0. Background — Why crowding measurement for DPL-RC

### 0.1. Research Philosophy P5 (Crowding-aware)

Charter §15 v1.8 + research_philosophy.md:
- 7 Modern Trends Principle 5: "Risk Model 고도화 (Σ + Crowding + Concentration)"
- Acadian (2026) "Systematic Crowding Monitoring" + Behmaram (2024) demand elasticity
- `crowding_score_per_factor` 의무 호출

### 0.2. DPL-RC 의 crowding 특수성

DPL-RC complement sleeve = anti-crowding paradigm:
- 1715 vs complement cor ≤ 0.3 (G2 admission axis 6) = orthogonal weight space
- → 1715 의 crowding 과 complement 의 crowding 이 다른 factor space 사용 가능
- → **diversification benefit** via crowding 분산

→ complement 가 1715 와 같은 crowded factors 사용 시 paradigm value 약화 (cor ↑, sleeve overlap ↑).

---

## 1. crowding_score_per_factor.R 인프라 leverage

### 1.1. Function signature

```r
crowding_score_per_factor(
  factor_exposures,           # data.table(Ticker, factor_name, exposure)
  sig_date,                   # PIT signal date
  RAWDATA,                    # for Vol / Size / institutional flow inputs
  benchmark_tickers = NULL,   # KOSPI200 / KOSDAQ150 list
  top_n = 20L,                # decile/top-N portfolio size
  weights = list(
    hhi = 0.30,
    vol = 0.25,
    passive = 0.25,
    elasticity = 0.20
  )
)
```

### 1.2. 4 sub-components

| Component | 의미 | Weight |
|---|---|---|
| **HHI_top** | Herfindahl-Hirschman Index of top-N factor portfolio weights | 0.30 |
| **Vol_concentration** | Top-N portfolio volume / total market volume | 0.25 |
| **Passive_overlap_proxy** | Overlap with KOSPI200/KOSDAQ150 benchmark | 0.25 |
| **Demand_elasticity_proxy** | Size-weighted rank reversal cost (Behmaram 2024) | 0.20 |

### 1.3. Returns

`data.table(factor_name, crowding_score [0~1], hhi_top, vol_concentration, passive_overlap_proxy, demand_elasticity_proxy, n_universe)`

---

## 2. DPL-RC 80 features crowding measurement

### 2.1. Input preparation

```r
# Feature exposures per stock per sig_date (Forge cycle output)
factor_exposures = data.table(
  Ticker = c("005930", "000660", ..., "..."),    # KR universe stocks
  factor_name = c("fdb_m_L39_Overnight_Spread", "fdb_m_R01_VaR_95", ..., "complement_score_stage_X"),
  exposure = c(z_score_normalized_value, ...)
)

# 80 features × ~500 stocks = 40,000 rows per sig_date
```

### 2.2. Crowding score computation (per sig_date)

```r
For each sig_date t in {2014-01, ..., 2026-04}:
  features_t = compute_features_at(t)   # 80 features × stocks
  
  factor_exposures_t = melt(features_t, id="Ticker", variable="factor_name", value="exposure")
  
  crowding_t = crowding_score_per_factor(
    factor_exposures_t,
    sig_date = t,
    RAWDATA = rawdata,
    benchmark_tickers = kospi200_kosdaq150_list,
    top_n = 20
  )
  
  # crowding_t: 80 rows × {factor_name, crowding_score, hhi_top, ..., n_universe}
```

### 2.3. Aggregation across sig_dates

```r
crowding_summary_per_factor = aggregate(
  crowding_t over 124 sig_dates,
  by = factor_name,
  metric = list(
    crowding_score_median = median(crowding_score, na.rm=TRUE),
    crowding_score_q90 = quantile(crowding_score, 0.90, na.rm=TRUE),
    crowding_score_3m_delta_recent = recent_3m_mean - prior_3m_mean
  )
)

# Threshold checks (system prompt risk_research_init.md):
crowding_flags = crowding_summary_per_factor[
  crowding_score_median >= 0.75 OR
  crowding_score_3m_delta_recent >= 0.15
]
```

---

## 3. 1715 vs complement crowding distinction

### 3.1. 1715 production sleeve crowding

```r
# 1715 production retain alpha-vector (PG2 effective 2026-05-13)
# Top stocks: 삼성전자 4.78% / 삼성SDI 4.65% / SK하이닉스 4.37% / 에코프로비엠 4.29% / ...

str_1715_factor_exposures = production_inheritance_for_str_1715()  # production lineage

crowding_str_1715 = crowding_score_per_factor(
  str_1715_factor_exposures,
  sig_date = current_sig_date,
  RAWDATA,
  ...
)
```

### 3.2. Complement sleeve crowding (Forge cycle output)

```r
# Complement scorer output (4 stages from alpha-research)
# Stage 1-4 each produces w_comp,t weights per sig_date

for stage in c("stage_1_linear", "stage_2_en", "stage_3_lgb", "stage_4_neural"):
  complement_factor_exposures = stage_output[sig_date == t, .(Ticker, factor_name = stage, exposure = w_comp)]
  
  crowding_comp_stage = crowding_score_per_factor(
    complement_factor_exposures,
    sig_date = t,
    RAWDATA,
    ...
  )
```

### 3.3. Diff diagnostic

```r
diff_crowding = list(
  crowding_score_str_1715 = crowding_str_1715$crowding_score,
  crowding_score_comp_stage_1 = crowding_comp_stage_1$crowding_score,
  crowding_score_comp_stage_2 = crowding_comp_stage_2$crowding_score,
  crowding_score_comp_stage_3 = crowding_comp_stage_3$crowding_score,
  crowding_score_comp_stage_4 = crowding_comp_stage_4$crowding_score,
  
  # Differential measurement
  delta_crowding_comp_vs_1715 = crowding_score_comp - crowding_score_str_1715,
  
  # Direction expectation:
  # complement = anti-crowding paradigm
  # Expected: crowding_score_comp <= crowding_score_1715 (or comp newer factor space)
)
```

### 3.4. Sleeve overlap diagnosis

```r
# Top-20 stock overlap between 1715 and complement
overlap_1715_comp = length(intersect(top20_1715, top20_comp)) / 20

# Expected: low overlap (≤ 30%) for paradigm value
# High overlap (≥ 70%) → complement degenerate, similar stocks
```

---

## 4. Output protocol

### 4.1. risk_summary.crowding_score_per_factor schema

```json
{
  "crowding_score_per_factor": [
    {
      "factor_name": "STR_1715_AR_R05",
      "crowding_score": "Forge measurement (production retain)",
      "hhi_top": "Forge measurement",
      "vol_concentration": "Forge measurement",
      "passive_overlap_proxy": "Forge measurement",
      "demand_elasticity_proxy": "Forge measurement",
      "alert": "LEVEL_NONE|LEVEL_MEDIUM|LEVEL_HIGH"
    },
    {
      "factor_name": "DPL_RC_complement_stage_4_neural",
      "crowding_score": "Forge measurement",
      "hhi_top": "...",
      "alert": "..."
    },
    {
      "factor_name": "ml_m6_ensemble_v3 (1715 prerequisite)",
      "crowding_score": "Forge measurement",
      "...": "..."
    }
  ],
  "crowding_flags": [
    "any factor with crowding_score >= 0.75 (LEVEL_HIGH alert)",
    "any factor with 3m_delta >= 0.15 (RAPID_INCREASE alert)"
  ]
}
```

### 4.2. crowding_score_per_factor_dpl_rc.parquet (Forge cycle)

```
schema:
  sig_date | factor_name | crowding_score | hhi_top | vol_concentration | passive_overlap | demand_elasticity | n_universe | alert

N rows: 124 sig_dates × ~85 factors (80 base + 5 sleeve aggregates) = ~10,500
```

---

## 5. Crowding alert thresholds

### 5.1. Static threshold (risk_research_init.md inherit)

| Threshold | Alert level |
|---|---|
| crowding_score < 0.5 | LEVEL_NONE |
| 0.5 ≤ crowding_score < 0.75 | LEVEL_MEDIUM |
| crowding_score ≥ 0.75 | LEVEL_HIGH (`crowding_flags` 등재) |

### 5.2. Dynamic threshold (3m delta)

```
3m_delta = (mean(crowding_score over last 3 sig_dates) 
         - mean(crowding_score over preceding 3 sig_dates))

If 3m_delta >= 0.15: RAPID_INCREASE alert (decay/crowding emergence)
```

### 5.3. DPL-RC specific threshold

```
sleeve_overlap_1715_comp >= 0.70 (70% stock overlap): COMPLEMENT_DEGENERATE warn
abs(crowding_score_comp - crowding_score_str_1715) <= 0.05: NO_DIFFERENTIATION warn
```

---

## 6. PIT compliance audit

### 6.1. C1 (full-sample 통계 금지)

crowding_score_per_factor.R 내부 Date <= sig_date strict (line 60 `rd <- rd[Date <= sig_d]`).
- 본 risk cycle 디자인 정합. Forge cycle empirical 의무.

### 6.2. C10 (유동성 필터 당일 거래량 사용)

crowding_score 의 Vol_concentration 은 sig_date 직전 daily volume snapshot 사용 (line 65 `rd_last <- rd[, .SD[.N], by = Ticker]`).
- PIT-clean (t-1 close 까지).

### 6.3. C15 (load_month_factors)

crowding_score_per_factor 는 RAWDATA + factor_exposures input → factor_exposures 는 `load_month_factors()` 경유 (Forge cycle 의무).

---

## 7. Codex Round audit points (예상 challenge)

1. **C-CR1: "1715 production crowding 은 production retain 이지만 본 cycle 에서 fresh measurement 가능?"**
   - 정당화: 1715 production lineage retain — but crowding diagnosis 는 risk-side **monitoring**, NOT alpha 수정. crowding_score 자체는 Σ 와 동일 risk diagnostic 영역. Forge cycle empirical measurement 가능.

2. **C-CR2: "80 features × 124 sig_dates × crowding measurement = 9,920 computations 부담"**
   - 정당화: crowding_score_per_factor.R single call ~ 0.5-1 sec on KR 500-stock universe. Total 9,920 × 1s ≈ 2.75 hours CPU. Parallel future_lapply 권고. Forge cycle acceptable.

3. **C-CR3: "crowding 4 sub-component weights (0.30 / 0.25 / 0.25 / 0.20) sensitivity"**
   - 정당화: Acadian 2026 default weights inherit. Sensitivity grid retain (Forge cycle): {0.25, 0.30, 0.35} for HHI primary weight.

4. **C-CR4: "complement sleeve crowding 측정에 80 base features 부분 사용 — circular"**
   - 정당화: complement scorer output (w_comp weights) 의 crowding 측정. Base 80 features 자체의 crowding 은 별도 (factor-side, NOT sleeve-side). 두 measurement 분리.

5. **C-CR5: "Threshold 0.75 sourcing?"**
   - 정당화: risk_research_init.md system prompt 정합 inherit. Acadian 2026 empirical bound — high crowding ≥ 0.75 (top quartile in US equity). KR equity 정합 검증은 Forge cycle empirical 의무.

---

## 8. Submission summary

**Submitted**: 2026-05-17 risk-research Step 5.5 crowding_score_dpl_rc.md.

**Key deliverables**:
- 80 features × 124 sig_dates crowding measurement protocol (per-sig_date)
- crowding_score_per_factor.R inherit (Phase 2.C Acadian 2026 정합)
- 1715 production crowding + complement stage 1-4 crowding diagnostic
- Sleeve overlap diagnosis (≤ 30% expected, ≥ 70% degenerate warn)
- Static threshold (0.75 HIGH) + dynamic threshold (3m_delta 0.15 RAPID_INCREASE)
- DPL-RC specific overlap + differentiation warns
- crowding_flags 자동 등재 protocol

**Forge cycle handoff**:
- 80 base features × 124 sig_dates crowding measurement (9,920 ops, ~2.75h CPU)
- 1715 vs complement crowding diff diagnostic
- sleeve overlap 측정 (top-20 intersect)
- crowding_flags 등재 자동 (LEVEL_HIGH OR RAPID_INCREASE)

**다음 step**: 5.6 stress_scenarios_8.md (8 stress + DPL-RC injection matrix)
