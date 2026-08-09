## FQ-138 P0 — CLAIM + 사전등록 판독 (측정 전에 남이 못 박은 규칙을 그대로 읽는다)
## ★이 라운드의 가치: 사전등록이 **이미 완료**돼 있어 forking path 가 원천 차단된다.
##   내가 오늘 저지른 위반(1급 실패 후 2급 승격)이 구조적으로 불가능한 조건.
suppressPackageStartupMessages({ library(jsonlite); library(data.table) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/FQ138")
say  <- function(fmt, ...) { cat(sprintf(paste0("[p0] ", fmt, "\n"), ...)); flush.console() }
source("02_Infrastructure/ops/claim_state.R")
source("02_Infrastructure/ops/frontier_queue_io.R")

MY <- "Q-Lead 2026-08-09"
Q <- read_frontier_queue(); ids <- vapply(Q$entries, function(e) as.character(e$id)[1], "")
i <- which(ids == "FQ-138")
if (!length(i)) { say("★FQ-138 부재 — 중단"); quit(status = 1) }
e <- Q$entries[[i]]

say("=== 0. 배정 가드 ===")
g <- assert_can_start(e, "FQ-138", my_session = MY)
say("  통과 (재진입=%s)", isTRUE(g$reentry))

say("=== 1. ★원장 기재 사항 전문 ===")
for (k in c("lane","title","hypothesis","ev_rationale","wall_check","data_gate","status","owner","next_action")) {
  v <- e[[k]]; if (is.null(v)) next
  say("[%s]", k)
  say("  %s", substr(gsub("[\r\n]+", " ", paste(v, collapse = " ")), 1, 1500))
}
if (!is.null(e$source_refs)) {
  say("[source_refs]")
  for (s in unlist(e$source_refs)) say("  - %s", s)
}

say("=== 2. ★사전등록 산출물 탐색 (원장이 가리키는 곳) ===")
pats <- c("fq138", "FQ138", "FQ-138", "20260808")
found <- character(0)
for (d in c("stage_artifacts", "04_Research", "qepm/mailbox/worktask")) {
  if (!dir.exists(d)) next
  f <- list.files(d, recursive = TRUE, full.names = TRUE,
                  pattern = "prereg|preregistration", ignore.case = TRUE)
  hit <- f[grepl(paste(pats, collapse="|"), f, ignore.case = TRUE)]
  if (length(hit)) found <- c(found, hit)
}
say("  prereg 매칭 %d건", length(found))
for (x in head(found, 10)) say("    %s (%.1f KB)", x, file.size(x)/1024)

## 계약수주 관련 디렉토리도
say("=== 3. 계약수주 라인 산출물 ===")
d2 <- list.dirs("stage_artifacts", recursive = FALSE)
d2 <- d2[grepl("contract|계약|fq125|fq138|fq140|dart", basename(d2), ignore.case = TRUE)]
for (x in d2) {
  f <- list.files(x, full.names = FALSE)
  say("  %s : %d 파일 — %s", basename(x), length(f), paste(head(f, 6), collapse=", "))
}

say("=== 4. 판정 ===")
say("  ★사전등록 원문을 찾았으면 그 규칙대로 측정한다.")
say("    못 찾았으면 status='preregistered' 가 **거짓 표기**이며 그 자체가 발견이다(등재≠존재).")
saveRDS(list(entry = e, prereg_files = found), file.path(OUT, "p0.rds"))
say("=== P0 완료 ===")
