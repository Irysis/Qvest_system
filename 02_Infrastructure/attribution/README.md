# Attribution Engine (7 QEPM Modern Trends — Principle 7)

**Constitutional SOT**: `02_Infrastructure/docs/qvest_research_philosophy.md` Principle 7 — Attribution & Feedback Loop

**Built**: 2026-05-14 Session 81 (Phase 2.D)
**Mandate**: factor + selection + sector allocation + cost + residual 분해. Decay 자동 감지.

## Modules

### `brinson_decomp.R`

**Brinson-Fachler 분해** (Brinson, Hood & Beebower 1986 FAJ + Brinson-Fachler 1985 JoPM)

- Allocation effect (섹터배분 기여): `(w_p_k - w_b_k) × (r_b_k - r_b_total)`
- Selection effect (종목선택 기여): `w_b_k × (r_p_k - r_b_k)`
- Interaction effect (상호작용): `(w_p_k - w_b_k) × (r_p_k - r_b_k)`

API:
```r
source("02_Infrastructure/attribution/brinson_decomp.R")
br <- brinson_decomp(portfolio_panel, benchmark_panel, returns_panel)
br$summary           # cumulative totals
br$per_period        # per-Date breakdown
br$per_sector        # per-Sector cumulative
brinson_summary_text(br, lang = "ko")  # telegram-ready
```

### `carhart_4factor.R`

**Carhart 4-factor + NW(6) HAC standard errors** (Carhart 1997 JoF + Newey-West 1987)

- Jensen's α + 4 β {MKT, SMB, HML, UMD}
- NW lag 6 (monthly) t-stats
- R² + adjusted R²

API:
```r
source("02_Infrastructure/attribution/carhart_4factor.R")
c4 <- carhart_4factor(portfolio_returns, factor_returns)
c4$alpha_annualized      # Jensen's α annualized
c4$alpha_t               # NW-corrected t-stat
c4$betas                 # 4 factor exposures
c4$r_squared             # explanatory power
```

### Combined Decomposition

```r
result <- attribution_full_decomp(
  portfolio_returns_gross = pr_gross,
  portfolio_returns_net   = pr_net,
  factor_returns          = ff_factors,
  benchmark_returns       = bm_returns,
  rf_returns              = rf_panel,          # optional
  brinson_inputs          = list(              # optional
    portfolio_panel = port_panel,
    benchmark_panel = bench_panel,
    returns_panel = rets_panel
  )
)
result$decomposition_summary
# $alpha_carhart, $factor_exposures, $r_squared,
# $cost_drag_annualized, $brinson_total_active,
# $brinson_allocation, $brinson_selection
```

## 분기별 자동 호출 path

`monitoring agent` (Q3 2026-07 첫 발동 예정):

1. monitoring_init.md Step 5 `attribution_quarterly_audit` 호출
2. `attribution_full_decomp()` → 4 분해 metric
3. Telegram brief (`brinson_summary_text` + `carhart` alpha_t + cost_drag)
4. **Decay 감지 trigger**: alpha_t < 1.96 OR r² < 0.5 OR cost_drag > 5pp/yr → escalate

## Output spec (분기별 산출)

```
qepm/observability/attribution/
├── attribution_{quarter}.json    # decomposition_summary + carhart$betas/$alpha
├── brinson_{quarter}.parquet     # per_period + per_sector
└── alerts_{quarter}.json         # decay alerts (alpha_t / r_squared / cost_drag)
```

## 학술 출처

- Brinson G.P., Hood L.R., Beebower G.L. (1986) "Determinants of Portfolio Performance." *FAJ* 42(4).
- Brinson G.P., Fachler N. (1985) "Measuring Non-US Equity Portfolio Performance." *JoPM* 11(3).
- Carhart M.M. (1997) "On Persistence in Mutual Fund Performance." *JoF* 52(1).
- Newey W., West K. (1987) "A Simple, Positive Semi-Definite Heteroskedasticity and Autocorrelation Consistent Covariance Matrix." *Econometrica* 55.
- Acadian (2026) "Systematic Crowding Monitoring" (crowding decay).
