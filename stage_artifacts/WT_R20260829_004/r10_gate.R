# R10 — detect_lookahead 하드 게이트(risk 스크립트 전수) + challenge review 기록
suppressWarnings(suppressMessages({library(data.table); library(jsonlite)}))
ROOT <- Sys.getenv("QM_ROOT"); if(!nzchar(ROOT)) ROOT <- getwd(); setwd(ROOT)
Sys.setenv(CLAUDE_PROJECT_DIR = ROOT)
source(file.path(ROOT,"02_Infrastructure/validation/lookahead_detector.R"))
OUT <- file.path(ROOT,"stage_artifacts/WT_R20260829_004")
files <- c("r1_inputs.R","r2_model.R","r3_sigma.R","r4_regime.R","r5_tail_stress.R",
           "r6_emit.R","r7_package.R","r8_selfadv.R","r9_patch.R")
res <- lapply(files, function(f) { p <- file.path(OUT,f)
  z <- tryCatch(detect_lookahead(p, verbose=FALSE), error=function(e) list(clean=NA, error=conditionMessage(e)))
  list(file=f, clean=z$clean, n_violations=if(!is.null(z$violations)) length(z$violations) else NA,
       detail=z) })
for (z in res) cat(sprintf("[detect_lookahead] %-18s clean=%s violations=%s\n", z$file,
                            as.character(z$clean), as.character(z$n_violations)))
all_clean <- all(sapply(res, function(z) isTRUE(z$clean)))
cat("[R10] 전체 clean:", all_clean, "\n")
bad <- Filter(function(z) !isTRUE(z$clean), res)
if (length(bad)) for (z in bad) { cat("---", z$file, "---\n"); print(z$detail) }
write_json(list(gate="detect_lookahead", scanned=length(files), all_clean=all_clean,
                per_file=lapply(res, function(z) list(file=z$file, clean=z$clean, n_violations=z$n_violations))),
           file.path(OUT,"pit_gate_risk.json"), pretty=TRUE, auto_unbox=TRUE, na="null")
