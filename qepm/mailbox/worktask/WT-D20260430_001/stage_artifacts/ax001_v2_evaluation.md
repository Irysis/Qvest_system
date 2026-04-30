# AX-001 v2 3-Axis Evaluation — WT-D20260430_001 (M4 Trade War Fix)
Generated: 2026-04-30 11:30:16

## Context
Cycle WT-D20260430_001 (M4_TRADE_WAR_FIX) is a meta-allocation alpha (STR_1715 sleeve + cash), not a single-sleeve defense factor like prior cycle WT-D20260429_001. AX-001 v2 was originally calibrated for defense factors. Re-evaluation here treats M4 as a DIFFERENT DIMENSION: an overlay sleeve modulating an existing PG2 Core_Alpha. PASS criteria are documented honestly with limitations.

## Axis 1: crisis_alpha (8 stress periods, M4 vs S1 baseline)

| Stress | n_obs | M4 cum | S1 cum | S2 cum | M4-S1 alpha | M4-S2 alpha |
|---|---|---|---|---|---|---|
| GFC_2008 |  7 | -0.0331 | -0.0361 | -0.0331 | 0.0030 | 0.0000 |
| FlashCrash_2010 |  5 | 0.3828 | 0.3828 | 0.3828 | 0.0000 | 0.0000 |
| EuroCrisis_2011 |  4 | 0.0208 | 0.0482 | 0.0208 | -0.0274 | 0.0000 |
| ChinaShock_2015 |  7 | 0.1024 | 0.1024 | 0.1024 | 0.0000 | 0.0000 |
| VolMaggedon_2018 |  3 | 0.0204 | 0.0204 | 0.0204 | 0.0000 | 0.0000 |
| Covid_2020 |  3 | -0.0279 | -0.0428 | -0.0895 | 0.0149 | 0.0616 |
| Inflation_2022 | 12 | -0.0587 | -0.0587 | -0.0587 | 0.0000 | 0.0000 |
| TariffTantrum_2025_04 |  3 | 0.1767 | 0.1767 | 0.1767 | 0.0000 | 0.0000 |

- **n_positive_vs_S1**: 2 / 8 events with obs (PASS criterion: >= 3)
- **n_positive_vs_S2**: 2 / 8 events with obs
- **Axis 1 PASS**: FALSE

## Axis 2: MDD complement vs STR_1715 (full 267-month grid)

- **M4 MDD**: 0.3033
- **S1 MDD**: 0.3556
- **S2 MDD**: 0.3033
- **M4 vs S1 Δ**: +0.0523 pp (positive = M4 has smaller MDD = better)
- **M4 vs S2 Δ**: +0.0000 pp
- **Axis 2 PASS**: TRUE

## Axis 3: bad/normal regime IC ratio (combined_regime ≤ 0.3 vs ≥ 0.5)

- **n_normal**: 167 months, **n_bad**: 56 months
- **SR(normal) M4**: 1.6423, **SR(bad) M4**: 1.8586
- **SR(normal) S1**: 1.6265, **SR(bad) S1**: 1.7735
- **|bad - normal| / |normal| M4**: 0.1317
- **|bad - normal| / |normal| S1**: 0.0904
- **Axis 3 PASS** (>= 1.5): FALSE

## Statistical Significance (NW HAC)

- M4 vs S1 (lag=4): t=-1.4952, p=0.1361 (n=267)
- M4 vs S2 (lag=4): t=0.8102, p=0.4185 (n=267)
- M4 vs S1 (lag=12): t=-1.8280, p=0.0687
- M4 vs S2 (lag=12): t=0.8342, p=0.4049
- M4 vs S2 CRISIS-only (regime>0.6, lag=4): t=1.0604, p=0.2957 (n=39)

## Overall Verdict

- **Axis 1 (crisis_alpha PASS)**: FALSE
- **Axis 2 (MDD complement PASS)**: TRUE
- **Axis 3 (bad/normal ratio PASS)**: FALSE
- **AX-001 v2 OVERALL**: FALSE

## Trade War 2018-19 + COVID 2020 Reconciliation (KEY VALIDATION)

The optimizer's M4_TRADE_WAR_FIX hypothesis was that dropping the decay_strong moderate band
(Trade War 2018 false-positive zone) would resolve the M2/S3 baseline -0.95% drag while preserving
COVID 2020 protection. Forge realized backtest reconciliation (NW HAC sensible windows):

| Stress | M4 cum | S1 cum | S2 cum | M4-S2 alpha | Optimizer claim |
|---|---|---|---|---|---|
| Trade War 2018-19 (full 24mo) | -0.37% | -0.40% | -0.40% | +0.03pp | +0.03pp ✓ |
| COVID 2020 Q1 (Feb-Apr) | -2.79% | -4.28% | -8.95% | +6.16pp | +4.10pp (close) |
| GFC 2008-09 (Sep-Mar) | -3.31% | -3.61% | -3.31% | 0.00pp | (not optimizer claim) |
| EuroCrisis 2011 (4mo) | +2.08% | +4.82% | +2.08% | 0.00pp (vs S2) | (matched S2) |

**Trade War 2018-19 fix VERIFIED**: M4 -0.37% > S2 -0.40% (matched + 3bps margin). Optimizer's
"false-positive band drop" hypothesis works in full 24-month window.

**COVID 2020 protection VERIFIED + EXCEEDED**: M4 -2.79% better than S2 -8.95% by 616bps (vs
optimizer claim 410bps — Forge realized exceeds estimate, possibly due to deeper extreme protection
firing in 2020-02 + 2020-03).

**EuroCrisis 2011 NEGATIVE alpha vs S1**: M4 -2.74pp vs S1 — overlay sacrificed +2.74% by trimming
during 2011-08/09 (EuroDebt) when STR_1715 was rebounding. This is the cost of non-perfect timing.

## Honest Disclosure

M4 is a meta-allocation overlay, not a defense factor. The original AX-001 v2 calibration (built for
defense factors with crisis_alpha + MDD complement + bad/normal IC ratio >= 1.5) is applied here
with the understanding that overlay alpha primarily modulates M4 in EXTREME-only triggers
(10/267 months, 3.7% firing rate). Statistical significance vs S2 is borderline (p ≈ 0.42 lag=4 /
0.40 lag=12; aspirational improvement, not statistical rejection of H0: M4=S2).

**Critical honest finding**: M4 vs S1 NW HAC t=-1.50 (lag=4) — M4 sacrifices total compound return
(40.79% CAGR vs S1 41.91% CAGR = 1.12pp/yr drag) to achieve MDD complement (35.56% → 30.33% =
+5.23pp). M4 is **NOT** alpha-generating vs always-on; it's **risk-reduction** at the cost of mean
return. This is consistent with optimizer's documentation ("main value is variance reduction in
CRISIS bucket").

**vs S2 (existing MRS overlay)**: M4 +2.6 SR pp / +0.4pp CAGR / equal MDD. The M4 fix's value-add
is IN COMPARISON TO existing overlay, NOT vs always-on. PG2 admission rationale should focus on
"M4 strictly Pareto-dominates S2 in SR and Calmar".

**Compared to prior cycle WT-D20260429_001** (defense standalone failed Axis 2 with MDD complement
delta -1.3pp = 0 improvement): this cycle's Axis 2 is non-trivially positive (+5.23pp vs S1) BUT
the AX-001 v2 framework's other 2 axes are not designed for meta-allocation overlays. Axis 1 fails
because M4 is dormant in 6/8 stress periods (no firing); Axis 3 fails because M4 ≈ S1 by design
in normal regimes. **Recommend Governor + Q-Lead review of whether AX-001 v2 should be
revised/extended for meta-allocation type alpha (different from defense factor type).**

See chart oos_zoom_chart.png for visual reconciliation of Trade War 2018 + COVID 2020 + Inflation
2022 + Tariff 2025 zoom periods.
