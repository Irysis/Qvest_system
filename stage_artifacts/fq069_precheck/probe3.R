suppressPackageStartupMessages({ library(data.table); library(httr); library(jsonlite) })
ROOT <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
source("02_Infrastructure/config.R")
say <- function(fmt,...) cat(sprintf(paste0("[069c] ",fmt,"\n"),...))
key <- Sys.getenv("ECOS_API_KEY")
if (!nzchar(key)) { source("02_Infrastructure/data/data_collector_ecos.R"); key <- ECOS_API_KEY }
out <- list(); i <- 1L
repeat {
  u <- sprintf("https://ecos.bok.or.kr/api/StatisticItemList/%s/json/kr/%d/%d/512Y008", key, i, i+299L)
  r <- GET(u, timeout(30)); j <- fromJSON(content(r,"text",encoding="UTF-8"))
  row <- j$StatisticItemList$row; if (is.null(row) || !length(row)) break
  d <- as.data.table(row); out[[length(out)+1L]] <- d
  if (nrow(d) < 300) break; i <- i + 300L; if (i>2000L) break
}
D <- rbindlist(out, fill=TRUE)
say("전체 항목 %d", nrow(D))
say("--- GRP (BSI 종류) ---")
print(unique(D[, .(GRP_CODE, GRP_NAME)]))
say("--- 업종 항목 (ITEM_CODE 가 C/J 등으로 시작) ---")
ind <- unique(D[grepl("^[A-Z][0-9]", ITEM_CODE) | ITEM_CODE %in% c("99988"), .(ITEM_CODE, ITEM_NAME)])
say("업종 %d개:", nrow(ind))
print(ind, nrows=45)
say("--- 반도체/전자 관련 ---")
print(ind[grepl("반도체|전자|영상|통신|기계|화학|금속", ITEM_NAME)])
