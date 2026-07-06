# Weight Method Selected — WT-D20260706_MIDCAP

## Verdict: HOLD / INFEASIBLE ON SUCCESS GATES

The optimizer role is weights-only. Given alpha's `alpha_hat` (tierEmph_B) and risk's Σ (as-is,
no reinterpretation), the question is whether **benchmark-aware / TE-controlled optimization** can
bridge the cap-tier trap so the mid-cap sleeve delivers book-marginal ΔIR ≥ 0.05 vs PG2 (1.416).

**Answer: No.** All three success gates fail and the highest-IR variant is disqualified on turnover.

## Method comparison (contract build_benchmark_compare, NW lag-3, vs cap-w IKS200)

| method | port_t | IR | TE | netSR | turnover | post2017_t | oos_v2 | status |
|---|---|---|---|---|---|---|---|---|
| EW_top25 | 2.400 | 0.525 | 0.163 | 0.525 | 11.41 | -0.489 | -0.231 | handoff |
| alpha_prop | 2.645 | 0.556 | 0.173 | 0.556 | 13.84 | -0.130 | -0.135 | **DISQ turnover** |
| megacap_anchor | 1.715 | 0.376 | 0.159 | 0.376 | 13.25 | -0.953 | -0.355 | reject |
| inv_vol | 1.627 | 0.377 | 0.154 | 0.377 | 11.83 | -1.197 | -0.439 | reject |
| BMA κ0.25 | 2.401 | 0.506 | 0.160 | 0.506 | 13.08 | -0.352 | -0.190 | reject |
| BMA κ0.50 | 2.034 | 0.428 | 0.153 | 0.428 | 12.39 | -0.617 | -0.269 | reject |
| BMA κ0.75 | 1.597 | 0.336 | 0.149 | 0.336 | 11.76 | -0.886 | -0.374 | reject |
| BMA κ1.00 | 1.119 | 0.234 | 0.150 | 0.234 | 11.47 | -1.127 | -0.520 | reject |

## Benchmark-aware finding (the hypothesis's core test)

The κ sweep is the TE-control lever (κ = shrink strength toward cap-w tracking). As κ rises, **TE falls
monotonically (0.173→0.150) but post-2017 active t degrades monotonically (-0.13 → -1.13)** and IR
collapses. There is **no κ with post-2017 positive active**. TE-control vs cap-w forces the book to hold
the signal-dead mega-cap names, reintroducing exactly the trap the mid-cap tilt tried to escape. This
is the optimizer-level confirmation of alpha CF-3 and risk RF-R1 (market = 61% variance, β 0.79,
non-neutralizable long-only).

## Book-marginal (proxy; forge/governor authoritative)

- score_eff base active IR 0.617 → +tier sleeve 50/50 blend 0.605 → **ΔIR = -0.011** (negative).
- cor(base_active, tier_active) = 0.872; cor(tierEmph_B, score_eff) = 0.973 (alpha CF-1).
- Standalone tier IR 0.556 ≪ PG2 incumbent 1.416.
- The sleeve is a **tier-restriction of the incumbent alpha**, not orthogonal — no marginal value.

## Success gate evaluation

| gate | value | pass |
|---|---|---|
| ΔIR ≥ 0.05 | -0.011 | ✗ |
| paired NW-t ≥ 2.0 (post-2017) | -0.130 (best) | ✗ |
| oos_v2 ≥ 0.7 | -0.135 (best) | ✗ |

## as_of deployability note

At 2026-04-01 the tradeable top-25 by tierEmph_B is **92% SMALL / 8% MID / 0% MEGA** (size_rank
median 134). The intended mid-cap concentration does not survive to the deployable cut — extreme
small-cap within-tier z-scores dominate. This amplifies RF-R3 (passive-overlap 0.96) and AX-003
small-cap-value trap risk, and further undercuts the mid-cap thesis at the portfolio level.

## Handoff schedule

`weights.csv` = EW top-25 (Implementation-Discipline compliant, turnover 11.41), 268 as_of dates
(density ratio 1.0), Σw=1, [0,0.04] weights, long-only. This is the disciplined schedule for forge to
measure authoritatively — **not** a positive recommendation. Expected forge/judge outcome: FAIL.

## Constraints (all satisfied on handoff)

max_names 25 · long-only · [0,0.20] (actual max 0.04) · Σw=1 exact · schedule density 1.0 · NO
constraint relaxation performed (documented negative per R12 No Silent Override).
