# Page-1 census: total_count per universe firm -> exact full-fetch call cost (light, ~348 calls)
suppressPackageStartupMessages({library(data.table); library(httr); library(jsonlite)})
setDTthreads(1)
`%||%` <- function(a,b) if(is.null(a)||length(a)==0) b else a
key <- sub("^DART_API_KEY=","", grep("^DART_API_KEY=", readLines(".env",warn=FALSE), value=TRUE)[1])
U <- fread(".cache/dart/universe_corpcodes.csv", colClasses="character")
cat("universe firms:", nrow(U), "\n")

page1 <- function(corp_code, bgn="20050101", end="20260710") {
  r <- tryCatch(GET("https://opendart.fss.or.kr/api/list.json",
           query=list(crtfc_key=key, corp_code=corp_code, bgn_de=bgn, end_de=end,
                      page_no=1, page_count=100), timeout(30)),
           error=function(e) NULL)
  Sys.sleep(1.0)
  if (is.null(r) || status_code(r)!=200) return(list(status="HTTP", tc=NA, tp=NA))
  p <- tryCatch(fromJSON(content(r,"text",encoding="UTF-8"), flatten=TRUE), error=function(e) NULL)
  if (is.null(p) || is.null(p$status)) return(list(status="PARSE", tc=NA, tp=NA))
  if (p$status=="013") return(list(status="013_nodata", tc=0, tp=0))       # no disclosures
  if (p$status!="000") return(list(status=p$status, tc=NA, tp=NA))
  list(status="000", tc=as.integer(p$total_count %||% NA), tp=as.integer(p$total_page %||% NA),
       cls=if(!is.null(p$list)&&nrow(as.data.table(p$list))>0) as.data.table(p$list)$corp_cls[1] else NA)
}

res <- vector("list", nrow(U))
q429 <- 0L
for (i in seq_len(nrow(U))) {
  o <- page1(U$corp_code[i])
  res[[i]] <- data.table(corp_code=U$corp_code[i], ticker=U$ticker[i], stock=U$stock_code[i],
                         status=o$status, total_count=o$tc %||% NA, total_page=o$tp %||% NA,
                         cls=o$cls %||% NA)
  if (identical(o$status,"020")||identical(o$status,"429")) { q429 <- q429+1L; if(q429>=3){cat("QUOTA HIT — abort census\n"); break} }
  if (i %% 50 == 0) cat("  ...", i, "/", nrow(U), " (last tc=", o$tc %||% NA, ")\n")
}
R <- rbindlist(res, fill=TRUE)
fwrite(R, "stage_artifacts/WT-D20260710_005/census_cost.csv")
cat("\n=== CENSUS SUMMARY ===\n")
cat("firms queried:", nrow(R), " status000:", sum(R$status=="000",na.rm=T), " nodata:", sum(R$status=="013_nodata",na.rm=T), "\n")
ok <- R[status=="000" & is.finite(total_page)]
cat("total_page dist (calls per firm for full history):\n")
print(summary(ok$total_page))
cat("SUM total_page (= full-fetch call budget):", sum(ok$total_page), "\n")
cat("total_count dist:\n"); print(summary(ok$total_count))
cat("corp_cls:\n"); print(R[, .N, by=cls])
