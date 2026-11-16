#==============================================================================
# compute_fundamental.R — 재무 팩터 단일 모듈 (2026-11-16 도훈 '퀀티와이즈로 업데이트 안하던 시절에 정의한 펀더멘털 팩터 정의를
#   새롭게 만든 펀더멘털 데이터 캐시 기반으로 재정의해')
#
# 대체하는 것: compute_quality.R · compute_growth.R · compute_accrual.R 전부 · compute_value.R 의 재무 팩터 ·
#   compute_quality_xf_native.R · xlsx_factor_calculator.R(XF 팩터군 — 퀀티 자료가 2014년까지만 있던 시절 DART 2016~ 을 메우던 땜질 · 삭제).
#   팩터 이름과 저장 부호(높을수록 좋은 쪽 · 등록부 방향)는 구판 그대로 둔다 — 정의(입력 · 기간)만 바꾼다.
# 원천: 재무 캐시 두 개(fund_access.R::fa_latest · 결정일 기준 Factor_Date 이하 최신 행):
#   q = 분기 캐시(흐름 = 최근 4분기 합 TTM · 잔액 = 최근 분기 말 · 1년 전 비교 = 4분기 전) — 기본 기준(결정일에 알 수 있는 가장 최신 정보 ·
#       분기 갱신 수익성 = Hou, Xue & Zhang 2015 'Digesting Anomalies', RFS 28(3) https://doi.org/10.1093/rfs/hhu068)
#   a = 연간 캐시(회계연도) — 정의 자체가 회계연도인 것: F-score(Piotroski 2000 https://doi.org/10.2307/2672906) · 자산성장 · 투자
#       (Cooper, Gulen & Schill 2008 https://doi.org/10.1111/j.1540-6261.2008.01370.x · Fama & French 2015 https://doi.org/10.1016/j.jfineco.2014.10.010) ·
#       다년 안정성 · 지속성 · 5년 변화
# 구판과 달라진 점(전부): ① 2014년까지 분기 단독 · 2015~ 연간이 한 열에 섞이던 것 → 흐름은 늘 TTM 또는 회계연도
#   ② '직전 기간' = Factor_Date 두 번째(2014년까지 전 분기 · 이후 전년) → 늘 1년 전 ③ 원천 없던 항목(TaxPayable · MinorityInterest ·
#   PreferredStock · Investments) → 퀀티 v2 항목(NonControllingInt · PreferredCapital · Investments) ④ 순이익 = 지배주주 순이익(가치 · ROE)
#   ⑤ 합성 재고(유동자산 − 현금 − 매출채권) · 합성 주식 수(시가총액 ÷ 종가) → 퀀티 원값(Inventory · SharesCommonOutAdj).
# 시가총액 = RAWDATA Size(결정일 마지막 거래일 · PIT). 반환 = data.table(Ticker, Factor_Name, Raw_Value).
#==============================================================================
suppressPackageStartupMessages(library(data.table))

compute_fundamental <- function(RAWDATA, sig_date, FUND = NULL, CONSENSUS = NULL) {
  sig <- as.Date(sig_date)
  empty <- data.table(Ticker = character(), Factor_Name = character(), Raw_Value = numeric())
  if (!exists("fa_latest")) stop("[compute_fundamental] fund_access.R 가 먼저 source 돼야 한다")
  snap_date <- max(RAWDATA$Date[!is.na(RAWDATA$Size) & RAWDATA$Size > 0], na.rm = TRUE)
  mc <- RAWDATA[Date == snap_date & is.finite(Size) & Size > 0, .(Ticker, MC = Size)]
  Q <- fa_latest(sig, "q")
  A <- fa_latest(sig, "a")
  if (!nrow(Q) && !nrow(A)) return(empty)
  g <- function(D, col) if (col %in% names(D)) D[[col]] else rep(NA_real_, nrow(D))
  sdv <- function(n, d) fifelse(is.finite(n) & is.finite(d) & d > 0, n / d, NA_real_)
  sda <- function(n, d) fifelse(is.finite(n) & is.finite(d) & d != 0, n / abs(d), NA_real_)
  zs <- function(x) { s <- sd(x, na.rm = TRUE); if (!is.finite(s) || s < 1e-12) return(rep(NA_real_, length(x))); (x - mean(x, na.rm = TRUE)) / s }
  out <- list()
  put <- function(name, tick, val) { d <- data.table(Ticker = tick, Factor_Name = name, Raw_Value = val)[is.finite(Raw_Value)]; if (nrow(d)) out[[name]] <<- d }

  # ======================= 분기(TTM) 기준 표 + 시가총액 =======================
  q <- merge(Q, mc, by = "Ticker", all.x = TRUE)
  NIp  <- fifelse(is.finite(g(q, "NetIncomeParent")), g(q, "NetIncomeParent"), g(q, "NetIncome"))
  MC   <- g(q, "MC"); TD <- g(q, "TotalDebt"); CASH <- g(q, "CashAndEquiv")
  EV   <- MC + fifelse(is.finite(TD), TD, 0) - fifelse(is.finite(CASH), CASH, 0)
  BE   <- g(q, "BookEquity"); FCF <- g(q, "FCF"); DIV <- g(q, "CashDivCommon")
  tq <- q$Ticker

  # ---- 가치(V) — 흐름 = TTM · 잔액 = 최근 분기 · 시가총액 = 결정일 ----
  put("V01_BM", tq, sdv(BE, MC))                                                  # Fama & French(1992) 장부가 / 시가(우선주 제외 장부가)
  put("V02_EP", tq, sdv(NIp, MC))                                                 # 지배주주 순이익(TTM) / 시가
  put("V03_CFP", tq, sdv(g(q, "OperatingCF"), MC))
  put("V07_EV_EBITDA", tq, fifelse(g(q, "EBITDA") > 0 & EV > 0, EV / g(q, "EBITDA"), NA_real_))
  put("V08_PSR", tq, sdv(MC, g(q, "Revenue")))
  put("V10_FCF_Yield", tq, sdv(FCF, MC))
  put("V11_Shareholder_Yield", tq, sdv(DIV, MC))                                  # 보통주 현금배당(TTM) / 시가
  put("V13_EV_Sales", tq, fifelse(EV > 0, sdv(EV, g(q, "Revenue")), NA_real_))
  put("V14_EBIT_EV", tq, sdv(g(q, "OperatingProfit"), EV))                        # Greenblatt(2006) — 영업이익 / EV
  ie <- fifelse(is.finite(g(q, "InterestExp")), g(q, "InterestExp"), 0)
  nd <- g(q, "NetDebt")
  put("V15_NetDebt_Adj_EP", tq, sdv(NIp + ie, MC + fifelse(is.finite(nd), nd, 0)))
  put("V16_Tobins_Q", tq, sdv(MC + g(q, "TotalLiab"), g(q, "TotalAssets")))
  put("V17_Payout_Ratio", tq, g(q, "PayoutRatio"))
  put("V18_AM", tq, sdv(g(q, "TotalAssets"), MC))
  put("V19_Debt_to_Market", tq, sdv(TD, MC))                                      # Bhandari(1988)
  put("V20_SP", tq, sdv(g(q, "Revenue"), MC))
  put("V22_FCFF_EV", tq, sdv(FCF, EV))
  # RAFI 근사(Arnott, Hsu & Moore 2005): 매출 · 영업현금흐름 · 장부가 · 배당의 단면 몫 평균(양수만 · 2개 이상)
  sh <- function(x) { x <- fifelse(is.finite(x) & x > 0, x, NA_real_); x / sum(x, na.rm = TRUE) }
  rafi <- cbind(sh(g(q, "Revenue")), sh(g(q, "OperatingCF")), sh(BE), sh(DIV))
  put("V23_RAFI_Weight", tq, fifelse(rowSums(is.finite(rafi)) >= 2L, rowMeans(rafi, na.rm = TRUE), NA_real_))
  # 잔여이익(구판 그대로 자기자본비용 대용 8% = 무위험 3% + 위험 프리미엄 5% · compute_value.R 구판 주석)
  put("V24_Residual_Income", tq, sdv(NIp - BE * 0.08, MC))

  # ---- 퀄리티(Q) — TTM 기준 ----
  put("Q01_GPA", tq, g(q, "GPA"))                                                 # Novy-Marx(2013)
  put("Q02_ROE", tq, g(q, "ROE"))                                                 # 지배주주 순이익 / 1년 평균 장부가
  put("Q03_ROA", tq, g(q, "ROA"))
  put("Q05_Accrual", tq, -g(q, "AccrualBS"))                                      # Sloan(1996) 재무상태표 발생액 · 음수 저장(낮을수록 좋음)
  put("Q09_CFOA", tq, g(q, "CashOP"))
  put("Q10_Gross_Margin", tq, g(q, "GrossMargin"))
  put("Q11_Net_Margin", tq, g(q, "NetMargin"))
  put("Q12_Asset_Turnover", tq, g(q, "AssetTurnover"))
  put("Q13_Fin_Leverage", tq, g(q, "EquityMultiplier"))
  put("Q14_Current_Ratio", tq, g(q, "CurrentRatio"))
  put("Q15_Debt_to_Equity", tq, g(q, "DebtToEquity"))
  put("Q16_Debt_to_Assets", tq, g(q, "DebtToAssets"))
  put("Q17_ROIC", tq, g(q, "ROIC"))
  rg <- g(q, "Revenue_Growth"); og <- g(q, "OperatingProfit_Growth")
  put("Q18_Op_Leverage", tq, fifelse(is.finite(rg) & abs(rg) > 0.01 & is.finite(og), og / rg, NA_real_))   # 영업레버리지(1년 변화율 비)
  put("Q19_Cash_to_Assets", tq, g(q, "CashToAssets"))
  put("Q20_Net_Equity_Issuance", tq, -g(q, "NetShareIssuance"))                  # Pontiff & Woodgate(2008) · 음수 저장(자사주 = 양수)
  pr <- g(q, "PayoutRatio")
  put("Q23_Sustainable_Growth", tq, g(q, "ROE") * (1 - fifelse(is.finite(pr), pmin(pmax(pr, 0), 1), 0)))
  # Altman(1968) Z — 시가판: 1.2 WC/TA + 1.4 RE/TA + 3.3 EBIT/TA + 0.6 ME/TL + 1.0 Sales/TA
  TA <- g(q, "TotalAssets")
  put("Q24_Altman_Z", tq, 1.2 * sdv(g(q, "WorkingCapital"), TA) + 1.4 * sdv(g(q, "RetainedEarnings"), TA) + 3.3 * sdv(g(q, "EBIT"), TA) +
                          0.6 * sdv(MC, g(q, "TotalLiab")) + 1.0 * sdv(g(q, "Revenue"), TA))
  put("Q25_Ohlson_O", tq, -g(q, "OhlsonO"))                                      # Ohlson(1980) Model 1 전 항목(캐시) · 음수 저장(낮은 O = 좋음)
  put("Q26_RnD_Intensity", tq, g(q, "RandDIntensity"))
  put("Q27_CapEx_to_Rev", tq, -g(q, "CapexToRevenue"))                           # 음수 저장(낮은 투자 = 보수적 · CMA)
  cc <- g(q, "OCFToNI")
  put("Q28_Cash_Conversion", tq, fifelse(is.finite(cc) & abs(cc) < 10, cc, NA_real_))
  put("Q29_Inventory_Turnover", tq, g(q, "InventoryTurnover"))
  put("Q30_Receivables_Turnover", tq, g(q, "ReceivableTurnover"))
  put("Q31_WC_to_Assets", tq, g(q, "WorkingCapitalToAssets"))
  put("Q32_Interest_Coverage", tq, g(q, "InterestCoverage"))
  put("Q35_CashBased_OpProf", tq, g(q, "OCFToRevenue"))
  put("Q21_Revenue_Growth", tq, rg)
  put("Q22_Earnings_Growth", tq, g(q, "NIp_Growth"))

  # ---- 성장(GR) · 투자(IN) — TTM 1년 변화 ----
  put("GR01_Revenue_Growth", tq, rg)
  put("GR02_Earnings_Growth", tq, g(q, "NIp_Growth"))
  put("GR06_OCF_Growth", tq, g(q, "OperatingCF_Growth"))
  put("IN01_CapEx_to_Assets", tq, sdv(g(q, "InvestCF"), TA))                     # Titman, Wei & Xie(2004) — 구판 부호(투자활동 현금흐름 · 음수 = 지출)
  put("IN02_CapEx_to_Revenue", tq, sdv(g(q, "InvestCF"), g(q, "Revenue")))
  put("IN03_RD_to_Market", tq, sdv(g(q, "RandD"), MC))
  put("IN04_Net_Equity_Issuance", tq, -g(q, "NetShareIssuance"))                 # Bradshaw, Richardson & Sloan(2006)
  put("IN05_Net_Debt_Issuance", tq, -sdv(g(q, "d_TotalDebt"), g(q, "Lag_TotalAssets")))

  # ---- 발생액(AC) — TTM · 1년 변화 · 분모 = 1년 평균 총자산(AvgAssets) ----
  AV <- g(q, "AvgAssets"); NI <- g(q, "NetIncome"); OCF <- g(q, "OperatingCF")
  acc_cf <- sdv(NI - OCF, AV)                                                      # = 캐시 Accrual
  acc_bs <- sdv(g(q, "d_WorkingCapital"), AV)
  put("AC01_Total_Accruals_CF", tq, -acc_cf)
  put("AC11_Accruals_to_Assets", tq, -acc_cf)
  put("AC18_Accrual_Quality", tq, -acc_cf)
  put("AC07_Operating_Accruals", tq, -acc_cf)
  put("AC02_Total_Accruals_BS", tq, -acc_bs)
  put("AC03_WC_Accruals", tq, -sdv(g(q, "d_NWC_NonCash"), AV))                    # Sloan(1996) 운전자본 발생액(현금 · 단기차입 제외)
  put("AC04_NCO_Accruals", tq, -sdv(g(q, "d_NCO_Level"), AV))                     # Richardson et al.(2005) 비유동 영업 발생액
  put("AC05_NOA", tq, -g(q, "NOA"))                                               # Hirshleifer et al.(2004) 순영업자산 / 1년 전 총자산
  ac06 <- -sdv(g(q, "d_BookEquity") - g(q, "d_CashAndEquiv"), AV)                 # 구판 정의(Δ자기자본 − Δ현금) 그대로
  put("AC06_Comprehensive_Accruals", tq, ac06)
  put("AC08_Financial_Accruals", tq, ac06 - (-acc_cf))                            # 구판 정의(종합 − 영업) 그대로
  put("AC09_NNI", tq, -sdv(g(q, "d_NOA_Level"), AV))                              # Richardson, Sloan, Soliman & Tuna(2005)
  put("AC10_Pct_Accruals", tq, -g(q, "PercentAccrual"))                          # Hafzalla et al.(2011)
  put("AC12_Inventory_Accruals", tq, -sdv(g(q, "d_Inventory"), AV))
  put("AC16_BS_vs_CF_Diff", tq, -abs(acc_cf - acc_bs))
  put("AC17_Accrual_Reversal", tq, -abs(acc_cf - g(q, "Lag_Accrual")))
  put("AC19_Receivables_Accruals", tq, -sdv(g(q, "d_AccountsRecv"), AV))
  put("AC20_Payables_Accruals", tq, sdv(g(q, "d_AccountsPay"), AV))
  put("AC21_CF_to_Accrual_Ratio", tq, fifelse(is.finite(NI - OCF) & abs(NI - OCF) > 1e-8, OCF / abs(NI - OCF), NA_real_))
  put("AC24_NOA_Growth", tq, -sdv(g(q, "d_NOA_Level"), g(q, "Lag_TotalAssets")))
  # 수정 Jones 모형(Dechow, Sloan & Sweeney 1995) — 결정일 단면 회귀(전 종목 · PIT):
  #   TA_acc/A_{t-1} = b0 (1/A_{t-1}) + b1 (ΔREV − ΔREC)/A_{t-1} + b2 PPE/A_{t-1} + e · 비정상 = e · 정상 = 적합값
  LA <- g(q, "Lag_TotalAssets")
  jy <- sdv(NI - OCF, LA); jx0 <- sdv(1, LA); jx1 <- sdv(g(q, "d_Revenue") - g(q, "d_AccountsRecv"), LA); jx2 <- sdv(g(q, "PPE"), LA)
  okj <- is.finite(jy) & is.finite(jx0) & is.finite(jx1) & is.finite(jx2)
  if (sum(okj) >= 30L) {
    w <- function(x) { lo <- quantile(x[okj], 0.01); hi <- quantile(x[okj], 0.99); pmin(pmax(x, lo), hi) }
    fit <- lm.fit(cbind(w(jx0), w(jx1), w(jx2))[okj, , drop = FALSE], w(jy)[okj])
    res <- rep(NA_real_, length(jy)); res[okj] <- fit$residuals
    nda <- rep(NA_real_, length(jy)); nda[okj] <- w(jy)[okj] - fit$residuals
    put("AC13_Abnormal_Accruals", tq, -res)
    put("AC14_Discretionary_Accruals", tq, -abs(res))
    put("AC15_NonDiscretionary_Accruals", tq, nda)
  }
  # AC25 = AC01(음수 발생액) × z(−시가총액) — 소형주 저발생액
  zmc <- zs(-log(MC)); put("AC25_Accrual_Size_Interaction", tq, -acc_cf * zmc)

  # ======================= 연간(회계연도) 기준 =======================
  ta_ <- A$Ticker
  put("Q04_Piotroski_F", ta_, g(A, "PiotroskiF"))                                 # Piotroski(2000) 9개 신호(1년 전 대비)
  put("Q06_Asset_Growth", ta_, -g(A, "AssetGrowth"))                              # Cooper et al.(2008) · 음수 저장
  put("GR03_Asset_Growth", ta_, -g(A, "AssetGrowth"))
  put("Q07_Earnings_Stability", ta_, -g(A, "ROE_SD5"))                            # 5개 회계연도 ROE 표준편차(3개 이상) · 음수 저장
  put("Q33_Earnings_Persistence", ta_, g(A, "EarningsPersistence"))               # 10개 회계연도 ROA AR(1)
  put("GR04_GPA_Growth", ta_, g(A, "GPA_Delta5"))                                 # 5년 GPA 변화
  put("Q34_GP_Growth", ta_, g(A, "GPA_Delta5"))
  put("GR05_ROE_Growth", ta_, g(A, "ROE_Delta5"))                                 # 5년 ROE 변화
  put("IN06_Investment_to_Assets", ta_, -g(A, "PPE_InvGrowth"))                   # Lyandres, Sun & Zhang(2008) · 음수 저장
  put("AC22_Accrual_Volatility", ta_, -g(A, "Accrual_SD5"))
  put("AC23_Accrual_Persistence", ta_, -g(A, "AccrualPersistence"))

  # ======================= 합성 =======================
  R <- rbindlist(out, use.names = TRUE)
  if (!nrow(R)) return(empty)
  comp <- function(name, members, min_n = 2L) {
    M <- R[Factor_Name %in% members][, z := zs(Raw_Value), by = Factor_Name]
    C <- M[is.finite(z), .(v = mean(z), n = .N), by = Ticker][n >= min_n]
    if (nrow(C)) R <<- rbind(R, C[, .(Ticker, Factor_Name = name, Raw_Value = v)])
  }
  comp("Q08_Composite_Quality", c("Q01_GPA", "Q02_ROE", "Q03_ROA", "Q05_Accrual"))
  comp("GR07_Composite_Growth", c("GR01_Revenue_Growth", "GR02_Earnings_Growth", "GR03_Asset_Growth", "GR04_GPA_Growth",
                                  "GR05_ROE_Growth", "GR06_OCF_Growth"))
  R[is.finite(Raw_Value)]
}
