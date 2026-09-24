source("C:/Users/99922/OneDrive/Quant_Module_Moltbot/02_Infrastructure/validation/lookahead_detector.R")
files <- c(
  "C:/Users/99922/AppData/Local/Temp/claude/C--Users-99922-OneDrive-Quant-Module-Moltbot/be2e88bf-6a4c-44e5-a6ff-6aae164c14ca/scratchpad/pit_c11/d_knowledge/fx_pos_samedate.R", "C:/Users/99922/AppData/Local/Temp/claude/C--Users-99922-OneDrive-Quant-Module-Moltbot/be2e88bf-6a4c-44e5-a6ff-6aae164c14ca/scratchpad/pit_c11/d_knowledge/fx_neg_lagged.R", "C:/Users/99922/AppData/Local/Temp/claude/C--Users-99922-OneDrive-Quant-Module-Moltbot/be2e88bf-6a4c-44e5-a6ff-6aae164c14ca/scratchpad/pit_c11/d_knowledge/fx_mut_flagword.R", "C:/Users/99922/AppData/Local/Temp/claude/C--Users-99922-OneDrive-Quant-Module-Moltbot/be2e88bf-6a4c-44e5-a6ff-6aae164c14ca/scratchpad/pit_c11/d_knowledge/fx_mut_indirect.R",
  "C:/Users/99922/OneDrive/Quant_Module_Moltbot/02_Infrastructure/factor_db/factor_db_builder.R",
  "C:/Users/99922/OneDrive/Quant_Module_Moltbot/02_Infrastructure/factor_db/factor_db_daily_phase6.R",
  "C:/Users/99922/OneDrive/Quant_Module_Moltbot/02_Infrastructure/factor_db/factor_db_daily_phase7.R",
  "C:/Users/99922/OneDrive/Quant_Module_Moltbot/02_Infrastructure/factor_db/compute_defense.R",
  "C:/Users/99922/OneDrive/Quant_Module_Moltbot/02_Infrastructure/factor_db/compute_regime.R",
  "C:/Users/99922/OneDrive/Quant_Module_Moltbot/02_Infrastructure/regime/regime_engine_daily.R")
for (f in files) {
  r <- detect_lookahead(f, verbose = FALSE)
  c11 <- Filter(function(v) grepl("^C11", v$check), r$violations)
  cat(sprintf("%-40s clean=%s n_viol=%d C11=%d %s\n", basename(f), as.character(r$clean), r$n_violations, length(c11),
      paste(sapply(c11, function(v) sprintf("[L%d %s]", v$line, v$check)), collapse=" ")))
}
