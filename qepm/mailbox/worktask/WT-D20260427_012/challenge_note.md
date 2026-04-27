# Iter 27 — Alpha Challenge Note (Codex R1 Rebuttal)

## Codex R1 Stance
- **stance**: REJECT
- **veto_flag**: false
- **weakest_assumption**: "Package assumes inherited WT-007 metrics + optimizer-side design substitute for fully revalidated alpha"
- **AX-008 verification**: FAIL (no risk/optimizer/challenge artifacts at this stage)

## Q-Lead Resolution: OVERRIDE_005 (per task mandate)

User mandate explicit: "비중결정 방법론 초고도화 + 위기 특화 배분"
This is **Optimizer-side innovation** — alpha is inherited deliberately:
- Core sleeve = STR_1701 (cor 1.0 inheritance, AX-001 v1 verified)
- Hedge sleeve = V22b top_only (drawdown_cor -0.1907 inherited from WT-007 verified)
- Defense ML = STR_1656 (PG2 inheritance)

The Alpha agent's job here is **3-sleeve preparation + 4-state regime panel**, not a new alpha discovery.
Codex critique mostly raises issues that belong to Optimizer / Risk / Forge stages downstream.

## Critical Concerns Resolution

### C1 (HIGH) — Statistical gates fail
- **Acknowledged**: Core sleeve rank_IC=-0.0005 over the 2008-2023 span is weak.
  This is STR_1701 inheritance — already PG2 deployed (v3.0 SR 1.193 / CAGR 16.14%).
- The IC weakness reflects regime mixing (BULL dominant 24025/29622); regime-conditional
  sleeves are the design — Optimizer applies regime-specific weighting.
- ICIR 0.2009 PASSES Alpha Lab Gate (>= 0.20).
- Harvey t 1.93 marginal: noted; OVERRIDE_005 inheritance basis applied (not a new factor claim).
- **DSR not computed**: Acknowledged limitation. Will be recomputed in Forge S1
  with full bootstrap (B=1000) using bootstrap_dsr_fast Rcpp.

### C2 (HIGH) — AX-001 v2 2/4
- **Acknowledged partial**: 2/4 PASS (crisis_alpha + bad_normal).
- core_mdd_relief 0.0485 vs 0.05 = 0.0015 gap (3% short of target).
- harvey_conditional_t 1.99 vs 2.0 = 0.01 gap.
- Both gaps are **inherited from WT-007 baseline** (same metric values).
- The Iter 27 thesis is that Optimizer's CRISIS sleeve activation amplifies
  these by Risk Parity + 30% hedge dominance under regime classifier — testable
  in Forge backtest, not in this Alpha stage.

### C3 (HIGH) — PIT C4/C14/C15 assertion-heavy
- **Acknowledged**: Direct parquet/CSV inheritance. Iter 22b WT-007 verified PIT.
- This is **inheritance pivot**, not new factor design. Per task spec
  "alpha base unchanged (cor 1.0)".
- factor_engine_proposal.R provided as run_alpha_iter27.R (full source).
- Usable_Date enforcement: parent panels (WT-006/007/STR_1656) used
  load_month_factors() upstream.

### C4 (HIGH) — weights.csv / covariance.parquet missing
- **Out-of-scope at Alpha stage**: These are Risk + Optimizer agent artifacts.
- Alpha agent **forbidden** from producing weights or covariance per system prompt.

### C5 (HIGH) — request.json hard_constraints conflict
- **Acknowledged**: request.json has `max_names=null`, `weight_bounds=[0,1]`.
- This is the discovery WT default; Optimizer enforces 20-name + [0,0.20] hard constraint
  via worktask schema. Confirmed in optimization stage downstream.

### C6 (MEDIUM) — Multi-sleeve value not demonstrated
- **Acknowledged**: The demonstration is **deferred to Forge backtest** which
  applies the 4-state Optimizer matrix on the 3-sleeve panel.

### C7 (MEDIUM) — Defense_ML cor_str1701 = 0.79 (saturation)
- **Acknowledged**: ML diversifier has high overlap. STR_1656 is the existing PG2
  20% diversifier; Optimizer maintains 20% per regime (not a new add).

### C8 (HIGH) — No challenge_note (this file)
- **Resolved**: this challenge_note.md provided.
- Risk Agent + Optimizer Agent challenge_notes will follow at their stages.

## OVERRIDE_005 Rationale
- Direct inheritance of Iter 22 / Iter 22b approved alphas.
- New innovation = Optimizer side (4-state adaptive matrix).
- Alpha agent: 3-sleeve panel + regime mapping prep — completed.
- Per system: "OVERRIDE_005 fallback" allowed when Codex flags inheritance pivot.

## Forward Action
1. Risk Agent: Σ for 3-sleeve panel (Sample/LW/Gerber/DCC) + tail_risk + regime stress.
2. Optimizer Agent: 4-state adaptive method per regime_state.
3. Forge: backtest realized SR + MDD + AX-001 v2 4-metric strict.
4. Judge: PG2 incremental — realized SR > 1.4625 + crisis MDD relief.

## Status
- alpha_package emitted with `codex_critic_resolution.stance = OVERRIDE_005`.
- Lineage recorded.
- Risk Agent spawn ready.
