al <- readRDS("../aligned_series.rds")
act <- al$book_ret - al$bench_ret
fit <- lm(act ~ 1)
for (adj in c(TRUE, FALSE)) for (pw in c(FALSE, TRUE)) {
  se <- sqrt(diag(sandwich::NeweyWest(fit, lag = 3, prewhite = pw, adjust = adj)))
  cat(sprintf("adjust=%s prewhite=%s t=%.4f\n", adj, pw, coef(fit)[1] / se))
}
