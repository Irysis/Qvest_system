## FQ-169 P1 — 11종 팩터 패널 적재 (C15: load_month_factors 경유)
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/FQ169")
say  <- function(fmt, ...) { cat(sprintf(paste0("[p1] ", fmt, "\n"), ...)); flush.console() }
source("02_Infrastructure/config.R")
source("02_Infrastructure/factor_db/factor_db_connector.R")

FN <- c("D34_RealVol_21d","D35_RealVol_63d","D36_RealVol_126d","D41_Vol_of_Vol",
        "D42_EWMA_Vol","D45_Downside_Dev","D47_CVaR_5pct","D50_MaxDrawdown",
        "D03_RealVol","M26_Revenue_Mom","M01_Mom_12_1")

## 대상 월 = WT-D20260809_001 이 만든 수익 패널의 월말 (계약 경로 산출)
P <- readRDS(file.path(ROOT, "stage_artifacts/WT_D20260809_001/p0_panels.rds"))
ret <- as.data.table(P$ret)[!is.na(Ret_1m)]
mons <- sort(unique(ret$Date)); mons <- mons[mons >= as.Date("2003-01-01") & mons <= as.Date("2026-06-30")]
say("대상 월 %d개 (%s ~ %s)", length(mons), min(mons), max(mons))

acc <- vector("list", length(mons))
for (j in seq_along(mons)) {
  d <- mons[j]
  Fx <- tryCatch(as.data.table(load_month_factors(d, factor_names = FN)),
                 error = function(e) NULL)
  if (is.null(Fx) || !nrow(Fx)) next
  vcol <- if ("Z_Score_Aligned" %in% names(Fx)) "Z_Score_Aligned" else
          if ("Z_Score" %in% names(Fx)) "Z_Score" else NA_character_
  if (is.na(vcol)) { if (j == 1L) say("★값 컬럼 부재: %s", paste(names(Fx), collapse=",")); next }
  acc[[j]] <- Fx[Factor_Name %in% FN, .(Date = d, Ticker, Factor_Name, z = get(vcol))]
  if (j %% 40 == 0) say("  ... %d/%d (%s)", j, length(mons), d)
}
A <- rbindlist(acc, use.names = TRUE, fill = TRUE)
say("=== 적재 실측 ===")
say("  %d행 · %d개월 · %d종목 · 관측단위 (월말 Date x Ticker x Factor)",
    nrow(A), uniqueN(A$Date), uniqueN(A$Ticker))
print(A[, .(n_rows = .N, n_months = uniqueN(Date), n_tickers = uniqueN(Ticker)), by = Factor_Name][order(Factor_Name)])
miss <- setdiff(FN, unique(A$Factor_Name))
if (length(miss)) say("  ★미적재: %s (라운드에서 제외하고 기록)", paste(miss, collapse=", "))

W <- dcast(A, Date + Ticker ~ Factor_Name, value.var = "z")
W <- merge(W, ret[, .(Date, Ticker, Ret_1m)], by = c("Date","Ticker"))
W <- merge(W, as.data.table(P$liq)[, .(Date, Ticker, adv)], by = c("Date","Ticker"), all.x = TRUE)
say("  wide+수익 병합: %d행 · %d개월", nrow(W), uniqueN(W$Date))
say("  유동성필터(adv>=2e8) 후: %d행", nrow(W[is.na(adv) | adv >= 2e8]))
for (f in intersect(FN, names(W))) say("    %-18s 비결측 %.4f", f, mean(!is.na(W[[f]])))

saveRDS(W, file.path(OUT, "panel.rds"))
say("=== P1 완료 → panel.rds ===")
