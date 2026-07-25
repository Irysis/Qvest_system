# debug_one_gate4.R — debug-first Gate 4: latent (PCA) + pure-factor FWL + validation
# Small scope to verify mechanics: 1 PCA on cached pool + FWL on a handful of factors over a few months.
suppressMessages({ library(data.table); library(arrow) })
dir.create(".cache/scratch/ramp_debug", recursive = TRUE, showWarnings = FALSE)
sink(".cache/scratch/ramp_debug/debug_gate4_out.txt", split = TRUE)
t0 <- Sys.time()

source("02_Infrastructure/ramp/latent_factor_extraction.R")
source("02_Infrastructure/ramp/pure_factor_extraction.R")
source("02_Infrastructure/ramp/factor_validation.R")
config <- yaml::read_yaml("02_Infrastructure/ramp/ramp_config.yml")

# ---- Gate 4.1 latent factors (uses cached pool matrix) ----
cat("===== Gate 4.1 latent factors (PCA) =====\n")
pool <- readRDS("02_Infrastructure/ramp/debug/_cache_pool.rds")
lf <- extract_latent_factors(pool$R, n_pc = 10L, do_factanal = TRUE, factanal_factors = 5L)
cat(sprintf("PC1 variance explained: %.1f%%  (KR 베타지배 진단)\n", 100*lf$pc1_variance_explained))
cat("scree (top 10):\n"); print(lf$scree)
cat("factanal status:", lf$factanal$status, "\n")
if (identical(lf$factanal$status, "ok"))
  cat(sprintf("  factanal uniqueness mean=%.3f pval=%s\n", lf$factanal$uniquenesses_mean,
              as.character(lf$factanal$pval)))

# ---- Gate 4.2 pure factor FWL (small scope: 3 months x 6 factors) ----
cat("\n===== Gate 4.2 pure factor FWL =====\n")
rawdata <- as.data.table(read_parquet(".cache/rawdata.parquet"))
cat("rawdata range:", as.character(min(rawdata$Date)), "..", as.character(max(rawdata$Date)),
    " nrow:", nrow(rawdata), "\n")

test_factors <- c("M01_Mom_12_1", "V02_EP", "Q01_GPA", "D02_Beta",
                  "S01_Size", "L01_Amihud")
# pick a few recent month-ends for the debug
sig_dates <- as.Date(c("2024-01-31", "2024-02-29", "2024-03-31"))
pf <- extract_pure_factor(test_factors, sig_dates, rawdata, verbose = TRUE)
cat(sprintf("pure factor score rows: %d ; factors seen: %s\n",
            nrow(pf$scores), paste(unique(pf$scores$factor_id), collapse=",")))
cat("orthogonality summary (FWL working evidence |cor(z_pure,X)|<0.05):\n")
print(pf$orth_summary[, .(factor_id, status, n, max_orth_cor = round(max_orth_cor,4),
                          sec_r2 = round(sector_residual_r2,4), orthogonality_pass)])

cat(sprintf("\n[gate4 debug] elapsed: %.1f sec\n", as.numeric(Sys.time()-t0, units="secs")))
sink()
cat("debug_one_gate4 done\n")
