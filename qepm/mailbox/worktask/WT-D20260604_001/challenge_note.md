# Challenge Note — WT-D20260604_001 Composite Momentum (Alpha)

**Agent**: alpha-research
**Date**: 2026-06-04
**wt_type**: discovery
**Verdict (self)**: VALIDATED_SOFT_FAIL — composite momentum NOT a viable standalone KR discovery alpha.

---

## Codex Critic Round — `codex_skip_waiver`

**Status**: SKIPPED (waiver). Codex round did **not** execute.

**Reason**: `codex` CLI is not installed on this Windows-native environment (fresh migration; `npm install -g @openai/codex@latest` never run). `run_codex_qepm_critic.sh` correctly detected absence via `command -v codex`, wrote a STUB response (`stance: STUB`, `codex CLI unavailable`), and exited 0 (no silent failure). The PostToolUse `codex_round_auto_trigger` hook is also inactive pre-restart.

**Waiver type**: `codex_critic_skip_waiver` — infra unavailability (not a process bypass). Per `.claude/rules/codex-round.md` exception clause + Q-Lead urgent waiver. This WT is the **migration validation cycle**; codex availability on Windows is itself one of the checks (and the finding is: NOT available — install required for future cycles).

**Compensating control**: rigorous self-critique below (AX-008 Verification Triangulation partial — Forge-grade canonical_screen_bt 실측 used as the authoritative measurement; Architect/Codex legs unavailable → triangulation = 1/3, **does not satisfy AX-008 2/3**). Because the alpha is a **soft-fail (not advancing to admission)**, the unmet triangulation does not gate a deployment — but any future attempt to graduate momentum MUST re-run codex once CLI installed.

**Post-hoc obligation**: Layer 2 sweep (`cert_backfill_audit.R`) + codex re-run when `codex` CLI is installed on Windows.

---

## Self-Critique (in lieu of Codex)

### Concern 1 — composite rank-IC ≈ 0.000, Harvey-t ≈ 0 [classification: ACCEPT, it is the finding]
Measured: composite rank-IC = −0.00002, ICIR ≈ 0, Harvey-t ≈ 0 over 191 months (2008-01 → 2023-12).
Per-signal: MOM_12_1 IC=0.0038 (t_harvey 0.21), MOM_6_1 IC=**−0.0065** (t_harvey −0.40), RESID_MOM IC=0.0024 (t_harvey 0.21).
This is **not a bug — it is the empirical result**. KR equity momentum is structurally weak / reversal-prone (well documented: Korea shows short-horizon reversal where US/EU show momentum). The EW composite averages a weakly-positive 12-1, a negative 6-1, and a weak residual → near-zero. Intra-composite correlation is high (0.55–0.88), so no diversification benefit.
**Not rationalized away** — reported at face value.

### Concern 2 — rank-IC ≠ portfolio-alpha t (Cycle 2 lesson) [ACCEPT, explicitly separated]
Despite rank-IC ≈ 0, the **top quintile** has the highest forward return (Q5 = 1.00%/mo vs Q1–Q4 ≈ 0.4–0.7%), so the long-only top-20 screen yields a non-trivial **portfolio-alpha t (NW lag-3) = 1.633** (net SR 0.414, IR 0.414, 15bps, turnover 8.04/yr). This is the Cycle 2 教訓 in action: a tail edge invisible to full-cross-section rank-IC. **Both metrics reported separately** (rank-IC Harvey-t ≈ 0 vs portfolio-alpha t = 1.63).
**However**: 1.633 << 2.95 (hard hurdle, `measurement-graduation.md` §3, Harvey-Liu-Zhu). **FAIL on the authoritative gate.**

### Concern 3 — subperiod instability [ACCEPT]
subperiod_stability = 0.333. Only p1 (2008–2014) positive (mean IC +0.0117); p2 (2015–2019, −0.0092) and p3 (2020–2023, −0.0094) negative. Momentum **decayed / inverted post-2015** in KR — consistent with global momentum crowding + KR retail-flow reversal dominance. This kills any forward-looking case.

### Concern 4 — DSR gate [PARTIAL / N-A]
DSR not computed as a binding gate: per `measurement-graduation.md` §3 (2026-05-31 mandate), DSR≥0.5 is HARD **only for multiple-testing styles (n_trials>1)**. This is a single composite alpha (n_trials≈1: 3 component signals tested, logged in method_log, candidates_tried=3 ≤ 5 cap). For single-alpha, **oos_retention + portfolio_alpha_t** govern, and portfolio_alpha_t=1.63 already fails. No DSR fishing.

### Weakest assumption (self-identified)
The residual-momentum construction uses **sector-neutralization only** (cross-sectional `lm(MOM_12_1 ~ factor(Sector))`), a simplification of true Grinblatt-Moskowitz residual momentum (which regresses *return series* on FF factors over a rolling window). A fuller time-series residual (market-beta + size + value neutralized rolling) might recover more idiosyncratic momentum. But given MOM_12_1 itself has IC=0.0038 / Harvey-t=0.21, the headroom is small — unlikely to cross 2.95. Flagged as a possible refinement, not a rescue.

---

## Graduation Gate Result (alpha-stage screening, forge-authoritative pending)
| Gate | Value | Hurdle | Severity | Result |
|---|---|---|---|---|
| portfolio_alpha_t_nw_lag3 | **1.633** | ≥ 2.95 | HARD | **FAIL** |
| rank_ic | −0.00002 | ≥ 0.04 | advisory | FAIL |
| icir | ≈ 0 | ≥ 0.20 | advisory | FAIL |
| subperiod_stability | 0.333 | ≥ 0.50 | advisory | FAIL |
| harvey_t (rank-IC) | ≈ 0 | ≥ 3.0 | advisory | FAIL |
| DSR | N/A (n_trials≈1) | ≥ 0.5 | hard (only if n_trials>1) | not applicable |

**Decision**: Do NOT advance to risk/optimizer for admission. Honest soft-fail.

## Disposition (research_philosophy ① ④)
- ① Factor Zoo 축소 — Validation > Discovery: this is a **validated rejection** of composite price momentum as KR standalone alpha. Negative result has value (prevents future re-discovery).
- ④ Direct Portfolio Learning: the three momentum z-scores are retained as **DPL input features** (`alpha_scores.parquet`), not discarded — failed standalone alpha = DPL fuel.

## L-code candidate (for Q-Lead memory)
KR composite momentum (12-1 + 6-1 + sector-residual) standalone long-only: rank-IC ~0, portfolio-α t 1.63 < 2.95, subperiod-unstable (positive only pre-2015). VALIDATED_SOFT_FAIL. Reusable as DPL feature.
