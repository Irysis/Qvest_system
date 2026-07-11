#==============================================================================
# WT-D20260711_001 — Step 5: Self-Adversarial robustness on the complexity signal
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
OUT  <- file.path(ROOT, "stage_artifacts/WT_D20260711_001")
set.seed(20260711)
da <- readRDS(file.path(OUT, "analysis_merged.rds"))
spear <- function(x,y) suppressWarnings(cor(x,y,method="spearman",use="complete.obs"))

cat("=== 1. Permutation p-values (2-sided) vs fwd12m_excess, FULL N=", nrow(da), " ===\n")
perm_p <- function(x, y, B=20000) {
  obs <- spear(x,y); cnt <- 0
  for (b in 1:B) { if (abs(spear(x, sample(y))) >= abs(obs)-1e-12) cnt <- cnt+1 }
  (cnt+1)/(B+1)
}
for (ax in c("tone","uncertainty","complexity","composite")) {
  p <- perm_p(da[[ax]], da$fwd12m_excess)
  cat(sprintf("  %-11s rho=%+.3f  perm p=%.4f\n", ax, spear(da[[ax]], da$fwd12m_excess), p))
}

cat("\n=== 2. Influence: drop the single max-excess outlier (Wemade D019, +2.80) ===\n")
da2 <- da[order(-fwd12m_excess)]
cat("  top-3 excess docs:", paste(da2$doc_id[1:3], round(da2$fwd12m_excess[1:3],2), collapse=" | "), "\n")
d_no1 <- da[doc_id != da2$doc_id[1]]
for (ax in c("tone","complexity")) cat(sprintf("  drop-max %-11s rho=%+.3f (was %+.3f)\n", ax, spear(d_no1[[ax]], d_no1$fwd12m_excess), spear(da[[ax]], da$fwd12m_excess)))
# jackknife complexity: recompute rho leaving each obs out
jk <- sapply(1:nrow(da), function(i) spear(da$complexity[-i], da$fwd12m_excess[-i]))
cat(sprintf("  complexity jackknife rho range=[%+.3f, %+.3f] (all same sign=%s)\n", min(jk), max(jk), all(sign(jk)<0)))

cat("\n=== 3. complexity signal WITHIN cap_tier (rule out size-tier artifact) ===\n")
for (ct in c("LARGE","MID","SMALL")) {
  s <- da[cap_tier==ct]; cat(sprintf("  %-5s n=%d  rho(complexity,excess)=%+.3f  mean_complexity=%.2f\n", ct, nrow(s), spear(s$complexity, s$fwd12m_excess), mean(s$complexity)))
}
cat("  complexity mean by tier (is complexity itself a size proxy?):\n")
print(da[, .(mean_complexity=round(mean(complexity),2), mean_logSize=round(mean(logSize),2), .N), by=cap_tier][order(-mean_logSize)])

cat("\n=== 4. within year_bin (rule out time/vintage artifact) ===\n")
for (yb in c("FILE_2015_2017","FILE_2018_2020","FILE_2021_2023")) {
  s <- da[year_bin==yb]; cat(sprintf("  %-15s n=%d  rho(complexity,excess)=%+.3f\n", yb, nrow(s), spear(s$complexity, s$fwd12m_excess)))
}

cat("\n=== 5. tone (reverse-sign finding) robustness vs excess AND total ===\n")
cat(sprintf("  tone vs excess rho=%+.3f  vs total rho=%+.3f  (hypothesis was +; realized -)\n", spear(da$tone,da$fwd12m_excess), spear(da$tone,da$fwd12m_total)))
cat(sprintf("  tone perm p (excess)=%.4f\n", perm_p(da$tone, da$fwd12m_excess)))

cat("\n[5] DONE\n")
