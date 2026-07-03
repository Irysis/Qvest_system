suppressMessages({library(data.table); library(arrow); library(dplyr)})
arrow::set_io_thread_count(2L); setDTthreads(1L)
PROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(PROOT)
OUT <- file.path(PROOT,"stage_artifacts/WT-D20260621_006")
scores_primary <- readRDS(file.path(OUT,"scores_primary.rds"))
Sys.setenv(QM_ROOT=PROOT, CLAUDE_PROJECT_DIR=PROOT)
source("02_Infrastructure/config.R")
source("02_Infrastructure/factor_db/factor_db_connector.R")
targets <- c("L01_Amihud","L09_Amihud_20d","L10_Amihud_Ratio","L29_Illiq_Change",
             "M01_Mom_12_1","M08_Residual_Mom","L03_Volume_Mom","L28_Volume_Mom_3m")
omonths <- sort(unique(scores_primary$Date)); omonths <- omonths[seq(1,length(omonths),by=6)]
acc <- list()
for(i in seq_along(omonths)){
  sd <- omonths[i]
  fdb <- tryCatch(load_month_factors(sd, factor_names=targets), error=function(e) NULL)
  if(is.null(fdb)||!nrow(fdb)) next
  wide <- dcast(fdb, Ticker~Factor_Name, value.var="Z_Score_Aligned")
  sc <- scores_primary[Date==sd, .(Ticker, score)]
  mg <- merge(sc, wide, by="Ticker")
  if(nrow(mg)<20) next
  fac_cols <- intersect(names(wide), targets)
  cc <- sapply(fac_cols, function(fc){ v<-mg[[fc]]; if(sum(!is.na(v))<20) NA_real_ else cor(mg$score,v,method="spearman",use="complete.obs") })
  acc[[length(acc)+1]] <- as.data.table(as.list(cc))
}
cor_dt <- rbindlist(acc, fill=TRUE)
ortho <- data.table(factor=names(cor_dt),
                    mean_abs_corr=sapply(cor_dt,function(x)mean(abs(x),na.rm=TRUE)),
                    mean_corr=sapply(cor_dt,function(x)mean(x,na.rm=TRUE)),
                    n=sapply(cor_dt,function(x)sum(!is.na(x))))
fwrite(ortho, file.path(OUT,"orthogonality.csv"))
print(ortho)
cat("ORTHO_DONE\n")
