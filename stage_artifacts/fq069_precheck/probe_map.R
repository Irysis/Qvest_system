suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
R <- as.data.table(read_parquet(".cache/RAWDATA.parquet", col_select=c("Date","Ticker","Sector","Size","K200","KQ150")))
R[, Date := as.Date(Date)]
U <- R[Date>=as.Date("2015-01-01") & (K200==TRUE|KQ150==TRUE) & !is.na(Size)]
sec <- U[!is.na(Sector), .(종목수=uniqueN(Ticker)), by=Sector][order(-종목수)]
cat(sprintf("RAWDATA Sector %d종:\n", nrow(sec))); print(sec, nrows=40)
B <- as.data.table(read_parquet("stage_artifacts/fq069_precheck/fq069_bsi.parquet"))
ind <- unique(B[bsi=="업황전망", .(ITEM_CODE2, ITEM_NAME2)])[order(ITEM_CODE2)]
cat(sprintf("\nBSI 업종 %d종:\n", nrow(ind))); print(ind, nrows=50)
