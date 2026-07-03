## Run cheap methods + Schur grid + tail-dep + network. Heavy methods separate.
source("C:/Users/99922/OneDrive/Quant_Module_Moltbot/stage_artifacts/pg2_frontier_hrp/10_frontier_measure.R")
OUT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/stage_artifacts/pg2_frontier_hrp"

runs <- list()
addrun <- function(label, mg) { runs[[label]] <<- mg; cat(sprintf("  done: %-28s n=%d PORT_t=%.3f IR=%.3f\n", label, nrow(mg), nwt(mg$active), IRf(mg$active))) }

cat("=== baselines ===\n")
addrun("LinearTilt(baseline)", run_method("lineartilt"))
addrun("EW",                    run_method("ew"))
addrun("hrp_legacy",            run_method("hrp_legacy"))
addrun("minvar",                run_method("minvar"))
addrun("nco",                   run_method("nco"))

cat("=== Schur pure-risk gamma sweep ===\n")
for (g in schur_gamma_grid) addrun(sprintf("Schur_g%.2f", g), run_method("schur", schur_gamma = g))
cat("=== Schur x alpha-tilt gamma sweep ===\n")
for (g in schur_gamma_grid) addrun(sprintf("Schur_g%.2f_tilt", g), run_method("schur", schur_gamma = g, alpha_tilt = TRUE))

cat("=== tail-dep (Lohre lower-TDC HRP) ===\n")
addrun("TailDep_HRP",       run_method("taildep"))
addrun("TailDep_HRP_tilt",  run_method("taildep", alpha_tilt = TRUE))

cat("=== network RP ===\n")
addrun("Network_softmax",   run_method("network"))
addrun("Network_prop",      run_method("network_prop"))
addrun("Network_prop_tilt", run_method("network_prop", alpha_tilt = TRUE))

saveRDS(runs, file.path(OUT, "runs_cheap.rds"))

## summary + bookmarginal tables
summ <- rbindlist(lapply(names(runs), function(k) summarize_method(runs[[k]], k)))
bm   <- rbindlist(lapply(names(runs), function(k) bookmarginal(runs[[k]], k)))
fwrite(summ, file.path(OUT, "summary_cheap.csv"))
fwrite(bm,   file.path(OUT, "bookmarginal_cheap.csv"))
cat("\n===== SUMMARY (overlay applied) =====\n"); print(summ)
cat("\n===== BOOK-MARGINAL vs incumbent (1.4055) =====\n"); print(bm)
cat("\n[DONE cheap] saved runs_cheap.rds / summary_cheap.csv / bookmarginal_cheap.csv\n")
