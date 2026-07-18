# =============================================================================
# FQ-057 NP4 run_01: inputs — pinned rawdata에서 유동성 스냅샷(AvgTV20) 산출
# - pin tag 상속: fq057_20260718_171024 (FQ-057과 동일 vintage; daily_refresh 활성
#   중이므로 read_pinned 경유만 소비 — measurement-graduation §7)
# - 월간 수익/스냅샷 패널은 FQ-057 산출물(fq057_monthly_returns/snapshot.parquet,
#   동일 pin 파생) 재사용 — 재빌드 없음.
# - AvgTV20 = frollmean(Close*Vol, 20, align="right") by Ticker (과거 20일, PIT).
#   월말 마지막 관측을 (Ticker, ym) 스냅샷으로.
# Output: stage_artifacts/method_frontier/np4_liq_snapshot.parquet
# =============================================================================
suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite)
})
data.table::setDTthreads(1)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
setwd(ROOT)
source(file.path(ROOT, "02_Infrastructure/config.R"))
source(file.path(ROOT, "02_Infrastructure/data/pin_cache.R"))

OUT_DIR <- file.path(ROOT, "stage_artifacts/method_frontier")
PIN_TAG <- "fq057_20260718_171024"

RAW_PINNED <- read_pinned(RAWDATA_CACHE, PIN_TAG)
cat("[pin] consuming pinned rawdata:", RAW_PINNED, "\n")

# ever-member 집합은 FQ-057 스냅샷에서 (동일 pin 파생)
snap <- as.data.table(read_parquet(file.path(OUT_DIR, "fq057_monthly_snapshot.parquet")))
ever <- unique(snap$Ticker)
cat("[universe] ever-member tickers:", length(ever), "\n")

cat("[load] pinned RAWDATA col_select(Date,Ticker,Close,Vol)...\n")
rd <- as.data.table(read_parquet(RAW_PINNED,
        col_select = c("Date", "Ticker", "Close", "Vol")))
rd[, Date := as.Date(Date)]
rd <- rd[Date >= as.Date("2004-01-01") & Ticker %in% ever]
cat("[load] rows:", nrow(rd), "\n")

setorder(rd, Ticker, Date)
rd[, TV := as.numeric(Close) * as.numeric(Vol)]
rd[, AvgTV20 := frollmean(TV, 20L, align = "right"), by = Ticker]
rd[, ym := as.integer(format(Date, "%Y")) * 100L + as.integer(format(Date, "%m"))]

liq <- rd[!is.na(AvgTV20), .SD[.N], by = .(Ticker, ym), .SDcols = c("Date", "AvgTV20")]
liq <- liq[, .(Ticker, ym, liq_date = Date, avgtv20 = AvgTV20)]
cat("[liq] snapshot rows:", nrow(liq), "\n")

write_parquet(liq, file.path(OUT_DIR, "np4_liq_snapshot.parquet"))
meta <- list(pin_tag = PIN_TAG,
             built_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
             rule = "AvgTV20 = frollmean(Close*Vol, 20, right) by Ticker; month-end last obs; PIT past window only",
             n_rows = nrow(liq))
write_json(meta, file.path(OUT_DIR, "np4_liq_meta.json"), auto_unbox = TRUE, pretty = TRUE)
cat("[done] run_01 complete\n")
