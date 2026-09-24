suppressMessages({library(arrow); library(data.table)})
D <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/.cache/factor_db/"
fs <- sort(list.files(D, pattern="^factor_db_[0-9]{6}[.]parquet$"))
res <- rbindlist(lapply(fs, function(f){
  x <- read_parquet(file.path(D,f), col_select=c("Factor_Name"), mmap=FALSE)$Factor_Name
  data.table(ym=substr(f,11,16), D32=sum(x=="D32_Beta_VIX"), MA01=sum(x=="MA01_GDP_Sensitivity"), MA02=sum(x=="MA02_CPI_Sensitivity"), RE14=sum(x=="RE14_Inflation_YoY"), MA07=sum(x=="MA07_BusinessCycle_Composite"))
}))
cat("months:", nrow(res), range(res$ym), "\n")
print(res[, .(D32_months=sum(D32>0), MA01_months=sum(MA01>0), MA02_months=sum(MA02>0), RE14_months=sum(RE14>0), MA07_months=sum(MA07>0))])
print(res[MA02>0, range(ym)]); print(res[MA02==0 & ym>="200601", head(ym,40)])
fwrite(res, "presence.csv")
