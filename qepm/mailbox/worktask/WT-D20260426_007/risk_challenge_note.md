# Risk Challenge Note — WT-D20260426_007 (Iter 14)

**STR_1701_V2 Confidence-Aware Linear Tilt** — Risk Agent objections + measurement findings.

**Agent role boundary**: Risk measures common-risk structure (Σ), tail/stress diagnostics, and crowding TDC. Risk does NOT modify alpha_vector, set weights, or endorse alpha-side performance claims.

---

## 1. CRITICAL: V2 ≠ STR_1701 base (silent reconstruction)

**Claim** (alpha_package + request.json mandate): "STR_1701 multi-sleeve alpha base 그대로 사용 (변경 X)"

**Risk measurement** (cross-section correlation V2 `score_str1701` vs Iter11 `score_eff` STR_1701 production composite):

| Sample ym | n | Pearson | Spearman |
|-----------|---|---------|----------|
| 2010-01 | 185 | 0.082 | 0.084 |
| 2015-01 | 338 | 0.195 | 0.134 |
| 2020-01 | 350 | 0.006 | 0.020 |
| 2023-01 | 349 | -0.084 | -0.098 |
| **Pooled** (29,271 obs) | 29,271 | **0.057** | — |

**Verification**: V2's `score_str1701` is exactly reproduced by `0.5*z_A + 0.3*z_B + 0.2*z_C` (cor = 1.000). Iter11's `score_eff` is the actual STR_1701 PG2 production composite (PG2 active 80%).

→ **V2 is NOT STR_1701 base + confidence tilt**. V2 re-implemented Slot A/B/C with different definitions/data and applied `rank^0.5 × confidence^1.5` tilt on the new construction.

→ Implication: V2 is a **new alpha source**, not an enhancement of STR_1701. The "PG2 incremental" framing assumed by request.json (V2 80% replaces STR_1701 80%) requires re-validation: V2 may be additive (independent alpha) rather than incremental (same family), changing the optimal PG2 composition entirely.

**Disposition**: INFO_TO_OPTIMIZER + INFO_TO_GOVERNOR. Risk does not endorse "same family" claim. Optimizer must compute V2 vs STR_1701 production NAV correlation directly at backtest stage (not via score correlation).

---

## 2. RF-CROWD-1656 (HIGH): V2 ↔ STR_1656 lower-tail TDC = 0.4796 > 0.30 mandate

V2 daily proxy = top-20 by `alpha_v2` at each sig_date, EW held until next sig_date (1840 holding rows × ~3911 daily obs).

| Metric | Value | Threshold | Status |
|--------|-------|-----------|--------|
| Pearson cor | 0.5292 | informational | — |
| Spearman cor | 0.4985 | informational | — |
| **TDC q5 lower** | **0.4796** | **< 0.30** | **FAIL** |
| TDC q95 upper | 0.2500 | informational | — |
| n joint daily obs | 3,911 | — | — |

→ **V2 and STR_1656 are tail-coupled in lower 5%**. PG2 framework "V2 80% + STR_1656 20%" expecting tail-independent diversification is not supported by historical co-movement.

**Caveat**: V2 daily proxy is top-20 EW from V2 alpha_scores (no Optimizer tilt). Forge realized V2 NAV (with TWAP/VWAP execution) may differ. But this is a structural diversification estimate — Forge proof should match within structural bounds.

---

## 3. Regime Σ instability (RF-R2 multi-regime)

Top-100 data-rich tickers, 4-regime correlation panel:

| Regime | T | n_tickers | mean_corr | cond | PSD |
|--------|---|-----------|-----------|------|-----|
| BULL | 87 | 100 | 0.174 | 699.6 | TRUE |
| NORMAL | 65 | 100 | 0.190 | 116.2 | TRUE |
| CAUTION | 28 | 100 | 0.399 | 268.7 | TRUE |
| **CRISIS** | **6** | **100** | **0.399** | **4467.6** | TRUE |

→ All regimes (BULL/CAUTION/CRISIS) breach cond > 100 due to T < N panel issue. CRISIS is unusable (cond 4467.6, T=6).

**Fallback artifact written**: `covariance_pooled_fallback.parquet` (T=80 × N=244, LW_constcor + ridge → cond=100 PSD).

**Binding rule** (passed to Optimizer): MUST use pooled in CRISIS; SHOULD use in CAUTION when T<30; recommended for regime-uncertain.

---

## 4. Tail risk diagnostics (proxy on EW universe-322)

| Metric | Value | Interpretation |
|--------|-------|----------------|
| CVaR_95 daily | -3.67% | EW-322 proxy |
| CDaR_95 | -46.14% | EW-322 proxy |
| MDD in-sample | -60.46% | 2008 GFC EW-322 |
| EVT VaR_99 (GPD) | -5.52% | gpd_mle |
| EVT ES_99 | -6.88% | gpd_mle |
| Hill α (top 5%) | 3.158 | finite variance, finite mean |
| Param VaR_99 Normal | -3.40% | — |
| Param VaR_99 Cornish-Fisher | -5.29% | non-Normal adjusted |
| Param ES_99 Normal | -3.91% | — |

**Codex critic**: CVaR=3.67% > 2.5% cap; MDD=60% > 45% cap.

**Risk-vs-Optimizer role**: These are EW-322 PROXY diagnostics over 21 years (2002–2023). True 20-name long-only with confidence-tilt + Optimizer MVO/CVaR weights will produce different metrics. CVaR<2.5% / MDD<45% are FORGE/GOVERNOR gates on optimized portfolio NAV, not Risk-side proxy gates. Risk's role is honest diagnostic provision (not silent acceptance), and the worst-stress GFC -25.93% is escalated as RF-R4 HIGH challenge_flag.

---

## 5. Stress test (8 periods, Risk-side EW-322 proxy)

| Period | n | cum_ret | mdd |
|--------|---|---------|-----|
| GFC_2008 | 371 | -25.93% | -56.99% |
| EuDebt_2011 | 126 | +0.03% | -25.11% |
| Taper_2013 | 102 | +1.37% | -14.44% |
| China_Shock | 186 | -3.01% | -16.23% |
| Brexit_2016 | 83 | +1.82% | -6.12% |
| TradeWar_2018 | 204 | -7.64% | -21.65% |
| COVID_2020 | 123 | +6.82% | -38.39% |
| Rate_2022 | 246 | -17.86% | -25.33% |

**Worst**: GFC_2008 -25.93% (RF-R4 HIGH).

---

## 6. Σ structure verification

- **Σ shape**: 350 × 350 (universe-restricted; alpha_vector covers 350 tickers)
- **Method**: factor model BΩB' + D
- **Ω estimator selected**: Ledoit-Wolf Oracle (shrinkage_quality preference)
- **Ω cond**: 38.28 (well-conditioned)
- **Σ cond pre-ridge**: ~250
- **Ridge λ**: 0.0104 → Σ cond = 100.0 (binding boundary)
- **Σ min_eig**: 0.0131 > 0 → PSD verified
- **Systematic share**: 16% (FF5 R²) — expected for KR broad universe
- **Idiosyncratic share**: 84% — KR concentrated equity property

**Method-shopping log**: 5 candidates tried (sample / lw_oracle / lw_constcor / gerber_rmt / diag_shrink), all PSD, lw_oracle selected for shrinkage preserving structure.

**Codex C5 (factor coverage 23%)**: KR universe FF5 R² mean=23.4% is empirically expected for 322-name long-only universe (small/mid-cap names dominate). Iter 5 top-20 had R²=24.7%; broader 322-name universe at 23.4% is consistent. Σ structure preserved via factor model + diagonal D.

**Codex C6 (PIT C4/C12/C15)**: Same data lineage as Iter 4 (WT-D20260425_009) which passed; FF5 v2 has annual May lag for RMW/CMA, quarterly 45d lag for SUE, t-1 month-floor for prices. RAWDATA + FF5 v2 loaded via parquet cache (C15 — production loader pattern).

---

## 7. Crowding scoresheet (full)

| Diagnostic | Value | Interpretation |
|------------|-------|----------------|
| V2↔Iter11 score Pearson | **0.057** | NOT same-family; structural reconstruction |
| V2↔Iter11 alpha_v2 Pearson | 0.108 | confidence-tilt on different base |
| V2↔Iter11 Jaccard top-50 | 0.149 | low overlap |
| V2↔Iter11 Jaccard top-20 | 0.081 | very low overlap |
| V2↔STR_1656 daily Pearson | 0.529 | informational |
| V2↔STR_1656 daily Spearman | 0.499 | informational |
| **V2↔STR_1656 TDC q5 lower** | **0.4796** | **FAIL mandate <0.30** |
| V2↔STR_1656 TDC q95 upper | 0.250 | informational |
| Iter3 PG2 ancestor Jaccard | (from alpha_pkg) | inherited |
| Alpha-vector HHI | 0.0043 | very low (vs EW 0.0029) |
| Top-decile sector concentration | 14.3% (상사,자본재 / 화장품) | acceptable, well-distributed |
| Liquidity flags (<200M) | 0 | universe-pre-filtered |

---

## 8. Risk Agent boundary statement

Risk Agent **measures** common-risk structure + tail/stress + crowding. Risk Agent does **NOT**:
- Modify `alpha_vector` or `confidence_vector`
- Propose portfolio weights
- Endorse alpha-side `sub_stab` 0.7857 claim (alpha domain)
- Endorse "V2 = STR_1701 + tilt" framing (measurement contradicts)
- Apply hard caps (CVaR/MDD) — Optimizer/Forge/Governor domain

Risk Agent **DOES**:
- Provide PSD Σ + cond ≤ 100 + factor model decomposition (PASS)
- Surface RF-CROWD-1656 (TDC fail) + RF-R4 (stress fail) + structural V2-vs-STR_1701 inconsistency
- Provide pooled Σ fallback artifact for regime-uncertain rebalances
- Document method-shopping log (5/5 cap)
- PIT compliance C1/C2/C9/C11/C12/C13/C14/C15 PASS

## 9. Recommendations to Optimizer (handoff)

1. Use `security_covariance_ref` (factor model BΩB'+D, cond=100, PSD)
2. **BIND** `security_covariance_pooled_fallback_ref` in CRISIS regime; recommend in CAUTION when T<30
3. **Re-evaluate PG2 composition**: V2 ↔ STR_1701 score cor = 0.057 (NOT same family). V2 is NEW alpha; PG2 = V2 80% + STR_1656 20% (replacing STR_1701 80%) needs Forge realized NAV cor verification, not score-level approximation
4. **TDC q5 mandate FAIL**: V2 ↔ STR_1656 lower-tail = 0.480 > 0.30. Optimizer/Forge must measure realized portfolio TDC at NAV level; if confirmed > 0.30, the diversification benefit assumption breaks
5. Slot A/B/C internal blend already pre-applied in `alpha_v2` — no further multi-sleeve construction at Optimizer side
6. Cash overlay regime-conditional via RP_M (AX-001 v2)

---

**Risk Agent objection summary**: 2 HIGH (RF-CROWD-1656 + RF-R4), 1 INFO (V2-vs-STR_1701 structural finding), 5 MEDIUM regime cond breaches. PSD Σ + pooled fallback provided. Risk does NOT silently override Alpha — challenges escalated for Optimizer/Governor decision.
