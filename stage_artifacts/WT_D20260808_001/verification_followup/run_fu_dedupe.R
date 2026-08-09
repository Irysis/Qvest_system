# run_fu_dedupe.R — run_fu_verify.R 이 멱등하지 않아 challenge_flags 가 중복 append 됐다.
#   (검사 스크립트를 두 번 돌린 것이 원인 — 검사기가 상태를 바꾸면 안 된다는 교훈)
suppressPackageStartupMessages(library(jsonlite))
setwd(Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
say <- function(f, ...) cat(sprintf(paste0("[dedupe] ", f, "\n"), ...))
f <- "qepm/mailbox/worktask/WT-D20260808_001/alpha_package.json"
p <- fromJSON(f, simplifyVector = FALSE)
cf <- unlist(p$challenge_flags)
say("challenge_flags %d개 · 고유 %d개 · 중복 %d개", length(cf), length(unique(cf)), sum(duplicated(cf)))
if (any(duplicated(cf))) {
  p$challenge_flags <- as.list(cf[!duplicated(cf)])
  write_json(p, f, pretty = TRUE, auto_unbox = TRUE, digits = NA, null = "null")
  q <- fromJSON(f, simplifyVector = FALSE)
  say("수리 후 %d개 · 중복 %d개", length(q$challenge_flags), sum(duplicated(unlist(q$challenge_flags))))
} else say("중복 없음")
