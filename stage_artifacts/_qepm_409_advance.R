QM <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
source(file.path(QM, "02_Infrastructure/worktask/worktask_manager.R"))
for (w in c("WT-D20260614_001","WT-D20260614_002")) {
  r <- tryCatch(wt_advance(w, "ALPHA_DONE"), error=function(e) paste("ERR:",conditionMessage(e)))
  cat(w, "->", if (is.character(r)) r else "ALPHA_DONE ok", "\n")
}
