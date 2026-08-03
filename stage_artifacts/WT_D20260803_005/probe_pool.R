# probe_pool.R — WT-005 사전 확인: factor DB 풀 크기 + 로드 시간
suppressPackageStartupMessages({library(data.table);library(arrow);library(jsonlite)})
setwd(Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
fs <- list.files(".cache/factor_db", pattern = "^factor_db_[0-9]{6}[.]parquet$")
cat("n monthly files:", length(fs), " range:", min(fs), max(fs), "\n")
t0 <- Sys.time()
source("02_Infrastructure/config.R")
source("02_Infrastructure/factor_db/factor_db_connector.R")
cat("source secs:", round(as.numeric(difftime(Sys.time(), t0, units = "secs")), 1), "\n")
t0 <- Sys.time()
d <- load_month_factors(as.Date("2015-06-30"))
cat("load month#1 secs:", round(as.numeric(difftime(Sys.time(), t0, units = "secs")), 2),
    " rows:", nrow(d), " factors:", uniqueN(d$Factor_Name), "\n")
t0 <- Sys.time()
d2 <- load_month_factors(as.Date("2015-07-31"))
cat("load month#2 secs:", round(as.numeric(difftime(Sys.time(), t0, units = "secs")), 2), "\n")

# registry labels
R <- fromJSON("02_Infrastructure/factor_db/factor_registry.json", simplifyVector = FALSE)
LAB <- rbindlist(lapply(names(R), function(k) {
  x <- R[[k]]
  g <- function(p) { v <- x$labels[[p]]; if (is.null(v) || length(v) == 0L) NA_character_ else as.character(v)[1] }
  st <- x$lifecycle$status; st <- if (is.null(st) || length(st) == 0L) NA_character_ else as.character(st)[1]
  data.table(Factor_Name = k, status = st, family = g("economic_family"),
             turnover_profile = g("turnover_profile"), capacity = g("capacity"),
             corr_group = g("correlation_group"), evidence = g("evidence_tier"),
             horizon = g("horizon"), neutrality = g("neutrality"))
}), fill = TRUE)
cat("\n--- registry status ---\n"); print(table(LAB$status, useNA = "ifany"))
cat("\n--- family ---\n"); print(sort(table(LAB$family, useNA = "ifany"), decreasing = TRUE))
cat("\n--- turnover_profile ---\n"); print(table(LAB$turnover_profile, useNA = "ifany"))
cat("\n--- capacity ---\n"); print(table(LAB$capacity, useNA = "ifany"))
saveRDS(LAB, "stage_artifacts/WT_D20260803_005/registry_labels.rds")

# 월별 파케이 실재 factor (2015-06 기준) vs registry
inpq <- sort(unique(d$Factor_Name))
cat("\nparquet factors(2015-06):", length(inpq), " | registry:", nrow(LAB),
    " | parquet & active:", length(intersect(inpq, LAB[status == "active", Factor_Name])), "\n")
EOF_MARK <- TRUE
