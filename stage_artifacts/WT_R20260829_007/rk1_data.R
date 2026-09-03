# RK1 — Risk 데이터 구축 (WT-R20260829_007)
suppressWarnings(suppressMessages({library(data.table); library(arrow); library(jsonlite)}))
ROOT <- Sys.getenv("QM_ROOT"); if (!nzchar(ROOT)) ROOT <- getwd()
setwd(ROOT); Sys.setenv(CLAUDE_PROJECT_DIR = ROOT)
source(file.path(ROOT,"02_Infrastructure/config.R"))
source(file.path(ROOT,"02_Infrastructure/backtest_harness.R"))
OUT <- file.path(ROOT,"stage_artifacts/WT_R20260829_007")

rl <- load_rawdata(use_cache=TRUE)
RAW <- as.data.table(rl$RAWDATA); BM <- as.data.table(rl$BM_DT); rm(rl); gc(verbose=FALSE)
if(!inherits(RAW$Date,"Date")) RAW[,Date:=as.Date(Date)]
if(!inherits(BM$Date,"Date"))  BM[,Date:=as.Date(Date)]
RAW <- RAW[Date>=as.Date("2004-01-01")]
cat("[RK1] RAWDATA rows",nrow(RAW),"cols:",paste(names(RAW),collapse=","),"\n")

A <- as.data.table(read_parquet(file.path(OUT,"alpha_scores.parquet")))
cat("[RK1] alpha_scores dates",length(unique(A$Date)),"rows",nrow(A),"\n")
print(A[,.(n=.N, n_top=sum(in_top25)),by=Date][order(Date)][c(1:3,.N-2,.N-1,.N)])
cat("[RK1] last date names:", A[Date==max(Date),.N], " top25:", A[Date==max(Date), sum(in_top25)],"\n")

pn <- readRDS(file.path(OUT,"panel.rds"))
SIG <- as.data.table(pn$SIG)
cat("[RK1] SIG cols:",paste(names(SIG),collapse=","),"\n")
cat("[RK1] sectors n_distinct:", uniqueN(SIG$Sector), "\n")
print(head(sort(table(SIG[Date>=as.Date("2020-01-01")]$Sector),decreasing=TRUE),40))
cat("[RK1] fwd cols:", paste(names(as.data.table(pn$fwd)),collapse=","),"\n")
print(head(as.data.table(pn$fwd),3))
