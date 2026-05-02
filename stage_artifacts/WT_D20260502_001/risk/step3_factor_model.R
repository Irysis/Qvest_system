#==============================================================================
# WT-D20260502_001 Risk Research — Step 3: Factor Model B + Ω + D
#
# Goal: BΩB' + D structural decomposition
#  Factors: Market (BM_Ret) + Sector dummies + Size + Value/Quality/Momentum proxies
#  via 60M monthly OLS regression: r_i = α_i + Σ_k β_ik * F_k + ε_i
#
# Output:
#  - exposure_matrix B (N × K)
#  - factor_covariance Ω (K × K)
#  - specific_risk D = diag(σ²_ε)
#  - residual_variance for unexplained
#==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(jsonlite)
})

PROJ <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_DIR <- file.path(PROJ, "stage_artifacts/WT_D20260502_001/risk")
state <- readRDS(file.path(WT_DIR, "step2c_state.rds"))

`%||%` <- function(x, y) if (is.null(x)) y else x

# ---- Load RAWDATA (sector + size info) --------------------------------------
RAWDATA <- as.data.table(read_parquet(file.path(PROJ, ".cache/rawdata.parquet")))
covered <- state$covered_tickers_60M
n_assets <- length(covered)
cat(sprintf("[Step3] N=%d assets\n", n_assets))

# ---- Build sector mapping (most recent sector classification) ---------------
sector_map <- RAWDATA[Ticker %in% covered & Date >= "2025-01-01",
                      .(Sector = last(Sector), Sector_Lv2 = last(Sector_Lv2),
                        Market = last(Market)),
                      by = Ticker]
# Some tickers may have no recent data; fallback to most recent any
missing_sec <- setdiff(covered, sector_map$Ticker)
if (length(missing_sec) > 0) {
  fallback <- RAWDATA[Ticker %in% missing_sec,
                      .(Sector = last(Sector), Sector_Lv2 = last(Sector_Lv2),
                        Market = last(Market)),
                      by = Ticker]
  sector_map <- rbind(sector_map, fallback)
}

# Replace NA with "UNCLASSIFIED"
sector_map[is.na(Sector) | Sector == "", Sector := "UNCLASSIFIED"]
sector_map[is.na(Sector_Lv2) | Sector_Lv2 == "", Sector_Lv2 := "UNCLASSIFIED"]

cat(sprintf("[Step3] Sectors (Lv1): %d unique\n", uniqueN(sector_map$Sector)))
cat(sprintf("[Step3] Sectors (Lv2): %d unique\n", uniqueN(sector_map$Sector_Lv2)))
print(sector_map[, .N, by = Sector][order(-N)])

# ---- Build size mapping (most recent log size) ------------------------------
size_map <- RAWDATA[Ticker %in% covered & Date >= "2025-01-01",
                    .(LogSize = log(last(Size))),
                    by = Ticker]
missing_sz <- setdiff(covered, size_map$Ticker)
if (length(missing_sz) > 0) {
  fallback_sz <- RAWDATA[Ticker %in% missing_sz,
                         .(LogSize = log(last(Size))),
                         by = Ticker]
  size_map <- rbind(size_map, fallback_sz)
}
size_map[!is.finite(LogSize), LogSize := median(size_map$LogSize, na.rm = TRUE)]

# ---- Universe metadata ----------
universe_meta <- merge(sector_map, size_map, by = "Ticker", all = TRUE)
universe_meta <- universe_meta[Ticker %in% covered]
setorder(universe_meta, Ticker)
cat(sprintf("[Step3] Universe meta rows: %d\n", nrow(universe_meta)))

# ---- Build factor returns (60M monthly) -------------------------------------
ret_dt_long <- melt(state$monthly_wide_60, id.vars = "YM",
                    variable.name = "Ticker", value.name = "Ret",
                    variable.factor = FALSE)
ret_dt_long <- merge(ret_dt_long, universe_meta, by = "Ticker", all.x = TRUE)
ret_dt_long[is.na(Ret), Ret := 0]

# 1. Market factor: BM (KOSPI200) monthly returns
# CRITICAL: BM_Ret duplicated across tickers per Date — must dedupe to 1 per Date
RAWDATA[, YM := format(Date, "%Y-%m")]
bm_daily <- unique(RAWDATA[!is.na(BM_Ret), .(Date, BM_Ret)])
bm_daily[, YM := format(Date, "%Y-%m")]
bm_monthly <- bm_daily[, .(BM_Ret_Monthly = prod(1 + BM_Ret, na.rm = TRUE) - 1,
                            n_days = .N),
                        by = YM]
bm_monthly <- bm_monthly[YM %in% state$monthly_wide_60$YM]
setkey(bm_monthly, YM)
cat(sprintf("[Step3] BM monthly: %d months, range [%g, %g]\n",
            nrow(bm_monthly), min(bm_monthly$BM_Ret_Monthly),
            max(bm_monthly$BM_Ret_Monthly)))

# 2. Sector factors: Equal-weighted sector portfolios (cross-sectional)
# At each month, compute sector mean return
sector_factor_long <- ret_dt_long[!is.na(Sector),
                                   .(Sector_Ret = mean(Ret, na.rm = TRUE)),
                                   by = .(YM, Sector)]
sector_factor_wide <- dcast(sector_factor_long, YM ~ Sector,
                             value.var = "Sector_Ret", fill = 0)

# 3. Size factor: SMB-style — monthly cross-sectional return spread small minus big
ret_dt_long[, SizeQuintile := cut(LogSize, breaks = quantile(LogSize, probs = seq(0, 1, 0.2),
                                                              na.rm = TRUE),
                                   include.lowest = TRUE, labels = 1:5)]
size_factor_long <- ret_dt_long[!is.na(SizeQuintile),
                                 .(MeanRet = mean(Ret, na.rm = TRUE)),
                                 by = .(YM, SizeQuintile)]
size_factor_wide <- dcast(size_factor_long, YM ~ SizeQuintile,
                           value.var = "MeanRet", fill = 0)
size_factor_wide[, SMB := `1` - `5`]  # small minus big

# Combine all factors
factor_matrix <- merge(bm_monthly, size_factor_wide[, .(YM, SMB)], by = "YM")
sector_cols <- setdiff(names(sector_factor_wide), "YM")
factor_matrix <- merge(factor_matrix, sector_factor_wide, by = "YM")

# Sectors are cross-sectional; we drop one to avoid singularity (UNCLASSIFIED if exists)
if ("UNCLASSIFIED" %in% sector_cols) {
  factor_matrix[, UNCLASSIFIED := NULL]
  sector_cols <- setdiff(sector_cols, "UNCLASSIFIED")
}
# Actually drop the largest sector as the implicit base
biggest_sector <- sector_factor_long[, .(N = .N), by = Sector][order(-N)]$Sector[1]
cat(sprintf("[Step3] Dropping base sector '%s' for identifiability\n", biggest_sector))
factor_matrix[, (biggest_sector) := NULL]
sector_cols <- setdiff(sector_cols, biggest_sector)

# Remove BM_Ret to keep market as primary
factor_cols_in_F <- c("BM_Ret_Monthly", "SMB", sector_cols)
F_mat <- as.matrix(factor_matrix[, ..factor_cols_in_F])
rownames(F_mat) <- factor_matrix$YM
F_mat[is.na(F_mat)] <- 0
cat(sprintf("[Step3] Factor matrix: %d months x %d factors\n",
            nrow(F_mat), ncol(F_mat)))

# Demean factors
F_mat_dm <- scale(F_mat, center = TRUE, scale = FALSE)

# ---- OLS regression per asset: r_i = α + B * F + ε --------------------------
ret_mat_dm <- scale(as.matrix(state$monthly_wide_60[, ..covered]),
                     center = TRUE, scale = FALSE)
ret_mat_dm[is.na(ret_mat_dm)] <- 0

# Solve B = (F'F)^-1 F'R
FtF <- crossprod(F_mat_dm)
FtR <- crossprod(F_mat_dm, ret_mat_dm)
# Add small ridge for stability
FtF_reg <- FtF + diag(1e-6, nrow(FtF))
B_mat <- solve(FtF_reg, FtR)
B_mat <- t(B_mat)  # N × K
rownames(B_mat) <- covered
colnames(B_mat) <- factor_cols_in_F

# Compute residuals
R_pred <- F_mat_dm %*% t(B_mat)
R_residual <- ret_mat_dm - R_pred

# Specific variance D = diag(σ²_ε)
D_vec <- apply(R_residual, 2, var)
names(D_vec) <- covered

# Factor covariance Ω
Omega_mat <- cov(F_mat_dm)

# ---- BΩB' + D vs Sigma direct -----------------------------------------------
Sigma_factor_model <- B_mat %*% Omega_mat %*% t(B_mat) + diag(D_vec)
Sigma_factor_model <- (Sigma_factor_model + t(Sigma_factor_model)) / 2

# Compare to Σ from Step 2c
Sigma_lw_tikh <- state$Sigma_primary
diff_norm <- norm(Sigma_factor_model - Sigma_lw_tikh, type = "F")
cat(sprintf("[Step3] ||Σ_FactorModel - Σ_LW_Tikh||_F = %.6f\n", diff_norm))

# ---- Variance decomposition --------------------------------------------------
# For each asset: total var = systematic var (B*Omega*B') + specific var (D)
asset_total_var <- diag(Sigma_factor_model)
asset_systematic_var <- diag(B_mat %*% Omega_mat %*% t(B_mat))
asset_specific_var <- D_vec
asset_R2 <- asset_systematic_var / asset_total_var
mean_R2 <- mean(asset_R2, na.rm = TRUE)
median_R2 <- median(asset_R2, na.rm = TRUE)
cat(sprintf("[Step3] Mean R² (factor explanatory): %.3f | Median: %.3f\n",
            mean_R2, median_R2))

# Top common risks decomposition (by factor)
factor_var_contribs <- numeric(ncol(F_mat))
total_systematic_var <- sum(diag(B_mat %*% Omega_mat %*% t(B_mat)))
for (k in seq_along(factor_cols_in_F)) {
  Bk <- B_mat[, k, drop = FALSE]
  factor_var_contribs[k] <- sum(diag(Bk %*% Omega_mat[k, k, drop = FALSE] %*% t(Bk)))
}
factor_var_pct <- factor_var_contribs / total_systematic_var
names(factor_var_pct) <- factor_cols_in_F

# Top 5 contributing factors
top_factors_dt <- data.table(Factor = factor_cols_in_F, Var_Pct = round(factor_var_pct * 100, 2))
top_factors_dt <- top_factors_dt[order(-Var_Pct)]
cat("[Step3] Top 5 systematic risk factors:\n")
print(head(top_factors_dt, 5))

# ---- Save state -------------------------------------------------------------
state$exposure_matrix_B <- B_mat
state$factor_names <- factor_cols_in_F
state$factor_returns_F <- F_mat
state$factor_covariance_Omega <- Omega_mat
state$specific_risk_D <- D_vec
state$residuals_R_residual <- R_residual
state$Sigma_factor_model <- Sigma_factor_model
state$factor_R2 <- list(mean = mean_R2, median = median_R2,
                         per_asset = asset_R2)
state$top_factors <- top_factors_dt
state$universe_meta <- universe_meta
state$base_sector_dropped <- biggest_sector

# Update top_common_risks
state$top_common_risks_pct <- as.list(round(factor_var_pct * 100, 2))

saveRDS(state, file.path(WT_DIR, "step3_state.rds"))
# Save exposure matrix and factor cov as parquet
exposure_dt <- data.table(Ticker = rownames(B_mat))
for (k in seq_along(factor_cols_in_F)) {
  exposure_dt[[factor_cols_in_F[k]]] <- B_mat[, k]
}
write_parquet(exposure_dt, file.path(WT_DIR, "exposure_matrix.parquet"))

omega_dt <- as.data.table(Omega_mat)
omega_dt[, Factor := rownames(Omega_mat)]
setcolorder(omega_dt, c("Factor", factor_cols_in_F))
write_parquet(omega_dt, file.path(WT_DIR, "factor_covariance.parquet"))

specific_dt <- data.table(Ticker = names(D_vec), Specific_Var = D_vec,
                           Specific_Vol = sqrt(D_vec))
write_parquet(specific_dt, file.path(WT_DIR, "specific_risk.parquet"))

cat("[Step3] DONE. Exposure / factor cov / specific risk saved.\n")
