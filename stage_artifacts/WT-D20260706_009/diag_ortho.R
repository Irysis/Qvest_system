# diag_ortho.R — orthogonality of NSI vs incumbent book alpha (STR_1715 AR) + common factors
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
PAN <- file.path(ROOT,"stage_artifacts/WT-D20260706_009/panel")
sc <- as.data.table(read_parquet(file.path(PAN,"nsi_scores_monthly.parquet")))[Date>=as.Date("2005-01-01")]

bkp <- "05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/02_holdings_universe/alpha_scores_str1715_268m.parquet"
bk <- as.data.table(read_parquet(bkp))
cat("book cols:", paste(names(bk),collapse=", "), "\n")
print(head(bk,3))
