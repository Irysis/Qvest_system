## 오버레이 invested-fraction 추출용 구조 점검 → plain ASCII 요약 파일로 덤프.
suppressPackageStartupMessages({ library(arrow); library(data.table) })
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
PD <- file.path(ROOT,"05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2")
sink(file.path(ROOT,"stage_artifacts/pg2_overlay_gate_composition_20260705/overlay_inspect.txt"))
cat("=== carrier cols ===\n")
c1 <- tryCatch(as.data.table(read_parquet(file.path(ROOT,"06_Registry/book_carrier/carrier_STR_1715_AR_on_M4_R05_overlay_PG2.parquet"))), error=function(e){cat("ERR",conditionMessage(e),"\n");NULL})
if(!is.null(c1)){ cat("cols:",paste(names(c1),collapse=" | "),"\n"); cat("nrow:",nrow(c1),"\n")
  num <- names(c1)[sapply(c1,is.numeric)]; cat("numeric ranges:\n"); for(nm in num) cat(sprintf("  %s: [%.4f, %.4f] mean=%.4f\n", nm, min(c1[[nm]],na.rm=T), max(c1[[nm]],na.rm=T), mean(c1[[nm]],na.rm=T))) }
cat("\n=== bt_result_layer5_R05.rds ===\n")
bt <- tryCatch(readRDS(file.path(PD,"04_backtest_results/bt_result_layer5_R05.rds")), error=function(e){cat("ERR",conditionMessage(e),"\n");NULL})
if(!is.null(bt)){ cat("top names:",paste(names(bt),collapse=" | "),"\n")
  for(comp in c("period_returns","nav","holdings")){ if(!is.null(bt[[comp]])){ x<-bt[[comp]]
    cat(sprintf("[%s] class=%s cols=%s nrow=%s\n", comp, class(x)[1], if(is.data.frame(x)) paste(names(x),collapse=",") else "-", if(is.data.frame(x)) nrow(x) else length(x))) } } }
cat("\n=== search overlay/exposure signal files ===\n")
sink()
cat("written overlay_inspect.txt\n")
