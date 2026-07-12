#!/usr/bin/env Rscript
# FQ-017 atomic update (temp-rename): status measured + result refs.
suppressMessages(library(jsonlite))
root <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(root)
QP <- "06_Registry/alpha_frontier_queue.json"
q <- read_json(QP, simplifyVector = FALSE)
idx <- which(vapply(q$entries, function(x) identical(x$id, "FQ-017"), logical(1)))
stopifnot(length(idx) == 1)
q$entries[[idx]]$status <- "measured"
q$entries[[idx]]$next_action <- paste(
  "완료 — SCREEN_TIER 확정. m1 종목단 exclusion/tilt 오버레이 4암 전부 paired 증분 NW-t <2.0",
  "(최선 LARGE_tilt 1.27). cap-tier 트랩 재확인(소형 base 자체 PORT_t 1.52, 오버레이 증분 ~0).",
  "PIT 4종 clean. m1은 feature 보존, 자본기여 자격 없음.")
q$entries[[idx]]$result <- list(
  verdict = "SCREEN_TIER (overlay marginal FAIL; feature preserved)",
  measured_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  metric_type = "canonical_screen (screen_diagnostic)",
  best_arm_paired_nw_t = 1.27,
  l_code = trimws(readLines(file.path(root, "stage_artifacts/m1_overlay_drain/lcode_id.txt"))[1]),
  prereg_sha256 = "b93e48f2f238c4496e5774c9dd8b7c66bdfe89d9d9dccc4e514b683e79d1a3ee",
  result_path = "stage_artifacts/m1_overlay_drain/m1_overlay_drain_result.json",
  challenge_note = "stage_artifacts/m1_overlay_drain/challenge_note.md",
  infeasibility_note = "carrier per-stock holdings unavailable + m1-dead mega/mid tier + drain overlay=market-scalar -> measured via weighted_screen_bt contract primitive on dual-tier bases (see preregistration.json)")

tmp <- paste0(QP, ".tmp", Sys.getpid())
write_json(q, tmp, auto_unbox = TRUE, pretty = TRUE, digits = NA, null = "null")
if (file.exists(QP)) { file.copy(QP, paste0(QP, ".bak"), overwrite = TRUE); file.remove(QP) }
stopifnot(file.rename(tmp, QP))
cat("[FQ] FQ-017 -> status=measured (atomic temp-rename)\n")
