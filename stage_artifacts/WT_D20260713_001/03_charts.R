#==============================================================================
# WT-D20260713_001 R17 — Step 03: charts (standard 3 for best factor + sweep bar)
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow) })
setDTthreads(1L); try(arrow::set_io_thread_count(2L), silent=TRUE)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
OUT  <- file.path(ROOT, "stage_artifacts/WT_D20260713_001")
source(file.path(ROOT,"02_Infrastructure/contracts/backtest_result_contract.R"))
source(file.path(ROOT,"02_Infrastructure/contracts/canonical_screen_bt.R"))
source(file.path(ROOT,"02_Infrastructure/telegram/tg_chart_pack.R"))

res <- readRDS(file.path(OUT,"canon_results.rds"))
pan <- readRDS(file.path(OUT,"panels.rds"))
tvec <- c(FA=res$FA$port_t_full, FB=res$FB$port_t_full, FC=res$FC$port_t_full)
best <- names(which.max(tvec))
fmap <- c(FA="scores_FA.parquet", FB="scores_FB.parquet", FC="scores_FC.parquet")
sc <- as.data.table(read_parquet(file.path(OUT, fmap[best])))
cf <- canonical_screen_bt(sc[,.(Date,Ticker,score)], pan$returns_all, pan$bench_all, top_n=25L,
  cost_bps_oneway=15, liq_dt=pan$liq_all, liq_min=2e8, size_dt=pan$size_all,
  diag_dual_basis=TRUE, run_id=paste0("r17_",best,"_chart"), strategy_id=best)
pr <- as.data.table(cf$period_returns)
nm <- c(FA="F-A 텍스트유사도(Lazy Prices)", FB="F-B 제출지연", FC="F-C insider공시량 급변")
mn <- sprintf("cap-w PORT_t %.2f · EW-uni t %.2f · rank-IC %.3f · net-SR %.2f (canonical screening, 실측)",
              res[[best]]$port_t_full, res[[best]]$ew_t, res[[best]]$rank_ic, res[[best]]$net_sr)
paths <- tg_chart_pack(pr, out_dir=file.path(OUT,"charts"),
  title=paste0("WT-D20260713_001 R17 · 최선 ", nm[best]),
  metrics_note=mn, bm_label="KOSPI200∪KQ150(cap-w)", prefix=paste0("best_",best,"_"))

# sweep bar: 3-factor cap-w PORT_t
sp <- tg_chart_sweep(
  labels=c("F-A 텍스트유사도","F-B 제출지연","F-C insider공시량"),
  values=round(as.numeric(tvec),2),
  out_dir=file.path(OUT,"charts"),
  title="R17 3종 팩터 cap-w PORT_t (HARD 2.95)",
  hline=2.95, hline_label="졸업 HARD 2.95", highlight=nm[best],
  filename="r17_sweep_port_t.png")

allpaths <- c(paths, sp)
writeLines(allpaths, file.path(OUT,"chart_paths.txt"))
cat("[03] charts:\n"); cat(paste(allpaths, collapse="\n"),"\n")
cat("[03] best factor:", best, " PORT_t=", round(tvec[best],2),"\n")
cat("[03] DONE\n")
