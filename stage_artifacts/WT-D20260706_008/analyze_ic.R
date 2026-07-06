suppressPackageStartupMessages({library(data.table); library(arrow)})
source("02_Infrastructure/config.R")
OUT <- "stage_artifacts/WT-D20260706_008"

snap <- as.data.table(read_parquet(file.path(OUT,"stockfut_monthend_raw.parquet")))
snap[, me_date := as.Date(me_date)]

# ---- RAWDATA: monthly panel with forward returns ----
rd <- as.data.table(read_parquet(".cache/RAWDATA.parquet",
  col_select=c("Date","Ticker","Name","K200","KQ150","Close","Vol","Ret")))
rd[, Date := as.Date(Date)]
rd <- rd[Date >= as.Date("2015-11-01")]
setorder(rd, Ticker, Date)
rd[, ym := format(Date, "%Y-%m")]
# month-end row per ticker
me_rd <- rd[, .SD[.N], by=.(Ticker, ym)]  # last obs per ticker-month
me_rd[, nname := gsub("[[:space:]]+","", Name)]
# 20d avg trade value (liquidity) at month-end: approximate using Vol (daily trade value) rolling 20
setorder(rd, Ticker, Date)
rd[, adv20 := frollmean(Vol, 20, align="right"), by=Ticker]
adv_me <- rd[, .SD[.N], by=.(Ticker, ym)][, .(Ticker, ym, adv20)]
me_rd <- merge(me_rd, adv_me, by=c("Ticker","ym"), all.x=TRUE)

# monthly close -> forward 1M return
mc <- rd[, .(mclose = last(Close), me_dt = last(Date)), by=.(Ticker, ym)]
setorder(mc, Ticker, me_dt)
mc[, fwd_ret := shift(mclose, -1)/mclose - 1, by=Ticker]  # next month return (t -> t+1)
me_rd <- merge(me_rd, mc[, .(Ticker, ym, fwd_ret)], by=c("Ticker","ym"), all.x=TRUE)

# ---- Alias table for futures->rawdata name mismatches ----
alias <- c(
  "POSCO홀딩스"="POSCO홀딩스", "케이티앤지"="KT&G", "신한지주"="신한금융지주",
  "하나금융지주"="하나금융지주","우리금융지주"="우리금융지주","JB금융지주"="JB금융지주",
  "BNK금융지주"="BNK금융지주","메리츠금융지주"="메리츠금융지주","한국금융지주"="한국금융지주",
  "삼성SDS"="삼성에스디에스","와이지엔터"="와이지엔터테인먼트","JYPEnt"="JYPEnt.",
  "한국가스"="한국가스공사","롯데지주"="롯데지주","코오롱인더스트리"="코오롱인더스트리",
  "롯데칠성음료"="롯데칠성","아모레퍼시픽홀딩스"="아모레퍼시픽홀딩스"
)
# We'll match by normalized name directly; alias applied as fallback
snap[, nname := gsub("[[:space:]]+","", underlying)]
snap[, ym := format(me_date, "%Y-%m")]

# Build per-month name->ticker from me_rd (PIT: same month)
map_by_month <- me_rd[, .(Ticker, ym, nname, K200, KQ150, adv20, fwd_ret)]
# direct join
j <- merge(snap, map_by_month, by=c("ym","nname"), all.x=TRUE)
matched_direct <- j[!is.na(Ticker), .N]
# alias fallback for unmatched
unm <- j[is.na(Ticker)]
cat("Direct name match rows:", matched_direct, "/", nrow(snap), "\n")
cat("Unmatched rows:", nrow(unm), "\n")
cat("Distinct unmatched underlyings:", uniqueN(unm$underlying), "\n")
cat("Top unmatched underlyings:\n")
print(unm[, .N, by=underlying][order(-N)][1:20])

saveRDS(j, file.path("C:/Users/99922/AppData/Local/Temp/claude","wt008_joined.rds"))
saveRDS(me_rd, file.path("C:/Users/99922/AppData/Local/Temp/claude","wt008_merd.rds"))
cat("\nSaved joined panel.\n")
