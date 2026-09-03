suppressWarnings(suppressMessages(library(data.table)))
ROOT <- Sys.getenv("QM_ROOT"); if(!nzchar(ROOT)) ROOT <- getwd(); setwd(ROOT)
source(file.path(ROOT,"02_Infrastructure/validation/lookahead_detector.R"))
OUT <- file.path(ROOT,"stage_artifacts/WT_R20260829_007")
DEC <- c("op3_sigma_mod.R","op4_core.R","op6_emit_prep.R","op9_weights_csv.R")   # 의사결정 경로
EVA <- c("op1_engine.R","op2_sigmafree.R","op4_mvo.R","op5_compare.R","op7_diag.R","op8_asof.R","op10_hookprobe.R","op11_pit.R") # 사후 평가기
scan <- function(fs,lab){ cat("\n##",lab,"\n")
  for(f in fs){ r <- tryCatch(detect_lookahead(file.path(OUT,f), verbose=FALSE), error=function(e) NULL)
    n <- if(is.null(r)) NA else r$n_violations
    cat(sprintf("  %-22s violations=%s\n", f, ifelse(is.na(n),"ERR",n)))
    if(!is.na(n) && n>0){ print(r$violations)
      } } }
scan(DEC,"의사결정 경로 (decision path)"); scan(EVA,"사후 평가기 (evaluator — C1 오탐 예상 구간)")
