#==============================================================================
# 210_panel_v5j_investor_breadth.R — Cycle 58K
#
# 미사용 alternative data 도입: 개인 / 기관 / 기타외인 breadth (이미 보유).
# 외인 breadth 외 3 investor type → 진정한 alt-data orthogonal channel.
#
# Source: outputs/01_data/{gaein|inst|kita}_breadth_daily.csv
#   Cols: Date / n_buy / n_sell / n_active / ad_ratio / hhi_buy
#
# v5j = v5g (86 features) + 3 investor types × 4 PIT-clean features
#   (ad_ratio_lag1, hhi_buy_lag1, ad_ratio_rm21, ad_ratio_rsd21) = 12 신규
#   Total: 86 + 12 = 98 features
#
# 가설: 개인 buy ↑ + 외인 sell ↑ = 약세 (typical KR quant pattern)
#       기관/기타외인 net direction = independent signal
#==============================================================================

suppressPackageStartupMessages({
  library(arrow); library(data.table)
})

PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
WS <- file.path(PROJECT_ROOT,
  "04_Research/decision_framework/bearish_forecast_v2_alt_data")
IN_PATH <- file.path(WS, "outputs/01_data/feature_panel_v5g_cross_market.parquet")
OUT_PATH <- file.path(WS, "outputs/01_data/feature_panel_v5j_investor_breadth.parquet")
DATA_DIR <- file.path(WS, "outputs/01_data")

cat(sprintf("[%s] Loading v5g base panel...\n", format(Sys.time(), "%H:%M:%S")))
d <- as.data.table(read_parquet(IN_PATH))
d[, Date := as.Date(Date)]
setorder(d, Date)
cat(sprintf("  v5g panel rows=%d cols=%d\n", nrow(d), ncol(d)))

# PIT-safe rolling z (expanding, past-only)
roll_z <- function(x, min_obs = 252L) {
  n <- length(x); z <- rep(NA_real_, n)
  for (i in seq_len(n)) {
    if (i < min_obs) next
    hist <- x[1:(i - 1)]; mu <- mean(hist, na.rm = TRUE); s <- sd(hist, na.rm = TRUE)
    if (is.na(s) || s < 1e-9) next
    z[i] <- (x[i] - mu) / s
  }
  z
}

# PIT lag-1 + rolling stat
add_breadth_features <- function(d, src_file, prefix) {
  b <- fread(src_file)
  b[, Date := as.Date(Date)]
  setorder(b, Date)
  # Z-normalize raw breadth signals (PIT expanding)
  b[, ad_ratio_z := roll_z(ad_ratio)]
  b[, hhi_buy_z := roll_z(hhi_buy)]
  # Lag1 (PIT t-1)
  b[, ad_ratio_z_lag1 := shift(ad_ratio_z, 1, type = "lag")]
  b[, hhi_buy_z_lag1 := shift(hhi_buy_z, 1, type = "lag")]
  # Rolling 21d mean / std (PIT past)
  b[, ad_ratio_z_rm21 := frollmean(ad_ratio_z_lag1, 21, align = "right")]
  b[, ad_ratio_z_rsd21 := frollapply(ad_ratio_z_lag1, 21, sd, align = "right")]
  # Select PIT features
  new_cols <- c("ad_ratio_z_lag1", "hhi_buy_z_lag1",
                "ad_ratio_z_rm21", "ad_ratio_z_rsd21")
  out_cols <- paste0(prefix, "_", new_cols)
  setnames(b, new_cols, out_cols)
  b_subset <- b[, c("Date", out_cols), with = FALSE]
  d <- merge(d, b_subset, by = "Date", all.x = TRUE)
  list(d = d, added = out_cols)
}

cat(sprintf("[%s] Adding 개인 breadth features...\n",
            format(Sys.time(), "%H:%M:%S")))
r1 <- add_breadth_features(d, file.path(DATA_DIR, "gaein_breadth_daily.csv"),
                            "gaein")
d <- r1$d
cat(sprintf("[%s] Adding 기관 breadth features...\n",
            format(Sys.time(), "%H:%M:%S")))
r2 <- add_breadth_features(d, file.path(DATA_DIR, "inst_breadth_daily.csv"),
                            "inst")
d <- r2$d
cat(sprintf("[%s] Adding 기타외인 breadth features...\n",
            format(Sys.time(), "%H:%M:%S")))
r3 <- add_breadth_features(d, file.path(DATA_DIR, "kita_breadth_daily.csv"),
                            "kita")
d <- r3$d

new_features <- c(r1$added, r2$added, r3$added)
cat(sprintf("\n[%s] %d new investor breadth features added.\n",
            format(Sys.time(), "%H:%M:%S"), length(new_features)))

# Validation (collinearity vs existing)
existing <- setdiff(names(d), c("Date", new_features))
for (nc in new_features) {
  v <- d[[nc]]; mask <- !is.na(v)
  if (sum(mask) < 100) {
    cat(sprintf("  %-40s SPARSE (n=%d)\n", nc, sum(mask)))
    next
  }
  cors <- sapply(existing, function(ec) {
    other <- d[[ec]]; valid <- mask & !is.na(other)
    if (sum(valid) < 100) return(NA_real_)
    cor(v[valid], other[valid])
  })
  max_r <- max(abs(cors), na.rm = TRUE)
  cat(sprintf("  %-40s n=%d max|r|=%.3f\n", nc, sum(mask), max_r))
}

# Save
write_parquet(d, OUT_PATH)
cat(sprintf("\n[%s] Saved: %s\n  cols: %d (= 86 v5g + %d new)\n  rows: %d\n",
            format(Sys.time(), "%H:%M:%S"), OUT_PATH,
            ncol(d), length(new_features), nrow(d)))

# Audit JSON
audit <- list(
  cycle = "58K_panel_v5j_investor_breadth",
  generated_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
  base_panel = "v5g (86 features)",
  new_features = new_features,
  n_features_new = length(new_features),
  n_features_total = ncol(d) - 1L,
  n_rows = nrow(d),
  sources = c("gaein_breadth_daily.csv", "inst_breadth_daily.csv",
              "kita_breadth_daily.csv")
)
jsonlite::write_json(audit,
  file.path(WS, "outputs/04_evaluation/cycle58k_panel_v5j_build.json"),
  auto_unbox = TRUE, pretty = TRUE)
