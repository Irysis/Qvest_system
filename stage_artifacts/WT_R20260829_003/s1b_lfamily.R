# S1b — L-family 통제변수 적재 (C15: load_month_factors() 경유 · C13: Z_Score_Aligned only)
suppressWarnings(suppressMessages({library(data.table); library(future.apply)}))
ROOT <- Sys.getenv("QM_ROOT"); if (!nzchar(ROOT)) ROOT <- getwd(); setwd(ROOT)
Sys.setenv(CLAUDE_PROJECT_DIR = ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT_R20260829_003")
P <- readRDS(file.path(OUT, "panel.rds")); ME <- P$ME
CTRLS <- c("L01_Amihud","L09_Amihud_20d","L11_Kyle_Lambda")
plan(multisession, workers = min(6L, max(1L, parallel::detectCores() - 1L)))
t0 <- Sys.time()
res <- future_lapply(ME, function(d) {
  suppressWarnings(suppressMessages({library(data.table)}))
  source(file.path(Sys.getenv("QM_ROOT"), "02_Infrastructure/factor_db/factor_db_connector.R"))
  x <- tryCatch(as.data.table(load_month_factors(d, factor_names = CTRLS)), error = function(e) NULL)
  if (is.null(x) || !nrow(x)) return(NULL)
  x <- x[Factor_Name %in% CTRLS, .(Ticker, Factor_Name, Z_Score_Aligned)]
  w <- dcast(x, Ticker ~ Factor_Name, value.var = "Z_Score_Aligned", fun.aggregate = function(v) v[1])
  w[, Date := d][]
}, future.seed = TRUE, future.globals = list(CTRLS = CTRLS))
plan(sequential)
L <- rbindlist(res, fill = TRUE)
for (cc in CTRLS) if (!cc %in% names(L)) L[, (cc) := NA_real_]
setcolorder(L, c("Date","Ticker"))
cat(sprintf("[S1b] L-family: %d rows · %d months · cover %s · elapsed=%.1fs\n",
            nrow(L), uniqueN(L$Date),
            paste(sprintf("%s=%.1f%%", CTRLS, 100*sapply(CTRLS, function(c) mean(is.finite(L[[c]])))), collapse=" "),
            as.numeric(difftime(Sys.time(), t0, units="secs"))))
saveRDS(L, file.path(OUT, "lfamily.rds"))
