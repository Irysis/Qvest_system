suppressPackageStartupMessages({ library(jsonlite) })
setwd(Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
say <- function(fmt,...) cat(sprintf(paste0("[166] ",fmt,"\n"),...))
q <- fromJSON("06_Registry/alpha_frontier_queue.json", simplifyVector=FALSE)
for (id in c("FQ-164","FQ-165","FQ-166")) {
  e <- Filter(function(x) isTRUE(identical(x$id, id)), q$entries)
  if (!length(e)) { say("%s : 미등재", id); next }
  e <- e[[1]]
  say("%s | status=%s | owner=%s", id,
      if (is.null(e$status)) "?" else e$status,
      if (is.null(e$owner)) "?" else e$owner)
  say("     title: %s", substr(if (is.null(e$title)) "?" else e$title, 1, 130))
  for (k in c("hypothesis","next_action","data_gate","blocked_by","in_flight_since")) {
    if (!is.null(e[[k]])) say("     %-14s %s", k, substr(paste(unlist(e[[k]]), collapse=" "), 1, 190))
  }
  cat("\n")
}
## in-flight 마커: 오늘 생성된 WT 디렉토리
say("=== 오늘(0808/0809) WT 디렉토리 ===")
d <- list.dirs("qepm/mailbox/worktask", recursive=FALSE, full.names=FALSE)
d <- d[grepl("2026080[89]", d)]
for (x in sort(d)) {
  st <- file.path("qepm/mailbox/worktask", x, "status.json")
  s <- if (file.exists(st)) tryCatch(paste(unlist(fromJSON(st)), collapse=" "), error=function(e) "?") else "(no status)"
  say("  %-26s %s", x, substr(s, 1, 90))
}
