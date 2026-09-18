# diag_budget_vs_space.R — 탐색공간 대비 예산. Dream-RSI 전제가 성립하는가.
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot/04_Research/meta/axiom_replay")
source("R/replay_engine.R")
ws <- readRDS("out/worlds.rds")
ws <- Filter(function(w) identical(w$regime, "post_0904"), ws)
d <- do.call(rbind, lapply(ws, function(w) data.frame(
  base_id = sub("^RP_2026", "", w$base_id), kind = w$kind,
  nodes = nrow(w$nodes), measured = sum(w$nodes$evaluated), budget = w$budget,
  stringsAsFactors = FALSE)))
d$ratio <- d$nodes / d$budget
cat("=== 트리별 기록 칸 수 대 예산 ===\n")
print(d[order(-d$nodes), ], row.names = FALSE)
cat(sprintf("\n기록 칸 중앙 %.0f · 예산 중앙 %.0f · 비 %.2f\n",
            median(d$nodes), median(d$budget), median(d$ratio)))
cat("\n★Dream-RSI 는 탐색공간 >> 예산일 때 가지치기로 이득을 낸다.\n")
cat("  여기서는 기록된 공간이 예산과 같거나 작다 — 쳐낼 가지가 구조적으로 없다.\n")
