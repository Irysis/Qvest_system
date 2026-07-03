#=============================================================================#
# DVFS P1 강화 ablation — 청정 기준선(remeasure) 위 single-variable A/B
#
# 목적: P0(M01/M02/M03)+M07 반영 청정 기준선에서 각 P1 강화를 1개씩만 토글해
#       격리 측정. 어느 강화가 net 위험조정(SR/Calmar/MDD)·turnover를 개선하는지.
# arms: baseline / M05 graded / M06 canary(eemagg, tip) / M10 cov(252lw, invvol) / M11 defense top3
# 공정성: getSymbols 1회 → 동일 raw·동일 비용(20bps/leg)·동일 기간. M07 안A 전 arm 공통.
# 주의: 실측-only(canonical 표준함수). 결과는 metric_type='estimated'(BM=SPY 단일, §5-4 한계).
#=============================================================================#

pacman::p_load("quantmod","PerformanceAnalytics","tidyverse","magrittr","xts",
               "RiskPortfolios","rugarch","timeSeries","TTR","openxlsx")

`%||%` <- function(a, b) if (is.null(a)) b else a

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
N <- length(symbols_DVFS)

getSymbols(symbols_DVFS, src='yahoo', from='2007-01-01', auto.assign=TRUE)
price_raw <- do.call(cbind, lapply(symbols_DVFS, function(x) Ad(get(x)))) %>% setNames(symbols_DVFS)
spy_ohlc <- OHLC(SPY)

# 13612W 모멘텀 (월말 endpoint 가격) — M06 canary
mom_13612W <- function(price, i, ep, s) {
  idx <- ep[c(i, i-1, i-3, i-6, i-12)]
  if (any(idx < 1)) return(NA)                          # ep[1]=0 등 인덱스 0 가드(첫 루프)
  p <- as.numeric(price[idx, s])
  if (length(p) < 5 || any(is.na(p))) return(NA)
  12*(p[1]/p[2]-1) + 4*(p[1]/p[3]-1) + 2*(p[1]/p[4]-1) + 1*(p[1]/p[5]-1)
}

#=============================================================================#
# 공통 전략 엔진 — opts로 P1 arm 토글 (M07 안A 항상 적용)
#=============================================================================#
run_strategy <- function(opts = list()) {
  alloc   <- opts$alloc   %||% "binary"     # binary | graded         (M05)
  signal  <- opts$signal  %||% "breadth"    # breadth | canary_eemagg | canary_tip  (M06)
  covm    <- opts$cov     %||% "63complete" # 63complete | 252lw | invvol           (M10)
  defense <- opts$defense %||% "single"     # single | top3           (M11)

  price <- na.locf(price_raw)
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
    cw <- setNames(as.numeric(cum_wm), colnames(cum_wm))

    mom_win  <- rets[ep[i-12]:ep[i], ]
    eligible <- colnames(mom_win)[colSums(is.na(mom_win)) == 0]
    safe_elig <- intersect(safe_assets, eligible)
    cash <- names(which.max(cw[safe_elig]))

    # --- 신호 → CF(방어강도 0~1) + P_def(binary 방어플래그) ---
    if (signal == "breadth") {
      b <- cw[eligible] < cw[cash]
      ratio <- (sum(b, na.rm=TRUE) / length(eligible)) / (B / N)   # 전자산 가용 시 = sum(b)/11
      CF <- min(ratio, 1); P_def <- as.integer(ratio > 1)
    } else if (signal == "canary_eemagg") {
      m <- c(mom_13612W(price,i,ep,"EEM"), mom_13612W(price,i,ep,"AGG"))
      bc <- sum(m <= 0, na.rm = TRUE)                              # 0,1,2
      CF <- bc / 2; P_def <- as.integer(bc >= 2)
    } else { # canary_tip
      idx <- ep[c(i, i-1, i-3, i-6, i-12)]
      p <- if (any(idx < 1)) NA else as.numeric(price[idx, "TIP"])
      tip_u <- if (length(p) < 5 || any(is.na(p))) NA
               else mean(c(p[1]/p[2]-1, p[1]/p[3]-1, p[1]/p[4]-1, p[1]/p[5]-1))
      CF <- if (is.na(tip_u)) 0 else as.numeric(tip_u < 0)        # 첫 루프 데이터부족 → Risk-On 디폴트
      P_def <- if (is.na(tip_u)) 0L else as.integer(tip_u < 0)
    }

    # --- 동적 분위수 ---
    csp <- as.numeric(price[current_date, "SPY"]); css <- as.numeric(spy_sma200[current_date])
    vpt <- 0.95
    if (!is.na(csp) && !is.na(css)) vpt <- if (csp > css) bull_market_threshold else bear_market_threshold

    # --- EGARCH 필터 (전 arm 공통, M02 타이밍·fail-safe) ---
    garch_signal <- "Stable"
    if (i > 13) {
      prevw <- wts[[i - 13]]
      held <- names(prevw)[prevw > 0 & names(prevw) %in% safe_assets]
      prev_safe <- if (length(held) == 0) names(which.min(cw[safe_elig])) else held[1]
      fit <- tryCatch(ugarchfit(spec=egarch_spec,
                                data=rets[(ep[i]-garch_window+1):ep[i], prev_safe], solver='hybrid'),
                      error=function(e) NULL)
      rv_fb <- function() sd(as.numeric(tail(rets[1:ep[i], prev_safe], garch_window)), na.rm=TRUE)*sqrt(252)
      if (!is.null(fit) && inherits(fit, "uGARCHfit")) {
        pv <- as.numeric(sigma(ugarchforecast(fit, n.ahead=1))) * sqrt(252)
        if (!is.finite(pv)) pv <- rv_fb()
      } else pv <- rv_fb()
      hv <- rollapply(rets[, prev_safe], width=garch_window, FUN=sd, align="right") * sqrt(252)
      vthr <- quantile(hv[1:ep[i]], vpt, na.rm=TRUE)
      if (is.finite(pv) && pv > vthr) garch_signal <- "Spike"
    }

    # --- regime 결정 (M07 안A) ---
    decide_normal <- function() {
      if (alloc == "graded") "Graded" else if (P_def == 1) "Risk-Off" else "Risk-On"
    }
    if (garch_signal == "Stable") {
      regime <- decide_normal()
    } else {
      mtr <- Return.cumulative(rets[(ep[i]-trend_confirmation_lookback+1):ep[i], "SPY"])
      is_neg <- as.numeric(mtr) < 0
      adx <- as.numeric(last(ADX(spy_ohlc, n=adx_period)[paste0("/", current_date)])$ADX)
      is_strong <- !is.na(adx) && adx > adx_threshold
      if (is_neg && is_strong) {
        risky_elig <- intersect(setdiff(symbols_DVFS, cash_asset), eligible)
        rma <- mean(cw[risky_elig], na.rm=TRUE); if (is.na(rma)) rma <- -1
        regime <- if (rma < 0) "Absolute_Defense" else decide_normal()   # 안A: 강제 Risk-On 없음
      } else regime <- decide_normal()
    }

    # --- 슬리브 빌더 ---
    build_def <- function() {
      d <- setNames(rep(0, N), symbols_DVFS)
      if (defense == "top3") {                                    # M11
        def_pool <- intersect(c("GLD","TIP","TLT","IEF","SHV"), eligible)
        if (length(def_pool) == 0) { d[cash] <- 1; return(d) }    # 가드: 방어풀 공집합
        d3 <- names(sort(cw[def_pool], decreasing=TRUE)); d3 <- d3[seq_len(min(3, length(d3)))]
        if ("SHV" %in% eligible) d3[cw[d3] < cw["SHV"]] <- "SHV"  # SHV eligible일 때만 절대필터
        tb <- table(factor(d3, levels=symbols_DVFS))
        d[names(tb)] <- as.numeric(tb) / length(d3)
      } else d[cash] <- 1
      d
    }
    build_ron <- function() {
      r <- setNames(rep(0, N), symbols_DVFS)
      risky_elig <- intersect(setdiff(symbols_DVFS, cash_asset), eligible)
      top4 <- names(sort(cw[risky_elig], decreasing=TRUE)); top4 <- top4[seq_len(min(4, length(top4)))]
      if (length(top4) == 0) { r[cash] <- 1; return(r) }         # 가드: 가용 위험자산 없음
      if (length(top4) == 1) { r[top4] <- 1; return(r) }         # 단일자산 (cov 불가)
      if (covm == "invvol") {                                    # M10 sub
        sds <- apply(sub3[, top4, drop=FALSE], 2, sd, na.rm=TRUE); w <- (1/sds)/sum(1/sds)
      } else {
        if (covm == "252lw") {                                   # M10
          win <- rets[max(1, ep[i]-251):ep[i], top4, drop=FALSE]; win <- win[complete.cases(win), , drop=FALSE]
          cm <- tryCatch(RiskPortfolios::covEstimation(as.matrix(win), control=list(type='lw')),
                         error=function(e) cov(as.matrix(win)))
        } else cm <- cov(sub3[, top4, drop=FALSE], use="complete.obs")  # baseline 63d
        w <- tryCatch(optimalPortfolio(cm, control=list(type='erc', constraint='lo')),
                      error=function(e){ iv <- 1/sqrt(diag(cm)); iv/sum(iv) })
      }
      r[top4] <- w
      r
    }

    wt <- setNames(rep(0, N), symbols_DVFS)
    if (regime == "Absolute_Defense") wt[cash_asset] <- 1
    else if (regime == "Risk-Off")    wt <- build_def()
    else if (regime == "Risk-On")     wt <- build_ron()
    else                              wt <- CF * build_def() + (1 - CF) * build_ron()  # Graded

    wts[[i-12]] <- xts(t(wt), order.by = index(rets[ep[i]]))
    wts_sort[[i-12]] <- wts[[i-12]] %>% as.data.frame() %>% relocate(colnames(price))
  }

  wdf <- do.call(rbind, wts_sort)
  ra <- rets; ra[is.na(ra)] <- 0
  port <- Return.portfolio(ra, wdf, verbose = TRUE)
  to <- rowSums(abs(port$BOP.Weight - xts::lag.xts(port$EOP.Weight)), na.rm=TRUE)
  to[1] <- rowSums(abs(coredata(port$BOP.Weight)[1, , drop=FALSE]), na.rm=TRUE)
  to_xts <- xts(to, order.by = index(port$BOP.Weight))
  net <- port$returns - to_xts * 0.002
  list(net = net, turnover = to_xts, wts = wdf)
}

#=============================================================================#
# arms 실행
#=============================================================================#
arms <- list(
  baseline       = list(),
  M05_graded     = list(alloc = "graded"),
  M06_canary_eag = list(signal = "canary_eemagg"),
  M06_canary_tip = list(signal = "canary_tip"),
  M10_cov252lw   = list(cov = "252lw"),
  M10_invvol     = list(cov = "invvol"),
  M11_def_top3   = list(defense = "top3")
)

res <- list()
for (nm in names(arms)) {
  cat("running:", nm, "...\n")
  res[[nm]] <- run_strategy(arms[[nm]])
}

# 공통기간 net 결합
nets <- do.call(cbind, lapply(res, function(x) x$net)) %>% na.omit()
colnames(nets) <- names(res)
spy_ret <- Return.calculate(na.locf(price_raw)$SPY)
nets_b <- cbind(nets, SPY = spy_ret) %>% na.omit()

stratStats <- function(x) {
  s <- rbind(table.AnnualizedReturns(x), maxDrawdown(x))
  s[5, ] <- s[1, ] / s[4, ]; s[6, ] <- s[1, ] / UlcerIndex(x)
  rownames(s)[4:6] <- c("MaxDD", "Calmar", "UlcerPI"); s
}

cat("\n===== P1 Ablation 전구간 비교 =====\n")
print(round(stratStats(nets_b), 4))

cat("\n===== 연평균 turnover (왕복 명목) =====\n")
to_ann <- sapply(res, function(x) mean(x$turnover, na.rm=TRUE) * 12)
print(round(to_ann, 3))

cat("\n===== 2008 GFC(08.01~09.06) 누적 % =====\n")
print(round(Return.cumulative(nets_b["2008-01/2009-06"]) * 100, 2))
cat("\n===== 2022 약세장 연간 % =====\n")
print(round(Return.cumulative(nets_b["2022"]) * 100, 2))

cat("\n===== baseline 대비 Δ (SR / Calmar / MDD%p / turnover) =====\n")
ss <- stratStats(nets_b); base <- "baseline"
for (nm in names(res)) {
  if (nm == base) next
  cat(sprintf("%-15s ΔSR %+.3f  ΔCalmar %+.3f  ΔMDD %+.2f%%p  Δturn %+.2f\n",
              nm, ss["Annualized Sharpe (Rf=0%)", nm] - ss["Annualized Sharpe (Rf=0%)", base],
              ss["Calmar", nm] - ss["Calmar", base],
              (ss["MaxDD", nm] - ss["MaxDD", base]) * 100,
              to_ann[nm] - to_ann[base]))
}

write.xlsx(as.data.frame(round(stratStats(nets_b), 4)), file.path(out_dir, "p1_ablation_stratstats.xlsx"), rowNames=TRUE)
cat("\nn_trials(arms):", length(arms), " — DSR/RTL 통제는 후속(M13).\n저장:", out_dir, "\n")
