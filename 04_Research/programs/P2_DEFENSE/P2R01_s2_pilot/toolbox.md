# 처방 도구 상자 — 셀 사양 축 어휘 (v10.01 · 처방 루프 v0)

> 처방의 **구현**은 아래 축의 값만 바꿀 수 있다(셀 사양 delta). 바꾸지 않은 축은 기저 그대로다. 설명문 안의 숫자는 가렸다(<stat>) — 과거 측정 수치는 처방 입력이 아니다.

## 0. 바꿀 수 없는 것 (고정 축 · 헌법)
- 롱온리(w ≥ 0) · 보유 ≤ 25종 · 측정 유니버스 K200∪KQ150(시점별 멤버십) · 비용 15bps · 유동성 하한(20일 평균 거래대금 t-1) · 시그널 = 월말(리밸은 월간 이하 빈도로만 바꿀 수 있다) · 집행 close_t1 · 기저 신호(논문 엔진)와 그 가중(base_weight) · PIT C1~C15
- 노출 축소(현금)는 오버레이 층으로만 생긴다(Σw ≤ 1). 다른 축은 Σw = 1 이다.

## 1. factors — 기저 신호에 결합할 팩터 목록(0개 이상 · 팩터 DB id)
- 형식: `"factors": [{"kind": "db", "id": "<팩터 id>"}, ...]` · 빈 목록 = 논문 신호만.
- 결합: 기저 신호 가중 고정 · 나머지를 팩터들이 나눈다. 팩터 값 = 팩터 DB 의 정렬 z-점수(방향 정렬 · PIT 적재).

| id | 이름 | 범주 | 방향 | 정의 |
|---|---|---|---|---|
| V01_BM | Book-to-Market | value | higher_better | TotalEquity / MarketCap. Ratio of book value to market capitalization. |
| V02_EP | Earnings-to-Price | value | higher_better | NetIncome / MarketCap. Earnings yield metric. |
| V03_CFP | Cash Flow-to-Price | value | higher_better | OperatingCF / MarketCap. Operating cash flow yield. |
| V04_fPER | Forward PER | value | lower_better | Close / consensus eps_1y. Forward price-to-earnings ratio. |
| V05_fPBR | Forward PBR | value | lower_better | Close / consensus bps_1y. Forward price-to-book ratio. |
| V06_fDY | Forward Dividend Yield | value | higher_better | consensus dps_1y / Close. Forward dividend yield. |
| V07_EV_EBITDA | EV/EBITDA | value | lower_better | (MarketCap + TotalDebt - Cash) / EBITDA. Enterprise value to earnings multiple. |
| V08_PSR | Price-to-Sales | value | lower_better | MarketCap / Revenue. Price relative to revenue. |
| V09_PEG | PEG Ratio | value | lower_better | fPER / (EPS growth * 100). Price-to-earnings-to-growth. |
| V10_FCF_Yield | Free Cash Flow Yield | value | higher_better | (OperatingCF - CapEx) / MarketCap. FCF relative to market value. |
| V11_Shareholder_Yield | Shareholder Yield | value | higher_better | Dividends / MarketCap. Cash returned to shareholders as % of market cap. |
| V12_Composite_Value | Composite Value Score | value | higher_better | mean(z(-fPER) + z(-fPBR) + z(fDY) + z(CFP)). Composite value signal. |
| V13_EV_Sales | EV/Sales | value | lower_better | EV / Revenue. Enterprise value to revenue ratio. |
| V14_EBIT_EV | V14_EBIT_EV | value | higher_better | OperatingProfit / EV. Greenblatt Magic Formula component. |
| V15_NetDebt_Adj_EP | Net Debt-Adjusted Earnings Yield | value | higher_better | (NetIncome + InterestExp) / (MarketCap + NetDebt). Capital structure neutral earnings yield. |
| V16_Tobins_Q | Tobin's Q | value | lower_better | (MarketCap + TotalLiab) / TotalAssets. Market-to-replacement cost ratio. |
| V17_Payout_Ratio | Dividend Payout Ratio | value | higher_better | Dividends / NetIncome. % of earnings paid out to shareholders. |
| V18_AM | Total Assets to Market | value | higher_better | TotalAssets / MarketCap. Fama-French alternative value measure. |
| V19_Debt_to_Market | Debt-to-Market | value | higher_better | TotalDebt / MarketCap. Leverage metric (Bhandari 1988). |
| V20_SP | Sales-to-Price | value | higher_better | Revenue / MarketCap. Inverse of PSR, Barbee et al. (1996). |
| V21_Composite_Equity_Issuance | Net Equity Issuance | value | lower_better | log(ME_t / ME_5y) - log(1 + R_5y). 5-year equity issuance proxy. |
| V22_FCFF_EV | Free Cash Flow to Firm Yield | value | higher_better | (OperatingCF - CapEx) / EV. Capital structure neutral FCF yield. |
| V23_RAFI_Weight | Fundamental Index Weight | value | higher_better | Mean of (Revenue/sum + OCF/sum + BV/sum + Dividends/sum). RAFI weighting proxy. |
| V24_Residual_Income | Residual Income Yield | value | higher_better | (NetIncome - Equity * CoE) / MarketCap. RI model variant. |
| M01_Mom_12_1 | 12-1 Month Momentum | momentum | higher_better | 252-day cumulative return with 1-month skip. Classic 12-1 momentum signal. |
| M02_Mom_6_1 | 6-1 Month Momentum | momentum | higher_better | 126-day cumulative return with 1-month skip. 6-month momentum. |
| M03_Mom_3_1 | 3-1 Month Momentum | momentum | higher_better | 63-day cumulative return with 1-month skip. 3-month momentum. |
| M04_Mom_1 | 1-Month Momentum | momentum | higher_better | Last 21-day cumulative return. Short-term momentum. |
| M05_Trended_Mom | Trend Momentum | momentum | higher_better | log-price 252-day slope × 252. Linear trend strength. |
| M06_High_52w | 52-Week High Ratio | momentum | higher_better | Close / 52-week high. Distance from peak. |
| M07_IndMom | Industry Momentum | momentum | higher_better | Sector 12-1 month momentum. Industry-level 12-1 return signal. |
| M08_Residual_Mom | Residual Momentum | momentum | higher_better | CAPM residual 252-day cumulative return with 1-month skip. Idiosyncratic momentum. |
| M09_Composite_Mom | Composite Momentum v1 | momentum | higher_better | mean(z(M01) + z(M02) + z(M05)). 3-component momentum composite. |
| M10_Intermediate_Mom | Intermediate Momentum | momentum | higher_better | 252-147 day cumulative return (months 12-7). Novy-Marx (2012) intermediate momentum. |
| M11_ST_Reversal | Short-Term Reversal | momentum | lower_better | Last 5 trading days cumulative return. Weekly reversal signal. |
| M12_LR_Reversal | Long-Run Reversal | momentum | lower_better | 60m-13m cumulative return (1260-273 days). Multi-year reversal. |
| M13_VolAdj_Mom | Volatility-Adjusted Momentum | momentum | higher_better | Mom_12_1 / realized vol. Risk-adjusted momentum. |
| M14_RiskAdj_Mom | Risk-Adjusted Momentum | momentum | higher_better | (mean daily return / sd) * sqrt(252). Sharpe-like momentum ratio. |
| M15_Mom_3 | 3-Month Momentum (No Skip) | momentum | higher_better | Last 63 days cumulative return without skip. Pure 3-month return. |
| M16_Trend_Factor | Multiple MA Trend Signal | momentum | higher_better | Aggregated MA(3,5,10,20,50,100,200) crossover signals. Han et al. (2016) trend. |
| M17_Low_52w | 52-Week Low Ratio | momentum | higher_better | Close / 52-week low. Distance from trough. |
| M18_RSI | RSI(14) | momentum | higher_better | 14-day Relative Strength Index. Overbought/oversold indicator. |
| M19_MACD | MACD Signal | momentum | higher_better | (EMA12 - EMA26) / EMA26. MACD momentum signal. |
| M20_Keller_Mom | Keller Momentum Score | momentum | higher_better | 12*r1m + 4*r3m + 2*r6m + r12m. Weighted multi-period momentum. |
| M21_Seasonality | Return Seasonality | momentum | higher_better | Mean return in same calendar month (excl. last 252d), scaled monthly. Calendar effect. |
| M22_Max_Return | Maximum Daily Return | momentum | lower_better | Max single-day return in past month. Bali et al. (2011) lottery-like payoff. |
| M23_Acceleration | Momentum Acceleration | momentum | higher_better | Mom_6_1(now) - Mom_6_1(63d ago). Momentum second derivative. |
| M24_Sector_Rel_Mom | Sector-Relative Momentum | momentum | higher_better | M01 - sector average M01. Relative momentum within sector. |
| M25_Earnings_Mom_Streak | Earnings Momentum Streak | momentum | higher_better | Consecutive positive SUE observations (trailing). Earnings surprise persistence. |
| M26_Revenue_Mom | Revenue Momentum | momentum | higher_better | (revenue_fy1_now - revenue_fy1_63d) / /revenue_fy1_63d/. Consensus revenue change. |
| M27_Analyst_Rev_Mom | Analyst Revision Momentum | momentum | higher_better | eps_chg_1m. 1-month EPS revision (latest). |
| M28_OP_Rev_Mom | Operating Profit Revision Momentum | momentum | higher_better | (op_profit_fy1_now - op_profit_fy1_63d) / /op_profit_fy1_63d/. Operating profit consensus change. |
| M29_Mom_5d | 5-Day Momentum | momentum | higher_better | Last 5 trading days cumulative return. Micro momentum. |
| M30_Mom_10d | 10-Day Momentum | momentum | higher_better | Last 10 trading days cumulative return. Weekly-scale momentum. |
| M31_Breadth_Mom | Breadth Momentum | momentum | higher_better | Fraction of sectors with positive 6m momentum. Market breadth indicator. |
| M32_Composite_Mom_v2 | Composite Momentum v2 | momentum | higher_better | mean(z(M01) + z(M10) + z(M13) + z(M24) + z(M25)). 5-component momentum composite. |
| Q01_GPA | Gross Profit to Assets | quality | higher_better | GrossProfit / TotalAssets. Asset utilization efficiency. |
| Q02_ROE | Return on Equity | quality | higher_better | NetIncome / TotalEquity. Shareholder return efficiency. |
| Q03_ROA | Return on Assets | quality | higher_better | NetIncome / TotalAssets. Asset efficiency. |
| Q04_Piotroski_F | Piotroski F-Score | quality | higher_better | 9-point financial strength score based on profitability, leverage, liquidity, source of funds. |
| Q05_Accrual | Total Accrual Ratio | quality | lower_better | (dCA - dCash - dCL + dST_Debt - Depreciation) / TA. Working capital accruals. |
| Q06_Asset_Growth | Asset Growth | quality | higher_better | -(dTA / lag TA). Negate: low asset growth = conservative = better. |
| Q07_Earnings_Stability | Earnings Stability | quality | higher_better | 1 - sd(earnings changes over 5 years) / mean(/earnings changes/). Earnings consistency. |
| Q08_Composite_Quality | Composite Quality Score | quality | higher_better | Composite of GPA, ROE, ROA, Accrual signals. Multi-metric quality composite. |
| Q09_CFOA | Cash Flow from Operations to Assets | quality | higher_better | OperatingCF / TotalAssets. Cash-based profitability. |
| Q10_Gross_Margin | Gross Profit Margin | quality | higher_better | GrossProfit / Revenue. Pricing power indicator. |
| Q11_Net_Margin | Net Profit Margin | quality | higher_better | NetIncome / Revenue. Bottom-line profitability. |
| Q12_Asset_Turnover | Asset Turnover | quality | higher_better | Revenue / TotalAssets. Efficiency of asset use. |
| Q13_Fin_Leverage | Financial Leverage | quality | lower_better | TotalAssets / TotalEquity. Debt load relative to equity. |
| Q14_Current_Ratio | Current Ratio | quality | higher_better | CurrentAssets / CurrentLiab. Short-term liquidity. |
| Q15_Debt_to_Equity | Debt-to-Equity | quality | lower_better | TotalDebt / TotalEquity. Leverage ratio. |
| Q16_Debt_to_Assets | Debt-to-Assets | quality | lower_better | TotalDebt / TotalAssets. Debt burden relative to assets. |
| Q17_ROIC | Return on Invested Capital | quality | higher_better | NOPAT / (Equity + Debt - Cash). Return on total capital. |
| Q18_Op_Leverage | Operating Leverage | quality | lower_better | % change in Operating Income / % change in Revenue. Fixed cost impact. |
| Q19_Cash_to_Assets | Cash to Assets | quality | higher_better | CashAndEquiv / TotalAssets. Liquidity position. |
| Q20_Net_Equity_Issuance | Net Equity Issuance | quality | higher_better | -(dShares / lag Shares). Negate: buyback = positive. |
| Q23_Sustainable_Growth | Sustainable Growth Rate | quality | higher_better | ROE * (1 - Dividend Payout Ratio). Internal growth potential. |
| Q24_Altman_Z | Altman Z-Score | quality | higher_better | <stat>*WC_TA + <stat>*RE_TA + <stat>*EBIT_TA + <stat>*ME_TL + <stat>*Sales_TA. Bankruptcy risk. |
| Q25_Ohlson_O | Ohlson O-Score | quality | lower_better | Logit bankruptcy model using financials. Failure probability. |
| Q26_RnD_Intensity | R&D Intensity | quality | higher_better | RnDExpense / Revenue. Innovation investment. |
| Q27_CapEx_to_Rev | CapEx to Revenue | quality | higher_better | -InvestCF / Revenue. Capital intensity (negate). |
| Q28_Cash_Conversion | Cash Conversion Cycle | quality | lower_better | Days Inventory Outstanding + DSO - DPO. Working capital efficiency. |
| Q29_Inventory_Turnover | Inventory Turnover | quality | higher_better | COGS / Inventory. Inventory efficiency. |
| Q30_Receivables_Turnover | Receivables Turnover | quality | higher_better | Revenue / Receivables. Collection efficiency. |
| Q31_WC_to_Assets | Working Capital to Assets | quality | higher_better | (CurrentAssets - CurrentLiab) / TotalAssets. WC position. |
| Q32_Interest_Coverage | Interest Coverage | quality | higher_better | OperatingProfit / InterestExp. Debt service capacity. |
| Q33_Earnings_Persistence | Earnings Persistence | quality | higher_better | AR(1) coefficient of earnings series. Autocorrelation of earnings. |
| Q35_CashBased_OpProf | Cash-Based Operating Profitability | quality | higher_better | OperatingCF / Revenue. Cash profit margin. |
| D01_IdioVol | Idiosyncratic Volatility | defense | lower_better | Residual std from CAPM regression (252d). |
| D02_Beta | Market Beta | defense | lower_better | CAPM beta coefficient (252d rolling). Market sensitivity. |
| D03_RealVol | Realized Volatility | defense | lower_better | 252-day realized volatility of returns. Return standard deviation. |
| D04_Downside_Beta | Downside Beta | defense | lower_better | Beta estimated only on down market days (BM_Ret < 0). |
| D05_MaxRet | Maximum Return | defense | lower_better | Max single-day return in 252d. Lottery-like payoff. |
| D06_Upside_Beta | Upside Beta | defense | higher_better | Negate beta estimated only on up market days. Upside participation. |
| D07_Beta_Asymmetry | Beta Asymmetry | defense | lower_better | DownsideBeta - UpsideBeta. Asymmetry in market sensitivity. |
| D08_Tail_Beta | Tail Beta | defense | lower_better | Beta estimated on worst <stat> market returns. Crash sensitivity. |
| D09_Dimson_Beta | Dimson Beta | defense | lower_better | Adjusted beta for non-synchronous trading (lag + contemporaneous + lead). |
| D11_FP_Beta | Fama-Pierce Beta | defense | higher_better | Negate beta from Fama-Pierce methodology using book values. |
| D12_Beta_126d | 6-Month Beta | defense | lower_better | Beta estimated over 126-day window. Medium-term market sensitivity. |
| D13_Beta_63d | 3-Month Beta | defense | lower_better | Beta estimated over 63-day window. Short-term market sensitivity. |
| D14_Beta_Change | Beta Change | defense | lower_better | Change in beta (252d beta - 1y lag). Beta momentum. |
| D15_Cond_Bear_Beta | Conditional Bear Beta | defense | higher_better | Negate beta during market decline regime (dd > <stat>). |
| D16_Coskewness | Co-Skewness | defense | higher_better | Negate Ang-Chen-Xing co-skewness. Negative skewness = crash risk. |
| D17_Cokurtosis | Co-Kurtosis | defense | higher_better | Negate co-kurtosis. Higher co-kurt = extreme comovement = risky. |
| D19_EW_Beta_63 | Equal-Weighted Beta (63d) | defense | higher_better | Negate beta with equal-weighted market index (63d). |
| D20_EW_Beta_126 | Equal-Weighted Beta (126d) | defense | higher_better | Negate beta with equal-weighted market index (126d). |
| D21_CAPM_Alpha | CAPM Alpha | defense | higher_better | Intercept from CAPM regression. Risk-adjusted excess return. |
| D22_Tracking_Error | Tracking Error | defense | higher_better | Negate residual std from market-relative regression. |
| D23_Info_Ratio | Information Ratio | defense | higher_better | (mean residual) / (std residual). Risk-adjusted outperformance. |
| D24_Systematic_Risk_Prop | D24_Systematic_Risk_Prop | defense | lower_better | R-squared from CAPM. Proportion of systematic risk. |
| D25_Left_Tail_Beta | Left Tail Beta | defense | higher_better | Negate beta estimated on worst <stat> stock returns. |
| D26_Right_Tail_Beta | Right Tail Beta | defense | higher_better | Negate beta estimated on best <stat> stock returns. |
| D27_Beta_Stability | Beta Stability | defense | higher_better | Negate std dev of rolling 63d betas. Consistency of market sensitivity. |
| D28_Unlevered_Beta | Unlevered Beta | defense | higher_better | Negate asset beta adjusted for capital structure. |
| D29_Accounting_Beta | Accounting Beta | defense | higher_better | Negate beta from accounting fundamentals (EPS vs market). |
| D30_FM_Beta_21d | Factor Momentum Beta (21d) | defense | higher_better | Negate beta to 21d factor momentum. |
| D32_Beta_VIX | Beta to VIX | defense | higher_better | Beta with respect to VIX changes. Volatility sensitivity. |
| D33_Beta_Persistence | Beta Persistence | defense | higher_better | AR(1) of rolling betas. Stability of beta over time. |
| D34_RealVol_21d | 21-Day Volatility | defense | lower_better | 21-day realized volatility. Short-term vol. |
| D35_RealVol_63d | 63-Day Volatility | defense | lower_better | 63-day realized volatility. Medium-term vol. |
| D36_RealVol_126d | 126-Day Volatility | defense | lower_better | 126-day realized volatility. Long-term vol. |
| D37_Parkinson_Vol | Parkinson Volatility | defense | lower_better | Vol estimate using High-Low range. Range-based vol. |
| D38_GarmanKlass_Vol | Garman-Klass Volatility | defense | lower_better | Vol using OHLC prices. Efficient vol estimate. |
| D39_RogersSatchell_Vol | Rogers-Satchell Volatility | defense | lower_better | Vol using overnight-adjusted prices. Drift-robust vol. |
| D40_YangZhang_Vol | Yang-Zhang Volatility | defense | higher_better | Negate combined OHLC vol estimator. Best all-around vol. |
| D41_Vol_of_Vol | Volatility of Volatility | defense | higher_better | Negate std dev of rolling vols. Vol stability. |
| D42_EWMA_Vol | EWMA Volatility | defense | higher_better | Negate exponentially weighted vol (hl=21). Adaptive vol. |
| D43_Skewness | Return Skewness | defense | higher_better | Negate third moment of returns. Left-skew = risky. |
| D44_Kurtosis | Return Kurtosis | defense | higher_better | Negate fourth moment. Fat tails = risky. |
| D45_Downside_Dev | Downside Deviation | defense | higher_better | Negate std of negative returns. Downside risk. |
| D46_Sortino | Sortino Ratio | defense | higher_better | Mean return / downside deviation. Return per downside risk. |
| D47_CVaR_5pct | CVaR 5% | defense | higher_better | Negate average return in bottom <stat>. Tail risk measure. |
| D48_VaR_5pct | VaR 5% | defense | higher_better | Negate 5th percentile return. Value-at-Risk measure. |
| D49_VaR_1pct | VaR 1% | defense | higher_better | Negate 1st percentile return. Extreme tail risk. |
| D50_MaxDrawdown | Maximum Drawdown | defense | higher_better | Negate worst cumulative drawdown in lookback period. |
| D51_Ulcer_Index | Ulcer Index | defense | higher_better | Negate RMS of drawdowns. Prolonged drawdown impact. |
| D52_MinRet | Minimum Return | defense | higher_better | Minimum single-day return in 252d. Worst-day impact. |
| D53_Range_Vol | Range Volatility | defense | higher_better | Negate (High - Low) / Open. Intraday vol. |
| D54_Neg_Ret_Prop | Negative Return Proportion | defense | lower_better | Fraction of days with negative returns. Downside frequency. |
| D55_Vol_Trend | Volatility Trend | defense | lower_better | Increasing vol (1) if 21d vol > 252d vol else decreasing (-1). |
| D56_Up_Vol | Up-Day Volatility | defense | higher_better | Negate vol on positive return days. Volatility asymmetry. |
| D57_Down_Vol | Down-Day Volatility | defense | higher_better | Negate vol on negative return days. |
| D58_Vol_Asymmetry | Volatility Asymmetry | defense | higher_better | Negate (down-vol - up-vol). Vol clustering in down moves. |
| D60_Leverage | Financial Leverage | defense | higher_better | Negate (TotalDebt / TotalEquity). Leverage risk. |
| S01_Size | Size | size | higher_better | -log(MarketCap). Log negative market cap for size premium. |
| S02_Float_Size | Float Size | size | higher_better | -log(SharesOutstanding * Close). Log negative float value. |
| C01_SUE | Standardized Unexpected Earnings | consensus | higher_better | Standardized earnings surprise. (Actual - Forecast) / std. |
| C02_EPS_Chg_1m | 1-Month EPS Change | consensus | higher_better | 1-month EPS forecast revision. Consensus momentum. |
| C03_EPS_Chg_3m | 3-Month EPS Change | consensus | higher_better | 3-month EPS forecast revision. Medium-term momentum. |
| C04_ESBR | Earnings Sentiment Breadth Ratio | consensus | higher_better | % of analysts raising estimates. Revision direction. |
| C05_ESCR | Earnings Sentiment Consistency Ratio | consensus | higher_better | Consistency of revisions in same direction. |
| C06_TP_Gap | Target Price Gap | consensus | higher_better | (TargetPrice - Close) / Close. Analyst upside. |
| C07_TP_Mom | Target Price Momentum | consensus | higher_better | (TP_now - TP_35d) / TP_35d. Target price change over 35d. |
| C08_Coverage | Analyst Coverage | consensus | higher_better | Number of analysts covering the stock. Attention signal. |
| C09_Earnings_Surprise_Sq | Earnings Surprise Squared | consensus | higher_better | sign(sue) * sue^2. Amplified surprises. |
| C10_SUE_Persistence | SUE Persistence | consensus | higher_better | Average of last 4 SUE values. PEAD proxy. |
| C11_Earnings_Streak | Positive Earnings Streak | consensus | higher_better | Count of consecutive positive SUEs. Streak length. |
| C12_Estimate_Dispersion_Proxy | Estimate Dispersion (Proxy) | consensus | lower_better | /eps_chg_1m - eps_chg_3m/ / /eps_1y/. Forecast disagreement. |
| C13_Revision_Breadth_3m | Revision Breadth (3-Month) | consensus | higher_better | Average ESBR over last 3 observations. Recent revision sentiment. |
| C14_Revenue_Surprise | Revenue Surprise | consensus | higher_better | (rev_now - rev_63d) / /rev_63d/. Jegadeesh-Livnat (2006). |
| C15_Forecast_Error_Trend | Forecast Error Trend | consensus | higher_better | Latest SUE - 2nd latest SUE. SUE direction. |
| C16_EPS_Acceleration | EPS Acceleration | consensus | higher_better | eps_chg_1m - eps_chg_3m/3. Revision speed. |
| C17_OP_Revision | Operating Profit Revision | consensus | higher_better | (op_profit_now - op_profit_63d) / /op_profit_63d/. OP consensus change. |
| C18_Earnings_CAR_3d | Earnings Announcement CAR (3-day) | consensus | higher_better | 3-day cumulative abnormal return around earnings date. |
| C19_Composite_Earnings | Composite Earnings Factor | consensus | higher_better | mean(z(SUE) + z(ESBR) + z(EPS_chg_1m) + z(TP_Gap)). |
| L01_Amihud | Amihud Illiquidity | liquidity | lower_better | mean(/Ret/ / Volume). Illiquidity measure. |
| L02_Turnover | Turnover | liquidity | higher_better | mean(Volume / Shares Outstanding). Trading frequency. |
| L03_Volume_Mom | Volume Momentum | liquidity | higher_better | Recent volume / 252d avg volume. Volume trend. |
| L04_Bid_Ask_Proxy | Bid-Ask Spread Proxy | liquidity | higher_better | Negate estimated spread from High-Low range. |
| L05_Dollar_Volume | Dollar Volume | liquidity | higher_better | Volume * Close. Trading value. |
| L06_Zero_Trade_Days | Zero Trade Days | liquidity | lower_better | Fraction of days with zero trading volume. |
| L07_Zero_Return_Days | Zero Return Days | liquidity | lower_better | Fraction of days with zero price change. |
| L08_Roll_Spread | Roll Spread | liquidity | higher_better | Negate negative autocov(returns) based bid-ask estimate. |
| L09_Amihud_20d | Amihud Illiquidity (20-day) | liquidity | lower_better | 20-day Amihud illiquidity. Short-term liquidity. |
| L10_Amihud_Ratio | Amihud Ratio | liquidity | lower_better | Amihud_252d / Amihud_20d. Liquidity deterioration. |
| L11_Kyle_Lambda | Kyle Lambda | liquidity | lower_better | Price impact per unit of volume. Kyle (1985) microstructure. |
| L12_PS_Gamma | Roll Spread Gamma | liquidity | lower_better | Negative autocovariance proxy. Half-spread estimate. |
| L13_Vol_Variance_Ratio | Volume Variance Ratio | liquidity | lower_better | Var(volume 21d) / Var(volume 252d). Vol consistency. |
| L14_Price_Impact | Price Impact | liquidity | lower_better | Max abs(return) / volume. Vol-adjusted price impact. |
| L15_Turnover_252d | Turnover (252-day) | liquidity | higher_better | 252-day turnover ratio. Annual trading frequency. |
| L16_Turnover_Vol | Turnover Volatility | liquidity | lower_better | Std of daily turnover. Trading consistency. |
| L17_LOT_Measure | LIQ Measure | liquidity | lower_better | Lesmond Ogden Trzcinka (1999) effective spread proxy. |
| L18_Eff_Spread_Proxy | Effective Spread Proxy | liquidity | lower_better | High-Low midpoint spread estimate. |
| L19_Price_Delay | Price Delay | liquidity | higher_better | Negate 1-R^2(stock ret on lagged BM ret). Information speed. |
| L20_Trade_Frequency | Trade Frequency | liquidity | higher_better | Fraction of days with non-zero trading volume. |
| L21_Market_Depth | Market Depth | liquidity | higher_better | Volume / (High - Low). Depth per price range. |
| L22_Ret_Autocorr | Return Autocorrelation | liquidity | higher_better | Negate abs(AR(1) of daily returns). Mean reversion. |
| L23_Vol_Autocorr | Volume Autocorrelation | liquidity | higher_better | AR(1) of log volume. Trading persistence. |
| L24_Range_per_Vol | Range per Volume | liquidity | lower_better | (High - Low) / Volume. Price range efficiency. |
| L25_Amihud_Vol | Amihud-Volatility Adjusted | liquidity | lower_better | Amihud / realized vol. Vol-adjusted illiquidity. |
| L26_Log_MktCap | Log Market Cap | liquidity | higher_better | log(MarketCap). Size-based liquidity proxy. |
| L27_Price_Level | Price Level | liquidity | higher_better | log(Close). Absolute price level proxy. |
| L28_Vol_Mom_63d | Volume Momentum (63-day) | liquidity | higher_better | 63-day volume momentum. Medium-term trading trend. |
| L29_Illiq_Change | Illiquidity Change | liquidity | lower_better | (Amihud_now - Amihud_lag) / Amihud_lag. Liquidity deterioration. |
| L31_Vol_Concentration | Volume Concentration | liquidity | lower_better | Fraction of total 252d volume in top 20d. Trading concentration. |
| L32_Ret_Vol_Corr | Return-Volume Correlation | liquidity | higher_better | Correlation(returns, volume). |
| L33_AbsRet_Vol_Corr | Absolute Return-Volume Correlation | liquidity | higher_better | Correlation(/returns/, volume). |
| L34_Vol_Spike_Ratio | Volume Spike Ratio | liquidity | higher_better | Recent volume / rolling vol avg. Volume surge indicator. |
| L35_Reversal_Intensity | Reversal Intensity | liquidity | higher_better | -AR(1) of returns on high-volume days. Mean reversion strength. |
| L36_CLV_Stability | Close Location Value Stability | liquidity | lower_better | Std of CLV (where close falls in daily range). |
| L37_Relative_Vol | Relative Volume | liquidity | higher_better | Today's volume / 252d avg volume. Vol relative to average. |
| L38_DolVol_Mom | Dollar Volume Momentum | liquidity | higher_better | Recent dollar volume / 252d avg. Dollar trading trend. |
| L39_Overnight_Spread | Overnight Spread | liquidity | higher_better | Negate (Open - Close_prev) / Close_prev. Overnight gap. |
| L40_VWAP_Spread | VWAP Spread | liquidity | lower_better | Distance between Close and VWAP. Execution quality. |
| L41_Intraday_Vol_Proxy | Intraday Volatility Proxy | liquidity | lower_better | (High - Low) / Open. Daily range as vol proxy. |
| L42_Vol_Skewness | Volume Skewness | liquidity | lower_better | Skewness of daily volume distribution. |
| L43_Turnover_Change | Turnover Change | liquidity | higher_better | (Turnover_21d - Turnover_252d) / Turnover_252d. Turnover trend. |
| L44_Vol_Ret_Asymmetry | Volume-Return Asymmetry | liquidity | higher_better | Volume correlation differential (up vs down days). |
| L45_Composite_Liquidity | Composite Liquidity | liquidity | higher_better | Composite of multiple liquidity factors (PCA/mean z-scores). |
| AC01_Total_Accruals_CF | Total Accruals (CF Method) | accrual | lower_better | (dWC - dCash - dCL + dST - Depr) / TA. Working capital accruals. |
| AC02_Total_Accruals_BS | Total Accruals (BS Method) | accrual | lower_better | dWC / TA where WC = CA - CL. Balance sheet method. |
| AC03_WC_Accruals | Working Capital Accruals | accrual | lower_better | (dCA - dCash - dCL + dSTD) / TA. |
| AC04_NCO_Accruals | Non-Current Operating Accruals | accrual | lower_better | dNCA - dDepr / TA where NCA excl cash. |
| AC05_NOA | Net Operating Assets | accrual | lower_better | (OA - OCL) / lag TA. Operating asset intensity. |
| AC06_Comprehensive_Accruals | Comprehensive Accruals | accrual | lower_better | Mean of multiple accrual measures. |
| AC07_Operating_Accruals | Operating Accruals | accrual | lower_better | (Income - OCF) / TA. Accruals from operations. |
| AC08_Financial_Accruals | Financial Accruals | accrual | higher_better | dSTD + dLTD / TA. Financing side accruals. |
| AC09_NNI | Non-Operating Income Impact | accrual | lower_better | (NI - OI) / lag TA. Non-op earnings accruals. |
| AC10_Pct_Accruals | Percent Accruals | accrual | lower_better | Accruals / /NI/. Accrual intensity. |
| AC12_Inventory_Accruals | Inventory Accruals | accrual | lower_better | dInventory / TA. Inventory buildup. |
| AC13_Abnormal_Accruals | Abnormal Accruals | accrual | lower_better | Residual from accrual prediction model. |
| AC15_NonDiscretionary_Accruals | Non-Discretionary Accruals | accrual | lower_better | Jones model non-discretionary component. |
| AC16_BS_vs_CF_Diff | BS vs CF Accrual Difference | accrual | lower_better | Abs(AC02 - AC01). Method disagreement. |
| AC17_Accrual_Reversal | Accrual Reversal | accrual | higher_better | (Accrual_now - Accrual_lag) / /Accrual_lag/. Reversal speed. |
| AC19_Receivables_Accruals | Receivables Accruals | accrual | lower_better | dReceivables / TA. Receivable buildup. |
| AC20_Payables_Accruals | Payables Accruals | accrual | higher_better | dPayables / TA. Negative payables increase = good. |
| AC21_CF_to_Accrual_Ratio | CF to Accrual Ratio | accrual | higher_better | OCF / Accruals. Cash-to-accrual quality. |
| AC22_Accrual_Volatility | Accrual Volatility | accrual | lower_better | Std of historical accrual series. Consistency. |
| AC23_Accrual_Persistence | Accrual Persistence | accrual | lower_better | AR(1) of accrual series. |
| AC24_NOA_Growth | Net Operating Assets Growth | accrual | lower_better | dNOA / lag NOA. NOA growth rate. |
| AC25_Accrual_Size_Interaction | Accrual-Size Interaction | accrual | lower_better | Accruals * Size signal interaction. |
| R01_VaR_95 | Value-at-Risk 95% | risk | higher_better | Negate 5th percentile of returns. Tail risk at <stat> confidence. |
| R02_VaR_99 | Value-at-Risk 99% | risk | higher_better | Negate 1st percentile of returns. Extreme tail risk. |
| R03_CVaR_95 | Conditional VaR 95% | risk | higher_better | Negate mean of returns below 5th percentile. Expected shortfall. |
| R04_CVaR_99 | Conditional VaR 99% | risk | higher_better | Negate mean of returns below 1st percentile. Extreme tail expectation. |
| R05_Tail_Risk | Tail Risk Ratio | risk | higher_better | Negate abs(5th percentile / mean return). Tail severity. |
| R06_MDD | Maximum Drawdown | risk | higher_better | Negate abs(max drawdown from peak). |
| R07_Downside_Dev | Downside Deviation | risk | higher_better | Negate std of negative returns. |
| R08_Semi_Variance | Semi-Variance | risk | higher_better | Negate variance of negative returns. |
| R09_Coskewness | Co-Skewness | risk | higher_better | Co-skewness with market (Ang Chen Xing 2006). |
| R10_Cokurtosis | Co-Kurtosis | risk | higher_better | Negate co-kurtosis with market. |
| R11_Systematic_Risk | Systematic Risk (R-squared) | risk | higher_better | Negate R-squared from CAPM. |
| R12_Idiosyncratic_Risk | R12_Idiosyncratic_Risk | risk | higher_better | Negate idiosyncratic volatility from CAPM residuals. |
| R13_NCSKEW | Negative Coefficient of Skewness | risk | higher_better | Negate NCSKEW (Chen Hong Stein 2001 crash risk). |
| R14_DUVOL | Down-to-Up Volatility | risk | higher_better | Negate log(sd(down weeks) / sd(up weeks)). |
| R15_Sortino | Sortino Ratio | risk | higher_better | Mean return / downside deviation. Return per downside risk. |
| R16_Calmar | Calmar Ratio | risk | higher_better | Annualized return / abs(MDD). Return relative to max drawdown. |
| R17_Market_Leverage | Market Leverage | risk | higher_better | Negate (TotalDebt / MarketCap). Bhandari (1988). |
| R18_Book_Leverage | Book Leverage | risk | higher_better | Negate (TotalDebt / TotalAssets). Leverage on accounting basis. |
| R19_Composite_Risk | Composite Risk Score | risk | higher_better | mean(z(R01, R07, R13, R17)). Risk composite. |
| RE01_Mkt_EWMA_21d | Market Return EWMA (21-day) | regime | higher_better | EWMA(21) of benchmark returns. Market momentum. |
| RE02_Vol_Regime_Pctile | Volatility Regime Percentile | regime | higher_better | Negate percentile of market realized vol. Vol regime rank. |
| RE03_Mkt_Drawdown | Market Drawdown | regime | higher_better | Current drawdown from market peak. Market stress. |
| RE04_HighVol_Beta | High Volatility Regime Beta | regime | higher_better | Negate beta estimated on high-vol market days. |
| RE05_LowVol_Beta | Low Volatility Regime Beta | regime | higher_better | Negate beta estimated on low-vol market days. |
| RE06_Beta_Asymmetry | Regime Beta Asymmetry | regime | higher_better | HighVolBeta - LowVolBeta. Differential response. |
| RE07_Crisis_Beta | Crisis Beta | regime | higher_better | Negate beta estimated on market drawdown > <stat> days. |
| RE08_Down_Market_Excess | Down-Market Excess Return | regime | higher_better | Mean excess return on days when market is down. |
| RE09_Capture_Ratio | Up/Down Capture Ratio | regime | higher_better | Upside capture / downside capture. Asymmetric capture. |
| RE10_VIX_Pctile | VIX Percentile | regime | higher_better | Negate percentile of VIX. Volatility regime. |
| RE11_VIX_Change_EWMA | VIX Change EWMA | regime | higher_better | Negate EWMA of log VIX changes. VIX momentum. |
| RE12_VIX_Regime_3State | VIX Regime (3-State) | regime | higher_better | 1 if VIX <= q33, 0 if q33 < VIX <= q67, -1 if > q67. |
| RE13_Credit_Spread_Pctile | Credit Spread Percentile | regime | higher_better | Negate percentile of HY OAS. Credit stress. |
| RE14_Inflation_YoY | Inflation YoY | regime | higher_better | Negate year-over-year CPI inflation. Macro headwind. |
| RE15_Market_Breadth_21d | Market Breadth (21-day) | regime | higher_better | Fraction of stocks with positive returns (21d). Breadth indicator. |
| RE16_Canary_Signal | Canary Momentum Signal | regime | higher_better | S&P 500 momentum proxy (-1 if down, 1 if up). Defensive signal. |
| MA01_GDP_Sensitivity | GDP Sensitivity | regime | higher_better | Beta to industrial production / GDP growth. Cycle sensitivity. |
| MA02_CPI_Sensitivity | CPI Sensitivity | regime | lower_better | Beta to inflation (CPI change). Inflation sensitivity. |
| MA03_Rate_Sensitivity | Interest Rate Sensitivity | regime | lower_better | Beta to 10Y Treasury yield changes. Rate sensitivity. |
| MA04_YieldCurve_Sensitivity | Yield Curve Sensitivity | regime | higher_better | Beta to 10Y-2Y spread changes. |
| MA05_MonetaryPolicy_Mom | Monetary Policy Momentum | regime | higher_better | Negate 1Y change in 2Y yield. Tightening signal. |
| MA06_Risk_Sentiment_1Y | Risk Sentiment (1-Year) | regime | higher_better | 1Y market cumulative return. Risk appetite proxy. |
| MA07_BusinessCycle_Composite | Business Cycle Composite | regime | higher_better | <stat> * GDP growth - <stat> * inflation. Cycle signal. |
| CR01_Sector_Comovement | Sector Comovement | crowding | higher_better | Negate correlation with sector return. Higher comove = crowded. |
| CR02_Volume_Concentration | Volume Concentration | crowding | higher_better | Negate (20d avg vol / 252d avg vol). Volume surge = crowding. |
| CR03_Herding_Dispersion | Herding Dispersion | crowding | higher_better | Cross-sectional std of returns (21d). Dispersion = less herding. |
| CR04_Ownership_Concentration | Ownership Concentration Proxy | crowding | higher_better | 20d avg turnover. Low turnover = concentrated. |
| CR05_Short_Pressure_Proxy | Short Pressure Proxy | crowding | higher_better | Negate (Amihud_down / Amihud_up). Higher on down days = short pressure. |
| CR06_DTC_Proxy | Days to Cover Proxy | crowding | higher_better | Negate (EstShares / 20d avg volume). Low DTC = liquid. |
| CR07_Momentum_Crowding | Momentum Crowding | crowding | higher_better | Negate correlation with top quintile momentum portfolio. |
| CR08_Volume_Price_Divergence | Volume-Price Divergence | crowding | higher_better | Negate abs(price trend * vol trend sign). Divergence = negative. |
| CR09_Money_Flow_Ratio | Money Flow Ratio | crowding | higher_better | (UpVolume - DownVolume) / TotalVolume. Smart money proxy. |
| CR10_Convergence_Premium | Convergence (Mean Reversion) Premium | crowding | higher_better | Negate AR(1) of returns. Mean-reversion = convergence. |
| CR11_Idiosyncratic_Return | Idiosyncratic Return | crowding | higher_better | 1 - R-squared from CAPM. Unique returns = less crowded. |
| SE01_Consensus_Dispersion | Consensus Dispersion | crowding | higher_better | Negate analyst forecast std / mean. Disagreement = uncertainty. |
| SE01_Volatility_Uncertainty | Volatility Uncertainty (Fallback) | crowding | higher_better | Negate 21-day realized volatility (when consensus unavailable). |
| SE02_Consensus_Revision | Consensus Revision | crowding | higher_better | (EPS_now - EPS_prev) / /EPS_prev/. Recent estimate change. |
| TR01_ADX_Proxy | ADX (Average Directional Index) | crowding | higher_better | Wilder's ADX from +DI/-DI. Trend strength. |
| TR02_Trend_Consistency | Trend Consistency | crowding | higher_better | abs(% positive returns - <stat>) * 2. Consistency of direction. |
| GR01_Revenue_Growth | Revenue Growth | growth | higher_better | (Revenue_now - Revenue_1y) / /Revenue_1y/. YoY revenue growth. |
| GR02_Earnings_Growth | Earnings Growth | growth | higher_better | (NI_now - NI_1y) / /NI_1y/. YoY earnings growth. |
| GR03_Asset_Growth | Asset Growth | growth | higher_better | Negate (dTA / lag TA). Cooper Gulen Schill (2008). |
| GR04_GPA_Growth | Gross Profit Assets Growth | growth | higher_better | 5Y growth in GrossProfit / Assets. |
| GR05_ROE_Growth | ROE Growth | growth | higher_better | 5Y growth in NetIncome / Equity. |
| GR06_OCF_Growth | Operating Cash Flow Growth | growth | higher_better | (OCF_now - OCF_1y) / /OCF_1y/. YoY OCF growth. |
| GR07_Composite_Growth | Composite Growth Score | growth | higher_better | mean(z(GR01..GR06)). Multi-metric growth composite. |
| IN01_CapEx_to_Assets | CapEx to Assets | growth | higher_better | InvestCF / TotalAssets (negative = capex). Titman Wei Xie (2004). |
| IN02_CapEx_to_Revenue | CapEx to Revenue | growth | higher_better | InvestCF / Revenue. Capital intensity ratio. |
| IN03_RD_to_Market | R&D to Market | growth | higher_better | RnDExpense / MarketCap. R&D intensity. |
| IN04_Net_Equity_Issuance | Net Equity Issuance | growth | higher_better | Negate (dShares / lag Shares). Bradshaw Richardson Sloan (2006). |
| IN05_Net_Debt_Issuance | Net Debt Issuance | growth | higher_better | Negate (dDebt / TA). Deleveraging = positive. |
| IN06_Investment_to_Assets | Investment to Assets | growth | higher_better | Negate (dPPE + dInv) / lag TA. Low investment = better. |
| MK01_CAPM_Beta | CAPM Beta | growth | lower_better | Beta from CAPM regression (252d). Market sensitivity. |
| XF_DU01_NetMargin | DuPont Net Margin | quality | higher_better | (PretaxIncome - TaxExpense) / Revenue. DuPont profitability component. |
| XF_DU02_AssetTurnover | DuPont Asset Turnover | quality | higher_better | Revenue / TotalAssets. DuPont efficiency component. |
| XF_DU03_EquityMultiplier | DuPont Equity Multiplier | leverage | lower_better | TotalAssets / TotalEquity. DuPont leverage component. |
| XF_LL01_DebtToCapital | Debt to Capital | leverage | lower_better | (ShortTermBorr+LongTermBorr) / (TotalEquity+ShortTermBorr+LongTermBorr). Capital structure leverage. |
| XF_LL02_NetDebt | Net Debt | leverage | lower_better | (ShortTermBorr+LongTermBorr) - CashAndEquiv. Raw net debt, cross-sectionally normalized. |
| XF_LL03_CashRatio | Cash Ratio | leverage | higher_better | CashAndEquiv / CurrentLiab. Most conservative liquidity measure. |
| XF_LL04_QuickRatio | Quick Ratio | leverage | higher_better | (CurrentAssets - Inventory) / CurrentLiab. Acid-test liquidity. |
| XF_LL05_WorkingCapital | Working Capital Ratio | leverage | higher_better | (CurrentAssets - CurrentLiab) / TotalAssets. Net working capital scaled by assets. |
| XF_PR01_EBITDA_Margin | EBITDA Margin | quality | higher_better | (OperatingProfit + DepAmort) / Revenue. Cash-oriented profitability margin. |
| XF_PR02_RetainedEarnings_Ratio | Retained Earnings Ratio | quality | higher_better | RetainedEarnings / TotalEquity. Internal funding capacity. |
| XF_PR03_TaxRate | Effective Tax Rate | quality | lower_better | TaxExpense / PretaxIncome. Effective tax burden (PretaxIncome > 0 only). |
| XF_PR04_NetInterestMargin | Net Interest Margin | quality | higher_better | NetInterestExp / TotalAssets. Interest income efficiency (relevant for financials). |
| XF_PR05_EBITDA_to_Assets | EBITDA to Assets | quality | higher_better | (OperatingProfit + DepAmort) / TotalAssets. Asset-level cash profitability. |
| XF_EF01_InventoryTurnover | Inventory Turnover | quality | higher_better | COGS / Inventory. Inventory management efficiency. |
| XF_EF02_DaysPayable | Days Payable Outstanding | quality | higher_better | AccountsPay / (COGS / 365). Days to pay suppliers. |
| XF_EF03_DaysReceivable | Days Receivable Outstanding | quality | lower_better | AccountsRecv / (Revenue / 365). Days to collect from customers. |
| XF_EF04_CCC | Cash Conversion Cycle | quality | lower_better | DaysReceivable + DaysInventory - DaysPayable. Working capital cycle length in days. |
| XF_GD01_GrossProfit_Growth | Gross Profit Growth | growth | higher_better | dGrossProfit / /GrossProfit_prev/. Top-line margin growth. |
| XF_GD02_OpProfit_Growth | Operating Profit Growth | growth | higher_better | dOperatingProfit / /OperatingProfit_prev/. Core earnings growth. |
| XF_GD03_OCF_Growth | Operating Cash Flow Growth | growth | higher_better | dOperatingCF / /OperatingCF_prev/. Cash flow momentum. |
| XF_GD04_Dividend_Growth | Dividend Growth | growth | higher_better | dDividends / /Dividends_prev/. Shareholder payout momentum. |
| XF_RI01_RnD_to_Revenue | R&D to Revenue | quality | higher_better | RandD / Revenue. Research intensity, innovation proxy. |
| XF_RI02_CapEx_proxy | CapEx Proxy | quality | higher_better | -InvestCF / TotalAssets. Capital expenditure intensity (InvestCF is negative for spending). |
| XF_RI03_SGA_to_Revenue | SGA to Revenue | quality | lower_better | SGAExpense / Revenue. Selling, general, and admin cost efficiency. |
| INV13_Foreign_Resid_Individual_21d | Foreign Flow Residualized on Individual Flow (21d) | investor_flow | higher_better | residual_t(i) = z_F_t(i) - beta_t * z_I_t(i). z_F: 21d foreign net buy z-score. z_I: 21d individual net buy z-score. beta_t: expanding-window no-intercept OLS ( |
| INV13_Foreign_Resid_Individual_63d | Foreign Flow Residualized on Individual Flow (63d) | investor_flow | higher_better | residual_t(i) = z_F_t(i) - beta_t * z_I_t(i). z_F: 63d foreign net buy z-score. z_I: 63d individual net buy z-score. beta_t: expanding-window no-intercept OLS ( |
| INV13_Foreign_Resid_Individual_126d | Foreign Flow Residualized on Individual Flow (126d) | investor_flow | higher_better | residual_t(i) = z_F_t(i) - beta_t * z_I_t(i). z_F: 126d foreign net buy z-score. z_I: 126d individual net buy z-score. beta_t: expanding-window no-intercept OLS |
| INV01_Foreign_NetBuy_20d | Foreign Net Buy 20d | investor_flow | higher_better | frollsum(Foreign, 20) / Size. Net foreign purchase normalized by market cap. |
| INV02_Foreign_NetBuy_60d | Foreign Net Buy 60d | investor_flow | higher_better | frollsum(Foreign, 60) / Size |
| INV03_Inst_NetBuy_20d | Institutional Net Buy 20d | investor_flow | higher_better | frollsum(Institutional, 20) / Size |
| INV04_Inst_NetBuy_60d | Institutional Net Buy 60d | investor_flow | higher_better | frollsum(Institutional, 60) / Size |
| INV05_Foreign_Momentum | Foreign Flow Momentum | investor_flow | higher_better | roll_F20 / roll_F60 - 1. Foreign-flow acceleration. |
| INV06_Inst_Momentum | Institutional Flow Momentum | investor_flow | higher_better | roll_I20 / roll_I60 - 1. |
| INV07_Retail_Contrarian | Retail Contrarian | investor_flow | higher_better | -frollsum(Individual, 20) / Size. Barber & Odean (2000) — individuals fade. |
| INV08_Foreign_Inst_Agreement | Foreign-Institutional Agreement | investor_flow | higher_better | sign(F20)*sign(I20)*min(/F20/,/I20/) / Size |
| INV09_Flow_Persistence | Flow Persistence | investor_flow | higher_better | fraction of last 20d with (Foreign + Institutional) > 0 |
| INV10_Smart_Money_Flow | Smart Money Flow | investor_flow | higher_better | rollsum(F+I, 20) / rollsum(/F/+/I/+/Ind/, 20) |
| INV11_Foreign_Concentration | Foreign Concentration | investor_flow | higher_better | 1 if Foreign 20d net buy >= 90th cross-sectional percentile. |
| INV12_Supply_Demand_Imbalance | Supply-Demand Imbalance | investor_flow | higher_better | rollmean((F+I-Ind) / (/F/+/I/+/Ind/), 20) |
| AC11_Accruals_to_Assets | Accruals to Assets (simple) | accrual | lower_better | Alias of AC01 for completeness. (NI - OCF) / TA. |
| AC18_Accrual_Quality | Accrual Quality (QMJ Asness 2019) | accrual | lower_better | ACC = -(NI - OCF) / TA. Identical to AC01 by construction. QMJ component. |
| D10_Blume_Adj_Beta | Blume-Adjusted Beta | defense | lower_better | Blume (1971) shrinkage: 2/3 * Beta + 1/3. |
| D18_BAB_Rank | Betting Against Beta Rank | defense | lower_better | Frazzini & Pedersen (2014) cross-sectional beta rank — lower rank = BAB long. |
| D31_Relative_Beta | Relative Beta vs Sector | defense | lower_better | Beta(stock) - mean Beta(sector). Cross-sectional within-sector beta gap. |
| Q21_Revenue_Growth | Revenue Growth (YoY) | growth | higher_better | (Revenue_curr - Revenue_prev) / /Revenue_prev/ |
| Q22_Earnings_Growth | Earnings Growth (YoY) | growth | higher_better | (NetIncome_curr - NetIncome_prev) / max(/NetIncome_prev/, 1e-8) |
| Q34_GP_Growth | Gross Profit Growth (5Y) | growth | higher_better | 5-year growth in GrossProfit / TotalAssets ratio. |
| T01_RSI14 | RSI (14d) | technical | lower_better | Relative Strength Index, 14-day Wilder smoothing. <30 oversold, >70 overbought. |
| T03_BB20 | Bollinger Band Position (20d) | technical | higher_better | (Close - MA20) / (2 * SD20). >1 = upper band breach. |
| T04_OBV21 | On-Balance Volume (21d) | technical | higher_better | cumulative signed volume slope over 21d. |
| T05_MFI14 | Money Flow Index (14d) | technical | higher_better | Volume-weighted RSI, 14d. |
| T06_PMA5 | Price/MA5 | technical | higher_better | Close / MA5 - 1. Short-term momentum. |
| T07_PMA20 | Price/MA20 | technical | higher_better | Close / MA20 - 1. |
| T08_PMA60 | Price/MA60 | technical | higher_better | Close / MA60 - 1. |
| T09_PMA120 | Price/MA120 | technical | higher_better | Close / MA120 - 1. |
| T10_RSI28 | RSI (28d) | technical | lower_better | RSI with 28-day Wilder smoothing. |
| T13_Gap | Open Gap | technical | higher_better | (Open - prev Close) / prev Close. |
| T14_HLRange | High-Low Range | technical | lower_better | (High - Low) / Open. Daily volatility proxy. |
| T15_AutoCorr | Return AutoCorr (21d) | technical | lower_better | AR(1) coefficient of daily returns over 21d. |
| RE_HY_z | HY OAS Z-Score | regime | higher_better | Cross-sectional z-score of high-yield OAS regime indicator. |
| RE_TS_z | Term Spread Z-Score | regime | higher_better | Cross-sectional z-score of 10Y-2Y term spread. |
| RE_VIX_z | VIX Z-Score | regime | higher_better | Cross-sectional z-score of VIX level. |
| RE_MRS | Market Regime Score | regime | higher_better | Composite market regime indicator (HY + TS + VIX). |
| RE_exposure | Regime Exposure | regime | higher_better | Stock-level beta to composite regime score. |
| AC14_Discretionary_Accruals | Discretionary Accruals | accrual | lower_better | Jones-model discretionary (managed) component of total accruals: residual after regressing accruals on dRevenue and PPE (Jones 1991). High discretionary accrual |
| XF_Q06_Op_Margin | Operating Margin (XF native) | quality | higher_better | OperatingProfit / Revenue. Core operating profitability margin, xlsx-native quarterly. Higher operating profitability predicts higher returns (operating-profita |

## 2. weighting — 선정된 종목 안의 비중
- 형식: `{"kind": "ew"}` · `{"kind": "score_tilt"}` · `{"kind": "rank_weight"}` · `{"kind": "rank_weight_sqrt"}` · `{"kind": "inv_vol", "window": <일수>}` · `{"kind": "catalog", "catalog_id": "<id>", "label": "<라벨>"}`

| catalog_id | 계열 | 라벨 |
|---|---|---|
| lean:ivol | risk_based | ivol |
| lean:hrp | risk_based | hrp |
| lean:minvar | risk_based | minvar |
| lean:riskparity | risk_parity | riskparity |
| lean:score_tilt | score_blend | score_tilt |
| lean:score_pure | score_blend | score_pure |
| lean:rank_tilt | score_blend | rank_tilt |
| lean:softmax_tilt | score_blend | softmax_tilt |
| lean:winsor_tilt | score_blend | winsor_tilt |
| lean:nco_score_tilt | score_blend | nco_score_tilt |
| lean:entropy | entropy | entropy |
| lean:cvar | tail_aware | cvar |
| lean:omega | tail_aware | omega |
| lean:maxdiv | entropy | maxdiv |
| lean:nco | risk_based | nco |
| lean:resampled | classical | resampled |
| lean:robust_mv | classical | robust_mv |
| lean:factor_rp | risk_parity | factor_rp |
| lean:kelly | growth | kelly |
| lean:higher_moment | higher_moment | higher_moment |
| qepm:MVO | classical | MVO |
| qepm:MVO_grid | classical | MVO_grid |
| qepm:HRP | risk_parity | HRP |
| qepm:ERC | risk_parity | ERC |
| qepm:CVaR_LP | tail_aware | CVaR_LP |
| qepm:CDaR_LP | tail_aware | CDaR_LP |
| qepm:MaxDiv | entropy | MaxDiv |
| qepm:Protection_ES | tail_aware | Protection_ES |
| qepm:PPO_RL | reinforcement_learning | PPO_RL |
| qepm:Genetic | evolutionary | Genetic |
| qepm:DPL | deep_learning | DPL |
| paper:ConformalKelly | optimizer | ConformalKelly |
| paper:PreferenceRobustDistortion | risk | PreferenceRobustDistortion |
| paper:SchurDamping | optimizer | SchurDamping |
| paper:TailConformalBand | risk | TailConformalBand |
| gen:lean_score_tilt__shr_gerber_rmt | generated_shrinkage_lift | lean_score_tilt__shr_gerber_rmt |
| gen:lean_score_tilt__shr_ledoit_wolf | generated_shrinkage_lift | lean_score_tilt__shr_ledoit_wolf |
| gen:lean_score_tilt__shr_sample | generated_shrinkage_lift | lean_score_tilt__shr_sample |
| gen:qepm_MVO__shr_lw_nls | generated_shrinkage_lift | qepm_MVO__shr_lw_nls |

## 3. universe — 후보 범위(측정 유니버스 안에서만 좁힌다)
- `{"kind": "k200_kq150"}`(기본) · `{"kind": "index", "flag": "K200"|"KQ150"}` · `{"kind": "size_band", "q_lo": a, "q_hi": b}`(그날 횡단면 t-1 시총 분위 (a, b]) · `{"kind": "sector_neutral"}`(업종별 선정)

## 4. rebalance — 집행 주기 · 회전 통제
- `{"kind": "interval", "k": ≥2, "phase": 0..k-1}`(k개월마다) · `{"kind": "rank_buffer", "mult": >1}`(보유 종목은 순위가 mult×25 밖으로 밀릴 때까지 유지) · `{"kind": "no_trade_band" | "turnover_cap", "stat": "expanding_median"|"expanding_quantile", "q": (0,1), "min_hist": ≥3}`(자기 과거 거리의 확장창 통계 문턱) · 지원 kind(엔진 정본): interval, no_trade_band, turnover_cap, rank_buffer

## 5. overlay — 시변 노출(현금) 층 · 여러 층을 곱할 수 있다
- 형식: `"overlay": {"kind": "<kind>", "arm_id": "<arm_id>"}` 또는 층 목록 `[{...}, {...}]`. 신호는 보유 시작 전 데이터만(C5 · 엔진이 집행).
- 오버레이 처방은 노출 짝 대조(같은 평균 노출의 벤치 · R5)를 넘어야 '기전 방어'다 — 노출을 줄였을 뿐이면 '노출 방어'로 기록된다.

| arm_id | kind | 계열 | 방법 |
|---|---|---|---|
| dd_brake_q | dd_brake | drawdown | 낙폭이 확장창 중앙값(진입)~90분위(전량현금) 구간에서 선형 축소. 임계를 상수로 두지 않고 데이터에서 추정. |
| dd_recovery | dd_recovery | drawdown | 낙폭이 중앙값을 넘은 국면에서 직전 1개월 시장수익이 양일 때만 노출 유지 — 회복 조건부 재진입. |
| vol_x_dd | vol_x_dd | combo | 변동성 타게팅 노출 x 데이터주도 낙폭 브레이크 노출. 고변동과 깊은 낙폭은 다른 국면이다. |
| vol_x_turb | vol_x_turb | combo | 변동성 타게팅 노출 x 마할라노비스 난기류 게이트. 단변량 변동성이 못 보는 상태 이상을 곱한다. |
| turbulence | turbulence | state_multivar | (실현변동성·횡단면분산·낙폭) 벡터의 마할라노비스 거리를 확장창 평균·공분산 기준으로 계산, 확장분위 게이트. |
| ml_tail_gate | ml_tail_gate | ml | 확장창 로지스틱으로 익월 시장수익이 하위 10분위에 들 확률을 예측하고 노출 = 1 - p_hat. 라벨 임계도 그 시점 표본에서. |
| vol_median | vol_scale | vol_target | 노출 = min(1, 확장창 중앙 실현변동성 / 현재 60일 실현변동성). 목표치를 상수로 두지 않는다. |
| vol_ewma | ewma_vol | vol_target | EWMA 변동성으로 타게팅. lambda 를 상수로 박지 않고 1개월 앞 예측 MSE 최소화로 격자에서 고른다. |
| vol_har | har_vol | vol_target | HAR-RV(일/주/월) 확장창 OLS 로 1개월 앞 변동성을 예측하고 그 예측치로 타게팅. |
| ts_mom_sign | ts_mom_gate | trend | 시장 12개월 누적수익 부호가 음이면 전량 현금. 롱온리 슬리브라 숏 대신 현금이다. |
| dbeta_tilt_rank | dbeta_tilt | cross_sectional | 낙폭의 확장창 경험분포 중앙 위에서만 개입하되, 축소량을 그 달 보유의 하방베타 횡단면 순위에 비례시킨다. 횡단면 평균 노출 1-g/2 로 스칼라판 1-g 보다 덜 깎으면서 축소 몫을 하방 기여가 큰 종목에 몰아준다. 근거: B5 50셀 실측에서 스칼라 축소가 MDD <stat> 대비 CAGR <stat> 로 상방을 더 잃어 Calmar 중앙값이 전 블록 최악(<stat>)이었다 — 대칭 축소의 구조 |
| csd_idio_tilt | gen_20260903_133452 | cross_sectional | 시장 횡단면분산(H$xs)의 확장창 경험분포 중앙 위에서만 개입하고, 축소 강도 g 를 그 달 보유의 특이변동 기여(ovol×sqrt(1−bcorr^2)) 횡단면 순위에 비례시킨다. 횡단면분산 국면을 키우는 건 시장 공통성분이 아니라 종목별 특이성분이므로, 상태는 분산으로 읽되 축소는 특이변동이 큰 종목에 몰아준다. 임의 상수 없이 강도는 분산의 자기 이력 분위, 종목 차등은 보유 내 순위에 |
| holdlvl_syscrowd_tilt | gen_20260904_073542 | cross_sectional | 상태를 시장 시계열이 아니라 그 달 보유 자체에서 읽는다(holding_level): 각 보유의 체계위험 비중 φ=bcorr²(시장 공통성분이 설명하는 변동 몫 R²)의 횡단면 중앙값을 개입 강도 g 로 삼아, 등가중 책이 얼마나 단일 시장베팅으로 수렴했는지를 잰다. 상관은 그 자체로 [0,1] 체계 비중이라 낙폭처럼 이력 센터링 없이 수준을 그대로 쓰고, 축소는 각 보유의 분산 불가능한 하 |
| ml_dual_forecast_tilt | gen_20260906_174032 | cross_sectional | 확장창 과거쌍(i<=t-1, 결과가 실현된 쌍만)으로 시장 상태(rv60·dd·r252·xs)에서 두 예보를 학습한다 — ①익월 하방 손실폭 loss=max(0,-fwd) 회귀의 예보 s_m(체계 충격 크기) ②익월 실현 횡단면분산 disp 회귀의 예보 s_x(특이 산포 크기, 학습 중앙값으로 나눈 무차원 배수 kappa). 개입 강도 g 는 모형의 오늘 예보가 자기 적합값 경험분포에서 차지 |
| multivar_channel_tilt | gen_20260907_002324 | cross_sectional | 상태 4축(rv60·dd·-r252·xs)을 스트레스 방향으로 정렬해 확장창 평균·산포로 표준화한 뒤, 그 시점 상관행렬로 a=S^{-1}1 GLS 합성지수 m=z'a/sqrt(1'S^{-1}1)를 추정한다(rv60·xs 처럼 겹치는 축이 단순 평균에서 정보를 두 번 세는 것을 상관구조가 나눠 갖게 한다). 개입 강도 g 는 m 의 자기 이력 경험분포에서 중앙 위 분위를 선형화해 뽑고(상수  |
| trend_horizon_split_tilt | gen_20260910_112827 | cross_sectional | nav 한 원천에서 1·3·6·12개월 후행수익을 뽑아 각 지평을 자기 이력의 확장창 경험분포 백분위로 무차원화한다. 지평 평균 백분위가 중앙 아래인 만큼만 개입 강도 g 를 세우고, 장기 백분위 − 단기 백분위(꺾임 정도 λ)는 강도가 아니라 종목축 배합을 정한다 — 지속 하락 국면에서는 하방베타×시장상관(실제로 함께 내려가는 몫), 갓 꺾인 국면에서는 하방베타−베타(무조건부 베타를 넘는  |
| vol_term_structure_risk_split_tilt | gen_20260912_165005 | cross_sectional | rv20·rv60·rv120 을 로그로 취해 각 관측창을 자기 이력의 확장창 경험분포 백분위로 무차원화하고, 세 백분위 평균이 중앙 위인 만큼만 개입 강도 g 를 세운다. 단기−장기 로그 변동성 격차의 이력 백분위 λ 는 강도가 아니라 종목축 배합을 정한다 — 기간구조가 자기 이력 대비 가파른 달(충격 개시)에는 상관이 올라붙어 시장과 함께 가는 몫 ovol·/bcorr/ 로, 평평·역전된  |
| xs_vol_gap_corr_brake | gen_20260913_000156 | dispersion | 신호일 횡단면분산(H$xs)은 표본이 하루라 잡음이 수준을 덮으므로 로그로 옮겨 1~6개월 후행평균으로 평활하되, 평활 길이는 상수로 박지 않고 1개월 앞 산포를 가장 잘 맞힌 관측창을 과거쌍(결과가 실현된 쌍)만으로 고른다. 그 평활 산포와 시장변동성(rv20·rv60) 로그 격차 log(xs)-log(rv) 는 등가중 항등식(시장분산 = 평균상관 x 평균 종목분산, 횡단면분산 = (1-평 |
| trend_persist_tilt | trend_persist_tilt | cross_sectional | 상태 변수를 낙폭 깊이에서 추세 지속성으로 바꾼다. 깊이 기반 계열(스칼라 25회·횡단면 18회 측정, 둘 다 포화)은 급락에서 분위가 즉시 극단으로 가 강하게 걸리지만, 느린 침식은 깊이가 극단으로 안 가므로 수중 기간이 가장 긴 국면에서 가장 덜 개입한다. 이 arm 은 시장이 자기 추세(엔진 제공 r252 부호) 아래에 연속으로 머문 개월수를 상태로 쓰고, 그 연속 길이의 확장창 경험분 |
| book_risk_budget_brake | gen_20260915_203006 | holding_level | 그 달 보유(ctx$hold)를 단일요인으로 분해해 책 전체가 지고 있는 위험을 직접 추정한다: 요인 적재는 손실을 만드는 쪽인 하방베타로 읽되 관측수 신뢰도 n/(n+보유 안 관측수 중앙값)로 가중 평균해 d_bar 를 만들고(하방베타 결측은 전구간 베타로 후퇴, 음의 적재는 0 에서 자름), 잔차는 자체변동 x sqrt(1-시장상관^2) 의 평균분산을 등가중 n 종목으로 나눠 iota^2 |
| xs_vol_risk_share_equalize | gen_20260917_091415 | cross_sectional | 그 달 보유 각 종목이 나르는 단위비중당 분산을 현재 시장변동 sigma_m 에서 다시 추정한다: 시장항 (/beta/*sigma_m)^2 + 고유항 (ovol*sqrt(1-bcorr^2))^2 로 나누고(beta 결측은 하방베타로, bcorr 결측은 상관 0 으로 후퇴, 나머지 결측은 횡단면 중앙값), 관측수 신뢰도 n/(n+보유 안 관측수 중앙값)으로 횡단면 평균 쪽으로 축소한다. sig |
| erosion_grind_idio_tilt | b5gen_erosion_grind_2 | cross_sectional | 상태를 벤치마크 월수익 경로의 두 축 곱으로 읽는다: ① 지속성 = 후행 3·6·12개월 하락월 비율을 각각 자기 이력의 확장창 백분위로 환산해 평균, ② 완만함 = 1 − (rv60 백분위가 자기 이력 중앙 위인 만큼). 곱 점수는 하락이 여러 달에 걸쳐 조금씩 쌓이는 침식 국면에서 커지고 변동성이 극단으로 가는 급락에서는 스스로 0 쪽으로 물러선다 — 기존 다변량 arm 이 변동성을 스트 |
| book_convexity_brake | gen_20260918_235445 | holding_level | 그 달 보유(ctx$hold)에서 책의 위험 '양' 이 아니라 '모양' 을 추정한다: 종목의 전구간 베타 b_i(시장 전 국면 평균 적재)와 하방베타 d_i(시장 하락일만의 적재)를 각각 보유 횡단면 분위(<stat>/<stat>)로 절단하고 관측수 신뢰도 n/(n+보유 안 관측수 중앙값)로 보유 중앙값 쪽에 축소한 뒤, 하방 표본이 모자라 d_i 를 못 낸 이름은 측정된 이름들의 비대칭비 중앙값 x  |
| trend_run_gate | b5gen_trend_run_gate_1 | trend | 시장이 자기 12개월 추세(엔진 제공 r252 의 부호 — 0 은 정의 경계) 아래에 연속으로 머문 개월수를 상태로 읽고, 그 연속 길이가 자기 이력(추세 아래였던 달들의 연속 길이 경험분포) 중앙을 넘는 만큼만 총노출을 1−g 로 단계적으로 줄인다(상수 문턱 없음 · 증액 없음). 같은 상태를 보유 안 시장베타 순위로 소비하는 trend_persist_tilt 와 소비 지점이 다르다 — 이 |
| trend_ladder_gate | b5gen_trend_ladder_gate_1 | trend | nav 한 원천에서 1·3·6·12개월 후행수익을 뽑아 각 지평을 자기 이력의 확장창 경험분포 백분위로 무차원화하고, 지평 평균 백분위가 자기 이력 중앙 아래인 만큼만 총노출을 1−g 로 줄인다(상수 문턱 없음 · 증액 없음 · 지평 집합은 관측 창이지 문턱이 아니다). 단기 지평은 하락 초입에 먼저 내려가고 반등 초입에 먼저 올라오며 장기 지평은 침식이 여러 달 이어질 때만 함께 내려가므로 |
| ladder_idio_conc_tilt | b5gen_ladder_idio_conc_1 | cross_sectional | 상태는 trend_ladder_gate 와 동일한 지평 사다리(nav 한 원천의 1·3·6·12개월 후행수익을 각각 자기 이력의 확장창 경험분포 백분위로 환산해 평균, 중앙 아래인 만큼 g · 상수 문턱 없음)이고, 책 평균 노출 예산 E = 1 − g 를 그 스칼라 짝과 정확히 같게 고정한 뒤 총 축소량 g·n 을 종목 취약도에 비례해 배분하되 한 이름의 축소가 1 을 넘으면 넘친 몫을 남 |
| book_risk_balance_gap | gen_20260920_001003 | holding_level | 그 달 보유(ctx$hold)만 읽어 책 적재의 '수준'(선행 arm 의 위험예산 비교)도 '모양'(선행 arm 의 하락/전구간 비대칭)도 아닌 **흩어짐**을 추정한다: 종목 자체변동 ovol_i 를 보유 횡단면 중앙값 대치 + 관측수 신뢰도 n/(n+보유 안 관측수 중앙값) 축소로 다듬은 뒤 단일요인으로 시장 성분 m_i=ovol_i*/bcorr_i/ 와 잔차 u_i=ovol_i*sqrt |
| book_stress_vouch | gen_20260921_071600 | holding_level | 그 달 보유의 위험 숫자가 **어떤 이력 위에서 만들어졌는지**를 상태로 읽는다 — 이 칸의 선행 arm 셋(위험의 양·모양·흩어짐)은 hold 의 beta/dbeta 를 액면 그대로 믿지만, 엔진은 각 이름의 자기 가용 이력 전체에서 확장창으로 그 값을 만들므로(rf_cell_engine.R: 누적합·최소관측 250일·하방베타는 시장 하락일 60일) 위기를 통과한 창에서 나온 하방베타와 위 |
| multivar_book_whiten_tilt | gen_20260922_000207 | cross_sectional | 다변량 상태를 종목축으로 옮기는 지점에서 **보유 특성공간을 화이트닝**한다. 선행 arm 은 상태 축의 중복 계상만 지우고(확장창 상관으로 S^{-1}1 합성) 그 축 기여도를 보유 쪽에서는 채널별(β·하방베타·시장상관·고유변동성) 횡단면 순위를 그대로 섞어 소비하는데, 이 네 특성은 엔진이 같은 수익 표본의 누적합에서 만들어 한 책 안에서 강하게 얽혀 있다(rf_cell_engine.R) |
| multivar_marginal_risk_share_tilt | gen_20260923_142144 | cross_sectional | 같은 개입 예산을 **순위 램프가 아니라 한계 위험기여 비례로** 배분한다. 이 칸의 선행 arm 3종(multivar_channel_tilt · erosion_grind_idio_tilt · multivar_book_whiten_tilt)은 배분 규칙이 전부 동일하다 — 종목별 위험 점수를 만들고 그 보유 안 백분위 r 로 e = 1 − g·r 을 준다. 순위 램프는 두 가지를 버린다: ① |
| xs_innovation_signal_share_brake | gen_20260924_001351 | dispersion | 산포의 수준이 아니라 **혁신(예측된 몫을 뺀 나머지)** 을 총노출 축으로 옮긴다. 횡단면분산은 그 시점 횡단면의 평균 고유분산을 재는 추정량이고, 25종 롱온리 책의 분산은 공통성분 + 평균고유분산/유효종목수 로 갈리므로 산포는 종목 수로 지울 수 없는 몫에 직접 실린다. 다만 수준은 그 달의 책을 세울 때 쓴 후행 추정이 이미 담고 있으므로 남는 정보는 수준에서 예측분을 뺀 혁신이고,  |
| ml_posterior_loading_tilt | gen_20260925_213504 | cross_sectional | 학습 예보가 정한 예산을 **대입값(plug-in) 순위** 대신 **사후 적재 순위**로 배분한다. 이 칸의 선행 arm(ml_dual_forecast_tilt)은 확장창 과거쌍(i<=t-1)으로 상태 4축(rv60·dd·r252·xs)에서 익월 하방 손실폭과 익월 횡단면분산을 학습해 채널 배율 s_m·kappa 를 세우고, 각 보유의 예측 하방 산포 L=sqrt((max(0,dbeta)* |
| ml_tailprob_analog_tilt | gen_20261004_084327 | cross_sectional | 오늘과 닮은 과거 달에 tricube 적응 가중(상태 4열 rv60·dd·r252·xs 을 표준화하고 차원/표본 강도로 축소한 공분산으로 백화한 마할라노비스 거리)을 주어 익월 시장수익의 조건부 경험분포를 추정한다 — 추정 대상이 조건부 평균이 아니라 분포이고, 대역폭은 상수가 아니라 표본외(LOO) 하위 분위손실(pinball · tau <stat>/<stat>/<stat>)을 최소화하는 후보로 그 시점  |
| ml_downside_budget_trim | gen_20261005_000207 | cross_sectional | 학습 예보를 순위 램프가 아니라 **종목별 위험예산**으로 전달한다. 추정 내역: 확장창 과거쌍(i<=t-1 · H$fwd 의 t 행 미열람)으로 상태 4축(rv60·dd·r252·xs)에서 두 선형모형을 적합한다 — 머리 D 는 익월 하방 **2차모멘트** max(0,-fwd)^2 를, 머리 X 는 익월 실현 횡단면분산 xs[i+1](i+1<=t 라 관측됨)을 학습한다. 머리 D 의 당월  |
| ml_contrib_balance_trim | gen_20261006_070654 | cross_sectional | 학습 예보를 종목별 **단독 위험 수준**이 아니라 **책 2차형식 안의 위험기여 몫**으로 전달한다. 추정 내역: 확장창 과거쌍(i<=t-1 · H$fwd 의 t 행 미열람)으로 상태 4축(rv60·dd·r252·xs)에서 선형모형 둘을 적합한다 — 머리 S 는 익월 시장 하방 2차모멘트 max(0,-fwd)^2 를 학습해 체계 채널의 예측 하방 반분산 vsys = max(0,ps) 를 주 |
| ml_gainloss_exchange_tilt | gen_20261007_202609 | cross_sectional | 학습 예보를 이름의 **위험 수준**이 아니라 **하방 대비 상방 교환비**로 전달한다. 추정 내역 셋. ①상태 예보 — 확장창 과거쌍(i<=t-1 · H$fwd 의 t 행 미열람)에서 상태 4축(rv60·dd·r252·xs)을 표준화해 능형(ridge · 강도 = 차원/(차원+표본) × 평균 대각, 겹친 변동성 창에서도 적합이 정의되게)으로 머리 둘을 적합한다: 익월 시장의 하방 부분적률  |
| ml_ambiguity_worst_tilt | gen_20261008_083610 | cross_sectional | 학습 예보를 **점예보 하나**로 쓰지 않고 **표본외 자격을 번 모형들의 집합**으로 쓰고, 각 이름을 그 이름에게 가장 불리한 멤버로 평가한다(Γ-maximin). 추정 내역: 확장창 과거쌍(i<=t-1 · H$fwd 의 t 행 미열람)에서 상태 4축(변동성 축 1 + dd + r252 + xs)으로 두 머리를 능형 적합한다 — 머리 D 는 익월 시장 하방 손실폭 max(0,-fwd) 를 |
| ml_channel_codep_tilt | gen_20261009_193812 | cross_sectional | 이 칸의 가족이 쓰는 결합식 L_i = sqrt(p_i^2 + q_i^2)(체계 기여 p_i = max(0,dbeta_i)*s · 고유 기여 q_i = u_i*k)은 **두 채널 충격이 같은 달에 독립**이라는 가정의 식이다. 이 arm 은 그 가정을 상수로 두지 않고 추정해 복원된 교차항을 넣는다: L_i = sqrt(max(0, p_i^2 + q_i^2 + 2*rho*p_i*q_i)).  |

## 6. defense_sleeve — 보유 25종 중 k 자리를 방어 팩터 상위로 교체(총 종목 수 · 노출 불변)
- 형식: `{"kind": "factor_topk", "k": <정수>, "select": "ic_bad_rank_asof", "rank": <정수>, "exclude": ""|"base_factors"}` — 방어 팩터는 규칙이 고른다: 셀 시작일까지(as-of)의 KOSPI200 약세 보유월 횡단면 IC 순위. `factor_id` 로 직접 지정도 가능. · 지원 kind: factor_topk, antidefense, random_beta_matched(antidefense · random_beta_matched = 대조용) · select: ic_bad_rank_asof

## 7. cap_core — 벤치 인지 코어-위성(비중 단계 뒤)
- 형식: `{"k": <정수 ≥0>, "satellite": "floor"}` — 코어 = 그 시그널일 K200 t-1 시총 상위 k종(벤치 비중 근사) · 위성 = 이 전략 보유(합집합 ≤ 25 절단). 벤치를 덜 벗어나 '시장보다 더 빠지는' 위험을 줄이는 대신 알파 희석. k = 0 = 무처치.
