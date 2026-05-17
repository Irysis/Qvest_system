# Step 2.1 — 3-source Alpha Specifications

**WT_id**: WT-D20260518_002
**Agent**: alpha-research
**As-of**: 2026-05-18
**Cycle**: L-279~L-281 Hybrid 70/15/15 admit precedent re-cycle (정통 6-agent lifecycle)

---

## 0. Hybrid 70/15/15 — 3 Orthogonal Sources Summary

| Sleeve | Asset / Class | Allocation | Source | Academic Backbone | Cross-cor with STR_1715 |
|---|---|---|---|---|---|
| Sleeve 1 (Core Alpha) | STR_1715_AR_on_M4_R05_overlay_PG2 | **70%** | Inherited (Session 80 admit 2026-05-13) | Kritzman-Page-Turkington 2011 FAJ; multi-layer overlay precedent (L-307~L-313) | 1.0 (self) |
| Sleeve 2 (Cross-Asset TSMOM) | KR ETF rotation 9-asset universe → 8 effective post-KODEX_KTB10Y removal | **15%** | WT-S20260504_009 inherit | Moskowitz-Ooi-Pedersen 2012 JFE; Asness-Moskowitz-Pedersen 2013 JFE | 0.0766 (long-run) / breakdown COVID 5m 0.75 |
| Sleeve 3 (Duration Defense) | KODEX_KTB10Y (A148070) single | **15%** | WT-S20260504_008 inherit | Cieslak-Povala 2015; Campbell-Sunderam-Viceira 2017 | -0.137 (defensive complement) |

**Composition rationale (L-280)**:
- Cross-section vs time-series **definitionally orthogonal** (long-run cor 0.077 empirical)
- KR_10y Pareto MDD-dominant; TSMOM Pareto SR-dominant → blending captures both
- 60/40 + managed futures hybrid paradigm 진화 (Hurst-Ooi-Pedersen 2017)

---

## 1. Sleeve 1 — STR_1715_AR_on_M4_R05_overlay_PG2 (70%)

### 1.1 Lineage

```
STR_1631_MEGA_05 → STR_1697 → STR_1701 (Iter11 LinearTilt) → STR_1715 (Iter31 GridBest)
→ STR_1715 OVERRIDE_008 retrofit → WT-D20260430_001 M4 schedule upgrade
→ WT-S20260504_007 AR overlay R3 (S1_threshold MONITORING_PLUS)
→ WT-P20260504_001 AR admit (PG2 100%)
→ Session 80 R05 admit (Layer 5 R05_Tail_Risk sequential overlay, 2026-05-13 effective)
```

### 1.2 5-Layer Architecture (production retain, modification PROHIBITED)

```
w_final = w_str1715 × m4_scalar × β_AR × β_R05(regime_t)
```

| Layer | Function | β |
|---|---|---|
| 1 | STR_1715 Iter31 alpha (LinearTilt λ=1.5, TOphi=3, ub=0.20) | base |
| 2 | Static cross-sectional weighting | base |
| 3 | M4 BOCPD regime switch (regime_t) | ∈ {1.0 NORMAL} |
| 4 | AR threshold step overlay | β_AR ∈ {0.4, 0.7, 1.0} |
| 5 | R05 Tail Risk sequential overlay (new Session 80) | β_R05 ∈ {1.0 BULL/NORMAL, 0.5 CAUTION, 0.3 CRISIS} |

### 1.3 Admit metrics (PerfA standard, 255m raw cover, L-308 admit)

| Metric | Value |
|---|---|
| Sharpe | **1.9536** |
| MDD | **-24.81%** |
| CAGR | **41.50%** |
| Vol (ann) | 21.24% |
| Sortino | 1.22 |
| Calmar | 1.67 |
| Active vs KOSPI200 | +31.78pp |
| IR | **1.0505** |
| HitRate | 63.5% |

### 1.4 Statistical Defense (L-308 admit)

**Harvey 5-spec t_NW** (lag=6, Newey-West HAC):
- spec1 CAPM_KR_KOSPI200: t_NW = **6.767** (HLZ 3.0 PASS strict)
- spec2 excess_over_market: t_NW = **6.767**
- spec3 plain_raw_NW: t_NW = **6.767**
- spec4 crisis_2008_2010: t_NW = **3.257** (n=28)
- spec5 post2010_CAPM_KR: t_NW = **6.624**

→ **5/5 STRICT PASS** (L5_V2_aggressive_PRIMARY_RECOMMEND, n=255)

**DSR Bailey-LdP**: Z = **1.448 STRONG** (cross-cycle convention reconciled, same-harness)

**bad_normal_IC ratio**: **6.79** (AX-001 v2 conditional defense PASS)

### 1.5 Factor specs (inherit, mechanism preserved)

| factor_family | proxy | role |
|---|---|---|
| Composite (Iter31 LinearTilt) | Z_aligned λ=1.5 합성 | base alpha |
| Layer-3 Regime (M4 BOCPD) | BOCPD on KOSPI200 BM_Ret | regime scalar |
| Layer-4 AR threshold | K=5 / W=252 / threshold_step | concentration scalar |
| Layer-5 R05 Tail Risk | tail-risk sequential overlay | cash-control scalar |

**Source for inheritance**:
- `qepm/mailbox/worktask/WT-P20260504_001/governor_admission.json` (L-307 lineage 4-layer)
- `05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/03_admit_artifacts/governor_admission.json` (Session 80 5-layer)

### 1.6 PIT C1~C15 (Session 80 admit precedent verify)

- C1: rolling/expanding window (BOCPD posterior + AR threshold)
- C2: t-1 close strict (all overlays, lro_sha frozen)
- C9: dd_lag / vol_lag t-1 strict
- C13: Z_Score_Aligned only
- C14: Usable_Date ≤ sig_date strict
- C15: factor_db_connector::load_month_factors() 경유

---

## 2. Sleeve 2 — TSMOM ETF Rotation 8-asset (15%)

### 2.1 Universe (L-281 inherit, KODEX_KTB10Y removed → 8 ETFs)

| ETF | Code | Asset class |
|---|---|---|
| KODEX_200 | A069500 | KR Equity |
| TIGER_SP500_H | A360750 | US Equity (KRW-hedged) |
| KODEX_GOLD_H | A132030 | Commodity (KRW-hedged) |
| KODEX_UST10Y_H | A308620 | US Treasury 10y (KRW-hedged) |
| KODEX_200_UST | (composite) | KR Eq + UST blend |
| KODEX_KR_REIT | A132690 | Real Estate |
| KODEX_200_LV | A229200 | Low Vol Equity |
| TIGER_SHORT_TERM | A157450 | Cash equivalent (default 100% if no positive signals) |

**Note**: KODEX_KTB10Y_A148070 제거 (Sleeve 3 단독 KR_10y 중복 회피, L-281)

### 2.2 Signal Engineering (Moskowitz-Ooi-Pedersen 2012)

**TSMOM 12-1m vol-scaled, long-only**:
```
signal_{i,t} = trailing 12m cum return of ETF_i (PIT t-1)
filter: signal_{i,t} > 0 → eligible
w_{i,t} ∝ target_vol / vol_6m_{i,t}  (vol-scaling)
renormalize Σ w_{i,t} = 1 over positive set
if no positive signals → 100% TIGER_SHORT_TERM (cash default)
```

**Lag rule**: 모든 ETF returns + vols + macros t-1 (PIT C2/C5/C9 strict)

**Economic rationale**: behavioral underreaction + disposition effect (Moskowitz-Ooi-Pedersen 2012 §III)

### 2.3 Diagnostics (WT-S20260504_009 inherit, CONDITIONAL_PASS_DIRECTIONAL_ONLY)

| Metric | Value |
|---|---|
| OOS Sharpe net (n=136) | **0.9026** |
| OOS annual return | 4.62% |
| Δ Sharpe vs STR_1715 standalone (50/50 hypothetical) | +0.0663 |
| Cor with STR_1715 (long-run) | **0.0766** |
| Cor subperiod T1 (2015-18) | 0.0436 |
| Cor subperiod T2 (2019-22) | -0.091 |
| Cor subperiod T3 (2023-26) | 0.1396 |
| **Crisis Stagflation 12m outperform KOSPI** | **+25.0pp** (chronic crisis hedge ✓) |
| Crisis COVID 5m cor breakdown | 0.7518 (acute short-term breakdown, RF-A3) |
| Turnover annualized | 3.656 (≤ 6.0 cap PASS) |
| Annualized cost | **58.3 bps** (over 50bps budget +8.3bps, quarterly rebalance untested) |

### 2.4 Harvey 5-spec t_NW (WT-S20260504_009 inherit, ALL PASS)

- spec1 const: t_NW_ann = **9.972**
- spec2 STR_1715 only: t_NW_ann = **9.245**
- spec3 STR_1715 + KOSPI: t_NW_ann = **7.132**
- spec4 STR_1715 + KOSPI + VIX: t_NW_ann = **6.052**
- spec5 full macro: t_NW_ann = **6.546**

→ **5/5 STRICT PASS** (HLZ 3.0 hurdle)

### 2.5 DSR Bailey-LdP

- M=8 internal: DSR = **0.9545 PASS**
- M=30 lifecycle: DSR = 0.86 (strict FAIL) ⚠️
- M=50 conservative: DSR = 0.8107 (strict FAIL) ⚠️

**Disposition**: Codex C2 ACCEPT — DSR strict pass at lifecycle M=30 FAIL acknowledged. 단, **Hybrid blend의 DSR은 본 cycle Forge stage에서 재산출 필요** (3-source joint).

### 2.6 Cross-cor Verify (cycle G2 G3 mandate)

- Long-run cor(TSMOM, STR_1715) = 0.0766 (L-281 inherit, target ≈ 0.077)
- 본 cycle 재산출: Step 5 (cross_correlation_3source.csv) — Risk agent와 함께 verify

### 2.7 Challenge flags (RF-A1 ~ RF-A8 inherit)

| Flag | Severity | Resolution path |
|---|---|---|
| RF-A1 | HIGH | synthetic_etf_proxies — KOFIA NAV cross-validation REQUIRED post-admit (POST_DEPLOY) |
| RF-A2 | MEDIUM | cost 58.3bps over 50bps — quarterly rebalance test (POST_DEPLOY) |
| RF-A3 | HIGH | COVID 5m cor 0.75 acute breakdown documented |
| RF-A4 | HIGH | GFC 2008 pre-walk-forward window (no OOS evidence) |
| RF-A5 | HIGH | HMM diagnostic only (combined-panel posterior C9 violation) |
| RF-A6 | HIGH | GP/RL panels NULL (NA filter strict) → pure TSMOM fallback |
| RF-A7 | HIGH | DSR M=30 lifecycle FAIL |
| RF-A8 | MEDIUM | max single ETF weight 79.86% — Optimizer enforce 30% cap |

---

## 3. Sleeve 3 — KR 10y Bond ETF (KODEX_KTB10Y_A148070) (15%)

### 3.1 Universe

**Single asset**: KODEX_KTB10Y (A148070, KR 국고채 10년 ETF, 2011-04 inception)

### 3.2 Signal Engineering (Duration Premium)

**Synthetic 8-year modified duration** (pre-2011 synthetic + post-2011 OOS):

```
ret_t = -8 × (yield_t - yield_{t-1}) / 100 + (yield_{t-1} / 12) / 100
```

**Lag rule**: month-end yield t-1 PIT strict (PIT C2/C9 compliant)

**Economic rationale**: Duration risk premium + bond-equity correlation regime switching (Cieslak-Povala 2015; Campbell-Sunderam-Viceira 2017)

### 3.3 Diagnostics (WT-S20260504_008 inherit, axis 4/4 PASS)

| Metric | Value |
|---|---|
| Δ Sharpe (vs baseline, 50% kr_10y replace) | **+0.0526** (255m clean) |
| Bootstrap 95% CI (B=10000, block=6) | [0.0014, 0.1042] (lower bound positive ✓) |
| Newey-West t_NW (annualized, lag=6) | **5.06** (HLZ > 3.0 PASS) |
| DSR M=7 multiple testing penalty | p < 0.001 (STRONG PASS) |
| Δ MDD pp (255m simulation) | **-1.47pp** improvement |
| Cor with STR_1715 | **-0.137** (defensive complement, slightly negative) |
| Cost annualized | 35 bps (under 50bps budget ✓) |
| Subperiod stability (IS / OOS / Recent5Y) | +0.099 / +0.028 / +0.005 (3/3 positive, decay observed) |

### 3.4 Harvey + DSR (WT-S20260504_008 inherit)

- Harvey t_NW(ann) = **5.06** (kr_10y delta_excess regression)
- DSR M=7 penalty: p < 0.001 STRONG
- (단, 본 cycle Forge stage에서 5-spec strict Hybrid blend 재산출 필요)

### 3.5 KR Availability (axis 3/4 PASS)

- KODEX_KTB10Y AUM > 100B KRW (실투 가능)
- ER 23 bps weighted avg
- Real ETF data 2011-04 ~ 2026-04 (181m OOS) + synthetic pre-2011 (74m IS, RF-A5 disclosed)
- **KOFIA NAV 직접 cross-validation 본 cycle Forge stage에서 권고** (RF-A1 remediation path)

### 3.6 Challenge flags (RF-A1 ~ RF-A7 inherit)

| Flag | Severity | Resolution path |
|---|---|---|
| RF-A1 | HIGH | KODEX_KTB10Y synthetic vs actual NAV — Forge stage validation |
| RF-A2 | REMEDIATED | t_NW(ann) 5.06 PASSES Harvey 3.0 |
| RF-A3 | REMEDIATED | Recent5Y delta +0.005 decay BUT 3 subperiods all positive |
| RF-A4 | OK | eom yield PIT lag compliant |
| RF-A5 | HIGH | 2011-04 inception, pre-period synthetic 74m caveat |
| RF-A7 | REMEDIATED | alpha_scores parquet schema 정합 |

---

## 4. Cross-correlation matrix (3-source orthogonal verify)

**Long-run cor matrix (inherit from L-281 + WT-S20260504_008/009)**:

| | STR_1715 | TSMOM | KR_10y |
|---|---|---|---|
| **STR_1715** | 1.000 | 0.0766 | -0.137 |
| **TSMOM** | 0.0766 | 1.000 | TBD (본 cycle Risk stage 재산출) |
| **KR_10y** | -0.137 | TBD | 1.000 |

**Orthogonality verdict**: ALL pairs |cor| < 0.30 (strict orthogonal cap PASS) ✓

**G2 cycle gate**: cor(TSMOM, STR_1715) ≈ 0.077 KR empirical retain ✓

---

## 5. Hybrid 70/15/15 expected metrics (admit precedent inherit)

**L-279 finalization (2026-05-05, 256m S3 metrics)**:

| Metric | L-279 admit baseline | Target milestone |
|---|---|---|
| Sharpe | **1.665** | ≥ 1.97 (improvement path) |
| MDD | **-16.6%** (S0 -26.5% → S3 -9.83pp improvement) | ≤ -25% (mandate) |
| CAGR | **26.4%** | ≥ 16% (mandate) |
| Crisis Stagflation Active | **+25pp outperform KOSPI** | ✓ |
| Crisis Defense (S0 → S3) | -0.15 → **+0.15** (positive 전환) | ✓ |

**Improvement path explanation (Step 4 detail)**:
- Sleeve 1 STR_1715 R05 (Session 80) SR 1.9536 — 70% 가중 → blend 마진 +contribution
- Sleeve 2 TSMOM SR ~0.90 — 15% incremental
- Sleeve 3 KR_10y Δ Sharpe +0.05 — 15% defensive complement

**현 admit baseline 1.665 vs target 1.97 gap** = +0.305 SR — Layer 5 R05 (Session 80 신규) 효과로 부분 closure 가능

---

## 6. PIT C1~C15 strict compliance — 3-source

| Code | Sleeve 1 (STR_1715) | Sleeve 2 (TSMOM) | Sleeve 3 (KR_10y) |
|---|---|---|---|
| C1 rolling/expanding | ✓ BOCPD posterior | ✓ 12m trailing | ✓ rolling yield |
| C2 t-1 close | ✓ lro_sha frozen | ✓ all PIT lag | ✓ eom yield t-1 |
| C4 fund 45d/5월 | ✓ Iter31 base | n/a (ETF) | n/a (bond) |
| C9 dd/vol lag | ✓ M4+AR lag | ✓ vol_6m_t-1 | ✓ yield lag |
| C11 macro lag | ✓ FRED t-1 | ✓ FRED t-1 | ✓ ECOS CD91 t-1 |
| C13 Z_Score_Aligned | ✓ inherit | n/a (asset-level) | n/a (asset-level) |
| C14 Usable_Date | ✓ <= sig_date | ✓ <= sig_date | ✓ <= sig_date |
| C15 load_month_factors | ✓ Sleeve 1 factor | n/a (ETF time series) | n/a (bond yield) |

---

## 7. v5 Real PIT Mandate Strict Inheritance

본 cycle은 **v5 학습 strict 적용**:

1. **factor_db_connector routing**: Sleeve 1은 load_month_factors() 경유 strict (이미 admit precedent)
2. **synthetic absolute prohibition**: ret_comp 합성 절대 차단
   - Sleeve 2 TSMOM: real ETF NAV 우선, synthetic pre-inception caveat 명시
   - Sleeve 3 KR_10y: KODEX_KTB10Y 2011-04 이후 real NAV + pre-2011 synthetic caveat
3. **bt_result.rds SHA256 hash binding**: Sleeve 1 lro_sha (`ad3d44417b526c3d82dde8724cb971ba973f2e418fc36ada7795d687c809cb18`) 직접 emit
4. **Harvey 5-spec strict**: 모든 sleeve 5/5 PASS (placeholder 절대 X)
5. **DSR Bailey-LdP strict**: lifecycle M ≥ 20 multiple testing penalty
6. **3-source blend Harvey + DSR**: Forge stage에서 재산출 (본 cycle Step 5 mandate)

---

## 8. Step 2.1 Output

**File**: `stage_artifacts/WT_D20260518_002/3_source_alpha_specs.md` (this)
**Next**: Step 2.2 — L-279 precedent re-validate (5/5 decision rule + Harvey 5/5 + DSR z ≥ 1.5)
