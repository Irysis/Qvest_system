suppressPackageStartupMessages({ library(jsonlite); library(data.table) })
setwd(Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
say <- function(fmt,...) cat(sprintf(paste0("[099d1b] ",fmt,"\n"),...))
un <- fread("stage_artifacts/fq099/fq099d1_unmentioned.csv")$code
reg <- fromJSON("02_Infrastructure/factor_db/factor_registry.json", simplifyVector=FALSE)
say("언급 0회 %d건에 대해 dedup/lifecycle 실태 확인", length(un))
rows <- rbindlist(lapply(un, function(k){
  f <- reg[[k]]
  dd <- f$dedup; lc <- f$lifecycle
  ddtxt <- if (is.null(dd)) "" else paste(unlist(dd), collapse=" ")
  lctxt <- if (is.null(lc)) "" else paste(unlist(lc), collapse=" ")
  data.table(code=k,
             dedup_flag = nzchar(ddtxt) && !grepl("none|없음|null|NA", ddtxt, ignore.case=TRUE),
             lifecycle  = substr(lctxt,1,40),
             dedup_txt  = substr(ddtxt,1,110))
}))
say("--- dedup 기재가 있는 항목 ---")
d <- rows[dedup_flag==TRUE]
say("  %d / %d 건", nrow(d), nrow(rows))
if (nrow(d)) for (i in seq_len(nrow(d))) say("  %-30s %s", d$code[i], d$dedup_txt[i])
say("--- lifecycle 값 분포 ---")
print(rows[, .N, by=lifecycle][order(-N)][1:8])
say("★깨끗한 미탐색(중복기재 없음) = %d건", nrow(rows[dedup_flag==FALSE]))
fwrite(rows, "stage_artifacts/fq099/fq099d1b_dedup.csv")
