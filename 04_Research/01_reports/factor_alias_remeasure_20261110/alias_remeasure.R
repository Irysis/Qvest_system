# 별칭(alias) 선언 재측정 — 등록부 dedup role = alias 인 모든 쌍(alias ~ canonical)의 순위 상관 · 최대 절대차
#   표본 = 등록부 evidence.window 와 같은 6개월(200506/201006/201406/201806/202206/202606) · 값 = 커넥터 Z_Score_Aligned
#   (emission_guard 축 I 와 같은 기준: 순위 · pairwise complete). 읽기 전용 — 결과만 JSON 으로 쓴다.
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
setwd("G:/OneDrive/Quant_Module_Moltbot")
suppressMessages(suppressWarnings({
  source("02_Infrastructure/config.R")
  source("02_Infrastructure/factor_db/factor_db_connector.R")
}))
reg <- fromJSON("02_Infrastructure/factor_db/factor_registry.json", simplifyVector = FALSE)
al <- rbindlist(lapply(names(reg), function(k) {
  d <- reg[[k]]$dedup
  if (is.null(d) || !identical(as.character(d$role)[1], "alias") || is.null(d$canonical)) return(NULL)
  data.table(alias = k, canonical = as.character(d$canonical)[1],
             defect = if (is.null(d$defect$kind)) NA_character_ else as.character(d$defect$kind)[1])
}))
cat(sprintf("[alias] 선언 %d쌍\n", nrow(al)))
months <- as.Date(c("2005-06-30", "2010-06-30", "2014-06-30", "2018-06-30", "2022-06-30", "2026-06-30"))
res <- rbindlist(lapply(months, function(d) {
  z <- suppressMessages(suppressWarnings(as.data.table(load_month_factors(d, coverage_min = 0))))
  ym <- format(d, "%Y%m")
  rbindlist(lapply(seq_len(nrow(al)), function(i) {
    a <- z[Factor_Name == al$alias[i], .(Ticker, a = Z_Score_Aligned)]
    b <- z[Factor_Name == al$canonical[i], .(Ticker, b = Z_Score_Aligned)]
    m <- merge(a, b, by = "Ticker")
    m <- m[is.finite(a) & is.finite(b)]
    data.table(ym = ym, alias = al$alias[i], canonical = al$canonical[i], n_a = nrow(a), n_b = nrow(b), n_common = nrow(m),
               rho = if (nrow(m) >= 30) cor(rank(m$a), rank(m$b)) else NA_real_,
               max_abs_diff = if (nrow(m)) max(abs(m$a - m$b)) else NA_real_)
  }))
}))
sm <- res[, .(months = sum(is.finite(rho)), min_rho = round(min(rho, na.rm = TRUE), 6), max_rho = round(max(rho, na.rm = TRUE), 6),
              med_n_common = as.integer(stats::median(n_common))), by = .(alias, canonical)]
sm <- merge(sm, al, by = c("alias", "canonical"))
setorder(sm, min_rho)
print(sm)
cat("\n월별 (C10 · C13):\n"); print(res[alias %in% c("C10_SUE_Persistence", "C13_Revision_Breadth_3m")])
out <- "04_Research/01_reports/factor_alias_remeasure_20261110/alias_remeasure_20261110.json"
writeLines(toJSON(list(measured_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"), months = format(months, "%Y%m"),
                       basis = "signal_rank (rank of Z_Score_Aligned, pairwise complete — emission_guard axis I 기준)",
                       summary = sm, by_month = res), auto_unbox = TRUE, digits = NA, pretty = TRUE), out, useBytes = TRUE)
cat("written", out, "\n")
