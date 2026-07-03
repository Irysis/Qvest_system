## Validate the GRID harness reproduces recon_baseline (IC + regdir arms, CUR defense).
ED_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
`%||%` <- function(a,b) if(is.null(a)||length(a)==0||all(is.na(a))) b else a
source(file.path(ED_ROOT,"stage_artifacts/pg2_defense_optimize/eval_defense_grid.R"))
CUR <- list(factors=c("Q07_Earnings_Stability","M08_Residual_Mom","Q25_Ohlson_O"), weights=NULL)
oos_med <- function(x){ v <- x %||% NA_real_; if (length(v)>1) median(v, na.rm=TRUE) else v }

Sys.setenv(ED_PANEL_SRC="ic"); .ED$ready <- FALSE; .ED$PANEL_SRC <- "ic"
r_ic <- eval_defense(CUR, regime_map=NULL, label="grid_recon_ic")
cat("\n=== GRID IC (CUR defense) vs recon_baseline IC ===\n")
cat(sprintf("GRID:      SR=%.4f MDD=%.4f calmar=%.4f CAGR=%.4f PORT_t=%.4f IR=%.4f oos=%.4f n=%d\n",
            r_ic$SR, abs(r_ic$MDD), r_ic$calmar, r_ic$CAGR, r_ic$PORT_t, r_ic$IR,
            oos_med(r_ic$oos_retention), r_ic$n_periods))
cat("BASELINE:  SR=1.8196 MDD=0.2340 calmar=1.8021 PORT_t=5.4658 IR=1.2421 n=269 (recon_baseline.json)\n")

Sys.setenv(ED_PANEL_SRC="regdir"); .ED$ready <- FALSE; .ED$PANEL_SRC <- "regdir"
r_reg <- eval_defense(CUR, regime_map=NULL, label="grid_recon_regdir")
cat("\n=== GRID regdir (CUR defense) vs recon_baseline regdir ===\n")
cat(sprintf("GRID:      SR=%.4f MDD=%.4f calmar=%.4f CAGR=%.4f PORT_t=%.4f IR=%.4f oos=%.4f n=%d\n",
            r_reg$SR, abs(r_reg$MDD), r_reg$calmar, r_reg$CAGR, r_reg$PORT_t, r_reg$IR,
            oos_med(r_reg$oos_retention), r_reg$n_periods))
cat("BASELINE:  SR=1.7741 MDD=0.2263 calmar=1.9746 PORT_t=5.1902 IR=1.2083 n=269 (recon_baseline.json)\n")

saveRDS(list(ic=r_ic, regdir=r_reg),
        file.path(ED_ROOT,"stage_artifacts/pg2_defense_optimize/validate_grid.rds"))
cat("\n[EPISODES] GRID IC:\n"); print(r_ic$episodes)
