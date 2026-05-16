#==============================================================================
# Append last sig_date (2026-04-30) alpha for operational use.
# v2 alpha-research dropped the last sig_date because forward return unavailable.
# This patches alpha_scores.parquet AND alpha_package_draft.json alpha_vector.
#==============================================================================
suppressPackageStartupMessages({
  library(arrow); library(data.table); library(jsonlite)
})
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0) b else a

BASE <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
ART  <- file.path(BASE, "stage_artifacts/WT_D20260513_001")
MBOX <- file.path(BASE, "qepm/mailbox/worktask/WT-D20260513_001")

source(file.path(BASE, "02_Infrastructure/factor_db/factor_db_connector.R"))

raw <- as.data.table(read_parquet(file.path(BASE, ".cache/rawdata.parquet")))
setkey(raw, Date, Ticker)
raw[, TV := as.numeric(Vol) * as.numeric(Close)]
setkey(raw, Ticker, Date)
raw[, ADV_20d := frollmean(TV, n = 20L, align = "right", na.rm = TRUE), by = Ticker]
setkey(raw, Date, Ticker)

# Use last month-end trading day in 2026-04
all_trade_dates <- sort(unique(raw$Date))
trade_dt <- data.table(Date = all_trade_dates, ym = format(all_trade_dates, "%Y-%m"))
ME_2026_04 <- trade_dt[ym == "2026-04", max(Date)]
cat("Operational sig_date (true month-end):", as.character(ME_2026_04), "\n")

# Universe + liquidity at ME_2026_04
univ_row <- raw[Date == ME_2026_04]
univ <- univ_row[(K200 == TRUE | KQ150 == TRUE) &
                 !is.na(ADV_20d) & ADV_20d >= 2e8 &
                 (is.na(AdminStock) | AdminStock == FALSE) &
                 (is.na(TradingHalt) | TradingHalt == FALSE) &
                 (is.na(UnfaithfulDisc) | UnfaithfulDisc == FALSE), Ticker]
cat("Universe size:", length(univ), "\n")

# Verify PIT-clean: factor file Date <= ME_2026_04
ym_tag <- format(ME_2026_04, "%Y%m")
fpath  <- file.path(BASE, ".cache/factor_db", paste0("factor_db_", ym_tag, ".parquet"))
if (file.exists(fpath)) {
  raw_dates <- unique(as.Date(as.data.table(read_parquet(fpath))$Date))
  raw_dates <- raw_dates[!is.na(raw_dates)]
  max_fd <- max(raw_dates)
  cat("Factor file max Date:", as.character(max_fd), "(vs sig_date ", as.character(ME_2026_04), ")\n")
  stopifnot(max_fd <= ME_2026_04)
}

fdb <- load_month_factors(ME_2026_04, coverage_min = 0.05)
fsub <- fdb[Factor_Name == "D57_Down_Vol" & Ticker %in% univ]
cat("Down_Vol rows:", nrow(fsub), "\n")

cs_z <- function(x) {
  mu <- mean(x, na.rm = TRUE); sd_ <- sd(x, na.rm = TRUE)
  z <- (x - mu) / sd_
  z[!is.na(z) & z >  3] <-  3
  z[!is.na(z) & z < -3] <- -3
  z
}

fwide <- dcast(fsub, Ticker ~ Factor_Name, value.var = "Z_Score_Aligned")
fwide[, alpha := cs_z(D57_Down_Vol)]
fwide <- fwide[!is.na(alpha) & is.finite(alpha)]
fwide[, sig_date := ME_2026_04]
out <- fwide[, .(sig_date, Ticker, alpha)]
cat("Last sig_date alpha rows:", nrow(out), "\n")

# Append to alpha_scores.parquet
existing <- as.data.table(read_parquet(file.path(ART, "alpha_scores.parquet")))
combined <- rbind(existing, out)
combined <- unique(combined, by = c("sig_date", "Ticker"))
setorder(combined, sig_date, -alpha)
write_parquet(combined, file.path(ART, "alpha_scores.parquet"))
cat("Combined alpha_scores rows:", nrow(combined),
    " sig_dates:", uniqueN(combined$sig_date),
    " last_sig:", as.character(max(combined$sig_date)), "\n")

# Patch alpha_package_draft.json alpha_vector
pkg <- fromJSON(file.path(MBOX, "alpha_package_draft.json"), simplifyVector = FALSE)
ranked <- out[order(-alpha)]
alpha_vector <- setNames(as.list(as.numeric(ranked$alpha)), as.character(ranked$Ticker))
abs_a <- abs(ranked$alpha)
denom <- if (max(abs_a) > min(abs_a)) (max(abs_a) - min(abs_a)) else 1
conf <- pmin(1, pmax(0, (abs_a - min(abs_a)) / denom))
confidence_vector <- setNames(as.list(as.numeric(conf)), as.character(ranked$Ticker))
pkg$alpha_vector <- alpha_vector
pkg$confidence_vector <- confidence_vector
pkg$alpha_vector_n_tickers <- length(alpha_vector)

write_json(pkg, file.path(MBOX, "alpha_package_draft.json"),
           pretty = TRUE, auto_unbox = TRUE, null = "null", na = "null")
cat("alpha_package_draft.json patched. n_tickers in alpha_vector:", length(alpha_vector), "\n")

# Top10 names
top <- merge(ranked[1:10], raw[Date == ME_2026_04, .(Ticker, Name, Sector_Lv2)], by = "Ticker", all.x = TRUE)
setorder(top, -alpha)
cat("\nTop10 by alpha at 2026-04-30:\n")
print(top[, .(rank=1:.N, Ticker, alpha=round(alpha,3), Name, Sector_Lv2)])

cat("\nDONE append latest alpha v2\n")
