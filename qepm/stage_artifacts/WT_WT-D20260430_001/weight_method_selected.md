# Weight Method Selected — WT-D20260430_001

**Selected Method**: `M4_TRADE_WAR_FIX` (strong_p=0.30, joint_p=0.30)

**Selection Objective**: `to_adj_ret` (cost-adjusted net SR with hard constraints)

**Date**: 2026-04-30

---

## What M4 does

**Trigger logic** (Date × monthly):

```r
weight_str1715[t] = case_when(
  baseline_cash[t] > 0       ~ 1 - baseline_cash[t],   # defer to existing MRS overlay (S2)
  joint_warning[t] == 1      ~ 1 - 0.30,                # 30% protection (very high conviction; never fires in 2004-2026)
  decay_extreme[t] | bocpd_extreme[t] ~ 1 - 0.30,        # 30% protection (10 firings: 2019-11, COVID-Feb/Mar/Apr, 2023-Mar through Nov)
  decay_strong[t] | bocpd_strong[t]   ~ 1.00,            # NO protection (DROPPED — Trade War 2018 false-positive band)
  TRUE                        ~ 1.00
)
weight_cash[t] = 1 - weight_str1715[t]
```

**Key policy difference from M2_CURRENT_S3 (alpha agent's design)**:
- **DROP** moderate single-signal band (`decay_strong=1` alone WITHOUT `bocpd_strong=1`) — alpha agent had this at 8% protection
- **DEEPEN** extreme single-signal protection from 20% to 30%
- **JOINT** unchanged (was 25%, now 30%; never fires in this data so cosmetic)

**Why?**:
1. **Trade War 2018-2019 false-positive elimination** — alpha agent's 8% moderate band fired 6 times in 2017-2019 with mean ret_net = +1.76% (positive returns → cash drag). Risk-to-Alpha C3 challenge required this fix.
2. **COVID 2020 protection deepening** — alpha agent's 20% (decay_extreme) → 30% saves additional 2.07pp during 2020 Q1.
3. **Extreme-only firings have negative mean ret** — `decay_extreme=1` events have mean ret_net = -1.82% (n=10), genuine alpha source preserved.

---

## Method Shopping (5 named + 140 grid combinations = 145 total)

| Method | Description | SR_net | MDD | TW 2018 | COVID Q1 | pass_all |
|---|---|---:|---:|---:|---:|:---:|
| M5_HOLD_S1 | No overlay (always-on) | 1.5950 | -35.56% | -0.40% | -4.28% | ❌ MDD fails |
| M1_BASELINE_S2 | Existing MRS overlay only | 1.6134 | -30.12% | -0.40% | -8.91% | ✓ |
| M2_CURRENT_S3 | Alpha agent's 8/20/25% schedule | 1.6297 | -30.12% | **-1.06%** | -4.81% | ❌ TW fails |
| M3_PROTECTION_OPT | Keeps moderate band (8%), deepens others to 30% | 1.6402 | -30.12% | **-0.91%** | -2.74% | ❌ TW fails |
| **M4_TRADE_WAR_FIX** ⭐ | Drops moderate band, extreme-only at 30% | **1.6399** | **-30.12%** | **-0.37%** | **-2.74%** | **✓** ⭐ |

**Winner**: M4_TRADE_WAR_FIX — only method passing all 3 hard constraints (MDD, CRISIS vol, Trade War 2018) while improving SR over both M1_S2 and M2_S3.

---

## Selection Rationale

### Primary objective: Cost-adjusted SR_net (round-trip)
- M4: 1.6399 (vs S2 1.6134, +0.0264 uplift; vs S3 1.6297, +0.0102 uplift)

### Hard constraints (all 3 must pass)
1. **MDD ≥ S2 baseline (-30.12%)**: M4 = -30.12% (preserved)
2. **CRISIS vol_ratio < 1.0**: M4 = 0.8365 (preserved from S2 0.8361 / S3 0.8366) — *no over-tuning*
3. **Trade War 2018-2019 cum_ret ≥ S2 baseline (-0.40%)**: M4 = -0.37% (Risk-to-Alpha C3 fix verified)

### Secondary diagnostics
- **NW HAC t (vs S2, lag=4)**: M4 = 0.812 (vs S3 0.499, +63% absolute improvement). Still NOT statistically significant at 5% (p=0.418) — honest disclosure.
- **NW HAC t in CRISIS bucket (vs S2)**: M4 = +1.05 (vs S3 -1.28, sign-flipped from harmful to helpful).
- **IR vs S2**: M4 = 0.183 (vs S3 0.110, +66% improvement). Still below RF-O2 0.3 threshold — structural for meta-allocation overlay.

---

## Walk-Forward Audit (Honest Disclosure)

**Train window**: 2004-01 to 2019-12 (n=192)
**Test window**: 2020-01 to 2026-03 (n=75)

**Train activations (decay_extreme=1, baseline_cash=0)**: **1 firing** (2019-11)
**Test activations**: **9 firings** (COVID Feb/Mar/Apr 2020 + 6 events in 2023)

**Walk-forward weakness**: Train SR_net was essentially flat (1.5638-1.5644) across all strong_p values from 0.10 to 0.50. The 1 firing in train cannot discriminate between protection levels.

**strong_p=0.30 selection**: Theoretically anchored to existing MRS regime cap practice (existing 3-Layer system caps cash at ~30% in CRISIS bucket), NOT chosen by data-max optimization.

**Honest tradeoff**: strong_p=0.50 yields full SR 1.6537 (vs chosen 0.30 yields 1.6399, difference 0.0138). I chose the conservative anchor over data-max to avoid over-tuning given walk-forward weakness. This is documented in `optimization_package.json::walk_forward_audit.over_tuning_check`.

---

## Codex R1 Resolution

Codex R1 stance: **REJECT** (7 critical concerns).
Optimizer R1 response: **REVISE** (4 ACCEPT/PARTIAL + 3 REBUTTAL).

See `optimizer_challenge_note.md` for full classification.

Major resolutions:
- **C3 method shopping count**: 5 → **145 total** (5 named + 90 M3 grid + 50 M4 grid).
- **C4 cost calculation**: corrected to round-trip 30bps × |Δw| (was one-way 15bps). M4 SR_net 1.6419 → **1.6399**.
- **C5 CVaR_95 breach**: `infeasibility_report` populated with structured `cvar_95_template_breach` block. Inherited governance from risk_package (PG2 precedent: STR_1715 100% admitted with CVaR ~10%).

Pending Q-Lead decision:
- **C2 (M4 = alpha rewrite)**: Optimizer policy switch within Charter scope OR re-route as alpha_v2.

---

## Forge Handoff

**Inputs for Forge**:
- `weights.csv` (267 rows × 3 cols: Date, weight_str1715, weight_cash)
- STR_1715 base period_returns (from STR_1715 strategy backtest)
- Forge will compute realized NAV: `nav_M4[t] = nav_M4[t-1] × (1 + ret_net[t] × weight_str1715[t] - cost[t])`

**Expected Forge AB result** (if M4 vs S3 head-to-head):
- M4 SR_net should be ~1.640 (close to optimizer estimate)
- M4 NAV vs S3 NAV at 2018-2019 (Trade War): M4 ahead ~70bps cumulative
- M4 NAV vs S3 NAV at 2020 Q1 (COVID): M4 ahead ~2.07pp cumulative
- M4 NAV vs S3 NAV at end of 2026-03: TBD by Forge

**Forge metric_type**: `backtested` (official) once Forge produces NAV.
**Optimizer metric_type**: `estimated` (current package).
