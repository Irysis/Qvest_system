# Challenge Note — WT-D20260529_002 Track BAB (alpha-research)

**Codex stance**: REJECT (GPT-5.5 xhigh)
**Agent stance**: DROP (independent, pre-Codex)
**Convergence**: Codex REJECT and agent DROP AGREE on the disposition. No verdict-level dispute. Codex's C1/C2/C3 restate the agent's own rationale; C4/C5/C6 are process/audit items addressed below.
**weakest_assumption (Codex)**: "realized_beta near zero is a sufficient proxy for useful return orthogonality in a KR long-only BAB sleeve." — AGENT ACCEPTS. This is precisely the lesson the draft itself documents (return_cor 0.775 despite realized_beta -0.04). Codex correctly names it the weakest assumption; the data refutes it, which is why the verdict is DROP, not admit.

---

## Concern-by-concern classification (Charter §8 No Silent Override)

### C1 [HIGH] — Core alpha gates fail
> rank_ic 0.0137 < 0.04, ICIR 0.132 < 0.20, Harvey rankIC t 2.15 < 3.0, portfolio-α t -2.02, DSR 0.0004 < 0.50, monotonicity -0.16.

**ACCEPT.** Verbatim agreement with the agent's diagnostics. These are the measured in-harness values (build_bab_alpha.R, 238 lockbox months). They are the *basis* of the DROP verdict, not a rebuttable claim. No self-rationalization: the gates fail decisively and the package final_stance is already DROP.

### C2 [HIGH] — Mechanism translation fails (premium only in non-deployable LS)
> Positive FP-style BAB appears only in gross long-short, non-deployable under KR no-short; selected long-only net_SR -0.51.

**ACCEPT.** This is the agent's `long_short_fp_construction_check` finding stated back. Evidence:
- FP-style β-neutral LS: gross SR 0.462, raw t 2.059, long-leg β 0.42 / short-leg β 1.64 (238 mo).
- Mandate `no_short_legal_kr=true` → short leg non-deployable. Net of KR short-borrow + 15bps + high-β-leg turnover, gross SR 0.46 collapses.
- Long-only deployable leg: portfolio-α t -2.02, net_SR -0.51.
- **L-code anchor**: AX-005 v1.2 (KR low-vol/defense single-sleeve long-only structurally fails; EXCLUSION necessary not sufficient — L-136/140/165/166) + AX-007 (single-sleeve long-only top20 mechanism break). The premium lives in the SHORT leg (avoid high-β), not the deployable long leg.
- **Academic anchor**: PBFJ 2022 attributes the KR BAB premium to IVOL+MAX (lottery demand), not pure leverage — i.e. the deployable long-only leg is not where the leverage-constraint premium resides.

### C3 [HIGH] — realized_beta≈0 does not establish book diversification
> realized_beta -0.043 does not prevent return_cor_vs_STR_1715 0.775; signal-orthogonality + β-neutrality ≠ diversification.

**ACCEPT — this is the headline finding of the track.** The agent explicitly designed the measurement to separate signal-cor from return-cor (FLOW lesson: signal-cor -0.07 yet return-cor 0.71, β 1.15). BAB result: signal-cor 0.069 (orthogonal) BUT return-cor 0.775 (highly correlated) at realized_beta -0.04. Mechanism: two long-only KR-equity baskets share size/sector/idiosyncratic common factors beyond pure market beta, so β-neutrality does NOT buy return-orthogonality. This is quantitative confirmation, not assumption. Disposition: DROP (no diversification value).

### C4 [HIGH] — PIT/charter cleanliness (C10 / C13 / C15)
**PARTIAL.** Three sub-claims, each addressed with explicit evidence rather than rationalization:

- **C10 same-day liquidity** — REBUTTAL with evidence. Liquidity filter uses `tv20 = frollmean(tv, 20, align="right")` evaluated at month-end m, i.e. the trailing-20-day average trading value KNOWN at decision time m. This is t-trailing (past window ending at m), the ADV an investor observes when forming the signal at m — not a t+1 forward value. Sibling tracks (RESID_MOM line 36-37, identical pattern) use the same construction. C10 prohibits using *future/contemporaneous-unknowable* volume; a trailing-20d ADV at the rebalance date is standard PIT. **No C10 violation.** Evidence: build_bab_alpha.R L40-41, L93.
  - Self-check for rationalization: I am NOT claiming "영향 미미"/"관행적". I am asserting the window is strictly trailing-and-known. If Codex means "the 20d window includes day m's own volume" — day m's traded volume IS observable at month-end close m (it is realized intraday before the close-based decision). Acceptable. PARTIAL only because I add an explicit `liquidity_pit` assertion field rather than dispute entirely.

- **C13 Z_Score_Aligned / NEGATE** — REBUTTAL with evidence. C13 forbids `NEGATE_FACTORS`/`FLIP_SIGN` applied to **Factor DB pre-aligned columns** (you must use the DB's Z_Score_Aligned, not flip a DB factor's sign). My `beta` is self-computed from RAWDATA via rolling OLS — it is NOT a Factor DB column and has no canonical Z_Score_Aligned. `ALPHA = -z(beta)` is the *definitional direction* of the BAB hypothesis (low beta = high expected alpha, Frazzini-Pedersen), not a post-hoc sign-flip of a pre-aligned DB factor. **C13 does not apply to self-computed signals.** L-code anchor: C13 scope is Factor DB (`.claude/rules/factor-db.md`: "Z_Score_Aligned only" applies to DB factor access). PARTIAL: I add explicit `signal_direction_rationale` to pit_assertions documenting the definitional (not exploratory sign-search) basis.

- **C15 RAWDATA carve-out** — REBUTTAL with evidence. C15 governs **Factor DB parquet** (`load_month_factors()` mandatory). I read `.cache/RAWDATA.parquet` (price/volume), which is the documented RAWDATA source — alpha_research_init.md <tooling> explicitly lists `load_rawdata(use_cache=TRUE)` / RAWDATA as a permitted alpha data source distinct from Factor DB. All 7 sibling tracks (RESID_MOM/REV/52WHIGH/etc.) read RAWDATA directly. **C15 does not apply to RAWDATA.** No DB factor was accessed. PARTIAL: documented in pit_assertions.

### C5 [MEDIUM] — Missing verification artifacts / path inconsistency
**ACCEPT (process).** Actioned:
- This `challenge_note_BAB.md` now exists.
- `artifact_lineage.json` BAB entry appended (record_package_lineage).
- weights.csv / covariance.parquet / risk / optimization packages: **correctly absent** — those are Risk/Optimizer/Forge stage outputs. An alpha-research agent producing them would VIOLATE role boundary (agent_role_guard Hook, strict_prohibitions §1-3). Their absence is correct cooperative behavior, not a defect.
- Path note: the prompt referenced `stage_artifacts/WT_WT_D20260529_002_BAB` (which I created) and `qepm/mailbox/.../alpha_package_BAB.json`. The `qepm/stage_artifacts/...` variant in Codex's note does not exist by design; canonical stage path is `stage_artifacts/WT_WT_D20260529_002_BAB` per sibling convention. Documented.

### C6 [MEDIUM] — Academic support page-level / independent KR replication
**PARTIAL.** Frazzini-Pedersen 2014 JFE (BAB factor, leverage-constraint mechanism, Prop. 1-2 + Table III SMB-BAB) and PBFJ 2022 (Korea BAB positive premium, driver decomposition into IVOL+MAX) are cited at mechanism level in hypothesis_description. The verdict does NOT rest on academic existence (Charter principle 4: paper is a starting point, not an approval) — it rests on the in-harness 238-month measurement, which is the authoritative source. Codex's call for an *independent* KR replication is noted as a strengthening suggestion; however for a DROP verdict the in-harness hard-fail is sufficient and dispositive. Independent replication would only matter for an admit decision (not applicable here). PARTIAL: I acknowledge the citation could be page-level but the disposition is unaffected.

---

## Self-rationalization audit (mandatory)
grep of {미미, 관행적, 실무적, 보수적이면, 대부분 결과 동일} against my REBUTTAL text: the phrase "관행" appears only inside a quoted disclaimer ("I am NOT claiming 관행적"). No affirmative use of rationalization language. REBUTTALs (C4) are backed by file:line evidence + scope citation, not hand-waving.

## Escalation check
- HIGH severity concerns ≥ 5? Codex HIGH count = 4 (C1-C4). Below threshold of 5.
- AX axiom hard FAIL ≥ 3? No hard axiom FAIL — AX-005/AX-007 are CONFIRMED-as-expected (this is exactly the documented KR failure pattern), not violated by the agent.
- PIT C1 lockbox/lookahead violation? No (lockbox 2023-12-22 strict, forward label convention compliant).
- Codex REJECT + agent rebuttal ALL? No — agent ACCEPTS C1/C2/C3/C5 and only PARTIAL-rebuts C4/C6 on scope. Verdict CONVERGES (DROP=REJECT).
→ **No Q-Lead escalation required.** Disposition is consensual DROP.

## Final disposition
**DROP.** Both Codex (REJECT) and agent (DROP) agree the BAB long-only sleeve must not be admitted. Spec finalized as `alpha_package_BAB.json` with final_stance=DROP. Reuse value: low-beta as a RISK overlay / sector-neutralization input for risk-research, NOT a standalone alpha sleeve.
