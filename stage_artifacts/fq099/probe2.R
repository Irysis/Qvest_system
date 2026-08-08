suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
say <- function(fmt,...) cat(sprintf(paste0("[099] ",fmt,"\n"),...))
D <- as.data.table(read_parquet(".cache/fundamental_merged.parquet"))
say("--- Period 형태 x Source (상위) ---")
D[, pshape := gsub("[0-9]","#",as.character(Period))]
print(D[, .N, by=.(Source, pshape)][order(-N)][1:14])
say("--- Period 예시 ---")
for (s in unique(D$Source)) say("  %-13s : %s", s, paste(head(sort(unique(D[Source==s]$Period)),4), collapse=" | "))
say("--- Item 상위 12 (Source별 유무) ---")
it <- D[, .N, by=Item][order(-N)][1:12]
print(dcast(D[Item %in% it$Item, .N, by=.(Item,Source)], Item~Source, value.var="N", fill=0))
say("--- 같은 Ticker-Item-Factor_Date 에 Source 2개 이상 공존? ---")
cs <- D[, .(nsrc=uniqueN(Source)), by=.(Ticker,Item,Factor_Date)]
print(cs[, .N, by=nsrc][order(nsrc)])
