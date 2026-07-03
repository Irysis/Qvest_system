#=============================================================================#
# DVFS 오리지널(오염) vs Remeasure(청정) 성과 비교
#
# 목적: 05_Production/DVAA_DVFS_ETF.R 원본 로직(na.locf0 fromLast=TRUE 역방향 채움
#       + ep[i-1] GARCH + 원 breadth + 강제 Risk-On 로테이션 + pairwise cov)을 충실
#       재현(contaminated)하고, dvfs_remeasure.R(청정)와 동일 raw 데이터·동일 비용·
#       동일 기간으로 비교한다. 오염이 성과(특히 2008 GFC)를 얼마나 부풀렸는지 정량화.
#
# 공정성: getSymbols 1회 → 동일 raw price를 두 경로에 분기. 비용 fee=0.002 동일.
# 주의:  ERC만 contaminated에서도 tryCatch(EW fallback) — 원본은 tryCatch 없어 가짜0
#        자산이 cov에 들면 solver crash 가능. crash 방지용 최소 안전장치(차이 명시).
#=============================================================================#

pacman::p_load("quantmod","PerformanceAnalytics","tidyverse","magrittr","xts",
               "RiskPortfolios","rugarch","timeSeries","TTR","openxlsx")

egarch_spec <- ugarchspec(variance.model = list(model="eGARCH", garchOrder=c(1,1)),
                          mean.model = list(armaOrder=c(0,0)))

qm_root <- Sys.getenv("QM_ROOT", unset = "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
out_dir <- file.path(qm_root, "04_Research", "dvaa_dvfs_revalidation")

symbols_DVFS <- c('SPY','QQQ','IWM','ACWX','EFA','EEM','IYR','GLD','PDBC',
                  'IEF','TLT','LQD','HYG','TIP','AGG','EMB','SHV')
safe_assets <- c("GLD","TIP","TLT"); cash_asset <- "SHV"
B <- 11; garch_window <- 120
bull_market_threshold <- 0.99; bear_market_threshold <- 0.90
trend_confirmation_lookback <- 10; adx_period <- 14; adx_threshold <- 20

# ===== 공통 raw 다운로드 (1회 — 두 경로 동일 데이터) =====
getSymbols(symbols_DVFS, src='yahoo', from='2007-01-01', auto.assign=TRUE)
price_raw <- do.call(cbind, lapply(symbols_DVFS, function(x) Ad(get(x)))) %>% setNames(symbols_DVFS)
spy_ohlc <- OHLC(SPY)   # SPY는 NA 없음 → 역채움/전방채움 무관, 공통

#=============================================================================#
# 경로 1: ORIGINAL (contaminated) — 05_Production 원본 로직 충실 재현
#=============================================================================#
run_original <- function() {
  price <- na.locf0(price_raw, fromLast = TRUE)            # ★ 역방향 채움(오염원)
  rets  <- Return.calculate(price) %>% na.omit()
  spy_sma200 <- SMA(price$SPY, n = 200)
  ep <- endpoints(rets, on = 'months')
  wts <- list(); wts_sort <- list()

  for (i in 13:length(ep)) {
    current_date <- index(rets)[ep[i]]
    sub3 <- rets[ep[i-3]:ep[i], ]
    cum_1  <- Return.cumulative(rets[ep[i-1]:ep[i], ])
    cum_3  <- Return.cumulative(sub3)
    cum_6  <- Return.cumulative(rets[ep[i-6]:ep[i], ])
    cum_12 <- Return.cumulative(rets[ep[i-12]:ep[i], ])
    cum_wm <- (cum_1*6 + cum_3*6 + cum_6*6 + cum_12*1)/19

    predicted_vol <- NA; vol_threshold <- NA
    csp <- as.numeric(price[current_date, "SPY"]); css <- as.numeric(spy_sma200[current_date])
    vpt <- 0.95
    if (!is.na(csp) && !is.na(css)) vpt <- if (csp > css) bull_market_threshold else bear_market_threshold

    garch_signal <- "Stable"
    if (i > 13) {
      prevw <- wts[[i - 13]]
      held <- names(prevw)[prevw > 0 & names(prevw) %in% safe_assets]
      prev_safe <- if (length(held) == 0) names(which.min(cum_wm[, safe_assets])) else held[1]
      fit <- tryCatch(
        ugarchfit(spec = egarch_spec,
                  data = rets[(ep[i-1] - garch_window + 1):(ep[i-1]), prev_safe],  # ★ ep[i-1] 앵커
                  solver = 'hybrid'),
        error = function(e) NULL)
      if (!is.null(fit)) {
        pv <- as.numeric(sigma(ugarchforecast(fit, n.ahead = 1))) * sqrt(252)
        if (is.finite(pv)) {
          predicted_vol <- pv
          hv <- rollapply(rets[, prev_safe], width = garch_window, FUN = sd, align = "right") * sqrt(252)
          vol_threshold <- quantile(hv[1:ep[i-1]], vpt, na.rm = TRUE)   # ★ [1:ep[i-1]]
          if (pv > vol_threshold) garch_signal <- "Spike"
        }
      }
    }

    cash <- names(which.max(cum_wm[, safe_assets]))
    b <- cum_wm < cum_wm[, cash]                       # ★ 원 breadth (전 17열)
    P_wt <- ifelse(sum(b, na.rm = TRUE) > B, 1, 0)     # ★ sum(b) > B (비례 아님)

    if (garch_signal == "Stable") {
      final_decision <- ifelse(P_wt == 1, "Risk-Off", "Risk-On")
    } else {
      mtr <- Return.cumulative(rets[(ep[i] - trend_confirmation_lookback + 1):ep[i], "SPY"])
      is_neg <- as.numeric(mtr) < 0
      adx <- as.numeric(last(ADX(spy_ohlc, n = adx_period)[paste0("/", current_date)])$ADX)
      is_strong <- !is.na(adx) && adx > adx_threshold
      if (is_neg && is_strong) {
        risky <- setdiff(symbols_DVFS, cash_asset)
        rma <- mean(as.numeric(cum_wm[, risky]), na.rm = TRUE); if (is.na(rma)) rma <- -1
        final_decision <- ifelse(rma < 0, "Absolute_Defense", "Risk-On")   # ★ 강제 Risk-On
      } else {
        final_decision <- ifelse(P_wt == 1, "Risk-Off", "Risk-On")
      }
    }

    wt <- rep(0, length(symbols_DVFS)) %>% setNames(symbols_DVFS)
    if (final_decision == "Risk-On") {
      risky <- setdiff(symbols_DVFS, cash_asset)
      top4 <- names(sort(cum_wm[, risky], decreasing = TRUE))[1:4]
      cm <- cov(sub3[, top4], use = "pairwise.complete.obs")    # ★ pairwise
      ew <- tryCatch(optimalPortfolio(cm, control = list(type='erc', constraint='lo')),
                     error = function(e) rep(1/length(top4), length(top4)))  # crash 방지 EW
      wt[top4] <- ew
    } else if (final_decision == "Risk-Off") {
      wt[cash] <- 1
    } else {
      wt[cash_asset] <- 1
    }
    wts[[i-12]] <- xts(t(wt), order.by = index(rets[ep[i]]))
    wts_sort[[i-12]] <- wts[[i-12]] %>% as.data.frame() %>% relocate(colnames(price))
  }

  wdf <- do.call(rbind, wts_sort)
  port <- Return.portfolio(rets, wdf, verbose = TRUE)
  to <- rowSums(abs(port$BOP.Weight - xts::lag.xts(port$EOP.Weight)), na.rm = TRUE)
  net <- port$returns - xts(to, order.by = index(port$BOP.Weight)) * 0.002
  list(net = net, wts = wdf, rets = rets)
}

#=============================================================================#
# 경로 2: REMEASURE (clean) — dvfs_remeasure.R 로직 (M01/M02/M07 반영)
#=============================================================================#
run_remeasure <- function() {
  price <- na.locf(price_raw)                              # ★ 전방만(leading NA 보존)
  rets  <- Return.calculate(price); rets <- rets[-1, ]
  spy_sma200 <- SMA(price$SPY, n = 200)
  ep <- endpoints(rets, on = 'months')
  wts <- list(); wts_sort <- list()

  for (i in 13:length(ep)) {
    current_date <- index(rets)[ep[i]]
    sub3 <- rets[ep[i-3]:ep[i], ]
    cum_1  <- Return.cumulative(rets[ep[i-1]:ep[i], ])
    cum_3  <- Return.cumulative(sub3)
    cum_6  <- Return.cumulative(rets[ep[i-6]:ep[i], ])
    cum_12 <- Return.cumulative(rets[ep[i-12]:ep[i], ])
    cum_wm <- (cum_1*6 + cum_3*6 + cum_6*6 + cum_12*1)/19

    mom_win <- rets[ep[i-12]:ep[i], ]
    eligible <- colnames(mom_win)[colSums(is.na(mom_win)) == 0]    # ★ M01 마스킹
    cw <- setNames(as.numeric(cum_wm), colnames(cum_wm))

    predicted_vol <- NA; vol_threshold <- NA
    csp <- as.numeric(price[current_date, "SPY"]); css <- as.numeric(spy_sma200[current_date])
    vpt <- 0.95
    if (!is.na(csp) && !is.na(css)) vpt <- if (csp > css) bull_market_threshold else bear_market_threshold

    garch_signal <- "Stable"
    if (i > 13) {
      prevw <- wts[[i - 13]]
      held <- names(prevw)[prevw > 0 & names(prevw) %in% safe_assets]
      safe_elig <- intersect(safe_assets, eligible)
      prev_safe <- if (length(held) == 0) names(which.min(cw[safe_elig])) else held[1]
      fit <- tryCatch(
        ugarchfit(spec = egarch_spec,
                  data = rets[(ep[i] - garch_window + 1):ep[i], prev_safe],   # ★ M02 ep[i] 앵커
                  solver = 'hybrid'),
        error = function(e) NULL)
      rv_fb <- function() sd(as.numeric(tail(rets[1:ep[i], prev_safe], garch_window)), na.rm=TRUE)*sqrt(252)
      if (!is.null(fit) && inherits(fit, "uGARCHfit")) {
        pv <- as.numeric(sigma(ugarchforecast(fit, n.ahead = 1))) * sqrt(252)
        if (!is.finite(pv)) pv <- rv_fb()
      } else { pv <- rv_fb() }
      predicted_vol <- pv
      hv <- rollapply(rets[, prev_safe], width = garch_window, FUN = sd, align = "right") * sqrt(252)
      vol_threshold <- quantile(hv[1:ep[i]], vpt, na.rm = TRUE)      # ★ M02 [1:ep[i]]
      if (is.finite(pv) && pv > vol_threshold) garch_signal <- "Spike"
    }

    safe_elig <- intersect(safe_assets, eligible)
    cash <- names(which.max(cw[safe_elig]))
    b <- cw[eligible] < cw[cash]
    P_wt <- ifelse(sum(b, na.rm = TRUE) / length(eligible) > B / length(symbols_DVFS), 1, 0)  # ★ 비례

    if (garch_signal == "Stable") {
      final_decision <- ifelse(P_wt == 1, "Risk-Off", "Risk-On")
    } else {
      mtr <- Return.cumulative(rets[(ep[i] - trend_confirmation_lookback + 1):ep[i], "SPY"])
      is_neg <- as.numeric(mtr) < 0
      adx <- as.numeric(last(ADX(spy_ohlc, n = adx_period)[paste0("/", current_date)])$ADX)
      is_strong <- !is.na(adx) && adx > adx_threshold
      if (is_neg && is_strong) {
        risky_elig <- intersect(setdiff(symbols_DVFS, cash_asset), eligible)
        rma <- mean(cw[risky_elig], na.rm = TRUE); if (is.na(rma)) rma <- -1
        final_decision <- ifelse(rma < 0, "Absolute_Defense",
                                 ifelse(P_wt == 1, "Risk-Off", "Risk-On"))    # ★ M07 안A
      } else {
        final_decision <- ifelse(P_wt == 1, "Risk-Off", "Risk-On")
      }
    }

    wt <- rep(0, length(symbols_DVFS)) %>% setNames(symbols_DVFS)
    if (final_decision == "Risk-On") {
      risky_elig <- intersect(setdiff(symbols_DVFS, cash_asset), eligible)
      top4 <- names(sort(cw[risky_elig], decreasing = TRUE))
      top4 <- top4[seq_len(min(4, length(top4)))]
      cm <- cov(sub3[, top4], use = "complete.obs")            # ★ complete.obs
      ew <- tryCatch(optimalPortfolio(cm, control = list(type='erc', constraint='lo')),
                     error = function(e) { iv <- 1/sqrt(diag(cm)); iv/sum(iv) })
      wt[top4] <- ew
    } else if (final_decision == "Risk-Off") {
      wt[cash] <- 1
    } else {
      wt[cash_asset] <- 1
    }
    wts[[i-12]] <- xts(t(wt), order.by = index(rets[ep[i]]))
    wts_sort[[i-12]] <- wts[[i-12]] %>% as.data.frame() %>% relocate(colnames(price))
  }

  wdf <- do.call(rbind, wts_sort)
  ra <- rets; ra[is.na(ra)] <- 0                              # ★ 회계 NA→0
  port <- Return.portfolio(ra, wdf, verbose = TRUE)
  to <- rowSums(abs(port$BOP.Weight - xts::lag.xts(port$EOP.Weight)), na.rm = TRUE)
  to[1] <- rowSums(abs(coredata(port$BOP.Weight)[1, , drop=FALSE]), na.rm = TRUE)
  net <- port$returns - xts(to, order.by = index(port$BOP.Weight)) * 0.002
  list(net = net, wts = wdf, rets = ra)
}

#=============================================================================#
# 실행 + 비교
#=============================================================================#
cat("\n[1/2] ORIGINAL (contaminated) 실행...\n")
O <- run_original()
cat("[2/2] REMEASURE (clean) 실행...\n")
C <- run_remeasure()

# 공통 기간으로 정렬 + SPY 벤치
spy_ret <- Return.calculate(na.locf(price_raw)$SPY)
cmp <- cbind(O$net, C$net, spy_ret) %>% na.omit()
colnames(cmp) <- c("Original_contam", "Remeasure_clean", "SPY")

stratStats <- function(x) {
  s <- rbind(table.AnnualizedReturns(x), maxDrawdown(x))
  s[5, ] <- s[1, ] / s[4, ]; s[6, ] <- s[1, ] / UlcerIndex(x)
  rownames(s)[4:6] <- c("Maximum Drawdown", "Calmar Ratio", "Ulcer Perf Index")
  s
}

cat("\n===== 전구간 성과 비교 =====\n")
print(round(stratStats(cmp), 4))

cat("\n===== 연도별 수익률 (%) =====\n")
yr <- apply.yearly(cmp, Return.cumulative) * 100
rownames(yr) <- format(index(yr), "%Y")
print(round(yr, 2))

cat("\n===== 2008 GFC 구간(2008-01~2009-06) 누적수익 (%) =====\n")
gfc <- cmp["2008-01/2009-06"]
print(round(Return.cumulative(gfc) * 100, 2))

cat("\n===== 차이 요약 =====\n")
ss <- stratStats(cmp)
cat(sprintf("CAGR   : Original %.2f%%  vs  Remeasure %.2f%%  (차 %.2f%%p)\n",
            ss[1,1]*100, ss[1,2]*100, (ss[1,1]-ss[1,2])*100))
cat(sprintf("Sharpe : Original %.3f   vs  Remeasure %.3f   (차 %.3f)\n",
            ss[3,1], ss[3,2], ss[3,1]-ss[3,2]))
cat(sprintf("MaxDD  : Original %.2f%%  vs  Remeasure %.2f%%  (차 %.2f%%p)\n",
            ss[4,1]*100, ss[4,2]*100, (ss[4,1]-ss[4,2])*100))

# 저장
write.xlsx(as.data.frame(round(stratStats(cmp),4)), file.path(out_dir,"compare_stratstats.xlsx"), rowNames=TRUE)
write.xlsx(as.data.frame(round(yr,2)), file.path(out_dir,"compare_yearly.xlsx"), rowNames=TRUE)
cat("\n저장 완료:", out_dir, "\n")
