j <- jsonlite::fromJSON("stage_artifacts/scrap_ensemble_20260809/prereg_power_bars.json",
                        simplifyVector = FALSE)
cat("verdict =", j$meta$verdict, "\n")
cat("top keys =", paste(names(j), collapse = ", "), "\n")
cat("n bars   =", length(j$bars), "\n")
cat("bar keys =", paste(names(j$bars[[1]]), collapse = ","), "\n")
cat("bytes    =", file.size("stage_artifacts/scrap_ensemble_20260809/prereg_power_bars.json"), "\n\n")
for (b in j$bars) cat(sprintf("  %-22s n=%3d sd=%7.4f req_m=%7.4f req_y=%7.3f plausible=%s\n",
  b$arm_or_bucket, b$n, b$sd_monthly_pct, b$required_effect_pct_per_month,
  b$required_pct_per_year, b$plausible))
cat("\ncorrections:\n")
cat(" sec4 cited", j$p0_citation_corrections$sec4_uncond_rho$cited,
    "-> dedup85", j$p0_citation_corrections$sec4_uncond_rho$dedup85_vs_bm, "\n")
cat(" sec6 cited", j$p0_citation_corrections$sec6_resid$cited_n_t_gt2,
    "-> recomputed", j$p0_citation_corrections$sec6_resid$recomputed_vs_base, "\n")
