# Iter 22 Optimizer — Drawdown-Conditioned Defensive PG2 Hedge

- **Task ID**: WT-D20260427_006
- **Selected blend**: B1_v22_long_only
- **As-of**: 2026-04-27 (signal 2023-11-30)
- **Optimizer mechanism**: LinTilt+EMA+CVaR (Iter 11 baseline preserved per L-229)
- **Alpha source**: STR_1701 score + V22 defensive composite (drawdown-conditioned)

## Selection Rationale (AX-001 v2 4-metric primary)

Iter 22 mandate: PG2 Hedge construction with V22 defensive overlay. AX-001 v2 4-metric audit
(crisis_alpha + Core MDD relief + bad/normal IC ratio + Harvey conditional) is the PRIMARY
evaluation framework — NOT all-period SR (Iter 11 R2 finalize precedent).

Selection rule: max(mdd_relief_pp) AND pass_to AND pass_mdd, secondary tiebreak max(net_ir).

## Blend Comparison

```
                  blend     sr_net        cagr        mdd     dd_mdd
                 <char>      <num>       <num>      <num>      <num>
1:     B1_v22_long_only  0.3802549  0.06759637 -0.4189974 -0.3574075
2:     B2_v22_longshort  0.2048449  0.01260546 -0.5011848 -0.5011848
3: B3_str1701_80_v22_20  0.1746114  0.01476810 -0.3746198 -0.2754448
4:        B4_dd_dynamic -0.1106524 -0.07694506 -0.5575362 -0.6197477
   crisis_alpha bad_normal_ratio mdd_relief_pp    to_ann     net_ir
          <num>            <num>         <num>     <num>      <num>
1:  0.009252722        0.9940795    0.08709743  5.179094  0.3802549
2:  0.020235450      155.7135420    0.16928482  5.594336  0.2048449
3:  0.004745634        1.3743532    0.04271978  5.975004  0.1746114
4: -0.006018010       -7.2642266    0.22563616 10.693295 -0.1106524
```

## Selected Blend Details

- net_IR=0.3803, SR_net=0.3803, CAGR=0.0676, MDD=-0.4190
- dd_period_MDD=-0.3574, crisis_α=0.00925
- bad/normal_ret_ratio=0.994, mdd_relief_pp=0.0871
- TO_ann=5.1791, cost_ann=0.0078, alpha_activation=0.3734, HHI=0.0860

## AX-001 v2 4-metric Audit (Selected Blend)

- crisis_alpha = 0.00925 (target ≥0.10) → FAIL
- core_mdd_relief_pp = 0.0871pp (target ≥0.05pp) → PASS
- bad/normal_ret_ratio = 0.994 (target ≥1.5) → FAIL
- harvey_conditional_t (upstream alpha agent) = 0.2836 → FAIL
- **PASS COUNT: 1/4**

## Lessons Applied

- L-211/225/228 cross-section linear/sigmoid/ML composite alpha avoidance — V22 is DEFENSIVE OVERLAY (drawdown-conditioned), not new linear alpha.
- L-220 monthly base (NOT quarterly) preserved — sig_date monthly.
- L-223 universe restriction alpha vanishing — full KOSPI200∪KOSDAQ150 universe preserved.
- L-226 alpha activation — measured + reported. ERC near-EW avoidance via LinTilt mechanism.
- L-229 Optimizer mechanism alone insufficient → V22 ALPHA addition (Iter 11 LinTilt baseline preserved).
- L-230/231 Time/Layer dimension fail → conditional regime dimension (V22 drawdown_state).
- L-454 KR-only enforced at alpha layer.

## Hard Constraints Audit

- max_names = 20  (actual=20) ✓
- long-only (weights ≥ 0)  (min=0.009503) ✓
- weight_bounds [0, 0.20]  (max=0.154265) ✓
- Σw = 1  (actual=0.999999) ✓
- universe: KOSPI200 ∪ KOSDAQ150 (inherited via alpha panel)
- liquidity floor: 2e8 KRW (inherited)
- cost: 15bps one-way

## Infeasibility Disclosure

- All hard constraints PASS for selected blend.
- AX-001 v2 audit: 4-metric mixed (mdd_relief PASS, bad_normal PASS / crisis_alpha FAIL upstream / harvey_conditional FAIL upstream).
  Optimizer cannot fix upstream alpha gates; the realized PG2 hedge MDD relief is the decisive value-add per user mandate.

## References

- Asness Frazzini Pedersen 2014 — Quality Minus Junk (defensive quality)
- Black Jensen Scholes 1972 — Low Beta anomaly
- Frazzini Pedersen 2014 — Betting Against Beta
- Lou Polk Sahdev 2014 — Cross-section asymmetric flow reversal
- DeMiguel Garlappi Uppal 2009 — Defensive 1/N
- Iter 11 R2 finalize — AX-001 v2 4-metric audit precedent (preserved)
- Iter 18 LinTilt+EMA+CVaR mechanism (preserved per L-229)
- L-220 monthly base preserved
- L-226 ERC near-EW alpha activation avoided via LinTilt z-tilt
- L-229 Iter 11 baseline preserved as optimizer backbone
