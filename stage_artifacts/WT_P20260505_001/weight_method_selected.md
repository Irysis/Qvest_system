# Weight Method Selected — WT-P20260505_001

## Selected Method

**Path_C_static_70_15_15_capital_allocation_with_TSMOM_30pct_cap**

method_kind: `static_capital_allocator_with_constraint_overlay`

## Capital Weights (Path C 도훈 명시 STRICT)

| Source | Weight | Asset Class |
|---|---|---|
| STR_1715 (AR-on-M4 PG2) | 0.70 | KR equity top20 sleeve |
| TSMOM rotation | 0.15 | 9-ETF cross-asset momentum |
| KR 10y bond ETF | 0.15 | KODEX KTB10Y (A148070) |

## Pre-2015 Renorm Convention (post-Codex C2 fix)

Pre-2015 (2005-02 → 2014-12, 119 dates) lacks TSMOM ETF universe. Renormalized:
- STR_1715 0.70 (unchanged)
- KR_10y 0.20 (capped from Architect 0.30 to honor weight_bounds [0, 0.20])
- CASH_KRW 0.10 (residual)

## Selection Rationale

1. 도훈 명시 Path C (2026-05-05) — user-fixed exogenous capital policy
2. STR_1715 PG2 admitted base preservation (alpha invariance rank_corr = 1.0 strict)
3. Ortho overlay only (TSMOM + KR10y bond)
4. 3-source diversification: avg cor with AR ≈ -0.03

## Selection Objective

`to_adj_ret` (turnover-adjusted return)
- TO_round_trip ≈ 576.2%/yr
- cost ≈ 0.864%/yr (15bps × TO)
- net SR(PerfA, full256m, renorm) ≈ 1.80

## Alternatives Rejected (Charter §8 documentation)

- Risk-parity reweight (~33/40/27 capital): 도훈 framing 외 — REJECTED_BY_USER
- Inverse-vol: 도훈 framing 외 — REJECTED_BY_USER

## Method Shopping Log

`optimization_package.json::method_shopping_log` records 3 candidates per Charter mandate.

## References

- `optimization_package.json` final
- `optimizer_challenge_note.md` (Codex disposition)
- `weights.csv` (256-date walk-forward schedule)
