## S6 — 축3 살아있음 전수화 (61개월 × 전 가시 팩터)
##   sd(Z)=1 은 표준화 항등 → 판별력 0. 살아있는 통계:
##     modal_frac = 최빈값 점유율 (raw 0값 비율의 Z-면 등가)
##     uniq_ratio = 고유값/관측수
##   ★"죽은 배출"은 이진이 아니라 연속체 — 문턱 0.99 만으로는 0.94 를 놓친다.
suppressPackageStartupMessages({ library(data.table) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/infra/factor_emission_identity_20260809")
say <- function(fmt, ...) { cat(sprintf(paste0("[s6] ", fmt, "\n"), ...)); flush.console() }
t0 <- Sys.time()
source("02_Infrastructure/config.R")
source("02_Infrastructure/factor_db/factor_db_connector.R")

yrs <- 1996:2026
dates <- sort(as.Date(unlist(lapply(yrs, function(y) c(sprintf("%d-06-30", y), sprintf("%d-12-31", y))))))
dates <- dates[dates <= as.Date("2026-08-31")]

modal_uniq <- function(v) {
  v <- v[is.finite(v)]
  n <- length(v)
  if (!n) return(c(NA_real_, NA_real_, NA_real_))
  s <- sort(round(v, 10))
  r <- rle(s)
  c(max(r$lengths) / n, length(r$lengths) / n, mean(v == 0))
}

out <- list()
for (d in dates) {
  d <- as.Date(d, origin = "1970-01-01")
  z <- tryCatch(load_month_factors(d, coverage_min = 0), error = function(e) NULL)
  if (is.null(z)) next
  ymf <- sub("^factor_db_(\\d{6})\\.parquet$", "\\1", attr(z, "factor_db_file"))
  zt <- as.data.table(z)
  st <- zt[, {
    m <- modal_uniq(Z_Score_Aligned)
    .(n_obs = .N, modal_frac = m[1], uniq_ratio = m[2], zero_frac = m[3])
  }, by = Factor_Name]
  st[, ym := ymf]
  out[[ymf]] <- st
}
lv <- unique(rbindlist(out), by = c("ym", "Factor_Name"))
fwrite(lv, file.path(OUT, "s6_liveness_month_factor.csv"))
say("가시 셀 %s · 월 %d · 팩터 %d · %.1fs", format(nrow(lv), big.mark = ","),
    uniqueN(lv$ym), uniqueN(lv$Factor_Name), as.numeric(difftime(Sys.time(), t0, units = "secs")))

agg <- lv[, .(n_months = .N, max_modal = max(modal_frac, na.rm = TRUE),
              med_modal = as.numeric(median(modal_frac, na.rm = TRUE)),
              min_uniq = min(uniq_ratio, na.rm = TRUE),
              n_m99 = sum(modal_frac >= 0.99, na.rm = TRUE),
              n_m95 = sum(modal_frac >= 0.95, na.rm = TRUE),
              n_m90 = sum(modal_frac >= 0.90, na.rm = TRUE)), by = Factor_Name]
setorder(agg, -n_m99, -max_modal)
fwrite(agg, file.path(OUT, "s6_liveness_verdict.csv"))

say("=== 문턱별 팩터 수 (하나 이상의 월에서 초과) ===")
say("  modal_frac >= 0.99 : %d종 / >=0.95 : %d종 / >=0.90 : %d종 (전체 %d종)",
    agg[n_m99 > 0, .N], agg[n_m95 > 0, .N], agg[n_m90 > 0, .N], nrow(agg))
say("=== modal_frac >= 0.99 인 월이 있는 팩터 (준-죽은 배출) ===")
for (i in which(agg$n_m99 > 0)) with(agg[i], say(
  "  %-32s %d/%d월 >=0.99 · max %.4f · med %.4f · min_uniq %.5f",
  Factor_Name, n_m99, n_months, max_modal, med_modal, min_uniq))
say("=== modal_frac >= 0.95 (0.99 미만 포함) 상위 15 ===")
print(head(agg[n_m95 > 0][order(-n_m95, -max_modal)], 15))

say("=== 부채 계열 시대분해 (D60/Q16 사망 창과의 정합) ===")
DBT <- c("Q15_Debt_to_Equity", "Q16_Debt_to_Assets", "D60_Leverage",
         "XF_LL01_DebtToCapital", "R17_Market_Leverage")
e <- lv[Factor_Name %in% DBT]
e[, era := fifelse(ym < "201501", "pre2015", fifelse(ym < "202601", "2015_2025", "2026+"))]
print(e[, .(n_visible_months = .N, med_modal = round(as.numeric(median(modal_frac)), 4),
            max_modal = round(max(modal_frac), 4)), by = .(Factor_Name, era)][order(Factor_Name, era)])
say("총 %.1fs · 완료", as.numeric(difftime(Sys.time(), t0, units = "secs")))
