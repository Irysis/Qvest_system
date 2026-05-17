# Step 2.3 — Real PIT Data Sourcing Protocol (v5 학습 strict)

**WT_id**: WT-D20260518_002
**Agent**: alpha-research
**Mandate**: factor_db_connector::load_month_factors() 경유 strict + synthetic 절대 차단 + SHA256 hash binding

---

## 1. v5 Lifecycle 학습 strict — Mandate Inheritance

### 1.1 학습 내용 (request.json inherit)

| Mandate Field | Strict Application |
|---|---|
| `factor_db_connector_routing` | load_month_factors() 경유 strict (직접 parquet load 금지, PIT C15) |
| `synthetic_absolute_prohibition` | ret_comp 합성 절대 차단 (v4 학습 retain) |
| `bt_result_sha256_hash_binding` | raw PIT data hash 직접 emit (lro_sha frozen) |
| `harvey_5spec_strict` | CAPM/FF3/FF5/Carhart4/FF6 정식 regression (placeholder X) |
| `dsr_bailey_ldp_strict` | n_trials ≥ 20 multiple testing penalty |

### 1.2 5-cycle empirical pattern (WT-D20260517_005 retire scoped 5/13~5/17)

DPL Path A 5-cycle 가운데 동일 patten:
- **PIT lookahead detect → Codex Round CORROBORATE → no-admission**
- → 본 cycle은 정통 lifecycle Codex Round + AX-008 3/3 target strict (회피 절대 X)

---

## 2. Source 1 — STR_1715 (Sleeve 1, 70%)

### 2.1 Factor DB Routing (PIT C15 strict)

**Path**: `02_Infrastructure/factor_db/factor_db_connector.R`

```r
source("02_Infrastructure/factor_db/factor_db_connector.R")
factors <- load_month_factors(sig_date)  # KR_top342 default
```

**OR** Production retain (lro_sha frozen):
```r
# 본 cycle은 STR_1715 alpha modification 금지 → production inherit
str1715_weights <- read.csv("05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/02_holdings_universe/weights_267m_timeseries.csv")
```

### 2.2 SHA256 hash binding

**Sleeve 1 lro_sha** (Session 80 admit retain):
```
ad3d44417b526c3d82dde8724cb971ba973f2e418fc36ada7795d687c809cb18
```

**alpha_package.json emit 의무** — `lro_sha` field 명시.

### 2.3 PIT lag rules

| Data Class | Lag |
|---|---|
| Fundamental quarterly | 45d |
| Fundamental annual | 5월 (May) |
| Price | t-1 close |
| Investor flow | t-1 settlement |
| Macro FRED/ECOS | t-1 |
| IC history (Z_aligned) | Usable_Date ≤ sig_date |

### 2.4 Synthetic prohibition guard

**Forbidden patterns** (절대 차단):
```r
# WRONG (v4 학습 위반)
ret_comp <- 0.7 * ret_str1715 + 0.15 * ret_tsmom + 0.15 * ret_kr10y

# RIGHT (PerfA standard, Backtest Contract v1.0)
Return.portfolio(R = ret_matrix, weights = c(0.7, 0.15, 0.15), rebalance_on = "months")
```

**Detection trigger**: `prod(1+r)-1`, `cumprod(1+r)`, manual arithmetic SR via mean/sd ratio.

---

## 3. Source 2 — TSMOM ETF Rotation (Sleeve 2, 15%)

### 3.1 Real KR ETF universe (KOFIA NAV verification REQUIRED)

| ETF | Code | Inception | Real NAV Source |
|---|---|---|---|
| KODEX_200 | A069500 | 2002-10 | KOFIA NAV |
| TIGER_SP500_H | A360750 | 2020-08 | KOFIA NAV (synthetic pre-2020) |
| KODEX_GOLD_H | A132030 | 2010-10 | KOFIA NAV |
| KODEX_UST10Y_H | A308620 | 2018-10 | KOFIA NAV |
| KODEX_200_UST | (composite) | — | composite (KR Eq + UST) |
| KODEX_KR_REIT | A132690 | 2010-10 | KOFIA NAV |
| KODEX_200_LV | A229200 | 2015-12 | KOFIA NAV |
| TIGER_SHORT_TERM | A157450 | 2012-04 | KOFIA NAV (cash equivalent) |

### 3.2 KOFIA NAV Cross-validation (POST_DEPLOY_AR_006 binding, RF-A1)

**WT-S20260504_009 inherit caveat**: All 9 ETF returns synthesized from KOSPI/FRED/macros. Actual KOFIA NAV cross-validation REQUIRED in follow-up promotion WT.

**본 cycle Forge stage strict**:
- KOFIA NAV API 직접 fetch (post-inception periods)
- Pre-inception periods: synthetic via FRED + KRW spot + asset class proxy (caveat 명시)
- Cross-validation: synthetic vs actual NAV correlation > 0.95 (post-inception 비교)
- Architect concurrent verification (AX-008 3/3 target)

### 3.3 PIT lag rules (TSMOM signal)

```r
# Signal at sig_date_t (PIT C2/C5/C9 strict)
trailing_12m_return = prod(1 + ret[(t-13):(t-1)]) - 1   # exclude current month
trailing_12m_return = trailing_12m_return - ret[t-1]    # 12m-1m skip lag
vol_6m = sd(ret[(t-7):(t-1)]) * sqrt(12)                # exclude current month
target_vol = 0.10                                         # 10% annualized target
w_i = target_vol / vol_6m_i                              # scale per asset
```

### 3.4 Synthetic prohibition (Sleeve 2 specific)

- TSMOM signal: real ETF return time-series only (post-inception)
- pre-inception synthetic with caveat (challenge_flags RF-A1)
- Hybrid blend: **PerfA Return.portfolio strict** (manual arithmetic 절대 X)

---

## 4. Source 3 — KR 10y Bond ETF (Sleeve 3, 15%)

### 4.1 Real KR ETF universe

**Single asset**: KODEX_KTB10Y (A148070, KR 국고채 10년 ETF, 2011-04 inception)

### 4.2 KOFIA NAV Cross-validation (RF-A1 remediation path)

- 2011-04 ~ 2026-04: real KOFIA NAV (181m OOS)
- pre-2011 (74m IS): synthetic via `ret_t = -8 × (yield_t - yield_{t-1}) / 100 + (yield_{t-1} / 12) / 100`
- WT-S20260504_008 Codex C1 inherit: Asness 2013 §3 학술 precedent + research_wt scope

**본 cycle Forge stage strict**: ECOS KR Gov 10y yield 시계열 + KOFIA KODEX_KTB10Y NAV cross-validation.

### 4.3 PIT lag rules

```r
# yield t-1 strict (PIT C2/C9)
yield_eom_t_minus_1 = ECOS_KR_Gov10Y[eom_lag_1]
ret_t = -8 * (yield_eom_t - yield_eom_t_minus_1) / 100 + (yield_eom_t_minus_1 / 12) / 100
```

### 4.4 Subperiod stability check

- IS (74m pre-2011 synthetic): Δ Sharpe +0.099
- OOS (181m post-2011 real NAV): Δ Sharpe +0.028
- Recent 5Y (2021-26): Δ Sharpe +0.005 (decay observed, RF-A3 disclosed)

---

## 5. Hybrid Blend — Backtest Contract v1.0 Strict

### 5.1 PerformanceAnalytics standard functions ONLY

**Allowed**:
```r
library(PerformanceAnalytics)

# 1. Joint return computation (NOT manual arithmetic)
ret_hybrid <- Return.portfolio(
  R = cbind(ret_str1715, ret_tsmom, ret_kr10y),
  weights = c(0.70, 0.15, 0.15),
  rebalance_on = "months",
  verbose = FALSE
)

# 2. Cumulative return
nav_hybrid <- Return.cumulative(ret_hybrid)

# 3. Sharpe ratio
sr_hybrid <- SharpeRatio.annualized(ret_hybrid, Rf = 0, scale = 12)

# 4. MDD
mdd_hybrid <- maxDrawdown(ret_hybrid)

# 5. Annual returns
ann_ret <- apply.monthly(ret_hybrid, FUN = Return.cumulative)
ann_table <- table.AnnualizedReturns(ret_hybrid, Rf = 0)
```

**Forbidden**:
```r
# WRONG (Charter v1.4 §13 violation, L-282 lesson)
sr_hybrid <- mean(ret_hybrid) / sd(ret_hybrid) * sqrt(12)   # manual arithmetic
nav_hybrid <- prod(1 + ret_hybrid) - 1                       # manual cumulation
ret_hybrid <- 0.7 * ret_str1715 + 0.15 * ret_tsmom + 0.15 * ret_kr10y   # self合成
```

### 5.2 bt_result.rds emit (Backtest Contract v1.0)

**10-component bt_result list** (Forge stage Step 6 mandate):
1. `manifest`
2. `strategy_spec`
3. `nav`
4. `period_returns`
5. `holdings`
6. `benchmark_returns`
7. `metrics`
8. `benchmark_compare`
9. `rolling_metrics`
10. `drawdowns`
11. `audit`

### 5.3 SHA256 hash binding (3-source)

**Sleeve 1**: lro_sha frozen (Session 80 admit)
**Sleeve 2**: bt_result_tsmom SHA256 hash emit
**Sleeve 3**: bt_result_kr10y SHA256 hash emit
**Hybrid blend**: bt_result_hybrid SHA256 hash emit

→ alpha_package.json `ic_provenance` + governor_admission.json `lro_sha_hybrid_frozen` field 명시.

---

## 6. Harvey 5-spec Strict (Forge stage mandate)

### 6.1 Specifications (각 sleeve + Hybrid blend)

| Spec | Regression Model |
|---|---|
| **spec1** | CAPM (KR_KOSPI200 mkt factor) |
| **spec2** | FF3 (MKT + SMB + HML) |
| **spec3** | Carhart4 (FF3 + MOM) |
| **spec4** | FF5 (MKT + SMB + HML + RMW + CMA) |
| **spec5** | FF6 (FF5 + MOM) |

### 6.2 Threshold (HLZ 2016)

- t_NW > 3.0 strict (Newey-West HAC lag=6)
- 5-spec ALL PASS = STRICT majority

### 6.3 Source data

- KR FF factors: 자체 구축 (lift-out from factor_db Z_aligned) or KCMI dataset (POST_DEPLOY_AR_010 binding)
- Hybrid blend ret_net regression on 5-spec factor matrix

---

## 7. DSR Strict (Forge stage mandate)

### 7.1 Bailey-Lopez de Prado 2014 (Deflated Sharpe Ratio)

```r
source("02_Infrastructure/cpp/rcpp_hotspots.R")
dsr <- bootstrap_dsr_fast(
  returns = ret_hybrid,
  n_trials = 20L,  # M ≥ 20 lifecycle multiple testing penalty (L-279 strict)
  B = 10000L,
  seed = 42L
)
```

### 7.2 Z-score threshold

- z ≥ 1.5 (본 cycle G6 gate)
- L-279 admit precedent: z = 6.0973 STRONG

### 7.3 n_trials cumulative count

- WT-S20260504_007 (4 overlay variants) + WT-S20260504_008 (7 candidates) + WT-S20260504_009 (6 methods × 3 subperiods = 18) = 29 → round to **n_trials = 30**
- 본 cycle Forge stage strict M=30 lifecycle penalty (WT-S20260504_009 DSR M=30 FAIL → Hybrid blend 재산출 strict)

---

## 8. Architect Concurrent Verification (AX-008 3/3 target)

### 8.1 Forge fresh + Codex post-resolution + Architect PASS

**WT-D20260518_002 strict 3/3 target**:
1. **Forge fresh**: 본 cycle Hybrid 70/15/15 256m+ backtest (real PIT data)
2. **Codex post-resolution**: Codex Round 5단계 (REVISE/REJECT 시 challenge_note rebuttal)
3. **Architect PASS**: Independent code path reproduction (4-decimal match × 6 metrics × variants)

### 8.2 Architect 검증 contract

- 별도 code path (base R merge + manual shift_lag, NOT factor_engine wrapper)
- 6 metrics: Sharpe / CAGR / MDD / Vol / Sortino / Calmar
- 4-decimal tolerance (0.005 strict)
- LRO frozen SHA match exact (Sleeve 1)
- PIT C1~C15 walk-through (no violation)

---

## 9. Step 2.3 Output

**File**: `stage_artifacts/WT_D20260518_002/real_pit_sourcing_protocol.md` (this)
**Next**: Step 2.4 — SR improvement path to milestone 1.97+ (target gap closure)
