setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot/04_Research/meta/axiom_replay")
source("R/wp1_promotion.R")
led <- ar_load_ledger(1); att <- ar_attempts_df(led); ent <- ar_entries_df(led, att)
r <- wp1_sweep(ent, att); ev <- r$events
cat("=== 승격 사건 12건 (payoff = 자식최고 - 부모최고) ===\n")
print(data.frame(child = sub("^RP_2026", "", ev$child_id), d = ev$depth,
                 bp = round(ev$bp_recorded, 3), pbest = round(ev$pbest, 3),
                 base = round(ev$base_port_t, 3), mar_cur = round(ev$margin_cur, 3),
                 mar_uni = round(ev$margin_uni, 3), child_best = round(ev$child_best, 3),
                 payoff = round(ev$payoff, 3), cells = ev$subtree_cells), row.names = FALSE)
cat("\npayoff 부호: 개선", sum(ev$payoff > 0), "· 동일", sum(ev$payoff == 0), "· 악화", sum(ev$payoff < 0), "\n")
cat("승격 칸 총합:", sum(ent$n_cells[ent$kind == "promo"]), "/ 전체", nrow(att), "\n")
cat("\n=== 문턱 스윕 (프로그램 최고", round(r$program_best, 3), ") ===\n")
s <- r$sweep
s$minutes_saved <- round(s$minutes_saved); s$pct_all_cells <- round(s$pct_all_cells, 1)
s$pct_promo_cells <- round(s$pct_promo_cells, 1); s$program_best <- round(s$program_best, 3)
s$best_loss <- round(s$best_loss, 3); s$lineage_loss <- round(s$lineage_loss, 3)
print(s[s$rule == "current", ], row.names = FALSE)
cat("\n[uniform 규칙은 current 와 동일한가]", isTRUE(all.equal(s[s$rule=="current",-1], s[s$rule=="uniform",-1], check.attributes=FALSE)), "\n")
saveRDS(list(events = ev, sweep = r$sweep, program_best = r$program_best), "out/wp1_promotion.rds")
