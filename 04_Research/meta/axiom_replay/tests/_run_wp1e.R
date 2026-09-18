setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot/04_Research/meta/axiom_replay")
source("R/wp1_promotion.R")
led <- ar_load_ledger(1); att <- ar_attempts_df(led); ent <- ar_entries_df(led, att)
cache <- new.env(parent = emptyenv())
ent$base_port_t <- vapply(ent$base_artifacts, .wp1_base_port_t, numeric(1), cache = cache)
run <- ent[ent$n_measured > 0 & ent$kind != "promo", ]
o <- order(run$base_port_t)
cat("=== 착수한 원본 entry (n=", nrow(run), ") ===\n", sep="")
print(data.frame(entry = sub("^RP_2026","",run$base_id[o]), bg = run$base_grade[o],
                 base_t = round(run$base_port_t[o],3), cells = run$n_cells[o],
                 best = round(run$best_port_t[o],3), best_g = run$best_grade[o]), row.names = FALSE)
# 음수 기저인데 착수된 건들의 근거 — 원장 원문에서 rescue/defensive 흔적
led2 <- ar_load_ledger(1)
neg <- run$base_id[is.finite(run$base_port_t) & run$base_port_t < 0]
cat("\n=== 기저 음수인데 착수된 entry 의 원장 필드 ===\n")
for (E in led2$entries) if ((E$base_id %||% "") %in% neg) {
  ap <- file.path(E$base_artifacts, "authoritative_remeasure.json")
  j <- if (file.exists(ap)) fromJSON(ap, simplifyVector=FALSE) else NULL
  cat(sprintf("  %s\n    base_grade=%s  grade_base=%s  rolling=%s  rescued=%s  defensive=%s\n",
      sub("^RP_2026","",E$base_id), E$base_grade %||% "-",
      j$grade_base %||% "-",
      if (!is.null(j$rolling_grade)) paste0(j$rolling_grade$rescue_applied %||% "?",
            "/pass=", round(as.numeric(j$rolling_grade$recent_pass_rate %||% NA),3)) else "-",
      j$recent_regime_rescued %||% "-",
      if (!is.null(j$defensive_score)) (j$defensive_score$defensive %||% "-") else "-"))
}
