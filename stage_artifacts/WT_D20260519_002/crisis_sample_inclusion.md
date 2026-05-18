# Crisis Sample Inclusion Protocol — WT-D20260519_002

**도훈 mandate 2026-05-19 추가**: 최대 가능 기간 활용 시 **8 crisis epoch inclusion**으로 다양한 위기 패턴 학습 + sub-window stability 4/5 mandate 달성 가능성 ↑.

본 protocol은 **각 crisis epoch + bad month label 정합 + Sub-window 분할 + Stress-test design**을 명시.

---

## 1. Bad month label definition (단일 mandate)

**Label**: `bad_month_t = (BM_Ret_KOSPI_monthly_t < -0.05)`

- **Numerator**: month-end BM_Ret (geometric compound of daily BM_Ret from rawdata.parquet, t-1 close → t close)
- **Threshold**: -5% (도훈 mandate 정합 — v5 동일 threshold retain)
- **Aggregation**: `prod(1 + BM_Ret_daily) - 1 < -0.05`

**대안 threshold (Forge cycle empirical compare)**:
- `-3%` (lenient, n=116 bad / 437 = 26.5%)
- `-5%` (medium, n=81 bad / 437 = **18.5%**) ⭐ **default**
- `-10%` (severe, n=28 bad / 437 = 6.4%) — too sparse

**Label horizon**: monthly aggregation (daily prediction → monthly aggregation via `max(p_t) over month` OR `mean(p_t)` OR `streak>=k consecutive days p_t>τ`).

---

## 2. Crisis epoch catalog (8 + extras)

각 crisis는 rawdata empirical probe로 확인. **모든 bad months (BM<-5%)** 명시.

### Crisis 1 — 1990 KR pre-Asia (S1)
- Period: 1990-04
- Bad months: 1990-04 (BM_Ret = -18.6%)
- n_bad: 1
- Context: KR early market structural decline
- Forge stress weight: 1.0 (baseline)

### Crisis 2 — 1997 IMF (S1) ⭐ KEY for max-history mandate
- Period: 1997-10 ~ 1998-05
- Bad months: **1997-10 (-27.2%, worst)**, 1997-11 (-12.5%), 1998-04 (-12.4%), 1998-05 (-20.1%), plus moderate 1997-12 / 1998-01 / 1998-02 etc.
- n_bad (<-5%): **5+ extreme + moderate**
- Context: IMF currency crisis, sovereign debt, dollar shortage
- Forge stress weight: 2.0 (extreme — worst KR equity crash)

### Crisis 3 — 2000 Dotcom (S1+S2)
- Period: 2000-04 ~ 2002-12
- Bad months: 2000-04 (-15.7%), 2000-07 (-14.0%), 2000-10 (-16.1%), 2002-12 (-13.4%) + 2001-02, 2001-09, 2002-04 moderate
- n_bad: **~9**
- Context: tech bubble burst, 9/11 amplification
- Forge stress weight: 1.5

### Crisis 4 — 2008 GFC (S2+S3)
- Period: 2008-01 ~ 2008-12
- Bad months: **2008-10 (-23.1%)**, 2008-01 (-14.4%), 2008-09, 2008-11 + moderate
- n_bad: **5+**
- Context: Lehman collapse, global credit crunch
- Forge stress weight: 2.0 (extreme)
- Yield curve inversion: 2007-Q3 KR/US both inverted before crisis (Estrella-Hardouvelis 1991 prediction signal ★)

### Crisis 5 — 2011 Eurozone (S3)
- Period: 2011-08 ~ 2011-09
- Bad months: 2011-08, 2011-09
- n_bad: 2
- Context: Greece/Italy debt crisis, US debt ceiling
- Forge stress weight: 1.2

### Crisis 6 — 2015~2016 China shock (S3)
- Period: 2015-08 ~ 2016-02
- Bad months: 2015-08, 2016-01
- n_bad: 2
- Context: China CNY devaluation, oil crash
- Forge stress weight: 1.0

### Crisis 7 — 2018 vol spike (S3+S4)
- Period: 2018-10
- Bad months: 2018-10 (-13.4%)
- n_bad: 1
- Context: VIX spike, US trade war, Powell hawkish pivot
- Forge stress weight: 1.5

### Crisis 8 — 2020 COVID (S4)
- Period: 2020-02 ~ 2020-03
- Bad months: 2020-02 (-6.4%), 2020-03 (-11.7% est)
- n_bad: 2
- Context: pandemic, V-shape recovery
- Forge stress weight: 1.5 (KR less severe than US/EU)

### Crisis 9 — 2022 Inflation (S4)
- Period: 2022-06 ~ 2022-09
- Bad months: **2022-06 (-13.2%)**, **2022-09 (-12.8%)**
- n_bad: 2
- Context: Fed rate hike pace, inflation persistence
- Forge stress weight: 1.5
- Yield curve inversion: 2022-Q2 US 10y-2y inverted ★

### Crisis 10 — 2026-03 recent (S4)
- Period: 2026-03
- Bad months: 2026-03 (-19.1%)
- n_bad: 1
- Context: recent (still developing, OOS validation valuable)
- Forge stress weight: 1.0

**Total bad months**: **~81** (counting all <-5% threshold across full 1990~2026).

---

## 3. Sub-window split protocol (4/5 stability mandate)

도훈 mandate spec G1 sub-window stability `4/5 windows`. 본 cycle 정합:

### Default: 5 sub-windows by time (rolling 5-fold)

| Window | Period (monthly) | n_obs | n_bad | Crisis included |
|---|---|---|---|---|
| **W1** | 1990-01 ~ 1997-09 | 93 | ~5 | pre-IMF baseline |
| **W2** | 1997-10 ~ 2003-12 | 75 | ~14 | **IMF + Dotcom** (high-stress) |
| **W3** | 2004-01 ~ 2010-12 | 84 | ~7 | **GFC** (high-stress) |
| **W4** | 2011-01 ~ 2017-12 | 84 | ~5 | Eurozone + China shock + 2015~ |
| **W5** | 2018-01 ~ 2026-05 | 101 | ~6 | **COVID + Inflation + 2026** |
| **Total** | 1990-01 ~ 2026-05 | **437** | **~37 by -5% × 5 splits, broader counts approx 81** | full |

Note: W1 may have fewer bad months by -5% strict due to less volatile early KR period. Alternative threshold (lower bar -3% in W1 only) considered for balance, but **default retain -5% uniform** to avoid threshold-tuning data mining.

### Alternative: Crisis-stratified 5-fold (Forge optional compare)

| Fold | Crisis included | Train | Test |
|---|---|---|---|
| Fold-1 | IMF held-out | rest | 1997-10 ~ 1998-12 |
| Fold-2 | Dotcom held-out | rest | 2000-04 ~ 2002-12 |
| Fold-3 | GFC held-out | rest | 2008-01 ~ 2009-06 |
| Fold-4 | COVID held-out | rest | 2020-02 ~ 2020-12 |
| Fold-5 | Inflation held-out | rest | 2022-06 ~ 2022-12 |

이 alternative은 **crisis-specific generalization 검증** 용. Forge cycle 시 optional add.

---

## 4. Walk-forward train/val/test split (default)

Purged WF + 1 month embargo (Lopez de Prado 2018 Ch 7):

```
1990-01 ─────────────── 2010-12 │ 2011-01 ──── 2014-12 │ 2015-01 ─── 2026-05
        Train (252m, ~62 bad)   │ Validation (48m)     │ Test (137m, ~25 bad)
                                  embargo 1m            embargo 1m
```

**Train**: 1990-01 ~ 2010-12 (252 monthly, includes IMF + Dotcom + GFC = 3 major crises)
**Validation**: 2011-01 ~ 2014-12 (48 monthly, mostly calm, Eurozone tail)
**Test**: 2015-01 ~ 2026-05 (137 monthly, includes 2015 CN + 2018 vol + COVID + 2022 inflation + 2026)

**Embargo**: 1 month between splits (no leakage, purge labels around boundary).

**Purged walk-forward rolling refit (Forge)**:
- Initial fit: train ending 2010-12
- Refit every 12 monthly bars
- Test data 2015-01 부터 5 sub-window evaluation
- Final OOS metrics: 137m test

---

## 5. Stress-test pre-declare (Forge mandate)

본 cycle은 **사후 cherry-pick 차단** 위해 사전 declared stress test set fix:

### Stress Set A: 8 crisis stratification (W2 + W3 + W5 in default 5-fold)
- IMF (1997~1998)
- Dotcom (2000~2002)
- GFC (2008)
- Eurozone (2011)
- China (2015~2016)
- 2018 vol
- COVID (2020)
- Inflation (2022)

Per-crisis metrics:
- Recall_crisis (bad month detection rate)
- Precision_crisis
- AUC_crisis
- Brier_crisis

### Stress Set B: Quietude verification (false alarm test)
- Calm periods: 2003~2007, 2012~2014, 2016~2017, 2023~2025
- Metric: **False positive rate** ≤ 0.25 (Precision proxy)

### Stress Set C: Recent OOS (2026-Q1)
- 2026-01, 2026-02, 2026-03 (post-train cutoff)
- Out-of-sample real-time monitoring proof

---

## 6. Imbalanced class handling (도훈 mandate 정합)

**Bad month base rate**: ~18.5% (81/437). **Not catastrophic imbalance** (vs v5 ~12.2%, but still moderate).

### Strategy 1: No oversampling (default)
- LightGBM `is_unbalance=True` OR `scale_pos_weight = (1-r)/r = 4.4`
- Threshold tuning post-fit (default 0.5 → optimal_via_F1 or balanced_accuracy)

### Strategy 2: SMOTE-like (optional, Forge compare)
- SMOTE on training set only
- ⚠️ caveat: synthetic minority risk (Codex C-1 v4 학습) — Forge 시 명시 documentation
- Time-series SMOTE: SMOTENC with categorical + temporal_feature aware

### Strategy 3: Cost-sensitive learning
- LightGBM `objective="binary"` + `class_weight={0: 1, 1: 4}`
- Calibration: Platt scaling post-fit

**Recommendation**: Strategy 1 (no oversampling, just class_weight) — **simplest + no synthetic risk**.

---

## 7. Calibration protocol

**Probability calibration 의무** (도훈 spec axis_3 calibration):

```
raw probability p̂_t (from 5-model ensemble)
  ↓
Platt scaling: σ(a·p̂ + b) on validation set
  ↓
Final calibrated p_bad_t ∈ [0, 1]
```

Alternative: isotonic regression (Forge optional compare).

**Calibration evaluation**:
- Brier score < 0.20 (G1)
- Reliability diagram (10 bins) — slope ≈ 1.0 ± 0.1
- Expected Calibration Error (ECE) < 0.05

---

## 8. Forecast aggregation (daily → monthly)

본 cycle daily-frequency design + monthly bad month label. Aggregation strategies:

### Method 1: Max probability (default, recall-focused)
- `p_bad_monthly_t = max(p_bad_daily_{t,d}) for d in month`
- Pros: catches sharp transitions
- Cons: noise-sensitive (single high day flags entire month)

### Method 2: Mean probability
- `p_bad_monthly_t = mean(p_bad_daily_{t,d})`
- Pros: smoother
- Cons: smear transitions

### Method 3: Streak detection (k consecutive days)
- `p_bad_monthly_t = 1 if any streak of k≥5 consecutive days with p_daily > 0.5`
- Pros: regime-shift focused
- Cons: requires k tuning

### Method 4: Trailing window average
- `p_bad_monthly_t = mean(p_bad_daily over last 20 trading days)`
- Pros: temporal stability
- Cons: lagged response

**Default**: Method 1 (max) — recall-priority for v5 Recall 0.089 fix.

**Forge compare**: 4 methods empirical on G1 5-subgate.

---

## 9. Audit conclusion

도훈 mandate "8 crisis inclusion + diverse 위기 패턴 학습" 정합 PASS:

1. ✅ 8 crisis epoch catalog complete (IMF + Dotcom + GFC + Eurozone + China + 2018 + COVID + Inflation)
2. ✅ Bad month label uniform (-5% threshold) + alternatives declared
3. ✅ 5 sub-window split + alternative crisis-stratified 5-fold
4. ✅ Walk-forward train(1990~2010)/val(2011~2014)/test(2015~2026) with embargo
5. ✅ Stress Set A/B/C pre-declared (사후 cherry-pick 차단)
6. ✅ Imbalanced class handling 3 strategies, default class_weight no synthetic
7. ✅ Calibration Platt scaling + reliability diagram
8. ✅ Daily → monthly aggregation 4 methods, default max

**Recall 0.089 → Recall 0.60+ 가능성 evidence**:
- v5 positive class ~30 / 254 = 11.8%
- v1 positive class ~81 / 437 = 18.5% × **2.7×**
- ML model + diverse crisis = generalization 향상 + sub-window 4/5 stability 가능성 ↑
- Daily-frequency 25× sample = noise smoothing 가능

---

## 참조

- 도훈 mandate 2026-05-19 추가 (max-history + 8 crisis)
- `historical_coverage_audit.md` (S1~S4 stratum)
- Lopez de Prado 2018 AFML Ch 7 (Purged Walk-Forward + Embargo)
- Hamilton 1989 Econometrica (Markov Switching for regime)
- L-330 (v5 paradigm scope retain)
- `.cache/rawdata.parquet` BM_Ret probe (worst 15 months)
