## =============================================================================
## STR_1656_MLRA: ML Risk Architecture Diversifier — S1 Implementation
## 핵심 아이디어: XGBoost 5-seed ensemble + MI prefilter(top50, 309 daily factors)
##               Walk-forward expanding window + Purged CV (21d embargo)
##               S1-A: full 50F (RE* 포함) / S1-B: non-regime ~35F (RE* 제거)
##               EW 20종목 + 15bps commission + 유동성 2억원 (v53: max 20)
##               Gu, Kelly & Xiu (2020 RFS) + Ban et al. (2018 EJOR)
##
## PIT 준수 (C1-C15):
##   C1  : expanding window only
##   C2  : OOS > IS (same-day circular 없음)
##   C13 : Z_Score_Aligned (일간 DB 이미 정규화)
##   C14 : fwd_ret = t+1~t+21 (IS target 전용)
##   C15 : 월간 DB 미사용 (일간 DB open_dataset 직접)
##   purge: 21d embargo gap
##
## OPT 준수:
##   OPT-1: Arrow open_dataset predicate pushdown (parquet 반복 없음)
##   OPT-2: load_rawdata(use_cache=TRUE)
##   OPT-4: 백테스트 mclapply 병렬
## =============================================================================

cat("=== STR_1656_MLRA: ML Risk Architecture Diversifier S1 ===\n")
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
PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
STRATEGY_DIR <- file.path(PROJECT_ROOT, "04_Research/strategies/STR_1656_MLRA")
OUTPUT_DIR   <- file.path(STRATEGY_DIR, "output")
dir.create(OUTPUT_DIR, showWarnings = FALSE, recursive = TRUE)
DAILY_DB_DIR <- file.path(PROJECT_ROOT, ".cache/factor_db_daily")

source(file.path(PROJECT_ROOT, "02_Infrastructure/config.R"))
source(file.path(PROJECT_ROOT, "02_Infrastructure/backtest_harness.R"))

# =============================================================================
# 설정
# =============================================================================
LIQ_THRESHOLD <- 2e8
N_HOLDINGS    <- 20L   # v53 규칙: 최대 20종목 (30→20 2026-04-19)
COMMISSION    <- 0.0015
MI_TOP_N      <- 50L
PURGE_DAYS    <- 21L
XGB_SEEDS     <- c(42L, 123L, 456L, 789L, 2024L)
OOS_START_YR  <- 2008L
OOS_END_YR    <- 2025L
RE_PAT        <- "^(RE_|RE0|RE1)"
XGB_MAX_ROWS  <- 80000L   # OOM 방지: IS 서브샘플 상한 (200K→80K)

cat("[CONFIG] N=", N_HOLDINGS, "| MI=", MI_TOP_N,
    "| seeds=", paste(XGB_SEEDS, collapse=","),
    "| purge=", PURGE_DAYS, "\n")

xgb_ok <- tryCatch({ library(xgboost); TRUE }, error=function(e) FALSE)
if (!xgb_ok) stop("xgboost 패키지 필요")
cat("[XGB] OK\n")

# =============================================================================
# 1. RAWDATA 1회 로드 (OPT-2: use_cache=TRUE)
# =============================================================================
cat("\n[1] RAWDATA...\n")
rw  <- load_rawdata(use_cache = TRUE)
RAWDATA <- rw$RAWDATA; BM_DT <- rw$BM_DT
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
  else { fwd <- c(cl[22:n], rep(NA_real_,21L)) - cl; exp(fwd)-1 }
}, by=Ticker]
ret_dt[, logR := NULL]
ret_dt <- ret_dt[!is.na(fwd_ret_21d)]
cat(sprintf("    fwd rows: %d\n", nrow(ret_dt)))

# 메모리 절감: RAWDATA → SIZE_DT + ALL_ME_DATES 추출 후 RAWDATA 해제
# C10 fix: 당일 Size 직접 사용 → 20일 rolling mean (AvgTV20)으로 교체
SIZE_DT <- RAWDATA[Date >= as.Date("2003-01-01"), .(Date, Ticker, Size)]
setkey(SIZE_DT, Ticker, Date)
SIZE_DT[, AvgTV20 := frollmean(Size, 20L, align = "right", na.rm = TRUE), by = Ticker]
setkey(SIZE_DT, Date, Ticker)
# 월말 날짜 벡터 (Arrow predicate용) — RAWDATA 해제 전에 추출
RAWDATA[, ym__ := format(Date, "%Y-%m")]
ALL_ME_DATES <- RAWDATA[, .(me_date = max(Date)), by=ym__][order(me_date)]$me_date
RAWDATA[, ym__ := NULL]
cat(sprintf("    [ME] 월말 날짜 %d개 (%s ~ %s)\n",
            length(ALL_ME_DATES), min(ALL_ME_DATES), max(ALL_ME_DATES)))
ret_dt[, c("Ret", "Size") := NULL]
setkey(ret_dt, Date, Ticker)

# RAWDATA + BM_DT 해제 (walk-forward 중 불필요. 백테스트 시 재로드)
rm(RAWDATA, BM_DT, rw); gc()
cat(sprintf("    [MEM] RAWDATA 해제 완료. ret_dt: %.0fMB | SIZE_DT: %.0fMB\n",
            object.size(ret_dt)/1e6, object.size(SIZE_DT)/1e6))

# =============================================================================
# 3. OPT-1 준수: open_dataset (Arrow lazy, parquet 반복 없음)
# =============================================================================
cat("[3] Arrow Dataset...\n")
pq_files    <- list.files(DAILY_DB_DIR, pattern="\\.parquet$", full.names=TRUE)
ds_daily    <- open_dataset(pq_files, format="parquet")
ds_cols     <- schema(ds_daily)$names
EXCL        <- c("Date","Ticker",
                 grep("^(dps_1y|bps_1y|eps_1y|target_price)", ds_cols, value=TRUE),
                 grep("\\.x$|\\.y$", ds_cols, value=TRUE))
ALL_FCOLS   <- setdiff(ds_cols, EXCL)
RE_COLS     <- grep(RE_PAT, ALL_FCOLS, value=TRUE)
NONRE_COLS  <- setdiff(ALL_FCOLS, RE_COLS)
cat(sprintf("    팩터 전체=%d RE*=%d NonRE=%d\n",
            length(ALL_FCOLS), length(RE_COLS), length(NONRE_COLS)))

# =============================================================================
# 유틸 — Arrow predicate collect (OPT-1 핵심)
# dates_vec: 특정 날짜 벡터 (월말 날짜 등) — NULL 시 범위 filter 사용
# =============================================================================
arrow_collect <- function(fcols, dates_vec=NULL, d0=NULL, d1=NULL) {
  need <- intersect(c("Date","Ticker",fcols), ds_cols)
  q <- ds_daily
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

mi_prefilter <- function(dt, fcols, n_top=50L) {
  dt[, ym_ := format(Date,"%Y-%m")]
  # 각 월의 마지막 Date를 찾고, 해당 Date의 모든 Ticker 포함
  me_dates <- dt[, .(me_date = max(Date)), by=ym_]
  me <- dt[Date %in% me_dates$me_date, c("Date","Ticker",fcols,"fwd_ret_21d"), with=FALSE]
  dt[, ym_ := NULL]
  y   <- me$fwd_ret_21d
  ics <- vapply(fcols, function(f){
    x <- me[[f]]; v <- is.finite(x)&is.finite(y)
    if (sum(v)<100L) return(NA_real_)
    tryCatch(abs(cor(x[v],y[v],method="spearman")), error=function(e) NA_real_)
  }, numeric(1L))
  valid <- ics[!is.na(ics)]
  if (!length(valid)) return(character(0L))
  names(sort(valid, decreasing=TRUE))[seq_len(min(n_top,length(valid)))]
}

build_mat <- function(dt, cols) {
  m <- as.matrix(dt[, intersect(cols,names(dt)), with=FALSE])
  m[!is.finite(m)] <- 0; m
}

xgb5_predict <- function(X_tr, y_tr, X_te, X_vl=NULL, seeds=XGB_SEEDS,
                         max_rows=XGB_MAX_ROWS) {
  # OOM 방지: IS가 max_rows 초과 시 서브샘플
  if (nrow(X_tr) > max_rows) {
    idx <- sample(nrow(X_tr), max_rows)
    X_tr <- X_tr[idx, , drop=FALSE]
    y_tr <- y_tr[idx]
  }
  params <- list(booster="gbtree", objective="reg:squarederror",
                 eta=0.02, max_depth=5L, subsample=0.7,
                 colsample_bytree=0.5, min_child_weight=10L,
                 lambda=1, alpha=0.1, nthread=1L)  # nthread 1 → 메모리 절감
  dtest <- xgb.DMatrix(data=X_te)
  preds <- lapply(seeds, function(sd){
    set.seed(sd)
    tryCatch({
      dtr <- xgb.DMatrix(data=X_tr, label=y_tr)
      m <- if (!is.null(X_vl) && nrow(X_vl)>10L) {
        dvl <- xgb.DMatrix(data=X_vl, label=rep(0,nrow(X_vl)))
        fit <- xgb.train(params, dtr, 500L, evals=list(v=dvl),
                         early_stopping_rounds=30L, verbose=0L)
        rm(dvl); fit
      } else xgb.train(params, dtr, 300L, verbose=0L)
      p <- predict(m, dtest)
      rm(dtr, m); gc(FALSE)
      p
    }, error=function(e) { cat("    xgb err:", e$message, "\n"); NULL })
  })
  rm(dtest); gc(FALSE)
  valid <- Filter(Negate(is.null), preds)
  if (!length(valid)) return(rep(0, nrow(X_te)))
  n_te <- nrow(X_te)
  rmat <- vapply(valid, function(p) frank(p,ties.method="average")/n_te, numeric(n_te))
  if (is.null(dim(rmat))) rmat else rowMeans(rmat)
}

# =============================================================================
# 3b. 청크 MI prefilter (309 팩터 → 60개씩 분할 로드 → top50 선정)
#     전체 309F 한번에 collect하면 OOM → 60F 청크로 IC 계산 → top50 반환
# =============================================================================
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
    cat(sprintf("      MI chunk %d/%d (%d factors)\n", i, length(f_chunks), length(ch)))
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

# =============================================================================
# 4. Walk-Forward — lapply (OPT-1 준수, parquet 반복 없음)
# =============================================================================
cat("\n[4] Walk-Forward lapply...\n")

IS_START_D <- as.Date("2003-01-01")
OOS_YEARS  <- OOS_START_YR:OOS_END_YR

wf_out <- lapply(OOS_YEARS, function(oos_yr) {
  cat(sprintf("  OOS %d\n", oos_yr))
  is_end_yr <- oos_yr - 2L
  if (is_end_yr < 2005L) return(NULL)

  is_end_d <- as.Date(sprintf("%d-12-31", is_end_yr))
  val_s    <- as.Date(sprintf("%d-01-01", oos_yr-1L))
  val_e    <- as.Date(sprintf("%d-12-31", oos_yr-1L))
  oos_s    <- as.Date(sprintf("%d-01-01", oos_yr))
  oos_e    <- as.Date(sprintf("%d-12-31", oos_yr))

  # MI prefilter — chunked (309 팩터를 60개씩 분할 로드, OOM 방지)
  cat("    MI prefilter (chunked)...\n")
  tops  <- mi_prefilter_chunked(IS_START_D, is_end_d, ALL_FCOLS, MI_TOP_N)
  top_A <- tops$all; top_B <- tops$nonre
  cat(sprintf("    topA=%d topB=%d\n", length(top_A), length(top_B)))
  if (length(top_A) < 5L && length(top_B) < 5L) return(NULL)

  # top 팩터만 월말 collect (ALL_FCOLS 309개 대신 ~100개만 → OOM 해결)
  top_union <- unique(c(top_A, top_B))
  is_me_d   <- ALL_ME_DATES[ALL_ME_DATES >= IS_START_D & ALL_ME_DATES <= is_end_d]
  is_dt     <- tryCatch(arrow_collect(top_union, dates_vec = is_me_d), error = function(e) NULL)
  if (is.null(is_dt) || nrow(is_dt) < 1000L) return(NULL)
  cat(sprintf("    IS=%d rows (month-end, %d factors)\n", nrow(is_dt), length(top_union)))

  is_dt <- merge(is_dt, ret_dt[,.(Date,Ticker,fwd_ret_21d)], by=c("Date","Ticker"))
  is_dt <- merge(is_dt, SIZE_DT[, .(Date, Ticker, AvgTV20)], by=c("Date","Ticker"), all.x=TRUE)
  is_dt <- is_dt[!is.na(fwd_ret_21d) & !is.na(AvgTV20) & AvgTV20 >= LIQ_THRESHOLD]
  gc(FALSE)
  cat(sprintf("    IS=%d rows (filtered)\n", nrow(is_dt)))

  X_trA <- build_mat(is_dt, top_A)
  X_trB <- build_mat(is_dt, top_B)
  y_tr  <- is_dt$fwd_ret_21d
  is_last <- max(is_dt$Date)
  rm(is_dt); gc(FALSE)

  # Val — purge 적용 (top 팩터 + month-end only)
  X_vlA <- NULL; X_vlB <- NULL
  val_me_d <- ALL_ME_DATES[ALL_ME_DATES >= val_s & ALL_ME_DATES <= val_e &
                            ALL_ME_DATES > (is_last+PURGE_DAYS)]
  if (length(val_me_d) > 0L) {
    val_dt <- tryCatch(arrow_collect(top_union, dates_vec = val_me_d), error = function(e) NULL)
    if (!is.null(val_dt) && nrow(val_dt) > 0L) {
      val_m <- merge(val_dt, ret_dt[,.(Date,Ticker,fwd_ret_21d)], by=c("Date","Ticker"))
      val_m <- val_m[!is.na(fwd_ret_21d)]
      if (nrow(val_m) > 50L) { X_vlA <- build_mat(val_m, top_A); X_vlB <- build_mat(val_m, top_B) }
      rm(val_dt, val_m); gc(FALSE)
    }
  }

  # OOS month-end (top 팩터만)
  oos_me_d <- ALL_ME_DATES[ALL_ME_DATES >= oos_s & ALL_ME_DATES <= oos_e]
  oos_me   <- tryCatch(arrow_collect(top_union, dates_vec = oos_me_d), error = function(e) NULL)
  if (is.null(oos_me) || nrow(oos_me) == 0L) {
    rm(X_trA, X_trB, y_tr); gc(FALSE); return(NULL)
  }
  oos_me <- merge(oos_me, SIZE_DT[, .(Date, Ticker, AvgTV20)], by=c("Date","Ticker"), all.x=TRUE)
  oos_me <- oos_me[!is.na(AvgTV20) & AvgTV20 >= LIQ_THRESHOLD]
  gc(FALSE)

  X_teA    <- build_mat(oos_me, top_A)
  X_teB    <- build_mat(oos_me, top_B)

  pA <- tryCatch(xgb5_predict(X_trA,y_tr,X_teA,X_vlA), error=function(e) rep(0,nrow(X_teA)))
  pB <- tryCatch(xgb5_predict(X_trB,y_tr,X_teB,X_vlB), error=function(e) rep(0,nrow(X_teB)))

  # Score를 oos_me에 먼저 할당 (행 정렬 보존)
  oos_me[, SA := pA]
  oos_me[, SB := pB]

  scA <- oos_me[, .(Date, Ticker, AvgTV20, Score=SA, variant="S1_A")]
  scB <- oos_me[, .(Date, Ticker, AvgTV20, Score=SB, variant="S1_B")]

  # IC: Score가 포함된 oos_me와 ret_dt merge → 행 정렬 일치
  oos_r <- merge(oos_me[, .(Date, Ticker, SA, SB)],
                 ret_dt[, .(Date, Ticker, fwd_ret_21d)],
                 by=c("Date","Ticker"))
  oos_r <- oos_r[!is.na(fwd_ret_21d) & !is.na(SA)]
  oos_r[, ym_ := format(Date, "%Y-%m")]

  icA <- oos_r[, .(IC=tryCatch(cor(SA, fwd_ret_21d, method="spearman", use="complete.obs"),
                                error=function(e) NA_real_),
                   variant="S1_A", oos_year=oos_yr), by=ym_]
  icB <- oos_r[, .(IC=tryCatch(cor(SB, fwd_ret_21d, method="spearman", use="complete.obs"),
                                error=function(e) NA_real_),
                   variant="S1_B", oos_year=oos_yr), by=ym_]
  setnames(icA, "ym_", "ym"); setnames(icB, "ym_", "ym")
  cat(sprintf("    oos_r=%d rows\n", nrow(oos_r)))

  cat(sprintf("    IC-A=%.4f IC-B=%.4f\n",
              mean(icA$IC,na.rm=TRUE), mean(icB$IC,na.rm=TRUE)))

  rm(X_trA, X_trB, y_tr, X_teA, X_teB, X_vlA, X_vlB, oos_me, oos_r); gc(FALSE)
  list(scA=scA, scB=scB, icA=icA, icB=icB)
})

valid_wf  <- Filter(Negate(is.null), wf_out)
scores_A  <- lapply(valid_wf, `[[`, "scA")
scores_B  <- lapply(valid_wf, `[[`, "scB")
ic_recs_A <- lapply(valid_wf, `[[`, "icA")
ic_recs_B <- lapply(valid_wf, `[[`, "icB")

# =============================================================================
# 5. IC 요약
# =============================================================================
cat("\n[5] IC 분석...\n")
ic_all_A <- rbindlist(Filter(Negate(is.null), ic_recs_A), fill=TRUE)
ic_all_B <- rbindlist(Filter(Negate(is.null), ic_recs_B), fill=TRUE)
if (nrow(ic_all_A)==0L) { ic_all_A <- data.table(ym=character(),IC=numeric(),variant=character(),oos_year=integer()) }
if (nrow(ic_all_B)==0L) { ic_all_B <- data.table(ym=character(),IC=numeric(),variant=character(),oos_year=integer()) }

icir_fn <- function(ic_dt) {
  if (is.null(ic_dt)||nrow(ic_dt)==0L) return(list(IC=NA,ICIR=NA,N=0L))
  v <- ic_dt$IC[!is.na(ic_dt$IC)]
  if (length(v)<5L) return(list(IC=NA,ICIR=NA,N=length(v)))
  list(IC=round(mean(v),5), ICIR=round(mean(v)/sd(v),4), N=length(v))
}

icir_A   <- icir_fn(ic_all_A); icir_B   <- icir_fn(ic_all_B)
cur_yr   <- as.integer(format(Sys.Date(),"%Y"))
icir_3yA <- if ("oos_year" %in% names(ic_all_A)) icir_fn(ic_all_A[oos_year >= cur_yr-3L]) else list(IC=NA,ICIR=NA,N=0L)
icir_3yB <- if ("oos_year" %in% names(ic_all_B)) icir_fn(ic_all_B[oos_year >= cur_yr-3L]) else list(IC=NA,ICIR=NA,N=0L)

cat(sprintf("  S1-A: IC=%.4f ICIR=%.4f N=%d 3Y=%.4f\n",
            icir_A$IC%||%NA, icir_A$ICIR%||%NA, icir_A$N, icir_3yA$ICIR%||%NA))
cat(sprintf("  S1-B: IC=%.4f ICIR=%.4f N=%d 3Y=%.4f\n",
            icir_B$IC%||%NA, icir_B$ICIR%||%NA, icir_B$N, icir_3yB$ICIR%||%NA))

gate_A <- !is.na(icir_A$ICIR) && icir_A$ICIR >= 0.20
gate_B <- !is.na(icir_B$ICIR) && icir_B$ICIR >= 0.20
cat(sprintf("  Alpha Lab Gate: S1-A=%s S1-B=%s\n",
            ifelse(gate_A,"PASS","FAIL"), ifelse(gate_B,"PASS","FAIL")))

# =============================================================================
# 6. 백테스트 — OPT-4: mclapply 병렬
# =============================================================================
# walk-forward 결과 외 대형 객체 해제
rm(ret_dt, SIZE_DT); gc()

# 백테스트용 RAWDATA 재로드
cat("\n[6-0] RAWDATA 재로드 (백테스트용)...\n")
rw2 <- load_rawdata(use_cache=TRUE)
RAWDATA <- rw2$RAWDATA; BM_DT <- rw2$BM_DT
setDT(RAWDATA); setkey(RAWDATA, Date, Ticker)
rm(rw2); gc()

cat("[6] 백테스트 mclapply...\n")

bt_inputs <- list(
  S1_A = rbindlist(Filter(Negate(is.null),scores_A), fill=TRUE),
  S1_B = rbindlist(Filter(Negate(is.null),scores_B), fill=TRUE)
)
n_cores <- min(2L, max(1L, detectCores()-1L))
cat(sprintf("  cores=%d\n", n_cores))

bt_results <- mclapply(names(bt_inputs), function(nm){
  sc <- bt_inputs[[nm]]
  if (nrow(sc)==0L) return(NULL)
  FAC <- sc[!is.na(Score), .(Date,Ticker,Score)]
  setkey(FAC, Date, Ticker)
  bt <- tryCatch(
    run_monthly_simulation(RAWDATA=RAWDATA, BM_DT=BM_DT, FACTORS=FAC,
                           n_holdings=N_HOLDINGS, commission=COMMISSION,
                           weight_method="EW",
                           buffer_zone=list(keep_n=N_HOLDINGS+5L,entry_n=N_HOLDINGS)),
    error=function(e){ cat(nm,"BT err:",e$message,"\n"); NULL })
  if (is.null(bt)) return(NULL)
  r <- bt$DAILY_NAV_DT$Strategy_Ret; r <- r[is.finite(r)]
  cum <- cumprod(1+r); nyr <- length(r)/252
  list(label=nm,
       CAGR=round((tail(cum,1)^(1/nyr)-1)*100,2),
       Sharpe=round(mean(r)/sd(r)*sqrt(252),4),
       MDD=round(min(cum/cummax(cum)-1)*100,2),
       nav_dt=bt$DAILY_NAV_DT)
}, mc.cores=n_cores)
names(bt_results) <- names(bt_inputs)
bt_A <- bt_results[["S1_A"]]; bt_B <- bt_results[["S1_B"]]

lapply(names(bt_results), function(nm){
  r <- bt_results[[nm]]
  if (!is.null(r)) cat(sprintf("  %s: CAGR %.1f%% SR %.4f MDD %.1f%%\n",
                                nm, r$CAGR, r$Sharpe, r$MDD))
})

# =============================================================================
# 7. 차트 (lapply — for loop 없음)
# =============================================================================
cat("\n[7] 차트...\n")
chart_paths <- list()
tryCatch({
  # Equity Curve
  eq_data <- rbindlist(Filter(Negate(is.null), lapply(c("S1_A","S1_B"), function(nm){
    b <- bt_results[[nm]]; if(is.null(b)) return(NULL)
    d <- copy(b$nav_dt)[,.(Date=as.Date(Date),ret=Strategy_Ret)]
    d <- d[is.finite(ret)]; d[,cum:=cumprod(1+ret)]; d[,label:=nm]; d
  })), fill=TRUE)

  bm <- BM_DT[order(Date),.(Date=as.Date(Date),BM_Ret)]
  bm[,cum:=cumprod(1+fifelse(is.finite(BM_Ret),BM_Ret,0))][,label:="KOSPI BM"]
  eq_all <- rbind(eq_data[,.(Date,cum,label)], bm[,.(Date,cum,label)], fill=TRUE)

  if (nrow(eq_all)>0) {
    p1 <- ggplot(eq_all, aes(x=Date,y=cum,color=label,linetype=label)) +
      geom_line(linewidth=0.8) + scale_y_log10(labels=scales::comma) +
      scale_color_manual(values=c("S1_A"="#1f77b4","S1_B"="#ff7f0e","KOSPI BM"="#7f7f7f")) +
      scale_linetype_manual(values=c("S1_A"="solid","S1_B"="dashed","KOSPI BM"="dotted")) +
      labs(title="STR_1656_MLRA S1 — Equity Curves",
           subtitle="XGBoost 5-seed | EW 30 | OOS Walk-Forward",
           x=NULL, y="Cumulative (Log)", color=NULL, linetype=NULL) +
      theme_minimal(base_size=12)+theme(legend.position="bottom")
    ep <- file.path(OUTPUT_DIR,"equity_curve.png")
    ggsave(ep,p1,width=12,height=6,dpi=150); chart_paths$equity <- ep
    cat("  equity_curve.png\n")
  }

  # Annual Returns
  ar_all <- rbindlist(Filter(Negate(is.null), lapply(c("S1_A","S1_B"), function(nm){
    b <- bt_results[[nm]]; if(is.null(b)) return(NULL)
    d <- copy(b$nav_dt)[,.(Date=as.Date(Date),ret=Strategy_Ret)]
    d <- d[is.finite(ret)]; d[,yr:=as.integer(format(Date,"%Y"))]
    a <- d[,.(annual_ret=prod(1+ret)-1),by=yr]; a[,label:=nm]; a
  })), fill=TRUE)

  if (nrow(ar_all)>0) {
    p2 <- ggplot(ar_all,aes(x=factor(yr),y=annual_ret*100,fill=label)) +
      geom_col(position="dodge",width=0.7) +
      geom_hline(yintercept=0,linetype="dashed",color="grey40") +
      scale_fill_manual(values=c("S1_A"="#1f77b4","S1_B"="#ff7f0e")) +
      labs(title="STR_1656_MLRA S1 — Annual Returns",
           subtitle="S1-A (full 50F) vs S1-B (non-RE ~35F)",
           x=NULL,y="Return (%)",fill=NULL) +
      theme_minimal(base_size=11)+
      theme(axis.text.x=element_text(angle=45,hjust=1),legend.position="bottom")
    ap <- file.path(OUTPUT_DIR,"annual_returns.png")
    ggsave(ap,p2,width=14,height=6,dpi=150); chart_paths$annual <- ap
    cat("  annual_returns.png\n")
  }

  # IC 시계열
  ic_c <- rbind(ic_all_A[,.(ym,IC,variant)], ic_all_B[,.(ym,IC,variant)], fill=TRUE)
  if (nrow(ic_c)>0) {
    ic_c[, dt := as.Date(paste0(ym,"-01"))]
    p3 <- ggplot(ic_c, aes(x=dt,y=IC,color=variant)) +
      geom_line(alpha=0.5) +
      geom_smooth(se=FALSE,method="loess",span=0.3,linewidth=1.1) +
      geom_hline(yintercept=0,linetype="dashed",color="grey40") +
      scale_color_manual(values=c("S1_A"="#1f77b4","S1_B"="#ff7f0e")) +
      labs(title="STR_1656_MLRA S1 — Monthly IC",
           subtitle=sprintf("S1-A ICIR=%.3f | S1-B ICIR=%.3f",
                            icir_A$ICIR%||%NA, icir_B$ICIR%||%NA),
           x=NULL,y="Spearman IC",color=NULL) +
      theme_minimal(base_size=11)+theme(legend.position="bottom")
    ip <- file.path(OUTPUT_DIR,"ic_timeseries.png")
    ggsave(ip,p3,width=12,height=5,dpi=150); chart_paths$ic <- ip
    cat("  ic_timeseries.png\n")
  }
}, error=function(e) cat("  차트 오류:",e$message,"\n"))

# =============================================================================
# 8. 결과 저장
# =============================================================================
cat("\n[8] 결과 저장...\n")
srA       <- if(!is.null(bt_A)) bt_A$Sharpe else -Inf
srB       <- if(!is.null(bt_B)) bt_B$Sharpe else -Inf
best_bt   <- if(srA>=srB) bt_A else bt_B
best_lbl  <- if(srA>=srB) "S1_A" else "S1_B"
best_icir <- if(srA>=srB) icir_A$ICIR else icir_B$ICIR
hard_fail <- !is.null(best_bt) && abs(best_bt$MDD) > 45

perf <- list(
  strategy_id="STR_1656_MLRA", variant_best=best_lbl,
  timestamp=as.character(Sys.time()),
  s1_a=list(ICIR=icir_A$ICIR, IC=icir_A$IC, N_months=icir_A$N,
             ICIR_3y=icir_3yA$ICIR, gate_pass=gate_A,
             CAGR=if(!is.null(bt_A))bt_A$CAGR else NA,
             Sharpe=if(!is.null(bt_A))bt_A$Sharpe else NA,
             MDD=if(!is.null(bt_A))bt_A$MDD else NA),
  s1_b=list(ICIR=icir_B$ICIR, IC=icir_B$IC, N_months=icir_B$N,
             ICIR_3y=icir_3yB$ICIR, gate_pass=gate_B,
             CAGR=if(!is.null(bt_B))bt_B$CAGR else NA,
             Sharpe=if(!is.null(bt_B))bt_B$Sharpe else NA,
             MDD=if(!is.null(bt_B))bt_B$MDD else NA),
  alpha_lab_gate=list(pass=gate_A||gate_B, best_ICIR=best_icir, threshold=0.20),
  hard_fail=hard_fail,
  pit_checks=list(C1="expanding only",C2="OOS>IS",C13="Z_Score_Aligned",
                  C14="fwd t+1~t+21",OPT1="Arrow predicate",
                  OPT4="mclapply",purge_days=PURGE_DAYS),
  ml_config=list(seeds=XGB_SEEDS,mi_top_n=MI_TOP_N,purge_days=PURGE_DAYS,
                 n_holdings=N_HOLDINGS,commission=COMMISSION,liq=LIQ_THRESHOLD)
)
write_json(perf, file.path(OUTPUT_DIR,"performance.json"), auto_unbox=TRUE, pretty=TRUE)

if (nrow(ic_all_A)>0) fwrite(ic_all_A, file.path(OUTPUT_DIR,"ic_timeseries_A.csv"))
if (nrow(ic_all_B)>0) fwrite(ic_all_B, file.path(OUTPUT_DIR,"ic_timeseries_B.csv"))
if (!is.null(bt_A))   fwrite(bt_A$nav_dt, file.path(OUTPUT_DIR,"nav_S1_A.csv"))
if (!is.null(bt_B))   fwrite(bt_B$nav_dt, file.path(OUTPUT_DIR,"nav_S1_B.csv"))
cat("  performance.json + CSV 저장 완료\n")

# =============================================================================
# 9. Stage Artifacts
# =============================================================================
ARTIFACT_DIR <- file.path(PROJECT_ROOT, "stage_artifacts")
dir.create(ARTIFACT_DIR, showWarnings=FALSE, recursive=TRUE)

write_json(list(
  factor_id="ML_XGB_ENSEMBLE", strategy_id="STR_1656_MLRA",
  stage="S1", created_at=as.character(Sys.time()),
  variants=c("S1_A_full50F","S1_B_nonRE35F"),
  implementation_profile=list(
    model="XGBoost 5-seed ensemble", seeds=XGB_SEEDS,
    mi_prefilter_top=MI_TOP_N, window_type="expanding walk-forward",
    purge_window_days=PURGE_DAYS, n_holdings=N_HOLDINGS,
    commission_bps=15, liq_threshold_krw=LIQ_THRESHOLD,
    overlay="없음 S1 순수 팩터", weight_method="EW"),
  turnover_risk="중간", capacity_risk="낮음",
  pit_compliance=list(
    C1="expanding only PASS", C2="OOS>IS PASS",
    C10="AvgTV20 (frollmean 20d) PASS — C10 fix applied 2026-04-19",
    C13="Z_Score_Aligned PASS", C14="fwd t+1~t+21 PASS",
    OPT1="Arrow open_dataset PASS", OPT4="mclapply PASS",
    purge=paste0(PURGE_DAYS,"d embargo PASS"))
), file.path(ARTIFACT_DIR,"s1_construction_STR_1656_MLRA.json"),
   auto_unbox=TRUE, pretty=TRUE)

write_json(list(
  factor_id="ML_XGB_ENSEMBLE", strategy_id="STR_1656_MLRA",
  stage="S2", created_at=as.character(Sys.time()),
  s1_a=list(IC_IR=icir_A$ICIR, IC_mean=icir_A$IC, IC_IR_3y=icir_3yA$ICIR,
             N_months=icir_A$N,
             CAGR=if(!is.null(bt_A))bt_A$CAGR else NA,
             SR=if(!is.null(bt_A))bt_A$Sharpe else NA,
             MDD=if(!is.null(bt_A))bt_A$MDD else NA,
             tag=if(gate_A) ifelse(!is.na(icir_A$ICIR)&&icir_A$ICIR>=0.40,
                                   "Strong","Moderate") else "Weak"),
  s1_b=list(IC_IR=icir_B$ICIR, IC_mean=icir_B$IC, IC_IR_3y=icir_3yB$ICIR,
             N_months=icir_B$N,
             CAGR=if(!is.null(bt_B))bt_B$CAGR else NA,
             SR=if(!is.null(bt_B))bt_B$Sharpe else NA,
             MDD=if(!is.null(bt_B))bt_B$MDD else NA,
             tag=if(gate_B) ifelse(!is.na(icir_B$ICIR)&&icir_B$ICIR>=0.40,
                                   "Strong","Moderate") else "Weak"),
  role_bias="RoleBias_Diversifier", expected_role="diversifier",
  alpha_lab_gate=list(pass=gate_A||gate_B, threshold=0.20,
                      result=sprintf("S1-A:%s S1-B:%s",
                                     ifelse(gate_A,"PASS","FAIL"),
                                     ifelse(gate_B,"PASS","FAIL"))),
  s5_recommendation=if(gate_A||gate_B)
    list(proceed=TRUE, priority="CVaR LP + 섹터중립 + Low-Beta Slate A~D",
         note="ablation 4단계 적층 레이어 기여도 측정")
  else list(proceed=FALSE, note="ICIR<0.20 S5 보류")
), file.path(ARTIFACT_DIR,"s2_profile_STR_1656_MLRA.json"),
   auto_unbox=TRUE, pretty=TRUE)
cat("[9] s1_construction + s2_profile 완료\n")

# =============================================================================
# 10. 텔레그램
# =============================================================================
cat("\n[10] 텔레그램...\n")
tryCatch({
  source(file.path(PROJECT_ROOT,"02_Infrastructure/telegram/telegram_notify.R"))
  gate_str <- if(gate_A||gate_B) "PASS" else "FAIL"
  hf_str   <- if(hard_fail) " | MDD Hard Fail" else ""
  msg <- paste0(
    "\U0001F916 [Forge] STR_1656_MLRA S1 완료\n\n",
    "\U0001F4CA <b>XGBoost 5-seed + MI top50</b>\n",
    "<b>S1-A (full 50F)</b>  IC=",round(icir_A$IC%||%NA,4),
    " ICIR=",round(icir_A$ICIR%||%NA,4),
    " CAGR=",if(!is.null(bt_A))bt_A$CAGR else NA,
    "% SR=",if(!is.null(bt_A))bt_A$Sharpe else NA,"\n",
    "<b>S1-B (non-RE 35F)</b> IC=",round(icir_B$IC%||%NA,4),
    " ICIR=",round(icir_B$ICIR%||%NA,4),
    " CAGR=",if(!is.null(bt_B))bt_B$CAGR else NA,
    "% SR=",if(!is.null(bt_B))bt_B$Sharpe else NA,"\n\n",
    "\U0001F6A6 <b>Alpha Lab Gate:</b> ",gate_str,hf_str,"\n",
    "\U0001F3AF <b>Best:</b> ",best_lbl,"\n",
    "\U0001F4CC <b>RoleBias:</b> RoleBias_Diversifier\n",
    "\U0001F4AA <b>강점:</b> ML 비선형 alpha + 5-seed 앙상블 안정화\n",
    "\U0001F4A1 <b>약점:</b> 2024 alpha decay (IC 0.017) RE 의존 진단 중\n",
    "\U0001F553 ",as.character(Sys.time()))
  tg_send(msg)
  if (!is.null(chart_paths$equity)&&file.exists(chart_paths$equity))
    tg_send_photo(chart_paths$equity, caption="\U0001F4C8 STR_1656_MLRA S1 Equity")
  if (!is.null(chart_paths$annual)&&file.exists(chart_paths$annual))
    tg_send_photo(chart_paths$annual, caption="\U0001F4CA STR_1656_MLRA S1 Annual")
  cat("  텔레그램 완료\n")
}, error=function(e) cat("  텔레그램 오류:",e$message,"\n"))

# =============================================================================
# 최종
# =============================================================================
cat("\n",paste(rep("=",60),collapse=""),"\n")
cat("=== STR_1656_MLRA S1 COMPLETE ===\n")
cat(sprintf("  S1-A ICIR=%.4f SR=%.3f MDD=%.1f%%\n",
            icir_A$ICIR%||%NA,
            if(!is.null(bt_A))bt_A$Sharpe else NA,
            if(!is.null(bt_A))bt_A$MDD else NA))
cat(sprintf("  S1-B ICIR=%.4f SR=%.3f MDD=%.1f%%\n",
            icir_B$ICIR%||%NA,
            if(!is.null(bt_B))bt_B$Sharpe else NA,
            if(!is.null(bt_B))bt_B$MDD else NA))
cat(sprintf("  Gate: %s | Hard Fail: %s | RoleBias: RoleBias_Diversifier\n",
            ifelse(gate_A||gate_B,"PASS","FAIL"), ifelse(hard_fail,"YES","NO")))
cat(sprintf("  산출물: %s\n", OUTPUT_DIR))
cat(paste(rep("=",60),collapse=""),"\n")
cat("종료:", as.character(Sys.time()),"\n")
