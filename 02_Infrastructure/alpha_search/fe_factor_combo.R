# =============================================================================
# fe_factor_combo.R — factor DB 조합형 generic factor engine
# =============================================================================
# 목적: FACTOR_NAMES로 지정한 여러 factor의 Z_Score_Aligned를 월별 PIT 로더로
#       가져와 weighted composite Score를 생성한다. AlphaSearch에서 논문/전략풀의
#       조합형 베이스 시그널을 빠르게 검증하기 위한 엔진이다.
#
# 원칙:
#   - C15: factor DB 직접 parquet 읽기 금지, load_month_factors(sig_date)만 사용.
#   - C13: NEGATE/FLIP 없음. factor DB의 Z_Score_Aligned 방향을 그대로 사용.
#   - overlay, grade hurdle, market timing, stop-loss는 본 엔진에서 구현하지 않는다.
#     이 파일은 다른 모드(QEPM/팩터 로테이션)가 재사용할 수 있는 베이스 시그널 산출물만 만든다.
#
# 환경변수:
#   FACTOR_NAMES       필수, comma-separated factor names
#   FACTOR_WEIGHTS     선택, comma-separated non-negative weights. 미지정 시 동일가중.
#   FACTOR_MIN_COUNT   선택, 월별 종목 score 산출에 필요한 최소 factor 개수.
#                      미지정 시 모든 지정 factor가 있어야 한다.
#
# 출력: FACTORS(Date, Ticker, Score)
# =============================================================================

stopifnot(exists("RAWDATA"), is.data.table(RAWDATA))

.FE_FACTOR_STR <- Sys.getenv("FACTOR_NAMES", "")
.FE_FACTORS <- trimws(strsplit(.FE_FACTOR_STR, ",", fixed = TRUE)[[1]])
.FE_FACTORS <- unique(.FE_FACTORS[nzchar(.FE_FACTORS)])
if (!length(.FE_FACTORS)) {
  stop("[fe_factor_combo] FACTOR_NAMES 환경변수 미설정 — comma-separated factor names 필요")
}

.FE_WEIGHT_STR <- Sys.getenv("FACTOR_WEIGHTS", "")
if (nzchar(.FE_WEIGHT_STR)) {
  .FE_WEIGHTS <- suppressWarnings(as.numeric(trimws(strsplit(.FE_WEIGHT_STR, ",", fixed = TRUE)[[1]])))
  if (length(.FE_WEIGHTS) != length(.FE_FACTORS) ||
      any(!is.finite(.FE_WEIGHTS)) || any(.FE_WEIGHTS < 0) || !any(.FE_WEIGHTS > 0)) {
    stop("[fe_factor_combo] FACTOR_WEIGHTS는 FACTOR_NAMES와 같은 길이의 non-negative numeric vector여야 함")
  }
} else {
  .FE_WEIGHTS <- rep(1, length(.FE_FACTORS))
}
.FE_WEIGHTS <- setNames(.FE_WEIGHTS, .FE_FACTORS)

.FE_MIN_COUNT <- suppressWarnings(as.integer(Sys.getenv("FACTOR_MIN_COUNT", "")))
if (is.na(.FE_MIN_COUNT) || .FE_MIN_COUNT < 1L) .FE_MIN_COUNT <- length(.FE_FACTORS)
.FE_MIN_COUNT <- min(.FE_MIN_COUNT, length(.FE_FACTORS))

local({
  conn <- file.path(Sys.getenv("CLAUDE_PROJECT_DIR", "G:/Quant_Module_Moltbot"),
                    "02_Infrastructure", "factor_db", "factor_db_connector.R")
  if (!exists("load_month_factors", mode = "function")) source(conn)
})

# Universe 산출만 RAWDATA를 사용한다. 이후 factor DB 로딩 peak를 낮추기 위해 해제한다.
.rd_slim <- RAWDATA[, .(Date, Ticker, Close, Vol, K200, KQ150)]
setorder(.rd_slim, Ticker, Date)

.rd_slim[, .ym := format(Date, "%Y-%m")]
.month_ends <- sort(.rd_slim[, .(Date = max(Date)), by = .ym]$Date)
.rd_slim[, .ym := NULL]
.fdb_min <- as.Date("2002-08-01")
.month_ends <- .month_ends[.month_ends >= .fdb_min]

.rd_slim[, .TV := Close * Vol]
.rd_slim[, .AvgTV20 := frollmean(.TV, 20L, align = "right"), by = Ticker]
.mem <- .rd_slim[Date %in% .month_ends & (K200 == TRUE | KQ150 == TRUE) &
                   !is.na(.AvgTV20) & .AvgTV20 >= 2e8,
                 .(Date, Ticker)]
setkey(.mem, Date, Ticker)

rm(.rd_slim)
if (exists("RAWDATA", inherits = FALSE)) rm(RAWDATA)
gc(verbose = FALSE)

.factor_list <- vector("list", length(.month_ends))
for (i in seq_along(.month_ends)) {
  d <- .month_ends[i]
  uni_tk <- .mem[.(d), Ticker, nomatch = 0L]
  if (!length(uni_tk)) next

  fdt <- tryCatch(
    load_month_factors(d, coverage_min = 0.05, factor_names = .FE_FACTORS),
    error = function(e) NULL
  )
  if (is.null(fdt) || nrow(fdt) == 0) {
    if (!is.null(fdt)) rm(fdt)
    next
  }

  fz_long <- fdt[
    Factor_Name %in% .FE_FACTORS & Ticker %in% uni_tk & is.finite(Z_Score_Aligned),
    .(Ticker, Factor_Name, Z = Z_Score_Aligned)
  ]
  rm(fdt)
  if (!nrow(fz_long)) next

  fz_long[, W := .FE_WEIGHTS[Factor_Name]]
  fz <- fz_long[
    ,
    .(
      Score = sum(W * Z, na.rm = TRUE) / sum(W, na.rm = TRUE),
      factor_count = .N
    ),
    by = Ticker
  ][factor_count >= .FE_MIN_COUNT & is.finite(Score), .(Ticker, Score)]
  rm(fz_long)

  if (nrow(fz) < 20L) next
  fz[, Date := d]
  .factor_list[[i]] <- fz[, .(Date, Ticker, Score)]
  if (i %% 24L == 0L) gc(verbose = FALSE)
}

FACTORS <- rbindlist(Filter(Negate(is.null), .factor_list), use.names = TRUE)
rm(.factor_list)
gc(verbose = FALSE)

cat(sprintf(
  "[fe_factor_combo] factors=%s | min_count=%d | rows=%d | signal months=%d | avg N/month=%.0f\n",
  paste(.FE_FACTORS, collapse = ","),
  .FE_MIN_COUNT,
  nrow(FACTORS),
  uniqueN(FACTORS$Date),
  if (nrow(FACTORS)) nrow(FACTORS) / max(uniqueN(FACTORS$Date), 1L) else 0
))
