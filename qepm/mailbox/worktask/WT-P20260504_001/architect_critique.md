# Architect Critique — WT-S20260504_007 AR Pure Risk Overlay

**Author**: Architect (3rd source under AX-008)
**Date**: 2026-05-04
**Source WT**: WT-S20260504_007 (research)
**Target WT**: WT-P20260504_001 (promotion)
**Mandate**: Independent verification of Q-Lead post-hoc AR overlay metrics.

---

## 1. Executive verdict

**PASS** (all 4 metrics match within tolerance for all 3 overlay variants + S0 baseline).

Reproduction is **exact to 4 decimal places** on CAGR / Vol / Sharpe / MDD / Sortino / Calmar across S0/S1/S2/S3. Maximum metric divergence observed: 0.005pp on MDD (rounding artifact, well below 1pp tolerance).

| variant | CAGR_diff_pp | Vol_diff_pp | Sharpe_diff | MDD_diff_pp | Sortino_diff | Calmar_diff |
|---|---|---|---|---|---|---|
| S0 | 0.000 | 0.000 | 0.0000 | -0.004 | 0.0000 | 0.0000 |
| S1 | 0.000 | 0.000 | 0.0000 | -0.002 | 0.0000 | 0.0000 |
| S2 | 0.000 | 0.000 | 0.0000 | -0.005 | 0.0000 | 0.0000 |
| S3 | 0.000 | 0.000 | 0.0000 | -0.003 | 0.0000 | 0.0000 |

The mathematical reproduction is unambiguous. **Forge v2 (Q-Lead post-hoc) numbers are correct given its inputs and methodology.**

That said, AX-008 mandates not only reproduction but architectural review. The remainder of this document raises concerns that, while not fatal, must be addressed before promotion.

---

## 2. Reproduction summary

### 2.1 Inputs (SHA-verified)

- `lro_params_frozen.json` SHA `ad3d44417b526c3d82dde8724cb971ba973f2e418fc36ada7795d687c809cb18` matches request mandate.
- `beta_t_mapping.csv`: 268 rows (2004-02-02 ~ 2026-05-01), 5 leading NA on each variant (warmup).
- `03_period_returns.csv` (STR_1715 PG2): 268 monthly `ret_net` rows.

### 2.2 Independent code path

I deliberately wrote a different code path from `posthoc_overlay_apply.R`:

| Aspect | Forge (data.table) | Architect (base R) |
|---|---|---|
| Load | `fread()` | `read.csv()` |
| Sort | `setorder()` | `order()` |
| Lag | `data.table::shift()` | `c(rep(fill, n), head(x, -n))` |
| Merge | `dt1[dt2, on="ym"]` | `merge(df1, df2, by="ym")` |
| Cost | `db_thr * COST_BPS` | identical formula |
| Metrics | `PerformanceAnalytics::table.AnnualizedReturns` | identical |

**Result**: Identical to 4 decimals across all 24 metric × variant cells.

### 2.3 Period boundary (263m vs 268m)

The "263m" comes from dropping rows where any β-lag is NA. Original `beta_t_mapping.csv` has 5 leading NA rows (2004-02 ~ 2004-06). After applying `shift_lag(beta, 1, 1.0)`:
- Row 1: β_lag = 1.0 (fill), but β_current = NA → row keeps fill but `db = |β_current - β_prev| = NA`
- Rows 2-5: β_lag = NA (shifted from original NA)
- Row 6: β_lag = NA (last NA shifted by 1)
- Row 7+: β_lag = valid

`complete.cases()` drops rows with NA in any β_lag column → 268 - 5 = **263 rows**.

This is mathematically defensible. The 5 dropped months (2004-02 ~ 2004-06) correspond to AR warmup (~6 months W=252d × first AR mapping window).

### 2.4 Cross-check: full 268m baseline (no trim, no overlay)

Running `table.AnnualizedReturns` on raw `str_df$ret_net` over full 268m:
- SR = 1.6583
- CAGR = 0.4395
- Vol = 0.2651
- MDD = -0.4169

L-274 publishes SR=1.7477 / CAGR=0.4378 / MDD=-0.3205 for STR_1715 PG2 268m.

**Discrepancy**: L-274 MDD = -0.3205 differs materially from raw `ret_net` MDD = -0.4169. This means L-274's reported MDD comes from a different return series — most likely the post-M4-cash-overlay return series, which Forge v2 does NOT use (Forge v2 uses raw `ret_net` from `03_period_returns.csv`). This raises a methodological concern (see §4).

---

## 3. Architectural review

### 3.1 β_t lag implementation (PIT C1, C2)

**Status**: Architecturally sound (with one caveat).

The `lro_params_frozen.json` declares:
- `ar_t_window_end_rule`: "trading_dates < rebalance_date (t-1 close cutoff)"
- `beta_t_application_rule`: "applied at rebalance_date open"

Forge implements via `shift(β, 1, fill = 1.0)` — i.e., β computed at rebalance_date_t is APPLIED to ret_{t+1} (one period lag).

**Examination of beta_t_mapping.csv**:
- Row dates are month-start (e.g., 2004-07-01, 2004-08-02 — first business day of each month).
- The β value at row `2004-07-01` represents AR computed using data through 2004-06-30 (eligible per `t-1 close cutoff`).
- After `shift(1)`, the β assigned to `2004-08-02` row in the merge is the β from `2004-07-01` row.
- This β is applied to `ret_net[2004-08-02]`, which represents the return from 2004-07-XX to 2004-08-02 (month-start to month-start).

**Caveat**: The intent (per LRO) is "β computed at t-1 close, applied at t open". With month-start return schedule, β computed at end-of-July would be applied to August's return. The Forge `shift(1)` achieves this: the β value originally on row `2004-07-01` (which itself uses ≤ 2004-06-30 data per LRO `t-1 close cutoff` rule) is shifted to row `2004-08-02` and multiplied by `ret_net[2004-08-02]` (Aug return). **This is t-1 lag relative to return timing — correct PIT**.

However, an even-more-conservative interpretation (β computed at end-of-July → apply to August → only justifiable if we use β computed by end of July, NOT β registered with date 2004-07-01 which by `lro` rule uses through 2004-06-30 data) is in fact what Forge implements. So the lag is conservative.

**No PIT violation found.**

### 3.2 Cost model: 15bps × |Δβ_t|

**Status**: Reasonable, but coarse.

The model treats β as a sleeve scaling factor applied uniformly to all 20 stocks. Trading cost = 15bps × the *fraction* of sleeve scaled up/down between consecutive months.

**Pros**:
- Consistent with Production Constraints (15bps one-way cost).
- Avoids double-counting the within-sleeve rebalancing turnover (already deducted in `STR_1715` `ret_net`).

**Cons / concerns**:
- Cost = 15bps × |Δβ| × **1.0 (full sleeve gross)**. But trading down β implies SELLING |Δβ| of every stock in the sleeve simultaneously to raise cash. Real-world execution is asymmetric (entry cost + exit cost = round trip). Forge applies one-sided 15bps. If Δβ = 0.3 (β goes from 1.0 → 0.7), Forge charges 0.3 × 15bps = 4.5bps. This is conservative on the return side but doesn't capture round-trip semantics.
- An even stricter interpretation: 15bps × |Δβ| × 2 (round trip) = 9bps for that example. Over 263m, average |Δβ| (S1 threshold) is ~0.05/month → ~7.5bps/month one-sided cost or ~15bps round trip. Annualized ~90-180bps cost drag.
- Empirically: the SR improvement under S1 (+0.057) is small enough that doubling overlay cost to round-trip would erase ~0.04 SR. Material but not fatal.

**Recommendation**: Document cost convention explicitly in Judge stage. If round-trip is the institutional standard, S1 SR could drop from 1.78 → ~1.74 (still > S0 baseline 1.72 trivially).

### 3.3 Cash residual rate: 0% assumption

**Status**: Conservative on absolute returns, neutral on Sharpe.

Forge sets `cash_rate = 0`, i.e., the de-risked portion (1 - β) of the portfolio earns nothing. This understates real-world performance:
- KR risk-free over 2004-2026 ≈ 1.5-3.5%/year (CD 91d ranged 1.5% to 5.0%).
- For S1 with avg β ≈ 0.85 (rough), 15% in cash × 2-3% rf = +30-45bps/year drag eliminated by including rf.

**Effect on Sharpe**: Adding rf to cash side raises both the strategy return AND the risk-free benchmark equally (since rf is excess return base) → net Sharpe **unchanged or slightly higher**. So the SR comparison is fair.

**Effect on CAGR**: S1 CAGR would rise from 39.34% to ~39.8% (negligible). Not material.

**Effect on MDD**: MDD computed in NAV space. Cash earning 0% during drawdown = no contribution to recovery. Real cash earning 2.5% during 2008 (when β=0.4 for ~12 months) would have offset losses by ~30bps. Marginal MDD improvement.

**Verdict**: 0% is conservative. Real-world deployment would slightly outperform on absolute terms.

### 3.4 Period boundary: 263m vs 268m

**Status**: Defensible, but disclosed.

The 5-month trim is mechanical (NA warmup). Q-Lead correctly documents this in `forge_package_v2_posthoc_supplementary.json` line 22:
> "MDD slightly larger due to 263m window vs L-274 268m"

**Concern**: The S0 baseline reported by Forge (CAGR 45.64% / SR 1.7186 / MDD -0.4169) is the **263m subset** of `ret_net`, NOT the L-274 268m baseline (CAGR 43.78% / SR 1.7477 / MDD -0.3205). This means:

- L-274's MDD -0.3205 includes M4 cash overlay smoothing on the actual NAV.
- Forge's 263m baseline -0.4169 is from raw `ret_net` (which IS already net of M4 per `03_period_returns.csv` ret_net = ret_gross - cost; M4 affects ret_gross via cash weight, but the period returns CSV stores monthly returns AS REALIZED).

**This is the materially important question**: which `ret_net` is being used? Reading the CSV header — `ret_gross, ret_net, cash_weight` — and noting `cash_weight = 0` for ALL 268 months in `03_period_returns.csv` — the CSV stores returns of the **risk sleeve only, before M4 cash blend**. So Forge's S0 baseline 263m IS the risk-sleeve-only baseline, not the M4-blended baseline that L-274 reports.

**Implication**: The β overlay is being applied on top of the risk sleeve, NOT on top of the M4-cash-blended portfolio. If admitted, the live deployment must apply β to the risk-sleeve weights BEFORE M4 cash overlay (or apply both overlays compositionally, which would compound de-risking).

This is a significant **deployment semantics** issue, see §3.5.

### 3.5 Walk-forward holdings vs static snapshot — production semantics

**Status**: Critical concern from Codex Round 1 partially resolved, but layered semantics question remains.

Codex Round 1's main concern (forge v1) was that the 268-month weights schedule was actually a static May-2026 snapshot repeated 268 times, not true walk-forward. Forge v2's post-hoc bypasses this entirely by directly applying β to monthly `ret_net` from STR_1715's actual walk-forward backtest. **Mathematically this resolves Codex Round 1 concerns** (no synthetic schedule).

However, the **deployment semantics** remain ambiguous:

1. STR_1715 is admitted with M4 cash overlay (per L-274). Live deployment does:
   - At rebalance_date: compute risk-sleeve weights via STR_1715 grid → apply M4 schedule (`w_str = 0.7-1.0` based on regime) → final = `w_str × risk_sleeve + (1-w_str) × cash`.

2. AR overlay proposes to ADD a β layer:
   - At rebalance_date: compute risk-sleeve weights → apply β → apply M4 → ?

**Order matters**:
- (β ∘ M4) → final w = β × M4 × risk_sleeve. AR de-risks ON TOP of M4.
- (M4 ∘ β) → final w = M4 × β × risk_sleeve. M4 overrides AR.
- Compositional: β AND M4 simultaneously decide cash.

Forge v2's post-hoc applies β to `ret_net` which is NET OF NEITHER M4 NOR β — it's pure risk-sleeve return. The math is `r_overlay = β × r_risk_sleeve`. This corresponds to deployment semantics **β replaces M4 entirely** OR **β acts on top of risk sleeve before M4**.

If deployed as **β replaces M4**: STR_1715 is no longer the admitted strategy. Need new WT.
If deployed as **β on top of M4**: The β overlay's empirical evidence (post-hoc on raw `ret_net`) does NOT prove it works on M4-adjusted returns. Different return distribution → different overlay impact.

**Recommendation**: Before promotion, Q-Lead must specify ONE of:
- (a) β replaces M4 (re-test as a new strategy, e.g., STR_1715_AR with M4=OFF).
- (b) β operates on M4-output returns (re-run post-hoc using M4-adjusted return series, NOT raw `ret_net`).
- (c) β AND M4 are compositionally optimized (joint sweep, not post-hoc β alone).

Option (b) is the most surgical: the post-hoc test should apply β to the M4-blended NAV-implied return series, not to raw `ret_net`. Currently this is NOT done.

### 3.6 PIT C1~C15 audit

| Code | Check | Status |
|---|---|---|
| C1 | full-sample stats? | PASS — β_t uses expanding percentile per LRO line 18. |
| C2 | same-day circular? | PASS — `t-1 close cutoff` enforced. |
| C3 | aggregate→apply same period? | PASS — AR window separated from β-application window. |
| C4 | financial statement lag? | N/A — overlay does not use financials. |
| C5 | overlay t-1? | PASS — `shift(β, 1, fill=1.0)`. |
| C9 | DD/VT lag? | N/A. |
| C13 | NEGATE_FACTORS? | PASS — β is a scalar in [0, 1], not a sign flip. |
| C14 | IC Usable_Date? | N/A — overlay does not use IC. |
| C15 | direct parquet load? | N/A — overlay uses curated outputs. |

**No PIT violation found** in the methodology.

### 3.7 AX-001/002/007/008 audit

- **AX-000**: Documented (immutable). N/A check.
- **AX-001 v2** (defense conditional): N/A — AR overlay is NOT a defense factor; it's a risk-mitigation overlay.
- **AX-002** (harness only): **PASS** — `ret_net` from harness backtest used directly. β SHA frozen and verified. No future leakage.
- **AX-005** (KR defense top20): N/A — AR is overlay, not factor.
- **AX-007** (single-sleeve top20 break): **EXEMPT** per Forge claim (selection mechanism unchanged, only sleeve scale modulated). I concur — the 20 stocks are fixed by STR_1715; β scales the gross exposure. No selection change.
- **AX-008** (verification triangulation): With this Architect verification = **PASS**, the 3-source count becomes Forge PASS + Codex PARTIAL + Architect PASS = **2.5/3 PASS** ≥ 2-source floor. AX-008 floor compliance achieved.

---

## 4. Outstanding concerns (must address before promotion)

| # | Issue | Severity | Resolution path |
|---|---|---|---|
| 1 | Baseline mismatch: Forge S0 (263m raw `ret_net` MDD -0.4169) ≠ L-274 published baseline (268m, MDD -0.3205). Means S1 is being compared against a baseline that L-274 does NOT report. | HIGH | Q-Lead must re-state ΔMDD relative to either (a) Forge S0 263m or (b) re-compute L-274-style 268m baseline including M4 effect. Cannot mix the two. |
| 2 | Layered semantics: β + M4 interaction undefined. | HIGH | Pick one of (a) replace M4 → new WT, (b) apply β to M4-blended returns → re-run post-hoc, (c) joint optimize β AND M4. |
| 3 | Cost model one-sided 15bps × \|Δβ\|. Round-trip is institutionally standard. | MEDIUM | Document explicitly in Judge stage; sensitivity show round-trip cost. |
| 4 | Cash residual 0% assumption. Real cash earns rf>0 → small absolute return upside. | LOW | Document assumption; consider rf>0 sensitivity. |
| 5 | S1 MDD -29.53% still violates "MDD<25%" target (gap 4.53pp). Production Constraints L-274 target unmet. | MEDIUM | S3 sigmoid achieves MDD -19.74% but Sortino 0.98 (just under 1.0). Pick which constraint binds. |
| 6 | Codex Round 1 RF-F4 (baseline fairness) and RF-F5 (DSR penalty) — not addressed in v2 post-hoc. | MEDIUM | If promoting AR overlay as primary, Judge stage should re-run Codex with v2 forge_package + this Architect verification. |

---

## 5. Recommendation

**ADMIT-COMPATIBLE conditional on resolving Issues 1 & 2** (baseline mismatch + layered semantics).

The mathematical reproduction is unambiguous and clean. Forge v2's pivot from forge v1 (synthetic snapshot) to direct `ret_net` overlay is methodologically correct. The β computation is PIT-clean. The cost model is conservative.

**However**, the deployment is not yet defined: AR overlay's interaction with M4 cash overlay is undefined. Until Q-Lead specifies whether AR replaces M4, layers on top of M4, or co-optimizes with M4, **promotion would be premature**.

If the answer is "AR replaces M4 entirely": this is a NEW strategy and requires fresh WT lifecycle (alpha → risk → optimizer → forge → judge → governor) with M4 OFF baseline.

If the answer is "AR on top of M4": the post-hoc must be re-run using M4-blended monthly returns as input, NOT raw `ret_net`. The current post-hoc does not prove the overlay works on M4-adjusted returns.

**My verdict for AX-008 third-source role**: **PASS** on numerical reproduction. Architectural concerns are not fatal but require Q-Lead resolution before book_state admission.

---

## 6. Files produced

- `/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot/qepm/mailbox/worktask/WT-P20260504_001/architect_R_script.R`
- `/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot/qepm/mailbox/worktask/WT-P20260504_001/architect_independent_verification.json`
- `/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot/qepm/mailbox/worktask/WT-P20260504_001/architect_metrics.csv`
- `/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot/qepm/mailbox/worktask/WT-P20260504_001/architect_comparison_table.csv`
- `/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot/qepm/mailbox/worktask/WT-P20260504_001/architect_critique.md` (this file)
