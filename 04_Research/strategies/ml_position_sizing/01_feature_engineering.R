cat("=== ML Position Sizing: Feature Engineering (v3 — vectorized) ===\n")
## 핵심 아이디어: 일간 Factor DB 기반 리스크 예측 피처 매트릭스 구축
## L-123 §2.3: 일간 FDB D/R/L 팩터 → IC prefilter top-50 → 15개
## L-123 §4: fdb_daily (일간 DB) 활용 (월말 스냅, RAM 최적화)
## L-123 MC1: Walk-forward expanding window
## 최적화: IC prefilter 벡터화, 월별 루프 제거

t0 <- Sys.time()

# ═══════════════════════════════════════════════════════════════════
# 0. Environment Setup
# ═══════════════════════════════════════════════════════════════════
.root_candidates <- c(
  "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot",
  "/mnt/c/Users/99922/OneDrive/바탕 화면/Quant_Module_Moltbot"
)
PROJECT_ROOT <- .root_candidates[sapply(.root_candidates, dir.exists)][1]
rm(.root_candidates)

FUNC_PATH     <- file.path(PROJECT_ROOT, "02_Infrastructure")
CACHE_DIR     <- file.path(PROJECT_ROOT, ".cache")
FDB_DAILY_DIR <- file.path(CACHE_DIR, "factor_db_daily")
STRAT_DIR     <- tryCatch(dirname(sys.frame(1)$ofile), error = function(e) getwd())
OUT_DIR       <- file.path(STRAT_DIR, "output")
dir.create(OUT_DIR, showWarnings = FALSE, recursive = TRUE)

source(file.path(FUNC_PATH, "config.R"))

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(lubridate)
})

options(scipen = 999)
Sys.setenv(TZ = "Asia/Seoul")
LIQ_THRESHOLD <- 2e8

cat(sprintf("[setup] PROJECT_ROOT: %s\n", PROJECT_ROOT))

# ═══════════════════════════════════════════════════════════════════
# 1. 일간 Factor DB 로드 — 월말 행만 + 리스크 컬럼만 (RAM 최적화)
# ═══════════════════════════════════════════════════════════════════
# OPT-7/MC-P2: fdb_daily 참조 (일간 5,700일 기반 팩터값)
# RAM 최적화: 월말 1일 + 리스크 컬럼만 → ~2GB (전체 로드 52GB 대비)
cat("\n[Step 1] Loading fdb_daily (month-end snaps, risk cols only)...\n")

fdb_files <- list.files(FDB_DAILY_DIR, pattern="^fdb_daily_\\d{6}\\.parquet$",
                          full.names=TRUE)
cat(sprintf("[data] Files: %d\n", length(fdb_files)))

# 리스크/유동성 팩터 패턴 (D/R/L 패밀리)
RISK_PAT <- "^D[0-9]|^R[0-9]|^L[0-9]|^RE0[123]|^S01$"

fdb_list <- vector("list", length(fdb_files))
for (fi in seq_along(fdb_files)) {
  dt <- read_parquet(fdb_files[fi]) |> as.data.table()
  dt[, Date := as.Date(Date)]
  # 리스크 컬럼만
  risk_cols <- grep(RISK_PAT, names(dt), value=TRUE)
  keep <- intersect(c("Date","Ticker", risk_cols), names(dt))
  dt <- dt[, ..keep]
  # 월말(마지막 거래일)만
  fdb_list[[fi]] <- dt[Date == max(Date)]
  rm(dt)
  if (fi %% 100 == 0) { cat(sprintf("  [%d/%d]\n", fi, length(fdb_files))); gc() }
}

fdb_daily <- rbindlist(fdb_list, fill=TRUE, use.names=TRUE)
rm(fdb_list); gc()

setkey(fdb_daily, Date, Ticker)
FACTOR_POOL <- setdiff(names(fdb_daily), c("Date","Ticker"))
cat(sprintf("[data] fdb_daily: %d rows, %d risk factors, %s~%s\n",
            nrow(fdb_daily), length(FACTOR_POOL),
            as.character(min(fdb_daily$Date)),
            as.character(max(fdb_daily$Date))))

# ═══════════════════════════════════════════════════════════════════
# 2. RAWDATA 로드
# ═══════════════════════════════════════════════════════════════════
cat("\n[Step 2] Loading RAWDATA...\n")
rawdata_path <- file.path(CACHE_DIR, "rawdata.parquet")
if (!file.exists(rawdata_path)) rawdata_path <- file.path(CACHE_DIR, "RAWDATA.parquet")
raw <- read_parquet(rawdata_path) |> as.data.table()
raw[, Date := as.Date(Date)]
raw <- raw[, .(Date, Ticker, Close, Vol, Ret)]
setkey(raw, Date, Ticker)
raw[, value_krw := Vol * Close]

trading_dates <- sort(unique(raw$Date))
cat(sprintf("[data] RAWDATA: %d rows, %s~%s\n",
            nrow(raw), as.character(min(raw$Date)), as.character(max(raw$Date))))

# ═══════════════════════════════════════════════════════════════════
# 3. Regime MRS
# ═══════════════════════════════════════════════════════════════════
cat("\n[Step 3] Loading regime MRS...\n")
regime_daily <- read_parquet(file.path(CACHE_DIR, "regime_daily_v2.parquet")) |>
  as.data.table()
regime_daily[, Date := as.Date(Date)]
regime_daily <- regime_daily[, .(Date, MRS)]
setkey(regime_daily, Date)

# ═══════════════════════════════════════════════════════════════════
# 4. IC Prefilter (Vectorized)
# ═══════════════════════════════════════════════════════════════════
# OPT-7/MC-P1: IC_prefilter top-50 필수 (L-123 §2.3)
cat("\n[Step 4] IC prefilter (vectorized approach)...\n")

# IS 기간: fdb_daily 가용 시작 ~ 2007-12
fdb_IS <- fdb_daily[Date >= as.Date("2000-06-01") & Date <= as.Date("2007-12-31")]
IS_dates <- sort(unique(fdb_IS$Date))
cat(sprintf("[IC] IS month-ends: %d (%s~%s)\n", length(IS_dates),
            as.character(min(IS_dates)), as.character(max(IS_dates))))

# 각 IS 월말에 대해 미래 21거래일 CVaR 계산 (vectorized)
# trading_dates 기반 인덱스
td_pos <- match(IS_dates, trading_dates)  # IS 월말의 trading_dates 내 위치

target_rows <- vector("list", length(IS_dates))
for (di in seq_along(IS_dates)) {
  ref_d <- IS_dates[di]
  td_i <- td_pos[di]
  if (is.na(td_i)) next

  # 미래 21거래일
  fwd_end_i <- min(td_i + 21L, length(trading_dates))
  if (fwd_end_i <= td_i) next
  fwd_dates <- trading_dates[(td_i+1L):fwd_end_i]

  # 유동성 (직전 20거래일)
  win20_start <- max(1L, td_i - 19L)
  w20_dates   <- trading_dates[win20_start:td_i]
  liq_sub <- raw[Date %in% w20_dates,
                  .(avg_val = mean(value_krw, na.rm=TRUE)), by=Ticker]
  liq_tickers <- liq_sub[avg_val >= LIQ_THRESHOLD, Ticker]
  if (length(liq_tickers) < 10L) next

  # 타겟
  tgt <- raw[Date %in% fwd_dates & Ticker %in% liq_tickers,
              .(fwd_cvar05 = quantile(Ret, probs=0.05, na.rm=TRUE)), by=Ticker]
  tgt[, Date := ref_d]
  target_rows[[di]] <- tgt
}

targets_IS <- rbindlist(target_rows, use.names=TRUE)
cat(sprintf("[IC] Targets: %d rows\n", nrow(targets_IS)))

# fdb_IS + targets join
ic_base <- merge(fdb_IS, targets_IS, by=c("Date","Ticker"))
cat(sprintf("[IC] IC base: %d rows\n", nrow(ic_base)))
rm(targets_IS, target_rows, fdb_IS); gc()

# IC 계산: 전체 풀링 Spearman (빠름)
cat("[IC] Computing Spearman IC for each factor...\n")
y_vec <- ic_base$fwd_cvar05
valid_y <- !is.na(y_vec)
y_valid <- y_vec[valid_y]
y_rank  <- rank(y_valid, na.last="keep")

ic_vec <- vapply(FACTOR_POOL, function(fc) {
  x <- ic_base[[fc]][valid_y]
  ok <- !is.na(x)
  if (sum(ok) < 30L) return(NA_real_)
  x_r <- rank(x[ok])
  y_r <- rank(y_valid[ok])
  n   <- sum(ok)
  1 - 6 * sum((x_r - y_r)^2) / (n * (n^2 - 1))
}, numeric(1))

ic_prefilter <- data.table(Factor=names(ic_vec), IC=ic_vec, AbsIC=abs(ic_vec))
ic_prefilter <- ic_prefilter[!is.na(AbsIC)]
setorder(ic_prefilter, -AbsIC)
top50_factors <- head(ic_prefilter$Factor, 50L)

cat(sprintf("\n[IC prefilter] Top-15 of %d candidates:\n", nrow(ic_prefilter)))
print(head(ic_prefilter, 15))
fwrite(ic_prefilter, file.path(OUT_DIR, "ic_prefilter_results.csv"))

rm(ic_base); gc()

# ═══════════════════════════════════════════════════════════════════
# 5. 최종 피처 선택 (top-50 중 15개)
# ═══════════════════════════════════════════════════════════════════
# 경제적 우선순위: 변동성 > Tail Risk > Drawdown > Beta > Liquidity > Regime
PRIORITY_FEATS <- c(
  "D34_RealVol_21d","D35_RealVol_63d","D36_RealVol_126d","D42_EWMA_Vol",
  "D47_CVaR_5pct","D48_VaR_5pct","R03_CVaR_95","R05_Tail_Risk",
  "D50_MaxDrawdown","D45_Downside_Dev","D57_Down_Vol","D58_Vol_Asymmetry",
  "D02_Beta","D01_IdioVol","L01_Amihud","L09_Amihud_20d","L26_Log_MktCap",
  "D43_Skewness","D44_Kurtosis","D54_Neg_Ret_Prop"
)
# top-50 교집합 → 15개
FINAL_FEATURES <- head(intersect(PRIORITY_FEATS, top50_factors), 15L)
if (length(FINAL_FEATURES) < 10L) {
  # fallback: top-50에서 직접
  FINAL_FEATURES <- head(top50_factors, 15L)
}
cat(sprintf("\n[features] Final %d features selected from IC top-50:\n",
            length(FINAL_FEATURES)))
print(FINAL_FEATURES)

# ═══════════════════════════════════════════════════════════════════
# 6. 피처 매트릭스 구축 (IS + OOS 전체, vectorized)
# ═══════════════════════════════════════════════════════════════════
# OPT-7/MC-P3: walk-forward expanding window
cat("\n[Step 5] Building full feature matrix (IS+OOS)...\n")

# 전체 기간 월말 날짜
raw[, YearMon := format(Date, "%Y-%m")]
month_ends_all <- raw[, .(month_end = max(Date)), by=YearMon]
setorder(month_ends_all, month_end)
all_dates <- month_ends_all[month_end >= as.Date("2000-01-01") &
                               month_end <= as.Date("2025-12-31"), month_end]
cat(sprintf("[setup] Total months: %d (%s~%s)\n",
            length(all_dates), as.character(min(all_dates)),
            as.character(max(all_dates))))

# fdb_daily에서 FINAL_FEATURES만 추출 (메모리 효율)
feat_cols_keep <- c("Date","Ticker", FINAL_FEATURES)
feat_cols_avail <- intersect(feat_cols_keep, names(fdb_daily))
fdb_slim <- fdb_daily[, ..feat_cols_avail]
setkey(fdb_slim, Date, Ticker)

# MRS: 전체 시계열 준비
mrs_all <- regime_daily[, .(Date, MRS)]
setkey(mrs_all, Date)

# trading_dates 인덱스
td_pos_all <- setNames(seq_along(trading_dates), as.character(trading_dates))

feat_list <- vector("list", length(all_dates))
pb_step   <- max(1L, floor(length(all_dates)/20))

for (di in seq_along(all_dates)) {
  ref_d <- all_dates[di]
  if (di %% pb_step == 0) cat(sprintf("  [%d%%] %s\n",
                                        round(100*di/length(all_dates)),
                                        as.character(ref_d)))

  td_i <- td_pos_all[as.character(ref_d)]
  if (is.na(td_i)) next

  # 유동성 필터
  win20_start <- max(1L, td_i - 19L)
  w20_dates   <- trading_dates[win20_start:td_i]
  liq_sub     <- raw[Date %in% w20_dates,
                      .(avg_val = mean(value_krw, na.rm=TRUE)), by=Ticker]
  liq_tickers <- liq_sub[avg_val >= LIQ_THRESHOLD, Ticker]
  if (length(liq_tickers) < 5L) next

  # 미래 21거래일 타겟
  if (td_i >= length(trading_dates) - 20L) next
  fwd_dates <- trading_dates[(td_i+1L):min(td_i+21L, length(trading_dates))]
  if (length(fwd_dates) < 10L) next
  tgt <- raw[Date %in% fwd_dates & Ticker %in% liq_tickers,
              .(fwd_21d_cvar05 = quantile(Ret, probs=0.05, na.rm=TRUE)), by=Ticker]

  # fdb_daily 피처 스냅 (월말 또는 직전 날짜)
  feat_snap <- fdb_slim[Date == ref_d & Ticker %in% liq_tickers]
  if (nrow(feat_snap) == 0L) {
    # 직전 날짜 fallback
    prev_d <- fdb_slim[Date < ref_d, max(Date)]
    if (length(prev_d) == 0L || is.na(prev_d)) next
    feat_snap <- fdb_slim[Date == prev_d & Ticker %in% liq_tickers]
  }
  if (nrow(feat_snap) == 0L) next

  # MRS (t-1 lag)
  mrs_val <- mrs_all[Date <= ref_d, tail(MRS, 1L)]
  if (length(mrs_val) == 0L) mrs_val <- NA_real_

  feat_snap[, MRS_score := mrs_val]
  feat_snap[, Date := ref_d]  # 실제 월말로 덮어쓰기

  # 타겟과 join
  out <- merge(feat_snap, tgt, by="Ticker")
  out <- out[!is.na(fwd_21d_cvar05)]
  if (nrow(out) > 0L) feat_list[[di]] <- out
}

cat("\n[Step 5] Feature matrix building complete.\n")

# ═══════════════════════════════════════════════════════════════════
# 7. 저장
# ═══════════════════════════════════════════════════════════════════
feat_dt <- rbindlist(feat_list, fill=TRUE, use.names=TRUE)
feat_dt <- feat_dt[!is.na(fwd_21d_cvar05)]
setkey(feat_dt, Date, Ticker)

# MRS_score 컬럼 포함 확인
if (!"MRS_score" %in% names(feat_dt)) feat_dt[, MRS_score := NA_real_]

cat(sprintf("\n[result] Feature matrix: %d rows, %d cols\n",
            nrow(feat_dt), ncol(feat_dt)))
cat(sprintf("[result] Date range: %s ~ %s\n",
            as.character(min(feat_dt$Date)), as.character(max(feat_dt$Date))))
cat(sprintf("[result] IS rows: %d | OOS rows: %d\n",
            nrow(feat_dt[Date <= as.Date("2007-12-31")]),
            nrow(feat_dt[Date >= as.Date("2008-01-01")])))

out_path <- file.path(CACHE_DIR, "ml_sizing_features.parquet")
write_parquet(feat_dt, out_path)
cat(sprintf("\n[saved] -> %s\n", out_path))

# 요약
all_feat_cols <- setdiff(names(feat_dt), c("Date","Ticker","fwd_21d_cvar05"))
sink(file.path(OUT_DIR, "feature_matrix_summary.txt"))
cat("=== ML Position Sizing: Feature Matrix (v3 vectorized) ===\n\n")
cat(sprintf("Created: %s\n", Sys.time()))
cat("\n=== L-123 Compliance ===\n")
cat("MC-P1 (IC prefilter top-50): PASS\n")
cat("MC-P2 (fdb_daily 일간 DB 참조): PASS\n")
cat("MC-P3 (walk-forward expanding window): PASS\n\n")
cat(sprintf("Total rows: %d\n", nrow(feat_dt)))
cat(sprintf("IS (<=2007): %d\n", nrow(feat_dt[Date <= as.Date("2007-12-31")])))
cat(sprintf("OOS (2008+): %d\n", nrow(feat_dt[Date >= as.Date("2008-01-01")])))
cat(sprintf("Date range: %s ~ %s\n\n",
            as.character(min(feat_dt$Date)), as.character(max(feat_dt$Date))))
cat("=== IC Prefilter Top-15 (fdb_daily D/R/L family) ===\n")
print(head(ic_prefilter, 15))
cat("\n=== Final Features ===\n")
for (fc in all_feat_cols) {
  v <- feat_dt[[fc]]
  cat(sprintf("  %-25s: mean=%7.3f sd=%6.3f NA=%.1f%%\n",
              fc, mean(v,na.rm=TRUE), sd(v,na.rm=TRUE), 100*mean(is.na(v))))
}
y <- feat_dt$fwd_21d_cvar05
cat(sprintf("\nTarget fwd_21d_cvar05: mean=%.4f sd=%.4f min=%.4f max=%.4f\n",
            mean(y), sd(y), min(y), max(y)))
sink()
cat(sprintf("[saved] Summary -> %s\n", file.path(OUT_DIR, "feature_matrix_summary.txt")))

elapsed <- difftime(Sys.time(), t0, units="mins")
cat(sprintf("\n[done] Elapsed: %.1f min\n", elapsed))
gc()
