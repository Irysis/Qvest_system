#==============================================================================
# Quant Module — Unified Regime Signal (3-Layer Cascade + BCS Overlay)
# Version: 1.1.0
#
# 위기국면 사전 탐지 → 방어팩터 전환 + 현금화 타이밍 결정
#
# Architecture:
#   Layer 1 (Detection):   MSM Crisis_Prob — Recall 86.5%, 고감도 조기 탐지
#   Layer 2 (Confirmation): FRED MRS — Precision 40%, 검증된 거시 확인
#   Layer 3 (Validation):   KTRI + VEA — Precision 60.8%, 시장 미시구조 확인
#   Layer 4 (Behavioral):   BCS Daily — r=-0.143, 행태 기반 동행/선행 탐지
#
# Score → Category → Cash% + Factor Adjustments
# BCS overlay: 월간 캐스케이드에 일간 행태 오버레이 (+15%/+5% 추가 캐시)
#
# Usage:
#   source("config.R")
#   source("regime_signal.R")
#   build_regime_signal_table()         # 전체 파이프라인 → parquet 저장
#   signal_dt <- load_regime_signal()   # 캐시 로드
#   regime <- get_regime_at_date(as.Date("2020-03-31"), signal_dt)
#   FACTORS <- merge_regime_signal(FACTORS, signal_dt)
#
# Dependencies: data.table, arrow
#==============================================================================

if (!exists("PROJECT_ROOT")) {
  source(file.path(dirname(dirname(sys.frame(1)$ofile %||% ".")), "config.R"))
}

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
})

cat("[regime_signal] Loading 3-Layer Cascade module...\n")


#==============================================================================
# 1. load_msm_signal() — MSM .RData → monthly Crisis_Prob
#==============================================================================

load_msm_signal <- function() {
  # Primary: parquet cache (from msm_update.R)
  msm_parquet <- file.path(CACHE_DIR, "msm_hybrid_latest.parquet")

  if (file.exists(msm_parquet)) {
    dt <- as.data.table(read_parquet(msm_parquet))
    dt[, Date := as.Date(Date)]
    # Avg_Prob = Crisis probability (0-1)
    setnames(dt, "Avg_Prob", "MSM_Crisis_Prob", skip_absent = TRUE)
    dt[, YM := format(Date, "%Y-%m")]
    cat(sprintf("[regime_signal] MSM loaded (parquet): %d months | %s ~ %s\n",
                nrow(dt), min(dt$Date), max(dt$Date)))
    return(dt[, .(Date, YM, MSM_Crisis_Prob)])
  }

  # Fallback: .RData (production)
  msm_dir <- file.path(PROJECT_ROOT,
                        "05_Production/1.Regime_Def_Model/1-1.MSM")
  rdata_files <- list.files(msm_dir, pattern = "MSM\\.RData$",
                            full.names = TRUE)
  if (length(rdata_files) == 0) {
    warning("[regime_signal] No MSM data found. Layer 1 will be disabled.")
    return(data.table(Date = as.Date(character(0)),
                      YM = character(0),
                      MSM_Crisis_Prob = numeric(0)))
  }

  full_path <- rdata_files[length(rdata_files)]  # latest
  env <- new.env()
  load(full_path, envir = env)

  if (exists("monthly_prob", envir = env)) {
    mp <- env$monthly_prob
    dt <- data.table(
      Date = as.Date(index(mp)),
      MSM_Crisis_Prob = as.numeric(coredata(mp))
    )
  } else if (exists("History_Daily", envir = env)) {
    hd <- as.data.table(env$History_Daily)
    hd[, Date := as.Date(Date)]
    hd[, YM := format(Date, "%Y-%m")]
    dt <- hd[, .(MSM_Crisis_Prob = mean(Crisis_Prob, na.rm = TRUE),
                  Date = max(Date)), by = YM]
  } else {
    warning("[regime_signal] Unrecognized MSM RData structure.")
    return(data.table(Date = as.Date(character(0)),
                      YM = character(0),
                      MSM_Crisis_Prob = numeric(0)))
  }

  dt[, YM := format(Date, "%Y-%m")]
  cat(sprintf("[regime_signal] MSM loaded (RData): %d months | %s ~ %s\n",
              nrow(dt), min(dt$Date), max(dt$Date)))
  dt[, .(Date, YM, MSM_Crisis_Prob)]
}


#==============================================================================
# 2. load_fred_signal() — macro_regime.parquet → monthly MRS
#==============================================================================

load_fred_signal <- function() {
  # Priority 1: macro_regime.parquet (pre-computed monthly MRS via fred_compute_regime)
  fred_path <- if (exists("FRED_REGIME_CACHE")) {
    FRED_REGIME_CACHE
  } else {
    file.path(CACHE_DIR, "macro_regime.parquet")
  }

  if (file.exists(fred_path)) {
    dt <- as.data.table(read_parquet(fred_path))
    dt[, Date := as.Date(Date)]
    dt[, YM := format(Date, "%Y-%m")]
    setnames(dt, "Macro_Risk_Score", "FRED_MRS", skip_absent = TRUE)
    keep_cols <- intersect(names(dt),
                           c("Date", "YM", "FRED_MRS", "VIX_Regime", "Buddha_Mode"))
    dt <- dt[, ..keep_cols]
    cat(sprintf("[regime_signal] FRED loaded (regime cache): %d months | %s ~ %s\n",
                nrow(dt), min(dt$Date), max(dt$Date)))
    return(dt)
  }

  # Priority 2 (Step 4): fred_robust wide/long format → compute simple MRS placeholder
  # Briefing 호환: wide 우선, long fallback. MRS 계산 불가 시 NA_real_ 반환.
  robust_wide <- file.path(CACHE_DIR, "fred_macro_wide.parquet")
  robust_long <- file.path(CACHE_DIR, "fred_macro.parquet")

  wide_dt <- NULL
  if (file.exists(robust_wide)) {
    wide_dt <- as.data.table(read_parquet(robust_wide))
    cat(sprintf("[regime_signal] FRED loaded (robust wide): %d rows\n", nrow(wide_dt)))
  } else if (file.exists(robust_long)) {
    long_dt <- as.data.table(read_parquet(robust_long))
    if (all(c("Date", "Series", "Value") %in% names(long_dt))) {
      wide_dt <- dcast(long_dt, Date ~ Series, value.var = "Value")
      cat(sprintf("[regime_signal] FRED loaded (robust long→wide): %d rows\n",
                  nrow(wide_dt)))
    }
  }

  if (is.null(wide_dt) || nrow(wide_dt) == 0) {
    warning("[regime_signal] FRED regime cache not found. Layer 2 disabled.")
    return(data.table(Date = as.Date(character(0)),
                      YM = character(0),
                      FRED_MRS = numeric(0)))
  }

  # Monthly aggregation: last obs per YM
  date_col <- intersect(c("Date", "date"), names(wide_dt))[1]
  if (is.na(date_col)) {
    warning("[regime_signal] FRED wide has no Date column. Layer 2 disabled.")
    return(data.table(Date = as.Date(character(0)), YM = character(0),
                      FRED_MRS = numeric(0)))
  }
  if (date_col != "Date") setnames(wide_dt, date_col, "Date")
  wide_dt[, Date := as.Date(Date)]
  wide_dt[, YM := format(Date, "%Y-%m")]

  # Month-end last obs for key axes
  key_cols <- intersect(c("VIX", "HY_Spread", "Term_Spread", "KRW_USD",
                          "StL_Fin_Stress", "Chi_Fin_Cond"),
                        names(wide_dt))
  monthly <- wide_dt[, {
    last_row <- .SD[which.max(Date)]
    as.list(last_row)
  }, by = YM, .SDcols = unique(c("Date", key_cols))]

  # Simplified MRS approximation (full calc in fred_compute_regime)
  monthly[, FRED_MRS := 0]
  if ("VIX" %in% names(monthly)) {
    monthly[, FRED_MRS := FRED_MRS +
              fifelse(!is.na(VIX) & VIX > 30, 20,
                      fifelse(!is.na(VIX) & VIX > 20, 10, 0))]
  }
  if ("Term_Spread" %in% names(monthly)) {
    monthly[, FRED_MRS := FRED_MRS +
              fifelse(!is.na(Term_Spread) & Term_Spread < 0, 15, 0)]
  }
  if ("HY_Spread" %in% names(monthly)) {
    monthly[, FRED_MRS := FRED_MRS +
              fifelse(!is.na(HY_Spread) & HY_Spread > 5.0, 15, 0)]
  }
  monthly <- monthly[, .(Date, YM, FRED_MRS)]
  cat(sprintf("[regime_signal] FRED robust MRS computed: %d months | %s ~ %s\n",
              nrow(monthly), min(monthly$Date), max(monthly$Date)))
  monthly
}


#==============================================================================
# 3. load_ktri_signal() — KTRI v3 csv → monthly KTRI/VEA
#==============================================================================

load_ktri_signal <- function() {
  # Search for KTRI v3 signals
  ktri_paths <- c(
    file.path(PROJECT_ROOT, "04_Regime_Engine/output/ktri_v3_signals.csv"),
    file.path(PROJECT_ROOT, "04_Research/regime_comparison/output/ktri_v3_signals.csv")
  )

  ktri_path <- ktri_paths[file.exists(ktri_paths)]
  if (length(ktri_path) == 0) {
    warning("[regime_signal] KTRI v3 signals not found. Layer 3 disabled.")
    return(data.table(Date = as.Date(character(0)),
                      YM = character(0),
                      KTRI_Score = numeric(0),
                      VEA_Score = numeric(0)))
  }

  daily <- fread(ktri_path[1])
  daily[, Date := as.Date(DATE)]
  daily <- daily[!is.na(KTRI)]

  # Aggregate to monthly: last trading day of month
  daily[, YM := format(Date, "%Y-%m")]
  monthly <- daily[, {
    last_row <- .SD[which.max(Date)]
    .(Date       = last_row$Date,
      KTRI_Score = last_row$KTRI,
      VEA_Score  = last_row$VEA)
  }, by = YM]

  setorder(monthly, Date)
  cat(sprintf("[regime_signal] KTRI loaded: %d months | %s ~ %s\n",
              nrow(monthly), min(monthly$Date), max(monthly$Date)))
  monthly
}


#==============================================================================
# 4. compute_regime_score() — 3-Layer Cascade → Score 0-100
#==============================================================================
#
# Layer 1 (MSM):  base_score += 40 × min(1, Crisis_Prob / 0.8)
# Layer 2 (FRED): base_score += 0.35 × MRS
# Layer 3 (KTRI): +15 if (KTRI≤35 AND VEA≥70), +8 if one condition only
#
# Score 자연 상한: 40 + 35 + 15 = 90 (전 Layer 극단 동시 발동)
# 실전 상한: ~75-85 (GFC/COVID급)
#==============================================================================

compute_regime_score <- function(msm_prob, fred_mrs, ktri_score, vea_score) {
  # Handle NAs — missing layer contributes 0
  msm_prob   <- fifelse(is.na(msm_prob),   0, msm_prob)
  fred_mrs   <- fifelse(is.na(fred_mrs),   0, fred_mrs)
  ktri_score <- fifelse(is.na(ktri_score), 50, ktri_score)  # neutral default

vea_score  <- fifelse(is.na(vea_score),  50, vea_score)   # neutral default

  # Layer 1: MSM Detection (max 40 pts)
  layer1 <- 40 * pmin(1, msm_prob / 0.8)

  # Layer 2: FRED Confirmation (max 35 pts)
  layer2 <- 0.35 * fred_mrs

  # Layer 3: KTRI + VEA Validation (max 15 pts)
  ktri_alert <- ktri_score <= 35
  vea_alert  <- vea_score >= 70
  layer3 <- fifelse(ktri_alert & vea_alert, 15,
                    fifelse(ktri_alert | vea_alert, 8, 0))

  score <- layer1 + layer2 + layer3

  # Clamp to [0, 100]
  pmin(100, pmax(0, score))
}


#==============================================================================
# 5. classify_regime_category() — Score → Category
#==============================================================================

classify_regime_category <- function(score) {
  fifelse(score >= 70, "RISK_OFF",
          fifelse(score >= 45, "CAUTION",
                  fifelse(score >= 25, "NEUTRAL", "RISK_ON")))
}


#==============================================================================
# 6. get_cash_allocation() — Score → Graduated Cash %
#    L-06 교훈 반영: elevated 과잉 캐시아웃 방지, crisis만 high cash
#==============================================================================

get_cash_allocation <- function(score) {
  fifelse(
    score >= 70, 0.50 + 0.50 * pmin(1, (score - 70) / 30),
    fifelse(
      score >= 45, 0.15 + 0.20 * (score - 45) / 25,
      0
    )
  )
}


#==============================================================================
# 7. get_factor_adjustments() — Category → Factor Weight Delta
#==============================================================================
#
# Returns named list of factor weight adjustments (additive deltas)
# LowVol↑ Quality↑ in risk-off; Mom↑ Value↑ in risk-on
#==============================================================================

get_factor_adjustments <- function(category) {
  adj <- data.table(
    Category = c("RISK_OFF", "CAUTION", "NEUTRAL", "RISK_ON"),
    fw_Mom    = c(-0.15, -0.05,  0.00,  0.10),
    fw_LowVol = c( 0.20,  0.10,  0.00, -0.05),
    fw_Quality = c( 0.10,  0.05,  0.00,  0.00),
    fw_Value  = c(-0.10, -0.05,  0.00,  0.10)
  )

  # Vectorized merge
  input_dt <- data.table(Category = category)
  result <- merge(input_dt, adj, by = "Category", all.x = TRUE, sort = FALSE)

  # Fill NA (unknown category) with neutral
  for (col in c("fw_Mom", "fw_LowVol", "fw_Quality", "fw_Value")) {
    set(result, which(is.na(result[[col]])), col, 0)
  }

  result
}


#==============================================================================
# 8. build_regime_signal_table() — 전체 파이프라인
#    load → merge → score → classify → save
#==============================================================================

build_regime_signal_table <- function(save_path = NULL) {
  cat("═══════════════════════════════════════════════════\n")
  cat("[regime_signal] Building Unified 3-Layer Cascade\n")
  cat("═══════════════════════════════════════════════════\n\n")

  # ── Load all 3 layers ──
  msm_dt  <- load_msm_signal()
  fred_dt <- load_fred_signal()
  ktri_dt <- load_ktri_signal()

  cat("\n[regime_signal] Merging layers on YM...\n")

  # ── Build base timeline from all sources ──
  all_ym <- sort(unique(c(msm_dt$YM, fred_dt$YM, ktri_dt$YM)))
  base <- data.table(YM = all_ym)

  # Merge MSM
  if (nrow(msm_dt) > 0) {
    base <- merge(base, msm_dt[, .(YM, MSM_Crisis_Prob)],
                  by = "YM", all.x = TRUE)
  } else {
    base[, MSM_Crisis_Prob := NA_real_]
  }

  # Merge FRED
  if (nrow(fred_dt) > 0) {
    base <- merge(base, fred_dt[, .(YM, FRED_MRS)],
                  by = "YM", all.x = TRUE)
  } else {
    base[, FRED_MRS := NA_real_]
  }

  # Merge KTRI
  if (nrow(ktri_dt) > 0) {
    base <- merge(base, ktri_dt[, .(YM, KTRI_Score, VEA_Score)],
                  by = "YM", all.x = TRUE)
  } else {
    base[, KTRI_Score := NA_real_]
    base[, VEA_Score := NA_real_]
  }

  # ── Reconstruct Date (month-end) ──
  base[, Date := as.Date(paste0(YM, "-01"))]
  base[, Date := as.Date(cut(Date + 31, "month")) - 1]  # last day of month
  setorder(base, Date)

  # ── LOCF: carry forward last available value for missing months ──
  # FRED starts ~2000-01, KTRI has gaps → use last observation carried forward
  locf_cols <- c("FRED_MRS", "KTRI_Score", "VEA_Score")
  for (col in locf_cols) {
    if (col %in% names(base)) setnafill(base, type = "locf", cols = col)
  }
  n_filled <- sum(!is.na(base$FRED_MRS)) - nrow(fred_dt)
  if (n_filled > 0) cat(sprintf("[regime_signal] LOCF filled: FRED %d months\n", n_filled))

  # ── Layer alerts ──
  base[, Layer1_Alert := (!is.na(MSM_Crisis_Prob) & MSM_Crisis_Prob >= 0.50)]
  base[, Layer2_Alert := (!is.na(FRED_MRS) & FRED_MRS >= 30)]
  base[, Layer3_Alert := (!is.na(KTRI_Score) & KTRI_Score <= 35 &
                           !is.na(VEA_Score) & VEA_Score >= 70)]

  # ── Compute score ──
  base[, Regime_Score := compute_regime_score(
    MSM_Crisis_Prob, FRED_MRS, KTRI_Score, VEA_Score
  )]

  # ── Category ──
  base[, Category := classify_regime_category(Regime_Score)]

  # ── Cash allocation ──
  base[, Cash_Pct := get_cash_allocation(Regime_Score)]

  # ── Factor adjustments ──
  adj <- get_factor_adjustments(base$Category)
  base[, fw_Mom     := adj$fw_Mom]
  base[, fw_LowVol  := adj$fw_LowVol]
  base[, fw_Quality := adj$fw_Quality]
  base[, fw_Value   := adj$fw_Value]

  # ── Select and order final columns ──
  final_cols <- c("Date", "YM",
                  "MSM_Crisis_Prob", "FRED_MRS", "KTRI_Score", "VEA_Score",
                  "Layer1_Alert", "Layer2_Alert", "Layer3_Alert",
                  "Regime_Score", "Category", "Cash_Pct",
                  "fw_Mom", "fw_LowVol", "fw_Quality", "fw_Value")
  signal_dt <- base[, ..final_cols]

  # ── Summary ──
  cat("\n[regime_signal] ═══ Distribution ═══\n")
  cat_summary <- signal_dt[, .N, by = Category]
  cat_summary[, Pct := round(N / sum(N) * 100, 1)]
  print(cat_summary)

  cat(sprintf("\n[regime_signal] Score stats: mean=%.1f, median=%.1f, max=%.1f\n",
              mean(signal_dt$Regime_Score, na.rm = TRUE),
              median(signal_dt$Regime_Score, na.rm = TRUE),
              max(signal_dt$Regime_Score, na.rm = TRUE)))

  cat(sprintf("[regime_signal] Layer coverage: MSM %d, FRED %d, KTRI %d months\n",
              sum(!is.na(signal_dt$MSM_Crisis_Prob)),
              sum(!is.na(signal_dt$FRED_MRS)),
              sum(!is.na(signal_dt$KTRI_Score))))

  # ── Save ──
  if (is.null(save_path)) {
    save_path <- if (exists("REGIME_SIGNAL_CACHE")) {
      REGIME_SIGNAL_CACHE
    } else {
      file.path(CACHE_DIR, "unified_regime_signal.parquet")
    }
  }
  dir.create(dirname(save_path), recursive = TRUE, showWarnings = FALSE)
  write_parquet(signal_dt, save_path)
  cat(sprintf("\n[regime_signal] Saved: %s (%d rows)\n", save_path, nrow(signal_dt)))

  # Also save to regime_comparison output for research
  research_path <- file.path(RESEARCH_OUTPUT,
                             "regime_comparison/output/unified_regime_signal.parquet")
  dir.create(dirname(research_path), recursive = TRUE, showWarnings = FALSE)
  write_parquet(signal_dt, research_path)

  cat("\n═══════════════════════════════════════════════════\n")
  cat("[regime_signal] Build complete.\n")
  cat("═══════════════════════════════════════════════════\n")

  invisible(signal_dt)
}


#==============================================================================
# 9. load_regime_signal() — 캐시 로드
#==============================================================================

load_regime_signal <- function() {
  cache_path <- if (exists("REGIME_SIGNAL_CACHE")) {
    REGIME_SIGNAL_CACHE
  } else {
    file.path(CACHE_DIR, "unified_regime_signal.parquet")
  }

  if (!file.exists(cache_path)) {
    cat("[regime_signal] Cache not found. Running build_regime_signal_table()...\n")
    return(build_regime_signal_table())
  }

  dt <- as.data.table(read_parquet(cache_path))
  dt[, Date := as.Date(Date)]
  setorder(dt, Date)

  cat(sprintf("[regime_signal] Loaded: %d months | %s ~ %s\n",
              nrow(dt), min(dt$Date), max(dt$Date)))
  dt
}


#==============================================================================
# 10. get_regime_at_date() — 특정 날짜의 국면 조회
#==============================================================================
#
# Rolling lookup: sig_date 이전 가장 가까운 월의 국면 반환
# Returns: 1-row data.table with all regime columns
#==============================================================================

get_regime_at_date <- function(date, signal_dt = NULL) {
  if (is.null(signal_dt)) signal_dt <- load_regime_signal()

  date <- as.Date(date)
  row <- signal_dt[Date <= date]

  if (nrow(row) == 0) {
    # Before any data — return neutral defaults
    return(data.table(
      Date = date, YM = format(date, "%Y-%m"),
      MSM_Crisis_Prob = NA_real_, FRED_MRS = NA_real_,
      KTRI_Score = NA_real_, VEA_Score = NA_real_,
      Layer1_Alert = FALSE, Layer2_Alert = FALSE, Layer3_Alert = FALSE,
      Regime_Score = 0, Category = "NEUTRAL",
      Cash_Pct = 0,
      fw_Mom = 0, fw_LowVol = 0, fw_Quality = 0, fw_Value = 0
    ))
  }

  row[.N]  # latest row on or before date
}


#==============================================================================
# 11. merge_regime_signal() — 전략 FACTORS에 rolling join
#==============================================================================
#
# FACTORS: data.table(Date, Ticker, Score, ...)
# signal_dt: output of load_regime_signal()
#
# Returns: FACTORS with added regime columns (Regime_Score, Category,
#          Cash_Pct, fw_Mom, fw_LowVol, fw_Quality, fw_Value)
#==============================================================================

merge_regime_signal <- function(FACTORS, signal_dt = NULL) {
  if (is.null(signal_dt)) signal_dt <- load_regime_signal()

  if (nrow(signal_dt) == 0) {
    cat("[regime_signal] Empty signal table. FACTORS unchanged.\n")
    return(FACTORS)
  }

  # Prepare for rolling join
  regime_join <- signal_dt[, .(Date, Regime_Score, Category, Cash_Pct,
                                fw_Mom, fw_LowVol, fw_Quality, fw_Value)]
  setkey(regime_join, Date)

  # Unique dates from FACTORS
  sig_dates <- sort(unique(FACTORS$Date))
  date_dt <- data.table(Date = sig_dates)
  setkey(date_dt, Date)

  # Rolling join: each FACTORS date picks up latest regime on or before
  matched <- regime_join[date_dt, roll = TRUE]

  # Remove any existing regime columns in FACTORS to avoid conflict
  regime_cols <- c("Regime_Score", "Category", "Cash_Pct",
                   "fw_Mom", "fw_LowVol", "fw_Quality", "fw_Value")
  existing <- intersect(names(FACTORS), regime_cols)
  if (length(existing) > 0) {
    FACTORS[, (existing) := NULL]
  }

  # Merge back
  FACTORS <- merge(FACTORS, matched, by = "Date", all.x = TRUE)

  n_matched <- sum(!is.na(FACTORS$Regime_Score))
  n_total <- uniqueN(FACTORS$Date)
  cat(sprintf("[regime_signal] Merged: %d/%d signal dates matched (%.1f%%)\n",
              sum(!is.na(matched$Regime_Score)), n_total,
              sum(!is.na(matched$Regime_Score)) / n_total * 100))

  FACTORS
}


#==============================================================================
# 12. Stress Period Spot-Check — 검증용 유틸리티
#==============================================================================

spot_check_stress_periods <- function(signal_dt = NULL) {
  if (is.null(signal_dt)) signal_dt <- load_regime_signal()

  stress <- list(
    GFC_2008    = c("2008-06", "2009-03"),
    COVID_2020  = c("2020-01", "2020-06"),
    Rate_2022   = c("2022-01", "2022-10")
  )

  cat("\n[regime_signal] ═══ Stress Period Spot-Check ═══\n\n")

  for (name in names(stress)) {
    period <- stress[[name]]
    rows <- signal_dt[YM >= period[1] & YM <= period[2]]
    if (nrow(rows) == 0) {
      cat(sprintf("  %s: NO DATA\n", name))
      next
    }

    cat(sprintf("  ── %s (%s ~ %s) ──\n", name, period[1], period[2]))
    cat(sprintf("    Months: %d\n", nrow(rows)))
    cat(sprintf("    Avg Score: %.1f | Max Score: %.1f\n",
                mean(rows$Regime_Score), max(rows$Regime_Score)))
    cat(sprintf("    Category: %s\n",
                paste(rows[, .N, by = Category][, sprintf("%s(%d)", Category, N)],
                      collapse = ", ")))
    cat(sprintf("    Avg Cash%%: %.1f%%\n",
                mean(rows$Cash_Pct) * 100))
    cat(sprintf("    L1 alerts: %d | L2: %d | L3: %d\n",
                sum(rows$Layer1_Alert), sum(rows$Layer2_Alert),
                sum(rows$Layer3_Alert)))

    # Show peak score month
    peak <- rows[which.max(Regime_Score)]
    cat(sprintf("    Peak: %s Score=%.1f (%s) Cash=%.0f%%\n",
                peak$YM, peak$Regime_Score, peak$Category,
                peak$Cash_Pct * 100))
    cat("\n")
  }
}


#==============================================================================
# 13. compute_bcs_daily() — Behavioral Composite Score (Daily)
#==============================================================================
#
# BCS v2: VIX_Chg3(40%) + Complacency(25%) + MultiDanger(15%) + PutOI(20%)
# r = -0.143 with Fwd_1M, Q1-Q5 = 2.52%/mo
# Orthogonal to Cascade (r=0.07)
# Leads: COVID +80d, Rate Shock +181d, 2015 China +83d, 2011 EU +84d
#==============================================================================

compute_bcs_daily <- function() {
  cat("[regime_signal] Computing BCS daily signal...\n")

  # ── Load data ──
  fred_path <- file.path(CACHE_DIR, "macro_fred.parquet")
  bm_path   <- file.path(CACHE_DIR, "benchmark.parquet")
  drv_path  <- file.path(RESEARCH_OUTPUT,
                          "regime_comparison/output/derivatives_indicators_daily.parquet")

  if (!file.exists(drv_path)) {
    warning("[regime_signal] Derivatives data not found: ", drv_path)
    return(data.table(Date = as.Date(character(0)),
                      BCS = numeric(0), BCS_Q = character(0)))
  }

  # Load and merge
  fred_wide <- dcast(as.data.table(read_parquet(fred_path)),
                      Date ~ Series, value.var = "Value")
  fred_wide[, Date := as.Date(Date)]
  bm <- as.data.table(read_parquet(bm_path))
  bm[, Date := as.Date(Date)]
  drv <- as.data.table(read_parquet(drv_path))
  drv[, Date := as.Date(Date)]

  dt <- merge(bm[, .(Date, BM_Ret)], fred_wide, by = "Date", all.x = TRUE)
  dt <- merge(dt, drv[, .(Date, PCR_OI, IV_Put_ATM, K200_Basis_Pct,
                            Put_OI, Call_OI, K200_Fut_OI)],
              by = "Date", all.x = TRUE)
  setorder(dt, Date)

  # LOCF fill
  fill_cols <- intersect(names(dt),
    c("VIX","HY_Spread","KRW_USD","Term_Spread","PCR_OI","IV_Put_ATM","Put_OI","Call_OI"))
  for (col in fill_cols) setnafill(dt, type = "locf", cols = col)

  # ── Component 1: VIX 3d change (40%) ──
  dt[, VIX_Chg3 := VIX - shift(VIX, 3)]
  dt[, VIX_Chg3_pct := frank(VIX_Chg3, na.last = "keep") / sum(!is.na(VIX_Chg3))]

  # ── Component 2: Complacency (25%) ──
  dt[, PCR_Z120 := (PCR_OI - frollmean(PCR_OI, n = 120, align = "right")) /
                    pmax(frollapply(PCR_OI, n = 120, FUN = sd, align = "right"), 0.01)]
  dt[, IV_Z120 := (IV_Put_ATM - frollmean(IV_Put_ATM, n = 120, align = "right")) /
                   pmax(frollapply(IV_Put_ATM, n = 120, FUN = sd, align = "right"), 0.01)]
  dt[, Complacency := -PCR_Z120 - IV_Z120]
  dt[, Complacency_pct := frank(Complacency, na.last = "keep") / sum(!is.na(Complacency))]

  # ── Component 3: Multi-market danger (15%) ──
  dt[, VIX_Chg20 := VIX - shift(VIX, 20)]
  dt[, d_VIX_rise := fifelse(!is.na(VIX_Chg20) & VIX_Chg20 > 5, 1L, 0L)]
  dt[, d_HY_widen := fifelse(!is.na(HY_Spread) & !is.na(shift(HY_Spread, 20)) &
                              (HY_Spread - shift(HY_Spread, 20)) > 0.5, 1L, 0L)]
  dt[, d_KRW_weak := fifelse(!is.na(KRW_USD) & !is.na(shift(KRW_USD, 20)) &
                              (KRW_USD/shift(KRW_USD, 20)-1) > 0.03, 1L, 0L)]
  dt[, d_YC_invert := fifelse(!is.na(Term_Spread) & Term_Spread < 0, 1L, 0L)]
  dt[, MultiDanger := d_VIX_rise + d_HY_widen + d_KRW_weak + d_YC_invert]
  dt[, MultiDanger_pct := MultiDanger / 4]

  # ── Component 4: Put OI hedging pressure (20%) ──
  dt[, Put_OI_Chg20 := Put_OI / shift(Put_OI, 20) - 1]
  dt[, Put_OI_Chg_pct := frank(Put_OI_Chg20, na.last = "keep") / sum(!is.na(Put_OI_Chg20))]

  # ── BCS v2: 40/25/15/20 weighting ──
  dt[, BCS := fifelse(
    !is.na(VIX_Chg3_pct) & !is.na(Complacency_pct) & !is.na(Put_OI_Chg_pct),
    0.40 * VIX_Chg3_pct + 0.25 * Complacency_pct +
      0.15 * MultiDanger_pct + 0.20 * Put_OI_Chg_pct,
    NA_real_)]

  # ── Quintile classification ──
  bcs_breaks <- quantile(dt$BCS, seq(0, 1, 0.2), na.rm = TRUE)
  dt[, BCS_Q := cut(BCS, breaks = bcs_breaks, include.lowest = TRUE,
                     labels = c("Q1","Q2","Q3","Q4","Q5"))]

  out <- dt[!is.na(BCS), .(Date, VIX_Chg3, Complacency, MultiDanger,
                             Put_OI_Chg20, BCS, BCS_Q)]
  cat(sprintf("[regime_signal] BCS computed: %d days (%s ~ %s)\n",
              nrow(out), min(out$Date), max(out$Date)))
  out
}


#==============================================================================
# 14. load_bcs_signal() — BCS daily signal 로드 (캐시 우선)
#==============================================================================

load_bcs_signal <- function(recompute = FALSE) {
  bcs_path <- file.path(RESEARCH_OUTPUT,
                         "regime_comparison/output/bcs_daily_signal.parquet")

  if (!recompute && file.exists(bcs_path)) {
    dt <- as.data.table(read_parquet(bcs_path))
    dt[, Date := as.Date(Date)]
    setorder(dt, Date)
    cat(sprintf("[regime_signal] BCS loaded (cached): %d days (%s ~ %s)\n",
                nrow(dt), min(dt$Date), max(dt$Date)))
    return(dt)
  }

  dt <- compute_bcs_daily()
  if (nrow(dt) > 0) {
    bcs_dir <- dirname(bcs_path)
    dir.create(bcs_dir, recursive = TRUE, showWarnings = FALSE)
    write_parquet(dt, bcs_path)
    cat(sprintf("[regime_signal] BCS saved: %s\n", bcs_path))
  }
  dt
}


#==============================================================================
# 15. get_bcs_cash_overlay() — BCS Quintile → 추가 현금 비중
#==============================================================================
#
# Q5(danger) → +15% cash, Q4 → +5% cash, else → 0
# Cascade Cash_Pct에 additive로 적용 (pmin(1, ...))
#==============================================================================

get_bcs_cash_overlay <- function(bcs_q) {
  fifelse(is.na(bcs_q), 0,
    fifelse(bcs_q == "Q5", 0.15,
      fifelse(bcs_q == "Q4", 0.05, 0)))
}


#==============================================================================
# 16. merge_regime_with_bcs() — 전략에 Cascade + BCS 동시 적용
#==============================================================================
#
# FACTORS: data.table(Date, Ticker, Score, ...)
# Returns: FACTORS with Regime_Score, Category, Cash_Pct (cascade),
#          BCS, BCS_Q, BCS_Cash_Overlay, Total_Cash_Pct
#==============================================================================

merge_regime_with_bcs <- function(FACTORS, signal_dt = NULL, bcs_dt = NULL) {
  # Cascade merge
  FACTORS <- merge_regime_signal(FACTORS, signal_dt)

  # Load BCS
  if (is.null(bcs_dt)) bcs_dt <- load_bcs_signal()

  if (nrow(bcs_dt) == 0) {
    cat("[regime_signal] No BCS data. Returning cascade-only.\n")
    FACTORS[, BCS := NA_real_]
    FACTORS[, BCS_Q := NA_character_]
    FACTORS[, BCS_Cash_Overlay := 0]
    FACTORS[, Total_Cash_Pct := Cash_Pct]
    return(FACTORS)
  }

  # Monthly aggregation of BCS: last value of month
  bcs_dt[, YM := format(Date, "%Y-%m")]
  bcs_monthly <- bcs_dt[, .(BCS = tail(BCS, 1),
                              BCS_Q = as.character(tail(BCS_Q, 1))),
                          by = YM]

  # Remove existing BCS columns if any
  for (col in c("BCS","BCS_Q","BCS_Cash_Overlay","Total_Cash_Pct")) {
    if (col %in% names(FACTORS)) FACTORS[, (col) := NULL]
  }

  # Derive YM from FACTORS Date
  if (!"YM" %in% names(FACTORS)) FACTORS[, YM := format(Date, "%Y-%m")]

  FACTORS <- merge(FACTORS, bcs_monthly, by = "YM", all.x = TRUE)

  # Compute overlay
  FACTORS[, BCS_Cash_Overlay := get_bcs_cash_overlay(BCS_Q)]
  FACTORS[, Total_Cash_Pct := pmin(1, fifelse(is.na(Cash_Pct), 0, Cash_Pct) +
                                       BCS_Cash_Overlay)]

  n_bcs <- sum(!is.na(FACTORS$BCS))
  cat(sprintf("[regime_signal] BCS overlay merged: %d/%d dates with BCS\n",
              n_bcs, nrow(FACTORS)))

  FACTORS
}


cat("[regime_signal] Loaded (v1.1). Functions:\n")
cat("  build_regime_signal_table()     — full cascade pipeline → parquet\n")
cat("  load_regime_signal()            — load cascade cache\n")
cat("  get_regime_at_date(date)        — single date lookup\n")
cat("  merge_regime_signal(FACTORS)    — cascade rolling join\n")
cat("  spot_check_stress_periods()     — GFC/COVID/Rate stress test\n")
cat("  compute_bcs_daily()             — build BCS daily signal\n")
cat("  load_bcs_signal()               — load BCS daily cache\n")
cat("  get_bcs_cash_overlay(bcs_q)     — BCS Q → cash overlay\n")
cat("  merge_regime_with_bcs(FACTORS)  — cascade + BCS combined\n")
