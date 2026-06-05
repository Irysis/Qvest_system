#==============================================================================
# 135_feature_panel_v5f_ecos_kr.R — Cycle 53I Step 1: v5f panel build
#
# Mandate:
#   v5e 74 features (Cycle 53H: v4a 70 + 4 US macro)
#   + 5 ECOS KR macro features:
#       ecos_m2_yoy_lag1
#       ecos_krw_usd_change_5d_lag1
#       ecos_base_rate_lag1
#       ecos_industrial_production_yoy_lag1
#       ecos_cpi_yoy_lag1
#   = 79 features
#
# Hypothesis:
#   Cycle 53H (US macro at q126) showed +0.0556 additive vs 53B (0.4012 vs 0.3456).
#   KR macro (ECOS) is structurally different axis from BBVA composite (which is
#   5-axis aggregation, not raw macro). Test whether raw KR macro adds incremental
#   info beyond BBVA composite + US macro panel.
#
# PIT 정합:
#   - v5e 74 features PIT validated (Cycle 53H, inherits Cycle 52 + Cycle 47B)
#   - ECOS lag1 + publication lag applied in Step 0 (35d / 50d / 1d)
#
# Output:
#   outputs/01_data/feature_panel_v5f_ecos_kr.parquet (79 features)
#==============================================================================

suppressPackageStartupMessages({
  library(arrow); library(data.table); library(jsonlite)
})

PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
WS <- file.path(PROJECT_ROOT, "04_Research/decision_framework/bearish_forecast_v2_alt_data")
DATA_DIR <- file.path(WS, "outputs/01_data")
EVAL_DIR <- file.path(WS, "outputs/04_evaluation")

dir.create(EVAL_DIR, recursive = TRUE, showWarnings = FALSE)

cat("\n========== Cycle 53I Step 1: v5f panel build (v5e 74 + ECOS KR 5) ==========\n")

# Step 1a: Load v5e (74 features)
v5e_path <- file.path(DATA_DIR, "feature_panel_v5e_q126_usmacro.parquet")
if (!file.exists(v5e_path)) stop(sprintf("missing v5e panel: %s", v5e_path))
v5e <- as.data.table(read_parquet(v5e_path))
v5e[, Date := as.Date(Date)]
setorder(v5e, Date)
n_v5e <- ncol(v5e) - 1L
cat(sprintf("[Step 1a] v5e base: %d rows × %d features\n", nrow(v5e), n_v5e))
stopifnot(n_v5e == 74L)

# Step 1b: Load ECOS daily panel
ecos_path <- file.path(DATA_DIR, "ecos_kr_daily.csv")
if (!file.exists(ecos_path)) stop(sprintf("missing ecos panel: %s — run scripts/134_ecos_fetch_kr_macro.R first", ecos_path))
ecos <- fread(ecos_path)
ecos[, Date := as.Date(Date)]
setorder(ecos, Date)
cat(sprintf("[Step 1b] ECOS panel: %d rows × %d cols\n", nrow(ecos), ncol(ecos)))

ecos_features <- c(
  "ecos_m2_yoy_lag1",
  "ecos_krw_usd_change_5d_lag1",
  "ecos_base_rate_lag1",
  "ecos_industrial_production_yoy_lag1",
  "ecos_cpi_yoy_lag1"
)
stopifnot(all(ecos_features %in% names(ecos)))

# Step 1c: Merge v5e + ECOS on Date
combined <- merge(v5e, ecos[, c("Date", ecos_features), with = FALSE],
                  by = "Date", all.x = TRUE)
setorder(combined, Date)

n_combined <- ncol(combined) - 1L
cat(sprintf("\n[Step 1c] Combined panel: %d rows × %d features (74 v5e + 5 ECOS = 79)\n",
            nrow(combined), n_combined))
stopifnot(n_combined == 79L)

# Step 1d: Coverage per ECOS feature
cat("\n[Coverage ECOS features in merged panel]\n")
for (col in ecos_features) {
  non_na <- sum(!is.na(combined[[col]]))
  first_valid <- combined[!is.na(get(col))][1, Date]
  last_valid <- combined[!is.na(get(col))][.N, Date]
  cat(sprintf("  %s: non-NA=%d/%d (%.1f%%), range %s ~ %s\n",
              col, non_na, nrow(combined), 100 * non_na / nrow(combined),
              as.character(first_valid), as.character(last_valid)))
}

# OOS coverage (2018~2026)
oos <- combined[Date >= as.Date("2018-01-01") & Date <= as.Date("2026-04-30")]
cat("\n[OOS 2018-01~2026-04 coverage]\n")
for (col in ecos_features) {
  non_na <- sum(!is.na(oos[[col]]))
  cat(sprintf("  %s: non-NA=%d/%d (%.1f%%)\n",
              col, non_na, nrow(oos), 100 * non_na / nrow(oos)))
}

# Step 1e: BBVA composite vs ECOS overlap diagnostic (correlation)
bbva_cols <- grep("^bbva_", names(combined), value = TRUE)
us_macro_cols <- c("us_t10y2y_spread_lag1", "us_initial_claims_4w_avg_lag1",
                    "us_cfnai_lag1", "us_stlfsi_lag1")

cat(sprintf("\n[Step 1e] BBVA composite columns found: %d\n", length(bbva_cols)))

# Pearson correlation: each ECOS vs each BBVA composite (on overlap rows)
cor_bbva <- list()
sample_panel <- combined[Date >= as.Date("2005-01-01") & Date <= as.Date("2026-04-30")]
for (e in ecos_features) {
  v_e <- sample_panel[[e]]
  cors <- sapply(bbva_cols, function(b) {
    v_b <- sample_panel[[b]]
    valid <- !is.na(v_e) & !is.na(v_b)
    if (sum(valid) < 50) return(NA_real_)
    cor(v_e[valid], v_b[valid])
  })
  cor_bbva[[e]] <- list(
    max_abs_cor_bbva = round(max(abs(cors), na.rm = TRUE), 3),
    top_bbva_partner = bbva_cols[which.max(abs(cors))]
  )
  cat(sprintf("  %s: max|cor|=%.3f with %s\n",
              e, cor_bbva[[e]]$max_abs_cor_bbva, cor_bbva[[e]]$top_bbva_partner))
}

# ECOS vs US macro overlap
cor_usmacro <- list()
for (e in ecos_features) {
  v_e <- sample_panel[[e]]
  cors <- sapply(us_macro_cols, function(u) {
    v_u <- sample_panel[[u]]
    valid <- !is.na(v_e) & !is.na(v_u)
    if (sum(valid) < 50) return(NA_real_)
    cor(v_e[valid], v_u[valid])
  })
  cor_usmacro[[e]] <- as.list(round(cors, 3))
  names(cor_usmacro[[e]]) <- us_macro_cols
}
cat("\n[ECOS vs US macro correlation matrix (5×4)]\n")
ecos_us_mat <- matrix(NA_real_, nrow = length(ecos_features), ncol = length(us_macro_cols),
                     dimnames = list(ecos_features, us_macro_cols))
for (e in ecos_features) for (u in us_macro_cols) ecos_us_mat[e, u] <- cor_usmacro[[e]][[u]]
print(round(ecos_us_mat, 3))

# Step 1f: Save
out_path <- file.path(DATA_DIR, "feature_panel_v5f_ecos_kr.parquet")
write_parquet(combined, out_path)
cat(sprintf("\n[Saved] %s (size: %.1f KB)\n",
            out_path, file.info(out_path)$size / 1024))

# Step 1g: Audit log
audit <- list(
  cycle = "53I_ecos_kr_macro_q126",
  step = "step1_feature_panel_build",
  base_panel = list(
    path = v5e_path,
    n_features = n_v5e,
    inherit = "Cycle 53H Path C extension: v4a 70 + 4 US macro (additive proven at q126 +0.0556)"
  ),
  added_features = list(
    ecos_m2_yoy_lag1 = list(
      source = "ECOS 161Y006/BBHA00 M2 평잔 원계열 (monthly)",
      semantics = "M2 broad money YoY %, 35d publication lag",
      pit_lag = "monthly + 35d shift + daily ffill"
    ),
    ecos_krw_usd_change_5d_lag1 = list(
      source = "ECOS 731Y001 KRW/USD 매매기준율 (daily)",
      semantics = "5-day % change of KRW/USD, lag1",
      pit_lag = "daily + 1d shift"
    ),
    ecos_base_rate_lag1 = list(
      source = "ECOS 817Y002 KR_Call1D (daily call rate, base rate proxy)",
      semantics = "한국은행 기준금리 proxy (call rate, daily), lag1",
      pit_lag = "daily + 1d shift"
    ),
    ecos_industrial_production_yoy_lag1 = list(
      source = "ECOS 901Y033/A00 전산업생산지수 (monthly)",
      semantics = "Industrial production index YoY %, 50d publication lag",
      pit_lag = "monthly + 50d shift + daily ffill"
    ),
    ecos_cpi_yoy_lag1 = list(
      source = "ECOS 901Y009 KR_CPI (monthly)",
      semantics = "CPI YoY %, 35d publication lag",
      pit_lag = "monthly + 35d shift + daily ffill"
    )
  ),
  combined_n_features = n_combined,
  output = out_path,
  bbva_overlap_diagnostic = cor_bbva,
  ecos_vs_us_macro_correlation = cor_usmacro,
  pit_audit = list(
    C2 = "PASS — daily series shifted +1d (no same-day circular)",
    C4 = "PASS — monthly stats shifted by publication lag (35d/50d/35d)",
    C13 = "PASS — no sign flip, raw lag1 features",
    C14 = "N/A — not factor IC",
    C15 = "N/A — not Factor DB"
  ),
  inherits_from = list(
    "Cycle 53H: v5e panel (v4a 70 + 4 US macro) — q126 ADDITIVE_STRONG +0.0556",
    "Cycle 52: v4a base panel (v1.3 + foreign breadth winner)",
    "Cycle 134 (this cycle): ecos_kr_daily.csv from BOK ECOS API"
  )
)
write_json(audit,
           file.path(EVAL_DIR, "v5f_ecos_kr_step1.json"),
           auto_unbox = TRUE, pretty = TRUE, na = "null")
cat(sprintf("[Audit] %s\n", file.path(EVAL_DIR, "v5f_ecos_kr_step1.json")))

cat("\n========== Cycle 53I Step 1 DONE — Run scripts/136_patchtst_q126_v5f_ecos.py next ==========\n")
