#==============================================================================
# WT-D20260514_003 — Build final weights.csv (multi-method × walk-forward)
# Output format: long-format with method + as_of_date + Ticker + weight
# Schedule density ≥ 0.95 of alpha sig_dates (Charter §9)
#==============================================================================

suppressMessages({
  library(arrow); library(data.table); library(jsonlite)
})
PROJECT_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
setwd(PROJECT_ROOT)
WT_ID <- "WT-D20260514_003"
STAGE <- "stage_artifacts/WT_D20260514_003"
OPTWS <- file.path(STAGE, "optimizer_workspace")

# Load existing v2 weights (5 baseline methods)
weights_dt <- fread(file.path(OPTWS, "weights_long_v2.csv"))
weights_dt[, as_of_date := as.Date(as_of_date)]
weights_dt[, decision_date := as.Date(decision_date)]
cat("[final] base 5 methods weights:", nrow(weights_dt), "rows\n")

# Build RCD_dynamic weights (regime-conditional sleeve betas)
# Decision: CRISIS/CAUTION → β_c2=0.30 ; NORMAL → 0.10 ; BULL → 0.00
# Then ticker-level = β_c2 × c2_in_sleeve + β_s17 × overlay × s17_in_sleeve + cash

# Load underlying sleeve data
c2_alpha <- as.data.table(read_parquet(file.path(STAGE, "alpha_scores.parquet")))
setnames(c2_alpha, "sig_date", "Date")
c2_alpha[, ym := format(Date, "%Y-%m")]
str1715_alpha <- as.data.table(read_parquet(
  "05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/02_holdings_universe/alpha_scores_str1715_268m.parquet"
))
str1715_alpha[, ym := format(Date, "%Y-%m")]
pg2_sched <- fread(
  "05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/02_holdings_universe/weights_267m_timeseries.csv"
)
pg2_sched[, as_of_date := as.Date(as_of_date)]
pg2_sched[, sig_ym := realized_ym]
suppressMessages({
  RAWDATA <- as.data.table(read_parquet(".cache/RAWDATA.parquet"))
})
setkey(RAWDATA, Date, Ticker)
sector_pit <- RAWDATA[, .(Sector = last(Sector)), by = .(Date, Ticker)]
ticker_last_sector <- RAWDATA[!is.na(Sector), .(latest_sector = last(Sector)), by = Ticker]
setkey(ticker_last_sector, Ticker)

# Helpers (same as run_optimizer_v2.R)
SECTOR_CAP_N <- 6L; TOPN <- 20L

select_c2_top20 <- function(c2_sd, sector_map_sd, top_n = 20L, cap_n = 6L) {
  dt <- merge(c2_sd, sector_map_sd, by = "Ticker", all.x = TRUE)
  na_idx <- which(is.na(dt$Sector))
  if (length(na_idx) > 0L) {
    miss <- dt$Ticker[na_idx]
    fb <- ticker_last_sector[miss, latest_sector, on = "Ticker"]
    dt$Sector[na_idx] <- fb
  }
  dt <- dt[!is.na(Sector)]
  setorder(dt, -alpha)
  sel <- dt[, head(.SD, cap_n), by = Sector]
  setorder(sel, -alpha)
  head(sel, top_n)
}

select_str1715_top20 <- function(s17_sd, top_n = 20L) {
  dt <- s17_sd[!is.na(score_eff)]
  setorder(dt, -score_eff)
  head(dt, top_n)
}

build_c2_in_sleeve <- function(c2_top) {
  al <- pmax(c2_top$alpha, 0.01)
  w <- al / sum(al)
  setNames(w, c2_top$Ticker)
}

get_daily_panel <- function(tickers, end_date, n_days = 252L) {
  start_date <- end_date - 365L
  rd <- RAWDATA[Ticker %in% tickers & Date >= start_date & Date <= end_date, .(Date, Ticker, Ret)]
  if (nrow(rd) == 0L) return(NULL)
  wide <- dcast(rd, Date ~ Ticker, value.var = "Ret", fill = 0)
  m <- as.matrix(wide[, !"Date"])
  m[!is.finite(m)] <- 0
  if (nrow(m) > n_days) m <- m[(nrow(m) - n_days + 1):nrow(m), , drop = FALSE]
  m
}

build_str1715_in_sleeve <- function(s17_top, ret_panel_252d) {
  tk <- s17_top$Ticker
  if (is.null(ret_panel_252d) || ncol(ret_panel_252d) == 0L) {
    return(setNames(rep(1/length(tk), length(tk)), tk))
  }
  use_tk <- intersect(tk, colnames(ret_panel_252d))
  if (length(use_tk) < 5L) return(setNames(rep(1/length(tk), length(tk)), tk))
  vols <- apply(ret_panel_252d[, use_tk, drop = FALSE], 2, sd, na.rm = TRUE)
  vols[!is.finite(vols) | vols < 1e-6] <- median(vols, na.rm = TRUE)
  iv <- 1 / vols
  w_in <- setNames(iv / sum(iv), use_tk)
  while (max(w_in) > 0.20) {
    over <- which(w_in > 0.20)
    excess <- sum(w_in[over] - 0.20)
    w_in[over] <- 0.20
    under <- setdiff(seq_along(w_in), over)
    if (length(under) == 0L) break
    room <- 0.20 - w_in[under]
    if (sum(room) <= 1e-10) break
    add <- excess * room / sum(room)
    w_in[under] <- w_in[under] + add
  }
  miss <- setdiff(tk, use_tk)
  if (length(miss) > 0L) {
    eq_w <- mean(w_in)
    w_full <- c(w_in, setNames(rep(eq_w, length(miss)), miss))
    w_full <- w_full / sum(w_full)
    return(w_full)
  }
  w_in / sum(w_in)
}

# ─── Iterate sig_dates: build RCD + STR1715_PG2_pure weights ─
s17_ym_map <- str1715_alpha[, .(s17_date = min(Date)), by = ym]
setkey(s17_ym_map, ym)

sig_ym_c2 <- sort(unique(c2_alpha$ym))
sig_ym_s17 <- sort(unique(str1715_alpha$ym))
sig_ym_pg2 <- sort(unique(pg2_sched$sig_ym))
common_ym <- sort(Reduce(intersect, list(sig_ym_c2, sig_ym_s17, sig_ym_pg2)))
sig_schedule <- unique(c2_alpha[ym %in% common_ym, .(Date, ym)])
setorder(sig_schedule, Date)

cat("[final] RCD + PG2 admit pure weights for", nrow(sig_schedule), "sig_dates\n")

new_method_records <- list()
for (i in seq_len(nrow(sig_schedule))) {
  sd_t <- sig_schedule$Date[i]; ym_t <- sig_schedule$ym[i]
  s17_sd <- s17_ym_map[ym_t, s17_date]
  pg2_row <- pg2_sched[sig_ym == ym_t]
  if (is.na(s17_sd) || nrow(pg2_row) == 0L) next

  c2_sd_dt <- c2_alpha[Date == sd_t]
  s17_sd_dt <- str1715_alpha[Date == s17_sd]
  sector_map_sd <- sector_pit[Date == sd_t, .(Ticker, Sector)]

  c2_top <- select_c2_top20(c2_sd_dt, sector_map_sd, top_n = TOPN, cap_n = SECTOR_CAP_N)
  s17_top <- select_str1715_top20(s17_sd_dt, top_n = TOPN)
  if (nrow(c2_top) < 15L || nrow(s17_top) < 15L) next

  daily_panel <- get_daily_panel(c(c2_top$Ticker, s17_top$Ticker), end_date = sd_t)
  if (is.null(daily_panel) || nrow(daily_panel) < 50L) next

  w_c2_in <- build_c2_in_sleeve(c2_top)
  w_s17_in <- build_str1715_in_sleeve(s17_top, daily_panel)

  overlay <- pg2_row$combined_overlay_V2[1]
  regime  <- pg2_row$regime[1]

  # RCD beta
  rcd_bc2 <- if (regime %in% c("CRISIS", "CAUTION")) 0.30 else if (regime == "NORMAL") 0.10 else 0.00
  rcd_bs17 <- 1 - rcd_bc2

  # Build RCD ticker weights
  rcd_w <- setNames(rep(0, length(union(names(w_c2_in), names(w_s17_in)))),
                     union(names(w_c2_in), names(w_s17_in)))
  for (tkr in names(w_c2_in))  rcd_w[tkr] <- rcd_w[tkr] + rcd_bc2 * w_c2_in[[tkr]]
  for (tkr in names(w_s17_in)) rcd_w[tkr] <- rcd_w[tkr] + rcd_bs17 * overlay * w_s17_in[[tkr]]
  cash_rcd <- 1 - rcd_bs17 * overlay - rcd_bc2
  cash_rcd <- pmax(cash_rcd, 0)
  # Cap 0.20
  excess <- pmax(rcd_w - 0.20, 0)
  if (sum(excess) > 1e-10) {
    rcd_w <- pmin(rcd_w, 0.20)
    cash_rcd <- 1 - sum(rcd_w)
    cash_rcd <- pmax(cash_rcd, 0)
  }
  rec_rcd <- data.table(
    as_of_date = sd_t,
    decision_date = pg2_row$decision_date[1],
    decision_ym = ym_t,
    Ticker = c(names(rcd_w), "CASH"),
    weight = c(as.numeric(rcd_w), cash_rcd),
    method = "RCD_dynamic",
    beta_c2 = rcd_bc2,
    beta_str1715 = rcd_bs17,
    overlay = overlay,
    regime = regime
  )
  new_method_records[[length(new_method_records) + 1L]] <- rec_rcd

  # STR1715_PG2_pure: β_c2=0, β_s17=1, overlay applied (admit lineage)
  pg2_w <- setNames(rep(0, length(w_s17_in)), names(w_s17_in))
  for (tkr in names(w_s17_in)) pg2_w[tkr] <- 1 * overlay * w_s17_in[[tkr]]
  cash_pg2 <- 1 - overlay
  cash_pg2 <- pmax(cash_pg2, 0)
  excess_pg <- pmax(pg2_w - 0.20, 0)
  if (sum(excess_pg) > 1e-10) {
    pg2_w <- pmin(pg2_w, 0.20)
    cash_pg2 <- 1 - sum(pg2_w)
    cash_pg2 <- pmax(cash_pg2, 0)
  }
  rec_pg2 <- data.table(
    as_of_date = sd_t,
    decision_date = pg2_row$decision_date[1],
    decision_ym = ym_t,
    Ticker = c(names(pg2_w), "CASH"),
    weight = c(as.numeric(pg2_w), cash_pg2),
    method = "STR1715_PG2_pure",
    beta_c2 = 0,
    beta_str1715 = 1,
    overlay = overlay,
    regime = regime
  )
  new_method_records[[length(new_method_records) + 1L]] <- rec_pg2
}

new_methods_dt <- rbindlist(new_method_records)
cat("[final] new methods (RCD + STR1715_PG2_pure):", nrow(new_methods_dt), "rows\n")

# Combine all methods
all_weights_dt <- rbind(weights_dt, new_methods_dt)
cat("[final] Total weights rows:", nrow(all_weights_dt), "\n")
cat("[final] Methods:", unique(all_weights_dt$method), "\n")
cat("[final] Unique as_of_dates:", uniqueN(all_weights_dt$as_of_date), "\n")

# Save final weights.csv (master)
setorder(all_weights_dt, method, as_of_date, -weight, Ticker)
fwrite(all_weights_dt, file.path(STAGE, "weights.csv"))
cat("[final] Saved: weights.csv\n")

# Schedule density check
alpha_n_sig <- 268  # from alpha_package.diagnostics.n_months (267 forward + initial)
unique_dates <- uniqueN(all_weights_dt$as_of_date)
density_ratio <- unique_dates / alpha_n_sig
cat(sprintf("[final] Schedule density: %d / %d = %.4f (mandate >= 0.95)\n",
            unique_dates, alpha_n_sig, density_ratio))
if (density_ratio < 0.95) {
  cat("[final] *** WARNING: Schedule density < 0.95 (Charter §9 mandate) ***\n")
} else {
  cat("[final] OK: Schedule density mandate satisfied\n")
}

# Methods × unique_dates count
cat("\n[final] Per method sig_date count:\n")
print(all_weights_dt[, .(unique_sig_dates = uniqueN(as_of_date)), by = method])
