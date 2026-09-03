PROJECT_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
Sys.setenv(CLAUDE_PROJECT_DIR = PROJECT_ROOT, QM_ROOT = PROJECT_ROOT)
setwd(PROJECT_ROOT)
suppressMessages(library(arrow)); suppressMessages(library(data.table))

ud <- readRDS("04_Research/strategies/RF_B3_13_SmallCap/universe_diag.rds")
ud <- ud[Date >= as.Date("2005-01-01")]

d <- as.data.table(read_parquet(".cache/rawdata.parquet"))
setorder(d, Ticker, Date)
d[, .TV := Close * Vol]
d[, .AvgTV20 := shift(frollmean(.TV, 20L, align = "right"), 1L), by = Ticker]
d[, .SizeLag := shift(Size, 1L), by = Ticker]

# B1-5 기준선 유니버스 (K200∪KQ150 + adv20>=2e8) 월별 중앙 시총
base <- d[Date %in% ud$Date & (K200 == TRUE | KQ150 == TRUE) &
            is.finite(.AvgTV20) & .AvgTV20 >= 2e8 & is.finite(.SizeLag),
          .(n_base = .N, med_size_base = median(.SizeLag)), by = Date]

m <- merge(ud, base, by = "Date", all.x = TRUE)

cat("=== B3-13 유니버스 실측 (2005-01 ~) ===\n")
cat(sprintf("월 수: %d (%s ~ %s)\n", nrow(m), format(min(m$Date)), format(max(m$Date))))
cat(sprintf("adv20 하한 통과 n         : median %d (min %d / max %d)\n",
            as.integer(median(m$n_liq)), min(m$n_liq), max(m$n_liq)))
cat(sprintf("→ 하위 1/3 소형주 n       : median %d (min %d / max %d)\n",
            as.integer(median(m$n_small)), min(m$n_small), max(m$n_small)))
cat(sprintf("→ 스코어 산출 n (Mom∩Ilq) : median %d (min %d / max %d)\n",
            as.integer(median(m$n_scored)), min(m$n_scored), max(m$n_scored)))
cat(sprintf("25종 미달 월 수           : %d / %d\n", sum(m$n_scored < 25L), nrow(m)))
cat(sprintf("시총 임계(하위 1/3 컷)    : median %.0f억 (min %.0f억 / max %.0f억)\n",
            median(m$thr)/1e8, min(m$thr)/1e8, max(m$thr)/1e8))
cat(sprintf("소형주 유니버스 중앙 시총 : median %.0f억\n", median(m$med_size_small)/1e8))
cat(sprintf("B1-5 기준선 중앙 시총     : median %.0f억 (n median %d)\n",
            median(m$med_size_base, na.rm = TRUE)/1e8,
            as.integer(median(m$n_base, na.rm = TRUE))))
cat(sprintf("★배수 (소형주/기준선)     : median %.4f  (= 1/%.1f배)\n",
            median(m$med_size_small / m$med_size_base, na.rm = TRUE),
            1 / median(m$med_size_small / m$med_size_base, na.rm = TRUE)))

# 구간별
m[, yr5 := paste0(5 * (as.integer(format(Date, "%Y")) %/% 5), "s")]
print(m[, .(n_liq = as.integer(median(n_liq)), n_small = as.integer(median(n_small)),
            n_scored = as.integer(median(n_scored)),
            thr_억 = round(median(thr)/1e8), small_억 = round(median(med_size_small)/1e8),
            base_억 = round(median(med_size_base, na.rm = TRUE)/1e8),
            배수 = round(median(med_size_small/med_size_base, na.rm = TRUE), 4)), by = yr5])
