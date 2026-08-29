## p4_pit_gate.R — detect_lookahead 하드 게이트 (엔진 전 파일)
QM <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(QM)
source("02_Infrastructure/validation/lookahead_detector.R")
files <- c("stage_artifacts/WT_R20260829_001/p1_build_panel.R",
           "stage_artifacts/WT_R20260829_001/p2_measure.R",
           "stage_artifacts/WT_R20260829_001/p3_diagnostics.R")
res <- list()
for (f in files) {
  r <- detect_lookahead(f, verbose = FALSE)
  res[[basename(f)]] <- list(scanned = isTRUE(r$scanned), clean = r$clean,
                             n_violations = r$n_violations)
  cat(sprintf("%-24s scanned=%s clean=%s n_viol=%d\n", basename(f),
              isTRUE(r$scanned), as.character(r$clean), r$n_violations))
  if (isTRUE(r$n_violations > 0)) print(r$violations)
}
jsonlite::write_json(res, "stage_artifacts/WT_R20260829_001/pit_lookahead_scan.json",
                     auto_unbox = TRUE, na = "null")
