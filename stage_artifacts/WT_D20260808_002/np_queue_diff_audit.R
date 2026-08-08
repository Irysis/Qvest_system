## 큐 재직렬화 감사 — 내 append 가 남의 항목을 훼손했는가 (값 수준 비교, 포맷 차이 무시)
suppressPackageStartupMessages(library(jsonlite))
setwd(Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
say <- function(fmt,...) cat(sprintf(paste0("[qa] ",fmt,"\n"),...))
QP <- "06_Registry/alpha_frontier_queue.json"

## 세션 시작 시점(내 write 이전) 상태 = 다른 세션이 남긴 .bak 이 아니라, git stash 없이
## 확보 가능한 유일한 기준선은 HEAD. ★단 파일은 세션 시작 때 이미 M(수정됨) 이었으므로
## HEAD 대비 diff 에는 **남의 미커밋 변경**이 섞인다 — 그걸 내 훼손으로 오독하면 안 된다.
head_txt <- system2("git", c("show", "HEAD:06_Registry/alpha_frontier_queue.json"), stdout = TRUE)
old <- fromJSON(paste(head_txt, collapse="\n"), simplifyVector = FALSE)
new <- fromJSON(QP, simplifyVector = FALSE)
say("★입력 실측: HEAD entries %d · 현재 entries %d (증가 %d)",
    length(old$entries), length(new$entries), length(new$entries)-length(old$entries))

gid <- function(e) if (is.null(e$id)) NA_character_ else as.character(e$id)
oi <- vapply(old$entries, gid, character(1)); ni <- vapply(new$entries, gid, character(1))
say("HEAD 에만 있는 id: %s", paste(setdiff(oi, ni), collapse=" ") )
say("현재에만 있는 id: %s", paste(setdiff(ni, oi), collapse=" ") )

## 값 수준 비교 (재귀 identical) — 공통 id 전수
om <- setNames(old$entries, oi); nm <- setNames(new$entries, ni)
common <- intersect(oi, ni)
diff_ids <- common[!vapply(common, function(k) identical(om[[k]], nm[[k]]), logical(1))]
say("공통 id %d 중 값이 달라진 항목: %d", length(common), length(diff_ids))
if (length(diff_ids)) {
  say("  달라진 id: %s", paste(head(diff_ids, 20), collapse=" "))
  for (k in head(diff_ids, 3)) {
    a <- om[[k]]; b <- nm[[k]]
    fa <- union(names(a), names(b))
    ch <- fa[!vapply(fa, function(f) identical(a[[f]], b[[f]]), logical(1))]
    say("  [%s] 달라진 필드: %s", k, paste(ch, collapse=", "))
  }
}
## ★양성 대조 — 비교기가 실제로 차이를 잡는지 (0 을 결론으로 쓰지 않기 위해)
probe <- om[[common[1]]]; probe$title <- paste0(probe$title, "_MUTATED")
say("★양성 대조: 일부러 변형한 항목을 identical 이 다르다고 판정하는가 = %s",
    !identical(om[[common[1]]], probe))
