suppressPackageStartupMessages({library(data.table); library(arrow)})
source("02_Infrastructure/config.R")
OUT <- "stage_artifacts/WT-D20260706_008"; TMP <- "C:/Users/99922/AppData/Local/Temp/claude"
norm <- function(x) gsub("[[:space:]]+","", x)
snap <- as.data.table(read_parquet(file.path(OUT,"stockfut_monthend_raw.parquet")))
snap[, me_date := as.Date(me_date)]; snap[, nname := norm(underlying)]; snap[, ym := format(me_date,"%Y-%m")]
rd <- as.data.table(read_parquet(".cache/RAWDATA.parquet",
  col_select=c("Date","Ticker","Name","K200","KQ150","Close","Vol","Ret","Sector")))
rd[, Date := as.Date(Date)]; rd <- rd[Date >= as.Date("2015-11-01")]
setorder(rd, Ticker, Date)
rd[, trade_val := Vol * Close]  # KRW trade value = shares * price
rd[, ym := format(Date,"%Y-%m")]

latest <- rd[Date==max(Date) & !is.na(Name) & Name!=""]; latest[, nname := norm(Name)]
name2tk <- unique(latest[, .(nname, Ticker)])
dup <- name2tk[, .N, by=nname][N>1, nname]; name2tk <- name2tk[!nname %in% dup]
alias <- data.table(
  fut=c("POSCO홀딩스","케이티앤지","삼성SDS","와이지엔터","JYPEnt","한국가스","롯데칠성음료","NC","한온시스템"),
  rd =c("POSCO홀딩스","KT&G","삼성에스디에스","와이지엔터테인먼트","JYPEnt.","한국가스공사","롯데칠성","엔씨소프트","한온시스템"))
snap <- merge(snap, alias, by.x="nname", by.y="fut", all.x=TRUE)
snap[, rd_nname := fifelse(!is.na(rd), rd, nname)]
snap <- merge(snap, name2tk, by.x="rd_nname", by.y="nname", all.x=TRUE)

# monthly panel: close (month-end), fwd 1M ret, adv20 in KRW, membership, sector
mc <- rd[, .(mclose=last(Close), me_dt=last(Date),
             adv20=mean(tail(trade_val,20),na.rm=TRUE),
             K200=last(K200), KQ150=last(KQ150), Sector=last(Sector)), by=.(Ticker, ym)]
setorder(mc, Ticker, me_dt)
mc[, fwd_ret := shift(mclose,-1)/mclose - 1, by=Ticker]
panel <- merge(snap[!is.na(Ticker)], mc, by=c("Ticker","ym"), all.x=TRUE)
panel <- panel[!is.na(fwd_ret)]
saveRDS(panel, file.path(TMP,"wt008_panel.rds"))
cat("Panel rows:", nrow(panel), " months:", uniqueN(panel$ym), "\n")
cat("adv20 (KRW) summary:\n"); print(summary(panel$adv20))
cat("liq>=2e8 rows:", panel[adv20>=2e8,.N], " median names/mo (liq):", median(panel[adv20>=2e8,.N,by=ym]$N),"\n")
