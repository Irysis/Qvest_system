# Optimizer Self-Adversarial Challenge — WT-D20260705_001

**Agent**: optimizer-research (v8.2, Opus 4.8 native adversarial reasoning — no external Codex)
**As-of**: 2026-07-05
**Scope**: weights only. Alpha α̂ + Risk Σ received read-only, unmodified.
**Verdict summary**: NO mandate-compliant weighting method lifts the alpha past the capital-grade gate (portfolio-alpha t = 2.95). Best compliant method (AlphaProp+buffer) net_port_t ≈ 2.63 vs KOSPI200, EW baseline 1.77. Weighting is a modest lift, not a rescue. This alpha is SCREEN_TIER — confirmed.

---

## Measurement basis (honesty pre-condition)

- **Authoritative benchmark = KOSPI200 total return** (request.json `benchmark_definition`, measurement-graduation §2). All headline t-stats below are net-active vs KOSPI200, NW lag-3.
- Returns: RAWDATA daily total return `Ret` compounded to monthly; KOSPI200 from RAWDATA `BM_Ret` (corrected IKS200 per benchmark bug-fix 2026-07-02). Signal month t → realization t+1 (PIT).
- **Reconciliation vs alpha agent**: my EW top-25 net_port_t = 1.769 vs alpha agent's reported 1.41 (clean IKS200 vintage). Same order, same SCREEN_TIER verdict; residual gap = benchmark-vintage/compounding basis. NOT a signal discrepancy.
- **Trap avoided**: the alpha panel's `F1_active_realized` column is active-vs-EW-universe-mean (cross-sec mean = 0), NOT vs KOSPI200. Using it directly would inflate t to ~2.7 for EW — a false pass. I re-measured against the mandated cap-weighted KOSPI200. This is the single most important honesty guard in this package.

---

## Self-concern 1 (ACCEPT — mandatory) — Concentration methods "pass" only by violating the mandate

- Raw MVO_l2 headline net_port_t = 2.827 and MVO_l2+buffer = 2.899 (closest to 2.95). **But both are disqualified:**
  - median 14 names (<15 in 113/197 months) → violates Grinold breadth floor (min_names 15) hard-coded in system prompt.
  - avg HHI 0.12 > 0.10 cap.
  - turnover 15.4/yr > 11.0 cap (raw); buffer brings to 11.2 but breadth/HHI still fail.
- The MVO edge is a recent-tail artifact: advantage over EW is +38.7 bps/mo on average but sourced almost entirely from 2023 (+393 bps/mo), 2025 (+144), 2026 (+540 over 6 months on a 7-16 name book). In 2012-2015 MVO *underperformed* EW by 50-180 bps/mo. A full-period t inflated by a thin concentrated recent window is exactly the DGU-2009 / measurement-graduation §6 failure mode.
- **Resolution**: forced MVO to comply (min_names≥20, HHI≤0.10, bounds [0,0.20]) → net_port_t collapses 2.827 → **2.232** (compliant), 2.652 (compliant+buffer). No silent relaxation; disqualification is explicit in method_comparison with `mandate_compliant` flags. ACCEPTED.

## Self-concern 2 (ACCEPT — mandatory) — Post-2017 decay makes any full-period t misleading

- Compliant MVO+buffer subperiod: pre2018 t=3.28, post2018 t=0.51, **post2022 t=−0.14**.
- EW: pre2018 t=2.85, post2018 t=0.18, post2022 t=−0.36.
- The alpha has decayed to zero/negative recently across every weighting scheme. No sizing method reverses cohort-wide decay (KR post-2017 structural, 6-method common per alpha package + memory [[project-discovery-substrate-phase0]]). The full-period t is dominated by pre-2018. ACCEPTED — reported prominently; does NOT override SCREEN_TIER_FAIL.

## Self-concern 3 (ACCEPT) — Sizing does not fix a selection-driven alpha (Grinold breadth)

- The alpha's residual edge is in name *selection* (top-25 membership), not in *sizing*. EW→AlphaProp lifts t 1.77→2.12 (net_ir 0.41→0.50) — a real but small tilt gain, entirely inside pre-2018. Confidence-weighting (ConfAlphaProp) does not beat plain AlphaProp. This confirms the alpha-search-style prior: broad-alpha edge is selection, not weighting. ACCEPTED.

## Self-concern 4 (PARTIAL) — Turnover control genuinely helps and is not cosmetic

- Raw alpha turnover 12.5/yr (EW) already under the 11.0-mandate only after buffering. Buffer zone (top-40 inertia 40%) reduces turnover EW 12.5→11.7, AlphaProp 12.8→10.9 AND *raises* net_port_t (AlphaProp 2.12→2.63) by cutting churn cost without losing signal. This is a legitimate implementation-discipline win (research_philosophy ⑥). PARTIAL: it improves the number but still lands at 2.63 < 2.95 — not a graduation lever, an efficiency lever.

## Self-concern 5 (REBUTTAL) — Is the PIT covariance letting MVO peek at winners?

- Concern: MVO uses a trailing-60m active-return covariance; could it be look-ahead? Rebuttal (3-axis):
  - **Academic**: Ledoit-Wolf shrinkage (δ=0.81, matching risk agent) on strictly `Date < d` history — standard PIT walk-forward.
  - **L-code/structural**: covariance built only from `F1_active_realized` at dates strictly before the rebalance; no realization-month data enters weight construction.
  - **Quantitative**: even with the PIT covariance, compliant MVO underperforms in 2012-2015 and post-2022 — a look-ahead artifact would help uniformly. The concentration edge is time-clustered (recent tail), consistent with small-sample variance, not peeking. REBUTTAL sustained: the MVO issue is concentration/mandate-violation + tail-variance, not look-ahead.

## RF-O9 walk-forward (ACCEPT, unconditional) — weights.csv is a full time series

- weights.csv = 197 as_of_dates × 25 names (2010-01 … 2026-05), schedule_density_ratio = 1.00 ≥ 0.95. No single-snapshot. Turnover computed as delta round-trip (Σ|Δw|, one-way, ×15bps) — NOT ×12 annualization shortcut (annualized = mean monthly traded × 12). Verified: Σw∈[0.999996,1.000004], n=25 all dates, max weight 0.093 < 0.20, all ≥ 0.

---

## Escalation check
- Hard-constraint violations in the RECOMMENDED method: NONE (25 names, [0,0.20], Σw=1, turnover 10.9<11.0, liq — top-25 all large/mid cap ≫ 2e8). No Q-Lead escalate trigger fired.
- Disqualified methods (raw MVO variants) are reported with explicit violation flags, not silently dropped (No Silent Override, R12).

## AX-008 triangulation
Self-adversarial = 1 of 3 sources. Forge (build_bt_result re-measurement) + judge Gate are downstream. This package's numbers are `metric_type=canonical_screen`-equivalent (walk-forward helper), NOT forge-authoritative — admission binding = forge re-measure.

## Bottom line
Weighting cannot rescue this alpha. Recommended = **AlphaProp+buffer** (net_ir best among mandate-compliant, net_port_t 2.63, turnover 10.9). Still SCREEN_TIER (< 2.95). Route: DPL feature / factor-rotation RCMA input, not capital admission.
