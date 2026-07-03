suppressMessages({ library(data.table); library(arrow) })
Sys.setenv(CLAUDE_PROJECT_DIR = getwd(), QM_ROOT = getwd())
source("02_Infrastructure/config.R")
source("02_Infrastructure/factor_db/factor_db_connector.R")
source("02_Infrastructure/factor_db/crowding_score_per_factor.R")
OUT <- "stage_artifacts/WT-D20260614_002"
FACTORS <- c("D01_IdioVol","D02_Beta","M07_IndMom","M01_Mom_12_1","M05_Trended_Mom",
             "Q01_GPA","Q04_Piotroski_F","Q09_CFOA","Q07_Earnings_Stability","V01_BM")
SIG_DATE <- as.Date("2026-05-31")

fac <- load_month_factors(SIG_DATE, coverage_min = 0.05, factor_names = FACTORS)
setnames(fac, c("Factor_Name","Z_Score_Aligned"), c("factor_name","exposure"))
fe <- fac[, .(Ticker, factor_name, exposure)]

rd <- as.data.table(read_parquet(".cache/RAWDATA.parquet",
        col_select=c("Date","Ticker","Close","Vol","Size","K200","KQ150")))
rd[, Date := as.Date(Date)]
res <- tryCatch(
  crowding_score_per_factor(fe, sig_date = SIG_DATE, RAWDATA = rd, top_n = 20),
  error = function(e) { cat("[crowding] ERROR:", conditionMessage(e), "\n"); NULL })
if (!is.null(res)) {
  print(res)
  saveRDS(res, file.path(OUT, "_risk_crowding.rds"))
  write_parquet(as.data.table(res), file.path(OUT, "crowding_per_factor.parquet"))
}
