suppressPackageStartupMessages(library(jsonlite))
setwd(Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
S <- fromJSON("02_Infrastructure/worktask/schema.json", simplifyVector=FALSE)
d <- S$definitions$alpha_package$properties$diagnostics$properties
for (k in c("rank_ic","canonical_port_t_nw_lag3","alpha_inheritance_cor")) { cat("--",k,"--\n"); str(d[[k]]) }
cat("-- verdict --\n"); str(S$definitions$alpha_package$properties$verdict)
cat("-- alpha_vector --\n"); str(S$definitions$alpha_package$properties$alpha_vector, max.level=2)
