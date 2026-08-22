library(jsonlite)
setwd(Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
v <- fromJSON("stage_artifacts/WT-D20260821_002/verdict_result.json", simplifyVector = FALSE)
for (pn in names(v$axis2_skew_interaction)) {
  a <- v$axis2_skew_interaction[[pn]]
  cat("\n== axis2:", pn, "==\n")
  cat(sprintf("  monthlyCS n=%d  skew mean %+.4f  sd %.4f\n", a$n, a$skew_mean, a$skew_sd))
  cat(sprintf("  slope %+.6f  se %.6f  t %+.4f  p %.5f   (1sd -> ann %+.4f%%p)\n",
              a$slope, a$se_nw3, a$t_nw3, a$p_nw3, a$effect_per_1sd_skew_annual_pct))
  cat(sprintf("  +disp ctrl: skew slope %+.6f t %+.4f | disp slope %+.6f t %+.4f\n",
              a$slope_ctrl_disp, a$t_ctrl_disp, a$disp_slope, a$disp_t))
  d <- a$daily_variant
  if (!is.null(d$t_nw3))
    cat(sprintf("  dailyCS  n=%d  slope %+.6f  t %+.4f  p %.5f  (1sd -> ann %+.4f%%p)  skew mean %+.4f sd %.4f\n",
                d$n, d$slope, d$t_nw3, d$p_nw3, d$effect_per_1sd_skew_annual_pct, d$skew_mean, d$skew_sd))
}
