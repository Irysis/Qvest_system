suppressPackageStartupMessages({ library(jsonlite); library(data.table) })
setwd(Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
say <- function(fmt,...) cat(sprintf(paste0("[099] ",fmt,"\n"),...))
PL <- c("Revenue","COGS","GrossProfit","SGAExpense","OperatingProfit","PretaxIncome","TaxExpense",
        "InterestExp","InterestIncome","DepAmort","RandD","OperatingCF","InvestCF","FinanceCF",
        "Dividends","FCF1","FCF2","EBITDA","EBIT")
reg <- fromJSON("02_Infrastructure/factor_db/factor_registry.json", simplifyVector=FALSE)
blob <- sapply(reg, function(g) paste(unlist(g), collapse=" | "))
hits <- lapply(PL, function(p) names(which(sapply(blob, function(b) grepl(p, b, fixed=TRUE)))))
names(hits) <- PL
allhit <- sort(unique(unlist(hits)))
say("★유량 항목 의존 팩터: %d / %d  (%.1f%%)", length(allhit), length(reg), 100*length(allhit)/length(reg))
for (p in PL) if (length(hits[[p]])) say("  %-16s %2d건", p, length(hits[[p]]))
say("--- 카테고리 분포 ---")
cat0 <- sapply(allhit, function(k) { v <- reg[[k]]$category; if (is.null(v)) "?" else v })
print(sort(table(cat0), decreasing=TRUE))
writeLines(allhit, "stage_artifacts/fq099/flow_dependent_factors.txt")
say("전량 → stage_artifacts/fq099/flow_dependent_factors.txt")
say("=== 생산 팩터셋(STR_1715 / PG2)과의 교집합 ===")
cand <- c("04_Research/strategies/STR_1715_WT016_Iter31_GridBestProd/forward_weights.R",
          "02_Infrastructure/portfolio/forward_weights_D3_M4gAE.R")
for (f in cand) if (file.exists(f)) {
  txt <- paste(readLines(f, warn=FALSE), collapse="\n")
  used <- allhit[sapply(allhit, function(k) grepl(k, txt, fixed=TRUE))]
  say("  %-58s → 유량의존 팩터 %d건%s", basename(f), length(used),
      if(length(used)) paste0(": ", paste(head(used,12), collapse=" ")) else "")
}
