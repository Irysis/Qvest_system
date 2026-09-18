# diag_one_tree.R — 한 트리에서 이탈 지점의 합법집합과 정렬을 직접 본다
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot/04_Research/meta/axiom_replay")
source("R/replay_engine.R")
source("R/policies/pi0_current.R")
ws <- readRDS("out/worlds.rds")
id <- "RP_20260910_123836_21280_combo_rulefast_promo1"
w <- ws[[id]]
cat("트리:", id, " 블록순서:", paste(w$block_order, collapse = ">"), "\n")
nd <- w$nodes
cat("\n기록 순서(칸·블록·바닥·측정):\n")
print(nd[, c("n", "cell_code", "block", "parent", "evaluated", "score", "batch")], row.names = FALSE)
rec_seq <- unlist(lapply(split(nd, nd$batch), function(b) b$cell_code), use.names = FALSE)
pos <- 22L
rev_before <- nd$node_id[match(rec_seq[seq_len(pos - 1)], nd$cell_code)]
winners <- .re_block_winners(nd)
legal <- ar_legal(nd, rev_before, winners)
cat("\n이탈 지점 pos =", pos, " 기록 칸 =", rec_seq[pos], "\n")
cat("공개된 칸 수:", length(rev_before), " 현재 바닥:", .re_floor(nd, rev_before), "\n")
lg <- nd[nd$node_id %in% legal, c("node_id", "cell_code", "block")]
ord <- w$block_order; if (!length(ord)) ord <- c("B1", "B2", "B3", "B5", "B4")
rk <- match(lg$block, ord); rk[is.na(rk)] <- 99L
num <- suppressWarnings(as.integer(sub("^B[0-9]+_", "", lg$cell_code)))
cat("\n합법집합(정렬 전):\n")
print(data.frame(cell = lg$cell_code, block = lg$block, rk = rk, num = num), row.names = FALSE)
cat("\n블록 승자(B4 자격):\n"); print(winners)
cat("승자 공개 여부:", all(winners %in% rev_before), "\n")
