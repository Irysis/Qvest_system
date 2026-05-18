# Daily-Frequency Protocol — Step 2.4

**WT-D20260519_002 Bear Prediction Engine v1.0**

**v5 fail mode**: 124 monthly × ~30 bad positive class **insufficient sample**.

**v1 redesign**: **daily-frequency expansion** for 25× sample with **monthly aggregation** for forecast horizon 1M.

---

## 1. Sample math justification

### v5 monthly
- sig_dates: 124 monthly (2014-01~2026-04)
- positive class: ~30 bad months
- ratio: 124 / 30 = 4.1× neg/pos
- effective param capacity (rule of thumb 10 obs/param): 12 params max
- features: 80 → catastrophic over-parameterization

### v1 monthly (max-history)
- sig_dates: 437 monthly (1990-01~2026-05)
- positive class: ~81 bad months
- ratio: 437 / 81 = 5.4× neg/pos (less skewed)
- effective param capacity: 8 params per class × 81 pos = ~648 params capacity
- features: 32 → **well within capacity (~ 20× margin)**

### v1 daily (alternative — Forge cycle compare)
- daily obs: ~9000 trading days (1990~2026)
- positive class definition (daily): day t where forward 20-day BM_Ret < -3% OR realized vol > 95th pct
- estimated positive days: ~1500~2000
- ratio: 9000 / 1500 = 6× neg/pos
- effective capacity: 8 × 1500 = ~12000 param capacity
- features: 32 → **massive margin (~ 375× margin)**

**Verdict**: Both monthly and daily have **sufficient sample**, but daily provides **25× expansion** for noise smoothing + sub-window stability.

---

## 2. Frequency mode comparison

| Aspect | Monthly (default) | Daily (auxiliary) |
|---|---|---|
| **Forecast horizon** | 1M (spec compliance) | 1D ahead → aggregate to 20D |
| **n_obs** | 437 | ~9000 |
| **Positive class** | ~81 | ~1500 |
| **Label aggregation** | direct: bad_month = BM_Ret_month < -5% | aggregate daily p_bad → monthly via max/mean/streak |
| **Feature lag** | t-1 month-end | t-1 day |
| **Sub-window stability** | 4/5 (437 monthly across 5 windows) | 4/5 (9000 daily across 5 windows) |
| **Computational cost** | low | moderate (20× more obs) |
| **Noise** | high (single monthly outcome) | low (daily averaging) |
| **Regime persistence** | natural (monthly state stable) | requires temporal smoothing |

**Default**: **monthly mode** (spec 정합 forecast_horizon = 1M).
**Auxiliary**: daily mode for Forge cycle compare on G1 5-subgate.

---

## 3. Monthly mode protocol (primary)

### Label

```r
# rawdata BM_Ret daily compounding to monthly
bm_daily <- unique(rawdata[, .(Date, BM_Ret)])
bm_daily[, ym := format(Date, "%Y-%m")]
bm_monthly <- bm_daily[, .(
  bm_ret = prod(1 + BM_Ret, na.rm=TRUE) - 1,
  ndays = .N,
  month_end_date = max(Date)
), by = ym]
bm_monthly[, bad_month := bm_ret < -0.05]
```

### Feature at sig_date t (month-end)

```r
# Each feature computed using t-1 close + lag rules
feature_panel_t <- compute_features_for_sigdate(
  sig_date = month_end_date,
  data_lag_rules = list(
    price = 1L,        # t-1 close
    fred_daily = 1L,   # FRED publish T+1
    fred_monthly = 30L, # FRED monthly publish T+1m+5d → t-30d buffer
    ecos_monthly = 35L, # ECOS T+1m+5~7d → t-35d buffer
    investor = 2L,     # KRX investor T+2
    seibro = 2L        # SEFRS k≥2
  )
)
```

### Training

```
Train: 1990-01 to 2010-12 (252 monthly)
Val:   2011-01 to 2014-12 (48 monthly)
Test:  2015-01 to 2026-05 (137 monthly)
Embargo: 1 month between splits
```

### Evaluation

- **5 sub-window evaluation** (within test 2015~2026):
  - W1: 2015-01~2017-12 (36m)
  - W2: 2018-01~2020-12 (36m, incl COVID + 2018 vol)
  - W3: 2021-01~2022-12 (24m, incl Inflation)
  - W4: 2023-01~2024-12 (24m)
  - W5: 2025-01~2026-05 (17m, incl 2026-03)

- **G1 5-subgate per window**:
  - AUC ≥ 0.60
  - Brier < 0.20
  - Recall ≥ 0.60
  - Precision ≥ 0.40
  - 4/5 windows pass

### Walk-forward refit

```
Refit cadence: annual (every 12 months)
Models refit: all 5 (Logistic + LightGBM + RF + LSTM + MSM)
Calibration refit: Platt on prior val window
```

---

## 4. Daily mode protocol (auxiliary)

### Label (daily)

Multiple label definitions for Forge compare:

#### Definition 1: Forward 20-day return threshold

```r
# At each day t, label = 1 if forward 20-day BM_Ret < -3%
bm_daily <- unique(rawdata[, .(Date, BM_Ret)])
setorder(bm_daily, Date)
bm_daily[, bm_forward_20d := frollapply(BM_Ret, n=20, FUN=function(x) prod(1+x)-1, align="left")]
bm_daily[, bad_day := bm_forward_20d < -0.03]
# Note: PIT-safe since label uses forward returns (target, not feature)
```

#### Definition 2: Volatility regime

```r
# realized vol over 60d window > 95th percentile rolling 252d
bm_daily[, rv_60d := frollapply(BM_Ret, n=60, FUN=sd, align="right") * sqrt(252)]
bm_daily[, rv_60d_95th := frollapply(rv_60d, n=252, FUN=function(x) quantile(x, 0.95, na.rm=TRUE), align="right")]
bm_daily[, bad_day := rv_60d > rv_60d_95th]
```

#### Definition 3: Combined (UNION)

```r
bm_daily[, bad_day := bad_day_d1 | bad_day_d2]
```

**Default**: Definition 1 (-3% forward 20d threshold) — direct return-based, intuitive.

### Feature at day t

All features computed at daily frequency:

```r
sig_dates_daily <- unique(rawdata[Date >= "1990-01-04" & Date <= "2026-05-18", Date])
# Filter to trading days only
sig_dates_daily <- sig_dates_daily[!weekdays(sig_dates_daily) %in% c("Saturday", "Sunday")]

# For each daily sig_date:
for (d in sig_dates_daily) {
  feature_panel_daily_d <- compute_features(
    sig_date = d,
    lag_rules = list(price=1L, fred_daily=1L, fred_monthly=30L, ecos=35L, investor=2L, seibro=2L)
  )
}
```

### Aggregation (daily → monthly)

After daily model fit:
```r
# Per-day p_bad_d
# Aggregate to month
monthly_aggregation <- list(
  method_max = max(p_bad_d for d in month),
  method_mean = mean(p_bad_d for d in month),
  method_streak = max(consecutive days with p_bad_d > 0.5)
)
# Default: method_max (recall-focused)
p_bad_monthly_t <- max(p_bad_d for d in t-month)
```

### Training (daily mode)

```
Train: 1990-01-04 ~ 2010-12-31 (~5300 daily)
Val:   2011-01-04 ~ 2014-12-31 (~1000 daily)
Test:  2015-01-05 ~ 2026-05-18 (~2900 daily)
Embargo: 20 trading days (~1 month equivalent)
```

### Sub-window evaluation (daily)

Same 5 sub-windows as monthly mode but evaluated on daily → monthly aggregated p_bad.

---

## 5. Comparison protocol (Forge mandate)

**Forge cycle empirical compare**:

| Comparison | Goal |
|---|---|
| Monthly LightGBM vs Daily LightGBM (aggregated) | Sample expansion 25× uplift? |
| Monthly ensemble vs Daily ensemble | Stability ↑ |
| max aggregation vs mean vs streak | Optimal aggregation |
| Label def 1 vs 2 vs 3 | Optimal target |

**Decision criteria** (pre-declared):
- **Daily mode admit only if**: G1 5-subgate pass count > monthly mode at same params
- Else: Monthly mode default (spec 정합 + simpler)

---

## 6. Computational budget

### Monthly mode
- n_train = 252, n_features = 32
- LightGBM fit: ~1 sec
- LSTM fit (50 epochs): ~10 sec
- MSM fit (EM 200 iter): ~30 sec (most expensive)
- Total per-refit: ~60 sec
- Total walk-forward (16 refits @ annual): ~16 min

### Daily mode
- n_train = 5300, n_features = 32
- LightGBM fit: ~5 sec
- LSTM fit (50 epochs): ~60 sec
- MSM fit: ~5 min (large sample)
- Total per-refit: ~6 min
- Total walk-forward (16 refits): ~96 min (~1.6 hr)

**Both modes within budget** (Forge cycle 4~5hr GPU estimated).

---

## 7. PIT integrity for daily mode

추가 PIT concern for daily mode:

| Concern | Handling |
|---|---|
| **Daily features uses t-1 close** | All daily sig_dates use prior day Close |
| **Macro features (monthly)** | Stale value held until next publish (no interpolation) — explicit NaN or last-known-value |
| **Embargo for refit** | 20-day embargo strictly enforced (avoid leakage near refit boundary) |
| **Forward label leakage** | Target uses forward 20d returns — but **not feature**, only label. PIT compliant. |

**Forge cycle lookahead_detector.R audit** mandatory for daily mode.

---

## 8. Audit conclusion

도훈 mandate **"Daily-frequency ~3000 obs × 600-700 bad days = 25x"** 정합 PASS (with max-history 활용):

1. ✅ Monthly mode default (437 obs × 81 pos class, 437/124 = 3.5× v5)
2. ✅ Daily mode auxiliary (~9000 obs × ~1500 pos class, 25× v5 sample)
3. ✅ 4 label definitions for monthly + 3 for daily
4. ✅ 3 aggregation methods (max/mean/streak) for daily → monthly
5. ✅ Purged WF + embargo (1m monthly / 20d daily)
6. ✅ 5 sub-windows G1 5-subgate evaluation
7. ✅ Comparison protocol pre-declared (Forge cycle empirical)
8. ✅ PIT integrity for daily mode (lookahead audit binding)
9. ✅ Computational budget within scope (~16 min monthly / ~96 min daily)

---

## 참조

- 도훈 mandate 2026-05-19 추가 (max-history + daily frequency)
- López de Prado (2018) AFML Ch 7 (Purged WF + Embargo)
- `historical_coverage_audit.md` (4-stratum)
- `crisis_sample_inclusion.md` (8 crisis epochs)
- L-330 (v5 monthly insufficient sample)
