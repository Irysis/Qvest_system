suppressPackageStartupMessages({ library(jsonlite); library(data.table) })
setwd(Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
say <- function(fmt,...) cat(sprintf(paste0("[scope] ",fmt,"\n"),...))
flow <- readLines("stage_artifacts/fq099/flow_dependent_factors.txt")
reg <- fromJSON("02_Infrastructure/factor_db/factor_registry.json", simplifyVector=FALSE)
say("★입력 실측: 텍스트매칭 후보 %d건 / 레지스터리 %d", length(flow), length(reg))
r <- rbindlist(lapply(flow, function(k){
  f <- reg[[k]]; if(is.null(f)) return(data.table(code=k, ds="미등재"))
  data.table(code=k, ds=if(is.null(f$data_source)) "?" else as.character(f$data_source))
}))
say("--- data_source 분포 ---"); print(r[, .N, by=ds][order(-N)])
fund <- r[ds=="fundamental"]$code
say("★진짜 영향 범위(data_source=fundamental) = %d / %d 건 (%.1f%% of %d)",
    length(fund), length(flow), 100*length(fund)/length(reg), length(reg))
say("--- 텍스트만 걸린 오탐 ---")
say("  %s", paste(setdiff(flow, fund), collapse=" "))
writeLines(fund, "stage_artifacts/fq099/flow_dependent_TRUE.txt")
## 미탐색 25건도 재필터
cf <- if (file.exists("stage_artifacts/fq099/fq099d1_clean_final.txt")) readLines("stage_artifacts/fq099/fq099d1_clean_final.txt") else character(0)
say("★미탐색 25건 중 data_source=fundamental = %d건", length(intersect(cf, fund)))
say("  제외되는 것: %s", paste(setdiff(cf, fund), collapse=" "))
