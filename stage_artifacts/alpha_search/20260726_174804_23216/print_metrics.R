hr <- jsonlite::fromJSON("stage_artifacts/alpha_search/20260726_174804_23216/hurdle_result.json")
m  <- hr[["metrics"]]
sb <- hr[["score_breakdown"]]
diag <- hr[["diagnostics"]]

cat("=== SPEC_LOWFREQ_MASS_v1 실측 ===\n")
cat("grade:", hr[["grade"]], " score:", hr[["total_score"]], "\n")
cat("CAGR:", m[["CAGR"]], "% | Sharpe:", m[["Sharpe"]], "| MDD:", m[["MDD"]], "%\n")
cat("Calmar:", m[["Calmar"]], "| IR:", m[["IR"]], "| Turnover:", m[["Turnover_Ann"]], "%\n")
cat("BM_Corr:", m[["BM_Corr"]], "| Rolling3Y_Pos:", m[["Rolling3Y_Pos"]], "%\n")
cat("OOS:", diag[diag$code == "D062", "msg"], "\n")
cat("AlphaTrend:", diag[diag$code == "D061", "msg"], "\n")
cat("Stress:", diag[diag$code == "D042", "msg"], "\n")
