## PARITY GATE — reconstruct current defense (Q07/M08/Q25 EW), run eval_defense,
## and compare to noLayer4 baseline (SR 1.898 / MDD 23.3% / PORT_t 6.21 / IR 1.416).
suppressPackageStartupMessages({library(data.table); library(arrow); library(jsonlite)})
options(scipen=999); setDTthreads(1L)
ED_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
source(file.path(ED_ROOT,"stage_artifacts/pg2_defense_optimize/eval_defense.R"))
ed_init()

CUR <- list(factors=c("Q07_Earnings_Stability","M08_Residual_Mom","Q25_Ohlson_O"), weights=NULL)
cat("\n=== eval_defense(CURRENT defense EW) ===\n")
r <- eval_defense(CUR, label="current")

## GATE (i): recon def_z vs stored score_defense_z
d <- r$score_eff[!is.na(def_z) & !is.na(stored_defz)]
gate_i_max <- max(abs(d$def_z - d$stored_defz), na.rm=TRUE)
gate_i_cor <- cor(d$def_z, d$stored_defz)
# per-year breakdown
d[, yr := year(Date)]
byyr <- d[, .(maxdiff=max(abs(def_z-stored_defz)), cor=cor(def_z,stored_defz), n=.N), by=yr][order(yr)]

## GATE (ii): score_eff_new vs stored score_eff
e <- r$score_eff[!is.na(score_eff) & !is.na(stored_eff)]
gate_ii_max <- max(abs(e$score_eff - e$stored_eff), na.rm=TRUE)
gate_ii_cor <- cor(e$score_eff, e$stored_eff)

## GATE (iii): book metrics vs baseline
tgt <- list(SR=1.898, MDD=0.233, PORT_t=6.21, IR=1.416)
tol <- list(SR=0.03, MDD=0.005, PORT_t=0.15, IR=0.03)
mm <- list(SR=r$SR, MDD=abs(r$MDD), PORT_t=r$PORT_t, IR=r$IR)
gate_iii <- rbindlist(lapply(names(tgt), function(k){
  diff <- mm[[k]]-tgt[[k]]; pass <- is.finite(diff) && abs(diff) <= tol[[k]]
  data.table(metric=k, got=round(mm[[k]],4), target=tgt[[k]], diff=round(diff,4), tol=tol[[k]], pass=pass)
}))

cat(sprintf("\n[GATE i]  def_z vs stored: max|diff|=%.6f cor=%.5f n=%d (need <1e-4)\n", gate_i_max, gate_i_cor, nrow(d)))
print(byyr)
cat(sprintf("\n[GATE ii] score_eff vs stored: max|diff|=%.6f cor=%.5f n=%d\n", gate_ii_max, gate_ii_cor, nrow(e)))
cat("\n[GATE iii] book metrics:\n"); print(gate_iii)
cat(sprintf("\n[BOOK] SR=%.4f MDD=%.4f calmar=%.4f CAGR=%.4f PORT_t=%.4f IR=%.4f oos_ret=%.4f n=%d\n",
            r$SR, r$MDD, r$calmar, r$CAGR, r$PORT_t, r$IR, r$oos_retention %||% NA, r$n_periods))

## also: base_gross recon vs 5-panel ret_orig (engine faithfulness)
mm2 <- r$monthly[is.finite(ret_orig_use) & is.finite(ret_orig_book)]
og_max <- max(abs(mm2$ret_orig_use - mm2$ret_orig_book), na.rm=TRUE)
og_cor <- cor(mm2$ret_orig_use, mm2$ret_orig_book)
cat(sprintf("\n[ENGINE] recon base_gross vs 5-panel ret_orig: max|diff|=%.5f cor=%.5f n=%d\n", og_max, og_cor, nrow(mm2)))

parity_pass <- (gate_i_max < 1e-4) &&
               all(gate_iii$pass)
cat(sprintf("\n[PARITY_PASS] = %s\n", parity_pass))

saveRDS(list(gate_i_max=gate_i_max, gate_i_cor=gate_i_cor, byyr=byyr,
             gate_ii_max=gate_ii_max, gate_iii=gate_iii, book=mm,
             calmar=r$calmar, CAGR=r$CAGR, oos_retention=r$oos_retention,
             engine_maxdiff=og_max, engine_cor=og_cor, n_periods=r$n_periods,
             episodes=r$episodes, parity_pass=parity_pass),
        file.path(ED_ROOT,"stage_artifacts/pg2_defense_optimize/parity_result.rds"))
cat("[saved] parity_result.rds\n")
