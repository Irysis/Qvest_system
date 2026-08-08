suppressPackageStartupMessages({ library(data.table); library(httr); library(jsonlite) })
ROOT <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
source("02_Infrastructure/config.R")
say <- function(fmt,...) cat(sprintf(paste0("[069] ",fmt,"\n"),...))
key <- Sys.getenv("ECOS_API_KEY")
if (!nzchar(key)) { source("02_Infrastructure/data/data_collector_ecos.R"); key <- ECOS_API_KEY }
## BSI 통계표 탐색
u <- sprintf("https://ecos.bok.or.kr/api/StatisticTableList/%s/json/kr/1/1500/", key)
r <- GET(u, timeout(40)); j <- fromJSON(content(r,"text",encoding="UTF-8"))
d <- as.data.table(j$StatisticTableList$row)
hit <- d[grepl("기업경기|실사|BSI", STAT_NAME)]
say("BSI 관련 통계표 %d건:", nrow(hit))
print(unique(hit[, .(STAT_CODE, STAT_NAME, CYCLE)]))
