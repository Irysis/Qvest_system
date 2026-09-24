suppressMessages({library(arrow);library(data.table)})
m <- as.data.table(read_parquet(".cache/macro_fred.parquet", mmap=FALSE))[Series_ID=="CPIAUCSL"]; m[, Date:=as.Date(Date)]; setorder(m, Date)
m[, yoy := Value/shift(Value,12)-1]
chk <- function(ym, sigd){
  d <- as.data.table(read_parquet(sprintf(".cache/factor_db/factor_db_%s.parquet", ym), mmap=FALSE))[Factor_Name=="RE14_Inflation_YoY"]
  rv <- unique(d$Raw_Value)
  cands <- m[Date >= as.Date(sigd) - 70 & Date <= as.Date(sigd), .(Date, yoy, neg_yoy = -yoy)]
  cat("== sig", sigd, " RE14 Raw_Value(unique):", paste(signif(rv,6), collapse=","), "\n"); print(cands)
}
chk("202003","2020-03-31"); chk("202208","2022-08-31"); chk("202608","2026-08-31")
