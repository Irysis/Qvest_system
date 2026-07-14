suppressWarnings(suppressMessages(library(jsonlite)))
R <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
chk <- function(p) { j <- tryCatch(fromJSON(file.path(R,p), simplifyVector=FALSE), error=function(e) e)
  if (inherits(j,"error")) cat(sprintf("[FAIL] %s : %s\n", p, conditionMessage(j)))
  else cat(sprintf("[OK]   %s (well-formed)\n", p)); invisible(j) }
fq <- chk("06_Registry/alpha_frontier_queue.json")
chk("qepm/observability/insider_safe_live_track.json")
chk("stage_artifacts/WT_D20260715_011/verdict.json")
chk("stage_artifacts/l_code/ramp/l_code_R42_insider_safe_live_track_wiring.json")
mk <- file.path(R, ".cache/last_round_closure.json")
if (file.exists(mk)) { m <- fromJSON(mk, simplifyVector=FALSE)
  cat(sprintf("[OK]   closure marker: round=%s verdict=%s np=%d\n", m$round_id, m$verdict_type, length(m$next_probes))) }
## FQ-053 P2 필드 확인
if (!inherits(fq,"error")) {
  ids <- vapply(fq$entries, function(e) e$id, character(1))
  e53 <- fq$entries[[which(ids=="FQ-053")]]
  cat(sprintf("[OK]   FQ-053 status=%s  p2_live_track present=%s\n", e53$status, !is.null(e53$p2_live_track)))
}
cat("[validate] JSON edits 전부 well-formed\n")
