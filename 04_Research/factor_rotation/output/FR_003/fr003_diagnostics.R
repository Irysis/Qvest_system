#!/usr/bin/env Rscript
# FR_003 진단 — 계약 산출물(bt$period_returns / bt$benchmark_returns)만 읽는다.
#   성과 수치를 새로 만들지 않는다. 여기서 내는 것은 *반증용 회귀 진단*이다(F1 베타 트랩).
suppressPackageStartupMessages({ library(data.table); library(sandwich); library(lmtest) })
PROJ <- Sys.getenv("CLAUDE_PROJECT_DIR", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
OUT  <- file.path(PROJ, "04_Research/factor_rotation/output")
args <- commandArgs(trailingOnly = TRUE)          # arm 파일 basename 들
.nw_t <- function(fit, lag = 3L) {
  ct <- tryCatch(coeftest(fit, vcov. = NeweyWest(fit, lag = lag, prewhite = FALSE)),
                 error = function(e) NULL)
  if (is.null(ct)) return(c(NA_real_, NA_real_))
  c(ct[1, 1], ct[1, 3])
}
res <- list()
for (a in args) {
  f <- file.path(OUT, paste0(a, "_bt_result.rds")); if (!file.exists(f)) { cat("[skip]", a, "\n"); next }
  bt <- readRDS(f)
  pr <- as.data.table(bt$period_returns)[, .(date, ret_net)]
  br <- as.data.table(bt$benchmark_returns)[, .(date, benchmark_ret)]
  M  <- merge(pr, br, by = "date"); setorder(M, date)
  fit_raw <- lm(ret_net ~ benchmark_ret, data = M)               # β + α(월)
  ab <- .nw_t(fit_raw)
  # 하락월/심도별 초과 (방어 기전이 볼록한지 — 선형 β 로 안 잡히는 부분)
  M[, act := ret_net - benchmark_ret]
  dn <- M[benchmark_ret < 0]; dp <- M[benchmark_ret >= 0]; deep <- M[benchmark_ret <= -0.10]
  res[[a]] <- data.table(
    arm = a, n_months = nrow(M),
    beta = round(unname(coef(fit_raw)[2]), 4),
    alpha_m_pct = round(100 * ab[1], 4), alpha_t_nw3 = round(ab[2], 3),
    r2 = round(summary(fit_raw)$r.squared, 4),
    down_n = nrow(dn), down_excess_pct = round(100 * mean(dn$act), 4),
    down_hit = round(mean(dn$act > 0), 4),
    deep_n = nrow(deep), deep_excess_pct = if (nrow(deep)) round(100 * mean(deep$act), 4) else NA_real_,
    up_excess_pct = round(100 * mean(dp$act), 4))
}
R <- rbindlist(res, fill = TRUE); print(R)
fwrite(R, file.path(OUT, "FR_003/FR_003_beta_diagnostics.csv"))
# 두 arm 이 있으면 대응표본 차이 (같은 달만)
if (length(args) >= 2) {
  g <- function(a) { bt <- readRDS(file.path(OUT, paste0(a, "_bt_result.rds")))
    as.data.table(bt$period_returns)[, .(date, r = ret_net)] }
  A <- g(args[1]); B <- g(args[2]); P <- merge(A, B, by = "date", suffixes = c("_1", "_2"))
  d <- P$r_1 - P$r_2; fit <- lm(d ~ 1)
  ct <- coeftest(fit, vcov. = NeweyWest(fit, lag = 3L, prewhite = FALSE))
  cat(sprintf("\n[대응표본] %s - %s : n=%d  평균차 %+.4f%%/월  NW3 t=%.3f  p=%.4f\n",
              args[1], args[2], nrow(P), 100 * mean(d), ct[1, 3], ct[1, 4]))
}
