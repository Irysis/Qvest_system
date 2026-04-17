#==============================================================================
# apply_universe_mapping.R — RAWDATA에 Universe 메타 매핑
#
# 2단계 조인:
#   Layer 1: universe.parquet (KRX API 기반, Ticker/Name/Market/Sector_KRX)
#   Layer 2: universe_support/*.parquet (QuantiWise, WI26/Float/K200/KQ150/시장조치)
#            → Phase B에서 활성화 (Universe_Support.xlsx 준비 후)
#
# Usage:
#   source("02_Infrastructure/config.R")
#   source("02_Infrastructure/apply_universe_mapping.R")
#   apply_universe_mapping()
#==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
})

apply_universe_mapping <- function() {
  cat("[mapping] Applying universe metadata to RAWDATA...\n")

  if (!file.exists(RAWDATA_CACHE)) {
    cat("[mapping] RAWDATA.parquet not found — skip.\n")
    return(invisible(NULL))
  }

  raw <- as.data.table(read_parquet(RAWDATA_CACHE))
  raw[, Date := as.Date(Date)]

  # ── Layer 1: KRX 기본 유니버스 ────────────────────────────────────────────
  if (file.exists(UNIVERSE_CACHE)) {
    uni <- as.data.table(read_parquet(UNIVERSE_CACHE))
    uni[, Date := as.Date(Date)]

    # 기존 메타 컬럼 제거 (있으면)
    meta_cols <- intersect(c("Name", "Market", "Sector"), names(raw))
    if (length(meta_cols) > 0) raw[, (meta_cols) := NULL]

    setkey(uni, Ticker, Date)
    setkey(raw, Ticker, Date)

    # roll join: 각 (Ticker, Date)에 가장 가까운 이전 universe 정보 매핑
    raw <- uni[, .(Date, Ticker, Name, Market, Sector)][raw, roll = Inf, on = .(Ticker, Date)]

    cat(sprintf("[mapping] Layer 1 (KRX): %d rows, Sector NA = %.1f%%\n",
                nrow(raw),
                100 * sum(is.na(raw$Sector)) / nrow(raw)))
  } else {
    cat("[mapping] universe.parquet not found — Layer 1 skipped.\n")
  }

  # ── Layer 2: Universe_Support 메타 (Phase B — xlsx 준비 후 활성화) ──────────
  if (exists("UNIVERSE_SUPPORT_CACHE") && dir.exists(UNIVERSE_SUPPORT_CACHE)) {
    # 파일명은 us_{cache_name}.parquet (parse_universe_support.R 규칙)
    support_files <- list(
      us_sector_lv1     = "Sector_Lv1",      # WI26 대분류 → Sector 덮어쓰기
      us_sector_lv2     = "Sector_Lv2",      # WI26 중분류
      us_float          = "Float",            # 유동비율
      us_k200           = "K200",             # KOSPI 200 멤버십
      us_kq150          = "KQ150",            # KOSDAQ 150 멤버십
      us_trading_halt   = "TradingHalt",      # 거래정지
      us_admin_stock    = "AdminStock",       # 관리종목
      us_unfaithful_disc = "UnfaithfulDisc"   # 불성실공시
    )

    n_joined <- 0L
    for (cache_name in names(support_files)) {
      pq_path <- file.path(UNIVERSE_SUPPORT_CACHE, paste0(cache_name, ".parquet"))
      if (!file.exists(pq_path)) next

      col_name <- support_files[[cache_name]]
      meta <- as.data.table(read_parquet(pq_path))
      meta[, Date := as.Date(Date)]
      setnames(meta, "Value", col_name, skip_absent = TRUE)

      # 기존 컬럼 덮어쓰기 (Sector_Lv1 → Sector)
      if (col_name == "Sector_Lv1" && "Sector" %in% names(raw)) {
        raw[, Sector := NULL]
        setnames(meta, "Sector_Lv1", "Sector", skip_absent = TRUE)
        col_name <- "Sector"
      }
      if (col_name %in% names(raw)) raw[, (col_name) := NULL]

      setkey(meta, Ticker, Date)
      setkey(raw, Ticker, Date)
      raw <- meta[raw, roll = Inf, on = .(Ticker, Date)]
      n_joined <- n_joined + 1L
    }

    if (n_joined > 0) {
      cat(sprintf("[mapping] Layer 2 (Support): %d fields joined\n", n_joined))
    }
  } else {
    cat("[mapping] Universe_Support cache not found — Layer 2 skipped (Phase B pending).\n")
  }

  # ── 저장 ──────────────────────────────────────────────────────────────────
  setorder(raw, Date, Ticker)
  write_parquet(raw, RAWDATA_CACHE)
  cat(sprintf("[mapping] RAWDATA updated: %s rows | %s ~ %s\n",
              format(nrow(raw), big.mark = ","),
              min(raw$Date), max(raw$Date)))

  invisible(raw)
}

cat("[apply_universe_mapping] Loaded.\n")
