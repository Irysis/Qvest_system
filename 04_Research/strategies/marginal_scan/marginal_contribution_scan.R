## =============================================================================
## Marginal Contribution Scan v1
## VDplus C19를 앵커로 놓고 288개 팩터를 하나씩 추가하여
## 한계 SR 개선을 측정하는 systematic scan (Pre-S0 리서치)
##
## 방법: 월간 FDB → C19 + candidate → top-N → next-month EW return → SR
## PIT: OOS 2008~2025, 유동성 필터 적용, t-1 signal → t execution
## =============================================================================

cat("=== Marginal Contribution Scan v1 ===\n")
cat("시작:", as.character(Sys.time()), "\n\n")

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
})

PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
FDB_DIR      <- file.path(PROJECT_ROOT, ".cache/factor_db")
OUTPUT_DIR   <- file.path(PROJECT_ROOT, "04_Research/strategies/marginal_scan")

source(file.path(PROJECT_ROOT, "02_Infrastructure/config.R"))
source(file.path(PROJECT_ROOT, "02_Infrastructure/backtest_harness.R"))

N_TOP        <- 20L
LIQ_THRESH   <- 2e8
BASELINE_FAC <- "C19_Composite_Earnings"
OOS_START    <- as.Date("2008-01-01")
OOS_END      <- as.Date("2025-12-31")

# =============================================================================
# [1] RAWDATA + 월별 수익률
# =============================================================================
cat("[1] RAWDATA...\n")
rw <- load_rawdata(use_cache = TRUE)
RAWDATA <- rw$RAWDATA; BM_DT <- rw$BM_DT
setDT(RAWDATA); setkey(RAWDATA, Date, Ticker)

# 월말 날짜 + 다음 월말 매핑 (next-month return 계산)
RAWDATA[, ym := format(Date, "%Y-%m")]
me_dates <- RAWDATA[, .(me_date = max(Date)), by = ym][order(me_date)]
me_dates[, next_me := shift(me_date, type = "lead")]
me_dates <- me_dates[!is.na(next_me)]

# 월별 수익률: me_date ~ next_me 구간 수익률
cat("[1b] 월별 수익률 계산...\n")
monthly_ret <- lapply(seq_len(nrow(me_dates)), function(i) {
  d0 <- me_dates$me_date[i]; d1 <- me_dates$next_me[i]
  sub <- RAWDATA[Date > d0 & Date <= d1, .(ret = prod(1 + Ret) - 1), by = Ticker]
  sub[, sig_date := d0]
  sub
})
monthly_ret <- rbindlist(monthly_ret)
setkey(monthly_ret, sig_date, Ticker)

# 유동성 필터: sig_date 기준 20d 평균 거래대금
cat("[1c] 유동성 필터...\n")
RAWDATA[, Vol_KRW := Vol * Close]
liq_dt <- RAWDATA[, .(
  avg_vol20 = mean(tail(Vol_KRW, 20L), na.rm = TRUE)
), by = .(ym, Ticker)]
me_liq <- merge(me_dates[, .(ym, me_date)], liq_dt, by = "ym")
me_liq <- me_liq[avg_vol20 >= LIQ_THRESH]
setnames(me_liq, "me_date", "sig_date")
setkey(me_liq, sig_date, Ticker)
rm(RAWDATA, BM_DT, rw); gc()
cat(sprintf("    월별 수익 rows: %s | 유동성 통과: %s\n",
            format(nrow(monthly_ret), big.mark = ","),
            format(nrow(me_liq), big.mark = ",")))

# =============================================================================
# [2] 월간 Factor DB 로드 (OOS 기간)
# =============================================================================
cat("\n[2] 월간 FDB 로드...\n")
oos_me <- me_dates[me_date >= OOS_START & me_date <= OOS_END]
fdb_files <- list.files(FDB_DIR, "^factor_db_\\d{6}\\.parquet$", full.names = TRUE)

fdb_list <- lapply(seq_len(nrow(oos_me)), function(i) {
  sig_d <- oos_me$me_date[i]
  ym_tag <- format(sig_d, "%Y%m")
  fpath <- file.path(FDB_DIR, paste0("factor_db_", ym_tag, ".parquet"))
  if (!file.exists(fpath)) return(NULL)
  dt <- as.data.table(read_parquet(fpath))
  dt[, sig_date := sig_d]
  dt[Coverage == TRUE, .(sig_date, Ticker, Factor_Name, Z_Score)]
})
fdb_all <- rbindlist(Filter(Negate(is.null), fdb_list), fill = TRUE)
rm(fdb_list); gc()
cat(sprintf("    FDB rows: %s | dates: %d | factors: %d\n",
            format(nrow(fdb_all), big.mark = ","),
            uniqueN(fdb_all$sig_date), uniqueN(fdb_all$Factor_Name)))

# =============================================================================
# [3] Baseline: C19 only → top-N → SR
# =============================================================================
cat("\n[3] Baseline C19...\n")
c19_dt <- fdb_all[Factor_Name == BASELINE_FAC, .(sig_date, Ticker, z_c19 = Z_Score)]

# 유동성 필터 적용
c19_dt <- merge(c19_dt, me_liq[, .(sig_date, Ticker)], by = c("sig_date", "Ticker"))

# 날짜별 top-N
c19_dt[, rnk := frank(-z_c19, ties.method = "first"), by = sig_date]
base_port <- c19_dt[rnk <= N_TOP, .(sig_date, Ticker)]

# next-month return
base_port <- merge(base_port, monthly_ret, by = c("sig_date", "Ticker"))
base_monthly <- base_port[, .(port_ret = mean(ret, na.rm = TRUE)), by = sig_date]
setorder(base_monthly, sig_date)

base_sr <- mean(base_monthly$port_ret) / sd(base_monthly$port_ret) * sqrt(12)
base_cagr <- (prod(1 + base_monthly$port_ret))^(12 / nrow(base_monthly)) - 1
base_cum <- cumprod(1 + base_monthly$port_ret)
base_mdd <- min(base_cum / cummax(base_cum) - 1)
cat(sprintf("  C19 baseline: SR=%.4f CAGR=%.1f%% MDD=%.1f%% (N=%d months)\n",
            base_sr, base_cagr * 100, base_mdd * 100, nrow(base_monthly)))

# =============================================================================
# [4] Systematic Scan: C19 + each candidate → SR delta
# =============================================================================
cat("\n[4] Systematic scan (%d factors)...\n", uniqueN(fdb_all$Factor_Name))

all_factors <- setdiff(unique(fdb_all$Factor_Name), BASELINE_FAC)
cat(sprintf("    Scanning %d candidates against C19 baseline...\n", length(all_factors)))

# Pivot C19 for merge
c19_wide <- fdb_all[Factor_Name == BASELINE_FAC, .(sig_date, Ticker, z_c19 = Z_Score)]

scan_results <- rbindlist(lapply(all_factors, function(f) {
  # Get candidate factor
  cand <- fdb_all[Factor_Name == f, .(sig_date, Ticker, z_cand = Z_Score)]

  # Merge with C19
  combo <- merge(c19_wide, cand, by = c("sig_date", "Ticker"))
  if (nrow(combo) < 1000L) return(NULL)

  # Liquidity filter
  combo <- merge(combo, me_liq[, .(sig_date, Ticker)], by = c("sig_date", "Ticker"))
  if (nrow(combo) < 500L) return(NULL)

  # Combined score: z_c19 + z_cand (equal weight)
  combo[, z_combo := z_c19 + z_cand]

  # Top-N selection
  combo[, rnk := frank(-z_combo, ties.method = "first"), by = sig_date]
  port <- combo[rnk <= N_TOP, .(sig_date, Ticker)]

  # Monthly returns
  port <- merge(port, monthly_ret, by = c("sig_date", "Ticker"))
  port_m <- port[, .(port_ret = mean(ret, na.rm = TRUE)), by = sig_date]
  setorder(port_m, sig_date)

  if (nrow(port_m) < 24L) return(NULL)

  sr <- mean(port_m$port_ret) / sd(port_m$port_ret) * sqrt(12)
  cagr <- (prod(1 + port_m$port_ret))^(12 / nrow(port_m)) - 1
  cum <- cumprod(1 + port_m$port_ret)
  mdd <- min(cum / cummax(cum) - 1)

  # Correlation with C19 (cross-sectional average)
  corr_avg <- combo[, .(cc = tryCatch(cor(z_c19, z_cand, use = "complete.obs"),
                                       error = function(e) NA_real_)), by = sig_date]
  avg_corr <- mean(corr_avg$cc, na.rm = TRUE)

  # Portfolio overlap with baseline
  port[, key := paste(sig_date, Ticker)]
  base_port_tmp <- c19_dt[rnk <= N_TOP, .(sig_date, Ticker)]
  base_port_tmp[, key := paste(sig_date, Ticker)]
  overlap <- length(intersect(port$key, base_port_tmp$key)) / nrow(port)

  data.table(
    factor_name = f,
    sr = round(sr, 4),
    sr_delta = round(sr - base_sr, 4),
    cagr = round(cagr * 100, 2),
    mdd = round(mdd * 100, 2),
    corr_with_c19 = round(avg_corr, 3),
    overlap_pct = round(overlap * 100, 1),
    n_months = nrow(port_m)
  )
}))

cat(sprintf("    Scan 완료: %d factors evaluated\n", nrow(scan_results)))

# =============================================================================
# [5] 결과 정렬 + 저장
# =============================================================================
cat("\n[5] 결과...\n")
setorder(scan_results, -sr_delta)

cat("\n=== TOP 20 Marginal SR Improvement ===\n")
print(head(scan_results, 20))

cat("\n=== BOTTOM 10 (SR 악화) ===\n")
print(tail(scan_results, 10))

cat(sprintf("\n[Summary] Baseline SR=%.4f | SR 개선 팩터: %d/%d (%.0f%%)\n",
            base_sr, sum(scan_results$sr_delta > 0), nrow(scan_results),
            100 * mean(scan_results$sr_delta > 0)))

# 저장
fwrite(scan_results, file.path(OUTPUT_DIR, "marginal_scan_results.csv"))

# Top candidates (SR 개선 + MDD 개선 + 낮은 상관)
synergy <- scan_results[sr_delta > 0 & mdd > base_mdd * 100 & corr_with_c19 < 0.3]
setorder(synergy, -sr_delta)
cat(sprintf("\n=== SYNERGY CANDIDATES (SR+, MDD+, corr<0.3): %d개 ===\n", nrow(synergy)))
if (nrow(synergy) > 0) print(head(synergy, 15))

fwrite(synergy, file.path(OUTPUT_DIR, "synergy_candidates.csv"))

cat(sprintf("\n=== 완료 (%s) ===\n", Sys.time()))
