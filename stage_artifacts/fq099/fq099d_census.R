suppressPackageStartupMessages({ library(jsonlite); library(data.table) })
setwd(Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
say <- function(fmt,...) cat(sprintf(paste0("[099d] ",fmt,"\n"),...))
flow <- readLines("stage_artifacts/fq099/flow_dependent_factors.txt")
say("유량의존 팩터 %d건 대상", length(flow))

blobs <- list()
for (f in c("hypothesis_index"="06_Registry/hypothesis_index.json",
            "knowledge_index" ="06_Registry/knowledge_index.json",
            "distilled"       ="06_Registry/distilled_knowledge.json",
            "frontier_queue"  ="06_Registry/alpha_frontier_queue.json")) {
  nm <- names(which(sapply(c("06_Registry/hypothesis_index.json","06_Registry/knowledge_index.json",
                             "06_Registry/distilled_knowledge.json","06_Registry/alpha_frontier_queue.json"), identical, f)))
  blobs[[basename(f)]] <- if (file.exists(f)) paste(readLines(f, warn=FALSE), collapse="\n") else ""
}
## ★양성 대조 — 이 인덱스들이 팩터코드를 담기는 하는가 (0 이 '언급 없음'인지 '잘못된 계측'인지)
ctrl <- c("Q07_Earnings_Stability","M08_Residual_Mom","C01_SUE","V02_EP")
say("--- 양성 대조: 알려진 생산/기존 팩터코드가 각 인덱스에 등장하는가 ---")
for (b in names(blobs)) {
  hit <- sum(sapply(ctrl, function(k) grepl(k, blobs[[b]], fixed=TRUE)))   # ★fixed 필수
  say("  %-28s %d/%d 종 등장 %s", b, hit, length(ctrl), if(hit==0) "← ⚠계측 무효 가능" else "")
}
say("--- 유량의존 51건 언급 census (fixed 매칭) ---")
res <- rbindlist(lapply(names(blobs), function(b) {
  n <- sapply(flow, function(k) length(gregexpr(k, blobs[[b]], fixed=TRUE)[[1]][gregexpr(k, blobs[[b]], fixed=TRUE)[[1]] > 0]))
  data.table(index=b, 언급된팩터=sum(n>0), 총언급=sum(n))
}))
print(res)
top <- sort(sapply(flow, function(k) sum(sapply(blobs, function(b) length(gregexpr(k,b,fixed=TRUE)[[1]][gregexpr(k,b,fixed=TRUE)[[1]]>0])))), decreasing=TRUE)
say("--- 언급 상위 12 ---")
for (i in seq_len(min(12,length(top)))) if (top[i]>0) say("  %-28s %d회", names(top)[i], top[i])
say("언급 0회인 유량의존 팩터: %d / %d", sum(top==0), length(top))
writeLines(names(top)[top>0], "stage_artifacts/fq099/fq099d_mentioned.txt")
