suppressMessages({ library(jsonlite) })
.rt <- function() {
  cands <- c(Sys.getenv("CLAUDE_PROJECT_DIR", unset = ""), Sys.getenv("QM_ROOT", unset = ""),
             "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
  cands <- cands[nzchar(cands)]
  hit <- cands[file.exists(file.path(cands, "02_Infrastructure/hooks/qvest_hook_router.py"))]
  if (!length(hit)) stop("root"); hit[1]
}
setwd(.rt()); OUTD <- "04_Research/method_frontier/fq002_contract_magnitude"
r <- fromJSON(file.path(OUTD, "fq125_stage1_results.json"))
cn <- r$canonical_A_size
cat("== 게이트 ==\n"); str(r$gate$combined); str(r$gate$new_segment); cat("verdict:", r$gate$verdict, "\n")
cat("\n== canonical ==\n")
cat(sprintf("PORT_t %.4f p %.4f | IR %.4f | alpha_ann %.4f | net_SR %.4f | TO %.4f | n %d | metric_type %s\n",
            cn$portfolio_alpha_t_nw_lag3, cn$portfolio_alpha_t_pvalue, cn$information_ratio,
            cn$alpha_annualized, cn$net_sr, cn$turnover_annual, cn$n_months, cn$metric_type))
cat(sprintf("EW-uni PORT_t %.4f | post2017 %s | oos_ret_approx %s\n",
            cn$diag_ew_universe$portfolio_alpha_t_nw_lag3,
            format(cn$diag_ew_universe$post2017_t_nw_lag3), format(cn$diag_ew_universe$oos_retention_approx)))
cat("cap_tier weight_share:"); print(unlist(cn$diag_cap_tier$weight_share_avg))
cat("\n== 섭동 ==\n"); print(unlist(r$perturbation[c("q05_t_nw_pooled","q05_t_nw_family_M","q05_t_nw_family_S")]))
cat("\n== 위반주입 ==\n"); print(unlist(r$violation_injection_correction_backdate[1:7]))
cat("\n== lag1 ==\n"); print(unlist(r$lag1_stress))
cat("\n== 국면 corr ==\n"); print(unlist(r$regime[1:4]))
cat("\n== coverage ==\n"); print(unlist(r$coverage[1:4]))
cat("\n== ic_series 앞/뒤 ==\n"); print(head(r$ic_series,3)); print(tail(r$ic_series,3))
rr <- fromJSON(file.path(OUTD, "fq125_stage1_regime_robust.json"))
cat("\n== R1 순열 ==\n"); print(unlist(rr$R1_permutation))
cat("\n== R4 소비면 ==\n")
cat(sprintf("uncond PORT_t %.4f n %d SR %.4f | broad PORT_t %.4f n %d SR %.4f IR %.4f alpha_ann %.4f\n",
  rr$R4_consumption$unconditional$portfolio_alpha_t_nw_lag3, rr$R4_consumption$unconditional$n_months,
  rr$R4_consumption$unconditional$net_sr,
  rr$R4_consumption$broad_led_only$portfolio_alpha_t_nw_lag3, rr$R4_consumption$broad_led_only$n_months,
  rr$R4_consumption$broad_led_only$net_sr, rr$R4_consumption$broad_led_only$information_ratio,
  rr$R4_consumption$broad_led_only$alpha_annualized))
cc <- fromJSON(file.path(OUTD, "fq125_stage1_controls.json"))
cat("\n== C1/C2 ==\n"); print(unlist(cc$C1_size_alternative$pure_size)); print(unlist(cc$C2_size_residualized$summary))
cat("gap_retention:", cc$C2_size_residualized$gap_retention, "| rho:", cc$C2_size_residualized$cross_sec_rho_mean, "\n")
