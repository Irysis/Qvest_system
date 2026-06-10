# Aggregate batch-2 LO screen JSONs into a report table + selection.
suppressWarnings(suppressMessages({ library(data.table); library(jsonlite) }))
PROJ <- Sys.getenv("CLAUDE_PROJECT_DIR", "G:/Quant_Module_Moltbot")
DIR  <- file.path(PROJ, "stage_artifacts", "alpha_search", "lo_screen")
`%||%` <- function(a,b) if (is.null(a)||length(a)==0||(length(a)==1&&is.na(a))) b else a

batch2 <- c(
  "D01_IdioVol","D04_Downside_Beta","D05_MaxRet","D16_Coskewness","D17_Cokurtosis",
  "D25_Left_Tail_Beta","D43_Skewness","D44_Kurtosis","D45_Downside_Dev","D46_Sortino",
  "D50_MaxDrawdown","D51_Ulcer_Index",
  "R03_CVaR_95","R05_Tail_Risk","R07_Downside_Dev","R09_Coskewness","R10_Cokurtosis",
  "R13_NCSKEW","R14_DUVOL","R15_Sortino","R16_Calmar","R19_Composite_Risk",
  "M02_Mom_6_1","M03_Mom_3_1","M10_Intermediate_Mom","M13_VolAdj_Mom","M14_RiskAdj_Mom",
  "M16_Trend_Factor","M22_Max_Return","M23_Acceleration",
  "Q05_Accrual","Q09_CFOA","Q12_Asset_Turnover","Q17_ROIC","Q23_Sustainable_Growth",
  "Q28_Cash_Conversion","Q33_Earnings_Persistence","Q35_CashBased_OpProf"
)

rows <- list()
missing <- c()
for (f in batch2) {
  p <- file.path(DIR, paste0(f, ".json"))
  if (!file.exists(p)) { missing <- c(missing, f); next }
  j <- tryCatch(fromJSON(p), error=function(e) NULL)
  if (is.null(j)) { missing <- c(missing, paste0(f,"(parse_fail)")); next }
  lo <- j$long_only_top25; v <- j$verdict; mc <- j$multi_axis_corr
  rows[[f]] <- data.table(
    factor = f,
    n = lo$n_months %||% NA,
    sharpe = lo$sharpe %||% NA,
    cagr = lo$cagr_pct %||% NA,
    mdd = lo$mdd_pct %||% NA,
    calmar = lo$calmar %||% NA,
    net_ir = lo$net_ir %||% NA,
    port_t = lo$portfolio_alpha_t_nw_lag3 %||% NA,
    oos_ret = lo$oos_retention %||% NA,
    sr_is = lo$active_sr_is %||% NA,
    sr_oos = lo$active_sr_oos %||% NA,
    c4_alpha = lo$carhart4_alpha_ann_pct %||% NA,
    c4_t = lo$carhart4_alpha_t %||% NA,
    grade = (lo$essence$grade %||% NA),
    corr_val = mc$vs_value_bm_lo %||% NA,
    corr_1715 = mc$vs_STR_1715 %||% NA,
    oos_robust = v$oos_robust_orthogonal_candidate %||% NA,
    defense = v$defense_candidate %||% NA
  )
}
DT <- rbindlist(rows, use.names=TRUE, fill=TRUE)
setorder(DT, -sharpe)

# Selection per prompt 판정:
#  OOS robust 직교 = oos_ret>=0.5 AND |c4_t|>=1.96  (+ corr 사후 확인)
#  방어 후보 = mdd < 30
DT[, sel_oos_robust := is.finite(oos_ret) & oos_ret >= 0.5 & is.finite(c4_t) & abs(c4_t) >= 1.96]
DT[, sel_defense := is.finite(mdd) & mdd < 30]

fwrite(DT, file.path(DIR, "_batch2_summary.csv"))
cat(sprintf("\n=== BATCH 2 SUMMARY (%d/%d completed; missing %d) ===\n", nrow(DT), length(batch2), length(missing)))
print(DT[, .(factor, sharpe, cagr, mdd, calmar, oos_ret, c4_t, grade, corr_1715, sel_oos_robust, sel_defense)])
cat("\n--- OOS ROBUST 직교 후보 (oos_ret>=0.5 & |c4_t|>=1.96) ---\n")
print(DT[sel_oos_robust == TRUE, .(factor, oos_ret, c4_t, corr_val, corr_1715, sharpe, mdd)])
cat("\n--- 방어 후보 (MDD<30%) ---\n")
print(DT[sel_defense == TRUE, .(factor, mdd, calmar, sharpe, c4_t, grade)][order(mdd)])
if (length(missing)) cat(sprintf("\n--- MISSING/FAILED: %s ---\n", paste(missing, collapse=", ")))
cat("\n[saved] _batch2_summary.csv\n")
