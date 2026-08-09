## 병렬 세션 충돌 방지 — 현재 in-flight 전수 census (도훈 지시 2026-08-09)
## 규약: 큐 owner 불신 → **오늘자 WT request.json 실측** + 큐 next_action 본문 대조
suppressPackageStartupMessages({ library(jsonlite) })
setwd(Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
say <- function(fmt,...) cat(sprintf(paste0("[census] ",fmt,"\n"),...))

say("=== A. 오늘자 WT 실측 (0808/0809) ===")
base <- "qepm/mailbox/worktask"
ds <- sort(list.dirs(base, recursive=FALSE, full.names=FALSE))
ds <- ds[grepl("2026080[89]", ds)]
for (d in ds) {
  p <- file.path(base, d)
  ti <- NA_character_
  for (f in c("request.json","alpha_hypothesis.json")) {
    fp <- file.path(p, f)
    if (file.exists(fp)) {
      j <- tryCatch(fromJSON(fp, simplifyVector=FALSE), error=function(e) NULL)
      cand <- if (!is.null(j$hypothesis_title)) j$hypothesis_title else j$title
      if (!is.null(cand) && is.character(cand)) { ti <- cand[1]; break }
    }
  }
  st <- file.path(p, "status.json")
  s  <- if (file.exists(st)) tryCatch(fromJSON(st)$status, error=function(e) "?") else "(none)"
  has_pkg <- file.exists(file.path(p, "alpha_package.json"))
  say("%-20s %-16s pkg=%-5s %s", d, substr(s,1,16), has_pkg, substr(ifelse(is.na(ti),"(제목 미상)",ti), 1, 78))
}

say("")
say("=== B. 큐 open 항목 중 최근 등재(FQ-160+) ===")
q <- fromJSON("06_Registry/alpha_frontier_queue.json", simplifyVector=FALSE)
for (e in q$entries) {
  id <- e$id; if (is.null(id)) next
  n <- suppressWarnings(as.integer(sub("^FQ-", "", id)))
  if (is.na(n) || n < 160) next
  st <- if (is.null(e$status)) "?" else e$status
  ow <- if (is.null(e$owner)) "?" else e$owner
  say("%-8s %-24s owner=%-32s %s", id, substr(st,1,24), substr(ow,1,32),
      substr(if (is.null(e$title)) "?" else e$title, 1, 60))
}
