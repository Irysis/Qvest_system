## 위기신호 역방향(비중 확대) 가설 — 착수 전 중복/선행연구 확인
## 규약: 제목이 아니라 next_action **본문**까지 검색 (2026-08-09 교훈)
suppressPackageStartupMessages({ library(jsonlite) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
say <- function(fmt, ...) { cat(sprintf(paste0("[dup] ", fmt, "\n"), ...)); flush.console() }
source("02_Infrastructure/ops/frontier_queue_io.R")
Q <- read_frontier_queue()

blob <- vapply(Q$entries, function(e) paste(unlist(e), collapse = " "), character(1))
ids  <- vapply(Q$entries, function(e) as.character(e$id)[1], character(1))
ttl  <- vapply(Q$entries, function(e) gsub("[\r\n]+"," ", as.character(e$title)[1]), character(1))
stt  <- vapply(Q$entries, function(e) if(is.null(e$status)) "" else as.character(e$status)[1], character(1))

say("=== 원장 %d 항목 · 역방향/contrarian/비중확대 관련 검색 ===", length(ids))
pat <- c("역방향","반대 방향","contrarian","역전","비중 확대","비중확대","확대","선행","lead","지연","lagging",
         "bottom","저점","반등","위기.*매수","risk-on")
hits <- unique(unlist(lapply(pat, function(p) which(grepl(p, blob)))))
say("  1차 후보 %d건 — 국면/위기 문맥으로 좁힘", length(hits))
regime <- hits[grepl("위기|crisis|국면|regime|CRISIS|Bear|bear|MSM", blob[hits])]
for (i in sort(regime)) say("  %-9s | %-34s | %s", ids[i], substr(stt[i],1,34), substr(ttl[i],1,64))

say("=== 핵심 선행연구 본문 확인 (FQ-114/115/117/129) ===")
for (k in c("FQ-114","FQ-115","FQ-117","FQ-129")) {
  i <- which(ids == k); if (!length(i)) { say("  %s 부재", k); next }
  e <- Q$entries[[i]]
  say("--- %s [%s] %s", k, e$status, substr(gsub("[\r\n]+"," ", e$title), 1, 80))
  for (f in c("hypothesis","ev_rationale","next_action")) {
    v <- e[[f]]; if (!is.null(v))
      say("    [%s] %s", f, substr(gsub("[\r\n]+"," ", paste(v, collapse=" ")), 1, 520))
  }
}

say("=== hypothesis_index 검색 ===")
hi <- paste(unlist(fromJSON("06_Registry/hypothesis_index.json", simplifyVector = FALSE)), collapse=" ")
for (k in c("역방향","contrarian","비중 확대","위기.*매수","반등","선행지표"))
  say("  %-12s : %s", k, grepl(k, hi))

say("=== 오늘자 WT 소관 (병렬 세션 충돌 방지) ===")
d <- sort(basename(list.dirs("qepm/mailbox/worktask", recursive = FALSE)))
d <- d[grepl("20260809", d, fixed = TRUE)]
for (x in d) {
  f <- file.path("qepm/mailbox/worktask", x, "task.json")
  h <- if (file.exists(f)) tryCatch(paste(fromJSON(f)$hypothesis_title,
        substr(paste(fromJSON(f)$hypothesis_description, collapse=" "),1,110)), error=function(e) "?") else "?"
  say("  %-20s %s", x, substr(gsub("[\r\n]+"," ", h), 1, 130))
}
