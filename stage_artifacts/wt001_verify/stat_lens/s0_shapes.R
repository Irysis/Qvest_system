suppressPackageStartupMessages({library(data.table); library(arrow)})
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
setwd(ROOT)
OUT <- file.path(ROOT,"stage_artifacts/WT_D20260808_001")
fwd <- readRDS(file.path(OUT,"fwd_cache.rds"))
cat("fwd names:", paste(names(fwd), collapse=", "), "\n")
r <- as.data.table(fwd$returns_dt); b <- as.data.table(fwd$bench_dt)
cat("returns_dt cols:", paste(names(r),collapse=","), " nrow=",nrow(r)," ndates=",uniqueN(r$Date),
    " range=",as.character(min(r$Date)),"~",as.character(max(r$Date)),"\n")
print(head(r,3))
cat("bench_dt cols:", paste(names(b),collapse=","), " nrow=",nrow(b), " ndates=",uniqueN(b$Date),"\n")
print(head(b,3))
cat("liq cols:", paste(names(as.data.table(fwd$liq_dt)),collapse=","),"\n")
# monthly spacing check
d <- sort(unique(r$Date)); cat("median day-gap between dates:", median(as.numeric(diff(d))),"\n")
