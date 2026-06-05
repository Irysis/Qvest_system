#==============================================================================
# Step 2 — Sector-Neutralized 8-Family Z Panel v3.6
#
# v3.5 → v3.6 fix:
#   - 각 family F_{fam} per-Date sector dummy regression residual
#   - Asness-Frazzini 2013 "Devil in HML" sector-controlled portfolio standard
#   - F_neut(i, t, fam) = F(i, t, fam) - mean(F(. , t, fam) | sector(i))
#   - per-Date cross-section neutralization (sector via rawdata$Sector)
#   - Re-standardize Z (cross-section) per Date per family after residualization
#
# Mandate: Sector-neut IC retention ≥ 50% per family + composite (RF-A4 fix target)
#
# Methodology refs:
#   - Asness-Frazzini 2013 "Devil in HML's Details" J. Portfolio Mgmt
#   - Cochrane 2011 "Discount Rates" J. Finance — orthogonal alpha extraction
#
# Output:
#   - outputs/v3_6/k200_factor_panel_sector_neut_v36.parquet
#   - outputs/v3_6/sector_neutralize_diag_v36.json
#==============================================================================

suppressPackageStartupMessages({
  library(arrow)
  library(data.table)
  library(jsonlite)
})

BASE <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
OUT_DIR <- file.path(BASE, "qepm/mailbox/worktask/WT-D20260528_003/outputs/v3_6")
STAGE_DIR <- file.path(BASE, "stage_artifacts/WT_D20260528_003_v3_6")
RAWDATA <- file.path(BASE, ".cache/rawdata.parquet")
PANEL_V35 <- file.path(BASE, "qepm/mailbox/worktask/WT-D20260528_003/outputs/v3_5/k200_factor_panel_v35.parquet")

# v3.6: retain v3.5 panel (8 family Z_aligned) — only add sector residualization
cat("[Sector Neut Panel v3.6] === START ===\n")
t0 <- Sys.time()

# ---- 1. Load v3.5 panel (already 8-family Z_aligned, cross-section re-standardized) ----
cat("[1] Loading v3.5 panel ...\n")
panel <- as.data.table(read_parquet(PANEL_V35))
panel[, Date := as.Date(Date)]
fam_cols <- c("F_value", "F_quality", "F_momentum", "F_growth",
               "F_consensus", "F_low_vol", "F_size", "F_dividend")
cat("  panel rows:", nrow(panel), " | n_dates:", length(unique(panel$Date)), "\n")

# ---- 2. Load rawdata for sector mapping ----
cat("[2] Loading rawdata sector mapping ...\n")
rd <- as.data.table(read_parquet(RAWDATA, col_select = c("Date","Ticker","Sector")))
rd[, Date := as.Date(Date)]
# Get most recent sector per ticker as of each sig_date (PIT-safe: use last available)
# For simplicity: use the sector field at each Date directly (PIT-OK since Sector is contemporaneous categorical)
rd_unique <- rd[!is.na(Sector)]
setkey(rd_unique, Date, Ticker)

# ---- 3. Per-sig_date sector merge + residualization ----
cat("[3] Per-sig_date sector residualize ...\n")
sig_dates <- sort(unique(panel$Date))

panel_neut_list <- list()
sector_diag_list <- list()

for (i in seq_along(sig_dates)) {
  sig_d <- sig_dates[i]
  sub <- panel[Date == sig_d]

  # Sector mapping at sig_d (or most recent before sig_d)
  # Use rd_unique at sig_d for the ticker; fall back to nearest past Date per ticker
  sec_at_d <- rd_unique[Date == sig_d, .(Ticker, Sector)]
  miss_tk <- setdiff(sub$Ticker, sec_at_d$Ticker)
  if (length(miss_tk) > 0) {
    # Find most recent Sector before sig_d per missing ticker
    miss_dt <- rd_unique[Ticker %in% miss_tk & Date <= sig_d,
                           .SD[Date == max(Date)], by = Ticker]
    miss_dt <- miss_dt[, .(Ticker, Sector)]
    sec_at_d <- rbind(sec_at_d, miss_dt)
  }
  sub <- merge(sub, sec_at_d, by = "Ticker", all.x = TRUE)
  sub[is.na(Sector), Sector := "UNKNOWN"]  # safety bucket

  # Per family: residualize
  for (fc in fam_cols) {
    x <- sub[[fc]]
    if (sum(!is.na(x)) < 5L) {
      sub[, (paste0(fc, "_neut")) := x]
      next
    }
    # Sector mean (per sector) — robust to small sectors
    sec_means <- sub[!is.na(get(fc)), .(mu = mean(get(fc), na.rm = TRUE)), by = Sector]
    sub <- merge(sub, sec_means, by = "Sector", all.x = TRUE, sort = FALSE)
    sub[, (paste0(fc, "_neut")) := get(fc) - mu]
    sub[, mu := NULL]
  }

  # Re-standardize per family cross-section (after residualization)
  for (fc in fam_cols) {
    nc <- paste0(fc, "_neut")
    sub[!is.na(get(nc)), (nc) := {
      v <- get(nc)
      m <- mean(v, na.rm = TRUE)
      s <- sd(v, na.rm = TRUE)
      if (!is.na(s) && s > 1e-12) (v - m) / s else v - m
    }]
  }

  # Sector concentration diagnostic
  n_sectors <- length(unique(sub$Sector[sub$Sector != "UNKNOWN"]))
  n_unknown <- sum(sub$Sector == "UNKNOWN")
  sector_diag_list[[i]] <- list(
    sig_date = as.character(sig_d),
    n_tickers = nrow(sub),
    n_sectors = n_sectors,
    n_unknown_sector = n_unknown,
    pct_unknown = round(n_unknown / nrow(sub), 4)
  )

  panel_neut_list[[i]] <- sub
}

panel_neut <- rbindlist(panel_neut_list, fill = TRUE, use.names = TRUE)
neut_cols <- paste0(fam_cols, "_neut")
keep_cols <- c("Date", "Ticker", "Sector", fam_cols, neut_cols)
panel_neut <- panel_neut[, ..keep_cols]
setorder(panel_neut, Date, Ticker)

cat("  panel_neut rows:", nrow(panel_neut), " | NA in F_value_neut:",
    sum(is.na(panel_neut$F_value_neut)), "\n")

# ---- 4. Save outputs ----
cat("[4] Saving sector-neutralized panel ...\n")
write_parquet(panel_neut, file.path(OUT_DIR, "k200_factor_panel_sector_neut_v36.parquet"))
write_parquet(panel_neut, file.path(STAGE_DIR, "k200_factor_panel_sector_neut_v36.parquet"))

# Diagnostic
sector_diag <- rbindlist(sector_diag_list, use.names = TRUE, fill = TRUE)
diag <- list(
  method = "Sector dummy regression residual per-Date per-family (Asness-Frazzini 2013 standard)",
  formula = "F_neut(i, t, fam) = F(i, t, fam) - mean(F(., t, fam) | sector(i))",
  post_residual = "Re-standardize cross-section z per Date per family",
  sector_source = "rawdata$Sector (27 unique KR sectors, PIT contemporaneous)",
  n_sig_dates = length(sig_dates),
  n_unique_sectors_avg = round(mean(sector_diag$n_sectors), 1),
  pct_unknown_avg = round(mean(sector_diag$pct_unknown), 4),
  built_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S"),
  elapsed_min = round(as.numeric(difftime(Sys.time(), t0, units = "mins")), 2)
)
writeLines(toJSON(diag, pretty = TRUE, auto_unbox = TRUE, na = "null"),
            file.path(OUT_DIR, "sector_neutralize_diag_v36.json"))
write_parquet(sector_diag, file.path(OUT_DIR, "sector_neutralize_per_date_v36.parquet"))

cat("[Sector Neut Panel v3.6] === DONE === elapsed:",
    round(as.numeric(difftime(Sys.time(), t0, units = "mins")), 2), "min\n")
cat("  Avg n_sectors per Date:", round(mean(sector_diag$n_sectors), 1), "\n")
cat("  Avg pct unknown sector:", round(mean(sector_diag$pct_unknown), 4), "\n")
