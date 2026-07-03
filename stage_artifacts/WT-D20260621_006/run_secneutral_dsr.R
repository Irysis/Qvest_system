suppressMessages({library(arrow); library(data.table); library(dplyr); library(jsonlite)})
arrow::set_io_thread_count(2L); setDTthreads(2L)
PROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(PROOT)
OUT <- file.path(PROOT,"stage_artifacts/WT-D20260621_006")
sc <- readRDS(file.path(OUT,"scores_primary.rds"))
ret <- readRDS(file.path(OUT,"returns_dt.rds"))
# sector from rawdata at each sig_date
ds <- open_dataset(".cache/rawdata.parquet")
sec <- ds %>% filter(Date >= as.Date("2005-01-01")) %>% select(Date,Ticker,Sector) %>% collect() %>% as.data.table()
sec[, Date := as.Date(Date)]
m <- merge(sc[,.(Date,Ticker,score)], ret, by=c("Date","Ticker"))
m <- merge(m, sec, by=c("Date","Ticker"), all.x=TRUE)
# sector-neutral score = score - sector mean per date
m[, score_sn := score - mean(score, na.rm=TRUE), by=.(Date,Sector)]
# raw IC vs sector-neutral IC
ic_raw <- m[, .(ic=if(.N>=10) cor(score, Ret_1m, method="spearman") else NA_real_), by=Date][!is.na(ic)]
ic_sn  <- m[!is.na(score_sn), .(ic=if(.N>=10) cor(score_sn, Ret_1m, method="spearman") else NA_real_), by=Date][!is.na(ic)]
icr <- mean(ic_raw$ic); ics <- mean(ic_sn$ic)
# DSR-diagnostic (single hypothesis chain -> advisory; report anyway per Codex C4)
# net SR of PRIMARY screen from screen_primary
scr <- readRDS(file.path(OUT,"screen_primary.rds"))
net_sr <- scr[tag=="primary_n20", net_sr]; n_m <- scr[tag=="primary_n20", n_months]
# DSR (Bailey-LdP): assume n_trials = number of pre-registered chain configs (audit) ~ 18 enumerated, but chain=>advisory
# PSR(SR*=0) ~ Phi( SR*sqrt(n-1) / sqrt(1 - skew*SR + (kurt-1)/4*SR^2) ); simplified with normal returns
SR_m <- net_sr/sqrt(12)  # monthly
psr0 <- pnorm(SR_m*sqrt(n_m-1))
out <- list(
  ic_raw=round(icr,5), ic_sector_neutral=round(ics,5),
  ic_sn_retention = round(ics/icr,3),
  sector_neutral_note = "RF-A4: sector-neutral IC vs raw IC. retention near 1 = not a sector bet.",
  dsr_diagnostic = list(
    psr_vs_zero = round(psr0,4),
    net_sr_annual = round(net_sr,4), n_months = n_m,
    note = "selection_type=chain -> DSR gate NOT binding (measurement-graduation §3). Reported as diagnostic only per Codex C4. PSR(SR*=0) is prob SR>0, not multi-trial-deflated."
  )
)
cat(toJSON(out, auto_unbox=TRUE, pretty=TRUE))
saveRDS(out, file.path(OUT,"secneutral_dsr.rds"))
cat("\nSECDSR_DONE\n")
