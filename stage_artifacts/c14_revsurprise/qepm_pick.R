suppressPackageStartupMessages({ library(jsonlite); library(data.table) })
setwd(Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
say <- function(fmt,...) cat(sprintf(paste0("[qepm] ",fmt,"\n"),...))
q <- fromJSON("06_Registry/alpha_frontier_queue.json", simplifyVector=FALSE)
E <- q$entries
g <- function(x,k){ v<-x[[k]]; if(is.null(v)) "" else paste(unlist(v),collapse=" ") }
r <- rbindlist(lapply(E, function(x) data.table(
  id=g(x,"id"), status=g(x,"status"), gate=g(x,"data_gate"), owner=g(x,"owner"),
  title=g(x,"title"), ev=substr(g(x,"ev_rationale"),1,90), wall=substr(g(x,"wall_check"),1,70))))
say("★입력 실측: 큐 %d항목 · frontier_open %d", nrow(r), nrow(r[grepl("open",status,fixed=TRUE)]))

## v8.3 도달경로 ① 비-return 신규 원천 (FQ-001~005 주력) ② screen-tier 재고회수 (FQ-006~008)
say("=== v8.3 주력 경로 ①② 상태 ===")
print(r[id %in% paste0("FQ-00", 1:8), .(id, status=substr(status,1,22), gate=substr(gate,1,30), owner=substr(owner,1,18))])

say("=== frontier_open ∧ 게이트없음 ∧ owner 미배정 ∧ 자본주장 가능(wall_check 에 '자본 주장 아님' 없음) ===")
cand <- r[grepl("open",status,fixed=TRUE) & (gate=="" | grepl("없음",gate,fixed=TRUE)) &
          grepl("미배정",owner,fixed=TRUE) & !grepl("자본 주장 아님",wall,fixed=TRUE)]
say("  %d건", nrow(cand))
print(head(cand[, .(id, title=substr(title,1,62))], 14))

## hypothesis_index in-flight 확인 (병렬 중복 방지 의무)
hi <- fromJSON("06_Registry/hypothesis_index.json", simplifyVector=FALSE)
blob <- paste(unlist(hi), collapse=" ")
say("=== in-flight WT 조회 (병렬 중복 방지) ===")
for (k in cand$id) if (nzchar(k) && grepl(k, blob, fixed=TRUE)) say("  ★%s 은 hypothesis_index 에 이미 등장 — 중복 확인 필요", k)
say("  (위 출력 없으면 중복 없음)")
