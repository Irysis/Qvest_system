ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
OUT  <- file.path(ROOT, "stage_artifacts/WT_D20260808_001")
say <- function(...) cat(sprintf(...), "\n")

pc <- readRDS(file.path(OUT, "precheck_results.rds"))
say("== precheck names: %s", paste(names(pc), collapse=", "))
say("--- f1 table (F1 quintile spreads) ---")
print(pc$f1)
say("--- power ---")
for (n in names(pc$power)) {
  p <- pc$power[[n]]
  say("%s: k_mean=%.4f  placebo_sd_med=%.6f  n_months=%d  req_monthly=%.6f  req_annual_pct=%.4f",
      n, p$k_mean, p$placebo_sd_median, p$n_months, p$required_monthly, 100*p$required_annual)
}
say("--- derived: prior effect = |Q1_minus_Q3| * k/25 ---")
f1 <- pc$f1
for (i in seq_len(nrow(f1))) {
  fn <- f1$F_[i]; k <- pc$power[[fn]]$k_mean
  say("%s: Q1-Q3=%.4f  Q5-Q3=%.4f  k=%.4f  |Q1-Q3|*k/25 = %.4f   |Q5-Q3|*k/25 = %.4f",
      fn, f1$Q1_minus_Q3_ann[i], f1$Q5_minus_Q3_ann[i], k,
      abs(f1$Q1_minus_Q3_ann[i])*k/25, abs(f1$Q5_minus_Q3_ann[i])*k/25)
}
say("--- p_hit ---"); print(pc$p_hit)
say("--- band ---"); print(pc$band)

r <- readRDS(file.path(OUT, "wt122_results.rds"))
say("== results names: %s", paste(names(r), collapse=", "))
say("--- F3 ---")
str(r$F3)
say("--- F2 ---")
str(r$F2)
a <- readRDS(file.path(OUT, "wt122_addendum.rds"))
say("== addendum names: %s", paste(names(a), collapse=", "))
str(a)
