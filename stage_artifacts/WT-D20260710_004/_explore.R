# WT-D20260710_004 Stage A — data schema exploration (read-only, no selection)
suppressMessages({library(arrow); library(data.table)})
setDTthreads(1)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"

cat("=== tier_panel.parquet (score_eff book base) ===\n")
tp <- tryCatch(read_parquet(file.path(ROOT,"stage_artifacts","WT_D20260706_MIDCAP","tier_panel.parquet")), error=function(e){cat("ERR",conditionMessage(e),"\n");NULL})
if(!is.null(tp)){
  tp <- as.data.table(tp)
  cat("cols:", paste(names(tp), collapse=", "), "\n")
  cat("rows:", nrow(tp), " dates:", length(unique(tp$Date)), " range:", as.character(min(tp$Date)),"..",as.character(max(tp$Date)),"\n")
  cat("score_eff non-NA:", sum(!is.na(tp$score_eff)), " in_univ TRUE:", sum(tp$in_univ==TRUE, na.rm=TRUE), "\n")
  cat("has score_core_z:", "score_core_z" %in% names(tp), " score_defense_z:", "score_defense_z" %in% names(tp), "\n")
}

cat("\n=== buyback_decisions_clean.parquet ===\n")
bb <- tryCatch(read_parquet(file.path(ROOT,".cache","dart","buyback_decisions_clean.parquet")), error=function(e){cat("ERR",conditionMessage(e),"\n");NULL})
if(!is.null(bb)){
  bb <- as.data.table(bb)
  cat("cols:", paste(names(bb), collapse=", "), "\n")
  cat("rows:", nrow(bb), "\n")
  print(head(bb, 3))
  if("Ticker" %in% names(bb)) cat("unique tickers:", length(unique(bb$Ticker)), "\n")
}

cat("\n=== insider_trades (exec net buy) — check if useful ===\n")
it <- tryCatch(read_parquet(file.path(ROOT,".cache","dart","insider_trades.parquet")), error=function(e){cat("ERR",conditionMessage(e),"\n");NULL})
if(!is.null(it)){ it<-as.data.table(it); cat("cols:", paste(names(it),collapse=", "),"rows:",nrow(it),"\n") }

cat("\n=== benchmark.parquet ===\n")
bm <- tryCatch(read_parquet(file.path(ROOT,".cache","benchmark.parquet")), error=function(e){cat("ERR",conditionMessage(e),"\n");NULL})
if(!is.null(bm)){ bm<-as.data.table(bm); cat("cols:", paste(names(bm),collapse=", "),"rows:",nrow(bm),"\n"); print(head(bm,2)) }
