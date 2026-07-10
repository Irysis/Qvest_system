suppressMessages({library(arrow); library(data.table)})
setDTthreads(1)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
p <- readRDS(file.path(ROOT,"stage_artifacts","WT-D20260710_001","panel.rds"))
p <- as.data.table(p)
cat("panel.rds cols:", paste(names(p),collapse=", "),"\n\n")
cat("rows:",nrow(p)," dates:",length(unique(p$Date))," range:",as.character(min(p$Date)),"..",as.character(max(p$Date)),"\n")
cat("V02_EP coverage:", round(mean(!is.na(p$V02_EP)),3), " M08 cov:", round(mean(!is.na(p$M08_Residual_Mom)),3),
    " score_eff cov:", round(mean(!is.na(p$score_eff)),3), " Ret_1m cov:", round(mean(!is.na(p$Ret_1m)),3),"\n")
cat("tiers:", paste(names(table(p$tier)),table(p$tier),collapse=" | "),"\n")
# DART buyback event date parse check
bb <- as.data.table(read_parquet(file.path(ROOT,".cache","dart","buyback_decisions_clean.parquet")))
bb[, rcept_dt := as.Date(substr(rcept_no,1,8), format="%Y%m%d")]
cat("\nbuyback rcept_dt range:", as.character(min(bb$rcept_dt,na.rm=TRUE)),"..",as.character(max(bb$rcept_dt,na.rm=TRUE)),
    " n_events:",nrow(bb)," parse_ok:",sum(!is.na(bb$rcept_dt)),"\n")
cat("events by year:\n"); print(table(format(bb$rcept_dt,"%Y")))
# ticker format compat: panel Ticker vs bb Ticker
cat("\npanel Ticker sample:", paste(head(unique(p$Ticker),3),collapse=",")," | bb Ticker sample:", paste(head(unique(bb$Ticker),3),collapse=","),"\n")
cat("bb tickers in panel univ:", length(intersect(unique(bb$Ticker), unique(p$Ticker))),"/",length(unique(bb$Ticker)),"\n")
