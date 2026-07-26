#==============================================================================
# post_state.R — 수리 후 산출물 최종 상태 + pin 대조
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(ROOT)
source(file.path(ROOT, "02_Infrastructure", "config.R"))

TTM  <- file.path(CACHE_DIR, "fundamental_dart_quarterly.parquet")
PIN  <- file.path(CACHE_DIR, "pins", "reprt_map_pre_20260726", "fundamental_dart_quarterly.parquet")

after  <- as.data.table(read_parquet(TTM, mmap = FALSE))
before <- as.data.table(read_parquet(PIN, mmap = FALSE))

cat(sprintf("[행수] before(pin)=%d  after=%d  delta=%+d\n",
            nrow(before), nrow(after), nrow(after) - nrow(before)))
cat(sprintf("[티커] before=%d  after=%d\n", uniqueN(before$Ticker), uniqueN(after$Ticker)))

cat("\n[quarter 분포]\n")
cmp <- merge(before[, .(before = .N), by = quarter],
             after[, .(after = .N), by = quarter], by = "quarter", all = TRUE)
cmp[, delta := after - before]
print(cmp[order(quarter)])

cat("\n[Factor_Date 고정일 분포 — after]\n")
print(after[, .N, by = .(md = format(as.Date(Factor_Date), "%m-%d"))][order(md)])
cat(sprintf("\n[Factor_Date 범위] %s ~ %s\n",
            min(after$Factor_Date), max(after$Factor_Date)))

# quarter ↔ Factor_Date 결합 불변식 (수리의 직접 증거)
chk <- after[, .(md = unique(format(as.Date(Factor_Date), "%m-%d"))), by = quarter][order(quarter)]
cat("\n[불변식] quarter → Factor_Date 고정일 1:1\n"); print(chk)
stopifnot(nrow(chk) == 4L,
          chk[quarter == 1L]$md == "05-15", chk[quarter == 2L]$md == "08-15",
          chk[quarter == 3L]$md == "11-15", chk[quarter == 4L]$md == "03-31")
cat("  OK — q1=05-15 q2=08-15 q3=11-15 q4=03-31 (각 quarter 당 고정일 정확히 1개)\n")
cat("\n[done]\n")
