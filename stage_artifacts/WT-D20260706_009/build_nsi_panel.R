# build_nsi_panel.R — WT-D20260706_009 Alpha Research
# Hypothesis: Net Share Issuance (capital discipline). LONG net-retirement (shares outstanding shrinking:
#   buyback+cancellation, 감자), SHORT/AVOID net-issuance (SEO/dilution). Daniel-Titman 2006, Pontiff-Woodgate 2008.
#
# Two split-immune signal variants built:
#   (A) NSI_shares  = -Δlog(split-adjusted shares outstanding, TTM 4Q).  Split/bonus removed by:
#         * detecting clean multiplicative jumps (splits/무상증자 are value-neutral, ~integer ratios)
#         * capping |Δlog| in signal to a real-issuance band; large jumps -> treated as split (0 contribution)
#       Higher score = more retirement = LONG.
#   (B) NSI_cei     = -(Δlog(ME_TTM) - cumret_TTM) = Composite Equity Issuance (Daniel-Titman).
#       Naturally split-proof (ME and return both split-adjusted). Isolates *net issuance* portion of
#       market-cap growth. Higher score = net retirement = LONG.
#
# PIT DESIGN (C1/C2/C4/C10/C14/C15):
#   - Shares from .cache/shares_issued.parquet: Item=ISSD, quarterly, Factor_Date = period+~45d (already PIT-lagged).
#     signal at month t uses only shares with Factor_Date <= t (as-of merge). 재무 45일/5월 규칙 준수.
#   - ME (market cap) from RAWDATA Size at month-end t (price-based, PIT at t).
#   - Forward return Ret_1m = realized t->t+1. Universe/ADV at t (C10). No full-sample stats (C1).

suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT-D20260706_009/panel")
dir.create(OUT, showWarnings = FALSE, recursive = TRUE)
LIQ_MIN <- 2e8

# ---- 1. RAWDATA daily -> month-end panel (Size, forward return, universe, adv20, bench) ----
cat("[nsi] loading RAWDATA...\n"); flush.console()
rd <- as.data.table(read_parquet(".cache/RAWDATA.parquet"))
rd <- rd[, .(Date, Ticker, K200, KQ150, Close, Vol, Size, Ret, BM_Ret)]
rd[, Date := as.Date(Date)]
setorder(rd, Ticker, Date)
cat("[nsi] rd:", nrow(rd), "rows\n"); flush.console()

# month key (fast integer, avoid cut.Date segfault)
ud <- sort(unique(rd$Date)); lt <- as.POSIXlt(ud)
ym_map <- data.table(Date = ud, ym = as.Date(sprintf("%04d-%02d-01", lt$year + 1900L, lt$mon + 1L)))
rd <- merge(rd, ym_map, by = "Date", all.x = TRUE)
setorder(rd, Ticker, Date)

rd[, dvalue := Close * Vol]
rd[, adv20 := frollmean(dvalue, 20, align = "right"), by = Ticker]

# month-end rows
is_last <- rd[, .I[.N], by = .(Ticker, ym)]$V1
me <- rd[is_last]
setorder(me, Ticker, ym)
me[, close_prev := shift(Close, 1), by = Ticker]
me[, mret := Close / close_prev - 1]
me[, Ret_1m := shift(mret, -1), by = Ticker]            # forward 1M realized
me[, in_univ := (K200 == TRUE | KQ150 == TRUE)]
cat("[nsi] month-end rows:", nrow(me), "\n"); flush.console()

# ---- 2. shares outstanding (ISSD), PIT via Factor_Date ----
si <- as.data.table(read_parquet(".cache/shares_issued.parquet"))
si <- si[Item == "ISSD" & is.finite(Value) & Value > 0]
si[, Factor_Date := as.Date(Factor_Date)]
si[, Period_Date := as.Date(Period_Date)]
setorder(si, Ticker, Period_Date)
# quarterly log-shares, TTM (4-quarter) change, at each fiscal quarter
si[, log_sh := log(Value)]
si[, dlog_4q := log_sh - shift(log_sh, 4), by = Ticker]   # TTM Δlog(shares)
# ---- split/bonus detection: value-neutral jumps. Real issuance/retirement is SMALL.
#   Any single-quarter |Δlog| jump > SPLIT_THRESH treated as split/bonus -> excluded from TTM signal path.
SPLIT_THRESH <- 0.35   # ~ +42%/-30% single-quarter = almost surely split/bonus (무상증자/액면분할), not SEO
si[, dlog_1q := log_sh - shift(log_sh, 1), by = Ticker]
si[, is_split_q := is.finite(dlog_1q) & abs(dlog_1q) > SPLIT_THRESH]
# SPLIT-ADJUSTED log-share series (VECTORIZED): remove cumulative split jumps.
#   cum_adj_t = cumsum of (jump at split quarters up to and including t). log_sh_adj = log_sh - cum_adj.
si[, jump_removed := fifelse(is.finite(is_split_q) & is_split_q & is.finite(dlog_1q), dlog_1q, 0), by = Ticker]
si[, cum_adj := cumsum(jump_removed), by = Ticker]
si[, log_sh_adj := log_sh - cum_adj]
si[, dlog_4q_adj := log_sh_adj - shift(log_sh_adj, 4), by = Ticker]   # split-adjusted TTM Δlog(shares)

# as-of PIT table: for each ticker keep (Factor_Date, dlog_4q_adj, raw_dlog_4q)
sh_pit <- si[is.finite(dlog_4q_adj), .(Ticker, avail = Factor_Date, dlog_4q_adj, dlog_4q_raw = dlog_4q)]
setorder(sh_pit, Ticker, avail)

# ---- 3. as-of merge shares signal onto month-end t (latest Factor_Date <= t) ----
me_u <- me[in_univ == TRUE, .(Ticker, Date = ym, Size, adv20, Ret_1m)]
setorder(me_u, Ticker, Date)
# rolling as-of join per ticker
setkey(sh_pit, Ticker, avail); setkey(me_u, Ticker, Date)
mm <- sh_pit[me_u, on = .(Ticker, avail = Date), roll = TRUE]   # each me row gets latest shares<=Date
setnames(mm, "avail", "Date")
# NSI signal (A): higher = more retirement (long). = -Δlog(shares)
mm[, nsi_shares := -dlog_4q_adj]
mm[, nsi_shares_raw := -dlog_4q_raw]

# ---- 4. Composite Equity Issuance (B): -(Δlog ME_TTM - cumret_TTM) ----
# need ME (=Size at t) and 12m cum return per ticker at month-end. Build from me.
setorder(me, Ticker, ym)
me[, logsize := log(Size)]
me[, dlog_me_12 := logsize - shift(logsize, 12), by = Ticker]   # Δlog market cap over 12 months
# cumulative 12m log-return (VECTORIZED via rolling sum of log(1+mret)).
#   requires 12 consecutive finite months ending at t. frollsum with na.rm handled by finite-count check.
me[, lr := log1p(mret)]
me[, lr_ok := as.integer(is.finite(lr))]
me[, roll_lr := frollsum(fifelse(is.finite(lr), lr, 0), 12, align = "right"), by = Ticker]
me[, roll_n  := frollsum(lr_ok, 12, align = "right"), by = Ticker]
me[, log_cumret_12 := fifelse(is.finite(roll_n) & roll_n == 12L, roll_lr, NA_real_)]
me[, cei := dlog_me_12 - log_cumret_12]   # issuance part of ME growth (>0 = net issuance)
cei_dt <- me[in_univ == TRUE & is.finite(cei), .(Ticker, Date = ym, cei)]
cei_dt[, nsi_cei := -cei]   # higher = net retirement (long)

# merge CEI onto mm
mm <- merge(mm, cei_dt[, .(Ticker, Date, nsi_cei)], by = c("Ticker","Date"), all.x = TRUE)

# ---- 5. size percentile per month (for large-cap decomposition) ----
mm[, size_pctile := frank(Size, ties.method="average")/.N, by = Date]  # 1 = largest
mm[, size_rank := frank(-Size, ties.method="first"), by = Date]        # 1 = largest

# scores panel (signal at month-end t, PIT)
scores <- mm[, .(Date, Ticker, Size, adv20, size_pctile, size_rank,
                 nsi_shares, nsi_shares_raw, nsi_cei)]

# ---- 6. returns / universe / benchmarks (cap-w KOSPI200 + EW universe) ----
returns_monthly <- me[!is.na(Ret_1m) & in_univ == TRUE, .(Date = ym, Ticker, Ret_1m)]
universe_flags  <- me[in_univ == TRUE, .(Date = ym, Ticker, in_univ, adv20, Size)]

bm <- unique(rd[!is.na(BM_Ret), .(Date, ym, BM_Ret)], by = "Date")
bm_m <- bm[, .(bm_mret = prod(1 + BM_Ret) - 1), by = ym]  # panel construction compound
setorder(bm_m, ym); bm_m[, BM_Ret_fwd := shift(bm_mret, -1)]
benchmark_capw <- bm_m[!is.na(BM_Ret_fwd), .(Date = ym, BM_Ret = BM_Ret_fwd)]

ew <- returns_monthly[, .(BM_Ret = mean(Ret_1m, na.rm = TRUE)), by = Date]
benchmark_ew <- ew[, .(Date, BM_Ret)]

# ---- write ----
write_parquet(scores,          file.path(OUT, "nsi_scores_monthly.parquet"))
write_parquet(returns_monthly, file.path(OUT, "returns_monthly.parquet"))
write_parquet(benchmark_capw,  file.path(OUT, "benchmark_capw.parquet"))
write_parquet(benchmark_ew,    file.path(OUT, "benchmark_ew.parquet"))
write_parquet(universe_flags,  file.path(OUT, "universe_flags.parquet"))

cat(sprintf("[nsi] scores: %d rows / %d months (%s..%s)\n",
    nrow(scores), uniqueN(scores$Date), as.character(min(scores$Date)), as.character(max(scores$Date))))
cat(sprintf("[nsi] nsi_shares non-NA: %d  nsi_cei non-NA: %d\n",
    sum(is.finite(scores$nsi_shares)), sum(is.finite(scores$nsi_cei))))
# split-detection diagnostics
cat(sprintf("[nsi] split quarters flagged: %d / %d (%.2f%%)\n",
    sum(si$is_split_q, na.rm=TRUE), nrow(si), 100*mean(si$is_split_q, na.rm=TRUE)))
cat("[nsi] DONE\n")
