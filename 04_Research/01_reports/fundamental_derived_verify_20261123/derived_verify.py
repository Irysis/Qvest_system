# 재무 캐시 파생지표 독립 재계산 대조(쓰기 없음) — build_fundamental_caches.R 를 쓰지 않고 정의에서 다시 계산
# A. 입력(분기 단독) → 캐시 원계정(TTM · 잔액 · _Q) · 날짜(PIT)
# B. 캐시 원계정 → 파생 223 (분기 표 · 연간 표) — 1년 전 = (종목, 기간 − 100) 조회(R 의 행 이동과 다른 방식)
# C. 파생 날짜 ≥ 쓰인 해들의 원 분기 날짜
import sys, json, numpy as np, pandas as pd, pyarrow.dataset as ds
np.seterr(all="ignore")
ROOT = "G:/OneDrive/Quant_Module_Moltbot"
OUT = sys.argv[1]
NS = int(sys.argv[2]) if len(sys.argv) > 2 else 400
rep = json.load(open(f"{ROOT}/.cache/fundamental_caches_report.json", encoding="utf-8"))
STOCKS, FLOWS, DER = set(rep["stocks"]), list(rep["flows"]), rep["derived_items"]
nan = np.nan

din = ds.dataset(f"{ROOT}/.cache/fundamental_v2/fund_v2_quarterly.parquet")
allt = sorted(set(din.to_table(columns=["Ticker"]).column(0).to_pylist()))
rng = np.random.default_rng(20261123)
sample = sorted(set(rng.choice(allt, NS, replace=False).tolist()) | {"A005930", "A000660", "A035420", "A051910", "A005380", "A068270"})
flt = ds.field("Ticker").isin(sample)
inp = din.to_table(filter=flt, columns=["Ticker", "Period", "Item", "Value", "Factor_Date"]).to_pandas()
inp["P"] = inp.Period.astype(int); inp["FD"] = pd.to_datetime(inp.Factor_Date)
dup = inp.duplicated(["Ticker", "P", "Item"]).sum()
cq = ds.dataset(f"{ROOT}/.cache/fundamental_quarterly.parquet").to_table(filter=flt).to_pandas()
ca = ds.dataset(f"{ROOT}/.cache/fundamental_annual.parquet").to_table(filter=flt).to_pandas()
for c in (cq, ca): c["P"] = c.Period.astype(int); c["FD"] = pd.to_datetime(c.Factor_Date)
res = {"sample_tickers": len(sample), "input_dup_rows": int(dup)}

def mi(P): return (P // 100) * 12 + P % 100
def close(a, b): return np.isclose(a, b, rtol=1e-7, atol=1e-9)

# ---------- A. 입력 → 원계정 ----------
W = inp.pivot_table(index=["Ticker", "P"], columns="Item", values="Value", aggfunc="first")
rowfd = inp.groupby(["Ticker", "P"]).FD.max()
W = W.reset_index(); W["rowfd"] = rowfd.values; W["mi"] = mi(W.P)
key = pd.Series(np.arange(len(W)), index=pd.MultiIndex.from_arrays([W.Ticker, W.mi]))
def pos_back(months):
    idx = pd.MultiIndex.from_arrays([W.Ticker, W.mi - months])
    return key.reindex(idx).fillna(-1).astype(int).values
p3, p6, p9 = pos_back(3), pos_back(6), pos_back(9)
ok4 = (p3 >= 0) & (p6 >= 0) & (p9 >= 0)
def take(a, p): a = np.asarray(a, float); return np.where(p >= 0, a[np.maximum(p, 0)], nan)
exp = {}
for f in FLOWS:
    if f not in W: continue
    x = W[f].values.astype(float)
    exp[f] = np.where(ok4, x + take(x, p3) + take(x, p6) + take(x, p9), nan)
    exp[f + "_Q"] = x
for s in STOCKS:
    if s in W: exp[s] = W[s].values.astype(float)
fdn = W.rowfd.values.astype("datetime64[D]").astype(float)
fd0 = np.nanmax(np.vstack([fdn, take(fdn, p3), take(fdn, p6), take(fdn, p9)]), axis=0)
E = pd.DataFrame(exp); E["Ticker"] = W.Ticker.values; E["P"] = W.P.values; E["fd0"] = fd0
El = E.melt(id_vars=["Ticker", "P", "fd0"], var_name="Item", value_name="ev")
El = El[np.isfinite(El.ev)]
cr = cq[cq.Kind.isin(["raw", "raw_q"])].copy()
cr["Item2"] = cr.Item   # raw_q 항목 이름은 이미 '_Q' 로 끝난다
m = El.merge(cr[["Ticker", "P", "Item2", "Value", "FD"]].rename(columns={"Item2": "Item"}), on=["Ticker", "P", "Item"], how="outer")
both = m[m.ev.notna() & m.Value.notna()]
m["fdd"] = m.FD.values.astype("datetime64[D]").astype(float)
A = {"raw_pairs": int(len(both)), "raw_value_mismatch": int((~close(both.ev, both.Value)).sum()),
     "only_expected(drop_by_order_contract?)": int((m.ev.notna() & m.Value.isna()).sum()),
     "only_cache": int((m.ev.isna() & m.Value.notna()).sum()),
     "cache_fd_before_fd0": int((both.FD.values.astype("datetime64[D]").astype(float) < both.fd0.values).sum()),
     "cache_fd_le_period_end": 0}
res["A_input_to_raw"] = A
bad = both[~close(both.ev, both.Value)]
res["A_examples"] = bad.head(8).astype(str).to_dict("records")

# ---------- B. 원계정 → 파생 ----------
def derive(T):
    T = T.sort_values(["Ticker", "P"]).reset_index(drop=True)
    k = pd.Series(np.arange(len(T)), index=pd.MultiIndex.from_arrays([T.Ticker, T.P]))
    lp = k.reindex(pd.MultiIndex.from_arrays([T.Ticker, T.P - 100])).fillna(-1).astype(int).values
    g = lambda c: T[c].values.astype(float) if c in T else np.full(len(T), nan)
    L = lambda a: take(a, lp)
    fin = np.isfinite
    sdv = lambda n, d: np.where(fin(n) & fin(d) & (d > 0), n / np.where(d == 0, 1, d), nan)
    sda = lambda n, d: np.where(fin(n) & fin(d) & (d != 0), n / np.abs(np.where(d == 0, 1, d)), nan)
    def gr(x): p = L(x); return np.where(fin(x) & fin(p) & (p != 0), (x - p) / np.abs(np.where(p == 0, 1, p)), nan)
    def avg(x): p = L(x); return np.where(fin(x) & fin(p), (x + p) / 2, x)
    dlt = lambda x: x - L(x)
    z0 = lambda x: np.where(np.isnan(x), 0, x)
    def ind(a, b, op):  # R 비교 → 숫자(NA 전파)
        r = op(a, b).astype(float); r[~(fin(a) & fin(b))] = nan; return r
    gt = lambda a, b: ind(a, b, np.greater); lt = lambda a, b: ind(a, b, np.less)
    D = {}
    CB, CBo, LB, Bo = g("CurrentBorr"), g("CurrentBonds"), g("LongTermBorr"), g("Bonds")
    STD = np.where(np.isnan(CB) & np.isnan(CBo), nan, z0(CB) + z0(CBo))
    LTD = np.where(np.isnan(LB) & np.isnan(Bo), nan, z0(LB) + z0(Bo))
    TD = np.where(np.isnan(STD) & np.isnan(LTD), nan, z0(STD) + z0(LTD))
    STD = np.where(fin(TD) & np.isnan(STD), 0, STD); LTD = np.where(fin(TD) & np.isnan(LTD), 0, LTD)
    TA, TL, TE, CA, CL, Cash = g("TotalAssets"), g("TotalLiab"), g("TotalEquity"), g("CurrentAssets"), g("CurrentLiab"), g("CashAndEquiv")
    Rev, GP, OP, NI, OCF, Capex = g("Revenue"), g("GrossProfit"), g("OperatingProfit"), g("NetIncome"), g("OperatingCF"), g("Capex")
    D.update(ShortTermDebt=STD, LongTermDebt=LTD, TotalDebt=TD, NetDebtCalc=TD - Cash, WorkingCapital=CA - CL,
             NWC_NonCash=(CA - Cash) - (CL - z0(STD)))
    EP = g("EquityParent")
    BE = np.where(~np.isnan(EP), EP, TE - z0(g("NonControllingInt"))) - z0(g("PreferredCapital"))
    D.update(BookEquity=BE, TangibleEquity=BE - z0(g("Intangibles")), FCF=OCF - Capex)
    PT, Tax = g("PretaxIncome"), g("TaxExpense")
    TR = np.where(fin(PT) & (PT > 0), np.clip(Tax / np.where(PT == 0, 1, PT), 0, 1), nan)
    D.update(TaxRate=TR, NOPAT=OP * (1 - np.where(np.isnan(TR), 0, TR)))
    NIP = g("NetIncomeParent"); NIp = np.where(~np.isnan(NIP), NIP, NI)
    AA, AE = avg(TA), avg(BE)
    D.update(AvgAssets=AA, AvgEquity=AE, AvgInventory=avg(g("Inventory")), AvgRecv=avg(g("AccountsRecv")), AvgPay=avg(g("AccountsPay")),
             AvgInvestedCapital=avg(g("InvestedCapital")), AvgPPE=avg(g("PPE")))
    EBITDA, EBIT, IE = g("EBITDA"), g("EBIT"), g("InterestExp")
    D.update(GrossMargin=sdv(GP, Rev), OPM=sdv(OP, Rev), NetMargin=sdv(NIp, Rev), PretaxMargin=sdv(PT, Rev),
             EBITDA_Margin=sdv(EBITDA, Rev), EBIT_Margin=sdv(EBIT, Rev), ROE=sdv(NIp, AE), ROE_End=sdv(NIp, BE),
             ROA=sdv(NI, AA), ROA_End=sdv(NI, TA), ROIC=sdv(D["NOPAT"], D["AvgInvestedCapital"]),
             ROIC_NOPLAT=sdv(g("NOPLAT"), D["AvgInvestedCapital"]), GPA=sdv(GP, TA), OPA=sdv(OP, TA),
             OP_BE=sdv(OP - z0(IE), BE), CashOP=sdv(OCF, TA), ComprehensiveROE=sdv(g("CompIncParent"), AE), EBITDA_Assets=sdv(EBITDA, TA))
    COGS = g("COGS")
    D.update(AssetTurnover=sdv(Rev, AA), FixedAssetTurnover=sdv(Rev, D["AvgPPE"]), InventoryTurnover=sdv(COGS, D["AvgInventory"]),
             ReceivableTurnover=sdv(Rev, D["AvgRecv"]), PayableTurnover=sdv(COGS, D["AvgPay"]))
    D.update(DaysInventory=sdv(np.full(len(T), 365.0), D["InventoryTurnover"]), DaysReceivable=sdv(np.full(len(T), 365.0), D["ReceivableTurnover"]),
             DaysPayable=sdv(np.full(len(T), 365.0), D["PayableTurnover"]))
    D["CCC"] = D["DaysInventory"] + D["DaysReceivable"] - D["DaysPayable"]
    Emp = g("Employees")
    D.update(WorkingCapitalTurnover=sda(Rev, D["WorkingCapital"]), RevenuePerEmployee=sdv(Rev, Emp), OPPerEmployee=sdv(OP, Emp))
    ND = g("NetDebt")
    D.update(DebtRatio=sdv(TL, TE), LiabToAssets=sdv(TL, TA), DebtToAssets=sdv(TD, TA), DebtToEquity=sdv(TD, BE),
             IBDebtToAssets=sdv(g("InterestBearingDebt"), TA), NetDebtToEquity=sdv(ND, BE), NetDebtToEBITDA=sdv(ND, EBITDA),
             NetDebtToAssets=sdv(ND, TA), EquityMultiplier=sdv(TA, TE), EquityRatio=sdv(TE, TA), LongTermDebtRatio=sdv(LTD, TA),
             ShortDebtShare=sdv(STD, TD), InterestCoverage=sda(OP, IE), EBITDA_Coverage=sda(EBITDA, IE),
             ImpliedInterestRate=sdv(IE, avg(TD)), FinanceCostToRevenue=sdv(g("FinanceCost"), Rev))
    PPE, Inv, AR = g("PPE"), g("Inventory"), g("AccountsRecv")
    D.update(CurrentRatio=sdv(CA, CL), QuickRatio=sdv(g("QuickAssets"), CL), CashRatio=sdv(Cash, CL), CashToAssets=sdv(Cash, TA),
             WorkingCapitalToAssets=sdv(D["WorkingCapital"], TA), TangibleAssetRatio=sdv(PPE, TA), IntangibleRatio=sdv(g("Intangibles"), TA),
             NonCurrentAssetRatio=sdv(g("NonCurrentAssets"), TA), InvestmentsToAssets=sdv(g("Investments"), TA),
             InventoryToAssets=sdv(Inv, TA), RecvToAssets=sdv(AR, TA))
    FCF, Dep = D["FCF"], g("DepAmortCF")
    D.update(OCFToRevenue=sdv(OCF, Rev), OCFToNI=sda(OCF, NIp), OCFToLiab=sdv(OCF, TL), OCFToDebt=sdv(OCF, TD),
             FCFToRevenue=sdv(FCF, Rev), FCFToAssets=sdv(FCF, TA), FCFToEquity=sdv(FCF, BE), CapexToRevenue=sdv(Capex, Rev),
             CapexToAssets=sdv(Capex, AA), CapexToDep=sdv(Capex, Dep), Accrual=sdv(NI - OCF, AA), PercentAccrual=sda(NI - OCF, NI),
             AccrualBS=sdv(dlt(D["NWC_NonCash"]) - z0(Dep), AA),
             NOA=sdv((TA - Cash) - (TL - z0(TD)), L(TA)), CashEarningsToNI=sda(g("CashEarnings"), NIp))
    CDC, SO, SA = g("CashDivCommon"), g("SharesCommonOutAdj"), g("SharesCommonAvgAdj")
    LSO = L(SO)
    D.update(PayoutRatio=sdv(CDC, NIp), DividendToEquity=sdv(CDC, BE), DividendsPaidToOCF=sdv(g("DividendsPaid"), OCF),
             SharesGrowth=gr(SO), NetShareIssuance=np.where(fin(SO) & fin(LSO) & (LSO > 0), np.log(SO / np.where(LSO > 0, LSO, 1)), nan),
             BuybackRatio=sdv(g("BuybackShares"), SO), TreasuryShareRatio=sdv(g("TreasuryShares"), g("SharesCommonAdj")))
    SGA, RD = g("SGAExpense"), g("RandD")
    D.update(COGSRatio=sdv(COGS, Rev), SGARatio=sdv(SGA, Rev), RandDIntensity=sdv(RD, Rev), RandDToAssets=sdv(RD, TA),
             LaborCostRatio=sdv(g("LaborCost"), Rev), AdvertisingRatio=sdv(g("ExpAdvertising"), Rev), DepAmortRatio=sdv(Dep, Rev),
             EffectiveTaxRate=TR, NetInterestToRevenue=sdv(g("NetInterestExp"), Rev), SGAEfficiency=sdv(GP, SGA))
    D.update(BPS=sdv(BE, SO), EPS=sdv(NIp, SA), SPS=sdv(Rev, SA), CFPS=sdv(OCF, SA), DPS=g("AdjDPS"),
             LogAssets=np.where(fin(TA) & (TA > 0), np.log(np.where(TA > 0, TA, 1)), nan))
    base = dict(Revenue=Rev, GrossProfit=GP, OperatingProfit=OP, NetIncome=NI, NIp=NIp, EBITDA=EBITDA, OperatingCF=OCF, FCF=FCF,
                TotalAssets=TA, BookEquity=BE, Capex=Capex, CashDivCommon=CDC, Employees=Emp, InvestedCapital=g("InvestedCapital"),
                Inventory=Inv, AccountsRecv=AR, PPE=PPE, TotalDebt=TD, RandD=RD, SGAExpense=SGA, EPSParentAdj=g("EPSParentAdj"), AdjDPS=g("AdjDPS"))
    for it, x in base.items(): D[it + "_Growth"] = gr(x)
    D.update(AssetGrowth=sdv(dlt(TA), L(TA)), PPE_InvGrowth=sdv(dlt(PPE) + dlt(Inv), L(TA)), DebtGrowthToAssets=sdv(dlt(TD), L(TA)))
    D["InvestmentFF"] = D["AssetGrowth"]
    for it in ["GPA", "ROE", "ROA", "OPM", "GrossMargin", "NetMargin", "EBITDA_Margin", "Accrual", "InterestCoverage", "DebtRatio",
               "CurrentRatio", "CashToAssets", "AssetTurnover", "EquityMultiplier", "OCFToRevenue", "SGAEfficiency", "RandDIntensity",
               "TangibleAssetRatio", "DebtToAssets", "PayoutRatio", "CashOP", "OP_BE", "LongTermDebtRatio"]:
        D["Delta_" + it] = dlt(D[it])
    NOAL = (TA - Cash) - (TL - z0(TD)); NCOL = (g("NonCurrentAssets") - z0(g("Investments"))) - (g("NonCurrentLiab") - z0(LTD))
    D.update(NOA_Level=NOAL, NCO_Level=NCOL)
    src = dict(WorkingCapital=D["WorkingCapital"], NWC_NonCash=D["NWC_NonCash"], ShortTermDebt=STD, LongTermDebt=LTD, TotalDebt=TD,
               BookEquity=BE, NOA_Level=NOAL, NCO_Level=NCOL)
    for it in ["WorkingCapital", "NWC_NonCash", "CurrentAssets", "CashAndEquiv", "CurrentLiab", "ShortTermDebt", "LongTermDebt",
               "TotalDebt", "NonCurrentAssets", "NonCurrentLiab", "Investments", "Inventory", "AccountsRecv", "AccountsPay",
               "BookEquity", "TotalEquity", "PPE", "Revenue", "TotalAssets", "TotalLiab", "NOA_Level", "NCO_Level", "NetIncome",
               "OperatingCF", "SharesCommonOutAdj"]:
        D["d_" + it] = dlt(src[it] if it in src else g(it))
    D.update(Lag_TotalAssets=L(TA), Lag_NOA_Level=L(NOAL), Lag_Accrual=L(D["Accrual"]))
    def y5(x):
        for _ in range(5): x = L(x)
        return x
    D.update(GPA_Delta5=D["GPA"] - y5(D["GPA"]), ROE_Delta5=D["ROE_End"] - y5(D["ROE_End"]))
    D.update(PF_ROA=gt(D["ROA_End"], 0 * TA + 0), PF_CFO=gt(OCF, np.zeros(len(T))), PF_dROA=gt(dlt(D["ROA_End"]), np.zeros(len(T))),
             PF_Accrual=gt(OCF, NI), PF_dLever=lt(dlt(sdv(LTD, AA)), np.zeros(len(T))), PF_dLiquid=gt(dlt(D["CurrentRatio"]), np.zeros(len(T))),
             PF_dMargin=gt(dlt(D["GrossMargin"]), np.zeros(len(T))), PF_dTurn=gt(dlt(sdv(Rev, L(TA))), np.zeros(len(T))))
    D["PF_ROA"] = gt(D["ROA_End"], np.zeros(len(T)))
    eq = gt(SO, LSO); D["PF_EqIssue"] = np.where(np.isnan(eq), nan, 1 - eq)
    pf = np.vstack([D[c] for c in ["PF_ROA", "PF_CFO", "PF_dROA", "PF_Accrual", "PF_dLever", "PF_dLiquid", "PF_EqIssue", "PF_dMargin", "PF_dTurn"]])
    D["PiotroskiF"] = np.where(np.isnan(pf).any(axis=0), nan, pf.sum(axis=0))
    D["AltmanZ_Book"] = (0.717 * sdv(D["WorkingCapital"], TA) + 0.847 * sdv(g("RetainedEarnings"), TA) + 3.107 * sdv(EBIT, TA)
                         + 0.420 * sdv(BE, TL) + 0.998 * sdv(Rev, TA))
    CE = g("CashEarnings"); LNI = L(NI)
    # R 의 & : NA & FALSE = FALSE
    a, b = NI < 0, LNI < 0; av, bv = fin(NI), fin(LNI)
    intwo = np.where((av & ~a) | (bv & ~b), 0.0, np.where(av & bv, 1.0, nan))
    D.update(O_SIZE=D["LogAssets"], O_TLTA=sdv(TL, TA), O_WCTA=sdv(D["WorkingCapital"], TA), O_CLCA=sdv(CL, CA), O_OENEG=gt(TL, TA),
             O_NITA=sdv(NI, TA), O_FUTL=sdv(np.where(fin(CE), CE, OCF), TL), O_INTWO=intwo,
             O_CHIN=np.where(fin(NI) & fin(LNI) & ((np.abs(NI) + np.abs(LNI)) > 0), (NI - LNI) / np.where((np.abs(NI) + np.abs(LNI)) > 0, np.abs(NI) + np.abs(LNI), 1), nan))
    D["OhlsonO"] = (-1.32 - 0.407 * D["O_SIZE"] + 6.03 * D["O_TLTA"] - 1.43 * D["O_WCTA"] + 0.0757 * D["O_CLCA"] - 1.72 * D["O_OENEG"]
                    - 2.37 * D["O_NITA"] - 1.83 * D["O_FUTL"] + 0.285 * D["O_INTWO"] - 0.521 * D["O_CHIN"])
    def lagmat(x, n):
        M = [x]; cur = x
        for _ in range(n - 1): cur = L(cur); M.append(cur)
        return np.vstack(M).T
    def roll_sd(x, n=5, mn=3):
        M = lagmat(x, n); cnt = np.isfinite(M).sum(1)
        with np.errstate(all="ignore"): s = np.nanstd(M, axis=1, ddof=1)
        return np.where(cnt >= mn, s, nan)
    def ar1(x, n=10, mn=4):
        M = lagmat(x, n); Y, X = M[:, :-1], M[:, 1:]; ok = np.isfinite(Y) & np.isfinite(X); c = ok.sum(1)
        Y = np.where(ok, Y, 0); X = np.where(ok, X, 0); mx = X.sum(1) / np.maximum(c, 1); my = Y.sum(1) / np.maximum(c, 1)
        sxy = (X * Y).sum(1) - c * mx * my; sxx = (X * X).sum(1) - c * mx * mx
        return np.where((c >= mn - 1) & (sxx > 1e-12), sxy / np.where(sxx > 1e-12, sxx, 1), nan)
    D.update(ROE_SD5=roll_sd(D["ROE_End"]), ROA_SD5=roll_sd(D["ROA_End"]), GrossMargin_SD5=roll_sd(D["GrossMargin"]),
             Revenue_Growth_SD5=roll_sd(D["Revenue_Growth"]), OPM_SD5=roll_sd(D["OPM"]), EarningsPersistence=ar1(D["ROA_End"]),
             Accrual_SD5=roll_sd(D["Accrual"]), AccrualPersistence=ar1(D["Accrual"]))
    O = pd.DataFrame(D); O["Ticker"] = T.Ticker.values; O["P"] = T.P.values
    return O

def compare(cache, label):
    raw = cache[cache.Kind == "raw"].pivot_table(index=["Ticker", "P"], columns="Item", values="Value", aggfunc="first").reset_index()
    # 원계정 값이 하나도 없는 행(파생만 남은 행)도 1년 전 조회의 '행'으로 존재해야 한다
    rows = cache[["Ticker", "P"]].drop_duplicates()
    raw = rows.merge(raw, on=["Ticker", "P"], how="left")
    O = derive(raw)
    der = cache[cache.Kind == "derived"][["Ticker", "P", "Item", "Value"]]
    Ol = O.melt(id_vars=["Ticker", "P"], var_name="Item", value_name="mine")
    Ol = Ol[np.isfinite(Ol.mine)]
    mm = Ol.merge(der, on=["Ticker", "P", "Item"], how="outer")
    out = []
    for it, g in mm.groupby("Item"):
        b = g[g.mine.notna() & g.Value.notna()]
        out.append(dict(item=it, n_cache=int(g.Value.notna().sum()), n_mine=int(g.mine.notna().sum()),
                        mismatch=int((~close(b.mine, b.Value)).sum()), only_cache=int((g.mine.isna() & g.Value.notna()).sum()),
                        only_mine=int((g.mine.notna() & g.Value.isna()).sum())))
    R = pd.DataFrame(out)
    R["covered"] = R.item.isin(O.columns)
    missing = sorted(set(cache[cache.Kind == "derived"].Item) - set(O.columns))
    return R, mm, missing

Rq, mmq, missq = compare(cq, "q")
Ra, mma, missa = compare(ca, "a")
Rq.to_csv(f"{OUT}/derived_verify_quarterly.csv", index=False); Ra.to_csv(f"{OUT}/derived_verify_annual.csv", index=False)
for lab, R, miss in (("quarterly", Rq, missq), ("annual", Ra, missa)):
    res[f"B_{lab}"] = dict(items=len(R), pairs=int((R.n_cache).sum()), mismatch_items=int((R.mismatch > 0).sum()),
                           mismatch_rows=int(R.mismatch.sum()), only_cache_rows=int(R.only_cache.sum()), only_mine_rows=int(R.only_mine.sum()),
                           not_recomputed=miss,
                           worst=R.assign(bad=R.mismatch + R.only_cache + R.only_mine).sort_values("bad", ascending=False).head(15).to_dict("records"))

# 연간 원계정 = 분기 표 같은 기간 원계정(TTM = 회계연도 합)
ar = ca[ca.Kind == "raw"][["Ticker", "P", "Item", "Value"]].merge(cq[cq.Kind == "raw"][["Ticker", "P", "Item", "Value"]], on=["Ticker", "P", "Item"], how="left", suffixes=("_a", "_q"))
res["annual_raw_eq_quarterly_raw"] = dict(rows=len(ar), missing_in_q=int(ar.Value_q.isna().sum()), mismatch=int((~close(ar.Value_a, ar.Value_q.fillna(-9e99))).sum() - ar.Value_q.isna().sum()))
fmq = ds.dataset(f"{ROOT}/.cache/qw_fund_v2/fiscal_month.parquet").to_table().to_pandas()
fmq["FiscalMonth"] = pd.to_numeric(fmq.FiscalMonth, errors="coerce").fillna(12).astype(int)
aa = ca[["Ticker", "P"]].drop_duplicates().merge(fmq[["Ticker", "FiscalMonth"]], on="Ticker", how="left")
res["annual_rows_not_fiscal_month"] = int((aa.P % 100 != aa.FiscalMonth.fillna(12)).sum())

# ---------- C. 파생 날짜 ≥ 쓰인 해(최대 10개 해)의 원 분기 날짜(입력 기준 fd0) ----------
def date_check(cache, label):
    f = E[["Ticker", "P", "fd0"]].copy()
    d = cache[cache.Kind == "derived"][["Ticker", "P", "Item", "FD", "Period_Date"]].copy()
    d["fdd"] = d.FD.values.astype("datetime64[D]").astype(float)
    worst = d[["Ticker", "P"]].drop_duplicates()
    worst["need"] = -np.inf
    for k in range(10):
        x = f.rename(columns={"fd0": f"f{k}"}); x["P"] = x.P + 100 * k
        worst = worst.merge(x, on=["Ticker", "P"], how="left")
        worst["need"] = np.fmax(worst.need, worst[f"f{k}"]); worst = worst.drop(columns=f"f{k}")
    d = d.merge(worst, on=["Ticker", "P"], how="left")
    # 연간 표 회계 베타는 시장 중앙값 날짜까지 더하므로 더 늦을 수 있다(늦은 쪽은 위반 아님)
    v = d[d.fdd < d.need]
    pdd = pd.to_datetime(d.Period_Date)
    return dict(rows=len(d), before_input_dates=int(len(v)), items_with_violation=sorted(v.Item.unique().tolist())[:20],
                fd_le_period_end=int((d.FD <= pdd).sum()))
res["C_dates_quarterly"] = date_check(cq, "q")
# 연간 표의 fd0 = 회계연도 말 행의 TTM 날짜 = 분기 표 fd0 와 같은 행
res["C_dates_annual"] = date_check(ca, "a")

# ---------- D. 원계정 날짜 규칙(pit.md C4): 분기 행 Factor_Date − 기간 말 ≥ 45 + 45 · 회계연도 말 ≥ 90 + 45 ----------
ii = inp.merge(fmq[["Ticker", "FiscalMonth"]], on="Ticker", how="left")
ii["PD"] = pd.to_datetime(ii.P.astype(str) + "01") + pd.offsets.MonthEnd(0)
ii["gap"] = (ii.FD - ii.PD).dt.days
ii["fy"] = (ii.P % 100) == ii.FiscalMonth.fillna(12)
res["D_input_lag_days"] = dict(fy_end_min=int(ii[ii.fy].gap.min()), fy_end_lt135=int((ii[ii.fy].gap < 135).sum()),
                               quarter_min=int(ii[~ii.fy].gap.min()), quarter_lt90=int((ii[~ii.fy].gap < 90).sum()))
json.dump(res, open(f"{OUT}/derived_verify_summary.json", "w", encoding="utf-8"), ensure_ascii=False, indent=1, default=str)
print(json.dumps(res, ensure_ascii=False, indent=1, default=str)[:9000])

# ---------- E. 불일치 행 원인 분류(분기 표): 1년 전 행 규칙(R = 4행 전이 정확히 12개월 전) · 순서 계약으로 빠진 원계정 ----------
q2 = cq[["Ticker", "P"]].drop_duplicates().sort_values(["Ticker", "P"]).reset_index(drop=True)
q2["mi"] = mi(q2.P)
sh_t, sh_m = q2.Ticker.shift(4), q2.mi.shift(4)
q2["r_lag_ok"] = (sh_t == q2.Ticker) & (sh_m == q2.mi - 12)
kk = set(zip(q2.Ticker, q2.P)); q2["spec_lag_ok"] = [(t, p - 100) in kk for t, p in zip(q2.Ticker, q2.P)]
q2["lag_rule_differs"] = q2.r_lag_ok != q2.spec_lag_ok
# 순서 계약으로 빠진 원계정이 있는 행(입력 TTM 기대값은 있는데 캐시에 없는 (종목, 기간))
dropped_rows = set(map(tuple, m[m.ev.notna() & m.Value.isna()][["Ticker", "P"]].drop_duplicates().values))
bad = mmq[(mmq.mine.notna() | mmq.Value.notna())].copy()
bad["is_bad"] = ~(bad.mine.notna() & bad.Value.notna() & close(bad.mine.fillna(0), bad.Value.fillna(0)))
bad = bad[bad.is_bad].merge(q2[["Ticker", "P", "lag_rule_differs"]], on=["Ticker", "P"], how="left")
def lagrow_dropped(t, p):
    return any((t, p - 100 * k) in dropped_rows for k in range(0, 12))
bad["dropped_raw_nearby"] = [lagrow_dropped(t, p) for t, p in zip(bad.Ticker, bad.P)]
lag_bad_rows = set(map(tuple, q2[q2.lag_rule_differs][["Ticker", "P"]].values))
bad["lag_rule_nearby"] = [any((t, p - 100 * k) in lag_bad_rows for k in range(0, 12)) for t, p in zip(bad.Ticker, bad.P)]
bad["cls"] = np.select([bad.lag_rule_nearby, bad.dropped_raw_nearby], ["lag_rule", "order_drop"], "unexplained")
res["E_quarterly_mismatch_classes"] = bad.cls.value_counts().to_dict()
res["E_unexplained_examples"] = bad[bad.cls == "unexplained"].head(10).astype(str).to_dict("records")
res["E_lag_rule_differs_rows"] = int(q2.lag_rule_differs.sum()); res["E_rows"] = len(q2)
res["E_lag_rule_examples"] = q2[q2.lag_rule_differs].head(6).astype(str).to_dict("records")
json.dump(res, open(f"{OUT}/derived_verify_summary.json", "w", encoding="utf-8"), ensure_ascii=False, indent=1, default=str)
for k in ["A_input_to_raw", "E_quarterly_mismatch_classes", "E_lag_rule_differs_rows", "E_rows", "E_unexplained_examples", "E_lag_rule_examples"]:
    print(k, json.dumps(res[k], ensure_ascii=False, default=str)[:3000])
