# Macro Overlay Signal Design — Iter 21 (WT-D20260427_005)

## Objective (Layer-Level Mandate)
- **Alpha**: STR_1701 그대로 inheritance (cor ≥ 0.95, panel as-is, no recompute)
- **Optimizer**: Iter 11 LinTilt λ=1.0 baseline 그대로 (본 alpha sprint 산출물 변경 X)
- **Layer 신규**: continuous **Macro Stress Index (MSI)** — Optimizer가 cash sleeve / weight bound / TO budget를 dynamic하게 조정할 수 있도록 alpha_scores parquet에 attach
- **평가**: PG2 blended SR > 1.4625 baseline + 위기 구간 MDD 추가 완화 + 평시 alpha 보존

## Mandate Compliance
| Item | Iter 18 baseline | Iter 21 (this WT) |
|------|------------------|--------------------|
| score_str1701 panel | inherited as-is | **inherited as-is (cor=1)** |
| Universe filter | KOSPI200∪KOSDAQ150, AvgTV20≥2e8 | preserved |
| Optimizer mechanism | LinTilt λ=1.0 (downstream) | preserved (downstream) |
| Macro overlay | regime_state (4-state discrete) | **continuous MSI ∈ [0,1]** + 4-state regime_state |

## Macro Signal Source (KR-only mandate compliant)

### Tier 1 — KR Domestic Stress Indicators
1. **KOSPI200 60d realized vol** (from RAWDATA BM_Ret) — equity vol stress
2. **KOSPI200 12M momentum / 252d vol** (Sharpe-like; Faber 2007 GTAA)
3. **KR yield curve slope** = KR_Gov10Y − KR_Gov3Y (ECOS) — recession proxy
4. **KR Corporate spread** = KR_CorpBBB − KR_Gov3Y (ECOS) — credit stress
5. **USD/KRW 30d momentum** (ECOS ecos_krw_usd) — KR currency stress (foreign capital flight proxy, KR-relevant)

### Tier 2 — Cross-Validation (External, weight 0)
- VIX (FRED) — cross-validation only, NOT used as input (L-454 KR internals dominate)
- Brent crude 60d vol — drop (no KR-specific copper/oil cache verified)

### Aggregation: Macro Stress Index (MSI)
```
For each Tier 1 signal s_k(t):
  z_k(t) = (s_k(t) − mu_k(expanding to t-1)) / sigma_k(expanding to t-1)
  z_k_clip(t) = clip(z_k(t), -3, 3)
  
  Direction-aligned: stress_k(t) = sign × z_k_clip(t)
    - vol_60d → +1 (high vol = stress)
    - mom/vol → -1 (low Sharpe = stress)
    - yield_slope → -1 (inversion = stress)
    - corp_spread → +1 (wide spread = stress)
    - krw_mom_30d → +1 (KRW weakening = stress)

MSI(t) = mean(stress_k(t)) for k available
MSI_norm(t) = pnorm(MSI(t))  ∈ [0, 1]  (CDF mapping)
```

PIT: All inputs use **expanding window** mean/std with **t-1 lag** (no full-sample). MSI computed at month-end sig_date using data through t-1.

## PIT Compliance (C1~C15)
- **C1**: expanding window stats only (no full-sample mu/sigma)
- **C2**: t-1 lag enforced (`shift(x, 1)` before z-score)
- **C5**: overlay signal computed on t-1 data, applied at t
- **C9**: MSI matches dd_lag/vol_lag pattern: `c(NA, head(msi, -1))` if Optimizer reads
- **C11**: KR-only inputs (yield/spread/krw); FRED VIX recorded as cross-val NOT input
- **C13**: direction-align via signed z-score (no NEGATE_FACTORS, no FLIP_SIGN)

## Output Columns Added to alpha_scores.parquet
| Column | Definition | Range |
|--------|-----------|-------|
| `score_str1701` | inherited STR_1701 (no change) | preserved |
| `score_eff` | inherited (no change) | preserved |
| `confidence` | inherited (no change) | preserved |
| `fwd_1m` | inherited | preserved |
| **`macro_stress_z_kospi_vol`** | KOSPI 60d vol z-score (expanding) | ~[-3, 3] |
| **`macro_stress_z_kospi_mom_vol`** | KOSPI 12M mom/vol z-score (sign flipped) | ~[-3, 3] |
| **`macro_stress_z_yield_slope`** | KR (Gov10Y-Gov3Y) z-score (sign flipped) | ~[-3, 3] |
| **`macro_stress_z_corp_spread`** | KR Corp BBB spread z-score | ~[-3, 3] |
| **`macro_stress_z_krw_mom`** | USD/KRW 30d mom z-score | ~[-3, 3] |
| **`msi_raw`** | mean of available stress_z components | ~[-3, 3] |
| **`msi_norm`** | pnorm(msi_raw) ∈ [0, 1] | [0, 1] |
| **`regime_state_legacy`** | 4-state from msi_norm quantile (BULL/NORMAL/CAUTION/CRISIS) | discrete |

## AX-001 v2 4-Metric Design
| Metric | Definition | Computation |
|--------|-----------|-------------|
| **crisis_alpha** | mean fwd_1m of top-decile stocks under msi_norm > 0.75 | per sig_date avg |
| **core_mdd_relief** | Counterfactual: STR_1701 + dynamic cash (msi-based) MDD vs constant 0% cash | analytical proxy |
| **bad_normal_ic_ratio** | Spearman IC under msi_norm > 0.75 / Spearman IC under msi_norm < 0.5 | regime-conditional |
| **harvey_t** | inherited from STR_1701 base (audit only) | t = 0.30 (5-spec NW lag3) |

## Optimizer-side Usage (Downstream, NOT this WT)
This sprint produces macro signal **only**. Optimizer agent (next WT stage) will:
- `cash_pct(t) = clamp(0.0 + msi_norm(t-1) × 0.50, 0, 0.50)` — continuous 0~50%
- `max_w(t) = 0.20 − msi_norm(t-1) × 0.10` — shrinks to 0.10 in stress
- `to_budget(t) = 600% × (1 − msi_norm(t-1) × 0.67)` — 600 → 200 in stress

## References
- Faber 2007 — Quantitative Approach to Tactical Asset Allocation
- Kritzman, Page, Turkington 2012 — Regime Shifts: Implications for Dynamic Strategies (FAJ)
- Barroso, Santa-Clara 2015 — Momentum has its moments (JFE)
- Estrella, Hardouvelis 1991 — Term Structure as Predictor of Recessions
- L-454 — KR internals dominate global FRED (cor=-0.46 vs -0.14)
- L-220 — vol-reduction quarterly Harvey 격하 회피 (monthly base 유지)
- L-454 — KR domestic data prioritized over external

## Honest Disclosure
- This WT's alpha SCORE PANEL = inheritance only (cor=1, identical)
- Diagnostics (rank_ic / icir / Harvey) = inherited from STR_1701 (graduation_status: 2/5 gates, **honest disclosure**)
- The **value-add of this WT is the Macro Overlay layer**, not the alpha. Layer evaluation is done at Optimizer + Forge backtest stage downstream.
- AX-001 v2 metrics are computed at the alpha-level (regime-conditional IC); definitive Crisis_alpha + Core MDD relief is measured at PG2 portfolio level (Forge).
