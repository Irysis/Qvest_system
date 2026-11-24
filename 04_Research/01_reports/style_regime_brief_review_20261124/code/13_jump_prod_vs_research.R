## 13_jump_prod_vs_research.R — 운영 함수(sw_jump_regime · 순수 R) 대 λ 선택 실행의 시험 경로(Rcpp) — 마지막 날 상태 · 지속 일수 대조
##   같은 자료 · 같은 (λ, κ) · 같은 적합 주기(분기)면 같은 상태여야 한다(두 구현 대조 · 어긋나면 운영 배선 보류).
suppressMessages({ library(arrow); library(data.table); library(jsonlite) })
a <- commandArgs(trailingOnly = TRUE); CODE <- a[1]; KF <- a[2]; JM <- a[3]
source(file.path(CODE, "02_Infrastructure/reports/style_jump_model.R"))
jp <- fromJSON(file.path(JM, "style_jump_params.json")); TP <- readRDS(file.path(JM, "style_jump_test_paths.rds"))
D <- as.data.table(read_parquet(file.path(KF, "kr_factor_returns_daily.parquet"), col_select = c("Date", "MKT", "SMB", "HML", "RMW", "CMA", "WML")))
D[, Date := as.Date(Date)]; setorder(D, Date); D <- D[complete.cases(D)]
ok_all <- TRUE
for (f in names(jp$factors)) {
  p <- jp$factors[[f]]; t0 <- Sys.time()
  z <- sw_jump_regime(D[[f]], D$MKT, D$Date, as.numeric(p$lambda), kappa = p$kappa,
                      refit_months = as.integer(jp$refit_months))
  te <- as.data.table(TP[[f]]$test); last <- te[.N]
  rl <- rle(te$state); dur <- rl$lengths[length(rl$lengths)]
  same <- isTRUE(z$ok) && z$state == last$state && z$days == dur
  ok_all <- ok_all && same
  cat(sprintf("%s %s · 운영 %s %d일(적합 %s · %.1f초) · 연구 %s %d일(%s)\n", if (same) "일치" else "불일치", f,
              if (isTRUE(z$ok)) ifelse(z$state == 1L, "강세", "약세") else "?", if (isTRUE(z$ok)) z$days else NA_integer_,
              if (isTRUE(z$ok)) format(z$fit_date) else "-", as.numeric(difftime(Sys.time(), t0, units = "secs")),
              ifelse(last$state == 1L, "강세", "약세"), dur, p$cfg))
}
quit(status = if (ok_all) 0L else 1L)
