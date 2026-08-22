## WT-D20260822_006 P1a — 대조군 parity + 계열 구조 (MEAN-BLIND: 처치 미구성)
suppressPackageStartupMessages({library(data.table); library(arrow)})
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
source("02_Infrastructure/config.R")
W004 <- "stage_artifacts/WT-D20260822_004"; OUT <- "stage_artifacts/WT-D20260822_006"
A <- readRDS(file.path(W004,"p1_arms.rds"))
cat("p1_arms.rds names:", paste(names(A), collapse=", "), "\n")
cat("BT arms:", paste(names(A$BT), collapse=", "), "\n")
b <- A$BT$C0_zscore_ew
cat("BT element names:\n"); print(names(b))
cat("\nC0 portfolio_alpha_t_nw_lag3 =", format(b$portfolio_alpha_t_nw_lag3, digits=12), "\n")
cat("published                     = 0.94741072\n")
as_ <- b$active_series
cat("\nactive_series class:", paste(class(as_), collapse="/"), " len/nrow:",
    if (is.null(dim(as_))) length(as_) else nrow(as_), "\n")
if (!is.null(dim(as_))) print(head(as.data.table(as_),3)) else print(head(as_,3))
str(b[setdiff(names(b), c("active_series"))], max.level=1)
