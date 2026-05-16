#==============================================================================
# Patch alpha_package_draft.json orthogonality block.
# Original: date-exact merge → 138m overlap (measurement artifact)
# Fix: year-month aligned merge → 265m overlap (proper measurement)
#==============================================================================

suppressPackageStartupMessages({
  library(arrow); library(data.table); library(jsonlite)
})

BASE <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
ART  <- file.path(BASE, "stage_artifacts/WT_D20260513_001")
MBOX <- file.path(BASE, "qepm/mailbox/worktask/WT-D20260513_001")

CANDIDATE_NAMES <- c(
  "C1_D01_IdioVol_LOW",
  "C2_D11_FP_Beta_LOW",
  "C3_HAR_RV_combine_LOW",
  "C4_D57_Down_Vol_LOW",
  "C5_Sophisticated_4axis_composite"
)

cr <- as.data.table(read_parquet(file.path(ART, "candidate_portfolio_returns.parquet")))
str1715 <- as.data.table(read_parquet(file.path(BASE, "stage_artifacts/WT_WT-S20260504_002/str1715_monthly_returns.parquet")))
str1715[, ym := format(as.Date(date), "%Y-%m")]
cr[, ym := format(as.Date(sig_date), "%Y-%m")]

ortho_fixed <- list()
for (cand in CANDIDATE_NAMES) {
  m <- merge(cr[candidate == cand, .(ym, cand_ret = portfolio_ret)],
             str1715[, .(ym, str1715_ret = ret_net)],
             by = "ym")
  m <- m[!is.na(cand_ret) & !is.na(str1715_ret) & is.finite(cand_ret) & is.finite(str1715_ret)]
  if (nrow(m) < 24) {
    ortho_fixed[[cand]] <- list(error = "insufficient_overlap", n = nrow(m))
    next
  }
  cor_p <- cor(m$cand_ret, m$str1715_ret, method = "pearson")
  cor_s <- cor(m$cand_ret, m$str1715_ret, method = "spearman")
  cor_k <- cor(m$cand_ret, m$str1715_ret, method = "kendall")
  ortho_fixed[[cand]] <- list(
    candidate = cand,
    n_overlap_months = nrow(m),
    returns_cor_pearson = round(cor_p, 4),
    returns_cor_spearman = round(cor_s, 4),
    returns_cor_kendall = round(cor_k, 4),
    orthogonality_rank_pass = cor_s < 0.30,
    orthogonality_return_pass = cor_p < 0.40,
    measurement_method = "year_month_aligned_merge"
  )
  cat(sprintf("%-40s cor_p=%.4f cor_s=%.4f n=%d\n", cand, cor_p, cor_s, nrow(m)))
}

# Patch the alpha_package_draft.json
pkg <- fromJSON(file.path(MBOX, "alpha_package_draft.json"), simplifyVector = FALSE)
best <- pkg$best_candidate
o <- ortho_fixed[[best]]
pkg$orthogonality_vs_STR_1715_admit <- list(
  returns_cor_pearson  = o$returns_cor_pearson,
  returns_cor_spearman = o$returns_cor_spearman,
  returns_cor_kendall  = o$returns_cor_kendall,
  rank_pass_lt_0_30 = o$orthogonality_rank_pass,
  return_pass_lt_0_40 = o$orthogonality_return_pass,
  n_overlap_months = o$n_overlap_months,
  measurement_method = "year_month_aligned_merge (corrected from date-exact merge)",
  previous_artifact_138m = "date-exact merge missed month-day labeling drift; YM-aligned 265m is correct"
)

# Also patch the per-candidate method_log cor values for traceability
log_list <- pkg$method_shopping_log$method_log
for (i in seq_along(log_list)) {
  cn <- log_list[[i]]$name
  if (!is.null(ortho_fixed[[cn]]) && !is.null(ortho_fixed[[cn]]$returns_cor_pearson)) {
    log_list[[i]]$cor_str_pearson_ym <- ortho_fixed[[cn]]$returns_cor_pearson
    log_list[[i]]$cor_str_spearman_ym <- ortho_fixed[[cn]]$returns_cor_spearman
    log_list[[i]]$n_overlap_ym <- ortho_fixed[[cn]]$n_overlap_months
  }
}
pkg$method_shopping_log$method_log <- log_list

write_json(pkg, file.path(MBOX, "alpha_package_draft.json"),
           pretty = TRUE, auto_unbox = TRUE, null = "null", na = "null")
cat("\nalpha_package_draft.json patched with YM-aligned orthogonality.\n")

# Save companion validation
fwrite(rbindlist(lapply(ortho_fixed, function(x) {
  if (!is.null(x$error)) return(data.table())
  data.table(candidate = x$candidate, n = x$n_overlap_months,
             cor_p = x$returns_cor_pearson, cor_s = x$returns_cor_spearman,
             cor_k = x$returns_cor_kendall,
             rank_pass = x$orthogonality_rank_pass,
             ret_pass = x$orthogonality_return_pass)
})), file.path(ART, "orthogonality_ym_aligned.csv"))
cat("orthogonality_ym_aligned.csv written.\n")
