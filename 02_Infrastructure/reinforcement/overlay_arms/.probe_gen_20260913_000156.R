root <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
source(file.path(root, "02_Infrastructure/reinforcement/overlay_probe.R"))
r <- overlay_probe_arm("gen_20260913_000156", root)
print(r$checks)
cat("OK=", isTRUE(r$ok), " axis=", as.character(r$axis), " reason=", as.character(r$reason),
    " mean_expo=", as.numeric(r$mean_exposure), " t_var=", as.numeric(r$t_var), "\n")
