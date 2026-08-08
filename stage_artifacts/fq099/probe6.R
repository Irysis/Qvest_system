suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
say <- function(fmt,...) cat(sprintf(paste0("[099] ",fmt,"\n"),...))
PL <- c("Revenue","COGS","GrossProfit","SGAExpense","OperatingProfit","PretaxIncome","TaxExpense",
        "InterestExp","NetInterestExp","TotalNetInterestExp","InterestIncome","DepAmort","RandD",
        "OrdRandD","OperatingCF","InvestCF","FinanceCF","Dividends","FCF1","FCF2")
D <- as.data.table(read_parquet(".cache/fundamental_merged.parquet"))
D[, mm := substr(as.character(Period),5,6)]

say("=== A. 유량 항목의 소스 구성 (병합 후 실제로 이긴 소스) ===")
A <- D[Item %in% PL, .N, by=.(Item, Source)]
print(dcast(A, Item~Source, value.var="N", fill=0))

say("=== B. 12월 셀에서 DART 가 이긴 유량 항목 ===")
B <- D[Item %in% PL & mm=="12", .N, by=.(Item,Source)]
print(dcast(B, Item~Source, value.var="N", fill=0))

say("=== C. 스케일 교대 실측: DART가 12월을 이긴 항목의 Dec/Sep 비율 ===")
for (itm in c("COGS","DepAmort","Dividends")) {
  S <- D[Item==itm & Value>0 & mm %in% c("09","12")]
  if (!nrow(S)) { say("  %s: 데이터 없음", itm); next }
  S[, yr := as.integer(substr(as.character(Period),1,4))]
  s9  <- S[mm=="09", .(Ticker,yr,v09=Value)]
  s12 <- S[mm=="12", .(Ticker,yr,v12=Value,src12=Source)]
  w <- merge(s9, s12, by=c("Ticker","yr"))
  if (!nrow(w)) { say("  %s: 병합 0행", itm); next }
  w[, ratio := v12/v09]
  say("  --- %s ---", itm)
  print(w[, .(n=.N, Dec_Sep_중앙값=round(median(ratio),3),
              q25=round(quantile(ratio,.25),2), q75=round(quantile(ratio,.75),2)), by=.(src12)][order(src12)])
}

say("=== D. TTM 파일 소비자 ===")
say("  fundamental_xlsx_ttm.parquet 존재: %s", file.exists(".cache/fundamental_xlsx_ttm.parquet"))
