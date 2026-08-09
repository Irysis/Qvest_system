## S4 — 죽은 배출의 시간 범위 확정 (표본 6월로는 못 재는 축)
##   대상: 축3a 에서 부분-비가시로 나온 D60_Leverage / Q16_Debt_to_Assets
##         + 전건 비가시 C15_Forecast_Error_Trend
##         + 양성 대조 C01_SUE / M26_Revenue_Mom
##   방법: load_month_factors(factor_names=...) — arrow pushdown, 재빌드 없음
suppressPackageStartupMessages({ library(data.table) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/infra/factor_emission_identity_20260809")
say <- function(fmt, ...) { cat(sprintf(paste0("[s4] ", fmt, "\n"), ...)); flush.console() }
source("02_Infrastructure/config.R")
source("02_Infrastructure/factor_db/factor_db_connector.R")
led <- fread(".cache/factor_db/emission_ledger.csv", colClasses = list(character = "ym"))

FS <- c("C15_Forecast_Error_Trend", "D60_Leverage", "Q16_Debt_to_Assets",
        "C01_SUE", "M26_Revenue_Mom")
## 1996~2026 매년 6월 + 12월 (62개월)
yrs <- 1996:2026
dates <- sort(as.Date(unlist(lapply(yrs, function(y) c(sprintf("%d-06-30", y), sprintf("%d-12-31", y))))))
dates <- dates[dates <= as.Date("2026-08-31")]

res <- rbindlist(lapply(dates, function(d) {
  z <- tryCatch(load_month_factors(d, coverage_min = 0, factor_names = FS),
                error = function(e) NULL)
  if (is.null(z)) return(NULL)
  fil <- attr(z, "factor_db_file")
  ymf <- sub("^factor_db_(\\d{6})\\.parquet$", "\\1", fil)
  zt <- as.data.table(z)
  visn <- zt[, .N, by = Factor_Name]
  rbindlist(lapply(FS, function(f) {
    lr <- led[ym == ymf & Factor_Name == f, sum(n_rows)]
    data.table(ym = ymf, Factor_Name = f,
               ledger_rows = if (length(lr)) as.integer(lr) else 0L,
               visible_rows = as.integer(visn[Factor_Name == f, N][1] %||% 0L))
  }))
}))
res <- unique(res, by = c("ym", "Factor_Name"))
res[is.na(visible_rows), visible_rows := 0L]
res[, state := fifelse(ledger_rows == 0L, "NOT_EMITTED",
              fifelse(visible_rows == 0L, "DEAD_EMISSION", "LIVE"))]
fwrite(res, file.path(OUT, "s4_scope_by_month.csv"))

say("검사 월 %d개 (%s ~ %s)", uniqueN(res$ym), min(res$ym), max(res$ym))
tb <- dcast(res, Factor_Name ~ state, value.var = "ym", fun.aggregate = length)
print(tb)
say("=== 팩터별 DEAD_EMISSION 월 목록 ===")
for (f in FS) {
  d <- res[Factor_Name == f & state == "DEAD_EMISSION", ym]
  l <- res[Factor_Name == f & state == "LIVE", ym]
  say("  %-26s DEAD %2d월 · LIVE %2d월 · 미배출 %2d월",
      f, length(d), length(l), res[Factor_Name == f & state == "NOT_EMITTED", .N])
  if (length(d)) say("      DEAD: %s", paste(d, collapse = " "))
  if (length(d) && length(l)) say("      LIVE: %s", paste(l, collapse = " "))
}
say("완료")
