suppressPackageStartupMessages({ library(data.table) })
setwd(Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
say <- function(fmt,...) cat(sprintf(paste0("[099a] ",fmt,"\n"),...))
flow <- readLines("stage_artifacts/fq099/flow_dependent_factors.txt")
PLI <- c("Revenue","COGS","GrossProfit","SGAExpense","OperatingProfit","PretaxIncome","TaxExpense",
         "InterestExp","InterestIncome","DepAmort","RandD","OperatingCF","InvestCF","FinanceCF",
         "Dividends","FCF1","FCF2","EBITDA","EBIT")
cands <- c("qepm/mailbox/worktask/WT-D20260425_010/factor_engine_proposal.R",
           "qepm/mailbox/worktask/WT-D20260430_001/stage_artifacts/factor_engine.R",
           "stage_artifacts/WT_D20260425_010/_recompute_alpha_asof.R")
for (p in cands) {
  if (!file.exists(p)) { say("부재: %s", p); next }
  txt <- paste(readLines(p, warn=FALSE), collapse="\n")
  say("=== %s (%d줄) ===", basename(p), length(strsplit(txt,"\n")[[1]]))
  say("   fundamental_merged 참조 : %s", grepl("fundamental_merged", txt, fixed=TRUE))
  say("   load_month_factors 경유 : %s", grepl("load_month_factors", txt, fixed=TRUE))
  hf <- flow[sapply(flow, function(k) grepl(k, txt, fixed=TRUE))]
  hi <- PLI [sapply(PLI,  function(k) grepl(k, txt, fixed=TRUE))]
  say("   유량의존 팩터코드 %2d건 %s", length(hf), if(length(hf)) paste0(": ",paste(head(hf,15),collapse=" ")) else "")
  say("   ★유량 원항목      %2d건 %s", length(hi), if(length(hi)) paste0(": ",paste(hi,collapse=" ")) else "")
}
