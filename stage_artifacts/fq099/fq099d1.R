suppressPackageStartupMessages({ library(jsonlite); library(data.table) })
setwd(Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
say <- function(fmt,...) cat(sprintf(paste0("[099d1] ",fmt,"\n"),...))
flow <- readLines("stage_artifacts/fq099/flow_dependent_factors.txt")
ment <- if (file.exists("stage_artifacts/fq099/fq099d_mentioned.txt")) readLines("stage_artifacts/fq099/fq099d_mentioned.txt") else character(0)
un <- setdiff(flow, ment)
say("언급 0회 %d건 대상", length(un))
reg <- fromJSON("02_Infrastructure/factor_db/factor_registry.json", simplifyVector=FALSE)
## 등재 시점 후보 필드 탐색 (필드명 추측 금지 — 실제 키를 본다)
keys <- unique(unlist(lapply(reg[flow], names)))
say("레지스터리 팩터 키 %d종: %s", length(keys), paste(head(keys,25), collapse=" "))
dcand <- grep("date|added|created|since|version|vintage|introduc", keys, ignore.case=TRUE, value=TRUE)
say("시점 후보 필드: %s", if(length(dcand)) paste(dcand, collapse=" ") else "★없음")
## 대안 축: evidence_tier / labels 로 성숙도 판정
say("--- 언급 0회 40건의 라벨 분포 ---")
rows <- rbindlist(lapply(un, function(k) {
  f <- reg[[k]]; if (is.null(f)) return(data.table(code=k, cat="미등재", ev=NA_character_, cap=NA_character_))
  lb <- f$labels
  data.table(code=k,
             cat = if (!is.null(f$category)) f$category else "?",
             ev  = if (!is.null(lb$evidence_tier)) as.character(lb$evidence_tier) else NA_character_,
             cap = if (!is.null(lb$capacity)) as.character(lb$capacity) else NA_character_)
}))
print(rows[, .N, by=.(cat, ev)][order(-N)])
say("--- 카테고리별 언급0 목록 ---")
for (c0 in sort(unique(rows$cat))) say("  %-10s %2d건: %s", c0, rows[cat==c0,.N], paste(rows[cat==c0]$code, collapse=" "))
fwrite(rows, "stage_artifacts/fq099/fq099d1_unmentioned.csv")
say("저장 → stage_artifacts/fq099/fq099d1_unmentioned.csv")
