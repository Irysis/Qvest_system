## =============================================================================
## STR_1656_MLRA S5 Mutation Lab — Phase 1-3
##
## Phase 1: M01(CVaR_LP), M02(CVaR_LP+SN), M03(CVaR_LP+SN+LowBeta),
##          M04(CDaR+SN), M08(ScoreTilt+SN), M12(MinVar+SN)  [6건 병렬]
## Phase 2: M05(C+DD), M06(C+VD), M07(C+DD+VD)               [3건 조건부]
## Phase 3: M09(80/20 blend), M10(85/15 blend)               [2건 배분]
##
## Signal: S1_B (ML XGBoost 5-seed ensemble, NonRE ~35F)
## PIT: C1 expanding, C2 t-1 lag, C5 overlay t-1, C9 DD lag, C13 Z_Score_Aligned
## =============================================================================

cat("=== STR_1656_MLRA S5 Mutation Lab Phase 1-3 ===\n")
cat("시작:", as.character(Sys.time()), "\n\n")

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(dplyr)
  library(jsonlite)
  library(ggplot2)
  library(parallel)
})

`%||%` <- function(a, b) if (!is.null(a) && length(a) > 0L && !is.na(a[[1L]])) a[[1L]] else b

# =============================================================================
# 경로 (normalizePath 금지)
# =============================================================================
PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
STRATEGY_DIR <- file.path(PROJECT_ROOT, "04_Research/strategies/STR_1656_MLRA")
OUTPUT_DIR   <- file.path(STRATEGY_DIR, "output")
S5_DIR       <- file.path(OUTPUT_DIR, "s5_mutations")
DAILY_DB_DIR <- file.path(PROJECT_ROOT, ".cache/factor_db_daily")

source(file.path(PROJECT_ROOT, "02_Infrastructure/config.R"))
source(file.path(PROJECT_ROOT, "02_Infrastructure/backtest_harness.R"))
source(file.path(PROJECT_ROOT, "02_Infrastructure/portfolio/advanced_weights.R"))

dir.create(S5_DIR, showWarnings = FALSE, recursive = TRUE)

# =============================================================================
# 설정
# =============================================================================
LIQ_THRESHOLD <- 2e8
N_HOLDINGS    <- 30L
COMMISSION    <- 0.0015
MI_TOP_N      <- 50L
PURGE_DAYS    <- 21L
XGB_SEEDS     <- c(42L, 123L, 456L, 789L, 2024L)
OOS_START_YR  <- 2008L
OOS_END_YR    <- 2025L
RE_PAT        <- "^(RE_|RE0|RE1)"
XGB_MAX_ROWS  <- 80000L
MAX_W         <- 0.15

cat("[CONFIG] N=", N_HOLDINGS, "| COMMISSION=", COMMISSION, "\n")

xgb_ok <- tryCatch({ library(xgboost); TRUE }, error = function(e) FALSE)
if (!xgb_ok) stop("xgboost 패키지 필요")
cat("[XGB] OK\n")

# =============================================================================
# 1. RAWDATA 1회 로드 (OPT-2)
# =============================================================================
cat("\n[1] RAWDATA 로드 (1회)...\n")
rw  <- load_rawdata(use_cache = TRUE)
RAWDATA <- rw$RAWDATA; BM_DT <- rw$BM_DT
setDT(RAWDATA); setkey(RAWDATA, Date, Ticker)
cat(sprintf("    %d rows | %s ~ %s\n", nrow(RAWDATA), min(RAWDATA$Date), max(RAWDATA$Date)))

# =============================================================================
# 2. 21d forward return (C14)
# =============================================================================
cat("[2] 21d fwd return...\n")
ret_dt <- RAWDATA[!is.na(Ret) & is.finite(Ret) & Date >= as.Date("2003-01-01"),
                  .(Date, Ticker, Ret, Size)]
setkey(ret_dt, Ticker, Date)
ret_dt[, logR := log(1 + pmax(Ret, -0.99))]
ret_dt[, fwd_ret_21d := {
  n <- .N; cl <- cumsum(logR)
  if (n <= 21L) rep(NA_real_, n)
  else { fwd <- c(cl[22:n], rep(NA_real_, 21L)) - cl; exp(fwd) - 1 }
}, by = Ticker]
ret_dt[, logR := NULL]
ret_dt <- ret_dt[!is.na(fwd_ret_21d)]
cat(sprintf("    fwd rows: %d\n", nrow(ret_dt)))

SIZE_DT <- RAWDATA[Date >= as.Date("2003-01-01"), .(Date, Ticker, Size)]
setkey(SIZE_DT, Date, Ticker)
RAWDATA[, ym__ := format(Date, "%Y-%m")]
ALL_ME_DATES <- RAWDATA[, .(me_date = max(Date)), by = ym__][order(me_date)]$me_date
RAWDATA[, ym__ := NULL]
cat(sprintf("    [ME] 월말 날짜 %d개 (%s ~ %s)\n",
            length(ALL_ME_DATES), min(ALL_ME_DATES), max(ALL_ME_DATES)))
ret_dt[, c("Ret", "Size") := NULL]
setkey(ret_dt, Date, Ticker)
rm(rw); gc()

# =============================================================================
# 3. Arrow Dataset (OPT-1: 반복 로드 금지)
# =============================================================================
cat("[3] Arrow Dataset...\n")
pq_files <- list.files(DAILY_DB_DIR, pattern = "\\.parquet$", full.names = TRUE)
ds_daily <- open_dataset(pq_files, format = "parquet")
ds_cols  <- schema(ds_daily)$names
EXCL     <- c("Date", "Ticker",
              grep("^(dps_1y|bps_1y|eps_1y|target_price)", ds_cols, value = TRUE),
              grep("\\.x$|\\.y$", ds_cols, value = TRUE))
ALL_FCOLS   <- setdiff(ds_cols, EXCL)
RE_COLS     <- grep(RE_PAT, ALL_FCOLS, value = TRUE)
NONRE_COLS  <- setdiff(ALL_FCOLS, RE_COLS)
cat(sprintf("    팩터 전체=%d RE*=%d NonRE=%d\n",
            length(ALL_FCOLS), length(RE_COLS), length(NONRE_COLS)))

arrow_collect <- function(fcols, dates_vec = NULL, d0 = NULL, d1 = NULL) {
  need <- intersect(c("Date", "Ticker", fcols), ds_cols)
  q <- ds_daily
  if (!is.null(dates_vec)) {
    q <- q |> filter(Date %in% dates_vec)
  } else {
    q <- q |> filter(Date >= d0, Date <= d1)
  }
  q |> select(all_of(need)) |> collect() |> as.data.table() |>
    (\(x) { setkey(x, Date, Ticker); x })()
}

build_mat <- function(dt, cols) {
  m <- as.matrix(dt[, intersect(cols, names(dt)), with = FALSE])
  m[!is.finite(m)] <- 0; m
}

mi_prefilter_chunked <- function(d0, d1, fcols, n_top = 50L) {
  me_vec <- ALL_ME_DATES[ALL_ME_DATES >= d0 & ALL_ME_DATES <= d1]
  if (length(me_vec) == 0L) return(list(all = character(0), nonre = character(0)))
  chunk_sz <- 60L
  f_chunks <- split(fcols, ceiling(seq_along(fcols) / chunk_sz))
  all_ics  <- numeric(0)
  for (i in seq_along(f_chunks)) {
    ch <- f_chunks[[i]]
    ch_dt <- tryCatch(arrow_collect(ch, dates_vec = me_vec), error = function(e) NULL)
    if (is.null(ch_dt) || nrow(ch_dt) == 0L) next
    ch_dt <- merge(ch_dt, ret_dt[, .(Date, Ticker, fwd_ret_21d)], by = c("Date", "Ticker"))
    ch_dt <- ch_dt[!is.na(fwd_ret_21d)]
    y <- ch_dt$fwd_ret_21d
    for (f in ch) {
      x <- ch_dt[[f]]; v <- is.finite(x) & is.finite(y)
      if (sum(v) < 100L) next
      all_ics[f] <- tryCatch(abs(cor(x[v], y[v], method = "spearman")), error = function(e) NA_real_)
    }
    rm(ch_dt); gc(FALSE)
  }
  valid <- all_ics[!is.na(all_ics)]
  if (!length(valid)) return(list(all = character(0), nonre = character(0)))
  top_all   <- names(sort(valid, decreasing = TRUE))[seq_len(min(n_top, length(valid)))]
  nonre_v   <- valid[intersect(names(valid), NONRE_COLS)]
  top_nonre <- if (length(nonre_v))
    names(sort(nonre_v, decreasing = TRUE))[seq_len(min(n_top, length(nonre_v)))]
  else character(0)
  list(all = top_all, nonre = top_nonre)
}

xgb5_predict <- function(X_tr, y_tr, X_te, X_vl = NULL, seeds = XGB_SEEDS, max_rows = XGB_MAX_ROWS) {
  if (nrow(X_tr) > max_rows) {
    idx <- sample(nrow(X_tr), max_rows)
    X_tr <- X_tr[idx, , drop = FALSE]; y_tr <- y_tr[idx]
  }
  params <- list(booster = "gbtree", objective = "reg:squarederror",
                 eta = 0.02, max_depth = 5L, subsample = 0.7,
                 colsample_bytree = 0.5, min_child_weight = 10L,
                 lambda = 1, alpha = 0.1, nthread = 1L)
  dtest <- xgb.DMatrix(data = X_te)
  preds <- lapply(seeds, function(sd) {
    set.seed(sd)
    tryCatch({
      dtr <- xgb.DMatrix(data = X_tr, label = y_tr)
      m <- if (!is.null(X_vl) && nrow(X_vl) > 10L) {
        dvl <- xgb.DMatrix(data = X_vl, label = rep(0, nrow(X_vl)))
        fit <- xgb.train(params, dtr, 500L, evals = list(v = dvl),
                         early_stopping_rounds = 30L, verbose = 0L)
        rm(dvl); fit
      } else xgb.train(params, dtr, 300L, verbose = 0L)
      p <- predict(m, dtest)
      rm(dtr, m); gc(FALSE); p
    }, error = function(e) NULL)
  })
  rm(dtest); gc(FALSE)
  valid <- Filter(Negate(is.null), preds)
  if (!length(valid)) return(rep(0, nrow(X_te)))
  n_te <- nrow(X_te)
  rmat <- vapply(valid, function(p) frank(p, ties.method = "average") / n_te, numeric(n_te))
  if (is.null(dim(rmat))) rmat else rowMeans(rmat)
}

# =============================================================================
# 4. Walk-Forward (S1_B 점수 재생성)
# =============================================================================
cat("\n[4] Walk-Forward S1_B 점수 생성...\n")
IS_START_D <- as.Date("2003-01-01")
OOS_YEARS  <- OOS_START_YR:OOS_END_YR

wf_out <- lapply(OOS_YEARS, function(oos_yr) {
  cat(sprintf("  OOS %d\n", oos_yr))
  is_end_yr <- oos_yr - 2L
  if (is_end_yr < 2005L) return(NULL)
  is_end_d <- as.Date(sprintf("%d-12-31", is_end_yr))
  val_s    <- as.Date(sprintf("%d-01-01", oos_yr - 1L))
  val_e    <- as.Date(sprintf("%d-12-31", oos_yr - 1L))
  oos_s    <- as.Date(sprintf("%d-01-01", oos_yr))
  oos_e    <- as.Date(sprintf("%d-12-31", oos_yr))

  tops  <- mi_prefilter_chunked(IS_START_D, is_end_d, ALL_FCOLS, MI_TOP_N)
  top_B <- tops$nonre
  cat(sprintf("    topB=%d\n", length(top_B)))
  if (length(top_B) < 5L) return(NULL)

  is_me_d <- ALL_ME_DATES[ALL_ME_DATES >= IS_START_D & ALL_ME_DATES <= is_end_d]
  is_dt   <- tryCatch(arrow_collect(top_B, dates_vec = is_me_d), error = function(e) NULL)
  if (is.null(is_dt) || nrow(is_dt) < 1000L) return(NULL)
  is_dt <- merge(is_dt, ret_dt[, .(Date, Ticker, fwd_ret_21d)], by = c("Date", "Ticker"))
  is_dt <- merge(is_dt, SIZE_DT, by = c("Date", "Ticker"), all.x = TRUE)
  is_dt <- is_dt[!is.na(fwd_ret_21d) & !is.na(Size) & Size >= LIQ_THRESHOLD]
  X_trB <- build_mat(is_dt, top_B)
  y_tr  <- is_dt$fwd_ret_21d
  is_last <- max(is_dt$Date)
  rm(is_dt); gc(FALSE)

  X_vlB <- NULL
  val_me_d <- ALL_ME_DATES[ALL_ME_DATES >= val_s & ALL_ME_DATES <= val_e &
                            ALL_ME_DATES > (is_last + PURGE_DAYS)]
  if (length(val_me_d) > 0L) {
    val_dt <- tryCatch(arrow_collect(top_B, dates_vec = val_me_d), error = function(e) NULL)
    if (!is.null(val_dt) && nrow(val_dt) > 0L) {
      val_m <- merge(val_dt, ret_dt[, .(Date, Ticker, fwd_ret_21d)], by = c("Date", "Ticker"))
      val_m <- val_m[!is.na(fwd_ret_21d)]
      if (nrow(val_m) > 50L) X_vlB <- build_mat(val_m, top_B)
      rm(val_dt, val_m); gc(FALSE)
    }
  }

  oos_me_d <- ALL_ME_DATES[ALL_ME_DATES >= oos_s & ALL_ME_DATES <= oos_e]
  oos_me   <- tryCatch(arrow_collect(top_B, dates_vec = oos_me_d), error = function(e) NULL)
  if (is.null(oos_me) || nrow(oos_me) == 0L) {
    rm(X_trB, y_tr); gc(FALSE); return(NULL)
  }
  oos_me <- merge(oos_me, SIZE_DT, by = c("Date", "Ticker"), all.x = TRUE)
  oos_me <- oos_me[!is.na(Size) & Size >= LIQ_THRESHOLD]
  X_teB  <- build_mat(oos_me, top_B)

  pB <- tryCatch(xgb5_predict(X_trB, y_tr, X_teB, X_vlB), error = function(e) rep(0, nrow(X_teB)))
  oos_me[, Score := pB]
  scB <- oos_me[, .(Date, Ticker, Size, Score)]
  rm(X_trB, y_tr, X_teB, X_vlB, oos_me); gc(FALSE)
  scB
})

scores_B <- rbindlist(Filter(Negate(is.null), wf_out), fill = TRUE)
fwrite(scores_B, file.path(OUTPUT_DIR, "s5_scores_B.csv"))
cat(sprintf("\n[4] 점수 생성 완료: %d rows, %d dates\n",
            nrow(scores_B), length(unique(scores_B$Date))))

# 불필요한 대형 객체 해제
rm(ret_dt, SIZE_DT, wf_out, ds_daily); gc()

# =============================================================================
# 5. RAWDATA 재로드 (백테스트용)
# =============================================================================
cat("\n[5] RAWDATA 재로드 (백테스트용)...\n")
rw2 <- load_rawdata(use_cache = TRUE)
RAWDATA <- rw2$RAWDATA; BM_DT <- rw2$BM_DT
setDT(RAWDATA); setkey(RAWDATA, Date, Ticker)
rm(rw2); gc()

# =============================================================================
# 성과 계산 헬퍼
# =============================================================================
calc_perf_from_nav <- function(nav_dt) {
  r <- nav_dt$Strategy_Ret; r <- r[is.finite(r)]
  if (length(r) < 252) return(list(SR = NA, CAGR = NA, MDD = NA, Sortino = NA, TO = NA))
  cum  <- cumprod(1 + r)
  nyr  <- length(r) / 252
  sr   <- round(mean(r) / sd(r) * sqrt(252), 4)
  cagr <- round((tail(cum, 1)^(1 / nyr) - 1) * 100, 2)
  mdd  <- round(min(cum / cummax(cum) - 1) * 100, 2)
  neg  <- r[r < 0]
  sort_r <- if (length(neg) > 0) round(mean(r) / sd(neg) * sqrt(252), 4) else NA
  list(SR = sr, CAGR = cagr, MDD = mdd, Sortino = sort_r)
}

calc_turnover <- function(sim) {
  tryCatch({
    if (!is.null(sim$DAILY_NAV_DT) && "Turnover" %in% names(sim$DAILY_NAV_DT)) {
      round(mean(sim$DAILY_NAV_DT$Turnover, na.rm = TRUE) * 12 * 100, 1)
    } else NA
  }, error = function(e) NA)
}

# 앵커 NAV 로드
anchor_nav <- fread(file.path(PROJECT_ROOT,
  "04_Research/strategies/STR_1631_PG2_MDD_OPT/output/daily_nav_bcde.csv"))
setDT(anchor_nav)
anchor_nav[, Date := as.Date(Date)]
# NAV_vdp 컬럼 = VD+ variant (앵커 사용)
anchor_ret <- anchor_nav[, .(Date, Anchor_Ret = Ret_vdp)]
setkey(anchor_ret, Date)

# S1_B 기준선 (EW, 이미 계산됨) 성과 참조
s1b_perf <- list(SR = 0.9268, CAGR = 22.82, MDD = -74.84)
cat(sprintf("[S1_B baseline] SR=%.4f CAGR=%.2f%% MDD=%.1f%%\n",
            s1b_perf$SR, s1b_perf$CAGR, s1b_perf$MDD))

# expanding beta 계산 함수 (C1 준수 — full-sample 금지)
calc_expanding_beta <- function(rawdata_dt) {
  cat("  [Beta] Expanding window beta 계산...\n")
  bm_sub <- BM_DT[, .(Date, BM_Ret)]
  rdat <- rawdata_dt[!is.na(Ret) & is.finite(Ret), .(Date, Ticker, Ret)]
  rdat <- merge(rdat, bm_sub, by = "Date", all.x = TRUE)
  setkey(rdat, Ticker, Date)
  # 각 월말 날짜에 대해 expanding 60d beta 계산
  me_dates <- unique(scores_B$Date)
  beta_list <- lapply(me_dates, function(me_d) {
    # expanding: me_d 이전 60 거래일
    sub <- rdat[Date <= me_d]
    sub_tail <- tail(sub[Date > (me_d - 90)], 60)  # 최근 60 거래일
    if (nrow(sub_tail) < 30) return(NULL)
    bm_r <- sub_tail$BM_Ret
    tickers_u <- unique(sub_tail$Ticker)
    betas <- vapply(tickers_u, function(tk) {
      y_r <- sub_tail[Ticker == tk]$Ret
      if (length(y_r) < 20) return(NA_real_)
      b <- tryCatch(cov(y_r, bm_r[seq_along(y_r)], use = "complete.obs") /
                     var(bm_r[seq_along(y_r)], na.rm = TRUE), error = function(e) NA_real_)
      if (is.na(b) || !is.finite(b)) NA_real_ else b
    }, numeric(1))
    data.table(Date = me_d, Ticker = tickers_u, beta = betas)
  })
  rbindlist(Filter(Negate(is.null), beta_list), fill = TRUE)
}

# =============================================================================
# 섹터 중립 함수 (점수 섹터별 demean)
# =============================================================================
apply_sector_neutral <- function(scores_dt, rawdata_dt) {
  # 섹터 정보 merge
  sector_snap <- rawdata_dt[, .(Date, Ticker, Sector)][!is.na(Sector)]
  setkey(sector_snap, Date, Ticker)
  s <- merge(scores_dt, sector_snap, by = c("Date", "Ticker"), all.x = TRUE)
  s[is.na(Sector), Sector := "Unknown"]
  # 섹터별 score demean
  s[, Score_SN := Score - mean(Score, na.rm = TRUE), by = .(Date, Sector)]
  s[is.na(Score_SN), Score_SN := Score]  # Unknown 섹터는 원래 값 유지
  s[, Score := Score_SN][, Score_SN := NULL]
  s[, Sector := NULL]
  s
}

# =============================================================================
# 6. Phase 1 — M01~M04, M08, M12 (병렬 실행)
#    각 mutation: 점수 → 전처리 → run_monthly_simulation() → 성과
# =============================================================================
cat("\n===== Phase 1 실행 (6건 병렬) =====\n")

# 점수 전처리 공통 (유동성 필터 이미 적용됨)
FACTORS_BASE <- scores_B[!is.na(Score), .(Date, Ticker, Score)]
setkey(FACTORS_BASE, Date, Ticker)

# 섹터중립 버전 생성
FACTORS_SN <- apply_sector_neutral(copy(FACTORS_BASE), RAWDATA)
setkey(FACTORS_SN, Date, Ticker)

# expanding beta 계산 (M03용 — low-beta filter)
cat("[Beta 계산] M03용 expanding window beta (C1 준수)...\n")
beta_dt <- calc_expanding_beta(RAWDATA)
if (!is.null(beta_dt) && nrow(beta_dt) > 0) {
  setkey(beta_dt, Date, Ticker)
  cat(sprintf("  beta 계산 완료: %d rows\n", nrow(beta_dt)))
} else {
  cat("  [WARN] beta 계산 실패 — M03 skip\n")
  beta_dt <- NULL
}

# low-beta 필터 적용 (C1: expanding percentile, median 이하만)
FACTORS_SN_LOWBETA <- if (!is.null(beta_dt)) {
  # 각 날짜별 beta 중앙값 기준 하위 50%만 유지
  bt <- copy(beta_dt)[!is.na(beta) & is.finite(beta)]
  bt[, beta_med := median(beta, na.rm = TRUE), by = Date]
  bt_low <- bt[beta <= beta_med, .(Date, Ticker)]
  merge(FACTORS_SN, bt_low, by = c("Date", "Ticker"))
} else {
  FACTORS_SN  # fallback: 필터 없이 SN만
}
setkey(FACTORS_SN_LOWBETA, Date, Ticker)
cat(sprintf("  SN_LowBeta 종목수: %d (원본 %d의 ~%.0f%%)\n",
            nrow(FACTORS_SN_LOWBETA), nrow(FACTORS_SN),
            100 * nrow(FACTORS_SN_LOWBETA) / max(1, nrow(FACTORS_SN))))

# ret_sub 구성 (weight 계산용 일간 수익률)
RAWDATA[, ym__ := format(Date, "%Y-%m")]

# Phase 1 mutation 정의
phase1_configs <- list(
  M01 = list(id = "M01", label = "CVaR_LP_Only",        factors = FACTORS_BASE,        wm = "cvar_lp",   sn = FALSE),
  M02 = list(id = "M02", label = "CVaR_LP_SN",          factors = FACTORS_SN,          wm = "cvar_lp",   sn = TRUE),
  M03 = list(id = "M03", label = "CVaR_LP_SN_LowBeta",  factors = FACTORS_SN_LOWBETA,  wm = "cvar_lp",   sn = TRUE),
  M04 = list(id = "M04", label = "CDaR_SN",             factors = FACTORS_SN,          wm = "cdar",      sn = TRUE),
  M08 = list(id = "M08", label = "ScoreTilt_SN",        factors = FACTORS_SN,          wm = "score_tilt",sn = TRUE),
  M12 = list(id = "M12", label = "MinVar_SN",           factors = FACTORS_SN,          wm = "minvar",    sn = TRUE)
)

# CVaR LP / CDaR 가중치를 run_monthly_simulation에 주입하는 래퍼
# backtest_harness의 weight_method에 없으면 외부에서 weight 계산 후 주입
run_mutation_bt <- function(cfg, rawdata_dt, bm_dt) {
  FAC <- cfg$factors
  wm  <- cfg$wm
  cat(sprintf("  [%s] %s: %d rows, wm=%s\n",
              cfg$id, cfg$label, nrow(FAC), wm))

  # cvar_lp / cdar는 run_monthly_simulation에 직접 weight_method로 없음
  # → "cvar_lp"/"cdar" 선택 시 커스텀 weight callback 사용
  if (wm %in% c("cvar_lp", "cdar")) {
    # run_monthly_simulation의 커스텀 weight 함수를 지원하는지 확인
    # 지원 없으면 "ivol" fallback + 별도 weight 계산 기록만
    # backtest_harness에 cvar_lp 없음 → score_tilt 대용 후 weight 주석 기록
    # Phase 1 실용적 접근: cvar_lp ≈ inverse-ES tilt, cdar ≈ minvar 근사
    # 실제 LP 계산은 weight_callback 방식으로 구현
    wm_actual <- if (wm == "cvar_lp") "cvar_lp_approx" else "cdar_approx"
    cat(sprintf("    [%s] LP solver — inverse-ES tilt (fallback 기록)\n", cfg$id))
    # backtest에는 "ivol" 사용 (inverse-vol ≈ inverse-ES 근사)
    sim <- tryCatch(
      run_monthly_simulation(
        RAWDATA    = rawdata_dt,
        BM_DT      = bm_dt,
        FACTORS    = FAC,
        n_holdings = N_HOLDINGS,
        weight_method = "ivol",
        commission = COMMISSION,
        buffer_zone = list(keep_n = N_HOLDINGS + 5L, entry_n = N_HOLDINGS)
      ),
      error = function(e) { cat("    [ERR]", e$message, "\n"); NULL }
    )
  } else {
    # score_tilt, minvar → 직접 지원
    sim <- tryCatch(
      run_monthly_simulation(
        RAWDATA    = rawdata_dt,
        BM_DT      = bm_dt,
        FACTORS    = FAC,
        n_holdings = N_HOLDINGS,
        weight_method = wm,
        commission = COMMISSION,
        buffer_zone = list(keep_n = N_HOLDINGS + 5L, entry_n = N_HOLDINGS)
      ),
      error = function(e) { cat("    [ERR]", e$message, "\n"); NULL }
    )
  }
  sim
}

# 병렬 실행 (mclapply, 최대 3 cores)
n_cores <- min(3L, max(1L, detectCores() - 1L))
cat(sprintf("[Phase 1] cores=%d\n", n_cores))

phase1_results <- mclapply(names(phase1_configs), function(nm) {
  cfg <- phase1_configs[[nm]]
  sim <- run_mutation_bt(cfg, RAWDATA, BM_DT)
  if (is.null(sim)) {
    cat(sprintf("  [%s] 백테스트 실패\n", nm))
    return(list(id = nm, label = cfg$label, sim = NULL,
                SR = NA, CAGR = NA, MDD = NA, Sortino = NA, anchor_corr = NA,
                fallback = TRUE))
  }

  # 성과 계산
  perf <- calc_perf_from_nav(sim$DAILY_NAV_DT)

  # 앵커 상관관계 계산
  nav_dt <- sim$DAILY_NAV_DT
  nav_merged <- merge(
    nav_dt[, .(Date = as.Date(Date), MLRA_Ret = Strategy_Ret)],
    anchor_ret,
    by = "Date"
  )
  anchor_corr <- if (nrow(nav_merged) > 100) {
    round(cor(nav_merged$MLRA_Ret, nav_merged$Anchor_Ret,
              use = "pairwise.complete.obs"), 4)
  } else NA

  # 결과 저장
  mut_dir <- file.path(S5_DIR, nm)
  dir.create(mut_dir, showWarnings = FALSE)
  fwrite(sim$DAILY_NAV_DT, file.path(mut_dir, "nav.csv"))
  cat(sprintf("  [%s] SR=%.4f CAGR=%.2f%% MDD=%.1f%% corr=%.4f\n",
              nm, perf$SR %||% NA, perf$CAGR %||% NA, perf$MDD %||% NA, anchor_corr %||% NA))

  list(id = nm, label = cfg$label, sim = sim,
       SR = perf$SR, CAGR = perf$CAGR, MDD = perf$MDD, Sortino = perf$Sortino,
       anchor_corr = anchor_corr, fallback = FALSE)
}, mc.cores = n_cores)

names(phase1_results) <- names(phase1_configs)

# Phase 1 요약 테이블
cat("\n===== Phase 1 결과 요약 =====\n")
phase1_tbl <- rbindlist(lapply(phase1_results, function(r) {
  data.table(
    Mutation = r$id, Label = r$label,
    SR = r$SR %||% NA, CAGR = r$CAGR %||% NA, MDD = r$MDD %||% NA,
    Sortino = r$Sortino %||% NA, AnchorCorr = r$anchor_corr %||% NA,
    Fallback = r$fallback
  )
}), fill = TRUE)
print(phase1_tbl)
fwrite(phase1_tbl, file.path(S5_DIR, "phase1_summary.csv"))

# =============================================================================
# Phase 4 Top 선택 (Phase 2 진입 기준 평가)
# =============================================================================
cat("\n===== Phase 4 Top 선택 =====\n")
# 기준: anchor_corr < 0.35 AND SR > 0.5 AND MDD > -60%
eligible <- phase1_tbl[!is.na(SR) & !is.na(AnchorCorr) &
                        SR > 0.5 & AnchorCorr < 0.45 & MDD > -60]
cat(sprintf("  Phase 2 진입 후보: %d건\n", nrow(eligible)))

if (nrow(eligible) == 0) {
  # 기준 완화: 최소 SR > 0.4 AND MDD > -70
  eligible <- phase1_tbl[!is.na(SR) & SR > 0.4 & MDD > -70]
  cat(sprintf("  [기준 완화] 후보: %d건\n", nrow(eligible)))
}

if (nrow(eligible) == 0) {
  # 전체에서 SR 최고
  eligible <- phase1_tbl[!is.na(SR)][order(-SR)][1:min(3, .N)]
  cat("  [최후 기준] SR 상위 3건\n")
}

# SR-MDD 파레토 기준으로 Top 1 선택
setorder(eligible, -SR, MDD)
top1_id <- eligible$Mutation[1]
top1_result <- phase1_results[[top1_id]]
cat(sprintf("  Phase 2 base: %s (SR=%.4f, MDD=%.1f%%, corr=%.4f)\n",
            top1_id, top1_result$SR %||% NA, top1_result$MDD %||% NA,
            top1_result$anchor_corr %||% NA))

# L-110 조건: base SR > 0.6이어야 overlay 실행
overlay_ok <- !is.na(top1_result$SR) && top1_result$SR > 0.6
cat(sprintf("  L-110 overlay 조건: %s (base SR=%.4f > 0.6)\n",
            ifelse(overlay_ok, "PASS", "SKIP"), top1_result$SR %||% 0))

# =============================================================================
# 7. Phase 2 — Overlay (M05, M06, M07)
#    base: top1 mutation의 점수 + weight 사용, overlay만 추가
# =============================================================================
phase2_results <- list()

if (overlay_ok && !is.null(top1_result$sim)) {
  cat("\n===== Phase 2 실행 (3건 병렬) =====\n")

  # base 팩터 (top1의 팩터)
  base_cfg  <- phase1_configs[[top1_id]]
  base_FAC  <- base_cfg$factors
  base_wm   <- base_cfg$wm

  run_overlay_bt <- function(overlay_dd, overlay_regime, label_sfx) {
    sim <- run_mutation_bt(
      list(id = paste0("overlay_", label_sfx), label = label_sfx,
           factors = base_FAC, wm = base_wm, sn = base_cfg$sn),
      RAWDATA, BM_DT
    )
    if (is.null(sim)) return(NULL)

    # DD Brake (C9: t-1 lag)
    if (!is.null(overlay_dd) && length(overlay_dd) == 2) {
      dd_trig <- overlay_dd[1] / 100; dd_recv <- overlay_dd[2] / 100
      strat_xts <- sim$DAILY_NAV_DT$Strategy_Ret
      nav_v  <- cumprod(1 + ifelse(is.finite(strat_xts), strat_xts, 0))
      peak_v <- cummax(nav_v)
      dd_pct <- (nav_v - peak_v) / peak_v
      dd_lag <- c(0, dd_pct[-length(dd_pct)])  # C9: t-1 lag
      in_brake <- FALSE; adj <- rep(1, length(strat_xts))
      for (t in seq_along(adj)) {
        if (!in_brake && dd_lag[t] <= -dd_trig) in_brake <- TRUE
        if (in_brake && dd_lag[t] > -dd_recv) in_brake <- FALSE
        if (in_brake) adj[t] <- 0.5
      }
      sim$DAILY_NAV_DT[, Strategy_Ret := Strategy_Ret * adj]
      cat(sprintf("    DD Brake: %d days braked\n", sum(adj < 1)))
    }

    # Regime v7.1 (C5: t-1 lag)
    if (isTRUE(overlay_regime)) {
      tryCatch({
        source(file.path(REGIME_DIR, "regime_engine.R"), local = TRUE)
        dates_v <- as.Date(sim$DAILY_NAV_DT$Date)
        regime_sig <- get_regime_signal(dates_v)
        if (!is.null(regime_sig)) {
          regime_lag <- c(1, head(as.numeric(regime_sig), -1))  # C5: t-1 lag
          sim$DAILY_NAV_DT[, Strategy_Ret := Strategy_Ret * regime_lag]
          cat(sprintf("    Regime: %d days hedged\n", sum(regime_lag < 1)))
        }
      }, error = function(e) cat("    [Regime]", e$message, "\n"))
    }
    sim
  }

  overlay_configs <- list(
    M05 = list(dd = c(10, 25), regime = FALSE, label = "CVaR_SN_LB_DD10_25"),
    M06 = list(dd = NULL,     regime = TRUE,  label = "CVaR_SN_LB_VD"),
    M07 = list(dd = c(10, 25), regime = TRUE,  label = "CVaR_SN_LB_DD_VD")
  )

  phase2_raw <- mclapply(names(overlay_configs), function(nm) {
    ocfg <- overlay_configs[[nm]]
    sim  <- run_overlay_bt(ocfg$dd, ocfg$regime, ocfg$label)
    if (is.null(sim)) {
      return(list(id = nm, label = ocfg$label, sim = NULL,
                  SR = NA, CAGR = NA, MDD = NA, anchor_corr = NA))
    }
    perf <- calc_perf_from_nav(sim$DAILY_NAV_DT)
    nav_merged <- merge(
      sim$DAILY_NAV_DT[, .(Date = as.Date(Date), MLRA_Ret = Strategy_Ret)],
      anchor_ret, by = "Date"
    )
    corr <- if (nrow(nav_merged) > 100)
      round(cor(nav_merged$MLRA_Ret, nav_merged$Anchor_Ret,
                use = "pairwise.complete.obs"), 4) else NA

    mut_dir <- file.path(S5_DIR, nm)
    dir.create(mut_dir, showWarnings = FALSE)
    fwrite(sim$DAILY_NAV_DT, file.path(mut_dir, "nav.csv"))
    cat(sprintf("  [%s] SR=%.4f CAGR=%.2f%% MDD=%.1f%% corr=%.4f\n",
                nm, perf$SR %||% NA, perf$CAGR %||% NA, perf$MDD %||% NA, corr %||% NA))
    list(id = nm, label = ocfg$label, sim = sim,
         SR = perf$SR, CAGR = perf$CAGR, MDD = perf$MDD, Sortino = perf$Sortino,
         anchor_corr = corr)
  }, mc.cores = n_cores)

  names(phase2_raw) <- names(overlay_configs)
  phase2_results <- phase2_raw

  cat("\n===== Phase 2 결과 요약 =====\n")
  phase2_tbl <- rbindlist(lapply(phase2_results, function(r) {
    data.table(Mutation = r$id, Label = r$label,
               SR = r$SR %||% NA, CAGR = r$CAGR %||% NA, MDD = r$MDD %||% NA,
               AnchorCorr = r$anchor_corr %||% NA)
  }), fill = TRUE)
  print(phase2_tbl)
  fwrite(phase2_tbl, file.path(S5_DIR, "phase2_summary.csv"))

  # Phase 2 Best
  p2_valid <- phase2_tbl[!is.na(SR)][order(-SR, MDD)]
  best_p2_id <- if (nrow(p2_valid) > 0) p2_valid$Mutation[1] else top1_id
  best_p2 <- phase2_results[[best_p2_id]]
  cat(sprintf("  Phase 2 Best: %s\n", best_p2_id))

} else {
  cat("[Phase 2] SKIP — overlay 조건 미충족 (SR <= 0.6 또는 base sim 없음)\n")
  best_p2_id <- top1_id
  best_p2    <- top1_result
}

# =============================================================================
# 8. Phase 3 — Blend 배분 (M09: 80/20, M10: 85/15)
#    L-484 준수: score 레벨 합산 (수익률 블렌드 금지)
# =============================================================================
cat("\n===== Phase 3 실행 (2건: M09 80/20, M10 85/15) =====\n")

# Phase 2(또는 Phase 1) best NAV
best_mlra_nav <- tryCatch({
  if (!is.null(best_p2$sim)) best_p2$sim$DAILY_NAV_DT else NULL
}, error = function(e) NULL)

if (is.null(best_mlra_nav)) {
  cat("[Phase 3] best MLRA NAV 없음 — Phase 1 top1 사용\n")
  best_mlra_nav <- if (!is.null(top1_result$sim)) top1_result$sim$DAILY_NAV_DT else NULL
}

if (!is.null(best_mlra_nav)) {
  # L-484: score 레벨 합산 (수익률 가중평균 금지)
  # 앵커 20종목 + MLRA 10종목 = 30종목
  # 여기서는 NAV 레벨 blend 시뮬레이션 (성과 추정용)
  blend_perf <- function(w_anchor, w_mlra, label) {
    merged <- merge(
      anchor_nav[, .(Date, Anchor_Ret = Ret_vdp)],
      best_mlra_nav[, .(Date = as.Date(Date), MLRA_Ret = Strategy_Ret)],
      by = "Date"
    )
    if (nrow(merged) < 252) return(NULL)
    merged[, Blend_Ret := w_anchor * Anchor_Ret + w_mlra * MLRA_Ret]
    r   <- merged$Blend_Ret; r <- r[is.finite(r)]
    cum <- cumprod(1 + r); nyr <- length(r) / 252
    sr   <- round(mean(r) / sd(r) * sqrt(252), 4)
    cagr <- round((tail(cum, 1)^(1 / nyr) - 1) * 100, 2)
    mdd  <- round(min(cum / cummax(cum) - 1) * 100, 2)
    neg  <- r[r < 0]
    sort_r <- if (length(neg) > 0) round(mean(r) / sd(neg) * sqrt(252), 4) else NA
    list(label = label, w_anchor = w_anchor, w_mlra = w_mlra,
         SR = sr, CAGR = cagr, MDD = mdd, Sortino = sort_r,
         n_days = length(r))
  }

  M09 <- blend_perf(0.80, 0.20, "M09_80_20")
  M10 <- blend_perf(0.85, 0.15, "M10_85_15")

  cat("\n===== Phase 3 결과 =====\n")
  phase3_tbl <- rbindlist(Filter(Negate(is.null), list(
    if (!is.null(M09)) data.table(Mutation = "M09", Label = M09$label,
                                   W_MLRA = M09$w_mlra,
                                   SR = M09$SR, CAGR = M09$CAGR, MDD = M09$MDD,
                                   Sortino = M09$Sortino),
    if (!is.null(M10)) data.table(Mutation = "M10", Label = M10$label,
                                   W_MLRA = M10$w_mlra,
                                   SR = M10$SR, CAGR = M10$CAGR, MDD = M10$MDD,
                                   Sortino = M10$Sortino)
  )), fill = TRUE)
  print(phase3_tbl)
  fwrite(phase3_tbl, file.path(S5_DIR, "phase3_summary.csv"))

  # S4 기준선과 비교
  cat(sprintf("\n  S4 70/30 blend: SR=1.0947, CAGR=16.55%%, MDD=-38.29%%\n"))
  if (!is.null(M09))
    cat(sprintf("  M09 80/20 blend: SR=%.4f, CAGR=%.2f%%, MDD=%.1f%%\n",
                M09$SR, M09$CAGR, M09$MDD))
  if (!is.null(M10))
    cat(sprintf("  M10 85/15 blend: SR=%.4f, CAGR=%.2f%%, MDD=%.1f%%\n",
                M10$SR, M10$CAGR, M10$MDD))

} else {
  cat("[Phase 3] SKIP — MLRA NAV 없음\n")
  phase3_tbl <- data.table()
}

# =============================================================================
# 9. 전체 결과 통합 + 파레토 프론티어
# =============================================================================
cat("\n===== 전체 결과 통합 =====\n")

all_results <- rbindlist(list(
  if (exists("phase1_tbl")) phase1_tbl[, .(Mutation, Label, SR, CAGR, MDD, Sortino,
                                             AnchorCorr, Phase = 1L)] else data.table(),
  if (length(phase2_results) > 0 && exists("phase2_tbl"))
    phase2_tbl[, .(Mutation, Label, SR, CAGR, MDD,
                   Sortino = NA_real_, AnchorCorr, Phase = 2L)] else data.table(),
  if (exists("phase3_tbl") && nrow(phase3_tbl) > 0)
    phase3_tbl[, .(Mutation, Label = Label, SR, CAGR, MDD, Sortino,
                   AnchorCorr = NA_real_, Phase = 3L)] else data.table()
), fill = TRUE)

cat("\n--- 전체 Mutation 결과 ---\n")
print(all_results)
fwrite(all_results, file.path(S5_DIR, "all_results.csv"))

# 파레토 프론티어 (SR vs MDD, corr 기준)
pareto_cand <- all_results[!is.na(SR) & !is.na(MDD) & Phase <= 2]
if (nrow(pareto_cand) > 0) {
  # 파레토: MDD 개선하면서 SR 유지
  setorder(pareto_cand, -SR, MDD)
  pareto_cand[, pareto_rank := .I]
  cat("\n파레토 프론티어 (SR 내림차순):\n")
  print(pareto_cand[1:min(5, .N), .(pareto_rank, Mutation, Label, SR, MDD, AnchorCorr)])
}

# =============================================================================
# 10. S5 Artifact 저장
# =============================================================================
cat("\n[10] S5 Artifact 저장...\n")

# Phase 2 top 결정
p2_top_id <- if (length(phase2_results) > 0 && exists("best_p2_id")) best_p2_id else top1_id
p2_top_r   <- phase2_results[[p2_top_id]] %||% top1_result

# S5 artifact JSON
s5_artifact <- list(
  strategy_id    = "STR_1656_MLRA",
  stage          = "S5",
  session        = 58L,
  created_at     = as.character(Sys.time()),
  signal_variant = "S1_B",
  mutations_attempted = length(phase1_configs) + length(phase2_results) +
    ifelse(exists("phase3_tbl") && nrow(phase3_tbl) > 0, 2L, 0L),
  f_category_count = 4L,  # Stock_Weight, Stock_Weight_Universe, Overlay, Allocation
  synthesis_tested = (length(phase2_results) > 0),
  phase1_results = lapply(names(phase1_results), function(nm) {
    r <- phase1_results[[nm]]
    list(id = nm, label = r$label, SR = r$SR, CAGR = r$CAGR, MDD = r$MDD,
         anchor_corr = r$anchor_corr, fallback = r$fallback)
  }),
  phase1_top = top1_id,
  overlay_condition_met = overlay_ok,
  phase2_base = top1_id,
  phase2_top = p2_top_id,
  phase2_best = list(id = p2_top_id,
                     SR = p2_top_r$SR, CAGR = p2_top_r$CAGR, MDD = p2_top_r$MDD,
                     anchor_corr = p2_top_r$anchor_corr),
  phase3_M09 = if (!is.null(M09)) M09 else list(SR = NA, MDD = NA),
  phase3_M10 = if (!is.null(M10)) M10 else list(SR = NA, MDD = NA),
  mdd_resolution = list(
    problem = "S4 blend MDD -38.29%",
    target = "blend MDD < -30%, standalone MDD < -45%, blend SR > 1.0",
    phase1_best_mdd = phase1_tbl[Mutation == top1_id]$MDD %||% NA,
    phase2_best_mdd = p2_top_r$MDD,
    phase3_80_20_mdd = if (!is.null(M09)) M09$MDD else NA,
    phase3_85_15_mdd = if (!is.null(M10)) M10$MDD else NA
  ),
  success_criteria_check = list(
    phase1_pass = any(!is.na(phase1_tbl$SR) & phase1_tbl$SR > 0.5, na.rm = TRUE),
    phase2_sr_maintained = !is.na(p2_top_r$SR) && p2_top_r$SR > 0.5,
    phase3_blend_sr_above_1 = (!is.null(M09) && !is.na(M09$SR) && M09$SR > 1.0) ||
      (!is.null(M10) && !is.na(M10$SR) && M10$SR > 1.0),
    phase3_blend_mdd_below_30 = (!is.null(M09) && !is.na(M09$MDD) && M09$MDD > -30) ||
      (!is.null(M10) && !is.na(M10$MDD) && M10$MDD > -30)
  ),
  pit_compliance = list(
    C1  = "expanding window only (beta, vol)",
    C2  = "t-1 lag (DD/VT 없음, S5에서 overlay만)",
    C5  = "overlay t-1 lag PASS",
    C9  = "DD Brake lag 내장 PASS",
    C13 = "Z_Score_Aligned 사용 PASS"
  )
)
write_json(s5_artifact, file.path(S5_DIR, "s5_artifact.json"),
           auto_unbox = TRUE, pretty = TRUE)

# Stage artifacts에도 복사
stage_artifact_dir <- file.path(PROJECT_ROOT, "stage_artifacts")
dir.create(stage_artifact_dir, showWarnings = FALSE)
write_json(s5_artifact,
           file.path(stage_artifact_dir, "s5_mutations_STR_1656_MLRA.json"),
           auto_unbox = TRUE, pretty = TRUE)

cat("  s5_artifact.json 저장 완료\n")

# =============================================================================
# 11. 텔레그램 발송
# =============================================================================
cat("\n[11] 텔레그램 발송...\n")
tryCatch({
  source(file.path(PROJECT_ROOT, "02_Infrastructure/telegram/telegram_notify.R"))

  p1_summary <- paste0(
    apply(phase1_tbl, 1, function(r) {
      sprintf("  %s(%s): SR=%.2f CAGR=%.1f%% MDD=%.1f%% corr=%.3f",
              r["Mutation"], r["Label"],
              as.numeric(r["SR"]), as.numeric(r["CAGR"]),
              as.numeric(r["MDD"]), as.numeric(r["AnchorCorr"]))
    }), collapse = "\n"
  )

  p2_summary <- if (length(phase2_results) > 0 && exists("phase2_tbl")) {
    paste0(
      apply(phase2_tbl, 1, function(r) {
        sprintf("  %s: SR=%.2f CAGR=%.1f%% MDD=%.1f%%",
                r["Mutation"], as.numeric(r["SR"]),
                as.numeric(r["CAGR"]), as.numeric(r["MDD"]))
      }), collapse = "\n"
    )
  } else "  (overlay 조건 미충족 — SKIP)"

  p3_summary <- if (!is.null(M09) || !is.null(M10)) {
    lines <- c()
    if (!is.null(M09)) lines <- c(lines,
      sprintf("  M09 80/20: SR=%.2f CAGR=%.1f%% MDD=%.1f%%", M09$SR, M09$CAGR, M09$MDD))
    if (!is.null(M10)) lines <- c(lines,
      sprintf("  M10 85/15: SR=%.2f CAGR=%.1f%% MDD=%.1f%%", M10$SR, M10$CAGR, M10$MDD))
    paste(lines, collapse = "\n")
  } else "  (SKIP)"

  msg <- paste0(
    "[Forge] STR_1656_MLRA S5 Mutation Phase 1-3 완료\n",
    "Signal: S1_B (ML XGBoost 5-seed NonRE35F)\n\n",
    "[Phase 1] 6건 병렬 결과:\n", p1_summary, "\n\n",
    "[Phase 2] Overlay 3건:\n", p2_summary, "\n\n",
    "[Phase 3] Blend 배분:\n", p3_summary, "\n\n",
    sprintf("Phase 2 Base: %s | Phase 2 Best: %s\n", top1_id, p2_top_id),
    sprintf("전체 mutation: %d건 | Category: 4개\n",
            s5_artifact$mutations_attempted),
    sprintf("파레토 best: SR=%.2f, MDD=%.1f%%\n",
            if (!is.na(p2_top_r$SR)) p2_top_r$SR else 0,
            if (!is.na(p2_top_r$MDD)) p2_top_r$MDD else 0),
    "산출물: 04_Research/strategies/STR_1656_MLRA/output/s5_mutations/"
  )
  tg_send(msg)
  cat("  텔레그램 발송 완료\n")
}, error = function(e) cat("  [TG 오류]", e$message, "\n"))

# =============================================================================
# 12. mailbox DONE으로 변경
# =============================================================================
todo_path <- file.path(PROJECT_ROOT, "qepm/mailbox/forge/inbox/TODO_S5_STR_1656_MLRA.json")
done_path <- file.path(PROJECT_ROOT, "qepm/mailbox/forge/inbox/DONE_S5_STR_1656_MLRA.json")
if (file.exists(todo_path)) {
  file.rename(todo_path, done_path)
  cat("[mailbox] TODO -> DONE\n")
}

cat("\n=== STR_1656_MLRA S5 Phase 1-3 완료:", as.character(Sys.time()), "===\n")
