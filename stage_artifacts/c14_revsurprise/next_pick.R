suppressPackageStartupMessages({ library(jsonlite); library(data.table); library(arrow) })
setwd(Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
say <- function(fmt,...) cat(sprintf(paste0("[pick] ",fmt,"\n"),...))
fp <- sort(Sys.glob(".cache/factor_db/factor_db_*.parquet"))
prod <- unique(as.data.table(read_parquet(fp[length(fp)]))$Factor_Name)
flowT <- readLines("stage_artifacts/fq099/flow_dependent_TRUE.txt")
flowX <- readLines("stage_artifacts/fq099/flow_dependent_factors.txt")   # 텍스트매칭 51 (xlsx 포함)
q <- fromJSON("06_Registry/alpha_frontier_queue.json", simplifyVector=FALSE)
E <- q$entries
say("★입력 실측: 큐 %d항목 · 산출팩터 %d · 유량의존(전체) %d", length(E), length(prod), length(flowX))

get <- function(x,k) { v <- x[[k]]; if (is.null(v)) "" else paste(unlist(v), collapse=" ") }
r <- rbindlist(lapply(E, function(x){
  blob <- paste(unlist(x), collapse=" ")
  fac  <- prod[sapply(prod, function(k) grepl(k, blob, fixed=TRUE))]      # ★fixed 필수
  flw  <- flowX[sapply(flowX, function(k) grepl(k, blob, fixed=TRUE))]
  data.table(id=get(x,"id"), status=get(x,"status"),
             gate=substr(get(x,"data_gate"),1,28), owner=substr(get(x,"owner"),1,14),
             n_fac=length(fac), n_flow=length(flw),
             title=substr(get(x,"title"),1,58))
}))
open <- r[grepl("open", status, fixed=TRUE)]
say("frontier_open %d건", nrow(open))
## 세 조건
cand <- open[(gate=="" | grepl("없음", gate, fixed=TRUE)) & n_flow==0]
say("★게이트없음 ∧ 유량비의존 = %d건", nrow(cand))
say("  그중 산출팩터를 명시한 것(=착수 즉시 데이터 있음) %d건", nrow(cand[n_fac>0]))
print(head(cand[order(-n_fac)][, .(id, n_fac, owner, title)], 16))
