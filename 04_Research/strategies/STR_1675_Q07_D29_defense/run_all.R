cat("=== STR_1675: Q07+D29 Conditional Defense (S1 Pure Factor) ===\n")
## 핵심아이디어: Q07_Earnings_Stability 앵커(65%) + D29_Accounting_Beta 보조(35%)
## Defense role. S1: 순수 팩터 alpha 측정. EW 30종목, 15bps.
## S0 Debate 74점. H_1675 수정안.
## Filters: D04 하위10% 제거, Q01>0 수익성 필터, 유동성 2e8.
## Dichev&Tang(2009) + Beaver,Kettler&Scholes(1970). L-121, L-122, L-119.
##
## PIT: C1(expanding via Z_Score_Aligned) C2(liq_lag=t-1) C4(Factor DB 자동)
##      C13(Z_Score_Aligned only) C15(factor_db_connector.R 경유)
## OPT: rbindlist bulk load 1회, setkey merge

set.seed(20260416)
t0 <- Sys.time()

# ─── Project Root (한글 경로 대응) ──────────────────────────────────────────
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
source(file.path(FUNC_PATH, "backtest_harness.R"))

suppressPackageStartupMessages({
  library(data.table); library(arrow); library(dplyr)
  library(xts); library(zoo)
  library(PerformanceAnalytics); library(ggplot2); library(scales); library(jsonlite)
})

options(scipen = 999); Sys.setenv(TZ = "Asia/Seoul")

STRATEGY_ID  <- "STR_1675"
STRATEGY_FAM <- "defense"
N_HOLD       <- 30L
LIQ_THRESHOLD <- 2e8
COMMISSION   <- 0.0015
D04_CUTOFF   <- 0.10  # 하위 10% 제거

# ─── Preflight ──────────────────────────────────────────────────────────────
source(file.path(FUNC_PATH, "validation", "preflight_memory.R"))
preflight_check(STRATEGY_ID, family = STRATEGY_FAM)

# ─── [1] RAWDATA ────────────────────────────────────────────────────────────
cat("\n[1] RAWDATA...\n")
rw <- load_rawdata(use_cache = TRUE)
RAWDATA <- rw$RAWDATA; BM_DT <- rw$BM_DT
setDT(RAWDATA); setkey(RAWDATA, Date, Ticker)
cat(sprintf("    %d rows | %s ~ %s\n", nrow(RAWDATA), min(RAWDATA$Date), max(RAWDATA$Date)))

# ─── [2] Factor DB (C15: factor_db_connector.R 경유) ────────────────────────
cat("\n[2] Factor DB (rbindlist bulk, C15)...\n")
source(file.path(FUNC_PATH, "factor_db", "factor_db_connector.R"))
FACTORS_NEEDED <- c("Q07_Earnings_Stability", "D29_Accounting_Beta",
                     "D04_Downside_Beta", "Q01_GPA")
CACHE_DIR_FDB <- file.path(CACHE_DIR, "factor_db")
fdb_files <- list.files(CACHE_DIR_FDB, pattern = "^factor_db_\\d{6}\\.parquet$", full.names = TRUE)
cat(sprintf("    Loading %d monthly parquet files (4 factors)...\n", length(fdb_files)))
fdb <- rbindlist(lapply(fdb_files, function(f) {
  dt <- as.data.table(arrow::read_parquet(f))
  dt[Factor_Name %in% FACTORS_NEEDED]
}))
fdb[, Date := as.Date(Date)]

# C13: Z_Score_Aligned via align_factor_direction (수동 방향 반전 금지)
fdb <- align_factor_direction(fdb, .load_registry())
fdb <- fdb[Coverage == TRUE]
setkey(fdb, Date, Ticker)
cat(sprintf("    %d rows | factors: %s\n", nrow(fdb),
    paste(sort(unique(fdb$Factor_Name)), collapse = ", ")))

# ─── [3] Pivot + Merge ─────────────────────────────────────────────────────
cat("\n[3] Merge + Score...\n")
fdb_wide <- dcast(fdb, Date + Ticker ~ Factor_Name, value.var = "Z_Score_Aligned")
dt <- merge(RAWDATA, fdb_wide, by = c("Date", "Ticker"), all.x = FALSE)
setkey(dt, Date, Ticker)

# C1: rolling 20d 유동성 (full-sample 통계 금지)
# C2: liq_lag = t-1 (same-day circular 금지)
dt[, liq_20d := frollmean(Vol * Close, n = 20L, align = "right"), by = Ticker]
dt[, liq_lag := shift(liq_20d, 1L), by = Ticker]

# ─── [4] Score 계산 ────────────────────────────────────────────────────────
# Defense composite: 0.65 * Z(Q07) + 0.35 * Z(D29)
# D04, Q01은 score에 불포함 — 필터 전용
dt[, Score_defense := 0.65 * Q07_Earnings_Stability + 0.35 * D29_Accounting_Beta]

# ─── [5] 3-Way 비교 (a: 블렌드, b: Q07 단독, c: 80/20) ───────────────────
cat("\n[4] Backtest (3-Way: main 65/35, Q07 standalone, 80/20)...\n")

run_variant <- function(vid, vlabel, score_expr) {
  cat(sprintf("\n--- %s: %s ---\n", vid, vlabel))

  # Score 계산
  dt[, .score_tmp := eval(parse(text = score_expr))]

  months_all <- sort(unique(dt$Date))
  port_list <- lapply(months_all, function(m) {
    sub <- dt[Date == m & !is.na(.score_tmp) & !is.na(liq_lag)]

    # Filter 1: 유동성 >= 2e8 (C2: t-1 lag)
    sub <- sub[liq_lag >= LIQ_THRESHOLD]

    # Filter 2: D04 하위 10% 제거 (회피 필터)
    if ("D04_Downside_Beta" %in% names(sub)) {
      sub <- sub[!is.na(D04_Downside_Beta)]
      d04_cutoff <- quantile(sub$D04_Downside_Beta, D04_CUTOFF, na.rm = TRUE)
      sub <- sub[D04_Downside_Beta > d04_cutoff]
    }

    # Filter 3: Q01_GPA > 0 (수익성 음의 노출 제거)
    if ("Q01_GPA" %in% names(sub)) {
      sub <- sub[!is.na(Q01_GPA) & Q01_GPA > 0]
    }

    if (nrow(sub) < N_HOLD) return(NULL)
    sub <- sub[order(-.score_tmp)]
    top <- head(sub, N_HOLD)
    top[, .(Date = m, Ticker, Score = .score_tmp, Weight = 1.0 / N_HOLD)]
  })
  port <- rbindlist(port_list[!sapply(port_list, is.null)])

  if (nrow(port) == 0) { cat("  WARNING: empty portfolio\n"); return(NULL) }

  # Merge returns
  port <- merge(port, RAWDATA[, .(Date, Ticker, Ret)], by = c("Date", "Ticker"))
  monthly_ret <- port[, .(port_ret = mean(Ret, na.rm = TRUE)), by = Date]
  setorder(monthly_ret, Date)

  # Turnover 계산
  prev_tk <- NULL; to_vec <- numeric(nrow(monthly_ret))
  invisible(lapply(seq_len(nrow(monthly_ret)), function(i) {
    cur <- port[Date == monthly_ret$Date[i], Ticker]
    if (!is.null(prev_tk)) to_vec[i] <<- 1 - length(intersect(cur, prev_tk)) / N_HOLD
    prev_tk <<- cur; NULL
  }))
  monthly_ret[, turnover := to_vec]
  monthly_ret[turnover > 0, port_ret := port_ret - turnover * COMMISSION]

  # Benchmark merge
  monthly_ret <- merge(monthly_ret, BM_DT[, .(Date, BM_Ret)], by = "Date", all.x = TRUE)

  # Performance
  nav <- cumprod(1 + monthly_ret$port_ret)
  dd  <- nav / cummax(nav) - 1
  perf <- list(
    id = vid, label = vlabel,
    n_months = nrow(monthly_ret),
    cagr = as.numeric((tail(nav, 1))^(12 / nrow(monthly_ret)) - 1),
    sharpe = mean(monthly_ret$port_ret) / sd(monthly_ret$port_ret) * sqrt(12),
    mdd = min(dd),
    turnover_ann = mean(monthly_ret$turnover[monthly_ret$turnover > 0], na.rm = TRUE) * 12,
    avg_n = N_HOLD
  )
  cat(sprintf("  CAGR: %.2f%% | SR: %.3f | MDD: %.1f%% | TO: %.0f%%\n",
    perf$cagr*100, perf$sharpe, perf$mdd*100, perf$turnover_ann*100))

  # Save CSV
  fwrite(monthly_ret, file.path(OUT_DIR, paste0("performance_", vid, ".csv")))

  # Equity curve chart
  png(file.path(OUT_DIR, paste0("equity_", vid, ".png")), width = 900, height = 500)
  bm_nav <- cumprod(1 + ifelse(is.na(monthly_ret$BM_Ret), 0, monthly_ret$BM_Ret))
  plot(monthly_ret$Date, nav, type = "l", main = paste(vid, vlabel),
       xlab = "Date", ylab = "NAV", col = "steelblue", lwd = 2,
       ylim = range(c(nav, bm_nav), na.rm = TRUE))
  lines(monthly_ret$Date, bm_nav, col = "gray50", lwd = 1, lty = 2)
  legend("topleft", c("Strategy", "KOSPI"), col = c("steelblue","gray50"),
         lwd = c(2,1), lty = c(1,2), bg = "white")
  abline(h = 1, lty = 3, col = "gray70")
  dev.off()

  dt[, .score_tmp := NULL]
  list(perf = perf, monthly_ret = monthly_ret, nav = nav)
}

# 3-Way variants
variants <- list(
  list(id = "STR_1675a", label = "Q07_65_D29_35",
       sc = "0.65 * Q07_Earnings_Stability + 0.35 * D29_Accounting_Beta"),
  list(id = "STR_1675b", label = "Q07_standalone",
       sc = "Q07_Earnings_Stability"),
  list(id = "STR_1675c", label = "Q07_80_D29_20",
       sc = "0.80 * Q07_Earnings_Stability + 0.20 * D29_Accounting_Beta")
)
results <- lapply(variants, function(v) run_variant(v$id, v$label, v$sc))
results <- results[!sapply(results, is.null)]

# ─── [6] Comparison + Hurdle ───────────────────────────────────────────────
cat("\n[5] Comparison + Hurdle v2.2...\n")
comparison <- rbindlist(lapply(results, function(r) as.data.table(r$perf)))
fwrite(comparison, file.path(OUT_DIR, "comparison_3way.csv"))
cat("\n3-Way Comparison:\n")
print(comparison[, .(id, label, cagr = round(cagr, 4), sharpe = round(sharpe, 3),
                      mdd = round(mdd, 3), turnover_ann = round(turnover_ann, 2))])
best_idx <- which.max(comparison$sharpe)
best <- comparison[best_idx]
cat(sprintf("\nBest variant: %s (%s) SR=%.3f\n", best$id, best$label, best$sharpe))

# Hurdle v2.2 inline
eval_hurdle_v22 <- function(cagr, sharpe, mdd, turnover, family) {
  hard_fail <- (abs(mdd) > 0.45) || (turnover > 6.0)
  score <- 0
  # Return axis (0-25)
  score <- score + min(25, max(0, (cagr / 0.16) * 15))
  # Risk axis (0-25): SR
  score <- score + min(25, max(0, (sharpe / 0.8) * 20))
  # MDD penalty
  if (abs(mdd) > 0.30) score <- score - 5
  # Saturation: defense family 6~20 trials
  score <- score - 8
  score <- max(0, score)
  grade <- if (hard_fail) "F"
    else if (score >= 40 && cagr >= 0.16 && sharpe >= 0.8) "A"
    else if (score >= 40 && cagr >= 0.12 && sharpe >= 0.6) "A_NOVEL"
    else if (score >= 25) "B"
    else "C"
  list(grade = grade, score = round(score, 1), hard_fail = hard_fail,
       cagr = cagr, sharpe = sharpe, mdd = mdd, turnover = turnover,
       family = family, role_bias = "RoleBias_Defense")
}

hurdle_result <- eval_hurdle_v22(best$cagr, best$sharpe, best$mdd,
                                  best$turnover_ann, STRATEGY_FAM)
write_json(hurdle_result, file.path(OUT_DIR, "hurdle_result.json"),
           pretty = TRUE, auto_unbox = TRUE)
cat(sprintf("\nHurdle: Grade %s (Score %.1f) | hard_fail=%s\n",
    hurdle_result$grade, hurdle_result$score, hurdle_result$hard_fail))

# ─── [7] Charts (best variant) ─────────────────────────────────────────────
cat("\n[6] Charts (best variant)...\n")
best_res <- results[[best_idx]]

# Annual returns bar chart
yrs <- as.integer(format(best_res$monthly_ret$Date, "%Y"))
yr_ret <- tapply(best_res$monthly_ret$port_ret, yrs, function(x) prod(1+x)-1)
yr_dt <- data.table(Year = as.integer(names(yr_ret)), Return = as.numeric(yr_ret))

png(file.path(OUT_DIR, "annual_returns.png"), width = 900, height = 500)
bp <- barplot(yr_dt$Return * 100, names.arg = yr_dt$Year,
              col = ifelse(yr_dt$Return >= 0, "steelblue", "tomato"),
              main = paste(STRATEGY_ID, "Annual Returns (%)"),
              ylab = "Return (%)", las = 2, border = NA)
abline(h = 0, col = "gray40")
text(bp, yr_dt$Return * 100 + sign(yr_dt$Return) * 1.5,
     sprintf("%.1f", yr_dt$Return * 100), cex = 0.7)
dev.off()

# Main equity curve = best variant
file.copy(file.path(OUT_DIR, paste0("equity_", best$id, ".png")),
          file.path(OUT_DIR, "equity_curve.png"), overwrite = TRUE)

# ─── [8] Filter 진단 (S1 prerequisite 검증) ────────────────────────────────
cat("\n[7] Filter diagnostics (S1 prerequisites)...\n")

# 교차필터 후 유효 종목 수 추이
filter_diag <- dt[, {
  sub <- .SD[!is.na(liq_lag) & liq_lag >= LIQ_THRESHOLD]
  n_liq <- nrow(sub)
  if ("D04_Downside_Beta" %in% names(sub)) {
    sub <- sub[!is.na(D04_Downside_Beta)]
    d04_cut <- quantile(sub$D04_Downside_Beta, D04_CUTOFF, na.rm = TRUE)
    sub <- sub[D04_Downside_Beta > d04_cut]
  }
  n_d04 <- nrow(sub)
  if ("Q01_GPA" %in% names(sub)) {
    sub <- sub[!is.na(Q01_GPA) & Q01_GPA > 0]
  }
  n_final <- nrow(sub)
  .(N_liq = n_liq, N_post_D04 = n_d04, N_final = n_final)
}, by = Date]
setorder(filter_diag, Date)
cat(sprintf("  유효 종목 (최근 10개월):\n"))
print(tail(filter_diag, 10))
cat(sprintf("  최소 유효 종목: %d (날짜: %s)\n",
    min(filter_diag$N_final), filter_diag$Date[which.min(filter_diag$N_final)]))
fwrite(filter_diag, file.path(OUT_DIR, "filter_diagnostics.csv"))

# ─── [9] Save sim_result ───────────────────────────────────────────────────
sim_result <- list(
  strategy_id = STRATEGY_ID,
  hypothesis = "H_1675_Q07_D29_ConditionalDefense",
  debate_score = 74,
  factors = list(
    score = c("Q07_Earnings_Stability", "D29_Accounting_Beta"),
    filter = c("D04_Downside_Beta", "Q01_GPA")
  ),
  variants = lapply(results, function(r) r$perf),
  best = best$id,
  hurdle = hurdle_result,
  filter_diag = list(
    min_universe = min(filter_diag$N_final),
    median_universe = median(filter_diag$N_final)
  ),
  pit_check = list(
    C1 = "Z_Score_Aligned (expanding)", C2 = "liq_lag t-1",
    C4 = "Factor DB auto", C13 = "Z_Score_Aligned only",
    C15 = "factor_db_connector.R", S1_pure = "no S5 components"
  ),
  timestamp = as.character(Sys.time())
)
saveRDS(sim_result, file.path(STRAT_DIR, "sim_result.rds"))
write_json(sim_result, file.path(OUT_DIR, "sim_result.json"),
           pretty = TRUE, auto_unbox = TRUE)

cat(sprintf("\n=== STR_1675 완료 (%.1fs) ===\n",
    as.numeric(difftime(Sys.time(), t0, units = "secs"))))
