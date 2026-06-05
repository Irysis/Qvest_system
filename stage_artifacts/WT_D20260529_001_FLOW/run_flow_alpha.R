# =============================================================
# WT-D20260529_001 Track FLOW — Behavioral Investor-Flow Alpha
# 4th orthogonal source (cor<0.30 vs STR_1715 + D)
# qvest-alpha-style: Factor Zoo 축소 / Cost-aware / Uncertainty-aware
# PIT: lockbox 2023-12-22 strict | C13~C15 via load_month_factors()
# =============================================================
suppressMessages({
  library(data.table); library(arrow); library(jsonlite)
})
options(warn = 1)

ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/WT_D20260529_001_FLOW")
dir.create(OUT, showWarnings = FALSE, recursive = TRUE)

source("02_Infrastructure/factor_db/factor_db_connector.R")

LOCKBOX_CUTOFF <- as.Date("2023-12-22")   # PIT strict (research lockbox)
LIQ_FLOOR      <- 2e8                      # production mandate (stricter than request 5e7)
COST_BPS       <- 15

# ---- INV factor universe (investor_flow family) ----
# Selection rationale (Factor Zoo 축소 — Validation > Discovery):
# We do NOT invent new factors. We VALIDATE & COMBINE existing PIT-safe INV* factors,
# selecting a parsimonious crisis-aware subset. Candidate cap = 5 (R2-C method-shopping).
INV_ALL <- c(
  "INV01_Foreign_NetBuy_20d", "INV02_Foreign_NetBuy_60d",
  "INV03_Inst_NetBuy_20d", "INV04_Inst_NetBuy_60d",
  "INV05_Foreign_Momentum", "INV06_Inst_Momentum",
  "INV07_Retail_Contrarian", "INV08_Foreign_Inst_Agreement",
  "INV09_Flow_Persistence", "INV10_Smart_Money_Flow",
  "INV11_Foreign_Concentration", "INV12_Supply_Demand_Imbalance",
  "INV13_Foreign_Resid_Individual_21d", "INV13_Foreign_Resid_Individual_63d",
  "INV13_Foreign_Resid_Individual_126d"
)

# =============================================================
# 1. RAWDATA: universe membership + forward 1M returns
# =============================================================
cat("[1] Loading rawdata...\n")
raw <- as.data.table(read_parquet(".cache/rawdata.parquet",
        col_select = c("Date","Ticker","Close","Vol","K200","KQ150",
                        "Ret","BM_Ret","AdminStock","TradingHalt")))
raw[, Date := as.Date(Date)]
setkey(raw, Ticker, Date)

# Monthly grid (month-end signal dates) from factor connector convention.
# Use rawdata month-ends; signal dates are last trading day of each month.
raw[, ym := format(Date, "%Y-%m")]
month_ends <- raw[, .(eom = max(Date)), by = ym][order(eom)]
sig_dates  <- month_ends$eom
sig_dates  <- sig_dates[sig_dates >= as.Date("2005-01-01") & sig_dates <= LOCKBOX_CUTOFF]
cat("  sig_dates:", length(sig_dates), "from", as.character(min(sig_dates)), "to", as.character(max(sig_dates)), "\n")

# Forward 1M excess return per ticker (sig_date t -> next month-end), PIT: realized AFTER t
# Build month-end close panel
me_close <- raw[Date %in% sig_dates, .(Date, Ticker, Close, K200, KQ150,
                                       Vol, AdminStock, TradingHalt)]
setorder(me_close, Ticker, Date)
me_close[, Close_next := shift(Close, n = 1L, type = "lead"), by = Ticker]
me_close[, Date_next  := shift(Date,  n = 1L, type = "lead"), by = Ticker]
me_close[, ret_fwd_1m := Close_next / Close - 1]

# Benchmark forward 1M return (KOSPI200 TR proxy = BM_Ret cumulated). Use month-end BM index proxy.
# Compute monthly BM return from BM_Ret (daily) compounded within each forward month.
raw[, ym_int := as.integer(factor(ym))]
bm_daily <- unique(raw[, .(Date, BM_Ret)])[order(Date)]
bm_daily <- bm_daily[!is.na(BM_Ret)]
bm_daily[, ym := format(Date, "%Y-%m")]
bm_month <- bm_daily[, .(bm_ret_m = prod(1 + BM_Ret) - 1), by = ym][order(ym)]
# map each sig_date to its forward month's bm return
suppressWarnings(library(lubridate))
sig_ym <- data.table(Date = sig_dates, ym = format(sig_dates, "%Y-%m"))
# forward month = next calendar month after sig month
sig_ym[, fwd_ym := format(as.Date(paste0(ym, "-01")) %m+% months(1), "%Y-%m")]
sig_ym <- merge(sig_ym, bm_month, by.x = "fwd_ym", by.y = "ym", all.x = TRUE)
setnames(sig_ym, "bm_ret_m", "bm_fwd_1m")
me_close <- merge(me_close, sig_ym[, .(Date, bm_fwd_1m)], by = "Date", all.x = TRUE)
me_close[, exret_fwd_1m := ret_fwd_1m - bm_fwd_1m]

# liquidity (20d avg trading value) at sig_date — t value (month-end). Use rolling 20d avg of Vol*Close.
raw[, trd_val := Vol * Close]
setkey(raw, Ticker, Date)
raw[, adv20 := frollmean(trd_val, 20, align = "right"), by = Ticker]
adv_me <- raw[Date %in% sig_dates, .(Date, Ticker, adv20)]
me_close <- merge(me_close, adv_me, by = c("Date","Ticker"), all.x = TRUE)

# universe filter: K200 or KQ150, liquid, not admin/halt
me_close[, in_univ := (K200 == 1 | KQ150 == 1) & !is.na(adv20) & adv20 >= LIQ_FLOOR &
            (is.na(AdminStock) | AdminStock == 0) & (is.na(TradingHalt) | TradingHalt == 0)]
cat("  univ rows (in_univ TRUE):", sum(me_close$in_univ, na.rm = TRUE), "\n")

# =============================================================
# 2. Load INV factor Z-scores per sig_date (PIT-safe via connector)
# =============================================================
cat("[2] Loading INV factor panel via load_month_factors()...\n")
load_inv_panel <- function(sd) {
  dt <- tryCatch(load_month_factors(sd), error = function(e) NULL)
  if (is.null(dt)) return(NULL)
  dt <- dt[Factor_Name %in% INV_ALL]
  if (nrow(dt) == 0) return(NULL)
  w <- dcast(dt, Ticker ~ Factor_Name, value.var = "Z_Score_Aligned")
  w[, Date := sd]
  w
}
inv_list <- lapply(sig_dates, load_inv_panel)
inv_panel <- rbindlist(inv_list, fill = TRUE)
cat("  inv_panel rows:", nrow(inv_panel), " cols:", ncol(inv_panel), "\n")
avail_inv <- intersect(INV_ALL, names(inv_panel))
cat("  INV available:", length(avail_inv), "\n")

# merge factors with forward returns + universe
panel <- merge(me_close[in_univ == TRUE, .(Date, Ticker, exret_fwd_1m, ret_fwd_1m, bm_fwd_1m, adv20)],
               inv_panel, by = c("Date","Ticker"), all.x = FALSE)
panel <- panel[!is.na(exret_fwd_1m)]
cat("  merged panel rows:", nrow(panel), "\n")

saveRDS(panel, file.path(OUT, "panel.rds"))
cat("[2] panel saved.\n")
