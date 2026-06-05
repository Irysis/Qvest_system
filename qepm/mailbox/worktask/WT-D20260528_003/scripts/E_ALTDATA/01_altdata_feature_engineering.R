#==============================================================================
# WT-D20260528_003 Hypothesis E — Alternative Data ML (KR-specific axis)
# Step 1: Alt-Data Daily Features → Monthly Snapshot Panel (PIT-clean)
#
# Philosophy (Track 4 도훈 mandate):
#   D_ML (162 features) = fundamental/momentum/quality axis.
#   E_ALTDATA = flow + insider + crowding + microstructure (orthogonal).
#   투자자 거래주체별 net flow + DART 임원공시 + KR retail-driven crowding.
#
# Pipeline:
#   1. Same sig_date schedule + universe as D_ML (직접 비교 가능)
#   2. Block 1: INV01-INV12 + Foreign/Inst/Retail flow rolling (Factor DB daily)
#   3. Block 2: DART insider trades 21d/60d count + buy ratio (자체 계산)
#   4. Block 3: CR01-CR11 + SE02 crowding/sentiment (Factor DB daily)
#   5. Block 4: L01-L44 microstructure (Factor DB daily, 12개 selective)
#   6. Forward 1M log return label (winsorize 99.5%, D_ML과 동일)
#
# Feature target: ~60-80 features (도훈 spec)
# PIT C1 strict: All features at sig_date - 1 trading day snapshot
# Lockbox: sig_date <= 2023-12-22 (alpha-research scope)
# Insider: rcept_dt = DART filing date (publication lag 자동 포함, PIT C4 satisfied)
#
# Academic grounding:
#   - Pollet-Wilson 2010 RFS (smart money flow comovement)
#   - Bettis-Coles-Lemmon 2000 JFE (insider trading regulation)
#   - Cohen-Malloy-Pomorski 2012 JF (opportunistic insiders)
#   - Anton-Polk 2014 JF (common ownership crowding)
#   - Amihud 2002 JFM (illiquidity premium)
#   - Roll 1984 JF (implicit bid-ask spread)
#==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(jsonlite)
})

t0 <- Sys.time()

PROJ <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
setwd(PROJ)

WT_ID    <- "WT-D20260528_003"
HYP_TAG  <- "E_ALTDATA"
OUT_DIR  <- file.path("stage_artifacts", "WT_D20260528_003_E_ALTDATA")
dir.create(OUT_DIR, showWarnings = FALSE, recursive = TRUE)

SIG_CUTOFF    <- as.Date("2023-12-22")
LIQ_THRESHOLD <- 2e8
DAILY_DB_DIR  <- ".cache/factor_db_daily"

cat(sprintf("[%s] === E_ALTDATA Step 1 START ===\n", format(Sys.time(), "%H:%M:%S")))

# ---- Step 1: sig_date schedule (D_ML과 동일) ----
cat(sprintf("[%s] Step 1 — sig_date schedule (matched to D_ML)\n", format(Sys.time(), "%H:%M:%S")))

avail <- list.files(DAILY_DB_DIR, pattern = "^fdb_daily_\\d{6}\\.parquet$")
ym_avail <- sort(gsub("fdb_daily_(\\d{6})\\.parquet", "\\1", avail))

raw <- as.data.table(read_parquet(".cache/rawdata.parquet"))
raw[, Date := as.Date(Date)]
raw[, YM   := format(Date, "%Y%m")]

month_ends <- raw[, .(Date = max(Date)), by = YM]
setkey(month_ends, YM)

sig_dates <- month_ends[YM %in% ym_avail & Date <= SIG_CUTOFF, sort(Date)]
sig_dates <- sig_dates[sig_dates >= as.Date("2008-01-01")]
cat(sprintf("  sig_dates total: %d  first: %s  last: %s\n",
    length(sig_dates), as.character(sig_dates[1]), as.character(sig_dates[length(sig_dates)])))

# ---- Step 2: Universe filter (D_ML과 동일) ----
cat(sprintf("[%s] Step 2 — universe filter (K200 ∪ KQ150, LIQ 20d >= 2e8)\n", format(Sys.time(), "%H:%M:%S")))

raw[, TV := Close * Vol]
setorder(raw, Ticker, Date)
raw[, TV_20d := frollmean(TV, n = 20L, na.rm = TRUE), by = Ticker]

build_universe <- function(sd) {
  snap <- raw[Date == sd]
  if (nrow(snap) == 0) return(character(0))
  uni <- snap[(K200 == TRUE | KQ150 == TRUE) &
              TV_20d >= LIQ_THRESHOLD &
              AdminStock == FALSE &
              TradingHalt == FALSE &
              UnfaithfulDisc == FALSE,
              Ticker]
  unique(uni)
}

uni_list <- lapply(sig_dates, build_universe)
names(uni_list) <- as.character(sig_dates)
uni_size <- sapply(uni_list, length)
cat(sprintf("  Universe size: min=%d med=%d max=%d\n",
    min(uni_size), as.integer(median(uni_size)), max(uni_size)))

# ---- Step 3: Forward 1M log return label (D_ML과 동일) ----
cat(sprintf("[%s] Step 3 — forward 1M log return label\n", format(Sys.time(), "%H:%M:%S")))

me_seq <- sort(month_ends[YM %in% ym_avail, Date])

build_fwd_ret <- function(sd) {
  next_me <- me_seq[me_seq > sd][1]
  if (is.na(next_me)) return(NULL)
  snap_now  <- raw[Date == sd,      .(Ticker, P0 = Close)]
  snap_next <- raw[Date == next_me, .(Ticker, P1 = Close)]
  m <- merge(snap_now, snap_next, by = "Ticker", all = FALSE)
  m[, log_ret_1m := log(P1 / P0)]
  m[, sig_date := sd]
  m[, .(sig_date, Ticker, log_ret_1m)]
}

fwd_ret_list <- lapply(sig_dates, build_fwd_ret)
fwd_ret <- rbindlist(fwd_ret_list, fill = TRUE)
fwd_ret <- fwd_ret[!is.na(log_ret_1m)]

qlo <- quantile(fwd_ret$log_ret_1m, 0.005, na.rm = TRUE)
qhi <- quantile(fwd_ret$log_ret_1m, 0.995, na.rm = TRUE)
fwd_ret[, log_ret_1m_w := pmin(pmax(log_ret_1m, qlo), qhi)]
cat(sprintf("  Forward 1M log return — n=%d  Winsorize [%.4f, %.4f]\n",
    nrow(fwd_ret), qlo, qhi))

# ---- Step 4: Alt-Data Feature List (Block 1-4) ----
# Block 1 — Investor Flow (12 base + Block-1 derived 7) = ~19 features
BLOCK1_FLOW <- c(
  "INV01_Foreign_NetBuy_20d", "INV02_Foreign_NetBuy_60d",
  "INV03_Inst_NetBuy_20d",    "INV04_Inst_NetBuy_60d",
  "INV05_Foreign_Momentum",   "INV06_Inst_Momentum",
  "INV07_Retail_Contrarian",  "INV08_Foreign_Inst_Agreement",
  "INV09_Flow_Persistence",   "INV10_Smart_Money_Flow",
  "INV11_Foreign_Concentration", "INV12_Supply_Demand_Imbalance"
)

# Block 3 — Crowding / Sentiment (10 base) = ~10 features
BLOCK3_CROWD <- c(
  "CR01_Sector_Comovement",     "CR02_Volume_Concentration",
  "CR03_Herding_Dispersion",    "CR04_Ownership_Concentration",
  "CR05_Short_Pressure_Proxy",  "CR06_DTC_Proxy",
  "CR08_Volume_Price_Divergence", "CR09_Money_Flow_Ratio",
  "CR10_Convergence_Premium",   "CR11_Idiosyncratic_Return"
)

# Block 4 — Microstructure (selective, orthogonal to D_ML L26/L01) = ~12 features
# 직교성: D_ML이 이미 사용한 L01_Amihud, L05_Dollar_Volume, L26_Log_MktCap 제외
# 보완 microstructure 채택
BLOCK4_MICRO <- c(
  "L02_Turnover",         "L03_Volume_Mom",
  "L04_Bid_Ask_Proxy",    "L06_Zero_Trade_Days",
  "L07_Zero_Return_Days", "L09_Amihud_20d",
  "L10_Amihud_Ratio",     "L11_Kyle_Lambda",
  "L14_Price_Impact",     "L15_Turnover_252d",
  "L16_Turnover_Vol",     "L20_Trade_Frequency",
  "L22_Ret_Autocorr",     "L29_Illiq_Change",
  "L31_Vol_Concentration", "L32_Ret_Vol_Corr",
  "L38_DolVol_Mom",       "L39_Overnight_Spread"
)

# Block 2 — Insider (직접 계산, DART) 7 features 예정
# (Block 2는 사후 자체 계산)

SEL_FACTORS <- c(BLOCK1_FLOW, BLOCK3_CROWD, BLOCK4_MICRO)
cat(sprintf("  Selected DB factors: Block1=%d Block3=%d Block4=%d total=%d\n",
    length(BLOCK1_FLOW), length(BLOCK3_CROWD), length(BLOCK4_MICRO), length(SEL_FACTORS)))

# ---- Step 5: Load daily factor data (selective) ----
cat(sprintf("[%s] Step 5 — loading daily factor data (%d factors)\n",
    format(Sys.time(), "%H:%M:%S"), length(SEL_FACTORS)))

earliest_sd <- min(sig_dates)
lookback_start <- earliest_sd - 90  # 60d rolling

parquet_paths <- file.path(DAILY_DB_DIR, paste0("fdb_daily_", ym_avail, ".parquet"))
parquet_paths <- parquet_paths[file.exists(parquet_paths)]

required_cols <- c("Date", "Ticker", SEL_FACTORS)
daily_list <- list()
n_loaded <- 0L
for (pp in parquet_paths) {
  ym <- gsub(".*fdb_daily_(\\d{6})\\.parquet", "\\1", pp)
  ym_date <- as.Date(paste0(ym, "01"), "%Y%m%d")
  lookback_month_first <- as.Date(format(lookback_start, "%Y-%m-01"))
  if (ym_date < lookback_month_first) next
  if (ym_date > SIG_CUTOFF + 60) next
  tmp <- tryCatch({
    schema <- arrow::read_parquet(pp, col_select = NULL)
    avail_cols <- intersect(required_cols, names(schema))
    as.data.table(schema)[, ..avail_cols]
  }, error = function(e) NULL)
  if (!is.null(tmp) && nrow(tmp) > 0) {
    daily_list[[ym]] <- tmp
    n_loaded <- n_loaded + 1L
  }
}

if (length(daily_list) == 0) stop("No daily data loaded — check paths")

daily <- rbindlist(daily_list, fill = TRUE)
daily[, Date := as.Date(Date)]
setorder(daily, Ticker, Date)
cat(sprintf("  Daily data loaded: %d months, %d rows × %d cols\n",
    n_loaded, nrow(daily), ncol(daily)))

# Coverage check per factor
factor_cov <- sapply(SEL_FACTORS, function(f) {
  if (!(f %in% names(daily))) return(NA_real_)
  mean(!is.na(daily[[f]]))
})
factor_cov_dt <- data.table(factor = names(factor_cov), coverage = unname(factor_cov))
factor_cov_dt <- factor_cov_dt[order(-coverage)]
cat("  Factor coverage (top/bottom):\n")
print(rbind(head(factor_cov_dt, 5), tail(factor_cov_dt, 5)))

# ---- Step 6: Block 1 derived flow features (raw investor_wide → 7 new) ----
# Block 1.B: Foreign/Inst/Retail raw flow 5/21/60d rolling
cat(sprintf("[%s] Step 6 — Block 1.B raw flow rolling (investor_wide)\n",
    format(Sys.time(), "%H:%M:%S")))

inv <- as.data.table(read_parquet(".cache/investor_stock/investor_wide.parquet"))
inv[, Date := as.Date(Date)]
inv <- inv[Date >= lookback_start & Date <= SIG_CUTOFF + 60]
setorder(inv, Ticker, Date)
cat(sprintf("  investor_wide loaded: %d rows\n", nrow(inv)))

# Net flow per type (KRW) — 5/21/60d rolling sum (cumulative net buy in window)
inv[, foreign_flow_5d  := frollsum(Foreign,       n = 5L,  fill = NA, na.rm = TRUE), by = Ticker]
inv[, foreign_flow_21d := frollsum(Foreign,       n = 21L, fill = NA, na.rm = TRUE), by = Ticker]
inv[, foreign_flow_60d := frollsum(Foreign,       n = 60L, fill = NA, na.rm = TRUE), by = Ticker]
inv[, inst_flow_5d     := frollsum(Institutional, n = 5L,  fill = NA, na.rm = TRUE), by = Ticker]
inv[, inst_flow_21d    := frollsum(Institutional, n = 21L, fill = NA, na.rm = TRUE), by = Ticker]
inv[, retail_flow_21d  := frollsum(Individual,    n = 21L, fill = NA, na.rm = TRUE), by = Ticker]
# Retail flow as contrarian indicator (Barber-Odean 2000 evidence)
inv[, retail_flow_60d  := frollsum(Individual,    n = 60L, fill = NA, na.rm = TRUE), by = Ticker]

# Concentration: Foreign / (|Foreign|+|Inst|+|Retail|) — smart money ratio
inv[, smart_money_ratio_21d := foreign_flow_21d /
    (abs(foreign_flow_21d) + abs(inst_flow_21d) + abs(retail_flow_21d) + 1e6)]

# Normalize by market cap proxy (sig_date 시 size로 scale)
# 단순 raw flow 사용 — Risk가 cov 정합 시 처리
BLOCK1_B_COLS <- c("foreign_flow_5d", "foreign_flow_21d", "foreign_flow_60d",
                   "inst_flow_5d", "inst_flow_21d",
                   "retail_flow_21d", "retail_flow_60d",
                   "smart_money_ratio_21d")
cat(sprintf("  Block 1.B derived: %d cols\n", length(BLOCK1_B_COLS)))

# Merge inv into daily for downstream snapshot
inv_keep <- inv[, c("Date", "Ticker", BLOCK1_B_COLS), with = FALSE]
daily <- merge(daily, inv_keep, by = c("Date", "Ticker"), all.x = TRUE)
cat(sprintf("  Daily after merge: %d rows × %d cols\n", nrow(daily), ncol(daily)))

# ---- Step 7: Block 2 — Insider trading 21d/60d aggregates ----
cat(sprintf("[%s] Step 7 — Block 2 insider trades (DART)\n",
    format(Sys.time(), "%H:%M:%S")))

ins <- tryCatch(as.data.table(read_parquet(".cache/dart/insider_trades.parquet")),
                error = function(e) NULL)
if (!is.null(ins)) {
  ins[, Date := as.Date(Date)]
  ins[, rcept_dt := as.Date(rcept_dt)]
  # PIT: use rcept_dt (filing date) — already includes DART publication lag
  ins[, sp_stock_lmp_cnt        := as.numeric(gsub(",", "", sp_stock_lmp_cnt))]
  ins[, sp_stock_lmp_irds_cnt   := as.numeric(gsub(",", "", sp_stock_lmp_irds_cnt))]
  ins[, sp_stock_lmp_irds_rate  := as.numeric(gsub(",", "", sp_stock_lmp_irds_rate))]

  # Net change = irds_cnt signed (필요 시 부호 추정; 음수 sell, 양수 buy)
  # 임원 직책 = 등기/비등기 임원, 주요주주

  cat(sprintf("  insider trades: %d rows (date range %s ~ %s)\n",
      nrow(ins), as.character(min(ins$rcept_dt, na.rm = TRUE)),
      as.character(max(ins$rcept_dt, na.rm = TRUE))))

  # Insider feature aggregation per Ticker per Date — count windowed
  # Since file is sparse (9790 rows, 2024+), full PIT aggregate on rcept_dt

  build_insider_feat <- function(sd) {
    win21_start <- sd - 21
    win60_start <- sd - 60

    f21 <- ins[rcept_dt > win21_start & rcept_dt <= sd,
               .(insider_count_21d = .N,
                 insider_irds_sum_21d = sum(sp_stock_lmp_irds_cnt, na.rm = TRUE),
                 insider_buy_count_21d = sum(sp_stock_lmp_irds_cnt > 0, na.rm = TRUE)),
               by = Ticker]
    f60 <- ins[rcept_dt > win60_start & rcept_dt <= sd,
               .(insider_count_60d = .N,
                 insider_irds_sum_60d = sum(sp_stock_lmp_irds_cnt, na.rm = TRUE)),
               by = Ticker]
    if (nrow(f21) == 0 && nrow(f60) == 0) return(NULL)
    m <- merge(f21, f60, by = "Ticker", all = TRUE)
    m[, sig_date := sd]
    m[]
  }

  insider_feat_list <- lapply(sig_dates, build_insider_feat)
  insider_feat <- rbindlist(insider_feat_list, fill = TRUE)
  if (nrow(insider_feat) > 0) {
    # Fill NA → 0 for counts
    insider_feat[is.na(insider_count_21d),    insider_count_21d    := 0]
    insider_feat[is.na(insider_count_60d),    insider_count_60d    := 0]
    insider_feat[is.na(insider_irds_sum_21d), insider_irds_sum_21d := 0]
    insider_feat[is.na(insider_irds_sum_60d), insider_irds_sum_60d := 0]
    insider_feat[is.na(insider_buy_count_21d), insider_buy_count_21d := 0]
    # Buy/sell ratio: positive irds / total irds
    insider_feat[, insider_buy_ratio_21d := insider_buy_count_21d / pmax(insider_count_21d, 1)]
    cat(sprintf("  insider_feat: %d (sig_date, Ticker) rows\n", nrow(insider_feat)))
  }
} else {
  insider_feat <- NULL
  cat("  WARN: insider_trades.parquet not loaded\n")
}

# ---- Step 8: Snapshot at sig_date (t-1 PIT) ----
cat(sprintf("[%s] Step 8 — Monthly snapshot at sig_date (t-1 lag strict)\n",
    format(Sys.time(), "%H:%M:%S")))

all_trade_days <- sort(unique(daily$Date))
sig_to_lag_map <- sapply(sig_dates, function(sd) {
  prev_days <- all_trade_days[all_trade_days < sd]
  if (length(prev_days) == 0) return(NA_character_)
  as.character(max(prev_days))
})
n_mapped <- sum(!is.na(sig_to_lag_map))
cat(sprintf("  Mapped %d / %d sig_dates to t-1 trading days\n", n_mapped, length(sig_dates)))

setkey(daily, Date, Ticker)
sig_lag_dt <- data.table(
  sig_date = sig_dates,
  lag_date = as.Date(sig_to_lag_map)
)
sig_lag_dt <- sig_lag_dt[!is.na(lag_date)]

snap_keys <- data.table()
for (i in seq_len(nrow(sig_lag_dt))) {
  sd <- sig_lag_dt$sig_date[i]
  ld <- sig_lag_dt$lag_date[i]
  uni_now <- uni_list[[as.character(sd)]]
  if (length(uni_now) == 0) next
  snap_keys <- rbind(snap_keys,
    data.table(sig_date = sd, lag_date = ld, Ticker = uni_now))
}
cat(sprintf("  snap_keys: %d (sig_date, lag_date, Ticker) tuples\n", nrow(snap_keys)))

setnames(snap_keys, "lag_date", "Date")
snap_panel <- merge(daily, snap_keys[, .(sig_date, Date, Ticker)],
  by = c("Date", "Ticker"), all.x = FALSE, all.y = TRUE)
snap_panel[, Date := NULL]
cat(sprintf("  Snapshot panel: %d rows × %d cols\n", nrow(snap_panel), ncol(snap_panel)))

# Merge insider features (sig_date base)
if (!is.null(insider_feat) && nrow(insider_feat) > 0) {
  snap_panel <- merge(snap_panel, insider_feat, by = c("sig_date", "Ticker"), all.x = TRUE)
  # Fill insider NA → 0 (most stocks have no recent insider trades)
  insider_cols <- setdiff(names(insider_feat), c("sig_date", "Ticker"))
  for (cc in insider_cols) snap_panel[is.na(get(cc)), (cc) := 0]
  cat(sprintf("  Merged insider: %d cols\n", length(insider_cols)))
}

# ---- Step 9: Block 1 rolling moments on key flow factors ----
cat(sprintf("[%s] Step 9 — Block 1 rolling moments on top flow factors\n",
    format(Sys.time(), "%H:%M:%S")))

# For each sig_date, cross-section rank percent for top 8 flow + crowding factors
KEY_RANK <- c("INV01_Foreign_NetBuy_20d", "INV02_Foreign_NetBuy_60d",
              "INV05_Foreign_Momentum", "INV10_Smart_Money_Flow",
              "CR03_Herding_Dispersion", "CR08_Volume_Price_Divergence",
              "L02_Turnover", "L11_Kyle_Lambda")

for (f in KEY_RANK) {
  if (!(f %in% names(snap_panel))) next
  snap_panel[, paste0(f, "_rank_pct") := frank(get(f), ties.method = "average", na.last = "keep") / .N,
             by = sig_date]
}

# ---- Step 10: Block 4 cross-factor interactions (4개 — 학술 grounding) ----
cat(sprintf("[%s] Step 10 — Block 4 interactions\n", format(Sys.time(), "%H:%M:%S")))

zscore_xs <- function(x) {
  mu <- mean(x, na.rm = TRUE); sd <- sd(x, na.rm = TRUE)
  if (is.na(sd) || sd == 0) return(rep(0, length(x)))
  (x - mu) / sd
}

# Z-score normalize for interaction (per sig_date)
for (f in c("INV05_Foreign_Momentum", "INV07_Retail_Contrarian", "INV10_Smart_Money_Flow",
            "CR03_Herding_Dispersion", "CR05_Short_Pressure_Proxy",
            "L02_Turnover", "L11_Kyle_Lambda")) {
  if (!(f %in% names(snap_panel))) next
  snap_panel[, paste0(f, "_zxs") := zscore_xs(get(f)), by = sig_date]
}

# Academic interactions:
# I1. Smart Money × Crowding (Pollet-Wilson 2010 × Anton-Polk 2014)
if (all(c("INV10_Smart_Money_Flow_zxs", "CR03_Herding_Dispersion_zxs") %in% names(snap_panel)))
  snap_panel[, int_smart_crowd := INV10_Smart_Money_Flow_zxs * CR03_Herding_Dispersion_zxs]
# I2. Foreign Momentum × Turnover (institutional belief × liquidity availability)
if (all(c("INV05_Foreign_Momentum_zxs", "L02_Turnover_zxs") %in% names(snap_panel)))
  snap_panel[, int_foreign_turnover := INV05_Foreign_Momentum_zxs * L02_Turnover_zxs]
# I3. Retail Contrarian × Kyle Lambda (noise trader × price impact)
if (all(c("INV07_Retail_Contrarian_zxs", "L11_Kyle_Lambda_zxs") %in% names(snap_panel)))
  snap_panel[, int_retail_kyle := INV07_Retail_Contrarian_zxs * L11_Kyle_Lambda_zxs]
# I4. Short Pressure × Herding (Cohen-Diether-Malloy 2007 crowding reversal)
if (all(c("CR05_Short_Pressure_Proxy_zxs", "CR03_Herding_Dispersion_zxs") %in% names(snap_panel)))
  snap_panel[, int_short_herd := CR05_Short_Pressure_Proxy_zxs * CR03_Herding_Dispersion_zxs]

# ---- Step 11: Merge forward return label + sector ----
cat(sprintf("[%s] Step 11 — merge label + sector\n", format(Sys.time(), "%H:%M:%S")))

panel <- merge(snap_panel, fwd_ret[, .(sig_date, Ticker, log_ret_1m_w)],
               by = c("sig_date", "Ticker"), all.x = FALSE, all.y = FALSE)

sector_dt <- raw[, .(Ticker, Date, Sector_Lv2)]
sector_dt <- sector_dt[, .SD[.N], by = Ticker]
panel <- merge(panel, sector_dt[, .(Ticker, Sector_Lv2)], by = "Ticker", all.x = TRUE)

# Drop rows with all-NA features (handle low-coverage cases)
feature_cols <- setdiff(names(panel), c("sig_date", "Ticker", "log_ret_1m_w", "Sector_Lv2"))
# Compute non-NA count per row (use as.matrix on sub-data.table)
non_na_count <- rowSums(!is.na(as.matrix(panel[, .SD, .SDcols = feature_cols])))
n_before <- nrow(panel)
panel <- panel[non_na_count >= 5L]
cat(sprintf("  Panel filter (min 5 non-NA features): %d -> %d rows\n", n_before, nrow(panel)))

# ---- Step 12: Save panel ----
cat(sprintf("[%s] Step 12 — saving panel\n", format(Sys.time(), "%H:%M:%S")))
out_panel <- file.path(OUT_DIR, "altdata_panel_train.parquet")
write_parquet(panel, out_panel)
cat(sprintf("  Saved: %s (%d rows × %d cols)\n", out_panel, nrow(panel), ncol(panel)))

feature_cols_final <- setdiff(names(panel), c("sig_date", "Ticker", "log_ret_1m_w", "Sector_Lv2"))
cat(sprintf("  Feature cols: %d\n", length(feature_cols_final)))

writeLines(feature_cols_final, file.path(OUT_DIR, "feature_cols.txt"))

# Feature coverage diagnostics
cov_dt <- data.table(
  feature = feature_cols_final,
  coverage = sapply(feature_cols_final, function(c) mean(!is.na(panel[[c]])))
)
fwrite(cov_dt, file.path(OUT_DIR, "feature_coverage.csv"))
cat("  Coverage summary:\n")
cat(sprintf("    >0.95: %d / %d\n", sum(cov_dt$coverage > 0.95), nrow(cov_dt)))
cat(sprintf("    >0.50: %d / %d\n", sum(cov_dt$coverage > 0.50), nrow(cov_dt)))
cat(sprintf("    >0.05: %d / %d\n", sum(cov_dt$coverage > 0.05), nrow(cov_dt)))

# Feature-block tagging
block_tag <- sapply(feature_cols_final, function(f) {
  if (grepl("^INV", f) || grepl("flow|smart_money", f)) "Block1_Flow"
  else if (grepl("^insider", f)) "Block2_Insider"
  else if (grepl("^CR", f) || grepl("^SE", f)) "Block3_Crowding"
  else if (grepl("^L\\d", f)) "Block4_Microstructure"
  else if (grepl("^int_", f)) "Block5_Interaction"
  else "Other"
})
block_summary <- as.data.table(table(block_tag))
cat("  Block breakdown:\n"); print(block_summary)
fwrite(data.table(feature = feature_cols_final, block = unname(block_tag)),
       file.path(OUT_DIR, "feature_block_tag.csv"))

# Metadata
saveRDS(list(
  sig_dates = sig_dates,
  feature_cols = feature_cols_final,
  uni_size = uni_size,
  panel_rows = nrow(panel),
  build_time_min = round(as.numeric(difftime(Sys.time(), t0, units = "mins")), 2)
), file.path(OUT_DIR, "panel_meta.rds"))

write_json(list(
  sig_date_first = as.character(min(sig_dates)),
  sig_date_last  = as.character(max(sig_dates)),
  sig_date_count = length(sig_dates),
  feature_cols_n = length(feature_cols_final),
  panel_rows = nrow(panel),
  blocks = as.list(setNames(block_summary$N, block_summary$block_tag)),
  build_time_min = round(as.numeric(difftime(Sys.time(), t0, units = "mins")), 2)
), file.path(OUT_DIR, "panel_summary.json"), pretty = TRUE, auto_unbox = TRUE)

cat(sprintf("\n=== E_ALTDATA Step 1 COMPLETE — elapsed %.2f min ===\n",
    as.numeric(difftime(Sys.time(), t0, units = "mins"))))
