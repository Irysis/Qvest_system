#==============================================================================
# Append the latest sig_date (2026-04) alpha for downstream operational use.
# alpha_scores parquet was IC merge with forward return, so last sig_date (no fwd ret) dropped.
# We re-compute C4_D57_Down_Vol alpha for 2026-04-30 sig_date and append.
#==============================================================================

suppressPackageStartupMessages({
  library(arrow); library(data.table); library(jsonlite)
})

BASE <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
ART  <- file.path(BASE, "stage_artifacts/WT_D20260513_001")
MBOX <- file.path(BASE, "qepm/mailbox/worktask/WT-D20260513_001")

source(file.path(BASE, "02_Infrastructure/factor_db/factor_db_connector.R"))

raw <- as.data.table(read_parquet(file.path(BASE, ".cache/rawdata.parquet")))
setkey(raw, Date, Ticker)

LATEST_SIG <- as.Date("2026-04-30")
# Find actual closest available month-end
actual_sig <- raw[Date <= LATEST_SIG, max(Date)]
cat("Operational sig_date:", as.character(actual_sig), "\n")

# Universe + liquidity
raw[, TV := as.numeric(Vol) * as.numeric(Close)]
setkey(raw, Ticker, Date)
raw[, ADV_20d := frollmean(TV, n = 20L, align = "right", na.rm = TRUE), by = Ticker]
setkey(raw, Date, Ticker)

univ_row <- raw[Date == actual_sig]
univ <- univ_row[(K200 == TRUE | KQ150 == TRUE) &
                 !is.na(ADV_20d) & ADV_20d >= 2e8 &
                 (is.na(AdminStock) | AdminStock == FALSE) &
                 (is.na(TradingHalt) | TradingHalt == FALSE) &
                 (is.na(UnfaithfulDisc) | UnfaithfulDisc == FALSE), Ticker]
cat("Universe size at", as.character(actual_sig), ":", length(univ), "\n")

# Factor DB
fdb <- load_month_factors(actual_sig, coverage_min = 0.05)
NEEDED <- c("D57_Down_Vol")
fsub <- fdb[Factor_Name %in% NEEDED & Ticker %in% univ]
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
fwide[, sig_date := actual_sig]
out <- fwide[, .(sig_date, Ticker, alpha)]
cat("Latest alpha rows:", nrow(out), "\n")
cat("Top10:\n"); print(out[order(-alpha)][1:10])

# Append to existing alpha_scores
existing <- as.data.table(read_parquet(file.path(ART, "alpha_scores.parquet")))
combined <- rbind(existing, out)
combined <- unique(combined, by = c("sig_date", "Ticker"))
setorder(combined, sig_date, -alpha)
write_parquet(combined, file.path(ART, "alpha_scores.parquet"))
cat("Combined alpha_scores rows:", nrow(combined),
    " sig_dates:", uniqueN(combined$sig_date),
    " last sig:", as.character(max(combined$sig_date)), "\n")

# Also patch the alpha_package_draft.json with the latest as_of alpha_vector
pkg <- fromJSON(file.path(MBOX, "alpha_package_draft.json"), simplifyVector = FALSE)
ranked <- out[order(-alpha)]
alpha_vector <- setNames(as.list(as.numeric(ranked$alpha)), as.character(ranked$Ticker))
# Confidence vector: scaled by abs(alpha) percentile
abs_a <- abs(ranked$alpha)
denom <- if (max(abs_a) > min(abs_a)) (max(abs_a) - min(abs_a)) else 1
conf <- (abs_a - min(abs_a)) / denom
conf <- pmin(1, pmax(0, conf))
confidence_vector <- setNames(as.list(as.numeric(conf)), as.character(ranked$Ticker))

pkg$alpha_vector <- alpha_vector
pkg$confidence_vector <- confidence_vector
pkg$as_of_sig_date_actual <- as.character(actual_sig)
pkg$alpha_vector_n_tickers <- length(alpha_vector)
write_json(pkg, file.path(MBOX, "alpha_package_draft.json"),
           pretty = TRUE, auto_unbox = TRUE, null = "null", na = "null")
cat("alpha_package_draft.json patched. n_tickers in alpha_vector:", length(alpha_vector), "\n")

cat("\n=== DONE append ===\n")
