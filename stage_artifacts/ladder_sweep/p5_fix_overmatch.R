## p5 — ★자가 검거: p4 의 M26 매칭이 '언급' 을 '판독 보유' 로 오인해 7건에 정정문을 붙였다.
## 존재 검사(문자열 언급) ≠ 정체 검사(그 판독을 실제로 담았는가). 정체 기준으로 재판정한다.
suppressPackageStartupMessages({ library(jsonlite); library(data.table) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
say <- function(fmt, ...) { cat(sprintf(paste0("[p5] ", fmt, "\n"), ...)); flush.console() }
source("02_Infrastructure/ops/frontier_queue_io.R")

MARK <- " \u2605\uc815\uc815(2026-08-09 ladder_sweep): \uc774 \ub77c\uc6b4\ub4dc\uc758"   # " ★정정(2026-08-09 ladder_sweep): 이 라운드의"
Q <- read_frontier_queue(); ids <- vapply(Q$entries, function(e) as.character(e$id)[1], "")
n0 <- length(Q$entries)

## 사다리 판독을 실제로 담은 항목의 지문: 사다리 수치 또는 채널 서술
FP <- "2\\.818|2\\.041|1\\.544|\uc0ac\ub2e4\ub9ac|\ud578\ub514\uce61|\ube44-\uc2e0\ud638 \ucc44\ub110|EW-basis|EW-\uc720\ub2c8\ubc84\uc2a4 basis"

say("=== p4 가 건드린 항목 재판정 (정체 기준) ===")
kept <- 0L; rev <- 0L
for (k in seq_along(Q$entries)) {
  na <- as.character(Q$entries[[k]]$next_action)[1]
  if (is.na(na) || !grepl(MARK, na, fixed = TRUE)) next
  pos <- regexpr(MARK, na, fixed = TRUE)
  before <- substr(na, 1, pos - 1L)                     # 내 정정문 **이전** 원문만으로 판정
  blob   <- paste(before, paste(unlist(Q$entries[[k]][setdiff(names(Q$entries[[k]]), "next_action")]),
                                collapse = " "))
  has <- grepl(FP, blob)
  if (has) { kept <- kept + 1L; say("  유지  %s — 사다리 판독 지문 있음", ids[k]) }
  else {
    Q$entries[[k]]$next_action <- sub("\\s*$", "", before)
    rev <- rev + 1L; say("  되돌림 %s — M26 **언급**만 있고 사다리 판독 없음", ids[k])
  }
}
say("  ⇒ 유지 %d · 되돌림 %d", kept, rev)

Q$updated <- "2026-08-09"
write_frontier_queue(Q)
Q2 <- read_frontier_queue()
say("=== 재읽기 검증: 항목 %d → %d (불변 %s) · 잔여 마커 %d건 ===",
    n0, length(Q2$entries), length(Q2$entries) == n0,
    sum(vapply(Q2$entries, function(e) {
      na <- as.character(e$next_action)[1]
      !is.na(na) && grepl(MARK, na, fixed = TRUE) }, TRUE)))
say("=== FQ-196 등재 확인: %s ===",
    "FQ-196" %in% vapply(Q2$entries, function(e) as.character(e$id)[1], ""))
say("=== p5 완료 ===")
