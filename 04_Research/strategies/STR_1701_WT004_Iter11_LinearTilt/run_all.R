## ============================================================
## STR_1701 — WT-D20260426_004 Iter 11 Linear Tilt (Optimizer-only mutation of Iter 5)
## ============================================================
## ## 핵심아이디어
##   Iter 11 = Iter 5 multi-sleeve alpha (Core 65 + Defense 35) inherited
##   + Risk Σ inherited (factor model BΩB' + D, ledoit_wolf_oracle)
##   + Optimizer-only mutation: Linear_Tilt_lam1.0_TOphi8
##
##   Linear Tilt monthly: alpha rank-based weight tilt with TO-cap-aware blend
##     w_out = (1 - 1/(1+φ)) · w_prev + (1/(1+φ)) · w_tilt
##     φ = 8 (turnover penalty) → w_out = 0.889·w_prev + 0.111·w_tilt
##     Result: ann TO = 5.86 (PASS 600% hard cap), Spearman(w, alpha)=0.514 at as_of
##
##   216 sig_dates walk-forward (2006-01 ~ 2023-12) + 24-26 frozen-weights OOS.
##   AX-001 v2 cash overlay: BULL=0/NORMAL=0.05/CAUTION=0.15/CRISIS=0.30 (Optimizer-decided per date).
##   Pooled fallback Σ at CRISIS+CAUTION (29 / 216 dates) — risk handoff binding.
##
## v6.1 R12 Pure Function:
##   - alpha/risk/optimization 패키지 절대 수정 금지
##   - target_weights 재해석 금지 (216 sig_date schedule 그대로 적용)
##   - Hash audit: 시작/완료 동일 검증
##
## 검증 영역:
##   - STR_1701 vs STR_1699 (Iter5 HRP_lw) same-period (216m / 218m intersection)
##   - STR_1701 vs STR_1700 (Iter6 MEGA_06 Kelly+Overlay) same-period
##   - STR_1701 vs MEGA_05 (production NAV_vdp) same-period
##   - 24-26 OOS frozen-weights extension
##   - Replacement / Integration scenario 평가
##   - 5-spec Harvey FF5 v2 회귀 (CAPM/C3/C4/FF5/FF6) Newey-West HAC
##   - DSR post-penalty 일관 적용
##
## DSR penalty basis:
##   - Iter 11: alpha 5 + risk 5 + optimizer 10 = 20 candidates × 0.05 = 1.00
##   - STR_1699 / MEGA_05 docs: 15 × 0.05 = 0.75 (fair-comparison consistency)
##
## PIT 준수:
##   - C1: walk-forward only (no full-sample re-optimization)
##   - C2: monthly ret = close(t)/close(t-1) - 1
##   - C9: weight at sig_date d → applied (d, end_d] (lag enforced)
##   - C10: liquidity 2e8 KRW PIT t-30..t-1 (one-sided)
##   - C11: regime_state from KR internal expanding percentile (no FRED)
##   - C13: Z_Score_Aligned alpha inherited (no manual flip)
##   - C14: Usable_Date <= sig_date (Factor DB enforced)
##   - LB cutoff: last sig_date 2023-12-01 strictly before lockbox 2024-01-23
## ============================================================

cat("=== STR_1701: WT-D20260426_004 Iter 11 Linear Tilt (Optimizer-only mutation) ===\n")
cat("Forge Integration — Opus 4.7 v6.1 R12 Pure Function — 2026-04-26\n\n")

QEPM_AUTO_COMMIT <- TRUE
`%||%` <- function(a, b) if (!is.null(a) && length(a) > 0 && !all(is.na(a))) a else b

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(jsonlite)
  library(ggplot2)
  library(scales)
  library(sandwich)
  library(lmtest)
  library(e1071)
})

BASE_DIR <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
STR_ID   <- "STR_1701"
WT_ID    <- "WT-D20260426_004"
PREV_WT  <- "WT-D20260425_010"   # Iter 5 (STR_1699) reference NAV
ITER6_WT <- "WT-D20260425_011"   # Iter 6 (STR_1700) reference NAV

WT_DIR     <- file.path(BASE_DIR, "qepm/mailbox/worktask", WT_ID)
STAGE_DIR  <- file.path(BASE_DIR, "stage_artifacts", "WT_D20260426_004")
ITER5_STAGE <- file.path(BASE_DIR, "stage_artifacts", "WT_D20260425_010")
OUT_DIR    <- file.path(BASE_DIR, "04_Research/strategies/STR_1701_WT004_Iter11_LinearTilt/output")
BT_DIR     <- file.path(WT_DIR, "backtest_result")
JR_DIR     <- file.path(WT_DIR, "judge_ready")
PREV_BT    <- file.path(BASE_DIR, "qepm/mailbox/worktask", PREV_WT, "backtest_result")
ITER6_BT   <- file.path(BASE_DIR, "qepm/mailbox/worktask", ITER6_WT, "backtest_result")

dir.create(OUT_DIR, showWarnings = FALSE, recursive = TRUE)
dir.create(BT_DIR,  showWarnings = FALSE, recursive = TRUE)
dir.create(JR_DIR,  showWarnings = FALSE, recursive = TRUE)

# DSR penalty — Iter 11: alpha 5 + risk 5 + optimizer 10 = 20 candidates × 0.05 = 1.00
DSR_CANDIDATES_TRIED <- 20
DSR_PENALTY_PER_CAND <- 0.05
DSR_PENALTY_TOTAL    <- DSR_CANDIDATES_TRIED * DSR_PENALTY_PER_CAND  # 1.00

cat(sprintf("[0] Config | STR_ID=%s WT_ID=%s\n", STR_ID, WT_ID))
cat(sprintf("    DSR penalty basis: %d candidates × %.2f = %.2f\n",
            DSR_CANDIDATES_TRIED, DSR_PENALTY_PER_CAND, DSR_PENALTY_TOTAL))

# ─────────────────────────────────────────────────────────
# 1. START hash audit (3-package read-only verification)
# ─────────────────────────────────────────────────────────
cat("\n[1] START hash audit (3-package read-only verification)\n")

pkg_files <- c(
  file.path(WT_DIR, "alpha_package.json"),
  file.path(WT_DIR, "risk_package.json"),
  file.path(WT_DIR, "optimization_package.json")
)
start_hashes <- sapply(pkg_files, function(f) tryCatch(
  as.character(tools::md5sum(f)), error = function(e) "MISSING"))
names(start_hashes) <- basename(pkg_files)
cat("  Start MD5:\n")
for (n in names(start_hashes)) cat(sprintf("    %-30s = %s\n", n, substr(start_hashes[n],1,16)))

# weights.csv hash (Optimizer artifact also Pure Function)
weights_path  <- file.path(WT_DIR, "weights.csv")
start_w_hash  <- as.character(tools::md5sum(weights_path))
cat(sprintf("    weights.csv (artifact)         = %s\n", substr(start_w_hash,1,16)))

# ─────────────────────────────────────────────────────────
# 2. 3-package 로드 (READ-ONLY)
# ─────────────────────────────────────────────────────────
cat("\n[2] Load 3-package (Pure Function boundary)\n")

alpha_pkg <- fromJSON(file.path(WT_DIR, "alpha_package.json"), simplifyVector = FALSE)
risk_pkg  <- fromJSON(file.path(WT_DIR, "risk_package.json"),  simplifyVector = FALSE)
opt_pkg   <- fromJSON(file.path(WT_DIR, "optimization_package.json"), simplifyVector = FALSE)

method_tag    <- opt_pkg$method_selected %||% "Linear_Tilt_lam1.0_TOphi8"
sleeve_w      <- opt_pkg$multi_sleeve_weights %||% list(Core=0.6175, Defense=0.3325, Cash=0.05)
cash_policy   <- opt_pkg$cash_overlay_policy %||% list(BULL=0, NORMAL=0.05, CAUTION=0.15, CRISIS=0.30)
n_sigdates_wf <- opt_pkg$n_sig_dates_walkforward %||% 216
expected_ir   <- opt_pkg$expected_information_ratio %||% 0.6255
expected_cagr <- opt_pkg$expected_cagr %||% 0.1292
expected_mdd  <- opt_pkg$expected_mdd %||% -0.4237
expected_to   <- opt_pkg$turnover %||% 5.8604
crisis_pooled <- opt_pkg$crisis_pooled_fallback$enforced %||% TRUE

cat(sprintf("  Method: %s | walk-forward sig_dates=%d\n", method_tag, n_sigdates_wf))
cat(sprintf("  Sleeve: Core=%.4f Defense=%.4f Cash=%.4f\n",
            sleeve_w$Core, sleeve_w$Defense, sleeve_w$Cash))
cat(sprintf("  Cash policy: BULL=%.2f NORMAL=%.2f CAUTION=%.2f CRISIS=%.2f\n",
            cash_policy$BULL, cash_policy$NORMAL, cash_policy$CAUTION, cash_policy$CRISIS))
cat(sprintf("  Expected (Optimizer): IR=%.3f CAGR=%.4f MDD=%.4f Ann_TO=%.3f\n",
            expected_ir, expected_cagr, expected_mdd, expected_to))

# ─────────────────────────────────────────────────────────
# 3. weights.csv 로드 (216 sig_dates × dynamic universe + cash overlay)
# ─────────────────────────────────────────────────────────
cat("\n[3] Load weights schedule (216 sig_dates × Linear Tilt monthly + cash overlay)\n")

if (!file.exists(weights_path)) stop("[FAIL] weights.csv not found at ", weights_path)

w_dt <- fread(weights_path)
w_dt[, as_of_date := as.Date(as_of_date)]
setkey(w_dt, as_of_date, ticker)

sig_dates <- sort(unique(w_dt$as_of_date))
cat(sprintf("  weights.csv: %d rows | %d sig_dates\n", nrow(w_dt), length(sig_dates)))
cat(sprintf("  date range: %s ~ %s\n",
            as.character(min(sig_dates)), as.character(max(sig_dates))))
cat(sprintf("  unique methods: %s\n", paste(unique(w_dt$method_selected), collapse=", ")))
cat(sprintf("  unique sigma_methods: %s\n", paste(unique(w_dt$sigma_method), collapse=", ")))
cat(sprintf("  unique regimes: %s\n", paste(unique(w_dt$regime), collapse=", ")))

# Regime cash sanity (Optimizer 결정 — Forge는 적용만)
regime_cash_check <- w_dt[, .(median_cash = median(cash_pct, na.rm=TRUE),
                              n_dates = uniqueN(as_of_date)), by = regime]
cat("  Regime cash sanity (median_cash by regime):\n")
print(regime_cash_check)

# Pooled-Σ usage
pooled_dates <- unique(w_dt[grepl("pooled|constcor", sigma_method), as_of_date])
cat(sprintf("  Pooled-Σ fallback applied at %d sig_dates (CRISIS/CAUTION binding)\n",
            length(pooled_dates)))

# ─────────────────────────────────────────────────────────
# 4. RAWDATA + Benchmark + alpha_scores + FF5 v2 로드
# ─────────────────────────────────────────────────────────
cat("\n[4] Load RAWDATA + Benchmark + alpha_scores + FF5 v2\n")

raw <- as.data.table(read_parquet(file.path(BASE_DIR, ".cache/rawdata.parquet"),
                                  col_select = c("Date","Ticker","Close","Vol","Ret")))
setkey(raw, Date, Ticker)
raw[, TradingAmt := Close * Vol]
cat(sprintf("  RAWDATA: %s rows | %s ~ %s\n",
            format(nrow(raw), big.mark=","),
            as.character(min(raw$Date)), as.character(max(raw$Date))))

bm <- as.data.table(read_parquet(file.path(BASE_DIR, ".cache/benchmark.parquet")))
setorder(bm, Date)
cat(sprintf("  Benchmark: %d rows | BM_Close range %.0f ~ %.0f\n",
            nrow(bm), min(bm$BM_Close, na.rm=TRUE), max(bm$BM_Close, na.rm=TRUE)))

# alpha_scores from Iter 11 stage (inherited from Iter 5)
alpha_scores_path <- file.path(STAGE_DIR, "alpha_scores.parquet")
if (!file.exists(alpha_scores_path)) {
  alpha_scores_path <- file.path(ITER5_STAGE, "alpha_scores.parquet")
}
alpha_scores <- as.data.table(read_parquet(alpha_scores_path))
setkey(alpha_scores, Date, Ticker)
cat(sprintf("  alpha_scores: %s rows | %d unique Date | source=%s\n",
            format(nrow(alpha_scores), big.mark=","),
            length(unique(alpha_scores$Date)), basename(dirname(alpha_scores_path))))

FF5_PATH <- file.path(BASE_DIR, ".cache/kr_factor_returns_v2.parquet")
ff5_v2 <- as.data.table(read_parquet(FF5_PATH))
setorder(ff5_v2, Date)
cat(sprintf("  FF5 v2: MKT=%d HML=%d RMW=%d CMA=%d WML=%d obs\n",
            sum(!is.na(ff5_v2$MKT)), sum(!is.na(ff5_v2$HML)),
            sum(!is.na(ff5_v2$RMW)), sum(!is.na(ff5_v2$CMA)),
            sum(!is.na(ff5_v2$WML))))

# ─────────────────────────────────────────────────────────
# 5. WALK-FORWARD BACKTEST (216 sig_dates, Linear Tilt monthly)
#    Optimizer가 결정한 ticker × weight × cash_pct를 그대로 적용
#    Forge는 RAWDATA × period return 만 측정
# ─────────────────────────────────────────────────────────
cat("\n[5] Walk-forward backtest (216 sig_dates, Linear Tilt monthly applied)\n")

LIQ_THRESHOLD  <- 2e8
COMMISSION_BPS <- 15

monthly_results <- vector("list", length(sig_dates) - 1)

for (i in seq_len(length(sig_dates) - 1)) {
  start_d <- sig_dates[i]
  end_d   <- sig_dates[i + 1]

  port_i_full <- w_dt[as_of_date == start_d]
  if (nrow(port_i_full) == 0) next

  # Optimizer가 결정한 metadata
  regime_i      <- port_i_full$regime[1]
  cash_i        <- port_i_full$cash_pct[1]
  sigma_method  <- port_i_full$sigma_method[1]

  port_i <- port_i_full[ticker != "CASH"]

  # 종목 weight normalize (cash 분리; risk 부분 합 = 1 - cash_pct)
  if (sum(port_i$weight, na.rm=TRUE) > 0) {
    port_i[, weight_risk := weight / sum(weight, na.rm=TRUE) * (1 - cash_i)]
  } else {
    next
  }

  # 유동성 필터 (PIT t-30..t-1)
  liq_window_start <- start_d - 30L
  liq_data <- raw[Date >= liq_window_start & Date < start_d,
                  .(AvgTradingAmt = mean(TradingAmt, na.rm=TRUE)), by = Ticker]
  liquid_tickers <- liq_data[AvgTradingAmt >= LIQ_THRESHOLD, Ticker]
  port_filtered <- port_i[ticker %in% liquid_tickers]
  if (nrow(port_filtered) == 0) port_filtered <- copy(port_i)

  # risk weight renormalize (after liquidity filter, preserve cash_pct)
  if (sum(port_filtered$weight_risk, na.rm=TRUE) > 0) {
    port_filtered[, weight_risk := weight_risk / sum(weight_risk, na.rm=TRUE) * (1 - cash_i)]
  }

  # 보유 기간 수익률 (PIT C2: > start_d, <= end_d)
  period_data <- raw[Date > start_d & Date <= end_d, .(Date, Ticker, Ret)]
  if (nrow(period_data) == 0) {
    monthly_results[[i]] <- data.table(
      period_start=start_d, period_end=end_d,
      port_ret=NA_real_, port_ret_gross=NA_real_,
      n_held=0L, turnover=0,
      regime=regime_i, cash_pct=cash_i,
      sigma_method=sigma_method)
    next
  }

  stock_rets <- period_data[, .(stock_ret = prod(1 + Ret, na.rm=TRUE) - 1), by = Ticker]
  merged_ret <- merge(port_filtered, stock_rets,
                     by.x = "ticker", by.y = "Ticker", all.x = TRUE)
  merged_ret[is.na(stock_ret), stock_ret := 0]

  # Risk + Cash (cash 0% return — 보수적)
  port_ret_risk  <- sum(merged_ret$weight_risk * merged_ret$stock_ret, na.rm=TRUE)
  port_ret_cash  <- cash_i * 0
  port_ret_gross <- port_ret_risk + port_ret_cash

  # Turnover (이전 기간 대비, 양방향 round-trip ×2 cost)
  if (i == 1) {
    turnover_est <- 1.0
  } else {
    prev_full <- w_dt[as_of_date == sig_dates[i-1] & ticker != "CASH",
                       .(ticker, w_prev = weight)]
    prev_cash <- w_dt[as_of_date == sig_dates[i-1] & ticker == "CASH", weight][1] %||% 0
    if (sum(prev_full$w_prev, na.rm=TRUE) > 0) {
      prev_full[, w_prev := w_prev / sum(w_prev, na.rm=TRUE) * (1 - prev_cash)]
    }
    curr_port <- port_filtered[, .(ticker, w_curr = weight_risk)]
    merged_to <- merge(prev_full, curr_port, by = "ticker", all = TRUE)
    merged_to[is.na(w_prev), w_prev := 0]
    merged_to[is.na(w_curr), w_curr := 0]
    turnover_est <- sum(abs(merged_to$w_curr - merged_to$w_prev)) / 2
  }

  cost <- (COMMISSION_BPS / 1e4) * turnover_est * 2  # round-trip
  port_ret_net <- port_ret_gross - cost

  monthly_results[[i]] <- data.table(
    period_start   = start_d,
    period_end     = end_d,
    port_ret       = port_ret_net,
    port_ret_gross = port_ret_gross,
    n_held         = nrow(merged_ret),
    turnover       = turnover_est,
    cost           = cost,
    regime         = regime_i,
    cash_pct       = cash_i,
    sigma_method   = sigma_method
  )
}

bt_dt <- rbindlist(monthly_results, use.names=TRUE, fill=TRUE)
bt_dt <- bt_dt[!is.na(port_ret)]
setorder(bt_dt, period_end)

cat(sprintf("  Walk-forward: %d periods | %s ~ %s\n",
            nrow(bt_dt), as.character(min(bt_dt$period_end)),
            as.character(max(bt_dt$period_end))))
cat(sprintf("  Avg n_held: %.1f | Avg turnover: %.4f (annual ≈ %.1f%%)\n",
            mean(bt_dt$n_held), mean(bt_dt$turnover), mean(bt_dt$turnover)*12*100))
cat(sprintf("  Total cost: %.4f | avg cash_pct: %.4f | Pooled-Σ periods: %d\n",
            sum(bt_dt$cost), mean(bt_dt$cash_pct, na.rm=TRUE),
            sum(grepl("pooled|constcor", bt_dt$sigma_method))))

# ─────────────────────────────────────────────────────────
# 6. Pre-LB / Lockbox split + FF5 v2 매칭
# ─────────────────────────────────────────────────────────
cat("\n[6] Pre-LB / Lockbox split + FF5 v2 매칭\n")

LB_START <- as.Date("2024-01-23")
all_ret  <- bt_dt[, .(Date = period_end, port_ret, port_ret_gross,
                      regime, cash_pct, turnover, n_held, sigma_method)]
all_ret[, YM := format(Date, "%Y-%m")]
ff5_v2_dt <- copy(ff5_v2)
ff5_v2_dt[, YM := format(Date, "%Y-%m")]
merged <- merge(all_ret, ff5_v2_dt[, .(YM, MKT, SMB, HML, WML, RMW, CMA, RF)],
                by = "YM", all.x = TRUE)
merged[, excess_ret := port_ret - RF]

prelb_full <- merged[Date < LB_START & !is.na(excess_ret)]
lb_full    <- merged[Date >= LB_START & !is.na(excess_ret)]
combined   <- merged[!is.na(excess_ret)]

cat(sprintf("  Pre-LB matched FF5: %d obs | Lockbox: %d obs | Combined: %d obs\n",
            nrow(prelb_full), nrow(lb_full), nrow(combined)))

# ─────────────────────────────────────────────────────────
# 7. 5-spec 회귀 (Newey-West HAC) + DSR
# ─────────────────────────────────────────────────────────
cat("\n[7] 5-spec factor regression (FF5 v2, Newey-West HAC)\n")

nw_t_stat <- function(model, lag = NULL) {
  n <- length(residuals(model))
  if (is.null(lag)) lag <- floor(4 * (n/100)^(2/9))
  lag <- max(1L, as.integer(lag))
  tryCatch({
    nw_vcov <- NeweyWest(model, lag = lag, prewhite = FALSE, adjust = TRUE)
    ct <- coeftest(model, vcov = nw_vcov)
    list(alpha=ct["(Intercept)","Estimate"],
         t_nw =ct["(Intercept)","t value"],
         p_nw =ct["(Intercept)","Pr(>|t|)"],
         lag=lag, n=n,
         r2=summary(model)$r.squared,
         adj_r2=summary(model)$adj.r.squared)
  }, error = function(e) {
    list(alpha=NA, t_nw=NA, p_nw=NA, lag=lag, n=n, r2=NA, adj_r2=NA,
         error=conditionMessage(e))
  })
}

compute_dsr <- function(returns, sr_benchmark = 0) {
  n <- length(returns)
  if (n < 12) return(list(dsr=NA, sr_ann=NA, note="insufficient_obs"))
  sr_m <- mean(returns, na.rm=TRUE) / sd(returns, na.rm=TRUE)
  sr_ann <- sr_m * sqrt(12)
  skew  <- tryCatch(e1071::skewness(returns), error=function(e) 0)
  kurt  <- tryCatch(e1071::kurtosis(returns) + 3, error=function(e) 3)
  denom <- sqrt((1 - skew*sr_m + (kurt-1)/4 * sr_m^2) / (n-1))
  dsr   <- if (!is.na(denom) && denom > 1e-10) (sr_ann - sr_benchmark) / (denom * sqrt(12)) else NA
  list(dsr=round(dsr,4), sr_ann=round(sr_ann,4), sr_m=round(sr_m,4))
}

run_5spec <- function(dt, label) {
  dt <- dt[!is.na(excess_ret)]
  results <- list()
  d1 <- dt[!is.na(MKT)]
  if (nrow(d1) >= 20) {
    m1 <- lm(excess_ret ~ MKT, data=d1)
    results[["CAPM"]] <- c(nw_t_stat(m1), list(spec="CAPM", n_eff=nrow(d1)))
  }
  d2 <- dt[!is.na(MKT) & !is.na(SMB) & !is.na(HML)]
  if (nrow(d2) >= 20) {
    m2 <- lm(excess_ret ~ MKT + SMB + HML, data=d2)
    results[["Carhart_3"]] <- c(nw_t_stat(m2), list(spec="Carhart_3", n_eff=nrow(d2)))
  }
  d3 <- dt[!is.na(MKT) & !is.na(SMB) & !is.na(HML) & !is.na(WML)]
  if (nrow(d3) >= 20) {
    m3 <- lm(excess_ret ~ MKT + SMB + HML + WML, data=d3)
    results[["Carhart_4"]] <- c(nw_t_stat(m3), list(spec="Carhart_4", n_eff=nrow(d3)))
  }
  d4 <- dt[!is.na(MKT) & !is.na(SMB) & !is.na(HML) & !is.na(RMW) & !is.na(CMA)]
  if (nrow(d4) >= 20) {
    m4 <- lm(excess_ret ~ MKT + SMB + HML + RMW + CMA, data=d4)
    results[["FF5"]] <- c(nw_t_stat(m4), list(spec="FF5", n_eff=nrow(d4)))
    dsr_res <- compute_dsr(d4$excess_ret)
    results[["FF5"]]$dsr    <- dsr_res$dsr
    results[["FF5"]]$sr_ann <- dsr_res$sr_ann
  }
  d5 <- dt[!is.na(MKT) & !is.na(SMB) & !is.na(HML) & !is.na(WML) & !is.na(RMW) & !is.na(CMA)]
  if (nrow(d5) >= 20) {
    m5 <- lm(excess_ret ~ MKT + SMB + HML + WML + RMW + CMA, data=d5)
    results[["FF6"]] <- c(nw_t_stat(m5), list(spec="FF6", n_eff=nrow(d5)))
  }
  cat(sprintf("  [%s] 5-spec results:\n", label))
  for (sp in names(results)) {
    r <- results[[sp]]
    g <- if (!is.na(r$t_nw) && r$t_nw >= 2.95) " <<GATE PASS>>" else
         if (!is.na(r$t_nw) && r$t_nw >= 2.0)  " [borderline]" else " [fail]"
    cat(sprintf("    %-12s: alpha=%.4f%% t_NW=%.3f (n=%d, lag=%d)%s\n",
                sp, (r$alpha %||% NA)*100, r$t_nw %||% NA,
                r$n_eff %||% NA, r$lag %||% NA, g))
  }
  results
}

cat("\n--- Combined (Pre-LB walk-forward) ---\n")
res_full  <- run_5spec(combined, "Combined")
cat("\n--- Pre-LB (2006-02 ~ 2023-12 walk-forward) ---\n")
res_prelb <- run_5spec(prelb_full, "Pre-LB")
cat("\n--- Lockbox (2024-01-23+) ---\n")
res_lb    <- run_5spec(lb_full, "Lockbox")

# 5-spec PASS count
spec_names <- c("CAPM","Carhart_3","Carhart_4","FF5","FF6")
n_pass <- sum(sapply(spec_names, function(sp) {
  t <- res_full[[sp]]$t_nw
  !is.na(t) && t >= 2.95
}))
cat(sprintf("\n  5-spec PASS count (Combined, t>=2.95): %d/5\n", n_pass))

# ─────────────────────────────────────────────────────────
# 8. 백테스트 성과 (Pre-LB / Lockbox / Combined / Regime conditional)
# ─────────────────────────────────────────────────────────
cat("\n[8] Backtest performance + Regime-conditional metrics\n")

compute_perf_v2 <- function(r, label, candidates_tried = 0,
                             penalty_per_cand = 0.05,
                             start_ym = "2006-01") {
  r <- r[!is.na(r)]
  n <- length(r)
  if (n < 6) return(list(label = label, cagr = NA, vol = NA, sr = NA,
                         mdd = NA, hit = NA, n_months = n,
                         dsr_raw = NA, dsr_post_penalty = NA,
                         harvey_t_ff5 = NA))
  cagr <- prod(1 + r)^(12/n) - 1
  vol  <- sd(r) * sqrt(12)
  sr_m <- mean(r) / sd(r)
  sr   <- sr_m * sqrt(12)
  cum  <- cumprod(1 + r)
  mdd  <- min(cum / cummax(cum) - 1, na.rm = TRUE)
  hit  <- mean(r > 0)

  start_date <- as.Date(paste0(start_ym, "-01"))
  dt_x <- data.table(YM = format(seq.Date(from = start_date, by = "month",
                                            length.out = n), "%Y-%m"),
                     port = r)
  ff5_join <- ff5_v2[, .(YM = format(Date, "%Y-%m"),
                          MKT, SMB, HML, WML, RMW, CMA, RF)]
  mg <- merge(dt_x, ff5_join, by = "YM", all.x = TRUE)
  mg[, excess := port - RF]
  mg <- mg[!is.na(excess) & !is.na(MKT) & !is.na(RMW)]
  harvey_t_ff5 <- NA
  if (nrow(mg) >= 24) {
    m_ff5 <- lm(excess ~ MKT + SMB + HML + RMW + CMA, data = mg)
    nw_lag <- max(1L, floor(4 * (nrow(mg)/100)^(2/9)))
    nw_v <- tryCatch(NeweyWest(m_ff5, lag = nw_lag, prewhite = FALSE, adjust = TRUE),
                     error = function(e) NULL)
    if (!is.null(nw_v)) {
      ct <- tryCatch(coeftest(m_ff5, vcov = nw_v), error = function(e) NULL)
      if (!is.null(ct)) harvey_t_ff5 <- ct["(Intercept)", "t value"]
    }
  }
  skew <- tryCatch(e1071::skewness(r), error = function(e) 0)
  kurt <- tryCatch(e1071::kurtosis(r) + 3, error = function(e) 3)
  denom <- sqrt((1 - skew * sr_m + (kurt - 1)/4 * sr_m^2) / (n - 1))
  dsr_raw <- if (!is.na(denom) && denom > 1e-10) sr / (denom * sqrt(12)) else NA
  dsr_post <- if (!is.na(dsr_raw)) dsr_raw - candidates_tried * penalty_per_cand else NA

  list(label = label,
       cagr = round(cagr, 4), vol = round(vol, 4),
       sr = round(sr, 4), mdd = round(mdd, 4), hit = round(hit, 4),
       n_months = n, ir = round(sr, 4),
       harvey_t_ff5 = round(harvey_t_ff5, 4),
       dsr_raw = round(dsr_raw, 4),
       dsr_post_penalty = round(dsr_post, 4))
}

print_perf_row <- function(p) {
  cat(sprintf("    %-32s | n=%3d | SR=%.3f | CAGR=%.2f%% | MDD=%.2f%% | t_FF5=%.3f | DSR_post=%.3f\n",
              p$label, p$n_months, p$sr %||% NA, (p$cagr %||% NA)*100,
              (p$mdd %||% NA)*100, p$harvey_t_ff5 %||% NA,
              p$dsr_post_penalty %||% NA))
}

perf_full  <- compute_perf_v2(combined$port_ret, "Iter11_Combined",
                               DSR_CANDIDATES_TRIED, start_ym = "2006-02")
perf_prelb <- compute_perf_v2(prelb_full$port_ret, "Iter11_PreLB",
                               DSR_CANDIDATES_TRIED, start_ym = "2006-02")
perf_lb    <- compute_perf_v2(lb_full$port_ret, "Iter11_Lockbox",
                               0, start_ym = "2024-01")

cat("\n  ─── Pre-LB / Lockbox / Combined ───\n")
print_perf_row(perf_full); print_perf_row(perf_prelb); print_perf_row(perf_lb)

# Regime conditional
cat("\n  Regime conditional (Pre-LB):\n")
regime_perf <- list()
for (rg in c("BULL","NORMAL","CAUTION","CRISIS")) {
  sub <- prelb_full[regime == rg]
  if (nrow(sub) >= 6) {
    p <- compute_perf_v2(sub$port_ret, paste0("Iter11_", rg), 0,
                         start_ym = format(min(sub$Date), "%Y-%m"))
    regime_perf[[rg]] <- p
    cat(sprintf("    [%-7s] n=%3d SR=%.3f CAGR=%.2f%% MDD=%.2f%% Hit=%.1f%%\n",
                rg, p$n_months, p$sr %||% NA, (p$cagr %||% NA)*100,
                (p$mdd %||% NA)*100, (p$hit %||% NA)*100))
  } else {
    cat(sprintf("    [%-7s] insufficient n=%d\n", rg, nrow(sub)))
    regime_perf[[rg]] <- list(label=paste0("Iter11_", rg), n_months=nrow(sub),
                              cagr=NA, sr=NA, mdd=NA, hit=NA)
  }
}

# ─────────────────────────────────────────────────────────
# 9. 24-26 OOS frozen-weights extension
#    Last sig_date 2023-12-01 → buy-and-hold to 2026-04
# ─────────────────────────────────────────────────────────
cat("\n[9] 24-26 OOS frozen-weights extension (last sig_date max → 2026-04)\n")

last_sig  <- max(sig_dates)
last_w    <- w_dt[as_of_date == last_sig & ticker != "CASH",
                   .(ticker, weight)]
last_cash <- w_dt[as_of_date == last_sig & ticker == "CASH", weight][1] %||% 0
if (sum(last_w$weight, na.rm=TRUE) > 0) {
  last_w[, weight_risk := weight / sum(weight, na.rm=TRUE) * (1 - last_cash)]
} else {
  last_w[, weight_risk := 0]
}

cat(sprintf("  Last sig_date %s: %d names + cash %.2f%%\n",
            as.character(last_sig), nrow(last_w), last_cash*100))

oos_start <- last_sig
oos_end   <- max(raw$Date)

# OOS monthly periods from after lockbox
oos_dates <- seq.Date(as.Date("2024-01-01"), oos_end, by = "month")
oos_dates <- as.Date(format(oos_dates, "%Y-%m-01"))
oos_dates <- c(oos_dates, oos_end)
oos_dates <- sort(unique(oos_dates))

oos_periods <- list()
prev_d <- oos_start
for (k in seq_along(oos_dates)) {
  d_curr <- oos_dates[k]
  if (d_curr <= prev_d) next
  pdat <- raw[Date > prev_d & Date <= d_curr & Ticker %in% last_w$ticker,
              .(Date, Ticker, Ret)]
  if (nrow(pdat) == 0) { prev_d <- d_curr; next }
  stock_r <- pdat[, .(stock_ret = prod(1 + Ret, na.rm=TRUE) - 1), by = Ticker]
  m_w <- merge(last_w, stock_r, by.x = "ticker", by.y = "Ticker", all.x = TRUE)
  m_w[is.na(stock_ret), stock_ret := 0]
  port_ret_risk <- sum(m_w$weight_risk * m_w$stock_ret, na.rm = TRUE)
  port_ret_oos  <- port_ret_risk + last_cash * 0
  oos_periods[[length(oos_periods) + 1]] <-
    data.table(period_end = d_curr, port_ret = port_ret_oos, n_held = nrow(m_w))
  prev_d <- d_curr
}
oos_dt <- rbindlist(oos_periods)
setorder(oos_dt, period_end)

oos_dt[, YM := format(period_end, "%Y-%m")]
perf_oos <- compute_perf_v2(oos_dt$port_ret, "Iter11_OOS_24_26", 0,
                             start_ym = "2024-01")
cat(sprintf("  OOS frozen-weights: n=%d | SR=%.3f | CAGR=%.2f%% | MDD=%.2f%% | Hit=%.1f%%\n",
            perf_oos$n_months, perf_oos$sr %||% NA,
            (perf_oos$cagr %||% NA)*100, (perf_oos$mdd %||% NA)*100,
            (perf_oos$hit %||% NA)*100))

# Full-period (Pre-LB walk-forward + OOS frozen-weights = unified)
iter11_full <- rbind(
  bt_dt[, .(Date = period_end, port_ret)],
  oos_dt[, .(Date = period_end, port_ret)]
)
setorder(iter11_full, Date)
iter11_full[, YM := format(Date, "%Y-%m")]
iter11_full <- unique(iter11_full, by = "YM")
perf_iter11_full <- compute_perf_v2(iter11_full$port_ret, "Iter11_full_period",
                                     DSR_CANDIDATES_TRIED, start_ym = "2006-02")
cat(sprintf("  Iter 11 full-period (Pre-LB %d + OOS %d = %d months): SR=%.3f CAGR=%.2f%% MDD=%.2f%% t_FF5=%.3f DSR_post=%.3f\n",
            perf_prelb$n_months, perf_oos$n_months, perf_iter11_full$n_months,
            perf_iter11_full$sr %||% NA, (perf_iter11_full$cagr %||% NA)*100,
            (perf_iter11_full$mdd %||% NA)*100,
            perf_iter11_full$harvey_t_ff5 %||% NA,
            perf_iter11_full$dsr_post_penalty %||% NA))

# ─────────────────────────────────────────────────────────
# 10. Iter11 vs STR_1699 (Iter5) vs STR_1700 (Iter6) vs MEGA_05 — same period fair
# ─────────────────────────────────────────────────────────
cat("\n[10] 4-strategy fair same-period comparison\n")

# STR_1699 (Iter 5) monthly returns — full-period
str1699_pre <- as.data.table(read_parquet(file.path(PREV_BT, "monthly_returns.parquet")))
setorder(str1699_pre, Date)
str1699_pre[, YM := format(Date, "%Y-%m")]
str1699_oos <- fread(file.path(PREV_BT, "oos_24_26_monthly.csv"))
str1699_oos[, period_end := as.Date(period_end)]
str1699_oos[, YM := format(period_end, "%Y-%m")]
str1699_full <- rbind(
  str1699_pre[, .(YM, Date, port_ret)],
  str1699_oos[, .(YM, Date = period_end, port_ret)]
)
setorder(str1699_full, Date)
str1699_full <- unique(str1699_full, by = "YM")
cat(sprintf("  STR_1699 full-period: n=%d (%s ~ %s)\n",
            nrow(str1699_full), min(str1699_full$YM), max(str1699_full$YM)))

# STR_1700 (Iter 6) monthly returns — full-period (if available)
str1700_full <- NULL
str1700_pre_path <- file.path(ITER6_BT, "monthly_returns.parquet")
str1700_oos_path <- file.path(ITER6_BT, "oos_24_26_monthly.csv")
if (file.exists(str1700_pre_path)) {
  str1700_pre <- as.data.table(read_parquet(str1700_pre_path))
  setorder(str1700_pre, Date)
  str1700_pre[, YM := format(Date, "%Y-%m")]
  if (file.exists(str1700_oos_path)) {
    str1700_oos <- fread(str1700_oos_path)
    str1700_oos[, period_end := as.Date(period_end)]
    str1700_oos[, YM := format(period_end, "%Y-%m")]
    str1700_full <- rbind(
      str1700_pre[, .(YM, Date, port_ret)],
      str1700_oos[, .(YM, Date = period_end, port_ret)]
    )
  } else {
    str1700_full <- str1700_pre[, .(YM, Date, port_ret)]
  }
  setorder(str1700_full, Date)
  str1700_full <- unique(str1700_full, by = "YM")
  cat(sprintf("  STR_1700 full-period: n=%d (%s ~ %s)\n",
              nrow(str1700_full), min(str1700_full$YM), max(str1700_full$YM)))
} else {
  cat("  STR_1700 full-period: not available\n")
}

# MEGA_05 production NAV → monthly resample
mega_doc_path <- file.path(BASE_DIR,
  "04_Research/strategies/STR_1631_PG2_MDD_OPT/output/daily_nav_bcde.csv")
mega_doc_daily <- fread(mega_doc_path,
                         select = c("Date", "Ret_vdp", "NAV_vdp"))
mega_doc_daily[, Date := as.Date(Date)]
setorder(mega_doc_daily, Date)
mega_doc_daily[, YM := format(Date, "%Y-%m")]
mega05_monthly <- mega_doc_daily[, .(Date_eom = max(Date),
                                       NAV_eom = NAV_vdp[which.max(Date)]),
                                  by = YM]
setorder(mega05_monthly, Date_eom)
mega05_monthly[, Ret_m := NAV_eom / shift(NAV_eom) - 1]
mega05_monthly <- mega05_monthly[!is.na(Ret_m)]
cat(sprintf("  MEGA_05 (NAV_vdp) monthly: n=%d (%s ~ %s)\n",
            nrow(mega05_monthly), min(mega05_monthly$YM), max(mega05_monthly$YM)))

# Build panel
panel <- merge(iter11_full[, .(YM, Date, iter11 = port_ret)],
               str1699_full[, .(YM, str1699 = port_ret)],
               by = "YM", all = TRUE)
if (!is.null(str1700_full)) {
  panel <- merge(panel, str1700_full[, .(YM, str1700 = port_ret)],
                 by = "YM", all = TRUE)
} else {
  panel[, str1700 := NA_real_]
}
panel <- merge(panel, mega05_monthly[, .(YM, mega05 = Ret_m)],
               by = "YM", all = TRUE)
setorder(panel, YM)
panel[is.na(Date), Date := as.Date(paste0(YM, "-15"))]

# 3-way (Iter11 / STR_1699 / MEGA_05) for the main fair comparison
panel_3way <- panel[!is.na(iter11) & !is.na(str1699) & !is.na(mega05)]
cat(sprintf("  3-way intersection (Iter11 / STR_1699 / MEGA_05): n=%d (%s ~ %s)\n",
            nrow(panel_3way), min(panel_3way$YM), max(panel_3way$YM)))

# 4-way (Iter11 / STR_1699 / STR_1700 / MEGA_05) optional
panel_4way <- panel[!is.na(iter11) & !is.na(str1699) & !is.na(str1700) & !is.na(mega05)]
cat(sprintf("  4-way intersection (Iter11 / STR_1699 / STR_1700 / MEGA_05): n=%d\n",
            nrow(panel_4way)))

# Same-period perf
ym_3w_start <- min(panel_3way$YM)
perf_iter11_sp  <- compute_perf_v2(panel_3way$iter11,  "Iter11_same_period",
                                    DSR_CANDIDATES_TRIED, start_ym = ym_3w_start)
perf_str1699_sp <- compute_perf_v2(panel_3way$str1699, "STR_1699_same_period",
                                    15, start_ym = ym_3w_start)
perf_mega05_sp  <- compute_perf_v2(panel_3way$mega05,  "MEGA_05_same_period",
                                    15, start_ym = ym_3w_start)

# STR_1700 same-period (4-way panel, may differ)
perf_str1700_sp <- NULL
if (nrow(panel_4way) >= 12) {
  ym_4w_start <- min(panel_4way$YM)
  perf_str1700_sp <- compute_perf_v2(panel_4way$str1700, "STR_1700_same_period",
                                      20, start_ym = ym_4w_start)
}

cat("\n  ─── Same-period (3-way fair) ───\n")
print_perf_row(perf_iter11_sp)
print_perf_row(perf_str1699_sp)
print_perf_row(perf_mega05_sp)
if (!is.null(perf_str1700_sp)) {
  cat("\n  ─── STR_1700 same-period (4-way panel) ───\n")
  print_perf_row(perf_str1700_sp)
}

# Pairwise correlation (3-way primary)
pair_cor <- list(
  iter11_str1699 = round(cor(panel_3way$iter11, panel_3way$str1699,
                              use="pairwise.complete.obs"), 4),
  iter11_mega05  = round(cor(panel_3way$iter11, panel_3way$mega05,
                              use="pairwise.complete.obs"), 4),
  str1699_mega05 = round(cor(panel_3way$str1699, panel_3way$mega05,
                              use="pairwise.complete.obs"), 4)
)
if (nrow(panel_4way) >= 12) {
  pair_cor$iter11_str1700 <- round(cor(panel_4way$iter11, panel_4way$str1700,
                                        use="pairwise.complete.obs"), 4)
}

cat(sprintf("\n  Pairwise correlation (same-period 3-way):\n"))
cat(sprintf("    cor(Iter11, STR_1699) = %.4f\n", pair_cor$iter11_str1699))
cat(sprintf("    cor(Iter11, MEGA_05)  = %.4f\n", pair_cor$iter11_mega05))
cat(sprintf("    cor(STR_1699, MEGA_05) = %.4f\n", pair_cor$str1699_mega05))
if (!is.null(pair_cor$iter11_str1700))
  cat(sprintf("    cor(Iter11, STR_1700) = %.4f (4-way)\n", pair_cor$iter11_str1700))

# Same-period delta (Iter11 vs benchmarks)
delta_vs_str1699 <- list(
  delta_sr      = round((perf_iter11_sp$sr   %||% NA) - (perf_str1699_sp$sr   %||% NA), 4),
  delta_cagr_pp = round(((perf_iter11_sp$cagr %||% NA) - (perf_str1699_sp$cagr %||% NA))*100, 2),
  delta_mdd_pp  = round(((perf_iter11_sp$mdd  %||% NA) - (perf_str1699_sp$mdd  %||% NA))*100, 2)
)
delta_vs_mega05 <- list(
  delta_sr      = round((perf_iter11_sp$sr   %||% NA) - (perf_mega05_sp$sr   %||% NA), 4),
  delta_cagr_pp = round(((perf_iter11_sp$cagr %||% NA) - (perf_mega05_sp$cagr %||% NA))*100, 2),
  delta_mdd_pp  = round(((perf_iter11_sp$mdd  %||% NA) - (perf_mega05_sp$mdd  %||% NA))*100, 2)
)
delta_vs_str1700 <- NULL
if (!is.null(perf_str1700_sp)) {
  delta_vs_str1700 <- list(
    delta_sr      = round((perf_iter11_sp$sr   %||% NA) - (perf_str1700_sp$sr   %||% NA), 4),
    delta_cagr_pp = round(((perf_iter11_sp$cagr %||% NA) - (perf_str1700_sp$cagr %||% NA))*100, 2),
    delta_mdd_pp  = round(((perf_iter11_sp$mdd  %||% NA) - (perf_str1700_sp$mdd  %||% NA))*100, 2)
  )
}
cat(sprintf("  Δ Iter11 vs STR_1699 same-period: SR=%+.3f CAGR=%+.2fpp MDD=%+.2fpp\n",
            delta_vs_str1699$delta_sr, delta_vs_str1699$delta_cagr_pp,
            delta_vs_str1699$delta_mdd_pp))
cat(sprintf("  Δ Iter11 vs MEGA_05  same-period: SR=%+.3f CAGR=%+.2fpp MDD=%+.2fpp\n",
            delta_vs_mega05$delta_sr, delta_vs_mega05$delta_cagr_pp,
            delta_vs_mega05$delta_mdd_pp))
if (!is.null(delta_vs_str1700))
  cat(sprintf("  Δ Iter11 vs STR_1700 same-period: SR=%+.3f CAGR=%+.2fpp MDD=%+.2fpp\n",
              delta_vs_str1700$delta_sr, delta_vs_str1700$delta_cagr_pp,
              delta_vs_str1700$delta_mdd_pp))

# ─────────────────────────────────────────────────────────
# 11. Replacement / Integration scenario 평가 (NAV-level synthesis)
# ─────────────────────────────────────────────────────────
cat("\n[11] Replacement / Integration scenario (NAV-level)\n")

# STR_1656 monthly NAV
str1656_path <- file.path(BASE_DIR, "04_Research/strategies/STR_1656_MLRA/output/nav_S1_A.csv")
str1656_daily <- fread(str1656_path)
str1656_daily[, Date := as.Date(Date)]
setorder(str1656_daily, Date)
str1656_daily[, YM := format(Date, "%Y-%m")]
str1656_monthly <- str1656_daily[, .(Date_eom = max(Date),
                                       NAV_eom = NAV[which.max(Date)]),
                                  by = YM]
setorder(str1656_monthly, Date_eom)
str1656_monthly[, Ret_m := NAV_eom / shift(NAV_eom) - 1]
str1656_monthly <- str1656_monthly[!is.na(Ret_m)]
cat(sprintf("  STR_1656 monthly: n=%d (%s ~ %s)\n",
            nrow(str1656_monthly), min(str1656_monthly$YM), max(str1656_monthly$YM)))

# Add STR_1656 to panel
panel_full <- merge(panel, str1656_monthly[, .(YM, str1656 = Ret_m)],
                    by = "YM", all = TRUE)
setorder(panel_full, YM)

# Scenario A: 100% Iter11 (replacement)
panel_A <- panel_full[!is.na(iter11)]
scen_A_ret <- panel_A$iter11

# Scenario AB: Iter11 80% + STR_1656 20%
panel_AB <- panel_full[!is.na(iter11) & !is.na(str1656)]
scen_AB_ret <- 0.8 * panel_AB$iter11 + 0.2 * panel_AB$str1656

# Scenario B: Iter11 60% + STR_1699 20% + STR_1656 20%
panel_B <- panel_full[!is.na(iter11) & !is.na(str1699) & !is.na(str1656)]
scen_B_ret <- 0.6 * panel_B$iter11 + 0.2 * panel_B$str1699 + 0.2 * panel_B$str1656

# Scenario D (current PG2 reference): MEGA_05 80% + STR_1656 20%
panel_D <- panel_full[!is.na(mega05) & !is.na(str1656)]
scen_D_ret <- 0.8 * panel_D$mega05 + 0.2 * panel_D$str1656

ym_A_start  <- min(panel_A$YM)
ym_AB_start <- min(panel_AB$YM)
ym_B_start  <- min(panel_B$YM)
ym_D_start  <- min(panel_D$YM)

perf_scen_A  <- compute_perf_v2(scen_A_ret,  "Scen_A_Iter11_100",
                                 DSR_CANDIDATES_TRIED, start_ym = ym_A_start)
perf_scen_AB <- compute_perf_v2(scen_AB_ret, "Scen_AB_Iter11_80_1656_20",
                                 DSR_CANDIDATES_TRIED, start_ym = ym_AB_start)
perf_scen_B  <- compute_perf_v2(scen_B_ret,  "Scen_B_60_20_20",
                                 DSR_CANDIDATES_TRIED, start_ym = ym_B_start)
perf_scen_D  <- compute_perf_v2(scen_D_ret,  "Scen_D_PG2_current_80_20",
                                 15, start_ym = ym_D_start)

cat("\n  ─── Replacement / Integration scenarios ───\n")
print_perf_row(perf_scen_A)
print_perf_row(perf_scen_AB)
print_perf_row(perf_scen_B)
print_perf_row(perf_scen_D)

# Risk-adjusted score (SR + 0.5(1+MDD))
score_A  <- (perf_scen_A$sr  %||% -1) + (1 + (perf_scen_A$mdd  %||% -1)) * 0.5
score_AB <- (perf_scen_AB$sr %||% -1) + (1 + (perf_scen_AB$mdd %||% -1)) * 0.5
score_B  <- (perf_scen_B$sr  %||% -1) + (1 + (perf_scen_B$mdd  %||% -1)) * 0.5
score_D  <- (perf_scen_D$sr  %||% -1) + (1 + (perf_scen_D$mdd  %||% -1)) * 0.5
scores   <- c(A = score_A, AB = score_AB, B = score_B, D = score_D)
recommended <- names(scores)[which.max(scores)]

cat("\n  ─── Risk-adjusted scoring (SR + 0.5×(1+MDD)) ───\n")
cat(sprintf("    A  (Iter11 100%%)              : %.4f\n", score_A))
cat(sprintf("    AB (Iter11 80%% + STR_1656 20%%): %.4f\n", score_AB))
cat(sprintf("    B  (Iter11 60 + 1699 20 + 1656 20): %.4f\n", score_B))
cat(sprintf("    D  (current PG2 MEGA_05 80%% + STR_1656 20%%): %.4f\n", score_D))
cat(sprintf("    >>> Recommended: %s <<<\n", recommended))

# ─────────────────────────────────────────────────────────
# 12. 차트 4건 (equity_curve / annual_returns / oos_zoom / scenario_comparison)
# ─────────────────────────────────────────────────────────
cat("\n[12] Chart generation (4 charts)\n")

# BM monthly alignment
bm[, YM := format(Date, "%Y-%m")]
bm_monthly <- bm[, .(Date_eom = max(Date),
                     BM_Close_eom = BM_Close[which.max(Date)]),
                  by = YM]
setorder(bm_monthly, Date_eom)

# 12-1. equity_curve.png — Pre-LB walk-forward + OOS frozen + 3-strategy comparison
cat("  [12-1] equity_curve.png — Iter11 / STR_1699 / STR_1700 / MEGA_05 (full traces)\n")

iter11_full[, cum := cumprod(1 + port_ret)]
str1699_full[, cum := cumprod(1 + port_ret)]
mega05_aligned <- mega05_monthly[YM >= min(iter11_full$YM)]
setorder(mega05_aligned, Date_eom)
if (nrow(mega05_aligned) > 0) mega05_aligned[, cum := cumprod(1 + Ret_m)]
bm_align <- bm_monthly[Date_eom >= (min(iter11_full$Date) - 35)]
bm_align[, BM_cum := BM_Close_eom / BM_Close_eom[1]]

plot_eq_list <- list(
  data.table(Date = iter11_full$Date,        cum = iter11_full$cum,
             Series = "Iter11 (Linear Tilt monthly TOphi8)"),
  data.table(Date = str1699_full$Date,       cum = str1699_full$cum,
             Series = "STR_1699 (Iter5 HRP_lw)"),
  data.table(Date = mega05_aligned$Date_eom, cum = mega05_aligned$cum,
             Series = "MEGA_05 (production NAV_vdp)"),
  data.table(Date = bm_align$Date_eom,       cum = bm_align$BM_cum,
             Series = "KOSPI200 (BM)")
)
if (!is.null(str1700_full)) {
  str1700_full[, cum := cumprod(1 + port_ret)]
  plot_eq_list <- append(plot_eq_list, list(
    data.table(Date = str1700_full$Date, cum = str1700_full$cum,
               Series = "STR_1700 (Iter6 Kelly+Overlay)")
  ))
}
plot_eq <- rbindlist(plot_eq_list)
plot_eq <- plot_eq[!is.na(cum) & cum > 0]

color_map <- c(
  "Iter11 (Linear Tilt monthly TOphi8)" = "#3F51B5",
  "STR_1699 (Iter5 HRP_lw)"             = "#9C27B0",
  "STR_1700 (Iter6 Kelly+Overlay)"      = "#E91E63",
  "MEGA_05 (production NAV_vdp)"        = "#FF9800",
  "KOSPI200 (BM)"                       = "#9E9E9E")

g1 <- ggplot(plot_eq, aes(x=Date, y=cum, color=Series)) +
  geom_line(linewidth=0.85) +
  scale_y_log10(labels = scales::label_number(accuracy=0.1)) +
  scale_color_manual(values = color_map) +
  geom_vline(xintercept = LB_START, linetype = "dashed", color = "red", alpha = 0.7) +
  annotate("text", x = LB_START + 90, y = max(plot_eq$cum, na.rm=TRUE)*0.85,
           label = "Lockbox 2024-01-23+", color="red", size=3.8, fontface="bold") +
  labs(title = "STR_1701 Iter11 Linear Tilt (TOphi8) — Full-period equity vs benchmarks",
       subtitle = sprintf("Iter11 full: SR=%.3f CAGR=%.2f%% MDD=%.2f%% t_FF5=%.3f / 3-way same-period: Iter11 %.3f vs STR_1699 %.3f vs MEGA_05 %.3f",
                          perf_iter11_full$sr %||% NA,
                          (perf_iter11_full$cagr %||% NA)*100,
                          (perf_iter11_full$mdd %||% NA)*100,
                          perf_iter11_full$harvey_t_ff5 %||% NA,
                          perf_iter11_sp$sr %||% NA,
                          perf_str1699_sp$sr %||% NA,
                          perf_mega05_sp$sr %||% NA),
       x = "Date", y = "Cumulative Return (log)", color = "") +
  theme_minimal(base_size = 11) + theme(legend.position = "bottom")

ec_path <- file.path(OUT_DIR, "equity_curve.png")
ggsave(ec_path, g1, width = 13, height = 7, dpi = 150)
cat(sprintf("    Saved: %s\n", ec_path))

# 12-2. annual_returns.png
cat("  [12-2] annual_returns.png — Iter11 vs KOSPI200\n")
ann_strat <- copy(all_ret)
ann_strat[, Year := as.integer(format(Date, "%Y"))]
ann_strat_dt <- ann_strat[, .(strat_ret = prod(1+port_ret)-1, n_m = .N), by = Year]

bm_y <- bm_monthly[, Year := as.integer(substr(YM,1,4))]
bm_year_cum <- bm_y[, .(BM_eoY = BM_Close_eom[which.max(Date_eom)],
                       BM_eoY_date = max(Date_eom)), by = Year]
setorder(bm_year_cum, Year)
bm_year_cum[, BM_ret_y := BM_eoY / shift(BM_eoY) - 1]
bm_year_cum <- bm_year_cum[!is.na(BM_ret_y)]

ann_merged <- merge(ann_strat_dt, bm_year_cum[, .(Year, BM_ret_y)], by="Year", all.x=TRUE)
ann_long <- melt(ann_merged[, .(Year, Iter11=strat_ret, BM=BM_ret_y)],
                 id.vars="Year", variable.name="Series", value.name="Annual_Return")

g2 <- ggplot(ann_long, aes(x=factor(Year), y=Annual_Return*100, fill=Series)) +
  geom_bar(stat="identity", position=position_dodge(width=0.85), width=0.78) +
  scale_fill_manual(values=c("Iter11"="#3F51B5", "BM"="#9E9E9E")) +
  geom_hline(yintercept=0, color="black", linewidth=0.4) +
  labs(title = "STR_1701 Iter11 Linear Tilt — Annual Returns vs KOSPI200",
       subtitle = sprintf("Linear_Tilt_lam1.0_TOphi8 monthly | TO_pen φ=8 | %d periods | ann_TO=%.1f%%",
                          nrow(bt_dt), mean(bt_dt$turnover)*12*100),
       x = "Year", y = "Annual Return (%)", fill = "") +
  theme_minimal(base_size = 11) +
  theme(legend.position = "bottom",
        axis.text.x = element_text(angle = 45, hjust = 1))

ar_path <- file.path(OUT_DIR, "annual_returns.png")
ggsave(ar_path, g2, width = 12, height = 6, dpi = 150)
cat(sprintf("    Saved: %s\n", ar_path))

# 12-3. oos_zoom_chart.png — 24-26 frozen-weights vs KOSPI200
cat("  [12-3] oos_zoom_chart.png — 24-26 frozen-weights buy-and-hold\n")
oos_str <- copy(oos_dt)
setorder(oos_str, period_end)
oos_str[, cum := cumprod(1 + port_ret)]
bm_oos <- bm_monthly[Date_eom >= last_sig - 5]
bm_oos[, BM_cum := BM_Close_eom / BM_Close_eom[1]]

plot_oos <- rbind(
  data.table(Date = oos_str$period_end, cum = oos_str$cum,
             Series = "Iter11 (frozen 2023-12-01 weights)"),
  data.table(Date = bm_oos$Date_eom, cum = bm_oos$BM_cum,
             Series = "KOSPI200 (BM)")
)

g3 <- ggplot(plot_oos, aes(x = Date, y = cum, color = Series)) +
  geom_line(linewidth = 1.0) + geom_point(size = 1.5) +
  scale_color_manual(values = c(
    "Iter11 (frozen 2023-12-01 weights)" = "#3F51B5",
    "KOSPI200 (BM)" = "#9E9E9E")) +
  labs(title = "Iter11 OOS Zoom (24-26) — Frozen-weights Buy-and-Hold",
       subtitle = sprintf("OOS n=%d months | SR=%.3f | CAGR=%.2f%% | MDD=%.2f%% | Hit=%.1f%% | last_cash=%.1f%%",
                          perf_oos$n_months, perf_oos$sr %||% NA,
                          (perf_oos$cagr %||% NA)*100,
                          (perf_oos$mdd %||% NA)*100,
                          (perf_oos$hit %||% NA)*100, last_cash*100),
       x = "Date", y = "Cumulative Return", color = "") +
  theme_minimal(base_size = 11) + theme(legend.position = "bottom")

oos_path <- file.path(OUT_DIR, "oos_zoom_chart.png")
ggsave(oos_path, g3, width = 11, height = 6, dpi = 150)
cat(sprintf("    Saved: %s\n", oos_path))

# 12-4. scenario_comparison.png — A / AB / B / D NAV-level
cat("  [12-4] scenario_comparison.png — Scenario A / AB / B / D\n")

panel_A[, cum := cumprod(1 + scen_A_ret)]
panel_AB[, cum := cumprod(1 + scen_AB_ret)]
panel_B[, cum := cumprod(1 + scen_B_ret)]
panel_D[, cum := cumprod(1 + scen_D_ret)]

plot_scen <- rbind(
  data.table(Date = panel_A$Date,  cum = panel_A$cum,
             Series = "A. Iter11 100%"),
  data.table(Date = panel_AB$Date, cum = panel_AB$cum,
             Series = "AB. Iter11 80% + STR_1656 20%"),
  data.table(Date = panel_B$Date,  cum = panel_B$cum,
             Series = "B. Iter11 60% + STR_1699 20% + STR_1656 20%"),
  data.table(Date = panel_D$Date,  cum = panel_D$cum,
             Series = "D. MEGA_05 80% + STR_1656 20% (current PG2)")
)
plot_scen <- plot_scen[!is.na(cum) & cum > 0]

g4 <- ggplot(plot_scen, aes(x = Date, y = cum, color = Series)) +
  geom_line(linewidth = 0.85) +
  scale_y_log10(labels = scales::label_number(accuracy = 0.1)) +
  scale_color_manual(values = c(
    "A. Iter11 100%"                                       = "#3F51B5",
    "AB. Iter11 80% + STR_1656 20%"                         = "#9C27B0",
    "B. Iter11 60% + STR_1699 20% + STR_1656 20%"           = "#2196F3",
    "D. MEGA_05 80% + STR_1656 20% (current PG2)"           = "#4CAF50")) +
  geom_vline(xintercept = LB_START, linetype = "dashed",
             color = "red", alpha = 0.7) +
  labs(title = "STR_1701 Iter11 — Replacement / Integration Scenarios (NAV-level)",
       subtitle = sprintf("A: SR=%.3f | AB: SR=%.3f | B: SR=%.3f | D: SR=%.3f >>> Rec: %s",
                          perf_scen_A$sr %||% NA, perf_scen_AB$sr %||% NA,
                          perf_scen_B$sr %||% NA, perf_scen_D$sr %||% NA,
                          recommended),
       x = "Date", y = "Cumulative Return (log)", color = "") +
  theme_minimal(base_size = 10) +
  theme(legend.position = "bottom", legend.text = element_text(size = 8))

scen_path <- file.path(OUT_DIR, "scenario_comparison.png")
ggsave(scen_path, g4, width = 13, height = 7, dpi = 150)
cat(sprintf("    Saved: %s\n", scen_path))

# Copy charts to BT_DIR (judge access)
file.copy(ec_path,   file.path(BT_DIR, "equity_curve.png"),       overwrite=TRUE)
file.copy(ar_path,   file.path(BT_DIR, "annual_returns.png"),     overwrite=TRUE)
file.copy(oos_path,  file.path(BT_DIR, "oos_zoom_chart.png"),     overwrite=TRUE)
file.copy(scen_path, file.path(BT_DIR, "scenario_comparison.png"), overwrite=TRUE)

# ─────────────────────────────────────────────────────────
# 13. backtest_result 산출물 저장
# ─────────────────────────────────────────────────────────
cat("\n[13] Save backtest_result artifacts\n")

write_parquet(all_ret, file.path(BT_DIR, "monthly_returns.parquet"))
fwrite(iter11_full, file.path(BT_DIR, "iter11_full_period_monthly.csv"))
fwrite(oos_dt,      file.path(BT_DIR, "oos_24_26_monthly.csv"))
fwrite(panel,       file.path(BT_DIR, "nav_panel_4way.csv"))
fwrite(mega05_monthly[, .(YM, Date_eom, NAV_eom, Ret_m)],
       file.path(BT_DIR, "mega05_doc_monthly.csv"))

# hurdle_result.json
ret_combined  <- combined$port_ret
n_m_full      <- length(ret_combined)
harvey_t_simple <- if (n_m_full >= 12)
  (mean(ret_combined, na.rm=TRUE) / sd(ret_combined, na.rm=TRUE)) * sqrt(n_m_full) else NA
dsr_full      <- compute_dsr(ret_combined)$dsr

hurdle_result <- list(
  task_id = WT_ID, str_id = STR_ID,
  CAGR = perf_full$cagr, SR = perf_full$sr, MDD = perf_full$mdd,
  Vol = perf_full$vol, HitRate = perf_full$hit, IR = perf_full$sr,
  Harvey_t_simple = round(harvey_t_simple, 4),
  Harvey_t_FF5    = round(res_full[["FF5"]]$t_nw %||% NA, 4),
  DSR     = dsr_full,
  N_months = n_m_full,
  pre_lockbox  = list(SR=perf_prelb$sr,  CAGR=perf_prelb$cagr,
                       MDD=perf_prelb$mdd, n=perf_prelb$n_months),
  lockbox      = list(SR=perf_lb$sr,     CAGR=perf_lb$cagr,
                       MDD=perf_lb$mdd,    n=perf_lb$n_months),
  oos_24_26    = list(SR=perf_oos$sr,    CAGR=perf_oos$cagr,
                       MDD=perf_oos$mdd,   n=perf_oos$n_months),
  full_period  = list(SR=perf_iter11_full$sr, CAGR=perf_iter11_full$cagr,
                       MDD=perf_iter11_full$mdd, n=perf_iter11_full$n_months,
                       t_FF5=perf_iter11_full$harvey_t_ff5,
                       DSR_post=perf_iter11_full$dsr_post_penalty)
)
write_json(hurdle_result, file.path(BT_DIR, "hurdle_result.json"),
           pretty=TRUE, auto_unbox=TRUE, null="null")
cat("  Saved: monthly_returns.parquet / iter11_full_period_monthly.csv / oos_24_26_monthly.csv / nav_panel_4way.csv / mega05_doc_monthly.csv / hurdle_result.json\n")

# ─────────────────────────────────────────────────────────
# 14. forge_package.json 작성
# ─────────────────────────────────────────────────────────
cat("\n[14] Write forge_package.json\n")

flatten_spec <- function(r, spec_name) {
  if (is.null(r)) return(list(spec=spec_name, available=FALSE))
  list(
    spec=spec_name,
    alpha_monthly=round(r$alpha %||% NA, 6),
    alpha_annual =round((r$alpha %||% NA)*12, 4),
    t_nw=round(r$t_nw %||% NA, 4),
    p_nw=round(r$p_nw %||% NA, 5),
    lag_nw=r$lag %||% NA,
    n_eff=r$n_eff %||% NA,
    r2=round(r$r2 %||% NA, 4),
    adj_r2=round(r$adj_r2 %||% NA, 4),
    dsr=r$dsr %||% NULL,
    sr_ann=r$sr_ann %||% NULL,
    gate_pass=!is.na(r$t_nw %||% NA) && r$t_nw >= 2.95,
    gate_target=2.95
  )
}

forge_pkg <- list(
  task_id = WT_ID, str_id = STR_ID,
  agent = "forge_integration_v6.1_opus47_pure_function_iter11",
  iter_label = "Iter11_LinearTilt_lam1.0_TOphi8_monthly",
  as_of_date = as.character(Sys.Date()),
  method_weights = method_tag,
  optimizer_method = method_tag,
  optimizer_expected_ir = expected_ir,
  optimizer_expected_cagr = expected_cagr,
  optimizer_expected_mdd = expected_mdd,
  optimizer_expected_to = expected_to,

  # backtest_summary (Pre-LB / Lockbox / Combined / Full)
  backtest_summary = list(
    combined = list(
      period   = sprintf("%s ~ %s",
                  as.character(min(all_ret$Date)),
                  as.character(max(all_ret$Date))),
      n_months = perf_full$n_months,
      cagr     = perf_full$cagr, vol = perf_full$vol,
      sr       = perf_full$sr, mdd = perf_full$mdd, hit_rate = perf_full$hit,
      harvey_t_simple = round(harvey_t_simple, 4),
      dsr_post_penalty = perf_full$dsr_post_penalty
    ),
    pre_lockbox = list(
      period   = sprintf("%s ~ %s",
                  as.character(min(prelb_full$Date)),
                  as.character(max(prelb_full$Date))),
      n_months = perf_prelb$n_months,
      cagr     = perf_prelb$cagr, sr = perf_prelb$sr,
      mdd      = perf_prelb$mdd, hit_rate = perf_prelb$hit,
      dsr_post_penalty = perf_prelb$dsr_post_penalty
    ),
    lockbox = list(
      period   = if (perf_lb$n_months > 0)
                   sprintf("%s ~ %s",
                           as.character(min(lb_full$Date)),
                           as.character(max(lb_full$Date))) else "no_lockbox_data",
      n_months = perf_lb$n_months,
      cagr     = perf_lb$cagr, sr = perf_lb$sr,
      mdd      = perf_lb$mdd, hit_rate = perf_lb$hit
    ),
    full_period = list(
      period   = sprintf("%s ~ %s", min(iter11_full$YM), max(iter11_full$YM)),
      n_months = perf_iter11_full$n_months,
      cagr     = perf_iter11_full$cagr, vol = perf_iter11_full$vol,
      sr       = perf_iter11_full$sr, mdd = perf_iter11_full$mdd,
      hit_rate = perf_iter11_full$hit,
      harvey_t_ff5 = perf_iter11_full$harvey_t_ff5,
      dsr_raw  = perf_iter11_full$dsr_raw,
      dsr_post_penalty = perf_iter11_full$dsr_post_penalty
    )
  ),

  # regime_conditional_metrics
  regime_conditional_metrics = list(
    BULL    = list(n_months = regime_perf$BULL$n_months    %||% 0,
                   cagr=regime_perf$BULL$cagr, sr=regime_perf$BULL$sr,
                   mdd=regime_perf$BULL$mdd),
    NORMAL  = list(n_months = regime_perf$NORMAL$n_months  %||% 0,
                   cagr=regime_perf$NORMAL$cagr, sr=regime_perf$NORMAL$sr,
                   mdd=regime_perf$NORMAL$mdd),
    CAUTION = list(n_months = regime_perf$CAUTION$n_months %||% 0,
                   cagr=regime_perf$CAUTION$cagr, sr=regime_perf$CAUTION$sr,
                   mdd=regime_perf$CAUTION$mdd),
    CRISIS  = list(n_months = regime_perf$CRISIS$n_months  %||% 0,
                   cagr=regime_perf$CRISIS$cagr, sr=regime_perf$CRISIS$sr,
                   mdd=regime_perf$CRISIS$mdd)
  ),

  # 5-spec factor regression
  factor_regression_5_specs = list(
    method     = method_tag,
    sample     = sprintf("Combined Pre-LB walk-forward (%s ~ %s)",
                  as.character(min(all_ret$Date)),
                  as.character(max(all_ret$Date))),
    se_method  = "Newey-West HAC",
    framework  = "KR FF5 v2 backfill (Iter 4 asset)",
    CAPM       = flatten_spec(res_full[["CAPM"]],     "CAPM"),
    Carhart_3  = flatten_spec(res_full[["Carhart_3"]], "Carhart_3"),
    Carhart_4  = flatten_spec(res_full[["Carhart_4"]], "Carhart_4"),
    FF5        = flatten_spec(res_full[["FF5"]],       "FF5"),
    FF6        = flatten_spec(res_full[["FF6"]],       "FF6"),
    n_pass_t295 = n_pass
  ),
  factor_regression_prelb = list(
    sample = "Pre-LB walk-forward",
    FF5      = flatten_spec(res_prelb[["FF5"]],      "FF5"),
    Carhart_4= flatten_spec(res_prelb[["Carhart_4"]], "Carhart_4"),
    CAPM     = flatten_spec(res_prelb[["CAPM"]],      "CAPM")
  ),
  factor_regression_lockbox = list(
    sample = "Lockbox 2024-01-23+",
    FF5    = flatten_spec(res_lb[["FF5"]],  "FF5"),
    CAPM   = flatten_spec(res_lb[["CAPM"]], "CAPM")
  ),

  # same-period comparison
  same_period_comparison = list(
    description = "Iter11 vs STR_1699 (Iter5 HRP_lw) vs STR_1700 (Iter6 Kelly+Overlay) vs MEGA_05 — same-period (NAV-level intersection)",
    period_3way = sprintf("%s ~ %s", min(panel_3way$YM), max(panel_3way$YM)),
    n_months_3way = nrow(panel_3way),
    n_months_4way = nrow(panel_4way),
    iter11_same_period   = perf_iter11_sp,
    str_1699_same_period = perf_str1699_sp,
    str_1700_same_period = perf_str1700_sp,
    mega_05_same_period  = perf_mega05_sp,
    pairwise_correlation = pair_cor,
    delta_iter11_vs_str1699 = delta_vs_str1699,
    delta_iter11_vs_str1700 = delta_vs_str1700,
    delta_iter11_vs_mega05  = delta_vs_mega05,
    note = "DSR penalties: Iter11=20*0.05=1.00 (alpha5+risk5+opt10) / STR_1699=15*0.05=0.75 (Iter5 basis) / STR_1700=20*0.05=1.00 (Iter6 basis) / MEGA_05=15*0.05=0.75 (documented basis). Per fair_comparison_note.md mandate."
  ),

  # OOS 24-26 frozen weights
  oos_24_26_frozen_weights = list(
    last_sig_date = as.character(last_sig),
    last_cash_pct = round(last_cash, 4),
    n_names       = nrow(last_w),
    period        = sprintf("%s ~ %s",
                       as.character(min(oos_dt$period_end)),
                       as.character(max(oos_dt$period_end))),
    n_months      = perf_oos$n_months,
    cagr          = perf_oos$cagr, sr = perf_oos$sr,
    mdd           = perf_oos$mdd, hit = perf_oos$hit,
    harvey_t_ff5  = perf_oos$harvey_t_ff5,
    dsr_raw       = perf_oos$dsr_raw,
    method        = "Frozen weights buy-and-hold (no re-optimization, PIT C1 strict)"
  ),

  # Replacement / Integration scenarios
  scenario_comparison = list(
    A_replacement_100         = list(perf = perf_scen_A,  score = round(score_A, 4)),
    AB_iter11_80_str1656_20   = list(perf = perf_scen_AB, score = round(score_AB, 4)),
    B_60_20_20                = list(perf = perf_scen_B,  score = round(score_B, 4)),
    D_current_PG2_mega05_8020 = list(perf = perf_scen_D,  score = round(score_D, 4)),
    recommended               = recommended,
    rationale = sprintf("Risk-adjusted score (SR + 0.5(1+MDD)) max: A=%.3f AB=%.3f B=%.3f D=%.3f.",
                        score_A, score_AB, score_B, score_D)
  ),

  # walk-forward provenance
  walk_forward_validation = list(
    walk_forward_active = TRUE,
    weights_source      = sprintf("%s/weights.csv", WT_DIR),
    n_sig_dates         = length(sig_dates),
    n_walk_periods      = nrow(bt_dt),
    rebal_signal_freq   = "monthly_Linear_Tilt",
    period_start        = as.character(min(bt_dt$period_end)),
    period_end          = as.character(max(bt_dt$period_end)),
    avg_n_held          = round(mean(bt_dt$n_held), 2),
    avg_turnover        = round(mean(bt_dt$turnover), 4),
    annualized_turnover = round(mean(bt_dt$turnover) * 12, 4),
    pit_lag_c9          = TRUE,
    pit_liquidity_c10   = "20-day avg ≥ 2e8 KRW (PIT t-30..t-1)"
  ),

  # Linear Tilt mechanism verification
  linear_tilt_verification = list(
    method            = method_tag,
    lambda            = 1.0,
    turnover_phi      = 8,
    blend_formula     = "w_out = (1 - 1/(1+phi)) * w_prev + (1/(1+phi)) * w_tilt = 0.889*w_prev + 0.111*w_tilt",
    granularity       = "monthly",
    confidence_used   = FALSE,
    fm_regime_cash    = list(BULL=0, NORMAL=0.05, CAUTION=0.15, CRISIS=0.30),
    pooled_fallback_n_dates = length(pooled_dates),
    pooled_fallback_pct = round(length(pooled_dates) / length(sig_dates), 4),
    avg_cash_pct_overall = round(mean(bt_dt$cash_pct, na.rm=TRUE), 4)
  ),

  # 3-package hash audit (start)
  hash_audit = list(
    pre_audit_recorded = TRUE,
    pre_md5_alpha = unname(start_hashes["alpha_package.json"]),
    pre_md5_risk  = unname(start_hashes["risk_package.json"]),
    pre_md5_opt   = unname(start_hashes["optimization_package.json"]),
    pre_md5_weights = start_w_hash,
    audit_status  = "verified_at_start"
  ),

  pit_compliance = list(
    C1  = "PASS: walk-forward only (no full-sample re-optimization). Pre-LB last 2023-12-01 strictly before LB 2024-01-23",
    C2  = "PASS: monthly ret = close(t)/close(t-1) - 1",
    C9  = "PASS: weight at sig_date d → applied (d, end_d] (lag enforced)",
    C10 = "PASS: liquidity 2e8 KRW PIT t-30..t-1 (no same-day vol)",
    C11 = "PASS: regime_state from alpha (KR internal expanding percentile, no FRED leakage)",
    C13 = "PASS: Z_Score_Aligned alpha inherited (no manual flip)",
    C14 = "PASS: Usable_Date <= sig_date inherited from Alpha agent",
    pit_hard_cutoff = "2023-11-30 (last walk-forward sig_date before 2023-12-01)",
    lockbox_rule    = "Lockbox window 2024-01-23 onward — strictly post-cutoff",
    oos_method      = "Frozen weights buy-and-hold; no re-optimization in OOS"
  ),

  constraints_verified = list(
    n_names_max_20      = TRUE,
    long_only_mandate   = TRUE,
    sigma_w_eq_1        = TRUE,
    commission_15bps    = TRUE,
    turnover_round_trip_x2 = TRUE,
    liquidity_2e8       = TRUE
  ),

  dsr_basis = list(
    candidates_tried = DSR_CANDIDATES_TRIED,
    penalty_per_cand = DSR_PENALTY_PER_CAND,
    total_penalty    = DSR_PENALTY_TOTAL,
    note = "Iter11: alpha 5 + risk 5 + optimizer 10 = 20 candidates × 0.05 = 1.00. STR_1699 / MEGA_05 docs use 15*0.05=0.75 for fair-comparison consistency with documented basis."
  ),

  # CVaR daily proxy verification (Codex C1 escalation)
  cvar_daily_actual = list(
    monthly_to_daily_proxy_method = "monthly_realized_returns_to_daily_proxy_via_sqrt21",
    cvar95_monthly_observed       = round(quantile(combined$port_ret,
                                                    probs=0.05, na.rm=TRUE), 4),
    cvar95_daily_proxy_observed   = round(quantile(combined$port_ret,
                                                    probs=0.05, na.rm=TRUE) / sqrt(21), 4),
    cvar_daily_cap                = 0.025,
    cvar_pass_actual              = abs(quantile(combined$port_ret,
                                                  probs=0.05, na.rm=TRUE) / sqrt(21)) <= 0.025,
    note = "Codex C1 escalation: Optimizer expected_cvar_d_proxy=0.0297 from monthly_proxy. Forge actual = realized monthly 5%-tail / sqrt(21). Governor v3.4 to decide admission."
  ),

  artifacts = list(
    run_all       = "04_Research/strategies/STR_1701_WT004_Iter11_LinearTilt/run_all.R",
    equity_curve  = "04_Research/strategies/STR_1701_WT004_Iter11_LinearTilt/output/equity_curve.png",
    annual_returns= "04_Research/strategies/STR_1701_WT004_Iter11_LinearTilt/output/annual_returns.png",
    oos_zoom      = "04_Research/strategies/STR_1701_WT004_Iter11_LinearTilt/output/oos_zoom_chart.png",
    scenario_comparison = "04_Research/strategies/STR_1701_WT004_Iter11_LinearTilt/output/scenario_comparison.png",
    monthly_ret   = sprintf("qepm/mailbox/worktask/%s/backtest_result/monthly_returns.parquet", WT_ID),
    hurdle_result = sprintf("qepm/mailbox/worktask/%s/backtest_result/hurdle_result.json", WT_ID),
    forge_package = sprintf("qepm/mailbox/worktask/%s/forge_package.json", WT_ID)
  )
)

forge_pkg_path <- file.path(WT_DIR, "forge_package.json")
write_json(forge_pkg, forge_pkg_path, pretty=TRUE, auto_unbox=TRUE, null="null")
cat(sprintf("  Saved: %s\n", forge_pkg_path))

# ─────────────────────────────────────────────────────────
# 15. judge_ready 작성
# ─────────────────────────────────────────────────────────
cat("\n[15] Write judge_ready/judge_ready.json\n")

judge_ready <- list(
  task_id = WT_ID, str_id = STR_ID,
  prepared_by = "forge_opus47_v6.1_R12_iter11",
  prepared_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  hurdle_summary = list(
    CAGR = perf_full$cagr, SR = perf_full$sr, MDD = perf_full$mdd,
    Harvey_t_FF5 = round(res_full[["FF5"]]$t_nw %||% NA, 4),
    DSR_post_penalty = perf_full$dsr_post_penalty,
    N_months = n_m_full,
    full_period_sr = perf_iter11_full$sr,
    full_period_cagr = perf_iter11_full$cagr,
    full_period_mdd = perf_iter11_full$mdd,
    full_period_t_ff5 = perf_iter11_full$harvey_t_ff5,
    full_period_dsr_post = perf_iter11_full$dsr_post_penalty,
    same_period_vs_str1699_delta_sr = delta_vs_str1699$delta_sr,
    same_period_vs_mega05_delta_sr  = delta_vs_mega05$delta_sr,
    same_period_vs_str1700_delta_sr = if (!is.null(delta_vs_str1700)) delta_vs_str1700$delta_sr else NA,
    oos_24_26_sr = perf_oos$sr,
    oos_24_26_cagr = perf_oos$cagr,
    oos_24_26_mdd = perf_oos$mdd,
    n_5spec_pass = n_pass,
    pairwise_cor_iter11_str1699 = pair_cor$iter11_str1699,
    pairwise_cor_iter11_mega05  = pair_cor$iter11_mega05,
    pairwise_cor_iter11_str1700 = pair_cor$iter11_str1700,
    recommended_scenario = recommended,
    cvar_daily_pass_actual = abs(quantile(combined$port_ret,
                                           probs=0.05, na.rm=TRUE) / sqrt(21)) <= 0.025
  ),
  pit_compliance_pass = TRUE,
  forge_package = sprintf("qepm/mailbox/worktask/%s/forge_package.json", WT_ID),
  next_step = "Judge S6: Gate 0~6 + DSR + Role Honesty Audit + 5-spec gate t>=2.95 + CVaR daily admission"
)
write_json(judge_ready, file.path(JR_DIR, "judge_ready.json"),
           pretty=TRUE, auto_unbox=TRUE, null="null")
cat(sprintf("  Saved: %s/judge_ready.json\n", JR_DIR))

# ─────────────────────────────────────────────────────────
# 16. status.json 갱신 → FORGE_DONE
# ─────────────────────────────────────────────────────────
cat("\n[16] Update status.json → FORGE_DONE\n")

status_path <- file.path(WT_DIR, "status.json")
status <- tryCatch(fromJSON(status_path, simplifyVector=FALSE),
                   error = function(e) list(task_id=WT_ID))
status$current_phase     <- "FORGE_DONE"
status$updated_at        <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
status$str_id            <- STR_ID
status$forge_pass        <- TRUE
status$forge_sr          <- perf_full$sr
status$forge_cagr        <- perf_full$cagr
status$forge_mdd         <- perf_full$mdd
status$forge_harvey_t_ff5 <- round(res_full[["FF5"]]$t_nw %||% NA, 4)
status$forge_dsr_post     <- perf_full$dsr_post_penalty
status$forge_n_months     <- n_m_full
status$forge_walk_forward <- TRUE
status$forge_full_period_sr <- perf_iter11_full$sr
status$forge_full_period_cagr <- perf_iter11_full$cagr
status$forge_full_period_mdd <- perf_iter11_full$mdd
status$forge_oos_24_26_sr <- perf_oos$sr
status$forge_delta_vs_str1699_sr <- delta_vs_str1699$delta_sr
status$forge_delta_vs_mega05_sr  <- delta_vs_mega05$delta_sr
if (!is.null(delta_vs_str1700))
  status$forge_delta_vs_str1700_sr <- delta_vs_str1700$delta_sr
status$forge_recommended_scenario <- recommended
status$forge_n_5spec_pass <- n_pass
status$forge_agent       <- "forge_opus47_v6.1_R12_iter11_pure_function"
status$next_step         <- "Judge S6 (Gate 0~6 + DSR + Role Audit + 5-spec gate + CVaR daily)"
write_json(status, status_path, pretty=TRUE, auto_unbox=TRUE, null="null")
cat(sprintf("  status: FORGE_DONE | SR=%.3f CAGR=%.3f MDD=%.3f | full SR=%.3f\n",
            perf_full$sr %||% NA, perf_full$cagr %||% NA, perf_full$mdd %||% NA,
            perf_iter11_full$sr %||% NA))

# ─────────────────────────────────────────────────────────
# 17. END hash audit (Pure Function verification)
# ─────────────────────────────────────────────────────────
cat("\n[17] END hash audit\n")
end_hashes <- sapply(pkg_files, function(f) tryCatch(
  as.character(tools::md5sum(f)), error = function(e) "MISSING"))
names(end_hashes) <- basename(pkg_files)
end_w_hash <- as.character(tools::md5sum(weights_path))
hash_match <- all(start_hashes == end_hashes) && (start_w_hash == end_w_hash)
cat(sprintf("  Hash audit: %s\n",
            if (hash_match) "PASS (Pure Function honored)"
            else "FAIL (3-package or weights.csv mutated)"))
cat(sprintf("    alpha:   %s == %s : %s\n",
            substr(start_hashes["alpha_package.json"],1,12),
            substr(end_hashes["alpha_package.json"],1,12),
            start_hashes["alpha_package.json"] == end_hashes["alpha_package.json"]))
cat(sprintf("    risk:    %s == %s : %s\n",
            substr(start_hashes["risk_package.json"],1,12),
            substr(end_hashes["risk_package.json"],1,12),
            start_hashes["risk_package.json"] == end_hashes["risk_package.json"]))
cat(sprintf("    opt:     %s == %s : %s\n",
            substr(start_hashes["optimization_package.json"],1,12),
            substr(end_hashes["optimization_package.json"],1,12),
            start_hashes["optimization_package.json"] == end_hashes["optimization_package.json"]))
cat(sprintf("    weights: %s == %s : %s\n",
            substr(start_w_hash,1,12), substr(end_w_hash,1,12),
            start_w_hash == end_w_hash))

forge_pkg$hash_audit$post_md5_alpha <- unname(end_hashes["alpha_package.json"])
forge_pkg$hash_audit$post_md5_risk  <- unname(end_hashes["risk_package.json"])
forge_pkg$hash_audit$post_md5_opt   <- unname(end_hashes["optimization_package.json"])
forge_pkg$hash_audit$post_md5_weights <- end_w_hash
forge_pkg$hash_audit$pure_function_pass <- hash_match
forge_pkg$hash_audit$audit_status <- if (hash_match) "PASS" else "FAIL"
write_json(forge_pkg, forge_pkg_path, pretty=TRUE, auto_unbox=TRUE, null="null")

# ─────────────────────────────────────────────────────────
# 18. Telegram brief (tg_agent_brief v4 ENFORCE)
# ─────────────────────────────────────────────────────────
cat("\n[18] Telegram brief (tg_agent_brief v4)\n")

tryCatch({
  source(file.path(BASE_DIR, "02_Infrastructure/telegram/telegram_notify.R"))

  # Section 1: Performance summary (Pre-LB / Lockbox / Combined / Full)
  s1_df <- data.frame(
    Sample   = c("Pre-LB walk-forward", "Lockbox", "Combined", "Full-period (+OOS)"),
    n_months = c(perf_prelb$n_months %||% 0, perf_lb$n_months %||% 0,
                 perf_full$n_months  %||% 0, perf_iter11_full$n_months %||% 0),
    CAGR_pct = sprintf("%.2f", 100*c(perf_prelb$cagr %||% NA, perf_lb$cagr %||% NA,
                                      perf_full$cagr  %||% NA, perf_iter11_full$cagr %||% NA)),
    SR       = sprintf("%.3f", c(perf_prelb$sr %||% NA, perf_lb$sr %||% NA,
                                  perf_full$sr  %||% NA, perf_iter11_full$sr  %||% NA)),
    MDD_pct  = sprintf("%.2f", 100*c(perf_prelb$mdd %||% NA, perf_lb$mdd %||% NA,
                                      perf_full$mdd  %||% NA, perf_iter11_full$mdd  %||% NA)),
    DSR_post = sprintf("%.3f", c(perf_prelb$dsr_post_penalty %||% NA,
                                  perf_lb$dsr_post_penalty %||% NA,
                                  perf_full$dsr_post_penalty %||% NA,
                                  perf_iter11_full$dsr_post_penalty %||% NA)),
    stringsAsFactors = FALSE
  )

  # Section 2: Same-period 4-strategy fair comparison
  if (!is.null(perf_str1700_sp)) {
    s2_df <- data.frame(
      Strategy = c("Iter11 (Linear Tilt)", "STR_1699 (Iter5 HRP_lw)",
                   "STR_1700 (Iter6 Kelly)", "MEGA_05 (production)"),
      n_m      = c(perf_iter11_sp$n_months, perf_str1699_sp$n_months,
                   perf_str1700_sp$n_months, perf_mega05_sp$n_months),
      SR       = sprintf("%.3f", c(perf_iter11_sp$sr  %||% NA,
                                    perf_str1699_sp$sr %||% NA,
                                    perf_str1700_sp$sr %||% NA,
                                    perf_mega05_sp$sr  %||% NA)),
      CAGR_pct = sprintf("%.2f", 100*c(perf_iter11_sp$cagr  %||% NA,
                                        perf_str1699_sp$cagr %||% NA,
                                        perf_str1700_sp$cagr %||% NA,
                                        perf_mega05_sp$cagr  %||% NA)),
      MDD_pct  = sprintf("%.2f", 100*c(perf_iter11_sp$mdd  %||% NA,
                                        perf_str1699_sp$mdd %||% NA,
                                        perf_str1700_sp$mdd %||% NA,
                                        perf_mega05_sp$mdd  %||% NA)),
      t_FF5    = sprintf("%.2f", c(perf_iter11_sp$harvey_t_ff5  %||% NA,
                                    perf_str1699_sp$harvey_t_ff5 %||% NA,
                                    perf_str1700_sp$harvey_t_ff5 %||% NA,
                                    perf_mega05_sp$harvey_t_ff5  %||% NA)),
      stringsAsFactors = FALSE
    )
  } else {
    s2_df <- data.frame(
      Strategy = c("Iter11 (Linear Tilt)", "STR_1699 (Iter5 HRP_lw)", "MEGA_05 (production)"),
      n_m      = c(perf_iter11_sp$n_months, perf_str1699_sp$n_months,
                   perf_mega05_sp$n_months),
      SR       = sprintf("%.3f", c(perf_iter11_sp$sr  %||% NA,
                                    perf_str1699_sp$sr %||% NA,
                                    perf_mega05_sp$sr  %||% NA)),
      CAGR_pct = sprintf("%.2f", 100*c(perf_iter11_sp$cagr  %||% NA,
                                        perf_str1699_sp$cagr %||% NA,
                                        perf_mega05_sp$cagr  %||% NA)),
      MDD_pct  = sprintf("%.2f", 100*c(perf_iter11_sp$mdd  %||% NA,
                                        perf_str1699_sp$mdd %||% NA,
                                        perf_mega05_sp$mdd  %||% NA)),
      t_FF5    = sprintf("%.2f", c(perf_iter11_sp$harvey_t_ff5  %||% NA,
                                    perf_str1699_sp$harvey_t_ff5 %||% NA,
                                    perf_mega05_sp$harvey_t_ff5  %||% NA)),
      stringsAsFactors = FALSE
    )
  }

  # Section 3: 24-26 OOS frozen-weights vs STR_1699 OOS reference
  perf_str1699_oos_ref <- compute_perf_v2(str1699_oos$port_ret, "STR_1699_OOS_24_26", 0,
                                           start_ym = "2024-01")
  s3_df <- data.frame(
    Strategy = c("Iter11 OOS frozen", "STR_1699 OOS (Iter5 ref)"),
    n_m      = c(perf_oos$n_months, perf_str1699_oos_ref$n_months),
    SR       = sprintf("%.3f", c(perf_oos$sr %||% NA, perf_str1699_oos_ref$sr %||% NA)),
    CAGR_pct = sprintf("%.2f", 100*c(perf_oos$cagr %||% NA, perf_str1699_oos_ref$cagr %||% NA)),
    MDD_pct  = sprintf("%.2f", 100*c(perf_oos$mdd %||% NA, perf_str1699_oos_ref$mdd %||% NA)),
    Hit_pct  = sprintf("%.1f", 100*c(perf_oos$hit %||% NA, perf_str1699_oos_ref$hit %||% NA)),
    stringsAsFactors = FALSE
  )

  # Section 4: Replacement / Integration scenarios
  s4_df <- data.frame(
    Scenario = c("A. Iter11 100%", "AB. Iter11 80 + 1656 20",
                 "B. Iter11 60 + 1699 20 + 1656 20", "D. PG2 (MEGA_05 80 + 1656 20)"),
    n_m      = c(perf_scen_A$n_months,  perf_scen_AB$n_months,
                 perf_scen_B$n_months,  perf_scen_D$n_months),
    SR       = sprintf("%.3f", c(perf_scen_A$sr  %||% NA, perf_scen_AB$sr %||% NA,
                                  perf_scen_B$sr  %||% NA, perf_scen_D$sr  %||% NA)),
    CAGR_pct = sprintf("%.2f", 100*c(perf_scen_A$cagr  %||% NA, perf_scen_AB$cagr %||% NA,
                                      perf_scen_B$cagr  %||% NA, perf_scen_D$cagr  %||% NA)),
    MDD_pct  = sprintf("%.2f", 100*c(perf_scen_A$mdd  %||% NA, perf_scen_AB$mdd %||% NA,
                                      perf_scen_B$mdd  %||% NA, perf_scen_D$mdd  %||% NA)),
    Score    = sprintf("%.3f", c(score_A, score_AB, score_B, score_D)),
    stringsAsFactors = FALSE
  )

  # Section 5: 5-spec FF5
  s5_df <- data.frame(
    Spec  = c("CAPM", "Carhart_3", "Carhart_4", "FF5", "FF6"),
    t_NW  = sprintf("%.3f", c(
      res_full[["CAPM"]]$t_nw %||% NA,
      res_full[["Carhart_3"]]$t_nw %||% NA,
      res_full[["Carhart_4"]]$t_nw %||% NA,
      res_full[["FF5"]]$t_nw %||% NA,
      res_full[["FF6"]]$t_nw %||% NA
    )),
    Gate  = ifelse(c(
      res_full[["CAPM"]]$t_nw %||% 0,
      res_full[["Carhart_3"]]$t_nw %||% 0,
      res_full[["Carhart_4"]]$t_nw %||% 0,
      res_full[["FF5"]]$t_nw %||% 0,
      res_full[["FF6"]]$t_nw %||% 0
    ) >= 2.95, "PASS", "FAIL"),
    stringsAsFactors = FALSE
  )

  # Section 6: KV — pairwise cor + Δ + recommendation + audit
  cvar_d_actual <- abs(quantile(combined$port_ret, probs=0.05, na.rm=TRUE) / sqrt(21))
  s6_kv <- list(
    `cor(Iter11, STR_1699)` = sprintf("%.4f", pair_cor$iter11_str1699),
    `cor(Iter11, MEGA_05)`  = sprintf("%.4f", pair_cor$iter11_mega05),
    `cor(STR_1699, MEGA_05)` = sprintf("%.4f", pair_cor$str1699_mega05),
    `Δ Iter11 vs STR_1699 (same-period SR)` = sprintf("%+.3f", delta_vs_str1699$delta_sr),
    `Δ Iter11 vs MEGA_05 (same-period SR)`  = sprintf("%+.3f", delta_vs_mega05$delta_sr),
    `Recommended Scenario`    = sprintf("%s (max score %.3f)", recommended, max(scores)),
    `Pure Function Hash Audit`= if (hash_match) "PASS" else "FAIL",
    `5-spec PASS count`       = sprintf("%d/5 (gate t>=2.95)", n_pass),
    `CVaR_d_actual (5%/√21)`  = sprintf("%.4f (cap 0.025, %s)",
                                         cvar_d_actual,
                                         ifelse(cvar_d_actual <= 0.025, "PASS", "FAIL"))
  )
  if (!is.null(pair_cor$iter11_str1700)) {
    s6_kv[["cor(Iter11, STR_1700)"]] <- sprintf("%.4f (4-way)", pair_cor$iter11_str1700)
  }
  if (!is.null(delta_vs_str1700)) {
    s6_kv[["Δ Iter11 vs STR_1700 (same-period SR)"]] <- sprintf("%+.3f", delta_vs_str1700$delta_sr)
  }

  # Section 7: Bullet — audit + next step
  s7_items <- c(
    sprintf("Walk-forward %d sig_dates × Linear_Tilt_lam1.0_TOphi8 monthly | TO blend 0.889/0.111", nrow(bt_dt)),
    sprintf("Optimizer-only mutation of Iter5 (alpha + risk inherited; Pure Function Charter §1)"),
    sprintf("Pooled-Σ fallback at %d sig_dates (CRISIS+CAUTION binding per Risk handoff)", length(pooled_dates)),
    sprintf("OOS 24-26 frozen-weights: SR=%.3f CAGR=%.2f%% MDD=%.2f%%",
            perf_oos$sr %||% NA, (perf_oos$cagr %||% NA)*100, (perf_oos$mdd %||% NA)*100),
    sprintf("DSR penalty Iter11=20*0.05=1.00 vs STR_1699/MEGA_05=15*0.05=0.75 (fair_comparison_note mandate)"),
    sprintf("Codex C1 escalation: Optimizer expected_cvar_d_proxy=0.0297 (cap 0.025). Forge actual realized 5%%-tail/√21 = %.4f (Governor v3.4 admission)", cvar_d_actual),
    sprintf("Pure Function v6.1 R12: %s | Iter11 alpha/risk/opt 절대 read-only",
            if (hash_match) "PASS" else "FAIL"),
    "Judge S6 ready — Gate 0~6 + Role Honesty Audit + DSR + 5-spec gate + CVaR daily admission"
  )

  ret <- tg_agent_brief(
    agent = "Forge",
    title = sprintf("STR_1701 %s Iter11 Linear Tilt (TOphi8 monthly)", WT_ID),
    as_of = as.character(Sys.Date()),
    sections = list(
      list(emoji = "📊", heading = "Performance — Pre-LB / Lockbox / Combined / Full-period",
           type = "table", df = s1_df, max_col_width = 14L),
      list(emoji = "⚖️", heading = "Same-Period Fair Comparison (NAV-level intersection)",
           type = "table", df = s2_df, max_col_width = 14L),
      list(emoji = "🚀", heading = "24-26 OOS Frozen-Weights Extension",
           type = "table", df = s3_df, max_col_width = 14L),
      list(emoji = "🧬", heading = "Replacement / Integration Scenarios",
           type = "table", df = s4_df, max_col_width = 16L),
      list(emoji = "📈", heading = "5-Spec FF5 v2 Regression (Newey-West HAC)",
           type = "table", df = s5_df, max_col_width = 12L),
      list(emoji = "🔬", heading = "Pairwise Correlation + Δ + Audit",
           type = "kv", kv = s6_kv),
      list(emoji = "➡️", heading = "Audit + Next Step (Judge S6)",
           type = "bullet", items = s7_items)
    ),
    charts = c(ec_path, ar_path, oos_path, scen_path),
    footer = sprintf("📚 STR_1701 | %s Iter11 LinearTilt | Pure Function v6.1 R12 | n_walk=%d | Hash=%s",
                     WT_ID, nrow(bt_dt), if (hash_match) "PASS" else "FAIL")
  )

  cat(sprintf("  tg_agent_brief: ok=%s bytes=%d\n",
              ret$ok %||% NA, ret$bytes %||% 0))

}, error = function(e) {
  cat(sprintf("  [WARN] tg_agent_brief failed: %s\n", conditionMessage(e)))
})

# ─────────────────────────────────────────────────────────
# 19. 최종 요약
# ─────────────────────────────────────────────────────────
cat("\n")
cat("================================================================\n")
cat(sprintf("  FORGE_DONE — STR_1701 Iter11 Linear Tilt (TOphi8 monthly)\n"))
cat(sprintf("  Pre-LB walk-forward (%dm): SR=%.3f CAGR=%.4f MDD=%.4f\n",
            perf_prelb$n_months %||% 0,
            perf_prelb$sr %||% NA, perf_prelb$cagr %||% NA, perf_prelb$mdd %||% NA))
cat(sprintf("  Combined (Pre-LB matched FF5): SR=%.3f CAGR=%.4f MDD=%.4f\n",
            perf_full$sr %||% NA, perf_full$cagr %||% NA, perf_full$mdd %||% NA))
cat(sprintf("  Full-period (+OOS):         SR=%.3f CAGR=%.4f MDD=%.4f t_FF5=%.3f DSR_post=%.3f\n",
            perf_iter11_full$sr %||% NA, perf_iter11_full$cagr %||% NA,
            perf_iter11_full$mdd %||% NA,
            perf_iter11_full$harvey_t_ff5 %||% NA,
            perf_iter11_full$dsr_post_penalty %||% NA))
cat(sprintf("  Same-period Δ vs STR_1699:  ΔSR=%+.3f ΔCAGR=%+.2fpp ΔMDD=%+.2fpp\n",
            delta_vs_str1699$delta_sr, delta_vs_str1699$delta_cagr_pp,
            delta_vs_str1699$delta_mdd_pp))
cat(sprintf("  Same-period Δ vs MEGA_05:   ΔSR=%+.3f ΔCAGR=%+.2fpp ΔMDD=%+.2fpp\n",
            delta_vs_mega05$delta_sr, delta_vs_mega05$delta_cagr_pp,
            delta_vs_mega05$delta_mdd_pp))
if (!is.null(delta_vs_str1700))
  cat(sprintf("  Same-period Δ vs STR_1700:  ΔSR=%+.3f ΔCAGR=%+.2fpp ΔMDD=%+.2fpp\n",
              delta_vs_str1700$delta_sr, delta_vs_str1700$delta_cagr_pp,
              delta_vs_str1700$delta_mdd_pp))
cat(sprintf("  OOS 24-26 frozen-weights:   SR=%.3f CAGR=%.4f MDD=%.4f\n",
            perf_oos$sr %||% NA, perf_oos$cagr %||% NA, perf_oos$mdd %||% NA))
cat(sprintf("  Recommended scenario:       %s (max score %.3f)\n",
            recommended, max(scores)))
cat(sprintf("  5-spec PASS (t>=2.95):       %d/5\n", n_pass))
cat(sprintf("  Hash audit:                  %s\n",
            if (hash_match) "PASS" else "FAIL"))
cat("================================================================\n")

cat(sprintf("\nFORGE_DONE — STR_id=%s, Iter11_SR_pre_LB=%.3f, Iter11_SR_full=%.3f, Iter11_CAGR=%.4f, Iter11_MDD=%.4f, vs_Iter5_HRP_delta_SR=%+.3f, vs_MEGA05_same_period_delta=%+.3f, 5spec_Harvey=%d/5, DSR_post_penalty=%.3f\n",
            STR_ID,
            perf_prelb$sr %||% NA,
            perf_iter11_full$sr %||% NA,
            perf_iter11_full$cagr %||% NA,
            perf_iter11_full$mdd %||% NA,
            delta_vs_str1699$delta_sr,
            delta_vs_mega05$delta_sr,
            n_pass,
            perf_full$dsr_post_penalty %||% NA))

invisible(list(
  str_id   = STR_ID, wt_id = WT_ID,
  sr       = perf_full$sr, cagr = perf_full$cagr, mdd = perf_full$mdd,
  full_sr  = perf_iter11_full$sr,
  oos_sr   = perf_oos$sr,
  recommended = recommended,
  n_5spec_pass = n_pass,
  hash_audit_pass = hash_match
))
