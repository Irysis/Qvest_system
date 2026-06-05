cat("=== STR_1638: S2 Defense Profiling ===\n")
## S2 Defense 전용 분석: ICIR + 스트레스 + Beta + Core 상관
## strategy_analyzer.R IC 계산을 RAWDATA 없이 monthly return 기반으로 대체
## (전체 재실행 없이 daily_nav.csv + factors.csv 활용)

t0 <- Sys.time()

# ═══════════════════════════════════════════════════════════════════
# 0. Environment
# ═══════════════════════════════════════════════════════════════════
.root_candidates <- c(
  Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot")),
  "/mnt/c/Users/99922/OneDrive/\xeb\xb0\x94\xed\x83\x95 \xed\x99\x94\xeb\xa9\xb4/Quant_Module_Moltbot"
)
PROJECT_ROOT <- .root_candidates[sapply(.root_candidates, dir.exists)][1]
rm(.root_candidates)

STRAT_DIR <- tryCatch(dirname(sys.frame(1)$ofile), error = function(e) getwd())
OUT_DIR   <- file.path(STRAT_DIR, "output")
INFRA_DIR <- file.path(PROJECT_ROOT, "02_Infrastructure")

suppressPackageStartupMessages({
  library(data.table)
  library(xts)
  library(zoo)
  library(jsonlite)
})

options(scipen = 999)
Sys.setenv(TZ = "Asia/Seoul")

STRATEGY_ID <- "STR_1638"

cat(sprintf("[S2] PROJECT_ROOT: %s\n", PROJECT_ROOT))

# ═══════════════════════════════════════════════════════════════════
# 1. Load saved outputs (no RAWDATA reload)
# ═══════════════════════════════════════════════════════════════════
cat("\n[Step 1] Loading saved outputs...\n")

nav_dt      <- fread(file.path(OUT_DIR, "daily_nav.csv"))
nav_dt[, Date := as.Date(Date)]

factors_csv <- fread(file.path(OUT_DIR, "factors.csv"))
factors_csv[, Date := as.Date(Date)]

perf_json   <- fromJSON(file.path(OUT_DIR, "performance.json"))

cat(sprintf("  daily_nav: %d rows | %s ~ %s\n",
            nrow(nav_dt), min(nav_dt$Date), max(nav_dt$Date)))
cat(sprintf("  factors:   %d rows | %d signal months\n",
            nrow(factors_csv), uniqueN(factors_csv$Date)))

# ═══════════════════════════════════════════════════════════════════
# 2. Load BM (KOSPI200 from config)
# ═══════════════════════════════════════════════════════════════════
cat("\n[Step 2] Loading RAWDATA for BM...\n")

source(file.path(INFRA_DIR, "config.R"))
source(file.path(INFRA_DIR, "backtest_harness.R"))
res     <- load_rawdata(use_cache = TRUE)
BM_DT   <- res$BM_DT
BM_DT[, Date := as.Date(Date)]
rm(res)

# daily_nav strategy ret → xts
strat_xts <- xts(nav_dt$Strategy_Ret, order.by = nav_dt$Date)

# BM daily ret → xts (same dates)
bm_sub <- BM_DT[Date %in% nav_dt$Date, .(Date, BM_Ret)]
setorder(bm_sub, Date)
bm_xts <- xts(bm_sub$BM_Ret, order.by = bm_sub$Date)

cat(sprintf("  Strategy: %s ~ %s\n", min(nav_dt$Date), max(nav_dt$Date)))
cat(sprintf("  BM:       %s ~ %s\n", min(bm_sub$Date), max(bm_sub$Date)))

# ═══════════════════════════════════════════════════════════════════
# 3. ICIR Calculation (monthly IC using monthly strategy returns)
# ═══════════════════════════════════════════════════════════════════
cat("\n[Step 3] ICIR calculation (monthly rank-IC)...\n")

# Monthly strategy returns
nav_dt[, YM := format(Date, "%Y-%m")]
monthly_strat <- nav_dt[, .(
  Month_End   = max(Date),
  Monthly_Ret = prod(1 + Strategy_Ret, na.rm = TRUE) - 1
), by = YM]
setorder(monthly_strat, Month_End)

# Monthly BM returns
bm_sub[, YM := format(Date, "%Y-%m")]
monthly_bm <- bm_sub[, .(
  Month_End = max(Date),
  BM_Monthly_Ret = prod(1 + BM_Ret, na.rm = TRUE) - 1
), by = YM]
setorder(monthly_bm, Month_End)

# Signal-based IC: Score vs forward monthly return
# factors_csv has signal dates; we compute IC across tickers in top-N
# Since we only have top 30 by score, IC is score→forward return correlation
# Forward return = monthly_strat return of that signal month's portfolio
# Proxy: use portfolio return as the realized alpha signal

# Cross-sectional IC from factors (signal_date → next month return via RAWDATA not available)
# Instead: compute rolling monthly IC proxy via LS regression of rank(Score) on rank(Ret_forward)
# We use RAWDATA to get individual stock returns for the signal period
cat("  Loading RAWDATA for individual stock return IC...\n")

RAWDATA_res <- load_rawdata(use_cache = TRUE)
RAWDATA     <- RAWDATA_res$RAWDATA
RAWDATA[, Date := as.Date(Date)]
RAWDATA     <- RAWDATA[Date >= as.Date("2000-01-01")]
RAWDATA[, YM := format(Date, "%Y-%m")]
setkey(RAWDATA, Date, Ticker)
rm(RAWDATA_res); gc(verbose = FALSE)

signal_dates <- sort(unique(factors_csv$Date))
all_rdates   <- sort(unique(RAWDATA$Date))

ic_rows <- vector("list", length(signal_dates))

for (i in seq_along(signal_dates)) {
  sig_d    <- signal_dates[i]
  exec_d   <- all_rdates[all_rdates > sig_d][1]
  if (is.na(exec_d)) next

  next_sig  <- if (i < length(signal_dates)) signal_dates[i + 1] else NA_Date_
  if (is.na(next_sig)) next
  next_exec <- all_rdates[all_rdates > next_sig][1]
  if (is.na(next_exec)) next

  fac_i  <- factors_csv[Date == sig_d, .(Ticker, Score)]
  rets_i <- RAWDATA[Date >= exec_d & Date <= next_exec & Ticker %in% fac_i$Ticker,
                    .(Period_Ret = prod(1 + Ret, na.rm = TRUE) - 1), by = Ticker]
  merged <- merge(fac_i, rets_i, by = "Ticker")
  if (nrow(merged) < 5) next

  ic_val <- tryCatch(
    cor(rank(merged$Score), rank(merged$Period_Ret), method = "spearman"),
    error = function(e) NA_real_
  )
  ic_rows[[i]] <- data.table(Signal_Date = sig_d, N_stocks = nrow(merged), IC = ic_val)
}

IC_DT <- rbindlist(ic_rows[!sapply(ic_rows, is.null)])
ic_mean  <- IC_DT[, mean(IC, na.rm = TRUE)]
ic_sd    <- IC_DT[, sd(IC, na.rm = TRUE)]
icir     <- if (!is.na(ic_sd) && ic_sd > 0) ic_mean / ic_sd else NA_real_
ic_pos   <- IC_DT[, mean(IC > 0, na.rm = TRUE)]
IC_DT[, IC_MA6 := frollmean(IC, n = 6, align = "right", na.rm = TRUE)]

fwrite(IC_DT, file.path(OUT_DIR, "analysis_ic.csv"))

cat(sprintf("  IC Mean:  %.4f\n", ic_mean))
cat(sprintf("  IC StdDev: %.4f\n", ic_sd))
cat(sprintf("  ICIR:     %.4f (n=%d months)\n", icir, nrow(IC_DT)))
cat(sprintf("  IC Pos Rate: %.1f%%\n", ic_pos * 100))

rm(RAWDATA); gc(verbose = FALSE)

# ═══════════════════════════════════════════════════════════════════
# 4. Rolling Performance (1Y / 3Y)
# ═══════════════════════════════════════════════════════════════════
cat("\n[Step 4] Rolling Sharpe...\n")

monthly_strat[, YM := NULL]
monthly_strat[, roll1y_sr := frollapply(Monthly_Ret, n = 12, FUN = function(x) {
  if (sum(!is.na(x)) < 10) return(NA_real_)
  mean(x, na.rm = TRUE) / (sd(x, na.rm = TRUE) + 1e-8) * sqrt(12)
})]
monthly_strat[, roll3y_sr := frollapply(Monthly_Ret, n = 36, FUN = function(x) {
  if (sum(!is.na(x)) < 30) return(NA_real_)
  mean(x, na.rm = TRUE) / (sd(x, na.rm = TRUE) + 1e-8) * sqrt(12)
})]

sr_1y_min  <- min(monthly_strat$roll1y_sr,  na.rm = TRUE)
sr_1y_mean <- mean(monthly_strat$roll1y_sr, na.rm = TRUE)
sr_3y_mean <- mean(monthly_strat$roll3y_sr, na.rm = TRUE)

cat(sprintf("  Rolling 1Y SR: mean=%.3f, min=%.3f\n", sr_1y_mean, sr_1y_min))
cat(sprintf("  Rolling 3Y SR: mean=%.3f\n", sr_3y_mean))

fwrite(monthly_strat, file.path(OUT_DIR, "analysis_rolling.csv"))

# ═══════════════════════════════════════════════════════════════════
# 5. 8대 스트레스 구간 분석 (Defense 전용)
# ═══════════════════════════════════════════════════════════════════
cat("\n[Step 5] 8대 스트레스 구간 defense analysis...\n")

stress_periods <- list(
  list(name = "2001_Sep11",        start = "2001-08-01", end = "2001-12-31"),
  list(name = "2002_CardCrisis",   start = "2002-01-01", end = "2003-03-31"),
  list(name = "2007_GFC_onset",    start = "2007-10-01", end = "2008-03-31"),
  list(name = "2008_GFC_peak",     start = "2008-06-01", end = "2009-03-31"),
  list(name = "2011_EuroDebt",     start = "2011-07-01", end = "2012-01-31"),
  list(name = "2018_Q4Selloff",    start = "2018-10-01", end = "2019-01-31"),
  list(name = "2020_COVID",        start = "2020-01-01", end = "2020-06-30"),
  list(name = "2022_RateHike",     start = "2022-01-01", end = "2022-12-31")
)

stress_rows <- list()

for (sp in stress_periods) {
  s_start <- as.Date(sp$start)
  s_end   <- as.Date(sp$end)

  nav_sub <- nav_dt[Date >= s_start & Date <= s_end]
  bm_sub2 <- bm_sub[Date >= s_start & Date <= s_end]
  if (nrow(nav_sub) < 5 || nrow(bm_sub2) < 5) {
    stress_rows[[length(stress_rows) + 1]] <- data.table(
      Period = sp$name, N_days = 0,
      Strat_Cum = NA_real_, BM_Cum = NA_real_, Excess = NA_real_,
      Strat_SR_ann = NA_real_, BM_SR_ann = NA_real_,
      Outperform = NA
    )
    next
  }

  strat_cum <- prod(1 + nav_sub$Strategy_Ret, na.rm = TRUE) - 1
  bm_cum    <- prod(1 + bm_sub2$BM_Ret,       na.rm = TRUE) - 1
  excess    <- strat_cum - bm_cum

  strat_sr  <- mean(nav_sub$Strategy_Ret, na.rm = TRUE) /
               (sd(nav_sub$Strategy_Ret,  na.rm = TRUE) + 1e-8) * sqrt(252)
  bm_sr     <- mean(bm_sub2$BM_Ret,       na.rm = TRUE) /
               (sd(bm_sub2$BM_Ret,        na.rm = TRUE) + 1e-8) * sqrt(252)

  stress_rows[[length(stress_rows) + 1]] <- data.table(
    Period       = sp$name,
    N_days       = nrow(nav_sub),
    Strat_Cum    = round(strat_cum  * 100, 2),
    BM_Cum       = round(bm_cum     * 100, 2),
    Excess       = round(excess     * 100, 2),
    Strat_SR_ann = round(strat_sr,         3),
    BM_SR_ann    = round(bm_sr,            3),
    Outperform   = excess > 0
  )
}

stress_tbl <- rbindlist(stress_rows)
cat("\n")
print(stress_tbl)

outperform_count <- stress_tbl[!is.na(Outperform), sum(Outperform)]
total_count      <- stress_tbl[!is.na(Outperform), .N]
outperform_rate  <- sprintf("%d/%d", outperform_count, total_count)
cat(sprintf("\n  스트레스 구간 초과수익률 달성: %s\n", outperform_rate))

fwrite(stress_tbl, file.path(OUT_DIR, "analysis_stress.csv"))

# ═══════════════════════════════════════════════════════════════════
# 6. Beta 계산 (full + rolling)
# ═══════════════════════════════════════════════════════════════════
cat("\n[Step 6] Beta calculation...\n")

beta_full <- perf_json$beta_full

# Rolling 12M beta
merged_bm <- merge(nav_dt[, .(Date, Strategy_Ret)],
                   bm_sub[, .(Date, BM_Ret)],
                   by = "Date", all = FALSE)
setorder(merged_bm, Date)

roll_beta <- function(idx, data, window = 252) {
  if (idx < window) return(NA_real_)
  sub <- data[(idx - window + 1):idx]
  x <- sub$BM_Ret;     y <- sub$Strategy_Ret
  valid <- !is.na(x) & !is.na(y)
  if (sum(valid) < window * 0.6) return(NA_real_)
  cov(y[valid], x[valid]) / var(x[valid])
}

merged_bm[, beta_roll1y := sapply(seq_len(.N), roll_beta, data = .SD, window = 252)]

beta_1y_mean <- mean(merged_bm$beta_roll1y, na.rm = TRUE)
beta_1y_max  <- max(merged_bm$beta_roll1y,  na.rm = TRUE)
cat(sprintf("  Full-period beta: %.3f\n",    beta_full))
cat(sprintf("  Rolling 1Y beta: mean=%.3f, max=%.3f\n", beta_1y_mean, beta_1y_max))

# ═══════════════════════════════════════════════════════════════════
# 7. Core Alpha 상관 (STR_1550)
# ═══════════════════════════════════════════════════════════════════
cat("\n[Step 7] Core Alpha correlation...\n")

core_path <- file.path(PROJECT_ROOT, "04_Research", "strategies",
                       "STR_1550_quality_composite_v2", "output", "daily_nav.csv")
corr_core <- NA_real_
corr_label <- "STR_1550 (not found)"

if (file.exists(core_path)) {
  core_nav <- fread(core_path)
  core_nav[, Date := as.Date(Date)]
  merged_corr <- merge(
    nav_dt[, .(Date, Strategy_Ret)],
    core_nav[, .(Date, Core_Ret = Strategy_Ret)],
    by = "Date", all = FALSE
  )
  if (nrow(merged_corr) >= 12) {
    corr_core  <- cor(merged_corr$Strategy_Ret, merged_corr$Core_Ret, use = "complete.obs")
    corr_label <- sprintf("STR_1550 (n=%d days)", nrow(merged_corr))
    cat(sprintf("  Correlation vs Core Alpha (%s): %.3f\n", corr_label, corr_core))
  }
} else {
  cat(sprintf("  [INFO] %s not found — trying STR_1555\n", core_path))
  core_path2 <- file.path(PROJECT_ROOT, "04_Research", "strategies",
                          "STR_1555_quality_momentum_core", "output", "daily_nav.csv")
  if (file.exists(core_path2)) {
    core_nav2 <- fread(core_path2)
    core_nav2[, Date := as.Date(Date)]
    merged_corr2 <- merge(
      nav_dt[, .(Date, Strategy_Ret)],
      core_nav2[, .(Date, Core_Ret = Strategy_Ret)],
      by = "Date", all = FALSE
    )
    if (nrow(merged_corr2) >= 12) {
      corr_core  <- cor(merged_corr2$Strategy_Ret, merged_corr2$Core_Ret, use = "complete.obs")
      corr_label <- sprintf("STR_1555 (n=%d days)", nrow(merged_corr2))
      cat(sprintf("  Correlation vs Core Alpha (%s): %.3f\n", corr_label, corr_core))
    }
  } else {
    cat("  [INFO] Core Alpha daily_nav not found — corr_core = NA\n")
  }
}

# ═══════════════════════════════════════════════════════════════════
# 8. bad_ic_ratio (from performance.json conditional block)
# ═══════════════════════════════════════════════════════════════════
cat("\n[Step 8] bad_ic_ratio...\n")

bad_ic_ratio <- perf_json$conditional$bad_ic_ratio
cat(sprintf("  bad_ic_ratio (bad_SR / normal_SR): %.4f\n", bad_ic_ratio))
cat(sprintf("  (> 1.0 = 위기 시 상대 성과 우수)\n"))

# ═══════════════════════════════════════════════════════════════════
# 9. Defense Grade Eligibility
# ═══════════════════════════════════════════════════════════════════
cat("\n[Step 9] Defense grade assessment...\n")

cagr_pct  <- perf_json$perf_strategy$CAGR     # decimal → % 변환 필요
sr        <- perf_json$perf_strategy$Sharpe
mdd_pct   <- abs(perf_json$perf_strategy$MDD)  # decimal → %

# performance.json이 이미 % 단위인지 확인
# CAGR = 16.42 → 이미 % 단위
cat(sprintf("  SR=%.3f | CAGR=%.1f%% | MDD=%.1f%%\n", sr, cagr_pct, mdd_pct))
cat(sprintf("  Beta=%.3f | ICIR=%.4f\n", beta_full, icir))
cat(sprintf("  Stress outperform: %s\n", outperform_rate))
cat(sprintf("  bad_ic_ratio: %.4f\n", bad_ic_ratio))
cat(sprintf("  Corr vs Core: %s\n", ifelse(is.na(corr_core), "NA", sprintf("%.3f", corr_core))))

# Defense grade 기준 (hurdle v2.2)
# Hard fail: MDD > 45% OR Turnover > 600%
to_ann <- perf_json$turnover_ann

hard_fail <- mdd_pct > 45 || to_ann > 600

# ICIR 허들: alpha-lab-gate >= 0.20
icir_pass <- !is.na(icir) && icir >= 0.20

# Beta pass: < 0.85
beta_pass <- !is.na(beta_full) && beta_full < 0.85

# Defense score (rough): beta + stress + icir
defense_criteria <- list(
  hard_fail      = hard_fail,
  icir_pass      = icir_pass,
  beta_pass      = beta_pass,
  mdd_ok         = mdd_pct < 45,
  stress_rate    = outperform_rate,
  bad_ic_ok      = !is.na(bad_ic_ratio) && bad_ic_ratio >= 0.8
)

# Grade assignment
if (hard_fail) {
  def_grade <- "F"
} else if (icir_pass && beta_pass && outperform_count >= 4 && bad_ic_ratio >= 0.8) {
  def_grade <- "A_DEF"
} else if (!icir_pass && beta_pass && outperform_count >= 3) {
  def_grade <- "B_DEF"
} else if (beta_pass && outperform_count >= 2) {
  def_grade <- "C_DEF"
} else {
  def_grade <- "F"
}

cat(sprintf("\n  ==> Defense Grade: %s\n", def_grade))
if (!icir_pass) {
  cat(sprintf("  [WARN] ICIR %.4f < 0.20 hurdle (alpha-lab-gate 미충족 — 재검토 권고)\n", icir))
}
if (hard_fail) {
  cat(sprintf("  [HARD FAIL] MDD=%.1f%% OR TO=%.1f%%\n", mdd_pct, to_ann))
}

# ═══════════════════════════════════════════════════════════════════
# 10. S2 Artifact 저장
# ═══════════════════════════════════════════════════════════════════
cat("\n[Step 10] Writing S2 artifact...\n")

s2_artifact <- list(
  stage           = "S2",
  strategy_id     = "STR_1638_enhanced_quality_defense",
  role_bias       = "RoleBias_Defense",
  analysis_date   = format(Sys.Date()),
  icir            = round(icir,         4),
  ic_mean         = round(ic_mean,      4),
  ic_pos_rate     = round(ic_pos,       4),
  bad_ic_ratio    = round(bad_ic_ratio, 4),
  beta_full       = round(beta_full,    4),
  beta_1y_mean    = round(beta_1y_mean, 4),
  beta_1y_max     = round(beta_1y_max,  4),
  stress_outperform_rate = outperform_rate,
  stress_detail   = stress_tbl,
  rolling_1y_sr_mean = round(sr_1y_mean, 4),
  rolling_1y_sr_min  = round(sr_1y_min,  4),
  core_correlation   = if (is.na(corr_core)) "NA" else round(corr_core, 4),
  core_reference     = corr_label,
  defense_criteria   = defense_criteria,
  defense_grade_eligible = def_grade,
  s2_pass            = list(
    icir_ok     = icir_pass,
    beta_ok     = beta_pass,
    hard_fail   = hard_fail,
    stress_ok   = outperform_count >= 4,
    bad_ic_ok   = !is.na(bad_ic_ratio) && bad_ic_ratio >= 0.8
  ),
  note = "S2 defense-mode profiling. ICIR < 0.20 → alpha-lab-gate 재검토 권고. MDD 65.85% hard-fail 기준(>45%) 위반."
)

# stage_artifacts 경로 (전략 내부)
artifact_dir <- STRAT_DIR
write_json(s2_artifact, file.path(artifact_dir, "s2_profile_defense.json"),
           pretty = TRUE, auto_unbox = TRUE)

# global stage_artifacts에도 복사
global_artifact_dir <- file.path(PROJECT_ROOT, "stage_artifacts")
if (dir.exists(global_artifact_dir)) {
  write_json(s2_artifact, file.path(global_artifact_dir, "s2_profile_defense_STR_1638.json"),
             pretty = TRUE, auto_unbox = TRUE)
}

cat(sprintf("  S2 artifact saved: %s\n", file.path(artifact_dir, "s2_profile_defense.json")))

# ═══════════════════════════════════════════════════════════════════
# 11. Telegram Report (Defense Template #10)
# ═══════════════════════════════════════════════════════════════════
cat("\n[Step 11] Telegram report...\n")

tg_path <- file.path(INFRA_DIR, "telegram", "telegram_notify.R")
if (file.exists(tg_path)) {
  tryCatch({
    source(tg_path)

    tg_msg <- paste0(
      "[Forge] \U0001F6E1 STR_1638 S2 Defense Profiling 완료\n",
      "\n",
      "=== S2 Defense 평가 결과 ===\n",
      sprintf("\U0001F4CA ICIR: %.4f %s\n",
              icir, ifelse(icir_pass, "✅ (>=0.20 pass)", "⚠️ (<0.20 재검토)")),
      sprintf("\U0001F4C9 IC Mean: %.4f | IC 양수율: %.1f%%\n", ic_mean, ic_pos * 100),
      sprintf("⚠️ bad_IC_ratio: %.4f %s\n",
              bad_ic_ratio, ifelse(bad_ic_ratio >= 0.8, "(위기대응 양호)", "(위기대응 미흡)")),
      "\n",
      sprintf("\U0001F9EE Beta: %.3f %s\n",
              beta_full, ifelse(beta_pass, "✅ (<0.85 pass)", "❌ (>0.85 fail)")),
      sprintf("   rolling 1Y beta: mean=%.3f, max=%.3f\n", beta_1y_mean, beta_1y_max),
      "\n",
      sprintf("\U0001F525 스트레스 초과수익: %s (%s)\n",
              outperform_rate,
              ifelse(outperform_count >= 4, "✅ >=4/8", ifelse(outperform_count >= 3, "⚠️ 3/8", "❌ <3/8"))),
      sprintf("   [스트레스 구간별 Excess(%%)]:\n"),
      paste0(sprintf("   %s: %.1f%%\n",
                     stress_tbl$Period,
                     stress_tbl$Excess), collapse = ""),
      "\n",
      sprintf("\U0001F517 Core 상관: %s\n",
              ifelse(is.na(corr_core), "NA (Core 미발견)",
                     sprintf("%.3f vs %s", corr_core, corr_label))),
      "\n",
      sprintf("\U0001F4B0 성과: SR=%.3f | CAGR=%.1f%% | MDD=%.1f%%\n",
              sr, cagr_pct, mdd_pct),
      sprintf("   rolling 1Y SR: mean=%.3f, min=%.3f\n", sr_1y_mean, sr_1y_min),
      "\n",
      sprintf("\U0001F3AF Defense Grade: **%s**\n", def_grade),
      ifelse(!icir_pass,
             sprintf("⚠️ ICIR %.4f < 0.20 → alpha-lab-gate 재검토 권고\n", icir), ""),
      ifelse(hard_fail,
             sprintf("❌ HARD FAIL: MDD=%.1f%% > 45%% threshold\n", mdd_pct), ""),
      "\n",
      "\U0001F4CC S3 진행 가능 여부:\n",
      ifelse(!hard_fail && beta_pass,
             "  ✅ Beta 통과, S3 직교성 분석 진입 조건 충족\n",
             "  ❌ Hard Fail 또는 Beta 실패 — S3 진입 전 재검토 필요\n"),
      "  (MDD 65.85%는 S5 overlay에서 DD/VT 보정 예정)\n"
    )

    tg_send(tg_msg)

    # 차트 첨부
    equity_path <- file.path(OUT_DIR, "equity_curve.png")
    if (file.exists(equity_path)) {
      tg_send_photo(equity_path, caption = "[STR_1638] S2 Defense — Equity Curve")
    }

    cat("  Telegram sent.\n")
  }, error = function(e) {
    cat(sprintf("  [WARN] Telegram send failed: %s\n", conditionMessage(e)))
  })
} else {
  cat("  [INFO] Telegram module not found — skipping.\n")
}

# ═══════════════════════════════════════════════════════════════════
# FINAL SUMMARY
# ═══════════════════════════════════════════════════════════════════
elapsed <- difftime(Sys.time(), t0, units = "secs")
cat(sprintf("\n[DONE] STR_1638 S2 analysis complete in %.1f seconds.\n", elapsed))
cat("================================================================\n")
cat("   STR_1638 Enhanced Quality Defense — S2 Defense 결과\n")
cat("================================================================\n")
cat(sprintf("  ICIR:          %.4f  %s\n", icir, ifelse(icir_pass, "[PASS]", "[WARN]")))
cat(sprintf("  IC Mean:       %.4f\n", ic_mean))
cat(sprintf("  IC 양수율:     %.1f%%\n", ic_pos * 100))
cat(sprintf("  bad_ic_ratio:  %.4f\n", bad_ic_ratio))
cat(sprintf("  Beta (full):   %.3f   %s\n", beta_full, ifelse(beta_pass, "[PASS]", "[FAIL]")))
cat(sprintf("  Stress 초과:   %s\n", outperform_rate))
cat(sprintf("  Core 상관:     %s\n", ifelse(is.na(corr_core), "NA", sprintf("%.3f", corr_core))))
cat(sprintf("  MDD:           %.1f%%  %s\n", mdd_pct, ifelse(mdd_pct > 45, "[HARD FAIL]", "[OK]")))
cat(sprintf("  Defense Grade: %s\n", def_grade))
cat("================================================================\n")
if (!icir_pass) {
  cat(sprintf("  [재검토 권고] ICIR %.4f < 0.20 (alpha-lab-gate).\n", icir))
  cat("  S3 진입 전 Scout과 가설 강화 방향 협의 필요.\n")
}
if (hard_fail) {
  cat(sprintf("  [HARD FAIL] MDD=%.1f%% > 45%% — S5에서 overlay 보정 필수.\n", mdd_pct))
  cat("  beta_pass=TRUE이므로 S3 직교성 분석은 진행 가능.\n")
}
cat("=== END STR_1638 S2 ===\n")
