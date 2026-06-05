#==============================================================================
# WT-D20260528_003 v3.7 — Step 2: Sector Neutralization
#
# RF-A4 회피: v3.6 archive에서 sector tilt 의존이 알파의 본질이었음.
# 사전 회피 의무 — Asness-Frazzini 2013 sector-controlled portfolio standard.
#
# Per-Date per-factor: F_neut(i, t, k) = F(i, t, k) - mean(F(.,t,k) | sector(i))
# Re-standardize Z cross-section after residualization.
#
# Retention gate: sector-neutralized ICIR ≥ 50% of raw ICIR per factor.
#
# Output:
#   - outputs/v3_7/top12_factor_panel_neut.parquet (Date × Ticker × 12 Z_neut)
#   - outputs/v3_7/top12_sector_neut_retention.json (per-factor retention ratio)
#==============================================================================

suppressPackageStartupMessages({
  library(arrow)
  library(data.table)
  library(jsonlite)
})

BASE <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
setwd(BASE)
OUT_DIR <- file.path(BASE, "qepm/mailbox/worktask/WT-D20260528_003/outputs/v3_7")
RAWDATA <- file.path(BASE, ".cache/rawdata.parquet")

TOP12 <- c("D43_Skewness", "D44_Kurtosis", "L44_Vol_Ret_Asymmetry",
           "CR08_Volume_Price_Divergence", "Q07_Earnings_Stability",
           "M22_Max_Return", "L42_Vol_Skewness", "CR01_Sector_Comovement",
           "Q11_Net_Margin", "D22_Tracking_Error", "Q32_Interest_Coverage",
           "L33_AbsRet_Vol_Corr")

cat("[Step 2: Sector neutralize] === START ===\n")
t0 <- Sys.time()

# ---- 1. Load v3.7 panel (Step 1 output) ----
cat("[1] Loading top12 panel ...\n")
panel <- as.data.table(read_parquet(file.path(OUT_DIR, "top12_factor_panel.parquet")))
panel[, Date := as.Date(Date)]
cat("  panel rows:", nrow(panel), " | n_dates:", uniqueN(panel$Date), "\n")

# ---- 2. Load rawdata sector mapping ----
cat("\n[2] Loading rawdata Sector ...\n")
rd <- as.data.table(read_parquet(RAWDATA, col_select = c("Date","Ticker","Sector")))
rd[, Date := as.Date(Date)]
rd_unique <- rd[!is.na(Sector)]
setkey(rd_unique, Date, Ticker)

# ---- 3. Per-sig_date sector residualize ----
cat("\n[3] Per-sig_date sector residualize ...\n")
sig_dates <- sort(unique(panel$Date))
panel_neut_list <- vector("list", length(sig_dates))
sector_diag_list <- vector("list", length(sig_dates))

for (i in seq_along(sig_dates)) {
  sig_d <- sig_dates[i]
  sub <- panel[Date == sig_d]

  # Sector mapping at sig_d
  sec_at_d <- rd_unique[Date == sig_d, .(Ticker, Sector)]
  miss_tk <- setdiff(sub$Ticker, sec_at_d$Ticker)
  if (length(miss_tk) > 0) {
    # Nearest past Sector per missing ticker
    miss_dt <- rd_unique[Ticker %in% miss_tk & Date <= sig_d,
                          .SD[Date == max(Date)], by = Ticker]
    miss_dt <- miss_dt[, .(Ticker, Sector)]
    sec_at_d <- rbind(sec_at_d, miss_dt)
  }
  sub <- merge(sub, sec_at_d, by = "Ticker", all.x = TRUE)
  sub[is.na(Sector), Sector := "UNKNOWN"]

  # Per factor: residualize then re-standardize
  for (fc in TOP12) {
    if (!fc %in% names(sub)) next
    # Sector mean
    sub_valid <- sub[!is.na(get(fc))]
    if (nrow(sub_valid) < 10) {
      sub[, paste0(fc, "_neut") := NA_real_]
      next
    }
    sec_means <- sub_valid[, .(mu = mean(get(fc), na.rm = TRUE)), by = Sector]
    sub <- merge(sub, sec_means, by = "Sector", all.x = TRUE, sort = FALSE)
    sub[, residual := get(fc) - mu]
    # Re-standardize residual cross-section
    sd_r <- sd(sub$residual, na.rm = TRUE)
    if (!is.na(sd_r) && sd_r > 1e-9) {
      sub[, paste0(fc, "_neut") := residual / sd_r]
    } else {
      sub[, paste0(fc, "_neut") := residual]
    }
    sub[, c("mu", "residual") := NULL]
  }

  # Diagnostic
  n_sectors <- length(unique(sub$Sector[sub$Sector != "UNKNOWN"]))
  n_unknown <- sum(sub$Sector == "UNKNOWN")
  sector_diag_list[[i]] <- list(
    Date = as.character(sig_d),
    n_tickers = nrow(sub),
    n_sectors = n_sectors,
    n_unknown = n_unknown,
    unknown_pct = round(100 * n_unknown / nrow(sub), 2)
  )

  panel_neut_list[[i]] <- sub
  if (i %% 30 == 0) cat("  ", i, "/", length(sig_dates), "(", as.character(sig_d), ") sectors=", n_sectors, "\n")
}

panel_neut <- rbindlist(panel_neut_list, use.names = TRUE, fill = TRUE)
cat("\n  Panel neut rows:", nrow(panel_neut), "\n")

# ---- 4. Merge fwd_ret + IC retention ----
cat("\n[4] IC retention per factor (raw vs neut) ...\n")
neut_cols <- paste0(TOP12, "_neut")
retention_dt <- data.table()
for (fc in TOP12) {
  fc_n <- paste0(fc, "_neut")
  if (!fc_n %in% names(panel_neut)) next

  # Per-Date rank IC (raw + neut)
  raw_ic <- panel_neut[!is.na(fwd_ret) & !is.na(get(fc)),
                       .(rank_ic = if (.N >= 10) suppressWarnings(cor(get(fc), fwd_ret, method="spearman")) else NA_real_),
                       by = Date][!is.na(rank_ic)]
  neut_ic <- panel_neut[!is.na(fwd_ret) & !is.na(get(fc_n)),
                        .(rank_ic = if (.N >= 10) suppressWarnings(cor(get(fc_n), fwd_ret, method="spearman")) else NA_real_),
                        by = Date][!is.na(rank_ic)]

  m_raw <- mean(raw_ic$rank_ic, na.rm = TRUE)
  s_raw <- sd(raw_ic$rank_ic, na.rm = TRUE)
  icir_raw <- if (!is.na(s_raw) && s_raw > 0) m_raw / s_raw else NA_real_

  m_neut <- mean(neut_ic$rank_ic, na.rm = TRUE)
  s_neut <- sd(neut_ic$rank_ic, na.rm = TRUE)
  icir_neut <- if (!is.na(s_neut) && s_neut > 0) m_neut / s_neut else NA_real_

  retention_dt <- rbind(retention_dt, data.table(
    Factor_Name = fc,
    rank_ic_raw = m_raw,
    rank_ic_neut = m_neut,
    icir_raw = icir_raw,
    icir_neut = icir_neut,
    ic_retention = if (!is.na(icir_raw) && abs(icir_raw) > 1e-9) icir_neut / icir_raw else NA_real_,
    rank_ic_t_neut = if (!is.na(s_neut) && s_neut > 0) m_neut / (s_neut / sqrt(nrow(neut_ic))) else NA_real_,
    n_dates = nrow(neut_ic)
  ))
}
print(retention_dt)
cat("\n")

# 5y recent ICIR for neut
cat("[5] Recent 5y neut ICIR ...\n")
recent_cutoff <- as.Date("2018-12-31")
recent_neut_dt <- data.table()
for (fc in TOP12) {
  fc_n <- paste0(fc, "_neut")
  if (!fc_n %in% names(panel_neut)) next
  recent <- panel_neut[Date >= recent_cutoff & !is.na(fwd_ret) & !is.na(get(fc_n))]
  ic_recent <- recent[, .(rank_ic = if (.N >= 10) suppressWarnings(cor(get(fc_n), fwd_ret, method="spearman")) else NA_real_),
                       by = Date][!is.na(rank_ic)]
  if (nrow(ic_recent) < 12) next
  m <- mean(ic_recent$rank_ic, na.rm = TRUE)
  s <- sd(ic_recent$rank_ic, na.rm = TRUE)
  recent_neut_dt <- rbind(recent_neut_dt, data.table(
    Factor_Name = fc,
    n_dates_5y = nrow(ic_recent),
    rank_ic_mean_5y_neut = m,
    icir_5y_neut = if (!is.na(s) && s > 0) m / s else NA_real_,
    rank_ic_t_5y_neut = if (!is.na(s) && s > 0) m / (s / sqrt(nrow(ic_recent))) else NA_real_
  ))
}
print(recent_neut_dt)
cat("\n")

# ---- 6. Save ----
cat("[6] Save ...\n")
keep_cols <- c("Date", "Ticker", "Sector", "fwd_ret", neut_cols)
panel_neut_out <- panel_neut[, keep_cols, with = FALSE]
write_parquet(panel_neut_out, file.path(OUT_DIR, "top12_factor_panel_neut.parquet"))
cat("  saved: top12_factor_panel_neut.parquet (", nrow(panel_neut_out), "rows)\n")

diag <- list(
  task_id = "WT-D20260528_003",
  step = "02_sector_neutralize",
  methodology = "Asness-Frazzini 2013 sector-controlled portfolio (dummy regression residual)",
  retention_per_factor = lapply(seq_len(nrow(retention_dt)), function(i) as.list(retention_dt[i])),
  recent_5y_neut = lapply(seq_len(nrow(recent_neut_dt)), function(i) as.list(recent_neut_dt[i])),
  sector_diag_per_date_sample = sector_diag_list[c(1, length(sig_dates)/2, length(sig_dates))],
  gate_50pct_retention = list(
    target = 0.5,
    n_pass = sum(retention_dt$ic_retention >= 0.5, na.rm = TRUE),
    n_fail = sum(retention_dt$ic_retention < 0.5, na.rm = TRUE)
  )
)
write_json(diag, file.path(OUT_DIR, "top12_sector_neut_retention.json"),
           pretty = TRUE, auto_unbox = TRUE, na = "null")
cat("  saved: top12_sector_neut_retention.json\n")

elapsed <- as.numeric(Sys.time() - t0, units = "secs")
cat("\n[Step 2] === DONE === elapsed:", round(elapsed, 1), "sec\n")
