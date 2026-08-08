suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
R <- as.data.table(read_parquet(".cache/RAWDATA.parquet",
      col_select=c("Date","Ticker","Name","Sector_Lv2","Size","K200","KQ150")))
R[, Date := as.Date(Date)]
U <- R[Date >= as.Date("2015-01-01") & (K200==TRUE|KQ150==TRUE) & !is.na(Size)]
S <- U[!is.na(Sector_Lv2) & grepl("반도체|디스플레이패널", Sector_Lv2)]
L <- S[, .(months=uniqueN(format(Date,"%Y-%m")), last=max(Date),
           name=Name[which.max(Date)], lv2=Sector_Lv2[which.max(Date)]), by=Ticker][order(-months)]
cat(sprintf("2015+ 반도체 등장 종목 %d개\n\n", nrow(L)))
print(L[months>=12, .(Ticker, name, lv2, months)], nrows=60)
