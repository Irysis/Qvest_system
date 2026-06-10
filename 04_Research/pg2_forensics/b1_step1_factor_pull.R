# =============================================================================
# b1_step1_factor_pull.R — PG2 forensics B1: 7-factor z-score panel pull
#
# PURPOSE (diagnostic only — no grade declarations):
#   Rebuild individual 7-factor Z_Score_Aligned panel for the 268 score dates of
#   STR_1715 PG2 alpha panel, via load_month_factors() (PIT C15 — no direct
#   parquet load; C13 — Z_Score_Aligned only, no NEGATE/FLIP; C14 — connector's
#   direction inference uses Usable_Date <= sig_date internally).
#
# ALIGNMENT (established empirically, b0b/b0e):
#   - alpha panel Date t (month-start label) = factor data through month-end(t)
#     (factor_db_YYYYMM Date col = month-end; builder PIT Date <= sig_date)
#   - Ret_1m @ Date t = calendar month(t)+1 total return (forward, PIT-safe)
#   - production period_returns realized_ym m covers calendar m-1
#     (top-20 EW recon vs ret_orig: pearson 0.81 @ offset +2)
#
# OUTPUT (intermediate, 04_Research/pg2_forensics/intermediate/):
#   factor_panel_7f.parquet  — Date, Ticker, 7 factor z cols, Ret_1m,
#                              score_eff, score_core_z, score_defense_z, regime_state
#   theta_by_date.csv        — parsed theta_core / theta_defense weights per date
# =============================================================================
suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite)
})

PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
Sys.setenv(QM_ROOT = PROJECT_ROOT)
PROD_DIR <- file.path(PROJECT_ROOT, "05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2")
OUT_DIR  <- file.path(PROJECT_ROOT, "04_Research/pg2_forensics")
INT_DIR  <- file.path(OUT_DIR, "intermediate")
dir.create(INT_DIR, showWarnings = FALSE, recursive = TRUE)

source(file.path(PROJECT_ROOT, "02_Infrastructure/config.R"))
source(file.path(PROJECT_ROOT, "02_Infrastructure/factor_db/factor_db_connector.R"))

FACTORS_7 <- c("C01_SUE","C02_EPS_Chg_1m","C04_ESBR","C06_TP_Gap",
               "Q07_Earnings_Stability","M08_Residual_Mom","Q25_Ohlson_O")

# ---- 1. Load production alpha panel (read-only) ----
sc <- as.data.table(read_parquet(file.path(PROD_DIR, "02_holdings_universe/alpha_scores_str1715_268m.parquet")))
sc[, Date := as.Date(Date)]
dates <- sort(unique(sc$Date))
cat(sprintf("[step1] alpha panel: %d rows, %d dates (%s ~ %s)\n",
            nrow(sc), length(dates), min(dates), max(dates)))

# ---- 2. Parse theta weights per date (constant within date) ----
theta_dt <- sc[, .SD[1L], by = Date][, .(Date, theta_core, theta_defense)]
parse_theta <- function(js) as.data.table(as.list(fromJSON(js)))
tc <- rbindlist(lapply(theta_dt$theta_core, parse_theta), fill = TRUE)
td <- rbindlist(lapply(theta_dt$theta_defense, parse_theta), fill = TRUE)
setnames(tc, paste0("w_", names(tc)))
setnames(td, paste0("w_", names(td)))
theta_out <- cbind(theta_dt[, .(Date)], tc, td)
fwrite(theta_out, file.path(INT_DIR, "theta_by_date.csv"))
cat(sprintf("[step1] theta parsed: %d dates | core w cols: %s\n",
            nrow(theta_out), paste(names(tc), collapse=", ")))

# ---- 3. Per-month factor pull via connector (C15) ----
# sig_date for load_month_factors = month-end of month(Date t)
month_end <- function(d) seq(as.Date(format(d, "%Y-%m-01")), by = "1 month", length.out = 2)[2] - 1L

pull_one <- function(t_date) {
  sig_d <- month_end(t_date)
  fdt <- tryCatch(load_month_factors(sig_d, coverage_min = 0.05),
                  error = function(e) { cat(sprintf("  [WARN] %s: %s\n", sig_d, conditionMessage(e))); NULL })
  if (is.null(fdt)) return(NULL)
  fdt <- fdt[Factor_Name %in% FACTORS_7]
  if (nrow(fdt) == 0) return(NULL)
  w <- dcast(fdt, Ticker ~ Factor_Name, value.var = "Z_Score_Aligned")
  w[, Date := t_date]
  w
}

cat("[step1] pulling 7-factor z for", length(dates), "months via load_month_factors()...\n")
t0 <- Sys.time()
panels <- vector("list", length(dates))
sink_null <- file(file.path(INT_DIR, "connector_log.txt"), open = "wt")
sink(sink_null, type = "output")  # connector is chatty — divert to log
for (i in seq_along(dates)) {
  panels[[i]] <- pull_one(dates[i])
}
sink(type = "output"); close(sink_null)
fz <- rbindlist(panels, fill = TRUE)
cat(sprintf("[step1] pulled: %d rows | %.1f min\n", nrow(fz),
            as.numeric(difftime(Sys.time(), t0, units = "mins"))))

# ---- 4. Join with alpha panel (restrict to production universe rows) ----
merged <- merge(
  sc[, .(Date, Ticker, score_eff, score_core_z, score_defense_z, Ret_1m, regime_state)],
  fz, by = c("Date", "Ticker"), all.x = TRUE
)
have7 <- intersect(FACTORS_7, names(merged))
cat(sprintf("[step1] merged: %d rows | factor cols present: %d/7\n", nrow(merged), length(have7)))
for (f in have7) {
  cat(sprintf("  %-24s non-NA share: %.3f\n", f, merged[, mean(!is.na(get(f)))]))
}

# ---- 5. Construction fidelity check (diagnostic):
#  reconstruct core/defense sleeve scores from factor z + theta and correlate
#  with the production sleeve scores (validates factor identity + direction).
theta_long_core <- melt(theta_out, id.vars = "Date",
                        measure.vars = grep("^w_(C01|C02|C04|C06)", names(theta_out), value = TRUE),
                        variable.name = "wcol", value.name = "w")
theta_long_core[, Factor_Name := sub("^w_", "", wcol)]
fid <- merged[, c("Date","Ticker","score_core_z","score_defense_z", have7), with = FALSE]
fl <- melt(fid, id.vars = c("Date","Ticker","score_core_z","score_defense_z"),
           measure.vars = have7, variable.name = "Factor_Name", value.name = "z")
fl <- merge(fl, theta_long_core[, .(Date, Factor_Name, w)],
            by = c("Date","Factor_Name"), all.x = TRUE)
core_f <- c("C01_SUE","C02_EPS_Chg_1m","C04_ESBR","C06_TP_Gap")
def_f  <- c("Q07_Earnings_Stability","M08_Residual_Mom","Q25_Ohlson_O")
recon <- fl[, .(
  core_recon = { idx <- Factor_Name %in% core_f & !is.na(z) & !is.na(w)
                 if (any(idx)) sum(z[idx]*w[idx])/sum(w[idx]) else NA_real_ },
  def_recon  = { idx <- Factor_Name %in% def_f & !is.na(z)
                 if (any(idx)) mean(z[idx]) else NA_real_ },
  score_core_z = score_core_z[1L], score_defense_z = score_defense_z[1L]
), by = .(Date, Ticker)]
fid_stats <- recon[, .(
  cor_core = tryCatch(cor(core_recon, score_core_z, use = "complete.obs", method = "spearman"), error = function(e) NA_real_),
  cor_def  = tryCatch(cor(def_recon,  score_defense_z, use = "complete.obs", method = "spearman"), error = function(e) NA_real_),
  n = .N
), by = Date]
cat(sprintf("[step1] construction fidelity (spearman, median across months): core=%.3f defense=%.3f\n",
            median(fid_stats$cor_core, na.rm = TRUE), median(fid_stats$cor_def, na.rm = TRUE)))
fwrite(fid_stats, file.path(INT_DIR, "construction_fidelity_by_month.csv"))

write_parquet(merged, file.path(INT_DIR, "factor_panel_7f.parquet"))
cat("[step1] saved:", file.path(INT_DIR, "factor_panel_7f.parquet"), "\n")
cat("[step1] DONE\n")
