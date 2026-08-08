suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
say <- function(fmt,...) cat(sprintf(paste0("[fq068] ",fmt,"\n"),...))
R <- as.data.table(read_parquet(".cache/RAWDATA.parquet",
      col_select=c("Date","Ticker","Name","Sector","Sector_Lv2","Size","K200","KQ150")))
R[, Date := as.Date(Date)]
U <- R[Date >= as.Date("2020-01-01") & (K200==TRUE|KQ150==TRUE) & !is.na(Size) & Size>0]
last <- U[Date == max(Date)]
say("최신월 유니버스 %d종목", nrow(last))
say("--- Sector 상위 12 ---")
print(head(last[, .N, by=Sector][order(-N)], 12))
say("--- 반도체 관련 Sector_Lv2 검색 ---")
sem <- last[grepl("반도체|semi|전자부품|IT부품|디스플레이", paste(Sector, Sector_Lv2), ignore.case=TRUE)]
say("매칭 %d종목", nrow(sem))
if (nrow(sem)) {
  setorder(sem, -Size); sem[, rk_all := match(Ticker, last[order(-Size)]$Ticker)]
  sem[, tier := fifelse(rk_all<=10,"MEGA", fifelse(rk_all<=30,"MID","OTHER"))]
  print(sem[, .(Ticker, Name, Sector_Lv2, tier, rk_all)][1:min(20,.N)])
  say("tier 분포: %s", paste(sprintf("%s=%d", names(table(sem$tier)), table(sem$tier)), collapse=" · "))
  say("★MEGA 제외 가용 종목 = %d (top-25 EW 로 표현 가능한 횡단면)", sum(sem$tier!="MEGA"))
}
