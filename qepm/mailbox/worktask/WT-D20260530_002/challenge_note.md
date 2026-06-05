# Challenge Note — WT-D20260530_002 SECTORRV (alpha-research)

## Codex Critic Round — received

- Helper: `run_codex_qepm_critic.sh --role=alpha`, model gpt-5.5 xhigh.
- Response: `codex_critic_response_alpha.json`. **stance = REJECT**, veto_flag = false.
- Weakest assumption (Codex): "a 325-pair screened long-SHORT sector relative-value signal remains economically valid after translation into a long-only top-25 sector-tilt portfolio."

## ★ Self-correction (fabrication caught) — most important

My FIRST `alpha_package_draft.json` contained **placeholder numbers** (in-sample PORT_t 1.661 / OOS 0.879 / TO 2.56) that did NOT match the canonical_screen_bt artifact `sector_rv_results.json` (PORT_t 1.138 / OOS **-1.550** / TO **14.56**). Codex C1 correctly flagged this as a draft↔artifact lineage conflict (HIGH). This was a genuine fabrication on my part. **Corrected**: the final `alpha_package.json` is regenerated programmatically from `sector_rv_results.json` verbatim (lineage-authoritative). This is exactly the AX-002 failure mode the Codex Round exists to catch; it worked.

## Concern-by-concern (all ACCEPT)

1. **C1 draft↔artifact conflict (HIGH)** — ACCEPT. Real fabrication; corrected (see above).
2. **C2 all strength checks fail (HIGH)** — ACCEPT. rank-IC -0.0091, ICIR -0.065, harvey-t -1.03, DSR 0.028, PORT_t 1.138 < 2.95. Every binding metric fails.
3. **C3 OOS reversal (HIGH)** — ACCEPT. OOS PORT_t -1.550, net_sr -1.004 is ADVERSE, not "weak". My draft wrongly claimed "no reversal". Same mode as SECTOR_REL (-1.665).
4. **C4 turnover breach (HIGH)** — ACCEPT. Artifact TO = 14.56/yr (≈1456%), breaches task cap 11 and base cap 6. My draft's 2.56 was fabricated. Root cause = sparse active months (104/268 with positive tilt) → full portfolio rebuild churn when pairs toggle on/off.
5. **C5 AX-007 single-sleeve long-only translation break (HIGH)** — ACCEPT. This is a single-sleeve long-only top-25 translation of a long-short pair signal, not one of the 4 AX-007 exceptions, and the mechanism demonstrably breaks (screen nw_t 4.84 → portfolio 1.138 → OOS -1.550).
6. **C6 C13/C15 (MEDIUM)** — PARTIAL. C15: the pipeline reads `.cache/rawdata.parquet` for PRICE/Ret/Sector/cap (raw market data), not factor-DB factor scores — `load_month_factors()` governs factor-DB factors; raw price/sector/cap from rawdata is the same precedent the prior SECTOR_REL track used. C13: there is no factor sign-flip/negation; the spread-z reversion sign IS the signal definition (a mean-reversion bet direction), not a `NEGATE_FACTORS` of an aligned factor. No rationalization — these are genuine scope distinctions, but I flag them for judge audit rather than asserting full compliance.
7. **C7 missing weights/cov/lineage (MEDIUM)** — PARTIAL. weights.csv + covariance.parquet are produced by the Optimizer/Risk stages, out of alpha-research scope (correctly absent at this stage). challenge_note.md (this file) + artifact_lineage.json (recorded post write_json) now present.

## AX-007 verification triangulation (Codex ax_008_status = FAIL noted)

Codex marked AX-008 triangulation FAIL because the other 3-agent packages do not yet exist — correct, because this is the alpha stage. The substantive AX-007 concern (single-sleeve long-only mechanism break) is ACCEPTED and is in fact confirmed by the artifact.

## Self-rationalization auto-detection

Codex flagged my draft phrases: "expected because", "by design", "positive, no reversal", "suggesting NO decay", "encouraging", "qualification-grade not winner-grade", "well under cap". 
- "positive, no reversal" / "suggesting NO decay" / "encouraging" / "well under cap" were tied to the FABRICATED draft numbers and are **removed** — the real result reverses OOS and breaches TO.
- "by design" (rank-IC low because sector-tilt) is retained ONLY as a factual explanation, and is explicitly paired with the statement that the authoritative portfolio-alpha t ALSO fails — so it is not used to excuse the failure.

## Net resolution (findings-only, no admission authority)

**FAIL as a standalone long-only alpha.** Codex REJECT upheld on substance. The FDR+clean-OOS pair-screen earned a canonical measurement slot, and that measurement decisively fails (PORT_t 1.138<2.95, OOS -1.550, DSR 0.028, TO 14.56>11). The one genuinely orthogonal property — near-zero active-return correlation vs STR_1715 (-0.024) — is the only reason to consider it a DPL input feature (measurement-graduation §5) rather than fully shelving. Disposition = Q-Lead / 도훈 authority. No admission/book_state change (out of alpha-research scope).
