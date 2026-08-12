## AZ1 step1b — C15 loader 구조 확인 (한 달 로드)
suppressPackageStartupMessages({ library(data.table) })
DATA_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
CODE_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/.claude/worktrees/jovial-mcnulty-f7d018"
setwd(DATA_ROOT)
source(file.path(CODE_ROOT, "02_Infrastructure/factor_db/factor_db_connector.R"))
cat("[signature]", paste(names(formals(load_month_factors)), collapse=", "), "\n")
z <- try(load_month_factors(as.Date("2020-06-30")), silent = TRUE)
if (inherits(z, "try-error")) { cat("실패:", conditionMessage(attr(z,"condition")), "\n"); quit(status=0) }
z <- as.data.table(z)
cat(sprintf("[한 달 로드] %d행 x %d열\n", nrow(z), ncol(z)))
cat("[열 앞 12개]", paste(head(names(z),12), collapse=", "), "\n")
num <- names(z)[sapply(z, is.numeric)]
cat(sprintf("[수치 열] %d개: %s ...\n", length(num), paste(head(num, 15), collapse=", ")))
