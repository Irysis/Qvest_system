## hypothesis_index 재빌드 — in-flight WT 인덱싱 (병렬 중복실행 방지 SOT)
setwd(Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
source("02_Infrastructure/tools/hypothesis_index.R")
before <- tryCatch(length(jsonlite::fromJSON("06_Registry/hypothesis_index.json",
            simplifyVector=FALSE)$entries), error=function(e) NA_integer_)
cat(sprintf("[hi] ★입력 실측: 재빌드 전 entries = %s\n", before))
res <- build_hypothesis_index()
h <- jsonlite::fromJSON("06_Registry/hypothesis_index.json", simplifyVector=FALSE)
cat(sprintf("[hi] 재빌드 후 entries = %d (증분 %+d)\n", length(h$entries), length(h$entries)-before))
cat(sprintf("[hi] coverage wt_inflight_indexed = %s\n", h$coverage$wt_inflight_indexed))
blob <- vapply(h$entries, function(x) paste(unlist(x), collapse=" "), character(1))
cat(sprintf("[hi] ★in-flight 등재 확인 — 'WT-D20260808_002' 포함 entry = %d (양성 대조 'WT-D2026' = %d)\n",
    sum(grepl("WT-D20260808_002", blob, fixed=TRUE)), sum(grepl("WT-D2026", blob, fixed=TRUE))))
hit <- which(grepl("WT-D20260808_002", blob, fixed=TRUE))
for (i in hit) cat(sprintf("[hi]   %s | %s | verdict=%s\n",
    h$entries[[i]]$strategy_id, substr(h$entries[[i]]$title,1,70), h$entries[[i]]$verdict))
