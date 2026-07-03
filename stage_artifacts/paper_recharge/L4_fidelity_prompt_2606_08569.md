# RUNTIME INJECTION (read this first)

PAPER = 2606.08569 "Stock Investment: The p-index Approach" (Xie, Nie, Chang 2026; q-fin.PM)
ENGINE = C:/Users/99922/OneDrive/Quant_Module_Moltbot/02_Infrastructure/alpha_search/factor_engine_pindex_2606_08569.R
VERIF_JSON = C:/Users/99922/OneDrive/Quant_Module_Moltbot/stage_artifacts/paper_recharge/auto_verify_2606.08569.json

## IMPORTANT CONSTRAINT — full PDF UNAVAILABLE
The paper full text / PDF could NOT be retrieved in this environment (jina HTTP 402; arxiv-mcp lacks the pdf extra; paper-search returned empty). You have ONLY the **abstract** (below) plus the implementer's IMPL_SPEC (inside VERIF_JSON). You therefore CANNOT verify the exact equation numbers/forms (eq.6-9) against the source. Apply fail-closed: if you cannot CONFIRM from available evidence that the engine faithfully implements the paper's signal definition and direction, set `fidelity_pass=false` with `fidelity_confidence` reflecting the limitation.

## PAPER ABSTRACT (only available source)
"This paper has used European put option to construct the p-index risk measure to evaluate the performance of different investment strategies in China's SSE 50 index and the US SP500 index during 2018-2023. The p-index measures the insurance fee for each insured dollar to guarantee that the asset achieves at least a delta rate of return on a specified future date. It is found that with the fair price strategy, one-week and one-month holding periods can earn more, and among seven economic sectors, materials sector stocks generated highest annualized rates of return. With momentum and contrarian strategies of one-week holding period, the p-ratio-efficient-contrarian strategy produced the highest annualized rate of return (9.97%), followed by the p-index-inefficient-momentum strategy (9.01%) and the p-index-efficient-contrarian strategy (6.48%); the MCIRS method employing the p-index consistently delivered higher returns than its beta-based approach; and efficient (outperforming) stocks failed to sustain their momentum while inefficient (underperforming) stocks exhibited no mean reversion. The p-index-efficient-contrarian strategy outperformed in low-sentiment (low-volume) regimes, while the p-index-inefficient-momentum strategy outperformed during high-sentiment (high-volume) periods. For the five hundred stocks of the US S&P 500 index during 2018-2023, efficient stocks sustained their momentum while inefficient stocks exhibited mean reversion. The p-index-efficient-momentum strategy produced the highest annualized rate of return (3.69%), followed by the p-ratio-inefficient-contrarian strategy (3.67%) and the beta-efficient-momentum strategy (3.48%)."

Key facts from abstract for your check:
- p-index = put-insurance fee per insured dollar to guarantee >= delta return at horizon T (European put). Constructed WITHOUT option market data.
- The WINNING direction is market-UNSTABLE: China(SSE50) = efficient-CONTRARIAN best; US(S&P500) = efficient-MOMENTUM best. The paper does NOT give a Korea result.
- The engine under review implements a p-index LEVEL cross-sectional sort, direction = LOW (long low p-index), pre-committed by the implementer.

## YOUR JOB
Read the ENGINE file and the IMPL_SPEC inside VERIF_JSON, then judge fidelity per the checklist below. Pay special attention to:
1. Is the p-index computation a genuine put-insurance construct (not a fabricated/placeholder proxy)? Is there any "requires code generation" / arbitrary-combo / fallback fabrication (batch_434)?
2. Does the implemented SIGNAL DEFINITION match the paper's p-index concept, and does the chosen DIRECTION (LOW) correspond to a real named strategy/economic claim in the paper (vs invented)? Note the paper's direction is market-unstable and gives no KR result — judge whether pre-committing LOW is defensible vs a fabricated direction.
3. Universe/rebal/period/PIT compliance (KOSPI200 U KQ150, top-25 long-only, monthly, 2005~, t-1 PIT).
4. KR feasibility (no option market data / cross-market / alt-data dependence).

---

# (verifier instructions follow)
