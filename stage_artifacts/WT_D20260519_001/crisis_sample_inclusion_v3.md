# DPL_KR_v3 Crisis Sample Inclusion Protocol — 8 Crisis Events

**WT-D20260519_001 · alpha-research Mandate Extension**
**Date**: 2026-05-18
**Author**: alpha-research agent (autonomous)
**도훈 mandate 2026-05-19**: Crisis sample diversification (3 → 8 crisis events)

---

## 1. Eight Major Crisis Events (1990~2026)

| # | Crisis | Date Range | KR Drawdown | Walk-Forward Window Coverage |
|---|---|---|---|---|
| 1 | **Asia IMF Crisis** | 1997-07 ~ 1998-12 | KOSPI -65% | Pre-train history (train window 1) |
| 2 | **Dot-com Crash** | 2000-03 ~ 2002-09 | KOSPI -55% | Window 1 test (2001-2002) |
| 3 | **Global Financial Crisis (GFC)** | 2007-10 ~ 2009-03 | KOSPI -54% | Window 4 test (2007-2008) |
| 4 | **EU Sovereign Crisis** | 2011-08 ~ 2012-06 | KOSPI -25% | Window 6 test (2011-2012) |
| 5 | **China A-share Shock** | 2015-06 ~ 2016-01 | KOSPI -22% | Window 8 test (2015-2016) |
| 6 | **Vol Mageddon** | 2018-02 (Feb 5) | KOSPI -7% (1-day) | Window 9 test (2017-2018) |
| 7 | **COVID-19 Crash** | 2020-02 ~ 2020-04 | KOSPI -36% (March bottom) | Window 10 test (2019-2020) |
| 8 | **Inflation / Rate Hike Cycle** | 2022-01 ~ 2022-12 | KOSPI -25% (FY) | Window 11 test (2021-2022) |

---

## 2. Crisis Inclusion in Walk-Forward Windows

### 2.1 Coverage Map

Walk-forward 13-window schema (historical_coverage_audit_v3.md §5.1):

```
Crisis           Train/Val/Test         Window
==============   ====================   ======
IMF 1997         pre-Window 1 (history) — embedded in rawdata
Dot-com 2000-02  Train (W1) + Val (W1)  Window 1 (val)
Dot-com 2001-02  Test (W1)              Window 1 (test)
GFC 2007-08      Train (W2-4)           Window 2-4 (multi)
GFC 2008 peak    Val (W4)               Window 4 (val)
EU 2011-12       Test (W6)              Window 6 (test)
China 2015       Test (W8)              Window 8 (test)
Vol Mag 2018-02  Val/Test (W9)          Window 9 (val/test)
COVID 2020-03    Test (W10)             Window 10 (test)
Inflation 2022   Test (W11)             Window 11 (test)
```

### 2.2 Critical Crisis Test Windows (5 explicit + 3 embedded)

**Explicit Test Windows** (DPL_v3 measurement during crisis):
- Window 4 test 2007-2008 (GFC) — 24 months including GFC peak
- Window 6 test 2011-2012 (EU) — 24 months including EU peak
- Window 9 test 2017-2018 (Vol Mageddon) — 24 months including Feb 2018
- Window 10 test 2019-2020 (COVID) — 24 months including March 2020 bottom
- Window 11 test 2021-2022 (Inflation) — 24 months including 2022 drawdown

**Embedded Crisis Periods** (in train/val):
- Window 1 train 1995-1999 includes IMF 1997 (training stress test)
- Window 1 val 2000-2000 includes dot-com peak
- Window 8 test 2015-2016 includes China A-share August 2015

---

## 3. AX-001 v2 Conditional Defense Measurement

### 3.1 Per-Crisis Metric

For each test window containing a crisis:
- **Crisis_SR**: SR during crisis sub-period (start = crisis_start, end = crisis_end)
- **Crisis_MDD**: max drawdown during crisis sub-period
- **Crisis_alpha_vs_KOSPI**: (DPL_v3 cum_ret) - (KOSPI cum_ret) during crisis
- **Crisis_outperform_pp**: outperform percentage points vs KOSPI

### 3.2 AX-001 v2 Conditional Pass Criteria

Per AX-001 v2 (active 8 axioms, .claude/rules/axioms.md):
> 방어형 팩터는 조건부 성과로 평가 (crisis_alpha + Core 대비 MDD + bad/normal IC ratio). 전기간 SR 기준 적용 금지.

**DPL_v3 Crisis Pass Criteria** (≥ 5 of 8):
- Crisis_alpha > 0 (positive outperformance vs KOSPI200)
- Crisis_MDD ≤ KOSPI200_MDD (better drawdown control)
- bad/normal IC ratio ≥ 1.0 (signal stronger during stress)

**Aggregated Crisis Score**:
- 8/8 PASS: STRONG_CRISIS_ROBUST
- 6-7/8 PASS: CRISIS_ROBUST
- 5/8 PASS: CONDITIONAL_PASS (G3' new gate)
- 4 or fewer PASS: G3' FAIL → DEFER

---

## 4. Stratified Crisis Analysis Schema

### 4.1 Per-Window Crisis Reporting

Forge cycle emit per-window:

```json
{
  "window_id": 4,
  "test_period": "2007-01 ~ 2008-12",
  "crisis_subperiod": "2007-10 ~ 2008-12 (GFC)",
  "test_sharpe": 1.2,
  "crisis_sharpe": 0.8,
  "crisis_mdd": -0.28,
  "kospi_crisis_mdd": -0.54,
  "crisis_alpha_pp": 12.4,
  "outperform_kospi": true,
  "ic_during_crisis": 0.045,
  "ic_during_normal": 0.038,
  "bad_normal_ic_ratio": 1.18
}
```

### 4.2 Aggregated Crisis Summary

```json
{
  "crisis_windows_tested": 5,
  "crisis_windows_with_positive_alpha": 4,
  "crisis_windows_outperform_kospi": 3,
  "crisis_avg_mdd_vs_kospi_pp_improve": 18.2,
  "median_bad_normal_ic_ratio": 1.12,
  "ax_001_v2_conditional_status": "CONDITIONAL_PASS"
}
```

---

## 5. KR-Specific Crisis Characteristics

### 5.1 Asia IMF 1997 (Pre-Train, Embedded)

- KOSPI -65% peak-to-trough (1997-07 to 1998-09)
- Currency crisis: KRW USD -50%
- Many chaebol bankruptcies (Daewoo, Kia)
- DPL_v3 training observes this period (window 1 train)
- **Importance**: stress signal for emerging-market risk patterns

### 5.2 GFC 2008 (Window 4 Test)

- KOSPI -54% (2007-10 to 2008-10)
- Global synchronized crash
- DPL_v3 test window includes peak
- **Test**: cross-market vs idiosyncratic alpha

### 5.3 COVID March 2020 (Window 10 Test)

- KOSPI -36% (Jan to March 2020)
- Fast recovery (V-shaped)
- DPL_v3 test window includes crisis + recovery
- **Test**: regime transition agility

### 5.4 Inflation 2022 (Window 11 Test)

- KOSPI -25% (FY 2022)
- Rate hike cycle (Fed + BOK)
- Tech sector underperformance
- DPL_v3 test window includes full year
- **Test**: rate-sensitive sector rotation

---

## 6. Implementation Mandate for Forge

### 6.1 Per-Window Crisis Sub-period Identification

```r
crisis_subperiods <- list(
  W1 = list(start = "2000-03-01", end = "2002-09-01"),  # Dot-com (test W1)
  W4 = list(start = "2007-10-01", end = "2009-03-01"),  # GFC
  W6 = list(start = "2011-08-01", end = "2012-06-01"),  # EU
  W8 = list(start = "2015-06-01", end = "2016-01-01"),  # China
  W9 = list(start = "2018-02-01", end = "2018-12-01"),  # Vol Mag
  W10 = list(start = "2020-02-01", end = "2020-04-01"), # COVID
  W11 = list(start = "2022-01-01", end = "2022-12-01")  # Inflation
)
```

### 6.2 Per-Window Crisis Metric Computation

```r
for (w in c(1, 4, 6, 8, 9, 10, 11)) {
  test_period <- ...  # Window w test period
  crisis <- crisis_subperiods[[paste0("W", w)]]
  crisis_returns <- subset(test_returns, Date >= crisis$start & Date <= crisis$end)
  
  crisis_sharpe <- SharpeRatio.annualized(crisis_returns)
  crisis_mdd <- maxDrawdown(crisis_returns)
  crisis_alpha_pp <- (Return.cumulative(dpl_v3_crisis) - Return.cumulative(kospi_crisis)) * 100
  
  # bad/normal IC ratio
  ic_normal <- ic_history[ic_history$sig_date %in% normal_period, ]$rank_ic %>% mean
  ic_crisis <- ic_history[ic_history$sig_date %in% crisis_period, ]$rank_ic %>% mean
  bad_normal_ic_ratio <- ic_crisis / ic_normal
  
  ...
}
```

### 6.3 G3' Crisis-Conditional Performance Gate

**Pass criteria**:
- ≥ 5 of 7 explicit crisis test windows positive crisis_alpha (vs KOSPI)
- Median crisis_MDD vs KOSPI ≥ 10pp improvement
- Median bad_normal_ic_ratio ≥ 1.0

**Failure**:
- < 5/7 pass → G3' FAIL → DEFER

---

## 7. Comparison Baseline During Crisis

For each crisis test window, compute:
- DPL_v3 crisis_metrics
- STR_1715_AR_on_M4_R05_overlay_PG2 same-period crisis_metrics (from existing alpha_scores_str1715_268m.parquet, where available)
- KOSPI200 same-period crisis_metrics (benchmark)
- EW long-only top-20 same-period crisis_metrics (baseline)

**Reporting**: 4-way comparison table per crisis window.

---

## 8. Honest Caveats

### 8.1 Pre-2000 Crisis Asymmetry

- IMF 1997 (-65%) and Dot-com 2001-2002 (-55%) are deepest KR drawdowns in history
- Most observers consider these "tail" events, not representative
- Including 1990s as training data exposes model to emerging-market regime
- **Risk**: 1990s signal may not generalize to 2020s mature market (regime shift)

### 8.2 8/8 Crisis Coverage Not Guaranteed

- Vol Mageddon (Feb 2018) is 1-day event; crisis_sharpe measurement may be noisy
- China A-share 2015 KR market less impacted (-22% only)
- Window 8 test (2015-2016) may show mild crisis_metrics, not strong defense signal

### 8.3 Survivorship Bias Pre-2000

- 1990s delisted stocks tracked via rawdata.parquet (v5 canonical) but some pre-1990 entries may be missing
- Per-sig_date universe filter mitigates retroactive selection
- 1990s small universe (N_t < 200) may distort top-20 concentration measurement

---

## 9. Crisis Sample Inclusion Summary

- ✅ 8 crisis events identified across 1990~2026
- ✅ 7 explicit test windows containing distinct crisis (Window 1, 4, 6, 8, 9, 10, 11)
- ✅ 1 embedded in train (Window 1 train IMF 1997)
- ✅ Per-crisis metric computation protocol (SR / MDD / alpha vs KOSPI / IC ratio)
- ✅ AX-001 v2 conditional defense criteria mapped to crisis metrics
- ✅ G3' new gate (crisis-conditional ≥ 5/7 pass) added to admission_protocol_v3.md
- ✅ KR-specific crisis characteristics documented (IMF / GFC / COVID / Inflation distinct)
- ✅ Honest caveats: 1990s regime shift risk + survivorship bias + Vol Mag noise

---

**End of Crisis Sample Inclusion Protocol v3**

Lineage: 도훈 mandate 2026-05-19 + AX-001 v2 conditional defense + historical_coverage_audit_v3.md §5 walk-forward + L-326 STR_1715 baseline robust precedent.
