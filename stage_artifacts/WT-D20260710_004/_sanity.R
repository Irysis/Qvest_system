suppressMessages({library(arrow); library(data.table)})
setDTthreads(1)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
panel <- as.data.table(readRDS(file.path(ROOT,"stage_artifacts","WT-D20260710_001","panel.rds")))
bb <- as.data.table(read_parquet(file.path(ROOT,".cache","dart","buyback_decisions_clean.parquet")))
bb[, rcept_dt := as.Date(substr(rcept_no,1,8), format="%Y%m%d")]
bb <- bb[!is.na(rcept_dt) & Ticker %in% unique(panel$Ticker)]
# A5 sanity: how many unique band-stocks are fresh-buyback; distinct firms doing buybacks in band
Sb <- panel[!is.na(score_eff), .(Date,Ticker,score=score_eff,adv=tv20)]
Sb <- Sb[is.na(adv)|adv>=2e8]; setorder(Sb, Date, -score); Sb[, rk:=seq_len(.N), by=Date]
band <- Sb[rk>=21 & rk<=40 & Date>=as.Date("2015-01-01")]
ev <- unique(bb[, .(Ticker, rcept_dt)])
band[, fresh_bb := FALSE]
for(i in seq_len(nrow(band))){
  e <- ev[Ticker==band$Ticker[i] & rcept_dt<=band$Date[i]]
  if(nrow(e)>0 && as.numeric(band$Date[i]-max(e$rcept_dt))/30.44 <= 3) band$fresh_bb[i] <- TRUE
}
cat("band stock-months 2015+:", nrow(band), " fresh_bb:", sum(band$fresh_bb),
    " distinct fresh firms:", length(unique(band[fresh_bb==TRUE]$Ticker)),
    " distinct band firms:", length(unique(band$Ticker)), "\n")
# A3 sparseness: how many months have >=8 names in a MEGA/MID age bucket
cat("MEGA names/month median:", median(panel[tier=='MEGA',.N,by=Date]$N),
    " MID:", median(panel[tier=='MID',.N,by=Date]$N), "\n")
