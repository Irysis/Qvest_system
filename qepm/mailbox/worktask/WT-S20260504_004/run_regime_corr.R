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

# Daily returns from RAWDATA
RAW <- read_parquet(file.path(PROJ, ".cache/rawdata.parquet")); setDT(RAW)
RAW_a <- RAW[Ticker %in% active & !is.na(Ret), .(Date, Ticker, Ret, BM_Ret)]
rwide <- dcast(RAW_a, Date ~ Ticker, value.var = "Ret")
rwide <- rwide[order(Date)]
bm_dt <- unique(RAW_a[!is.na(BM_Ret), .(Date, BM_Ret)])
setkey(rwide, Date); setkey(bm_dt, Date)
rwide <- bm_dt[rwide, on = "Date"]

# Regime label by 60d trailing BM cum return:  > +5% BULL, < -5% BEAR, else NORMAL
rwide[, bm_60d_cum := frollapply(BM_Ret, N = 60, FUN = function(x) prod(1+x, na.rm=TRUE)-1, align = "right")]
rwide[, regime := fifelse(bm_60d_cum > 0.05, "BULL",
                  fifelse(bm_60d_cum < -0.05, "BEAR", "NORMAL"))]

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

cat(sprintf("[regime] obs counts: BULL=%d BEAR=%d NORMAL=%d\n",
            sum(rwide$regime == "BULL", na.rm=TRUE),
            sum(rwide$regime == "BEAR", na.rm=TRUE),
            sum(rwide$regime == "NORMAL", na.rm=TRUE)))

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
  melt_cor(cor_norm, "NORMAL")
), use.names = TRUE, fill = TRUE)

write_parquet(out, file.path(SAGE, "regime_correlation.parquet"))

# Summary: avg pairwise correlation per regime
summ <- out[, .(avg_corr = mean(corr, na.rm=TRUE),
                med_corr = median(corr, na.rm=TRUE),
                n_pairs = .N), by = regime]
fwrite(summ, file.path(SAGE, "regime_correlation_summary.csv"))
print(summ)
cat("[regime] regime_correlation.parquet written\n")
