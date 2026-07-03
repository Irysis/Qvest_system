## ============================================================================
## Build defense-factor panel cache: candidate factors' aligned Z per sig_date,
## pinned to alpha_scores tickers (post liq/universe scope). Canonical vintage =
## factor_db_{same YYYYMM as sig_date} (matches factor_engine_proposal.R L139-152).
## M08 fallback: if factor missing in same-month file, source from prior month
## (production forced-deviation, PIT-safe). Coverage==TRUE (keep NA Z as canonical).
## PIT C13/C14/C15: align_factor_direction(sig_date) expanding-IC, Usable_Date<=sig_d.
## Segfault guard: setDTthreads(1), read_parquet col_select, no open_dataset.
## ============================================================================
suppressPackageStartupMessages({library(data.table); library(arrow); library(jsonlite)})
options(scipen=999); Sys.setenv(TZ="Asia/Seoul"); setDTthreads(1L)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(ROOT)
source(file.path(ROOT,"02_Infrastructure/config.R"))
source(file.path(ROOT,"02_Infrastructure/factor_db/factor_db_connector.R"))
OUT <- file.path(ROOT,"stage_artifacts/pg2_defense_optimize")
dir.create(OUT, recursive=TRUE, showWarnings=FALSE)

CAND_DEF <- c("Q07_Earnings_Stability","M08_Residual_Mom","Q25_Ohlson_O",
              "RE07_Crisis_Beta","D45_Downside_Dev","D48_VaR_5pct",
              "D28_Unlevered_Beta","D56_Up_Vol","Q01_GPA")

ap <- as.data.table(read_parquet(file.path(ROOT,"stage_artifacts/WT_D20260425_010/alpha_scores.parquet")))
ap[, Date := as.Date(Date)]
sig_dates <- sort(unique(ap$Date))
REG <- .load_registry()

prev_ym <- function(SD) format(seq(SD, by="-1 month", length.out=2)[2], "%Y%m")

panel_rows <- vector("list", length(sig_dates))
for (i in seq_along(sig_dates)) {
  SD <- sig_dates[i]; ym <- format(SD, "%Y%m")
  fp <- file.path(FACTOR_DB_DIR, sprintf("factor_db_%s.parquet", ym))
  if (!file.exists(fp)) next
  f <- as.data.table(read_parquet(fp, col_select=c("Ticker","Factor_Name","Z_Score","Coverage")))
  f <- f[Factor_Name %in% CAND_DEF & Coverage==TRUE, .(Ticker,Factor_Name,Z_Score)]
  # M08 (and any) fallback: factors present in CAND but absent same-month -> prior month
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
  fa <- align_factor_direction(f, REG, sig_date=SD, min_ic_months=12L)
  if ("Z_Score_Aligned" %in% names(fa)) fa[, Z_Score := Z_Score_Aligned]
  # pin to alpha tickers this sig_date (post liq/universe scope)
  tks <- ap[Date==SD, Ticker]
  fa <- fa[Ticker %in% tks, .(sig_date=SD, Ticker, Factor_Name, Z_Aligned=Z_Score)]
  panel_rows[[i]] <- fa
  if (i %% 40 == 0) cat(sprintf("[panel] %d/%d %s rows=%d\n", i, length(sig_dates), as.character(SD), nrow(fa)))
}
PANEL <- rbindlist(panel_rows, use.names=TRUE, fill=TRUE)
cat(sprintf("\n[panel] total rows=%d | sig_dates=%d | factors=%s\n",
            nrow(PANEL), uniqueN(PANEL$sig_date), paste(sort(unique(PANEL$Factor_Name)),collapse=",")))
# per-factor month coverage
cov <- PANEL[, .(n_months=uniqueN(sig_date), n_rows=.N), by=Factor_Name][order(-n_months)]
print(cov)
write_parquet(PANEL, file.path(OUT, "defense_factor_panel.parquet"))
cat(sprintf("[panel] saved -> %s\n", file.path(OUT,"defense_factor_panel.parquet")))
