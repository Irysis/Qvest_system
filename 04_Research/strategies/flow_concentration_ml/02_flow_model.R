cat("=== STR_1678: Flow Concentration ML — Model Training & Backtest ===\n")
## 핵심아이디어: XGBoost로 기관+외국인 순매수 집중 예측 → 포트폴리오 구성
## OPT-7/MC-P1: 일간 Factor DB 309 팩터 → MI prefilter → top-50 선택 후 수급 피처와 결합
## OPT-7/MC-P2: fdb_daily (일간) 참조 — 5700일+ 학습 데이터
## OPT-7/MC-P3: Walk-forward expanding window (63거래일 리피트)
## IS: 2000-01 ~ 2007-12 (8년) | OOS: 2008-01 ~ 2025-12

# ── 0. 라이브러리 ─────────────────────────────────────────────────────────────
suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(dplyr)       # collect(), filter(), select() for arrow datasets
  library(xgboost)
  library(ggplot2)
  library(jsonlite)
})

# ── 1. 경로 ──────────────────────────────────────────────────────────────────
PROJECT_ROOT  <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
CACHE_DIR     <- file.path(PROJECT_ROOT, ".cache")
DAILY_FDB_DIR <- file.path(CACHE_DIR, "factor_db_daily")   # OPT-7/MC-P2
FDB_DIR       <- file.path(CACHE_DIR, "factor_db")          # 월간 (C19)
FEAT_FILE     <- file.path(CACHE_DIR, "flow_features_daily.parquet")
OUT_DIR       <- file.path(PROJECT_ROOT,
                           "04_Research/strategies/flow_concentration_ml/output")
dir.create(OUT_DIR, showWarnings = FALSE, recursive = TRUE)

cat("[02] Loading infrastructure...\n")
source(file.path(PROJECT_ROOT, "02_Infrastructure/config.R"))
source(file.path(PROJECT_ROOT, "02_Infrastructure/backtest_harness.R"))

# ── 2. 수급 피처 로드 ─────────────────────────────────────────────────────────
cat("[02] Loading flow feature matrix...\n")
if (!file.exists(FEAT_FILE)) {
  stop("[02] FATAL: flow_features_daily.parquet not found. Run 01_flow_features.R first.")
}
feat_dt <- as.data.table(read_parquet(FEAT_FILE))
feat_dt[, Date := as.Date(Date)]
setkey(feat_dt, Date, Ticker)
cat("[02] Feature rows:", nrow(feat_dt), "\n")

# ── 3. 일간 Factor DB 벌크 로드 (OPT-7/MC-P2) ─────────────────────────────────
## 309 팩터 × 5700일+ — 루프 내 로드 절대 금지 (OPT-1)
## open_dataset으로 디렉토리 전체를 한 번에 메모리 매핑
cat("[02] Opening daily Factor DB (fdb_daily) via open_dataset...\n")
# JSON 파일이 혼재하므로 parquet 파일 목록만 명시적으로 지정
fdb_daily_files <- list.files(DAILY_FDB_DIR,
                               pattern = "^fdb_daily_\\d{6}\\.parquet$",
                               full.names = TRUE)
cat("[02] Daily FDB parquet files found:", length(fdb_daily_files), "\n")
fdb_daily_ds <- open_dataset(fdb_daily_files, format = "parquet")
cat("[02] Daily FDB schema columns:", ncol(fdb_daily_ds), "\n")

# 메타 컬럼 제외한 팩터 컬럼 목록 파악
fdb_schema_cols <- names(fdb_daily_ds)
meta_cols       <- c("Date", "Ticker")
excl_pats       <- c(grep("\\.x$|\\.y$", fdb_schema_cols, value = TRUE),
                     grep("^(RE_|RE0|RE1)", fdb_schema_cols, value = TRUE),
                     grep("^(dps_1y|bps_1y|eps_1y|target_price)", fdb_schema_cols, value = TRUE))
fdb_factor_cols <- setdiff(fdb_schema_cols, c(meta_cols, excl_pats))
cat("[02] Factor columns available:", length(fdb_factor_cols), "\n")

# IS 기간 내 데이터만 collect (MI prefilter용)
IS_END    <- as.Date("2007-12-31")
OOS_START <- as.Date("2008-01-01")
OOS_END   <- as.Date("2025-12-31")

cat("[02] Collecting IS daily FDB for MI prefilter (2000-01 ~ 2007-12)...\n")
fdb_is <- fdb_daily_ds |>
  filter(Date >= as.Date("2000-01-01"), Date <= IS_END) |>
  select(all_of(c("Date", "Ticker", fdb_factor_cols))) |>
  collect() |>
  as.data.table()
fdb_is[, Date := as.Date(Date)]
setkey(fdb_is, Date, Ticker)
cat("[02] IS daily FDB rows:", nrow(fdb_is), "\n")
gc()

# ── 4. MI prefilter: 309 → top-50 팩터 선택 (OPT-7/MC-P1) ─────────────────
## L-123 §2.3: 전체 팩터에서 타겟(flow)과의 MI로 사전 선택
## 단순 |IC| (Spearman correlation with target) 기반 prefilter
## (mutual_info_regression 대신 IC 기반 — R에서 직접 사용)
cat("[02] Running MI/IC prefilter: fdb_daily 309 factors -> top 50 (L-123 §2.3)...\n")

# IS 기간의 flow 타겟과 일간 팩터 병합
feat_is <- feat_dt[Date <= IS_END & !is.na(fwd_inst_foreign_netbuy_21d)]
merged_is <- fdb_is[feat_is[, .(Date, Ticker, fwd_inst_foreign_netbuy_21d)],
                    on = .(Date, Ticker), nomatch = 0]

# 각 팩터와 타겟의 |Spearman IC| 계산 (MI prefilter proxy)
MI_prefilter <- function(dt, factor_cols, target_col, top_n = 50) {
  cat("[02]   Computing |IC| for", length(factor_cols), "factors...\n")
  ic_scores <- vapply(factor_cols, function(fc) {
    x <- dt[[fc]]
    y <- dt[[target_col]]
    ok <- !is.na(x) & !is.na(y) & is.finite(x) & is.finite(y)
    if (sum(ok) < 100L) return(0)
    abs(cor(rank(x[ok]), rank(y[ok]), method = "spearman"))
  }, numeric(1))
  ic_dt <- data.table(Factor = factor_cols, IC = ic_scores)
  setorder(ic_dt, -IC)
  cat("[02]   Top 5 factors by |IC|:\n")
  print(head(ic_dt, 5))
  head(ic_dt$Factor, top_n)
}

top50_factors <- MI_prefilter(merged_is, fdb_factor_cols,
                               "fwd_inst_foreign_netbuy_21d", top_n = 50)
cat("[02] Top-50 factors selected by MI prefilter.\n")
rm(merged_is, fdb_is); gc()

# ── 5. 전체 기간 일간 FDB (top-50 컬럼만) 로드 ──────────────────────────────
cat("[02] Loading full daily FDB (top-50 factors + OOS)...\n")
fdb_full <- fdb_daily_ds |>
  filter(Date >= as.Date("2000-01-01"), Date <= OOS_END) |>
  select(all_of(c("Date", "Ticker", top50_factors))) |>
  collect() |>
  as.data.table()
fdb_full[, Date := as.Date(Date)]
setkey(fdb_full, Date, Ticker)
cat("[02] Full daily FDB (top-50) rows:", nrow(fdb_full),
    "| Date:", as.character(min(fdb_full$Date)), "~", as.character(max(fdb_full$Date)), "\n")
gc()

# ── 6. C19 월간 팩터 로드 (VDplus 기준선용) ──────────────────────────────────
cat("[02] Loading C19 from monthly Factor DB (bulk open_dataset)...\n")
fdb_files <- list.files(FDB_DIR, pattern = "^factor_db_\\d{6}\\.parquet$", full.names = TRUE)
c19_raw <- open_dataset(fdb_files, format = "parquet") |>
  filter(Factor_Name == "C19_Composite_Earnings") |>
  select(Date, Ticker, Z_Score) |>
  collect() |>
  as.data.table()
c19_raw[, Date := as.Date(Date)]
setnames(c19_raw, "Z_Score", "C19_score")
setkey(c19_raw, Date, Ticker)
cat("[02] C19 rows:", nrow(c19_raw), "\n")

# locf: 월간 C19 → 일간 feat_dt 병합
c19_raw[, month_key := format(Date, "%Y-%m")]
feat_dt[, month_key := format(Date, "%Y-%m")]
c19_monthly <- c19_raw[, .(month_key, Ticker, C19_score)]
setkey(c19_monthly, month_key, Ticker); setkey(feat_dt, month_key, Ticker)
feat_dt <- c19_monthly[feat_dt, on = .(month_key, Ticker)]
feat_dt[is.na(C19_score), C19_score := 0]
setkey(feat_dt, Date, Ticker)
rm(c19_raw, c19_monthly); gc()

# ── 7. 수급 피처 + 일간 FDB 통합 ─────────────────────────────────────────────
cat("[02] Merging flow features with daily FDB top-50...\n")
combined_dt <- fdb_full[feat_dt, on = .(Date, Ticker), nomatch = 0]
setkey(combined_dt, Date, Ticker)
cat("[02] Combined rows:", nrow(combined_dt), "\n")
rm(fdb_full, feat_dt); gc()

# ── 8. 피처 컬럼 정의 ────────────────────────────────────────────────────────
FLOW_FEATURES <- c(
  "inst_netbuy_5d", "inst_netbuy_20d", "inst_netbuy_60d",
  "foreign_netbuy_5d", "foreign_netbuy_20d", "foreign_netbuy_60d",
  "individual_netbuy_5d",
  "inst_flow_momentum", "foreign_flow_momentum",
  "inst_concentration",
  "ret_5d", "ret_20d", "volume_ratio_20d", "log_mcap", "turnover_chg_20d",
  "foreign_own_chg_20d",   # Feature 16
  "earnings_proximity"     # Feature 17
)

# MI top-50 중 combined_dt에 실제 있는 컬럼만
FDB_FEATURES  <- top50_factors[top50_factors %in% names(combined_dt)]
FEATURE_COLS  <- c(FLOW_FEATURES[FLOW_FEATURES %in% names(combined_dt)], FDB_FEATURES)
cat("[02] Total features:", length(FEATURE_COLS),
    "(flow:", length(FLOW_FEATURES[FLOW_FEATURES %in% names(combined_dt)]),
    "+ fdb:", length(FDB_FEATURES), ")\n")

TARGET_REG   <- "fwd_inst_foreign_netbuy_21d"
TARGET_CLS   <- "fwd_flow_top20"
LIQ_THRESH   <- 2e8

# XGBoost 파라미터
XGB_PARAMS_REG <- list(
  objective        = "reg:squarederror",
  eta              = 0.01,
  max_depth        = 5,
  subsample        = 0.7,
  colsample_bytree = 0.5,
  nthread          = 4,
  verbosity        = 0
)
XGB_PARAMS_CLS <- list(
  objective        = "binary:logistic",
  eta              = 0.01,
  max_depth        = 5,
  subsample        = 0.7,
  colsample_bytree = 0.5,
  nthread          = 4,
  verbosity        = 0
)
NROUNDS <- 500

# ── 9. 월말 리밸런싱 날짜 시퀀스 ──────────────────────────────────────────────
combined_dt[, ym := format(Date, "%Y-%m")]
month_last_dates <- combined_dt[Date >= OOS_START & Date <= OOS_END,
                                 .(rebal_date = max(Date)), by = ym][order(ym), rebal_date]
cat("[02] OOS rebalancing months:", length(month_last_dates), "\n")

# ── 10. Walk-forward expanding window 모델 학습 + 예측 (OPT-7/MC-P3) ──────────
cat("[02] Walk-forward training (expand window, refit every 63 trading days)...\n")
REFIT_FREQ <- 63L

pred_records       <- list()
feat_importance_list <- list()
model_reg          <- NULL
model_cls          <- NULL
last_refit_date    <- as.Date("1900-01-01")
refit_count        <- 0L

for (i in seq_along(month_last_dates)) {
  rd <- month_last_dates[i]

  need_refit <- (is.null(model_reg) ||
                   as.integer(rd - last_refit_date) >= REFIT_FREQ)

  if (need_refit) {
    train_end      <- rd - 1L   # t-1 lag (C2 PASS)
    train_sub <- combined_dt[
      Date <= train_end &
        !is.na(fwd_inst_foreign_netbuy_21d) &
        !is.na(fwd_flow_top20)
    ]
    cc_idx <- complete.cases(train_sub[, ..FEATURE_COLS])
    train_complete <- train_sub[cc_idx]
    cat("[02]   train_complete rows at", as.character(rd), ":", nrow(train_complete), "\n")

    if (nrow(train_complete) < 500L) {
      cat("[02]   Insufficient data, skip refit.\n"); next
    }

    X_train    <- as.matrix(train_complete[, ..FEATURE_COLS])
    y_reg      <- train_complete[[TARGET_REG]]
    y_cls      <- train_complete[[TARGET_CLS]]

    dtrain_reg <- xgb.DMatrix(X_train, label = y_reg)
    dtrain_cls <- xgb.DMatrix(X_train, label = y_cls)

    model_reg  <- xgb.train(XGB_PARAMS_REG, dtrain_reg, nrounds = NROUNDS, verbose = 0)
    model_cls  <- xgb.train(XGB_PARAMS_CLS, dtrain_cls, nrounds = NROUNDS, verbose = 0)

    refit_count      <- refit_count + 1L
    last_refit_date  <- rd

    feat_importance_list[[refit_count]] <- list(
      refit_date     = as.character(rd),
      importance_reg = xgb.importance(model = model_reg),
      importance_cls = xgb.importance(model = model_cls)
    )
    cat("[02]   Refit #", refit_count, "at", as.character(rd),
        "| train rows:", nrow(train_complete), "\n")
  }

  if (is.null(model_reg)) next

  score_dt <- combined_dt[Date == rd & liq_20d >= LIQ_THRESH]
  score_ok  <- score_dt[complete.cases(score_dt[, ..FEATURE_COLS])]
  if (nrow(score_ok) < 20L) next

  X_score  <- as.matrix(score_ok[, ..FEATURE_COLS])
  dscore   <- xgb.DMatrix(X_score)
  score_ok[, pred_reg := predict(model_reg, dscore)]
  score_ok[, pred_cls := predict(model_cls, dscore)]

  pred_records[[i]] <- score_ok[, .(Date, Ticker, pred_reg, pred_cls, C19_score)]
}

cat("[02] Walk-forward complete. Total refits:", refit_count, "\n")

pred_all <- rbindlist(pred_records, fill = TRUE)
pred_all[, Date := as.Date(Date)]
setkey(pred_all, Date, Ticker)
cat("[02] Prediction records:", nrow(pred_all), "\n")
gc()

# ── 11. Feature Importance 시각화 ─────────────────────────────────────────────
cat("[02] Plotting feature importance...\n")
if (length(feat_importance_list) > 0L) {
  recent_imp   <- tail(feat_importance_list, min(3L, length(feat_importance_list)))
  imp_reg_avg  <- rbindlist(lapply(recent_imp, function(x) x$importance_reg), fill = TRUE)[
    , .(Gain = mean(Gain, na.rm = TRUE)), by = Feature][order(-Gain)]

  p_imp <- ggplot(head(imp_reg_avg, 20L),
                  aes(x = reorder(Feature, Gain), y = Gain)) +
    geom_bar(stat = "identity", fill = "#2E86AB") +
    coord_flip() +
    labs(title = "STR_1678 Flow Concentration — XGBoost Feature Importance (top 20)",
         x = "Feature", y = "Gain (avg last 3 refits)") +
    theme_minimal(base_size = 11)

  ggsave(file.path(OUT_DIR, "feature_importance.png"), p_imp,
         width = 10, height = 6, dpi = 150)

  imp_cls_avg <- rbindlist(lapply(recent_imp, function(x) x$importance_cls), fill = TRUE)[
    , .(Gain = mean(Gain, na.rm = TRUE)), by = Feature][order(-Gain)]

  write_json(list(regression = as.list(imp_reg_avg),
                  classification = as.list(imp_cls_avg)),
             file.path(OUT_DIR, "feature_importance.json"),
             pretty = TRUE, auto_unbox = TRUE)
  cat("[02] Feature importance saved.\n")
}

# ── 12. RAWDATA + BM 로드 (백테스트용) ───────────────────────────────────────
cat("[02] Loading RAWDATA for backtest simulation...\n")
res2   <- load_rawdata(use_cache = TRUE)
RAWDATA <- as.data.table(res2$RAWDATA)
BM_DT   <- as.data.table(res2$BM_DT)
setkey(RAWDATA, Date, Ticker)
rm(res2); gc()

# ── 13. 포트폴리오 빌더 헬퍼 ─────────────────────────────────────────────────
build_portfolio <- function(dt, score_col = "pred_reg", top_n = 20L) {
  rb_dates <- sort(unique(dt$Date))
  rbindlist(lapply(rb_dates, function(rd) {
    sub <- dt[Date == rd]
    setorderv(sub, score_col, order = -1L)
    sel <- head(sub, top_n)
    if (nrow(sel) < 5L) return(NULL)
    sel[, .(Date, Ticker, weight = 1 / .N)]
  }), fill = TRUE)
}

# ── 14. 백테스트 A — Flow Standalone ──────────────────────────────────────────
cat("[02] Backtest A: Flow Standalone (top-20 by pred_reg, EW)...\n")
# run_monthly_simulation expects FACTORS(Date, Ticker, Score)
FACTORS_A <- pred_all[, .(Date, Ticker, Score = pred_reg)]
FACTORS_A <- FACTORS_A[!is.na(Score)]
sim_A  <- run_monthly_simulation(RAWDATA, BM_DT, FACTORS_A,
  n_holdings = 20L, commission = 0.0015,
  buffer_zone = list(keep_n = 35L, entry_n = 20L))
perf_A <- summarise_perf(sim_A)
cat(sprintf("[02] Flow Standalone: SR=%.3f | CAGR=%.2f%% | MDD=%.2f%%\n",
            perf_A$SR, perf_A$CAGR * 100, perf_A$MDD * 100))

# ── 15. VDplus C19 기준선 ──────────────────────────────────────────────────────
cat("[02] Building VDplus C19 baseline...\n")
c19_for_vd <- combined_dt[!is.na(C19_score) & C19_score != 0 & liq_20d >= LIQ_THRESH,
                           .(Date, Ticker, C19_score)]
c19_rebal  <- c19_for_vd[Date %in% month_last_dates & Date >= OOS_START & Date <= OOS_END]

FACTORS_VD <- c19_rebal[, .(Date, Ticker, Score = C19_score)]
FACTORS_VD <- FACTORS_VD[!is.na(Score)]

sim_VD  <- run_monthly_simulation(RAWDATA, BM_DT, FACTORS_VD,
  n_holdings = 20L, commission = 0.0015,
  buffer_zone = list(keep_n = 35L, entry_n = 20L))
perf_VD <- summarise_perf(sim_VD)
cat(sprintf("[02] VDplus C19 EW: SR=%.3f | CAGR=%.2f%% | MDD=%.2f%%\n",
            perf_VD$SR, perf_VD$CAGR * 100, perf_VD$MDD * 100))

# ── 16. 백테스트 B — VDplus + Flow Synergy ────────────────────────────────────
cat("[02] Backtest B: VDplus+Flow Synergy (C19 top-20 pool, flow-weighted)...\n")
# Synergy: C19 pool에서 flow로 가중
FACTORS_B <- rbindlist(lapply(sort(unique(c19_rebal$Date)), function(rd) {
  c19_rd  <- c19_for_vd[Date == rd]
  if (nrow(c19_rd) < 5L) return(NULL)
  setorder(c19_rd, -C19_score)
  top20_c19 <- head(c19_rd$Ticker, 20L)
  flow_rd <- pred_all[Date == rd & Ticker %in% top20_c19]
  if (nrow(flow_rd) < 5L) {
    return(data.table(Date = rd, Ticker = top20_c19, Score = 1.0))
  }
  flow_rd[, .(Date, Ticker, Score = pred_reg)]
}), fill = TRUE)
FACTORS_B <- FACTORS_B[!is.na(Score)]

sim_B  <- run_monthly_simulation(RAWDATA, BM_DT, FACTORS_B,
  n_holdings = 20L, commission = 0.0015,
  buffer_zone = list(keep_n = 35L, entry_n = 20L))
perf_B <- summarise_perf(sim_B)
cat(sprintf("[02] VDplus+Flow Synergy: SR=%.3f | CAGR=%.2f%% | MDD=%.2f%%\n",
            perf_B$SR, perf_B$CAGR * 100, perf_B$MDD * 100))

# ── 17. 상관 분석 ──────────────────────────────────────────────────────────────
get_monthly_rets <- function(sim) {
  nav <- as.data.table(sim$nav)
  nav[, ym := format(Date, "%Y-%m")]
  nav[, .(nav_end = last(NAV)), by = ym][
    , monthly_ret := nav_end / shift(nav_end) - 1][!is.na(monthly_ret)]
}
mr_A  <- get_monthly_rets(sim_A)
mr_VD <- get_monthly_rets(sim_VD)
mr_B  <- get_monthly_rets(sim_B)

common_ym <- Reduce(intersect, list(mr_A$ym, mr_VD$ym, mr_B$ym))
cor_mat <- cor(cbind(
  FlowSA  = mr_A[ym  %in% common_ym, monthly_ret],
  VDplus  = mr_VD[ym %in% common_ym, monthly_ret],
  Synergy = mr_B[ym  %in% common_ym, monthly_ret]
), use = "complete.obs")
cat("[02] Return correlation matrix:\n"); print(round(cor_mat, 3))

# ── 18. 스트레스 구간 분석 ────────────────────────────────────────────────────
stress_periods <- list(
  list(label = "9/11",       start = "2001-09-01", end = "2001-12-31"),
  list(label = "GFC",        start = "2007-10-01", end = "2009-03-31"),
  list(label = "EuDebt",     start = "2011-07-01", end = "2011-12-31"),
  list(label = "ChinaShock", start = "2015-06-01", end = "2016-02-29"),
  list(label = "TradeWar",   start = "2018-03-01", end = "2018-12-31"),
  list(label = "COVID",      start = "2020-01-01", end = "2020-06-30"),
  list(label = "RateHike",   start = "2022-01-01", end = "2022-12-31"),
  list(label = "IranWar",    start = "2026-02-01", end = "2026-04-30")
)

calc_stress <- function(sim, periods) {
  nav <- as.data.table(sim$nav)
  rbindlist(lapply(periods, function(p) {
    s <- as.Date(p$start); e <- as.Date(p$end)
    sub <- nav[Date >= s & Date <= e]
    if (nrow(sub) < 5L)
      return(data.table(label = p$label, CAGR_pct = NA_real_, MDD_pct = NA_real_))
    ret_cum <- last(sub$NAV) / first(sub$NAV) - 1
    n_yr    <- max(as.numeric(e - s) / 365.25, 0.1)
    cagr_p  <- ((1 + ret_cum)^(1 / n_yr) - 1) * 100
    mdd_p   <- max(1 - sub$NAV / cummax(sub$NAV), na.rm = TRUE) * 100
    data.table(label = p$label, CAGR_pct = round(cagr_p, 2), MDD_pct = round(mdd_p, 2))
  }))
}

stress_A  <- calc_stress(sim_A,  stress_periods)
stress_VD <- calc_stress(sim_VD, stress_periods)
stress_B  <- calc_stress(sim_B,  stress_periods)

stress_out <- Reduce(function(a, b) merge(a, b, by = "label"), list(
  setnames(stress_A,  c("CAGR_pct","MDD_pct"), c("CAGR_FlowSA","MDD_FlowSA")),
  setnames(stress_VD, c("CAGR_pct","MDD_pct"), c("CAGR_VDplus","MDD_VDplus")),
  setnames(stress_B,  c("CAGR_pct","MDD_pct"), c("CAGR_Synergy","MDD_Synergy"))
))
cat("[02] Stress summary:\n"); print(stress_out)
fwrite(stress_out, file.path(OUT_DIR, "stress_analysis.csv"))

# ── 19. Equity Curve 시각화 ───────────────────────────────────────────────────
cat("[02] Plotting equity curves...\n")
get_nav_dt <- function(sim, label) {
  nav <- as.data.table(sim$nav)
  nav[, Date := as.Date(Date)]
  nav[Date >= OOS_START & Date <= OOS_END, .(Date, NAV, Strategy = label)]
}
bm_nav <- BM_DT[Date >= OOS_START & Date <= OOS_END, .(Date, BM_Ret)]
bm_nav[, NAV := cumprod(1 + replace(BM_Ret, is.na(BM_Ret), 0))]
bm_nav[, Strategy := "KOSPI BM"]

plot_dt <- rbindlist(list(
  get_nav_dt(sim_A,  "Flow Standalone"),
  get_nav_dt(sim_VD, "VDplus C19 EW"),
  get_nav_dt(sim_B,  "VDplus+Flow Synergy"),
  bm_nav[, .(Date, NAV, Strategy)]
))

p_eq <- ggplot(plot_dt, aes(x = Date, y = NAV, color = Strategy)) +
  geom_line(linewidth = 0.8) +
  scale_y_log10(labels = scales::comma) +
  scale_color_manual(values = c(
    "Flow Standalone"     = "#E63946",
    "VDplus C19 EW"      = "#457B9D",
    "VDplus+Flow Synergy" = "#2A9D8F",
    "KOSPI BM"           = "#999999"
  )) +
  labs(
    title = "STR_1678 Flow Concentration ML — OOS Equity Curves (2008-2025)",
    subtitle = sprintf(
      "FlowSA SR=%.2f CAGR=%.1f%% | VD SR=%.2f CAGR=%.1f%% | Synergy SR=%.2f CAGR=%.1f%%",
      perf_A$SR,  perf_A$CAGR  * 100,
      perf_VD$SR, perf_VD$CAGR * 100,
      perf_B$SR,  perf_B$CAGR  * 100
    ),
    x = "Date", y = "NAV (log scale)", color = "Strategy"
  ) +
  theme_minimal(base_size = 12) +
  theme(legend.position = "bottom")

ggsave(file.path(OUT_DIR, "equity_curve.png"), p_eq,
       width = 14, height = 7, dpi = 150)
cat("[02] Equity curve saved.\n")

# ── 20. 결과 JSON 저장 ────────────────────────────────────────────────────────
write_json(list(
  strategy_id  = "STR_1678_A_FlowStandalone",
  description  = "Top-20 by XGBoost predicted institutional+foreign flow, EW, monthly rebal",
  model        = "XGBoost Regression",
  features     = list(total = length(FEATURE_COLS),
                      flow_features = length(FLOW_FEATURES[FLOW_FEATURES %in% names(combined_dt)]),
                      fdb_daily_top50 = length(FDB_FEATURES)),
  IS_period    = "2000-01 ~ 2007-12",
  OOS_period   = "2008-01 ~ 2025-12",
  refit_count  = refit_count,
  performance  = list(SR = round(perf_A$SR, 4), CAGR = round(perf_A$CAGR, 4),
                      MDD = round(perf_A$MDD, 4),
                      Ann_Vol = round(if (!is.null(perf_A$Ann_Vol)) perf_A$Ann_Vol else NA_real_, 4)),
  corr_vs_VDplus = round(cor_mat["FlowSA","VDplus"], 4),
  stress = as.list(stress_A)
), file.path(OUT_DIR, "flow_standalone_results.json"), pretty = TRUE, auto_unbox = TRUE)

write_json(list(
  strategy_id       = "STR_1678_B_VDplusFlowSynergy",
  description       = "C19 top-20 pool, weights proportional to predicted flow score",
  model             = "XGBoost Regression (position sizing within VDplus pool)",
  IS_period         = "2000-01 ~ 2007-12",
  OOS_period        = "2008-01 ~ 2025-12",
  refit_count       = refit_count,
  vdplus_baseline   = list(SR  = round(perf_VD$SR, 4), CAGR = round(perf_VD$CAGR, 4),
                            MDD = round(perf_VD$MDD, 4)),
  synergy_performance = list(SR = round(perf_B$SR, 4), CAGR = round(perf_B$CAGR, 4),
                              MDD = round(perf_B$MDD, 4)),
  improvement       = list(SR_delta   = round(perf_B$SR   - perf_VD$SR,   4),
                            CAGR_delta = round(perf_B$CAGR - perf_VD$CAGR, 4),
                            MDD_delta  = round(perf_B$MDD  - perf_VD$MDD,  4)),
  corr_FlowSA_VDplus  = round(cor_mat["FlowSA", "VDplus"],  4),
  corr_Synergy_VDplus = round(cor_mat["Synergy","VDplus"],  4),
  stress = as.list(stress_B)
), file.path(OUT_DIR, "flow_vdplus_synergy_results.json"), pretty = TRUE, auto_unbox = TRUE)

# ── 21. 최종 요약 ──────────────────────────────────────────────────────────────
cat("\n========================================================\n")
cat("STR_1678 Flow Concentration ML — FINAL RESULTS\n")
cat("========================================================\n")
cat(sprintf("Total features: %d (flow:%d + fdb_daily_top50:%d)\n",
            length(FEATURE_COLS),
            length(FLOW_FEATURES[FLOW_FEATURES %in% names(combined_dt)]),
            length(FDB_FEATURES)))
cat(sprintf("%-30s SR=%5.3f | CAGR=%6.2f%% | MDD=%6.2f%%\n",
            "A. Flow Standalone:",    perf_A$SR,  perf_A$CAGR*100,  perf_A$MDD*100))
cat(sprintf("%-30s SR=%5.3f | CAGR=%6.2f%% | MDD=%6.2f%%\n",
            "   VDplus C19 EW (base):", perf_VD$SR, perf_VD$CAGR*100, perf_VD$MDD*100))
cat(sprintf("%-30s SR=%5.3f | CAGR=%6.2f%% | MDD=%6.2f%%\n",
            "B. VDplus+Flow Synergy:", perf_B$SR,  perf_B$CAGR*100,  perf_B$MDD*100))
cat(sprintf("   Synergy delta: SR=%+.3f | CAGR=%+.2f%%\n",
            perf_B$SR - perf_VD$SR, (perf_B$CAGR - perf_VD$CAGR)*100))
cat(sprintf("Flow-VDplus Corr: %.3f | Synergy-VDplus Corr: %.3f\n",
            cor_mat["FlowSA","VDplus"], cor_mat["Synergy","VDplus"]))
cat(sprintf("XGBoost refits: %d\n", refit_count))
cat("========================================================\n")

cat("=== 02_flow_model.R COMPLETE ===\n")
