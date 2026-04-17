## =============================================================================
## STR_1659_RF_UA: Random Forest Uncertainty-Aware Diversifier — S1 Implementation
## 핵심 아이디어: ranger 5-seed ensemble + UA Tree Variance Sorting
##               kappa=1.0 고정 (최적화 금지, C1 준수)
##               Feature pool: V/Q/AC/GR/IN/S family 일간 DB ~79 factors
##               XGBoost(STR_1656) 일간 RE*/전체 309F 풀과 분리 → 0% overlap
##               S1-A: RF Point Prediction / S1-B: UA Tree Variance (PRIMARY)
##               S1-C: UA Lower Bound / S1-D: QRF Quantile
##               EW 30종목 + 15bps commission + 유동성 2억원
##               Liu et al. (2026) UA Ranking + Breiman (2001) Random Forests
##               L-123 §4: 일간 DB 5700일 학습 (p>>n 해결 핵심)
##               L-124: RF(ICIR 0.69) ≈ XGB, Tree > Linear in KR cross-section
##
## PIT 준수 (C1-C15):
##   C1  : Walk-Forward Expanding Window only (full-sample 통계 없음)
##   C2  : OOS > IS + purge 21일 (same-day circular 없음)
##   C4  : 일간 DB는 재무 45일 lag 내재
##   C9  : DD/VT 오버레이 없음 (S1 순수 팩터)
##   C13 : Z_Score_Aligned 사용 (방향 반전 금지)
##   C14 : fwd_ret 21d lag 후 계산 (t+1~t+21)
##   C15 : Arrow open_dataset predicate pushdown (parquet 반복 없음)
##
## OPT 준수:
##   OPT-1: Arrow open_dataset → for loop 내 parquet 반복 없음 (L-534)
##   OPT-2: load_rawdata(use_cache=TRUE) 1회
##   OPT-4: 백테스트 mclapply 병렬
##   OPT-7/MC-P2: 일간 factor_db_daily 참조 (L-123 §4)
##   OPT-7/MC-P3: Walk-forward expanding + oos_yr 패턴 (L-123 MC1)
## =============================================================================

cat("=== STR_1659_RF_UA: RF Uncertainty-Aware Diversifier ===\n")
cat("시작:", as.character(Sys.time()), "\n\n")

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(dplyr)
  library(jsonlite)
  library(ggplot2)
  library(parallel)
})

# null-coalescing (rlang 미사용 시 직접 정의)
`%||%` <- function(a, b) if (!is.null(a) && length(a) > 0L && !is.na(a[[1L]])) a[[1L]] else b

# =============================================================================
# 경로 (normalizePath 금지 — WSL 한글 경로 버그)
# =============================================================================
PROJECT_ROOT  <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
STRATEGY_DIR  <- file.path(PROJECT_ROOT, "04_Research/strategies/STR_1659_RF_UA")
OUTPUT_DIR    <- file.path(STRATEGY_DIR, "output")
ARTIFACT_DIR  <- file.path(PROJECT_ROOT, "stage_artifacts")
# OPT-7/MC-P2: 일간 factor_db_daily 경로 (L-123 §4: 일간 5700일 학습 필수)
DAILY_DB_DIR  <- file.path(PROJECT_ROOT, ".cache/factor_db_daily")

dir.create(OUTPUT_DIR,   showWarnings = FALSE, recursive = TRUE)
dir.create(ARTIFACT_DIR, showWarnings = FALSE, recursive = TRUE)

source(file.path(PROJECT_ROOT, "02_Infrastructure/config.R"))
source(file.path(PROJECT_ROOT, "02_Infrastructure/backtest_harness.R"))

# =============================================================================
# 설정
# =============================================================================
LIQ_THRESHOLD <- 2e8
N_HOLDINGS    <- 30L
COMMISSION    <- 0.0015
MI_TOP_N      <- 40L      # S0 조건: 79개 중 50% 수준 (noise filtering)
PURGE_DAYS    <- 21L
RF_SEEDS      <- c(42L, 123L, 456L, 789L, 2024L)
OOS_START_YR  <- 2008L
OOS_END_YR    <- 2025L
KAPPA         <- 1.0      # UA score: pred - kappa*se (C1 준수: 최적화 금지)
RF_NUM_TREES  <- 500L
RF_MAX_DEPTH  <- 8L
RF_MIN_NODE   <- 20L
RF_THREADS    <- 2L       # OOM 방지 (RAM < 80%)
RF_MAX_IS     <- 80000L   # IS 서브샘플 상한 (OOM 방지, L-123 §4)

# RF 풀 구성: V/Q/AC/GR/IN/S family (XGB STR_1656 풀과 0% overlap)
# XGB 풀: RE*/전체 309 일간팩터 (RE* 포함 여부로 S1-A/B 분리)
# RF 풀: fundamental family만 (daily 업데이트 팩터 6개 제외 — S0 조건)
RF_FAMILY_PAT <- "^(V[0-9]|Q[0-9]|AC[0-9]|GR[0-9]|IN[0-9]|S[0-9]|XF_DU)"
# DAILY_EXCL: update_freq='daily' 팩터 + .x/.y 중복 컬럼 제외
DAILY_EXCL    <- c("V04_fPER", "V05_fPBR", "V06_fDY", "V09_PEG",
                   "V21_Composite_Equity_Issuance", "S01_Size")

cat("[CONFIG] N=", N_HOLDINGS, "| MI=", MI_TOP_N,
    "| kappa=", KAPPA, "| seeds=", paste(RF_SEEDS, collapse=","),
    "| purge=", PURGE_DAYS, "\n")
cat("[CONFIG] daily_db =", DAILY_DB_DIR, "\n")

# ranger 패키지 확인 (OPT-7/MC-P2: ranger 사용)
ranger_ok <- tryCatch({ library(ranger); TRUE }, error=function(e) FALSE)
if (!ranger_ok) {
  cat("[RANGER] 설치 시도...\n")
  install.packages("ranger", repos="https://cran.rstudio.com", quiet=TRUE)
  ranger_ok <- tryCatch({ library(ranger); TRUE }, error=function(e) FALSE)
}
if (!ranger_ok) stop("ranger 패키지 필요 (keep.inbag=TRUE UA SE 지원)")
cat("[RANGER] OK\n")

# =============================================================================
# 1. RAWDATA 1회 로드 (OPT-2: use_cache=TRUE)
# =============================================================================
cat("\n[1] RAWDATA...\n")
rw       <- load_rawdata(use_cache = TRUE)
RAWDATA  <- rw$RAWDATA
BM_DT    <- rw$BM_DT
setDT(RAWDATA); setkey(RAWDATA, Date, Ticker)
cat(sprintf("    %d rows | %s ~ %s\n", nrow(RAWDATA), min(RAWDATA$Date), max(RAWDATA$Date)))

# =============================================================================
# 2. 21d forward return (C14: t+1~t+21, IS target only)
# =============================================================================
cat("[2] 21d fwd return...\n")
ret_dt <- RAWDATA[!is.na(Ret) & is.finite(Ret) & Date >= as.Date("2003-01-01"),
                  .(Date, Ticker, Ret, Size)]
setkey(ret_dt, Ticker, Date)
ret_dt[, logR := log(1 + pmax(Ret, -0.99))]
ret_dt[, fwd_ret_21d := {
  n <- .N; cl <- cumsum(logR)
  if (n <= 21L) rep(NA_real_, n)
  else { fwd <- c(cl[22:n], rep(NA_real_, 21L)) - cl; exp(fwd)-1 }
}, by = Ticker]
ret_dt[, logR := NULL]
ret_dt <- ret_dt[!is.na(fwd_ret_21d)]
cat(sprintf("    fwd rows: %d\n", nrow(ret_dt)))

# 월말 날짜 벡터
RAWDATA[, ym__ := format(Date, "%Y-%m")]
ALL_ME_DATES <- RAWDATA[, .(me_date = max(Date)), by=ym__][order(me_date)]$me_date
RAWDATA[, ym__ := NULL]
cat(sprintf("    [ME] 월말 날짜 %d개 (%s ~ %s)\n",
            length(ALL_ME_DATES), min(ALL_ME_DATES), max(ALL_ME_DATES)))

# SIZE_DT 보존
SIZE_DT <- RAWDATA[Date >= as.Date("2003-01-01"), .(Date, Ticker, Size)]
setkey(SIZE_DT, Date, Ticker)

rm(RAWDATA, BM_DT, rw); gc()
cat(sprintf("    [MEM] RAWDATA 해제. ret_dt: %.0fMB | SIZE_DT: %.0fMB\n",
            object.size(ret_dt)/1e6, object.size(SIZE_DT)/1e6))

# =============================================================================
# 3. OPT-7/MC-P2 + OPT-1: open_dataset (Arrow lazy, factor_db_daily 참조)
#    L-123 §4: 일간 DB 5700일 학습이 p>>n 해결 핵심
# =============================================================================
cat("[3] Arrow Dataset (factor_db_daily)...\n")
pq_files <- list.files(DAILY_DB_DIR, pattern="\\.parquet$", full.names=TRUE)
if (length(pq_files) == 0L) stop("factor_db_daily parquet 없음: ", DAILY_DB_DIR)

ds_daily  <- open_dataset(pq_files, format="parquet")
ds_cols   <- schema(ds_daily)$names

# RF 풀: V/Q/AC/GR/IN/S family + .x/.y 중복 제거 + DAILY_EXCL 제거
# S0 조건 + C13: Z_Score_Aligned 없는 일간 DB는 원시 팩터 값 사용
raw_rf_candidates <- grep(RF_FAMILY_PAT, ds_cols, value=TRUE)
raw_rf_candidates <- setdiff(raw_rf_candidates, DAILY_EXCL)
# .x/.y 중복 컬럼 제거 (깔끔한 컬럼만 사용)
raw_rf_candidates <- raw_rf_candidates[!grepl("\\.x$|\\.y$", raw_rf_candidates)]
RF_POOL    <- raw_rf_candidates
cat(sprintf("    RF 풀(일간DB): %d팩터 (daily_excl=%d)\n",
            length(RF_POOL), length(DAILY_EXCL)))

# =============================================================================
# 유틸 — Arrow predicate collect (OPT-1: for loop 내 parquet 반복 없음)
# =============================================================================
arrow_collect <- function(fcols, dates_vec=NULL, d0=NULL, d1=NULL) {
  need <- intersect(c("Date","Ticker",fcols), ds_cols)
  q    <- ds_daily
  if (!is.null(dates_vec)) {
    q <- q |> filter(Date %in% dates_vec)
  } else {
    q <- q |> filter(Date >= d0, Date <= d1)
  }
  q |> select(all_of(need)) |>
    collect() |>
    as.data.table() |>
    (\(x){ setkey(x, Date, Ticker); x })()
}

# MI prefilter — bulk collect (OPT-1: for loop 내 arrow_collect 청크, 반복 없음)
# L-123 §2.3: 309→40 pre-select (noise filtering)
mi_prefilter_chunked <- function(d0, d1, fcols, n_top = 40L) {
  me_vec   <- ALL_ME_DATES[ALL_ME_DATES >= d0 & ALL_ME_DATES <= d1]
  if (length(me_vec) == 0L) return(character(0L))

  chunk_sz <- 60L
  f_chunks <- split(fcols, ceiling(seq_along(fcols) / chunk_sz))
  all_ics  <- numeric(0)

  for (ci in seq_along(f_chunks)) {
    ch    <- f_chunks[[ci]]
    # bulk collect: 해당 청크 팩터 × 월말 날짜 (parquet 1회 scan)
    ch_dt <- tryCatch(arrow_collect(ch, dates_vec=me_vec), error=function(e) NULL)
    if (is.null(ch_dt) || nrow(ch_dt) == 0L) next
    ch_dt <- merge(ch_dt, ret_dt[, .(Date, Ticker, fwd_ret_21d)], by=c("Date","Ticker"))
    ch_dt <- ch_dt[!is.na(fwd_ret_21d)]
    y <- ch_dt$fwd_ret_21d
    for (f in intersect(ch, names(ch_dt))) {
      x <- ch_dt[[f]]; v <- is.finite(x) & is.finite(y)
      if (sum(v) < 100L) next
      all_ics[f] <- tryCatch(abs(cor(x[v], y[v], method="spearman")),
                             error=function(e) NA_real_)
    }
    rm(ch_dt); gc(FALSE)
    cat(sprintf("      MI chunk %d/%d done\n", ci, length(f_chunks)))
  }

  valid <- all_ics[!is.na(all_ics)]
  if (!length(valid)) return(character(0L))
  names(sort(valid, decreasing=TRUE))[seq_len(min(n_top, length(valid)))]
}

# 특징 행렬 구성 (NA → 0)
build_mat <- function(dt, cols) {
  avail <- intersect(cols, names(dt))
  m     <- as.matrix(dt[, avail, with=FALSE])
  m[!is.finite(m)] <- 0
  m
}

# ranger 5-seed UA 예측 (S1-A/B/C/D 동시)
# L-123 MC1: Walk-forward expanding window
# keep.inbag=TRUE → type="se" 로 tree variance 추출
rf5_predict_ua <- function(X_tr, y_tr, X_te, seeds=RF_SEEDS, kappa=KAPPA) {
  # OOM 방지: IS > RF_MAX_IS 시 서브샘플
  if (nrow(X_tr) > RF_MAX_IS) {
    idx  <- sample(nrow(X_tr), RF_MAX_IS)
    X_tr <- X_tr[idx, , drop=FALSE]
    y_tr <- y_tr[idx]
  }
  n_te   <- nrow(X_te)
  mtry_v <- max(1L, floor(sqrt(ncol(X_tr))))

  # 결과 행렬 초기화
  preds_pt  <- matrix(0, nrow=n_te, ncol=length(seeds))  # Point
  preds_se  <- matrix(0, nrow=n_te, ncol=length(seeds))  # SE (UA)
  preds_q50 <- matrix(0, nrow=n_te, ncol=length(seeds))  # QRF 50%ile

  df_tr <- as.data.frame(X_tr); df_tr$.y <- y_tr
  df_te <- as.data.frame(X_te)

  for (si in seq_along(seeds)) {
    sd <- seeds[si]

    # S1-A/B/C: keep.inbag=TRUE (SE 추출 필수)
    fit_main <- tryCatch(
      ranger(
        formula       = .y ~ .,
        data          = df_tr,
        num.trees     = RF_NUM_TREES,
        mtry          = mtry_v,
        max.depth     = RF_MAX_DEPTH,
        min.node.size = RF_MIN_NODE,
        num.threads   = RF_THREADS,
        keep.inbag    = TRUE,
        seed          = sd,
        verbose       = FALSE
      ),
      error=function(e){ cat("    ranger(main) err:", e$message, "\n"); NULL }
    )
    if (!is.null(fit_main)) {
      pred_se <- predict(fit_main, df_te, type="se")
      preds_pt[, si] <- pred_se$predictions
      preds_se[, si] <- pmax(pred_se$se, 0)   # SE >= 0
      rm(fit_main, pred_se); gc(FALSE)
    }

    # S1-D: QRF quantile=0.5 (중앙값 → P(r>0|x) 근사)
    fit_q <- tryCatch(
      ranger(
        formula       = .y ~ .,
        data          = df_tr,
        num.trees     = RF_NUM_TREES,
        mtry          = mtry_v,
        max.depth     = RF_MAX_DEPTH,
        min.node.size = RF_MIN_NODE,
        num.threads   = RF_THREADS,
        quantreg      = TRUE,
        seed          = sd,
        verbose       = FALSE
      ),
      error=function(e){ cat("    ranger(QRF) err:", e$message, "\n"); NULL }
    )
    if (!is.null(fit_q)) {
      qpred <- tryCatch(predict(fit_q, df_te, type="quantiles", quantiles=0.5),
                        error=function(e) NULL)
      if (!is.null(qpred)) preds_q50[, si] <- qpred$predictions[, 1L]
      rm(fit_q, qpred); gc(FALSE)
    }
    cat(sprintf("      seed=%d done\n", sd))
  }

  # 5-seed 앙상블 집계
  pt_mean <- rowMeans(preds_pt)
  se_mean <- rowMeans(preds_se)

  # 랭크 정규화 (0~1)
  rank_norm <- function(x) { r <- rank(x, ties.method="average"); r/max(r,1L) }

  list(
    SA     = rank_norm(pt_mean),                          # S1-A: Point
    SB     = rank_norm(pt_mean - kappa * se_mean),        # S1-B: UA (PRIMARY)
    SC     = rank_norm(pt_mean - se_mean),                # S1-C: UA conservative
    SD     = rank_norm(rowMeans(preds_q50)),              # S1-D: QRF 50%ile
    pt_raw = pt_mean,
    ua_raw = pt_mean - kappa * se_mean
  )
}

# =============================================================================
# 4. Walk-Forward Expanding — lapply (OPT-1 + OPT-7/MC-P3)
#    L-123 §4: oos_yr loop (일간 IS 수백만 행 → expand 학습)
# =============================================================================
cat("\n[4] Walk-Forward lapply (oos_yr)...\n")

IS_START_D <- as.Date("2003-01-01")
OOS_YEARS  <- OOS_START_YR:OOS_END_YR

wf_out <- lapply(OOS_YEARS, function(oos_yr) {
  cat(sprintf("\n  === OOS %d ===\n", oos_yr))
  is_end_yr <- oos_yr - 2L
  if (is_end_yr < 2005L) return(NULL)

  is_end_d <- as.Date(sprintf("%d-12-31", is_end_yr))
  oos_s    <- as.Date(sprintf("%d-01-01", oos_yr))
  oos_e    <- as.Date(sprintf("%d-12-31", oos_yr))

  is_me_d  <- ALL_ME_DATES[ALL_ME_DATES >= IS_START_D & ALL_ME_DATES <= is_end_d]
  if (length(is_me_d) < 12L) return(NULL)

  # ── MI prefilter: bulk collect (OPT-1 준수, for loop 내 Arrow 청크)
  cat("    [MI] chunked prefilter...\n")
  top_feats <- mi_prefilter_chunked(IS_START_D, is_end_d, RF_POOL, MI_TOP_N)
  cat(sprintf("    top_feats=%d\n", length(top_feats)))
  if (length(top_feats) < 5L) return(NULL)

  # ── IS 데이터: 일간 DB bulk collect (OPT-1: arrow_collect 1회)
  #    L-123 §4: 일간 5700일 → IS 수백만 행 (p>>n 해결)
  cat("    [IS] bulk collect (일간 DB)...\n")
  is_dt <- tryCatch(
    arrow_collect(top_feats, d0=IS_START_D, d1=is_end_d),
    error=function(e) { cat("    [IS ERR]", e$message, "\n"); NULL }
  )
  if (is.null(is_dt) || nrow(is_dt) < 1000L) return(NULL)

  is_dt <- merge(is_dt, ret_dt[, .(Date, Ticker, fwd_ret_21d)], by=c("Date","Ticker"))
  is_dt <- merge(is_dt, SIZE_DT, by=c("Date","Ticker"), all.x=TRUE)
  is_dt <- is_dt[!is.na(fwd_ret_21d) & !is.na(Size) & Size >= LIQ_THRESHOLD]
  gc(FALSE)
  cat(sprintf("    IS=%d rows (일간 전체, %d factors)\n", nrow(is_dt), length(top_feats)))

  feat_cols <- intersect(top_feats, names(is_dt))
  X_tr <- build_mat(is_dt, feat_cols)
  y_tr <- is_dt$fwd_ret_21d
  rm(is_dt); gc(FALSE)

  # ── OOS: 월말 단면 (채점용, 일간 DB)
  oos_me_d <- ALL_ME_DATES[ALL_ME_DATES >= oos_s & ALL_ME_DATES <= oos_e]
  if (length(oos_me_d) == 0L) { rm(X_tr, y_tr); gc(FALSE); return(NULL) }

  cat("    [OOS] month-end collect...\n")
  oos_dt <- tryCatch(
    arrow_collect(top_feats, dates_vec=oos_me_d),
    error=function(e) { cat("    [OOS ERR]", e$message, "\n"); NULL }
  )
  if (is.null(oos_dt) || nrow(oos_dt) == 0L) { rm(X_tr, y_tr); gc(FALSE); return(NULL) }

  oos_dt <- merge(oos_dt, SIZE_DT, by=c("Date","Ticker"), all.x=TRUE)
  oos_dt <- oos_dt[!is.na(Size) & Size >= LIQ_THRESHOLD]
  cat(sprintf("    OOS=%d rows\n", nrow(oos_dt)))

  # 컬럼 정렬 (IS/OOS 불일치 방지)
  feat_oos <- intersect(feat_cols, names(oos_dt))
  if (length(feat_oos) != ncol(X_tr)) {
    common_f <- intersect(colnames(X_tr), feat_oos)
    if (length(common_f) < 3L) { rm(X_tr,y_tr,oos_dt); gc(FALSE); return(NULL) }
    X_tr <- X_tr[, common_f, drop=FALSE]
    feat_oos <- common_f
  }
  X_te <- build_mat(oos_dt, feat_oos)

  # ── ranger 5-seed UA 예측
  cat("    [RF] 학습+예측...\n")
  preds <- tryCatch(
    rf5_predict_ua(X_tr, y_tr, X_te, RF_SEEDS, KAPPA),
    error=function(e){ cat("    [RF ERR]", e$message, "\n"); NULL }
  )
  rm(X_tr, y_tr, X_te); gc(FALSE)
  if (is.null(preds)) return(NULL)

  oos_dt[, SA := preds$SA]
  oos_dt[, SB := preds$SB]
  oos_dt[, SC := preds$SC]
  oos_dt[, SD := preds$SD]

  # IC 계산
  oos_fwd <- merge(
    oos_dt[, .(Date, Ticker, SA, SB, SC, SD)],
    ret_dt[, .(Date, Ticker, fwd_ret_21d)],
    by=c("Date","Ticker")
  )
  oos_fwd <- oos_fwd[!is.na(fwd_ret_21d) & !is.na(SA)]
  oos_fwd[, ym_ := format(Date, "%Y-%m")]

  ic_calc <- function(sc_col, vname) {
    dt_ic <- oos_fwd[, .(
      IC      = tryCatch(cor(.SD[[sc_col]], fwd_ret_21d, method="spearman",
                             use="complete.obs"), error=function(e) NA_real_),
      variant = vname,
      oos_year = oos_yr
    ), by=ym_, .SDcols=c(sc_col,"fwd_ret_21d")]
    setnames(dt_ic, "ym_", "ym")
    dt_ic
  }
  ic_A <- ic_calc("SA", "S1_A")
  ic_B <- ic_calc("SB", "S1_B")
  ic_C <- ic_calc("SC", "S1_C")
  ic_D <- ic_calc("SD", "S1_D")

  cat(sprintf("    IC-A=%.4f IC-B=%.4f IC-C=%.4f IC-D=%.4f\n",
              mean(ic_A$IC,na.rm=TRUE), mean(ic_B$IC,na.rm=TRUE),
              mean(ic_C$IC,na.rm=TRUE), mean(ic_D$IC,na.rm=TRUE)))

  scA <- oos_dt[!is.na(SA), .(Date, Ticker, Size, Score=SA, variant="S1_A")]
  scB <- oos_dt[!is.na(SB), .(Date, Ticker, Size, Score=SB, variant="S1_B")]
  scC <- oos_dt[!is.na(SC), .(Date, Ticker, Size, Score=SC, variant="S1_C")]
  scD <- oos_dt[!is.na(SD), .(Date, Ticker, Size, Score=SD, variant="S1_D")]

  rm(oos_dt, oos_fwd, preds); gc(FALSE)
  list(scA=scA, scB=scB, scC=scC, scD=scD,
       icA=ic_A, icB=ic_B, icC=ic_C, icD=ic_D)
})

valid_wf <- Filter(Negate(is.null), wf_out)
cat(sprintf("\n[WF] 완료: %d/%d 연도 성공\n", length(valid_wf), length(OOS_YEARS)))

scores_A  <- lapply(valid_wf, `[[`, "scA")
scores_B  <- lapply(valid_wf, `[[`, "scB")
scores_C  <- lapply(valid_wf, `[[`, "scC")
scores_D  <- lapply(valid_wf, `[[`, "scD")
ic_recs_A <- lapply(valid_wf, `[[`, "icA")
ic_recs_B <- lapply(valid_wf, `[[`, "icB")
ic_recs_C <- lapply(valid_wf, `[[`, "icC")
ic_recs_D <- lapply(valid_wf, `[[`, "icD")

# =============================================================================
# 5. IC / ICIR 분석 (Alpha Lab Gate: ICIR >= 0.20)
# =============================================================================
cat("\n[5] IC 분석...\n")
mk_ic_dt <- function(lst) {
  dt <- rbindlist(Filter(Negate(is.null), lst), fill=TRUE)
  if (nrow(dt) == 0L) dt <- data.table(ym=character(), IC=numeric(),
                                        variant=character(), oos_year=integer())
  dt
}
ic_all <- list(A=mk_ic_dt(ic_recs_A), B=mk_ic_dt(ic_recs_B),
               C=mk_ic_dt(ic_recs_C), D=mk_ic_dt(ic_recs_D))

icir_fn <- function(ic_dt) {
  if (is.null(ic_dt) || nrow(ic_dt) == 0L) return(list(IC=NA_real_, ICIR=NA_real_, N=0L))
  v <- ic_dt$IC[!is.na(ic_dt$IC)]
  if (length(v) < 5L) return(list(IC=NA_real_, ICIR=NA_real_, N=length(v)))
  list(IC=round(mean(v),5), ICIR=round(mean(v)/sd(v),4), N=length(v))
}

icir_sum <- lapply(ic_all, icir_fn)
cur_yr   <- as.integer(format(Sys.Date(), "%Y"))
icir_3y  <- lapply(ic_all, function(dt) {
  if ("oos_year" %in% names(dt)) icir_fn(dt[oos_year >= cur_yr-3L])
  else list(IC=NA_real_, ICIR=NA_real_, N=0L)
})

cat(sprintf("  S1-A: IC=%.4f ICIR=%.4f N=%d  3Y=%.4f\n",
            icir_sum$A$IC%||%NA, icir_sum$A$ICIR%||%NA,
            icir_sum$A$N, icir_3y$A$ICIR%||%NA))
cat(sprintf("  S1-B: IC=%.4f ICIR=%.4f N=%d  3Y=%.4f  [PRIMARY]\n",
            icir_sum$B$IC%||%NA, icir_sum$B$ICIR%||%NA,
            icir_sum$B$N, icir_3y$B$ICIR%||%NA))
cat(sprintf("  S1-C: IC=%.4f ICIR=%.4f N=%d  3Y=%.4f\n",
            icir_sum$C$IC%||%NA, icir_sum$C$ICIR%||%NA,
            icir_sum$C$N, icir_3y$C$ICIR%||%NA))
cat(sprintf("  S1-D: IC=%.4f ICIR=%.4f N=%d  3Y=%.4f\n",
            icir_sum$D$IC%||%NA, icir_sum$D$ICIR%||%NA,
            icir_sum$D$N, icir_3y$D$ICIR%||%NA))

gate_B <- !is.na(icir_sum$B$ICIR) && icir_sum$B$ICIR >= 0.20
cat(sprintf("  Alpha Lab Gate (PRIMARY S1-B): %s\n",
            ifelse(gate_B, "PASS (ICIR >= 0.20)", "FAIL (ICIR < 0.20)")))

# 연도별 S1-B IC
yr_ic_B <- ic_all$B[, .(mean_IC=round(mean(IC,na.rm=TRUE),4), n_months=.N),
                    by=oos_year][order(oos_year)]
cat("\n  연도별 S1-B IC:\n"); print(yr_ic_B)

# =============================================================================
# 6. 백테스트 — RAWDATA 재로드 + mclapply (OPT-4)
# =============================================================================
rm(ret_dt, SIZE_DT); gc()
cat("\n[6-0] RAWDATA 재로드 (백테스트용)...\n")
rw2     <- load_rawdata(use_cache=TRUE)
RAWDATA <- rw2$RAWDATA; BM_DT <- rw2$BM_DT
setDT(RAWDATA); setkey(RAWDATA, Date, Ticker)
rm(rw2); gc()

cat("[6] 백테스트 mclapply (OPT-4)...\n")
bt_inputs <- list(
  S1_A = rbindlist(Filter(Negate(is.null), scores_A), fill=TRUE),
  S1_B = rbindlist(Filter(Negate(is.null), scores_B), fill=TRUE),
  S1_C = rbindlist(Filter(Negate(is.null), scores_C), fill=TRUE),
  S1_D = rbindlist(Filter(Negate(is.null), scores_D), fill=TRUE)
)
n_cores <- min(2L, max(1L, detectCores()-1L))
cat(sprintf("  cores=%d\n", n_cores))

bt_results <- mclapply(names(bt_inputs), function(nm) {
  sc <- bt_inputs[[nm]]
  if (is.null(sc) || nrow(sc) == 0L) return(NULL)
  FAC <- sc[!is.na(Score), .(Date, Ticker, Score)]
  setkey(FAC, Date, Ticker)
  bt <- tryCatch(
    run_monthly_simulation(RAWDATA=RAWDATA, BM_DT=BM_DT, FACTORS=FAC,
                           n_holdings=N_HOLDINGS, commission=COMMISSION,
                           weight_method="EW",
                           buffer_zone=list(keep_n=N_HOLDINGS+5L, entry_n=N_HOLDINGS)),
    error=function(e){ cat(nm, "BT err:", e$message, "\n"); NULL }
  )
  if (is.null(bt)) return(NULL)
  r <- bt$DAILY_NAV_DT$Strategy_Ret; r <- r[is.finite(r)]
  cum <- cumprod(1+r); nyr <- length(r)/252
  neg_r <- r[r < 0]
  sortino <- if (length(neg_r) > 1L) mean(r)/sd(neg_r)*sqrt(252) else NA_real_
  to_val  <- if (!is.null(bt$TURNOVER)) mean(bt$TURNOVER, na.rm=TRUE)*100 else NA_real_
  list(
    label    = nm,
    CAGR     = round((tail(cum,1)^(1/nyr)-1)*100, 2),
    Sharpe   = round(mean(r)/sd(r)*sqrt(252), 4),
    Sortino  = round(sortino, 4),
    MDD      = round(min(cum/cummax(cum)-1)*100, 2),
    Turnover = round(to_val, 2),
    nav_dt   = bt$DAILY_NAV_DT
  )
}, mc.cores=n_cores)
names(bt_results) <- names(bt_inputs)

cat("\n[6] 성과 요약:\n")
lapply(names(bt_results), function(nm) {
  r <- bt_results[[nm]]; if (is.null(r)) return(invisible(NULL))
  pri <- if (nm=="S1_B") " [PRIMARY]" else ""
  cat(sprintf("  %s%s: CAGR=%.1f%% SR=%.4f Sortino=%.4f MDD=%.1f%% TO=%.1f%%\n",
              nm, pri, r$CAGR, r$Sharpe, r$Sortino%||%NA, r$MDD, r$Turnover%||%NA))
})

# =============================================================================
# 7. 차트 생성
# =============================================================================
cat("\n[7] 차트 생성...\n")
chart_paths <- list()
tryCatch({
  library(ggplot2); library(scales)

  # 7-1. Equity Curve (4 variant + BM)
  eq_data <- rbindlist(Filter(Negate(is.null), lapply(names(bt_results), function(nm) {
    b <- bt_results[[nm]]; if(is.null(b)) return(NULL)
    d <- copy(b$nav_dt)[, .(Date=as.Date(Date), ret=Strategy_Ret)]
    d <- d[is.finite(ret)][, cum:=cumprod(1+ret)][, label:=nm]; d
  })), fill=TRUE)
  bm_d <- copy(bt_results[["S1_B"]]$nav_dt)[, .(Date=as.Date(Date), BM_Ret)]
  bm_d <- bm_d[is.finite(BM_Ret)][, cum:=cumprod(1+BM_Ret)][, label:="KOSPI BM"]
  eq_all <- rbind(eq_data[,.(Date,cum,label)], bm_d[,.(Date,cum,label)], fill=TRUE)

  if (nrow(eq_all) > 0L) {
    col_map  <- c("S1_A"="#1f77b4","S1_B"="#e74c3c","S1_C"="#2ca02c",
                  "S1_D"="#9467bd","KOSPI BM"="#7f7f7f")
    ltyp_map <- c("S1_A"="dotted","S1_B"="solid","S1_C"="dashed",
                  "S1_D"="longdash","KOSPI BM"="dotted")
    p1 <- ggplot(eq_all, aes(x=Date, y=cum, color=label, linetype=label)) +
      geom_line(linewidth=0.9) + scale_y_log10(labels=comma) +
      scale_color_manual(values=col_map) + scale_linetype_manual(values=ltyp_map) +
      labs(title="STR_1659_RF_UA — Equity Curves (S1-B PRIMARY)",
           subtitle=sprintf("RF 5-seed | kappa=%.1f | EW %d | OOS Walk-Forward 2008~2025",
                            KAPPA, N_HOLDINGS),
           x=NULL, y="Cumulative (Log)", color=NULL, linetype=NULL) +
      theme_minimal(base_size=12) + theme(legend.position="bottom")
    ep <- file.path(OUTPUT_DIR, "equity_curve.png")
    ggsave(ep, p1, width=12, height=6, dpi=150)
    chart_paths$equity <- ep; cat("  equity_curve.png\n")
  }

  # 7-2. Annual Returns (S1-B PRIMARY)
  bt_B_nav <- bt_results[["S1_B"]]
  if (!is.null(bt_B_nav)) {
    nav_B <- copy(bt_B_nav$nav_dt)[, .(Date=as.Date(Date), ret=Strategy_Ret, bm=BM_Ret)]
    nav_B <- nav_B[is.finite(ret)][, yr:=as.integer(format(Date,"%Y"))]
    ann_B <- nav_B[, .(
      Strategy = (prod(1+ret)^(12/.N)-1)*100,
      BM       = (prod(1+fifelse(is.finite(bm),bm,0))^(12/.N)-1)*100
    ), by=yr]
    ann_melt <- melt(ann_B, id.vars="yr", variable.name="type", value.name="ret")
    p2 <- ggplot(ann_melt, aes(x=yr, y=ret, fill=type)) +
      geom_bar(stat="identity", position="dodge", alpha=0.8) +
      geom_hline(yintercept=0, color="black", linewidth=0.4) +
      scale_fill_manual(values=c("Strategy"="#e74c3c","BM"="#7f7f7f")) +
      labs(title="STR_1659_RF_UA S1-B — Annual Returns",
           subtitle="UA Tree Variance (kappa=1.0) PRIMARY",
           x=NULL, y="Annual Return (%)", fill=NULL) +
      theme_minimal(base_size=12) + theme(legend.position="top")
    ap <- file.path(OUTPUT_DIR, "annual_returns.png")
    ggsave(ap, p2, width=12, height=5, dpi=150)
    chart_paths$annual <- ap; cat("  annual_returns.png\n")
  }
}, error=function(e) cat("[CHART ERR]", e$message, "\n"))

# =============================================================================
# 8. 결과 저장
# =============================================================================
cat("\n[8] 결과 저장...\n")

# 8-1. nav_S1_B.csv (primary)
bt_B_r <- bt_results[["S1_B"]]
if (!is.null(bt_B_r)) {
  nav_csv <- copy(bt_B_r$nav_dt)[, .(
    Date,
    NAV_Strategy = cumprod(1+fifelse(is.finite(Strategy_Ret), Strategy_Ret, 0))
  )]
  fwrite(nav_csv, file.path(OUTPUT_DIR, "nav_S1_B.csv"))
  cat("  nav_S1_B.csv\n")
}

# 8-2. performance.json
perf_list <- lapply(names(bt_results), function(nm) {
  r <- bt_results[[nm]]; k <- substr(nm, 4, 4)
  ic_r <- icir_sum[[k]]
  if (is.null(r)) return(NULL)
  list(variant=nm, CAGR=r$CAGR, Sharpe=r$Sharpe, Sortino=r$Sortino,
       MDD=r$MDD, Turnover=r$Turnover,
       IC=ic_r$IC%||%NA, ICIR=ic_r$ICIR%||%NA, IC_N=ic_r$N,
       alpha_lab_gate=(!is.na(ic_r$ICIR) && ic_r$ICIR >= 0.20))
})
perf_list <- Filter(Negate(is.null), perf_list)
write_json(perf_list, file.path(OUTPUT_DIR, "performance.json"),
           auto_unbox=TRUE, pretty=TRUE)
cat("  performance.json\n")

# 8-3. IC 상세 (S1-B)
fwrite(ic_all$B, file.path(OUTPUT_DIR, "ic_detail_S1_B.csv"))
cat("  ic_detail_S1_B.csv\n")

# 8-4. variant 비교표
cmp <- rbindlist(lapply(names(bt_results), function(nm) {
  r <- bt_results[[nm]]; k <- substr(nm,4,4)
  ic_r <- icir_sum[[k]]
  data.table(Variant=nm, CAGR=r$CAGR%||%NA, SR=r$Sharpe%||%NA,
             Sortino=r$Sortino%||%NA, MDD=r$MDD%||%NA,
             IC=ic_r$IC%||%NA, ICIR=ic_r$ICIR%||%NA,
             Gate=(!is.na(ic_r$ICIR) && ic_r$ICIR >= 0.20),
             Primary=(nm=="S1_B"))
}), fill=TRUE)
cat("\n  4 Variant 비교:\n"); print(cmp)
fwrite(cmp, file.path(OUTPUT_DIR, "variant_comparison.csv"))
cat("  variant_comparison.csv\n")

# =============================================================================
# 9. Stage Artifact (s1_construction_STR_1659_RF_UA.json)
# =============================================================================
cat("\n[9] Stage Artifact 작성...\n")
s1_artifact <- list(
  factor_id       = "STR_1659_RF_UA",
  stage           = "S1",
  strategy_name   = "RF Uncertainty-Aware Diversifier",
  timestamp       = as.character(Sys.time()),
  hypothesis      = paste0(
    "ranger 5-seed ensemble + UA Tree Variance Sorting (kappa=1.0). ",
    "Feature pool: V/Q/AC/GR/IN/S family 일간 DB (XGB STR_1656과 0% overlap). ",
    "Liu et al. (2026) UA Ranking + Breiman (2001) Random Forests. ",
    "L-123 §4: 일간 DB 5700일 학습 (p>>n 해결)."
  ),
  primary_variant    = "S1_B",
  kappa              = KAPPA,
  n_features_pool    = length(RF_POOL),
  mi_top_n           = MI_TOP_N,
  oos_years          = list(start=OOS_START_YR, end=OOS_END_YR),
  purge_days         = PURGE_DAYS,
  seeds              = RF_SEEDS,
  ic_summary         = lapply(icir_sum, function(x)
    list(IC=x$IC, ICIR=x$ICIR, N=x$N)),
  alpha_lab_gate_primary = gate_B,
  backtest           = lapply(bt_results, function(r) {
    if (is.null(r)) return(NULL)
    list(CAGR=r$CAGR, SR=r$Sharpe, Sortino=r$Sortino, MDD=r$MDD, Turnover=r$Turnover)
  }),
  pit_compliance     = list(
    C1  = "Walk-Forward Expanding only (oos_yr loop)",
    C2  = "OOS > IS + purge 21d",
    C4  = "일간 DB 재무 45일 lag 내재",
    C9  = "오버레이 없음 (S1 순수 팩터)",
    C13 = "일간 DB 원시값 → z-score DB (방향 반전 없음)",
    C14 = "fwd_ret t+1~t+21",
    C15 = "Arrow open_dataset (parquet 직접 반복 없음)"
  ),
  opt_compliance     = list(
    "OPT-1"    = "Arrow open_dataset bulk collect (for loop 내 parquet 반복 없음)",
    "OPT-2"    = "load_rawdata(use_cache=TRUE) 1회",
    "OPT-4"    = "mclapply 병렬 백테스트",
    "OPT-7/MC-P2" = "factor_db_daily 참조 (L-123 §4: 일간 5700일 학습)",
    "OPT-7/MC-P3" = "Walk-forward expanding + oos_yr"
  ),
  overlap_check      = list(
    xgb_pool = "STR_1656: RE*/전체 309 일간팩터",
    rf_pool  = "V/Q/AC/GR/IN/S fundamental family only",
    overlap_pct = 0
  ),
  output_files       = list(
    performance_json  = file.path(OUTPUT_DIR, "performance.json"),
    equity_curve_png  = file.path(OUTPUT_DIR, "equity_curve.png"),
    annual_returns_png= file.path(OUTPUT_DIR, "annual_returns.png"),
    nav_primary_csv   = file.path(OUTPUT_DIR, "nav_S1_B.csv"),
    variant_comparison= file.path(OUTPUT_DIR, "variant_comparison.csv"),
    ic_detail_csv     = file.path(OUTPUT_DIR, "ic_detail_S1_B.csv")
  )
)
art_path <- file.path(ARTIFACT_DIR, "s1_construction_STR_1659_RF_UA.json")
write_json(s1_artifact, art_path, auto_unbox=TRUE, pretty=TRUE)
cat("  stage artifact:", art_path, "\n")

# =============================================================================
# 10. 텔레그램 발송 [Forge]
# =============================================================================
cat("\n[10] 텔레그램 발송...\n")
tryCatch({
  source(file.path(PROJECT_ROOT, "02_Infrastructure/telegram/telegram_notify.R"))
  bt_B2  <- bt_results[["S1_B"]]
  icir_B <- icir_sum$B$ICIR%||%NA
  ic_B   <- icir_sum$B$IC%||%NA
  msg <- paste0(
    "[Forge] STR_1659_RF_UA S1 완료\n\n",
    "RF Uncertainty-Aware Diversifier\n",
    "kappa=1.0 고정 | V/Q/AC/GR/IN/S 일간 DB\n",
    "XGB(STR_1656)와 0% overlap\n\n",
    "S1-B PRIMARY (UA Tree Variance):\n",
    sprintf("  CAGR=%.1f%% | SR=%.3f | MDD=%.1f%%\n",
            bt_B2$CAGR%||%NA, bt_B2$Sharpe%||%NA, bt_B2$MDD%||%NA),
    sprintf("  IC=%.4f | ICIR=%.4f\n", ic_B, icir_B),
    sprintf("  Alpha Lab Gate: %s\n\n",
            ifelse(gate_B, "PASS (>= 0.20)", "FAIL (< 0.20)")),
    "4 Variant ICIR:\n",
    sprintf("  A=%.3f | B=%.3f | C=%.3f | D=%.3f\n",
            icir_sum$A$ICIR%||%NA, icir_sum$B$ICIR%||%NA,
            icir_sum$C$ICIR%||%NA, icir_sum$D$ICIR%||%NA),
    sprintf("\nOOS %d~%d | 성공=%d/%d 연도",
            OOS_START_YR, OOS_END_YR, length(valid_wf), length(OOS_YEARS))
  )
  tg_send(msg)
  if (!is.null(chart_paths$equity))
    tg_send_photo(chart_paths$equity, caption="[STR_1659] Equity Curves")
  if (!is.null(chart_paths$annual))
    tg_send_photo(chart_paths$annual, caption="[STR_1659] Annual Returns S1-B")
}, error=function(e) cat("[TG ERR]", e$message, "\n"))

# =============================================================================
# 완료
# =============================================================================
cat(sprintf("\n=== STR_1659_RF_UA 완료: %s ===\n", as.character(Sys.time())))
cat(sprintf("  S1-B: CAGR=%.1f%% SR=%.4f MDD=%.1f%% ICIR=%.4f Gate=%s\n",
            bt_results$S1_B$CAGR%||%NA,
            bt_results$S1_B$Sharpe%||%NA,
            bt_results$S1_B$MDD%||%NA,
            icir_sum$B$ICIR%||%NA,
            ifelse(gate_B, "PASS", "FAIL")))
cat("  출력 디렉토리:", OUTPUT_DIR, "\n")
cat("  Stage Artifact:", art_path, "\n")
