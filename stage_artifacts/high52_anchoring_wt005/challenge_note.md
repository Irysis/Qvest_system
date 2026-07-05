# Self-Adversarial Challenge — WT-D20260706_005 (52wk-high anchoring, George-Hwang 2004)
Agent: Alpha Research (QEPM). AX-008 self-adversarial (Opus 4.8 native, Codex Round removed v8.2).
Verdict pre-challenge: **VALIDATED_NEGATIVE** — does NOT escape the cap-tier trap in mega.
Devil's-advocate concerns raised: 5. Classification: ACCEPT / PARTIAL / REBUTTAL.

---
## C1 — "Is the mega-tier a false negative from tiny sample (only 10 names → median split = 5 vs 5)?"
**Concern**: mega long-short uses only ~10 stocks/month, split 5-hi vs 5-lo. Noise could mask a real edge.
**Classification: REBUTTAL (quantitative).**
- Same 10-name split gave the parallel session mom/rev/eff a mega LS t=0.59; my pr52 mega LS t_full=0.684, post2017=0.450 — statistically indistinguishable from *their* dead result, i.e. the low-power split is not hiding a pr52-specific edge; it produces the SAME dead reading as the known-dead signals.
- Independent corroboration via a *different* estimator: mega top-5 long-only vs benchmark PORT_t_full = −1.058 (post2017 −0.433, IR −0.222) — a non-spread construction, still negative. Two independent mega constructions agree: no edge.
- Only post2020 mega LS reaches t=1.22 (still <2, and that window = C3 concern below). So: low power is real, but the reading is consistently ≤0.7t across full/post2017, converging with the known signal-dead benchmark. **No escape.**

## C2 — "Is pr52 just repackaged 12-1 momentum (which is already dead in KR)?"
**Concern**: George-Hwang claims 52wk-high subsumes momentum; if in KR it IS momentum, the death is not news.
**Classification: PARTIAL.**
- Measured: mean cross-sectional Spearman(pr52, mom12-1) = **0.427** — moderate, NOT a repackaging (that would be >0.8). So pr52 is a *genuinely distinct* price-level anchoring signal, mechanistically separate from return-continuation. The hypothesis' distinctness claim HOLDS.
- BUT distinctness does not rescue payoff: distinct-and-dead (canonical PORT_t −0.041, oos −1.13) is still dead. The value of C2 is diagnostic, not exculpatory: this is a *new, independent* falsification of an anchoring mechanism, not a re-test of momentum. Recorded as such (adds information; does not change verdict).

## C3 — "Is any positive tier reading a 2023-26 Hynix-AI-run artifact?"
**Concern**: today's memory confirms a real 2025-26 mega-cap semiconductor concentration regime; a near-high signal could mechanically ride Samsung/Hynix.
**Classification: REBUTTAL (quantitative) — and it CUTS AGAINST any escape claim.**
- pre2020 vs post2020 split done explicitly. mega LS: pre2020 −0.089 → post2020 +1.22; mid: pre2020 **−2.413** → post2020 +1.99; small: pre2020 +0.14 → post2020 +1.85. The *only* place pr52 shows life is post2020, exactly the AI-run window — i.e. the modest post2020 uptick IS the artifact the concern warns about, not a durable anchoring edge. Even so it never clears t=2.
- Decisive: the deployable long-only book that would harvest a real mega edge (mega top-5 long-only) is post2017 −0.433 and full −1.058 — the semiconductor run does NOT translate into long-only book alpha. So the concern is validated (any "life" is regime-local) AND it does not produce an escape.

## C4 — "Lookahead in the 252d rolling High (window includes formation date)?"
**Concern**: rolling252-max(High) includes the formation month-end day's own High; forward return then measured next month.
**Classification: REBUTTAL (construction + quantitative).**
- Construction: window ends AT formation date t (inclusive of t's own High/Close — all observable at t's close), forward return is ym_next. This is exactly George-Hwang's PIT formation (C1 rolling per date, C2 no same-day forward use). No return info from the holding month enters the score.
- Empirical guard: built a strict lag1 variant (price AND high both shifted to the prior trading day). lag1 PORT_t_full = 0.391 vs base −0.041; post2017 −1.049 vs −1.036. lag1 is if anything *slightly stronger* full-period — a lookahead leak would make the base version stronger than lag1, not weaker. **No leak.** Liquidity filter uses t-1 ADV (C10). ✔

## C5 — "Is it liquid / could top-decile be illiquid microcaps (RF-A5)?"
**Concern**: near-high names could cluster in illiquid small-caps.
**Classification: REBUTTAL (quantitative).**
- Universe is K200∪KQ150 members with t-1 20d ADV ≥ 2e8 KRW enforced pre-signal (median 335 eligible stocks/month). Turnover_annual = 14.55 (elevated but the signal churns among liquid members, not a liquidity artifact). Ex-mega re-test (removes top-10, keeps mid+small liquid members) PORT_t_full 0.180 / post2017 −1.017 — the death is not a mega-vs-micro composition artifact; it is signal-universal across the liquid universe.

---
## Self-rationalization auto-detection
Scanned my own reasoning for "미미/관행적/실무적/보수적이면 OK/대부분 결과 동일" — none used to wave away a violation. The one "same as parallel session" comparison (C1) is a *quantitative convergence argument* (my t≈0.68 vs their t≈0.59 on identical construction), not a hand-wave. ✔

## Escalation check
- HIGH severity concerns: 0 (all rebutted/partial with data). AX axiom hard FAIL: 0. PIT C1 lockbox/lookahead: none (C4 rebutted). → **No Q-Lead auto-escalate trigger.**

## Post-challenge verdict (UNCHANGED)
**VALIDATED_NEGATIVE.** 52wk-high anchoring is (a) a genuinely distinct signal (xsec corr 0.43 vs momentum), (b) PIT-clean (lag1 confirms), (c) but signal-dead as a long-only book (canonical PORT_t −0.04, oos_retention −1.13 HARD FAIL, post2017 −1.04). **It does NOT escape the cap-tier trap in mega** (mega LS t_full 0.68 / post2017 0.45 ≈ the parallel session's known-dead 0.59; mega top-5 long-only −1.06). This CONFIRMS the parallel session's finding is signal-universal in mega, now extended to a distinct anchoring family. Screen-route: DPL_FEATURE at most (weak, mostly regime-local post2020). No graduation candidacy.
