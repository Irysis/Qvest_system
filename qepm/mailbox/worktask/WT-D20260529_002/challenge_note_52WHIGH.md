# Challenge Note — WT-D20260529_002 Track 52WHIGH (alpha-research)

**Codex stance**: REJECT (veto_flag set). 7 concerns (4 HIGH / 3 MEDIUM).
**Agent verdict**: DROP (converges with Codex's "DROP directionally right").
**Decision protocol**: Codex agreement on non-deployability + my independent empirical hard-fail. No Q-Lead escalate trigger met for *signal admission* (we are NOT admitting). However Codex C2 (PIT) demanded a measurement-validity rebuild — performed (see C2).

Self-rationalization grep on 52WHIGH files: NO hits (미미/관행적/실무적/보수적이면/대부분/이미반영 absent). Codex's flagged "immaterial" was in sibling PEAD files, not 52WHIGH.

---

## C1 [HIGH] — All usable gates fail; turnover note
**Classification: ACCEPT (fully).** This IS the verdict. rank_IC=-0.0008, ICIR=-0.006, rankIC Harvey-t=-0.089, portfolio-alpha t=0.243, DSR=0.270, monotonicity=-0.236. All below gate. → DROP. (Note: Codex misread turnover — turnover_yr=6.03 is annual one-way *count* ≈ 600%/yr; this is a borderline implementation flag but moot since the alpha is dropped, not deployed.)

## C2 [HIGH] — Same-day Close_t/hi252/tv20/in_univ vs "t-1" claim (PIT)
**Classification: PARTIAL ACCEPT + REBUTTAL with new evidence.**
- ACCEPT: package text said "t-1 close" imprecisely; the measurement used the standard monthly convention (signal as-of month-end close t, forward return t→t+1m). Corrected wording to "month-end close t, trailing features as-of t".
- REBUTTAL (empirical, Codex explicitly requested this rebuild): I rebuilt the panel with ALL signal inputs strictly shifted to prior trading day t-1 (`pit_t1_strict.R`): close_{t-1}, high_{t-1}, liquidity_{t-1}, universe_{t-1}; position at t, return t→t+1m.
  - **Result: lockbox rank_IC = +0.00367, Harvey-t = 0.40, n=226** — still ~0, still << gate.
  - The null is ROBUST to PIT convention. The same-day convention did NOT manufacture signal; if anything strict t-1 nudges rank_IC from -0.0008 to +0.0037, both economically zero. Quant data: |rank_IC| < 0.004 either way.
- The standard monthly harness (Close_t + trailing-as-of-t, identical to REV/all Cycle 3 siblings, build_rev_alpha.R L59-72) is the project convention; C2 is a valid wording fix, not a result-invalidating lookahead. PIT C2 substantively SATISFIED (proven, not asserted).

## C3 [HIGH] — C13/C15 lineage (Z_Score_Aligned, load_month_factors carve-out)
**Classification: PARTIAL ACCEPT.**
- 52WHIGH is a NEW price-derived factor not in Factor DB (proximity = Close/52w-high). Direct RAWDATA.parquet read is the documented carve-out path for new price-only factors (alpha_research_init.md §Step 3 "신규 팩터: 자체 계산", and L-164 v1.1 carve-out for price-derived signals). C15's `load_month_factors()` mandate is for the 288 existing DB factors, not raw price.
- C13 (Z_Score_Aligned): direction attestation = signal sign is explicit and documented (high proximity → long, per George-Hwang). For a DROP this is moot; for any future deployment a Z_Score_Aligned attestation would be added. PARTIAL — wording strengthened, but no deployment so no hard C13 artifact required.

## C4 [HIGH] — Not orthogonal enough for 5th source (|cor|>0.30)
**Classification: ACCEPT (fully) — this is a second, independent reason for DROP.**
cor_vs_FLOW=-0.379, cor_vs_REV=-0.395, cor_vs_raw_past1m=+0.362 all exceed the 0.30 mandate. The signal is a thinly-disguised price-level/momentum proxy (+0.36 vs raw 1M return), not a clean orthogonal anchoring channel. Even if it had signal, it would fail the diversification mandate. Recorded in alpha_validation.orthogonality.mandate_passed=false.

## C5 [MEDIUM] — Multiple-testing understated (n_trials=3)
**Classification: ACCEPT.** DSR already fails at n_trials=3 (0.270 < 0.5). Adding direction-inversion + raw/sector-neutral choice + Cycle 3 sibling search budget only pushes DSR LOWER. Conclusion (DROP) is monotone in the right direction; no re-test changes it. Noted as conservative-floor: true DSR ≤ 0.270.

## C6 [MEDIUM] — AX-008 / No-Silent-Override artifacts missing for 52WHIGH
**Classification: ACCEPT.** This challenge_note_52WHIGH.md (now written) + 52WHIGH artifact_lineage entry (written at finalize) close the gap. weights.csv/covariance.parquet/risk/optimization are correctly ABSENT — alpha-research role boundary forbids them (agent_role_guard), and a DROP never advances to Risk/Optimizer. Their absence is COMPLIANT, not a gap.

## C7 [MEDIUM] — KR mechanism citation too thin for a negative finding
**Classification: PARTIAL ACCEPT.** Added L-code tie: the KR retail-driven anomaly-reversal pattern is documented in memory `learning_kr_lottery_anomaly_reversal.md` (Boyer-Mitton 2010 / Bali 2011 KR mechanism reversal). George-Hwang (2004 JF) and Grinblatt-Han (2005 JFE) are the source theory; the KR null is consistent with the same retail-driven reversal family. Page-level cites deferred (negative finding — not admitting a claim, reporting a non-replication per AX-000).

---

## Verification Triangulation (AX-008)
- Forge: n/a (no backtest advance — DROP).
- Codex: REJECT, but "DROP directionally right" (agree on outcome).
- Agent (independent): DROP on rank_IC≈0 + portfolio-t 0.24 + ortho-fail + PIT-robust null.
- 2/2 available sources agree the signal is non-deployable. Outcome = DROP (uncontested).

## Net resolution
Codex REJECT does not require rebuttal-to-admit because **we are not admitting** — agent and Codex agree the artifact must not advance. Codex's procedural concerns (C2/C3/C6/C7) are accepted/partially-accepted and remediated (PIT t-1 rebuild proves null robustness; lineage+challenge_note written; role-boundary absences clarified). The DROP verdict stands, now audit-clean.
