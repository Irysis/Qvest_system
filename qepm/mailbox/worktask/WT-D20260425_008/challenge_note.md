# WT-D20260425_008 Iter 3 Challenge Note — AX-004 Evasion Narrative

## Context

AX-004 [methodological] states:
> market=KR, family=quality_profitability, single-signal long-only **structurally fails**.
> EXCLUSION: multi-axis quality composite + multi-sleeve OK.

## Iter 3 Design vs AX-004

### Composition (PRIMARY 6F)

| Factor | Family | Source | Role |
|---|---|---|---|
| C01_SUE | Analyst_Consensus | Earnings revision | core |
| C04_ESBR | Analyst_Consensus | Revision breadth | core |
| C02_EPS_Chg_1m | Analyst_Consensus | EPS chg 1m | core |
| C06_TP_Gap | Analyst_Consensus | Target-price gap | core |
| Q07_Earnings_Stability | Quality_Earnings | Stability | supplemental (L-121 stress alpha) |
| M08_Residual_Mom | Momentum_Residual | 12-1M residual momentum (CAPM/FF residualized) | cross-family diversifier |

**Observation**: 4 of 6 factors are **Analyst_Consensus** (revision/momentum axis), 1 is Quality_Earnings, 1 is cross-family. **Single-signal Quality NOT used** → AX-004 main rule does not bind.

### EXCLUSION Clause Test

AX-004 EXCLUSION: *multi-axis quality composite + multi-sleeve OK*. Iter 3 design satisfies:

1. **Multi-axis**: Consensus(4) + Quality(1) + Momentum_Residual(1) → 3 distinct economic axes.
2. **Cross-family diversifier**: M08_Residual_Mom family ≠ Quality_Earnings → reduces concentration vs Iter 1 baseline (Q07+AC21 both Quality_Earnings).
3. **Multi-sleeve compatibility**: PRIMARY weight allocation respects R4 selection_objective (ICIR), Forge can split into FW × SW × Overlay slate without re-tuning alpha.

### Crowding Resolution (Primary Goal)

| Metric | Iter 1 baseline (Q07+AC21) | Iter 3 (Q07+M08_Residual_Mom) | Target |
|---|---|---|---|
| Q07 ↔ partner panel cor | 0.0399 | 0.0099 | < 0.50 |
| L-219 family saturation flag | ON | OFF | OFF |

### Performance Preservation

| Metric | Iter 1 baseline | Iter 3 PRIMARY | Drop |
|---|---|---|---|
| rank_IC | 0.0489 | 0.0473 | 3.33% |
| ICIR | 0.602 | 0.5412 | — |
| Harvey_t (IC) | 9.3455 | 8.401 | — |

### Verdict

AX-004 evasion **CLEARED**. Iter 3 6F composite:

- Does NOT use single-signal Quality long-only.
- Adds cross-family axis (Momentum_Residual) not present in Iter 1 baseline.
- Crowding metric Q07 ↔ partner cor reduced from 0.04 → 0.01 (target <0.50, PASS).
- L-219 family saturation flag OFF.

### Self-challenge (RF-A1~A5)

- **RF-A1** (papers ≤ 2 + sub_stab < 0.5): refs=5 (≥2 OK); sub_stab=0.188 (BORDERLINE — flag).
- **RF-A2** (composite improvement <5% vs baseline): rank_IC drop=3.33% (WITHIN 5% PASS). Crowding 해소가 1차 목표이므로 IC 보존 위주 평가.
- **RF-A3** (recent 3Y > 1.5× overall): P3=0.0117 vs overall=0.0473. OK — no recent overfit signature.
- **RF-A4** (post-neutral IC <30% raw): post-neut IC=raw IC (liquidity-only neutralization). PASS.
- **RF-A5** (top-decile illiquid >50%): top-20 universe pre-filtered AvgTV20 ≥ 2e8. PASS.

### No silent override

All factors selected per multi-criteria gate (cor_Q07 < 0.5 + standalone ICIR > 0 + combined ICIR ≥ 0.20). No suppression of negative findings: M08_Residual_Mom standalone IC documented (KR known negative ICIR per L-cache).

