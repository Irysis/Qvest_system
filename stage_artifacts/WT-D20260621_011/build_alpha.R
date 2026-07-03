# WT-D20260621_011 — C29 Index Inclusion Frontrun Drift  (STEP 1-3: data prep)
# Alpha-only. PIT: panel = EFFECTIVE-date only -> A_lag=1 (effective+1M) is the ONLY PIT-valid config.
# Segfault guard: single-thread compute, file-based.

suppressMessages({library(arrow); library(data.table); library(dplyr)})
arrow::set_cpu_count(1L); setDTthreads(1L)
options(stringsAsFactors = FALSE); set.seed(20260621)

ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
OUT  <- file.path(ROOT, "stage_artifacts/WT-D20260621_011")
source(file.path(ROOT, "02_Infrastructure/contracts/canonical_screen_bt.R"))

ym <- function(d) format(as.Date(d), "%Y-%m")

# ---- STEP 1: membership event dating (per-index 0->1 = fresh passive demand impulse) ----
cat("=== STEP 1: membership event dating ===\n")
me_dt <- function(path, col){
  d <- as.data.table(read_parquet(path)); setnames(d, col, "flag")
  d[, flag := as.integer(flag)]; d <- d[!is.na(flag)]
  setorder(d, Ticker, Date)
  d[, prevf := shift(flag,1L), by=Ticker]
  d[, incl := as.integer(flag==1L & prevf==0L & !is.na(prevf))]
  d
}
k2 <- me_dt(file.path(ROOT,".cache/universe_support/us_k200.parquet"),"K200"); k2[,idx:="K200"]
kq <- me_dt(file.path(ROOT,".cache/universe_support/us_kq150.parquet"),"KQ150"); kq[,idx:="KQ150"]
mem <- rbind(k2[,.(Date,Ticker,flag,incl,idx)], kq[,.(Date,Ticker,flag,incl,idx)])
member_m <- mem[flag==1L, .(member=1L), by=.(Date,Ticker)]           # member of EITHER index
member_m[, ymk := ym(Date)]
incl_events <- unique(mem[incl==1L, .(Date,Ticker,idx)])            # per-index entry events
incl_events[, ymk := ym(Date)]
cat("inclusion events total:", nrow(incl_events),
    " 2005+:", nrow(incl_events[Date>=as.Date("2005-01-01")]), "\n")
print(incl_events[, .N, by=idx])

# most-recent inclusion month per ticker, as month-sequence index over the panel month grid
mgrid <- sort(unique(member_m$Date))
gidx  <- data.table(Date=mgrid, g=seq_along(mgrid)); gidx[, ymk:=ym(Date)]
gidx  <- unique(gidx[, .(ymk, g)])           # ensure 1 row per ymk
gidx  <- gidx[, .(g=min(g)), by=ymk]         # collapse any month with >1 panel date
incl_events <- merge(incl_events, gidx[,.(ymk, g_incl=g)], by="ymk")

# ---- STEP 2-3: RAWDATA monthly snapshot (Size, ADV21, eligibility flags) ----
cat("\n=== STEP 2-3: RAWDATA monthly snapshot ===\n")
ds <- arrow::open_dataset(file.path(ROOT,".cache/RAWDATA.parquet"))
raw <- ds %>% select(Date,Ticker,Close,Size,Vol,Ret,K200,KQ150,
                     AdminStock,TradingHalt,UnfaithfulDisc,Sector) %>%
  filter(Date >= as.Date("2003-06-01")) %>% collect() %>% as.data.table()
setorder(raw, Ticker, Date)
cat("raw rows:", nrow(raw), "\n")
raw[, tv := Close * Vol]                                   # daily traded value (KRW)
raw[, adv21 := frollmean(tv, 21, align="right"), by=Ticker]
raw[, ymk := ym(Date)]
# month-end snapshot per ticker (last trading day of month)
snap <- raw[raw[, .I[Date==max(Date)], by=.(Ticker,ymk)]$V1]
snap <- merge(snap, gidx, by="ymk", all.x=TRUE)   # month-sequence index g
cat("snapshot rows:", nrow(snap), "\n")

# ---- forward 1M realized returns (asset-level monthly = compound of daily Ret within month) ----
# Asset monthly compounding from daily is standard return aggregation. Portfolio returns are routed
# through canonical_screen_bt -> contract build_benchmark_compare (PerformanceAnalytics-grade).
mret <- raw[!is.na(Ret), .(mret = prod(1+Ret)-1), by=.(Ticker, ymk)]
allm <- sort(unique(mret$ymk))
nextmap <- data.table(ymk=allm, nextymk=c(allm[-1], NA_character_))
fwd <- merge(mret[,.(Ticker,ymk,mret_now=mret)], nextmap, by="ymk")  # not used; keep mret_now
# Ret_1m at sig month s = realized return of month s+1
fwd2 <- merge(nextmap, mret[,.(Ticker, nextymk=ymk, Ret_next=mret)], by="nextymk")
returns_dt_all <- fwd2[!is.na(ymk), .(ymk, Ticker, Ret_1m=Ret_next)]
cat("returns_dt_all rows:", nrow(returns_dt_all), "\n")

# ---- benchmark monthly (KOSPI200 TR from benchmark.parquet; RAWDATA BM_Ret is ~NA) ----
bm <- as.data.table(read_parquet(file.path(ROOT,".cache/benchmark.parquet")))
bm[, Date := as.Date(Date)]; bm <- bm[!is.na(BM_Ret)]
bm_m <- bm[, .(BM_Ret = prod(1+BM_Ret)-1), by=.(ymk=ym(Date))]
cat("bm_m rows:", nrow(bm_m), " range:", min(bm_m$ymk), max(bm_m$ymk), "\n")

saveRDS(list(incl_events=incl_events, member_m=member_m, snap=snap, gidx=gidx,
             returns_dt_all=returns_dt_all, bm_m=bm_m),
        file.path(OUT,"intermediate.rds"))
cat("\nSaved intermediate.rds\n")
