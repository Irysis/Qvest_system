suppressPackageStartupMessages(library(data.table))
D <- fread("04_Research/strategies/RF_B2_9_MinVarLW/lw_diagnostics.csv")[Date>=as.Date("2005-01-01")]
D[, yr := year(Date)]
a <- D[, .(n=.N, minvar=sum(mode=="MINVAR_LW"), fb_pct=round(100*mean(mode!="MINVAR_LW"))), by=yr]
b <- D[mode=="MINVAR_LW", .(delta=round(median(delta),3), cond=round(median(cond),1), erank=round(median(erank),1), rho_sh=round(median(rho_shrunk),3), wmax=round(median(w_max),3), nobs=as.numeric(median(n_obs))), by=yr]
print(merge(a,b,by="yr",all.x=TRUE))
