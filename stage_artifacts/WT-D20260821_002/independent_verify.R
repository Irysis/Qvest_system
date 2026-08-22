## 독립 검증 — verdict.R 경로와 다른 자구로 co-primary NW3 t 재산출 (post-lock, 순서 무관)
suppressPackageStartupMessages({library(data.table); library(jsonlite)})
setwd(Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
G <- readRDS("stage_artifacts/WT-D20260821_002/gate_series.rds")

## 자체 구현 Bartlett-kernel NW (verdict.R 의 nw_t 와 독립 자구)
nw_t_indep <- function(x, lag = 3L) {
  x <- as.numeric(x); n <- length(x); m <- mean(x); e <- x - m
  g0 <- sum(e * e) / n
  s <- g0
  for (k in 1:lag) {
    gk <- sum(e[(k + 1):n] * e[1:(n - k)]) / n
    s <- s + 2 * (1 - k / (lag + 1)) * gk
  }
  se <- sqrt(s / n)
  list(mean = m, se = se, t = m / se, n = n)
}
## sandwich 패키지 경유 2차 대조 (있으면)
nw_t_sandwich <- function(x, lag = 3L) {
  if (!requireNamespace("sandwich", quietly = TRUE) ||
      !requireNamespace("lmtest", quietly = TRUE)) return(NA_real_)
  df <- data.frame(y = as.numeric(x))
  fit <- stats::lm(y ~ 1, data = df)
  V <- sandwich::NeweyWest(fit, lag = lag, prewhite = FALSE, adjust = FALSE)
  unname(coef(fit)[1] / sqrt(V[1, 1]))
}

out <- list()
for (key in c("F3L|c_vs_a", "F3L|b_vs_a", "F0|c_vs_a", "F0|b_vs_a",
              "F1|c_vs_a", "F1|b_vs_a", "F2|c_vs_a", "F2|b_vs_a")) {
  d <- G$diffs[[key]]$d
  r <- nw_t_indep(d)
  out[[key]] <- list(n = r$n, mean_monthly = r$mean, mean_annual_pct = 100 * 12 * r$mean,
                     sd_monthly = sd(d), t_nw3_indep = r$t,
                     t_nw3_sandwich = nw_t_sandwich(d),
                     t_iid = r$mean / (sd(d) / sqrt(r$n)))
}
cat("=== 독립 재산출 (Bartlett NW lag-3 자체구현 + sandwich 대조) ===\n")
for (k in names(out)) {
  o <- out[[k]]
  cat(sprintf("%-12s n=%3d  mean_ann %+7.4f%%p  sd %.6f  t_indep %+7.4f  t_sand %+7.4f  t_iid %+7.4f\n",
              k, o$n, o$mean_annual_pct, o$sd_monthly, o$t_nw3_indep, o$t_nw3_sandwich, o$t_iid))
}
write_json(out, "stage_artifacts/WT-D20260821_002/independent_verify.json",
           auto_unbox = TRUE, pretty = TRUE, digits = 10, na = "null")
