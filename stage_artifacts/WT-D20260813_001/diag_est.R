suppressWarnings(suppressMessages({library(data.table);library(arrow)}))
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
source("02_Infrastructure/portfolio/hrp_core.R")
apkg <- jsonlite::fromJSON("qepm/mailbox/worktask/WT-D20260813_001/alpha_package.json")
tickers <- names(apkg$alpha_vector)
ds <- open_dataset(".cache/RAWDATA.parquet")
rd <- as.data.table(dplyr::collect(dplyr::select(dplyr::filter(ds, Ticker %in% tickers), Date,Ticker,Ret)))
rd[,Date:=as.Date(Date)]; rd[,ym:=format(Date,"%Y-%m")]; rd[,g:=1+ifelse(is.na(Ret),0,Ret)]
m <- rd[,.(mret=prod(g)-1),by=.(Ticker,ym)]; m<-m[ym<="2026-07"]
w <- dcast(m, ym~Ticker, value.var="mret"); setorder(w,ym)
mat <- as.matrix(w[,..tickers]); rownames(mat)<-w$ym
cc <- mat[complete.cases(mat),,drop=FALSE]   # 25 x 25
sink("stage_artifacts/WT-D20260813_001/diag_est.txt")
cat("complete-case dim:", dim(cc), "\n")
cn <- function(C){ev<-eigen((C+t(C))/2,symmetric=TRUE,only.values=TRUE)$values; c(cond=max(ev)/max(min(ev),1e-12),mineig=min(ev))}
for(mm in c("sample","ledoit_wolf","lw_nls","gerber_rmt")){
  o <- tryCatch(.get_cor_cov(cc, cov_method=mm), error=function(e) paste("ERR",conditionMessage(e)))
  if(is.character(o)){cat(mm, o, "\n"); next}
  st <- cn(o$cov); cat(sprintf("%-12s cond=%.3e mineig=%.5f\n", mm, st["cond"], st["mineig"]))
}
# Also test on 60m pairwise as before for comparison
sink()
