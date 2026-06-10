# Weight Method Selected — WT-D20260606_001 (Optimizer Research)

**Date**: 2026-06-06 | **Agent**: optimizer-research | **as_of**: 2026-05-31
**Selection objective**: `net_ir` (net-of-cost book-marginal ΔIR vs incumbent R05; R4-P3 enum compliant)

## TL;DR — Honest verdict

The WT central thesis — *"β/regime overlay + uncertainty sizing lifts book SR toward 2.5"* — is **REFUTED by the data**.

- Incumbent R05 book SR = **1.549** (already M4 regime-overlaid).
- Best achievable book SR with diversifier + overlay = **~1.74** — gap to 2.5 **NOT closed**.
- Overlay (regime de-risk + uncertainty sizing) provides **MDD control** (34%→21%) but **NO SR/IR lift**.
- Selected: **static multi-sleeve, EW top-20 sleeve leg, book allocation a=0.15, overlay OFF** for the IR-optimal deliverable.
- **Recommendation: DPL transition** (measurement-graduation §5).

## Method selected

`STATIC_MULTISLEEVE_EW_a0.15`

- **Book** = 0.85 · R05 (frozen incumbent) + 0.15 · residual-mom-sleeve(EW top-20).
- **Sleeve leg internal weights**: Equal-Weight (1/N), 20 names, 0.05 each, capped [0,0.20], Σw=1.
- **Overlay**: OFF in IR-optimal deliverable. Optional regime de-risk overlay schedule provided (overlay_exposure column) for MDD-priority mandate only.

## Why EW over MVO / HRP / ERC (sleeve internal scheme)

| scheme | sleeve SR | sleeve MDD | TO ann round-trip | selected |
|---|---|---|---|---|
| EW  | 0.618 | 0.576 | **14.08** | ✅ |
| MVO | 0.789 | 0.545 | 20.65 | ✗ (turnover +47%) |
| HRP | 0.709 | 0.550 | 18.27 | ✗ |
| ERC | 0.696 | 0.564 | 15.56 | ✗ |

MVO has the highest standalone SR but its +47% turnover (20.6 vs 14.1) erodes the net edge at book sizing, and concentration is unwarranted for a broad 20-name alpha (DeMiguel-Garlappi-Uppal 2009: 1/N robust OOS; Grinold breadth — the alpha edge is in *selection*, not *sizing*). EW selected. **This is the Cycle-2 lesson applied honestly: sizing did not beat EW net of turnover.**

## Why a=0.15 (book allocation to sleeve)

| a | book SR | active IR | ΔIR vs R05 | MDD |
|---|---|---|---|---|
| 0.05 | 1.589 | 0.677 | +0.016 | 0.339 |
| 0.10 | 1.648 | 0.693 | +0.032 | 0.342 |
| **0.15** | **1.701** | **0.710** | **+0.049** | 0.345 |
| 0.20 | 1.742 | 0.728 | +0.067 | 0.356 |

a=0.15 is the largest allocation with a risk-acceptable tail. a=0.20 reaches ΔIR +0.067 (>0.05) but exposes the book to the sleeve's **−26.8% momentum-crash month** (risk RF-R4) and the benefit is **statistically uncertain** (risk RX-2: ΔIR 95%CI [−0.0149,+0.0056] straddles zero). Conservative vol-aware sizing per risk `sizing_guidance` + RX-3 CVaR book cap.

## The overlay test (WT core question) — definitive

| test | result | verdict |
|---|---|---|
| Regime de-risk on book (best SR) | SR 1.736, MDD 0.240 | ≈ static a0.15 — **no SR lift**, vol/MDD cut only |
| Regime de-risk active IR | IR 0.578, ΔIR **−0.083** | overlay **HURTS** IR |
| Uncertainty sizing (k=0→2) | SR 1.638→1.551, avg_a 0.169→0.011 | haircut **de-allocates** weak sleeve → converges to R05; **no lift** |
| **CONTROL: overlay on R05 ALONE** | SR 1.46–1.57 vs base 1.549 | **DECISIVE — no lift / slight harm** |

The **control test** is the key evidence: applying the identical regime overlay to R05 *alone* produces **no SR improvement** (1.46–1.57 vs 1.549). This proves the overlay machinery (crisis-prob/regime timing) carries **no incremental alpha** on this book — because **R05 is already M4 regime-overlaid**. A second overlay layer is redundant. The measurement-graduation §5 claim that "overlay = SR 2.5 main lever" does **not hold on this incumbent**.

The uncertainty-aware haircut (μ̃ = μ̂ − k·SE, Liao 2025) behaves correctly and honestly: as k rises it de-allocates the sleeve toward zero, recognizing the edge is not statistically significant (matching risk RX-2). It adds nothing beyond a small static allocation.

## Implementation flags (honest, not relaxed)

- **Turnover**: sleeve one-way 0.587/mo → **14.08/yr round-trip** (= one-way ×12×2). **EXCEEDS** P6 ceiling (≤11/yr). 15bps cost IS deducted; net ΔIR stays +0.049 > 0 (net>cost holds), but the **ceiling is breached** → flagged RF-O-turnover, NOT silently relaxed. Book-level turnover lower (sleeve = 15% of book).
- **ΔIR +0.049 < 0.05** admission threshold (borderline) → flagged RF-O-dIR.
- **Thesis refuted** → flagged RF-O-thesis (CRITICAL).

## Σ used

Direct **Ledoit-Wolf** (constant-correlation target), rebuilt per-month on each candidate universe (PSD, well-conditioned). Per risk **RX-1**, structural BΩB'+D is advisory only (diagonal-D violated: residual off-diag |cor| 0.115). Only used for MVO/HRP/ERC comparison; the selected EW scheme needs no Σ.

## Schedule fidelity (RF-O9)

weights.csv = full monthly time-series schedule, **269 unique as_of_dates** (2004-01..2026-05), density 1.0 ≥ 0.95. Walk-forward satisfied — not a single snapshot. `as_of_date` column present.

## Recommendation

**DPL transition (measurement-graduation §5).** Incremental sleeve+overlay tuning has a structural ceiling (~SR 1.74, control-proven). The SR-2.5 gap requires direct portfolio learning (features→weights end-to-end, net-SR objective) or a structurally different lever — not more two-stage sleeve stacking. Do not spin wheels on overlay parameters. Forge handoff prepared for the borderline diversifier; governor admit NOT recommended (ΔIR<0.05 + standalone FAIL).
