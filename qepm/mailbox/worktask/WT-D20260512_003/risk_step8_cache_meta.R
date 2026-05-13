#==============================================================================
# Risk Step 8: Save covariance cache + meta.json for R6 freshness SLA
#==============================================================================

suppressPackageStartupMessages({
  library(arrow); library(data.table); library(jsonlite); library(digest)
})

setwd("/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot")
source("02_Infrastructure/config.R")

OUT_DIR <- "stage_artifacts/WT_D20260512_003"
CACHE_DIR <- ".cache/covariance"
dir.create(CACHE_DIR, showWarnings = FALSE, recursive = TRUE)

# Load Σ
res24 <- readRDS(file.path(OUT_DIR, "_risk_step24_results.rds"))
Sigma <- res24$results[[5]]$Sigma
B <- attr(Sigma, "B")
Omega <- attr(Sigma, "Omega")
D <- attr(Sigma, "D")

# Σ as long parquet
cov_long <- as.data.table(expand.grid(i = rownames(Sigma), j = colnames(Sigma), stringsAsFactors = FALSE))
cov_long[, sigma_ij := as.vector(Sigma)]
cov_long[, estimator := "factor_model_8f"]

# Cache file: WT-D20260512_003_factor_model_8f_20260401.parquet
cache_tag <- "WT-D20260512_003_factor_model_8f_20260401"
cache_path <- file.path(CACHE_DIR, paste0(cache_tag, ".parquet"))
meta_path <- file.path(CACHE_DIR, paste0(cache_tag, ".meta.json"))

write_parquet(cov_long, cache_path)
cache_hash <- digest(file = cache_path, algo = "sha256")

# Read alpha regime_state to determine regime_tag at as_of
alpha_dt <- as.data.table(read_parquet(file.path(OUT_DIR, "alpha_scores_new.parquet")))
last_date <- max(alpha_dt$Date)
cur <- alpha_dt[Date == last_date]
regime_tag <- tolower(unique(cur$regime_state)[1])

# Factor coverage R^2 across universe (avg)
ret_long <- as.data.table(read_parquet(file.path(OUT_DIR, "_risk_monthly_returns_long.parquet")))
F_mat <- as.matrix(res24$F_mat)
ret_mat <- res24$ret_mat
keep <- res24$univ

# Per-stock R^2
r2_per_stock <- numeric(length(keep))
names(r2_per_stock) <- keep
ok_rows <- complete.cases(F_mat)
Fk <- F_mat[ok_rows, ]
Rk <- ret_mat[ok_rows, ]
for (j in seq_along(keep)) {
  y <- Rk[, j]
  fit <- lm(y ~ Fk)
  r2_per_stock[j] <- summary(fit)$r.squared
}
avg_r2 <- mean(r2_per_stock, na.rm = TRUE) * 100

meta <- list(
  task_id = "WT-D20260512_003",
  method = "factor_model_8f",
  covariance_asof = "2026-04-01",
  estimation_window_months = 60,
  estimation_window_range = "2021-05-01 / 2026-04-01",
  dimension = ncol(Sigma),
  condition_number = 153.92,
  min_eigenvalue = 1.748e-03,
  psd = TRUE,
  regime_tag = regime_tag,
  created_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  freshness_sla_days = 30,
  cache_hash = cache_hash,
  invalidate_rule = "regime_change OR age_gt_30d OR dimension_change",
  blend_method = "structured (8-factor B Ω B' + D, no shrinkage applied)",
  factor_coverage_r2_pct = avg_r2,
  parent_strategy = "STR_1715_AR_on_M4_PG2",
  alpha_package_sha256 = digest(file = "qepm/mailbox/worktask/WT-D20260512_003/alpha_package.json", algo = "sha256")
)
write_json(meta, meta_path, pretty = TRUE, auto_unbox = TRUE)
cat("[Step8] Cache:", cache_path, "  hash:", substr(cache_hash, 1, 12), "\n")
cat("[Step8] Meta:", meta_path, "\n")
cat("[Step8] regime_tag:", regime_tag, "\n")
cat(sprintf("[Step8] Factor coverage R^2 (avg): %.2f%%\n", avg_r2))
