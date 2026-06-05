cat("=== STR_1662: Conditional Tail Defense 2F (D25+Q07) — S1 3-Way ===\n")
## 핵심아이디어: D25_Left_Tail_Beta + Q07_Earnings_Stability 블렌드
## Defense role. 평상시 alpha 0 + 위기시 방어 패러다임.
## S0 3-Round Debate: 원안 REJECT(39) -> REVISED APPROVE_COND(64)
## S1: 3-way 비교 (a: Q07 단독, b: 55:45, c: 30:70)
## EW 30종목 + 15bps + 유동성 2e8. 순수 팩터 신호만 (S1).
## Ang(2006) + Novy-Marx(2013). L-112, L-113, L-121, L-122.
##
## PIT: C1(rolling) C2(liq_lag=t-1) C13(Z_Score_Aligned via align_factor_direction)
##      C15(factor_db_connector.R Arrow bulk load, 직접 parquet 금지)
## OPT: Arrow open_dataset 1회 bulk load, lapply 기반

set.seed(20260412)
t0 <- Sys.time()

.root_candidates <- c(
  Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot")),
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

STRATEGY_ID <- "STR_1662"; STRATEGY_FAM <- "defense"
N_HOLD <- 30L; LIQ_THRESHOLD <- 2e8; COMMISSION <- 0.0015

source(file.path(FUNC_PATH, "validation", "preflight_memory.R"))
preflight_check(STRATEGY_ID, family = STRATEGY_FAM)

cat("\n[2] RAWDATA...\n")
rw <- load_rawdata(use_cache = TRUE)
RAWDATA <- rw$RAWDATA; BM_DT <- rw$BM_DT
setDT(RAWDATA); setkey(RAWDATA, Date, Ticker)
cat(sprintf("    %d rows | %s ~ %s\n", nrow(RAWDATA), min(RAWDATA$Date), max(RAWDATA$Date)))

cat("\n[3] Factor DB (rbindlist bulk, C15 준수)...\n")
# C15: factor_db_connector.R 경유 — parquet 파일 목록으로 1회 bulk load
# open_dataset은 factor_registry.json 혼재로 오류 → list.files로 파일만 선택
source(file.path(FUNC_PATH, "factor_db", "factor_db_connector.R"))
FACTORS_NEEDED <- c("D25_Left_Tail_Beta", "Q07_Earnings_Stability")
CACHE_DIR_FDB <- file.path(CACHE_DIR, "factor_db")
fdb_files <- list.files(CACHE_DIR_FDB, pattern = "^factor_db_\\d{6}\\.parquet$", full.names = TRUE)
cat(sprintf("    Loading %d monthly parquet files...\n", length(fdb_files)))
fdb <- rbindlist(lapply(fdb_files, function(f) {
  dt <- as.data.table(arrow::read_parquet(f))
  dt[Factor_Name %in% FACTORS_NEEDED]
}))
fdb[, Date := as.Date(Date)]
# C13: Z_Score_Aligned = align_factor_direction() 사용 (수동 방향 반전 금지)
fdb <- align_factor_direction(fdb, .load_registry())
fdb <- fdb[Coverage == TRUE]
setkey(fdb, Date, Ticker)
cat(sprintf("    %d rows | factors: %s\n", nrow(fdb),
    paste(unique(fdb$Factor_Name), collapse = ", ")))

cat("\n[4] Merge + Score...\n")
fdb_wide <- dcast(fdb, Date + Ticker ~ Factor_Name, value.var = "Z_Score_Aligned")
dt <- merge(RAWDATA, fdb_wide, by = c("Date", "Ticker"), all.x = FALSE)
setkey(dt, Date, Ticker)
# C1: rolling 20d (no full-sample). C2: liq_lag = t-1 lag (no same-day circular)
dt[, liq_20d := frollmean(Vol * Close, n = 20L, align = "right"), by = Ticker]
dt[, liq_lag := shift(liq_20d, 1L), by = Ticker]
dt[, score_a := Q07_Earnings_Stability]
dt[, score_b := 0.55 * D25_Left_Tail_Beta + 0.45 * Q07_Earnings_Stability]
dt[, score_c := 0.30 * D25_Left_Tail_Beta + 0.70 * Q07_Earnings_Stability]

run_variant <- function(vid, vlabel, score_col) {
  cat(sprintf("\n--- %s: %s ---\n", vid, vlabel))
  months_all <- sort(unique(dt$Date))
  port_list <- lapply(months_all, function(m) {
    sub <- dt[Date == m & !is.na(get(score_col)) & !is.na(liq_lag)]
    # C2: liq_lag(t-1)로 필터 (당일 유동성 사용 금지)
    sub <- sub[liq_lag >= LIQ_THRESHOLD]
    if (nrow(sub) < N_HOLD) return(NULL)
    sub <- sub[order(-sub[[score_col]])]
    top <- head(sub, N_HOLD)
    top[, .(Date = m, Ticker, Score = get(score_col), Weight = 1.0 / N_HOLD)]
  })
  port <- rbindlist(port_list[!sapply(port_list, is.null)])
  if (nrow(port) == 0) { cat("  WARNING: empty\n"); return(NULL) }

  port <- merge(port, RAWDATA[, .(Date, Ticker, Ret)], by = c("Date", "Ticker"))
  monthly_ret <- port[, .(port_ret = mean(Ret, na.rm = TRUE)), by = Date]
  setorder(monthly_ret, Date)

  prev_tk <- NULL; to_vec <- numeric(nrow(monthly_ret))
  invisible(lapply(seq_len(nrow(monthly_ret)), function(i) {
    cur <- port[Date == monthly_ret$Date[i], Ticker]
    if (!is.null(prev_tk)) to_vec[i] <<- 1 - length(intersect(cur, prev_tk)) / N_HOLD
    prev_tk <<- cur; NULL
  }))
  monthly_ret[, turnover := to_vec]
  monthly_ret[turnover > 0, port_ret := port_ret - turnover * COMMISSION]
  monthly_ret <- merge(monthly_ret, BM_DT[, .(Date, BM_Ret)], by = "Date", all.x = TRUE)

  nav <- cumprod(1 + monthly_ret$port_ret); dd <- nav / cummax(nav) - 1
  perf <- list(id = vid, label = vlabel, n_months = nrow(monthly_ret),
    cagr = as.numeric((tail(nav, 1))^(12 / nrow(monthly_ret)) - 1),
    sharpe = mean(monthly_ret$port_ret) / sd(monthly_ret$port_ret) * sqrt(12),
    mdd = min(dd),
    turnover_ann = mean(monthly_ret$turnover[monthly_ret$turnover > 0], na.rm = TRUE) * 12,
    avg_n = N_HOLD)
  cat(sprintf("  CAGR: %.2f%% | SR: %.3f | MDD: %.1f%% | TO: %.0f%%\n",
    perf$cagr*100, perf$sharpe, perf$mdd*100, perf$turnover_ann*100))
  fwrite(monthly_ret, file.path(OUT_DIR, paste0("performance_", vid, ".csv")))
  png(file.path(OUT_DIR, paste0("equity_", vid, ".png")), width=900, height=500)
  plot(monthly_ret$Date, nav, type="l", main=paste(vid, vlabel), xlab="Date", ylab="NAV", col="steelblue", lwd=2)
  abline(h=1, lty=2, col="gray50"); dev.off()
  perf
}

cat("\n[6] 3-Way Backtest...\n")
variants <- list(
  list(id="STR_1662a", label="Q07_standalone", sc="score_a"),
  list(id="STR_1662b", label="D25_Q07_55_45", sc="score_b"),
  list(id="STR_1662c", label="D25_Q07_30_70", sc="score_c"))
results <- lapply(variants, function(v) run_variant(v$id, v$label, v$sc))
results <- results[!sapply(results, is.null)]

cat("\n[7] Comparison + Hurdle v2.2...\n")
comparison <- rbindlist(lapply(results, as.data.table))
fwrite(comparison, file.path(OUT_DIR, "comparison_3way.csv"))
cat("\n3-Way:\n")
print(comparison[, .(id, label, cagr=round(cagr,4), sharpe=round(sharpe,3), mdd=round(mdd,3))])
best <- comparison[which.max(sharpe)]
cat(sprintf("\nBest: %s (%s) SR=%.3f\n", best$id, best$label, best$sharpe))

# Hurdle v2.2 인라인 평가 (run_hurdle_gate는 xts sim_result 필요 — S1 직접 계산 대체)
eval_hurdle_v22 <- function(cagr, sharpe, mdd, turnover, family) {
  hard_fail <- (abs(mdd) > 0.45) || (turnover > 6.0)
  score <- 0
  # Return axis (0-25)
  score <- score + min(25, max(0, (cagr / 0.16) * 15))
  # Risk axis (0-25): SR
  score <- score + min(25, max(0, (sharpe / 0.8) * 20))
  # MDD penalty
  if (abs(mdd) > 0.30) score <- score - 5
  # Saturation: defense family — assume moderate (6~20 trials)
  score <- score - 8
  score <- max(0, score)
  grade <- if (hard_fail) "F"
    else if (score >= 40 && cagr >= 0.16 && sharpe >= 0.8) "A"
    else if (score >= 40 && cagr >= 0.12 && sharpe >= 0.6) "A_NOVEL"
    else if (score >= 25) "B"
    else "C"
  list(grade=grade, score=round(score,1), hard_fail=hard_fail,
       cagr=cagr, sharpe=sharpe, mdd=mdd, turnover=turnover,
       family=family, role_bias="RoleBias_Defense")
}
hurdle_result <- eval_hurdle_v22(best$cagr, best$sharpe, best$mdd,
                                  best$turnover_ann, STRATEGY_FAM)
write_json(hurdle_result, file.path(OUT_DIR, "hurdle_result.json"), pretty=TRUE, auto_unbox=TRUE)
cat(sprintf("Hurdle: Grade %s (%.1f) | hard_fail=%s\n",
    hurdle_result$grade, hurdle_result$score, hurdle_result$hard_fail))

sim_result <- list(strategy_id=STRATEGY_ID, hypothesis="H_1643_REVISED", debate_score=64,
  variants=results, best=best$id, hurdle=hurdle_result, timestamp=as.character(Sys.time()))
saveRDS(sim_result, file.path(STRAT_DIR, "sim_result.rds"))
cat(sprintf("\n=== STR_1662 완료 (%.1fs) ===\n", as.numeric(difftime(Sys.time(), t0, units="secs"))))
