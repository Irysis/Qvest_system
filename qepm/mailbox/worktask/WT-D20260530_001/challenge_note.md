# Challenge Note — WT-D20260530_001 (Hawkes self-excitation ⊥ flow-level)

Codex Critic Round (role=alpha) + agent self-adversarial review. Charter §8 No Silent Override.

Self-rationalization auto-check: grepped responses for "미미/관행적/실무적/보수적이면 OK/대부분 결과 동일" — none used.

Codex helper invoked async (`run_codex_qepm_critic.sh`). The canonical pipeline completed (DONE, results.rds 08:52) with the authoritative numbers below; if the async Codex response lands after this measure window, the finding is unchanged (negative result, no admission/book change → no silent-override risk). This note records the agent self-adversarial resolution of the role-card concerns.

## Authoritative results (canonical_screen_bt, NW lag-3; results.rds)
- portfolio-alpha t: full **-0.582** / IS 0.831 / OOS **-2.224**
- net SR: full -0.175 / IS 0.267 / OOS -1.366
- raw Hawkes (pre-ortho): portfolio-alpha t -1.411, net SR -0.41
- rank-IC: full 0.0085 (ICIR 0.067, t 0.835) / IS 0.0042 / OOS 0.0282 (ICIR 0.223, t 1.18); Harvey haircut N=25 → 0.00
- DSR 0.004; realized_beta 0.705; turnover 13.81/yr (> 11 cap)
- signal cor 0.008/0.071/-0.003 (STR_1715/D/FLOW); return cor 0.42/0.40 (STR_1715/D)
- AX-001 v2 bad/normal rank-IC ratio 3.618 (n_bad=12)

## Concern Resolution

### 1. [HIGH] alpha_vector deployability — ACCEPT
authoritative portfolio-alpha t fails full (-0.582) and OOS (-2.224) vs 2.95; DSR 0.004. → `alpha_vector_status=non_deployable_audit_only`, `deployable=false`. Ships for inheritance/audit lineage only (discovery factor_specs≥1 satisfied).

### 2. [HIGH] "harvey_t" mislabel — ACCEPT
rank-IC t (full 0.835 / OOS 1.18) is plain t, not Harvey-Liu-Zhu (2016) haircut. Added `rankic_t_harvey_haircut_n25` = **0.00** (full & OOS): Sidak N=25 cumulative trials → p_sidak≈1 → t≈0. No multiple-testing-adjusted rank-IC significance. Renamed simple fields `rankic_t_simple_*`.

### 3. [MEDIUM] intensity_slope scale dependence — PARTIAL
- Rebuttal (quantitative): intensity_slope IS cross-sectionally z-scored per sig_date (1/99 winsor + z) before composite; orthogonalization on INV01/05/09 removes flow-level subspace.
- Concession: raw λ not per-ticker normalized pre-slope → residual activity-level bounded post-z. `intensity_slope_scale_caveat` documented. Refinement, not result-changing (fails authoritative regardless). Ref Ozaki 1979.

### 4. [MEDIUM] "orthogonal" headline misleading — ACCEPT
signal-space orthogonal (0.008/0.071/-0.003) but NOT return-space orthogonal (return cor 0.42 vs STR_1715, 0.40 vs D), via shared KR universe + beta 0.705. Reframed + `orthogonality_note`. RF retained.

### 5. [MEDIUM] turnover breach — ACCEPT
TO 13.81/yr = 1.26x the TO≤11 cap. `turnover_constraint_breach` added. Hard constraint violated → additional fail dimension.

### 6. [LOW] DSR basis — ACCEPT
`dsr_note`: per-period net active SR -0.051 (negative) << BHY expected-max-from-N=25 0.161 → DSR 0.004. Robust to basis (SR negative).

### Bonus: AX-001 v2 honest framing
bad-regime rank-IC 0.046 > normal 0.013 (3.62x) looks like crisis edge, BUT rank-IC-conditional, not crisis portfolio-alpha, and base signal non-viable. Documented `ax001_v2_note`. NOT claimed as defensive-factor pass.

## Weakest Assumption — AGREE
"Orthogonal residual of Hawkes self-excitation carries deployable alpha" — NOT supported. IS portfolio-alpha t 0.831 < hurdle, OOS -2.224, full -0.582, DSR 0.004. cheap-screen rank-IC 0.0283/t3.57 was a screening artifact not reproduced under canonical (0.0085/t0.835, haircut 0.00). OOS rank-IC (0.0282) coincidentally near cheap-screen but OOS portfolio-alpha t -2.224 — exactly the Cycle2 rank-IC vs portfolio-alpha t divergence.

## Escalation check
- HIGH concerns = 3 (< 5) → no auto-escalate. AX hard FAIL = 0. PIT C1/lookahead = none (forward-return self-consistency: 2024 bear months negative; strict t-1 flow window `Date<sig_date`; data.table shift lead per rule). No Q-Lead escalate.

## Verdict
This construction (Hawkes self-excitation ⊥ INV01/05/09, top25 EW long-only, 15bps, N=155 sig_dates 2013-06..2026-04): VALIDATED_HARD_FAIL candidate. raw Hawkes worse than residual; residual also fails canonical. findings-only — "this construction does not reproduce the cheap-screen signal under authoritative portfolio-alpha t", not "Hawkes flow has no alpha" universally. No admission/book change (measure stage).
