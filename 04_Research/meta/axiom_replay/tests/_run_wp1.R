setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot/04_Research/meta/axiom_replay")
source("R/wp1_promotion.R")
led <- ar_load_ledger(1); att <- ar_attempts_df(led); ent <- ar_entries_df(led, att)
cat("entries:", nrow(ent), " kinds:\n"); print(table(ent$kind))
r <- wp1_sweep(ent, att)
cat("\n=== 승격 사건 12건 ===\n")
ev <- r$events
print(data.frame(child = substr(ev$child_id, 4, 60), d = ev$depth,
                 bp = round(ev$bp_recorded, 3), bp_chk = round(ev$bp_computed, 3),
                 pbest = round(ev$pbest, 3), base = round(ev$base_port_t, 3),
                 child_best = round(ev$child_best, 3), payoff = round(ev$payoff, 3),
                 cells = ev$subtree_cells), row.names = FALSE)
cat("\n=== 문턱 스윕 (프로그램 최고 =", round(r$program_best, 3), ") ===\n")
s <- r$sweep; s$minutes_saved <- round(s$minutes_saved)
s$program_best <- round(s$program_best, 3); s$best_loss <- round(s$best_loss, 3)
print(s, row.names = FALSE)
