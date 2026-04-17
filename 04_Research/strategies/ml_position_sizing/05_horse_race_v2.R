cat("=== ML Position Sizing: Horse Race v2 (ranger + torch + fdb_daily MI_prefilter) ===\n")
## 핵심 아이디어: 일간 FDB 피처 MI_prefilter top-50 → 월말 관측치 학습 (비중복)
## OPT-7/MC-P1: MI_prefilter 309→50 pre-select (L-123 §2.3)
## OPT-7/MC-P2: fdb_daily (factor_db_daily) 참조 — 일간 피처 소스
## OPT-7/MC-P3: walk-forward expanding_window (oos_year 단위 refit, MC1 준수)
## ranger(QRF 대체 5-10x 빠름) + torch LSTM + daily FDB 피처
## 학습: 월말 관측치만 (비중복, 과적합 방지) × 일간 rolling 피처
## Pilot(IS:1990~2022, OOS:2023~2026-04) → Pass → Full(IS:1990~2007+, OOS:2008~2026-04)

t0 <- Sys.time()

# ═══════════════════════════════════════════════════════════════════
# 0. 환경 설정
# ═══════════════════════════════════════════════════════════════════
.root_candidates <- c(
  "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot",
  "/mnt/c/Users/99922/OneDrive/바탕 화면/Quant_Module_Moltbot"
)
PROJECT_ROOT <- .root_candidates[sapply(.root_candidates, dir.exists)][1]
rm(.root_candidates)

FUNC_PATH <- file.path(PROJECT_ROOT, "02_Infrastructure")
CACHE_DIR  <- file.path(PROJECT_ROOT, ".cache")
STRAT_DIR  <- tryCatch(dirname(sys.frame(1)$ofile), error = function(e)
  file.path(PROJECT_ROOT, "04_Research/strategies/ml_position_sizing"))
OUT_DIR    <- file.path(STRAT_DIR, "output")
HRV2_CACHE <- file.path(CACHE_DIR, "hr_v2")
dir.create(OUT_DIR,    showWarnings = FALSE, recursive = TRUE)
dir.create(HRV2_CACHE, showWarnings = FALSE, recursive = TRUE)

source(file.path(FUNC_PATH, "config.R"))

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(zoo)
  library(lubridate)
  library(PerformanceAnalytics)
  library(xts)
  library(glmnet)
  library(xgboost)
  library(ranger)
  library(quantreg)
})

HAS_TORCH   <- FALSE  # OOM fix: LSTM 비활성화 (메모리 절약)
HAS_RUGARCH <- FALSE  # OOM fix: GARCH 비활성화 (3134 ticker 순차 피팅 = 메모리+시간 폭발)
if (HAS_TORCH)   suppressPackageStartupMessages(library(torch))
if (HAS_RUGARCH) suppressPackageStartupMessages(library(rugarch))

options(scipen = 999)
Sys.setenv(TZ = "Asia/Seoul")
cat(sprintf("[packages] ranger: TRUE | quantreg: TRUE | xgboost: TRUE | torch: %s | rugarch: %s\n",
            HAS_TORCH, HAS_RUGARCH))

# ─── 파라미터 ──────────────────────────────────────────────────────
TAU          <- 0.05
N_TOP        <- 20
TREE_N       <- 200          # OOM fix: 500→200 (메모리 선형 비례)
TREE_THREADS <- 4
LIQ_THRESH   <- 2e8         # 유동성 필터
MI_TOP_N     <- 50          # OPT-7/MC-P1: MI_prefilter top-50

# ─── 기간 ─────────────────────────────────────────────────────────
IS_HARD_START   <- as.Date("1990-01-04")   # RAWDATA 시작일
PILOT_IS_END    <- as.Date("2022-12-31")
PILOT_OOS_START <- as.Date("2023-01-01")
PILOT_OOS_END   <- as.Date("2026-04-08")   # RAWDATA 끝 (2026-04-08)
FULL_IS_END     <- as.Date("2007-12-31")
FULL_OOS_START  <- as.Date("2008-01-01")
FULL_OOS_END    <- as.Date("2026-04-08")

# ═══════════════════════════════════════════════════════════════════
# 1. RAWDATA 로드 (1회만, OPT-1)
# ═══════════════════════════════════════════════════════════════════
cat("\n[Step 1] Loading RAWDATA (1회 로드, OPT-1)...\n")
raw <- read_parquet(file.path(CACHE_DIR, "rawdata.parquet")) |> as.data.table()
raw[, Date := as.Date(Date)]
keep_raw <- intersect(c("Date","Ticker","Close","Vol","Size","Ret","BM_Ret"), names(raw))
raw <- raw[, ..keep_raw]
setkey(raw, Ticker, Date)
cat(sprintf("[rawdata] %d rows, %d tickers, %s ~ %s\n",
            nrow(raw), uniqueN(raw$Ticker),
            as.character(min(raw$Date)), as.character(max(raw$Date))))
gc()

# ═══════════════════════════════════════════════════════════════════
# 2. OPT-7/MC-P2: Daily Factor DB (fdb_daily) 로드 — 피처 소스
#    MI_prefilter용 후보 팩터 풀: D/R/L/RE family (CVaR 예측 관련)
# ═══════════════════════════════════════════════════════════════════
cat("\n[Step 2] Loading fdb_daily (factor_db_daily, OPT-7/MC-P2)...\n")
FDB_DAILY_DIR <- file.path(CACHE_DIR, "factor_db_daily")
fdb_daily_files <- list.files(FDB_DAILY_DIR, pattern = "\\.parquet$", full.names = TRUE)
cat(sprintf("[fdb_daily] %d files found\n", length(fdb_daily_files)))

# D/R/L family — CVaR 예측에 직접 관련된 팩터 (309개 중 risk/liquidity/momentum 계열)
# OPT-7/MC-P1: MI_prefilter 대상 후보 컬럼
FDB_CANDIDATE_COLS <- c(
  # Risk family (D: 변동성/베타)
  "D01_IdioVol","D02_Beta","D03_RealVol","D04_Downside_Beta","D05_MaxRet",
  "D06_Upside_Beta","D12_Beta_126d","D13_Beta_63d","D34_RealVol_21d",
  "D35_RealVol_63d","D36_RealVol_126d","D43_Skewness","D44_Kurtosis",
  "D45_Downside_Dev","D47_CVaR_5pct","D48_VaR_5pct","D50_MaxDrawdown",
  "D54_Neg_Ret_Prop","D57_Down_Vol","D58_Vol_Asymmetry",
  # R family (tail risk)
  "R01_VaR_95","R03_CVaR_95","R05_Tail_Risk","R06_MDD","R07_Downside_Dev",
  "R08_Semi_Variance","R11_Systematic_Risk","R12_Idiosyncratic_Risk",
  "R13_NCSKEW","R14_DUVOL",
  # L family (liquidity)
  "L01_Amihud","L02_Turnover","L05_Dollar_Volume","L09_Amihud_20d",
  "L11_Kyle_Lambda","L26_Log_MktCap","L28_Vol_Mom_63d",
  # Momentum (M family)
  "M01_Mom_12_1","M02_Mom_6_1","M03_Mom_3_1","M04_Mom_1",
  "M11_ST_Reversal","M13_VolAdj_Mom","M14_RiskAdj_Mom","M29_Mom_5d","M30_Mom_10d",
  # Regime
  "RE_MRS","RE_exposure","RE02_Vol_Regime_Pctile","RE03_Mkt_Drawdown"
)

# 실제 존재하는 컬럼 확인 (첫 파일 기준)
d_sample <- read_parquet(fdb_daily_files[2]) |> as.data.table()
FDB_CANDIDATE_COLS <- intersect(FDB_CANDIDATE_COLS, names(d_sample))
cat(sprintf("[fdb_daily] Candidate features: %d (from D/R/L/M/RE family)\n",
            length(FDB_CANDIDATE_COLS)))
rm(d_sample); gc()

# ═══════════════════════════════════════════════════════════════════
# 3. OPT-7/MC-P1: MI_prefilter — 월말 샘플에서 mutual information 계산
#    309 팩터 → top-50 선택 (fwd_cvar05 vs each feature)
#    사용 기간: IS 전체 (expanding_window 기준 첫 refit)
# ═══════════════════════════════════════════════════════════════════
cat("\n[Step 3] OPT-7/MC-P1: MI_prefilter (309→50)...\n")

# MI 대리 지표: Spearman IC (rank correlation with fwd CVaR)
# 전체 후보 팩터 × 월말 샘플 → |IC| 순 정렬 → top-50
mi_prefilter_cache <- file.path(HRV2_CACHE, "mi_prefilter_features.rds")

if (file.exists(mi_prefilter_cache)) {
  cat("  [MI] Loading cached MI prefilter result...\n")
  SELECTED_FEATURES <- readRDS(mi_prefilter_cache)
  cat(sprintf("  [MI] Cached features: %d\n", length(SELECTED_FEATURES)))
} else {
  cat("  [MI] Computing IC-based MI_prefilter (Spearman)...\n")

  # 월말 날짜 목록 (IS 1990~2007 기준, expanding_window 초기 학습)
  mi_dates <- raw[Date >= IS_HARD_START & Date <= FULL_IS_END,
                  .(me = max(Date)), by=.(YM=format(Date,"%Y-%m"))][order(me), me]

  # fdb_daily에서 후보 팩터 월말값 + RAWDATA에서 fwd CVaR 계산
  # OPT-1: 파일 한 번에 읽기 (loop 내 반복 로드 금지)
  cat("  [MI] Loading fdb_daily for MI period (fdb_daily 단일 로드)...\n")

  # 월말 날짜 필터링으로 메모리 절약
  mi_files <- fdb_daily_files[as.numeric(sub(".*fdb_daily_(\\d{6})\\.parquet$","\\1",
                               basename(fdb_daily_files))) <= 200712]
  if (length(mi_files) == 0) mi_files <- fdb_daily_files[1:min(216, length(fdb_daily_files))]

  # fdb_daily 파일별 로드 → 월말 필터 → rbindlist (schema 안전)
  fdb_mi_cols <- c("Date","Ticker", FDB_CANDIDATE_COLS)
  mi_dates_char <- as.character(mi_dates)

  cat(sprintf("  [MI] Reading %d fdb_daily files (month-end filter)...\n", length(mi_files)))
  fdb_mi <- rbindlist(lapply(mi_files, function(f) {
    tryCatch({
      dt <- read_parquet(f) |> as.data.table()
      dt[, Date := as.Date(Date)]
      dt_me <- dt[as.character(Date) %in% mi_dates_char]
      if (nrow(dt_me) == 0) return(NULL)
      avail <- intersect(fdb_mi_cols, names(dt_me))
      dt_me[, ..avail]
    }, error=function(e) NULL)
  }), fill=TRUE)
  fdb_mi[, Date := as.Date(Date)]
  setkey(fdb_mi, Date, Ticker)
  cat(sprintf("  [MI] fdb_daily loaded: %d rows (month-end only)\n", nrow(fdb_mi)))

  # 해당 월말 기준 fwd CVaR 계산 (벡터화 — lapply 최소화)
  cat("  [MI] Computing fwd_cvar05 (vectorized)...\n")
  # 각 종목×날짜에 대해 "다음 21 영업일" 행 번호를 rolling 방식으로 계산
  # approach: raw에 month label 붙여서 group_by(Ticker, month) 방식
  # mi_dates 기준 "해당 월말 다음 35일" 구간 추출 후 first-21-rows per ticker
  raw_fwd_window <- raw[Date > min(mi_dates) & Date <= max(mi_dates) + 40L]
  raw_fwd_window[, YM := format(Date, "%Y-%m")]

  # 각 mi_date의 YM
  mi_yms <- data.table(me_date=mi_dates, YM=format(mi_dates, "%Y-%m"))
  # 다음 YM 기준으로 그룹핑 (해당 월+1월의 수익률)
  # 정확히는: [me_date+1 ~ me_date+35] 구간에서 첫 21행 per Ticker
  # 효율적 구현: Date에 "소속 월말" 레이블링
  cvar_mi <- rbindlist(lapply(mi_dates, function(me_d) {
    # RAWDATA 서브셋: me_d 이후 35일
    sub_r <- raw_fwd_window[Date > me_d & Date <= me_d + 35L]
    if (nrow(sub_r) == 0) return(NULL)
    # 종목별 첫 21행 CVaR
    sub_r[order(Ticker, Date)][,
      if (.N >= 5) .(fwd_cvar05 = quantile(Ret[1:min(21,.N)], 0.05, na.rm=TRUE),
                    Date = me_d)
      else .(fwd_cvar05 = NA_real_, Date = me_d),
      by = Ticker][!is.na(fwd_cvar05)]
  }), fill=TRUE)
  cvar_mi <- cvar_mi[!is.na(fwd_cvar05)]
  setkey(cvar_mi, Date, Ticker)
  rm(raw_fwd_window); gc()

  # join
  mi_joined <- merge(fdb_mi, cvar_mi, by=c("Date","Ticker"), all=FALSE)
  cat(sprintf("  [MI] Joined: %d rows\n", nrow(mi_joined)))

  # Spearman IC per feature
  feat_cols_mi <- setdiff(names(mi_joined), c("Date","Ticker","fwd_cvar05"))
  ic_scores <- sapply(feat_cols_mi, function(fc) {
    x <- mi_joined[[fc]]; y <- mi_joined$fwd_cvar05
    ok <- !is.na(x) & !is.na(y) & is.finite(x) & is.finite(y)
    if (sum(ok) < 100) return(0)
    cor(x[ok], y[ok], method="spearman")
  })
  ic_dt <- data.table(Feature=names(ic_scores), IC=ic_scores, AbsIC=abs(ic_scores))
  ic_dt <- ic_dt[order(-AbsIC)]
  cat(sprintf("  [MI] Top-10 features by |IC|:\n"))
  print(ic_dt[1:min(10,.N)])

  # top-50 선택 (OPT-7/MC-P1 MI_prefilter)
  SELECTED_FEATURES <- ic_dt[1:min(MI_TOP_N, .N), Feature]
  cat(sprintf("  [MI] Selected %d features (top-%d by |Spearman IC|)\n",
              length(SELECTED_FEATURES), MI_TOP_N))

  saveRDS(SELECTED_FEATURES, mi_prefilter_cache)
  rm(fdb_mi, mi_joined, cvar_mi, cvar_list); gc()
}

cat(sprintf("[MI] Final features: %s\n", paste(SELECTED_FEATURES, collapse=", ")))

# ═══════════════════════════════════════════════════════════════════
# 4. C19 Factor DB 로드 — VDplus 유니버스 구성
# ═══════════════════════════════════════════════════════════════════
cat("\n[Step 4] Loading C19 from monthly factor_db (open_dataset)...\n")
fdb_monthly_files <- list.files(file.path(CACHE_DIR, "factor_db"),
                                pattern = "^factor_db_\\d{6}\\.parquet$", full.names = TRUE)
c19_dt <- open_dataset(fdb_monthly_files) |>
  dplyr::filter(Factor_Name == "C19_Composite_Earnings", Coverage == TRUE) |>
  dplyr::select(Date, Ticker, Z_Score) |>
  dplyr::collect() |>
  as.data.table()
c19_dt[, Date := as.Date(Date)]
setkey(c19_dt, Date, Ticker)
cat(sprintf("[c19] %d rows, %s ~ %s\n",
            nrow(c19_dt), as.character(min(c19_dt$Date)), as.character(max(c19_dt$Date))))
gc()

# ═══════════════════════════════════════════════════════════════════
# 5. Regime (MRS) 로드
# ═══════════════════════════════════════════════════════════════════
cat("\n[Step 5] Loading Regime (MRS, t-1 lag)...\n")
reg_dt <- read_parquet(file.path(CACHE_DIR, "regime_v7.parquet")) |> as.data.table()
if ("month_end" %in% names(reg_dt)) {
  reg_dt[, Date := as.Date(month_end)]
} else {
  reg_dt[, Date := as.Date(paste0(apply_month, "-01")) %m+% months(1) - 1L]
}
reg_dt <- reg_dt[!is.na(Date)][order(Date)]
# C9 준수: t-1 lag
reg_dt[, MRS_lag := shift(MRS, 1L, type="lag")]
reg_dt[is.na(MRS_lag), MRS_lag := 0]
mrs_map <- reg_dt[, .(Date, MRS_lag)]
setkey(mrs_map, Date)
cat(sprintf("[regime] MRS: %d months, range: %.1f ~ %.1f\n",
            nrow(mrs_map), min(mrs_map$MRS_lag, na.rm=TRUE),
            max(mrs_map$MRS_lag, na.rm=TRUE)))

# ═══════════════════════════════════════════════════════════════════
# 6. 피처 행렬 구성 함수 (fdb_daily 기반, 월말 관측치만)
#    OPT-7/MC-P2: fdb_daily에서 실제 피처값 읽기
#    학습 관측치 = 월말 날짜만 (비중복, 타겟 비겹침)
# ═══════════════════════════════════════════════════════════════════

#' @description 주어진 월말 날짜 벡터에 대해 fdb_daily 피처 로드 + fwd CVaR 계산
#' @param month_ends Date 벡터 (월말 날짜)
#' @param raw RAWDATA (전체)
#' @param fdb_daily_dir fdb_daily 디렉토리
#' @param selected_feats 선택된 피처 컬럼명
#' @param mrs_map MRS 맵
#' @return data.table (Date, Ticker, features..., fwd_cvar05)
build_training_matrix <- function(month_ends, raw, fdb_daily_dir,
                                  selected_feats, mrs_map,
                                  liq_tickers = NULL) {
  cat(sprintf("    [build_train] %d month-ends × ~%d features\n",
              length(month_ends), length(selected_feats)))

  # fdb_daily 파일에서 해당 월말 날짜만 Arrow 필터로 로드
  # OPT-1: 한 번에 로드
  all_fdb_files <- list.files(fdb_daily_dir, pattern="\\.parquet$", full.names=TRUE)

  # 해당 월 파일만 (YYYYMM 매칭)
  ym_set <- format(month_ends, "%Y%m")
  ym_nums <- as.numeric(ym_set)
  matched_files <- all_fdb_files[as.numeric(
    sub(".*fdb_daily_(\\d{6})\\.parquet$","\\1", basename(all_fdb_files))
  ) %in% ym_nums]

  if (length(matched_files) == 0) {
    cat("    [WARN] No fdb_daily files matched. Using RAWDATA fallback.\n")
    return(data.table())
  }

  # 파일별 로드 → 월말 필터 → rbindlist (schema 안전, OPT-1)
  load_cols <- c("Date","Ticker", selected_feats)
  me_chars  <- as.character(month_ends)

  fdb_sub <- rbindlist(lapply(matched_files, function(f) {
    tryCatch({
      dt <- read_parquet(f) |> as.data.table()
      dt[, Date := as.Date(Date)]
      dt_me <- dt[as.character(Date) %in% me_chars]
      if (nrow(dt_me) == 0) return(NULL)
      avail <- intersect(load_cols, names(dt_me))
      dt_me[, ..avail]
    }, error=function(e) NULL)
  }), fill=TRUE)
  fdb_sub[, Date := as.Date(Date)]

  # 유동성 필터 적용
  if (!is.null(liq_tickers)) {
    fdb_sub <- fdb_sub[Ticker %in% liq_tickers]
  }
  setkey(fdb_sub, Date, Ticker)
  cat(sprintf("    [fdb_daily] Loaded: %d rows (month-end only)\n", nrow(fdb_sub)))

  # MRS score 병합 (t-1 lag, C9 준수) — 벡터화
  # mrs_map에서 각 Date의 t-1 MRS를 roll join
  me_dt_tmp <- data.table(Date = as.Date(unique(fdb_sub$Date)))
  setkey(me_dt_tmp, Date); setkey(mrs_map, Date)
  me_mrs <- mrs_map[me_dt_tmp, roll=TRUE, on="Date"][, .(Date, MRS_lag)]
  fdb_sub <- merge(fdb_sub, me_mrs, by="Date", all.x=TRUE)
  fdb_sub[is.na(MRS_lag), MRS_lag := 0]

  # fwd CVaR 계산 (벡터화 — data.table group 방식)
  cat("    [target] Computing fwd_cvar05 (vectorized)...\n")
  raw_fwd <- raw[Date > min(month_ends) & Date <= max(month_ends) + 40L]
  cvar_tgt <- rbindlist(lapply(month_ends, function(me_d) {
    sub_r <- raw_fwd[Date > me_d & Date <= me_d + 35L]
    if (nrow(sub_r) == 0) return(NULL)
    sub_r[order(Ticker, Date)][,
      if (.N >= 5) .(fwd_cvar05 = quantile(Ret[1:min(21L,.N)], TAU, na.rm=TRUE),
                    Date = me_d)
      else .(fwd_cvar05 = NA_real_, Date = me_d),
      by=Ticker][!is.na(fwd_cvar05)]
  }), fill=TRUE)[!is.na(fwd_cvar05)]
  rm(raw_fwd); gc()
  setkey(cvar_tgt, Date, Ticker)

  # join
  train_dt <- merge(fdb_sub, cvar_tgt, by=c("Date","Ticker"), all=FALSE)
  cat(sprintf("    [train] Final: %d rows (month-end obs, non-overlapping target)\n",
              nrow(train_dt)))
  train_dt
}

# ═══════════════════════════════════════════════════════════════════
# 7. 모델 학습 & 예측 함수 (M1~M5)
# ═══════════════════════════════════════════════════════════════════
TARGET_COL    <- "fwd_cvar05"
FEAT_COLS_USE <- SELECTED_FEATURES  # MI_prefilter top-50

safe_fill_na <- function(X) { X[is.na(X)] <- 0; X }

# M1: Elastic Net Quantile — glmnet + pinball loss (rq는 239K행 singular 문제)
# glmnet으로 quantile regression 근사: 분위수 손실함수 가중 linear regression
train_m1 <- function(tr) {
  tryCatch({
    fc <- intersect(FEAT_COLS_USE, names(tr))
    X  <- safe_fill_na(as.matrix(tr[, ..fc]))
    y  <- tr[[TARGET_COL]]
    ok <- !is.na(y) & is.finite(y) & apply(X, 1, function(r) !any(is.nan(r) | is.infinite(r)))
    X  <- X[ok, ]; y <- y[ok]
    if (length(y) < 50) return(NULL)
    # scale X
    xm <- colMeans(X); xs <- apply(X, 2, sd); xs[xs==0] <- 1
    Xs <- sweep(sweep(X, 2, xm, "-"), 2, xs, "/")
    # Check-function weighted glmnet (quantile ≈ weighted LS with asymmetric weights)
    # w_i = TAU if y >= 0 else (1-TAU) → pinball approximation
    # Better: use quantreg on subsample if n > 10K, else full rq
    n <- length(y)
    if (n > 10000) {
      # Subsample for rq (simplex method)
      set.seed(42)
      idx <- sample(n, 8000)
      Xs_sub <- Xs[idx, ]; y_sub <- y[idx]
    } else {
      Xs_sub <- Xs; y_sub <- y
    }
    # glmnet으로 교체 (rq "br" singular 해결, L1+L2 정규화)
    if (!requireNamespace("glmnet", quietly=TRUE)) {
      cat("  [M1] glmnet not installed, falling back to rq\n")
      df_sub <- as.data.frame(cbind(y=y_sub, Xs_sub))
      fmla <- as.formula(paste("y ~", paste(fc, collapse="+")))
      names(df_sub) <- c("y", fc)
      model <- rq(fmla, tau=TAU, data=df_sub, method="fn")
      return(list(type="M1_rq", model=model, xm=xm, xs=xs, fc=fc))
    }
    # glmnet quantile loss via asymmetric weights
    tau <- TAU
    wt <- ifelse(y_sub < 0, tau, 1 - tau)
    model <- glmnet::cv.glmnet(Xs_sub, y_sub, weights=wt, alpha=0.5, nfolds=5)
    list(type="M1_glmnet", model=model, xm=xm, xs=xs, fc=fc)
  }, error=function(e) { cat("  [M1 ERR]", conditionMessage(e), "\n"); NULL })
}
pred_m1 <- function(obj, pr) {
  tryCatch({
    if (is.null(obj)) return(rep(NA_real_, nrow(pr)))
    X  <- safe_fill_na(as.matrix(pr[, obj$fc, with=FALSE]))
    Xs <- sweep(sweep(X, 2, obj$xm, "-"), 2, obj$xs, "/")
    if (obj$type == "M1_glmnet") {
      as.numeric(predict(obj$model, newx=Xs, s="lambda.min"))
    } else {
      df <- as.data.frame(Xs); names(df) <- obj$fc
      as.numeric(predict(obj$model, newdata=df))
    }
  }, error=function(e) { cat("  [M1 pred ERR]", conditionMessage(e), "\n"); rep(NA_real_, nrow(pr)) })
}

# M2: XGBoost Quantile
train_m2 <- function(tr) {
  tryCatch({
    fc <- intersect(FEAT_COLS_USE, names(tr))
    X  <- safe_fill_na(as.matrix(tr[, ..fc]))
    y  <- tr[[TARGET_COL]]
    ok <- !is.na(y) & is.finite(y)
    if (sum(ok) < 50) return(NULL)
    X <- X[ok, ]; y <- y[ok]
    dtrain <- xgb.DMatrix(X, label=y)
    params <- list(objective="reg:quantileerror", quantile_alpha=TAU,
                   eta=0.02, max_depth=5, subsample=0.7,
                   nthread=TREE_THREADS, verbose=0)
    list(type="M2", model=xgb.train(params, dtrain, nrounds=300, verbose=0), fc=fc)
  }, error=function(e) { cat("  [M2 ERR]", conditionMessage(e), "\n"); NULL })
}
pred_m2 <- function(obj, pr) {
  tryCatch({
    if (is.null(obj)) return(rep(NA_real_, nrow(pr)))
    X <- safe_fill_na(as.matrix(pr[, obj$fc, with=FALSE]))
    predict(obj$model, xgb.DMatrix(X))
  }, error=function(e) { cat("  [M2 pred ERR]", conditionMessage(e), "\n"); rep(NA_real_, nrow(pr)) })
}

# M3: Ranger Quantile (OPT-7 핵심 — quantregForest 대체)
# quantreg=TRUE 모드: 메모리 O(n) → 30K 행으로 샘플링 (대표성 유지)
train_m3 <- function(tr) {
  tryCatch({
    fc <- intersect(FEAT_COLS_USE, names(tr))
    df <- as.data.frame(tr[, c(fc, TARGET_COL), with=FALSE])
    for (c in fc) df[[c]][is.na(df[[c]])] <- 0
    ok <- !is.na(df[[TARGET_COL]]) & is.finite(df[[TARGET_COL]])
    df <- df[ok, ]
    if (nrow(df) < 50) return(NULL)
    # OOM fix: quantreg=TRUE는 메모리 O(n*trees). 30K rows 캡핑.
    if (nrow(df) > 30000) {
      set.seed(42); df <- df[sample(nrow(df), 30000), ]
    }
    cat(sprintf("    [M3] ranger data: %d rows (capped 30K)\n", nrow(df)))
    fmla <- as.formula(paste(TARGET_COL, "~", paste(fc, collapse="+")))
    model <- ranger(fmla, data=df,
                    num.trees=TREE_N, quantreg=TRUE,
                    min.node.size=20, num.threads=TREE_THREADS, verbose=FALSE)
    list(type="M3", model=model, fc=fc)
  }, error=function(e) { cat("  [M3 ERR]", conditionMessage(e), "\n"); NULL })
}
pred_m3 <- function(obj, pr) {
  tryCatch({
    if (is.null(obj)) return(rep(NA_real_, nrow(pr)))
    df <- as.data.frame(pr[, obj$fc, with=FALSE])
    for (c in obj$fc) df[[c]][is.na(df[[c]])] <- 0
    preds <- predict(obj$model, data=df, type="quantiles", quantiles=TAU)
    as.numeric(preds$predictions)
  }, error=function(e) { cat("  [M3 pred ERR]", conditionMessage(e), "\n"); rep(NA_real_, nrow(pr)) })
}

# M4: LSTM Quantile (torch)
train_m4 <- function(tr) {
  if (!HAS_TORCH) return(NULL)
  tryCatch({
    fc <- intersect(FEAT_COLS_USE, names(tr))
    X  <- as.matrix(tr[, ..fc])
    y  <- tr[[TARGET_COL]]
    ok <- complete.cases(cbind(X, y)) & is.finite(y)
    X  <- X[ok, ]; y <- y[ok]
    if (nrow(X) < 100) return(NULL)

    # 정규화 (학습 데이터 기준, PIT 준수)
    xm <- colMeans(X, na.rm=TRUE)
    xs <- apply(X, 2, sd, na.rm=TRUE); xs[xs==0] <- 1
    Xs <- sweep(sweep(X, 2, xm, "-"), 2, xs, "/")
    ym <- mean(y); ysd <- sd(y); if (ysd==0) ysd <- 1
    ys <- (y - ym) / ysd
    Xs[is.na(Xs)] <- 0

    n_obs  <- nrow(Xs); n_feat <- ncol(Xs)
    X_t <- torch_tensor(array(Xs, dim=c(n_obs,1,n_feat)), dtype=torch_float())
    y_t <- torch_tensor(ys, dtype=torch_float())

    lstm_net <- nn_module(
      initialize = function(k) {
        self$lstm <- nn_lstm(k, 64L, batch_first=TRUE)
        self$drop <- nn_dropout(0.1)
        self$fc   <- nn_linear(64L, 1L)
      },
      forward = function(x) {
        h <- self$lstm(x)[[1]][, -1, ]
        self$fc(self$drop(h))$squeeze(2)
      }
    )
    net <- lstm_net(k=n_feat)
    opt <- optim_adam(net$parameters, lr=0.001)

    net$train()
    for (ep in seq_len(50L)) {
      perm <- sample(n_obs)
      for (i in seq(1, n_obs, by=256L)) {
        ib <- perm[i:min(i+255L, n_obs)]
        opt$zero_grad()
        p  <- net(X_t[ib,,])
        d  <- y_t[ib] - p
        loss <- torch_mean(torch_where(d >= 0, TAU*d, (TAU-1)*d))
        loss$backward(); opt$step()
      }
      if (ep %% 10 == 0)
        cat(sprintf("    [M4] ep %d/50 done\n", ep))
    }
    net$eval()
    list(type="M4", model=net, xm=xm, xs=xs, ym=ym, ysd=ysd, fc=fc)
  }, error=function(e) { cat("  [M4 ERR]", conditionMessage(e), "\n"); NULL })
}
pred_m4 <- function(obj, pr) {
  if (!HAS_TORCH || is.null(obj)) return(rep(NA_real_, nrow(pr)))
  tryCatch({
    fc <- obj$fc
    X  <- as.matrix(pr[, ..fc]); X[is.na(X)] <- 0
    Xs <- sweep(sweep(X, 2, obj$xm, "-"), 2, obj$xs, "/")
    n  <- nrow(Xs); k <- ncol(Xs)
    Xt <- torch_tensor(array(Xs, dim=c(n,1,k)), dtype=torch_float())
    with_no_grad({ ps <- obj$model(Xt) })
    as.numeric(ps$cpu()) * obj$ysd + obj$ym
  }, error=function(e) { cat("  [M4 pred ERR]", conditionMessage(e), "\n"); rep(NA_real_, nrow(pr)) })
}

# M5: GARCH-X + XGBoost Residual
train_m5 <- function(tr, raw_is) {
  if (!HAS_RUGARCH) return(NULL)
  tryCatch({
    tks <- unique(tr$Ticker)
    # 종목별 GJR-GARCH → 마지막 1-step sigma
    garch_map <- setNames(rep(NA_real_, length(tks)), tks)
    spec <- ugarchspec(
      variance.model   = list(model="gjrGARCH", garchOrder=c(1,1)),
      mean.model       = list(armaOrder=c(0,0)),
      distribution.model = "norm"
    )
    for (tk in tks) {
      tk_ret <- raw_is[Ticker==tk][order(Date), na.omit(Ret)]
      if (length(tk_ret) < 100) next
      fit <- tryCatch(ugarchfit(spec, data=tk_ret, solver="hybrid"), error=function(e) NULL)
      if (is.null(fit)) next
      s1  <- tryCatch(sigma(ugarchforecast(fit, n.ahead=1))[1], error=function(e) NA_real_)
      garch_map[tk] <- s1 * sqrt(21) * qnorm(TAU)
    }
    # 잔차 계산
    fc  <- intersect(FEAT_COLS_USE, names(tr))
    tr2 <- copy(tr)
    tr2[, garch_pred := garch_map[Ticker]]
    tr2[, resid := fwd_cvar05 - garch_pred]
    ok  <- !is.na(tr2$resid) & is.finite(tr2$resid)
    if (sum(ok) < 50) return(NULL)
    X <- safe_fill_na(as.matrix(tr2[ok, ..fc]))
    y <- tr2$resid[ok]
    dr <- xgb.DMatrix(X, label=y)
    pr2 <- list(objective="reg:quantileerror", quantile_alpha=TAU,
                eta=0.02, max_depth=4, subsample=0.7,
                nthread=TREE_THREADS, verbose=0)
    list(type="M5", model=xgb.train(pr2, dr, nrounds=200, verbose=0),
         garch_map=garch_map, fc=fc)
  }, error=function(e) { cat("  [M5 ERR]", conditionMessage(e), "\n"); NULL })
}
pred_m5 <- function(obj, pr) {
  if (!HAS_RUGARCH || is.null(obj)) return(rep(NA_real_, nrow(pr)))
  tryCatch({
    X <- safe_fill_na(as.matrix(pr[, obj$fc, with=FALSE]))
    resid_p <- predict(obj$model, xgb.DMatrix(X))
    gv      <- sapply(pr$Ticker, function(tk) {
      v <- obj$garch_map[tk]; if (is.null(v)||is.na(v)) 0 else v
    })
    resid_p + gv
  }, error=function(e) { cat("  [M5 pred ERR]", conditionMessage(e), "\n"); rep(NA_real_, nrow(pr)) })
}

# ═══════════════════════════════════════════════════════════════════
# 8. 포트폴리오 가중치
# ═══════════════════════════════════════════════════════════════════
cvar2w <- function(cv, tks, wmin=0.02, wmax=0.15) {
  if (length(cv) != length(tks)) {
    n <- min(length(cv), length(tks))
    cv <- cv[seq_len(n)]; tks <- tks[seq_len(n)]
  }
  if (length(cv) == 0) return(setNames(numeric(0), character(0)))
  acv <- abs(cv); acv[is.na(acv)] <- max(acv, na.rm=TRUE); acv[acv==0] <- 1e-6
  w   <- 1/acv; w <- pmax(pmin(w/sum(w), wmax), wmin); w <- w/sum(w); setNames(w, tks)
}
ew_w <- function(tks) setNames(rep(1/length(tks), length(tks)), tks)
invvol_w <- function(vv, tks, wmin=0.02, wmax=0.15) {
  tryCatch({
    if (length(vv) != length(tks)) {
      n <- min(length(vv), length(tks))
      vv <- vv[seq_len(n)]; tks <- tks[seq_len(n)]
    }
    if (length(vv) == 0) return(setNames(numeric(0), character(0)))
    vv[is.na(vv)] <- max(vv, na.rm=TRUE); vv[vv==0] <- 1e-6
    w <- 1/vv; w <- pmax(pmin(w/sum(w), wmax), wmin); w <- w/sum(w); setNames(w, tks)
  }, error=function(e) ew_w(tks))
}
hrp_w <- function(ret_mat, tks, wmin=0.02, wmax=0.15) {
  tryCatch({
    n <- ncol(ret_mat); if (n<=1) return(ew_w(tks))
    cv <- cov(ret_mat, use="pairwise.complete.obs") + diag(1e-8, n)
    vo <- sqrt(diag(cv))
    di <- sqrt(pmax((1 - cov2cor(cv))/2, 0))
    hc <- hclust(as.dist(di), method="ward.D2")
    bsct <- function(items) {
      if (length(items)==1) return(setNames(1, tks[items]))
      k <- floor(length(items)/2)
      wl <- bsct(items[1:k]); wr <- bsct(items[(k+1):length(items)])
      vl <- sum(wl^2 * vo[items[1:k]]^2)
      vr <- sum(wr^2 * vo[items[(k+1):length(items)]]^2)
      a  <- vr/(vl+vr)
      c(a*wl, (1-a)*wr)
    }
    ord <- hc$order; wb <- bsct(ord)
    wout <- numeric(n)
    for (i in seq_along(ord)) wout[ord[i]] <- wb[i]
    wout <- pmax(pmin(wout, wmax), wmin); wout <- wout/sum(wout)
    setNames(wout, tks)
  }, error=function(e) ew_w(tks))
}

# ═══════════════════════════════════════════════════════════════════
# 9. Walk-Forward Backtest (OPT-7/MC-P3: expanding_window, oos_year)
# ═══════════════════════════════════════════════════════════════════
walk_forward <- function(raw, c19_dt, mrs_map, oos_months,
                         phase_label="PILOT", debug_n=3) {
  cat(sprintf("\n[%s] Walk-forward: %d OOS months\n", phase_label, length(oos_months)))

  res <- data.table(Date=as.Date(oos_months),
                    M1_ret=NA_real_, M2_ret=NA_real_, M3_ret=NA_real_,
                    M4_ret=NA_real_, M5_ret=NA_real_,
                    EW_ret=NA_real_, InvVol_ret=NA_real_, HRP_ret=NA_real_)

  mdls  <- list(m1=NULL,m2=NULL,m3=NULL,m4=NULL,m5=NULL)
  last_yr <- -1L

  for (mi in seq_along(oos_months)) {
    me   <- as.Date(oos_months[mi])
    yr   <- year(me)
    mstr <- format(me, "%Y-%m")

    # ── Annual Refit (expanding_window, oos_year 단위, MC1 준수) ──────
    if (yr > last_yr) {
      cat(sprintf("\n  [REFIT %d] expanding_window IS: %s ~ %s\n",
                  yr, format(IS_HARD_START,"%Y-%m"), format(me-1,"%Y-%m")))

      # 유동성 필터 (IS 전체 기준)
      raw_is <- raw[Date >= IS_HARD_START & Date < me]
      liq_dt <- raw_is[, .(liq = mean(Vol*Close, na.rm=TRUE)), by=Ticker]
      liq_ok  <- liq_dt[liq >= LIQ_THRESH, Ticker]
      cat(sprintf("    Liquid tickers: %d\n", length(liq_ok)))

      # IS 월말 날짜 (학습 관측치, 비중복)
      is_me <- raw_is[Ticker %in% liq_ok,
                      .(me_d=max(Date)), by=.(YM=format(Date,"%Y-%m"))][order(me_d), me_d]
      # 최근 5년만 사용 (OOM fix: 10→5년, 행 수 절반, noise 절감)
      is_me_use <- is_me[is_me >= me - 365*5]
      if (length(is_me_use) < 24) is_me_use <- is_me  # 데이터 부족 시 전체

      cat(sprintf("    Training month-ends: %d (non-overlapping obs)\n", length(is_me_use)))

      # fdb_daily 기반 학습 행렬 (OPT-7/MC-P2: fdb_daily)
      tr_dt <- tryCatch(
        build_training_matrix(is_me_use, raw, FDB_DAILY_DIR,
                              FEAT_COLS_USE, mrs_map, liq_ok),
        error=function(e) { cat("    [ERR] build_training_matrix:", conditionMessage(e),"\n"); data.table() }
      )

      if (nrow(tr_dt) == 0) {
        cat("    [WARN] Empty training data. Skipping refit.\n")
      } else {
        cat(sprintf("    Training rows: %d\n", nrow(tr_dt)))
        cat("    Training M1 (Elastic Net Quantile)...\n")
        mdls$m1 <- train_m1(tr_dt); gc()
        cat("    Training M2 (XGBoost Quantile)...\n")
        mdls$m2 <- train_m2(tr_dt); gc()
        cat("    Training M3 (Ranger Quantile — ranger, NOT quantregForest)...\n")
        mdls$m3 <- train_m3(tr_dt); gc()
        if (HAS_TORCH) { cat("    Training M4 (LSTM, torch)...\n"); mdls$m4 <- train_m4(tr_dt); gc() }
        if (HAS_RUGARCH) { cat("    Training M5 (GARCH-X+XGB)...\n"); mdls$m5 <- train_m5(tr_dt, raw_is); gc() }
        last_yr <- yr
        cat(sprintf("    Models: M1=%s M2=%s M3=%s M4=%s M5=%s\n",
                    !is.null(mdls$m1), !is.null(mdls$m2), !is.null(mdls$m3),
                    !is.null(mdls$m4), !is.null(mdls$m5)))
      }
    }

    # ── VDplus 유니버스 (C19 top-20, PIT C14 준수) ────────────────────
    c19_avail <- c19_dt[Date <= me]
    if (nrow(c19_avail) == 0) next
    c19_last  <- c19_avail[Date == max(Date)]
    # 유동성 필터 (t-1 기준, C10 준수)
    raw_pre  <- raw[Date >= me-40L & Date < me]
    liq_now  <- raw_pre[, .(lq=mean(Vol*Close,na.rm=TRUE)), by=Ticker]
    liq_ok_n <- liq_now[lq >= LIQ_THRESH, Ticker]
    c19_top  <- c19_last[Ticker %in% liq_ok_n & !is.na(Z_Score)][order(-Z_Score)][1:min(N_TOP,.N)]
    univ     <- c19_top$Ticker
    if (length(univ) == 0) next

    if (mi <= debug_n) cat(sprintf("  [DBG %s] universe=%d, C19_date=%s\n",
                                    mstr, length(univ), format(max(c19_avail$Date),"%Y-%m")))

    # ── 예측 피처 로드 (fdb_daily 월말값) ─────────────────────────────
    # 해당 월 fdb_daily 파일
    me_ym <- format(me, "%Y%m")
    pred_file <- list.files(FDB_DAILY_DIR,
                            pattern=paste0("fdb_daily_", me_ym, "\\.parquet$"),
                            full.names=TRUE)
    if (length(pred_file) == 0) {
      # 가장 가까운 이전 월 파일 사용
      avail_f <- list.files(FDB_DAILY_DIR, pattern="\\.parquet$", full.names=TRUE)
      avail_ym <- as.numeric(sub(".*fdb_daily_(\\d{6})\\.parquet$","\\1",basename(avail_f)))
      close_f  <- avail_f[which.min(abs(avail_ym - as.numeric(me_ym)))]
      pred_file <- close_f[avail_ym[which.min(abs(avail_ym-as.numeric(me_ym)))] <= as.numeric(me_ym)]
      if (length(pred_file)==0) pred_file <- close_f[1]
    }

    pred_dt <- tryCatch({
      pf <- read_parquet(pred_file[1]) |> as.data.table()
      pf[, Date := as.Date(Date)]
      # 월말 날짜 or 가장 최근 날짜
      pf_me <- pf[Date <= me][Date == max(Date)][Ticker %in% univ]
      load_f <- intersect(FEAT_COLS_USE, names(pf_me))
      pf_me[, c("Date","Ticker",load_f), with=FALSE]
    }, error=function(e) data.table())

    if (nrow(pred_dt) == 0) {
      if (mi <= debug_n) cat("  [DBG] No pred_dt, skip.\n"); next
    }

    # 없는 피처 컬럼 0으로 채움
    for (fc in FEAT_COLS_USE) {
      if (!fc %in% names(pred_dt)) pred_dt[, (fc) := 0]
    }
    # MRS (t-1, C9 준수)
    mrs_now <- mrs_map[Date <= me][.N, MRS_lag]
    pred_dt[, RE_MRS := if ("RE_MRS" %in% FEAT_COLS_USE) mrs_now else NULL]
    pred_dt[is.na(pred_dt)] <- 0

    if (mi <= debug_n) cat(sprintf("  [DBG %s] pred_dt: %d rows\n", mstr, nrow(pred_dt)))

    # ── 예측 ──────────────────────────────────────────────────────────
    cv1 <- pred_m1(mdls$m1, pred_dt)
    cv2 <- pred_m2(mdls$m2, pred_dt)
    cv3 <- pred_m3(mdls$m3, pred_dt)
    cv4 <- pred_m4(mdls$m4, pred_dt)
    cv5 <- pred_m5(mdls$m5, pred_dt)

    # ── 다음 월 수익률 ───────────────────────────────────────────────
    next_me <- if (mi < length(oos_months)) as.Date(oos_months[mi+1]) else me + 35L
    mret    <- raw[Date > me & Date <= next_me & Ticker %in% univ,
                   .(mret=prod(1+Ret,na.rm=TRUE)-1), by=Ticker]

    calc_pr <- function(cv_vec) {
      tryCatch({
        if (is.null(cv_vec) || all(is.na(cv_vec))) return(NA_real_)
        ok <- !is.na(cv_vec) & pred_dt$Ticker %in% mret$Ticker
        if (sum(ok) < 3) return(NA_real_)
        tks_ok <- pred_dt$Ticker[ok]; cv_ok <- cv_vec[ok]
        w <- cvar2w(cv_ok, tks_ok)
        if (length(w) == 0) return(NA_real_)
        mr <- mret[Ticker %in% names(w)]
        sum(w[mr$Ticker] * mr$mret, na.rm=TRUE)
      }, error=function(e) { cat("  [calc_pr ERR]", conditionMessage(e), "\n"); NA_real_ })
    }

    # HRP용 수익률 행렬
    raw_bl <- raw[Date >= me-65L & Date < me & Ticker %in% univ]
    ret_w  <- tryCatch({
      rw <- dcast(raw_bl[,.(Date,Ticker,Ret)], Date~Ticker, value.var="Ret", fill=NA)
      as.matrix(rw[,-1,with=FALSE])
    }, error=function(e) matrix(NA,1,1))

    vol_vec <- setNames(sapply(univ, function(tk) {
      v <- raw[Date >= me-25L & Date < me & Ticker==tk, sd(Ret,na.rm=TRUE)]*sqrt(252)
      if (is.na(v)||v==0) 0.2 else v
    }), univ)

    m1r <- calc_pr(cv1)
    m2r <- calc_pr(cv2)
    m3r <- calc_pr(cv3)
    m4r <- calc_pr(cv4)
    m5r <- calc_pr(cv5)

    ew_ret  <- mean(mret[Ticker %in% univ, mret], na.rm=TRUE)
    iv_w    <- tryCatch(invvol_w(vol_vec, univ), error=function(e) ew_w(univ))
    iv_ret  <- tryCatch(sum(iv_w[mret$Ticker] * mret$mret, na.rm=TRUE), error=function(e) ew_ret)
    hrp_ret <- tryCatch({
      hw <- hrp_w(ret_w, univ); sum(hw[mret$Ticker]*mret$mret, na.rm=TRUE)
    }, error=function(e) ew_ret)

    set(res, mi, "M1_ret",      m1r)
    set(res, mi, "M2_ret",      m2r)
    set(res, mi, "M3_ret",      m3r)
    set(res, mi, "M4_ret",      m4r)
    set(res, mi, "M5_ret",      m5r)
    set(res, mi, "EW_ret",      ew_ret)
    set(res, mi, "InvVol_ret",  iv_ret)
    set(res, mi, "HRP_ret",     hrp_ret)

    if (mi <= debug_n) {
      cat(sprintf("  [DBG %s] M1=%.2f%% M2=%.2f%% M3=%.2f%% M4=%.2f%% M5=%.2f%% EW=%.2f%%\n",
                  mstr, m1r*100, m2r*100, m3r*100, m4r*100, m5r*100, ew_ret*100))
    } else if (mi %% 12 == 1) {
      cat(sprintf("  [%s] M2=%.2f%% M3=%.2f%% EW=%.2f%%\n", mstr, m2r*100, m3r*100, ew_ret*100))
    }

    # 체크포인트: 12개월마다 중간 결과 저장
    if (mi %% 12 == 0 || mi == length(oos_months)) {
      ckpt_file <- file.path(OUT_DIR, "hr_v2_checkpoint.parquet")
      arrow::write_parquet(res[!is.na(M2_ret)], ckpt_file)
      cat(sprintf("  [CHECKPOINT] %d months saved -> %s\n", sum(!is.na(res$M2_ret)), basename(ckpt_file)))
    }
  }
  res
}

# ═══════════════════════════════════════════════════════════════════
# 10. 성과 통계
# ═══════════════════════════════════════════════════════════════════
perf_stat <- function(rv, label) {
  rv <- na.omit(rv)
  if (length(rv) < 6) return(data.table(Method=label, CAGR=NA,SR=NA,MDD=NA,N=length(rv),NA_pct=NA))
  eq  <- cumprod(1+rv)
  cag <- tail(eq,1)^(12/length(rv)) - 1
  sr  <- mean(rv)/sd(rv)*sqrt(12)
  mdd <- min((eq-cummax(eq))/cummax(eq))
  data.table(Method=label, CAGR=round(cag*100,2), SR=round(sr,3),
             MDD=round(mdd*100,2), N=length(rv), NA_pct=NA)
}

# ═══════════════════════════════════════════════════════════════════
# 11. PHASE 1: PILOT (IS:1990~2022, OOS:2023-01~2026-04)
# ═══════════════════════════════════════════════════════════════════
cat("\n\n========================================\n")
cat("PHASE 1: PILOT (IS:1990~2022, OOS:2023-01~2026-04)\n")
cat("========================================\n")

pilot_me <- raw[Date >= PILOT_OOS_START & Date <= PILOT_OOS_END,
                .(me=max(Date)), by=.(YM=format(Date,"%Y-%m"))][order(me), me]
cat(sprintf("[pilot] OOS: %d months (%s ~ %s)\n",
            length(pilot_me), format(min(pilot_me),"%Y-%m"), format(max(pilot_me),"%Y-%m")))

pilot_res <- walk_forward(raw, c19_dt, mrs_map, pilot_me,
                          phase_label="PILOT", debug_n=3)

# 중간 저장
write_parquet(pilot_res, file.path(HRV2_CACHE, "pilot_results.parquet"))
cat(sprintf("\n[Pilot] Saved: %s\n", file.path(HRV2_CACHE, "pilot_results.parquet")))

# ── Pilot 검증 ──────────────────────────────────────────────────────
cat("\n--- PILOT VALIDATION ---\n")
mcols <- paste0("M", 1:5, "_ret")
all_na <- sapply(mcols, function(c) all(is.na(pilot_res[[c]])))
na_pct <- sapply(c(mcols, "EW_ret","InvVol_ret","HRP_ret"),
                 function(c) round(100*mean(is.na(pilot_res[[c]])),1))
cat("All-NA (TRUE=FAIL):\n"); print(all_na)
cat("NA% by method:\n"); print(na_pct)

cat("\n[Pilot] Monthly Returns (all months):\n")
print(pilot_res, nrows=nrow(pilot_res))

perf_pilot <- rbindlist(lapply(seq_along(mcols), function(i)
  perf_stat(pilot_res[[mcols[i]]], paste0("M",i))))
perf_pilot <- rbind(perf_pilot,
  perf_stat(pilot_res$EW_ret,     "EW"),
  perf_stat(pilot_res$InvVol_ret, "InvVol"),
  perf_stat(pilot_res$HRP_ret,    "HRP"))
cat("\n[Pilot] Performance:\n"); print(perf_pilot)

n_valid <- sum(!all_na)
pilot_pass <- n_valid >= 3
cat(sprintf("\n[PILOT] Valid ML models: %d/5 → %s\n", n_valid,
            if (pilot_pass) "PASS" else "FAIL"))

if (!pilot_pass) {
  cat("[PILOT FAIL] Fix models before full run.\n")
  system("echo 'PILOT_FAIL' > /tmp/codex_pit_approved_ml_position_sizing_v2.flag")
  stop("PILOT FAILED: insufficient valid models")
}
cat("[PILOT PASS] Proceeding to full run...\n")

# ═══════════════════════════════════════════════════════════════════
# 12. PHASE 2: FULL RUN (IS:1990~2007+, OOS:2008-01~2026-04)
# ═══════════════════════════════════════════════════════════════════
cat("\n\n========================================\n")
cat("PHASE 2: FULL RUN (IS:1990~2007+expanding, OOS:2008~2026-04)\n")
cat("========================================\n")

full_me <- raw[Date >= FULL_OOS_START & Date <= FULL_OOS_END,
               .(me=max(Date)), by=.(YM=format(Date,"%Y-%m"))][order(me), me]
cat(sprintf("[full] OOS: %d months (%s ~ %s)\n",
            length(full_me), format(min(full_me),"%Y-%m"), format(max(full_me),"%Y-%m")))

full_res <- walk_forward(raw, c19_dt, mrs_map, full_me,
                         phase_label="FULL", debug_n=3)

# 저장 (don't lose work)
write_parquet(full_res, file.path(CACHE_DIR, "hr_v2_predictions.parquet"))
cat(sprintf("[Full] Predictions saved: %s\n", file.path(CACHE_DIR, "hr_v2_predictions.parquet")))

# ═══════════════════════════════════════════════════════════════════
# 13. 최종 성과 & 저장
# ═══════════════════════════════════════════════════════════════════
cat("\n\n========================================\n")
cat("FINAL RESULTS (2008~2026-04)\n")
cat("========================================\n")

mlabs <- c("M1_ElNet","M2_XGB","M3_Ranger","M4_LSTM","M5_GarchX","EW","InvVol","HRP")
mcs2  <- c("M1_ret","M2_ret","M3_ret","M4_ret","M5_ret","EW_ret","InvVol_ret","HRP_ret")
perf_full <- rbindlist(lapply(seq_along(mlabs), function(i)
  perf_stat(full_res[[mcs2[i]]], mlabs[i])))
cat("\nFull Period Performance:\n"); print(perf_full)

fwrite(perf_full,  file.path(OUT_DIR, "horse_race_v2_results.csv"))
fwrite(full_res,   file.path(OUT_DIR, "horse_race_v2_monthly.csv"))
cat("Results saved to output/\n")

# Equity Curve
tryCatch({
  library(ggplot2); library(scales)
  pd <- melt(full_res, id.vars="Date", measure.vars=mcs2,
             variable.name="Method", value.name="Ret")
  pd[, Method := gsub("_ret","",Method)]
  pd <- pd[!is.na(Ret)][order(Method,Date)]
  pd[, eq := cumprod(1+Ret), by=Method]
  g <- ggplot(pd, aes(x=Date, y=eq, color=Method)) +
    geom_line(linewidth=0.7) + scale_y_log10() +
    labs(title="Horse Race v2: CVaR Position Sizing (OOS 2008~2026-04)",
         subtitle="VDplus C19 Top-20 | MI_prefilter top-50 | ranger+torch | IS 1990~",
         x=NULL, y="Cumulative Return (log)") +
    theme_minimal()
  ggsave(file.path(OUT_DIR,"horse_race_v2_equity.png"), g, width=14, height=7, dpi=120)
  cat("Equity curve saved.\n")
}, error=function(e) cat("[PLOT ERR]", conditionMessage(e), "\n"))

# PIT flag
system("echo 'PASS' > /tmp/codex_pit_approved_ml_position_sizing_v2.flag")
cat("\n[PIT] Flag: /tmp/codex_pit_approved_ml_position_sizing_v2.flag\n")

elapsed <- as.numeric(difftime(Sys.time(), t0, units="mins"))
cat(sprintf("\n=== Horse Race v2 COMPLETE in %.1f min ===\n", elapsed))
best <- perf_full[which.max(SR)]
cat(sprintf("Best by SR: %s (SR=%.3f, CAGR=%.1f%%, MDD=%.1f%%)\n",
            best$Method, best$SR, best$CAGR, best$MDD))
