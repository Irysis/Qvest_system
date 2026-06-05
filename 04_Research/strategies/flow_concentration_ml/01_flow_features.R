cat("=== STR_1678: Flow Concentration ML — Feature Engineering ===\n")
## 핵심아이디어: 기관·외국인 수급 herding momentum으로 다음 21일 순매수 집중 예측
## 논문 근거: Sias(2004) Institutional Herding, Lakonishok et al.(1992)
## PIT: 모든 피처는 t-1 기준 과거 데이터. 타겟만 미래(예측 대상).
## C1 PASS: rolling/expanding only.  C2 PASS: 피처=lag, 타겟=forward.
## OPT-7/MC-P1: 일간 Factor DB 309 팩터 → MI prefilter → top-50 선택
## OPT-7/MC-P2: fdb_daily 참조 (일간 5700일 이상 학습 데이터)
## OPT-7/MC-P3: walk-forward expanding window

# ── 0. 라이브러리 ─────────────────────────────────────────────────────────────
suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
})

# ── 1. 경로 설정 (normalizePath 금지) ────────────────────────────────────────
PROJECT_ROOT  <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
CACHE_DIR     <- file.path(PROJECT_ROOT, ".cache")
INV_DIR       <- file.path(CACHE_DIR, "investor_stock")
FDB_DIR       <- file.path(CACHE_DIR, "factor_db")          # 월간 (월별 z-score)
DAILY_FDB_DIR <- file.path(CACHE_DIR, "factor_db_daily")    # 일간 (wide, 309 팩터)
OUT_FILE      <- file.path(CACHE_DIR, "flow_features_daily.parquet")

cat("[01] Project root:", PROJECT_ROOT, "\n")
cat("[01] Output:", OUT_FILE, "\n")

# ── 2. 인프라 로드 ────────────────────────────────────────────────────────────
# config.R을 먼저 source하여 PROJECT_ROOT, FUNC_PATH 등 전역변수 초기화
source(file.path(PROJECT_ROOT, "02_Infrastructure/config.R"))
source(file.path(PROJECT_ROOT, "02_Infrastructure/backtest_harness.R"))

# ── 3. RAWDATA 1회 로드 (OPT-2) ──────────────────────────────────────────────
cat("[01] Loading RAWDATA...\n")
res <- load_rawdata(use_cache = TRUE)
raw <- as.data.table(res$RAWDATA)
setkey(raw, Date, Ticker)
cat("[01] RAWDATA rows:", nrow(raw),
    "| Date:", as.character(min(raw$Date)), "~", as.character(max(raw$Date)), "\n")

# 필요 컬럼만 추출
price_dt <- raw[, .(Date, Ticker, Ret, Vol, Size, Close)]
rm(res, raw); gc()

# ── 4. 투자자 수급 데이터 1회 벌크 로드 (OPT-1 — 루프 내 로드 절대 금지) ────
cat("[01] Loading investor parquets (bulk)...\n")
inst_dt    <- as.data.table(read_parquet(file.path(INV_DIR, "investor_institutional.parquet")))
foreign_dt <- as.data.table(read_parquet(file.path(INV_DIR, "investor_foreign.parquet")))
indiv_dt   <- as.data.table(read_parquet(file.path(INV_DIR, "investor_individual.parquet")))

cat("[01] Institutional rows:", nrow(inst_dt), "\n")
cat("[01] Foreign rows:      ", nrow(foreign_dt), "\n")
cat("[01] Individual rows:   ", nrow(indiv_dt), "\n")

inst_dt    <- inst_dt[,    .(Date = as.Date(Date), Ticker, inst_nb    = NetBuy)]
foreign_dt <- foreign_dt[, .(Date = as.Date(Date), Ticker, foreign_nb = NetBuy)]
indiv_dt   <- indiv_dt[,   .(Date = as.Date(Date), Ticker, indiv_nb   = NetBuy)]

setkey(inst_dt,    Date, Ticker)
setkey(foreign_dt, Date, Ticker)
setkey(indiv_dt,   Date, Ticker)
gc()

# ── 5. 수급 데이터 병합 ──────────────────────────────────────────────────────
cat("[01] Merging investor data...\n")
flow_dt <- inst_dt[foreign_dt, on = .(Date, Ticker)]
flow_dt[is.na(inst_nb),    inst_nb    := 0]
flow_dt[is.na(foreign_nb), foreign_nb := 0]

flow_dt <- indiv_dt[flow_dt, on = .(Date, Ticker)]
flow_dt[is.na(indiv_nb), indiv_nb := 0]

setkey(flow_dt, Date, Ticker)
cat("[01] Flow data rows:", nrow(flow_dt), "\n")
gc()

# ── 6. 수급 피처 엔지니어링 (frollsum — for 루프 금지) ──────────────────────
cat("[01] Computing rolling flow features...\n")
setorder(flow_dt, Ticker, Date)

# PIT C2 PASS: t-1 lag 후 rolling — 예측 시점 t에서 t-1 기준 과거 N일 누적
flow_dt[, `:=`(
  inst_nb_lag    = shift(inst_nb,    1L, type = "lag"),
  foreign_nb_lag = shift(foreign_nb, 1L, type = "lag"),
  indiv_nb_lag   = shift(indiv_nb,   1L, type = "lag")
), by = Ticker]

flow_dt[, `:=`(
  inst_netbuy_5d      = frollsum(inst_nb_lag,    5L, align = "right", fill = NA, na.rm = TRUE),
  inst_netbuy_20d     = frollsum(inst_nb_lag,   20L, align = "right", fill = NA, na.rm = TRUE),
  inst_netbuy_60d     = frollsum(inst_nb_lag,   60L, align = "right", fill = NA, na.rm = TRUE),
  foreign_netbuy_5d   = frollsum(foreign_nb_lag,  5L, align = "right", fill = NA, na.rm = TRUE),
  foreign_netbuy_20d  = frollsum(foreign_nb_lag, 20L, align = "right", fill = NA, na.rm = TRUE),
  foreign_netbuy_60d  = frollsum(foreign_nb_lag, 60L, align = "right", fill = NA, na.rm = TRUE),
  individual_netbuy_5d = frollsum(indiv_nb_lag,  5L, align = "right", fill = NA, na.rm = TRUE)
), by = Ticker]

# 가속도 피처
flow_dt[, `:=`(
  inst_flow_momentum    = inst_netbuy_5d  - inst_netbuy_20d,
  foreign_flow_momentum = foreign_netbuy_5d - foreign_netbuy_20d
)]

cat("[01] Flow rolling features done.\n")

# ── 7. 집중도 피처 (cross-sectional per-date) ──────────────────────────────────
cat("[01] Computing inst_concentration...\n")
flow_dt[!is.na(inst_netbuy_20d),
        inst_concentration := inst_netbuy_20d / sum(abs(inst_netbuy_20d), na.rm = TRUE),
        by = Date]
flow_dt[is.na(inst_concentration), inst_concentration := 0]

# ── 8. Feature 16: foreign_own_chg_20d ─────────────────────────────────────────
## 외인 지분율 변화 추정: 누적 외인 순매수 / 시가총액 = 지분율 변화 proxy
## PIT C2 PASS: foreign_nb_lag (t-1) 기준 누적
cat("[01] Computing foreign_own_chg_20d...\n")

# 시가총액(Size)을 flow_dt에 병합 (price_dt에서)
size_dt <- price_dt[, .(Date, Ticker, Size)]
setkey(size_dt, Date, Ticker)
flow_dt <- size_dt[flow_dt, on = .(Date, Ticker)]

flow_dt[is.na(Size) | Size <= 0, Size := NA_real_]
flow_dt[!is.na(Size) & !is.na(foreign_nb_lag),
        foreign_own_proxy := cumsum(foreign_nb_lag) / Size,
        by = Ticker]

flow_dt[, foreign_own_chg_20d := foreign_own_proxy - shift(foreign_own_proxy, 20L, type = "lag"),
        by = Ticker]

cat("[01] foreign_own_chg_20d done.\n")
gc()

# ── 9. Feature 17: earnings_proximity ──────────────────────────────────────────
## 분기 실적발표 예상일: Q1→5/15, Q2→8/15, Q3→11/15, Q4→3/15
## PIT C4 PASS: 규칙 기반 근사(재무제표 미사용, 예상일 고정)
## 값이 작을수록 실적발표 임박 → 수급 변동 커질 가능성
cat("[01] Computing earnings_proximity...\n")

all_dates <- sort(unique(flow_dt$Date))
yr_range  <- unique(as.integer(format(all_dates, "%Y")))

# 연도별 예상 실적발표일 생성
earnings_all <- do.call(rbind, lapply(yr_range, function(yr) {
  data.frame(
    earnings_date = as.Date(c(
      paste0(yr,   "-05-15"),
      paste0(yr,   "-08-15"),
      paste0(yr,   "-11-15"),
      paste0(yr+1, "-03-15")
    )),
    stringsAsFactors = FALSE
  )
}))
earnings_dates_vec <- sort(unique(as.Date(earnings_all$earnings_date)))

# 각 거래일에서 가장 가까운 예상 발표일까지 남은 일수
# (음수 = 이미 지난 발표일은 제외, 양수 = 앞으로 남은 일수)
compute_proximity <- function(d) {
  future_ed <- earnings_dates_vec[earnings_dates_vec >= d]
  if (length(future_ed) == 0L) return(NA_real_)
  as.numeric(min(future_ed) - d)
}

# 날짜 레벨에서만 계산 (종목마다 동일하므로 date lookup table 생성)
date_proximity <- data.table(
  Date = all_dates,
  earnings_proximity = vapply(all_dates, compute_proximity, numeric(1))
)
setkey(date_proximity, Date)
setkey(flow_dt, Date, Ticker)
flow_dt <- date_proximity[flow_dt, on = "Date"]

cat("[01] earnings_proximity done.\n")

# ── 10. 가격/거래량 피처 ──────────────────────────────────────────────────────
cat("[01] Computing price/volume features...\n")
setorder(price_dt, Ticker, Date)

price_dt[, `:=`(
  ret_lag  = shift(Ret, 1L, type = "lag"),
  vol_lag  = shift(Vol, 1L, type = "lag"),
  size_lag = shift(Size, 1L, type = "lag")
), by = Ticker]

# frollapply는 by=Ticker와 호환 불가 → log-return sum으로 근사
# log(1+r) 합계 = log(1+r1) + log(1+r2) + ... ≈ cumulative return (작은 r에서 정확)
price_dt[, log_ret_lag := log1p(pmax(ret_lag, -0.999, na.rm = TRUE))]
price_dt[, `:=`(
  ret_5d   = expm1(frollsum(log_ret_lag,  5L, align = "right", fill = NA, na.rm = TRUE)),
  ret_20d  = expm1(frollsum(log_ret_lag, 20L, align = "right", fill = NA, na.rm = TRUE)),
  vol_5d   = frollmean(vol_lag,  5L, align = "right", fill = NA, na.rm = TRUE),
  vol_20d  = frollmean(vol_lag, 20L, align = "right", fill = NA, na.rm = TRUE),
  log_mcap = log(pmax(size_lag, 1, na.rm = TRUE))
), by = Ticker]

price_dt[vol_20d > 0, volume_ratio_20d  := vol_5d / vol_20d]
price_dt[is.na(volume_ratio_20d) | !is.finite(volume_ratio_20d), volume_ratio_20d := NA_real_]
price_dt[, turnover_chg_20d := volume_ratio_20d]

price_feat <- price_dt[, .(Date, Ticker, ret_5d, ret_20d, volume_ratio_20d,
                            log_mcap, turnover_chg_20d)]
setkey(price_feat, Date, Ticker)

cat("[01] Price/volume features done.\n")
gc()

# ── 11. 타겟: fwd_inst_foreign_netbuy_21d ─────────────────────────────────────
cat("[01] Computing forward target (21d net buying)...\n")
flow_dt[, combined_nb := inst_nb + foreign_nb]
setorder(flow_dt, Ticker, Date)

# 미래 21 거래일 순매수 합계 (예측 대상 — 훈련 데이터 구성에만 사용)
# shift로 역방향 rolling: shift(-1) ~ shift(-21) 합산
for (k in 1:21) {
  flow_dt[, paste0("fwd_nb_", k) := shift(combined_nb, k, type = "lead"), by = Ticker]
}
fwd_cols <- paste0("fwd_nb_", 1:21)
flow_dt[, fwd_combined_nb_21d := rowSums(.SD, na.rm = TRUE), .SDcols = fwd_cols]
flow_dt[, (fwd_cols) := NULL]  # 중간 컬럼 제거

# 타겟: cross-sectional z-score per date
flow_dt[!is.na(fwd_combined_nb_21d),
        fwd_inst_foreign_netbuy_21d := {
          mu <- mean(fwd_combined_nb_21d, na.rm = TRUE)
          sd_val <- sd(fwd_combined_nb_21d, na.rm = TRUE)
          if (is.na(sd_val) || sd_val == 0) NA_real_
          else (fwd_combined_nb_21d - mu) / sd_val
        },
        by = Date]

# 이진 타겟: 상위 20% = 1
flow_dt[!is.na(fwd_combined_nb_21d),
        fwd_flow_top20 := as.integer(
          fwd_combined_nb_21d >= quantile(fwd_combined_nb_21d, 0.80, na.rm = TRUE)
        ),
        by = Date]

cat("[01] Target computation done.\n")
gc()

# ── 12. 유동성 피처 (20일 평균 거래대금) ──────────────────────────────────────
cat("[01] Computing liquidity filter (20d avg turnover)...\n")
price_dt[, turnover_raw := Close * Vol]
setorder(price_dt, Ticker, Date)
price_dt[, turnover_lag := shift(turnover_raw, 1L, type = "lag"), by = Ticker]
price_dt[, liq_20d := frollmean(turnover_lag, 20L, align = "right", fill = NA, na.rm = TRUE)]

liq_dt <- price_dt[, .(Date, Ticker, liq_20d)]
setkey(liq_dt, Date, Ticker)

# ── 13. 전체 병합 ─────────────────────────────────────────────────────────────
cat("[01] Final merge...\n")
setkey(flow_dt, Date, Ticker)
feat_dt <- price_feat[flow_dt, on = .(Date, Ticker)]
feat_dt  <- liq_dt[feat_dt, on = .(Date, Ticker)]
feat_dt[is.na(liq_20d), liq_20d := 0]

# ── 14. 피처 컬럼 선택 ────────────────────────────────────────────────────────
feat_cols <- c(
  "Date", "Ticker",
  # 수급 피처 (10)
  "inst_netbuy_5d", "inst_netbuy_20d", "inst_netbuy_60d",
  "foreign_netbuy_5d", "foreign_netbuy_20d", "foreign_netbuy_60d",
  "individual_netbuy_5d",
  "inst_flow_momentum", "foreign_flow_momentum",
  "inst_concentration",
  # 가격/거래량 피처 (5)
  "ret_5d", "ret_20d", "volume_ratio_20d", "log_mcap", "turnover_chg_20d",
  # 추가 피처 (2)
  "foreign_own_chg_20d",  # Feature 16
  "earnings_proximity",   # Feature 17
  # 타겟
  "fwd_inst_foreign_netbuy_21d", "fwd_flow_top20",
  # 메타
  "liq_20d"
)

# 실제 존재하는 컬럼만 선택
exist_cols <- feat_cols[feat_cols %in% names(feat_dt)]
feat_dt <- feat_dt[, ..exist_cols]
feat_dt[, Date := as.Date(Date)]

cat("[01] Final feature rows:", nrow(feat_dt), "\n")
cat("[01] Features:", paste(setdiff(exist_cols, c("Date","Ticker","fwd_inst_foreign_netbuy_21d","fwd_flow_top20","liq_20d")), collapse=", "), "\n")
na_counts <- feat_dt[, lapply(.SD, function(x) sum(is.na(x)))]
cat("[01] NA counts:\n"); print(na_counts)

# ── 15. 저장 ──────────────────────────────────────────────────────────────────
cat("[01] Saving to:", OUT_FILE, "\n")
write_parquet(feat_dt, OUT_FILE)
cat("[01] Saved. Rows:", nrow(feat_dt),
    "| Date:", as.character(min(feat_dt$Date, na.rm=TRUE)), "~",
    as.character(max(feat_dt$Date, na.rm=TRUE)), "\n")

cat("=== 01_flow_features.R COMPLETE ===\n")
