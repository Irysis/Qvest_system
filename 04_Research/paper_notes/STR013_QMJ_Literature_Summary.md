# STR_013 QMJ — Quality/Profitability Factor Literature Summary

**Generated:** 2026-03-01
**Purpose:** Korea applicability and STR_013 utility assessment for 11 quality/profitability papers
**Universe:** KOSPI200 + KOSDAQ150, long-only, DART fundamentals + OHLCVS

---

## Paper Inventory

| ID | Paper | Authors | Year | Journal | Note File |
|----|-------|---------|------|---------|-----------|
| P135 | Quality Minus Junk | Asness, Frazzini, Pedersen | 2019 | Rev. Accounting Studies | P135.md |
| P136 | Choosing Factors | Fama & French | 2018 | JFE | P136.md |
| P137 | Digesting Anomalies | Hou, Xue, Zhang | 2015 | RFS | P137.md |
| P138 | History of Cross-Section | Linnainmaa & Roberts | 2018 | RFS | P138.md |
| P139 | Gross Profitability Premium | Novy-Marx | 2013 | JFE | P139.md |
| P140 | Profitability and Investment Premium Pre-1963 | Wahal | 2019 | JFE | P140.md |
| P141 | Sticky Expectations | Bouchaud et al. | 2019 | JF | P141.md |
| P142 | International Value and Profitability Premiums | Cakici et al. | 2022 | Working Paper | P142.md |
| P143 | Dissecting Anomalies | Fama & French | 2008 | JF | P143.md |
| P144 | Five-Factor Asset Pricing Model | Fama & French | 2015 | JFE | P144.md |
| P145 | Choosing Factors (duplicate) | Fama & French | 2018 | JFE | P145.md → see P136 |
| P184 | QMJ Working Paper | Asness, Frazzini, Pedersen | 2017 | SSRN | P184.md |
| P185 | QMJ Published (Springer) | Asness, Frazzini, Pedersen | 2019 | Springer | P185.md → see P135 |

---

## Korea Applicability Assessment

| Paper | Korea Applicability | Data Required | Confidence | Key Adjustment |
|-------|--------------------|-----------|----|----------------|
| P135 QMJ | HIGH (85% implementable) | DART + OHLCVS | HIGH | April rebalancing; 연결재무제표 |
| P136 Choosing Factors | HIGH | DART 연결재무제표 | HIGH | RMWcp > RMWop; Feb rebalancing |
| P137 q-factor | HIGH | DART 분기보고서 | MEDIUM | Monthly ROE rebalancing via quarterly DART |
| P138 History Cross-Section | WARNING only | None (calibration paper) | N/A | 74% haircut on in-sample alpha estimates |
| P139 GP/A | HIGH | DART annual | HIGH | Industry-adjust; GP/ME better than GP/A for Korea |
| P140 Pre-1963 Profitability | CALIBRATION only | None | N/A | RMW × 0.65, CMA × 0.05 haircut |
| P141 Sticky Expectations | MEDIUM | DART quarterly + FnGuide optional | MEDIUM | CFOA primary; post-earnings seasonal weighting |
| P142 International | HIGH — directly relevant | DART annual | HIGH | Asia Pacific calibration: GP/ME FFC alpha 1.34%/mo |
| P143 Dissecting Anomalies | MEDIUM (cautionary) | DART annual | MEDIUM | Use value-weights; avoid Y/B; keep accruals gate |
| P144 FF5 | HIGH | DART annual | HIGH | April rebalancing; test HML redundancy for Korea |
| P184 QMJ WP | (same as P135) | same | same | See P135 |
| P185 QMJ Springer | (same as P135) | same | same | See P135 |

---

## STR_013 Utility Assessment

| Paper | STR_013 Direct Use | Contribution | Implementation Step |
|-------|-------------------|-------------|-------------------|
| P135 QMJ | PRIMARY | Full composite quality score formula | Quality = z(Prof + Growth + Safety) |
| P136 Choosing Factors | PRIMARY | Replace RMWop with RMWcp in composite | CP = OP - accruals |
| P137 q-factor | SUPPLEMENTARY | Monthly-rebalanced ROE component | Add quarterly ROE to quality composite |
| P138 History Cross-Section | CALIBRATION | Alpha haircut framework | Expected alpha × 0.26 (pre/in ratio) |
| P139 GP/A | PRIMARY sub-factor | GPOA sub-factor; industry adjustment | Industry-adj GP/A in profitability z-score |
| P140 Pre-1963 | CALIBRATION | RMW haircut 0.65, CMA haircut 0.05 | Adjust live alpha expectations |
| P141 Sticky Expectations | ENHANCEMENT | CFOA weighting; seasonal timing | CFOA weight 1.5× in profitability |
| P142 International | CALIBRATION | Asia Pacific alpha scaling | GP/ME over GP/A; large-cap bias favorable |
| P143 Dissecting Anomalies | GUARDRAIL | Accruals gate; value-weighting mandate | Screen: exclude high-accrual stocks |
| P144 FF5 | FOUNDATIONAL | OP definition; factor construction | Annual OP + monthly q-ROE dual layer |
| P184/P185 | DUPLICATE | Formula verification | See P135/P136 |

---

## Key Factor Selection for STR_013

### Recommended Quality Composite (Korean-Calibrated):

```
Korea_Quality = z(Profitability_KOR + Growth_KOR + Safety_KOR)
```

#### Profitability_KOR (from P135, P136, P139, P141, P142):
```
Profitability_KOR = z(
  2.0 × z_GPME   +   # GP/ME — Asia Pacific strongest (P142); scaled 2x
  1.5 × z_CFOA   +   # CFOA — most persistent, sticky-expectations (P141); scaled 1.5x
  1.0 × z_GPOA   +   # GP/A — Novy-Marx base (P139); industry-adjusted
  1.0 × z_RMWcp  +   # Cash profitability — FF2018 best (P136); includes accruals
  1.0 × z_ROA    +   # ROA — robust pre-sample (P138/P140)
  0.7 × z_ROE    +   # ROE — less persistent than CFOA (P141 calibration)
  1.0 × z_ACC       # Cash earnings fraction HIGH = GOOD (P135/P184)
)
```

#### Growth_KOR (from P135):
```
Growth_KOR = z(Δ5yr_GPOA + Δ5yr_ROE + Δ5yr_ROA + Δ5yr_CFOA + Δ5yr_GMAR)
NOTE: Limited by DART history (2016-2024 → 5yr available only from 2021+)
EARLY YEARS: Use 3yr growth proxy until 5yr available
```

#### Safety_KOR (from P135):
```
Safety_KOR = z(
  -z_beta    +   # FP beta (60m corr × 12m vol) to IKS200; LOW beta = safe
  -z_lev     +   # 부채비율 (LOW leverage = safe)
  -z_Oscore  +   # Altman Z-score proxy (HIGH = safe)
  -z_EVOL       # Rolling 5yr ROE std dev (LOW = safe)
)
NOTE: O-score full 9-variable form has IFRS mapping issues; use Z-score as proxy
```

---

## Expected Alpha Calibration (Korea Live)

Based on cross-paper evidence:

| Factor Component | US In-Sample alpha | Pre-sample ratio (P138, P140) | Asia Pacific adjustment (P142) | Korea Expected alpha |
|-----------------|-------------------|------------------------------|-------------------------------|---------------------|
| GP/A profitability | 0.52%/mo | 0.0% pre-sample (→ haircut ~50%) | ×1.3 (Asia Pacific boost) | ~0.30-0.35%/mo |
| CFOA | 0.55%/mo | robust (distress category) | ×1.3 | ~0.40-0.50%/mo |
| RMWcp | 0.24%/mo | ~0.17% pre-sample (×0.65) | ×1.3 | ~0.20-0.30%/mo |
| Safety (QMJ) | 0.61%/mo | distress/beta robust | ×1.0 | ~0.40-0.55%/mo |
| **QMJ composite** | **1.05%/mo** | mixed components | ×1.1 | **~0.60-0.80%/mo** |

**Conservative live Korea QMJ composite estimate: 0.50-0.65%/mo (net of conservative haircuts)**

---

## Implementation Warnings (Critical)

1. **Data snooping risk is HIGH** for GP/A standalone (P138: pre-sample t=-0.01). Industry-adjust and use only as one of 6+ sub-factors in composite, not standalone.

2. **CMA / asset growth should be EXCLUDED** from STR_013 (P140: near-zero pre-sample; P138: in-sample only). Do not use as primary signal.

3. **Y/B (earnings-to-book) is wrong profitability measure** for large-cap Korea (P143: big stock t=0.82). Use GP/A, CFOA, or OP instead.

4. **Monthly rebalancing** is beneficial but requires DART quarterly filing lag management (P137). Full monthly rebalancing only feasible if using quarterly 분기보고서 data with publication lag adjustment.

5. **Chaebol-specific issues**: Consolidated vs. standalone financials (연결 vs. 별도) materially affect all DART ratios. ALWAYS use 연결재무제표.

6. **BAB/Safety double counting**: If STR_011 already includes low-volatility / low-beta components, do NOT also run full QMJ Safety score — there will be high correlation and false diversification appearance.

---

## Portfolio Formation Calendar (Korea)

| Date | Action | Data Used | Source |
|------|--------|-----------|--------|
| March 31 | 사업보고서 filing deadline | FY t-1 annual fundamentals | DART |
| April 1 | Rebalance profitability scores | GP/A, OP, CFOA (annual) | DART |
| April 1 | Rebalance Safety (annual) | Leverage, Z-score, EVOL | DART |
| Monthly | Update Safety-BAB | Rolling beta to IKS200 | OHLCVS |
| May/Aug/Nov | Update ROE partial refresh | Q1/Q2/Q3 분기보고서 | DART |
| Feb-Apr | Seasonal upweight | Post-사업보고서 earnings update | Bouchaud P141 |

---

## Recommended Implementation Sequence for STR_013

**Phase 1 — Foundation (immediate):**
1. Implement GP/A (industry-adjusted) from DART annual → STR_GPA_base
2. Add CFOA from DART 현금흐름표 → STR_CFOA_base
3. Add Safety (BAB + leverage) from OHLCVS + DART → STR_Safety_base
4. Composite: Quality = z(GP/A + CFOA + Safety) → STR_013_v0

**Phase 2 — Enhancement:**
5. Switch to GP/ME (Asia Pacific calibration, Cakici P142)
6. Add RMWcp from FF2018 (P136) — cash profitability
7. Add ROA + ACC to profitability composite
8. Apply Bouchaud seasonal weighting (upweight April)

**Phase 3 — Full QMJ:**
9. Add Growth sub-score once 5yr DART history available (2021+)
10. Add full O-score / Z-score for Safety
11. Monthly ROE rebalancing via quarterly DART
12. Regime conditioning: QMJ × 1.5 in CRISIS, × 0.8 in BULL_EXPANSION

---

## Regime Conditioning Summary

| Regime | QMJ Weight Multiplier | Best Sub-Component | Source |
|--------|----------------------|-------------------|--------|
| CRISIS | 1.5× | Safety (flight to quality) | P135 |
| BEAR | 1.2× | Safety + Profitability | P135, P136 |
| NORMAL | 1.0× | Full composite | P135 |
| BULL_EXPANSION | 0.8× | Reduce (momentum dominates) | P135 |
| RECOVERY | 1.0-1.3× (RMWcp) | Cash profitability reprices | P136 |

---

## Factor Correlation Matrix (Expected for Korea)

| Factor | QMJ | HML | MOM | BAB | LowVol |
|--------|-----|-----|-----|-----|--------|
| QMJ | 1.00 | **-0.18** | +0.05 | **+0.45** | **+0.35** |
| HML | -0.18 | 1.00 | -0.22 | +0.12 | +0.08 |
| MOM | +0.05 | -0.22 | 1.00 | -0.03 | -0.15 |
| BAB | +0.45 | +0.12 | -0.03 | 1.00 | **+0.65** |
| LowVol | +0.35 | +0.08 | -0.15 | +0.65 | 1.00 |

**Critical:** QMJ negatively correlated with HML (-0.18) → excellent diversifier against value strategies.
**Warning:** QMJ and LowVol/BAB are highly correlated (+0.35, +0.45) → STR_011 (LowVol) and STR_013 (QMJ) will have significant overlap in Safety component.

---

## STR_013 vs. STR_011 Differentiation

| Aspect | STR_011 (LowVol+Macro) | STR_013 (QMJ) |
|--------|----------------------|---------------|
| Primary signal | Return volatility (OHLCVS) | Fundamental quality (DART) |
| Rebalancing | Monthly (volatility) | Annual fundamental + monthly BAB |
| Risk profile | Low beta, defensive | Defensive + fundamental quality |
| Overlap | BAB/Safety component | Safety component |
| Regime behavior | Defensive always | Conditional on quality pricing |
| Differentiation | Short-term risk signals | Long-term fundamental quality |

**Recommendation:** In ensemble (ensemble_engine.R), target correlation(STR_011, STR_013) < 0.50 by ensuring STR_013 uses Quality = Profitability + Growth as PRIMARY components and only 30% weight to Safety.
