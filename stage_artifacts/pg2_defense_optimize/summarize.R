suppressPackageStartupMessages({library(data.table)})
ED_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
r <- readRDS(file.path(ED_ROOT,"stage_artifacts/pg2_defense_optimize/parity_result.rds"))
cat("gate_i_max=", r$gate_i_max, " gate_i_cor=", r$gate_i_cor, "\n")
cat("gate_ii_max=", r$gate_ii_max, "\n")
cat("engine_maxdiff=", r$engine_maxdiff, " engine_cor=", r$engine_cor, "\n")
cat("book SR=", r$book$SR, "MDD=", r$book$MDD, "PORT_t=", r$book$PORT_t, "IR=", r$book$IR,
    "calmar=", r$calmar, "CAGR=", r$CAGR, "oos=", r$oos_retention, "n=", r$n_periods, "\n")
cat("parity_pass=", r$parity_pass, "\n")
cat("\n== episodes (current defense book active) ==\n"); print(r$episodes)
