# 01_prep.R — WT-D20260710_003 Joint-design Alpha Research: data bundle
# Reuses WT-D20260710_002 clean PIT panel (returns/bench/size/universe/features — K200 U KQ150,
# cap-w KOSPI200 fwd benchmark, 8 factors / 4 families) + extracts incumbent STR_1715 noL4 active series.
# No new PIT construction — reuses validated panel (build_panel.R WT-002, mirrors WT-D20260705_009).
suppressPackageStartupMessages({ library(data.table); library(arrow) })
setDTthreads(1)  # segfault avoidance. Do NOT set arrow io_thread_count (parquet HANG).

ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
P002 <- file.path(ROOT, "stage_artifacts/WT-D20260710_002/panel")
OUT  <- file.path(ROOT, "stage_artifacts/WT-D20260710_003")
dir.create(OUT, showWarnings = FALSE, recursive = TRUE)

rd_read <- function(f) as.data.table(read_parquet(file.path(P002, f)))
features <- rd_read("features_monthly.parquet")     # Date, Ticker, 8 factor Z cols
returns  <- rd_read("returns_monthly.parquet")      # Date, Ticker, Ret_1m (FORWARD 1M)
bench    <- rd_read("benchmark_monthly.parquet")    # Date, BM_Ret (FORWARD cap-w KOSPI200)
size     <- rd_read("size_monthly.parquet")         # Date, Ticker, Size (month-end mktcap)
univ     <- rd_read("universe_flags.parquet")       # Date, Ticker, in_univ, adv20

# incumbent STR_1715 noL4 active series (net vs KOSPI200) — book-marginal baseline
b <- readRDS(file.path(ROOT, "qepm/mailbox/worktask/WT-D20260702_002/output/bt_result_C_noL4_CLEAN_ann12.rds"))
pr <- as.data.table(b$period_returns)[, .(date, ret_net)]
br <- as.data.table(b$benchmark_returns)[, .(date, benchmark_ret)]
inc <- merge(pr, br, by = "date")
inc[, ym := as.integer(format(as.Date(date), "%Y%m"))]
inc[, active_inc := ret_net - benchmark_ret]
inc_active <- inc[, .(ym, inc_ret_net = ret_net, inc_bm = benchmark_ret, active_inc)]

# canonical vintage tag
pin <- list(
  panel_source = "stage_artifacts/WT-D20260710_002/panel (build_panel.R, PIT C1-C15 validated)",
  incumbent_source = "WT-D20260702_002/output/bt_result_C_noL4_CLEAN_ann12.rds",
  built_at = as.character(Sys.time()),
  factor_families = list(
    value    = c("V02_EP","V10_FCF_Yield","V12_Composite_Value"),
    quality  = c("Q01_GPA","Q08_Composite_Quality"),
    momentum = c("M08_Residual_Mom","M09_Composite_Mom"),
    lowrisk  = c("R12_Idiosyncratic_Risk")
  ),
  IS = c("2005-01-01","2018-12-01"), OOS = c("2019-01-01","2026-06-01")
)

bundle <- list(features = features, returns = returns, bench = bench,
               size = size, univ = univ, inc_active = inc_active,
               incumbent_book_ir = 1.416, pin = pin)
saveRDS(bundle, file.path(OUT, "panel_bundle.rds"))

cat(sprintf("[prep] features %d rows / %d months (%s..%s)\n",
    nrow(features), uniqueN(features$Date), as.character(min(features$Date)), as.character(max(features$Date))))
cat(sprintf("[prep] returns %d rows / bench %d months / size %d rows / univ %d rows\n",
    nrow(returns), nrow(bench), nrow(size), nrow(univ)))
cat(sprintf("[prep] incumbent active %d months (%s..%s), mean_active=%.4f\n",
    nrow(inc_active), min(inc_active$ym), max(inc_active$ym), mean(inc_active$active_inc)))
cat("[prep] DONE -> panel_bundle.rds\n")
