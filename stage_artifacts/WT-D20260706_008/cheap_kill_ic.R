suppressPackageStartupMessages({library(data.table)})
source("02_Infrastructure/config.R")
TMP <- "C:/Users/99922/AppData/Local/Temp/claude"
panel <- readRDS(file.path(TMP,"wt008_panel.rds")); setDT(panel)
setorder(panel, Ticker, ym)

# ---- PIT: all signals observed at me_date (close of month t), forward return = t->t+1 ----
# 1) basis_pct : futures premium/discount (rich=강세 positioning candidate)
# 2) oi_chg    : MoM % change in total OI (positioning build)
# 3) basis_mom : change in basis_pct MoM
# 4) fut_liq   : futures trade value (control)
panel[, oi_chg := tot_oi/shift(tot_oi,1) - 1, by=Ticker]
panel[, basis_mom := basis_pct - shift(basis_pct,1), by=Ticker]
panel[, log_futval := log1p(tot_val)]

# winsorize signals cross-sectionally
wins <- function(x, k=3) { m<-mean(x,na.rm=T); s<-sd(x,na.rm=T); pmin(pmax(x, m-k*s), m+k*s) }
for (v in c("basis_pct","oi_chg","basis_mom")) panel[, (paste0("z_",v)) := wins(get(v)), by=ym]

panel[, yr := as.integer(substr(ym,1,4))]
# liquidity filter: spot-stock 20d adv >= 2e8 (mandate)
panel_liq <- panel[!is.na(adv20) & adv20 >= 2e8]
cat("After liq filter (adv20>=2e8): rows", nrow(panel_liq), " median names/mo", median(panel_liq[,.N,by=ym]$N), "\n\n")

ic_tab <- function(dt, sigcol, label) {
  d <- dt[!is.na(get(sigcol)) & !is.na(fwd_ret)]
  ic_m <- d[, .(ic = cor(get(sigcol), fwd_ret, method="spearman"), n=.N), by=ym][n>=20]
  ic_m[, yr := as.integer(substr(ym,1,4))]
  f <- function(sub) {
    if(nrow(sub)==0) return(c(NA,NA,NA))
    m <- mean(sub$ic); s <- sd(sub$ic); t <- m/s*sqrt(nrow(sub))
    c(mean_ic=m, icir=m/s, t=t)
  }
  full <- f(ic_m); post <- f(ic_m[yr>=2018]); pre <- f(ic_m[yr<2018])
  cat(sprintf("%-14s | FULL ic=%+.4f icir=%+.3f t=%+.2f (n=%d) | POST2018 ic=%+.4f t=%+.2f (n=%d) | PRE2018 ic=%+.4f t=%+.2f\n",
    label, full[1],full[2],full[3], nrow(ic_m), post[1],post[3], nrow(ic_m[yr>=2018]), pre[1],pre[3]))
  invisible(ic_m)
}
cat("=== Cross-sectional rank-IC (signal @ t -> fwd 1M return), liq-filtered ===\n")
ic_tab(panel_liq, "z_basis_pct", "basis_pct")
ic_tab(panel_liq, "z_oi_chg",    "oi_change")
ic_tab(panel_liq, "z_basis_mom", "basis_mom")
cat("\n=== Same, NO liq filter (full cross-section) ===\n")
ic_tab(panel, "z_basis_pct", "basis_pct")
ic_tab(panel, "z_oi_chg",    "oi_change")
ic_tab(panel, "z_basis_mom", "basis_mom")

# decile monotonicity for basis_pct (liq)
cat("\n=== basis_pct decile forward returns (liq, full period) ===\n")
d <- panel_liq[!is.na(z_basis_pct)]
d[, dec := cut(z_basis_pct, breaks=quantile(z_basis_pct, probs=0:5/5, na.rm=T), labels=1:5, include.lowest=T), by=ym]
print(d[, .(mean_fwd=mean(fwd_ret,na.rm=T)*100, n=.N), by=dec][order(dec)])
saveRDS(panel_liq, file.path(TMP,"wt008_panel_liq.rds"))
