suppressPackageStartupMessages(library(jsonlite))
setwd(Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
`%||%` <- function(a,b) if (is.null(a)||length(a)==0L) b else a
h <- fromJSON("06_Registry/hypothesis_index.json", simplifyVector = FALSE)
e <- h$entries
cat("coverage keys:", paste(names(h$coverage), collapse=", "), "\n")
cat("n_entries:", length(e), "\n")
cat("--- entry 필드명 빈도 ---\n")
fn <- table(unlist(lapply(e, names)))
print(head(sort(fn, decreasing=TRUE), 25))
cat("--- 샘플 entry (마지막) ---\n")
cat(toJSON(e[[length(e)]], auto_unbox=TRUE, pretty=TRUE), "\n")
## in-flight 표기 탐색 (양성 대조: 문자열 fixed 검색, \\b 미사용)
st <- vapply(e, function(x) as.character(x$status %||% ""), character(1))
cat("--- status 분포 ---\n"); print(head(sort(table(st), decreasing=TRUE), 15))
hit <- grep("in_flight", st, fixed=TRUE)
cat("status 에 in_flight:", length(hit), "\n")
blob <- vapply(e, function(x) paste(unlist(x), collapse=" "), character(1))
cat("★blob 전체에서 in_flight 포함 entry:", sum(grepl("in_flight", blob, fixed=TRUE)), "\n")
cat("★양성 대조 — blob 에서 'M26' 포함:", sum(grepl("M26", blob, fixed=TRUE)),
    " / 'revenue':", sum(grepl("revenue", blob, fixed=TRUE)),
    " / 'Revenue':", sum(grepl("Revenue", blob, fixed=TRUE)),
    " / 'WT-D2026' :", sum(grepl("WT-D2026", blob, fixed=TRUE)), "\n")
