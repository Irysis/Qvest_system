suppressWarnings(suppressMessages({library(data.table);library(arrow)}))
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
apkg <- jsonlite::fromJSON("qepm/mailbox/worktask/WT-D20260813_001/alpha_package.json")
tickers <- names(apkg$alpha_vector)
ds <- open_dataset(".cache/RAWDATA.parquet")
rd <- as.data.table(dplyr::collect(dplyr::select(dplyr::filter(ds, Ticker %in% tickers), Date,Ticker,Ret)))
rd[,Date:=as.Date(Date)]; rd[,ym:=format(Date,"%Y-%m")]; rd[,g:=1+ifelse(is.na(Ret),0,Ret)]
m <- rd[,.(mret=prod(g)-1),by=.(Ticker,ym)]
m <- m[ym<="2026-07"]
w <- dcast(m, ym~Ticker, value.var="mret"); setorder(w,ym)
mat <- as.matrix(w[,..tickers]); rownames(mat)<-w$ym
sink("stage_artifacts/WT-D20260813_001/diag_win.txt")
for(L in c(60,84,120,160,200)){
  sub <- tail(mat,L); cc<-sum(complete.cases(sub))
  cat(sprintf("window %d months: complete-case rows=%d  (min per-ticker cov=%d)\n",L,cc,min(colSums(!is.na(sub)))))
}
for(t in c("A295310","A420770","A402340","A319660","A323280")) cat(t, w$ym[which(!is.na(w[[t]]))[1]],"\n")
sink()
