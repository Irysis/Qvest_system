## FQ-069 — 업종별 BSI 전망(512Y008) 인출: 사전등록 primary(BA) + secondary(BD/BE/BI)
suppressPackageStartupMessages({ library(data.table); library(httr); library(jsonlite); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT <- file.path(ROOT,"stage_artifacts/fq069_precheck"); source("02_Infrastructure/config.R")
say <- function(fmt,...) cat(sprintf(paste0("[bsi] ",fmt,"\n"),...))
key <- Sys.getenv("ECOS_API_KEY")
if (!nzchar(key)) { source("02_Infrastructure/data/data_collector_ecos.R"); key <- ECOS_API_KEY }

## 512Y008 은 2축(BSI코드 x 업종코드) — StatisticSearch 에 두 item 을 슬래시로 전달
get_bsi <- function(bsi_code, lab) {
  out <- list(); i <- 1L
  repeat {
    u <- sprintf("https://ecos.bok.or.kr/api/StatisticSearch/%s/json/kr/%d/%d/512Y008/M/200909/202612/%s",
                 key, i, i+999L, bsi_code)
    r <- tryCatch(GET(u, timeout(60)), error=function(e) NULL)
    if (is.null(r) || status_code(r)!=200) break
    j <- fromJSON(content(r,"text",encoding="UTF-8")); row <- j$StatisticSearch$row
    if (is.null(row) || !length(row)) break
    d <- as.data.table(row); out[[length(out)+1L]] <- d
    if (nrow(d) < 1000) break
    i <- i + 1000L; if (i > 40000L) break
  }
  if (!length(out)) { say("%s 인출 실패", lab); return(NULL) }
  D <- rbindlist(out, fill=TRUE)
  keep <- intersect(c("TIME","ITEM_CODE1","ITEM_NAME1","ITEM_CODE2","ITEM_NAME2","DATA_VALUE"), names(D))
  D <- D[, ..keep]
  setnames(D, c("TIME","DATA_VALUE"), c("ym","val"), skip_absent=TRUE)
  D[, val := as.numeric(val)]
  D <- D[!is.na(val)]
  D[, bsi := lab]
  say("%-16s %6d행 · 업종 %d · %s~%s", lab, nrow(D),
      uniqueN(D$ITEM_CODE2), min(D$ym), max(D$ym))
  D
}
L <- Filter(Negate(is.null), list(
  get_bsi("BA","업황전망"), get_bsi("BD","신규수주전망"),
  get_bsi("BE","채산성전망"), get_bsi("BI","설비투자전망")))
if (length(L)) { A <- rbindlist(L, fill=TRUE)
  write_parquet(A, file.path(OUT,"fq069_bsi.parquet"))
  say("저장 %d행 · BSI종류 %d · 업종 %d", nrow(A), uniqueN(A$bsi), uniqueN(A$ITEM_CODE2)) }
