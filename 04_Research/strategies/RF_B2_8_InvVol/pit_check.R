Sys.setenv(CLAUDE_PROJECT_DIR = "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
source("02_Infrastructure/config.R")
source(file.path(VALIDATION_DIR, "lookahead_detector.R"))
for (f in c("04_Research/strategies/RF_B2_8_InvVol/fe_b2_8_invvol.R",
            "04_Research/strategies/RF_B2_8_InvVol/fe_b2_8_ctrl_ew.R")) {
  p <- parse(f)
  r <- detect_lookahead(f)
  cat(basename(f), "| parse-exprs", length(p), "| clean =", isTRUE(r[["clean"]]), "\n")
}
