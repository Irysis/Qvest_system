##=============================================================================
## factor_db_daily_phase8.R — Fund/Consensus/Composite GAP 팩터 (57개)
## Phase 6+7 parquet에 additive merge (월별 fund rolling join)
##=============================================================================

cat("═══ Phase 8: Fund/Consensus/Composite GAP (57개) ═══\n")
cat("시각:", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n\n")

suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite); library(Rcpp)
})

.SELF_DIR <- tryCatch(dirname(sys.frame(1)$ofile),
  error = function(e) "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot/02_Infrastructure/factor_db")
INFRA_DIR <- tryCatch(dirname(dirname(sys.frame(1)$ofile)),
  error = function(e) "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot/02_Infrastructure")
source(file.path(INFRA_DIR, "config.R"))
sourceCpp(file.path(.SELF_DIR, "factor_db_daily_rcpp.cpp"))

FDB_DIR <- file.path(CACHE_DIR, "factor_db_daily")
CONS_DIR_PATH <- file.path(CACHE_DIR, "consensus")
OUT_START <- as.Date("1990-01-01")
t0 <- proc.time()

safe_div <- function(a, b, min_b=0) fifelse(!is.na(a) & !is.na(b) & abs(b) > min_b, a/b, NA_real_)
lag_n <- function(x, n) { m <- length(x); if(m<=n) rep(NA_real_,m) else c(rep(NA_real_,n), x[1:(m-n)]) }

# ═══ 1. Fundamental 데이터 준비 ═════════════════════════════════════════════
cat("[1/4] 데이터 준비...\n")

FUND <- as.data.table(read_parquet(file.path(CACHE_DIR, "fundamental_merged.parquet")))
FUND[, Factor_Date := as.Date(Factor_Date)]

FUND_ITEMS <- c("TotalEquity","Revenue","NetIncome","OperatingProfit","TotalAssets",
  "TotalLiab","CashAndEquiv","GrossProfit","OperatingCF","DepAmort","RandD",
  "RetainedEarnings","CapitalStock","COGS","SGAExpense","PretaxIncome",
  "CurrentAssets","CurrentLiab","AccountsRecv","Inventory","AccountsPay",
  "TotalDebt","ShortTermBorr","InvestCF","FinanceCF","Dividends","WorkingCapital","FCF2",
  "InterestExp","InterestIncome","TangibleAssets","IntangibleAssets","NonCurrentAssets","NonCurrentLiab")

fund_sub <- FUND[Item %in% FUND_ITEMS]
fund_sub <- fund_sub[, .(Value=Value[.N]), by=.(Ticker, Factor_Date, Item)]
fund_wide <- dcast(fund_sub, Ticker + Factor_Date ~ Item, value.var="Value")
setnames(fund_wide, "Factor_Date", "Date")
setkey(fund_wide, Ticker, Date)
# locf forward-fill
item_cols <- setdiff(names(fund_wide), c("Ticker","Date"))
for(ic in item_cols) fund_wide[, (ic) := nafill(get(ic), type="locf"), by=Ticker]

# prev period (YoY growth)
fund_prev <- fund_sub[, {
  d <- sort(unique(Factor_Date))
  if(length(d) >= 2) .SD[Factor_Date == d[length(d)-1]] else NULL
}, by=.(Ticker, Item)]
fp_wide <- NULL
if(nrow(fund_prev) > 0) {
  fp_wide <- dcast(fund_prev, Ticker + Factor_Date ~ Item, value.var="Value")
  setnames(fp_wide, "Factor_Date", "Date")
  prev_cols <- setdiff(names(fp_wide), c("Ticker","Date"))
  setnames(fp_wide, prev_cols, paste0("prev_", prev_cols))
  setkey(fp_wide, Ticker, Date)
  for(pc in paste0("prev_", prev_cols)) fp_wide[, (pc) := nafill(get(pc), type="locf"), by=Ticker]
}

# Consensus 로드
cons_data <- list()
for(item in c("target_price","eps_1y","bps_1y","dps_1y","sue","eps_chg_1m","eps_chg_3m",
              "esbr","escr","coverage","revenue_fy1","op_profit_fy1")) {
  fp <- file.path(CONS_DIR_PATH, paste0(item, ".parquet"))
  if(!file.exists(fp)) next
  cc <- as.data.table(read_parquet(fp))
  cc[, Date := as.Date(Date)]
  vc <- setdiff(names(cc), c("Date","Ticker"))
  if(length(vc)==0) next
  cc <- cc[, .(Ticker, Date, val=get(vc[1]))]
  setnames(cc, "val", item)
  setkey(cc, Ticker, Date)
  cons_data[[item]] <- cc
}

# RAWDATA Close/Size
RW <- as.data.table(read_parquet(RAWDATA_CACHE))
RW_PRICE <- RW[Date >= OUT_START, .(Ticker, Date, Close, Size, Ret)]
RW_PRICE[, YM := format(Date, "%Y%m")]
setkey(RW_PRICE, Ticker, Date)
rm(RW, FUND, fund_sub); gc(verbose=FALSE)
cat("  완료.\n\n")

# ═══ 2. 월별 루프: Fund GAP + Consensus GAP 계산 + merge ═══════════════════
cat("[2/4] 월별 Fund/Consensus GAP 계산...\n")
t1 <- proc.time()

files <- sort(list.files(FDB_DIR, pattern="fdb_daily_.*parquet", full.names=TRUE))
months <- gsub(".*fdb_daily_(\\d+)\\.parquet","\\1", basename(files))
pb <- max(1L, length(files) %/% 20L)

for(i in seq_along(files)) {
  ym <- months[i]
  chunk <- as.data.table(read_parquet(files[i]))
  setkey(chunk, Date, Ticker)

  # ─── Fund rolling join for this month ──────────────────────────────
  price_ym <- RW_PRICE[YM == ym, .(Ticker, Date, Close, Size, Ret)]
  if(nrow(price_ym) == 0) next
  setkey(price_ym, Ticker, Date)
  fd <- fund_wide[price_ym, roll=Inf, on=.(Ticker, Date)]
  # Size/Close/Ret 보존 후 fp_wide join
  .sz <- fd$Size; .cl <- fd$Close; .rt <- fd$Ret
  if(!is.null(fp_wide)) fd <- fp_wide[fd, roll=Inf, on=.(Ticker, Date)]
  # fp_wide join 후 Size/Close/Ret 복원
  fd[, Size := .sz]; fd[, Close := .cl]; fd[, Ret := .rt]

  # ─── Fund GAP 팩터 ────────────────────────────────────────────────
  # Accrual GAP (9)
  fd[, AC06_Comprehensive_Accruals := -safe_div(
    fifelse(is.na(TotalEquity),0,TotalEquity)-fifelse(is.na(prev_TotalEquity),0,prev_TotalEquity)-
    (fifelse(is.na(CashAndEquiv),0,CashAndEquiv)-fifelse(is.na(prev_CashAndEquiv),0,prev_CashAndEquiv)),
    pmax(abs(TotalAssets),1))]
  fd[, AC11_Accruals_to_Assets := -safe_div(NetIncome-OperatingCF, TotalAssets)]
  fd[, AC18_Accrual_Quality := -safe_div(NetIncome-OperatingCF, TotalAssets)]
  fd[, AC21_CF_to_Accrual_Ratio := safe_div(OperatingCF, abs(NetIncome-OperatingCF), 1e-6)]
  fd[, AC24_NOA_Growth := -safe_div(
    (TotalAssets-fifelse(is.na(CashAndEquiv),0,CashAndEquiv))-(TotalLiab-fifelse(is.na(TotalDebt),0,TotalDebt))-
    (fifelse(is.na(prev_TotalAssets),0,prev_TotalAssets)-fifelse(is.na(prev_CashAndEquiv),0,prev_CashAndEquiv)-
     (fifelse(is.na(prev_TotalLiab),0,prev_TotalLiab)-fifelse(is.na(prev_TotalDebt),0,prev_TotalDebt))),
    pmax(abs(prev_TotalAssets),1))]
  fd[, AC25_Accrual_Size_Interaction := -safe_div(NetIncome-OperatingCF, TotalAssets) * log(pmax(Size,1))]
  # AC17 Reversal, AC22 Vol, AC23 Persistence — 다기간 필요 → proxy
  fd[, AC17_Accrual_Reversal := abs(safe_div(NetIncome-OperatingCF, TotalAssets) -
      safe_div(prev_NetIncome-prev_OperatingCF, prev_TotalAssets))]
  fd[, AC22_Accrual_Volatility := abs(safe_div(NetIncome-OperatingCF, TotalAssets))]
  fd[, AC23_Accrual_Persistence := safe_div(NetIncome-OperatingCF, TotalAssets)]

  # Growth GAP (4)
  fd[, GR04_GPA_Growth := safe_div(
    safe_div(GrossProfit,TotalAssets)-safe_div(prev_GrossProfit,prev_TotalAssets),
    abs(safe_div(prev_GrossProfit,prev_TotalAssets)), 1e-6)]
  fd[, GR05_ROE_Growth := safe_div(
    safe_div(NetIncome,TotalEquity)-safe_div(prev_NetIncome,prev_TotalEquity),
    abs(safe_div(prev_NetIncome,prev_TotalEquity)), 1e-6)]
  fd[, GR06_OCF_Growth := safe_div(OperatingCF-prev_OperatingCF, abs(prev_OperatingCF), 1e-6)]

  # Investment GAP (2)
  fd[, IN05_Net_Debt_Issuance := -safe_div(TotalDebt-prev_TotalDebt, TotalAssets, 1e-6)]
  fd[, IN06_Investment_to_Assets := -safe_div(
    (TangibleAssets-prev_TangibleAssets)+(Inventory-prev_Inventory),
    pmax(abs(prev_TotalAssets),1))]

  # Quality GAP (7)
  # Q04 Piotroski F-Score (9 binary signals)
  fd[, Q04_Piotroski_F := {
    roa <- safe_div(NetIncome, TotalAssets)
    roa_p <- safe_div(prev_NetIncome, prev_TotalAssets)
    cfo <- safe_div(OperatingCF, TotalAssets)
    lev <- safe_div(TotalDebt, TotalAssets)
    lev_p <- safe_div(prev_TotalDebt, prev_TotalAssets)
    cr <- safe_div(CurrentAssets, CurrentLiab)
    cr_p <- safe_div(prev_CurrentAssets, prev_CurrentLiab)
    gm <- safe_div(GrossProfit, Revenue)
    gm_p <- safe_div(prev_GrossProfit, prev_Revenue)
    at <- safe_div(Revenue, TotalAssets)
    at_p <- safe_div(prev_Revenue, prev_TotalAssets)
    as.double(
      fifelse(!is.na(roa) & roa>0, 1, 0) + fifelse(!is.na(roa)&!is.na(roa_p)&roa>roa_p, 1, 0) +
      fifelse(!is.na(cfo) & cfo>0, 1, 0) + fifelse(!is.na(cfo)&!is.na(roa)&cfo>roa, 1, 0) +
      fifelse(!is.na(lev)&!is.na(lev_p)&lev<lev_p, 1, 0) + fifelse(!is.na(cr)&!is.na(cr_p)&cr>cr_p, 1, 0) +
      fifelse(!is.na(gm)&!is.na(gm_p)&gm>gm_p, 1, 0) + fifelse(!is.na(at)&!is.na(at_p)&at>at_p, 1, 0) +
      0)  # no new shares proxy = 0 (data not available)
  }]
  fd[, Q07_Earnings_Stability := abs(safe_div(NetIncome-prev_NetIncome, pmax(abs(prev_NetIncome),1)))]
  fd[, Q23_Sustainable_Growth := safe_div(NetIncome, TotalEquity)*(1-safe_div(Dividends, abs(NetIncome)))]
  fd[, Q24_Altman_Z := {
    wc <- CurrentAssets-fifelse(is.na(CurrentLiab),0,CurrentLiab)
    1.2*safe_div(wc,TotalAssets)+1.4*safe_div(RetainedEarnings,TotalAssets)+
    3.3*safe_div(OperatingProfit,TotalAssets)+0.6*safe_div(Size,TotalLiab)+
    1.0*safe_div(Revenue,TotalAssets)
  }]
  fd[, Q25_Ohlson_O := -safe_div(TotalLiab, TotalAssets)]
  fd[, Q33_Earnings_Persistence := safe_div(NetIncome, TotalAssets)]  # proxy: current ROA

  # Value GAP (8)
  fd[, V09_PEG := safe_div(safe_div(Close,fifelse(is.na(NetIncome/4e9),NA_real_,NetIncome/4e9)),
      abs(safe_div(NetIncome-prev_NetIncome, abs(prev_NetIncome))*100), 1e-6)]
  fd[, V15_NetDebt_Adj_EP := safe_div(NetIncome, Size+TotalDebt-fifelse(is.na(CashAndEquiv),0,CashAndEquiv))]
  fd[, V17_Payout_Ratio := safe_div(Dividends, abs(NetIncome), 1e-6)]
  fd[, V19_Debt_to_Market := safe_div(TotalDebt, Size)]
  ev <- fd$Size+fifelse(is.na(fd$TotalDebt),0,fd$TotalDebt)-fifelse(is.na(fd$CashAndEquiv),0,fd$CashAndEquiv)
  fd[, V22_FCFF_EV := safe_div(OperatingCF-abs(fifelse(is.na(InvestCF),0,InvestCF)), ev)]

  # Composite factors (cross-sectional z-score → proxy with raw for now)
  # GR07, Q08, V12, R19, M09, L45, M32 — 이 값들은 개별 팩터의 평균으로 근사
  # 정확한 cross-sectional composite는 전 종목 z-score 필요 → 별도 post-processing
  fd[, GR07_Composite_Growth := (fifelse(is.na(GR04_GPA_Growth),0,GR04_GPA_Growth)+
      fifelse(is.na(GR05_ROE_Growth),0,GR05_ROE_Growth)+
      fifelse(is.na(GR06_OCF_Growth),0,GR06_OCF_Growth))/3]
  fd[, Q08_Composite_Quality := (fifelse(is.na(Q04_Piotroski_F),0,Q04_Piotroski_F/9)+
      fifelse(is.na(Q24_Altman_Z),0,pmin(Q24_Altman_Z/10,1)))/2]
  fd[, V12_Composite_Value := (safe_div(TotalEquity,Size)+safe_div(NetIncome,Size)+
      safe_div(OperatingCF,Size))/3]
  fd[, V21_Composite_Equity_Issuance := log(pmax(Size/pmax(shift(Size,252L,type="lag"),1),1e-9)), by=Ticker]
  fd[, V23_RAFI_Weight := (safe_div(Revenue,1e12)+safe_div(OperatingCF,1e12)+
      safe_div(TotalEquity,1e12)+safe_div(Dividends,1e12))/4]
  fd[, R19_Composite_Risk := 0]  # placeholder

  # 팩터 컬럼 추출
  gap_cols <- grep("^AC[0-9]|^GR0[4-7]|^IN0[56]|^Q0[4-8]|^Q2[3-5]|^Q33|^V0[9]|^V1[25789]|^V2[123]|^R19",
                   names(fd), value=TRUE)
  fd_out <- fd[, c("Ticker","Date",gap_cols), with=FALSE]
  setkey(fd_out, Date, Ticker)

  # ─── Consensus GAP 팩터 ───────────────────────────────────────────
  # Rolling join consensus into price_ym
  cp <- copy(price_ym)
  for(cname in names(cons_data)) {
    cc <- cons_data[[cname]]
    cc_sub <- cc[Date <= max(cp$Date) & Date >= min(cp$Date) - 90]
    if(nrow(cc_sub) > 0) cp <- cc_sub[cp, roll=Inf, on=.(Ticker, Date)]
  }

  # Consensus-derived GAP
  if("target_price" %in% names(cp)) {
    tp_lag <- lag_n(cp$target_price, 35L)  # ~35 trading days
    cp[, C07_TP_Mom := safe_div(target_price - tp_lag, abs(tp_lag))]
  }
  if("sue" %in% names(cp)) {
    cp[, C09_Earnings_Surprise_Sq := fifelse(!is.na(sue), sign(sue)*sue^2, NA_real_)]
    cp[, C10_SUE_Persistence := roll_mean_cpp(fifelse(is.na(sue),0,sue), 63L)]
    cp[, C11_Earnings_Streak := roll_sum_cpp(fifelse(!is.na(sue)&sue>0,1,0), 252L)]
    cp[, C15_Forecast_Error_Trend := sue - lag_n(sue, 63L)]
  }
  if("eps_chg_1m" %in% names(cp) && "eps_chg_3m" %in% names(cp)) {
    cp[, C12_Estimate_Dispersion_Proxy := abs(eps_chg_1m - eps_chg_3m)]
    cp[, C16_EPS_Acceleration := eps_chg_1m - eps_chg_3m/3]
  }
  if("esbr" %in% names(cp)) {
    cp[, C13_Revision_Breadth_3m := roll_mean_cpp(fifelse(is.na(esbr),0,esbr), 63L)]
  }
  if("revenue_fy1" %in% names(cp)) {
    rv_lag <- lag_n(cp$revenue_fy1, 63L)
    cp[, C14_Revenue_Surprise := safe_div(revenue_fy1 - rv_lag, abs(rv_lag))]
    cp[, M26_Revenue_Mom := safe_div(revenue_fy1 - rv_lag, abs(rv_lag))]
  }
  if("op_profit_fy1" %in% names(cp)) {
    op_lag <- lag_n(cp$op_profit_fy1, 63L)
    cp[, C17_OP_Revision := safe_div(op_profit_fy1 - op_lag, abs(op_lag))]
    cp[, M28_OP_Rev_Mom := safe_div(op_profit_fy1 - op_lag, abs(op_lag))]
  }
  if("eps_chg_1m" %in% names(cp)) {
    cp[, M27_Analyst_Rev_Mom := eps_chg_1m]
    cp[, SE02_Consensus_Revision := eps_chg_1m]
  }
  # C18 Earnings CAR proxy
  cp[, C18_Earnings_CAR_3d := roll_cumret_cpp(Ret, 3L)]
  # C19 Composite
  cp[, C19_Composite_Earnings := 0]  # placeholder
  # M25 Earnings Mom Streak
  if("sue" %in% names(cp)) cp[, M25_Earnings_Mom_Streak := C11_Earnings_Streak]
  # D28/D29 (Fund-dependent)
  cp[, D28_Unlevered_Beta := NA_real_]
  cp[, D29_Accounting_Beta := NA_real_]
  # M07 IndMom, M09, M21, M24, M31, M32 — cross-sectional → placeholder
  cp[, M07_IndMom := NA_real_]
  cp[, M09_Composite_Mom := NA_real_]
  cp[, M21_Seasonality := NA_real_]
  cp[, M24_Sector_Rel_Mom := NA_real_]
  cp[, M31_Breadth_Mom := NA_real_]
  cp[, M32_Composite_Mom_v2 := NA_real_]
  cp[, L45_Composite_Liquidity := NA_real_]

  cons_gap <- grep("^C0[7-9]|^C1[0-9]|^M2[5-8]|^M0[79]|^M21|^M24|^M3[12]|^SE02|^D2[89]|^C18|^C19|^L45",
                   names(cp), value=TRUE)
  cp_out <- cp[, c("Ticker","Date",cons_gap), with=FALSE]
  setkey(cp_out, Date, Ticker)

  # ─── Merge all into chunk ──────────────────────────────────────────
  chunk <- merge(chunk, fd_out, by=c("Date","Ticker"), all.x=TRUE)
  chunk <- merge(chunk, cp_out, by=c("Date","Ticker"), all.x=TRUE)

  write_parquet(chunk, files[i], compression="snappy")
  if(i %% pb == 0 || i == length(files))
    cat(sprintf("  [%d/%d] %s (%d cols)\n", i, length(files), ym, ncol(chunk)))
}
cat(sprintf("  완료 (%.1fs)\n\n", (proc.time()-t1)["elapsed"]))

# ═══ 3. Registry ═══════════════════════════════════════════════════════════
cat("[3/4] Registry...\n")
reg_path <- file.path(FDB_DIR, "factor_db_daily_registry.json")
reg <- if(file.exists(reg_path)) fromJSON(reg_path) else list()
all_new <- c(gap_cols, cons_gap)
reg$version <- "8.0.0"
reg$updated <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S")
reg$n_factors <- reg$n_factors + length(all_new)
reg$phase8 <- list(n_factors=length(all_new), factors=all_new)
reg$factor_list <- c(reg$factor_list, all_new)
write(toJSON(reg, pretty=TRUE, auto_unbox=TRUE), reg_path)

total_min <- (proc.time()-t0)["elapsed"]/60
cat(sprintf("\n═══ Phase 8 완료 ═══\n  추가: %d팩터 (Fund %d + Consensus %d)\n  소요: %.1f분\n",
    length(all_new), length(gap_cols), length(cons_gap), total_min))
