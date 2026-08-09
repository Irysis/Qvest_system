## S5 — 전 팩터 × 61개월 죽은-배출 센서스
##   "배출 O(ledger n_rows>0) 인데 소비면 가시 0" = Z 전건 NA
##   = 빌더 682행 `sd(Raw_W) < 1e-12 → NA` = 횡단면 상수 배출
##   6개 표본월로는 D60/Q16 같은 창-국한 사망을 놓친다 → 반기 격자로 전수화
suppressPackageStartupMessages({ library(data.table) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/infra/factor_emission_identity_20260809")
say <- function(fmt, ...) { cat(sprintf(paste0("[s5] ", fmt, "\n"), ...)); flush.console() }
t0 <- Sys.time()
source("02_Infrastructure/config.R")
source("02_Infrastructure/factor_db/factor_db_connector.R")
led <- fread(".cache/factor_db/emission_ledger.csv", colClasses = list(character = "ym"))

yrs <- 1996:2026
dates <- sort(as.Date(unlist(lapply(yrs, function(y) c(sprintf("%d-06-30", y), sprintf("%d-12-31", y))))))
dates <- dates[dates <= as.Date("2026-08-31")]

rows <- list()
for (d in dates) {
  d <- as.Date(d, origin = "1970-01-01")
  z <- tryCatch(load_month_factors(d, coverage_min = 0), error = function(e) NULL)
  if (is.null(z)) next
  ymf <- sub("^factor_db_(\\d{6})\\.parquet$", "\\1", attr(z, "factor_db_file"))
  visible <- unique(as.data.table(z)$Factor_Name)
  em <- led[ym == ymf & n_rows > 0, .(Factor_Name, n_rows, n_tickers)]
  if (!nrow(em)) next
  em[, `:=`(ym = ymf, visible = Factor_Name %in% visible)]
  rows[[ymf]] <- em
}
cen <- unique(rbindlist(rows), by = c("ym", "Factor_Name"))
fwrite(cen, file.path(OUT, "s5_census_month_factor.csv"))
say("센서스: 월 %d · 팩터 %d · (월,팩터) 셀 %s · %.1fs",
    uniqueN(cen$ym), uniqueN(cen$Factor_Name), format(nrow(cen), big.mark = ","),
    as.numeric(difftime(Sys.time(), t0, units = "secs")))

agg <- cen[, .(n_emitted = .N, n_dead = sum(!visible), n_live = sum(visible),
               dead_yms = paste(ym[!visible], collapse = " ")), by = Factor_Name]
agg[, dead_frac := n_dead / n_emitted]
agg[, klass := fifelse(n_dead == 0L, "LIVE",
              fifelse(n_dead == n_emitted, "DEAD_ALWAYS", "DEAD_PARTIAL"))]
setorder(agg, -n_dead, Factor_Name)
fwrite(agg, file.path(OUT, "s5_dead_census_verdict.csv"))

say("=== 배출 셀 대비 죽은 배출 ===")
print(agg[, .(n_factors = .N, cells_emitted = sum(n_emitted), cells_dead = sum(n_dead)), by = klass])
say("=== DEAD_ALWAYS (전 배출월 소비면 0) ===")
for (i in which(agg$klass == "DEAD_ALWAYS")) with(agg[i], say("  %-32s %d/%d월", Factor_Name, n_dead, n_emitted))
say("=== DEAD_PARTIAL (일부 창만 사망 — ★버그 서명) ===")
for (i in which(agg$klass == "DEAD_PARTIAL")) with(agg[i], say(
  "  %-32s %d/%d월 (%.1f%%) · 사망월: %s", Factor_Name, n_dead, n_emitted, 100 * dead_frac, dead_yms))
say("총 %.1fs · 완료", as.numeric(difftime(Sys.time(), t0, units = "secs")))
