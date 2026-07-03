# Export covariance.parquet + factor_covariance + exposure + specific + regime_correlation
suppressMessages({ library(data.table); library(arrow) })
source("02_Infrastructure/config.R")
OUT <- "stage_artifacts/WT-D20260614_002"
rc <- readRDS(file.path(OUT, "_risk_core.rds"))
FACTORS <- colnames(rc$Omega)
names_alpha <- rownames(rc$Sigma)

# 1. covariance.parquet (security cov: long, Ticker_i, Ticker_j, cov)  + also wide matrix
Sig <- rc$Sigma
covdt <- as.data.table(Sig); covdt[, Ticker := names_alpha]
setcolorder(covdt, c("Ticker", names_alpha))
write_parquet(covdt, file.path(OUT, "covariance.parquet"))

# 2. factor_covariance.parquet (Omega 10x10 annualized)
Om <- as.data.table(rc$Omega); Om[, Factor := FACTORS]; setcolorder(Om, c("Factor", FACTORS))
write_parquet(Om, file.path(OUT, "factor_covariance.parquet"))

# 3. exposure_matrix.parquet (B 60x10)
Bdt <- as.data.table(rc$B); Bdt[, Ticker := names_alpha]; setcolorder(Bdt, c("Ticker", FACTORS))
write_parquet(Bdt, file.path(OUT, "exposure_matrix.parquet"))

# 4. specific_risk.parquet
sr <- data.table(Ticker = names_alpha, specific_var_annual = as.numeric(rc$D_vec),
                 specific_vol_annual = sqrt(as.numeric(rc$D_vec)),
                 factor_var_explained = as.numeric(rc$fac_var_explained[names_alpha]))
write_parquet(sr, file.path(OUT, "specific_risk.parquet"))

# 5. regime_correlation.parquet — factor correlation conditioned on market regime
panel <- as.data.table(read_parquet(file.path(OUT, "_factor_return_panel.parquet")))
bm <- as.data.table(read_parquet(".cache/benchmark.parquet"))[, .(Date=as.Date(Date), BM_Ret)]
bm[, ym := format(Date, "%Y%m")]
bmm <- bm[, .(bm_ret = prod(1+BM_Ret, na.rm=TRUE)-1), by=ym][ym %in% panel$ym]
P <- merge(panel, bmm, by="ym"); setorder(P, ym)
P[, regime := fifelse(bm_ret <= quantile(bm_ret,0.25), "CRISIS",
                fifelse(bm_ret >= quantile(bm_ret,0.75), "BULL", "NORMAL"))]
# average pairwise factor correlation per regime (off-diagonal mean) for the 60-name EW port proxy
reg_cor <- rbindlist(lapply(c("CRISIS","NORMAL","BULL","ALL"), function(rg) {
  sub <- if (rg=="ALL") P else P[regime==rg]
  M <- as.matrix(sub[, ..FACTORS]); M <- M[, colSums(is.finite(M))>10, drop=FALSE]
  C <- suppressWarnings(cor(M, use="pairwise.complete.obs"))
  off <- C[upper.tri(C)]
  data.table(regime=rg, n_months=nrow(sub), mean_pair_corr=mean(off, na.rm=TRUE),
             max_pair_corr=max(off, na.rm=TRUE), mom_block_corr=mean(C[c("M01_Mom_12_1","M05_Trended_Mom","M07_IndMom"),
                                                                       c("M01_Mom_12_1","M05_Trended_Mom","M07_IndMom")][upper.tri(diag(3))], na.rm=TRUE))
}))
write_parquet(reg_cor, file.path(OUT, "regime_correlation.parquet"))
cat("[export] regime correlation:\n"); print(reg_cor)
cat("[export] all parquets written.\n")
