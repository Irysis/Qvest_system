# run_wt014_post.R — WT-014 사후 진단 추출 (advisory 병기 — 판정 변경 없음)
#   abs 지표 + 부기간 paired Δ (post-hoc diagnostic 라벨)
suppressPackageStartupMessages({ library(data.table); library(sandwich); library(lmtest) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT_D20260802_014")
R <- readRDS(file.path(OUT, "wt014_eval_results.rds"))
say <- function(fmt, ...) cat(sprintf(paste0("[wt014p] ", fmt, "\n"), ...))
nw_t <- function(x, lag = 3L) {
  x <- x[is.finite(x)]
  if (length(x) < 6L) return(NA_real_)
  fit <- lm(x ~ 1)
  tryCatch(as.numeric(lmtest::coeftest(fit,
      vcov. = sandwich::NeweyWest(fit, lag = lag, prewhite = FALSE))[1, 3]),
    error = function(e) NA_real_)
}
b <- R$base; f <- R$filtered
say("abs: base SR=%.3f CAGR=%.4f MDD=%.4f | filt SR=%.3f CAGR=%.4f MDD=%.4f",
    b$abs_net_sr, b$abs_cagr, b$abs_mdd, f$abs_net_sr, f$abs_cagr, f$abs_mdd)
PD <- as.data.table(R$paired_series)
sub <- function(a, z) {
  d <- PD[date >= a & date <= z]
  list(n = nrow(d), mean_d = d[, mean(d_active)], t = nw_t(d$d_active))
}
s1 <- sub("1900-01-01", "2014-12-31"); s2 <- sub("2015-01-01", "2019-12-31")
s3 <- sub("2020-01-01", "2099-01-01"); s4 <- sub("2017-01-01", "2099-01-01")
say("부기간 Δactive: pre2015 n=%d %+.5f t=%+.2f | 2015-19 n=%d %+.5f t=%+.2f | 2020+ n=%d %+.5f t=%+.2f | post2017 n=%d %+.5f t=%+.2f",
    s1$n, s1$mean_d, s1$t, s2$n, s2$mean_d, s2$t, s3$n, s3$mean_d, s3$t, s4$n, s4$mean_d, s4$t)
# filtered 자체 부기간 PORT_t (base 대비 아님 — 수준)
saveRDS(c(R, list(post_diag = list(
  abs = list(base = b[c("abs_net_sr","abs_cagr","abs_mdd")],
             filtered = f[c("abs_net_sr","abs_cagr","abs_mdd")]),
  subperiod_paired = list(pre2015 = s1, y2015_19 = s2, y2020p = s3, post2017 = s4),
  label = "post-hoc diagnostic — 사전등록 판정 불변"))),
  file.path(OUT, "wt014_eval_results.rds"))
say("완료")
