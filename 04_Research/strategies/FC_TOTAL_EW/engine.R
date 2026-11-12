## FC_TOTAL_EW — 토탈 스코어 v0 · 가족 14개 등가중 (자체 사양 엔진 · 팩터 척추 1단계 F0)
## ★생성기 산출 — 손으로 고치지 않는다. 다시 만들기(저장소 루트): Rscript 02_Infrastructure/factor_db/fc_engine_gen.R --write
##   생성기 md5 e31ad11fa6be218017e961c47b06bbdc · 사양 md5 8986cd3ead68d1993064449273c8f5fe · 규칙 판 fce_rule_v0 · 사양 원문 = 같은 폴더 own_spec.json
##   결정 FACTOR-SPINE-STAGE1-20261112 · 팩터 척추 설계안 §3(문서 경로 = own_spec.json)
## 점수 = 종목마다 가족 점수 14개 가운데 값이 있는 것의 평균(가족 균형 등가중) · 전부 결측이면 결측
##   가족 점수 = 그 가족 구성원 중 값이 있는 것의 평균 — 가족 엔진 FC_FAM_<가족> 과 같은 값(같은 구성원 · 같은 접근자 인자) · 구성원 334개
##   결합용 뷰 점수 = 매 시점 횡단면 순위 [−1, 1](동순위 평균) × 등록부 기대수익 방향
##     — Gu, Kelly & Xiu (2020) RFS 33(5) https://doi.org/10.1093/rfs/hhaa009
##   평균 규칙 = Asness, Frazzini & Pedersen (2019) RAS 24(1) https://doi.org/10.1007/s11142-018-9470-2
##     · Jensen, Kelly & Pedersen (2023) JF 78(5) https://doi.org/10.1111/jofi.13249
##   결측 종목은 그 날 패널에서 뺀다(0 으로 채우지 않는다 · 06_Registry/factor_combinable.json missing 선택지 na)
## 계약: 입력 = RAWDATA(거래일 달력 — Date 열만 쓴다) · .RP_START_DATE(없으면 측정 축 정본의 활성 epoch 시작일)
##   출력 = FACTORS(Date, Ticker, Score) 만 · 날짜 = 결합용 뷰의 그 달 as-of(월말 거래일 — 셀 경로 달 스냅에서 항등)
##   as-of 가 시작일 이후인 달만 · 패널 마지막 달을 뷰가 아직 못 따라왔으면 그 달만 뺀다(그 달은 뒤 수익이 없다)
## PIT: 팩터 값은 정본 접근자 fc_load_month 한 길로만 읽는다(C15) · 방향 인자 = 문자열 상수 registry(C13 · 수동 반전 없음)
##   · IC 를 읽지 않는다(C1 · C14) · 재무 시차는 팩터 DB 가 이미 적용한 값만 쓴다(C4)
##   · 구성원 · 부호(s_reg) · 가족 · 뷰 빌더 판은 선언 때 고정 — 실행 때 뷰 메타와 다르면 멈춘다(새 사양으로 다시 선언)
## 진단(판정 입력 아님): 날짜별 구성원 수 · 점수 범위 · 종목별 유효 수(값이 있는 가족 수) 분포
##   → 이 폴더 fce_diag.csv(options(fce.diag_dir) 로 바꾼다 · 폴더가 없으면 쓰지 않는다)
.FCE_SPEC_ID <- "FC_TOTAL_EW"
.FCE_KIND <- "total"
.FCE_FAMILIES <- c("quality", "defense", "liquidity", "momentum", "accrual", "value", "growth", "investor_flow", "risk", "crowding", "consensus", "technical", "regime", "leverage")
.FCE_RULE <- "fce_rule_v0"
.FCE_GEN_MD5 <- "e31ad11fa6be218017e961c47b06bbdc"
.FCE_SPEC_MD5 <- "8986cd3ead68d1993064449273c8f5fe"
.FCE_VIEW_BUILDER <- "factor_combinable.R v1.1"
## 구성원(선언 때 고정) — id · 등록부 기대수익 부호 s_reg · 가족(등록부 category)
.FCE_M <- matrix(ncol = 3L, byrow = TRUE, data = c(
  "Q01_GPA", "1", "quality",
  "Q02_ROE", "1", "quality",
  "Q03_ROA", "1", "quality",
  "Q04_Piotroski_F", "1", "quality",
  "Q05_Accrual", "1", "quality",
  "Q06_Asset_Growth", "1", "quality",
  "Q07_Earnings_Stability", "1", "quality",
  "Q08_Composite_Quality", "1", "quality",
  "Q09_CFOA", "1", "quality",
  "Q10_Gross_Margin", "1", "quality",
  "Q11_Net_Margin", "1", "quality",
  "Q12_Asset_Turnover", "1", "quality",
  "Q13_Fin_Leverage", "1", "quality",
  "Q14_Current_Ratio", "1", "quality",
  "Q15_Debt_to_Equity", "1", "quality",
  "Q16_Debt_to_Assets", "1", "quality",
  "Q17_ROIC", "1", "quality",
  "Q18_Op_Leverage", "1", "quality",
  "Q19_Cash_to_Assets", "1", "quality",
  "Q20_Net_Equity_Issuance", "1", "quality",
  "Q23_Sustainable_Growth", "1", "quality",
  "Q24_Altman_Z", "1", "quality",
  "Q25_Ohlson_O", "1", "quality",
  "Q26_RnD_Intensity", "1", "quality",
  "Q27_CapEx_to_Rev", "1", "quality",
  "Q28_Cash_Conversion", "1", "quality",
  "Q29_Inventory_Turnover", "1", "quality",
  "Q30_Receivables_Turnover", "1", "quality",
  "Q31_WC_to_Assets", "1", "quality",
  "Q32_Interest_Coverage", "1", "quality",
  "Q33_Earnings_Persistence", "1", "quality",
  "Q35_CashBased_OpProf", "1", "quality",
  "XF_DU01_NetMargin", "1", "quality",
  "XF_DU02_AssetTurnover", "1", "quality",
  "XF_EF01_InventoryTurnover", "1", "quality",
  "XF_EF02_DaysPayable", "1", "quality",
  "XF_EF03_DaysReceivable", "-1", "quality",
  "XF_EF04_CCC", "-1", "quality",
  "XF_PR01_EBITDA_Margin", "1", "quality",
  "XF_PR02_RetainedEarnings_Ratio", "1", "quality",
  "XF_PR03_TaxRate", "-1", "quality",
  "XF_PR04_NetInterestMargin", "1", "quality",
  "XF_PR05_EBITDA_to_Assets", "1", "quality",
  "XF_Q06_Op_Margin", "1", "quality",
  "XF_RI01_RnD_to_Revenue", "1", "quality",
  "XF_RI02_CapEx_proxy", "-1", "quality",
  "XF_RI03_SGA_to_Revenue", "-1", "quality",
  "D01_IdioVol", "1", "defense",
  "D02_Beta", "1", "defense",
  "D03_RealVol", "1", "defense",
  "D04_Downside_Beta", "1", "defense",
  "D05_MaxRet", "1", "defense",
  "D06_Upside_Beta", "-1", "defense",
  "D07_Beta_Asymmetry", "1", "defense",
  "D09_Dimson_Beta", "1", "defense",
  "D10_Blume_Adj_Beta", "1", "defense",
  "D11_FP_Beta", "1", "defense",
  "D12_Beta_126d", "1", "defense",
  "D13_Beta_63d", "1", "defense",
  "D14_Beta_Change", "1", "defense",
  "D15_Cond_Bear_Beta", "1", "defense",
  "D16_Coskewness", "1", "defense",
  "D17_Cokurtosis", "1", "defense",
  "D18_BAB_Rank", "1", "defense",
  "D19_EW_Beta_63", "1", "defense",
  "D20_EW_Beta_126", "1", "defense",
  "D21_CAPM_Alpha", "1", "defense",
  "D22_Tracking_Error", "1", "defense",
  "D23_Info_Ratio", "1", "defense",
  "D24_Systematic_Risk_Prop", "1", "defense",
  "D25_Left_Tail_Beta", "1", "defense",
  "D26_Right_Tail_Beta", "-1", "defense",
  "D27_Beta_Stability", "1", "defense",
  "D28_Unlevered_Beta", "1", "defense",
  "D29_Accounting_Beta", "1", "defense",
  "D30_FM_Beta_21d", "1", "defense",
  "D31_Relative_Beta", "1", "defense",
  "D33_Beta_Persistence", "1", "defense",
  "D34_RealVol_21d", "1", "defense",
  "D35_RealVol_63d", "1", "defense",
  "D36_RealVol_126d", "1", "defense",
  "D37_Parkinson_Vol", "1", "defense",
  "D38_GarmanKlass_Vol", "1", "defense",
  "D39_RogersSatchell_Vol", "1", "defense",
  "D40_YangZhang_Vol", "1", "defense",
  "D41_Vol_of_Vol", "1", "defense",
  "D42_EWMA_Vol", "1", "defense",
  "D43_Skewness", "1", "defense",
  "D44_Kurtosis", "1", "defense",
  "D45_Downside_Dev", "1", "defense",
  "D46_Sortino", "1", "defense",
  "D47_CVaR_5pct", "1", "defense",
  "D48_VaR_5pct", "1", "defense",
  "D49_VaR_1pct", "1", "defense",
  "D50_MaxDrawdown", "1", "defense",
  "D51_Ulcer_Index", "1", "defense",
  "D52_MinRet", "1", "defense",
  "D53_Range_Vol", "1", "defense",
  "D54_Neg_Ret_Prop", "1", "defense",
  "D55_Vol_Trend", "1", "defense",
  "D56_Up_Vol", "1", "defense",
  "D57_Down_Vol", "1", "defense",
  "D58_Vol_Asymmetry", "-1", "defense",
  "D60_Leverage", "1", "defense",
  "L01_Amihud", "-1", "liquidity",
  "L02_Turnover", "-1", "liquidity",
  "L03_Volume_Mom", "1", "liquidity",
  "L04_Bid_Ask_Proxy", "-1", "liquidity",
  "L05_Dollar_Volume", "-1", "liquidity",
  "L06_Zero_Trade_Days", "-1", "liquidity",
  "L07_Zero_Return_Days", "-1", "liquidity",
  "L08_Roll_Spread", "-1", "liquidity",
  "L09_Amihud_20d", "-1", "liquidity",
  "L10_Amihud_Ratio", "1", "liquidity",
  "L11_Kyle_Lambda", "-1", "liquidity",
  "L12_PS_Gamma", "1", "liquidity",
  "L13_Vol_Variance_Ratio", "1", "liquidity",
  "L14_Price_Impact", "-1", "liquidity",
  "L15_Turnover_252d", "-1", "liquidity",
  "L16_Turnover_Vol", "1", "liquidity",
  "L17_LOT_Measure", "-1", "liquidity",
  "L18_Eff_Spread_Proxy", "1", "liquidity",
  "L19_Price_Delay", "-1", "liquidity",
  "L20_Trade_Frequency", "-1", "liquidity",
  "L21_Market_Depth", "1", "liquidity",
  "L22_Ret_Autocorr", "1", "liquidity",
  "L23_Vol_Autocorr", "1", "liquidity",
  "L24_Range_per_Vol", "1", "liquidity",
  "L25_Amihud_Vol", "-1", "liquidity",
  "L26_Log_MktCap", "-1", "liquidity",
  "L27_Price_Level", "1", "liquidity",
  "L28_Vol_Mom_63d", "1", "liquidity",
  "L29_Illiq_Change", "1", "liquidity",
  "L31_Vol_Concentration", "1", "liquidity",
  "L32_Ret_Vol_Corr", "1", "liquidity",
  "L33_AbsRet_Vol_Corr", "1", "liquidity",
  "L34_Vol_Spike_Ratio", "1", "liquidity",
  "L35_Reversal_Intensity", "1", "liquidity",
  "L36_CLV_Stability", "1", "liquidity",
  "L37_Relative_Vol", "1", "liquidity",
  "L38_DolVol_Mom", "1", "liquidity",
  "L39_Overnight_Spread", "1", "liquidity",
  "L40_VWAP_Spread", "1", "liquidity",
  "L41_Intraday_Vol_Proxy", "1", "liquidity",
  "L42_Vol_Skewness", "-1", "liquidity",
  "L43_Turnover_Change", "1", "liquidity",
  "L44_Vol_Ret_Asymmetry", "1", "liquidity",
  "L45_Composite_Liquidity", "-1", "liquidity",
  "M01_Mom_12_1", "1", "momentum",
  "M02_Mom_6_1", "1", "momentum",
  "M03_Mom_3_1", "1", "momentum",
  "M04_Mom_1", "-1", "momentum",
  "M05_Trended_Mom", "1", "momentum",
  "M06_High_52w", "1", "momentum",
  "M07_IndMom", "1", "momentum",
  "M08_Residual_Mom", "1", "momentum",
  "M09_Composite_Mom", "1", "momentum",
  "M10_Intermediate_Mom", "1", "momentum",
  "M11_ST_Reversal", "-1", "momentum",
  "M12_LR_Reversal", "-1", "momentum",
  "M13_VolAdj_Mom", "1", "momentum",
  "M14_RiskAdj_Mom", "1", "momentum",
  "M15_Mom_3", "1", "momentum",
  "M16_Trend_Factor", "1", "momentum",
  "M17_Low_52w", "1", "momentum",
  "M18_RSI", "-1", "momentum",
  "M19_MACD", "1", "momentum",
  "M20_Keller_Mom", "1", "momentum",
  "M21_Seasonality", "1", "momentum",
  "M22_Max_Return", "-1", "momentum",
  "M23_Acceleration", "1", "momentum",
  "M24_Sector_Rel_Mom", "1", "momentum",
  "M25_Earnings_Mom_Streak", "1", "momentum",
  "M26_Revenue_Mom", "1", "momentum",
  "M27_Analyst_Rev_Mom", "1", "momentum",
  "M28_OP_Rev_Mom", "1", "momentum",
  "M30_Mom_10d", "-1", "momentum",
  "M32_Composite_Mom_v2", "1", "momentum",
  "AC01_Total_Accruals_CF", "1", "accrual",
  "AC02_Total_Accruals_BS", "1", "accrual",
  "AC03_WC_Accruals", "1", "accrual",
  "AC04_NCO_Accruals", "1", "accrual",
  "AC05_NOA", "1", "accrual",
  "AC06_Comprehensive_Accruals", "1", "accrual",
  "AC07_Operating_Accruals", "1", "accrual",
  "AC08_Financial_Accruals", "-1", "accrual",
  "AC09_NNI", "1", "accrual",
  "AC10_Pct_Accruals", "1", "accrual",
  "AC12_Inventory_Accruals", "1", "accrual",
  "AC13_Abnormal_Accruals", "1", "accrual",
  "AC14_Discretionary_Accruals", "1", "accrual",
  "AC15_NonDiscretionary_Accruals", "1", "accrual",
  "AC16_BS_vs_CF_Diff", "1", "accrual",
  "AC17_Accrual_Reversal", "1", "accrual",
  "AC19_Receivables_Accruals", "1", "accrual",
  "AC20_Payables_Accruals", "1", "accrual",
  "AC21_CF_to_Accrual_Ratio", "1", "accrual",
  "AC22_Accrual_Volatility", "1", "accrual",
  "AC23_Accrual_Persistence", "1", "accrual",
  "AC24_NOA_Growth", "1", "accrual",
  "AC25_Accrual_Size_Interaction", "1", "accrual",
  "V01_BM", "1", "value",
  "V02_EP", "1", "value",
  "V03_CFP", "1", "value",
  "V04_fPER", "-1", "value",
  "V05_fPBR", "-1", "value",
  "V06_fDY", "1", "value",
  "V07_EV_EBITDA", "-1", "value",
  "V08_PSR", "-1", "value",
  "V09_PEG", "-1", "value",
  "V10_FCF_Yield", "1", "value",
  "V11_Shareholder_Yield", "1", "value",
  "V12_Composite_Value", "1", "value",
  "V13_EV_Sales", "-1", "value",
  "V14_EBIT_EV", "1", "value",
  "V15_NetDebt_Adj_EP", "1", "value",
  "V16_Tobins_Q", "-1", "value",
  "V17_Payout_Ratio", "1", "value",
  "V18_AM", "1", "value",
  "V19_Debt_to_Market", "1", "value",
  "V20_SP", "1", "value",
  "V21_Composite_Equity_Issuance", "-1", "value",
  "V22_FCFF_EV", "1", "value",
  "V23_RAFI_Weight", "1", "value",
  "V24_Residual_Income", "1", "value",
  "GR01_Revenue_Growth", "1", "growth",
  "GR02_Earnings_Growth", "1", "growth",
  "GR03_Asset_Growth", "1", "growth",
  "GR04_GPA_Growth", "1", "growth",
  "GR05_ROE_Growth", "1", "growth",
  "GR06_OCF_Growth", "1", "growth",
  "GR07_Composite_Growth", "1", "growth",
  "IN01_CapEx_to_Assets", "1", "growth",
  "IN02_CapEx_to_Revenue", "1", "growth",
  "IN03_RD_to_Market", "1", "growth",
  "IN04_Net_Equity_Issuance", "1", "growth",
  "IN05_Net_Debt_Issuance", "1", "growth",
  "IN06_Investment_to_Assets", "1", "growth",
  "MK01_CAPM_Beta", "-1", "growth",
  "Q21_Revenue_Growth", "1", "growth",
  "Q22_Earnings_Growth", "1", "growth",
  "Q34_GP_Growth", "1", "growth",
  "XF_GD01_GrossProfit_Growth", "1", "growth",
  "XF_GD02_OpProfit_Growth", "1", "growth",
  "XF_GD03_OCF_Growth", "1", "growth",
  "XF_GD04_Dividend_Growth", "1", "growth",
  "INV01_Foreign_NetBuy_20d", "1", "investor_flow",
  "INV02_Foreign_NetBuy_60d", "1", "investor_flow",
  "INV03_Inst_NetBuy_20d", "1", "investor_flow",
  "INV04_Inst_NetBuy_60d", "1", "investor_flow",
  "INV05_Foreign_Momentum", "1", "investor_flow",
  "INV06_Inst_Momentum", "1", "investor_flow",
  "INV07_Retail_Contrarian", "1", "investor_flow",
  "INV08_Foreign_Inst_Agreement", "1", "investor_flow",
  "INV09_Flow_Persistence", "1", "investor_flow",
  "INV10_Smart_Money_Flow", "1", "investor_flow",
  "INV11_Foreign_Concentration", "1", "investor_flow",
  "INV12_Supply_Demand_Imbalance", "1", "investor_flow",
  "INV13_Foreign_Resid_Individual_126d", "1", "investor_flow",
  "INV13_Foreign_Resid_Individual_21d", "1", "investor_flow",
  "INV13_Foreign_Resid_Individual_63d", "1", "investor_flow",
  "R01_VaR_95", "-1", "risk",
  "R02_VaR_99", "-1", "risk",
  "R03_CVaR_95", "-1", "risk",
  "R04_CVaR_99", "-1", "risk",
  "R05_Tail_Risk", "1", "risk",
  "R06_MDD", "1", "risk",
  "R07_Downside_Dev", "1", "risk",
  "R08_Semi_Variance", "1", "risk",
  "R09_Coskewness", "-1", "risk",
  "R10_Cokurtosis", "1", "risk",
  "R11_Systematic_Risk", "1", "risk",
  "R12_Idiosyncratic_Risk", "1", "risk",
  "R13_NCSKEW", "-1", "risk",
  "R14_DUVOL", "-1", "risk",
  "R15_Sortino", "1", "risk",
  "R16_Calmar", "1", "risk",
  "R17_Market_Leverage", "-1", "risk",
  "R18_Book_Leverage", "1", "risk",
  "R19_Composite_Risk", "1", "risk",
  "CR01_Sector_Comovement", "1", "crowding",
  "CR02_Volume_Concentration", "-1", "crowding",
  "CR04_Ownership_Concentration", "-1", "crowding",
  "CR05_Short_Pressure_Proxy", "1", "crowding",
  "CR06_DTC_Proxy", "-1", "crowding",
  "CR07_Momentum_Crowding", "1", "crowding",
  "CR08_Volume_Price_Divergence", "1", "crowding",
  "CR09_Money_Flow_Ratio", "1", "crowding",
  "CR10_Convergence_Premium", "1", "crowding",
  "CR11_Idiosyncratic_Return", "1", "crowding",
  "SE01_Volatility_Uncertainty", "1", "crowding",
  "SE02_Consensus_Revision", "1", "crowding",
  "TR01_ADX_Proxy", "1", "crowding",
  "TR02_Trend_Consistency", "1", "crowding",
  "C01_SUE", "1", "consensus",
  "C02_EPS_Chg_1m", "1", "consensus",
  "C03_EPS_Chg_3m", "1", "consensus",
  "C04_ESBR", "1", "consensus",
  "C05_ESCR", "1", "consensus",
  "C06_TP_Gap", "1", "consensus",
  "C07_TP_Mom", "1", "consensus",
  "C08_Coverage", "1", "consensus",
  "C09_Earnings_Surprise_Sq", "1", "consensus",
  "C11_Earnings_Streak", "1", "consensus",
  "C12_Estimate_Dispersion_Proxy", "-1", "consensus",
  "C16_EPS_Acceleration", "1", "consensus",
  "C18_Earnings_CAR_3d", "1", "consensus",
  "C19_Composite_Earnings", "1", "consensus",
  "T01_RSI14", "-1", "technical",
  "T03_BB20", "1", "technical",
  "T04_OBV21", "1", "technical",
  "T05_MFI14", "1", "technical",
  "T06_PMA5", "1", "technical",
  "T07_PMA20", "1", "technical",
  "T08_PMA60", "1", "technical",
  "T09_PMA120", "1", "technical",
  "T10_RSI28", "-1", "technical",
  "T13_Gap", "1", "technical",
  "T14_HLRange", "-1", "technical",
  "T15_AutoCorr", "-1", "technical",
  "MA03_Rate_Sensitivity", "-1", "regime",
  "MA04_YieldCurve_Sensitivity", "1", "regime",
  "RE04_HighVol_Beta", "1", "regime",
  "RE05_LowVol_Beta", "1", "regime",
  "RE06_Beta_Asymmetry", "1", "regime",
  "RE07_Crisis_Beta", "1", "regime",
  "RE08_Down_Market_Excess", "1", "regime",
  "RE09_Capture_Ratio", "1", "regime",
  "XF_DU03_EquityMultiplier", "-1", "leverage",
  "XF_LL01_DebtToCapital", "-1", "leverage",
  "XF_LL02_NetDebt", "-1", "leverage",
  "XF_LL03_CashRatio", "1", "leverage",
  "XF_LL04_QuickRatio", "1", "leverage",
  "XF_LL05_WorkingCapital", "1", "leverage"
))
.FCE_MEMBERS <- data.frame(id = .FCE_M[, 1L], s_reg = as.integer(.FCE_M[, 2L]), family = .FCE_M[, 3L], stringsAsFactors = FALSE)
if (nrow(.FCE_MEMBERS) != 334L || anyDuplicated(.FCE_MEMBERS$id) > 0L || !all(.FCE_MEMBERS$s_reg %in% c(-1L, 1L)) ||
    !all(.FCE_MEMBERS$family %in% .FCE_FAMILIES))
  stop("[FC_TOTAL_EW] 구성원 표가 선언과 다르다 — 생성기로 다시 만들 것(손 편집 금지)")
.fce_root <- local({
  r <- Sys.getenv("CLAUDE_PROJECT_DIR", "")
  if (!nzchar(r)) r <- Sys.getenv("QM_ROOT", "")
  if (!nzchar(r)) stop("[FC_TOTAL_EW] CLAUDE_PROJECT_DIR · QM_ROOT 미설정 — 루트를 지어내지 않는다")
  gsub("\\\\", "/", r)
})
.fce_fc <- new.env(parent = globalenv())
sys.source(file.path(.fce_root, "02_Infrastructure", "factor_db", "factor_combinable.R"), envir = .fce_fc, keep.source = FALSE)
.fce_start <- if (exists(".RP_START_DATE")) as.Date(.RP_START_DATE) else local({
  e <- new.env(parent = globalenv())
  sys.source(file.path(.fce_root, "02_Infrastructure", "contracts", "measurement_axis.R"), envir = e, keep.source = FALSE)
  as.Date(e$ma_epoch(root = .fce_root)$start_date)
})
if (length(.fce_start) != 1L || is.na(.fce_start)) stop("[FC_TOTAL_EW] 측정 시작일을 읽지 못했다")
if (!exists("RAWDATA")) stop("[FC_TOTAL_EW] RAWDATA 없음 — 셀 경로 · 러너가 넘기는 패널(거래일 달력)이 필요하다")
.fce_cal <- sort(unique(as.Date(RAWDATA[["Date"]])))
.fce_me <- .fce_cal[!duplicated(format(.fce_cal, "%Y%m"), fromLast = TRUE)]
.fce_me <- .fce_me[.fce_me >= .fce_start]
if (!length(.fce_me)) stop(sprintf("[%s] 시작일 %s 뒤 월말 거래일이 패널에 없다", .FCE_SPEC_ID, format(.fce_start)))
.fce_rows <- list(); .fce_dg <- list()
for (.fce_i in seq_along(.fce_me)) {
  .fce_d <- .fce_me[.fce_i]
  .fce_r <- NULL
  invisible(utils::capture.output(.fce_r <- tryCatch(
    .fce_fc$fc_load_month(.fce_d, direction = "registry", factors = .FCE_MEMBERS$id, missing = "na", dedup = FALSE, family = TRUE),
    error = function(e) e)))
  if (inherits(.fce_r, "error")) {
    .fce_em <- conditionMessage(.fce_r)
    if (.fce_i == length(.fce_me) && (grepl("결합용 뷰에 그 달이 없다", .fce_em, fixed = TRUE) || grepl("보다 이르다", .fce_em, fixed = TRUE))) {
      cat(sprintf("[%s] 패널 마지막 달 %s 은 뺀다 — 결합용 뷰가 패널 끝을 아직 못 따라왔다(그 달은 뒤 수익이 없다): %s\n",
                  .FCE_SPEC_ID, format(.fce_d, "%Y-%m"), .fce_em))
      next
    }
    stop(.fce_r)
  }
  .fce_in <- .fce_r$info
  if (!identical(.fce_in$builder, .FCE_VIEW_BUILDER) || !identical(.fce_in$direction, "registry") || !identical(.fce_in$missing, "na") ||
      !identical(.fce_in$dedup, FALSE) || !identical(.fce_in$rerank_within_tickers, FALSE))
    stop(sprintf("[%s] 결합용 뷰 판 · 읽기 인자가 선언과 다르다(뷰 %s · 선언 %s) — 사양을 다시 선언할 것", .FCE_SPEC_ID,
                 as.character(.fce_in$builder)[1], .FCE_VIEW_BUILDER))
  .fce_asof <- as.Date(.fce_in$asof)
  if (.fce_asof < .fce_start) next
  .fce_m <- .fce_r$meta
  .fce_k <- match(.fce_m$Factor_Name, .FCE_MEMBERS$id)
  .fce_ok <- !is.na(.fce_k) & !is.na(.fce_m$s_reg) & !is.na(.fce_m$category)
  .fce_ok[.fce_ok] <- .fce_m$s_reg[.fce_ok] == .FCE_MEMBERS$s_reg[.fce_k[.fce_ok]] &
    .fce_m$category[.fce_ok] == .FCE_MEMBERS$family[.fce_k[.fce_ok]]
  if (!all(.fce_ok))
    stop(sprintf("[%s] 방향 · 가족 고정 위반 — 뷰 메타의 s_reg · category 가 선언과 다르다(%s): %s — 사양을 다시 선언할 것", .FCE_SPEC_ID,
                 format(.fce_d, "%Y-%m"), paste(utils::head(.fce_m$Factor_Name[!.fce_ok], 8L), collapse = ", ")))
  .fce_f <- .fce_r$families
  ## 토탈 v0 = 가족 점수(결합용 뷰가 낸 가족 평균) 가운데 값이 있는 것의 평균 · 전부 결측이면 결측
  .fce_fcol <- intersect(.FCE_FAMILIES, names(.fce_f))
  if (length(.fce_fcol)) {
    .fce_x <- do.call(cbind, lapply(.fce_fcol, function(cc) .fce_f[[cc]]))
    .fce_nf <- rowSums(!is.na(.fce_x))
    .fce_s <- ifelse(.fce_nf > 0L, rowSums(.fce_x, na.rm = TRUE) / pmax(.fce_nf, 1L), NA_real_)
  } else {
    .fce_nf <- integer(nrow(.fce_f)); .fce_s <- rep(NA_real_, nrow(.fce_f))
  }
  .fce_v <- is.finite(.fce_s)
  .fce_nv <- .fce_nf[.fce_v]
  .fce_np <- length(.fce_fcol)
  .fce_rows[[length(.fce_rows) + 1L]] <- data.frame(Date = rep(.fce_asof, sum(.fce_v)), Ticker = .fce_f$Ticker[.fce_v],
                                                    Score = .fce_s[.fce_v], stringsAsFactors = FALSE)
  .fce_dg[[length(.fce_dg) + 1L]] <- data.frame(Date = .fce_asof, n_members_present = nrow(.fce_m), n_families_present = .fce_np,
    n_scored = sum(.fce_v), score_min = if (any(.fce_v)) min(.fce_s[.fce_v]) else NA_real_,
    score_max = if (any(.fce_v)) max(.fce_s[.fce_v]) else NA_real_, n_valid_min = if (length(.fce_nv)) min(.fce_nv) else NA_real_,
    n_valid_median = if (length(.fce_nv)) stats::median(.fce_nv) else NA_real_, n_valid_max = if (length(.fce_nv)) max(.fce_nv) else NA_real_)
}
if (!length(.fce_rows)) stop(sprintf("[%s] 산출이 비었다 — 시작일 %s 뒤 점수가 있는 달이 없다", .FCE_SPEC_ID, format(.fce_start)))
FACTORS <- data.table::rbindlist(.fce_rows)
if (!nrow(FACTORS)) stop(sprintf("[%s] 산출이 비었다 — 점수가 있는 종목이 없다", .FCE_SPEC_ID))
.fce_dgt <- do.call(rbind, .fce_dg)
.fce_dgt$start <- format(.fce_start)
.fce_dgt$spec_md5 <- .FCE_SPEC_MD5
cat(sprintf("[%s] FACTORS %d행 · 달 %d(%s ~ %s) · 시작 %s · 구성원 선언 %d · 달마다 있는 구성원 %d ~ %d\n", .FCE_SPEC_ID, nrow(FACTORS),
            nrow(.fce_dgt), format(min(.fce_dgt$Date)), format(max(.fce_dgt$Date)), format(.fce_start), nrow(.FCE_MEMBERS),
            min(.fce_dgt$n_members_present), max(.fce_dgt$n_members_present)))
.fce_dd <- getOption("fce.diag_dir", file.path(.fce_root, "04_Research", "strategies", .FCE_SPEC_ID))
if (dir.exists(.fce_dd)) {
  .fce_tmp <- file.path(.fce_dd, sprintf(".fce_diag_%d.tmp", Sys.getpid()))
  .fce_to <- file.path(.fce_dd, "fce_diag.csv")
  .fce_wr <- tryCatch({
    utils::write.csv(.fce_dgt, .fce_tmp, row.names = FALSE)
    if (file.exists(.fce_to)) file.remove(.fce_to)
    file.rename(.fce_tmp, .fce_to)
  }, error = function(e) FALSE)
  if (!isTRUE(.fce_wr)) { unlink(.fce_tmp); warning(sprintf("[%s] 진단 파일을 쓰지 못했다(판정 무관): %s", .FCE_SPEC_ID, .fce_dd)) }
}
suppressWarnings(rm(list = c(".fce_rows", ".fce_dg", ".fce_dgt", ".fce_r", ".fce_f", ".fce_m", ".fce_in", ".fce_k", ".fce_ok", ".fce_s",
                             ".fce_v", ".fce_nv", ".fce_np", ".fce_x", ".fce_nf", ".fce_fcol", ".fce_cal", ".fce_me", ".fce_d", ".fce_i",
                             ".fce_asof", ".fce_em", ".fce_dd", ".fce_tmp", ".fce_wr", ".fce_to", ".fce_fc", ".fce_start", ".FCE_M")))
invisible(gc(verbose = FALSE))
