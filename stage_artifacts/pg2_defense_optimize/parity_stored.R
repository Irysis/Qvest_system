## Isolation test: feed STORED score_defense_z (not recon) through the SAME engine.
## If book metrics then reproduce baseline -> engine/overlay path is faithful and the
## ONLY parity break is def_z reconstruction (cache vintage drift). Confirms diagnosis.
suppressPackageStartupMessages({library(data.table); library(arrow); library(jsonlite)})
options(scipen=999); setDTthreads(1L)
ED_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
source(file.path(ED_ROOT,"stage_artifacts/pg2_defense_optimize/eval_defense.R"))
ed_init()

## Build a def_z that is EXACTLY the stored score_defense_z (identity), bypass recon.
## We monkeypatch by injecting stored defz into the same downstream path.
AP <- .ED$AP
## replicate eval_defense internals but with def_z := stored_defz
sc <- AP[, .(Date, Ticker, score_core_z, regime_state, def_z=score_defense_z, stored_eff=score_eff)]
sc[, score_eff := 0.65*score_core_z + 0.35*def_z]
## sanity: does 0.65*core_z+0.35*stored_defz == stored score_eff?
chk <- sc[!is.na(score_eff) & !is.na(stored_eff)]
cat(sprintf("[identity chk] 0.65core+0.35storeddef vs stored_eff: max|diff|=%.2e cor=%.6f\n",
            max(abs(chk$score_eff-chk$stored_eff),na.rm=TRUE), cor(chk$score_eff,chk$stored_eff)))

cb <- .carrier_book(sc[, .(Date, Ticker, score_eff, regime_state)])
cb[, realized_ym := format(eval_date, "%Y-%m")]
mp <- merge(.ED$P5, cb[, .(realized_ym, base_gross=port_ret_gross_recon)], by="realized_ym", all.x=TRUE)
setorder(mp, realized_ym)
mp[, ret_orig_use := ifelse(is.finite(base_gross), base_gross, ret_orig_book)]
COST <- 0.0015
mp[, dR05 := abs(beta_R05 - shift(beta_R05,1,fill=1.0))]
mp[, ret_noL4 := beta_R05*m4*ret_orig_use - dR05*COST]
mp <- mp[is.finite(ret_noL4)]
## engine faithfulness vs 5-panel ret_orig
og <- mp[is.finite(base_gross)]
cat(sprintf("[ENGINE stored-eff] base_gross vs 5-panel ret_orig: max|diff|=%.5f cor=%.5f n=%d\n",
            max(abs(og$base_gross-og$ret_orig_book)), cor(og$base_gross,og$ret_orig_book), nrow(og)))

## ALSO: pure book using 5-panel ret_orig verbatim (no recon at all) -> must hit 1.898
mp[, ret_noL4_book := beta_R05*m4*ret_orig_book - dR05*COST]
suppressPackageStartupMessages({library(PerformanceAnalytics); library(xts)})
sr_recon <- as.numeric(table.AnnualizedReturns(xts(mp$ret_noL4, order.by=mp$anchor_date), scale=12)[3,1])
sr_book  <- as.numeric(table.AnnualizedReturns(xts(mp$ret_noL4_book, order.by=mp$anchor_date), scale=12)[3,1])
mdd <- function(r){c<-cumprod(1+r);min(c/cummax(c)-1)}
cat(sprintf("\n[SR] stored-eff recon-engine noL4 SR=%.4f | 5-panel ret_orig verbatim noL4 SR=%.4f (target 1.898)\n", sr_recon, sr_book))
cat(sprintf("[MDD] recon=%.4f | book-verbatim=%.4f (target 0.233)\n", mdd(mp$ret_noL4), mdd(mp$ret_noL4_book)))
