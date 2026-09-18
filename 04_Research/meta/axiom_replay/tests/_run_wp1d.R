setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot/04_Research/meta/axiom_replay")
source("R/wp1_promotion.R")
led <- ar_load_ledger(1); att <- ar_attempts_df(led); ent <- ar_entries_df(led, att)
cache <- new.env(parent = emptyenv())
ent$base_port_t <- vapply(ent$base_artifacts, .wp1_base_port_t, numeric(1), cache = cache)
run <- ent[ent$n_measured > 0 & ent$kind != "promo", ]
cat("=== 착수한 원본 entry — 기저 대비 결과 ===\n")
o <- order(run$base_port_t)
print(data.frame(entry = sub("^RP_2026","",run$base_id[o]), base_g = run$base_grade[o],
                 base_t = round(run$base_port_t[o],3), cells = run$n_cells[o],
                 best = round(run$best_port_t[o],3), bg = run$best_grade[o],
                 opened = format(run$opened_at[o], "%m-%d")), row.names = FALSE)
cat("\n=== 파킹 entry (기저 미달) ===\n")
pk <- ent[ent$status == "parked", ]
print(data.frame(entry = sub("^RP_2026","",pk$base_id), base_g = pk$base_grade,
                 base_t = round(pk$base_port_t,3), cells = pk$n_cells,
                 reason = substr(pk$parked_reason,1,46)), row.names = FALSE)
