# STR_930–935 Quick Reference
**Ready-to-execute strategy designs | 2026-03-15**

---

## Strategy Card Deck

### STR_930: OtherCorp + Foreign Agreement + ESBR Confirmation
- **Hypothesis**: Triple confirmation (insider+foreign demand + analyst consensus)
- **Key Signals**: OC_40d, Foreign_40d, ESBR_40d
- **Weight Composition**: IdioVol 35% | OC+FO agreement 30% | ESBR 35%
- **Data**: `investor_wide` | `consensus` | `RAWDATA`
- **Expected**: Grade A (OC dominant + ESBR orthogonal)
- **FF5α Est**: 10–12% (t≈2.8–3.0)

### STR_931: OtherCorp + fPBR Value Targeting
- **Hypothesis**: Insider demand meets book value undervaluation
- **Key Signals**: OC_40d, fPBR (inverse rank)
- **Weight Composition**: IdioVol 35% | OC 25% | fPBR value 40%
- **Data**: `investor_wide` | `valuation` | `RAWDATA`
- **Expected**: Grade A (value different from EV_EBITDA; OC strong)
- **FF5α Est**: 10–11% (t≈2.8–2.9)

### STR_932: Individual Investor Contrarian
- **Hypothesis**: Retail selling = opportunity (bet against panic)
- **Key Signals**: -Individual_norm (negated)
- **Weight Composition**: IdioVol 50% | Individual contrarian 50%
- **Data**: `investor_wide` (Individual only) | `RAWDATA`
- **Expected**: Grade B–C (contrarian exploratory; retail likely noisy)
- **FF5α Est**: 2–5% (t≈0.8–1.5) — if any

### STR_933: OtherCorp Acceleration + ESBR + Coverage Expansion
- **Hypothesis**: Insider acceleration + consensus improvement + analyst growth = triple momentum
- **Key Signals**: OC_accel (ratio), ESBR_40d, Coverage_expansion
- **Weight Composition**: IdioVol 35% | OC accel 25% | ESBR 20% | Coverage exp 20%
- **Data**: `investor_wide` | `consensus` | `RAWDATA`
- **Expected**: Grade A (momentum powerful; OC+consensus+attention)
- **FF5α Est**: 9–11% (t≈2.7–2.9)

### STR_934: Institutional + Foreign Smart Money Agreement
- **Hypothesis**: Synchronized smart money (non-insider) conviction signal
- **Key Signals**: Inst_40d, Foreign_40d (agreement)
- **Weight Composition**: IdioVol 35% | Inst+FO agreement 65%
- **Data**: `investor_wide` (Inst, FO) | `RAWDATA`
- **Expected**: Grade B (smart money tier; OC proven dominant)
- **FF5α Est**: 5–8% (t≈1.8–2.4)

### STR_935: OtherCorp + fPER Value + Revenue Momentum Trifecta
- **Hypothesis**: "Growth at reasonable price" trifecta (demand + value + growth)
- **Key Signals**: OC_40d, fPER (inverse), Revenue_momentum
- **Weight Composition**: IdioVol 35% | OC 25% | fPER 20% | RevMom 20%
- **Data**: `investor_wide` | `valuation` | `consensus` | `RAWDATA`
- **Expected**: Grade A (strongest 3-factor: demand + value + growth)
- **FF5α Est**: 11–12% (t≈3.0–3.2) — highest potential

---

## Execution Commands

### Batch Run (Sequential)
```bash
#!/bin/bash
BASE_PATH="/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot/research_output/strategies"

for strategy in STR_930_oc_foreign_esbr STR_931_oc_fpbr STR_932_individual_contrarian \
                STR_933_oc_accel_esbr_cov STR_934_inst_foreign_flow STR_935_oc_fper_revmom; do
  echo "=== Running $strategy ==="
  cd "$BASE_PATH/$strategy"
  Rscript -e 'source("run_all.R")' 2>&1 | tee run.log
  echo "$strategy completed at $(date)"
done
```

### Parallel Run (3 at a time, tmux)
```bash
#!/bin/bash
BASE_PATH="/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot/research_output/strategies"

tmux new-session -d -s str930 -c "$BASE_PATH/STR_930_oc_foreign_esbr" "Rscript -e 'source(\"run_all.R\")'"
tmux new-session -d -s str931 -c "$BASE_PATH/STR_931_oc_fpbr" "Rscript -e 'source(\"run_all.R\")'"
tmux new-session -d -s str932 -c "$BASE_PATH/STR_932_individual_contrarian" "Rscript -e 'source(\"run_all.R\")'"

# Monitor
tmux list-sessions

# When done, run next batch
tmux new-session -d -s str933 -c "$BASE_PATH/STR_933_oc_accel_esbr_cov" "Rscript -e 'source(\"run_all.R\")'"
tmux new-session -d -s str934 -c "$BASE_PATH/STR_934_inst_foreign_flow" "Rscript -e 'source(\"run_all.R\")'"
tmux new-session -d -s str935 -c "$BASE_PATH/STR_935_oc_fper_revmom" "Rscript -e 'source(\"run_all.R\")'"
```

---

## Output Interpretation

### Key Output Files (per strategy)
```
research_output/strategies/STR_XXX_name/
  ├── run_all.R                    (strategy code)
  ├── sim_result.rds               (full backtest object)
  ├── Rplots.pdf                   (performance charts)
  └── output/
      ├── hurdle_result.json        (grade, FF5α, Sharpe, MDD, t-stats)
      ├── performance_summary.csv   (daily NAV, returns)
      ├── factor_analysis.csv       (correlations, turnover)
      └── tearsheet.pdf             (comprehensive report)
```

### Key Metrics to Check
| Metric | Hurdle | Target | Interpretation |
|--------|--------|--------|-----------------|
| **Score** | >50 (F) | >75 (A) | Overall quality |
| **FF5α** | >0% | >8% | Factor model alpha |
| **FF5α_t** | >1.96* | >2.8* | Significance |
| **Sharpe (OOS)** | >0.6 | >1.2 | Risk-adjusted return |
| **MDD** | <30% | <20% | Drawdown control |
| **Turnover** | <250% | <150% | Implementation cost |
| **IS/OOS ratio** | <1.5 | <1.2 | Overfitting check |

---

## Decision Tree

**After each strategy completes:**

1. **Score > 75 (Grade A)?**
   - YES → Flag for Grade A catalog, consider for production
   - NO → Continue to step 2

2. **FF5α > 8% and t > 2.5?**
   - YES → Interesting; check OOS stability
   - NO → Likely noise; mark as exploratory

3. **Sharpe OOS > 1.0?**
   - YES → Consider ensemble/blending
   - NO → Risk too high

4. **Turnover < 200% and MDD < 25%?**
   - YES → Production-ready candidate
   - NO → Need structural adjustment

---

## Hypotheses & Falsification

| Strategy | Core Hypothesis | How to Falsify | Alternative Outcome |
|----------|-----------------|----------------|---------------------|
| STR_930 | ESBR adds orthogonal alpha | Sharpe < STR_924 | Consensus noise |
| STR_931 | fPBR value different from EV/EBITDA | fPBR+OC < EV+OC | No value diversity |
| STR_932 | Retail selling = opportunity | Negative FF5α | Retail alpha real |
| STR_933 | Acceleration > level | Score < STR_930/931 | Momentum illusion |
| STR_934 | Smart money (non-insider) sufficient | Grade C/F | OC dominance absolute |
| STR_935 | Rev momentum amplifies OC+value | Sharpe < STR_931 | Too many signals |

---

## Knowledge Transfer

**For Dohoon (User Notes)**:
- **STR_932 is the "wild card"**: Bet against retail herding is academically sound (behavioral) but may be noise in Korean market. Lowest expected alpha.
- **STR_935 is the "strongest"**: Combines insider conviction + fundamental value + growth. Expect highest FF5α (11–12%) but also test for signal dilution.
- **STR_931 vs STR_923 comparison**: Key question is whether fPBR and EV_EBITDA capture orthogonal value or same factor. If correlated >0.7, one is redundant.
- **STR_934 is "due diligence"**: Confirms OtherCorp is uniquely powerful vs. other investor flows. If Grade A, it's noise in STR_934.

---

## Session Integration

These designs build on **MEMORY.md Session 35** findings:
- OtherCorp is dominant (FF5α 10–12%, t=2.8–3.1)
- 3–4 factor sweet spot > 6-factor kitchen-sink
- Consensus (ESBR, coverage) orthogonal to flow
- Value (EV_EBITDA) complements OC

**Success = 4–6 more Grade A strategies** expanding OC alpha family beyond STR_924/923.

