# Verify real factor presence in factor DB via load_month_factors (C15) for batch-2 candidates.
# Checks coverage (n tickers with finite Z_Score_Aligned) across 3 probe dates.
suppressWarnings(suppressMessages({ library(data.table); library(arrow) }))
PROJ  <- Sys.getenv("CLAUDE_PROJECT_DIR", "G:/Quant_Module_Moltbot")
INFRA <- file.path(PROJ, "02_Infrastructure")
source(file.path(INFRA, "config.R"))
source(file.path(INFRA, "factor_db", "factor_db_connector.R"))

# Candidate target factors (batch 2) — real registry names confirmed
cand <- c(
  # D 계열 대표 (tail/skew = 방어 가능성)
  "D01_IdioVol","D04_Downside_Beta","D05_MaxRet","D16_Coskewness","D17_Cokurtosis",
  "D25_Left_Tail_Beta","D43_Skewness","D44_Kurtosis","D45_Downside_Dev","D46_Sortino",
  "D50_MaxDrawdown","D51_Ulcer_Index",
  # R 계열 (risk)
  "R03_CVaR_95","R05_Tail_Risk","R07_Downside_Dev","R09_Coskewness","R10_Cokurtosis",
  "R13_NCSKEW","R14_DUVOL","R15_Sortino","R16_Calmar","R19_Composite_Risk",
  # M 나머지
  "M02_Mom_6_1","M03_Mom_3_1","M10_Intermediate_Mom","M13_VolAdj_Mom","M14_RiskAdj_Mom",
  "M16_Trend_Factor","M22_Max_Return","M23_Acceleration",
  # Q 나머지
  "Q05_Accrual","Q09_CFOA","Q12_Asset_Turnover","Q23_Sustainable_Growth",
  "Q33_Earnings_Persistence","Q35_CashBased_OpProf","Q17_ROIC","Q28_Cash_Conversion"
)

probes <- as.Date(c("2010-06-30","2017-06-30","2024-06-30"))
# month-end resolve: pick actual last available <= probe by trying connector
res <- data.table()
for (d in probes) {
  d <- as.Date(d, origin="1970-01-01")
  fdt <- tryCatch(load_month_factors(d, coverage_min = 0.0), error=function(e) NULL)
  if (is.null(fdt) || !nrow(fdt)) { cat(sprintf("probe %s: load failed\n", d)); next }
  cov <- fdt[Factor_Name %in% cand & is.finite(Z_Score_Aligned),
             .(n = .N), by = Factor_Name]
  cov[, probe := as.character(d)]
  res <- rbind(res, cov, fill=TRUE)
}
# pivot: factor x probe coverage
w <- dcast(res, Factor_Name ~ probe, value.var="n", fill=0L)
present <- unique(res$Factor_Name)
missing <- setdiff(cand, present)
cat("\n=== COVERAGE (n finite Z_Score_Aligned per probe date) ===\n")
print(w)
cat(sprintf("\n=== MISSING (0 rows all probes, n=%d): %s ===\n",
            length(missing), paste(missing, collapse=", ")))
fwrite(w, file.path(PROJ,"stage_artifacts","alpha_search","_verify_factors_batch2.csv"))
cat("[done] saved _verify_factors_batch2.csv\n")
