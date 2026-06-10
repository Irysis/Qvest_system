# Risk Challenge Note — WT-D20260606_001

**Agent**: risk-research (Opus 4.8)
**Date**: 2026-06-06
**Codex critic**: gpt-5.5 (xhigh), stance = **REVISE**, 6 concerns. veto=false.
**Disposition summary**: ACCEPT 4 (C1, C4, C5, C6) · PARTIAL 1 (C2) · REBUTTAL 1 (C3 AX-002 framing)

Codex critique is devil's advocate, not authoritative. Each concern classified with quantitative basis. Several ACCEPTs materially *weakened* my draft's confidence claims — this is correct and incorporated (honest reporting > defending the diversifier thesis).

---

## C1 [HIGH] — Weakest Σ assumption: diagonal D while factor_share 97.2% / MKT 96.4% → market-factor collapse?
**Disposition: ACCEPT (with computed evidence).**

Codex is right that the diagonal-D assumption deserved verification. I computed the **residual off-diagonal correlation** after BΩB'+D fit (`risk_revise.json::residual_offdiagonal`):
- mean −0.0127, **abs-mean 0.115**, max 0.999, **81 / 1225 pairs |cor| > 0.30**.

This **confirms diagonal-D is violated** — there is meaningful residual co-movement (the max 0.999 indicates a near-duplicate ticker pair, e.g. dual-class/holding structure). Action taken:
- Final package now reports residual off-diagonal diagnostics and **down-weights the structural Σ to ADVISORY for attribution only**; the optimizer is directed to prefer **direct Ledoit-Wolf Σ** (cond 1.0, PSD) or a **structural Σ with residual-correlation block** if it needs factor attribution. MKT 96.4% is honestly labeled a single-market-universe artifact (all 50 names share the dominant KR market mode — this is the structural truth from [[reference-str1715-structure]]: KR long-only covariance 1st eigenmode dominance, no-short cannot remove it). Not "expected, no problem" — it is a genuine concentration that the optimizer must handle.

Academic basis: Ledoit-Wolf (2004) shrinkage is precisely the remedy for noisy sample Σ at p/n=0.20; direct-LW provided as the PSD well-conditioned handoff.

---

## C2 [HIGH] — Diversifier conclusion is only narrow (beta_down +0.082, vol 30% vs 24%, GFC −42.7% → not hedge/defensive)
**Disposition: PARTIAL → mostly ACCEPT, with bootstrap evidence that goes FURTHER than Codex.**

I ran bootstrap CIs (B=2000, `risk_revise.json::bootstrap_ci`) and a downside-only sensitivity. The results **weaken my own draft more than Codex asked**:
- **cov_contribution 95% CI [−0.0149, +0.0056]** — straddles zero. P(cov<0)=0.806.
- **full_cor 95% CI [−0.213, +0.077]** — straddles zero.
- **beta_down 95% CI [−0.531, +0.713]** — essentially unestimable at n=267.
- **cov_contribution downside-only (R05<0, n=82) = +0.0014 (POSITIVE)** — the slight diversification flips to mild co-movement exactly when R05 is down.

ACCEPTED: removed all "GENUINE diversifier confirmed", "NO crash clustering", "hedge/defensive" language. Final framing: **"return-orthogonal in the mean (point cov −0.0044, ~81% prob negative) but the diversification benefit is statistically uncertain (CI straddles 0) and concentrated in non-stress regimes; it is NOT a downside hedge (downside cov +0.0014) and carries severe momentum-crash tail."** This is the most defensible honest statement and directly serves the optimizer's ΔIR decision (which should treat the benefit as a weak prior, not a fact).

---

## C3 [HIGH] — Canonical-screen discrepancy (risk t=2.06 vs alpha t=1.461) is AX-002 until reconciled
**Disposition: REBUTTAL on the AX-002 framing; ACCEPT the reconciliation duty (now DONE).**

I reconciled the root cause (`risk_revise.json::tstat_reconciliation`):
- Turnover matches 7.05/7.06 → **holdings identical** (confirmed).
- **Contemporaneous-benchmark alignment reproduces alpha: t=1.583 / IR=0.238** vs alpha 1.461/0.219 (residual = liq 5e7-vs-2e8 + winsorize minutiae).
- **Forward-benchmark alignment (risk default): t=2.06 / IR=0.469.**

Root cause: **alpha aligned the benchmark to the SCORE month (backward); risk aligned to the FORWARD realized month.** When portfolio return is realized over t→t+1, the correct benchmark is the market over t→t+1 (forward). So risk's alignment is **methodologically more correct**, and alpha's t=1.461 is mildly understated by a backward-BM misalignment.

REBUTTAL of AX-002: AX-002 = "process bypass = lookahead." My method is fully documented (risk_build.R), reproducible, and uses the *more* PIT-correct alignment (forward port vs forward BM — no lookahead). This is a **legitimate R3 cross-stage measurement difference**, not a process-honesty violation. Filed as **RF-R6 challenge to alpha** (benchmark-alignment reconciliation) rather than an AX-002 self-flag. **Conclusion invariant**: 1.46 / 1.58 / 2.06 are ALL < 2.95 → standalone FAIL confirmed under every alignment. (academic: forward-return / forward-benchmark pairing is the standard Jegadeesh-Titman 1993 momentum measurement convention; L-code: measurement-graduation §2 portfolio-alpha = realized active over the held period.)

---

## C4 [MEDIUM] — RF taxonomy inconsistent (RF-R2 threshold cond>100 vs draft cond>500; RF-R6/R7/R8 mislabeled)
**Disposition: ACCEPT.**

Two different RF-R rubrics exist: risk_research_init.md (RF-R2 = cond>500) vs codex_risk_critic_prompt.md (RF-R2 = cond>100). I conflated them and reused RF-R6/R7/R8 ids for ad-hoc flags. Fixed in final:
- Report **both thresholds explicitly**: structural cond 86.2 < 100 (critic rubric PASS) and < 500 (init rubric PASS); sample cond 239.9 > 100 (hence structural/LW preferred).
- Renamed my custom flags to a separate `risk_extra_flags` namespace (RX-1..RX-4) so they don't collide with the canonical RF-R6 (Hill α heavy tail) / RF-R7 (factor decay) / RF-R8 (regime small sample) in the critic rubric.

---

## C5 [MEDIUM] — Tail/stress under-flagged (CVaR95 17% vs 2.5% cap; 7 windows not 8; GFC cumulative ≠ single-period RF-R4)
**Disposition: ACCEPT.**

- **Single-month stress now reported** (`risk_revise.json::single_month_stress`): **worst sleeve 1m = −26.8% (2008-09)** vs R05 −15.1%. This **legitimately triggers RF-R4** (single-period > 25%) at the monthly level. GFC −42.7% relabeled explicitly as *window-cumulative* (not RF-R4 proof). 8th window **Brexit 2016 added** (sleeve_cum −2.4%).
- **CVaR95 monthly −17.0% vs 2.5% cap**: the 2.5% cap is a portfolio-level monthly cap; this is a **standalone single-sleeve 20-name concentrated momentum series** (30% ann vol), so a 17% monthly CVaR is expected and is NOT a portfolio CVaR. I flag it as RX-3 and note: **the optimizer must size this sleeve small** (CVaR cap applies to the *book*, not the raw sleeve). No infeasibility report at risk stage because risk does not set weights; the CVaR breach is a sizing constraint handed to the optimizer.

---

## C6 [MEDIUM] — TDC 0.131 proxy-level, no bootstrap CI, crisis n<30
**Disposition: ACCEPT.**

Bootstrap added: **TDC 95% CI [0.06, 0.24]** — entire CI < 1.0 (no tail clustering) but wide and proxy-level. Crisis windows (GFC n=18, Euro n=6, COVID n=6, Rate n=12) explicitly labeled **small-sample, no per-window CI** (n<30, RF-R8 acknowledged). I report them as directional context only, not statistical claims. The robust tail statement is: **empirical lower-tail dependence proxy 0.13 [0.06, 0.24] → no evidence of crash clustering with R05, but the estimate is imprecise.**

---

## AX-008 Triangulation
Codex set ax_008 = FAIL (no independent Forge/Architect + no uncertainty bands). I now provide **uncertainty bands (bootstrap CIs)** for all central co-risk claims, and the structural-vs-sample-vs-LW Σ three-way comparison is an internal triangulation. Full AX-008 (Forge/Architect 2/3) is a downstream judge/forge responsibility, not resolvable at risk stage. Acknowledged as a downstream gate, not silently closed.

## No Silent Override (Charter §8)
No alpha factor mix changed, no regime label redefined, no weights proposed. Alpha challenge filed as RF-R6 (benchmark alignment) — explicit, not silent.

## Self-rationalization audit
Codex flagged 6 of my phrases as rationalization ("GENUINE diversifier confirmed", "NO crash clustering", "MKT dominance expected", "well-conditioned no escalation", "RF-R2_cond_gt_500", "conclusion unchanged either way"). **5 of 6 ACCEPTED and removed/qualified.** The 6th ("conclusion unchanged either way") is retained because it is **quantitatively true** (1.46/1.58/2.06 all < 2.95) — but reframed as the reconciliation result, not a dismissal.
