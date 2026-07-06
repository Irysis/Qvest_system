suppressPackageStartupMessages({library(data.table); library(arrow)})
source("02_Infrastructure/config.R")
OUT <- "stage_artifacts/WT-D20260706_008"; TMP <- "C:/Users/99922/AppData/Local/Temp/claude"
norm <- function(x) gsub("[[:space:]]+","", x)

snap <- as.data.table(read_parquet(file.path(OUT,"stockfut_monthend_raw.parquet")))
snap[, me_date := as.Date(me_date)]; snap[, nname := norm(underlying)]; snap[, ym := format(me_date,"%Y-%m")]

rd <- as.data.table(read_parquet(".cache/RAWDATA.parquet",
  col_select=c("Date","Ticker","Name","K200","KQ150","Close","Vol","Ret")))
rd[, Date := as.Date(Date)]; rd <- rd[Date >= as.Date("2015-11-01")]
setorder(rd, Ticker, Date)

# ---- Static name->ticker map from LATEST date where names populated ----
latest <- rd[Date==max(Date) & !is.na(Name) & Name!=""]
latest[, nname := norm(Name)]
name2tk <- unique(latest[, .(nname, Ticker)])
# dedup: if same nname maps to multiple tickers, drop (ambiguous)
dup <- name2tk[, .N, by=nname][N>1, nname]
name2tk <- name2tk[!nname %in% dup]

# ---- Alias table (futures name -> rawdata normalized name) ----
alias <- data.table(
  fut = c("POSCO홀딩스","케이티앤지","신한지주","삼성SDS","와이지엔터","JYPEnt","한국가스",
          "롯데칠성음료","NC","iM금융지주","한온시스템","LG에너지솔루션"),
  rd  = c("POSCO홀딩스","KT&G","신한지주","삼성에스디에스","와이지엔터테인먼트","JYPEnt.","한국가스공사",
          "롯데칠성","엔씨소프트","iM금융지주","한온시스템","LG에너지솔루션"))
# map snap nname -> rd nname via alias, else identity
snap <- merge(snap, alias, by.x="nname", by.y="fut", all.x=TRUE)
snap[, rd_nname := fifelse(!is.na(rd), rd, nname)]
snap <- merge(snap, name2tk, by.x="rd_nname", by.y="nname", all.x=TRUE)
cat("Static-map matched rows:", snap[!is.na(Ticker),.N], "/", nrow(snap),
    " frac:", round(snap[!is.na(Ticker),.N]/nrow(snap),3), "\n")
cat("Distinct matched underlyings:", uniqueN(snap[!is.na(Ticker),underlying]), "\n")
um <- snap[is.na(Ticker), .N, by=underlying][order(-N)]
cat("Top unmatched:\n"); print(head(um,15))

# ---- Monthly panel + forward returns (by Ticker, robust to NA Name) ----
rd[, ym := format(Date,"%Y-%m")]
mc <- rd[, .(mclose=last(Close), me_dt=last(Date),
             adv20=mean(tail(Vol,20),na.rm=TRUE)), by=.(Ticker, ym)]
setorder(mc, Ticker, me_dt)
mc[, fwd_ret := shift(mclose,-1)/mclose - 1, by=Ticker]
# K200/KQ150 membership at each month-end (last obs)
mem <- rd[, .(K200=last(K200), KQ150=last(KQ150)), by=.(Ticker, ym)]
mc <- merge(mc, mem, by=c("Ticker","ym"))

panel <- merge(snap[!is.na(Ticker)], mc, by=c("Ticker","ym"), all.x=TRUE)
panel <- panel[!is.na(fwd_ret)]
cat("\nPanel rows with fwd_ret:", nrow(panel), " months:", uniqueN(panel$ym), "\n")
cat("Panel names/month: median", median(panel[,.N,by=ym]$N), "\n")
saveRDS(panel, file.path(TMP,"wt008_panel.rds"))
cat("Saved panel.\n")
