#==============================================================================
# universe_expanded_v2.R — KR Universe Expansion v2 (L-227 mandate)
#
# Goal: KR top ~342 (KOSPI200 ∪ KOSDAQ150 + 2e8 KRW) 한계 극복 → 500+ names
#
# Scope (Architect v1.0 advisory, 2026-04-26):
#   Iter 13 v2 ICIR 0.086, Iter 15 V3 alpha 부재, Iter 16 KR linear/sigmoid fail
#   → 모두 universe-restricted alpha attenuation 의심.
#   v2 universe option을 인프라 차원에서 정식 노출 (강제 X, opt-in).
#
# Design principles
#   - **PIT-safe**: 모든 universe 멤버십은 sig_date 시점 거래대금/시총 ranking 기반.
#     full-sample stats / forward-looking index membership 금지.
#   - **Backward-compat**: 기존 KOSPI200_KOSDAQ150_intersection (label "KR_top342")
#     기본값 유지. opt-in 시에만 v2 활성화.
#   - **No factor DB rebuild required (Phase 1)**: factor parquet은 universe-agnostic
#     (전종목 × 288/309 factors). universe 필터링은 load_month_factors() consumer
#     레이어에서 수행. → Phase 2에서 DB universe meta-tag 가능 (선택).
#
# Universe options (v2 advisory)
#   A) KR_TOP500_FREEFLOAT  : 시총·float top 500 (KOSPI ∪ KOSDAQ 통합)
#   B) KR_KOSPI300_KOSDAQ150 : KOSPI 시총 top 300 + KOSDAQ 시총 top 150 (~450)
#   C) KR_TOP500_LIQ1E8     : 거래대금 1e8+ 충족 종목 중 시총 top 500
#   D) KR_SECTOR_BAL_TOP500 : 섹터별 균형 top 500 (sector_n × cap_per_sector)
#
# Recommendation (Architect): **Option A (KR_TOP500_FREEFLOAT)** + Option C 보조
#   - A는 단일 ranking 기준 (FreeFloat MktCap PIT) → 재현성·해석성 최고
#   - C는 mid-cap noise 우려 시 거래대금 1e8 KRW hard floor opt-in
#   - B는 정기변경 의존 (외부 KOSPI300 정의가 KRX 정식 지수에 없음 — KOSPI300=시총상위 300으로 정의 필요. 표준 데이터셋 부재)
#   - D는 implementation cost 높고 sector taxonomy 안정성 의존 → Phase 2 보류
#
# API
#   build_universe_v2(sig_date, label, ...) → data.table(Date, Ticker, Universe_Label, Rank, MktCap, AvgTrdVal)
#   list_universe_v2_labels() → character vector
#   load_month_factors(sig_date, universe = "KR_top342") → 기존 인터페이스에 universe 파라미터 추가
#
# PIT contract
#   - sig_date t에 universe membership 결정 시 사용 데이터: t 시점 RAWDATA Close*Vol
#     (t-1까지의 누적 20d/60d 평균). t 시점 future return 절대 미참조.
#   - FreeFloat ratio는 KRX shareholder filing 기반, t 이전 마지막 공시 사용.
#   - 미공시 종목은 FreeFloat=1.0 conservative fallback (not exclusion).
#
# Risks (mandatory before adoption)
#   R1 Sector imbalance: top 500 확대 시 IT/2차전지/바이오 편중 → sector_max 30% guardrail
#   R2 Mega-cap correlation: STR_1701 (KOSPI200 등액중심)과 cor 변화 측정 필요.
#       v2 universe + 기존 STR_1701 alpha apply 후 daily corr / TDC 재계산.
#   R3 Liquidity floor: 거래대금 1e8 KRW < 2e8 mandate. 슬리피지·impact cost
#       backtest cost 가정 (15bps) 부족 가능 → 25bps proxy 권고 (opt-in C).
#   R4 Survivorship: 상장폐지 종목 t 시점 RAWDATA 존재 시 자동 포함 (기존
#       krx_update_universe.R 로직 carry-forward, dead ticker auto-drop).
#   R5 Coverage drift: factor_db_daily의 일부 팩터(특히 fundamental)가
#       mid-cap 종목에서 결측 증가 → coverage_min=0.05 → 0.10 상향 권고.
#
# Adoption phases
#   Phase 1 (this file): R 라이브러리 + load_month_factors universe 파라미터 (즉시 사용 가능).
#                        Factor DB rebuild 불필요.
#   Phase 2: factor_db_daily_registry.json universe_v2 entry (메타데이터만,
#            팩터 데이터는 동일).
#   Phase 3: alpha-research.md prompt에 v2 옵션 명시 (KR_top342 vs v2 비교 mandate).
#   Phase 4: hook 검증 (worktask_artifact_validator + mandate_compliance_check)
#            v2 schema 인식.
#==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(jsonlite)
})

# ---- Path resolution (한글 경로 호환) ----
.uev2_self_dir <- tryCatch(
  dirname(sys.frame(1)$ofile),
  error = function(e) {
    if (exists("FUNC_PATH")) file.path(FUNC_PATH, "factor_db")
    else file.path(
      "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot",
      "02_Infrastructure", "factor_db"
    )
  }
)

if (!exists("CACHE_DIR")) {
  source(file.path(dirname(.uev2_self_dir), "config.R"))
}

UNIVERSE_V2_CACHE <- file.path(CACHE_DIR, "universe_v2")
if (!dir.exists(UNIVERSE_V2_CACHE)) dir.create(UNIVERSE_V2_CACHE, recursive = TRUE)

UNIVERSE_V2_REGISTRY <- file.path(UNIVERSE_V2_CACHE, "universe_v2_registry.json")
RAWDATA_PATH <- file.path(CACHE_DIR, "rawdata.parquet")
UNIVERSE_BASE_PATH <- file.path(CACHE_DIR, "universe.parquet")  # 기존 KR_top342 base

# ---- Label specs ----
.UNIVERSE_V2_SPECS <- list(
  KR_top342 = list(
    description = "기존 KOSPI200 ∪ KOSDAQ150 + 2e8 KRW 유동성 (default, backward-compat)",
    target_size = 342,
    method = "intersection",
    liq_floor_krw = 2e8,
    sector_balance = FALSE,
    requires_freefloat = FALSE
  ),
  KR_TOP500_FREEFLOAT = list(
    description = "시총·float top 500 (KOSPI ∪ KOSDAQ 통합, FreeFloat MktCap PIT ranking)",
    target_size = 500,
    method = "freefloat_mktcap_top",
    liq_floor_krw = 2e8,
    sector_balance = FALSE,
    requires_freefloat = TRUE
  ),
  KR_KOSPI300_KOSDAQ150 = list(
    description = "KOSPI 시총 top 300 + KOSDAQ 시총 top 150 (시장별 분리 ranking)",
    target_size = 450,
    method = "market_split_top",
    market_quotas = list(KOSPI = 300L, KOSDAQ = 150L),
    liq_floor_krw = 2e8,
    sector_balance = FALSE,
    requires_freefloat = FALSE
  ),
  KR_TOP500_LIQ1E8 = list(
    description = "거래대금 1e8+ 종목 중 시총 top 500 (mid-cap 포함, slippage 25bps 권고)",
    target_size = 500,
    method = "mktcap_top_with_relaxed_liq",
    liq_floor_krw = 1e8,
    sector_balance = FALSE,
    requires_freefloat = FALSE,
    cost_recommendation_bps = 25L
  ),
  KR_SECTOR_BAL_TOP500 = list(
    description = "섹터별 균형 top 500 (Phase 2 reserve, taxonomy 안정성 의존)",
    target_size = 500,
    method = "sector_balanced",
    liq_floor_krw = 2e8,
    sector_balance = TRUE,
    sector_max_share = 0.30,
    requires_freefloat = TRUE,
    status = "RESERVED_PHASE2"
  )
)

#' List available universe v2 labels.
list_universe_v2_labels <- function() {
  names(.UNIVERSE_V2_SPECS)
}

#' Get spec for a given label.
get_universe_v2_spec <- function(label) {
  if (!label %in% names(.UNIVERSE_V2_SPECS)) {
    stop("[universe_v2] Unknown label: ", label,
         ". Available: ", paste(list_universe_v2_labels(), collapse = ", "))
  }
  .UNIVERSE_V2_SPECS[[label]]
}

#==============================================================================
# build_universe_v2 — 단일 sig_date에서 universe membership 계산 (PIT-safe)
#==============================================================================

#' Build universe membership for a given sig_date (PIT-safe).
#'
#' @param sig_date Date or character. Signal date.
#' @param label Universe label (see list_universe_v2_labels()).
#' @param liq_window_days Integer. Days for avg trading value rolling window.
#' @param force_recompute Logical. If TRUE, ignore cache.
#' @return data.table(Date, Ticker, Market, Universe_Label, MktCap, FreeFloat,
#'                   FreeFloatMktCap, AvgTrdVal_20d, Rank)
build_universe_v2 <- function(sig_date,
                              label = "KR_TOP500_FREEFLOAT",
                              liq_window_days = 20L,
                              force_recompute = FALSE) {

  sig_d <- as.Date(sig_date)
  spec <- get_universe_v2_spec(label)

  if (!is.null(spec$status) && spec$status == "RESERVED_PHASE2") {
    stop("[universe_v2] Label ", label, " is reserved for Phase 2. Not yet implemented.")
  }

  # Cache key
  cache_path <- file.path(
    UNIVERSE_V2_CACHE,
    sprintf("universe_%s_%s.parquet", label, format(sig_d, "%Y%m%d"))
  )
  if (file.exists(cache_path) && !force_recompute) {
    return(as.data.table(read_parquet(cache_path)))
  }

  # ---- 1. RAWDATA load (PIT: only Date <= sig_d) ----
  if (!file.exists(RAWDATA_PATH)) {
    stop("[universe_v2] RAWDATA not found: ", RAWDATA_PATH)
  }
  raw <- as.data.table(read_parquet(RAWDATA_PATH))
  raw[, Date := as.Date(Date)]
  raw <- raw[Date <= sig_d]

  if (nrow(raw) == 0) {
    stop("[universe_v2] No RAWDATA at or before ", sig_d)
  }

  # ---- 2. Liquidity stats over last liq_window_days ----
  cutoff <- sig_d - liq_window_days * 2L  # buffer for non-trading days
  raw_liq <- raw[Date >= cutoff & Date <= sig_d]

  liq_stats <- raw_liq[, .(
    AvgTrdVal_20d = mean(Vol * Close, na.rm = TRUE),
    LastClose = last(Close),
    LastVol = last(Vol),
    N_Days = .N
  ), by = Ticker]
  liq_stats <- liq_stats[N_Days >= liq_window_days * 0.5]  # at least half of trading days

  # ---- 3. MktCap (proxy: Close * SharesOut from RAWDATA, fallback Size column) ----
  raw_latest <- raw[Date == max(raw[Ticker %in% liq_stats$Ticker]$Date),
                     .(Ticker, Close, Vol, Size = if ("Size" %in% names(raw)) Size else NA_real_)]
  setkey(raw_latest, Ticker)

  mktcap_dt <- merge(liq_stats, raw_latest[, .(Ticker, Size)], by = "Ticker", all.x = TRUE)

  # MktCap proxy: Size 컬럼이 있으면 그것 사용. 없으면 Close * Vol 누적 proxy 불가 → SharesOut 필요.
  # 현재는 Size 컬럼 신뢰. 결측 종목은 LastClose * SharesOut(unknown) → drop with warning.
  if (all(is.na(mktcap_dt$Size))) {
    warning("[universe_v2] RAWDATA Size column all NA. Falling back to AvgTrdVal-based ranking (proxy).")
    mktcap_dt[, MktCap := AvgTrdVal_20d]
  } else {
    mktcap_dt[, MktCap := Size]
  }

  # ---- 4. FreeFloat (optional, KRX filing or DART) ----
  # Phase 1: FreeFloat=1.0 conservative fallback. Phase 2에서 KRX shareholder filing 통합.
  if (isTRUE(spec$requires_freefloat)) {
    freefloat_path <- file.path(CACHE_DIR, "freefloat_history.parquet")
    if (file.exists(freefloat_path)) {
      ff <- as.data.table(read_parquet(freefloat_path))
      ff[, Date := as.Date(Date)]
      ff_pit <- ff[Date <= sig_d, .SD[.N], by = Ticker, .SDcols = c("Date", "FreeFloat")]
      mktcap_dt <- merge(mktcap_dt, ff_pit[, .(Ticker, FreeFloat)], by = "Ticker", all.x = TRUE)
    } else {
      mktcap_dt[, FreeFloat := NA_real_]
    }
    mktcap_dt[is.na(FreeFloat), FreeFloat := 1.0]  # conservative fallback
    mktcap_dt[, FreeFloatMktCap := MktCap * FreeFloat]
  } else {
    mktcap_dt[, FreeFloat := 1.0]
    mktcap_dt[, FreeFloatMktCap := MktCap]
  }

  # ---- 5. Apply liq_floor ----
  mktcap_dt <- mktcap_dt[AvgTrdVal_20d >= spec$liq_floor_krw]

  # ---- 6. Market tagging (KOSPI vs KOSDAQ from KRX info cache) ----
  market_map <- .build_market_map(sig_d)
  mktcap_dt <- merge(mktcap_dt, market_map, by = "Ticker", all.x = TRUE)
  mktcap_dt[is.na(Market), Market := "KOSPI"]  # default

  # ---- 7. Selection by spec method ----
  if (spec$method == "freefloat_mktcap_top" || spec$method == "mktcap_top_with_relaxed_liq") {
    setorder(mktcap_dt, -FreeFloatMktCap)
    mktcap_dt[, Rank := seq_len(.N)]
    selected <- mktcap_dt[Rank <= spec$target_size]

  } else if (spec$method == "market_split_top") {
    quotas <- spec$market_quotas
    selected_list <- list()
    for (mk in names(quotas)) {
      sub <- mktcap_dt[Market == mk]
      setorder(sub, -FreeFloatMktCap)
      sub[, Rank := seq_len(.N)]
      selected_list[[mk]] <- sub[Rank <= quotas[[mk]]]
    }
    selected <- rbindlist(selected_list)

  } else if (spec$method == "intersection") {
    # 기존 KR_top342 — universe.parquet base 사용
    if (!file.exists(UNIVERSE_BASE_PATH)) {
      stop("[universe_v2] KR_top342 base universe.parquet missing: ", UNIVERSE_BASE_PATH)
    }
    base_uni <- as.data.table(read_parquet(UNIVERSE_BASE_PATH))
    base_uni[, Date := as.Date(Date)]
    # Latest base date <= sig_d
    base_dates <- sort(unique(base_uni$Date))
    base_d <- max(base_dates[base_dates <= sig_d])
    base_at_d <- base_uni[Date == base_d, .(Ticker)]
    selected <- merge(mktcap_dt, base_at_d, by = "Ticker")
    setorder(selected, -FreeFloatMktCap)
    selected[, Rank := seq_len(.N)]

  } else if (spec$method == "sector_balanced") {
    stop("[universe_v2] sector_balanced method not implemented in Phase 1.")

  } else {
    stop("[universe_v2] Unknown method: ", spec$method)
  }

  # ---- 8. Finalize ----
  selected[, `:=`(
    Date = sig_d,
    Universe_Label = label
  )]
  out <- selected[, .(Date, Ticker, Market, Universe_Label, MktCap, FreeFloat,
                      FreeFloatMktCap, AvgTrdVal_20d, Rank)]

  # ---- 9. Cache ----
  write_parquet(out, cache_path)

  out
}

#==============================================================================
# .build_market_map — KRX info cache → KOSPI/KOSDAQ tagging
#==============================================================================
.build_market_map <- function(sig_d) {
  krx_info_dir <- file.path(CACHE_DIR, "krx")
  kospi_files <- list.files(file.path(krx_info_dir, "stk_info"), full.names = TRUE)
  kosdaq_files <- list.files(file.path(krx_info_dir, "ksq_info"), full.names = TRUE)

  pick_pit <- function(files, sig_d) {
    if (length(files) == 0) return(character(0))
    file_dates <- as.Date(gsub(".*_(\\d{8})\\.parquet$", "\\1", basename(files)), "%Y%m%d")
    pit_files <- files[file_dates <= sig_d]
    if (length(pit_files) == 0) pit_files <- files[which.min(abs(file_dates - sig_d))]
    latest <- tail(sort(pit_files), 1)
    dt <- tryCatch(as.data.table(read_parquet(latest)), error = function(e) NULL)
    if (is.null(dt) || !"ISU_SRT_CD" %in% names(dt)) return(character(0))
    unique(dt$ISU_SRT_CD)
  }

  kospi_t <- pick_pit(kospi_files, sig_d)
  kosdaq_t <- pick_pit(kosdaq_files, sig_d)

  data.table(
    Ticker = c(kospi_t, kosdaq_t),
    Market = c(rep("KOSPI", length(kospi_t)), rep("KOSDAQ", length(kosdaq_t)))
  )[!duplicated(Ticker)]
}

#==============================================================================
# Universe-aware load_month_factors() wrapper
#==============================================================================

#' load_month_factors with universe filter (v2 wrapper).
#'
#' Backward-compat: universe="KR_top342" (default) → identical to legacy load_month_factors.
#' v2: universe="KR_TOP500_FREEFLOAT" → expanded universe.
#'
#' @param sig_date Date.
#' @param coverage_min Numeric (Architect 권고: 0.10 for v2, 0.05 for KR_top342).
#' @param universe Character. Universe label (see list_universe_v2_labels()).
#' @return data.table(Ticker, Factor_Name, Z_Score_Aligned) — universe 필터 후
load_month_factors_v2 <- function(sig_date,
                                  coverage_min = NULL,
                                  universe = "KR_top342") {
  # Default coverage_min by universe
  if (is.null(coverage_min)) {
    coverage_min <- if (universe == "KR_top342") 0.05 else 0.10
  }

  # 1. Load full factor month (universe-agnostic parquet)
  if (!exists("load_month_factors")) {
    source(file.path(.uev2_self_dir, "factor_db_connector.R"))
  }
  full <- load_month_factors(sig_date, coverage_min = coverage_min)

  # 2. Build universe at sig_date
  uni <- build_universe_v2(sig_date, label = universe)

  # 3. Filter
  out <- full[Ticker %in% uni$Ticker]
  attr(out, "universe_label") <- universe
  attr(out, "universe_size") <- nrow(uni)
  out
}

#==============================================================================
# Registry export — universe_v2 metadata
#==============================================================================

#' Export universe_v2 registry to JSON (for hook / agent prompt consumption).
export_universe_v2_registry <- function(path = UNIVERSE_V2_REGISTRY) {
  reg <- list(
    version = "2.0.0",
    updated = format(Sys.time(), "%Y-%m-%dT%H:%M:%S"),
    description = "KR Universe Expansion v2 (L-227 mandate). Backward-compat with KR_top342.",
    labels = .UNIVERSE_V2_SPECS,
    api = list(
      build = "build_universe_v2(sig_date, label, ...)",
      load = "load_month_factors_v2(sig_date, coverage_min, universe)",
      list = "list_universe_v2_labels()"
    ),
    architect_advisory = list(
      recommended_default = "KR_top342",
      recommended_v2 = "KR_TOP500_FREEFLOAT",
      mandate_when = "ICIR_attenuation_diagnosed (L-227)",
      cost_adjustment = list(
        KR_top342 = "15bps",
        KR_TOP500_FREEFLOAT = "20bps (mid-cap impact buffer)",
        KR_TOP500_LIQ1E8 = "25bps (1e8 floor concession)"
      )
    )
  )
  write(toJSON(reg, pretty = TRUE, auto_unbox = TRUE), path)
  cat("[universe_v2] Registry exported: ", path, "\n")
  invisible(reg)
}

cat("[universe_expanded_v2] Loaded.\n")
cat("[universe_expanded_v2] Functions: build_universe_v2(), load_month_factors_v2(),\n")
cat("                                  list_universe_v2_labels(), export_universe_v2_registry()\n")
cat("[universe_expanded_v2] Available labels: ",
    paste(list_universe_v2_labels(), collapse = ", "), "\n")
