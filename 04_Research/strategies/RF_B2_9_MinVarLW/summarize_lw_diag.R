# summarize_lw_diag.R — B2-9 LW 퇴화 진단 4종 분포 요약 (보고 ① 산출)
# 입력: lw_diagnostics.csv (엔진이 매 리밸런싱일 기록)
suppressPackageStartupMessages(library(data.table))
D <- fread("C:/Users/99922/OneDrive/Quant_Module_Moltbot/04_Research/strategies/RF_B2_9_MinVarLW/lw_diagnostics.csv")
D <- D[Date >= as.Date("2005-01-01")]
cat(sprintf("n_rebal(2005+)=%d\n", nrow(D)))
print(D[, .N, by = mode])
K <- D[mode == "MINVAR_LW"]
f <- function(nm, v, dg = 4) cat(sprintf("%-12s med %.*f | p10 %.*f | p90 %.*f | min %.*f | max %.*f\n",
                                         nm, dg, median(v, na.rm = TRUE), dg, quantile(v, .10, na.rm = TRUE),
                                         dg, quantile(v, .90, na.rm = TRUE), dg, min(v, na.rm = TRUE),
                                         dg, max(v, na.rm = TRUE)))
f("delta", K$delta); f("cond", K$cond, 1); f("erank", K$erank, 2)
f("rho_shrunk", K$rho_shrunk); f("rho_sample", K$rho_sample)
f("n_obs", K$n_obs, 0); f("w_max", K$w_max); f("n_eff", K$n_eff, 2); f("n_zero", K$n_zero, 0)
cat(sprintf("delta>=0.90 months: %d (%.1f%%) | delta>=0.99: %d\n",
            sum(K$delta >= .90), 100 * mean(K$delta >= .90), sum(K$delta >= .99)))
cat(sprintf("rho_shrunk>=0.90: %d | w_max>=0.30: %d (%.1f%%)\n",
            sum(K$rho_shrunk >= .90, na.rm = TRUE), sum(K$w_max >= .30), 100 * mean(K$w_max >= .30)))
# 연도별 delta 추이 (포화 시점 특정)
cat("\n[연도별] delta med · cond med · erank med · w_max med · n_obs med · mode 구성\n")
K[, yr := year(Date)]
print(D[, .(n = .N, minvar = sum(mode == "MINVAR_LW")), by = .(yr = year(Date))][
  K[, .(delta = round(median(delta), 3), cond = round(median(cond), 1),
        erank = round(median(erank), 2), w_max = round(median(w_max), 3),
        n_obs = median(n_obs)), by = yr], on = "yr"])
