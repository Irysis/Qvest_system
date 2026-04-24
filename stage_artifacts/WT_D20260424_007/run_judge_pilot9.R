#!/usr/bin/env Rscript
# ============================================================================
# Judge — Pilot 9 WT-D20260424_007 — FF3 Attribution + Lockbox OOS
# Author: Judge (Opus 4.7)
# Core Questions:
#   Q1: "FF3 retention 94.6%" 실체 검증 — portfolio return regress on FF3
#        R² > 0.5 → Forge 해석 (style loading) | R² < 0.3 → Alpha 해석 (independent)
#   Q2: Lockbox OOS 2024-01-23 ~ 2026-01-23 — 4-regime decomposition
#   Q3: L-198 β 철학 FINAL (β=0.884 vs Pilot 8 β=1.022)
# ============================================================================

suppressPackageStartupMessages({
  library(arrow); library(data.table); library(jsonlite)
})

ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT   <- "WT_D20260424_007"
OUT  <- file.path(ROOT, "stage_artifacts", WT)
dir.create(OUT, recursive=TRUE, showWarnings=FALSE)

cat("=== Judge Pilot 9 — FF3 Attribution + Lockbox OOS ===\n")

# ── 1. Load artifacts ────────────────────────────────────────────────────────
weights <- fread(file.path(OUT, "weights.csv"))
cat("Weights:", nrow(weights), "names | sum =", round(sum(weights$weight),6), "\n")

ff3 <- as.data.table(read_parquet(file.path(ROOT, ".cache/kr_factor_returns.parquet")))
rd  <- as.data.table(read_parquet(file.path(ROOT, ".cache/rawdata.parquet")))

# ── 2. Portfolio daily returns (buy-and-hold from sig_date) ───────────────────
# sig_date = 2023-12-28 (from alpha_validation.json)
# Train:   ~ 2022-01-22
# Val:     2022-01-23 ~ 2023-12-28  (~491일 Pilot8 기준)
# Lockbox: 2024-01-23 ~ 2026-01-23  (~487일 Pilot8 기준)
SIG_DATE   <- as.Date("2023-12-28")
LOCK_START <- as.Date("2024-01-23")
LOCK_END   <- as.Date("2026-01-23")

tickers <- weights$ticker
ret_dt <- rd[Ticker %in% tickers & Date >= as.Date("2000-01-01"),
             .(Date, Ticker, Ret, BM_Ret)]
setkey(ret_dt, Date, Ticker)

# Daily portfolio return = sum(w_i * r_i) — static weights (Pilot 9 is 1-period optimizer output)
# Use ERC weights as target; simulate buy-and-hold from SIG_DATE
w_map <- setNames(weights$weight, weights$ticker)

# Full timeline (from 2000 for training backtest + lockbox)
port_daily <- ret_dt[, .(port_ret = sum(Ret * w_map[Ticker], na.rm=TRUE),
                         bm_ret   = mean(BM_Ret, na.rm=TRUE),
                         n_active = sum(!is.na(Ret))),
                     by = Date]
port_daily <- port_daily[n_active > 0]
setorder(port_daily, Date)

cat("Portfolio daily: n=", nrow(port_daily), "Date range:",
    as.character(min(port_daily$Date)), "to", as.character(max(port_daily$Date)), "\n")

# ── 3. Split into train / val / lockbox ──────────────────────────────────────
port_daily[, regime_split := fifelse(Date < as.Date("2022-01-23"), "train",
                              fifelse(Date < LOCK_START, "val",
                              fifelse(Date <= LOCK_END, "lockbox", "post")))]

# ── 4. Monthly portfolio returns for FF3 regression ──────────────────────────
port_daily[, ym := format(Date, "%Y-%m")]
port_mo <- port_daily[, .(
  port_ret_mo = prod(1 + port_ret) - 1,
  bm_ret_mo   = prod(1 + bm_ret) - 1,
  n_days      = .N
), by = .(ym, regime_split)]
port_mo[, Date := as.Date(paste0(ym, "-01"))]
port_mo[, Date_match := {
  # Match to FF3 month-end date
  as.Date(sapply(ym, function(yx) {
    ff3_dates <- ff3$Date
    ff3_ym    <- format(ff3_dates, "%Y-%m")
    mv <- ff3_dates[ff3_ym == yx]
    if (length(mv) == 0) return(NA) else return(as.character(max(mv)))
  }))
}]

merged <- merge(port_mo, ff3, by.x = "Date_match", by.y = "Date", all.x = FALSE)
cat("Matched monthly rows:", nrow(merged), "\n")

# ── 5. FF3 ATTRIBUTION — port_ret ~ MKT + SMB + HML ──────────────────────────
ff3_data <- merged[!is.na(port_ret_mo) & !is.na(MKT) & !is.na(SMB) & !is.na(HML)]
cat("FF3 regression sample: n=", nrow(ff3_data), "\n")

# Full period (train+val+lockbox)
fit_ff3_full <- lm(port_ret_mo ~ MKT + SMB + HML, data = ff3_data)
ff3_r2_full  <- summary(fit_ff3_full)$r.squared
ff3_alpha_full <- coef(fit_ff3_full)[1]
ff3_t_alpha_full <- summary(fit_ff3_full)$coefficients[1, "t value"]

# Train only
train_data <- ff3_data[regime_split == "train"]
fit_train <- tryCatch(lm(port_ret_mo ~ MKT + SMB + HML, data = train_data), error=function(e) NULL)
ff3_r2_train <- if (!is.null(fit_train)) summary(fit_train)$r.squared else NA

# Lockbox only
lock_data <- ff3_data[regime_split == "lockbox"]
fit_lock <- tryCatch(lm(port_ret_mo ~ MKT + SMB + HML, data = lock_data), error=function(e) NULL)
ff3_r2_lock <- if (!is.null(fit_lock) && nrow(lock_data) >= 5) summary(fit_lock)$r.squared else NA

# ── 6. FF5 attribution ───────────────────────────────────────────────────────
ff5_data <- merged[!is.na(port_ret_mo) & !is.na(MKT) & !is.na(SMB) & !is.na(HML) &
                   !is.na(RMW) & !is.na(CMA)]
fit_ff5 <- tryCatch(lm(port_ret_mo ~ MKT + SMB + HML + RMW + CMA, data = ff5_data),
                    error=function(e) NULL)
ff5_r2  <- if (!is.null(fit_ff5)) summary(fit_ff5)$r.squared else NA

# Carhart4
fitc4 <- tryCatch(lm(port_ret_mo ~ MKT + SMB + HML + WML, data = ff3_data[!is.na(WML)]),
                  error=function(e) NULL)
c4_r2 <- if (!is.null(fitc4)) summary(fitc4)$r.squared else NA

cat("\n── FF3 Attribution ──\n")
cat("FF3 R² (Full):    ", round(ff3_r2_full, 4), "| retention =", round(1-ff3_r2_full, 4), "\n")
cat("FF3 R² (Train):   ", round(ff3_r2_train, 4), "| retention =", round(1-ff3_r2_train, 4), "\n")
cat("FF3 R² (Lockbox): ", round(ff3_r2_lock, 4), "| retention =", round(1-ff3_r2_lock, 4), "\n")
cat("FF5 R² (Full):    ", round(ff5_r2, 4), "| retention =", round(1-ff5_r2, 4), "\n")
cat("Carhart4 R²:      ", round(c4_r2, 4), "\n")
cat("FF3 Alpha (monthly):", round(ff3_alpha_full*100, 4), "% | t =", round(ff3_t_alpha_full, 3), "\n")

# ── 7. Interpretation ────────────────────────────────────────────────────────
# If R² > 0.5 → Forge 해석 맞음 (style loading 복제)
# If R² < 0.3 → Alpha 해석 맞음 (style-independent)
interp_verdict <- fifelse(ff3_r2_full > 0.5, "FORGE_CORRECT_STYLE_LOADING",
                   fifelse(ff3_r2_full < 0.3, "ALPHA_CORRECT_STYLE_INDEPENDENT",
                                              "AMBIGUOUS_PARTIAL_STYLE"))
cat("\n=== FF3 Interpretation Verdict:", interp_verdict, "===\n")

# Alpha Agent의 "FF3 retention 94.6%" 정의 검증
# → 개별 factor IC → FF3 IC 공분산 기반 (IC-level residualization)
# → portfolio return-level 아님
# Judge 계산이 진짜 return-level FF3 attribution

# ── 8. Write FF3 attribution analysis ────────────────────────────────────────
ff3_out <- list(
  task_id = "WT-D20260424_007",
  method = "Portfolio return monthly ~ FF3/FF5/Carhart4 (return-level attribution)",
  definition_clarification = list(
    alpha_agent_definition = "IC(factor) ~ IC(SMB_proxy) + IC(HML_proxy) + IC(MOM_proxy); retention = 1 - R²",
    alpha_agent_interpretation = "IC time-series style independence — IC공분산 기반",
    judge_definition = "portfolio_return ~ MKT + SMB + HML; retention = 1 - R²",
    judge_interpretation = "Return-level style independence — 포트폴리오 실수익률 기반 (진짜 alpha quality)",
    note = "두 정의가 다른 수준을 측정. Judge 정의가 'style-independent alpha' 실체에 더 근접."
  ),
  ff3_r2 = list(
    full    = round(ff3_r2_full, 4),
    train   = round(ff3_r2_train, 4),
    lockbox = round(ff3_r2_lock, 4),
    retention_full = round(1 - ff3_r2_full, 4)
  ),
  ff5_r2 = round(ff5_r2, 4),
  carhart4_r2 = round(c4_r2, 4),
  ff3_alpha = list(
    monthly_pct = round(ff3_alpha_full * 100, 4),
    t_stat      = round(ff3_t_alpha_full, 3)
  ),
  alpha_agent_claim = 0.9462,
  judge_measured    = round(1 - ff3_r2_full, 4),
  verdict = interp_verdict,
  verdict_rationale = list(
    r2_full = ff3_r2_full,
    threshold_high = 0.5,
    threshold_low  = 0.3,
    conclusion = fifelse(ff3_r2_full > 0.5,
      "Portfolio returns are largely explained by FF3 factors. Alpha Agent's '94.6% retention' is IC-level metric, not return-level. Forge 해석이 실질적으로 맞음.",
      fifelse(ff3_r2_full < 0.3,
      "Portfolio returns show genuine style-independence. Alpha Agent 해석 (IC-level + return-level 일치) 맞음.",
      "Partial style loading — between thresholds. Val SR -0.293 fail은 style 복제 + noise mix."))
  ),
  n_monthly_obs = nrow(ff3_data),
  date_range = list(
    start = as.character(min(ff3_data$Date_match)),
    end   = as.character(max(ff3_data$Date_match))
  ),
  judge_timestamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
)
write(toJSON(ff3_out, pretty=TRUE, auto_unbox=TRUE),
      file.path(OUT, "ff3_attribution_analysis.json"))
cat("→ ff3_attribution_analysis.json written\n")

# ── 9. Lockbox OOS performance + 4-regime decomposition ──────────────────────
lock_daily <- port_daily[regime_split == "lockbox"]
cat("\n── Lockbox OOS (daily) ──\n")
cat("n_days =", nrow(lock_daily), "\n")

if (nrow(lock_daily) > 0) {
  # Full Lockbox stats
  r <- lock_daily$port_ret
  b <- lock_daily$bm_ret

  # CAGR
  n_years <- nrow(lock_daily) / 252
  port_cagr <- (prod(1+r, na.rm=TRUE))^(1/n_years) - 1
  bm_cagr   <- (prod(1+b, na.rm=TRUE))^(1/n_years) - 1

  # Sharpe (annualized, rf=0)
  port_sr <- mean(r, na.rm=TRUE) / sd(r, na.rm=TRUE) * sqrt(252)

  # MDD
  eq <- cumprod(1+replace(r, is.na(r), 0))
  mdd <- min(eq/cummax(eq) - 1, na.rm=TRUE)

  # Active (vs benchmark)
  active <- r - b
  active_ir <- mean(active, na.rm=TRUE) / sd(active, na.rm=TRUE) * sqrt(252)
  alpha_ann <- mean(active, na.rm=TRUE) * 252 * 100
  te_ann    <- sd(active, na.rm=TRUE) * sqrt(252) * 100

  cat("Port CAGR: ", round(port_cagr*100, 2), "% | BM CAGR:", round(bm_cagr*100,2), "%\n")
  cat("Port Sharpe:", round(port_sr, 3), "| MDD:", round(mdd*100, 2), "%\n")
  cat("Active IR:  ", round(active_ir, 3), "| Alpha:", round(alpha_ann, 2), "% | TE:", round(te_ann, 2), "%\n")

  # Regime decomposition — using MRS regime from rawdata context (simplified)
  # 실제 MRS state 데이터가 없으면 BM vol 기반 proxy
  bm_roll_vol <- frollapply(lock_daily$bm_ret, 21, sd, na.rm=TRUE) * sqrt(252)
  bm_roll_ret <- frollapply(lock_daily$bm_ret, 21, mean, na.rm=TRUE) * 252

  # 4-regime proxy:
  # RISK_ON: vol low + ret high
  # NEUTRAL: vol mid
  # CAUTION: vol high + ret low
  # CRISIS: vol very high
  lock_daily[, vol21 := bm_roll_vol]
  lock_daily[, ret21 := bm_roll_ret]

  # Simple quantile split
  vol_q <- quantile(lock_daily$vol21, c(0.25, 0.5, 0.75), na.rm=TRUE)
  lock_daily[, regime_proxy := fifelse(vol21 < vol_q[1] & ret21 > 0, "RISK_ON",
                              fifelse(vol21 > vol_q[3] & ret21 < 0, "CRISIS",
                              fifelse(vol21 > vol_q[2], "CAUTION", "NEUTRAL")))]

  reg_stats <- lock_daily[!is.na(regime_proxy), .(
    n_days = .N,
    sr     = mean(port_ret, na.rm=TRUE) / sd(port_ret, na.rm=TRUE) * sqrt(252),
    cagr   = (prod(1+port_ret, na.rm=TRUE))^(252/.N) - 1,
    bm_sr  = mean(bm_ret, na.rm=TRUE) / sd(bm_ret, na.rm=TRUE) * sqrt(252),
    bm_cagr= (prod(1+bm_ret, na.rm=TRUE))^(252/.N) - 1,
    active_ir = mean(port_ret - bm_ret, na.rm=TRUE) / sd(port_ret - bm_ret, na.rm=TRUE) * sqrt(252)
  ), by = regime_proxy]

  cat("\n── Lockbox 4-Regime Decomposition (proxy) ──\n")
  print(reg_stats)

  lock_out <- list(
    wt_id = "WT-D20260424_007",
    pilot_label = "Pilot 9 — ERC (beta_port=0.884, confidence-aware)",
    period = paste(as.character(LOCK_START), "~", as.character(LOCK_END)),
    n_days = nrow(lock_daily),
    total_lockbox = list(
      sr        = round(port_sr, 4),
      cagr      = round(port_cagr * 100, 2),
      mdd       = round(mdd * 100, 2),
      active_ir = round(active_ir, 4),
      alpha_ann_pct = round(alpha_ann, 2),
      te_ann_pct    = round(te_ann, 2)
    ),
    regime_decomposition = reg_stats,
    compare_pilot8 = list(
      pilot8_sr = 0.073, pilot9_sr = round(port_sr, 4),
      pilot8_active_ir = -1.942, pilot9_active_ir = round(active_ir, 4),
      pilot8_mdd = 17.91, pilot9_mdd = round(mdd * 100, 2),
      delta_active_ir = round(active_ir - (-1.942), 4),
      improvement = fifelse(active_ir > -1.942, "BETTER", "WORSE_OR_EQUAL")
    )
  )
  write(toJSON(lock_out, pretty=TRUE, auto_unbox=TRUE),
        file.path(OUT, "lockbox_oos_summary.json"))
  cat("→ lockbox_oos_summary.json written\n")

  write(toJSON(reg_stats, pretty=TRUE, auto_unbox=TRUE),
        file.path(OUT, "lockbox_regime_decomposition.json"))
  cat("→ lockbox_regime_decomposition.json written\n")
} else {
  cat("[WARN] Lockbox period has no data — check date alignment\n")
}

# ── 10. Full backtest summary ────────────────────────────────────────────────
full_daily <- port_daily[!is.na(port_ret)]
full_r <- full_daily$port_ret
n_years_full <- nrow(full_daily) / 252
full_cagr <- (prod(1+full_r, na.rm=TRUE))^(1/n_years_full) - 1
full_sr <- mean(full_r, na.rm=TRUE) / sd(full_r, na.rm=TRUE) * sqrt(252)
eq_full <- cumprod(1+replace(full_r, is.na(full_r), 0))
full_mdd <- min(eq_full/cummax(eq_full) - 1, na.rm=TRUE)

cat("\n── Full Backtest ──\n")
cat("n_days =", nrow(full_daily), "| Years:", round(n_years_full, 2), "\n")
cat("Full CAGR:", round(full_cagr*100, 2), "% | Sharpe:", round(full_sr, 3), "| MDD:", round(full_mdd*100, 2), "%\n")

# ── 11. Equity curves ────────────────────────────────────────────────────────
tryCatch({
  png(file.path(OUT, "equity_curve_full.png"), width=1200, height=600)
  plot(full_daily$Date, eq_full, type="l", lwd=2, col="navy",
       main="Pilot 9 Full Equity Curve (ERC, β=0.884)",
       xlab="Date", ylab="Cumulative Return")
  abline(v=LOCK_START, col="red", lty=2)
  legend("topleft", legend=c("Portfolio", "Lockbox Start"),
         col=c("navy","red"), lty=c(1,2), lwd=c(2,1))
  dev.off()

  if (nrow(lock_daily) > 0) {
    eq_lock <- cumprod(1+replace(lock_daily$port_ret, is.na(lock_daily$port_ret), 0))
    eq_bm   <- cumprod(1+replace(lock_daily$bm_ret,   is.na(lock_daily$bm_ret),   0))
    png(file.path(OUT, "equity_curve_oos.png"), width=1200, height=600)
    plot(lock_daily$Date, eq_lock, type="l", lwd=2, col="navy",
         main="Pilot 9 Lockbox OOS Equity (2024-01-23 ~ 2026-01-23)",
         xlab="Date", ylab="Cumulative Return",
         ylim=range(c(eq_lock, eq_bm), na.rm=TRUE))
    lines(lock_daily$Date, eq_bm, col="orange", lty=2, lwd=2)
    legend("topleft", legend=c("Portfolio (ERC)","Benchmark"),
           col=c("navy","orange"), lty=c(1,2), lwd=c(2,2))
    dev.off()
  }
  cat("→ equity_curve_full.png + equity_curve_oos.png written\n")
}, error = function(e) cat("[WARN] Plot error:", conditionMessage(e), "\n"))

# ── 12. Access log (AX-002) ──────────────────────────────────────────────────
log_out <- list(
  wt_id = "WT-D20260424_007",
  accessor = "judge",
  purpose = "Lockbox OOS + FF3 attribution (first and only access)",
  timestamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  lockbox_period = paste(as.character(LOCK_START), "~", as.character(LOCK_END)),
  n_lockbox_days = nrow(lock_daily),
  ff3_regression_n = nrow(ff3_data)
)
write(toJSON(log_out, pretty=TRUE, auto_unbox=TRUE),
      file.path(OUT, "lockbox_access_log.json"))

cat("\n=== Judge Pilot 9 analysis complete ===\n")
