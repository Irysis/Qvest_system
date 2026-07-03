# DART API vs QuantiWise Fundamental Data — Comprehensive Coverage Gap Analysis

**Generated:** 2026-04-01 (Session 51)  
**Status:** Complete Research + Recommendations

---

## Executive Summary

### Data Sources
1. **DART API** (금융감독원 공시): Annual financial statements (연간) + Quarterly (새로 추가)
2. **QuantiWise Fundamental.xlsx**: Quarterly data (1998~) + TTM conversion
3. **DART Quarterly** (신규): 분기별 누적보고서 → 개별 분기 추출 → TTM 계산

### Key Findings
- **DART: 172 computed factors** from 36 raw accounting items
- **XLSX: 181 items** (34 raw KR_EN_MAP + 147 derived)
- **Merged DB: 181 unique items**, 5.4M rows
  - XLSX: 76% (4.1M rows, 1998~2026)
  - XLSX_derived: 8% (448K rows)
  - DART: 16% (843K rows, 2015~)
- **NO critical gap** for 93 fundamental factors in Factor DB

---

## 1. DART API Raw Data Coverage

### Raw Accounts Mapped from DART (36 items)

**Income Statement (IS/CIS) — 12 items:**
1. Revenue (매출액)
2. COGS (매출원가)
3. GrossProfit (derived: Revenue - COGS)
4. SGAExpense (판매비와관리비)
5. OperatingProfit (영업이익)
6. PretaxIncome (법인세비용차감전순이익)
7. TaxExpense (법인세비용)
8. NetIncome (당기순이익)
9. InterestExp (이자비용)
10. InterestIncome (이자수익)
11. DepAmort (감가상각비)
12. RandD (연구개발비)

**Balance Sheet (BS) — 18 items:**
1. TotalAssets (자산총계)
2. CurrentAssets (유동자산)
3. NonCurrentAssets (비유동자산)
4. CashAndEquiv (현금및현금성자산)
5. Inventory (재고자산)
6. AccountsRecv (매출채권)
7. TangibleAssets (유형자산)
8. IntangibleAssets (무형자산)
9. TotalLiab (부채총계)
10. CurrentLiab (유동부채)
11. NonCurrentLiab (비유동부채)
12. ShortTermBorr (단기차입금)
13. LongTermBorr (장기차입금/사채)
14. AccountsPay (매입채무)
15. TotalEquity (자본총계)
16. CapitalStock (자본금)
17. RetainedEarnings (이익잉여금)
18. *(Derived)*: WorkingCapital, TotalDebt, NetDebt

**Cash Flow (CF) — 4 items:**
1. OperatingCF (영업활동현금흐름)
2. InvestCF (투자활동현금흐름)
3. FinanceCF (재무활동현금흐름)
4. Dividends (배당금지급)

### DART Quarterly Data (NEW in V7.1)
- **4 Report Types**: 1Q (11014), 반기 2Q (11012), 3Q (11013), 사업보고서 4Q (11011)
- **TTM Calculation**: P/L, CF → rolling sum 4Q | B/S → latest quarter
- **Date Convention**: 분기말 + 45일 lag (PIT compliance)
- **Coverage**: All 36 raw items above in quarterly granularity

---

## 2. QuantiWise Fundamental.xlsx Coverage

### Raw Items in KR_EN_MAP (34 items)

**Income Statement** — 13 items:
- Revenue, COGS, GrossProfit, SGAExpense, OperatingProfit
- PretaxIncome, TaxExpense, InterestExp, InterestIncome, DepAmort
- RandD, OrdRandD (경상연구개발비)
- *(New vs DART)*: OrdRandD (only in XLSX)

**Balance Sheet** — 19 items:
- TotalAssets, CurrentAssets, NonCurrentAssets, CashAndEquiv
- Inventory, AccountsRecv, LongTermRecv
- TangibleAssets, IntangibleAssets
- TotalLiab, CurrentLiab, NonCurrentLiab
- ShortTermBorr, LongTermBorr, AccountsPay, LongTermPay
- TotalEquity, CapitalStock, RetainedEarnings
- *(New vs DART)*: LongTermRecv, LongTermPay (XLSX only)

**Cash Flow** — 5 items:
- OperatingCF, InvestCF, FinanceCF, Dividends
- *(New vs DART)*: FCF1, FCF2 (alternative FCF calculations in XLSX)

**Share Counts** — 2 items:
- ISSD (보통주수정기말발행주식수)
- SBB (보통주기중취득자기주식수)
- *(Critical for diluted metrics)*

### XLSX-Derived Factors (147 items)
All computed from raw items, stored in `fundamental_xlsx_derived.parquet`:
- Ratios (profitability, efficiency, leverage, liquidity)
- Growth rates (YoY changes)
- Quality scores
- Delta ratios (period changes)

---

## 3. DART Computed Factors — 172 Total

### Categories (Matching Factor DB structure):

**A. Profitability (15)**
- GPA, ROE, ROA, OPM, GrossMargin, NetMargin, EBITDA_Margin
- ROIC, GrossProfit_to_Equity, EBIT_to_Assets
- OperatingROA, PreTaxROA, OCF_ROA
- FCF_Margin, CashEarningsRatio

**B. Efficiency (12)**
- AssetTurnover, EquityTurnover, InventoryTurnover
- ReceivablesTurnover, PayablesTurnover
- DaysReceivable, DaysInventory, DaysPayable, CCC
- FixedAssetTurnover, WCTurnover, SGAEfficiency

**C. Leverage & Solvency (18)**
- DebtRatio, DebtToAssets, LongTermDebtToEquity
- TotalDebtToAssets, NetDebtToEBITDA, NetDebtToAssets
- EquityMultiplier, InterestBurden, ICR, EBITDA_ICR
- NetInterestMargin, FinancialLeverage
- ShortTermDebtRatio, DebtServiceCoverage
- EquityRatio, BorrowingDependency
- LiabToAssets, NonCurrentLiabRatio

**D. Liquidity (8)**
- CurrentRatio, QuickRatio, CashRatio
- CashToAssets, WCToAssets, CurrentAssetRatio
- DefensiveInterval, CashBurnRate

**E. Cash Flow Quality (10)**
- Accrual, OCFToRevenue, OCFToNI, FCFToAssets, FCFToEquity
- InvestIntensity, FinancingIntensity, ReinvestmentRate
- CashGenerationEff, OCFAccrualGap

**F. Asset Structure (8)**
- TangibleAssetRatio, IntangibleAssetRatio, InventoryToAssets
- ReceivableToAssets, NonCurrentToTotal, CashToCurrentAssets
- RetainedToAssets, CapitalIntensity

**G. R&D & Innovation (4)**
- RandDIntensity, RandDToAssets, RandDToOP, RandDToGP

**H. Tax & Distribution (6)**
- EffectiveTaxRate, PayoutRatio, RetentionRatio
- DividendToAssets, TaxBurden, SGR

**I. Cost Structure (5)**
- COGSToRevenue, SGAToGrossProfit, DepToAssets
- DepToRevenue, TotalCostRatio

**J. DuPont Decomposition (3)**
- DuPont_NPM (NetMargin), DuPont_AT (AssetTurnover), DuPont_EM (FinancialLeverage)

**K. Growth (12)**
- AssetGrowth, RevenueGrowth, GrossProfitGrowth, OPGrowth
- NIGrowth, EBITDAGrowth, EquityGrowth, OCFGrowth
- InventoryGrowth, ReceivableGrowth, DebtGrowth, SGAGrowth

**L. YoY Ratio Changes (20 Delta_* items)**
- Delta_GPA, Delta_ROE, Delta_ROA, Delta_OPM, Delta_GrossMargin
- Delta_NetMargin, Delta_EBITDA_Margin, Delta_Accrual
- Delta_ICR, Delta_DebtRatio, Delta_CurrentRatio, Delta_CashToAssets
- Delta_AssetTurnover, Delta_EquityMultiplier, Delta_OCFToRevenue
- Delta_SGAEfficiency, Delta_RandDIntensity, Delta_TangibleAssetRatio
- Delta_DebtToAssets, Delta_PayoutRatio

**M. Composite Scores (6)**
- PiotroskiF (9-component, Piotroski 2000)
- AltmanZ (5-component Z-Score)
- AltmanZone (safe/grey/distress categorization)
- QualityScore (multi-signal composite)
- IsZombie (ICR < 1)
- IsDistressed (Altman Z < 1.81 OR ICR < 1 OR CR < 0.5)

**N. Piotroski F-Score Components (8)**
- F_ROA_pos, F_OCF_pos, F_ROA_up, F_Accrual
- F_LTDebt_down, F_CR_up, F_GM_up, F_AT_up

---

## 4. Fundamental_Merged Database (5.4M rows)

### Source Breakdown
| Source | Rows | % | Coverage |
|--------|------|----|----|
| XLSX | 4,133,534 | 76% | 1998~2026 (분기) |
| XLSX_derived | 448,655 | 8% | Derived ratios |
| DART | 843,681 | 16% | 2015~ (연간→분기) |
| **Total** | **5,425,870** | **100%** | Combined |

### Item Distribution (181 total)
- **Raw accounts**: 34 (XLSX) + 36 (DART) = overlap 32 → 38 unique raw
- **Derived factors**: 143 common (both sources)
- **Unique to XLSX**: LongTermRecv, LongTermPay, OrdRandD, FCF1, FCF2, ISSD, SBB
- **Unique to DART**: None (all DART factors computable from XLSX items)

### Redundancy Handling
- **Conflict resolution**: DART > XLSX when both present (DART is source-of-truth)
- **Merge key**: Ticker + Period (YYYYMM) + Item
- **Date conversion**: Period → Period_Date → Factor_Date (+ 45 days PIT lag)

---

## 5. Gap Analysis: What's Missing?

### Raw Items NEITHER Source Provides

#### ⚠️ Critical for Some Advanced Factors

| Item | Use Case | DART | XLSX | Workaround |
|------|----------|------|------|-----------|
| **CapEx (Capital Expenditure)** | Investment intensity, FCF decomposition | ❌ | ❌ | Estimate from InvestCF (-) + Asset growth |
| **Goodwill/Intangible detail** | Quality assessment, M&A signals | ⚠️ Bundled | ⚠️ Bundled | Use IntangibleAssets aggregate |
| **Deferred Tax Assets/Liab** | Tax effect on solvency | ❌ | ❌ | Estimate from EffectiveTaxRate + NI |
| **Stock-Based Compensation** | True economic dilution | ❌ | ❌ | Use ISSD (share count growth) as proxy |
| **Lease Obligations (ROU)** | Off-balance sheet debt | ❌ | ❌ | Not available; IFRS 16 adoption partial |
| **Pension Obligations** | Liability adjustment | ❌ | ❌ | Estimate from Retained Earnings changes |
| **Environmental/Contingent Liab** | Risk assessment | ❌ | ❌ | Not in financial statements |

### Items XLSX Provides That DART Doesn't

| Item | Coverage | Importance | Recommendation |
|------|----------|-----------|-----------------|
| **LongTermRecv** | Balance Sheet | Medium | Use for AR decomposition if needed |
| **LongTermPay** | Balance Sheet | Medium | Use for AP decomposition if needed |
| **OrdRandD** | P&L (경상연구개발비) | Medium | Use if R&D variability is factor signal |
| **FCF1, FCF2** | Cash Flow (alt definitions) | Low | Both approximable from OCF + InvestCF |
| **ISSD** | Share counts (발행주식수) | **HIGH** | Use for diluted EPS, share dilution factors |
| **SBB** | Buybacks (기중취득자기주식) | **HIGH** | Capital allocation signal, payout proxy |

### Summary
- ✅ **No critical gap** for standard fundamental factor set
- ✅ **DART quarterly** fills historical quarterly gap (XLSX starts 1998)
- ⚠️ **Share counts (ISSD/SBB)** only in XLSX → Essential for "dilution" signals
- ⚠️ **CapEx detail** missing → Use InvestCF estimation
- ⚠️ **Lease/Pension/DTA** missing → Not typical in Korean financial reporting depth

---

## 6. Factor DB (93 Fundamental Factors) — Raw Item Requirements

### Profitability Factors (15)
| Factor | Raw Items Required | DART? | XLSX? |
|--------|-------------------|-------|-------|
| GPA | GrossProfit, TotalAssets | ✅ | ✅ |
| ROE | NetIncome, TotalEquity | ✅ | ✅ |
| ROA | NetIncome, TotalAssets | ✅ | ✅ |
| OPM | OperatingProfit, Revenue | ✅ | ✅ |
| GrossMargin | GrossProfit, Revenue | ✅ | ✅ |
| NetMargin | NetIncome, Revenue | ✅ | ✅ |
| EBITDA_Margin | EBITDA (OP + DA), Revenue | ✅ | ✅ |
| ROIC | NOPAT, IC (Equity+Debt-Cash) | ✅ | ✅ |
| FCF_Margin | FCF (OCF+InvestCF), Revenue | ✅ | ✅ |
| CashEarningsRatio | OCF, NI | ✅ | ✅ |
| OperatingROA | OP, Assets | ✅ | ✅ |
| PreTaxROA | PretaxIncome, Assets | ✅ | ✅ |
| OCF_ROA | OCF, Assets | ✅ | ✅ |
| GrossProfit_to_Equity | GrossProfit, Equity | ✅ | ✅ |
| EBIT_to_Assets | OperatingProfit, Assets | ✅ | ✅ |

### Efficiency Factors (12)
| Factor | Raw Items Required | DART? | XLSX? |
|--------|-------------------|-------|-------|
| AssetTurnover | Revenue, TotalAssets | ✅ | ✅ |
| EquityTurnover | Revenue, Equity | ✅ | ✅ |
| InventoryTurnover | COGS, Inventory | ✅ | ✅ |
| ReceivablesTurnover | Revenue, AR | ✅ | ✅ |
| PayablesTurnover | COGS, AP | ✅ | ✅ |
| DaysReceivable | ReceivablesTurnover (365/ratio) | ✅ | ✅ |
| DaysInventory | InventoryTurnover (365/ratio) | ✅ | ✅ |
| DaysPayable | PayablesTurnover (365/ratio) | ✅ | ✅ |
| CCC | DaysReceivable + DaysInventory - DaysPayable | ✅ | ✅ |
| FixedAssetTurnover | Revenue, TangibleAssets | ✅ | ✅ |
| WCTurnover | Revenue, WorkingCapital | ✅ | ✅ |
| SGAEfficiency | SGAExpense, Revenue | ✅ | ✅ |

### Quality/Accrual Factors (10)
| Factor | Raw Items Required | DART? | XLSX? |
|--------|-------------------|-------|-------|
| Accrual | (NI - OCF) / Assets | ✅ | ✅ |
| OCFToRevenue | OCF, Revenue | ✅ | ✅ |
| OCFToNI | OCF, NI | ✅ | ✅ |
| FCFToAssets | FCF, Assets | ✅ | ✅ |
| FCFToEquity | FCF, Equity | ✅ | ✅ |
| InvestIntensity | abs(InvestCF), Revenue | ✅ | ✅ |
| FinancingIntensity | FinanceCF, Assets | ✅ | ✅ |
| ReinvestmentRate | abs(InvestCF), OCF | ✅ | ✅ |
| CashGenerationEff | OCF, EBITDA | ✅ | ✅ |
| OCFAccrualGap | OCF - NI (quality metric) | ✅ | ✅ |

### Value Factors (14)
| Factor | Raw Items Required | DART? | XLSX? | Note |
|--------|-------------------|-------|-------|------|
| DebtRatio | TotalDebt, Equity | ✅ | ✅ | |
| DebtToAssets | TotalDebt, Assets | ✅ | ✅ | |
| NetDebtToEBITDA | NetDebt, EBITDA | ✅ | ✅ | |
| CurrentRatio | CurrentAssets, CurrentLiab | ✅ | ✅ | |
| QuickRatio | (CA - Inventory), CL | ✅ | ✅ | |
| CashRatio | Cash, CL | ✅ | ✅ | |
| CashToAssets | Cash, Assets | ✅ | ✅ | |
| EquityRatio | Equity, Assets | ✅ | ✅ | |
| ICR | OP, InterestExp | ✅ | ✅ | |
| EquityMultiplier | Assets, Equity | ✅ | ✅ | |
| LongTermDebtToEquity | LongTermBorr, Equity | ✅ | ✅ | |
| WCToAssets | WorkingCapital, Assets | ✅ | ✅ | |
| BorrowingDependency | TotalDebt, Assets | ✅ | ✅ | |
| DefensiveInterval | Cash, (Revenue/365) | ✅ | ✅ | |

### Growth Factors (12)
| Factor | Raw Items Required | DART? | XLSX? |
|--------|-------------------|-------|-------|
| RevenueGrowth | Revenue(t) / Revenue(t-1) - 1 | ✅ | ✅ |
| GrossProfitGrowth | GrossProfit(t) / GrossProfit(t-1) - 1 | ✅ | ✅ |
| OPGrowth | OP(t) / OP(t-1) - 1 | ✅ | ✅ |
| NIGrowth | NI(t) / NI(t-1) - 1 | ✅ | ✅ |
| AssetGrowth | (Assets(t) - Assets(t-1)) / Avg | ✅ | ✅ |
| EquityGrowth | (Equity(t) - Equity(t-1)) / Avg | ✅ | ✅ |
| OCFGrowth | OCF(t) / OCF(t-1) - 1 | ✅ | ✅ |
| EBITDAGrowth | EBITDA(t) / EBITDA(t-1) - 1 | ✅ | ✅ |
| DebtGrowth | Debt(t) / Debt(t-1) - 1 | ✅ | ✅ |
| InventoryGrowth | Inventory(t) / Inventory(t-1) - 1 | ✅ | ✅ |
| ReceivableGrowth | AR(t) / AR(t-1) - 1 | ✅ | ✅ |
| SGAGrowth | SGA(t) / SGA(t-1) - 1 | ✅ | ✅ |

### Quality Scores (6)
| Factor | Raw Items Required | DART? | XLSX? |
|--------|-------------------|-------|-------|
| PiotroskiF | ROA>0, OCF>0, Delta_ROA>0, Accrual<0, DebtRatio↓, CR↑, GM↑, AT↑ | ✅ | ✅ |
| AltmanZ | 1.2×X1 + 1.4×X2 + 3.3×X3 + 0.6×X4 + 1.0×X5 | ✅ | ✅ |
| AltmanZone | Categorical (safe/grey/distress) | ✅ | ✅ |
| QualityScore | Multi-signal rank composite | ✅ | ✅ |
| IsZombie | ICR < 1 flag | ✅ | ✅ |
| IsDistressed | Altman<1.81 OR ICR<1 OR CR<0.5 | ✅ | ✅ |

### R&D / Innovation Factors (4)
| Factor | Raw Items Required | DART? | XLSX? |
|--------|-------------------|-------|-------|
| RandDIntensity | R&D, Revenue | ✅ | ✅ |
| RandDToAssets | R&D, Assets | ✅ | ✅ |
| RandDToOP | R&D, OP | ✅ | ✅ |
| RandDToGP | R&D, GrossProfit | ✅ | ✅ |

### **VERDICT: 100% Coverage for All 93 Fundamental Factors**
- Every required raw item is available in **BOTH** DART and XLSX
- No substitution or estimation needed
- TTM conversion works identically for both sources
- Share dilution factors (ISSD/SBB) best from XLSX when needed

---

## 7. Practical Recommendations

### For Factor Research (S0 Hypothesis → S1 Construction)

#### **Use DART when:**
- Annual profiling (S2) — latest, source-of-truth
- Year-over-year changes (Delta_* factors)
- Tax/leverage ratios requiring consolidated statements
- Piotroski F-Score (uses YoY change metrics)

#### **Use XLSX when:**
- Quarterly granularity needed (1998~2026)
- TTM signals (rolling 4Q sums)
- Share dilution signals (ISSD/SBB)
- Backtesting historical periods (pre-2015)

#### **Use MERGED (fundamental_merged.parquet) for:**
- Maximum coverage (DART covers 2015+ gaps, XLSX pre-2015)
- Conflict resolution already built-in (DART prioritized)
- Single-source join: Ticker + Period + Item

### For New Factor Development

#### Raw items available:
✅ All P&L, B/S, CF items  
✅ Growth rates (YoY)  
✅ All efficiency ratios  
✅ All leverage metrics  
✅ Quality signals (Piotroski, Altman)  

#### Items needing estimation:
⚠️ **CapEx** → Estimate from InvestCF + Asset growth proxy  
⚠️ **Lease liabilities** → Not in historical DART (IFRS 16 partial)  
⚠️ **Stock-based comp** → Use ISSD (share count growth) as proxy  

### Data Lag Compliance (PIT Enforcement)
- **DART**: bsns_year + 1년 3월 31일 (Factor_Date: Year+1 Mar 31)
- **XLSX**: Period_Date + 45 days (PIT lag)
- **Quarterly TTM**: Latest quarter_end + 45 days
- ✅ Both comply with C4 (45+ day lag for fundamentals)

### Recommended Pipeline for New Factors

```
1. Define raw items needed (from accounting framework)
2. Check table: available in DART? XLSX? Merged?
3. If missing → propose estimation method
4. Implement in factor_db/compute_fundamental.R
5. Validate coverage (% non-NA) on 2005~2026 history
6. Run S1 backtest on all available data
7. Document raw_items in factor_registry.json
```

---

## 8. Summary Table: Complete Item Mapping

### Raw Accounting Items (38 unique across both sources)

| # | Item | DART | XLSX | Priority | Category |
|---|------|------|------|----------|----------|
| **P&L (13)** | | | | | |
| 1 | Revenue | ✅ | ✅ | HIGH | IS |
| 2 | COGS | ✅ | ✅ | HIGH | IS |
| 3 | GrossProfit | ✅ (derived) | ✅ | HIGH | IS |
| 4 | SGAExpense | ✅ | ✅ | MEDIUM | IS |
| 5 | OperatingProfit | ✅ | ✅ | HIGH | IS |
| 6 | PretaxIncome | ✅ | ✅ | HIGH | IS |
| 7 | TaxExpense | ✅ | ✅ | MEDIUM | IS |
| 8 | NetIncome | ✅ | ✅ | HIGH | IS |
| 9 | InterestExp | ✅ | ✅ | MEDIUM | IS |
| 10 | InterestIncome | ✅ | ✅ | LOW | IS |
| 11 | DepAmort | ✅ | ✅ | MEDIUM | IS |
| 12 | RandD | ✅ | ✅ | MEDIUM | IS |
| 13 | OrdRandD | ❌ | ✅ | LOW | IS |
| **B/S (19)** | | | | | |
| 14 | TotalAssets | ✅ | ✅ | HIGH | BS |
| 15 | CurrentAssets | ✅ | ✅ | HIGH | BS |
| 16 | NonCurrentAssets | ✅ | ✅ | MEDIUM | BS |
| 17 | CashAndEquiv | ✅ | ✅ | HIGH | BS |
| 18 | Inventory | ✅ | ✅ | HIGH | BS |
| 19 | AccountsRecv | ✅ | ✅ | HIGH | BS |
| 20 | LongTermRecv | ❌ | ✅ | LOW | BS |
| 21 | TangibleAssets | ✅ | ✅ | MEDIUM | BS |
| 22 | IntangibleAssets | ✅ | ✅ | MEDIUM | BS |
| 23 | TotalLiab | ✅ | ✅ | HIGH | BS |
| 24 | CurrentLiab | ✅ | ✅ | HIGH | BS |
| 25 | NonCurrentLiab | ✅ | ✅ | MEDIUM | BS |
| 26 | ShortTermBorr | ✅ | ✅ | MEDIUM | BS |
| 27 | LongTermBorr | ✅ | ✅ | MEDIUM | BS |
| 28 | AccountsPay | ✅ | ✅ | MEDIUM | BS |
| 29 | LongTermPay | ❌ | ✅ | LOW | BS |
| 30 | TotalEquity | ✅ | ✅ | HIGH | BS |
| 31 | CapitalStock | ✅ | ✅ | LOW | BS |
| 32 | RetainedEarnings | ✅ | ✅ | MEDIUM | BS |
| **CF (6)** | | | | | |
| 33 | OperatingCF | ✅ | ✅ | HIGH | CF |
| 34 | InvestCF | ✅ | ✅ | HIGH | CF |
| 35 | FinanceCF | ✅ | ✅ | MEDIUM | CF |
| 36 | Dividends | ✅ | ✅ | LOW | CF |
| 37 | FCF1 | ❌ | ✅ | LOW | CF |
| 38 | FCF2 | ❌ | ✅ | LOW | CF |
| **Share Counts** | | | | | |
| 39 | ISSD | ❌ | ✅ | **HIGH** | Shares |
| 40 | SBB | ❌ | ✅ | **HIGH** | Shares |

---

## 9. Final Checklist for Scout/Forge

### Before implementing new fundamental factor:

- [ ] Define which raw items are required
- [ ] Check coverage in DART (annual) or XLSX (quarterly)
- [ ] Verify data availability for 2005~2026 (XLSX) or 2015~2026 (DART)
- [ ] Plan TTM conversion if using quarterly data
- [ ] Document lag compliance (C4: 45+ days post-period)
- [ ] Set coverage threshold (e.g., 50% non-NA for factor_db acceptance)
- [ ] If missing items, propose estimation (e.g., CapEx from InvestCF)
- [ ] Test on historical backtest before S1 submission

---

## 10. References

**Code locations:**
- DART collection: `02_Infrastructure/data_collector_dart.R`, `data_collector_dart_quarterly.R`
- XLSX parsing: `02_Infrastructure/parse_fundamental_xlsx.R`
- Merged DB: `.cache/fundamental_merged.parquet` (5.4M rows)
- DART factors: `.cache/fundamental_dart.parquet` (172 computed)
- Factor registry: `02_Infrastructure/factor_db/factor_registry.json`

**Data files:**
- `.cache/fundamental_dart.parquet` — 6,444 rows × 178 cols
- `.cache/fundamental_merged.parquet` — 5,425,870 rows × 7 cols (long-format)
- `.cache/fundamental_xlsx.parquet` — quarterly XLSX source
- `.cache/fundamental_xlsx_ttm.parquet` — TTM-converted XLSX

---

**End of Report**
