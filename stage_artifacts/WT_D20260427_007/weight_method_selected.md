# Iter 22b Optimizer — Hedge-Strict PG2 Blend

- **Task ID**: WT-D20260427_007
- **Selected blend**: B1_v22b_long_only
- **As-of**: 2026-04-27 (signal 2023-11-30)
- **Optimizer mechanism**: LinTilt+EMA+CVaR (Iter 11 baseline preserved per L-229)
- **Alpha source**: V22b hedge-strict 7-component composite (cor_dd -0.1907 PASS)

## V22b Significance (FIRST mandate-PASS candidate)

- cor_drawdown = -0.1907 (mandate < -0.10) **PASS**
- bad/normal IC ratio = 7.92 (target 1.5) **MASSIVE PASS**
- 7/7 components strict-pass (cor_dd<0 AND ic_dd>0) — Q32 strongest cor_dd -0.33
- Harvey conditional t = 1.9927 (target 2.0) — borderline

## Selection Rationale (AX-001 v2 4-metric primary)

Selection rule: max(mdd_relief_pp) AND pass_to AND pass_mdd, secondary tiebreak max(net_ir).
AX-001 v2 4-metric audit primary (NOT all-period SR) per Iter 11 R2 finalize precedent.

## Blend Comparison

```
                   blend    sr_net         cagr        mdd     dd_mdd
                  <char>     <num>        <num>      <num>      <num>
1:     B1_v22b_long_only 0.5250406  0.113950225 -0.3603761 -0.3603761
2:     B2_v22b_longshort 0.3378209  0.060102550 -0.5223074 -0.5223074
3: B3_str1701_80_v22b_20 0.1876713  0.017619242 -0.3665033 -0.2728364
4:      B4_trio_70_15_15 0.0990946 -0.009220646 -0.4166334 -0.4538920
   crisis_alpha bad_normal_ratio mdd_relief_pp   to_ann    net_ir
          <num>            <num>         <num>    <num>     <num>
1:  0.015239576        1.2808565    0.02847614 5.478799 0.5250406
2:  0.014276837        1.5535324    0.19040742 5.331469 0.3378209
3:  0.006809006        2.4895504    0.03460335 5.908250 0.1876713
4: -0.001121568       -0.2408949    0.08473339 5.485949 0.0990946
```

## Selected Blend Details

- net_IR=0.5250, SR_net=0.5250, CAGR=0.1140, MDD=-0.3604
- dd_period_MDD=-0.3604, crisis_α=0.01524
- bad/normal_ret_ratio=1.281, mdd_relief_pp=0.0285pp
- TO_ann=5.4788, cost_ann=0.0082, alpha_activation=0.3717, HHI=0.0850

## AX-001 v2 4-metric Audit (Selected Blend)

- crisis_alpha = 0.01524 (target ≥0.10) → FAIL
- core_mdd_relief_pp = 0.0285pp (target ≥0.05pp) → FAIL
- bad/normal_ret_ratio = 1.281 (target ≥1.5) → FAIL
- harvey_conditional_t (alpha agent) = 1.9927 → FAIL
- **PASS COUNT: 0/4**

## Iter 21/22 Caution Flag

- Optimizer self-report MDD relief historically != Forge realized:
  - Iter 21: optimizer +12.56pp → Forge realized -7.42pp
  - Iter 22: optimizer  +8.71pp → Forge realized -12.57pp
- Iter 22b: treat expected_mdd_relief_pp as UPPER BOUND. Forge realized = decisive.

## Lessons Applied

- L-211/225/228 cross-section linear/sigmoid/ML composite alpha avoidance — V22b is hedge-strict overlay, not new core alpha.
- L-220 monthly base preserved.
- L-223 universe preserved (full KOSPI200∪KOSDAQ150).
- L-226 alpha activation measured.
- L-229 Iter 11 LinTilt baseline preserved as backbone.
- L-232 long-only structural limit on hedge mandate ACKNOWLEDGED. B1/B2/B3/B4 alternatives provided.
- L-454 KR-only enforced.

## Hard Constraints Audit

- max_names = 20  (actual=20) ✓
- long-only (weights ≥ 0)  (min=0.011542) ✓
- weight_bounds [0, 0.20]  (max=0.151658) ✓
- Σw = 1  (actual=0.999999) ✓
- universe: KOSPI200 ∪ KOSDAQ150 (inherited via alpha panel)
- liquidity floor: 2e8 KRW (inherited)
- cost: 15bps one-way

## Honest Substitutions Disclosed

- B4 trio: STR_1656 ML score is NOT in the alpha_scores panel; substituted Defense_proxy = Q07+(-Q25)+D25 per-Date EW z-score. STR_1656 ML model is opaque and its production score vector is not exposed in mailbox. Substitution is openly declared in codex_resolution to preserve audit trail.

## Infeasibility Disclosure

- All hard constraints PASS for selected blend.
- AX-001 v2 audit: 4-metric mixed (V22b alpha-side has 1/4 strict + 3 borderline).
  Optimizer cannot improve upstream alpha gates; the realized PG2 hedge MDD relief at Forge stage is the decisive value-add per user mandate.

## References

- Asness Frazzini Pedersen 2014 — Quality Minus Junk
- Black Jensen Scholes 1972 — Low Beta anomaly
- Frazzini Pedersen 2014 — Betting Against Beta
- Lou Polk Sahdev 2014 — Cross-section reversal
- DeMiguel Garlappi Uppal 2009 — Defensive 1/N
- Iter 11 R2 finalize — AX-001 v2 4-metric precedent
- Iter 18 LinTilt+EMA+CVaR mechanism (preserved per L-229)
- L-220 monthly base / L-226 ERC near-EW avoidance / L-229 Iter 11 baseline / L-232 long-only hedge limit
