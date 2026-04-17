cat("=== STR_1631 S5 Score Tilt Variants: V1/V2/V3/V4/V9/V10 ===\n")
## 핵심 아이디어: STR_1631 M23(Score Tilt, SR=1.118, CAGR=21.61%, MDD=29.74%)의
##   S5 변형 10건 중 구현 우선 6건 비교
##   V1: Regime-Conditional Alpha (Ang & Bekaert 2002)
##   V2: Expanding IC Confidence Alpha (Grinold & Kahn 2000)
##   V3: Rank Percentile Score (Blitz & Vliet 2007)
##   V4: Softmax Temperature Score (Garlappi et al. 2007)
##   V9: Winsorized Z-Score (Tukey 1962)
##   V10: Regime + Softmax Synthesis (V1+V4 결합)
## PIT: 모든 변형 C1+C2+C5 준수. Score_{t-1}, Regime_{t-1}.

t0 <- Sys.time()

# ═══════════════════════════════════════════════════════════════════
# 0. Environment Setup
# ═══════════════════════════════════════════════════════════════════
.root_candidates <- c(
  "/mnt/c/Users/User/OneDrive/\xeb\xb0\x94\xed\x83\x95 \xed\x99\x94\xeb\xa9\xb4/Quant_Module_Moltbot",
  "/mnt/c/Users/99922/OneDrive/\xeb\xb0\x94\xed\x83\x95 \xed\x99\x94\xeb\xa9\xb4/Quant_Module_Moltbot"
)
PROJECT_ROOT <- .root_candidates[sapply(.root_candidates, dir.exists)][1]
rm(.root_candidates)

FUNC_PATH  <- file.path(PROJECT_ROOT, "02_Infrastructure")
STRAT_DIR  <- tryCatch(dirname(sys.frame(1)$ofile), error = function(e) getwd())
OUT_DIR    <- file.path(STRAT_DIR, "output")
dir.create(OUT_DIR, showWarnings = FALSE, recursive = TRUE)

source(file.path(FUNC_PATH, "config.R"))

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(xts)
  library(zoo)
  library(PerformanceAnalytics)
  library(jsonlite)
})

options(scipen = 999)
Sys.setenv(TZ = "Asia/Seoul")

# ═══════════════════════════════════════════════════════════════════
# 1. Load Infrastructure (once)
# ═══════════════════════════════════════════════════════════════════
cat("[1] Loading infrastructure...\n")

source(file.path(INFRA_DIR, "backtest_harness.R"))
source(file.path(PORTFOLIO_DIR, "advanced_weights.R"))
source(file.path(PORTFOLIO_DIR, "shared_factor_runner.R"))
source(file.path(REGIME_DIR, "regime_engine_daily.R"))

# Rcpp weight engine (optional, speed boost)
cpp_path <- file.path(PORTFOLIO_DIR, "weight_engine.cpp")
if (file.exists(cpp_path)) {
  tryCatch(Rcpp::sourceCpp(cpp_path), error = function(e)
    cat(sprintf("[Rcpp] Skip: %s\n", conditionMessage(e))))
}

# ═══════════════════════════════════════════════════════════════════
# 2. Load RAWDATA (1회, use_cache)
# ═══════════════════════════════════════════════════════════════════
cat("[2] Loading RAWDATA (use_cache=TRUE)...\n")

res      <- load_rawdata(use_cache = TRUE)
RAWDATA  <- res$RAWDATA
BM_DT    <- res$BM_DT
rm(res)

# 분석 시작일 필터 (C1: 분석 구간만)
RAWDATA <- RAWDATA[Date >= as.Date("2004-01-01")]

cat(sprintf("[2] RAWDATA: %d rows, %s~%s\n",
            nrow(RAWDATA), min(RAWDATA$Date), max(RAWDATA$Date)))

# ═══════════════════════════════════════════════════════════════════
# 3. Load Pre-computed Factors (STR_1631 기존 factors.csv 재사용)
# ═══════════════════════════════════════════════════════════════════
cat("[3] Loading STR_1631 factors.csv...\n")

factors_path <- file.path(STRAT_DIR, "output", "factors.csv")
if (!file.exists(factors_path)) {
  stop(sprintf("[ERROR] factors.csv not found: %s\nrun_all.R를 먼저 실행하세요.", factors_path))
}
FACTORS <- fread(factors_path)
FACTORS[, Date := as.Date(Date)]

# 분석 시작일 이후만 사용
FACTORS <- FACTORS[Date >= as.Date("2004-01-01")]

cat(sprintf("[3] FACTORS: %d rows, %d signal dates\n",
            nrow(FACTORS), uniqueN(FACTORS$Date)))

# ═══════════════════════════════════════════════════════════════════
# 4. Load Regime Engine (use_cache, t-1 lagged internally)
# ═══════════════════════════════════════════════════════════════════
cat("[4] Loading Regime Engine (use_cache=TRUE)...\n")
# MRS는 build_daily_regime() 내부에서 t-1 lag 처리됨 (C5 준수)
# 추가 shift 불필요
REGIME <- tryCatch(
  build_daily_regime(use_cache = TRUE),
  error = function(e) {
    cat(sprintf("[4] Regime cache failed: %s. Rebuilding...\n", conditionMessage(e)))
    build_daily_regime(use_cache = FALSE)
  }
)
setkey(REGIME, Date)
cat(sprintf("[4] REGIME: %d rows, MRS range [%.1f, %.1f]\n",
            nrow(REGIME), min(REGIME$MRS, na.rm = TRUE), max(REGIME$MRS, na.rm = TRUE)))

# ═══════════════════════════════════════════════════════════════════
# 5. Compute Expanding IC History for V2 (ic_tilt)
# ═══════════════════════════════════════════════════════════════════
# PIT 준수: IC(t) = Spearman(Score_{t-1}, Ret_{next_month})
#            = 리밸런싱일 t에서 score는 t-1 month frozen, ret은 t→t+1 월수익률
# expanding window: k=1..t-1의 IC를 평균하여 alpha 결정
# C1(expanding window) + C2(t-1 frozen score) 준수
cat("[5] Computing expanding IC history for V2 (ic_tilt)...\n")

# 월별 수익률 계산: exec_date 기준 next month return
signal_dates <- sort(unique(FACTORS$Date))
ic_vec <- numeric(length(signal_dates))
names(ic_vec) <- as.character(signal_dates)

all_dates <- sort(unique(RAWDATA$Date))

for (i in seq_along(signal_dates)) {
  sig_dt   <- signal_dates[i]
  exec_dt  <- get_execution_date(sig_dt, all_dates)
  if (is.na(exec_dt)) { ic_vec[i] <- NA; next }

  # Next execution date
  if (i < length(signal_dates)) {
    next_exec <- get_execution_date(signal_dates[i + 1L], all_dates)
  } else {
    next_exec <- NA
  }
  if (is.na(next_exec)) { ic_vec[i] <- NA; next }

  # Stocks with score at this signal
  mf <- FACTORS[Date == sig_dt & !is.na(Score)]
  if (nrow(mf) < 5L) { ic_vec[i] <- NA; next }

  # Next-month return: exec_dt → next_exec (holding period return)
  ret_next <- RAWDATA[Ticker %in% mf$Ticker & Date > exec_dt & Date <= next_exec,
                       .(ret_hold = sum(Ret, na.rm = TRUE)), by = Ticker]
  mf_ret <- merge(mf[, .(Ticker, Score)], ret_next, by = "Ticker", all = FALSE)
  if (nrow(mf_ret) < 5L) { ic_vec[i] <- NA; next }

  # Spearman IC
  ic_val <- cor(mf_ret$Score, mf_ret$ret_hold, method = "spearman", use = "complete.obs")
  ic_vec[i] <- if (is.na(ic_val)) NA else ic_val
}

# Expanding mean IC (uses only past ICs: k=1..i-1 for signal i)
# Named by signal date for subsetting in run_monthly_simulation
ic_expanding <- setNames(
  cumsum(ifelse(is.na(ic_vec), 0, ic_vec)) /
    pmax(cumsum(!is.na(ic_vec)), 1L),
  names(ic_vec)
)

# Shift by 1: for signal i, use IC average of signals 1..i-1 (not including i itself)
ic_history_lagged <- c(NA, head(ic_expanding, -1L))
names(ic_history_lagged) <- names(ic_expanding)
# Remove NAs (first few months)
ic_history_lagged[is.na(ic_history_lagged)] <- NA

cat(sprintf("[5] IC history: %d periods, mean IC=%.4f (last 36m)\n",
            sum(!is.na(ic_history_lagged)),
            mean(tail(ic_history_lagged[!is.na(ic_history_lagged)], 36), na.rm = TRUE)))

# ═══════════════════════════════════════════════════════════════════
# 6. Define Weight Methods
# ═══════════════════════════════════════════════════════════════════
cat("[6] Defining weight methods...\n")

weight_methods_list <- list(
  # Base (M23 재현)
  list(name = "ScoreTilt_Base",  method = "score_tilt",    cov_method = "gerber_rmt"),
  # V1: Regime-Conditional Alpha
  list(name = "RegimeTilt_V1",   method = "regime_tilt",   cov_method = "gerber_rmt"),
  # V2: Expanding IC Confidence Alpha
  list(name = "ICTilt_V2",       method = "ic_tilt",       cov_method = "gerber_rmt"),
  # V3: Rank Percentile Score
  list(name = "RankTilt_V3",     method = "rank_tilt",     cov_method = "gerber_rmt"),
  # V4: Softmax Temperature (tau=1.0 fixed)
  list(name = "SoftmaxTilt_V4",  method = "softmax_tilt",  cov_method = "gerber_rmt"),
  # V9: Winsorized Z-Score (±2 sigma)
  list(name = "WinsorTilt_V9",   method = "winsor_tilt",   cov_method = "gerber_rmt"),
  # V10: Regime + Softmax Synthesis
  list(name = "RegimeSoftmax_V10", method = "regime_softmax", cov_method = "gerber_rmt")
)

cat(sprintf("[6] Methods: %s\n",
            paste(sapply(weight_methods_list, `[[`, "name"), collapse = ", ")))

# ═══════════════════════════════════════════════════════════════════
# 7. Run Comparison (sequential — 검증 우선)
# ═══════════════════════════════════════════════════════════════════
cat("[7] Running weight comparison (sequential)...\n")
cat("    Note: regime_dt passed to run_monthly_simulation for V1/V10.\n")
cat("          Regime overlay (apply_regime_overlay) NOT applied (S5 pure factor).\n\n")

results <- run_weight_comparison(
  FACTORS        = FACTORS,
  RAWDATA        = RAWDATA,
  BM_DT          = BM_DT,
  weight_methods = weight_methods_list,
  regime_dt      = REGIME,       # V1/V10: per-rebal MRS lookup
  ic_history     = ic_history_lagged,  # V2: expanding IC
  n_holdings     = 20L,
  commission     = 0.0015,
  buffer_zone    = list(keep_n = 35L, entry_n = 20L),
  output_dir     = OUT_DIR,
  run_hurdle     = FALSE,
  strategy_name  = "STR_1631_ScoreTiltVariants",
  parallel       = FALSE   # sequential: 검증 우선, 안정 확인 후 병렬
)

# ═══════════════════════════════════════════════════════════════════
# 8. Results Summary
# ═══════════════════════════════════════════════════════════════════
cat("\n══════════════════════════════════════════════════════\n")
cat("  STR_1631 Score Tilt Variants — 비교 결과\n")
cat("══════════════════════════════════════════════════════\n")

comp_dt <- results$comparison
# summarise_perf() returns "Label" column (not "Name")
if ("Name" %in% names(comp_dt) && !"Label" %in% names(comp_dt)) {
  setnames(comp_dt, "Name", "Label")
}
setorder(comp_dt, -Sharpe)

cat("\n[Base M23 Profile] SR=1.118, CAGR=21.61%, MDD=29.74%, TO=576.6%\n")
cat("\n[Variant Results]\n")
print(comp_dt[, .(Label, Sharpe, CAGR, MDD, TO, Method)])

# Base 대비 delta 계산
base_row <- comp_dt[Label == "ScoreTilt_Base"]
if (nrow(base_row) > 0) {
  comp_dt[, delta_SR   := Sharpe - base_row$Sharpe[1]]
  comp_dt[, delta_CAGR := CAGR   - base_row$CAGR[1]]
  comp_dt[, delta_MDD  := MDD    - base_row$MDD[1]]

  cat("\n[vs Base Score Tilt (delta)]\n")
  delta_view <- comp_dt[Label != "ScoreTilt_Base",
                         .(Label, delta_SR = round(delta_SR, 3),
                           delta_CAGR = round(delta_CAGR, 2),
                           delta_MDD  = round(delta_MDD, 2),
                           MDD_abs    = round(MDD, 2))]
  setorder(delta_view, delta_MDD)
  print(delta_view)
}

# Hard-fail check (TO > 600 또는 MDD > 45)
cat("\n[Hard Fail Check (TO>600% or MDD>45%)]\n")
hard_fail <- comp_dt[TO > 600 | MDD > 45]
if (nrow(hard_fail) > 0) {
  cat(sprintf("  FAIL: %s\n", paste(hard_fail$Label, collapse = ", ")))
} else {
  cat("  All variants PASS hard fail check.\n")
}

# MDD < 25% 목표 달성 여부
cat("\n[MDD < 25% Target]\n")
mdd_target <- comp_dt[MDD < 25]
if (nrow(mdd_target) > 0) {
  cat(sprintf("  ACHIEVED: %s\n",
              paste(sprintf("%s(%.1f%%)", mdd_target$Label, mdd_target$MDD), collapse = ", ")))
} else {
  best_mdd <- comp_dt[which.min(MDD)]
  cat(sprintf("  Not achieved. Best MDD: %s (%.1f%%)\n", best_mdd$Label, best_mdd$MDD))
}

# ═══════════════════════════════════════════════════════════════════
# 9. Save Results
# ═══════════════════════════════════════════════════════════════════
out_csv  <- file.path(OUT_DIR, "score_tilt_variants_comparison.csv")
out_json <- file.path(OUT_DIR, "score_tilt_variants_comparison.json")

fwrite(comp_dt, out_csv)

# JSON summary for stage_artifacts
json_summary <- list(
  run_timestamp  = format(Sys.time(), "%Y-%m-%dT%H:%M:%S"),
  parent         = "STR_1631_M23_score_tilt",
  parent_profile = list(sr = 1.118, cagr = 21.61, mdd = 29.74, to = 576.6),
  variants_tested = sapply(weight_methods_list, `[[`, "name"),
  results        = lapply(seq_len(nrow(comp_dt)), function(i) {
    row <- comp_dt[i]
    list(
      name     = row$Label,
      sr       = round(row$Sharpe, 3),
      cagr     = round(row$CAGR, 2),
      mdd      = round(row$MDD, 2),
      to       = round(row$TO, 1),
      method   = row$Method
    )
  }),
  mdd_target_25_achieved = nrow(comp_dt[MDD < 25]) > 0,
  best_mdd               = round(min(comp_dt$MDD, na.rm = TRUE), 2),
  best_sr                = round(max(comp_dt$Sharpe, na.rm = TRUE), 3)
)

writeLines(toJSON(json_summary, auto_unbox = TRUE, pretty = TRUE), out_json)

t1 <- Sys.time()
cat(sprintf("\n[완료] %.1f분 소요\n", as.numeric(difftime(t1, t0, units = "mins"))))
cat(sprintf("[출력] %s\n", out_csv))
cat(sprintf("[출력] %s\n", out_json))
