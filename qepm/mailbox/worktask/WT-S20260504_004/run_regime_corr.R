# Regime correlation: BULL / BEAR / NORMAL → STR_1715 active correlation shift
suppressPackageStartupMessages({
  library(arrow); library(data.table); library(jsonlite)
})
PROJ <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
SAGE <- file.path(PROJ, "stage_artifacts/WT_WT-S20260504_004")

# Load active 18 weights
w_csv <- file.path(PROJ,
  "04_Research/strategies/STR_1715_WT016_Iter31_GridBestProd/production_weights/20260501_weights_cap_0p20.csv")
w_dt <- fread(w_csv); w_dt <- w_dt[Weight > 0]
active <- w_dt$Ticker

# PIT: cap at as_of_date 2026-04-30 (NOT current 2026-05-04)
AS_OF <- as.Date("2026-04-30")

# Daily returns from RAWDATA
RAW <- read_parquet(file.path(PROJ, ".cache/rawdata.parquet")); setDT(RAW)
RAW <- RAW[Date <= AS_OF]  # PIT cutoff
RAW_a <- RAW[Ticker %in% active & !is.na(Ret), .(Date, Ticker, Ret, BM_Ret)]
rwide <- dcast(RAW_a, Date ~ Ticker, value.var = "Ret")
rwide <- rwide[order(Date)]
bm_dt <- unique(RAW_a[!is.na(BM_Ret), .(Date, BM_Ret)])
setkey(rwide, Date); setkey(bm_dt, Date)
rwide <- bm_dt[rwide, on = "Date"]

# Regime label by 60d trailing BM cum return WITH t-1 LAG (PIT C9):
# Compute the rolling cumulative on BM_Ret, then SHIFT it by 1 day for use as label
rwide[, bm_60d_cum_raw := frollapply(BM_Ret, N = 60, FUN = function(x) prod(1+x, na.rm=TRUE)-1, align = "right")]
rwide[, bm_60d_cum := shift(bm_60d_cum_raw, n = 1L, type = "lag")]  # t-1 lag (C9)
rwide[, regime := fifelse(is.na(bm_60d_cum), NA_character_,
                  fifelse(bm_60d_cum > 0.05, "BULL",
                  fifelse(bm_60d_cum < -0.05, "BEAR", "NORMAL")))]
# Also classify CRISIS as severe BEAR (cum_60d < -15%)
rwide[, regime_v2 := fifelse(is.na(bm_60d_cum), NA_character_,
                     fifelse(bm_60d_cum < -0.15, "CRISIS",
                     fifelse(bm_60d_cum < -0.05, "CAUTION",
                     fifelse(bm_60d_cum > 0.05,  "BULL", "NORMAL"))))]

# Compute corr per regime
get_cor <- function(dt, regime_label) {
  sub <- dt[regime == regime_label, .SD, .SDcols = active]
  sub <- as.matrix(sub)
  sub[is.na(sub)] <- 0
  if (nrow(sub) < 30) return(NULL)
  cor(sub, use = "pairwise.complete.obs")
}

cor_bull <- get_cor(rwide, "BULL")
cor_bear <- get_cor(rwide, "BEAR")
cor_norm <- get_cor(rwide, "NORMAL")

# v2 4-regime
get_cor_v2 <- function(dt, label) {
  sub <- dt[regime_v2 == label, .SD, .SDcols = active]
  sub <- as.matrix(sub); sub[is.na(sub)] <- 0
  if (nrow(sub) < 30) return(NULL)
  cor(sub, use = "pairwise.complete.obs")
}
cor_crisis  <- get_cor_v2(rwide, "CRISIS")
cor_caution <- get_cor_v2(rwide, "CAUTION")

cat(sprintf("[regime v1] BULL=%d BEAR=%d NORMAL=%d (PIT C9 t-1 lagged)\n",
            sum(rwide$regime == "BULL", na.rm=TRUE),
            sum(rwide$regime == "BEAR", na.rm=TRUE),
            sum(rwide$regime == "NORMAL", na.rm=TRUE)))
cat(sprintf("[regime v2] CRISIS=%d CAUTION=%d BULL=%d NORMAL=%d\n",
            sum(rwide$regime_v2 == "CRISIS", na.rm=TRUE),
            sum(rwide$regime_v2 == "CAUTION", na.rm=TRUE),
            sum(rwide$regime_v2 == "BULL", na.rm=TRUE),
            sum(rwide$regime_v2 == "NORMAL", na.rm=TRUE)))

# Long format: each pair x regime
melt_cor <- function(C, label) {
  if (is.null(C)) return(NULL)
  dt <- as.data.table(as.table(C))
  setnames(dt, c("Ticker_i", "Ticker_j", "corr"))
  dt[, regime := label]
  dt[Ticker_i != Ticker_j]
}
out <- rbindlist(list(
  melt_cor(cor_bull, "BULL"),
  melt_cor(cor_bear, "BEAR"),
  melt_cor(cor_norm, "NORMAL"),
  melt_cor(cor_crisis,  "CRISIS"),
  melt_cor(cor_caution, "CAUTION")
), use.names = TRUE, fill = TRUE)

write_parquet(out, file.path(SAGE, "regime_correlation.parquet"))

# Summary: avg pairwise correlation per regime
summ <- out[, .(avg_corr = mean(corr, na.rm=TRUE),
                med_corr = median(corr, na.rm=TRUE),
                n_pairs = .N), by = regime]
fwrite(summ, file.path(SAGE, "regime_correlation_summary.csv"))
print(summ)
cat("[regime] regime_correlation.parquet written\n")
