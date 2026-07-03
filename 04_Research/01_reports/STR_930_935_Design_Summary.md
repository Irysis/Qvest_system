# STR_930–935 Design Summary: OtherCorp Alpha Extensions
**Created: 2026-03-15**
**Context: Building on STR_906–929 discoveries; OtherCorp is dominant alpha (FF5α 10–12%, t=2.8–3.1)**

---

## Design Philosophy
These 6 strategies explore **different combinations of OtherCorp with complementary signals**:
- **Signal diversity**: Not just OC alone; pairing with value, momentum, flow agreement, contrarian
- **Data efficiency**: Use existing parquets (investor_wide, valuation, consensus, RAWDATA)
- **3-4 factor sweet spot**: Avoid kitchen-sink (6+ factors dilute signal per STR_922 learning)
- **Sector-neutral scoring**: All compute z(signal) within sector to eliminate sector bias

---

## Strategy Designs

### STR_930: OtherCorp + Foreign Agreement + ESBR Confirmation
**File**: `/research_output/strategies/STR_930_oc_foreign_esbr/run_all.R`

**Hypothesis**:
Triple alpha confirmation via three independent signals.
When OtherCorp insiders AND foreign investors both buy,
PLUS analyst consensus signals improving earnings surprises (ESBR),
the convergence maximizes signal reliability.

**Signal Construction**:
| Component | Calculation | Logic |
|-----------|-------------|-------|
| **OC Agreement** | `sqrt(\|OC_norm\| × \|FO_norm\|)` where both > 0 | Both insiders & foreign buying simultaneously |
| **ESBR (40d avg)** | `frollmean(esbr, 40)` | Analyst earnings surprise breadth improving |
| **IdioVol** | Residual vol from market regression (252d expanding) | Risk management |

**Weights**: IdioVol 35%, OC+FO agreement 30%, ESBR 35%

**Data Files**:
- `investor_wide.parquet` (OtherCorp, Foreign)
- `consensus.parquet` (esbr)
- `RAWDATA` (price, returns, sector)
- `FRED_REGIME_CACHE` (macro regime)

**Expected Edge**:
- Demand (OC+FO) + fundamental expectation (ESBR) = orthogonal confirmation
- ESBR independent from flow (consensus signal vs. transaction signal)
- Potential to improve on STR_924 (OC+FO only) by adding earnings dimension

**Turnover Profile**: Monthly rebalance, N=20, vol_target=18%

---

### STR_931: OtherCorp + fPBR Value Targeting
**File**: `/research_output/strategies/STR_931_oc_fpbr/run_all.R`

**Hypothesis**:
Insiders recognize book/market undervaluation as fundamental anchor.
fPBR (forward P/B) captures book value differently than EV/EBITDA.
Combining insider demand with cheap book provides **complementary value coverage**.

**Signal Construction**:
| Component | Calculation | Logic |
|-----------|-------------|-------|
| **OtherCorp (40d)** | `sum(OC, 40d) / Size` | Normalized insider buying demand |
| **fPBR Value** | Ranked by `-fPBR` (lower = better) | Classic value metric (different from EV_EBITDA) |
| **IdioVol** | Residual vol (252d expanding) | Risk control |

**Weights**: IdioVol 35%, OC 25%, fPBR value 40%

**Data Files**:
- `investor_wide.parquet` (OtherCorp)
- `valuation.parquet` (fPBR)
- `RAWDATA`
- `FRED_REGIME_CACHE`

**Expected Edge**:
- fPBR captures balance-sheet value (different dimension from EV_EBITDA used in STR_923)
- Insiders buying cheap book = strong anchoring signal
- Complementary to STR_923 (EV_EBITDA); test coverage difference

**Turnover Profile**: Monthly, N=20, vol_target=18%

---

### STR_932: Individual Investor Contrarian
**File**: `/research_output/strategies/STR_932_individual_contrarian/run_all.R`

**Hypothesis**:
Retail investor herding is noise; persistent **selling by individuals = opportunity**.
Negative Individual flow is contrarian **bullish signal** (bet against retail panic).
Different mechanism: use OTHER investor type as INVERSE signal (not OC-based).

**Signal Construction**:
| Component | Calculation | Logic |
|-----------|-------------|-------|
| **Individual Contrarian** | `-Individual_norm` (negate flow) | Negative Individual flow = positive signal |
| **IdioVol** | Residual vol (252d expanding) | Risk management |

**Weights**: IdioVol 50%, Individual contrarian 50%

**Data Files**:
- `investor_wide.parquet` (Individual)
- `RAWDATA`
- `FRED_REGIME_CACHE`

**Expected Edge**:
- Different source of alpha: CONTRARIAN (retail bias) vs. INSIDER (smart money)
- Minimal data requirements; easy to implement
- May underperform if Individual is noisy; test needed
- Contrasts with OC dominance: exploits opposite mechanism

**Turnover Profile**: Monthly, N=20, vol_target=18%

---

### STR_933: OtherCorp Acceleration + ESBR + Coverage Expansion
**File**: `/research_output/strategies/STR_933_oc_accel_esbr_cov/run_all.R`

**Hypothesis**:
Insider **acceleration** (increasing buying pace) + improving analyst consensus
+ expanding analyst coverage (growth in following) = **triple momentum** signal.
Captures insider conviction INCREASE, consensus improvement, and growing attention.

**Signal Construction**:
| Component | Calculation | Logic |
|-----------|-------------|-------|
| **OC Acceleration** | `(OC_40d - OC_80d/2) / \|OC_80d\|` | Is insider buying accelerating? |
| **ESBR (40d avg)** | `frollmean(esbr, 40)` | Analyst earnings surprise consensus |
| **Coverage Expansion** | `Coverage_40d - Coverage_80d` | Analyst count growth (attention) |
| **IdioVol** | Residual vol (252d expanding) | Risk control |

**Weights**: IdioVol 35%, OC acceleration 25%, ESBR 20%, Coverage expansion 20%

**Data Files**:
- `investor_wide.parquet` (OtherCorp)
- `consensus.parquet` (esbr, coverage)
- `RAWDATA`
- `FRED_REGIME_CACHE`

**Expected Edge**:
- Acceleration > absolute flow level (captures conviction momentum)
- Coverage expansion captures analyst discovery (attention anomaly)
- Three independent momentum signals = strong confirmation
- Potential to amplify STR_924/923 via momentum overlay

**Turnover Profile**: Monthly, N=20, vol_target=18%

---

### STR_934: Institutional + Foreign Smart Money Agreement
**File**: `/research_output/strategies/STR_934_inst_foreign_flow/run_all.R`

**Hypothesis**:
When BOTH institutional (domestic smart money) AND foreign investors buy together,
it signals **synchronized conviction across market segments**.
Different from STR_924 (OC+Foreign): targets non-insider smart money agreement.
Tests if smart money synchronization (even without insider signals) drives alpha.

**Signal Construction**:
| Component | Calculation | Logic |
|-----------|-------------|-------|
| **Inst+Foreign Agreement** | `sqrt(\|INST_norm\| × \|FO_norm\|)` if both > 0 | Synchronized smart money |
| **Fallback Signal** | Inst or Foreign alone (weighted 0.7) | When only one available |
| **IdioVol** | Residual vol (252d expanding) | Risk management |

**Weights**: IdioVol 35%, Inst+Foreign agreement 65%

**Data Files**:
- `investor_wide.parquet` (Institutional, Foreign)
- `RAWDATA`
- `FRED_REGIME_CACHE`

**Expected Edge**:
- Pure smart money agreement (no insider component)
- Tests whether foreign+domestic consensus alone (without OC) drives alpha
- Different investor composition than STR_924; may capture different alpha
- Simpler than STR_930 (only flow, no consensus data needed)

**Turnover Profile**: Monthly, N=20, vol_target=18%

---

### STR_935: OtherCorp + fPER Value + Revenue Momentum Trifecta
**File**: `/research_output/strategies/STR_935_oc_fper_revmom/run_all.R`

**Hypothesis**:
Insider demand (OtherCorp) + earnings multiple undervaluation (fPER cheap)
+ growing revenue (momentum) = **fundamental trifecta**.
Confirms growth at reasonable price, with insider conviction backing it.
Combines demand + double-fundamentals (valuation + growth).

**Signal Construction**:
| Component | Calculation | Logic |
|-----------|-------------|-------|
| **OtherCorp (40d)** | `sum(OC, 40d) / Size` | Insider demand (conviction) |
| **fPER Value** | Ranked by `-fPER` (lower = better) | Cheap earnings multiple |
| **Revenue Momentum** | `(REV_40d / REV_80d) - 1` | Consensus revenue growth acceleration |
| **IdioVol** | Residual vol (252d expanding) | Risk control |

**Weights**: IdioVol 35%, OC 25%, fPER 20%, RevMom 20%

**Data Files**:
- `investor_wide.parquet` (OtherCorp)
- `valuation.parquet` (fPER)
- `consensus.parquet` (revenue_fy1)
- `RAWDATA`
- `FRED_REGIME_CACHE`

**Expected Edge**:
- "Growth at reasonable price" theme: momentum + cheap multiple
- Revenue momentum (40d vs 80d) captures consensus expectation growth
- Insiders backing both valuation AND growth = strongest conviction signal
- Potential to outperform pure value strategies (STR_931) by capturing growth

**Turnover Profile**: Monthly, N=20, vol_target=18%

---

## Comparative Positioning

| Strategy | Alpha Source | Key Mechanism | Unique vs. 906–929 |
|----------|--------------|----------------|--------------------|
| **STR_930** | OC+FO demand | Triple confirmation (flow+flow+consensus) | ESBR consensus added |
| **STR_931** | OC demand | Value anchor (fPBR vs EV_EBITDA) | Different value metric |
| **STR_932** | Retail bias | Contrarian (Individual selling) | OPPOSITE mechanism |
| **STR_933** | OC momentum | Acceleration + consensus + attention | Momentum overlay |
| **STR_934** | Smart money | Inst+FO (no insider) | Non-insider segment only |
| **STR_935** | OC+growth | Trifecta (demand+value+momentum) | Strongest 3-factor combo |

---

## Implementation Checklist

- [x] All 6 scripts created with full `run_all.R` structure
- [x] Sector-neutral scoring implemented in all strategies
- [x] Macro regime (BUDDHA, soft MRS) applied consistently
- [x] DD Brake + Vol Target (18%) applied post-simulation
- [x] Data validation (40+ tickers, min 30 obs, vol_floor 5%)
- [x] Hurdle gate + Telegram integration enabled
- [x] No future-reference (expanding window, no full-sample stats)

**Ready to Run**:
```bash
cd "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot/research_output/strategies/STR_930_oc_foreign_esbr" && \
  Rscript -e 'source("run_all.R")'

# Repeat for STR_931...STR_935
```

---

## Expected Results & Hypothesis Testing

**Prior on Performance** (based on STR_906–929):
- Grade B minimum (hurdle Sharpe ~0.90)
- FF5α 8–12% range likely for OC-heavy strategies (STR_930,931,933,935)
- STR_932 (contrarian) riskier; may underperform or show zero alpha
- STR_934 (non-insider) likely weaker than OC-based (OC dominance confirmed)

**Key Questions**:
1. **Does fPBR value (STR_931) outperform EV_EBITDA (STR_923)**? Signals different value dimensions?
2. **Can Individual contrarian (STR_932) compete with insider alpha**? Or is retail flow noise?
3. **Does OC acceleration (STR_933) beat absolute OC flow**? Momentum > level?
4. **Is Inst+FO agreement (STR_934) sufficient alone**, or does OC dominance hold?
5. **Does revenue momentum (STR_935) amplify or dilute OC+value combo**?

**Success Criteria**:
- STR_930, 931, 935: Grade A (Score >80) expected
- STR_933: Grade A expected (momentum often powerful)
- STR_934: Grade B acceptable (smart money tier lower than insider)
- STR_932: Grade C acceptable (contrarian exploratory; OC alpha sufficient)

---

## Session Notes
- All strategies built on **monthly rebalance, N=20, EW weighting, 18% vol target**
- Same infrastructure (harness v2.2, hurdle v3, regime engine v1.4)
- Total backtest time (6 strategies): ~15–20 minutes on single core
- Expected to complete batch by 2026-03-15 23:00 KST

