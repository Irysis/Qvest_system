#==============================================================================
# WT-D20260711_001 — Step 4: BLIND-BREAK. Merge forward 12M returns, correlations.
# Executes FROZEN measurement (preregistration.json sha256 beba7a3c...).
# Scores were frozen (scores.csv sha256 d7b05e81...) BEFORE this returns access.
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
OUT  <- file.path(ROOT, "stage_artifacts/WT_D20260711_001")
set.seed(20260711)

scores <- fread(file.path(OUT, "scores.csv"))
meta   <- as.data.table(read_parquet(file.path(OUT, "excerpts_meta.parquet")))
pool   <- as.data.table(read_parquet(file.path(OUT, "candidate_pool.parquet")))
mp     <- readRDS(file.path(OUT, "monthly_panel.rds")); me <- mp$me; bench <- mp$bench_m

# --- merge meta + Size-at-snapshot (from candidate pool) ---
d <- merge(scores, meta, by = "doc_id")
d <- merge(d, pool[, .(Ticker, fiscal_year, Size, snap_ym)], by = c("Ticker","fiscal_year"), all.x = TRUE)
d[, logSize := log(Size)]

# --- forward 12M returns: window = 12 months STARTING the month AFTER rcept month (clean PIT) ---
ym_add <- function(ym, k) { y <- ym %/% 100L; m <- ym %% 100L; t <- (y*12L + (m-1L)) + k; (t %/% 12L)*100L + (t %% 12L) + 1L }
setkey(me, Ticker, ym); setkey(bench, ym)

fwd <- function(tk, rcept_dt) {
  rym <- as.integer(substr(rcept_dt,1,4))*100L + as.integer(substr(rcept_dt,5,6))
  yms <- vapply(1:12, function(k) ym_add(rym, k), integer(1))     # month after rcept, 12 months
  r <- me[.(tk, yms), on = c("Ticker","ym"), mret]
  b <- bench[.(yms), on = "ym", bench_mret]
  n_ok <- sum(!is.na(r))
  if (n_ok < 10) return(list(tot = NA_real_, bch = NA_real_, exc = NA_real_, n = n_ok))
  tot <- prod(1 + r[!is.na(r)]) - 1
  bch <- prod(1 + b[!is.na(b)]) - 1
  list(tot = tot, bch = bch, exc = tot - bch, n = n_ok)
}
res <- d[, { f <- fwd(Ticker, rcept_dt); .(fwd12m_total = f$tot, fwd12m_bench = f$bch, fwd12m_excess = f$exc, n_months = f$n) }, by = doc_id]
d <- merge(d, res, by = "doc_id")

# composite: higher = predicted-better outlook (all axes sign-aligned)
d[, composite := tone + (6 - uncertainty) + (6 - complexity)]

cat("=== merged sample ===\n")
cat("N docs:", nrow(d), " | with fwd return:", sum(!is.na(d$fwd12m_excess)), " | full 12m:", sum(d$n_months==12, na.rm=TRUE), "\n")
cat("fwd12m_excess summary:\n"); print(summary(d$fwd12m_excess))
cat("fwd12m_total summary:\n"); print(summary(d$fwd12m_total))

da <- d[!is.na(fwd12m_excess)]
saveRDS(da, file.path(OUT, "analysis_merged.rds"))
write_parquet(da[, .(doc_id, Ticker, corp_name, cap_tier, fiscal_year, rcept_dt, tone, uncertainty, complexity, composite, low_content, logSize, fwd12m_total, fwd12m_bench, fwd12m_excess, n_months)], file.path(OUT, "analysis_merged.parquet"))

# --- Spearman + bootstrap 90% CI ---
spear <- function(x, y) suppressWarnings(cor(x, y, method="spearman", use="complete.obs"))
boot_ci <- function(x, y, B=2000, probs=c(.05,.95)) {
  n <- length(x); rs <- numeric(B)
  for (b in 1:B) { i <- sample.int(n, n, replace=TRUE); rs[b] <- spear(x[i], y[i]) }
  quantile(rs, probs, na.rm=TRUE)
}
# partial spearman controlling for z (rank-based residualization)
partial_spear <- function(x, y, z) {
  rx <- rank(x); ry <- rank(y); rz <- rank(z)
  ex <- residuals(lm(rx ~ rz)); ey <- residuals(lm(ry ~ rz))
  suppressWarnings(cor(ex, ey, method="pearson"))
}
partial_boot_ci <- function(x, y, z, B=2000, probs=c(.05,.95)) {
  n <- length(x); rs <- numeric(B)
  for (b in 1:B) { i <- sample.int(n, n, replace=TRUE); rs[b] <- tryCatch(partial_spear(x[i], y[i], z[i]), error=function(e) NA_real_) }
  quantile(rs, probs, na.rm=TRUE)
}

axes <- c("tone","uncertainty","complexity","composite")
hyp_sign <- c(tone=+1, uncertainty=-1, complexity=-1, composite=+1)

run_block <- function(dat, label) {
  cat("\n========================", label, "(N=", nrow(dat), ") ========================\n")
  out <- list()
  for (ax in axes) {
    x <- dat[[ax]]
    for (tgt in c("fwd12m_excess","fwd12m_total")) {
      y <- dat[[tgt]]
      rho <- spear(x, y); ci <- boot_ci(x, y)
      excl0 <- (ci[1] > 0) | (ci[2] < 0)
      dir_ok <- sign(rho) == hyp_sign[[ax]]
      cat(sprintf("%-11s vs %-14s rho=%+.3f  90%%CI[%+.3f,%+.3f]  excl0=%s dir_match=%s\n",
                  ax, tgt, rho, ci[1], ci[2], excl0, dir_ok))
      out[[paste(ax,tgt)]] <- list(axis=ax, target=tgt, rho=rho, ci_lo=ci[1], ci_hi=ci[2], excl0=excl0, dir_match=dir_ok)
    }
  }
  # Size confound
  cat("--- Size confound (vs logSize) + partial (excess | logSize) ---\n")
  for (ax in axes) {
    x <- dat[[ax]]
    r_size <- spear(x, dat$logSize)
    pr <- partial_spear(x, dat$fwd12m_excess, dat$logSize)
    pci <- partial_boot_ci(x, dat$fwd12m_excess, dat$logSize)
    raw <- spear(x, dat$fwd12m_excess)
    collapse <- if (abs(raw) < 1e-9) NA else (abs(pr) < 0.5*abs(raw))
    cat(sprintf("%-11s  cor(axis,logSize)=%+.3f  raw rho(excess)=%+.3f  partial=%+.3f 90%%CI[%+.3f,%+.3f]  collapse>50%%=%s\n",
                ax, r_size, raw, pr, pci[1], pci[2], collapse))
    out[[paste(ax,"partial")]] <- list(axis=ax, cor_size=r_size, raw=raw, partial=pr, pci_lo=pci[1], pci_hi=pci[2], collapse=collapse)
  }
  out
}

full <- run_block(da, "FULL SAMPLE")
hi   <- run_block(da[low_content==0], "EXCL low-content (governance-boilerplate extractions)")

saveRDS(list(full=full, hiq=hi, n_full=nrow(da), n_hi=nrow(da[low_content==0])), file.path(OUT, "corr_results.rds"))
cat("\n[4] DONE\n")
