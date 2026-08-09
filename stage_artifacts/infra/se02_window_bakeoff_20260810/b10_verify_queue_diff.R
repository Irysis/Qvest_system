#==============================================================================
# b10_verify_queue_diff.R — 원장 갱신이 **순수 추가 + 의도한 필드만** 인가
#   텍스트 diff 를 믿지 않고 파싱해서 항목별로 비교한다.
#   (공유 원장 재직렬화 사고 계열 — reference-shared-registry-reserialize-precision-loss)
#==============================================================================
suppressMessages(library(jsonlite))
OLD <- file.path("C:/Users/99922/AppData/Local/Temp/claude",
                 "C--Users-99922-OneDrive-Quant-Module-Moltbot",
                 "731a7a86-b8bf-4640-9de7-b5e7830e4ad8/scratchpad/fq_old.json")
NEW <- "06_Registry/alpha_frontier_queue.json"
stopifnot(file.exists(OLD), file.exists(NEW))

old <- fromJSON(OLD, simplifyVector = FALSE)
new <- fromJSON(NEW, simplifyVector = FALSE)
oid <- vapply(old$entries, function(e) as.character(e$id)[1], character(1))
nid <- vapply(new$entries, function(e) as.character(e$id)[1], character(1))

cat(sprintf("old=%d  new=%d\n", length(oid), length(nid)))
cat(sprintf("added   = %s\n", paste(setdiff(nid, oid), collapse = ", ")))
cat(sprintf("removed = %s (0건이어야 함)\n", paste(setdiff(oid, nid), collapse = ", ")))

common <- intersect(oid, nid)
changed <- character(0)
for (id in common) {
  a <- old$entries[[which(oid == id)[1]]]
  b <- new$entries[[which(nid == id)[1]]]
  if (!identical(a, b)) changed <- c(changed, id)
}
cat(sprintf("\n기존 %d건 중 내용이 달라진 항목: %d건\n", length(common), length(changed)))
if (!length(changed)) {
  cat("  [주의] 0건 — FQ-222 는 의도적으로 고쳤으므로 최소 1건이어야 한다. 비교기 점검 필요.\n")
} else {
  for (id in changed) {
    a <- old$entries[[which(oid == id)[1]]]; b <- new$entries[[which(nid == id)[1]]]
    ka <- names(a); kb <- names(b)
    fld <- Filter(function(k) !identical(a[[k]], b[[k]]), intersect(ka, kb))
    cat(sprintf("  [%s] 신규키=%s · 삭제키=%s · 값변경=%s\n", id,
                paste(setdiff(kb, ka), collapse = "/"),
                paste(setdiff(ka, kb), collapse = "/"),
                paste(fld, collapse = "/")))
  }
}

# 정밀도 축: 고정밀 리터럴 소실 여부 (writer 가드와 독립 재검)
lits <- function(p) {
  t <- paste(readLines(p, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  unique(unlist(regmatches(t, gregexpr("-?[0-9]+[.][0-9]{5,}", t, perl = TRUE))))
}
lo <- lits(OLD); ln <- lits(NEW)
cat(sprintf("\n고정밀 리터럴: old=%d new=%d · 소실=%d %s\n", length(lo), length(ln),
            length(setdiff(lo, ln)), paste(head(setdiff(lo, ln), 5), collapse = ",")))
if (length(setdiff(lo, ln))) cat("  [STOP] 반올림 손실 발생\n") else cat("  OK — 반올림 손실 없음\n")

# 최상위 키 보존
cat(sprintf("\n최상위 키 old=[%s] new=[%s]\n", paste(names(old), collapse=","),
            paste(names(new), collapse=",")))
cat("\n[b10 완료]\n")
