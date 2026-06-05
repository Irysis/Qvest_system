# Weight Method Selected — WT-D20260528_003 (D_PROD)

**Agent**: optimizer-research · **as_of**: 2023-11-30 · **selection_objective**: `net_ir` (HARD; raw Sharpe-max forbidden)

## Selected: `Schedule_EWbase` (alpha-agent bandbuffer softmax-cap weights, verbatim)

The optimizer ran an 8-method walk-forward comparison (115 monthly rebalances + as_of target).
Selection rule: **max net_ir subject to turnover_yr ≤ 6.0 (HARD)**.

| Method | net IR | net SR | TE | MDD | TO/yr | TO≤6.0 |
|---|---|---|---|---|---|---|
| AlphaSoftmax | **1.017** | 0.778 | 0.214 | 0.432 | 12.53 | ❌ |
| **Schedule_EWbase ◀ SELECTED** | **0.980** | **0.741** | 0.181 | 0.342 | 5.28 | ✅ |
| EW | 0.970 | 0.737 | 0.181 | 0.342 | 4.98 | ✅ |
| ERC | 0.857 | 0.634 | 0.170 | 0.343 | 5.58 | ✅ |
| CVaR_LP (→ERC fallback) | 0.857 | 0.634 | 0.170 | 0.343 | 5.58 | ✅ |
| HRP | 0.789 | 0.579 | 0.167 | 0.337 | 6.85 | ❌ |
| MVO_betaneutral | 0.555 | 0.405 | 0.200 | 0.496 | 12.81 | ❌ |
| MVO_conf | 0.540 | 0.393 | 0.209 | 0.417 | 13.00 | ❌ |

## Why EW-family wins (not MVO/HRP/CVaR)

1. **AlphaSoftmax disqualified**: highest net IR (1.017) but re-tilting the 20 names by alpha-softmax doubles turnover to 12.5/yr → violates the 6.0 HARD cap. Selectable only by relaxing a hard constraint (forbidden — would require infeasibility_report waiver).
2. **MVO/HRP/ERC/CVaR all LOSE net IR vs EW.** For a 20-name, already-selected, broad microstructure/vol-tilt alpha, Σ-based concentration:
   - over-weights low-vol names (works against the vol-tilt edge),
   - adds turnover (HRP 6.85/yr breaches cap),
   - amplifies estimation error in the rolling 252d Σ.
   This is the **DeMiguel-Garlappi-Uppal (2009, RFS) 1/N out-of-sample dominance** result + **Grinold-Kahn breadth** (IR = IC·√breadth; EW maximizes breadth across the 20 names).
3. **Schedule_EWbase ≈ EW** (net IR 0.980 vs 0.970, +0.0093): the alpha agent's softmax-cap weights are a mild, turnover-controlled tilt that edges pure EW. Selecting it preserves the alpha agent's committed sizing (no re-interpretation) while being the net-IR-optimal turnover-feasible choice.

## Sizing vs EW (does sizing boost net SR?)

**Net SR: 0.741 (selected) vs 0.737 (EW) → ΔSR +0.005, ΔIR +0.009.** Sizing provides a *negligible* improvement over EW for this alpha. **Honest conclusion: weighting-method optimization does NOT meaningfully boost net SR here.** The alpha's edge is in name *selection* (the bandbuffer top-20), not in *sizing*. This is reported transparently — no inflated "improvement" claim.

## RF-R1 (MKT exposure) — risk-agent HIGH flag

Risk flagged MKT 64.8% variance share / beta 1.09 (at as_of 2023-11-30), action "Optimizer impose factor exposure constraints."

Findings:
- **as_of single-cross-section beta = 1.092** (the flagged value). **But walk-forward MEAN beta = 0.934 < 1.0** — the 1.09/64.8% is a 2023-11-30 snapshot artifact, not the operating book's typical exposure.
- A QP beta-cap (min ‖w−w_sched‖² s.t. b'w ≤ cap) reduces as_of beta 1.092→1.000 at only +0.0745 one-way turnover.
- **Walk-forward impact of applying the cap**: net IR 0.980→0.950, net SR 0.741→0.722, MDD 0.342→0.335, mean beta 0.934→0.895.

**Decision: beta-cap NOT applied** (explicit tradeoff, NOT silent override — Charter §8). The cap costs −0.03 net IR / −0.019 net SR for marginal MDD (−0.007) and beta reduction. For a **long-only, fully-invested, 20-name** mandate, MKT beta has a **structural floor near 1.0** — it cannot be reduced materially without shorting or cash (both prohibited by mandate). RF-R1 is mitigated by *analysis + quantified available variant*, and Forge/Judge may elect the cap=1.00 variant if book-level beta control is prioritized over net IR. The risk agent's own challenge note rebutted its sub-concern as "MKT structural optimizer scope" — consistent with this finding.

## DSR FAIL inheritance (forge handoff)

Alpha DSR_proper = 3.05e-15 (z=−7.80) FAILS the 0.50 graduation gate. **Sizing cannot repair DSR** — it is a multiple-testing property of the alpha signal, not a weighting artifact. The optimized 20-name executable-book walk-forward net SR (0.741) exceeds the alpha-reported IC-translated proxy SR (0.306, on the full 349-universe), but **this WT remains a forge_handoff, NOT graduated**. Forge/Judge inherit the DSR FAIL.

## Hard constraints (all PASS)

max_names 20 ✅ · long-only ✅ · weight ∈ [0.047, 0.056] ⊂ [0,0.20] ✅ · Σw=1 ✅ · turnover 5.28/yr ≤ 6.0 ✅ · cost v2.3_kr_retail_15bps (est 0.79%/yr) · schedule density 116/116 = 1.0 ≥ 0.95 ✅

## PIT

- Weights from alpha sig_dates ≤ 2023-12-22 lockbox.
- as_of book uses risk-agent Σ (BΩB'+D, cond100); all other walk-forward dates use rolling Ledoit-Wolf 252d cov with **Date < sig_date (C9 t-1)** — the risk snapshot Σ is only valid at as_of, so optimizer-internal rolling cov is required for the comparison (no risk-model redefinition; risk Σ used unchanged at its valid date).
