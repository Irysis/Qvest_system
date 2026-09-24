suppressMessages({library(arrow); library(data.table)})
R <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/.cache/"
rd_all <- as.data.table(read_parquet(paste0(R,"RAWDATA.parquet"), col_select=c("Date","Ticker","Ret"), mmap=FALSE)); rd_all[, Date:=as.Date(Date)]
m <- as.data.table(read_parquet(paste0(R,"macro_fred.parquet"), mmap=FALSE)); m[, Date:=as.Date(Date)]; m[, Series:=Series_ID]
mb <- function(MACRO, rd, s){
  rd_monthly <- rd[, .(monthly_ret = prod(1 + Ret, na.rm = TRUE) - 1), by = .(Ticker, YM = format(Date, "%Y-%m"))]
  ms <- MACRO[Series == s & !is.na(Value)]; setorder(ms, Date); ms[, YM := format(Date, "%Y-%m")]
  ms <- ms[, .SD[.N], by = YM]; setorder(ms, YM); ms[, macro_chg := Value - shift(Value, 1)]; ms <- ms[!is.na(macro_chg), .(YM, macro_chg)]
  mg <- merge(rd_monthly, ms, by="YM")[!is.na(monthly_ret) & !is.na(macro_chg)]
  mg[, {if (.N>=12L) {f<-lm.fit(cbind(1,macro_chg),monthly_ret); .(beta=unname(f$coefficients[2]))} else .(beta=NA_real_)}, by=Ticker][!is.na(beta)]
}
for (sg in c("2020-03-31","2022-08-31","2026-08-31")) {
  sig <- as.Date(sg); ym <- format(sig,"%Y%m")
  st <- as.data.table(read_parquet(sprintf("%sfactor_db/factor_db_%s.parquet",R,ym), mmap=FALSE))
  st <- st[Factor_Name %in% c("RE14_Inflation_YoY","MA07_BusinessCycle_Composite","MA01_GDP_Sensitivity","MA02_CPI_Sensitivity")]
  MA <- m[Date <= sig-1L & !is.na(Value)]
  MA_safe <- MA[!(Frequency=="m" & format(Date,"%Y-%m")==format(sig,"%Y-%m"))]
  cpi <- m[Series=="CPIAUCSL"][order(Date)]; cpi[, yoy:=Value/shift(Value,12)-1]
  cat(sprintf("\n== sig %s | stored RE14 = %s | CPI YoY ref=%s: %.6f | ref=prev: %.6f\n", sg,
     paste(signif(unique(st[Factor_Name=="RE14_Inflation_YoY"]$Raw_Value),7),collapse=","),
     format(sig,"%Y-%m"), -cpi[format(Date,"%Y-%m")==format(sig,"%Y-%m")]$yoy,
     -cpi[format(Date,"%Y-%m")==format(seq(as.Date(format(sig,"%Y-%m-01")),by="-1 month",length.out=2)[2],"%Y-%m")]$yoy))
  cat(sprintf("   stored MA07 = %s\n", paste(signif(unique(st[Factor_Name=="MA07_BusinessCycle_Composite"]$Raw_Value),7),collapse=",")))
  rd <- rd_all[Date <= sig & Date >= sig-365]
  for (pr in list(c("MA02_CPI_Sensitivity","CPIAUCSL"), c("MA01_GDP_Sensitivity","INDPRO"))) {
    a <- mb(MA, copy(rd), pr[2]); c <- mb(MA_safe, copy(rd), pr[2])
    x <- merge(st[Factor_Name==pr[1], .(Ticker, stored=Raw_Value)], merge(a[,.(Ticker,A=beta)], c[,.(Ticker,C=beta)], by="Ticker"), by="Ticker")
    cat(sprintf("   %s n=%d exact A=%.3f exact C(safe)=%.3f spearman(A,C)=%.4f topQ changes=%d\n", pr[1], nrow(x),
       mean(abs(x$stored-x$A)<1e-9), mean(abs(x$stored-x$C)<1e-9), cor(x$A,x$C,method="spearman"),
       sum(xor(frank(-x$A)<=nrow(x)/5, frank(-x$C)<=nrow(x)/5))))
  }
}
