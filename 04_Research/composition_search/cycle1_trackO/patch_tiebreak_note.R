# Append tie-break audit detail to combine_ab_results.json (no metric changes)
suppressPackageStartupMessages({ library(jsonlite) })
OUT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/04_Research/composition_search/cycle1_trackO"
j <- read_json(file.path(OUT, "combine_ab_results.json"))
j$is_selection$tie_break_audit <- list(
  tie_set = c("O3_MIDBAND_FLOOR", "O4_POWER_RHO"),
  note = "O4 IS SR 1.9180 within 0.005 of O3 1.9209 -> tie-break invoked. Unrounded IS MDD identical for both (-0.248053799245, shared 2008 drawdown episode under deep-guard) -> MDD tie-break indecisive -> argmax IS SR stands = O3_MIDBAND_FLOOR. Selection unchanged from commit.",
  o3_is_mdd_unrounded = -0.248053799245,
  o4_is_mdd_unrounded = -0.248053799245,
  audit_script = "tiebreak_audit.R"
)
write_json(j, file.path(OUT, "combine_ab_results.json"),
           pretty = TRUE, auto_unbox = TRUE, digits = 10)
cat("[patched] tie_break_audit appended to combine_ab_results.json\n")
