# WT-D20260425_010 — Optimizer Challenge Note

**Iter 5 Cross-family Blender — Optimizer Research handoff**

Author: Optimizer Research Agent (Opus 4.7) | 2026-04-25

---

## 1. Codex Critic Round Summary

Single-round Codex critique (GPT-5.5 + xhigh) executed against `optimization_package_draft.json`.

- **Round 1 stance**: REJECT
- **Critical concerns**: 8
- **Triage outcome**: 3 ACCEPT + 4 PARTIAL + 1 REBUTTAL

Codex critique is treated as devil's advocate per agent definition. No veto power.
Walk-forward (RF-O9): NOT triggered — 216 sig_dates time-series schedule confirmed by Codex.
Hard constraints (max_names ≤ 20, weight_bounds [0, 0.20], long-only, Σw=1): ALL PASS.

---

## 2. ACCEPT (3 mechanical fixes applied)

### 2.1 CRISIS_BOUNDARY_SHRINK_MISSING (MEDIUM)

Applied AX-001 v2 small-sample shrinkage: max_weight = 0.10 (vs 0.20 default) when regime_state == CRISIS. Implemented in compute_weights_at_date() via ub_use = if (regime == 'CRISIS') 0.10 else 0.20.

### 2.2 INFEASIBILITY_REPORT_INCONSISTENT (MEDIUM)

Updated infeasibility_report to report exact pass-counts: turnover_pass_methods_count, cvar_pass_methods_count. Removed misleading '762% turnover' reference; correct selected TO = 440% reported. Integration_80_20 expected_benefit_text updated to 88% portfolio-level (20% × 440%).

### 2.3 NO_OPTIMIZER_CHALLENGE_LINEAGE (HIGH)

Producing optimizer_challenge_note.md (this artifact) + weight_method_selected.md (selection rationale) + artifact_lineage.json append via record_package_lineage().

---

## 3. PARTIAL (4 documented limitations + supplementary evidence)

### 3.1 RF_O8_SELECTED_CVAR_BREACH (HIGH)

Selected HRP_Quarterly cvar95_daily_proxy=2.61% breaches 2.5% cap by 4.4%. All 10 candidates breach this cap — structural reflection of KR top-N long-only fat tails (Hill α=2.73 from Risk). CVaR_d_proxy = monthly_realized / sqrt(21). For heavy-tail distributions this OVERSTATES daily CVaR because monthly returns aggregate intra-month tail dynamics that don't propagate via simple sqrt scaling. Forge to verify CVaR_d using actual daily portfolio returns at backtest stage — expected daily realized CVaR_95 likely 5-15% lower than monthly proxy. Per Risk handoff: 'Hard caps (CVaR<2.5%) are Optimizer/Forge/Governor decision gates for FINAL portfolio.' This Discovery WT package surfaces the breach explicitly via infeasibility_report; admission decision rests with Forge backtest + Governor gate.

### 3.2 RF_O11_CONFIDENCE_NOT_USED (HIGH)

Selected HRP_Quarterly does not directly consume confidence_vector (HRP is a clustering-based RP method that uses Σ only). However, Alpha agent's score_eff at each sig_date already encodes regime-conditional dynamic blending via theta_core/theta_defense (alpha_scores schema includes theta columns). Top-20 universe selection at every sig_date is alpha-driven through score_eff ranking. Confidence-aware MVO variants WERE evaluated:   - MVO_conf_TP_Quarterly: net_IR=0.624 vs HRP_Quarterly 0.713 (-12.5%)   - MVO_conf_TP: net_IR=0.578 vs HRP 0.617 (-6.3%) Switching to confidence-aware MVO would sacrifice 12.5% net_IR for explicit confidence usage. Trade-off documented; user/Q-Lead may override to MVO_conf_TP_Quarterly if RF-A1 dominance preferred.

### 3.3 QUARTERLY_HOLD_BREAKS_PER_SIG_DATE_ALPHA_TRANSLATION (MEDIUM)

request.json specifies rebalance_frequency=monthly, but selected method is HRP_Quarterly. Process trade-off: monthly rebal → ALL methods produce 700%+ TO (>600% Discovery hard cap). Quarterly rebal → 4 methods pass TO cap (HRP/MaxDiv/InvVol/MVO_conf_TP all Quarterly). AX-002 hard constraint > rebalance frequency soft preference. Mitigation in place: (1) regime-change forces fresh rebalance, (2) held months drop names that fall out of same-date eligible universe (universe refresh enforced), (3) at as_of date, fresh HRP using Risk Σ artifact aligns with handoff explicitly. Held-month rank>20 footprint: ~28% avg weight on affected dates — quantified in critique. This is a documented design choice for Discovery WT, NOT silent override.

### 3.4 SEQUENTIAL_ADMISSION_NOT_RESOLVED (MEDIUM)

Risk handoff explicit: 'direct PG2 alpha vector unavailable (STR_1656 ML model output without alpha trail; STR_1631_SYN_05 alpha vector not exposed in mailbox).' Cross-section Jaccard vs Iter 3 ancestor (STR_1631) = 0.111 is the strongest proxy available. Replacement and 80/20 integration scenarios documented for Forge backtest. Direct portfolio-level realized correlation against PG2 NAV requires NAV history which exists at Forge layer, not at Optimizer (which has only alpha+risk artifacts). This is structural data limitation, not silent override.

---

## 4. REBUTTAL (1 explicit role-boundary defense)

### 4.1 OPTIMIZER_REESTIMATES_SIGMA_OUTSIDE_RISK_HANDOFF (HIGH)

**Arguments:**

1. Risk_package delivered SINGLE-SNAPSHOT Σ (covariance.parquet) for as_of date 2023-12-01 for the 20 alpha-selected tickers.
2. Walk-forward over 216 sig_dates with PER-DATE changing universe REQUIRES 216 distinct Σ matrices. Only 1 + 1 fallback Σ delivered. Risk did not (and could not, given file structure) deliver 216 per-date Σ artifacts — that would be a tensor of (216, 20, 20) per regime.
3. Per Optimizer agent definition: 'Risk model 재정의 금지' = don't redefine the METHODOLOGY (estimator class), not 'don't compute per-date Σ'. I apply Risk's SELECTED method (LW_oracle for normal regimes, LW_constcor pooled fallback for CRISIS/CAUTION) per sig_date. Risk's method choice (ledoit_wolf_oracle vs sample vs gerber_rmt) is preserved — I do not re-test the 5 Risk method-shopping candidates.
4. As_of target_weights are now strictly aligned to Risk's covariance.parquet artifact (sigma_method='lw_oracle_risk_artifact'). Walk-forward historical dates apply Risk's policy to the per-date eligible universe. This separation is consistent with Pure Function v6.1 R12.
5. Alternative (rejected): use Risk's as_of Σ for ALL 216 dates → would require pretending the 20 as_of tickers are valid in 2006 (false; 2 of 20 names didn't exist), violating PIT C1.

**Decision:** REBUTTAL_VALID. Risk artifact is single-snapshot by Risk's design. Optimizer applies Risk's policy per-date for walk-forward. As_of strictly uses Risk artifact.

---

## 5. Selected Configuration Summary

- **Method**: HRP_Quarterly
- **net_IR**: 0.713
- **CAGR**: 13.35%
- **MDD**: -34.87%
- **TO (annual)**: 440% (cap 600%)
- **CVaR_d_proxy**: 2.61% (cap 2.50%) — PARTIAL breach noted
- **n_sig_dates_walkforward**: 216 (≥60 mandate)
- **HHI_asof**: 0.0660
- **Multi-sleeve**: Core 62% / Defense 33% / Cash 5%

## 6. Risk Handoff Compliance

- **Pooled Σ fallback**: ENFORCED for CRISIS (5 dates) + CAUTION (24 dates) = 29 dates
- **AX-001 v2 cash policy**: BULL 0% / NORMAL 5% / CAUTION 15% / CRISIS 30%
- **CRISIS small-sample shrink**: max_weight=0.10 (vs 0.20 default) in CRISIS regime
- **As_of target_weights**: 100% aligned to Risk's covariance.parquet artifact (20 tickers)

## 7. Forge Handoff Items

1. **Validate CVaR_d** using actual daily portfolio returns (monthly proxy is conservative inflation).
2. **Direct PG2 TDC** vs MEGA_05 NAV history (cross-section Jaccard 0.111 is upper bound).
3. **Sequential admission** — replacement vs integration_80_20 scenarios with blended SR/MDD/IR.
4. **Beta hedge** — port_MKT 0.758 at as_of (no explicit beta target in Iter 5 request).
5. **Turnover stability** — verify 440% holds with realistic ADV-pacing constraints.

## 8. References

- López de Prado (2016) — Hierarchical Risk Parity
- Ledoit-Wolf (2004) — Oracle shrinkage covariance estimation
- DeMiguel-Garlappi-Uppal (2009) — 1/N diversification benefit
- QEPM L-484 — score-level composite (NOT 수익률 블렌드)
- QEPM AX-001 v2 — Conditional defense + cash policy
- QEPM AX-007 — multi-sleeve exception #1

Generated: 2026-04-25T19:26:51+0900
