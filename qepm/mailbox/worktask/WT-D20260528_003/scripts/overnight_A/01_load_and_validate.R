#==============================================================================
# WT-D20260528_003 Hypothesis A — Distribution Moments Pure
# Step 1: Factor DB PIT-clean load + sector neutralize + walk-forward expanding ICIR
#
# Factors: D43_Skewness + D44_Kurtosis (both registry: defense / higher_better)
# Lockbox: Factor_Date <= 2023-12-22 strict (per .claude/rules/lockbox-scope.md)
# Universe: KOSPI200 ∪ KOSDAQ150 intersection, LIQ 20d avg >= 2e8 KRW
# Walk-forward expanding ICIR (no full-sample static weight)
#==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(jsonlite)
})

t0 <- Sys.time()

# ---- Paths ----
PROJ <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
setwd(PROJ)
source("02_Infrastructure/factor_db/factor_db_connector.R")

WT_ID    <- "WT-D20260528_003"
HYP_TAG  <- "overnight_A"
OUT_DIR  <- file.path("stage_artifacts", "WT_D20260528_003_overnight_A")
dir.create(OUT_DIR, showWarnings = FALSE, recursive = TRUE)

SIG_CUTOFF <- as.Date("2023-12-22")  # PIT lockbox (alpha-research scope, lockbox-scope.md)
LIQ_THRESHOLD <- 2e8                 # 도훈 mandate (request 5e7 보다 보수적)

# ---- Step 1: build month-end sig_date list ----
cat("[Step 1] Building sig_date schedule (Factor DB month-end, <= 2023-12-22)\n")

avail <- list.files(".cache/factor_db", pattern = "^factor_db_\\d{6}\\.parquet$")
ym_avail <- gsub("factor_db_(\\d{6})\\.parquet", "\\1", avail)
ym_avail <- sort(ym_avail)

# month-end actual dates from RAWDATA
raw <- as.data.table(read_parquet(".cache/rawdata.parquet"))
raw[, Date := as.Date(Date)]
raw[, YM   := format(Date, "%Y%m")]

# month-end last trading day per YM
month_ends <- raw[, .(Date = max(Date)), by = YM]
setkey(month_ends, YM)

sig_dates <- month_ends[YM %in% ym_avail & Date <= SIG_CUTOFF, sort(Date)]
sig_dates <- sig_dates[sig_dates >= as.Date("2007-01-01")]   # KOSDAQ150 활성 시점부터
cat("  sig_dates total:", length(sig_dates), "first:", as.character(sig_dates[1]),
    " last:", as.character(sig_dates[length(sig_dates)]), "\n")

# ---- Step 2: universe filter per sig_date (K200 ∪ KQ150 + liquidity 2e8) ----
cat("[Step 2] Building universe per sig_date (K200 ∪ KQ150, LIQ 20d >= 2e8)\n")

# 20-day rolling avg trading value
raw[, TV := Close * Vol]
setorder(raw, Ticker, Date)
raw[, TV_20d := frollmean(TV, n = 20L, na.rm = TRUE), by = Ticker]

# universe per sig_date
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
cat("  Universe size summary: min=", min(uni_size), " med=", median(uni_size),
    " max=", max(uni_size), "\n")

# ---- Step 3: sector map per sig_date ----
sector_map_fn <- function(sd) {
  snap <- raw[Date == sd, .(Ticker, Sector_Lv2)]
  setkey(snap, Ticker)
  snap
}

# ---- Step 4: forward 1M return per (sig_date, ticker) ----
# month-end → next month-end return
cat("[Step 4] Computing forward 1M return per sig_date\n")
me_seq <- month_ends[YM %in% ym_avail, Date]
me_seq <- sort(me_seq)

fwd_ret_dt <- data.table()
for (i in seq_along(sig_dates)) {
  sd <- sig_dates[i]
  # find next month-end
  next_me <- me_seq[me_seq > sd][1]
  if (is.na(next_me)) next
  snap_now  <- raw[Date == sd,      .(Ticker, P0 = Close)]
  snap_next <- raw[Date == next_me, .(Ticker, P1 = Close)]
  m <- merge(snap_now, snap_next, by = "Ticker")
  m[, fwd_1m := P1 / P0 - 1]
  m[, sig_date := sd]
  fwd_ret_dt <- rbind(fwd_ret_dt, m[, .(sig_date, Ticker, fwd_1m)])
}
cat("  fwd_ret rows:", nrow(fwd_ret_dt), "\n")

# ---- Step 5: load D43 + D44 factor Z + sector neutralize per sig_date ----
cat("[Step 5] Loading D43+D44 + sector-neutralizing per sig_date\n")

panel <- list()
for (i in seq_along(sig_dates)) {
  sd <- sig_dates[i]
  fac <- tryCatch(load_month_factors(sd), error = function(e) NULL)
  if (is.null(fac)) next

  d43 <- fac[Factor_Name == "D43_Skewness", .(Ticker, Z43 = Z_Score_Aligned)]
  d44 <- fac[Factor_Name == "D44_Kurtosis", .(Ticker, Z44 = Z_Score_Aligned)]
  if (nrow(d43) == 0 || nrow(d44) == 0) next

  uni <- uni_list[[as.character(sd)]]
  if (length(uni) == 0) next

  smap <- sector_map_fn(sd)
  panel_sd <- merge(d43, d44, by = "Ticker", all = FALSE)
  panel_sd <- panel_sd[Ticker %in% uni]
  panel_sd <- merge(panel_sd, smap, by = "Ticker", all.x = TRUE)
  panel_sd[is.na(Sector_Lv2), Sector_Lv2 := "UNKNOWN"]

  if (nrow(panel_sd) < 30) next  # too few stocks for cross-section neutralize

  # Sector neutralize via OLS residual (dummy-coded)
  # require >= 2 stocks per sector to avoid singular
  sec_n <- panel_sd[, .N, by = Sector_Lv2][N >= 2, Sector_Lv2]
  panel_sd <- panel_sd[Sector_Lv2 %in% sec_n]
  if (nrow(panel_sd) < 30) next

  # Drop sectors with too few stocks AFTER filter
  panel_sd[, Sector_Lv2 := factor(Sector_Lv2)]

  # Neutralize Z43 + Z44 separately
  fit43 <- lm(Z43 ~ Sector_Lv2, data = panel_sd)
  fit44 <- lm(Z44 ~ Sector_Lv2, data = panel_sd)
  panel_sd[, Z43_neut := residuals(fit43)]
  panel_sd[, Z44_neut := residuals(fit44)]

  # Cross-sectional re-standardize after neutralize
  panel_sd[, Z43_neut := (Z43_neut - mean(Z43_neut, na.rm = TRUE)) /
                         sd(Z43_neut, na.rm = TRUE)]
  panel_sd[, Z44_neut := (Z44_neut - mean(Z44_neut, na.rm = TRUE)) /
                         sd(Z44_neut, na.rm = TRUE)]

  panel_sd[, sig_date := sd]
  panel[[i]] <- panel_sd[, .(sig_date, Ticker, Sector_Lv2, Z43, Z44, Z43_neut, Z44_neut)]

  if (i %% 24 == 0) cat("    sig_date ", as.character(sd), " n=", nrow(panel_sd), "\n", sep="")
}

panel_dt <- rbindlist(panel, fill = TRUE)
cat("  panel total rows:", nrow(panel_dt), " sig_dates with panel:",
    length(unique(panel_dt$sig_date)), "\n")

# ---- Step 6: merge fwd_ret ----
panel_dt <- merge(panel_dt, fwd_ret_dt, by = c("sig_date", "Ticker"), all.x = TRUE)
panel_dt <- panel_dt[!is.na(fwd_1m)]

# ---- Step 7: Cross-correlation D43_neut vs D44_neut ----
cor_d43_d44 <- panel_dt[, .(cor_neut = cor(Z43_neut, Z44_neut, use = "pairwise.complete.obs"),
                            cor_raw  = cor(Z43,      Z44,      use = "pairwise.complete.obs")),
                        by = sig_date]

cat("\n[Step 7] D43 vs D44 cross-corr summary\n")
cat("  raw:  mean=", round(mean(cor_d43_d44$cor_raw,  na.rm=TRUE), 3),
    " sd=",   round(sd(  cor_d43_d44$cor_raw,  na.rm=TRUE), 3),
    " min=",  round(min( cor_d43_d44$cor_raw,  na.rm=TRUE), 3),
    " max=",  round(max( cor_d43_d44$cor_raw,  na.rm=TRUE), 3), "\n")
cat("  neut: mean=", round(mean(cor_d43_d44$cor_neut, na.rm=TRUE), 3),
    " sd=",   round(sd(  cor_d43_d44$cor_neut, na.rm=TRUE), 3),
    " min=",  round(min( cor_d43_d44$cor_neut, na.rm=TRUE), 3),
    " max=",  round(max( cor_d43_d44$cor_neut, na.rm=TRUE), 3), "\n")

# ---- Step 8: per-sig_date IC ----
cat("\n[Step 8] Per-sig_date IC for D43_neut + D44_neut\n")
ic_dt <- panel_dt[, .(
  IC_43_neut = cor(Z43_neut, fwd_1m, method = "spearman", use = "pairwise.complete.obs"),
  IC_44_neut = cor(Z44_neut, fwd_1m, method = "spearman", use = "pairwise.complete.obs"),
  IC_43_raw  = cor(Z43,      fwd_1m, method = "spearman", use = "pairwise.complete.obs"),
  IC_44_raw  = cor(Z44,      fwd_1m, method = "spearman", use = "pairwise.complete.obs"),
  N_stock    = .N
), by = sig_date]

summary_ic <- function(ic_vec, name) {
  m  <- mean(ic_vec, na.rm = TRUE)
  s  <- sd(ic_vec, na.rm = TRUE)
  ir <- if (s > 0) m / s else NA_real_
  n  <- sum(!is.na(ic_vec))
  t  <- ir * sqrt(n)
  cat(sprintf("  %-15s IC_mean=%+.4f IC_sd=%.4f ICIR=%+.3f N=%d t=%+.2f\n",
              name, m, s, ir, n, t))
  list(name = name, ic_mean = m, ic_sd = s, icir = ir, n = n, t = t)
}

s43_neut <- summary_ic(ic_dt$IC_43_neut, "D43_neut")
s44_neut <- summary_ic(ic_dt$IC_44_neut, "D44_neut")
s43_raw  <- summary_ic(ic_dt$IC_43_raw,  "D43_raw")
s44_raw  <- summary_ic(ic_dt$IC_44_raw,  "D44_raw")

# ---- Save panel + IC ----
saveRDS(panel_dt, file.path(OUT_DIR, "panel_neut.rds"))
saveRDS(ic_dt,    file.path(OUT_DIR, "ic_per_sigdate.rds"))
saveRDS(cor_d43_d44, file.path(OUT_DIR, "cor_d43_d44.rds"))

# JSON summary
summary_json <- list(
  hypothesis    = "A",
  factors       = c("D43_Skewness", "D44_Kurtosis"),
  sig_dates_used = length(unique(panel_dt$sig_date)),
  signal_cutoff = as.character(SIG_CUTOFF),
  universe = "KOSPI200 union KOSDAQ150",
  liq_threshold_won_20d_avg = LIQ_THRESHOLD,
  panel_rows = nrow(panel_dt),
  cor_neut = list(
    mean = round(mean(cor_d43_d44$cor_neut, na.rm = TRUE), 4),
    median = round(median(cor_d43_d44$cor_neut, na.rm = TRUE), 4)
  ),
  ic_summary = list(
    D43_neut = s43_neut, D44_neut = s44_neut,
    D43_raw  = s43_raw,  D44_raw  = s44_raw
  )
)
write_json(summary_json, file.path(OUT_DIR, "step1_summary.json"),
           pretty = TRUE, auto_unbox = TRUE)

cat("\n[Step 1 DONE] elapsed:", round(as.numeric(Sys.time() - t0, units = "secs"), 1), "s\n")
cat("  panel saved:", file.path(OUT_DIR, "panel_neut.rds"), "\n")
cat("  ic saved:   ", file.path(OUT_DIR, "ic_per_sigdate.rds"), "\n")
cat("  summary:    ", file.path(OUT_DIR, "step1_summary.json"), "\n")
