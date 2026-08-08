suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
ROOT <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
say <- function(fmt,...) cat(sprintf(paste0("[099] ",fmt,"\n"),...))
PL <- c("Revenue","COGS","GrossProfit","SGAExpense","OperatingProfit","PretaxIncome","TaxExpense",
        "InterestExp","NetInterestExp","TotalNetInterestExp","InterestIncome","DepAmort","RandD",
        "OrdRandD","OperatingCF","InvestCF","FinanceCF","Dividends","FCF1","FCF2")
reg <- fromJSON("02_Infrastructure/factor_db/factor_registry.json", simplifyDataFrame=FALSE)
fl <- if (!is.null(reg$factors)) reg$factors else reg
say("registry 항목 %d", length(fl))
hit <- Filter(function(f){
  d <- paste(unlist(f[intersect(names(f), c("definition","formula","inputs","source_items"))]), collapse=" ")
  any(sapply(PL, function(p) grepl(paste0("\b",p,"\b"), d)))
}, fl)
say("유량 항목을 정의에 쓰는 팩터: %d", length(hit))
nm <- sapply(hit, function(f) f$code %||% f$factor_code %||% f$name %||% "?")
`%||%` <- function(a,b) if(is.null(a)) b else a
nm <- sapply(hit, function(f) { for (k in c("code","factor_code","name","id")) if(!is.null(f[[k]])) return(f[[k]]); "?" })
say("예시 30: %s", paste(head(nm,30), collapse=", "))
writeLines(as.character(nm), "stage_artifacts/fq099/flow_dependent_factors.txt")
say("전량 저장 → stage_artifacts/fq099/flow_dependent_factors.txt")
