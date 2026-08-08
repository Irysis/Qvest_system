suppressPackageStartupMessages({ library(jsonlite) })
ROOT <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
say <- function(fmt,...) cat(sprintf(paste0("[099] ",fmt,"\n"),...))
PL <- c("Revenue","COGS","GrossProfit","SGAExpense","OperatingProfit","PretaxIncome","TaxExpense",
        "InterestExp","InterestIncome","DepAmort","RandD","OperatingCF","InvestCF","FinanceCF",
        "Dividends","FCF1","FCF2")
reg <- fromJSON("02_Infrastructure/factor_db/factor_registry.json", simplifyVector=FALSE)
say("factor 수 %d (예: %s)", length(reg), paste(head(names(reg),3), collapse=", "))
## ★전 필드 스캔 (필드명 추측 금지)
blob <- sapply(reg, function(f) paste(unlist(f), collapse=" | "))
hits <- lapply(PL, function(p) names(which(sapply(blob, function(b) grepl(paste0("\b",p,"\b"), b)))))
names(hits) <- PL
allhit <- sort(unique(unlist(hits)))
say("유량 항목 의존 팩터: %d / %d", length(allhit), length(reg))
for (p in PL) if (length(hits[[p]])) say("  %-16s %2d건: %s", p, length(hits[[p]]), paste(head(hits[[p]],10),collapse=" "))
writeLines(allhit, "stage_artifacts/fq099/flow_dependent_factors.txt")
say("→ stage_artifacts/fq099/flow_dependent_factors.txt (%d건)", length(allhit))
