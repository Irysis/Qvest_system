#!/usr/bin/env Rscript
# p1b — turnover proxy 가 실제로 구성 가능한지 실사. "가능하면" 조건절의 근거를 만든다.
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
PROJ <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", ""))
if (!nzchar(PROJ)) PROJ <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
setwd(PROJ); OUT <- file.path(PROJ, "stage_artifacts/scrap_ensemble_20260809")
sink(file.path(OUT, "p1b_turnover_probe.log"), split = TRUE)

P <- readRDS(file.path(OUT, "p0_panel.rds"))
MP <- fromJSON(file.path(PROJ, "06_Registry/module_performance.json"), simplifyVector = FALSE)
cat(sprintf("module_performance.json: %d modules registered\n", length(MP$modules)))

probe <- head(P$scrap_ok, 4)
for (sid in probe) {
  ent <- MP$modules[[sid]]
  if (is.null(ent)) { cat(sprintf("%-34s <not in registry>\n", sid)); next }
  cat(sprintf("\n--- %s ---\n", sid))
  cat(sprintf("  registry fields: %s\n", paste(names(ent), collapse=", ")))
  tv <- unlist(ent)[grepl("turn", names(unlist(ent)), ignore.case=TRUE)]
  cat(sprintf("  turnover-like registry fields: %s\n",
              if (length(tv)) paste(names(tv), tv, sep="=", collapse=" ") else "<none>"))
  p <- file.path(PROJ, ent$sim_result_path)
  if (!file.exists(p)) { cat(sprintf("  sim_result missing: %s\n", p)); next }
  s <- tryCatch(readRDS(p), error=function(e) NULL)
  if (is.null(s)) { cat("  <load fail>\n"); next }
  cat(sprintf("  sim_result size=%.1f KB  names: %s\n", file.size(p)/1024,
              paste(names(s), collapse=", ")))
  if ("HOLDINGS_LOG" %in% names(s)) {
    H <- s$HOLDINGS_LOG
    cat(sprintf("  HOLDINGS_LOG class=%s\n", paste(class(H), collapse="/")))
    if (is.data.frame(H)) {
      H <- as.data.table(H)
      cat(sprintf("    dim=%dx%d cols=%s\n", nrow(H), ncol(H), paste(names(H), collapse=",")))
      print(head(H, 3))
    } else if (is.list(H)) {
      cat(sprintf("    list len=%d  names(head)=%s\n", length(H), paste(head(names(H),3), collapse=",")))
      print(head(H[[1]], 3))
    }
  }
}
cat("\n[done]\n"); sink()
