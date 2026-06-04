# temp runner for composite momentum alpha search
source("02_Infrastructure/alpha_search/run_alpha_search.R")
res <- run_alpha_search(
  strategy_name      = "AS_composite_mom",
  strategy_idea      = "composite momentum 12-1+6-1+residual",
  factor_engine_path = "G:/Quant_Module_Moltbot/02_Infrastructure/alpha_search/factor_engine_composite_mom.R",
  start_date         = "2010-01-01"
)
cat("\n===RESULT===\n")
`%||%` <- function(a,b) if (is.null(a) || length(a)==0) b else a
cat(sprintf("grade=%s score=%s pass=%s notable=%s excess=%s\n",
            res$grade, res$score %||% "NA", res$pass, res$notable, res$excess_cagr %||% "NA"))
cat("out_dir:", res$out_dir, "\n")
cat("charts:", paste(res$charts, collapse=" | "), "\n")
cat("l_code:", res$l_code %||% "NA", "\n")
