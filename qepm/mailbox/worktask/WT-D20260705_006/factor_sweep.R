# Conservative-Investment factor composite sweep via load_month_factors (C15, PIT-safe)
Sys.setenv(LC_ALL = "English_United States.utf8")
suppressWarnings(suppressMessages({ library(data.table); library(arrow) }))
data.table::setDTthreads(1L)
PROJ <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(PROJ)
source("02_Infrastructure/config.R")
source("02_Infrastructure/factor_db/factor_db_connector.R")   # load_month_factors
STA <- file.path(PROJ, "stage_artifacts/WT_D20260705_006")
bp <- readRDS(file.path(STA,"base_panels.rds"))
univ_dt <- bp$univ_dt; setkey(univ_dt, Date, Ticker)
me_dates <- bp$me_dates
FDB_MIN <- as.Date("2005-01-01")

CONS <- c("GR03_Asset_Growth","Q06_Asset_Growth","AC24_NOA_Growth","AC05_NOA",
          "AC09_NNI","IN04_Net_Equity_Issuance","IN05_Net_Debt_Issuance",
          "IN06_Investment_to_Assets","IN01_CapEx_to_Assets","Q20_Net_Equity_Issuance")
MOM <- "M04_Mom_1"; MOM_ALT <- "M01_Mom_12_1"
want <- unique(c(CONS, MOM, MOM_ALT))

sig_dates <- me_dates[me_dates >= FDB_MIN & me_dates <= max(bp$bench_dt$Date)]
# resume support: load already-collected months
PARTIAL <- file.path(STA,"FAC_partial.rds")
done_dates <- as.Date(character(0))
if (file.exists(PARTIAL)) {
  prev <- readRDS(PARTIAL); done_dates <- unique(prev$Date)
  cat("[resume] already have", length(done_dates), "months\n")
}
flist <- vector("list", length(sig_dates)); t0 <- Sys.time()
read_month <- function(d) {   # retry wrapper for OneDrive flakiness
  for (a in 1:3) {
    fdt <- tryCatch(load_month_factors(d, coverage_min=0.05, factor_names=want),
                    error=function(e) NULL)
    if (!is.null(fdt) && nrow(fdt)>0) return(fdt)
    Sys.sleep(0.2)
  }
  NULL
}
for (i in seq_along(sig_dates)) {
  d <- sig_dates[i]
  if (d %in% done_dates) next
  uni <- univ_dt[.(d), Ticker, nomatch=0L]; if (!length(uni)) next
  fdt <- read_month(d); if (is.null(fdt)) { cat("[miss]", as.character(d), "\n"); next }
  slim <- fdt[Factor_Name %in% want & Ticker %in% uni & is.finite(Z_Score_Aligned),
              .(Ticker, Factor_Name, Z=Z_Score_Aligned)]
  if (nrow(slim)) { slim[, Date := d]; flist[[i]] <- slim }
  if (i %% 20L == 0L) {   # incremental checkpoint save
    cur <- rbindlist(Filter(Negate(is.null), flist), use.names=TRUE)
    if (file.exists(PARTIAL)) cur <- rbindlist(list(readRDS(PARTIAL), cur), use.names=TRUE)
    saveRDS(unique(cur), PARTIAL, compress=TRUE)
    flist <- vector("list", length(sig_dates)); done_dates <- unique(cur$Date)
    cat(sprintf("[ckpt] %d/%d saved %d months (%.0fs)\n", i, length(sig_dates),
        length(done_dates), as.numeric(difftime(Sys.time(),t0,units="secs")))); flush.console()
  }
}
cur <- rbindlist(Filter(Negate(is.null), flist), use.names=TRUE)
if (file.exists(PARTIAL)) cur <- rbindlist(list(readRDS(PARTIAL), if(nrow(cur)) cur else NULL), use.names=TRUE)
FAC <- unique(cur)
cat(sprintf("[factors] rows=%d months=%d\n", nrow(FAC), uniqueN(FAC$Date)))
print(FAC[, .(months=uniqueN(Date), tickers=uniqueN(Ticker), mean_z=round(mean(Z),3)),
           by=Factor_Name][order(Factor_Name)])
saveRDS(FAC, file.path(STA,"FAC.rds"), compress=TRUE)
cat("SAVED FAC.rds\n")
