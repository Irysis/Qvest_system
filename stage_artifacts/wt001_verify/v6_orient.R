suppressPackageStartupMessages({library(data.table)})
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
say <- function(...) cat(sprintf(...), "\n")
om <- readRDS("stage_artifacts/WT_D20260802_009/orientation_meta.rds")
for (k in c("sign_p2","sign_p3")) {
  s <- as.data.table(om[[k]])
  say("[%s] n=%d  s=+1 %d개월 / s=-1 %d개월  | |rho|<0.10 fallback %d개월  rho 중앙값 %+.3f",
      k, nrow(s), sum(s$s>0, na.rm=TRUE), sum(s$s<0, na.rm=TRUE), sum(abs(s$rho)<0.10, na.rm=TRUE),
      median(s$rho, na.rm=TRUE))
  if (sum(s$s<0, na.rm=TRUE)>0) print(head(s[s<0], 12))
}
say("[fallback counts] %s", paste(names(om$fallback), om$fallback, collapse=" / "))
