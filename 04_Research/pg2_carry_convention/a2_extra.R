suppressPackageStartupMessages(library(data.table)); setDTthreads(1)
p <- fread("C:/Users/99922/AppData/Local/Temp/claude/C--Users-99922-OneDrive-Quant-Module-Moltbot/3d6b0eb6-6786-4a56-916d-9681f94897fe/scratchpad/a2_panel_carry.csv")
t12 <- tail(p,12)
cat(sprintf("last12m: mean cashfrac=%.3f, mean rf=%.2f%%, carry(ann)=%.3f%%p\n", mean(t12$cashfrac), mean(t12$rf_used), 100*mean(t12$cashfrac*t12$rf_m)*12))
m <- mean(p$ret_noL4); s <- sd(p$ret_noL4)
cat(sprintf("current mean=%.4f/m sd=%.4f/m (ann vol %.3f) SR_a=%.3f\n", m, s, s*sqrt(12), m/s*sqrt(12)))
cat(sprintf("SR2.5 @same vol: need mean %.4f/m (+%.2f%%p/yr) | @same mean: need ann vol %.3f (%.0f%% down)\n",
 2.5*s/sqrt(12), 12*100*(2.5*s/sqrt(12)-m), m*sqrt(12)/2.5, 100*(1-(m*sqrt(12)/2.5)/(s*sqrt(12)))))
cc <- p[regime %in% c("CAUTION","CRISIS")]
cat(sprintf("CAUTION+CRISIS %dm: mean cashfrac %.3f, carry ann %.2f%%p (in-month)\n", nrow(cc), mean(cc$cashfrac), 100*mean(cc$cashfrac*cc$rf_m)*12))
