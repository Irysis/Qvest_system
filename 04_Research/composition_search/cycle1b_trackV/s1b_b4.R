# =============================================================================
# s1b_b4.R — resume interrupted s1_build_inputs.R: B4 C19_Composite_Earnings scores
#   (s1 was cut 2026-06-11 ~16:04 during step 6; b3/b4 score parquets never written)
#   Logic = s1_build_inputs.R step 7 VERBATIM (driver_lo_screen legacy-loop):
#   K200uKQ150 + AvgTV20>=2e8 universe (adv_panel), monthly load_month_factors(d),
#   C19_Composite_Earnings Z_Score_Aligned. PIT C13/C14/C15 via connector.
# =============================================================================
suppressWarnings(suppressMessages({
  library(data.table); library(arrow)
}))
PROJ <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
Sys.setenv(CLAUDE_PROJECT_DIR = PROJ)
INFRA <- file.path(PROJ, "02_Infrastructure")
source(file.path(INFRA, "config.R"))
source(file.path(INFRA, "factor_db", "factor_db_connector.R"))   # load_month_factors (C15)
OUT <- file.path(PROJ, "04_Research/composition_search/cycle1b_trackV/inputs")
t0 <- Sys.time()

adv <- as.data.table(read_parquet(file.path(OUT, "adv_panel.parquet")))
adv[, Date := as.Date(Date)]
.fdb_min <- as.Date("2002-08-01")
mem <- adv[Date >= .fdb_min & (K200 == TRUE | KQ150 == TRUE) & !is.na(adv) & adv >= 2e8, .(Date, Ticker)]
setkey(mem, Date, Ticker)
b4_dates <- sort(unique(adv[Date >= .fdb_min, Date]))
rm(adv); gc(FALSE)

fac_list <- vector("list", length(b4_dates))
cat(sprintf("[s1b_b4] C19 monthly loop: %d months...\n", length(b4_dates)))
for (i in seq_along(b4_dates)) {
  d <- b4_dates[i]
  uni_tk <- mem[.(d), Ticker, nomatch = 0L]; if (!length(uni_tk)) next
  fdt <- tryCatch(load_month_factors(d, coverage_min = 0.05), error = function(e) NULL)
  if (is.null(fdt) || nrow(fdt) == 0) { if (!is.null(fdt)) rm(fdt); next }
  ff <- fdt[Factor_Name == "C19_Composite_Earnings" & Ticker %in% uni_tk & is.finite(Z_Score_Aligned),
            .(Ticker, Score = Z_Score_Aligned)]
  rm(fdt)
  if (nrow(ff) >= 10L) { ff[, Date := d]; fac_list[[i]] <- ff[, .(Date, Ticker, Score)] }
  if (i %% 24L == 0L) {
    gc(FALSE)
    cat(sprintf("[s1b_b4] %d/%d months (%.0fs)\n", i, length(b4_dates),
                as.numeric(difftime(Sys.time(), t0, units = "secs"))))
  }
}
b4 <- rbindlist(Filter(Negate(is.null), fac_list), use.names = TRUE)
stopifnot(nrow(b4) > 0)
write_parquet(b4, file.path(OUT, "b4_scores.parquet"))
cat(sprintf("[s1b_b4] b4_scores saved: %d rows, %d months | %.1f min\n",
            nrow(b4), uniqueN(b4$Date), as.numeric(difftime(Sys.time(), t0, units = "mins"))))
cat("[s1b_b4] DONE\n")
