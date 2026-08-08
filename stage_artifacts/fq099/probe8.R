suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
say <- function(fmt,...) cat(sprintf(paste0("[099] ",fmt,"\n"),...))
PL <- c("Revenue","COGS","GrossProfit","SGAExpense","OperatingProfit","PretaxIncome","TaxExpense",
        "DepAmort","OperatingCF","InvestCF","FinanceCF","Dividends","InterestExp","InterestIncome","RandD")
D <- as.data.table(read_parquet(".cache/fundamental_merged.parquet"))
D[, `:=`(mm=substr(as.character(Period),5,6), yr=as.integer(substr(as.character(Period),1,4)))]

say("=== A. 이음매: 유량 항목의 소스별 연도 범위 ===")
print(D[Item %in% PL, .(연도=paste0(min(yr),"~",max(yr)), n=.N,
        분기월비중=round(mean(mm!="12"),3)), by=Source][order(Source)])

say("=== B. Revenue 연도별 소스 (2012~2020) ===")
print(dcast(D[Item=="Revenue" & yr %in% 2012:2020, .N, by=.(yr,Source)], yr~Source, value.var="N", fill=0))

say("=== C. 스케일 점프 실측: 같은 종목의 2014 분기평균 vs 2016 DART연간 ===")
for (itm in c("Revenue","OperatingProfit","COGS")) {
  q14 <- D[Item==itm & Source=="XLSX" & yr==2014 & Value>0, .(q=mean(Value)), by=Ticker]
  a16 <- D[Item==itm & Source=="DART"  & yr==2016 & Value>0, .(a=Value[1]),   by=Ticker]
  w <- merge(q14,a16,by="Ticker"); if(!nrow(w)) { say("  %s: 0행",itm); next }
  w[, r := a/q]
  say("  %-16s n=%4d  연간/분기평균 중앙값 = %.2f  (분기값이면 ~1, 연간값이면 ~4)",
      itm, nrow(w), median(w$r))
}

say("=== D. 횡단면 오염: 각 스냅샷에서 최신 유량값의 소스 혼합 ===")
S <- D[Item=="Revenue" & Value>0]
setorder(S, Ticker, Factor_Date)
res <- rbindlist(lapply(seq(as.Date("2015-01-31"), as.Date("2018-12-31"), by="3 months"), function(sd) {
  z <- S[Factor_Date <= sd][, .SD[.N], by=Ticker]
  if (!nrow(z)) return(NULL)
  data.table(sig=sd, n=nrow(z), dart비중=round(mean(z$Source=="DART"),3))
}))
print(res)
