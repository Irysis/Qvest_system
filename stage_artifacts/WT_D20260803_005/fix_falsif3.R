suppressPackageStartupMessages({library(data.table)})
setwd(Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
OUT <- "stage_artifacts/WT_D20260803_005"
P1R <- readRDS(file.path(OUT,"persistence_results.rds")); META <- readRDS(file.path(OUT,"pool_meta.rds"))
DS <- META$dir_stat[!is.na(n_dir_flips)]
P <- merge(P1R$PR$primary, DS[, .(Factor_Name, n_dir_flips)], by="Factor_Name")
FLIP <- P[, .(n_pairs=.N, n_factors=uniqueN(Factor_Name), p=mean(sign(t_k)==sign(t_next))),
          by=.(dir_stable = n_dir_flips==0L)]
print(FLIP)
d <- FLIP[dir_stable==TRUE, p] - FLIP[dir_stable==FALSE, p]
v <- if (abs(d) < 0.10) "REJECTED_alignment_artifact" else "SUPPORTED"
cat(sprintf("falsif3: stable %.3f (%d factor) vs flipping %.3f (%d factor) | delta %+.3f -> %s\n",
  FLIP[dir_stable==TRUE,p], FLIP[dir_stable==TRUE,n_factors],
  FLIP[dir_stable==FALSE,p], FLIP[dir_stable==FALSE,n_factors], d, v))
fb <- readRDS(file.path(OUT,"finalize_bits.rds"))
fb$falsif3 <- list(p_stable=FLIP[dir_stable==TRUE,p], p_flipping=FLIP[dir_stable==FALSE,p],
                   n_factors_stable=FLIP[dir_stable==TRUE,n_factors],
                   n_factors_flipping=FLIP[dir_stable==FALSE,n_factors],
                   delta=d, verdict=v,
                   coverage_note="ic_sign NA(registry-fallback) 189 factor 제외 — 96/285 커버")
fb$flip_tab <- FLIP
saveRDS(fb, file.path(OUT,"finalize_bits.rds"))
cat("saved\n")
