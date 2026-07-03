## ============================================================================
## build_panel_regdir.R — defense-factor panel with REGISTRY FIXED direction.
## Rationale (PARITY_DIAGNOSIS §A): IC-sign alignment (expanding-IC cache) causes
## early-month direction SIGN FLIPS -> def_z vintage drift (Q25 -0.44 cor at 2008).
## Registry-fixed direction (Q25=lower_better, rest higher_better) is vintage-STABLE.
## Everything else identical to build_panel.R (same factor_db vintage, M08 prior-month
## fallback, pin-to-alpha-tickers scope, Coverage==TRUE keep-NA canonical).
## PIT: C13 (registry direction, NO IC-sign) / C14 / C15 (load via factor_db files
## with Usable_Date implicit in file YYYYMM). Segfault guard: setDTthreads(1).
## ============================================================================
suppressPackageStartupMessages({library(data.table); library(arrow); library(jsonlite)})
options(scipen=999); Sys.setenv(TZ="Asia/Seoul"); setDTthreads(1L)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(ROOT)
`%||%` <- function(a,b) if(is.null(a)||length(a)==0) b else a
source(file.path(ROOT,"02_Infrastructure/config.R"))
source(file.path(ROOT,"02_Infrastructure/factor_db/factor_db_connector.R"))
OUT <- file.path(ROOT,"stage_artifacts/pg2_defense_optimize")

CAND_DEF <- c("Q07_Earnings_Stability","M08_Residual_Mom","Q25_Ohlson_O",
              "RE07_Crisis_Beta","D45_Downside_Dev","D48_VaR_5pct",
              "D28_Unlevered_Beta","D56_Up_Vol","Q01_GPA")

ap <- as.data.table(read_parquet(file.path(ROOT,"stage_artifacts/WT_D20260425_010/alpha_scores.parquet")))
ap[, Date := as.Date(Date)]
sig_dates <- sort(unique(ap$Date))
REG <- .load_registry()

## registry fixed direction sign map (vintage-stable) — NO IC-sign
reg_sign <- sapply(CAND_DEF, function(f){
  d <- (REG[[f]]$direction %||% "higher_better")
  if (identical(d,"lower_better")) -1L else 1L
})
cat("[regdir] fixed signs:\n"); print(reg_sign)

prev_ym <- function(SD) format(seq(SD, by="-1 month", length.out=2)[2], "%Y%m")

panel_rows <- vector("list", length(sig_dates))
for (i in seq_along(sig_dates)) {
  SD <- sig_dates[i]; ym <- format(SD, "%Y%m")
  fp <- file.path(FACTOR_DB_DIR, sprintf("factor_db_%s.parquet", ym))
  if (!file.exists(fp)) next
  f <- as.data.table(read_parquet(fp, col_select=c("Ticker","Factor_Name","Z_Score","Coverage")))
  f <- f[Factor_Name %in% CAND_DEF & Coverage==TRUE, .(Ticker,Factor_Name,Z_Score)]
  miss <- setdiff(CAND_DEF, unique(f$Factor_Name))
  if (length(miss)) {
    fpp <- file.path(FACTOR_DB_DIR, sprintf("factor_db_%s.parquet", prev_ym(SD)))
    if (file.exists(fpp)) {
      fprev <- as.data.table(read_parquet(fpp, col_select=c("Ticker","Factor_Name","Z_Score","Coverage")))
      fprev <- fprev[Factor_Name %in% miss & Coverage==TRUE, .(Ticker,Factor_Name,Z_Score)]
      if (nrow(fprev)) f <- rbind(f, fprev)
    }
  }
  if (!nrow(f)) next
  ## REGISTRY FIXED direction (NOT align_factor_direction IC-sign)
  f[, sgn := reg_sign[Factor_Name]]
  f[, Z_Aligned := Z_Score * sgn]
  ## re-standardize to sd=1 per factor after sign flip (matches connector RC1 fix)
  f[!is.na(Z_Aligned), Z_Aligned := {
    s <- sd(Z_Aligned, na.rm=TRUE); if (is.na(s)||s<1e-10) Z_Aligned else Z_Aligned/s
  }, by=Factor_Name]
  tks <- ap[Date==SD, Ticker]
  fa <- f[Ticker %in% tks, .(sig_date=SD, Ticker, Factor_Name, Z_Aligned)]
  panel_rows[[i]] <- fa
  if (i %% 40 == 0) cat(sprintf("[panel] %d/%d %s rows=%d\n", i, length(sig_dates), as.character(SD), nrow(fa)))
}
PANEL <- rbindlist(panel_rows, use.names=TRUE, fill=TRUE)
cat(sprintf("\n[panel] total rows=%d | sig_dates=%d | factors=%s\n",
            nrow(PANEL), uniqueN(PANEL$sig_date), paste(sort(unique(PANEL$Factor_Name)),collapse=",")))
cov <- PANEL[, .(n_months=uniqueN(sig_date), n_rows=.N), by=Factor_Name][order(-n_months)]
print(cov)
write_parquet(PANEL, file.path(OUT, "defense_factor_panel_regdir.parquet"))
cat(sprintf("[panel] saved -> %s\n", file.path(OUT,"defense_factor_panel_regdir.parquet")))
