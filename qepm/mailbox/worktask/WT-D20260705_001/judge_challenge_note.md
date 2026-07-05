# Judge Self-Adversarial Challenge — WT-D20260705_001 (v8.2)

**Agent**: judge (Opus 4.8 native adversarial reasoning — no external Codex, v8.2)
**Date**: 2026-07-05 | **Strategy**: XATTN 5-seed Cross-Sectional Attention super-factor
**Verdict under challenge**: JUDGE_FAILED (capital), SCREEN-ROUTE eligible. essence_score Grade **B** (hard_fail=FALSE).
**AX-008 role**: Judge = adjudicator, NOT a triangulation source. 3-source = Forge(실측) + Self-Adversarial(agent challenge notes) + Architect. 2/3 PASS required.

Before finalizing I attack my own verdict: could this actually be capital-grade and I'm rubber-stamping a FAIL?

---

## Challenge 1 [devil's advocate] — Am I FAILing a strategy whose signal is provably real, on gates that punish a KR-structural (not strategy-specific) decay?

**Attack**: rank-IC t = 4.41 (HLZ hurdle t>3 + Bonferroni-18 PASS, placebo p=0). The signal is unambiguously real cross-sectionally. Calmar 0.58 misses 0.64 by a hair. The OOS collapse (0.037) and post-2018 decay are documented as *cohort-wide KR post-2017 decay* — a market-structure fact common to all 6 super-factor methods, NOT a defect of THIS strategy. Should I therefore treat the graduation gates as too blunt and pass it?

**Self-defense (why FAIL stands)**:
- The authoritative metric is **portfolio_alpha_t_nw_lag3 = 2.36** (forge build_bt_result, backtested), NOT rank-IC. measurement-graduation §2 is explicit: rank-IC ≫ portfolio-alpha is the *exact* divergence the whole graduation system exists to catch (Cycle-2 reference: rank-IC t 4.41 → realized port_t 1.41 EW / 2.36 optimized). Rank-IC strength is advisory; it does not rescue realized net alpha.
- The gates are **capital-admission** gates. Whether the decay is "structural KR" or "strategy-specific" is irrelevant to whether *deploying capital today* earns alpha: post-2022 PORT_t = −0.31 (forge), −0.01 (optimizer), −0.76 (alpha canonical). Deploying now = no expected active return. AX-000 requires honest FAIL of an empirically-established limit; passing it "because the decay is market-wide" is precisely the self-rationalization AX-000 reframe (2026-06-21) forbids.
- essence_score (authoritative) = Grade **B** with reason `OOS_ret 0.04<0.7(band fail), Calmar<0.64`. Two independent HARD gates fail (OOS, Calmar) + PORT_t 2.36<2.95. Not one marginal miss — three.
- **Verdict holds. FAIL is over-determined, not borderline.**

## Challenge 2 — Is the FAIL an artifact of the wrong universe? The mechanism is strong (port_t 6.06) in broad universe.

**Attack**: allliq universe port_t = 6.06, IR 1.39, calmar 1.75 — that IS capital-grade. Am I FAILing a good alpha just because the WT mandated the "wrong" (K200∪KQ150) universe where mega-caps lack peer-dispersion?

**Self-defense**: The WT mandate fixes the deployment universe = KOSPI200∪KQ150 (the book's investable set). allliq (median ~1438 names, deep small-caps) is explicitly labeled by the alpha agent as "mechanism location, NOT deployment." A strategy graded on a universe it cannot be deployed in is meaningless for admission. Even allliq fails oos_retention (0.30 < 0.7). The broad-universe strength is a legitimate *research finding* (routes to DPL-feature / broad+overlay follow-up WT) but not a capital-admission basis here. Universe mismatch is correctly a challenge_flag (HIGH), not a verdict-flip.

## Challenge 3 [Judge-specific REBUTTAL area] — PIT: is the ad-hoc training benchmark a C1/C2 look-ahead that invalidates everything?

**Attack**: xattn_score.py trains the attention net on a Sharpe loss using `kns_master_bench.parquet` = the 1-month early-shifted (corrupted) benchmark (clean[t]==master[t+1]). If future benchmark leaks into training, the learned scores are look-ahead-contaminated and PORT_t 2.36 is on sand. This is the single item I must verify, not accept.

**Self-defense / adjudication (REBUTTAL sustained)**:
- The training benchmark enters ONLY as a **per-month scalar** in the Sharpe loss numerator `(port_t − bench_t)`. bench_t is constant across all N stocks in month t → it cannot inject stock-specific future information into the *cross-sectional* attention weights (the gradient w.r.t. cross-sec scores is invariant to a month-constant offset). A shifted month-constant is a benign nuisance on the loss scale, not a stock-level leak.
- Decisively: ALL evaluation (alpha canonical_screen, optimizer walk-forward, forge build_bt_result) uses the **corrected `.cache/benchmark.parquet`** (clean IKS200, post-2026-07-02 bug-fix) with signal-month→realization(t+1) alignment. The alpha agent's look-ahead toggle (lag0 port_t 1.01 vs aligned 1.41) proves alignment does NOT inflate — the wrong (concurrent) bench gives a LOWER t. A look-ahead artifact would inflate the aligned number; it deflates. β_to_benchmark = 0.867 (sane; a mis-lag would give impossible β ~0.08 per [[reference-book-benchmark-alignment-realized-ym]]).
- Training window is strictly `midx < m` (past-only, WIN=96, refit=12). Z-score per-month (not full-sample, C1). No F1 (forward target) in the scoring path (C2 clean). Factor-DB Z_Score_Aligned, no sign-flip (C13). Substrate loaded via monthly factor_db path (C15-compliant).
- **REBUTTAL sustained: no C1/C2/C13/C15 violation reaches the authoritative metric. The training-bench shift is immaterial. PIT = CLEAN.**

## Challenge 4 [Judge-specific] — The 2 audit WARNs (C15 path skip, lookahead self-scan skip): am I waving through a real PIT gap?

**Attack**: forge audit shows WARN on `c15_factor_db_load_path` and `lookahead_detector_self_scan`. Should these block?

**Self-defense**: Both WARNs fire because forge's manifest carries no `factor_engine_path` — forge is a pure integration function consuming a frozen weights.csv; it owns no factor engine to scan. The signal-generation PIT is verified separately at source (Challenge 3). These are structural skips (0 critical, 0 FAIL), not evidence of look-ahead. audit_status=WARNING with critical_fail_count=0 is acceptable for a screen-tier FAIL. Not verdict-blocking, but I log them as a data-lineage completeness note (if this alpha were re-attempted capital-grade, forge should carry the factor_engine_path for full C15 self-scan).

## Challenge 5 — Could I be too harsh? Should this at least go to Governor for book-marginal consideration?

**Attack**: Even a screen-tier alpha with low active-corr could add book-marginal ΔIR. Should I hand to Governor rather than REJECT?

**Self-defense**: measurement-graduation §4 — book-marginal ΔIR≥0.05 admission requires *standalone ADMIT first*. A strategy failing all three HARD gates (PORT_t, OOS, Calmar) never reaches standalone ADMIT; there is no book-marginal path. Optimizer + alpha + forge unanimously route to screen-tier, not Governor. Handing a triple-HARD-fail to Governor would be process theater. REJECT (capital) + screen-route is correct. No Governor hand-off.

---

## Classification summary
| # | Challenge | Class | Verdict impact |
|---|-----------|-------|----------------|
| 1 | rank-IC real, decay structural → pass? | ACCEPT (FAIL stands) | none |
| 2 | wrong-universe artifact? | ACCEPT (FAIL stands) | none |
| 3 | training-bench look-ahead (PIT) | **REBUTTAL sustained** | PIT CLEAN |
| 4 | 2 audit WARNs | ACCEPT (structural, log) | none |
| 5 | Governor book-marginal path? | ACCEPT (no path) | REJECT correct |

## Auto-escalation check (v8.2)
- HIGH self-challenges ≥5? No (5 raised, but none is a HIGH-severity *finding* — 4 ACCEPT-no-impact + 1 REBUTTAL-clean). Not an escalate trigger.
- AX axiom hard FAIL ≥3? No (0).
- PIT C1 hard violation found? No (REBUTTAL sustained clean).
- → **No auto-escalate.** But per alpha agent's own escalation (5 HIGH flags = honest capital-ineligibility), Q-Lead is informed of REJECT-direction with screen-route recommendation (transparency escalate, not concealment).

## Self-rationalization scan
Banned phrases ("영향 미미 / 관행적 / 보수적이면 OK / 대부분 동일") — none used as load-bearing justification. The one soft-adjacent claim ("training-bench shift is benign nuisance") is backed by the month-constant-invariance argument + the deflating look-ahead toggle (quantitative), not by hand-waving.

## AX-008 triangulation (adjudication)
- **Forge (실측)**: PORT_t 2.36, SCREEN_TIER_FAIL, hash PASS, pure_function_violation=FALSE, metric_type=backtested → **PASS (source valid, honest)**.
- **Self-Adversarial (agent challenge notes)**: alpha/risk/optimizer/forge all raised ≥3 self-concerns, all converge SCREEN_TIER_FAIL, no silent override → **PASS**.
- **Architect**: not spawned this WT (screen-tier FAIL, structure not admission-bound). → abstain.
- **2/3 PASS satisfied** (Forge + Self-Adversarial). Judge adjudicates: verdict robust.
