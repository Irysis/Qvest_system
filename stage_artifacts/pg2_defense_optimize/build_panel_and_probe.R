## ============================================================================
## PG2 defense-optimize: (A) build defense factor panel cache, (B) parity probe
## Determines vintage (same-month vs T-1) that reproduces stored score_defense_z.
## PIT/self-synth compliant. Single-thread + arrow io_thread=1 (segfault guard).
## ============================================================================
suppressPackageStartupMessages({library(data.table); library(arrow); library(jsonlite)})
options(scipen=999); Sys.setenv(TZ="Asia/Seoul")
setDTthreads(1L); try(arrow::set_io_thread_count(1L), silent=TRUE)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
setwd(ROOT)
source(file.path(ROOT,"02_Infrastructure/config.R"))
source(file.path(ROOT,"02_Infrastructure/factor_db/factor_db_connector.R"))

OUT <- file.path(ROOT,"stage_artifacts/pg2_defense_optimize")
dir.create(OUT, recursive=TRUE, showWarnings=FALSE)

CAND_DEF <- c("Q07_Earnings_Stability","M08_Residual_Mom","Q25_Ohlson_O",
              "RE07_Crisis_Beta","D45_Downside_Dev","D48_VaR_5pct",
              "D28_Unlevered_Beta","D56_Up_Vol","Q01_GPA")
CUR_DEF  <- c("Q07_Earnings_Stability","M08_Residual_Mom","Q25_Ohlson_O")  # EW 1/3

winsor_z <- function(x,s=2.5){m<-mean(x,na.rm=T);sd<-sd(x,na.rm=T);if(is.na(sd)||sd<1e-10)return(x);pmax(pmin(x,m+s*sd),m-s*sd)}
zc <- function(x){m<-mean(x,na.rm=T);s<-sd(x,na.rm=T);if(is.na(s)||s<1e-10)x-m else (x-m)/s}

## alpha_scores: sig_dates + ticker pin + stored score_defense_z
ap <- as.data.table(read_parquet(file.path(ROOT,"stage_artifacts/WT_D20260425_010/alpha_scores.parquet")))
ap[, Date := as.Date(Date)]
sig_dates <- sort(unique(ap$Date))
cat(sprintf("[alpha] %d sig_dates %s~%s | %d rows\n", length(sig_dates),
            as.character(min(sig_dates)), as.character(max(sig_dates)), nrow(ap)))

## helper: load one factor_db file's aligned Z for requested factors at sig_date
load_fac_aligned <- function(fym, facs, sig_d){
  fpath <- file.path(FACTOR_DB_DIR, sprintf("factor_db_%s.parquet", fym))
  if (!file.exists(fpath)) return(NULL)
  f <- as.data.table(read_parquet(fpath, col_select=c("Ticker","Factor_Name","Z_Score","Coverage")))
  f <- f[Factor_Name %in% facs & Coverage==TRUE & !is.na(Z_Score), .(Ticker,Factor_Name,Z_Score)]
  if (!nrow(f)) return(NULL)
  fa <- align_factor_direction(f, .load_registry(), sig_date=sig_d, min_ic_months=12L)
  if ("Z_Score_Aligned" %in% names(fa)) fa[, Z_Score := Z_Score_Aligned]
  fa[, .(Ticker, Factor_Name, Z_Score)]
}

## reconstruct def_z for CUR_DEF at a sig_date using a given vintage rule, pinned to alpha tickers
recon_defz <- function(sig_d, vintage=c("prev","same")){
  vintage <- match.arg(vintage)
  fym <- if (vintage=="prev") format(seq(sig_d, by="-1 month", length.out=2)[2], "%Y%m") else format(sig_d,"%Y%m")
  fa <- load_fac_aligned(fym, CUR_DEF, sig_d)
  if (is.null(fa)) return(NULL)
  # M08 fallback: if missing in file, try prev-month (matches production forced deviation)
  miss <- setdiff(CUR_DEF, unique(fa$Factor_Name))
  if (length(miss)) {
    fym2 <- format(seq(as.Date(paste0(substr(fym,1,4),"-",substr(fym,5,6),"-01")), by="-1 month", length.out=2)[2], "%Y%m")
    fa2 <- load_fac_aligned(fym2, miss, sig_d)
    if (!is.null(fa2)) fa <- rbind(fa, fa2)
  }
  fw <- dcast(fa, Ticker ~ Factor_Name, value.var="Z_Score", fill=NA_real_)
  # pin to alpha tickers present this sig_date
  tks <- ap[Date==sig_d, Ticker]
  fw <- fw[Ticker %in% tks]
  facp <- intersect(CUR_DEF, names(fw))
  if (!length(facp)) return(NULL)
  W <- rep(1/length(CUR_DEF), length(CUR_DEF)); names(W) <- CUR_DEF; W <- W[facp]; W <- W/sum(W)
  X <- as.matrix(fw[, ..facp]); X <- apply(X, 2, winsor_z); X[is.na(X)] <- 0
  fw[, Score_Def := as.numeric(X %*% W)]
  fw[, def_z := zc(Score_Def)]
  merge(ap[Date==sig_d, .(Ticker, stored=score_defense_z)], fw[, .(Ticker, def_z)], by="Ticker", all.x=TRUE)
}

## PROBE on a spread of dates
probe_dates <- as.Date(c("2008-01-01","2012-06-01","2018-03-01","2022-09-01","2026-05-01","2026-06-01"))
probe_dates <- probe_dates[probe_dates %in% sig_dates]
cat("\n=== VINTAGE PROBE (max|diff| stored vs recon) ===\n")
res <- rbindlist(lapply(probe_dates, function(d){
  rp <- recon_defz(d, "prev"); rs <- recon_defz(d, "same")
  mp <- if (!is.null(rp)) max(abs(rp$def_z - rp$stored), na.rm=TRUE) else NA_real_
  ms <- if (!is.null(rs)) max(abs(rs$def_z - rs$stored), na.rm=TRUE) else NA_real_
  np <- if (!is.null(rp)) sum(!is.na(rp$def_z)) else 0L
  data.table(sig_date=d, maxdiff_prev=mp, maxdiff_same=ms, n_recon=np)
}), fill=TRUE)
print(res)
cat("\nprev-vintage median maxdiff:", median(res$maxdiff_prev, na.rm=TRUE),
    "| same-vintage median maxdiff:", median(res$maxdiff_same, na.rm=TRUE), "\n")
saveRDS(res, file.path(OUT,"vintage_probe.rds"))
cat("[done] probe saved\n")
