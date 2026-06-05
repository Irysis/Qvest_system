# M4 Incrementality Protocol — Diebold-Mariano Test Plan for Forge Stage 5

**Optimizer Agent v1.0 design_phase_a**
**WT-D20260518_001**
**Cycle: 2026-05-19**

---

## 1. Why This Document Exists

**Risk-pkg challenge_flags RF-R3-M4-REDUNDANT**:
> "Bear sensor full agreement with M4 BOCPD = 87.7%; conditional P(M4_crisis | bear=1) = 31.4% (more informative tail metric). **Forge Stage 5 Diebold-Mariano test mandatory for incremental info content.** If not significant, sensor admission re-examination."

This protocol specifies the **exact DM test procedure** that Forge Stage 5 must execute to admit or reject bear sensor v2.0 admission (or trigger Path B replacement branch DB-A).

---

## 2. Diebold-Mariano Test Definition

### 2.1 Source

Diebold, F.X. and Mariano, R.S., 1995. "Comparing predictive accuracy." *Journal of Business & Economic Statistics*, 13(3), 253-263.

### 2.2 Test setup

Compare two predictive models on the same target. In our setting:

| Symbol | Definition |
|---|---|
| y_t | Binary bear indicator (KOSPI200 monthly return < -5%), n=437 |
| ŷ^M4_t | M4 BOCPD predicted bear probability, t-1 PIT |
| ŷ^bear_t | Bear sensor v2.0 ensemble p_bad_t (Forge Stage 4 emit) |
| L(y, ŷ) | Loss function — Brier score = (y - ŷ)² |
| d_t | Differential loss = L(y_t, ŷ^M4_t) - L(y_t, ŷ^bear_t) |
| μ_d | Mean differential loss = mean(d_t) |
| σ_d | NW-HAC SE with lag h = sqrt(T) (T=437, h=21) |

### 2.3 DM statistic

```
DM = μ_d / σ_d  ~  N(0, 1) under H0
```

H0: μ_d = 0 (equal predictive accuracy)
H1_2sided: μ_d ≠ 0
H1_1sided: μ_d > 0 (bear sensor superior to M4)

### 2.4 R implementation (forecast package)

```r
library(forecast)
# Predicted bear probability series
p_M4_t <- m4_bocpd_pbear_pit$prob  # from M4 schedule
p_bear_t <- bear_sensor_v2$p_bad_t  # Forge Stage 4 output

# Targets
y_t <- (BM_Ret_m < -0.05) * 1L  # binary bear

# Loss differentials
L_M4 <- (y_t - p_M4_t)^2
L_bear <- (y_t - p_bear_t)^2
d_t <- L_M4 - L_bear

# DM test 2-sided
dm_result <- dm.test(L_M4, L_bear, alternative = "two.sided",
                      h = 21L, power = 2L)
# 1-sided (bear sensor superior)
dm_result_1s <- dm.test(L_M4, L_bear, alternative = "greater",
                         h = 21L, power = 2L)

cat("DM 2s p-value:", dm_result$p.value, "\n")
cat("DM 1s (bear>M4) p-value:", dm_result_1s$p.value, "\n")
```

---

## 3. Decision Rule

### 3.1 Admission branches

| Outcome | Branch | Action |
|---|---|---|
| **dm_p_1s < 0.05** AND **mean(d_t) > 0** | A1 | bear sensor SUPERIOR → consider Path B (replacement) admission |
| **0.05 ≤ dm_p_1s < 0.15** AND **mean(d_t) > 0** | A2 | bear sensor MARGINAL improvement → admit Path A Sequential only (no replacement) |
| **dm_p_2s ≥ 0.15** | A3 | bear sensor STATISTICALLY EQUIVALENT to M4 → re-examine admission (87.7% redundancy concern realized) |
| **mean(d_t) < 0** AND **dm_p_1s < 0.05** | A4 | M4 SUPERIOR to bear sensor → REJECT bear admission |

### 3.2 Per-window stratified DM

Forge Stage 5 emits DM per walk-forward window (W1~W5):

| Window | Train | Test | DM_p_1s | mean(d_t) | Direction |
|---|---|---|---|---|---|
| W1 | 1999~2007 | 2008~2009 (GFC) | TBD | TBD | TBD |
| W2 | 2001~2010 | 2011~2012 (Euro debt) | TBD | TBD | TBD |
| W3 | 2003~2014 | 2015~2017 (China shock) | TBD | TBD | TBD |
| W4 | 2007~2017 | 2018~2019 (Q4 selloff + trade war) | TBD | TBD | TBD |
| W5 | 2009~2020 | 2021~2023 (COVID recovery + rate hike) | TBD | TBD | TBD |

**Pass criteria**: bear sensor SUPERIOR (A1 or A2) in **3+ of 5 windows** for Path A admission.

**Per-regime stratified DM** (Pesaran-Timmermann 3-regime):

| Regime | n_obs | DM_p_1s | Direction | Notes |
|---|---|---|---|---|
| LOW_VOL_QE | 120 | TBD | TBD | base rate ~10% bear |
| HIGH_VOL_TAPER | 98 | TBD | TBD | base rate ~25% bear |
| INFLATION | 31 | TBD | TBD | base rate ~30% bear, **bootstrap CI mandatory** |
| DEFAULT | 188 | TBD | TBD | base rate ~18% bear |

---

## 4. Additional Tests (Robustness)

### 4.1 Log-loss differential (alternative to Brier)

```r
L_M4_log <- -(y_t * log(p_M4_t + 1e-9) + (1 - y_t) * log(1 - p_M4_t + 1e-9))
L_bear_log <- -(y_t * log(p_bear_t + 1e-9) + (1 - y_t) * log(1 - p_bear_t + 1e-9))
dm_log <- dm.test(L_M4_log, L_bear_log, alternative = "two.sided", h = 21L)
```

### 4.2 Hit-rate differential (PT 1992 test)

```r
# Pesaran-Timmermann 1992 test for directional accuracy
library(rugarch)
pred_M4_binary <- (p_M4_t > 0.5) * 1L
pred_bear_binary <- (p_bear_t > tau_optimal_isotonic) * 1L
pt_M4 <- PTtest(y_t, pred_M4_binary)
pt_bear <- PTtest(y_t, pred_bear_binary)
# Compare hit rates
```

### 4.3 White's 2000 Reality Check (multi-test correction)

If multiple Forge Stage 3 calibrators tested simultaneously (isotonic / Platt / ENIR / ROC-reg / Beta), apply White (2000) reality check:

```r
# Bootstrap superior predictive ability test
# Reference: White 2000 "A reality check for data snooping" ECMA
```

n_calibrators = 5, n_thresholds = 3 (Youden / cost-weighted / F1) → multi-test correction factor 15.

---

## 5. Implementation Binding for Forge Stage 5

### 5.1 Required artifacts

| Artifact | Path | Content |
|---|---|---|
| `m4_pbear_series.csv` | stage_artifacts/WT_D20260518_001/ | M4 BOCPD t-1 PIT predicted bear prob series (Forge inherits from STR_1715 PG2 manifest M4 schedule) |
| `bear_v2_pbad_series.csv` | stage_artifacts/WT_D20260518_001/ | Bear sensor v2.0 Forge Stage 4 ensemble p_bad_t series |
| `dm_test_full_results.json` | stage_artifacts/WT_D20260518_001/ | Full-sample DM 2-sided + 1-sided p-values |
| `dm_test_per_window.csv` | stage_artifacts/WT_D20260518_001/ | Per-window DM (W1~W5) |
| `dm_test_per_regime.csv` | stage_artifacts/WT_D20260518_001/ | Per-regime DM (4 regimes) |
| `dm_admission_verdict.md` | stage_artifacts/WT_D20260518_001/ | Branch A1~A4 decision + Path A/B/C selection |

### 5.2 R script binding template

```r
# 02_Infrastructure/.../forge_stage5_dm_test.R (Forge Stage 5 emit)
library(forecast)
library(data.table)

# Inputs
p_M4 <- fread("stage_artifacts/WT_D20260518_001/m4_pbear_series.csv")
p_bear <- fread("stage_artifacts/WT_D20260518_001/bear_v2_pbad_series.csv")
bm <- read_parquet(".cache/benchmark.parquet")

# Align dates
dt <- merge(p_M4, p_bear, by = "sig_date")
dt <- merge(dt, bm[, .(Date = sig_date, BM_Ret_m)], by.x = "sig_date", by.y = "Date")
dt[, y := as.integer(BM_Ret_m < -0.05)]

# Brier losses
dt[, L_M4 := (y - p_M4_bocpd)^2]
dt[, L_bear := (y - p_bad_t)^2]

# DM test full sample
h_NW <- ceiling(sqrt(nrow(dt)))  # NW-HAC lag for monthly h=21 if n=437
dm_2s <- dm.test(dt$L_M4, dt$L_bear, h = h_NW, power = 2, alternative = "two.sided")
dm_1s <- dm.test(dt$L_M4, dt$L_bear, h = h_NW, power = 2, alternative = "greater")

# Per-window
windows <- list(
  W1 = list(start = "2008-01-31", end = "2009-12-31"),
  W2 = list(start = "2011-01-31", end = "2012-12-31"),
  W3 = list(start = "2015-01-31", end = "2017-12-31"),
  W4 = list(start = "2018-01-31", end = "2019-12-31"),
  W5 = list(start = "2021-01-31", end = "2023-12-31")
)
per_window <- rbindlist(lapply(names(windows), function(w) {
  sub <- dt[sig_date >= windows[[w]]$start & sig_date <= windows[[w]]$end]
  if (nrow(sub) < 12) return(NULL)
  dm <- dm.test(sub$L_M4, sub$L_bear, h = 6, power = 2, alternative = "greater")
  data.table(window = w, n = nrow(sub), dm_p_1s = dm$p.value,
             mean_diff = mean(sub$L_M4 - sub$L_bear))
}))

# Save results
jsonlite::write_json(
  list(
    full_sample = list(
      n = nrow(dt),
      dm_2s_p = dm_2s$p.value,
      dm_1s_p = dm_1s$p.value,
      mean_diff = mean(dt$L_M4 - dt$L_bear),
      NW_lag = h_NW
    ),
    per_window = per_window
  ),
  "stage_artifacts/WT_D20260518_001/dm_test_full_results.json",
  pretty = TRUE, auto_unbox = TRUE
)

# Decision rule
verdict <- if (dm_1s$p.value < 0.05 && mean(dt$L_M4 - dt$L_bear) > 0) {
  "A1_BEAR_SUPERIOR_consider_Path_B"
} else if (dm_1s$p.value < 0.15 && mean(dt$L_M4 - dt$L_bear) > 0) {
  "A2_BEAR_MARGINAL_admit_Path_A_only"
} else if (dm_2s$p.value >= 0.15) {
  "A3_EQUIVALENT_re_examine_admission"
} else {
  "A4_M4_SUPERIOR_reject_bear_admission"
}
```

---

## 6. Acceptance Criteria for Path A Admission

**ALL of the following required**:

1. Full-sample DM 1-sided p < 0.15 (bear sensor at least marginally informative)
2. Per-window DM 1-sided p < 0.15 in **3+ of 5 windows**
3. Per-regime DM significant in **HIGH_VOL_TAPER OR INFLATION** (where bear sensor design intended)
4. Bear sensor net_IR (vs PG2 production with Layer 6) − net_IR (PG2 production) > 0.10 in full sample
5. mean(d_t) > 0 (bear sensor reduces Brier loss on average)

**Reject** if any of:

- A4 verdict in full sample (M4 superior)
- DM significant in 0~1 of 5 windows (overfitting concern)
- Per-regime: LOW_VOL_QE p < 0.05 AND mean(d) < 0 (bear sensor harmful in calm regimes)
- Net IR ΔIR < 0 (cost-adjusted)

---

## 7. Acceptance Criteria for Path B (Replacement) Branch DB-A

**ALL of the following required** (stricter than Path A):

1. Full-sample DM 1-sided p < 0.05 (statistically significant)
2. Per-window DM 1-sided p < 0.05 in **3+ of 5 windows**
3. Per-regime DM significant in **HIGH_VOL_TAPER AND INFLATION**
4. Path B SR > Path A SR > Path C SR in full sample
5. Path B underlying TO_ann ≤ 6.0/yr cap satisfied
6. 도훈 mandate approval for manifest v2.3 → v3.0 architectural rename

---

## 8. References

- Diebold-Mariano 1995 JBES (DM test)
- Newey-West 1987 ECMA (HAC variance estimator)
- Pesaran-Timmermann 1992 JASA (directional accuracy test)
- White 2000 ECMA (Reality Check for data snooping)
- Harvey-Liu-Zhu 2016 RFS (multi-testing correction)
- forecast::dm.test() (Hyndman R implementation)

---

## 9. Status

**Current**: Protocol specified. Bind Forge Stage 5.
**Pending**: Forge Stage 4 emits `bear_v2_pbad_series.csv` (Forge cycle prerequisite).
**Pending**: STR_1715 PG2 manifest M4 schedule extracted to `m4_pbear_series.csv` (Forge prerequisite — inherited).
