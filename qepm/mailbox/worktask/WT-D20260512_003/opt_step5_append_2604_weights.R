#==============================================================================
# WT-D20260512_003 Optimizer Step 5 — Append 2026-04-01 live weight to schedule
#
# Step 2b/2d walk-forward loop ran for i in 1:(length(sig_dates)-1) = 1:267,
# producing weights for sig_dates 1..267 (2004-01-01 ~ 2026-03-01). The 268th
# sig_date (2026-04-01) needs separate computation for the live weight emission
# at the as-of date.
#
# Append AlphaSoftmax_T05 weight for sig_date 2026-04-01 to weights.csv.
#==============================================================================

suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite); library(digest)
})

BASE_DIR <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
setwd(BASE_DIR)

cat("============================================================\n")
cat("[OPT-Step5] Append 2026-04-01 weight to schedule\n")
cat("============================================================\n\n")

WT <- "WT-D20260512_003"
stage <- file.path("stage_artifacts", "WT_D20260512_003")
mailbox <- file.path("qepm/mailbox/worktask", WT)

ae <- readRDS(file.path(stage, "alpha_emission.rds"))
asc <- ae$alpha_scores[!is.na(z_blend_composite)]
setkey(asc, Date, Ticker)

raw <- as.data.table(read_parquet(".cache/rawdata.parquet",
                                   col_select = c("Date", "Ticker", "Close", "Vol", "Ret")))
raw[, TradingAmt := Close * Vol]
setkey(raw, Date, Ticker)

as_of <- as.Date("2026-04-01")
UB <- 0.20; LB <- 0.0; LIQ_THRESHOLD <- 5e7; MAX_NAMES <- 20L

# Helpers (same as Step 2b)
normalize_long_only <- function(w, lb = 0, ub = 0.20, target_sum = 1) {
  w[is.na(w)] <- 0
  w[w < lb] <- lb
  if (sum(w) == 0) {
    w <- rep(target_sum / length(w), length(w))
    return(w)
  }
  w <- w / sum(w) * target_sum
  iter <- 0
  while (any(w > ub + 1e-12) && sum(w) > 0 && iter < 100) {
    excess_idx <- which(w > ub)
    excess <- sum(w[excess_idx]) - length(excess_idx) * ub
    w[excess_idx] <- ub
    free <- setdiff(seq_along(w), excess_idx)
    if (length(free) == 0) break
    if (sum(w[free]) == 0) w[free] <- excess / length(free)
    else w[free] <- w[free] + excess * (w[free] / sum(w[free]))
    w <- w / sum(w) * target_sum
    iter <- iter + 1
  }
  w
}

alpha_softmax <- function(alpha_t, temperature = 0.5, lb = 0, ub = 0.20) {
  ax <- alpha_t / temperature
  ax <- ax - max(ax)
  w_raw <- exp(ax)
  w <- w_raw / sum(w_raw)
  names(w) <- names(alpha_t)
  normalize_long_only(w, lb = lb, ub = ub, target_sum = 1)
}

# Build alpha + liquidity filter at 2026-04-01
panel_t <- asc[Date == as_of]
cat(sprintf("alpha panel @ %s: %d tickers (regime=%s)\n",
            as_of, nrow(panel_t), panel_t$regime_state[1L]))

regime_i <- panel_t$regime_state[1L]
setorder(panel_t, -z_blend_composite)
picks <- panel_t[seq_len(min(MAX_NAMES, .N))]
alpha_t <- picks$z_blend_composite
names(alpha_t) <- picks$Ticker

# Liquidity filter
start_d <- raw[Date >= as_of, Date[1L]]
if (is.na(start_d)) start_d <- max(raw$Date)
liq_data <- raw[Date >= (start_d - 30L) & Date < start_d,
                 .(AvgTA = mean(TradingAmt, na.rm=TRUE)), by = Ticker]
liquid_tk <- liq_data[AvgTA >= LIQ_THRESHOLD, Ticker]
tickers_liq <- intersect(names(alpha_t), liquid_tk)
if (length(tickers_liq) < 5L) tickers_liq <- names(alpha_t)
alpha_t_liq <- alpha_t[tickers_liq]

# Selected method = AlphaSoftmax_T05
ub_use <- if (regime_i == "CRISIS") min(UB, 0.10) else UB
w_2604 <- alpha_softmax(alpha_t_liq, temperature = 0.5, lb = LB, ub = ub_use)

cat(sprintf("\n2026-04-01 weights (AlphaSoftmax_T05, regime=%s, ub_use=%.2f):\n",
            regime_i, ub_use))
cat(sprintf("  n=%d | Σw=%.6f | max_w=%.4f | min_w=%.4f\n",
            length(w_2604), sum(w_2604), max(w_2604), min(w_2604)))

w_2604_dt <- data.table(
  sig_date = as_of,
  ticker = names(w_2604),
  weight = as.numeric(w_2604),
  regime = regime_i,
  method = "AlphaSoftmax_T05"
)
setorder(w_2604_dt, -weight)
print(w_2604_dt)

# Append to weights.csv
weights_csv <- fread(file.path(stage, "weights.csv"))
weights_csv <- rbindlist(list(weights_csv, w_2604_dt), fill = TRUE)
setorder(weights_csv, sig_date, -weight)
fwrite(weights_csv, file.path(stage, "weights.csv"))

cat(sprintf("\nweights.csv updated: %d rows | %d sig_dates\n",
            nrow(weights_csv), length(unique(weights_csv$sig_date))))

cat(sprintf("Density: %d / 268 = %.3f\n",
            length(unique(weights_csv$sig_date)),
            length(unique(weights_csv$sig_date)) / 268))

# Save 2026-04-01 live snapshot separately
fwrite(w_2604_dt, file.path(stage, "weights_2026_04_01.csv"))
cat(sprintf("Saved: %s\n", file.path(stage, "weights_2026_04_01.csv")))

cat("[OPT-Step5] DONE\n")
