## p1 — 팩터 DB 전수 패널 적재 (C15: load_month_factors 경유, PIT-safe)
## PG2 창(2004-02 ~ 2026-06, 269개월)에 맞춰 전 팩터를 long 으로 쌓는다.
## wide 로 펴면 329열이라 메모리 부담 — long 유지하고 소비 시점에 팩터별 subset.
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/pg2_hunt")
say  <- function(fmt, ...) { cat(sprintf(paste0("[p1] ", fmt, "\n"), ...)); flush.console() }
source("02_Infrastructure/config.R")
source("02_Infrastructure/factor_db/factor_db_connector.R")
source("02_Infrastructure/contracts/book_marginal.R")

B <- bm_load_incumbent()
P <- readRDS(file.path(ROOT, "stage_artifacts/WT_D20260809_001/p0_panels.rds"))
ret <- as.data.table(P$ret)[!is.na(Ret_1m)]
mons <- sort(unique(ret$Date))
mons <- mons[mons >= as.Date("2004-01-01") & mons <= as.Date("2026-06-30")]
say("=== 입력 실측 ===")
say("  PG2 창 %d개월 (%s ~ %s)", nrow(B), min(B$date), max(B$date))
say("  수익 패널 월 %d개 (%s ~ %s)", length(mons), min(mons), max(mons))

acc <- vector("list", length(mons)); t0 <- Sys.time()
for (j in seq_along(mons)) {
  d <- mons[j]
  Fx <- tryCatch(as.data.table(load_month_factors(d)), error = function(e) NULL)
  if (is.null(Fx) || !nrow(Fx)) next
  vcol <- if ("Z_Score_Aligned" %in% names(Fx)) "Z_Score_Aligned" else
          if ("Z_Score" %in% names(Fx)) "Z_Score" else NA_character_
  if (is.na(vcol)) next
  acc[[j]] <- Fx[, .(Date = d, Ticker, Factor_Name, z = get(vcol))]
  if (j %% 30 == 0) say("  ... %d/%d (%s) · 경과 %.1f분", j, length(mons), d,
                        as.numeric(difftime(Sys.time(), t0, units = "mins")))
}
A <- rbindlist(acc, use.names = TRUE, fill = TRUE)
say("=== 적재 실측 ===")
say("  %d행 · %d개월 · %d종목 · **%d팩터**", nrow(A), uniqueN(A$Date), uniqueN(A$Ticker), uniqueN(A$Factor_Name))

## 커버리지 필터 — 측정 가능한 팩터만 사냥 대상
COV <- A[, .(n_months = uniqueN(Date), n_obs = .N,
             avg_tickers = .N / uniqueN(Date)), by = Factor_Name]
COV[, eligible := n_months >= 120L & avg_tickers >= 30]
say("  커버리지: 적격(월>=120 ∧ 평균종목>=30) **%d / %d**", sum(COV$eligible), nrow(COV))
say("  탈락 사유 분해: 월<120 %d건 · 종목<30 %d건",
    sum(COV$n_months < 120L), sum(COV$avg_tickers < 30))
print(COV[order(-n_months)][1:8])

A <- A[Factor_Name %in% COV[eligible == TRUE, Factor_Name]]
A <- merge(A, ret[, .(Date, Ticker, Ret_1m)], by = c("Date","Ticker"))
say("  수익 병합 후 %d행 · %d팩터", nrow(A), uniqueN(A$Factor_Name))

saveRDS(A, file.path(OUT, "factor_long.rds"))
fwrite(COV, file.path(OUT, "coverage.csv"))
saveRDS(list(ret = ret, bench = as.data.table(P$bench), liq = as.data.table(P$liq),
             size_dt = as.data.table(P$size_dt)), file.path(OUT, "mkt.rds"))
writeLines(sort(unique(A$Factor_Name)), file.path(OUT, "factors_eligible.txt"))
say("=== P1 완료 → factor_long.rds (%d팩터) · mkt.rds · coverage.csv ===", uniqueN(A$Factor_Name))
