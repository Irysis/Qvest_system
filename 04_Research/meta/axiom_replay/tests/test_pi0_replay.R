# test_pi0_replay.R — P0-(a) 양성 대조
#   π₀ 리플레이가 기록 배치열을 재현하는가. 재현 못 하면 리플레이 엔진의 결과를 인용할 수 없다.
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot/04_Research/meta/axiom_replay")
source("R/replay_engine.R")
source("R/policies/pi0_current.R")

ws <- readRDS("out/worlds.rds")
res <- list()
for (w in ws) {
  rec <- do.call(rbind, lapply(split(w$nodes, w$nodes$batch), function(b)
    data.frame(batch = paste(b$cell_code, collapse = ","), n = nrow(b), stringsAsFactors = FALSE)))
  sizes <- vapply(split(w$nodes, w$nodes$batch), nrow, integer(1))
  r <- ar_replay(w, rf_policy_fn, W = 5L, budget = nrow(w$nodes), sizes = sizes)
  nmin <- min(nrow(rec), nrow(r$trace))
  same <- if (nmin == 0) logical(0) else vapply(seq_len(nmin), function(i)
    setequal(strsplit(rec$batch[i], ",")[[1]], strsplit(r$trace$batch[i], ",")[[1]]), logical(1))
  rec_seq <- unlist(lapply(split(w$nodes, w$nodes$batch), function(b) b$cell_code), use.names = FALSE)
  pi_seq  <- if (nrow(r$trace)) unlist(strsplit(r$trace$batch, ","), use.names = FALSE) else character(0)
  nseq <- min(length(rec_seq), length(pi_seq))
  seq_pref <- if (!nseq) 0L else sum(cumprod(as.integer(rec_seq[seq_len(nseq)] == pi_seq[seq_len(nseq)])))
  res[[w$base_id]] <- data.frame(
    base_id = w$base_id, regime = w$regime, kind = w$kind,
    n_nodes = nrow(w$nodes), rec_batches = nrow(rec), pi0_batches = nrow(r$trace),
    prefix_match = if (!length(same)) 0L else sum(cumprod(as.integer(same))),
    all_match = length(same) > 0 && all(same) && nrow(rec) == nrow(r$trace),
    n_seq = length(rec_seq), seq_prefix = seq_pref,
    seq_full = seq_pref == length(rec_seq) && length(pi_seq) == length(rec_seq),
    revealed = r$N, unreachable = r$unreachable, stringsAsFactors = FALSE)
}
d <- do.call(rbind, res)
cat("=== π₀ 재현 (트리", nrow(d), ") ===\n")
cat(sprintf("  완전 일치 %d/%d · 접두 일치 배치 %d/%d (%.1f%%)\n",
            sum(d$all_match), nrow(d), sum(d$prefix_match), sum(d$rec_batches),
            100 * sum(d$prefix_match) / sum(d$rec_batches)))
for (rg in c("post_0904", "pre_0904")) {
  s <- d[d$regime == rg, ]
  if (!nrow(s)) next
  cat(sprintf("  %-9s 완전 %d/%d · 접두 %d/%d (%.1f%%)\n", rg, sum(s$all_match), nrow(s),
              sum(s$prefix_match), sum(s$rec_batches), 100 * sum(s$prefix_match) / sum(s$rec_batches)))
}
cat("\n미재현 트리 (접두 결손 큰 순):\n")
b <- d[!d$all_match, ]
b <- b[order(b$prefix_match - b$rec_batches), ]
print(head(b[, c("base_id", "regime", "rec_batches", "pi0_batches", "prefix_match", "unreachable")], 10),
      row.names = FALSE)
saveRDS(d, "out/pi0_replay.rds")

cat("\n=== 칸 순서 재현 (환경이 배치 크기를 부여) ===\n")
cat(sprintf("  전 트리 완전 %d/%d · 접두 칸 %d/%d (%.1f%%)\n", sum(d$seq_full), nrow(d),
            sum(d$seq_prefix), sum(d$n_seq), 100 * sum(d$seq_prefix) / sum(d$n_seq)))
for (rg in c("post_0904", "pre_0904")) {
  s2 <- d[d$regime == rg, ]
  if (!nrow(s2)) next
  cat(sprintf("  %-9s 완전 %d/%d · 접두 칸 %d/%d (%.1f%%)\n", rg, sum(s2$seq_full), nrow(s2),
              sum(s2$seq_prefix), sum(s2$n_seq), 100 * sum(s2$seq_prefix) / sum(s2$n_seq)))
}
cat("\n=== 미재현 원인 진단 (post_0904) ===\n")
pp <- d[d$regime == "post_0904" & !d$seq_full, ]
if (nrow(pp)) print(pp[, c("base_id", "kind", "n_seq", "seq_prefix", "pi0_batches", "rec_batches", "unreachable")],
                    row.names = FALSE) else cat("  없음\n")
