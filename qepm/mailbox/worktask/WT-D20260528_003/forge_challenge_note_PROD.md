# Forge Challenge Note — WT-D20260528_003 D_PROD

**Codex stance**: REJECT (7 concerns: 5 HIGH, 2 MEDIUM)
**Codex response**: `codex_critic_response_forge.json`
**Self-rationalization audit**: 0 forbidden-phrase hits ("미미/관행적/보수적이면 OK/대부분 동일/실무적")
**Escalation check**: HIGH≥5 → reviewed. NO AX hard-FAIL, NO PIT C1, NO fabrication. Hard-gate FAILs (MDD/TO/DSR) are HONESTLY SURFACED, not overridden — they are Judge's adjudication scope, not forge defects. Escalation NOT triggered (resolutions are disclose-and-handoff, not silent pass).

## Resolution Summary

| Concern | Severity | Resolution | Action |
|---|---|---|---|
| C1 MDD 47.68% > 45% | HIGH | ACCEPT | Surfaced as `hard_gate_fails.mdd_45_fail=true`. Honest. Judge adjudicates. |
| C2 TO 6.018 > 6.0 | HIGH | ACCEPT (with convention note) | Surfaced as `hard_gate_fails.turnover_6_fail=true` + convention disclosure. Judge adjudicates. |
| C3 Same-period incumbent baseline absent | HIGH | PARTIAL | KOSPI200 same-period/cost done. STR_1715 per-stock reconstruction INFEASIBLE from artifacts (overlay-scalar only). Documented limitation. |
| C4 5-spec Harvey incomplete | HIGH | ACCEPT | RAN. `forge_harvey_addendum.json`: CAPM/Carhart3/4/FF5/FF6 t_NW. 0/5 PASS at t≥2.95. |
| C5 DSR total search penalty not explicit | HIGH | ACCEPT | Total candidates = alpha n_trials_eff 411 + optimizer 8 = 419 documented. DSR binding FAIL inherited honestly. |
| C6 Sharpe provenance inconsistent (0.8204 vs 0.7523) | MEDIUM | ACCEPT | Reconciled to SINGLE SOT = 0.8204 (contract mean-ER, Charter v1.4 §12). Chart + package + bundle now consistent. 0.7523 = aux geometric only. |
| C7 Artifact lineage ambiguous | MEDIUM | ACCEPT | Lineage documented: alpha/weights = `stage_artifacts/WT_D20260528_003`, cov = `..._risk_PROD`. Hash audit PASS confirms exact inputs. |

---

## C1 — Forge realized MDD 47.68% > 45% hard gate [HIGH] → ACCEPT

**Concern valid.** Daily share-based backtest MDD = 0.47675 (contract `06_metrics.csv`), above the 45% hard cap. This is the actual full-period (2014-04~2026-05) share-based drawdown, not a partial-book dispute.

**Resolution**: Forge does NOT mask this. Surfaced in `forge_package_PROD.json::hard_gate_fails.mdd_45_fail=true` with realized value 0.4768. IS MDD = 0.4768 (the GFC-era is pre-2014 so this is a post-2014 drawdown, dominated by 2020 COVID + 2022 KR bear). OOS MDD = 0.3287 (frozen book, better).

**Boundary**: Forge is pure-function — it cannot re-optimize to reduce MDD (that is optimizer scope, already finalized). The honest forge action is to REPORT the gate FAIL. Graduation/admission verdict belongs to Judge/Governor. Quantitative data 3-axis: realized MDD 0.4768 (contract), gate 0.45, exceedance +0.0268 (2.68pp).

## C2 — Forge realized turnover 6.0181 > 6.0 hard cap [HIGH] → ACCEPT (convention note)

**Concern valid.** Realized annual round-trip TO = 6.0181 > 6.0 hard cap. Codex correctly notes the formula is round-trip (not RF-F7 inflation) — it is a TRUE marginal hard-constraint fail.

**Resolution**: Surfaced as `hard_gate_fails.turnover_6_fail=true`.

**Convention disclosure (NOT a rebuttal, a measurement-basis fact)**:
- Optimizer reported 5.282 using **target-vs-target** turnover (|w_target_t − w_target_{t-1}|/2).
- Forge measures **target-vs-DRIFTED** turnover (|w_target_t − w_drifted_{t-1}|/2), which is the *realized executable* turnover after intra-period price drift. This is structurally ≥ target-vs-target and is the economically correct trade volume.
- The 0.74pp gap (6.018 vs 5.282) is the drift effect, not an error in either.
- The contract's `Annualized_Turnover=55.66` is a **daily-cadence annualization artifact** (per-rebalance-day TO × 252, treating 252 days as the cadence base while only 116 monthly rebalances occur). It is NOT economically meaningful and MUST NOT be used. The correct trade-level figure is 6.018.

Judge to adjudicate which convention governs the 6.0 cap. Either way forge reports honestly.

## C3 — Same-period incumbent/PG2 baseline fairness absent [HIGH] → PARTIAL

**Concern valid in principle** (v6.1 Same-Period Baseline Comparison Mandate).

**What was done**: KOSPI200 same-period, same-15bps-cost, PerformanceAnalytics comparison (`07_benchmark_compare.csv`):
- Strategy Sharpe 0.8204 vs KOSPI200 0.6418 (+0.1786)
- Alpha +8.57%/yr, beta 0.985, IR 0.436, TE 19.2%, correlation 0.701, up-capture 1.076, down-capture 0.998.

**What was NOT done + WHY (documented limitation, not silent omission)**: A same-period STR_1715 PG2 incumbent comparison requires the incumbent's per-stock tradeable holdings. The available STR_1715 artifacts (`05_Production/.../weights.csv` + `weights_267m_timeseries.csv`) are **regime-overlay scalar timeseries** (R05_z_avg, m4_scalar, beta_AR, cash_share), NOT per-ticker weights. Reconstructing STR_1715 share-based NAV would require re-running its full alpha engine + overlay pipeline — which is OUTSIDE forge pure-function scope (forge integrates the 3 packages of THIS WT, read-only). Forcing a reconstruction would risk fabricating an incumbent path.

Judge/Governor have direct access to STR_1715 PG2 documented metrics and can perform the incumbent Δ at admission stage with the proper pipeline. This is the honest scope boundary. (Answer-principles #7 uncertainty-explicit, #5 risk-explicit.)

## C4 — 5-spec Harvey regression incomplete [HIGH] → ACCEPT (RAN)

**Concern valid.** Alpha emitted CAPM only. Forge has the KR FF5 v2 factor returns and 144 monthly obs — so this is squarely in forge attribution scope (P7 Attribution mandate).

**Resolution**: RAN full 5-spec NW-HAC (`forge_harvey_addendum.json`):

| Spec | alpha (ann) | t_NW | verdict (t≥2.95) |
|---|---|---|---|
| CAPM | +12.03% | 1.950 | FAIL |
| Carhart3 | +10.91% | 2.106 | border |
| Carhart4 | +11.02% | 2.179 | border |
| FF5 | +11.02% | 2.154 | border |
| FF6 | +11.21% | 2.255 | border |

**Harvey 5-spec PASS = 0/5.** Alpha is positive (~11%/yr after risk factors) but t_NW peaks at 2.255 (FF6), below the Harvey-Liu-Zhu (2016) multiple-testing hurdle of 2.95–3.0. **This corroborates the alpha-stage DSR FAIL** — the strategy does not clear multiple-testing-adjusted significance. This is decisive evidence for Judge.

## C5 — DSR total search penalty not explicit [HIGH] → ACCEPT

**Concern valid.** Total search space must be explicit.

**Resolution**: Documented in `forge_package_PROD.json::dsr_inheritance`:
- Alpha multiple-testing: `dsr_n_trials_eff = 411` (LightGBM Optuna trials), `dsr_proper = 3.05e-15`, `dsr_z = -7.80`.
- Optimizer: 8 methods compared (`method_shopping_log.candidates_tried=8`).
- Total search candidates ≈ 411 + 8 = **419**.
- Forge monthly realized DSR_raw = 2.589 (PRE-penalty, on 144 obs) — but the binding gate is the ALPHA-stage DSR_proper which already incorporates the 411-trial penalty and FAILs at z=-7.80. Forge does NOT re-derive a more favorable DSR; the binding alpha DSR FAIL is inherited as-is. Harvey 0/5 (C4) is the independent confirmation of the same multiple-testing problem.

`graduated=false` retained throughout.

## C6 — Sharpe provenance inconsistent (0.8204 vs 0.7523) [MEDIUM] → ACCEPT

**Concern valid.** Draft had 0.8204 in package (contract mean-ER) but 0.7523 in `forge_metrics_bundle` + equity_curve title (table.AnnualizedReturns geometric).

**Resolution — single authoritative convention**:
- **SOT = 0.8204** = contract `build_bt_result()` Sharpe = `mean(ER)/sd(ER)*sqrt(252)` (Charter v1.4 §12, the sanctioned method). This is THE authoritative `sr_realized_share_based`.
- 0.7523 = `table.AnnualizedReturns` geometric-return/SD basis, retained as `sr_pa_geometric_aux` ONLY (cross-check, not primary).
- Chart title regenerated to 0.8204. `forge_metrics_bundle.json` provenance patched. All three artifacts now consistent.

## C7 — Artifact lineage ambiguous [MEDIUM] → ACCEPT

**Concern valid.** Codex saw a stale v3.6 dir reference.

**Resolution — canonical lineage**:
- alpha: `qepm/mailbox/worktask/WT-D20260528_003/alpha_package_PROD.json` (md5 2b8df9b2…) + scores `stage_artifacts/WT_D20260528_003/alpha_scores.parquet`
- risk: `risk_package_PROD.json` (md5 347f8d7d…) + covariance `stage_artifacts/WT_D20260528_003_risk_PROD/covariance.parquet` (md5 27a6643a…)
- optimization: `optimization_package_PROD.json` (md5 31c5fdcb…) + `stage_artifacts/WT_D20260528_003/weights.csv` (md5 bf4974d2…)

Forge consumed EXACTLY these (PROD suffix, READ-ONLY). START==END hash audit **PASS** confirms zero modification. Stale `archive_v3_*` dirs are NOT inputs. Reproducibility (AX-008) anchored by hash integrity.

---

## Net Outcome

Codex REJECT substantively addressed, NOT overridden:
- **Actionable gaps CLOSED**: C4 (Harvey 5-spec RAN, 0/5), C6 (SR reconciled to 0.8204 SOT), C5 (419-candidate penalty documented), C7 (lineage + hash PASS).
- **Hard-gate FAILs HONESTLY SURFACED**: C1 (MDD 47.68%>45%), C2 (TO 6.018>6.0), inherited DSR FAIL. Forge does NOT graduate (graduated=false). These are Judge/Governor adjudication, not forge pure-function defects.
- **Documented limitation**: C3 (STR_1715 incumbent per-stock reconstruction infeasible from overlay-scalar artifacts — out of forge scope, KOSPI200 same-period comparison provided instead).

**Final handoff**: `forge_to_judge_dsr_fail_acknowledged`. Forge's job is honest measurement + integration, not gate-passing. The strategy FAILS DSR + Harvey-2.95 + MDD-45 + TO-6.0; forge reports all four transparently. Judge owns the verdict.
