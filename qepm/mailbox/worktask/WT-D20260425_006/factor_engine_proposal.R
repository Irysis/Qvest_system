# WT-D20260425_006 factor_engine_proposal.R (Alpha hand-off → Forge)
# baseline 6F mix unchanged (inherited from WT-D20260425_003 PRIMARY)
# overlay layer (DD Brake + VolReg) NEW.

baseline_factors <- c("C01_SUE","C04_ESBR","C02_EPS_Chg_1m",
                      "C06_TP_Gap","Q07_Earnings_Stability","AC21_CF_to_Accrual_Ratio")
factor_weights   <- c(C01_SUE=0.1450, C04_ESBR=0.2005, C02_EPS_Chg_1m=0.1119,
                      C06_TP_Gap=0.0090, Q07_Earnings_Stability=0.2806,
                      AC21_CF_to_Accrual_Ratio=0.2529)
factor_weights   <- factor_weights / sum(factor_weights)

# Overlay parameters (DD Brake)
overlay_dd <- list(entry_pct=0.06, exit_pct=0.08, lookback_d=20L,
                   brake_mult_on=0.5, brake_mult_off=1.0, lag="t-1")
# Overlay parameters (VolReg)
overlay_vr <- list(target_vol_ann=0.12, lookback_d=60L, cap=c(0,1.5), lag="t-1")

# Effective alpha:  alpha_eff(t) = composite_z(t) * dd_brake_mult(t-1) * volreg_mult(t-1)
# Forge: see stage_artifacts/WT_WT-D20260425_006/run_alpha_research.R for canonical impl.

