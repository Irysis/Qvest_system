suppressWarnings(suppressMessages({library(data.table)}))
ROOT <- Sys.getenv("QM_ROOT"); if(!nzchar(ROOT)) ROOT <- getwd(); setwd(ROOT)
OUT <- file.path(ROOT,"stage_artifacts/WT_R20260829_007")
o6<-readRDS(file.path(OUT,"op6_objects.rds")); W<-copy(o6$SELW)
setorder(W, as_of_date, -weight, Ticker)
W[, `:=`(task_id="WT-R20260829_007", method="M2_EW25_buffer50",
         weight=round(weight,10))]
setcolorder(W, c("task_id","as_of_date","Ticker","weight","rank_proximity","method"))
fwrite(W, file.path(OUT,"weights.csv"))
chk <- W[, .(n=.N, sw=sum(weight), minw=min(weight), maxw=max(weight)), by=as_of_date]
cat("dates:",nrow(chk)," n range:",range(chk$n)," max|Sw-1|:",max(abs(chk$sw-1)),
    " min w:",min(chk$minw)," max w:",max(chk$maxw),"\n")
cat("violations n>25:",sum(chk$n>25)," w<0:",sum(W$weight<0)," |Sw-1|>1e-6:",sum(abs(chk$sw-1)>1e-6),"\n")
cat("first:",as.character(min(W$as_of_date))," last:",as.character(max(W$as_of_date)),"\n")
cat("schedule_density vs alpha sig_dates(259 realized / 260 total):",
    round(nrow(chk)/259,4), "/", round(nrow(chk)/260,4), "\n")
