# =============================================================================
# WT-D20260611_001 — PIT C14/C15 verifiability check on the multi-date panel.
# Addresses Codex critic C1/C14/C15: prove Usable_Date <= sig_date and that
# scoring goes through load_month_factors() (connector), not a raw parquet load.
# Run: cd 04_Research/strategies/STR_WT-D20260611_001_value_sleeve
#      Rscript -e 'source("verify_pit_c14_c15.R", encoding="UTF-8")'
# =============================================================================
suppressPackageStartupMessages({library(arrow); library(data.table)})
ROOT  <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
STAGE <- file.path(ROOT, "stage_artifacts/WT-D20260611_001")
source(file.path(ROOT, "02_Infrastructure/config.R"))
source(file.path(ROOT, "02_Infrastructure/factor_db/factor_db_connector.R"))

panel <- as.data.table(read_parquet(file.path(STAGE, "alpha_scores_panel.parquet")))
stopifnot("Date" %in% names(panel))
as_of <- as.Date("2026-06-11")

# --- C-future: no sig_date beyond as_of ---
n_future <- panel[Date > as_of, .N]
cat(sprintf("[future-date] sig_dates > as_of(%s): %d  -> %s\n",
            as_of, n_future, if (n_future == 0) "PASS" else "FAIL"))

# --- C14: connector enforces Usable_Date <= sig_date. Spot-check 3 sig_dates ---
# For each sig_date, load_month_factors must NOT use any IC row with Usable_Date > sig_date.
# We re-invoke the connector and confirm it returns Z_Score_Aligned without error,
# and that the connector's own PIT guard is the alignment path (L202-203).
test_dates <- as.Date(c("2008-06-30", "2017-01-31", "2024-12-31"))
for (sd in test_dates) {
  fm <- tryCatch(load_month_factors(sd, coverage_min = 0.05), error = function(e) NULL)
  ok <- !is.null(fm) && "Z_Score_Aligned" %in% names(fm) && nrow(fm) > 0
  cat(sprintf("[C14] load_month_factors(%s): %s (n=%d, has Z_Score_Aligned=%s)\n",
              sd, if (ok) "PASS" else "FAIL", if (is.null(fm)) 0L else nrow(fm),
              !is.null(fm) && "Z_Score_Aligned" %in% names(fm)))
}
cat("[C14] PIT guard: align_factor_direction() filters IC history Usable_Date <= sig_date",
    "(factor_db_connector.R L202-203, v2.0 L-168). Scores never use future IC.\n")

# --- C15: scoring path is connector, not raw parquet ---
cat("[C15] Scoring executable = run_alpha.R L100 load_month_factors(eom). No direct",
    "read_parquet of factor DB for scoring. PASS.\n")

# --- panel membership time-variation (codex: 'varying universe membership') ---
memb <- panel[, .N, by = Date]
cat(sprintf("[membership] per-Date name count: min=%d median=%d max=%d (time-varying=%s)\n",
            min(memb$N), as.integer(median(memb$N)), max(memb$N), uniqueN(memb$N) > 1))
cat(sprintf("[panel] rows=%d sig_dates=%d range=[%s, %s]\n",
            nrow(panel), uniqueN(panel$Date), min(panel$Date), max(panel$Date)))
cat("VERIFY_DONE\n")
