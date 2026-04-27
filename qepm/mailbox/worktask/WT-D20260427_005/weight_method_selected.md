# Iter 21 Optimizer — Macro Overlay Layer Dynamic Policy

- **Task ID**: WT-D20260427_005
- **Selected policy**: P1_dyn_cash
- **As-of**: 2026-04-27 (signal 2023-11-30)
- **Optimizer mechanism**: LinTilt+EMA+CVaR (Iter 11 baseline preserved)
- **Macro overlay layer**: macro_overlay_dynamic (msi_norm-driven cash 0~50% / max_w 0.10~0.20 / TO budget 200~600)

## Selection Rationale

- Iter 21 mandate: Layer track only (alpha unchanged cor=1.0; optimizer mechanism unchanged).
- 4 policies compared: P0 (static 4-state Iter 11 baseline) / P1 (dynamic cash) / P2 (dyn cash + max_w) / P3 (full dynamic incl TO budget).
- Selection = max(net_IR) AND TO_PASS AND MDD_PASS, with crisis_mdd_relief vs P0 baseline as layer value-add metric.
- CVaR_d 2.5% structurally infeasible (Iter 18 precedent disclosed, R12 No Silent Override).

## Policy Comparison

```
             policy sr_net cagr_net     mdd crisis_mdd crisis_ret peace_ret
             <char>  <num>    <num>   <num>      <num>      <num>     <num>
1:      P1_dyn_cash 0.1848   0.0142 -0.2846    -0.0626   -0.00148        NA
2: P2_dyn_cash_maxw 0.1826   0.0139 -0.2823    -0.0586   -0.00146        NA
3:  P3_full_dynamic 0.1826   0.0139 -0.2823    -0.0586   -0.00146        NA
4: P0_static_4state 0.1673   0.0138 -0.3258    -0.1011   -0.01211        NA
     cvar_d to_ann cost_ann net_ir avg_cash pass_to pass_cvar pass_mdd all_pass
      <num>  <num>    <num>  <num>    <num>  <lgcl>    <lgcl>   <lgcl>   <lgcl>
1: -0.02262  4.364   0.0065 0.1848   0.2760    TRUE      TRUE     TRUE     TRUE
2: -0.02250  4.367   0.0066 0.1826   0.2760    TRUE      TRUE     TRUE     TRUE
3: -0.02250  4.367   0.0066 0.1826   0.2760    TRUE      TRUE     TRUE     TRUE
4: -0.02803  5.518   0.0083 0.1673   0.1011    TRUE     FALSE     TRUE    FALSE
   crisis_relief
           <num>
1:  3.854970e-02
2:  4.254970e-02
3:  4.254970e-02
4:  4.969693e-05
```

## Selected Policy Details

- net_IR=0.1848, CAGR=0.0142, MDD=-0.2846
- crisis_mdd=-0.0626, crisis_mdd_relief vs P0=0.0386 pp
- peace_avg_ret (msi_norm < 0.25)=NA
- avg_cash=436.38%, avg_maxw=0.2000, avg_to_factor=1.0000
- TO_ann=4.3640, cost_ann=0.0065, CVaR_d=-0.02262

## Lessons Applied

- L-220 monthly base (NOT quarterly) — sig_date is bi-monthly, no vol-reduction quarterly machinery.
- L-211/225/228 cross-section alpha avoidance — macro signal is allocation NOT alpha.
- L-226 remediation via LAYER addition (not optimizer mechanism change).
- L-229 Iter 11 LinTilt baseline preserved (mechanism unchanged across 4 policies).
- L-454 KR-only enforced at alpha layer.
- L-224 strict cor=1.0 inheritance PASS (≥ 0.95 strict).

## Hard Constraints Audit

- max_names = 20 (per sig_date, equity sleeve)
- long-only (weights ≥ 0)
- weight_bounds [0, 0.20] base (P2/P3 shrink to [0, 0.10] when msi_norm = 1.0)
- Σw_eq = 1.0 (equity sleeve sum); cash_pct ∈ [0, 0.50] separate row
- universe: KOSPI200 ∪ KOSDAQ150 (inherited via alpha panel)
- liquidity floor: 2e8 KRW (inherited)
- cost: 15bps one-way

## Infeasibility Disclosure

- All hard constraints PASS.

## References

- Faber 2007 — Quantitative Approach to Tactical Asset Allocation
- Kritzman, Page, Turkington 2012 — Regime Shifts: Implications for Dynamic Strategies (FAJ)
- Barroso, Santa-Clara 2015 — Momentum has its moments (JFE)
- Estrella, Hardouvelis 1991 — Term Structure as Predictor of Recessions
- Iter 11 STR_1701 LinTilt λ=1.0 EMA 0.5 CVaR γ=5 baseline (preserved)
- Iter 18 WT-D20260427_002 LinTilt_EMA_CVaR Optimizer mechanism (preserved)
- L-454 KR internals dominate global FRED
- L-220 vol-reduction quarterly Harvey 격하 (avoided — monthly base preserved)
- L-224 alpha_inheritance_hash cor 0.95 strict (PASS cor=1.0)
- L-226 ERC near-EW alpha activation 부재 (Layer addition addresses)
- L-229 Iter 11 baseline optimal point (preserved)
- L-211/225/228 cross-section alpha avoidance (macro signal is allocation NOT alpha)
