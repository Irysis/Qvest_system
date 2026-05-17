# 8 Stress Scenarios + DPL-RC Injection Matrix

**WT-D20260517_003 · risk-research Step 5.6**
**Author**: risk-research agent
**Date**: 2026-05-17
**Parent**: alpha_package admission_criteria_7_axis (axis 2 MDD ≥ -24.81%) + strategy_analyzer.R:L498 def_stress_periods + v2 Codex C7 ACCEPT (4 → 8 scenarios)
**Purpose**: 8 stress scenarios × DPL-RC injection grid (a_max 4 values) = 32 stress combinations measurement protocol

---

## 0. Background — Why 8 stress scenarios

### 0.1. v2 Codex C7 ACCEPT inheritance

WT-D20260517_002 Codex Round 1 → C7 "4 scenarios → 8 scenarios 확장" ACCEPT. 본 cycle 정합 retain.

### 0.2. Stress periods inherit (def_stress_periods L498)

`02_Infrastructure/strategy_analyzer.R:L498` 8대 stress periods:
1. Terror_9_11 (2001-09-01 ~ 2001-12-31)
2. GFC (2007-10-01 ~ 2009-03-31)
3. Euro_Debt (2011-07-01 ~ 2011-12-31)
4. China_Shock (2015-06-01 ~ 2016-02-29)
5. US_China_Trade (2018-03-01 ~ 2018-12-31)
6. COVID (2020-01-01 ~ 2020-06-30)
7. Rate_Hike (2022-01-01 ~ 2022-12-31)
8. Iran_War (2026-02-01 ~ 2026-04-30)

### 0.3. KR equity 1715 production retain window 정합

1715 production retain: 2014-01 ~ 2026-04 (148m 정도).
- **1715 cycle 안에서 실제 적용 가능 stress** (2014-01 이후):
  - China_Shock (2015-06 ~ 2016-02)
  - US_China_Trade (2018-03 ~ 2018-12)
  - COVID (2020-01 ~ 2020-06)
  - Rate_Hike (2022-01 ~ 2022-12)
  - Iran_War (2026-02 ~ 2026-04) — within DPL-RC sample
- **Pre-2014 historical (stress proxy 분석용)**:
  - Terror_9_11 (2001), GFC (2007), Euro_Debt (2011)

→ 5 in-sample stress + 3 pre-sample historical proxy = 8 scenarios.

---

## 1. Eight stress scenarios (정의 + KR impact)

### 1.1. Scenario list (request.json §stress_scenarios_8 정합)

| # | Name | Period | KR equity impact (실증) | DPL-RC sample? |
|---|---|---|---|---|
| 1 | **GFC_2008** | 2007-10 ~ 2009-03 | KOSPI -45%, MDD persistent | Pre-sample proxy |
| 2 | **Euro_Debt** | 2011-07 ~ 2011-12 | KOSPI -22%, regime shift | Pre-sample proxy |
| 3 | **China_Shock** | 2015-06 ~ 2016-02 | KOSPI -18%, KOSDAQ -25% | In-sample (W1) |
| 4 | **US_China_Trade** | 2018-03 ~ 2018-12 | KOSPI -17%, sector rotation | In-sample (W2) |
| 5 | **COVID_2020** | 2020-01 ~ 2020-06 | KOSPI -33% peak-trough, recovery V | In-sample (W3) |
| 6 | **Rate_Hike_2022** | 2022-01 ~ 2022-12 | KOSPI -25%, MDD sustained | In-sample (W4) |
| 7 | **KR_Disinflation_2024** | 2024-Q1 ~ 2024-Q3 | KR specific stress, BoK policy | In-sample (W5) |
| 8 | **Iran_War_2026** | 2026-02 ~ 2026-04 | Geopolitical, energy spike | In-sample (W5) |

Note: scenario #7 (KR_Disinflation_2024) replaces def_stress_periods 의 Terror_9_11 (1715 sample 외, 분석 무관) — 도훈 mandate 2024 KR 디스플레이션 정합.

### 1.2. Scenario meta-data

```r
stress_scenarios_8 = list(
  list(name = "GFC_2008",            start = "2007-10-01", end = "2009-03-31", 
       in_sample = FALSE, proxy_type = "global_credit_shock"),
  list(name = "Euro_Debt",           start = "2011-07-01", end = "2011-12-31",
       in_sample = FALSE, proxy_type = "regional_sovereign"),
  list(name = "China_Shock",         start = "2015-06-01", end = "2016-02-29",
       in_sample = TRUE,  proxy_type = "EM_external"),
  list(name = "US_China_Trade",      start = "2018-03-01", end = "2018-12-31",
       in_sample = TRUE,  proxy_type = "trade_policy"),
  list(name = "COVID_2020",          start = "2020-01-01", end = "2020-06-30",
       in_sample = TRUE,  proxy_type = "pandemic_demand"),
  list(name = "Rate_Hike_2022",      start = "2022-01-01", end = "2022-12-31",
       in_sample = TRUE,  proxy_type = "monetary_policy"),
  list(name = "KR_Disinflation_2024", start = "2024-01-01", end = "2024-09-30",
       in_sample = TRUE,  proxy_type = "domestic_policy"),
  list(name = "Iran_War_2026",       start = "2026-02-01", end = "2026-04-30",
       in_sample = TRUE,  proxy_type = "geopolitical")
)
```

---

## 2. DPL-RC injection × stress matrix

### 2.1. 8 scenarios × 4 a_max values = 32 cells

```
Injection grid:
  a_max ∈ {0.05, 0.10, 0.15, 0.20}  (alpha cycle injection_grid_a_max retain)

Stress matrix (8 × 4 = 32 cells):
                    a=0.05   a=0.10   a=0.15   a=0.20
GFC_2008                ?        ?        ?        ?      (proxy)
Euro_Debt               ?        ?        ?        ?      (proxy)
China_Shock             ?        ?        ?        ?
US_China_Trade          ?        ?        ?        ?
COVID_2020              ?        ?        ?        ?
Rate_Hike_2022          ?        ?        ?        ?
KR_Disinflation_2024    ?        ?        ?        ?
Iran_War_2026           ?        ?        ?        ?
```

각 cell measurement metrics:
- Cumulative return (1715 standalone)
- Cumulative return (blend at a_max)
- MDD (1715 standalone)
- MDD (blend at a_max)
- Alpha vs benchmark (blend - 1715)
- Sharpe ratio (blend in stress period)
- Tail VaR_5 (in stress period)

### 2.2. In-sample vs proxy distinction

**In-sample (5 scenarios)**: 1715 + complement Forge cycle 의무 측정.
**Proxy (3 pre-sample)**: 본질적으로 1715 returns 가 pre-sample → 분석 limited.

**Proxy 분석 protocol**:
- 1715 의 architecture (Iter31 linear_tilt + M4 BOCPD + AR + R05) → pre-sample period 가상 application
- 가상 portfolio return = 1715 weights at month_t × actual returns_{t+1} of those stocks
- 단 종목 universe 변화 (2014 이전 universe 다름) → proxy 한계 explicit caveat

### 2.3. Stress 측정 example (in-sample COVID_2020)

```r
# COVID 2020 stress measurement
stress_period_t = c("2020-01", "2020-02", "2020-03", "2020-04", "2020-05", "2020-06")

for (a_max in c(0.05, 0.10, 0.15, 0.20)) {
  for (t in stress_period_t) {
    r_1715_t = production_returns$r_str1715[t]
    r_comp_t = forge_output$r_comp[t]
    p_bad_t1 = forge_output$p_bad_1715[t+1]  # forecast at t
    a_t = clip(a_max * p_bad_t1, 0, a_max)
    r_blend_t = (1 - a_t) * r_1715_t + a_t * r_comp_t
  }
  
  metrics = list(
    cum_r_1715 = prod(1 + r_1715[stress_period]) - 1,
    cum_r_blend = prod(1 + r_blend[stress_period]) - 1,
    mdd_1715 = maxDrawdown(r_1715[stress_period]),
    mdd_blend = maxDrawdown(r_blend[stress_period]),
    sr_1715 = SharpeRatio(r_1715[stress_period]),
    sr_blend = SharpeRatio(r_blend[stress_period]),
    var_5_blend = empirical 5th percentile of r_blend
  )
}
```

---

## 3. Stress test admission criteria

### 3.1. Hard requirements

| Threshold | Why |
|---|---|
| **MDD_blend ≥ MDD_1715 in stress (no worse)** | G4 admission axis 2 정합 |
| **cum_r_blend - cum_r_1715 ≥ 0 in stress** | paradigm value (complement should help in stress) |
| **No stress cell shows blend significantly worse than 1715 (Δ < -2pp cum return)** | 1715 alpha core preserve |

### 3.2. Soft criteria

- Average stress alpha (blend - 1715) > 0 across 5 in-sample scenarios
- Stress SR_blend > Stress SR_1715 across majority of scenarios
- Worst-stress (Rate_Hike_2022 likely) cum_r_blend > -25%

### 3.3. ABORT criteria

```
If ANY stress scenario:
  cum_r_blend - cum_r_1715 < -5pp at any a_max:
    → severe alpha damage in stress, paradigm INVALID
    → ABORT cycle
  
If ALL in-sample stress scenarios:
  cum_r_blend - cum_r_1715 < 0:
    → complement provides no stress hedge, paradigm value lost
    → DEFER (re-examine label / scorer)
```

---

## 4. Per-scenario expected behavior (priors)

### 4.1. GFC_2008 (proxy)

- 1715 architecture pre-sample → proxy analysis only
- Expected: 1715 likely heavy DD (-30% to -45%) given global credit shock
- Complement value: if defensive features (Tail_Risk + Risk_Beta_Vol 55%) hedge effective → mitigation expected
- Proxy caveat explicit

### 4.2. COVID_2020 (in-sample)

- 1715 production retain: 2020 Q1 acute DD then V recovery
- Complement value: pandemic regime → low-beta stocks (defensive heavy features) likely outperform
- Expected: blend MDD < 1715 MDD by 2-5pp; cum_return blend ~ 1715 (recovery V phase)

### 4.3. Rate_Hike_2022 (in-sample)

- 1715 production retain: sustained DD persistence
- Complement value: 7-axis admission 의 bad_state_improvement (axis 4) ≥ +0.30 → expected effective
- **Most critical scenario** for paradigm validation

### 4.4. Iran_War_2026 (in-sample)

- DPL-RC sample 내 (sig_date <= 2026-04)
- 4 sig_dates only (sample size 작음)
- Expected: short-term volatility, paradigm value in sample limited

---

## 5. Output protocol

### 5.1. stress_tests schema (risk_summary)

```json
{
  "stress_tests_8_scenarios": {
    "GFC_2008": {
      "in_sample": false,
      "proxy_caveat": "pre-2014 1715 architecture proxy only",
      "cum_return_1715_proxy": "Forge measurement",
      "cum_return_blend_a_005": "Forge measurement",
      "cum_return_blend_a_010": "...",
      "cum_return_blend_a_015": "...",
      "cum_return_blend_a_020": "...",
      "mdd_1715_proxy": "...",
      "mdd_blend_a_005_to_020": "..."
    },
    "Euro_Debt": {"...similar..."},
    "China_Shock": {"...similar..."},
    "US_China_Trade": {"...similar..."},
    "COVID_2020": {"...similar..."},
    "Rate_Hike_2022": {
      "in_sample": true,
      "n_sig_dates": 12,
      "cum_return_1715": "Forge measurement (production retain)",
      "cum_return_blend_a_005": "...",
      "mdd_blend_a_005_to_020": "...",
      "stress_alpha_blend_vs_1715": "...",
      "p_bad_1715_avg_during_stress": "..."
    },
    "KR_Disinflation_2024": {"...similar..."},
    "Iran_War_2026": {"...similar..."}
  }
}
```

### 5.2. stress_matrix.parquet (Forge cycle)

```
schema: data.table
  scenario | a_max | in_sample | cum_return_1715 | cum_return_blend | mdd_1715 | mdd_blend | sr_1715 | sr_blend | var_5_blend | stress_alpha
  
N rows: 8 scenarios × 4 a_max = 32
```

---

## 6. Worst-case stress design (single-scenario severity)

### 6.1. Worst-case shock identification

Forge cycle 의무 분석:
- Rank 32 cells by `cum_return_blend - cum_return_1715` (paradigm damage)
- Identify worst 3 cells → critical examination
- If worst 3 cells all in same scenario → scenario-specific failure
- If worst 3 cells all at same a_max (e.g., 0.20) → injection too high

### 6.2. Worst-case admission check

```
For worst 3 cells:
  if cum_r_blend < cum_r_1715 by >= 2pp AND a_max <= 0.10:
    → critical failure, paradigm at MINIMAL injection still hurts
    → ABORT or DEFER
  
  if cum_r_blend < cum_r_1715 by >= 2pp AND a_max >= 0.15:
    → high injection failure, paradigm OK at lower a_max
    → admission a_max ∈ {0.05, 0.10} only
```

### 6.3. Pareto stress curve

```
For each a_max ∈ {0.05, 0.10, 0.15, 0.20}:
  worst_stress_a = min over 8 scenarios of (cum_r_blend - cum_r_1715)
  avg_stress_a = mean over 8 scenarios of (cum_r_blend - cum_r_1715)
  
Pareto frontier: a_max vs (avg_stress, worst_stress)
→ admission 권고 a_max range
```

---

## 7. Cross-protocol integration

### 7.1. Stress + conditional risk attribution (Step 5.3)

Stress scenarios = severe bad_state subset
- COVID 2020 / Rate Hike 2022 / Iran 2026 ⊆ bad_state sig_dates (definition 1 x=3)
- Bad-state Σ_comp,bad (Step 5.3) overlaps with stress scenarios

### 7.2. Stress + EVaR (Step 5.4)

Worst-window EVaR α=0.10 k=3 worst window 은 stress scenarios overlap:
- Empirical worst 3m loss 일반적으로 COVID 2020 Q1 / Rate Hike 2022 Q1-Q3 / Iran 2026 Q1
- EVaR penalty in training → stress mitigation expected (training-time)

### 7.3. Stress + crowding (Step 5.5)

Crowding 자체는 stress period 무관 (static factor characteristic). 단 crowded factors 가 stress 시 더 큰 손실 보일 가능성 (Behmaram 2024 demand elasticity in stress). Forge cycle correlation 의무.

---

## 8. PIT compliance audit

### 8.1. C1 (full-sample 통계 금지)

Stress scenarios 는 historical periods 정의 (forward look 없음). 단:
- Stress definition 자체는 retrospective (e.g., COVID 2020 정의는 사후)
- 학술 / 도훈 mandate 정의 명시 → 본 risk cycle 정합. NOT signal, NOT alpha modification

### 8.2. C2 / C9

Returns 사용 모두 t-1 close based.

---

## 9. Codex Round audit points (예상 challenge)

1. **C-S1: "GFC_2008 / Euro_Debt / Terror_9_11 proxy 는 1715 architecture pre-sample, 의미 없음"**
   - 정당화: Proxy 분석은 explicit caveat noted. 1715 architecture 가상 application → universe drift 제한적이지만 stress-type pattern 식별 가능. v2 Codex C7 ACCEPT 8 scenarios 정합. 도훈 mandate 의 historical context retain.

2. **C-S2: "8 scenarios × 4 a_max = 32 cells 의 multiple-testing 부재"**
   - 정당화: stress test 는 **paradigm validity** 측정, NOT optimization. Bonferroni correction 의무 없음. ABORT criteria (severity threshold) 는 explicit (severe damage detection).

3. **C-S3: "KR_Disinflation_2024 scenario 의 KR 특수성 정량적 정의 부재"**
   - 정당화: 2024-Q1~Q3 KR BoK 정책 + GDP 디스플레이션 압력 → KR equity 특수 stress. Forge cycle 의무: 실제 KOSPI returns 분포 → 1715 + benchmark spread 측정.

4. **C-S4: "stress alpha threshold (cum_r_blend - cum_r_1715 ≥ 0) 의 admission rigor 약함"**
   - 정당화: paradigm value 확인 = soft criteria. Hard criteria = ABORT (Δ < -5pp 또는 모든 stress Δ < 0). Conservative admission 정합.

5. **C-S5: "Iran_War_2026 sample 4 sig_dates 만 → noise dominant"**
   - 정당화: noted limitation. 단 DPL-RC sample 내 most recent stress proxy 활용. Forge cycle CI 적용 의무.

---

## 10. Submission summary

**Submitted**: 2026-05-17 risk-research Step 5.6 stress_scenarios_8.md.

**Key deliverables**:
- 8 stress scenarios (5 in-sample + 3 pre-sample proxy)
- DPL-RC injection grid 4 × 8 = 32 cells matrix protocol
- Per-cell metrics (cum return, MDD, SR, VaR_5, stress alpha)
- Hard ABORT criteria (severe damage < -5pp Δ at any a_max)
- Soft admission criteria (avg stress alpha ≥ 0)
- Worst-case Pareto curve (a_max vs avg/worst stress)
- Cross-protocol integration (Step 5.3 bad-state / Step 5.4 EVaR / Step 5.5 crowding)
- v2 Codex C7 ACCEPT (4 → 8 scenarios) inherit retain

**Forge cycle handoff**:
- 8 scenarios × 4 a_max measurement (32 cells)
- In-sample 5 (actual measurement) + proxy 3 (caveat noted)
- stress_matrix.parquet 32 rows persist
- Pareto worst-case curve construction
- Cross-protocol integration with Steps 5.3 / 5.4 / 5.5

**다음 step**: 5.7 Codex Round 5단계 → 5.8 risk_package.json final
