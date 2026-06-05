cat("=== STR_1663: V02_EP Standalone Diversifier — S1 ===\n")
## 핵심아이디어: Earnings-to-Price(V02_EP) 단독 100%. Value family.
## Diversifier role. 잔차 alpha 3위, ICIR 0.364, crisis_ratio 0.75.
## 6가설 토론 결과: 블렌드는 약팩터 희석(L-119). 단일 강팩터 standalone만 성공(Q07 사례).
## EW 20종목 + 15bps + 유동성 2e8. 순수 팩터 신호 (S1, 오버레이 없음).
##
## PIT: C1(frollmean rolling, no full-sample) C2(liq_lag=shift(t-1)) C13(Z_Score_Aligned)
##      C15(factor_db_connector 경유, 직접 parquet 금지)
## OPT: rbindlist bulk load 1회, setkey(Date,Ticker)

set.seed(20260412)
t0 <- Sys.time()

# ---- 1. 경로 설정 ----
.root_candidates <- c(
  Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot")),
  "/mnt/c/Users/99922/OneDrive/\ubc14\ud0d5 \ud654\uba74/Quant_Module_Moltbot"
)
PROJECT_ROOT <- .root_candidates[sapply(.root_candidates, dir.exists)][1]
rm(.root_candidates)

FUNC_PATH  <- file.path(PROJECT_ROOT, "02_Infrastructure")
STRAT_DIR  <- tryCatch(dirname(sys.frame(1)$ofile), error = function(e) getwd())
OUT_DIR    <- file.path(STRAT_DIR, "output")
dir.create(OUT_DIR, showWarnings = FALSE, recursive = TRUE)

# ---- 2. 인프라 로드 ----
source(file.path(FUNC_PATH, "config.R"))
source(file.path(FUNC_PATH, "backtest_harness.R"))

suppressPackageStartupMessages({
  library(data.table); library(arrow); library(dplyr)
  library(xts); library(zoo)
  library(PerformanceAnalytics); library(ggplot2); library(scales); library(jsonlite)
})

options(scipen = 999)
Sys.setenv(TZ = "Asia/Seoul")

STRATEGY_ID  <- "STR_1663"
STRATEGY_FAM <- "value"
N_HOLD       <- 20L
LIQ_THRESHOLD <- 2e8
COMMISSION   <- 0.0015   # 15bps

# ---- 3. Preflight ----
source(file.path(FUNC_PATH, "validation", "preflight_memory.R"))
preflight_check(STRATEGY_ID, family = STRATEGY_FAM)

# ---- 4. RAWDATA (1회 로드) ----
cat("\n[4] RAWDATA...\n")
rw <- load_rawdata(use_cache = TRUE)
RAWDATA <- rw$RAWDATA
BM_DT   <- rw$BM_DT
setDT(RAWDATA)
setkey(RAWDATA, Date, Ticker)
cat(sprintf("    %d rows | %s ~ %s\n", nrow(RAWDATA), min(RAWDATA$Date), max(RAWDATA$Date)))

# ---- 5. Factor DB (C15: connector 경유, 1회 bulk load) ----
cat("\n[5] Factor DB — V02_EP (C15 준수)...\n")
source(file.path(FUNC_PATH, "factor_db", "factor_db_connector.R"))

FACTORS_NEEDED <- "V02_EP"
CACHE_DIR_FDB  <- file.path(CACHE_DIR, "factor_db")
fdb_files <- list.files(CACHE_DIR_FDB,
                         pattern = "^factor_db_\\d{6}\\.parquet$",
                         full.names = TRUE)
cat(sprintf("    %d monthly parquet files found.\n", length(fdb_files)))

# OPT: rbindlist 1회 bulk load. 루프 내 반복 로드 금지.
fdb <- rbindlist(lapply(fdb_files, function(f) {
  dt <- as.data.table(arrow::read_parquet(f))
  dt[Factor_Name %in% FACTORS_NEEDED]
}))
fdb[, Date := as.Date(Date)]

# C13: Z_Score_Aligned = align_factor_direction() 사용. 수동 방향 반전 절대 금지.
fdb <- align_factor_direction(fdb, .load_registry())
fdb <- fdb[Coverage == TRUE]
setkey(fdb, Date, Ticker)
cat(sprintf("    %d rows | Factor: %s\n", nrow(fdb), paste(unique(fdb$Factor_Name), collapse = ", ")))

# ---- 6. Merge + Score ----
cat("\n[6] Merge + Liquidity Lag + Score...\n")
fdb_wide <- dcast(fdb, Date + Ticker ~ Factor_Name, value.var = "Z_Score_Aligned")
dt <- merge(RAWDATA, fdb_wide, by = c("Date", "Ticker"), all.x = FALSE)
setkey(dt, Date, Ticker)

# C1: rolling 20일 (full-sample 통계 금지)
dt[, liq_20d := frollmean(Vol * Close, n = 20L, align = "right"), by = Ticker]
# C2: t-1 lag (same-day circular 금지)
dt[, liq_lag := shift(liq_20d, 1L), by = Ticker]

# Score: V02_EP standalone 100%
dt[, score := V02_EP]

cat(sprintf("    merged dt: %d rows, score non-NA: %d\n",
    nrow(dt), sum(!is.na(dt$score))))

# ---- 7. 월별 포트폴리오 구성 ----
cat("\n[7] Monthly Portfolio Construction...\n")
months_all <- sort(unique(dt$Date))
port_list  <- lapply(months_all, function(m) {
  sub <- dt[Date == m & !is.na(score) & !is.na(liq_lag)]
  # C2: liq_lag(t-1)로 필터 — 당일 유동성 사용 금지
  sub <- sub[liq_lag >= LIQ_THRESHOLD]
  if (nrow(sub) < N_HOLD) return(NULL)
  sub <- sub[order(-score)]
  top <- head(sub, N_HOLD)
  top[, .(Date = m, Ticker, Score = score, Weight = 1.0 / N_HOLD)]
})
port <- rbindlist(port_list[!sapply(port_list, is.null)])
cat(sprintf("    포트 행수: %d | 월수: %d\n", nrow(port), length(unique(port$Date))))

# ---- 8. 수익률 계산 ----
cat("\n[8] Return Calculation...\n")
port <- merge(port, RAWDATA[, .(Date, Ticker, Ret)], by = c("Date", "Ticker"))
monthly_ret <- port[, .(port_ret = mean(Ret, na.rm = TRUE)), by = Date]
setorder(monthly_ret, Date)

# Turnover 계산
prev_tk <- NULL
to_vec  <- numeric(nrow(monthly_ret))
invisible(lapply(seq_len(nrow(monthly_ret)), function(i) {
  cur_date <- monthly_ret$Date[i]
  cur <- port[Date == cur_date, Ticker]
  if (!is.null(prev_tk)) {
    to_vec[i] <<- 1 - length(intersect(cur, prev_tk)) / N_HOLD
  }
  prev_tk <<- cur
  NULL
}))
monthly_ret[, turnover := to_vec]
# 수수료 차감 (회전 발생 시)
monthly_ret[turnover > 0, port_ret := port_ret - turnover * COMMISSION]

# BM 병합
monthly_ret <- merge(monthly_ret, BM_DT[, .(Date, BM_Ret)], by = "Date", all.x = TRUE)

# ---- 9. 성과 지표 ----
cat("\n[9] Performance Metrics...\n")
nav <- cumprod(1 + monthly_ret$port_ret)
dd  <- nav / cummax(nav) - 1
n_m <- nrow(monthly_ret)

cagr     <- as.numeric(tail(nav, 1)^(12 / n_m) - 1)
sharpe   <- mean(monthly_ret$port_ret) / sd(monthly_ret$port_ret) * sqrt(12)
mdd      <- min(dd)
to_ann   <- mean(monthly_ret$turnover[monthly_ret$turnover > 0], na.rm = TRUE) * 12

# 초과수익 (BM 대비)
monthly_ret[, excess_ret := port_ret - BM_Ret]
ir <- mean(monthly_ret$excess_ret, na.rm = TRUE) / sd(monthly_ret$excess_ret, na.rm = TRUE) * sqrt(12)

cat(sprintf("  CAGR : %.2f%%\n  SR   : %.3f\n  MDD  : %.1f%%\n  TO   : %.0f%%\n  IR   : %.3f\n",
    cagr*100, sharpe, mdd*100, to_ann*100, ir))

# ---- 10. 출력 저장 ----
cat("\n[10] Save Outputs...\n")
fwrite(monthly_ret, file.path(OUT_DIR, "performance.csv"))

# Equity Curve 차트
png(file.path(OUT_DIR, "equity_curve.png"), width = 1000, height = 520)
par(mar = c(4, 4, 3, 2))
plot(as.Date(monthly_ret$Date), nav,
     type = "l", col = "steelblue", lwd = 2,
     main = "STR_1663 V02_EP Standalone — Equity Curve",
     xlab = "Date", ylab = "NAV")
abline(h = 1, lty = 2, col = "gray60")
grid(col = "gray90", lty = 1)
dev.off()

# Annual Returns 차트
monthly_ret[, Year := format(Date, "%Y")]
annual <- monthly_ret[, .(ann_ret = prod(1 + port_ret) - 1), by = Year]
png(file.path(OUT_DIR, "annual_returns.png"), width = 900, height = 480)
par(mar = c(4, 4, 3, 2))
bar_colors <- ifelse(annual$ann_ret >= 0, "steelblue", "tomato")
barplot(annual$ann_ret * 100, names.arg = annual$Year,
        col = bar_colors, main = "STR_1663 — Annual Returns (%)",
        ylab = "Return (%)", las = 2, cex.names = 0.85)
abline(h = 0, col = "black", lwd = 0.8)
dev.off()

# ---- 11. Hurdle v2.2 인라인 평가 ----
cat("\n[11] Hurdle Gate v2.2...\n")
hard_fail <- (abs(mdd) > 0.45) || (to_ann > 6.0)
score <- 0
score <- score + min(25, max(0, (cagr / 0.16) * 15))   # Return axis
score <- score + min(25, max(0, (sharpe / 0.8) * 20))  # Risk axis (SR)
if (abs(mdd) > 0.30) score <- score - 5                 # MDD penalty
# Saturation: value family — moderate (6~20 trials assumed)
score <- score - 8
score <- max(0, score)

grade <- if (hard_fail) "F" else if (score >= 40 && cagr >= 0.16 && sharpe >= 0.8) "A" else if (score >= 40 && cagr >= 0.12 && sharpe >= 0.6) "A_NOVEL" else if (score >= 25) "B" else "C"

hurdle_result <- list(
  strategy_id   = STRATEGY_ID,
  grade         = grade,
  grade_v21     = grade,   # backward compat
  score         = round(score, 1),
  hard_fail     = hard_fail,
  cagr          = round(cagr, 4),
  sharpe        = round(sharpe, 3),
  mdd           = round(mdd, 4),
  turnover_ann  = round(to_ann, 3),
  ir            = round(ir, 3),
  family        = STRATEGY_FAM,
  role_bias     = "RoleBias_Diversifier",
  n_months      = n_m,
  hurdle_version = "v2.2",
  evaluated_at  = as.character(Sys.time())
)

write_json(hurdle_result, file.path(OUT_DIR, "hurdle_result.json"),
           pretty = TRUE, auto_unbox = TRUE)
cat(sprintf("  Grade: %s | Score: %.1f | hard_fail: %s\n",
    grade, score, hard_fail))

# ---- 12. sim_result 저장 ----
sim_result <- list(
  strategy_id  = STRATEGY_ID,
  hypothesis   = "H_1663_V02EP_standalone",
  factor       = "V02_EP",
  blend        = "standalone_100pct",
  role_bias    = "RoleBias_Diversifier",
  hurdle       = hurdle_result,
  n_months     = n_m,
  timestamp    = as.character(Sys.time())
)
saveRDS(sim_result, file.path(STRAT_DIR, "sim_result.rds"))

cat(sprintf("\n=== STR_1663 완료 (%.1fs) ===\n",
    as.numeric(difftime(Sys.time(), t0, units = "secs"))))
