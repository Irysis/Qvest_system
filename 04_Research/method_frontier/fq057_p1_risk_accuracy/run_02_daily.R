# =============================================================================
# FQ-057 NP4-P1 run_02: 일간 수익 패널 — 실현분산(realized RV) 재료
#   - pin tag 상속(fq057_20260718_171024): read_pinned 경유 (daily_refresh 활성)
#   - ever-member(FQ-057 snapshot) 종목의 일간 Ret 만 carve (fdb_daily 미사용, rawdata 직접)
#   - 홀딩월 분할용 ym 부여. 월간패널/스냅샷/liq 는 FQ-057·NP4 산출 재사용(재빌드 없음).
#   Output: stage_artifacts/method_frontier/p1_daily_returns.parquet
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite) })
data.table::setDTthreads(1)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
setwd(ROOT)
source(file.path(ROOT, "02_Infrastructure/config.R"))
source(file.path(ROOT, "02_Infrastructure/data/pin_cache.R"))

OUT_DIR <- file.path(ROOT, "stage_artifacts/method_frontier")
PIN_TAG <- "fq057_20260718_171024"
RAW_PINNED <- read_pinned(RAWDATA_CACHE, PIN_TAG)
cat("[pin] consuming pinned rawdata:", RAW_PINNED, "\n")

# ever-member 집합 (FQ-057 월간 스냅샷 — 동일 pin 파생)
snap <- as.data.table(read_parquet(file.path(OUT_DIR, "fq057_monthly_snapshot.parquet")))
ever <- unique(snap$Ticker)
cat("[universe] ever-member tickers:", length(ever), "\n")

cat("[load] pinned RAWDATA col_select(Date,Ticker,Ret)...\n")
rd <- as.data.table(read_parquet(RAW_PINNED, col_select = c("Date", "Ticker", "Ret")))
rd[, Date := as.Date(Date)]
rd <- rd[Ticker %in% ever & Date >= as.Date("2004-11-01")]
rd <- rd[!is.na(Ret)]
rd[, ym := as.integer(format(Date, "%Y")) * 100L + as.integer(format(Date, "%m"))]
setorder(rd, Ticker, Date)
cat("[load] daily rows:", nrow(rd), " date range:", as.character(min(rd$Date)), "..",
    as.character(max(rd$Date)), "\n")

# 물리불가 방어 (R44 ret_sanity 정신 — 진단 로깅만, 값 유지: 유니버스 대상이라 clean 기대)
n_phys <- rd[abs(Ret) > 1.0, .N]
cat("[sanity] |Ret|>1.0 daily rows (phys-impossible):", n_phys, "\n")

write_parquet(rd, file.path(OUT_DIR, "p1_daily_returns.parquet"))
meta <- list(pin_tag = PIN_TAG, built_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
             n_rows = nrow(rd), n_tickers = length(ever),
             phys_impossible_daily = n_phys,
             note = "ever-member daily Ret; realized RV 재료; NA 제거; ym=홀딩월 분할키")
write_json(meta, file.path(OUT_DIR, "p1_daily_meta.json"), auto_unbox = TRUE, pretty = TRUE)
cat("[done] run_02 complete\n")
