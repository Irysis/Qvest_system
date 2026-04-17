cat("=== Meta-Learning Phase 1: IC Matrix ===\n")
cat("목적: 288 팩터 × 월별 Spearman IC 매트릭스 구축\n")
cat("생성일:", as.character(Sys.time()), "\n\n")

# ─── PIT 주석 (필수) ──────────────────────────────────────────────────────────
# [PIT 설계 문서]
#
# 이 스크립트는 각 월 말 t에서 Spearman IC(t,f)를 계산합니다:
#   IC(t,f) = cor(Z_Score[f at t], fwd_ret_21d[t+1 ~ t+21], method="spearman")
#
# [C1 — Full-sample 통계 금지]
#   IC는 rolling 방식: 각 월 독립적으로 당월 데이터만 사용.
#   전체 기간 통합 통계량 사용 없음.
#
# [C14 — IC 접근 시 Usable_Date 기준]
#   IC(t,f)의 Z_Score는 t(월말) 시점에 이미 알 수 있는 값.
#   fwd_ret는 t+1 거래일부터 t+21 거래일까지의 미래 수익률.
#   이 IC 행렬 자체는 "평가 메트릭"이며 직접 거래 신호가 아님.
#   Meta-Learning 모델이 IC를 feature로 사용할 때,
#   Usable_Date(t+21 이후) 이전 IC는 반드시 접근 불가 처리 필수.
#   즉, 이 행렬 자체는 미래참조 아님. 사용 단계에서 C14 준수 책임.
#
# [C2 — Same-day Circular 금지]
#   fwd_ret 시작: t+1 거래일 가격 (당일 t의 Close 대비)
#   따라서 당일 신호 → 다음 날 수익률 → circular 없음.
#
# [C13 — Z_Score_Aligned 대신 Z_Score 사용 이유]
#   IC 행렬은 방향 정렬 없이 원 Z_Score를 사용.
#   Direction은 IC 부호로 이미 반영됨 (양수 = 높을수록 수익 좋음).
#   알고리즘: Z_Score ↔ fwd_ret 상관. 부호 자체가 정보.
#   C13은 "수동 방향 반전 금지"이므로 Z_Score 사용은 적법.
#
# [C15 — Factor DB 접근]
#   개별 read_parquet 루프 금지. Arrow open_dataset 일괄 로드.
#   단, 연도 구간별 배치로 RAM 관리.
#
# ─────────────────────────────────────────────────────────────────────────────

# ─── 라이브러리 ──────────────────────────────────────────────────────────────
suppressPackageStartupMessages({
  library(arrow)
  library(dplyr)
  library(data.table)
  library(jsonlite)
})

# ─── 환경 설정 ───────────────────────────────────────────────────────────────
# config.R 경유로 PROJECT_ROOT 설정 (normalizePath 사용 금지 — WSL 한글 경로 버그)
PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
source(file.path(PROJECT_ROOT, "02_Infrastructure", "config.R"))

# ─── 경로 ────────────────────────────────────────────────────────────────────
FACTOR_DB_DIR <- file.path(PROJECT_ROOT, ".cache", "factor_db")
CACHE_DIR     <- file.path(PROJECT_ROOT, ".cache")
RAWDATA_PATH  <- file.path(CACHE_DIR, "RAWDATA.parquet")

OUT_MATRIX <- file.path(CACHE_DIR, "ic_matrix_expanding.parquet")
OUT_META   <- file.path(CACHE_DIR, "ic_matrix_meta.json")

# ─── 파라미터 ────────────────────────────────────────────────────────────────
DATE_START     <- as.Date("2005-01-01")
DATE_END       <- as.Date("2025-12-31")
FWD_DAYS       <- 21L          # 21 거래일 선행 수익률
MIN_STOCKS     <- 30L          # IC 계산 최소 주식수
BATCH_YEARS    <- 3L           # 연도별 배치 크기 (RAM 관리)
PROGRESS_STEP  <- 20L          # 진행 보고 주기

cat(sprintf("[설정] 기간: %s ~ %s | fwd_days=%d | min_stocks=%d\n",
            DATE_START, DATE_END, FWD_DAYS, MIN_STOCKS))

# ─── 1. RAWDATA 1회 로드 ─────────────────────────────────────────────────────
# OPT-1 준수: load_rawdata(use_cache=TRUE)로 1회만 로드
cat("\n[Step 1] RAWDATA 로딩...\n")
t_rd_start <- proc.time()

source(file.path(PROJECT_ROOT, "02_Infrastructure", "backtest_harness.R"))
raw_res <- load_rawdata(use_cache = TRUE)
RAWDATA  <- raw_res$RAWDATA
setkey(RAWDATA, Date, Ticker)
rm(raw_res)

# 일간 날짜 배열 (fwd_ret 계산용)
ALL_DATES <- sort(unique(RAWDATA$Date))
cat(sprintf("[Step 1] 완료: %d rows, %d 거래일 (%.1f초)\n",
            nrow(RAWDATA), length(ALL_DATES), (proc.time()-t_rd_start)[3]))

gc()

# ─── 2. 월말 날짜 목록 생성 ──────────────────────────────────────────────────
# Factor DB의 월말 날짜를 기준으로 (각 parquet 파일의 Date)
cat("\n[Step 2] Factor DB 월말 날짜 탐색...\n")

fdb_files_all <- list.files(
  FACTOR_DB_DIR,
  pattern = "^factor_db_\\d{6}\\.parquet$",
  full.names = FALSE
)

# 파일명에서 날짜 추출: factor_db_YYYYMM.parquet
fdb_ym <- gsub("factor_db_(\\d{4})(\\d{2})\\.parquet", "\\1-\\2", fdb_files_all)
fdb_dates <- as.Date(paste0(fdb_ym, "-01"))

# 필터: DATE_START ~ DATE_END 이내 파일만
# fwd_ret(t+21)이 RAWDATA 마지막 날짜보다 충분히 앞이어야 함
last_valid_t <- ALL_DATES[length(ALL_DATES) - FWD_DAYS - 5L]  # 5일 여유
keep_mask <- fdb_dates >= DATE_START & fdb_dates <= DATE_END & fdb_dates <= last_valid_t
target_yms <- fdb_ym[keep_mask]
target_files_full <- file.path(FACTOR_DB_DIR,
                                paste0("factor_db_", gsub("-", "", target_yms), ".parquet"))

cat(sprintf("[Step 2] 대상 월: %d건 (%s ~ %s)\n",
            length(target_yms), target_yms[1], tail(target_yms, 1)))

# ─── 3. 배치 처리: 연도 단위 open_dataset → IC 계산 ─────────────────────────
# OPT-1: 루프 내 read_parquet 금지. 연도 배치로 open_dataset 사용.
cat("\n[Step 3] IC 행렬 계산 시작 (배치 크기: ", BATCH_YEARS, "년)\n", sep="")

# 전체 결과 저장 리스트
all_ic_rows <- vector("list", length(target_yms))
names(all_ic_rows) <- target_yms

# 진행 카운터
n_total   <- length(target_yms)
n_done    <- 0L
n_skip    <- 0L
t_global  <- proc.time()

# 연도별 배치 인덱스 생성
years_seq <- unique(substr(target_yms, 1, 4))
batch_starts <- seq(1, length(years_seq), by = BATCH_YEARS)

for (b_start in batch_starts) {
  b_end   <- min(b_start + BATCH_YEARS - 1L, length(years_seq))
  yr_batch <- years_seq[b_start:b_end]

  # 이 배치에 해당하는 파일 필터
  batch_mask  <- substr(target_yms, 1, 4) %in% yr_batch
  batch_yms   <- target_yms[batch_mask]
  batch_files <- target_files_full[batch_mask]

  if (length(batch_files) == 0L) next

  # ── Arrow open_dataset으로 배치 전체 로드 ──────────────────────────────
  # C15 준수: 루프 내 read_parquet 금지. open_dataset 배치 로드.
  ds <- open_dataset(batch_files, format = "parquet")
  batch_dt <- ds |>
    dplyr::filter(Coverage == TRUE) |>
    dplyr::select(Date, Ticker, Factor_Name, Z_Score) |>
    dplyr::collect() |>
    as.data.table()

  setkey(batch_dt, Date, Ticker)

  # ── 월별 IC 계산 ──────────────────────────────────────────────────────────
  batch_dates_available <- sort(unique(batch_dt$Date))

  for (ym in batch_yms) {
    # 월말 날짜 찾기: Factor DB 내 해당 월 데이터
    ym_prefix <- gsub("-", "", ym)  # "200501"
    ym_date_str <- paste0(ym_prefix, "01")
    ym_date_start <- as.Date(paste0(substr(ym, 1, 4), "-", substr(ym, 6, 7), "-01"))
    ym_date_end   <- as.Date(paste0(
      ifelse(substr(ym, 6, 7) == "12",
             as.numeric(substr(ym, 1, 4)) + 1L,
             substr(ym, 1, 4)),
      "-",
      ifelse(substr(ym, 6, 7) == "12", "01", sprintf("%02d", as.numeric(substr(ym, 6, 7)) + 1L)),
      "-01"
    )) - 1

    # 해당 월의 Factor DB 날짜 (통상 월말)
    t_dates_in_ym <- batch_dates_available[
      batch_dates_available >= ym_date_start & batch_dates_available <= ym_date_end
    ]
    if (length(t_dates_in_ym) == 0L) {
      n_skip <- n_skip + 1L
      next
    }
    t_date <- t_dates_in_ym[length(t_dates_in_ym)]  # 해당 월 마지막 날짜

    # ── Forward return 계산 (C2 준수: t+1 거래일 시작) ──────────────────
    t_idx <- which(ALL_DATES == t_date)
    if (length(t_idx) == 0L || (t_idx + FWD_DAYS) > length(ALL_DATES)) {
      n_skip <- n_skip + 1L
      next
    }
    t_end_date <- ALL_DATES[t_idx + FWD_DAYS]  # t+21 거래일

    # 가격 추출
    p_t   <- RAWDATA[Date == t_date,   .(Ticker, Close_t  = Close)]
    p_t21 <- RAWDATA[Date == t_end_date, .(Ticker, Close_t21 = Close)]

    fwd_dt <- merge(p_t, p_t21, by = "Ticker")
    fwd_dt <- fwd_dt[Close_t > 0 & Close_t21 > 0]  # 가격 유효성 체크
    fwd_dt[, fwd_ret := Close_t21 / Close_t - 1]
    fwd_dt <- fwd_dt[is.finite(fwd_ret)]

    if (nrow(fwd_dt) < MIN_STOCKS) {
      n_skip <- n_skip + 1L
      next
    }

    # ── Factor 데이터 추출 및 merge ─────────────────────────────────────
    fdt_t <- batch_dt[Date == t_date, .(Ticker, Factor_Name, Z_Score)]
    merged_dt <- merge(fdt_t, fwd_dt[, .(Ticker, fwd_ret)], by = "Ticker")
    merged_dt <- merged_dt[is.finite(Z_Score) & is.finite(fwd_ret)]

    if (nrow(merged_dt) == 0L) {
      n_skip <- n_skip + 1L
      next
    }

    # ── 벡터화 IC 계산: 모든 팩터 동시 처리 ─────────────────────────────
    # Spearman IC = cor(Z_Score, fwd_ret, method="spearman")
    # data.table [by=Factor_Name]: 288 팩터 일괄 처리
    ic_dt <- merged_dt[
      !is.na(Z_Score) & !is.na(fwd_ret),
      .(
        IC      = tryCatch(
          cor(Z_Score, fwd_ret, method = "spearman", use = "complete.obs"),
          error  = function(e) NA_real_
        ),
        N_Stocks = .N
      ),
      by = Factor_Name
    ]
    ic_dt <- ic_dt[N_Stocks >= MIN_STOCKS]

    if (nrow(ic_dt) == 0L) {
      n_skip <- n_skip + 1L
      next
    }

    # ── Wide format으로 변환: 1행 = 1월 ──────────────────────────────────
    wide_row <- dcast(ic_dt, . ~ Factor_Name, value.var = "IC")
    wide_row[, . := NULL]  # 더미 열 제거
    wide_row[, Date := t_date]
    wide_row[, N_Factors := nrow(ic_dt)]
    wide_row[, N_Stocks_Median := as.integer(median(ic_dt$N_Stocks, na.rm = TRUE))]

    all_ic_rows[[ym]] <- wide_row

    n_done <- n_done + 1L

    # 진행 보고
    if (n_done %% PROGRESS_STEP == 0L) {
      elapsed <- (proc.time() - t_global)[3]
      pct     <- round(100 * n_done / n_total, 1)
      eta_sec <- round(elapsed / n_done * (n_total - n_done))
      cat(sprintf(
        "[%d/%d | %.1f%%] 최근: %s | IC C19=%.3f | 경과=%.0fs | ETA=%.0fs\n",
        n_done, n_total, pct,
        as.character(t_date),
        ifelse("C19_Composite_Earnings" %in% ic_dt$Factor_Name,
               ic_dt[Factor_Name == "C19_Composite_Earnings", IC], NA),
        elapsed, eta_sec
      ))
    }
  }

  # 배치 후 메모리 해제 (RAM 80% 이하 유지)
  rm(batch_dt, ds)
  gc()
}

cat(sprintf("\n[Step 3] 완료: 처리=%d, 스킵=%d, 총시간=%.1f초\n",
            n_done, n_skip, (proc.time() - t_global)[3]))

# ─── 4. 결과 취합 ────────────────────────────────────────────────────────────
cat("\n[Step 4] 결과 취합...\n")

# NULL 제거 후 rbindlist (팩터 컬럼이 월마다 다를 수 있음 → fill=TRUE)
valid_rows <- Filter(Negate(is.null), all_ic_rows)
cat(sprintf("[Step 4] 유효 월: %d건\n", length(valid_rows)))

if (length(valid_rows) == 0L) {
  stop("[ERROR] IC 행렬 생성 실패: 유효한 월 데이터 없음")
}

ic_matrix <- rbindlist(valid_rows, use.names = TRUE, fill = TRUE)
setorder(ic_matrix, Date)

# Date, N_Factors, N_Stocks_Median 제외한 팩터 컬럼 식별
meta_cols <- c("Date", "N_Factors", "N_Stocks_Median")
factor_cols <- setdiff(names(ic_matrix), meta_cols)

cat(sprintf("[Step 4] 매트릭스: %d행 × %d팩터 컬럼\n",
            nrow(ic_matrix), length(factor_cols)))
cat(sprintf("[Step 4] 날짜 범위: %s ~ %s\n",
            as.character(min(ic_matrix$Date)),
            as.character(max(ic_matrix$Date))))
gc()

# ─── 5. 저장 ─────────────────────────────────────────────────────────────────
cat("\n[Step 5] 저장...\n")

# Parquet 저장
write_parquet(ic_matrix, OUT_MATRIX)
cat(sprintf("[Step 5] Parquet 저장: %s (%.1f MB)\n",
            OUT_MATRIX,
            file.size(OUT_MATRIX) / 1e6))

# 메타데이터 JSON
meta <- list(
  description    = "Monthly Spearman IC matrix for all Factor DB factors",
  pit_note       = "IC values use Z_Score at t and fwd_ret_21d (t+1 to t+21). C14: matrix is evaluation metric, not trading signal. C1: computed per-month independently. C2: fwd_ret starts t+1.",
  date_start     = as.character(min(ic_matrix$Date)),
  date_end       = as.character(max(ic_matrix$Date)),
  n_months       = nrow(ic_matrix),
  n_factors      = length(factor_cols),
  factor_cols    = factor_cols,
  fwd_days       = FWD_DAYS,
  min_stocks     = MIN_STOCKS,
  build_time     = as.character(Sys.time()),
  build_duration_sec = round((proc.time() - t_global)[3], 1)
)
write_json(meta, OUT_META, pretty = TRUE, auto_unbox = TRUE)
cat(sprintf("[Step 5] 메타데이터 저장: %s\n", OUT_META))

# ─── 6. 결과 요약 ────────────────────────────────────────────────────────────
cat("\n════════════════════════════════════════\n")
cat(" Meta-Learning Phase 1 — IC Matrix 완료\n")
cat("════════════════════════════════════════\n")
cat(sprintf(" 매트릭스 차원: %d 월 × %d 팩터\n", nrow(ic_matrix), length(factor_cols)))
cat(sprintf(" 날짜 범위:    %s ~ %s\n",
            as.character(min(ic_matrix$Date)),
            as.character(max(ic_matrix$Date))))

# C19_Composite_Earnings 샘플 IC
if ("C19_Composite_Earnings" %in% names(ic_matrix)) {
  c19_ic <- ic_matrix[, C19_Composite_Earnings]
  c19_ic <- c19_ic[is.finite(c19_ic)]
  cat(sprintf(" C19_Composite_Earnings IC — 평균: %.4f | ICIR: %.3f | 유효월: %d\n",
              mean(c19_ic), mean(c19_ic) / sd(c19_ic), length(c19_ic)))
}

# GR05_ROE_Growth 샘플 IC
if ("GR05_ROE_Growth" %in% names(ic_matrix)) {
  gr05_ic <- ic_matrix[, GR05_ROE_Growth]
  gr05_ic <- gr05_ic[is.finite(gr05_ic)]
  cat(sprintf(" GR05_ROE_Growth IC     — 평균: %.4f | ICIR: %.3f | 유효월: %d\n",
              mean(gr05_ic), mean(gr05_ic) / sd(gr05_ic), length(gr05_ic)))
}

cat(sprintf(" 출력 파일: %s\n", OUT_MATRIX))
cat(sprintf(" 메타 파일: %s\n", OUT_META))
cat("════════════════════════════════════════\n")
