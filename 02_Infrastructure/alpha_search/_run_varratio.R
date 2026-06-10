# _run_varratio.R — alpha-search 호출 래퍼 (H-10 Variance Ratio Information Speed)
source("G:/Quant_Module_Moltbot/02_Infrastructure/alpha_search/run_alpha_search.R")
res <- run_alpha_search(
  strategy_name      = "VarRatio_InfoSpeed",
  strategy_idea      = "VR 정보속도(H-10, Lo-MacKinlay 1988 Variance Ratio 응용): VR(5d/1d)-VR(20d/5d) 상위 decile long. 일간 추세+주간 회귀 종목. RAWDATA-only, 252d 윈도우, 월간 EW.",
  factor_engine_path = "G:/Quant_Module_Moltbot/02_Infrastructure/alpha_search/fe_varratio.R",
  weight_method      = "equal",   # top decile EW (제1원칙: 논문 관행 EW)
  start_date         = "2005-01-01",
  universe           = "K200_KQ150",
  factor_analysis    = TRUE
)
cat("\n[_run_varratio] grade=", res$grade, " score=", res$score,
    " excess_cagr=", res$excess_cagr, " l_code=", res$l_code, "\n")
saveRDS(res, "G:/Quant_Module_Moltbot/stage_artifacts/alpha_search/_last_varratio_res.rds")
