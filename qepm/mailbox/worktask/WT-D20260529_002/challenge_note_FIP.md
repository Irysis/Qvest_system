# Challenge Note — WT-D20260529_002 Track FIP (Frog-in-the-Pan / Information Discreteness)

**Agent**: alpha-research | **Codex stance**: REJECT (veto=false) | **Agent stance**: DROP_as_standalone
**Concord**: Codex REJECT + agent DROP — full agreement on non-deployability. Codex critique is *stricter on audit-cleanliness* of the negative finding, not on direction.
**Date**: 2026-05-29

## Self-rationalization auto-check
grep for {미미, 관행적, 보수적이면 OK, 대부분 결과 동일, 실무적, near-zero market-neutral} on final package + this note → CLEAN (stale "near-zero" note removed after beta correction). No rationalization tokens.

---

## Concern dispositions

### C1 — All alpha gates fail (HIGH) → **ACCEPT (concord)**
rank_IC=0.0018<0.04, ICIR=0.0156<0.20, harvey_t_rankIC=0.23<3.0, portfolio_t=0.93<3.0, subperiod_stability=0.33<0.50, monotonicity=0.10<0.80, honest DSR(8 trials)=0.31<0.50.
This IS my DROP basis. No dispute. The hypothesis is empirically falsified in KR.

### C2 — Core FIP premise fails in KR (HIGH) → **ACCEPT (concord)**
`ic_improve_vs_vanilla = -0.0007` (NEGATIVE): ID/FIP refinement *destroys* alpha vs vanilla momentum. Robustness grid (12M & 6M × {refine, pure-continuous, vanilla}):
- vanilla_mom_12m t_port=1.48 / netSR=0.364 **>** fip_refine_12m t_port=0.96 / netSR=0.235
- fip_pure_continuous NEGATIVE (12m t_port=-0.51 ; 6m t_port=-1.73) — DGW2014 "continuous info → stronger momentum" premise does NOT hold in KR; if anything low-ID/continuous names underperform.
Empirical refutation, accepted. (Cite: DGW2014 RFS US result non-replication; consistent with KR momentum fragility — REV track same WT, rank_ic~0.027 also failed.)

### C3 — AX-007 not satisfied; cannibalization not 5th source (HIGH) → **ACCEPT (concord)**
- multi_sleeve=false, long_only_top20 → AX-007 single-sleeve long-only mechanism-break applies (no exception implemented).
- **realized_beta = 1.0847** (full market exposure — NOT neutral). The earlier draft value -0.0596 was a 1-month formation/holding misalignment artifact (regressed holding-month return on formation-month K200); corrected to 1.08, R²=0.46, n=214. This is the expected beta for a top20 long-only equity sleeve.
- **return_cor_vs_str1715 = 0.7559** (HIGH) — exactly the FLOW lesson: modest signal-cor (0.34) does NOT imply return-orthogonality. FIP cannibalizes STR_1715, not diversifies.
No favorable orthogonality dimension survives. Accepted as core DROP reason.

### C4 — PIT C10/C13/C15 process compliance (MEDIUM) → **PARTIAL (C10 remediated; C13/C15 labeled)**
- **C10** (same-day tv20/universe) → **REMEDIATED**: strict t-1 re-audit (tv20 + K200/KQ150 membership lagged 1 trading day, t-1 liquidity filter) → rank_ic=0.0022, t_rankIC=0.29, **t_port=1.06**, netSR=0.263. Results essentially unchanged → same-day filter was NOT masking hidden alpha. DROP robust. (artifact: `fip_pit_strict_results.rds`, block `diagnostics.pit_strict_t1_lag`.)
- **C13/C15** → **REBUTTAL (labeled)**: FIP is a research-only price-derived NEGATIVE finding, not a registered Factor DB production factor. Signal = trailing daily returns/signs (price-path), cross-sectionally z-scored per sig_date (rolling cross-section, C1-clean; no full-sample stat). C13 Z_Score_Aligned applies to Factor DB proxies via NEGATE/FLIP; a newly-designed price-path signal with attested direction (high momentum_z × continuity → long) is not a DB-factor sign-flip. C15 load_month_factors() carve-out N/A — mirrors REV track precedent in this same WT (same RAWDATA price-path approach, accepted as research negative). For a DROP this is not promoted to production, so production-factor compliance is out of scope. Grace per research_philosophy (Phase-gated warn).

### C5 — FIP challenge_note / lineage / stale fip_diagnostics.json (MEDIUM) → **ACCEPT (remediated)**
- challenge_note: THIS file.
- fip_diagnostics.json: **synced** (realized_beta -0.0596 → 1.0847, return_cor synced). Was stale because beta-fix patched fip_results.rds before regen; now regenerated.
- artifact_lineage.json: FIP entry appended post-final-emission (record_package_lineage, correct order per L-194).

### C6 — Missing weights.csv / covariance.parquet / WT-level verification artifacts (MEDIUM) → **REBUTTAL (role boundary)**
weights.csv = Optimizer role; covariance.parquet = Risk role. Alpha agent is **prohibited** from producing these (agent_role_guard Hook + init §strict_prohibitions 1-2). Their absence at the Alpha stage is correct role boundary, not a gap. For a DROP alpha there is no downstream Risk/Optimizer stage. (Codex `qepm/stage_artifacts/WT_WT-D20260529_002` path mismatch: canonical stage dir is `stage_artifacts/WT_WT_D20260529_002_FIP` — verified present, 244 sig_dates, no future dates, RF-A7 false.)

### C7 — Academic support not page-level (LOW) → **PARTIAL**
DGW2014 (Da-Gurun-Warachka 2014 RFS "Frog in the Pan: Continuous Information and Momentum") + Jegadeesh-Titman 1993 JF + Hirshleifer-Lim-Teoh 2011 JF named. Per Charter §4 "papers are starting point, not approval" — the *KR empirical test is the authoritative evidence* and it FAILS. Page-level US citation would not change a KR DROP. Accepted as low-severity; no further action needed for a negative finding (paper-cite verification feedback applies to claimed *positive* paper-derived numerics, not to a refutation).

---

## Escalation check
- HIGH severity concerns = 3 (C1/C2/C3) < 5 → no auto-escalate.
- AX axiom hard FAIL: AX-007 FAIL (1) < 3 → no auto-escalate.
- PIT C1 lookahead: none (C1 clean; C10 remediated strict-t1).
- Codex REJECT but agent does NOT rebut direction (concord DROP) → no Q-Lead escalate trigger.

**Outcome**: FIP DROPPED as standalone 5th source. Negative finding documented. Candidate L-code: "KR FIP/Information-Discreteness momentum refinement falsified — ID-refinement underperforms vanilla momentum, pure-continuity negative, beta~1.08 + 0.76 return-overlap with STR_1715 (cannibalization)."
