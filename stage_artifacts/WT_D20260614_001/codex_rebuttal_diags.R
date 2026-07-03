# codex_rebuttal_diags.R — RF-A2 (single-factor baselines) + RF-A4 (sector/size-neutral IC)
# Addresses Codex concerns C3, C4. Reuses cached scores path infra.
suppressMessages({library(arrow); library(data.table); library(dplyr); library(jsonlite)})
options(warn = 1)
root <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
Sys.setenv(CLAUDE_PROJECT_DIR = root)
out_dir <- file.path(root, "stage_artifacts", "WT_D20260614_001")
source(file.path(root, "02_Infrastructure", "factor_db", "factor_db_connector.R"))

FACTORS_USE <- c("V01_BM","V03_CFP","V10_FCF_Yield","V11_Shareholder_Yield")
START_DATE <- as.Date("2005-01-01"); LIQ_MIN <- 2e8

rp <- file.path(root, ".cache", "rawdata.parquet")
RAWDATA <- as.data.table(read_parquet(rp,
  col_select = c("Date","Ticker","Close","Vol","K200","KQ150","Sector","Size")))
RAWDATA[, Date := as.Date(Date)]; setorder(RAWDATA, Ticker, Date)
rd <- RAWDATA
rd[, ym := format(Date,"%Y-%m")]
month_ends <- sort(rd[, .(Date=max(Date)), by=ym]$Date); month_ends <- month_ends[month_ends>=START_DATE]
rd[, TV := Close*Vol]; rd[, AvgTV20 := frollmean(TV,20L,align="right"), by=Ticker]
mem <- rd[Date %in% month_ends & (K200==1|KQ150==1) & !is.na(AvgTV20) & AvgTV20>=LIQ_MIN,
          .(Date,Ticker,Sector,Size)]
setkey(mem, Date, Ticker)

# month-end close -> forward 1M ret
me <- rd[Date %in% month_ends, .(Date,Ticker,Close)]; setorder(me,Ticker,Date)
me[, Cn := shift(Close,-1L), by=Ticker]; me[, Ret_1m := Cn/Close-1]
returns_dt <- me[is.finite(Ret_1m), .(Date,Ticker,Ret_1m)]

# Load per-factor z (raw aligned) for all 4, per month, restricted to universe
fl <- vector("list", length(month_ends))
for (i in seq_along(month_ends)) {
  d <- month_ends[i]
  uni <- mem[.(d), .(Ticker,Sector,Size), nomatch=0L]
  if (!nrow(uni)) next
  fdt <- tryCatch(load_month_factors(d, coverage_min=0.05, factor_names=FACTORS_USE), error=function(e) NULL)
  if (is.null(fdt)||!nrow(fdt)) next
  w <- dcast(fdt[Factor_Name %in% FACTORS_USE & is.finite(Z_Score_Aligned)],
             Ticker ~ Factor_Name, value.var="Z_Score_Aligned")
  w <- merge(uni, w, by="Ticker")
  w[, Date := d]
  fl[[i]] <- w
}
A <- rbindlist(Filter(Negate(is.null), fl), use.names=TRUE, fill=TRUE)
A <- merge(A, returns_dt, by=c("Date","Ticker"))

# helper: monthly rank-IC + ICIR + NW3 t for a score column
nw_t <- function(x, lag=3L){x<-x[is.finite(x)];n<-length(x);if(n<5)return(NA);mu<-mean(x);e<-x-mu;g0<-sum(e^2)/n;s<-g0;for(l in 1:lag){if(l>=n)break;wt<-1-l/(lag+1);gl<-sum(e[(l+1):n]*e[1:(n-l)])/n;s<-s+2*wt*gl};mu/sqrt(s/n)}
ic_stats <- function(dt, scol){
  ib <- dt[is.finite(get(scol)) & is.finite(Ret_1m),
           .(ic = if(.N>=10) cor(get(scol),Ret_1m,method="spearman") else NA_real_), by=Date][is.finite(ic)]
  list(rank_ic=mean(ib$ic), icir=mean(ib$ic)/sd(ib$ic), harvey_t=nw_t(ib$ic,3L), n=nrow(ib))
}

# ---- RF-A2: single-factor baselines vs EW composite ----
A[, comp := rowMeans(.SD, na.rm=TRUE), .SDcols=FACTORS_USE]
A[, comp_kf := rowSums(is.finite(as.matrix(.SD))), .SDcols=FACTORS_USE]
A_full <- A[comp_kf==length(FACTORS_USE)]   # composite requires all 4 (match alpha def)
rf_a2 <- list()
for (f in FACTORS_USE) rf_a2[[f]] <- ic_stats(A[is.finite(get(f))], f)
rf_a2[["EW_composite"]] <- ic_stats(A_full, "comp")

# ---- RF-A4: sector-neutral and size-neutral IC of composite ----
# sector-neutral: demean comp within (Date,Sector); size-neutral: residual of comp ~ log? Size has NA; rank-demean within size quintile
A_full[, comp_secneu := comp - mean(comp, na.rm=TRUE), by=.(Date, Sector)]
A_full[, size_q := { s<-Size; if(all(is.na(s))) NA_integer_ else as.integer(cut(frank(s,ties.method="average")/.N, seq(0,1,0.2), labels=1:5, include.lowest=TRUE)) }, by=Date]
A_full[, comp_sizeneu := comp - mean(comp, na.rm=TRUE), by=.(Date, size_q)]
A_full[, comp_secsize := comp - mean(comp, na.rm=TRUE), by=.(Date, Sector, size_q)]
rf_a4 <- list(
  raw          = ic_stats(A_full, "comp"),
  sector_neu   = ic_stats(A_full, "comp_secneu"),
  size_neu     = ic_stats(A_full, "comp_sizeneu"),
  sectorsize_neu = ic_stats(A_full, "comp_secsize"))
raw_ic <- rf_a4$raw$rank_ic
rf_a4_retention <- list(
  sector_neu_pct  = rf_a4$sector_neu$rank_ic / raw_ic,
  size_neu_pct    = rf_a4$size_neu$rank_ic / raw_ic,
  sectorsize_pct  = rf_a4$sectorsize_neu$rank_ic / raw_ic)

res <- list(
  rf_a2_single_vs_composite = lapply(rf_a2, function(x) lapply(x, function(v) if(is.numeric(v)) round(v,5) else v)),
  rf_a4_neutralized_ic = lapply(rf_a4, function(x) lapply(x, function(v) if(is.numeric(v)) round(v,5) else v)),
  rf_a4_retention_pct = lapply(rf_a4_retention, function(v) round(v,3)),
  n_universe_months = uniqueN(A_full$Date))
write_json(res, file.path(out_dir, "codex_rebuttal_diags.json"), pretty=TRUE, auto_unbox=TRUE, digits=6)

cat("\n==== RF-A2 single vs composite (rank_ic | icir | harvey_t | n) ====\n")
for (nm in names(rf_a2)) cat(sprintf("  %-22s ic=%.4f icir=%.3f t=%.2f n=%d\n", nm,
  rf_a2[[nm]]$rank_ic, rf_a2[[nm]]$icir, rf_a2[[nm]]$harvey_t, rf_a2[[nm]]$n))
cat("\n==== RF-A4 neutralized IC ====\n")
for (nm in names(rf_a4)) cat(sprintf("  %-16s ic=%.4f icir=%.3f t=%.2f\n", nm,
  rf_a4[[nm]]$rank_ic, rf_a4[[nm]]$icir, rf_a4[[nm]]$harvey_t))
cat(sprintf("retention: sector=%.0f%% size=%.0f%% sector+size=%.0f%%\n",
  100*rf_a4_retention$sector_neu_pct, 100*rf_a4_retention$size_neu_pct, 100*rf_a4_retention$sectorsize_pct))
cat("DONE\n")
