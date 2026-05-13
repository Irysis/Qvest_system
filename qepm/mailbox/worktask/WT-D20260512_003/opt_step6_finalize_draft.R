#==============================================================================
# WT-D20260512_003 Optimizer Step 6 — Re-finalize draft package with 2026-04-01 weights
#
# Reuse Step 4 aggregate computation + update target_weights to 2026-04-01 live snap.
#==============================================================================

suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite); library(digest)
})

BASE_DIR <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
setwd(BASE_DIR)

cat("============================================================\n")
cat("[OPT-Step6] Re-finalize draft package with 2026-04-01 live weights\n")
cat("============================================================\n\n")

WT <- "WT-D20260512_003"
stage <- file.path("stage_artifacts", "WT_D20260512_003")
mailbox <- file.path("qepm/mailbox/worktask", WT)

# Load existing draft + 2026-04-01 weights
draft <- fromJSON(file.path(mailbox, "optimization_package_draft.json"),
                   simplifyVector = FALSE)
w_2604 <- fread(file.path(stage, "weights_2026_04_01.csv"))

# Replace target_weights with 2026-04-01 snap
new_target_weights <- as.list(w_2604$weight)
names(new_target_weights) <- w_2604$ticker

cat(sprintf("Updated target_weights @ 2026-04-01: n=%d | Σw=%.6f | max_w=%.4f\n",
            length(new_target_weights),
            sum(unlist(new_target_weights)),
            max(unlist(new_target_weights))))

draft$target_weights <- new_target_weights
draft$as_of_date <- "2026-04-01"

# Recompute factor loading on actual 2026-04-01 weights
emat <- as.data.table(read_parquet(file.path(stage, "exposure_matrix.parquet")))
setkey(emat, Ticker)
common_2604 <- intersect(names(new_target_weights), emat$Ticker)
B_2604 <- as.matrix(emat[Ticker %in% common_2604][match(common_2604, Ticker),
                          .(RM_KR, F_SIZE, F_VAL, F_MOM, F_QMJ, F_BAB, F_LIQ, F_TAIL)])
w_2604_v <- unlist(new_target_weights[common_2604])
factor_loading_final <- as.numeric(t(B_2604) %*% w_2604_v)
names(factor_loading_final) <- c("RM_KR", "F_SIZE", "F_VAL", "F_MOM", "F_QMJ", "F_BAB", "F_LIQ", "F_TAIL")

cat("\n[Factor loading @ 2026-04-01 live weights]\n")
print(round(factor_loading_final, 4))

draft$factor_loading_2604 <- as.list(factor_loading_final)

# Schedule fidelity update
weights_csv <- fread(file.path(stage, "weights.csv"))
sig_dates_used <- sort(unique(weights_csv$sig_date))
draft$schedule_fidelity$sig_dates_count <- length(sig_dates_used)
draft$schedule_fidelity$alpha_emission_target_count <- 268L
draft$schedule_fidelity$density_ratio <- length(sig_dates_used) / 268
draft$schedule_fidelity$pass <- (length(sig_dates_used) / 268 >= 0.95)
draft$schedule_fidelity$as_of_date_in_schedule <- "2026-04-01" %in% as.character(sig_dates_used)

# Add portfolio risk decomp using risk_package Σ
cov_long <- as.data.table(read_parquet(file.path(stage, "covariance.parquet")))
cov_long_full <- rbind(cov_long, cov_long[i != j, .(i = j, j = i, sigma_ij, estimator)])
cov_long_full <- unique(cov_long_full, by = c("i", "j"))
Sigma_full <- dcast(cov_long_full, i ~ j, value.var = "sigma_ij", fill = 0)
ix_rn <- Sigma_full$i
Sigma_full <- as.matrix(Sigma_full[, -1])
rownames(Sigma_full) <- ix_rn
common_sigma <- intersect(names(new_target_weights), rownames(Sigma_full))
Sigma_sub <- Sigma_full[common_sigma, common_sigma]
w_sigma_v <- unlist(new_target_weights[common_sigma])
port_var_m <- as.numeric(t(w_sigma_v) %*% Sigma_sub %*% w_sigma_v)
port_vol_ann <- sqrt(port_var_m * 12)
draft$portfolio_risk_2604 <- list(
  port_vol_monthly = sqrt(port_var_m),
  port_vol_annualized = port_vol_ann,
  cov_basis = "risk_package factor_model_8F (estimation_window 2021-05~2026-04)",
  cov_sha256 = digest(file = file.path(stage, "covariance.parquet"), algo = "sha256")
)

cat(sprintf("\nPortfolio risk @ 2026-04-01: vol_ann=%.4f\n", port_vol_ann))

# Save updated draft
write_json(draft, file.path(mailbox, "optimization_package_draft.json"),
            pretty = TRUE, auto_unbox = TRUE, null = "null", na = "null")
cat(sprintf("\n[Saved] %s (n target_weights = %d)\n",
            file.path(mailbox, "optimization_package_draft.json"),
            length(new_target_weights)))

cat("[OPT-Step6] DONE\n")
