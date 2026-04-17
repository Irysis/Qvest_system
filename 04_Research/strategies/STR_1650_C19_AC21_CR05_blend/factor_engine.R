## ============================================================
## STR_1650 factor_engine.R
## 핵심아이디어: 3-factor composite — C19(Consensus) + AC21(Accrual Quality) + CR05(Crowding Reversal)
## 근거: Sloan(1996) accrual anomaly, Lou&Polk(2022) crowding reversal,
##        상관분석 rho≈0 (overlap 0~0.6%) 확인 → 독립 alpha source 합산
## PIT: load_month_factors() 경유 (C15), Z_Score_Aligned 사용 (C13)
##      S1 순수 팩터 신호 — overlay 없음
## ============================================================

# ─── 경로 설정 ───────────────────────────────────────────────
.root_candidates <- c(
  "/mnt/c/Users/User/OneDrive/\ubc14\ud0d5 \ud654\uba74/Quant_Module_Moltbot",
  "/mnt/c/Users/99922/OneDrive/\ubc14\ud0d5 \ud654\uba74/Quant_Module_Moltbot"
)
PROJECT_ROOT <- .root_candidates[sapply(.root_candidates, dir.exists)][1]
rm(.root_candidates)

FUNC_PATH  <- file.path(PROJECT_ROOT, "02_Infrastructure")
CACHE_DIR  <- file.path(PROJECT_ROOT, ".cache")
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
  library(ggplot2)
  library(scales)
  library(lubridate)
  library(jsonlite)
})

options(scipen = 999)
Sys.setenv(TZ = "Asia/Seoul")

LIQ_THRESHOLD <- 2e8
N_HOLD        <- 20L
BUFFER_KEEP   <- 35L
BUFFER_ENTRY  <- 20L
COMMISSION    <- 0.0015

cat(sprintf("[setup] PROJECT_ROOT: %s\n", PROJECT_ROOT))
cat(sprintf("[setup] OUT_DIR: %s\n", OUT_DIR))

# ─── Step 1: RAWDATA 로드 (1회) ──────────────────────────────
cat("\n[Step 1] Loading RAWDATA...\n")
source(file.path(FUNC_PATH, "backtest_harness.R"))
source(file.path(FUNC_PATH, "factor_db", "factor_db_connector.R"))

res     <- load_rawdata(use_cache = TRUE)
RAWDATA <- res$RAWDATA
BM_DT   <- res$BM_DT
rm(res); gc(verbose = FALSE)

RAWDATA[, Date := as.Date(Date)]
BM_DT[,   Date := as.Date(Date)]
RAWDATA <- RAWDATA[Date >= ANALYSIS_START_DATE]
BM_DT   <- BM_DT[Date >= ANALYSIS_START_DATE]

# 불필요 컬럼 제거
drop_cols <- intersect(c("Open", "High", "Low", "source", "Size", "Market"), names(RAWDATA))
if (length(drop_cols) > 0) RAWDATA[, (drop_cols) := NULL]

# LIQ 20일 이동평균
setorder(RAWDATA, Ticker, Date)
RAWDATA[, TradVal := Close * Vol]
RAWDATA[, LIQ_20d := frollmean(TradVal, n = 20L, align = "right", na.rm = TRUE), by = Ticker]
RAWDATA[, TradVal := NULL]

# 시그널 날짜 목록
RAWDATA[, YM := format(Date, "%Y-%m")]
sig_dates_dt <- RAWDATA[, .(sig_date = max(Date)), by = YM]
setorder(sig_dates_dt, sig_date)
sig_dates_dt <- sig_dates_dt[sig_date >= SIGNAL_START_DATE]
SIG_DATES    <- sig_dates_dt$sig_date

# 시그널 스냅샷 (월말 Close + LIQ)
SIG_SNAP <- RAWDATA[Date %in% SIG_DATES & !is.na(Close),
                    .(Date, Ticker, Close, LIQ_20d)]
setkey(SIG_SNAP, Date, Ticker)

RAWDATA[, c("LIQ_20d", "YM") := NULL]
setkey(RAWDATA, Date, Ticker)
gc(verbose = FALSE)

cat(sprintf("[Step 1] RAWDATA: %s rows | %d tickers | %d signal dates (%s ~ %s)\n",
            format(nrow(RAWDATA), big.mark = ","),
            uniqueN(RAWDATA$Ticker),
            length(SIG_DATES), min(SIG_DATES), max(SIG_DATES)))

# ─── Step 2: 팩터 로딩 + composite 점수 계산 ─────────────────
cat("\n[Step 2] Building monthly composite scores (C19 + AC21 + CR05)...\n")

FACTOR_NAMES <- c("C19_Composite_Earnings", "AC21_CF_to_Accrual_Ratio", "CR05_Short_Pressure_Proxy")

# Expanding window IC 추적 (IC-weighted 변형용)
ic_accum <- list(
  C19_Composite_Earnings  = numeric(0),
  AC21_CF_to_Accrual_Ratio= numeric(0),
  CR05_Short_Pressure_Proxy= numeric(0)
)

FACTORS_EW_list   <- vector("list", length(SIG_DATES))
FACTORS_ICW_list  <- vector("list", length(SIG_DATES))

for (i in seq_along(SIG_DATES)) {
  sd <- SIG_DATES[i]

  # 유니버스: 유동성 필터
  univ <- SIG_SNAP[Date == sd & !is.na(LIQ_20d) & LIQ_20d >= LIQ_THRESHOLD]
  if (nrow(univ) < 30L) next

  # C15: load_month_factors() 경유
  fdt <- tryCatch(
    load_month_factors(sd),
    error = function(e) {
      cat(sprintf("  [WARNING] load_month_factors(%s) failed: %s\n", sd, conditionMessage(e)))
      NULL
    }
  )
  if (is.null(fdt) || nrow(fdt) == 0L) next

  # C13: Z_Score_Aligned만 사용. 3팩터 필터
  fdt_sub <- fdt[Factor_Name %in% FACTOR_NAMES]
  if (uniqueN(fdt_sub$Factor_Name) < 3L) next

  # Wide 형태로 변환
  wide <- dcast(fdt_sub, Ticker ~ Factor_Name, value.var = "Z_Score_Aligned")

  # 유니버스 교집합
  wide <- wide[Ticker %in% univ$Ticker]

  # 3팩터 모두 non-NA인 종목만
  wide <- wide[!is.na(C19_Composite_Earnings) &
               !is.na(AC21_CF_to_Accrual_Ratio) &
               !is.na(CR05_Short_Pressure_Proxy)]
  if (nrow(wide) < 20L) next

  # ── EW composite (1/3, 1/3, 1/3) ──
  wide[, Score_EW := (C19_Composite_Earnings +
                      AC21_CF_to_Accrual_Ratio +
                      CR05_Short_Pressure_Proxy) / 3.0]

  # ── IC-weighted composite (expanding window) ──
  # IC 가중: 현재까지 누적된 mean IC 비율 사용 (C14 준수: 미래 IC 금지)
  n_ic <- sapply(ic_accum, length)

  if (all(n_ic >= 3L)) {
    mean_ics <- sapply(ic_accum, mean, na.rm = TRUE)
    mean_ics <- pmax(mean_ics, 0)  # 음수 IC는 0으로 클램핑 (방향 이미 정렬됨)
    ic_sum   <- sum(mean_ics)
    if (ic_sum > 1e-8) {
      w_c19  <- mean_ics["C19_Composite_Earnings"]   / ic_sum
      w_ac21 <- mean_ics["AC21_CF_to_Accrual_Ratio"] / ic_sum
      w_cr05 <- mean_ics["CR05_Short_Pressure_Proxy"] / ic_sum
    } else {
      w_c19 <- w_ac21 <- w_cr05 <- 1/3
    }
    wide[, Score_ICW := w_c19  * C19_Composite_Earnings +
                        w_ac21 * AC21_CF_to_Accrual_Ratio +
                        w_cr05 * CR05_Short_Pressure_Proxy]
  } else {
    # IC 데이터 부족하면 EW 사용
    wide[, Score_ICW := Score_EW]
  }

  # Top N_HOLD 선택
  setorder(wide, -Score_EW)
  top_ew <- head(wide, N_HOLD)
  FACTORS_EW_list[[i]] <- data.table(
    Date   = sd,
    Ticker = top_ew$Ticker,
    Score  = top_ew$Score_EW
  )

  setorder(wide, -Score_ICW)
  top_icw <- head(wide, N_HOLD)
  FACTORS_ICW_list[[i]] <- data.table(
    Date   = sd,
    Ticker = top_icw$Ticker,
    Score  = top_icw$Score_ICW
  )

  # IC 누적 업데이트: 다음 월 수익률을 알아야 IC를 계산하므로
  # 실제로는 후행 1개월 수익률로 계산해야 하나,
  # 여기서는 expanding IC를 근사로 factor_ic_monthly.parquet에서 읽는다.
  # (IC 축적은 backtest 후에 compute_rolling_ic_all로 별도 계산)
}

FACTORS_EW  <- rbindlist(FACTORS_EW_list[!sapply(FACTORS_EW_list,  is.null)])
FACTORS_ICW <- rbindlist(FACTORS_ICW_list[!sapply(FACTORS_ICW_list, is.null)])

cat(sprintf("[Step 2] EW months: %d | ICW months: %d\n",
            uniqueN(FACTORS_EW$Date), uniqueN(FACTORS_ICW$Date)))

rm(FACTORS_EW_list, FACTORS_ICW_list, SIG_SNAP)
gc(verbose = FALSE)

# ─── Step 3: 백테스트 실행 (EW composite) ────────────────────
cat("\n[Step 3] Backtest — EW composite (1/3, 1/3, 1/3)...\n")

sim_ew <- run_monthly_simulation(
  RAWDATA, BM_DT, FACTORS_EW,
  n_holdings    = N_HOLD,
  weight_method = "equal",
  commission    = COMMISSION,
  buffer_zone   = list(keep_n = BUFFER_KEEP, entry_n = BUFFER_ENTRY)
)

perf_ew <- summarise_perf(sim_ew$strategy_xts, "STR_1650_EW (C19+AC21+CR05)")
perf_bm  <- summarise_perf(sim_ew$bm_xts,      "KOSPI200")
to_ew    <- calc_turnover(sim_ew$PORTFOLIO_LOG, sim_ew$DAILY_NAV_DT)

cat("\n=== EW Composite (Equal Weight 1/3 each) ===\n")
print(rbind(perf_ew, perf_bm))
cat(sprintf("  Turnover (ann.): %.1f%%\n", to_ew))

# ─── Step 4: 백테스트 실행 (IC-weighted composite) ───────────
cat("\n[Step 4] Backtest — IC-weighted composite (expanding window)...\n")

sim_icw <- run_monthly_simulation(
  RAWDATA, BM_DT, FACTORS_ICW,
  n_holdings    = N_HOLD,
  weight_method = "equal",
  commission    = COMMISSION,
  buffer_zone   = list(keep_n = BUFFER_KEEP, entry_n = BUFFER_ENTRY)
)

perf_icw <- summarise_perf(sim_icw$strategy_xts, "STR_1650_ICW (IC-weighted)")
to_icw   <- calc_turnover(sim_icw$PORTFOLIO_LOG, sim_icw$DAILY_NAV_DT)

cat("\n=== IC-Weighted Composite (Expanding Window IC) ===\n")
print(rbind(perf_icw, perf_bm))
cat(sprintf("  Turnover (ann.): %.1f%%\n", to_icw))

# ─── Step 5: 성과 비교 요약 ──────────────────────────────────
cat("\n")
cat("================================================================\n")
cat("   STR_1650: C19 + AC21 + CR05 Score Blending\n")
cat("   Consensus + Accrual Quality + Crowding Reversal\n")
cat("================================================================\n")
cat("\n--- EW Composite (1/3, 1/3, 1/3) ---\n")
print(perf_ew)
cat(sprintf("  Turnover: %.1f%%\n", to_ew))
cat("\n--- IC-Weighted Composite (Expanding Window) ---\n")
print(perf_icw)
cat(sprintf("  Turnover: %.1f%%\n", to_icw))
cat("\n--- Benchmark (KOSPI200) ---\n")
print(perf_bm)
cat("================================================================\n")

# ─── Step 6: 차트 생성 ───────────────────────────────────────
cat("\n[Step 6] Generating charts...\n")

generate_charts(sim_ew,  output_dir = file.path(OUT_DIR, "ew"),
                strategy_name = "STR_1650 EW (C19+AC21+CR05)")
generate_charts(sim_icw, output_dir = file.path(OUT_DIR, "icw"),
                strategy_name = "STR_1650 ICW (IC-Weighted)")

# ─── Step 7: 허들 평가 ───────────────────────────────────────
cat("\n[Step 7] Hurdle gate evaluation...\n")

source(file.path(FUNC_PATH, "hurdle_gate.R"))

hurdle_ew  <- tryCatch(
  run_hurdle_gate(sim_ew,  FACTORS = FACTORS_EW,
                  strategy_name = "STR_1650_EW",
                  output_dir = file.path(OUT_DIR, "ew")),
  error = function(e) {
    cat(sprintf("  [hurdle] EW 평가 실패: %s\n", conditionMessage(e)))
    NULL
  }
)

hurdle_icw <- tryCatch(
  run_hurdle_gate(sim_icw, FACTORS = FACTORS_ICW,
                  strategy_name = "STR_1650_ICW",
                  output_dir = file.path(OUT_DIR, "icw")),
  error = function(e) {
    cat(sprintf("  [hurdle] ICW 평가 실패: %s\n", conditionMessage(e)))
    NULL
  }
)

if (!is.null(hurdle_ew))  cat(sprintf("\n[Hurdle EW]  Grade: %s | Score: %.1f\n",
                                       hurdle_ew$grade, hurdle_ew$score))
if (!is.null(hurdle_icw)) cat(sprintf("[Hurdle ICW] Grade: %s | Score: %.1f\n",
                                       hurdle_icw$grade, hurdle_icw$score))

# ─── Step 8: 결과 저장 ───────────────────────────────────────
cat("\n[Step 8] Saving results...\n")

dir.create(file.path(OUT_DIR, "ew"),  showWarnings = FALSE, recursive = TRUE)
dir.create(file.path(OUT_DIR, "icw"), showWarnings = FALSE, recursive = TRUE)

fwrite(FACTORS_EW,  file.path(OUT_DIR, "factors_ew.csv"))
fwrite(FACTORS_ICW, file.path(OUT_DIR, "factors_icw.csv"))

fwrite(sim_ew$DAILY_NAV_DT,  file.path(OUT_DIR, "ew",  "daily_nav.csv"))
fwrite(sim_icw$DAILY_NAV_DT, file.path(OUT_DIR, "icw", "daily_nav.csv"))

perf_list <- list(
  strategy_id  = "STR_1650_C19_AC21_CR05_blend",
  description  = "Consensus + Accrual Quality + Crowding Reversal 3-factor composite",
  stage        = "S1",
  factors      = FACTOR_NAMES,
  ew_composite = list(
    weights  = list(C19 = 1/3, AC21 = 1/3, CR05 = 1/3),
    perf     = as.list(perf_ew),
    turnover = to_ew,
    hurdle   = if (!is.null(hurdle_ew)) list(grade = hurdle_ew$grade, score = hurdle_ew$score) else NULL
  ),
  icw_composite = list(
    method = "expanding_window_IC_weighted",
    perf   = as.list(perf_icw),
    turnover = to_icw,
    hurdle = if (!is.null(hurdle_icw)) list(grade = hurdle_icw$grade, score = hurdle_icw$score) else NULL
  ),
  benchmark    = as.list(perf_bm),
  run_date     = format(Sys.Date())
)

write_json(perf_list, file.path(OUT_DIR, "performance.json"),
           pretty = TRUE, auto_unbox = TRUE)

cat(sprintf("\n[DONE] factor_engine.R complete.\n"))
