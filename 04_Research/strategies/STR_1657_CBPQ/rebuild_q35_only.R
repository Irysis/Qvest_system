#!/usr/bin/env Rscript
# rebuild_q35_only.R
# Q35_CashBased_OpProf 선택적 재빌드 스크립트
#
# Ball et al. (2016) 공식: (Revenue - COGS - SGA - Accruals) / TotalAssets
# Accruals = NetIncome - OperatingCF
#
# 방식: 기존 parquet 로드 → Q35 행 제거 → 재계산 → 재삽입 → 저장
# 전체 Factor DB 재빌드 없이 Q35만 갱신
#
# PIT 준수: Factor_Date <= sig_date (각 월말 기준)
# C15: compute_quality 모듈 경유 (직접 계산)
# C13: Z_Score_Aligned = cross-sectional z-score (수동 반전 금지)
#
# 실행: Rscript -e 'source("rebuild_q35_only.R")'

cat("=== Q35_CashBased_OpProf 선택적 재빌드 시작 ===\n")
t_total <- Sys.time()

# ---- 경로 설정 ----
PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
INFRA_DIR    <- file.path(PROJECT_ROOT, "02_Infrastructure")
CACHE_DIR    <- file.path(PROJECT_ROOT, ".cache")
FDB_DIR      <- file.path(CACHE_DIR, "factor_db")
FUND_PATH    <- file.path(CACHE_DIR, "fundamental_merged.parquet")

source(file.path(INFRA_DIR, "config.R"))

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
})

# ---- 재무 데이터 로드 (1회) ----
cat("\n[1] 재무 데이터 로드...\n")
if (!file.exists(FUND_PATH)) stop("fundamental_merged.parquet 없음: ", FUND_PATH)
FUND <- as.data.table(read_parquet(FUND_PATH))
cat(sprintf("  FUND: %s rows | 컬럼: %s\n",
            format(nrow(FUND), big.mark = ","),
            paste(names(FUND)[1:min(8, ncol(FUND))], collapse = ", ")))

# Item 컬럼 확인 (long vs wide)
if ("Item" %in% names(FUND)) {
  cat("  FUND 형식: Long (Item 컬럼 있음)\n")
  FUND_FORMAT <- "long"
  # Factor_Date 또는 Date 컬럼 확인
  date_col <- if ("Factor_Date" %in% names(FUND)) "Factor_Date" else "Date"
  FUND[, Factor_Date := as.Date(get(date_col))]
  setkey(FUND, Factor_Date, Ticker, Item)
} else {
  cat("  FUND 형식: Wide (Item 컬럼 없음)\n")
  FUND_FORMAT <- "wide"
  date_col <- if ("Factor_Date" %in% names(FUND)) "Factor_Date" else "Date"
  FUND[, Factor_Date := as.Date(get(date_col))]
  setkey(FUND, Factor_Date, Ticker)
}

# 필요 컬럼 확인
if (FUND_FORMAT == "long") {
  needed_items <- c("Revenue", "COGS", "SGA", "NetIncome", "OperatingCF", "TotalAssets")
  avail_items <- unique(FUND$Item)
  cat(sprintf("  필요 아이템 체크: %s\n",
              paste(sapply(needed_items, function(x)
                sprintf("%s:%s", x, ifelse(x %in% avail_items, "OK", "MISS"))),
                collapse = " | ")))
} else {
  needed_cols <- c("Revenue", "COGS", "SGA", "NetIncome", "OperatingCF", "TotalAssets")
  avail_cols  <- names(FUND)
  cat(sprintf("  필요 컬럼 체크: %s\n",
              paste(sapply(needed_cols, function(x)
                sprintf("%s:%s", x, ifelse(x %in% avail_cols, "OK", "MISS"))),
                collapse = " | ")))
}

# ---- parquet 파일 목록 ----
cat("\n[2] Factor DB parquet 파일 목록 확인...\n")
pq_files <- list.files(FDB_DIR, pattern = "^factor_db_\\d{6}\\.parquet$", full.names = TRUE)
pq_files <- sort(pq_files)
cat(sprintf("  총 %d개 파일 (%s ~ %s)\n",
            length(pq_files),
            basename(pq_files[1]),
            basename(tail(pq_files, 1))))

if (length(pq_files) == 0) stop("factor_db parquet 파일 없음")

# ---- Q35 재계산 함수 ----
# Ball et al. (2016): CashBasedOpProf = (Revenue - COGS - SGA - Accruals) / TotalAssets
# Accruals = NetIncome - OperatingCF
compute_q35_for_date <- function(sig_d, FUND, FUND_FORMAT) {
  sig_d <- as.Date(sig_d)

  # PIT: Factor_Date <= sig_d
  if (FUND_FORMAT == "long") {
    fund_pit <- FUND[Factor_Date <= sig_d]
    if (nrow(fund_pit) == 0) return(NULL)

    # 종목별 최신 데이터만
    setorder(fund_pit, Ticker, Item, Factor_Date)
    fund_latest <- fund_pit[, .SD[.N], by = .(Ticker, Item)]

    # TTM_Value 우선
    if ("TTM_Value" %in% names(fund_latest)) {
      fund_latest[, use_val := fifelse(!is.na(TTM_Value), TTM_Value, Value)]
    } else {
      fund_latest[, use_val := Value]
    }

    # Wide pivot
    needed <- c("Revenue", "COGS", "SGA", "NetIncome", "OperatingCF", "TotalAssets")
    fund_sub <- fund_latest[Item %in% needed]
    if (nrow(fund_sub) == 0) return(NULL)
    fund_wide <- dcast(fund_sub, Ticker ~ Item, value.var = "use_val")

    # 컬럼명 표준화 (alias 처리) — FUND Item명 → 코드 기대 명칭
    alias_map <- c(
      SGAExpense     = "SGA",
      OperatingProfit = "OperatingIncome"
    )
    for (from_nm in names(alias_map)) {
      to_nm <- alias_map[[from_nm]]
      if (from_nm %in% names(fund_wide) && !to_nm %in% names(fund_wide)) {
        setnames(fund_wide, from_nm, to_nm)
      }
    }
  } else {
    # Wide 형식
    fund_pit <- FUND[Factor_Date <= sig_d]
    if (nrow(fund_pit) == 0) return(NULL)
    setorder(fund_pit, Ticker, Factor_Date)
    fund_wide <- fund_pit[, .SD[.N], by = Ticker]
  }

  # 필수 컬럼 확인
  req_cols <- c("Revenue", "NetIncome", "OperatingCF", "TotalAssets")
  if (!all(req_cols %in% names(fund_wide))) return(NULL)

  # Q35 계산
  q35 <- fund_wide[!is.na(Revenue) & !is.na(NetIncome) & !is.na(OperatingCF) &
                   !is.na(TotalAssets) & TotalAssets > 0]
  if (nrow(q35) == 0) return(NULL)

  q35[, accrual := NetIncome - OperatingCF]
  cogs_v <- if ("COGS" %in% names(q35)) q35$COGS else rep(0, nrow(q35))
  sga_v  <- if ("SGA"  %in% names(q35)) q35$SGA  else rep(0, nrow(q35))

  q35[, cbop := (Revenue
                 - fifelse(!is.na(cogs_v), cogs_v, 0)
                 - fifelse(!is.na(sga_v),  sga_v,  0)
                 - accrual) / TotalAssets]
  q35 <- q35[!is.na(cbop) & is.finite(cbop)]
  if (nrow(q35) == 0) return(NULL)

  q35[, .(Ticker, Factor_Name = "Q35_CashBased_OpProf", Raw_Value = cbop)]
}

# ---- Cross-sectional Z-score 함수 (C13: Z_Score_Aligned, 수동 반전 금지) ----
compute_zscore_cs <- function(dt) {
  dt2 <- copy(dt)
  dt2[, Z_Score := {
    vals <- Raw_Value
    mu <- mean(vals, na.rm = TRUE)
    s  <- sd(vals, na.rm = TRUE)
    if (is.na(s) || s < 1e-12) rep(NA_real_, .N)
    else pmin(pmax((vals - mu) / s, -3), 3)
  }, by = Factor_Name]
  # Z_Score_Aligned = Z_Score (registry 방향에 따라 부호 결정 — factor_db_connector에서 처리)
  # 여기서는 Raw_Value 기준 Z_Score만 계산, Z_Score_Aligned는 기존 값 유지 방향으로
  dt2
}

# ---- Q09 vs Q35 상관 확인용 함수 ----
check_q35_q09_corr <- function(pq_files, n_months = 60L) {
  # Z_Score 기준 (parquet 스키마: Z_Score_Aligned는 connector 런타임 계산)
  recent_files <- tail(pq_files, n_months)
  pair_list <- lapply(recent_files, function(f) {
    tryCatch({
      dt <- as.data.table(read_parquet(f))
      dt_sub <- dt[Factor_Name %in% c("Q35_CashBased_OpProf", "Q09_CFOA") &
                   !is.na(Z_Score),
                   .(Date, Ticker, Factor_Name, Z_Score)]
      dt_sub
    }, error = function(e) NULL)
  })
  pair_dt <- rbindlist(pair_list[!sapply(pair_list, is.null)])
  if (nrow(pair_dt) == 0) return(list(rho = NA_real_, n = 0L))

  wide <- dcast(pair_dt, Date + Ticker ~ Factor_Name, value.var = "Z_Score")
  valid <- !is.na(wide$Q35_CashBased_OpProf) & !is.na(wide$Q09_CFOA)
  if (sum(valid) < 50L) return(list(rho = NA_real_, n = sum(valid)))

  rho <- cor(wide$Q35_CashBased_OpProf[valid], wide$Q09_CFOA[valid], method = "spearman")
  list(rho = rho, n = sum(valid))
}

# ---- Step 1: 재빌드 전 Q35-Q09 상관 확인 ----
cat("\n[3] 재빌드 전 Q35-Q09 상관 확인 (최근 60개월)...\n")
before_corr <- tryCatch(check_q35_q09_corr(pq_files, 60L),
                        error = function(e) { cat("  오류:", e$message, "\n"); list(rho = NA_real_, n = 0L) })
cat(sprintf("  [BEFORE] Q35-Q09 Spearman rho = %.4f (n=%d)\n",
            ifelse(is.na(before_corr$rho), 0, before_corr$rho),
            before_corr$n))

# ---- Step 2: Q35 선택적 재계산 ----
cat("\n[4] Q35 선택적 재계산 중 (", length(pq_files), "개월)...\n")

n_updated  <- 0L
n_skipped  <- 0L
n_q35_rows <- 0L

for (i in seq_along(pq_files)) {
  f <- pq_files[i]
  ym <- sub("factor_db_(\\d{6})\\.parquet", "\\1", basename(f))
  sig_d <- as.Date(paste0(substr(ym, 1, 4), "-", substr(ym, 5, 6), "-01"))
  # 월말 날짜로 조정
  sig_d <- as.Date(format(sig_d + 31, "%Y-%m-01")) - 1

  # 기존 parquet 로드
  existing <- tryCatch(as.data.table(read_parquet(f)), error = function(e) NULL)
  if (is.null(existing)) { n_skipped <- n_skipped + 1L; next }

  # Q35 재계산
  q35_new <- tryCatch(
    compute_q35_for_date(sig_d, FUND, FUND_FORMAT),
    error = function(e) { cat(sprintf("  [WARN %s] %s\n", ym, e$message)); NULL }
  )

  if (is.null(q35_new) || nrow(q35_new) == 0) {
    n_skipped <- n_skipped + 1L
    if (i %% 50 == 0) cat(sprintf("  [%s] Q35 데이터 없음 — 건너뜀\n", ym))
    next
  }

  # 기존 Q35 행 제거
  existing_noq35 <- existing[Factor_Name != "Q35_CashBased_OpProf"]

  # Z_Score 계산 (cross-sectional)
  q35_new[, Date := as.Date(existing$Date[1])]

  # 기존 스키마 컬럼 목록 (Z_Score_Aligned는 parquet에 없음)
  schema_cols <- names(existing)

  # Z-score 계산 (C13 준수: Raw_Value 기준 cross-sectional)
  q35_new[, Z_Score := {
    vals <- Raw_Value
    mu <- mean(vals, na.rm = TRUE)
    s  <- sd(vals, na.rm = TRUE)
    if (is.na(s) || s < 1e-12) rep(NA_real_, .N)
    else pmin(pmax((vals - mu) / s, -3), 3)
  }]

  # Rank_Pct
  q35_new[, Rank_Pct := {
    vals <- Raw_Value
    r <- frank(vals, ties.method = "average", na.last = "keep")
    n_valid <- sum(!is.na(vals))
    if (n_valid > 1) (r - 1) / (n_valid - 1) else rep(NA_real_, .N)
  }]
  q35_new[, Coverage := !is.na(Raw_Value)]

  # Z_Sector (전체 평균으로 대체 — 섹터 정보 없으므로)
  q35_new[, Z_Sector := Z_Score]

  # 컬럼 정렬 (Z_Score_Aligned는 parquet에 저장 안 됨 — connector에서 런타임 계산)
  # 스키마: Date, Ticker, Factor_Name, Raw_Value, Z_Score, Z_Sector, Rank_Pct, Coverage
  extra_cols <- setdiff(schema_cols, names(q35_new))
  for (ec in extra_cols) q35_new[, (ec) := NA]
  setcolorder(q35_new, schema_cols)

  # 합치기
  combined <- rbind(existing_noq35, q35_new, fill = TRUE)
  combined[, Date := as.Date(Date)]

  # 저장
  tryCatch({
    write_parquet(combined, f)
    n_updated  <- n_updated + 1L
    n_q35_rows <- n_q35_rows + nrow(q35_new)
  }, error = function(e) {
    cat(sprintf("  [ERROR 저장 %s] %s\n", ym, e$message))
    n_skipped <<- n_skipped + 1L
  })

  if (i %% 60 == 0 || i == length(pq_files)) {
    cat(sprintf("  진행: %d/%d (갱신=%d, 건너뜀=%d)\n",
                i, length(pq_files), n_updated, n_skipped))
  }
}

cat(sprintf("\n[4] 완료: 갱신=%d개월, 건너뜀=%d개월, Q35 행 추가=%s\n",
            n_updated, n_skipped, format(n_q35_rows, big.mark = ",")))

# ---- Step 3: 재빌드 후 Q35-Q09 상관 확인 ----
cat("\n[5] 재빌드 후 Q35-Q09 상관 확인 (최근 60개월)...\n")
after_corr <- tryCatch(check_q35_q09_corr(pq_files, 60L),
                       error = function(e) { cat("  오류:", e$message, "\n"); list(rho = NA_real_, n = 0L) })
cat(sprintf("  [AFTER]  Q35-Q09 Spearman rho = %.4f (n=%d)\n",
            ifelse(is.na(after_corr$rho), 0, after_corr$rho),
            after_corr$n))

# ---- 상관 변화 보고 ----
cat("\n=== Q35 재빌드 결과 요약 ===\n")
cat(sprintf("  Before rho = %.4f\n", ifelse(is.na(before_corr$rho), NA, before_corr$rho)))
cat(sprintf("  After  rho = %.4f\n", ifelse(is.na(after_corr$rho), NA, after_corr$rho)))
if (!is.na(after_corr$rho)) {
  if (after_corr$rho < 0.70) {
    cat("  [COND_01] PASS: rho < 0.70 — Q35/Q09 독립성 확보\n")
  } else {
    cat("  [COND_01] WARNING: rho >= 0.70 — 두 팩터 중복 가능성\n")
  }
}

elapsed_total <- as.numeric(difftime(Sys.time(), t_total, units = "secs"))
cat(sprintf("\n[완료] 총 소요: %.1f초\n", elapsed_total))
cat("=== rebuild_q35_only.R 종료 ===\n")
