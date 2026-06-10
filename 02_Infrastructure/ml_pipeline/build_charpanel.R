#==============================================================================
# build_charpanel.R — Reusable characteristic panel builder (CA / Causal / IPCA / measurement)
#
# Extracts the PROVEN data-prep from run_ipca_kr.R (WT_D20260508_006) into a
# parameterized, reusable builder. Produces 3 parquets that ALL three frontier
# methods (CA, VoC, Causal) + canonical_screen_bt measurement consume:
#   1. charpanel.parquet      (Date, YearMonth, Ticker, ret_fwd1m, period_class, <chars...>)
#   2. returns_monthly.parquet(Date, Ticker, Ret_1m)   <- forward 1M, PIT-aligned at signal date
#   3. benchmark_monthly.parquet (Date, BM_Ret)
#
# PIT: load_month_factors (C15) + month-end sig_date + forward shift label.
# Universe: KOSPI200 ∪ KOSDAQ150 + adv20>=2e8 + !Admin/!Halt (t PIT).
#
# Config via env:
#   CHARPANEL_CHARS  comma-sep our factor-DB names (default = KR-30 GKX mapping)
#   CHARPANEL_OUT    output dir (default stage_artifacts/WT_CA/panel_kr30)
#   CHARPANEL_START  train start (default 2005-01-01)  CHARPANEL_FWD  forward sig (default 2026-04-30)
#
# Run (PowerShell, heavy arrow -> PowerShell tool):
#   $env:CLAUDE_PROJECT_DIR="G:/Quant_Module_Moltbot"; $env:PYTHONUTF8="1"
#   & "C:/Program Files/R/R-4.5.2/bin/Rscript.exe" 02_Infrastructure/ml_pipeline/build_charpanel.R
#==============================================================================

suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite)
  library(future); library(future.apply)
})

PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
source(file.path(PROJECT_ROOT, "02_Infrastructure/config.R"))
source(file.path(PROJECT_ROOT, "02_Infrastructure/factor_db/factor_db_connector.R"))

# ---- Config ----------------------------------------------------------------
# KR-30 = KR-38 (Gu-Kelly-Xiu / PMC10389732) mapped to our Factor DB.
# Missing in KR DB (documented gap, like the paper's own 94->38): convind, depr,
# pchdepr, hire, egr, lgr, pchcurrat, pchquick, quick, pchgm_pchsale.
# Derived later in Python: betasq (=Beta^2), absacc (=|acc|).
KR30_DEFAULT <- c(
  # momentum / reversal (mom1m,mom6m,mom12m,mom36m,chmom~accel,high52)
  "M04_Mom_1","M02_Mom_6_1","M01_Mom_12_1","M12_LR_Reversal","M23_Acceleration","M06_High_52w",
  # risk / vol (beta,idiovol,retvol,maxret)
  "D02_Beta","D01_IdioVol","D03_RealVol","D05_MaxRet",
  # liquidity (ill,turnover~ts)
  "L01_Amihud","L02_Turnover",
  # size (mvel1)
  "S01_Size",
  # value / yield (cfp,sp,dy)
  "V03_CFP","V20_SP","V06_fDY",
  # quality / profitability (gma,acc,agr,cash,currat,lev,rd_mve,rd_sale)
  "Q01_GPA","Q05_Accrual","Q06_Asset_Growth","Q19_Cash_to_Assets","Q14_Current_Ratio",
  "Q13_Fin_Leverage","IN03_RD_to_Market","Q26_RnD_Intensity",
  # issuance / growth (chcsho~net issuance, sgr)
  "IN04_Net_Equity_Issuance","GR01_Revenue_Growth"
)

chars_env <- Sys.getenv("CHARPANEL_CHARS", "")
CHARS <- if (nzchar(chars_env)) trimws(strsplit(chars_env, ",")[[1]]) else KR30_DEFAULT
OUT_DIR <- Sys.getenv("CHARPANEL_OUT", file.path(PROJECT_ROOT, "stage_artifacts/WT_CA/panel_kr30"))
TRAIN_START <- Sys.getenv("CHARPANEL_START", "2005-01-01")
FWD_SIG     <- Sys.getenv("CHARPANEL_FWD",   "2026-04-30")
TRAIN_END <- "2022-12-31"; VAL_END <- "2024-12-31"   # lockbox = 2025-01 onward
LIQ_FLOOR <- 2e8; MIN_N <- 30L
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)

cat("[charpanel] chars (", length(CHARS), "):", paste(CHARS, collapse=","), "\n")
cat("[charpanel] out:", OUT_DIR, " | range:", TRAIN_START, "->", FWD_SIG, "\n")

# ---- 1. Rawdata -> month-end snapshot + forward 1M return -------------------
cat("\n[1/5] rawdata -> month-end + forward returns ...\n")
raw <- as.data.table(read_parquet(file.path(PROJECT_ROOT, ".cache/rawdata.parquet")))
raw <- raw[Date >= as.Date(TRAIN_START) - 60 & Date <= as.Date("2026-05-31")]
raw[, YearMonth := format(Date, "%Y%m")]
raw <- raw[!is.na(Close) & is.finite(Close) & is.finite(Vol) & Vol > 0]

me_snap <- raw[, .SD[which.max(Date)], by = .(Ticker, YearMonth),
               .SDcols = c("Date","Close","Vol","Size","Sector","K200","KQ150",
                           "AdminStock","TradingHalt","BM_Ret")]
setorder(me_snap, Ticker, Date)

raw_won <- copy(raw); raw_won[, won := Close * Vol]
raw_won[, adv20_won := frollmean(won, 20L), by = Ticker]
adv20_me <- raw_won[, .SD[which.max(Date)], by = .(Ticker, YearMonth),
                    .SDcols = c("Date","adv20_won")]
me_snap <- merge(me_snap, adv20_me[, .(Ticker, YearMonth, adv20_won)],
                 by = c("Ticker","YearMonth"), all.x = TRUE)

# forward 1M (shift -1 lag = Close[t+1]/Close[t]-1, FORWARD per shift convention), winsor +-40%
me_snap[, Close_next := shift(Close, -1L, type = "lag"), by = Ticker]
me_snap[, ret_fwd1m := pmax(pmin(Close_next / Close - 1, 0.40), -0.40)]

# ---- 2. Universe filter (PIT) ----------------------------------------------
me_snap[, in_universe := (
  (((K200 == 1) %in% TRUE) | ((KQ150 == 1) %in% TRUE)) &
  !is.na(adv20_won) & adv20_won >= LIQ_FLOOR &
  (is.na(AdminStock) | AdminStock != 1) & (is.na(TradingHalt) | TradingHalt != 1)
)]
cat("[2/5] universe rows:", me_snap[in_universe==TRUE, .N], "\n")

# ---- 3. Characteristics via load_month_factors (parallel) ------------------
cat("\n[3/5] load_month_factors per month ...\n")
all_yms <- sort(unique(me_snap$YearMonth))
all_yms <- all_yms[all_yms >= format(as.Date(TRAIN_START), "%Y%m") &
                   all_yms <= format(as.Date(FWD_SIG), "%Y%m")]

load_one_month <- function(ym) {
  d <- as.Date(paste0(substr(ym,1,4), "-", substr(ym,5,6), "-01"))
  sig_d <- seq(d, length.out = 2, by = "month")[2] - 1
  ft <- tryCatch(load_month_factors(sig_d, coverage_min = 0.05), error = function(e) NULL)
  if (is.null(ft) || nrow(ft) == 0) return(NULL)
  setDT(ft); ft <- ft[Factor_Name %in% CHARS]
  if (nrow(ft) == 0L) return(NULL)
  wide <- dcast(ft, Ticker ~ Factor_Name, value.var = "Z_Score_Aligned")
  wide[, YearMonth := ym]; wide
}
t0 <- Sys.time()
plan(multisession, workers = min(8L, parallel::detectCores() - 1L))
chunks <- future_lapply(all_yms, load_one_month)
plan(sequential)
chunks <- chunks[!vapply(chunks, is.null, logical(1))]
char_panel <- rbindlist(chunks, fill = TRUE, use.names = TRUE)
cat("[3/5] char_panel rows:", nrow(char_panel),
    " in", round(as.numeric(Sys.time()-t0, units="secs"),1), "s\n")

present <- intersect(CHARS, names(char_panel))
missing <- setdiff(CHARS, present)
cov_tbl <- data.table(char = present,
                      coverage = vapply(present, function(c) mean(!is.na(char_panel[[c]])), numeric(1)))
cat("[3/5] coverage:\n"); print(cov_tbl[order(coverage)])
if (length(missing)) cat("[3/5] NOT in panel:", paste(missing, collapse=","), "\n")

# ---- 4. Merge + clean + re-z per period + split ----------------------------
cat("\n[4/5] merge + standardize + split ...\n")
panel <- merge(
  me_snap[in_universe == TRUE, .(Ticker, YearMonth, Date, ret_fwd1m, Sector, Size, BM_Ret)],
  char_panel, by = c("Ticker","YearMonth"), all.x = FALSE)
# keep rows with forward return + >=50% chars present (avoid all-missing); impute rest
# to cross-sectional median (=0 after z-score) — KR-paper style, retains universe N
panel <- panel[!is.na(ret_fwd1m)]
nz <- rowSums(!is.na(as.matrix(panel[, ..present])))
panel_full <- panel[nz >= ceiling(0.5 * length(present))]
for (ch in present) {
  panel_full[, (ch) := scale(get(ch))[, 1], by = YearMonth]
  panel_full[is.na(get(ch)), (ch) := 0]
}
panel_full[, period_class := fcase(
  Date <= as.Date(TRAIN_END), "train",
  Date <= as.Date(VAL_END),   "validation",
  default = "lockbox")]
cat("[4/5] panel_full rows:", nrow(panel_full), "\n")
print(panel_full[, .N, by = period_class])

# ---- 5. Save 3 parquets + meta ---------------------------------------------
cat("\n[5/5] save ...\n")
keep_cols <- c("Date","YearMonth","Ticker","ret_fwd1m","period_class", present)
write_parquet(panel_full[, ..keep_cols], file.path(OUT_DIR, "charpanel.parquet"))
write_parquet(panel_full[, .(Date, Ticker, Ret_1m = ret_fwd1m)],
              file.path(OUT_DIR, "returns_monthly.parquet"))
# benchmark monthly = compound UNIQUE daily BM_Ret per month. raw is ticker×date long, so
# dedup dates first — else (1+r) is multiplied once per ticker-day (massive over-count -> Inf).
bm_daily <- unique(raw[!is.na(BM_Ret), .(Date, YearMonth, BM_Ret)])
bm_monthly <- bm_daily[, .(BM_Ret = prod(1 + BM_Ret) - 1), by = YearMonth]
bm_dates <- bm_daily[, .(Date = max(Date)), by = YearMonth]
bm_out <- merge(bm_dates, bm_monthly, by = "YearMonth")[, .(Date, BM_Ret)]
write_parquet(bm_out, file.path(OUT_DIR, "benchmark_monthly.parquet"))

meta <- list(
  chars_requested = CHARS, chars_present = present, chars_missing = missing,
  coverage = setNames(as.list(cov_tbl$coverage), cov_tbl$char),
  n_rows = nrow(panel_full), n_months = uniqueN(panel_full$YearMonth),
  n_tickers = uniqueN(panel_full$Ticker),
  date_min = as.character(min(panel_full$Date)), date_max = as.character(max(panel_full$Date)),
  split = list(train_end = TRAIN_END, val_end = VAL_END, lockbox_start = "2025-01-01"),
  period_counts = as.list(panel_full[, .N, by = period_class][, setNames(N, period_class)]),
  liq_floor = LIQ_FLOOR, built_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"))
write_json(meta, file.path(OUT_DIR, "panel_meta.json"), pretty = TRUE, auto_unbox = TRUE, na = "null")

cat("\n[charpanel] DONE. n_rows=", nrow(panel_full), " months=", uniqueN(panel_full$YearMonth),
    " chars=", length(present), "/", length(CHARS), "\n", sep="")
cat("  ", file.path(OUT_DIR, "charpanel.parquet"), "\n")
cat("  ", file.path(OUT_DIR, "returns_monthly.parquet"), "\n")
cat("  ", file.path(OUT_DIR, "benchmark_monthly.parquet"), "\n")
