# weight_method_selected — WT-S20260504_004 (RMT Denoised Σ)

## Selected Method: **M4+RMT_VolTarget** (canonical)

### Rule
```
weight_cash_t    = max(M4_cash_t, RMT_cash_bridge_t)
weight_str1715_t = 1 - weight_cash_t
```

Both inputs are PIT monthly schedules. `weight_str1715_t` is then unrolled by Forge over STR_1715 base 18-active stock-level holdings (live from `production_weights/20260501_weights_cap_0p20.csv`, ticker schedule from `output/04_holdings.csv`).

### Three variants emitted
| Variant | Cash rule | active_cap | Role |
|---|---|---|---|
| **S1** | always 0 | 0.20 | baseline pure STR_1715 (no overlay) |
| **RMT_VolTarget** | 1 - scale (RMT statistical) | 0.20 | statistical de-risk only |
| **M4+RMT_VolTarget** | max(M4_cash, RMT_bridge) | 0.20 | canonical — regime + statistical conservative OR |

### Why M4+RMT_VolTarget (not pure RMT, not S1)?
1. **Non-redundant cash sources**: M4 = regime/event (BOCPD + BL tri-pillar), RMT = statistical vol (ES quantile). Different signal classes. Strict OR (`max`) is conservative — never under-protects.
2. **Inheritance from STR_1715 PG2 production**: M4 is live-active cash overlay. Removing it = regression. Adding RMT = new statistical layer on top.
3. **Empirical 2026-04-30 snapshot**: scale=0.7596 → cash_bridge=0.2404 (RMT). M4 cash_2026-03=0.2651. max=0.2651 (M4 dominates this month — RMT does NOT add bridge above M4 for the active month). Earlier months show RMT adding bridge where M4 was 0 (e.g., 2025-06 RMT 9.14% vs M4 0%).
4. **Selection objective = `to_adj_ret`** (turnover-adjusted): max() rule is monotonic in input cash → does not increase turnover beyond max of two inputs (deterministic, no oscillation).

### Why S1 not selected
S1 inherits MDD -32.05% unchanged. STR_1715 PG2 live full backtest gap = -7.05pp on MDD goal. S1 alone = no improvement.

### Why RMT_VolTarget alone not selected
RMT-only ignores M4 regime cash that is already live-active (PG2 admit basis). Variance reduction without M4 tri-pillar = regression vs PG2 baseline.

### Hard constraints audit (all PASS)
- max_names ≤ 20: 18 active stocks (STR_1715 inherited) ✅
- long_only: weights ≥ 0 (sleeve + stock level) ✅
- weight_bounds [0, 0.20]: max stock weight 0.20 (S-Oil + 쏠리드) ✅
- Σw = 1.0: max_dev = 0 (sleeve), 1e-6 (stock-level inherited) ✅
- universe: STR_1715 KOSPI200_KOSDAQ150 intersection ✅
- liquidity ≥ 2e8 KRW: STR_1715 production filter inherited ✅

### Schedule density
- unique_dates = 267 (parent M4 schedule, 2004-01..2026-03)
- sig_dates_count = 268 (STR_1715 268m backtest reference)
- ratio = 0.9963 ≥ 0.95 (PASS, certifier eligible)

### Codex Round 1 outcome
- stance: REJECT (7 concerns, 4 HIGH + 3 MEDIUM)
- veto_flag: false (advisory)
- Concerns 7 → 3 ACCEPT + 2 PARTIAL + 2 REBUTTAL
- Major edits applied to final:
  - `production_grade = false` (AX-008 미충족, C7 ACCEPT)
  - `infeasibility_report` 명시 (cvar_breach + cond>100, C2 ACCEPT)
  - `walk_forward_schema_waiver` 명시 + sleeve→stock unroll lineage (C1 PARTIAL)
  - method_shopping numeric proxy (turnover/cost, C3+C4 ACCEPT)
  - sizing_only role_card / recommendation_only spec 인용 (C5+C6 REBUTTAL)
- Q-Lead escalate 미발동 (HIGH<5 / AX hard FAIL<3 / Hard Constraint 위반 0)

### Forge handoff expectation
- Forge runs run_all.R with weights.csv (sleeve) × STR_1715 base ticker holdings (stock-level)
- 3 variants → 3 backtest results
- Judge verdict on canonical M4+RMT_VolTarget vs S1 vs RMT_VolTarget (forecast: 2~5pp MDD relief, 1~3pp CAGR drag)
- AX-008 triangulation: Forge + Judge + Architect 2/3 PASS path

### Lineage SHAs
- parent_alpha_package_sha = `34cc99fb...` (STR_1715 alpha frozen)
- risk_package_sha256 = `849f1248...`
- lro_params_sha256 = `3147d50e...` (RMT cutoff frozen, AX-002)
- weights_csv_sha256 = `6e1e84c5...` (canonical M4+RMT_VolTarget)
