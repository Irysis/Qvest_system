# R24 WT-D20260713_008 Step 01 — COVERAGE CENSUS (pre-registration input; NOT an association observation)
# Goal: quantify the honest maximum measurable filing-delay universe under the no-API constraint.
# Reuse R22 full-universe events.rds + attr_m.rds. Reuse WT-002 filings_inventory. Reuse WT-005 disc_ck.
suppressMessages({library(arrow); library(data.table)})
setDTthreads(1L); try(arrow::set_io_thread_count(2L), silent=TRUE)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
R22  <- file.path(ROOT,"stage_artifacts/WT_D20260713_006")
INV  <- file.path(ROOT,"stage_artifacts/WT_D20260711_002/filings_inventory.parquet")
DISC <- file.path(ROOT,"stage_artifacts/WT-D20260710_005/disc_ck")
OUT  <- file.path(ROOT,"stage_artifacts/WT_D20260713_008")
d2ym <- function(d){ (as.integer(d)%/%10000L)*100L + (as.integer(d)%/%100L)%%100L }

cat("========================= R24 COVERAGE CENSUS =========================\n")

## (A) RAWDATA full-universe event side (reuse R22) --------------------------
events <- readRDS(file.path(R22,"events.rds"))
attr_m <- readRDS(file.path(R22,"attr_m.rds"))
meta   <- readRDS(file.path(R22,"meta.rds"))
events[, sc := sub("^A","",Ticker)]
cat("\n[A] RAWDATA full-universe (from R22 events/attr):\n")
cat("   distinct tickers in attr_m panel :", uniqueN(attr_m$Ticker),"\n")
cat("   attr_m ym range                  :", paste(range(attr_m$ym),collapse=".."),"\n")
cat("   event onsets by type:\n"); print(events[, .N, by=type][order(-N)])
cat("   distinct event tickers by type:\n"); print(events[, .(n_tk=uniqueN(Ticker)), by=type][order(-n_tk)])
sev_types <- c("Delisting","AdminStock","UnfaithfulDisc")
sev_tk <- events[type %in% sev_types, uniqueN(Ticker)]
cat("   distinct tickers with ANY severe onset (Del/Admin/Unf):", sev_tk,"\n")

## (B) filings_inventory (F-B filing-delay predictor source) -----------------
inv <- as.data.table(read_parquet(INV))
inv <- inv[grepl("사업보고서", report_nm)]
inv[, rc := as.Date(as.character(rcept_dt),"%Y%m%d")]
inv[, deadline := as.Date(sprintf("%d-03-31", fy+1L))]
inv[, delay_d := as.integer(rc - deadline)]
inv[, rcept_ym := d2ym(rcept_dt)]
inv <- inv[is.finite(delay_d)]
inv_tk <- unique(inv$Ticker)
cat("\n[B] filings_inventory 사업보고서 (delay predictor source):\n")
cat("   rows:", nrow(inv)," distinct tickers:", length(inv_tk),
    " fy range:", paste(range(inv$fy),collapse=".."),"\n")
cat("   delay_d quantiles (days late vs 3/31 deadline):",
    paste(round(quantile(inv$delay_d,c(0,.5,.9,.99,1))),collapse=","),"\n")
cat("   late-filer rows (delay_d>0):", sum(inv$delay_d>0),
    " distinct late-filer tickers:", uniqueN(inv[delay_d>0,Ticker]),"\n")

## (C) disc_ck 사업보고서 extraction (potential coverage extension) ----------
fs <- list.files(DISC, pattern="[.]csv$", full.names=TRUE)
DK <- rbindlist(lapply(fs, function(f) tryCatch(
  fread(f, colClasses=list(character=c("stock_code","rcept_no")),
        select=c("stock_code","report_nm","rcept_dt")),
  error=function(e) NULL)), fill=TRUE)
DK[, stock_code := sprintf("%06d", as.integer(stock_code))]
DK[, rnt := trimws(report_nm)]
DK[, dym := d2ym(rcept_dt)]
dk_saup <- DK[grepl("사업보고서", rnt) & !grepl("첨부|정정예고", rnt)]
dk_saup_tk <- unique(dk_saup$stock_code)
cat("\n[C] disc_ck archive (50.7만행 list archive, 348 survivor stocks):\n")
cat("   total disc_ck rows:", nrow(DK)," distinct stocks:", uniqueN(DK$stock_code),"\n")
cat("   사업보고서 rows in disc_ck:", nrow(dk_saup)," distinct stocks:", length(dk_saup_tk),"\n")
inv_sc <- sub("^A","",inv_tk)
cat("   disc_ck 사업보고서 stocks NOT in filings_inventory:",
    length(setdiff(dk_saup_tk, inv_sc)),"\n")

## (D) Measurable universe intersection (predictor x events x controls) ------
inv_sc_all <- sub("^A","",inv_tk)
attr_sc <- unique(sub("^A","",attr_m$Ticker))
# tickers with filing-delay data AND present in rawdata attr panel (controls+events available)
measurable <- intersect(inv_sc_all, attr_sc)
cat("\n[D] MEASURABLE UNIVERSE (filing-delay data AND rawdata controls):\n")
cat("   filings_inventory tickers      :", length(inv_sc_all),"\n")
cat("   present in rawdata attr panel  :", length(measurable),"\n")
cat("   filing tickers NOT in rawdata  :", length(setdiff(inv_sc_all, attr_sc)),"\n")
# how many measurable tickers ever had a severe event
meas_sev <- events[type %in% sev_types & sc %in% measurable, uniqueN(sc)]
cat("   measurable tickers w/ ANY severe onset:", meas_sev,"\n")

## (E) Independent late-filing EPISODES (the R23 power bottleneck) -----------
# worst-decile delay per fiscal year across measurable universe (cross-section = per fy, all measurable filers)
inv_m <- inv[Ticker %in% paste0("A",measurable)]
inv_m[, sc := sub("^A","",Ticker)]
# per-fy cross-sectional decile of delay across ALL measurable filers that fy
inv_m[, dec := {r<-frank(delay_d,ties.method="average"); ceiling(r/.N*10)}, by=fy]
inv_m[dec>10, dec:=10L]
wd_epi <- inv_m[dec==10]  # worst-decile filing episodes
cat("\n[E] INDEPENDENT late-filing EPISODES (worst-decile delay, per-fy cross-section):\n")
cat("   total filing-year obs (measurable):", nrow(inv_m),"\n")
cat("   worst-decile filing episodes      :", nrow(wd_epi),"\n")
cat("   distinct worst-decile firms       :", uniqueN(wd_epi$sc),"\n")
cat("   worst-decile delay_d range        :", paste(range(wd_epi$delay_d),collapse=".."),"\n")
cat("   >> R23 had ~6 independent late-filer company-episodes (monthly-overlap collapsed).\n")
cat("   >> R24 episode-level worst-decile firm count above is the power comparison.\n")

## (F) Year distribution of worst-decile episodes ---------------------------
cat("\n[F] worst-decile episode count by fiscal year:\n")
print(wd_epi[, .N, by=fy][order(fy)])

saveRDS(list(events=events, attr_m=attr_m, meta=meta, inv=inv, inv_m=inv_m,
             measurable=measurable, dk_saup=dk_saup, wd_epi=wd_epi),
        file.path(OUT,"census.rds"))
cat("\n[01] DONE — census.rds saved. Universe decision to be frozen in preregistration.json\n")
