# Build universe/returns/benchmark/liq panels from LOCAL staged RAWDATA (avoid OneDrive mmap-1224)
Sys.setenv(LC_ALL = "English_United States.utf8")
suppressWarnings(suppressMessages({ library(data.table); library(arrow) }))
data.table::setDTthreads(1L)
PROJ <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(PROJ)
LOCAL <- "C:/Users/99922/AppData/Local/Temp/claude/C--Users-99922-OneDrive-Quant-Module-Moltbot/39968f13-46e1-4438-903c-c8d7b6c87713/scratchpad/data"
STA <- file.path(PROJ, "stage_artifacts/WT_D20260705_006"); dir.create(STA, recursive=TRUE, showWarnings=FALSE)
FDB_MIN <- as.Date("2005-01-01")

RAWDATA <- as.data.table(read_parquet(file.path(LOCAL,"RAWDATA.parquet")))
BM_DT   <- as.data.table(read_parquet(file.path(LOCAL,"benchmark.parquet")))
cat("CK1 loaded RAWDATA rows=", nrow(RAWDATA), "\n"); flush.console()
if (!inherits(RAWDATA$Date,"Date")) RAWDATA[, Date := as.Date(Date)]
# restrict to study window + 2-month daily buffer for 20d rolling window (memory-safe)
# AND to tickers that were EVER in K200/KQ150 (universe candidates only) — shrinks 10M->~2M
ever_univ <- unique(RAWDATA[Date >= as.Date("2004-10-01") & (K200==TRUE | KQ150==TRUE), Ticker])
rd <- RAWDATA[Date >= as.Date("2004-10-01") & Ticker %in% ever_univ,
              .(Date, Ticker, Close, Vol, K200, KQ150)]
rm(RAWDATA); gc(FALSE)
cat("CK1b filtered rd rows=", nrow(rd), " ever_univ tickers=", length(ever_univ), "\n"); flush.console()
setorder(rd, Ticker, Date)
rd[, ym := format(Date, "%Y-%m")]
me_dates <- sort(rd[, .(Date=max(Date)), by=ym]$Date)
me_dates <- me_dates[me_dates >= FDB_MIN]
rd[, ym := NULL]
rd[, TV := Close * Vol]
rd[, AvgTV20 := frollmean(TV, 20L, align="right"), by=Ticker]
cat("CK4 frollmean done\n"); flush.console()
me <- rd[Date %in% me_dates, .(Date, Ticker, Close, K200, KQ150, AvgTV20)]
rm(rd); gc(FALSE)
setorder(me, Ticker, Date)
me[, Ret_1m := shift(Close, -1L)/Close - 1, by=Ticker]
me[, in_univ := (K200==TRUE | KQ150==TRUE) & !is.na(AvgTV20) & AvgTV20 >= 2e8]
cat("CK5 forward ret rows=", nrow(me), " univ rows=", me[in_univ==TRUE,.N], "\n"); flush.console()

returns_dt <- me[!is.na(Ret_1m), .(Date, Ticker, Ret_1m)]
liq_dt     <- me[in_univ==TRUE, .(Date, Ticker, adv=AvgTV20)]
univ_dt    <- me[in_univ==TRUE, .(Date, Ticker)]; setkey(univ_dt, Date, Ticker)

if (!inherits(BM_DT$Date,"Date")) BM_DT[, Date := as.Date(Date)]
bm_me <- BM_DT[Date %in% me_dates, .(Date, BM_Close)]
setorder(bm_me, Date)
bm_me[, BM_Ret := shift(BM_Close, -1L)/BM_Close - 1]
bench_dt <- bm_me[!is.na(BM_Ret), .(Date, BM_Ret)]
cat("CK6 bench rows=", nrow(bench_dt), " (", as.character(min(bench_dt$Date)), "..", as.character(max(bench_dt$Date)), ")\n"); flush.console()

saveRDS(list(returns_dt=returns_dt, bench_dt=bench_dt, liq_dt=liq_dt,
             univ_dt=univ_dt, me_dates=me_dates), file.path(STA,"base_panels.rds"), compress=TRUE)
cat("SAVED base_panels.rds | months=", length(me_dates), "\n")
