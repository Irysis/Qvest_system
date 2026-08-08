suppressPackageStartupMessages({ library(jsonlite) })
setwd(Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
say <- function(fmt,...) cat(sprintf(paste0("[c14] ",fmt,"\n"),...))
reg <- fromJSON("02_Infrastructure/factor_db/factor_registry.json", simplifyVector=FALSE)
for (k in c("C14_Revenue_Surprise","AC14_Discretionary_Accruals","C01_SUE","C04_ESBR")) {
  f <- reg[[k]]; if (is.null(f)) { say("%s 미등재", k); next }
  say("=== %s ===", k)
  for (fld in c("name","category","definition","data_source","lag_rule","update_freq","storage")) {
    v <- f[[fld]]; if (!is.null(v)) say("   %-12s %s", fld, substr(paste(unlist(v),collapse=" "),1,150))
  }
  lb <- f$labels; if(!is.null(lb)) say("   %-12s %s", "labels", substr(paste(unlist(lb),collapse=" | "),1,180))
}
