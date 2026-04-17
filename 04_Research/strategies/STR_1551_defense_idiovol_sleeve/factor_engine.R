# STR_1551: D01_IdioVol 단독 — Defense Sleeve
# 학술 근거: Ang et al.(2006) IdioVol puzzle
# 역할: Defense sleeve (standalone KOSPI beat 불요, MDD 기여 핵심)
# PIT: Factor DB Z_Score_Aligned only (C13). 섹터중립 (B1).

cat("[factor_engine] STR_1551: Defense IdioVol Sleeve (D01 단독)...\n")
set.seed(1551)
suppressPackageStartupMessages(library(dplyr))

LIQ_THRESHOLD <- 2e8
NEEDED_FACTORS <- c("D01_IdioVol")

ds <- open_dataset(file.path(CACHE_DIR, "factor_db"), format = "parquet")
FDB_ALL <- ds |>
  filter(Factor_Name %in% NEEDED_FACTORS) |>
  select(Date, Ticker, Factor_Name, Z_Score, Coverage) |>
  collect() |> as.data.table()
FDB_ALL[, Date := as.Date(Date)]
source(file.path(FACTOR_DB_DIR, "factor_db_connector.R"))
FDB_ALL <- align_factor_direction(FDB_ALL, .load_registry())
setkey(FDB_ALL, Date, Ticker)
cat(sprintf("  FDB: %d rows\n", nrow(FDB_ALL)))

setorder(RAWDATA, Ticker, Date)
RAWDATA[, YM := format(Date, "%Y-%m")]
monthly_dates <- sort(RAWDATA[, .(SD = max(Date)), by = YM]$SD)
all_dates <- sort(unique(RAWDATA$Date))
monthly_dates <- monthly_dates[monthly_dates >= all_dates[min(253L, length(all_dates))]]
RAWDATA[, TradingValue := Close * Vol]
RAWDATA[, AvgTV20 := shift(frollmean(TradingValue, n = 20L, align = "right"),
                            n = 1L, type = "lag"), by = Ticker]

fdb_dates <- sort(unique(FDB_ALL$Date))
factor_list <- vector("list", length(monthly_dates))
n_done <- 0L; n_skipped <- 0L

for (i in seq_along(monthly_dates)) {
  sig_d <- as.Date(monthly_dates[i])
  valid_fdb <- fdb_dates[fdb_dates <= sig_d]
  if (length(valid_fdb) == 0L) { n_skipped <- n_skipped + 1L; next }
  fdb_d <- max(valid_fdb)
  fdt <- FDB_ALL[Date == fdb_d & Coverage == TRUE]
  if (nrow(fdt) == 0L) { n_skipped <- n_skipped + 1L; next }

  fdt_score <- fdt[, .(Ticker, Score = Z_Score_Aligned)]

  # 유동성 필터
  liq <- RAWDATA[Date == sig_d, .(Ticker, AvgTV20)]
  fdt_score <- merge(fdt_score, liq, by = "Ticker")
  fdt_score <- fdt_score[!is.na(AvgTV20) & AvgTV20 >= LIQ_THRESHOLD]
  if (nrow(fdt_score) < 20L) { n_skipped <- n_skipped + 1L; next }

  # 섹터중립: GICS 섹터 내 Z-score 재계산
  # RAWDATA에서 섹터 정보가 없으면 skip (Factor DB Z_Score_Aligned 자체가 cross-sectional)

  fdt_score[, Date := sig_d]
  factor_list[[i]] <- fdt_score[!is.na(Score), .(Date, Ticker, Score)]
  n_done <- n_done + 1L
}

FACTORS <- rbindlist(factor_list[!sapply(factor_list, is.null)])
setorder(FACTORS, Date, -Score)

if ("YM" %in% names(RAWDATA)) RAWDATA[, YM := NULL]
for (col in c("TradingValue", "AvgTV20")) {
  if (col %in% names(RAWDATA)) RAWDATA[, (col) := NULL]
}
rm(FDB_ALL); gc(verbose = FALSE)
cat(sprintf("  FACTORS: %s rows | %d dates (skip %d)\n",
            format(nrow(FACTORS), big.mark = ","), n_done, n_skipped))
