cat("=== STR_1631 PG2 MDD Optimization: Path B/C/D/E/VD+ Additional Variants ===\n")
## 핵심 아이디어: V1 Enhanced Regime 기반 + VT/DD 파라미터 탐색
##   V_B:  V1 + Vol Target 18% (V2의 15%보다 느슨, CAGR 보존 기대)
##   V_C:  V1 + DD Brake 8/20 (V3의 5/15보다 느슨, whipsaw 감소 기대)
##   V_D:  V1 + DD Brake 10/25 (더 느슨한 trigger, 방어성 약화 대신 CAGR 보존)
##   V_E:  V1 + Vol Target 20% (매우 느슨한 VT, CAGR 극대화 실험)
##   VD+:  V1 Enhanced Regime (Caution MRS 25→20 강화) + DD Brake 10/25
##         목표: MDD 26.1%(VD) → 25.0% 달성
##         Crisis:  40% factor + 30% inverse + 30% cash (VD와 동일)
##         Caution: inverse 10% 배분 (MRS threshold만 20으로 강화)
## PIT: C5 (overlay t-1 lag), C9 (DD t-1 lag), regime t-1 기반 MRS 사용
## 데이터 재활용: daily_nav_comparison.csv (V0/V1/V3 포함) 로드 → 재계산 없음
## Ref: run_all.R V1 구조 기반, Caution threshold 조정만 상이

t0 <- Sys.time()

# ===================================================================
# 0. Environment Setup
# ===================================================================
.root_candidates <- c(
  "/mnt/c/Users/User/OneDrive/\xeb\xb0\x94\xed\x83\x95 \xed\x99\x94\xeb\xa9\xb4/Quant_Module_Moltbot",
  "/mnt/c/Users/99922/OneDrive/\xeb\xb0\x94\xed\x83\x95 \xed\x99\x94\xeb\xa9\xb4/Quant_Module_Moltbot"
)
PROJECT_ROOT <- .root_candidates[sapply(.root_candidates, dir.exists)][1]
rm(.root_candidates)

FUNC_PATH <- file.path(PROJECT_ROOT, "02_Infrastructure")
STRAT_DIR <- tryCatch(dirname(sys.frame(1)$ofile), error = function(e) getwd())
OUT_DIR   <- file.path(STRAT_DIR, "output")
dir.create(OUT_DIR, showWarnings = FALSE, recursive = TRUE)

source(file.path(FUNC_PATH, "config.R"))

suppressPackageStartupMessages({
  library(data.table); library(xts); library(zoo)
  library(PerformanceAnalytics); library(ggplot2); library(scales)
  library(jsonlite); library(lubridate)
})
options(scipen = 999); Sys.setenv(TZ = "Asia/Seoul")

source(file.path(FUNC_PATH, "backtest_harness.R"))

# ===================================================================
# 1. Load existing daily NAV from prior run_all.R output
# ===================================================================
cat("\n[Step 1] Loading existing daily_nav_comparison.csv...\n")

CSV_PATH <- file.path(OUT_DIR, "daily_nav_comparison.csv")
if (!file.exists(CSV_PATH)) stop("daily_nav_comparison.csv not found. Run run_all.R first.")

nd <- fread(CSV_PATH)
nd[, Date := as.Date(Date)]
setkey(nd, Date)

cat(sprintf("  Loaded %d rows | %s ~ %s\n",
  nrow(nd), min(nd$Date), max(nd$Date)))

# Verify required columns
req_cols <- c("Date", "Strategy_Ret", "MRS", "n_axes_firing",
              "Ret_v0", "NAV_v0", "Layer_v0",
              "Ret_v1", "NAV_v1", "Layer_v1",
              "vol_scale",  # from V2 computation (expanding vol t-1)
              "dd_exposure")  # from V3 computation
missing <- setdiff(req_cols, names(nd))
if (length(missing) > 0) stop(paste("Missing columns:", paste(missing, collapse = ", ")))

# Also need Ret_Inv for regime overlay — reconstruct from BM if needed
# V1 uses Ret_Inv internally; we need to reconstruct
# Load BM and Inverse ETF
cat("[Step 1b] Loading BM + Inverse ETF for Ret_Inv...\n")
res <- load_rawdata(use_cache = TRUE)
BM_DT <- res$BM_DT; rm(res); gc(verbose = FALSE)
BM_DT[, Date := as.Date(Date)]

ip <- file.path(PROJECT_ROOT, ".cache/kodex_inverse_114800.csv")
ID <- if (file.exists(ip)) {
  dt <- fread(ip); dt[, Date := as.Date(Date)]; setkey(dt, Date); dt
} else NULL

nd <- merge(nd, BM_DT[, .(Date, BM_Ret)], by = "Date", all.x = TRUE)
if (!is.null(ID)) {
  nd <- merge(nd, ID[, .(Date, Ret_Inv)], by = "Date", all.x = TRUE)
  nd[is.na(Ret_Inv), Ret_Inv := -BM_Ret]
} else nd[, Ret_Inv := -BM_Ret]
nd[is.na(Ret_Inv), Ret_Inv := 0]

# Remove duplicate BM_Ret if already present from CSV
if ("BM_Ret.x" %in% names(nd)) nd[, BM_Ret := BM_Ret.x]
setkey(nd, Date)
gc(verbose = FALSE)

cat(sprintf("  nd ready: %d rows\n", nrow(nd)))

# ===================================================================
# Helper: summarise_perf wrapper
# ===================================================================
perf_fn <- function(ret_vec, label) {
  rx <- xts(ret_vec, order.by = nd$Date); names(rx) <- "Strategy"
  summarise_perf(rx, label)
}

# ===================================================================
# 2. VARIANT B: V1 Enhanced Regime + Vol Target 18%
#    - Same V1 regime logic (Layer_v1 / Ret_v1 already in nd)
#    - Apply VT 18% on top of V1 return
#    - C9: use vol_scale_18 = t-1 lagged expanding vol scaled to 18%
# ===================================================================
cat("\n[Step 2] Variant B: V1 + Vol Target 18%...\n")

VOL_TARGET_B <- 0.18
VOL_LOOKBACK <- 60L

# Compute expanding vol from Strategy_Ret (same base as V2)
# Note: vol_scale in nd was computed with VOL_TARGET=15%, need to recompute for 18%
nd[, base_vol_expanding_b := {
  n <- .N; vol <- rep(NA_real_, n)
  for (j in seq_len(n)) {
    if (j < VOL_LOOKBACK) { vol[j] <- NA_real_ }
    else { vol[j] <- sd(Strategy_Ret[1:j], na.rm = TRUE) * sqrt(252) }
  }
  vol
}]

# C9: t-1 lag
nd[, vol_scale_b := shift(
  fifelse(!is.na(base_vol_expanding_b) & base_vol_expanding_b > 0.01,
          pmin(VOL_TARGET_B / base_vol_expanding_b, 1.5),
          1.0),
  n = 1L, type = "lag")]
nd[is.na(vol_scale_b), vol_scale_b := 1.0]

# Apply VT on V1 return
nd[, Ret_vB := Ret_v1 * vol_scale_b]
nd[, NAV_vB := DEFAULT_INITIAL_CAPITAL * cumprod(1 + Ret_vB)]

cat(sprintf("  V_B: mean vol_scale_18=%.3f\n", mean(nd$vol_scale_b, na.rm = TRUE)))

# ===================================================================
# 3. VARIANT C: V1 Enhanced Regime + DD Brake 8/20
#    - Looser trigger than V3 (5/15) → fewer whipsaws, moderate protection
#    - DD on V1 NAV (not V0)
#    - C9: t-1 lag on dd_exposure
# ===================================================================
cat("\n[Step 3] Variant C: V1 + DD Brake 8/20...\n")

DD_TRIG_C  <- 0.08   # 8% drawdown triggers partial exit
DD_EXIT_C  <- 0.20   # 20% drawdown = zero exposure

nd[, running_max_v1 := cummax(NAV_v1)]
nd[, dd_pct_v1 := (NAV_v1 - running_max_v1) / running_max_v1]  # negative

nd[, dd_exposure_c := {
  exp_raw <- fifelse(dd_pct_v1 >= -DD_TRIG_C, 1.0,
                     fifelse(dd_pct_v1 <= -DD_EXIT_C, 0.0,
                             (dd_pct_v1 + DD_EXIT_C) / (DD_EXIT_C - DD_TRIG_C)))
  # C9: t-1 lag
  c(1.0, head(exp_raw, -1))
}]
nd[, Ret_vC := Ret_v1 * dd_exposure_c]
nd[, NAV_vC := DEFAULT_INITIAL_CAPITAL * cumprod(1 + Ret_vC)]

cat(sprintf("  V_C: mean dd_exposure_c=%.3f | 8/20 trigger\n",
  mean(nd$dd_exposure_c, na.rm = TRUE)))

# ===================================================================
# 4. VARIANT D: V1 Enhanced Regime + DD Brake 10/25
#    - Even looser trigger → minimal whipsaw, used as CAGR preservation check
#    - C9: t-1 lag on dd_exposure
# ===================================================================
cat("\n[Step 4] Variant D: V1 + DD Brake 10/25...\n")

DD_TRIG_D  <- 0.10   # 10% drawdown trigger
DD_EXIT_D  <- 0.25   # 25% drawdown = zero exposure

nd[, dd_exposure_d := {
  exp_raw <- fifelse(dd_pct_v1 >= -DD_TRIG_D, 1.0,
                     fifelse(dd_pct_v1 <= -DD_EXIT_D, 0.0,
                             (dd_pct_v1 + DD_EXIT_D) / (DD_EXIT_D - DD_TRIG_D)))
  # C9: t-1 lag
  c(1.0, head(exp_raw, -1))
}]
nd[, Ret_vD := Ret_v1 * dd_exposure_d]
nd[, NAV_vD := DEFAULT_INITIAL_CAPITAL * cumprod(1 + Ret_vD)]

cat(sprintf("  V_D: mean dd_exposure_d=%.3f | 10/25 trigger\n",
  mean(nd$dd_exposure_d, na.rm = TRUE)))

# ===================================================================
# 4b. VARIANT VD+: V1 Enhanced Regime (Caution MRS 20) + DD Brake 10/25
#     핵심: MRS Caution threshold 25 → 20으로 강화 → Caution 구간 더 일찍 진입
#     Crisis 배분: 40% factor + 30% inverse + 30% cash (VD와 동일)
#     Caution 배분: fw * factor + 10% inverse + (1-fw-0.10) * cash
#     DD Brake: entry 10%, exit 25% (VD와 동일)
#     PIT C5:  Regime Layer_vdp는 이미 t-1 lagged MRS 사용 (regime_engine_daily.R)
#     PIT C9:  dd_exposure_vdp = c(1.0, head(exp_raw, -1)) — t-1 lagged
# ===================================================================
cat("\n[Step 4b] Variant VD+: V1 Enhanced (Caution MRS=20) + DD Brake 10/25...\n")

CAUTION_THR_VDP <- 20L   # Caution threshold 강화: 25 → 20
DD_TRIG_VDP     <- 0.10  # DD Brake entry: 10% (VD와 동일)
DD_EXIT_VDP     <- 0.25  # DD Brake full exit: 25% (VD와 동일)

# --- Regime overlay (V1 구조와 동일, Caution threshold만 20으로 변경) ---
# C5: MRS는 regime_engine_daily.R이 이미 t-1 lag 적용한 값 → 추가 lag 불필요
nd[, crisis_flag_vdp := fifelse(MRS >= 55 & n_axes_firing >= 4, 1L, 0L)]
nd[, crisis_consec_vdp := {
  out <- integer(.N); cnt <- 0L
  for (j in seq_len(.N)) {
    if (nd$crisis_flag_vdp[j] == 1L) cnt <- cnt + 1L else cnt <- 0L
    out[j] <- cnt
  }
  out
}]
# Caution: MRS >= 20 (V1의 25 → 20 강화)
nd[, Layer_vdp := fifelse(crisis_consec_vdp >= 3L, 3L,
                           fifelse(MRS >= CAUTION_THR_VDP, 2L, 1L))]

nd[, Ret_vdp_regime := fcase(
  Layer_vdp == 1L, Strategy_Ret,
  Layer_vdp == 2L, {
    fw <- pmax(0.4, 1.0 - (MRS - CAUTION_THR_VDP) / 50)
    inv_w <- pmin(0.10, 1 - fw)
    fw * Strategy_Ret + inv_w * Ret_Inv + (1 - fw - inv_w) * 0
  },
  Layer_vdp == 3L, 0.40 * Strategy_Ret + 0.30 * Ret_Inv + 0.30 * 0
)]
nd[is.na(Ret_vdp_regime), Ret_vdp_regime := Strategy_Ret]

# NAV after regime overlay (intermediate, for DD computation)
nd[, NAV_vdp_regime := DEFAULT_INITIAL_CAPITAL * cumprod(1 + Ret_vdp_regime)]

# --- DD Brake 10/25 on top of VD+ regime NAV ---
# C9: t-1 lag on dd_exposure
nd[, running_max_vdp := cummax(NAV_vdp_regime)]
nd[, dd_pct_vdp := (NAV_vdp_regime - running_max_vdp) / running_max_vdp]  # negative

nd[, dd_exposure_vdp := {
  exp_raw <- fifelse(dd_pct_vdp >= -DD_TRIG_VDP, 1.0,
                     fifelse(dd_pct_vdp <= -DD_EXIT_VDP, 0.0,
                             (dd_pct_vdp + DD_EXIT_VDP) / (DD_EXIT_VDP - DD_TRIG_VDP)))
  # C9 CRITICAL: t-1 lag — today's exposure uses yesterday's drawdown signal
  c(1.0, head(exp_raw, -1))
}]

nd[, Ret_vdp := Ret_vdp_regime * dd_exposure_vdp]
nd[, NAV_vdp  := DEFAULT_INITIAL_CAPITAL * cumprod(1 + Ret_vdp)]

cat(sprintf("  VD+: Caution_thr=%d | DD_trig=%.0f%%/%.0f%%\n",
  CAUTION_THR_VDP, DD_TRIG_VDP * 100, DD_EXIT_VDP * 100))
cat(sprintf("  VD+: Normal=%.1f%% Caution=%.1f%% Crisis=%.1f%%\n",
  100 * mean(nd$Layer_vdp == 1), 100 * mean(nd$Layer_vdp == 2),
  100 * mean(nd$Layer_vdp == 3)))
cat(sprintf("  VD+: mean dd_exposure=%.3f\n", mean(nd$dd_exposure_vdp, na.rm = TRUE)))

# ===================================================================
# 5. VARIANT E: V1 Enhanced Regime + Vol Target 20%
#    - Very loose VT — minimal leverage cap, CAGR maximization test
#    - C9: t-1 lag
# ===================================================================
cat("\n[Step 5] Variant E: V1 + Vol Target 20%...\n")

VOL_TARGET_E <- 0.20

nd[, vol_scale_e := shift(
  fifelse(!is.na(base_vol_expanding_b) & base_vol_expanding_b > 0.01,
          pmin(VOL_TARGET_E / base_vol_expanding_b, 1.5),
          1.0),
  n = 1L, type = "lag")]
nd[is.na(vol_scale_e), vol_scale_e := 1.0]

nd[, Ret_vE := Ret_v1 * vol_scale_e]
nd[, NAV_vE := DEFAULT_INITIAL_CAPITAL * cumprod(1 + Ret_vE)]

cat(sprintf("  V_E: mean vol_scale_20=%.3f\n", mean(nd$vol_scale_e, na.rm = TRUE)))

# ===================================================================
# 6. Performance Comparison
# ===================================================================
cat("\n[Step 6] Performance Summary...\n")

p0   <- perf_fn(nd$Ret_v0,        "V0_Original")
p1   <- perf_fn(nd$Ret_v1,        "V1_EnhRegime")
p3   <- perf_fn(nd$Ret_v3,        "V3_DDBrake5_15")
pB   <- perf_fn(nd$Ret_vB,        "VB_V1+VT18")
pC   <- perf_fn(nd$Ret_vC,        "VC_V1+DD8_20")
pD   <- perf_fn(nd$Ret_vD,        "VD_V1+DD10_25")
pE   <- perf_fn(nd$Ret_vE,        "VE_V1+VT20")
pVDP <- perf_fn(nd$Ret_vdp,       "VDplus_MRS20+DD10_25")

cat("\n================================================================\n")
cat("   PG2 PATH B/C/D/E/VD+ — COMPARISON WITH BASELINE\n")
cat("================================================================\n")
cat("--- V0:  Original (baseline) ---\n");                  print(p0)
cat("--- V1:  Enhanced Regime (no overlay) ---\n");         print(p1)
cat("--- V3:  V0 + DD Brake 5/15 ---\n");                   print(p3)
cat("--- VB:  V1 + Vol Target 18% ---\n");                  print(pB)
cat("--- VC:  V1 + DD Brake 8/20 ---\n");                   print(pC)
cat("--- VD:  V1 + DD Brake 10/25 ---\n");                  print(pD)
cat("--- VE:  V1 + Vol Target 20% ---\n");                  print(pE)
cat("--- VD+: MRS Caution=20 + DD Brake 10/25 [TARGET] ---\n"); print(pVDP)

# ===================================================================
# 7. Compact summary table
# ===================================================================
cat("\n[Step 7] Compact comparison table...\n")

extract_row <- function(p, label) {
  nm <- names(p)
  # Try common field names from summarise_perf output
  get_field <- function(...) {
    for (f in c(...)) {
      idx <- which(nm == f)
      if (length(idx) > 0) return(as.numeric(p[idx]))
    }
    NA_real_
  }
  data.table(
    Variant  = label,
    CAGR     = get_field("CAGR", "Ann.Return", "Annualized Return"),
    SR       = get_field("Sharpe", "Sharpe Ratio", "SR"),
    MDD      = get_field("MDD", "Max.Drawdown", "Max Drawdown"),
    WinRate  = get_field("Win.Rate", "Win Rate", "WinRate")
  )
}

# Fallback: parse printed string to numeric
parse_perf_dt <- function(p_list, label) {
  vals <- as.numeric(unlist(p_list))
  nms  <- names(unlist(p_list))
  dt   <- as.data.table(as.list(setNames(vals, nms)))
  dt[, Variant := label]
  dt
}

# Build summary from perf objects (data.frame or named vector)
build_summary <- function(pobj, label) {
  df <- if (is.data.frame(pobj)) pobj else as.data.frame(t(pobj))
  nm <- tolower(gsub("[. ]", "_", names(df)))
  names(df) <- nm

  get_v <- function(...) {
    for (f in c(...)) {
      col <- grep(f, nm, value = TRUE, ignore.case = TRUE)[1]
      if (!is.na(col)) return(round(as.numeric(df[[col]]), 4))
    }
    NA_real_
  }
  # summarise_perf는 이미 % 단위 반환 (CAGR=22.53, MDD=33.86 등)
  # → * 100 하지 않음
  data.table(
    Variant  = label,
    CAGR_pct = round(get_v("cagr", "ann.*ret", "annualized"), 2),
    SR       = get_v("sharpe"),
    MDD_pct  = round(abs(get_v("mdd", "max.*draw", "maxdrawdown")), 2),
    WinRate  = round(get_v("win.*rate", "hitrate"), 2),
    Calmar   = round(get_v("calmar"), 3),
    WorstM   = round(get_v("worstmonth", "worst.*month"), 2)
  )
}

tbl <- tryCatch({
  rbindlist(list(
    build_summary(p0,   "V0_Original"),
    build_summary(p1,   "V1_EnhRegime"),
    build_summary(p3,   "V3_DD_5_15"),
    build_summary(pB,   "VB_VT18"),
    build_summary(pC,   "VC_DD_8_20"),
    build_summary(pD,   "VD_DD_10_25"),
    build_summary(pE,   "VE_VT20"),
    build_summary(pVDP, "VDplus_MRS20_DD10_25")
  ), fill = TRUE)
}, error = function(e) {
  cat("  [warn] build_summary failed:", conditionMessage(e), "\n")
  NULL
})

if (!is.null(tbl)) {
  cat("\n--- Compact Summary Table (incl. VD+) ---\n")
  print(tbl)
  cat("\nTarget: MDD <= 25%, CAGR >= 15%, SR >= 1.0\n")
  passed <- tbl[!is.na(MDD_pct) & MDD_pct <= 25.0 & !is.na(CAGR_pct) & CAGR_pct >= 15.0]
  if (nrow(passed) > 0) {
    cat("\n  *** [PASSED MDD+CAGR targets] ***\n")
    print(passed)
    # VD+ 달성 여부 별도 확인
    if ("VDplus_MRS20_DD10_25" %in% passed$Variant) {
      cat("\n  *** VD+ MDD 25% TARGET ACHIEVED ***\n")
    }
  } else {
    cat("\n  No variant fully satisfied MDD<=25% + CAGR>=15%\n")
    tbl[, mdd_gap  := pmax(0, MDD_pct - 25.0)]
    tbl[, cagr_gap := pmax(0, 15.0 - CAGR_pct)]
    tbl[, total_gap := mdd_gap + cagr_gap]
    setorder(tbl, total_gap)
    cat("  Closest variants:\n"); print(head(tbl, 4))
  }
  # VD vs VD+ explicit comparison
  vdp_row <- tbl[Variant == "VDplus_MRS20_DD10_25"]
  vd_row  <- tbl[Variant == "VD_DD_10_25"]
  if (nrow(vdp_row) > 0 && nrow(vd_row) > 0) {
    cat(sprintf("\n  VD  vs VD+ | MDD: %.2f%% vs %.2f%% | CAGR: %.2f%% vs %.2f%% | SR: %.3f vs %.3f\n",
      vd_row$MDD_pct, vdp_row$MDD_pct,
      vd_row$CAGR_pct, vdp_row$CAGR_pct,
      vd_row$SR, vdp_row$SR))
    cat(sprintf("  MDD delta: %.2f%% (VD+ - VD)\n", vdp_row$MDD_pct - vd_row$MDD_pct))
  }
}

# ===================================================================
# 8. Charts
# ===================================================================
cat("\n[Step 8] Generating charts...\n")

eq_dt <- nd[, .(Date,
  V0_Original      = NAV_v0,
  V1_EnhRegime     = NAV_v1,
  V3_DD_5_15       = NAV_v3,
  VB_VT18          = NAV_vB,
  VC_DD_8_20       = NAV_vC,
  VD_DD_10_25      = NAV_vD,
  VE_VT20          = NAV_vE,
  VDplus_MRS20_DD  = NAV_vdp)]
eq_long <- melt(eq_dt, id.vars = "Date", variable.name = "Variant", value.name = "NAV")

# Color palette
pal <- c(
  V0_Original     = "gray60",
  V1_EnhRegime    = "steelblue",
  V3_DD_5_15      = "darkgreen",
  VB_VT18         = "darkorange",
  VC_DD_8_20      = "firebrick",
  VD_DD_10_25     = "purple3",
  VE_VT20         = "darkturquoise",
  VDplus_MRS20_DD = "red2"    # 강조색: VD+ 목표 변형
)

g1 <- ggplot(eq_long, aes(x = Date, y = NAV, color = Variant,
                           linewidth = ifelse(Variant == "VDplus_MRS20_DD", 1.1, 0.55))) +
  geom_line() +
  scale_linewidth_identity() +
  scale_y_log10(labels = comma) +
  scale_color_manual(values = pal) +
  labs(title = "PG2 Path B/C/D/E/VD+: Equity Curves",
       subtitle = "VD+(red bold) = MRS Caution 20 + DD Brake 10/25 — MDD 25% target",
       x = NULL, y = "NAV (log scale)") +
  theme_minimal(base_size = 11) +
  theme(legend.position = "right")
ggsave(file.path(OUT_DIR, "equity_curve_bcde.png"), g1, width = 14, height = 7, dpi = 150)
cat("  Saved equity_curve_bcde.png\n")

# Drawdown chart
dd_fn <- function(nav) { rm_ <- cummax(nav); (nav - rm_) / rm_ * 100 }
dd_dt <- nd[, .(Date,
  V0_Original     = dd_fn(NAV_v0),
  V1_EnhRegime    = dd_fn(NAV_v1),
  V3_DD_5_15      = dd_fn(NAV_v3),
  VB_VT18         = dd_fn(NAV_vB),
  VC_DD_8_20      = dd_fn(NAV_vC),
  VD_DD_10_25     = dd_fn(NAV_vD),
  VE_VT20         = dd_fn(NAV_vE),
  VDplus_MRS20_DD = dd_fn(NAV_vdp))]
dd_long <- melt(dd_dt, id.vars = "Date", variable.name = "Variant", value.name = "Drawdown")

g2 <- ggplot(dd_long, aes(x = Date, y = Drawdown, color = Variant,
                           linewidth = ifelse(Variant == "VDplus_MRS20_DD", 1.0, 0.5))) +
  geom_line(alpha = 0.85) +
  scale_linewidth_identity() +
  geom_hline(yintercept = -25, linetype = "dashed", color = "red3", linewidth = 0.9) +
  annotate("text", x = min(dd_long$Date) + 400, y = -26.8,
           label = "MDD target -25%", color = "red3", size = 3.5, fontface = "bold") +
  scale_color_manual(values = pal) +
  labs(title = "PG2 Path B/C/D/E/VD+: Drawdown Comparison",
       subtitle = "VD+(red) = MRS Caution=20 + DD 10/25 | dashed = target boundary",
       x = NULL, y = "Drawdown (%)") +
  theme_minimal(base_size = 11) +
  theme(legend.position = "right")
ggsave(file.path(OUT_DIR, "drawdown_bcde.png"), g2, width = 14, height = 6, dpi = 150)
cat("  Saved drawdown_bcde.png\n")

# Annual returns — focus on key variants (VD, VD+, V1 비교)
ar_fn <- function(ret_vec, label) {
  rx <- xts(ret_vec, order.by = nd$Date)
  yr <- endpoints(rx, "years")
  ann <- period.apply(rx, yr, function(x) prod(1 + x) - 1)
  data.table(Year = year(index(ann)), Variant = label, AnnRet = as.numeric(ann) * 100)
}
ar_all <- rbindlist(list(
  ar_fn(nd$Ret_v1,   "V1_EnhRegime"),
  ar_fn(nd$Ret_vD,   "VD_DD_10_25"),
  ar_fn(nd$Ret_vdp,  "VDplus_MRS20_DD"),
  ar_fn(nd$Ret_vB,   "VB_VT18"),
  ar_fn(nd$Ret_vC,   "VC_DD_8_20"),
  ar_fn(nd$Ret_vE,   "VE_VT20")
))
pal_ar <- c(
  V1_EnhRegime     = "steelblue",
  VD_DD_10_25      = "purple3",
  VDplus_MRS20_DD  = "red2",
  VB_VT18          = "darkorange",
  VC_DD_8_20       = "firebrick",
  VE_VT20          = "darkturquoise"
)
g3 <- ggplot(ar_all, aes(x = factor(Year), y = AnnRet, fill = Variant)) +
  geom_bar(stat = "identity", position = position_dodge(width = 0.8), width = 0.72) +
  scale_fill_manual(values = pal_ar) +
  labs(title = "PG2 Path B/C/D/E/VD+: Annual Returns",
       subtitle = "VD+(red) vs VD(purple) vs V1(blue) — CAGR tradeoff check",
       x = "Year", y = "Return (%)") +
  theme_minimal(base_size = 11) +
  theme(axis.text.x = element_text(angle = 45, hjust = 1))
ggsave(file.path(OUT_DIR, "annual_returns_bcde.png"), g3, width = 14, height = 7, dpi = 150)
cat("  Saved annual_returns_bcde.png\n")

# VD vs VD+ focused chart (2-line comparison only)
ar_vd_vdp <- rbindlist(list(
  ar_fn(nd$Ret_v1,  "V1_EnhRegime"),
  ar_fn(nd$Ret_vD,  "VD_DD_10_25"),
  ar_fn(nd$Ret_vdp, "VDplus_MRS20_DD")
))
g4 <- ggplot(ar_vd_vdp, aes(x = factor(Year), y = AnnRet, fill = Variant)) +
  geom_bar(stat = "identity", position = position_dodge(width = 0.75), width = 0.7) +
  scale_fill_manual(values = c(V1_EnhRegime = "steelblue",
                                VD_DD_10_25 = "purple3",
                                VDplus_MRS20_DD = "red2")) +
  labs(title = "VD vs VD+ Annual Returns: MRS Caution 25 vs 20",
       subtitle = "VD+(red) = MRS Caution tightened to 20 | Same DD Brake 10/25",
       x = "Year", y = "Return (%)") +
  theme_minimal(base_size = 11) +
  theme(axis.text.x = element_text(angle = 45, hjust = 1))
ggsave(file.path(OUT_DIR, "annual_returns_vd_vs_vdplus.png"), g4, width = 12, height = 6, dpi = 150)
cat("  Saved annual_returns_vd_vs_vdplus.png\n")

# ===================================================================
# 9. Save JSON results
# ===================================================================
cat("\n[Step 9] Saving JSON...\n")

results_bcde <- list(
  task = "PG2_MDD_Optimization_PathBCDE_VDplus",
  base_variants_reference = "run_all.R (V0~V4)",
  target_mdd = 25.0,
  target_cagr = 15.0,
  pit_notes = list(
    C9_VT  = "vol_scale_b/e = shift(vol, n=1, lag) — expanding vol t-1 (C9)",
    C9_DD  = "dd_exposure = c(1.0, head(exp_raw, -1)) — t-1 lagged (C9)",
    C5     = "Regime overlay (Layer_v1/vdp) inherits t-1 from regime_engine_daily.R (C5)",
    C5_VDP = "VD+ MRS threshold changed (25->20) but still uses pre-existing t-1 lagged MRS"
  ),
  variants = list(
    VB = list(
      label      = "V1_Enhanced_Regime + Vol_Target_18pct",
      vol_tgt    = 0.18,
      dd_brake   = NULL,
      perf       = as.list(pB)
    ),
    VC = list(
      label      = "V1_Enhanced_Regime + DD_Brake_8_20",
      vol_tgt    = NULL,
      dd_trigger = 0.08,
      dd_exit    = 0.20,
      perf       = as.list(pC)
    ),
    VD = list(
      label      = "V1_Enhanced_Regime + DD_Brake_10_25",
      vol_tgt    = NULL,
      dd_trigger = 0.10,
      dd_exit    = 0.25,
      perf       = as.list(pD)
    ),
    VE = list(
      label      = "V1_Enhanced_Regime + Vol_Target_20pct",
      vol_tgt    = 0.20,
      dd_brake   = NULL,
      perf       = as.list(pE)
    ),
    VDplus = list(
      label             = "V1_Enhanced_Regime(Caution_MRS20) + DD_Brake_10_25",
      caution_threshold = 20L,
      crisis_alloc      = list(factor = 0.40, inverse = 0.30, cash = 0.30),
      caution_inverse   = 0.10,
      dd_trigger        = 0.10,
      dd_exit           = 0.25,
      pit_c5            = "MRS t-1 lagged (regime_engine_daily.R)",
      pit_c9            = "dd_exposure_vdp = c(1.0, head(exp_raw,-1))",
      regime_stats = list(
        normal_pct  = round(100 * mean(nd$Layer_vdp == 1), 1),
        caution_pct = round(100 * mean(nd$Layer_vdp == 2), 1),
        crisis_pct  = round(100 * mean(nd$Layer_vdp == 3), 1),
        mean_dd_exp = round(mean(nd$dd_exposure_vdp, na.rm = TRUE), 3)
      ),
      perf = as.list(pVDP)
    )
  ),
  overlay_stats = list(
    VB_mean_vol_scale    = round(mean(nd$vol_scale_b,    na.rm = TRUE), 3),
    VC_mean_dd_exposure  = round(mean(nd$dd_exposure_c,  na.rm = TRUE), 3),
    VD_mean_dd_exposure  = round(mean(nd$dd_exposure_d,  na.rm = TRUE), 3),
    VE_mean_vol_scale    = round(mean(nd$vol_scale_e,    na.rm = TRUE), 3),
    VDp_mean_dd_exposure = round(mean(nd$dd_exposure_vdp, na.rm = TRUE), 3)
  ),
  summary_table = if (!is.null(tbl)) as.list(tbl) else NULL,
  run_time_sec  = as.numeric(difftime(Sys.time(), t0, units = "secs"))
)
write_json(results_bcde, file.path(OUT_DIR, "pg2_bcde_comparison.json"),
           pretty = TRUE, auto_unbox = TRUE)
cat("  Saved pg2_bcde_comparison.json\n")

# Save extended daily CSV (VD+ columns appended)
fwrite(nd[, .(Date, Strategy_Ret, MRS, Layer_v1,
              Ret_v0, NAV_v0, Ret_v1, NAV_v1, Ret_v3, NAV_v3,
              vol_scale_b, Ret_vB, NAV_vB,
              dd_pct_v1, dd_exposure_c, Ret_vC, NAV_vC,
              dd_exposure_d, Ret_vD, NAV_vD,
              vol_scale_e, Ret_vE, NAV_vE,
              Layer_vdp, dd_pct_vdp, dd_exposure_vdp, Ret_vdp, NAV_vdp)],
       file.path(OUT_DIR, "daily_nav_bcde.csv"))
cat("  Saved daily_nav_bcde.csv\n")

# ===================================================================
# 10. Telegram notification (텔레그램 결과 발송)
# ===================================================================
cat("\n[Step 10] Telegram notification...\n")
tryCatch({
  source(file.path(PROJECT_ROOT, "02_Infrastructure/telegram/telegram_notify.R"))

  vdp_row <- if (!is.null(tbl)) tbl[Variant == "VDplus_MRS20_DD10_25"] else NULL
  vd_row  <- if (!is.null(tbl)) tbl[Variant == "VD_DD_10_25"]          else NULL
  mdd_achieved <- !is.null(vdp_row) && nrow(vdp_row) > 0 &&
                  !is.na(vdp_row$MDD_pct) && vdp_row$MDD_pct <= 25.0

  if (mdd_achieved) {
    msg <- paste0(
      "\U0001F3C6 [Q-Lead] MDD 25% \uBAA9\uD45C \uB2EC\uC131!\n\n",
      "\U0001F4CA VD+ \uD3EC\uD2B8\uD3F4\uB9AC\uC624 \uACB0\uACFC (MRS Caution 20 + DD Brake 10/25)\n",
      sprintf("  SR   : %.3f\n", vdp_row$SR),
      sprintf("  CAGR : %.2f%%\n", vdp_row$CAGR_pct),
      sprintf("  MDD  : %.2f%% [TARGET <= 25%%] \u2705\n", vdp_row$MDD_pct),
      "\n\U0001F4C8 VD vs VD+ \ube44\uad50\n"
    )
    if (!is.null(vd_row) && nrow(vd_row) > 0) {
      msg <- paste0(msg,
        sprintf("  VD   MDD=%.2f%% SR=%.3f CAGR=%.2f%%\n",
                vd_row$MDD_pct,  vd_row$SR,  vd_row$CAGR_pct),
        sprintf("  VD+  MDD=%.2f%% SR=%.3f CAGR=%.2f%%\n",
                vdp_row$MDD_pct, vdp_row$SR, vdp_row$CAGR_pct),
        sprintf("  MDD \uac1c\uc120: %.2f%%p\n", vd_row$MDD_pct - vdp_row$MDD_pct)
      )
    }
    msg <- paste0(msg,
      "\n\U0001F527 PIT \uc900\uc218: C5(\ub808\uc9d5 t-1), C9(DD t-1 lag)\n",
      "\U0001F3AF \ub2e4\uc74c: PG2 \ucd5c\uc885 \ud655\uc815 \ud6c4 Judge \uac80\uc99d")
  } else {
    # MDD 미달성 — VD+ 결과 보고
    vdp_mdd  <- if (!is.null(vdp_row) && nrow(vdp_row) > 0) vdp_row$MDD_pct else NA
    vdp_sr   <- if (!is.null(vdp_row) && nrow(vdp_row) > 0) vdp_row$SR      else NA
    vdp_cagr <- if (!is.null(vdp_row) && nrow(vdp_row) > 0) vdp_row$CAGR_pct else NA
    msg <- paste0(
      "\U0001F4CA [Q-Lead] VD+ \uc2dc\ubbac\ub808\uc774\uc158 \uc644\ub8cc (MDD 25% \ubbf8\ub2ec)\n\n",
      "\U0001F4CB VD+ \uACB0\uACFC (MRS Caution=20, DD 10/25)\n",
      sprintf("  SR   : %.3f\n",   ifelse(is.na(vdp_sr),   0, vdp_sr)),
      sprintf("  CAGR : %.2f%%\n", ifelse(is.na(vdp_cagr), 0, vdp_cagr)),
      sprintf("  MDD  : %.2f%% [\ub2e4\uc74c \uc5f0\uad6c \ud544\uc694]\n",
              ifelse(is.na(vdp_mdd), 0, vdp_mdd)),
      "\n\u26A0\uFE0F MDD 25% \ubbf8\ub2ec \u2192 \ucd94\uac00 \ud30c\ub77c\ubbf8\ud130 \ud0d0\uc0c9 \uac80\ud1a0"
    )
  }

  tg_send(msg)

  # 차트 발송
  eq_path <- file.path(OUT_DIR, "equity_curve_bcde.png")
  dd_path <- file.path(OUT_DIR, "drawdown_bcde.png")
  if (file.exists(eq_path)) tg_send_photo(eq_path, caption = "VD+ Equity Curves")
  if (file.exists(dd_path)) tg_send_photo(dd_path, caption = "VD+ Drawdown vs -25% target")

}, error = function(e) {
  cat(sprintf("  [warn] Telegram failed: %s\n", conditionMessage(e)))
})

cat(sprintf("\n[DONE] Path B/C/D/E/VD+ completed in %.1f sec\n",
  difftime(Sys.time(), t0, units = "secs")))
cat(sprintf("Output: %s\n", OUT_DIR))
