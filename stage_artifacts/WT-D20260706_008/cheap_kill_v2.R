suppressPackageStartupMessages({library(data.table)})
source("02_Infrastructure/config.R")
TMP <- "C:/Users/99922/AppData/Local/Temp/claude"
panel <- readRDS(file.path(TMP,"wt008_panel.rds")); setDT(panel)
setorder(panel, Ticker, ym)
cat("Panel rows:", nrow(panel), " months:", uniqueN(panel$ym), "\n")
cat("adv20 median (KRW):", median(panel$adv20,na.rm=T), "\n")
cat("liq(adv20>=2e8) rows:", panel[adv20>=2e8,.N]," median names/mo:", median(panel[adv20>=2e8,.N,by=ym]$N),"\n\n")

panel[, oi_chg := tot_oi/shift(tot_oi,1)-1, by=Ticker]
panel[, basis_mom := basis_pct - shift(basis_pct,1), by=Ticker]
wins <- function(x,k=3){m<-mean(x,na.rm=T);s<-sd(x,na.rm=T);pmin(pmax(x,m-k*s),m+k*s)}
for(v in c("basis_pct","oi_chg","basis_mom")) panel[, (paste0("z_",v)):=wins(get(v)), by=ym]
panel[, yr := as.integer(substr(ym,1,4))]
pl <- panel[adv20>=2e8]   # liq-filtered

ic_tab <- function(dt, sigcol, label){
  d <- dt[!is.na(get(sigcol)) & !is.na(fwd_ret)]
  ic_m <- d[, .(ic=cor(get(sigcol),fwd_ret,method="spearman"),n=.N), by=ym][n>=20]
  ic_m[, yr:=as.integer(substr(ym,1,4))]
  f <- function(s){ if(nrow(s)<3) return(c(NA,NA,NA)); m<-mean(s$ic);sd_<-sd(s$ic); c(m, m/sd_, m/sd_*sqrt(nrow(s))) }
  fu<-f(ic_m); po<-f(ic_m[yr>=2018])
  cat(sprintf("%-12s | FULL ic=%+.4f icir=%+.3f t=%+.2f (n=%d) | POST2018 ic=%+.4f t=%+.2f (n=%d)\n",
    label, fu[1],fu[2],fu[3],nrow(ic_m), po[1],po[3],nrow(ic_m[yr>=2018])))
  invisible(ic_m)
}
cat("=== rank-IC LIQ-FILTERED (adv20>=2e8, K200∪KQ150 futures underlyings) ===\n")
ic_tab(pl,"z_basis_pct","basis_pct"); ic_tab(pl,"z_oi_chg","oi_change"); ic_tab(pl,"z_basis_mom","basis_mom")
cat("\n=== rank-IC NO liq filter ===\n")
ic_tab(panel,"z_basis_pct","basis_pct"); ic_tab(panel,"z_oi_chg","oi_change"); ic_tab(panel,"z_basis_mom","basis_mom")

# quintile monotonicity (liq)
cat("\n=== basis_pct quintile fwd returns (liq) ===\n")
d <- pl[!is.na(z_basis_pct)]
d[, q := as.integer(cut(frank(z_basis_pct)/.N, breaks=0:5/5, labels=1:5, include.lowest=T)), by=ym]
print(d[!is.na(q), .(mean_fwd_pct=round(mean(fwd_ret,na.rm=T)*100,3), n=.N), by=q][order(q)])
saveRDS(panel, file.path(TMP,"wt008_panel_sig.rds"))
