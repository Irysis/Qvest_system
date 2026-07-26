#==============================================================================
# pin_and_rebuild.R — REPRT_MAP 수리 후 TTM 전량 재생성 (2026-07-26 R1)
#   ① 수리 전 산출물 pin (.cache/pins/reprt_map_pre_20260726/)
#   ② dart_compute_ttm() 전량 재생성
#   ③ 행수·quarter 분포 대조
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow) })

ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
setwd(ROOT)
source(file.path(ROOT, "02_Infrastructure", "config.R"))
source(file.path(ROOT, "02_Infrastructure", "data", "pin_cache.R"))

TTM_PATH <- file.path(CACHE_DIR, "fundamental_dart_quarterly.parquet")
TAG <- "reprt_map_pre_20260726"

# ── ① pin (수리 전 vintage 고정) ────────────────────────────────────────────
before <- as.data.table(read_parquet(TTM_PATH, mmap = FALSE))
cat(sprintf("[pre] rows=%d tickers=%d\n", nrow(before), uniqueN(before$Ticker)))
print(before[, .N, by = quarter][order(quarter)])

pin_cache(TTM_PATH, TAG)
cat(sprintf("[pin] tag=%s\n", TAG))

# ── ② 재생성 ────────────────────────────────────────────────────────────────
source(file.path(ROOT, "02_Infrastructure", "data", "data_collector_dart.R"))
source(file.path(ROOT, "02_Infrastructure", "data", "data_collector_dart_quarterly.R"))

stopifnot(identical(REPRT_MAP[reprt_code == "11013", quarter], 1L),
          identical(REPRT_MAP[reprt_code == "11014", quarter], 3L))
cat("[map] REPRT_MAP 정정 확인: 11013->1 / 11014->3\n")

t0 <- Sys.time()
invisible(dart_compute_ttm())
cat(sprintf("[rebuild] elapsed = %.1f min\n",
            as.numeric(difftime(Sys.time(), t0, units = "mins"))))

# ── ③ 대조 ──────────────────────────────────────────────────────────────────
after <- as.data.table(read_parquet(TTM_PATH, mmap = FALSE))
cat(sprintf("\n[post] rows=%d tickers=%d (before rows=%d tickers=%d)\n",
            nrow(after), uniqueN(after$Ticker), nrow(before), uniqueN(before$Ticker)))
print(after[, .N, by = quarter][order(quarter)])
cat("\n[post] Factor_Date 월-일 분포:\n")
print(after[, .N, by = .(md = format(as.Date(Factor_Date), "%m-%d"))][order(md)])
saveRDS(list(before_n = nrow(before), after_n = nrow(after),
             before_q = before[, .N, by = quarter][order(quarter)],
             after_q  = after[, .N, by = quarter][order(quarter)]),
        file.path(ROOT, "stage_artifacts", "dart_reprt_map_repair_20260726", "rebuild_counts.rds"))
cat("[done]\n")
