#=============================================================================#
# DVFS 1안 — 미국 기초지수(USD) 버전 (dvfs_idx)
#
# 도훈 mandate 2026-06-14: 미국 자산군 유지·USD 기준. ETF 대신 기초 가격지수 사용
#   (데이터 길고 추적오차·보수 없음). 한국 상장 ETF는 실투 수단(별도 매핑).
# 로직: 청정 기준선 dvfs_remeasure.R(M01 마스킹 / M02 EGARCH 타이밍·fail-safe /
#   M07 안A / B=11 / 비용 20bps)를 그대로. 데이터 소스만 지수/ETF 혼합으로 교체.
# 데이터 매핑: 주식·원자재 = 총수익/가격 지수(길게), 채권·국제·리츠·금 = ETF.
#   ETF Ad(배당재투자=총수익) ↔ 지수 Cl. ^SP500TR/^RUTTR=총수익, ^NDX/^SPGSCI=가격(라벨).
#   ★ PDBC(2014 상장→오염원) → ^SPGSCI(1990~)로 교체해 오염 원천 제거 + 데이터 확장.
#=============================================================================#

pacman::p_load("quantmod","PerformanceAnalytics","tidyverse","magrittr","xts",
               "RiskPortfolios","rugarch","timeSeries","TTR","openxlsx")

egarch_spec <- ugarchspec(variance.model = list(model="eGARCH", garchOrder=c(1,1)),
                          mean.model = list(armaOrder=c(0,0)))

qm_root <- Sys.getenv("QM_ROOT", unset = "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
out_dir <- file.path(qm_root, "04_Research", "dvaa_dvfs_revalidation")
if (!dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE)

#=============================================================================#
# Step 2: Data — 미국 기초지수(USD) + ETF 혼합 ([M01])
#=============================================================================#
# src_map: 자산명 → c(yahoo티커, 'Cl'(지수)/'Ad'(ETF))
src_map <- list(
  SPY = c('^SP500TR','Cl'),  QQQ = c('^NDXT','Cl'),  IWM = c('^RUTTR','Cl'),   # 주식: 총수익 지수(^NDXT=나스닥100 TR)
  ACWX= c('ACWX','Ad'),      EFA = c('EFA','Ad'),    EEM = c('EEM','Ad'),      # 국제: ETF
  IYR = c('IYR','Ad'),       GLD = c('GLD','Ad'),    PDBC= c('^SPGSCI','Cl'),  # 리츠·금=ETF, 원자재=지수
  IEF = c('IEF','Ad'),  TLT = c('TLT','Ad'),  LQD = c('LQD','Ad'),  HYG = c('HYG','Ad'),
  TIP = c('TIP','Ad'),  AGG = c('AGG','Ad'),  EMB = c('EMB','Ad'),  SHV = c('SHV','Ad')  # 채권: ETF
)
symbols_DVFS <- names(src_map)

px_list <- lapply(symbols_DVFS, function(s) {
  o  <- getSymbols(src_map[[s]][1], src='yahoo', from='2007-01-01', auto.assign=FALSE)
  px <- if (src_map[[s]][2] == 'Ad') Ad(o) else Cl(o)
  setNames(px, s)
})
price_DVFS <- do.call(cbind, px_list)

# [M01] 역방향 채움 없음 — 전방채움(leading NA 보존). interior 결측만 직전가.
price_DVFS <- na.locf(price_DVFS)
write.csv(as.data.frame(price_DVFS), file.path(out_dir, 'dvfs_idx_price_snapshot.csv'))

# [M01] na.omit 제거 — leading NA 보존(자산별 데이터 시작 상이), 루프서 eligible 마스킹.
rets_DVFS <- Return.calculate(price_DVFS)
rets_DVFS <- rets_DVFS[-1, ]

# ADX용 추세 = ^GSPC OHLC(지수 가격 추세). SMA200 = ^SP500TR(price_DVFS$SPY)로 일관.
gspc <- getSymbols('^GSPC', src='yahoo', from='2007-01-01', auto.assign=FALSE)
spy_ohlc   <- OHLC(gspc)
spy_sma200 <- SMA(price_DVFS$SPY, n = 200)

#=============================================================================#
# Step 3: Parameters
#=============================================================================#
ep <- endpoints(rets_DVFS, on = 'months')
rebalancing_dates <- index(rets_DVFS)[ep]
safe_assets <- c("GLD","TIP","TLT"); cash_asset <- "SHV"
mom_1 <- 1; mom_3 <- 3; mom_6 <- 6; mom_12 <- 12
B <- 11; garch_window <- 120
bull_market_threshold <- 0.99; bear_market_threshold <- 0.90
trend_confirmation_lookback <- 10; adx_period <- 14; adx_threshold <- 20
N <- length(symbols_DVFS)

wts <- list(); wts_sort <- list()
signal_history <- xts(matrix(NA, nrow = length(rebalancing_dates), ncol = 8), order.by = rebalancing_dates)
colnames(signal_history) <- c("VAA_Signal","GARCH_Signal","Final_Decision",
                              "Predicted_Vol","Vol_Threshold","Market_Trend","ADX_Value","Fit_Status")

#=============================================================================#
# Step 4: 자산 배분 루프 (청정 기준선 로직 그대로)
#=============================================================================#
for (i in 13:(length(ep))) {
  current_date <- index(rets_DVFS)[ep[i]]
  sub_ret_mom_1  <- rets_DVFS[ep[i-mom_1]  : ep[i], ]
  sub_ret_mom_3  <- rets_DVFS[ep[i-mom_3]  : ep[i], ]
  sub_ret_mom_6  <- rets_DVFS[ep[i-mom_6]  : ep[i], ]
  sub_ret_mom_12 <- rets_DVFS[ep[i-mom_12] : ep[i], ]
  cum_1  <- Return.cumulative(sub_ret_mom_1);  cum_3  <- Return.cumulative(sub_ret_mom_3)
  cum_6  <- Return.cumulative(sub_ret_mom_6);  cum_12 <- Return.cumulative(sub_ret_mom_12)
  cum_wm <- (cum_1*6 + cum_3*6 + cum_6*6 + cum_12*1) / 19

  mom_window_full <- rets_DVFS[ep[i-mom_12] : ep[i], ]
  eligible <- colnames(mom_window_full)[colSums(is.na(mom_window_full)) == 0]
  cw <- setNames(as.numeric(cum_wm), colnames(cum_wm))

  predicted_vol <- NA; vol_threshold <- NA; market_trend_ret <- NA; current_adx <- NA; fit_status <- NA

  current_spy_price  <- as.numeric(price_DVFS[current_date, "SPY"])
  current_spy_sma200 <- as.numeric(spy_sma200[current_date])
  vol_percentile_threshold <- 0.95
  if (!is.na(current_spy_price) && !is.na(current_spy_sma200)) {
    vol_percentile_threshold <- if (current_spy_price > current_spy_sma200) bull_market_threshold else bear_market_threshold
  }

  garch_signal <- "Stable"
  if (i > 13) {
    prev_weights <- wts[[i - 13]]
    safe_held <- names(prev_weights)[prev_weights > 0 & names(prev_weights) %in% safe_assets]
    safe_elig <- intersect(safe_assets, eligible)
    if (length(safe_elig) == 0) safe_elig <- safe_assets
    prev_safe_asset_held <- if (length(safe_held) == 0) names(which.min(cw[safe_elig])) else safe_held[1]

    garch_data_window <- rets_DVFS[(ep[i] - garch_window + 1):ep[i], prev_safe_asset_held]
    Garch_fit_attempt <- tryCatch(ugarchfit(spec = egarch_spec, data = garch_data_window, solver = 'hybrid'),
                                  error = function(e) NULL)
    rv_fallback <- function() sd(as.numeric(tail(rets_DVFS[1:ep[i], prev_safe_asset_held], garch_window)), na.rm=TRUE) * sqrt(252)
    if (!is.null(Garch_fit_attempt) && inherits(Garch_fit_attempt, "uGARCHfit")) {
      fc <- ugarchforecast(Garch_fit_attempt, n.ahead = 1)
      predicted_vol <- as.numeric(sigma(fc)) * sqrt(252)
      if (!is.finite(predicted_vol)) { predicted_vol <- rv_fallback(); fit_status <- 2L } else fit_status <- 1L
    } else { predicted_vol <- rv_fallback(); fit_status <- 2L }
    historical_vols <- rollapply(rets_DVFS[, prev_safe_asset_held], width = garch_window, FUN = sd, align = "right") * sqrt(252)
    vol_threshold <- quantile(historical_vols[1:ep[i]], vol_percentile_threshold, na.rm = TRUE)
    if (isTRUE(is.finite(predicted_vol) && is.finite(vol_threshold) && predicted_vol > vol_threshold)) garch_signal <- "Spike"
  }

  safe_elig <- intersect(safe_assets, eligible)
  if (length(safe_elig) == 0) safe_elig <- intersect(safe_assets, colnames(cum_wm))
  cash <- names(which.max(cw[safe_elig]))
  b    <- cw[eligible] < cw[cash]
  P_wt <- ifelse(sum(b, na.rm = TRUE) / length(eligible) > B / length(symbols_DVFS), 1, 0)

  if (garch_signal == "Stable") {
    final_decision <- ifelse(P_wt == 1, "Risk-Off", "Risk-On")
  } else {
    market_trend_ret <- Return.cumulative(rets_DVFS[(ep[i] - trend_confirmation_lookback + 1):ep[i], "SPY"])
    is_trend_negative <- as.numeric(market_trend_ret) < 0
    spy_adx <- ADX(spy_ohlc, n = adx_period)
    current_adx <- as.numeric(last(spy_adx[paste0("/", current_date)])$ADX)
    is_trend_strong <- !is.na(current_adx) && current_adx > adx_threshold
    if (is_trend_negative && is_trend_strong) {
      risky_elig <- intersect(setdiff(symbols_DVFS, cash_asset), eligible)
      risky_mom_avg <- mean(cw[risky_elig], na.rm = TRUE); if (is.na(risky_mom_avg)) risky_mom_avg <- -1
      final_decision <- ifelse(risky_mom_avg < 0, "Absolute_Defense",
                               ifelse(P_wt == 1, "Risk-Off", "Risk-On"))   # M07 안A
    } else final_decision <- ifelse(P_wt == 1, "Risk-Off", "Risk-On")
  }

  wt <- setNames(rep(0, N), symbols_DVFS)
  if (final_decision == "Risk-On") {
    risky_elig <- intersect(setdiff(symbols_DVFS, cash_asset), eligible)
    top_assets_names <- names(sort(cw[risky_elig], decreasing = TRUE)); top_assets_names <- top_assets_names[seq_len(min(4, length(top_assets_names)))]
    if (length(top_assets_names) >= 2) {
      covmat <- cov(sub_ret_mom_3[, top_assets_names], use = "complete.obs")
      erc_weights <- tryCatch(optimalPortfolio(covmat, control = list(type = 'erc', constraint = 'lo')),
                              error = function(e) { iv <- 1/sqrt(diag(covmat)); iv/sum(iv) })
      wt[top_assets_names] <- erc_weights
    } else if (length(top_assets_names) == 1) wt[top_assets_names] <- 1 else wt[cash] <- 1
  } else if (final_decision == "Risk-Off") wt[cash] <- 1 else wt[cash_asset] <- 1

  wts[[i-12]] <- xts(t(wt), order.by = index(rets_DVFS[ep[i]]))
  wts_sort[[i-12]] <- wts[[i-12]] %>% as.data.frame() %>% relocate(colnames(price_DVFS))
  signal_history[current_date, ] <- c(
    ifelse(P_wt == 1, 1, 0), ifelse(garch_signal == "Spike", 1, 0),
    match(final_decision, c("Risk-On","Risk-Off","Absolute_Defense")),
    round(predicted_vol*100,2), round(vol_threshold*100,2),
    round(as.numeric(market_trend_ret)*100,2), round(current_adx,2),
    ifelse(is.na(fit_status), NA, fit_status))
}

wts_VAA_DVFS <- do.call(rbind, wts_sort)

#=============================================================================#
# Step 5: Performance ([M03] 비용계약)
#=============================================================================#
rets_acct <- rets_DVFS; rets_acct[is.na(rets_acct)] <- 0
VAA_DVFS_ETF <- Return.portfolio(rets_acct, wts_VAA_DVFS, wealth.index = TRUE, verbose = TRUE)
to <- rowSums(abs(VAA_DVFS_ETF$BOP.Weight - xts::lag.xts(VAA_DVFS_ETF$EOP.Weight)), na.rm=TRUE)
to[1] <- rowSums(abs(coredata(VAA_DVFS_ETF$BOP.Weight)[1, , drop=FALSE]), na.rm=TRUE)
VAA_DVFS_ETF$turnover <- xts(to, order.by = index(VAA_DVFS_ETF$BOP.Weight))
fee <- 0.002
VAA_DVFS_ETF$net <- VAA_DVFS_ETF$returns - VAA_DVFS_ETF$turnover * fee   # metric_type='estimated'
total_net_cum <- Return.cumulative(VAA_DVFS_ETF$net)

rets_BM <- rets_acct
check <- cbind(VAA_DVFS_ETF$net, rets_BM$SPY, rets_BM$GLD, rets_BM$TLT) %>% na.omit()
colnames(check) <- c("DVFS_idx", "SP500TR", "GLD", "TLT")

stratStats <- function(x) {
  s <- rbind(table.AnnualizedReturns(x), maxDrawdown(x))
  s[5, ] <- s[1, ] / s[4, ]; s[6, ] <- s[1, ] / UlcerIndex(x)
  rownames(s)[4:6] <- c("Maximum Drawdown","Calmar Ratio","Ulcer Perf Index"); s
}

cat("\n===== DVFS_idx 전구간 성과 (net 20bps/leg) =====\n"); print(round(stratStats(check), 4))
cat("\n전구간 net 누적:", round(as.numeric(total_net_cum)*100, 2), "%  기간:",
    as.character(start(check)), "~", as.character(end(check)), "\n")
cat("\n===== 공통기간(2007-08~) — 원본 remeasure(CAGR 14.30/SR 0.854/MDD 22.83) 대조 =====\n")
print(round(stratStats(check['2007-08/']), 4))

cat("\n===== 최신 보유 (최근 리밸런스) =====\n")
latest_wt <- wts_VAA_DVFS[nrow(wts_VAA_DVFS), , drop=FALSE]
latest_held <- latest_wt[, as.numeric(latest_wt[1, ]) > 0, drop=FALSE]
cat("리밸런스일:", rownames(latest_wt), "\n"); print(round(latest_held, 4))

cat("\n[M02] Fit_Status (1=EGARCH,2=RVfallback):\n"); print(table(as.numeric(signal_history[,"Fit_Status"]), useNA="ifany"))
write.xlsx(as.data.frame(round(stratStats(check),4)), file.path(out_dir,"dvfs_idx_stratstats.xlsx"), rowNames=TRUE)
write.xlsx(as.data.frame(wts_VAA_DVFS), file.path(out_dir,"wts_DVFS_idx.xlsx"), rowNames=TRUE)
saveRDS(VAA_DVFS_ETF$net, file.path(out_dir,"dvfs_idx_net.rds"))
cat("\n저장 완료:", out_dir, "\n")
