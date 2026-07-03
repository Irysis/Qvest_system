# REVISE: walk-forward panel + leave-one-family ablation + sector-neutral IC + universe audit
# Addresses Codex C1, C3, C4, C6, RF-A4, RF-A5
suppressMessages({ library(data.table); library(arrow) })
Sys.setenv(CLAUDE_PROJECT_DIR=getwd(), QM_ROOT=getwd())
source("02_Infrastructure/factor_db/factor_db_connector.R")

OUT <- "stage_artifacts/WT-D20260614_002"
FACTORS <- c("D01_IdioVol","D02_Beta","M07_IndMom","M01_Mom_12_1","M05_Trended_Mom",
             "Q01_GPA","Q04_Piotroski_F","Q09_CFOA","Q07_Earnings_Stability","V01_BM")
AXIS <- list(defense=c("D01_IdioVol","D02_Beta"),
             momentum=c("M07_IndMom","M01_Mom_12_1","M05_Trended_Mom"),
             quality=c("Q01_GPA","Q04_Piotroski_F","Q09_CFOA","Q07_Earnings_Stability"),
             value=c("V01_BM"))

# ---- forward 1M returns + universe + sector from rawdata (monthly) ----
raw <- as.data.table(read_parquet(".cache/rawdata.parquet",
        col_select=c("Date","Ticker","Close","K200","KQ150","Sector","Vol","Size")))
raw[, Date := as.Date(Date)]
raw[, ym := format(Date, "%Y%m")]
# month-end snapshot per ticker
setorder(raw, Ticker, Date)
me <- raw[, .SD[.N], by=.(Ticker, ym)]  # last obs in month
me[, Close := as.numeric(Close)]
setorder(me, Ticker, ym)
me[, fwd_ret := shift(Close, -1)/Close - 1, by=Ticker]   # forward 1M (month t -> t+1)
me[, in_univ := (K200==TRUE | KQ150==TRUE)]
# 20d ADV proxy: Vol*Close not available pre-agg; use Size (market cap) as liquidity proxy floor presence
me[, mcap := as.numeric(Size)]

# month-end sig dates 2005..2026
sigdates <- sort(unique(me$ym))
sigdates <- sigdates[sigdates >= "200501" & sigdates <= "202604"]

# ---- per-month composite z (full + ablations) and IC ----
ic_rows <- list()
sn_ic_full <- c(); univ_frac <- c()
factor_sets <- c(list(FULL=FACTORS,
                      best_Q04="Q04_Piotroski_F", best_D01="D01_IdioVol",
                      DQV6=c("D01_IdioVol","D02_Beta","Q01_GPA","Q04_Piotroski_F","Q09_CFOA","Q07_Earnings_Stability","V01_BM")),
                 setNames(lapply(names(AXIS), function(a) setdiff(FACTORS, AXIS[[a]])),
                          paste0("drop_", names(AXIS))))

spearman <- function(x,y){ ok <- is.finite(x)&is.finite(y); if(sum(ok)<10) return(NA_real_); cor(rank(x[ok]),rank(y[ok])) }

for (ym in sigdates) {
  sig_d <- as.Date(paste0(substr(ym,1,4),"-",substr(ym,5,6),"-28"))
  fac <- tryCatch(load_month_factors(sig_d, coverage_min=0.05, factor_names=FACTORS),
                  error=function(e) NULL)
  if (is.null(fac) || nrow(fac)==0) next
  w <- dcast(fac, Ticker ~ Factor_Name, value.var="Z_Score_Aligned")
  # restrict to in-universe with forward return
  mm <- me[ym==get("ym"), .(Ticker, fwd_ret, in_univ, Sector, mcap)]
  d <- merge(w, mm, by="Ticker")
  d <- d[in_univ==TRUE & is.finite(fwd_ret)]
  if (nrow(d) < 30) next
  univ_frac <- c(univ_frac, nrow(d))
  ic_one <- list(ym=ym, n=nrow(d))
  for (nm in names(factor_sets)) {
    cols <- intersect(factor_sets[[nm]], names(d))
    if (length(cols)==0) { ic_one[[nm]] <- NA_real_; next }
    z <- rowMeans(as.matrix(d[, ..cols]), na.rm=TRUE)
    ic_one[[nm]] <- spearman(z, d$fwd_ret)
  }
  # sector-neutral IC (FULL): demean fwd_ret & composite z within sector, then IC
  colsF <- intersect(FACTORS, names(d))
  d[, zF := rowMeans(as.matrix(.SD), na.rm=TRUE), .SDcols=colsF]
  d[, zF_sn := zF - mean(zF, na.rm=TRUE), by=Sector]
  d[, fwd_sn := fwd_ret - mean(fwd_ret, na.rm=TRUE), by=Sector]
  sn_ic_full <- c(sn_ic_full, spearman(d$zF_sn, d$fwd_sn))
  ic_rows[[length(ic_rows)+1]] <- ic_one
}
panel <- rbindlist(ic_rows, fill=TRUE)
cat("[revise] walk-forward IC panel months:", nrow(panel), "range:", panel$ym[1],"->",panel$ym[nrow(panel)],"\n")

# write walk-forward IC panel (Date x set IC) — closes C1
write_parquet(panel, file.path(OUT,"alpha_ic_panel_walkforward.parquet"))

icir_of <- function(v){ v<-v[is.finite(v)]; if(length(v)<12) return(c(NA,NA,NA)); c(mean(v), mean(v)/sd(v), sqrt(length(v))*mean(v)/sd(v)) }
cat("\n[revise] === LEAVE-ONE-FAMILY ABLATION (in-universe sector-raw IC) ===\n")
cat(sprintf("%-14s %8s %8s %8s\n","set","meanIC","ICIR","t"))
abl <- list()
for (nm in names(factor_sets)) {
  s <- icir_of(panel[[nm]])
  abl[[nm]] <- list(meanIC=round(s[1],4), ICIR=round(s[2],3), t=round(s[3],2))
  cat(sprintf("%-14s %8.4f %8.3f %8.2f\n", nm, s[1], s[2], s[3]))
}
sn <- icir_of(sn_ic_full)
cat(sprintf("\n[revise] SECTOR-NEUTRAL IC (FULL): meanIC=%.4f ICIR=%.3f t=%.2f  (raw FULL meanIC=%.4f)\n",
            sn[1], sn[2], sn[3], icir_of(panel$FULL)[1]))
sn_retention <- sn[1]/icir_of(panel$FULL)[1]
cat(sprintf("[revise] sector-neutral IC retention = %.1f%% of raw (RF-A4 threshold 30%%)\n", 100*sn_retention))

# ---- universe + liquidity audit on as_of snapshot (top-30 holdings) ----
scores <- as.data.table(read_parquet(file.path(OUT,"alpha_scores.parquet")))
top30 <- scores[order(-alpha_z)][1:30, Ticker]
last_me <- me[ym=="202605"]
au <- last_me[Ticker %in% top30]
cat(sprintf("\n[revise] === UNIVERSE/LIQUIDITY AUDIT (top-30 @ 2026-05) ===\n"))
cat(sprintf("  top30 in K200uKQ150: %d/30 (%.0f%%)\n", sum(au$in_univ, na.rm=TRUE), 100*mean(au$in_univ,na.rm=TRUE)))
cat(sprintf("  median mcap (Size): %.3g | min: %.3g\n", median(au$mcap,na.rm=TRUE), min(au$mcap,na.rm=TRUE)))

saveRDS(list(ablation=abl, sn_ic=list(meanIC=sn[1],ICIR=sn[2],t=sn[3],retention=sn_retention),
             panel_months=nrow(panel), panel_range=c(panel$ym[1], panel$ym[nrow(panel)]),
             top30_in_univ_frac=mean(au$in_univ,na.rm=TRUE),
             top30_in_univ_n=sum(au$in_univ,na.rm=TRUE)),
        file.path(OUT,"_revise_diag.rds"))
cat("\n[revise] saved _revise_diag.rds + alpha_ic_panel_walkforward.parquet\n")
