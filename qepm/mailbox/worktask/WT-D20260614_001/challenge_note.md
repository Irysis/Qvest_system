# Challenge Note — WT-D20260614_001 VAL_DIVERSIFIER (alpha-research)

**Codex Critic Round** (GPT-5.5, xhigh) — stance = **REVISE**, veto_flag = false, AX-008 = FAIL (triangulation incomplete at draft stage).
**Resolution**: 4 of 7 concerns ACCEPTED with new measurement (RF-A2, RF-A4, date-realignment, n25 reframe). 3 PARTIAL/REBUTTAL with explicit grounds. **Package reframed: non-graduating DIVERSIFIER FEATURE, not a standalone alpha candidate.** Charter §8 No Silent Override satisfied — no concern dismissed without evidence.

## Self-rationalization audit (protocol mandate)
Codex flagged 7 rationalization phrases in the draft. Re-reviewed each:
- "direction (low cor) robust" → **WITHDRAWN**. New realigned measurement shows active_cor 0.109→0.269; my misaligned figure overstated diversification. Codex C2 correct.
- "This is FAVORABLE … BETTER" → **SOFTENED** to "moderate partial diversification" (active_cor 0.27, not near-orthogonal).
- "DSR not the binding gate" → **RETAINED with grounds** (measurement-graduation §3 2026-06-10: single de-contam recipe = chain/single, DSR advisory). But added multiple-testing caveat for upstream 409-cluster selection (C: PARTIAL).
- "single de-contaminated recipe; no factor fishing" → **PARTIAL** — the *recipe* is single, but it was SELECTED from a 409-batch cluster; effective multiple-testing exposure acknowledged (see C-multitest).
- "MDD alone is not auto-hard-fail" → **RETAINED** (measurement-graduation §3 2026-06-13 confirmed mandate, verbatim rule). Not rationalization — cited rule.
- "Value enters as a DIVERSIFIER FEATURE" → **RETAINED** (this is the package's correct framing per research_philosophy ④ DPL-feature; standalone fails, confirmed).
- "KR: value risk premium persists" → **RETAINED but qualified** — RF-A2/subperiod show V03_CFP/V01_BM persist (t=5.79/3.46), but recent decay is real (C5 ACCEPT).

## Concern resolutions

### C1 [HIGH] — IC/portfolio-alpha below standalone thresholds → **ACCEPT (already self-flagged)**
rank_ic 0.0269<0.04, ICIR 0.178<0.20, PORT_t 0.212(n30)/0.453(n25)<<2.95. Draft already flagged this (CF-PORTALPHA-LOW). Agreement: this is a low-confidence diversifier input, NOT a graduating alpha. No dispute. Package status set to NON_GRADUATING_DIVERSIFIER.

### C2 [HIGH] — diversifier claim not triangulated, alignment mismatch → **ACCEPT + CORRECTED**
Recomputed incumbent correlation with proper REALIZATION-MONTH alignment (sleeve fwd-return month t+1 ↔ incumbent monthly_ret dated first-of-(t+1)). Results (`diversifier_realign.json`, 219m):
- return_cor total: −0.030 (misaligned) → **0.488** (aligned)
- active_cor vs BM: +0.109 (misaligned) → **0.269** (aligned)
- rolling 36m active_cor: median 0.242, range [−0.34, 0.74]
My draft's misaligned figure was wrong by a half-month lag. Corrected: value-4 is a **moderate partial diversifier** (active_cor 0.27), weaker than carried "0.713 unique" claim. **Risk-research remains authoritative** for book-marginal ΔIR with proper covariance — this is an alpha-stage Pearson diagnostic only. Diversifier claim now triangulated and downgraded honestly.

### C3 [MEDIUM] — RF-A2 unresolved (composite vs best single) → **ACCEPT — composite is WORSE**
Ran single-factor baselines, identical PIT/cost/universe (`codex_rebuttal_diags.json`):
| signal | rank_ic | ICIR | Harvey-t |
|---|---|---|---|
| V03_CFP | 0.0344 | **0.340** | **5.79** |
| V01_BM | 0.0311 | 0.209 | 3.46 |
| V10_FCF_Yield | 0.0181 | 0.220 | 3.68 |
| V11_Shareholder_Yield | 0.0172 | 0.111 | 1.75 |
| **EW composite (4)** | 0.0269 | 0.178 | 3.10 |
**The EW-4 composite UNDERPERFORMS its two strongest single proxies (V03_CFP, V01_BM).** Equal-weighting drags the strong CFP/BM signals down with the weak V10/V11. RF-A2 FAILS for this recipe. Honest implication: the specific "value-4 EW" recipe is suboptimal; V03_CFP/V01_BM-weighted (or CFP-led) would be stronger. Forwarded to optimizer/risk as a re-weighting opportunity (NOT re-specified here — alpha role honors the requested recipe as the measured object, but flags the dominance).

### C4 [MEDIUM] — RF-A4 untested (sector/size-neutral IC) → **ACCEPT — sector retention <50%**
Neutralized-IC measured (`codex_rebuttal_diags.json`):
| neutralization | rank_ic | retention vs raw |
|---|---|---|
| raw | 0.0269 | 100% |
| sector-neutral | 0.0113 | **42%** |
| size-neutral | 0.0174 | 65% |
| sector+size | 0.0182 | 68% |
**Sector-neutral retention 42% < 50% threshold (RF-A4 fires).** A large part of the raw value IC is a SECTOR bet (KR value loads on cyclicals/financials). Size-neutral retains 65% (acceptable). Implication: risk-research must treat sector exposure as a primary risk axis; the "value alpha" is partly a sector tilt. Reported honestly.

### C5 [MEDIUM] — recent decay understated by sign-only stability → **ACCEPT**
subperiod_stability=1.0 is sign-only (all 3 periods positive IC). Magnitude decay is real: p1 0.0325 / p2 0.0321 / p3(2020-26) **0.0139**, recent ICIR 0.092. Draft CF-IC-DECAY already noted this; agreement. Renamed metric to `subperiod_sign_stability` to avoid overstatement; added `recent_ic_attenuation_ratio = 0.43` (p3/p1).

### C6 [HIGH] — AX-007 exception not satisfied; n30 > max_names 25 → **PARTIAL ACCEPT**
- **n30 > 25**: ACCEPT. Reframed: n30 is a DIAGNOSTIC screen only; **n25 (production-compliant) is now the PRIMARY reported screen** (PORT_t 0.453, IR 0.100, TO 5.00x). n30 retained as secondary diagnostic only.
- **AX-007 single-sleeve-top20 mechanism**: ACCEPT that standalone single-sleeve value-N long-only fails (AX-007 + this measurement). **REBUTTAL on framing**: this package does NOT claim standalone graduation. It is an explicit DIVERSIFIER FEATURE input to a multi-sleeve book (incumbent STR_1715 + value tilt) and/or DPL feature (research_philosophy ④). AX-007 exception "multi-sleeve" applies at the BOOK level (risk/governor), not the alpha-feature level. Alpha role delivers the feature + honest standalone-fail label; book construction is downstream. No silent override — standalone failure is stated.

### C7 [MEDIUM] — triangulation artifacts absent (lineage, risk/opt packages) → **PARTIAL ACCEPT (stage-appropriate)**
risk_package/optimization_package/weights.csv/covariance.parquet are DOWNSTREAM agents' outputs — absent at alpha draft stage BY DESIGN (Q-Lead spawns risk next). artifact_lineage.json + challenge_note: **NOW produced** (this file + record_package_lineage on final). AX-008 triangulation (Forge+Codex+Architect 2/3) completes at judge stage, not alpha stage. The Codex source of the triangle IS this round. Accepted: lineage produced before final handoff.

### C-multitest [from unresolved_disputes] — upstream 409-cluster selection multiple-testing → **PARTIAL ACCEPT**
The *recipe* is single (candidates_tried=1 at alpha stage), BUT it was SELECTED as "the unique diversifier" from a 409-candidate batch. That is effective multiple-testing exposure at the meta-level. Honest disclosure added to `method_shopping_log.upstream_selection_note`: this hypothesis survived a 409-wide screen; DSR/Harvey hurdle should be read with that breadth in mind. The carried baseline that drove selection was itself contaminated (CF-PROVENANCE-1), so the selection signal is doubly suspect. This STRENGTHENS the case for treating value-4 as feature-not-graduate.

## Net effect on package
- status: ALPHA_DRAFT → **ALPHA_FINAL (NON_GRADUATING_DIVERSIFIER_FEATURE)**
- Diversifier active_cor: 0.109 → **0.269** (corrected, weaker than claimed)
- RF-A2: composite worse than V03_CFP/V01_BM single (new flag CF-COMPOSITE-SUBOPTIMAL)
- RF-A4: sector-neutral IC retention 42%<50% (new flag CF-SECTOR-TILT)
- Primary screen: n30 → **n25** (production-compliant)
- 4 new measurements added; 2 new HIGH-relevance flags; no concern dismissed without evidence.

**Q-Lead escalation check**: HIGH concerns = 3 (C1/C2/C6) < 5 threshold; AX hard FAIL = 1 (AX-007, but exception-applicable at book level) < 3; no C1 lockbox/lookahead violation (PIT C1-C15 all PASS per Codex). → **No auto-escalate triggered.** Codex stance=REVISE (not REJECT) + agent addressed (not ALL-rebuttal). Proceed to final with corrections.
