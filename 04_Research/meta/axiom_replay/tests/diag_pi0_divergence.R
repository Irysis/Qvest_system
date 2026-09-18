# diag_pi0_divergence.R — π₀ 가 기록과 갈리는 첫 지점의 원인 분류
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot/04_Research/meta/axiom_replay")
source("R/replay_engine.R")
source("R/policies/pi0_current.R")
ws <- readRDS("out/worlds.rds")

rows <- list()
for (w in ws) {
  if (!identical(w$regime, "post_0904")) next
  sizes   <- vapply(split(w$nodes, w$nodes$batch), nrow, integer(1))
  r       <- ar_replay(w, rf_policy_fn, W = 5L, budget = nrow(w$nodes), sizes = sizes)
  rec_seq <- unlist(lapply(split(w$nodes, w$nodes$batch), function(b) b$cell_code), use.names = FALSE)
  pi_seq  <- if (nrow(r$trace)) unlist(strsplit(r$trace$batch, ","), use.names = FALSE) else character(0)
  n <- min(length(rec_seq), length(pi_seq))
  i <- if (!n) 1L else { d <- which(rec_seq[seq_len(n)] != pi_seq[seq_len(n)]); if (length(d)) d[1] else NA_integer_ }
  if (is.na(i)) next                                   # 접두 전체 일치
  rb <- sub("_.*$", "", rec_seq[i]); pb <- sub("_.*$", "", pi_seq[i])
  # 그 시점에 기록 칸이 π₀ 의 합법 집합에 있었나
  rev_before <- if (i > 1) {
    ids <- character(0)
    for (j in seq_len(i - 1)) ids <- c(ids, w$nodes$node_id[match(rec_seq[j], w$nodes$cell_code)])
    ids } else character(0)
  winners <- .re_block_winners(w$nodes)
  legal   <- ar_legal(w$nodes, rev_before, winners)
  rec_id  <- w$nodes$node_id[match(rec_seq[i], w$nodes$cell_code)]
  cause <- if (!(rec_id %in% legal)) "기록칸이 합법집합 밖(바닥 불일치)"
           else if (rb != pb) "블록 순서 차이"
           else "블록 안 칸 순서 차이"
  dup <- sum(duplicated(w$nodes$node_id))
  rows[[length(rows) + 1L]] <- data.frame(
    base_id = sub("^RP_2026", "", w$base_id), pos = i, n_seq = length(rec_seq),
    rec = rec_seq[i], pi0 = pi_seq[i], cause = cause, dup_nodes = dup,
    blk_order = paste(w$block_order, collapse = ">"), stringsAsFactors = FALSE)
}
d <- do.call(rbind, rows)
cat("=== post_0904 첫 이탈 지점 (", nrow(d), "트리) ===\n", sep = "")
print(d[order(d$pos), c("base_id", "pos", "n_seq", "rec", "pi0", "cause")], row.names = FALSE)
cat("\n원인 분포:\n"); print(table(d$cause))
cat("\n중복 node_id 있는 트리:", sum(d$dup_nodes > 0), "\n")
cat("\n기록된 블록 순서:\n"); print(table(d$blk_order))
